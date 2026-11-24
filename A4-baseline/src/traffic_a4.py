#!/usr/bin/env python3
"""Check the three slice traffic sources of my A4 runs against their models.

    python3 traffic_a4.py ../results/raw --out ../results

Reads every <tag>-tx.csv / -flows.csv (offered traffic, before the RAN) and writes
    traffic_model.png   (a) offered rate of one flow per slice, 100 ms bins
                        (b) video frame size: measured vs. truncated Pareto model
                        (c) VoIP inter-arrival: measured vs. Exp(20 ms)
                        (d) MTC rate over 1 s bins: measured vs. semi-Markov model
    traffic_table.md    expected vs. measured mean rate, packet rate, packet size per slice

Model parameters are the ones in a4-rana-servicerate.cc (SliceSourceApp).
"""
import argparse
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

# Model (same values as SliceSourceApp)
MTC_L = np.array([1.0, 0.5, 0.5, 0.5])  # mean state durations (s)
MTC_W = np.array([0.0, 55.0, 50.0, 0.0])  # packet rate in each state (pkt/s)
MTC_BYTES = 100
VOIP_MEAN_S, VOIP_BYTES = 0.020, 32
VIDEO_MBPS, VIDEO_FPS, VIDEO_SHAPE, VIDEO_BOUND = 15.0, 30.0, 2.5, 4.0
WARMUP, END = 2.0, 12.0

COL = {"MTC": "#3a9e5b", "VoIP": "#eb6834", "Video": "#2a78d6"}
MODEL = "#52514e"


def video_model():
    """Truncated Pareto: scale xm = mean*(a-1)/a, rejection above bound*mean."""
    m = VIDEO_MBPS * 1e6 / VIDEO_FPS / 8
    a, xm, ub = VIDEO_SHAPE, m * (VIDEO_SHAPE - 1) / VIDEO_SHAPE, VIDEO_BOUND * m
    norm = 1 - (xm / ub) ** a
    mean = a * xm**a * (xm ** (1 - a) - ub ** (1 - a)) / ((a - 1) * norm)
    pdf = lambda x: np.where((x >= xm) & (x <= ub), a * xm**a / x ** (a + 1) / norm, 0)
    return m, mean, xm, ub, pdf


def mtc_model():
    # next state uniform among the other three -> embedded chain uniform,
    # time share proportional to the mean duration
    share = MTC_L / MTC_L.sum()
    return share, float((share * MTC_W).sum())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw", type=Path)
    ap.add_argument("--out", type=Path, default=Path("."))
    a = ap.parse_args()

    txs = []
    for f in sorted(a.raw.glob("*-tx.csv")):
        tag = f.name[: -len("-tx.csv")]
        tx = pd.read_csv(f)
        fl = pd.read_csv(a.raw / f"{tag}-flows.csv").set_index("flow")
        tx["slice"] = tx["flow"].map(fl["slice"])
        tx["run"] = tag
        tx["t"] = tx["time_ns"] * 1e-9
        txs.append(tx[(tx["t"] >= WARMUP) & (tx["t"] < END)])
    tx = pd.concat(txs, ignore_index=True)
    dur = END - WARMUP

    share, mtc_pps = mtc_model()
    vm, vmean, xm, ub, vpdf = video_model()
    expected = {
        "MTC": (mtc_pps * MTC_BYTES * 8 / 1e3, mtc_pps, MTC_BYTES),
        "VoIP": (VOIP_BYTES * 8 / VOIP_MEAN_S / 1e3, 1 / VOIP_MEAN_S, VOIP_BYTES),
        "Video": (vmean * VIDEO_FPS * 8 / 1e3, None, None),
    }

    # per-flow measured rates, then mean over flows
    per_flow = tx.groupby(["run", "flow", "slice"]).agg(pkts=("seq", "size"),
                                                        bytes=("bytes", "sum")).reset_index()
    per_flow["kbps"] = per_flow["bytes"] * 8 / dur / 1e3
    per_flow["pps"] = per_flow["pkts"] / dur
    rows = ["| Slice | Model | Expected rate | Measured rate (mean ± sd over flows) | Expected pkt/s | Measured pkt/s | Pkt size | Flows |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    models = {
        "MTC": "4-state semi-Markov, Poisson inside a state",
        "VoIP": "Poisson, mean 20 ms",
        "Video": "30 fps, truncated Pareto frame size, 1400 B packets",
    }
    for s in ["MTC", "VoIP", "Video"]:
        g = per_flow[per_flow["slice"] == s]
        e_kbps, e_pps, e_sz = expected[s]
        meas_sz = tx.loc[tx["slice"] == s, "bytes"].mean()
        unit = (lambda v: f"{v / 1e3:.2f} Mbit/s") if s == "Video" else (lambda v: f"{v:.1f} kbit/s")
        e_pps_s = f"{e_pps:.0f}" if e_pps else f"{VIDEO_FPS:g} frames/s"
        sz_s = f"{meas_sz:.0f} B" + ("" if e_sz is None else f" (model {e_sz} B)")
        rows.append(f"| {s} | {models[s]} | {unit(e_kbps)} | "
                    f"{unit(g['kbps'].mean())} ± {unit(g['kbps'].std())} | {e_pps_s} | "
                    f"{g['pps'].mean():.1f} | {sz_s} | {len(g)} |")
    note = (f"\nWindow {WARMUP:g}–{END:g} s of every run ({tx['run'].nunique()} runs). "
            f"MTC time share per state (model) = {', '.join(f'{v:.0%}' for v in share)}. "
            f"Video: nominal 15 Mbit/s; the Pareto cap at {VIDEO_BOUND:g}x the mean trims the tail, "
            f"so the model mean is {vmean * VIDEO_FPS * 8 / 1e6:.2f} Mbit/s.")
    table = "\n".join(rows) + "\n" + note + "\n"
    (a.out / "traffic_table.md").write_text(table, encoding="utf-8")
    print(table)

    # ---------------- figure ----------------
    run0 = sorted(tx["run"].unique())[0]
    t0 = tx[tx["run"] == run0]
    fig, ax = plt.subplots(2, 2, figsize=(12, 7.5))

    # (a) offered rate of one flow per slice
    bins = np.arange(WARMUP, END + 1e-9, 0.1)
    for s in ["MTC", "VoIP", "Video"]:
        f0 = t0[t0["slice"] == s]["flow"].min()
        x = t0[t0["flow"] == f0]
        r, _ = np.histogram(x["t"], bins=bins, weights=x["bytes"] * 8 / 0.1 / 1e3)
        ax[0, 0].step(bins[:-1], r, where="post", color=COL[s], lw=1,
                      label=f"{s} (flow {f0})")
    ax[0, 0].set_yscale("symlog", linthresh=10)
    ax[0, 0].set_xlabel("Time (s)")
    ax[0, 0].set_ylabel("Offered rate, 100 ms bins (kbit/s)")
    ax[0, 0].set_title(f"(a) One flow per slice ({run0})")
    ax[0, 0].legend(fontsize=8)
    ax[0, 0].grid(alpha=0.3)

    # (b) video frame size
    v = tx[tx["slice"] == "Video"]
    frames = v.groupby(["run", "flow", "time_ns"])["bytes"].sum() / 1e3
    xs = np.linspace(xm, ub, 400)
    ax[0, 1].hist(frames, bins=60, density=True, color=COL["Video"], alpha=0.6,
                  label=f"measured ({len(frames)} frames)")
    ax[0, 1].plot(xs / 1e3, vpdf(xs) * 1e3, color=MODEL, lw=2,
                  label=f"truncated Pareto α={VIDEO_SHAPE:g}")
    ax[0, 1].axvline(vm / 1e3, color=MODEL, ls=":", lw=1)
    ax[0, 1].set_xlabel("Frame size (kB)")
    ax[0, 1].set_ylabel("Density")
    ax[0, 1].set_title(f"(b) Video frames: mean {frames.mean():.1f} kB (model {vmean / 1e3:.1f} kB)")
    ax[0, 1].legend(fontsize=8)
    ax[0, 1].grid(alpha=0.3)

    # (c) VoIP inter-arrival
    vo = tx[tx["slice"] == "VoIP"].sort_values(["run", "flow", "time_ns"])
    ia = vo.groupby(["run", "flow"])["t"].diff().dropna() * 1e3
    xs = np.linspace(0, 120, 300)
    ax[1, 0].hist(ia, bins=80, range=(0, 120), density=True, color=COL["VoIP"], alpha=0.6,
                  label=f"measured (mean {ia.mean():.1f} ms)")
    ax[1, 0].plot(xs, np.exp(-xs / 20) / 20, color=MODEL, lw=2, label="Exp(mean 20 ms)")
    ax[1, 0].set_xlabel("Inter-arrival (ms)")
    ax[1, 0].set_ylabel("Density")
    ax[1, 0].set_title("(c) VoIP packet inter-arrival")
    ax[1, 0].legend(fontsize=8)
    ax[1, 0].grid(alpha=0.3)

    # (d) MTC rate in 1 s bins vs. model mean
    m = tx[tx["slice"] == "MTC"]
    m1 = m.groupby(["run", "flow", np.floor(m["t"]).astype(int)]).size()
    full = pd.MultiIndex.from_product(
        [m["run"].unique(), sorted(m["flow"].unique()), range(int(WARMUP), int(END))])
    m1 = m1.reindex(full, fill_value=0)
    m1 = m1[m1.index.get_level_values(1).isin(m["flow"].unique())]
    ax[1, 1].hist(m1, bins=np.arange(0, 70, 2), color=COL["MTC"], alpha=0.6, density=True,
                  label=f"measured (mean {m1.mean():.1f} pkt/s)")
    ax[1, 1].axvline(mtc_pps, color=MODEL, lw=2, label=f"model mean {mtc_pps:.0f} pkt/s")
    ax[1, 1].set_xlabel("Packets in a 1 s bin")
    ax[1, 1].set_ylabel("Density")
    ax[1, 1].set_title("(d) MTC: on/off bursts around the semi-Markov mean")
    ax[1, 1].legend(fontsize=8)
    ax[1, 1].grid(alpha=0.3)

    fig.tight_layout()
    fig.savefig(a.out / "traffic_model.png", dpi=200)
    plt.close(fig)
    print(f"wrote {a.out}/traffic_model.png and traffic_table.md")


if __name__ == "__main__":
    main()
