#!/usr/bin/env python3
"""Service rate vs. server->UPF delay (Rana et al., IEEE TVT 2024, Fig. 6) from A4 runs.

    python3 analyze_a4.py ../results/raw --out ../results

Input: for every run <sched>-s<seed>, the files written by a4-rana-servicerate.cc
    <tag>-tx.csv  <tag>-rx.csv  <tag>-flows.csv

Method (all choices are command-line options, defaults follow Rana et al. Sec. V):
  1. RAN delay of a packet = rx time - tx time from the simulation (UPF -> UE part).
  2. Server -> UPF delay is added here, not in ns-3: all traffic is UDP, so it does not
     change what the RAN does. For each mean delay D on the x-axis (10..80 ms) an offset is
     drawn from Exp(D). --offset-mode window (default): one offset per flow per 2 s window,
     i.e. the path delay of a flow changes slowly; 'packet': one per packet; 'flow': one per
     flow for the whole run. Optional per-packet variation U(-j, +j) with --jitter-ms.
  3. A packet is lost if it never arrived OR its end-to-end delay exceeds the budget
     (100 ms for every slice). Expired packets count as lost, as in the paper.
  4. Per flow and per 2 s window (by tx time, after the warm-up), the flow meets its QoS if
        PLR <= target  (MTC 1e-2, VoIP 1e-2, video 1e-6 -> no loss in the window)
        p95 inter-packet delay variation <= target (VoIP, video 40 ms; MTC not checked:
        its 1 ms target is below the gaps of an on/off source, see study note)
     Windows in which the flow sent nothing (MTC OFF state) are skipped.
  5. Service rate of a flow = share of its windows that meet the QoS; of a slice = mean over
     its flows; overall (Fig. 6 y-axis) = mean of the three slice service rates.
  6. Mean and 95 % confidence interval (Student t) over the seeds.

Outputs in --out:
  per_run.csv          scheduler, seed, delay, slice, service rate
  service_rate.csv     mean, CI, number of seeds per (scheduler, delay, slice)
  ran_delay.csv        RAN-only delay and loss per scheduler and slice (explains differences)
  fig6_table.md        markdown table for the study note
  fig6_reproduction.png / .pdf   (a) overall vs. Rana Fig. 6, (b) per slice
"""
import argparse
import re
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

SLICES = ["MTC", "VoIP", "Video"]
DELAY_BUDGET_MS = {"MTC": 100.0, "VoIP": 100.0, "Video": 100.0}
PLR_TARGET = {"MTC": 1e-2, "VoIP": 1e-2, "Video": 1e-6}
IPDV_TARGET_MS = {"MTC": None, "VoIP": 40.0, "Video": 40.0}

# Two-sided 95 % Student t quantiles, df = 1..30
T95 = [12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228,
       2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
       2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042]

COLORS = {"Qos": "#2a78d6", "PF": "#eb6834", "RR": "#3a9e5b"}
LABELS = {"Qos": "5G-LENA QoS (mine)", "PF": "5G-LENA PF (mine)", "RR": "5G-LENA RR (mine)"}
REF_STYLE = {"Proposed": ("#8e44ad", "+"), "FLS": ("#5bb5d9", "s"), "CBAP": ("#1f8a70", "x")}
INK = "#52514e"


def ci95(x):
    x = np.asarray(x, dtype=float)
    n = len(x)
    if n < 2:
        return 0.0
    t = T95[min(n - 1, len(T95)) - 1]
    return t * x.std(ddof=1) / np.sqrt(n)


def find_runs(raw):
    runs = []
    for tx in sorted(raw.glob("*-tx.csv")):
        tag = tx.name[: -len("-tx.csv")]
        m = re.match(r"^(?P<sched>.+)-s(?P<seed>\d+)$", tag)
        if not m:
            print(f"skip {tag}: name is not <scheduler>-s<seed>")
            continue
        runs.append((m["sched"], int(m["seed"]), tag))
    return runs


def load_run(raw, tag, warmup, window, nwin):
    tx = pd.read_csv(raw / f"{tag}-tx.csv")
    rx = pd.read_csv(raw / f"{tag}-rx.csv")
    flows = pd.read_csv(raw / f"{tag}-flows.csv")
    rx = rx.drop_duplicates(["flow", "seq"])
    df = tx.merge(rx[["flow", "seq", "time_ns"]], on=["flow", "seq"], how="left",
                  suffixes=("", "_rx"))
    df["t_s"] = df["time_ns"] * 1e-9
    df["ran_ms"] = (df["time_ns_rx"] - df["time_ns"]) * 1e-6  # NaN = never received
    df["win"] = np.floor((df["t_s"] - warmup) / window).astype(int)
    df = df[(df["win"] >= 0) & (df["win"] < nwin)].copy()
    df["slice"] = df["flow"].map(flows.set_index("flow")["slice"])
    return df.sort_values(["flow", "seq"]).reset_index(drop=True), flows


def service_rate(df, flows, delay_ms, rng, mode, jitter_ms, nwin, overall):
    nflow = int(flows["flow"].max()) + 1
    if mode == "window":
        off = rng.exponential(delay_ms, size=(nflow, nwin))[df["flow"], df["win"]]
    elif mode == "flow":
        off = rng.exponential(delay_ms, size=nflow)[df["flow"]]
    else:
        off = rng.exponential(delay_ms, size=len(df))
    e2e = df["ran_ms"].to_numpy() + off
    if jitter_ms > 0:
        e2e = e2e + rng.uniform(-jitter_ms, jitter_ms, size=len(df))
    budget = df["slice"].map(DELAY_BUDGET_MS).to_numpy()
    ok = ~np.isnan(e2e) & (e2e <= budget)

    d = pd.DataFrame({"flow": df["flow"], "win": df["win"], "slice": df["slice"],
                      "e2e": e2e, "ok": ok})
    g = d.groupby(["flow", "win"])
    w = pd.DataFrame({"n": g.size(), "n_ok": g["ok"].sum()})
    w["slice"] = g["slice"].first()
    w["plr"] = 1 - w["n_ok"] / w["n"]

    # inter-packet delay variation between consecutive on-time packets of a flow
    dok = d[d["ok"]].copy()
    dok["ipdv"] = dok.groupby(["flow", "win"])["e2e"].diff().abs()
    w["ipdv95"] = dok.groupby(["flow", "win"])["ipdv"].quantile(0.95)
    w["ipdv95"] = w["ipdv95"].fillna(0.0)

    plr_ok = w["plr"] <= w["slice"].map(PLR_TARGET)
    ipdv_t = w["slice"].map(IPDV_TARGET_MS)
    ipdv_ok = ipdv_t.isna() | (w["ipdv95"] <= ipdv_t.fillna(np.inf))
    w["meet"] = plr_ok & ipdv_ok

    per_flow = w.groupby("flow").agg(sr=("meet", "mean"), slice=("slice", "first"))
    per_slice = per_flow.groupby("slice")["sr"].mean().reindex(SLICES)
    if overall == "flows":
        allv = per_flow["sr"].mean()
    else:
        allv = per_slice.mean()
    out = {s: 100 * per_slice[s] for s in SLICES}
    out["All"] = 100 * allv
    return out


def ran_stats(df):
    rows = []
    for s, g in df.groupby("slice"):
        r = g["ran_ms"].dropna()
        rows.append({"slice": s, "tx": len(g), "rx": len(r),
                     "ran_loss_pct": 100 * (1 - len(r) / max(len(g), 1)),
                     "ran_mean_ms": r.mean(), "ran_p95_ms": r.quantile(0.95),
                     "ran_p99_ms": r.quantile(0.99), "ran_max_ms": r.max()})
    return rows


def plot(agg, ref, out, delays):
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4.6))
    for name, (c, mk) in REF_STYLE.items():
        if name in ref.columns:
            ax1.plot(ref["delay_ms"], ref[name], ls="--", color=c, marker=mk, lw=1.2,
                     label=f"Rana Fig. 6: {name}")
    allrows = agg[agg["slice"] == "All"]
    for sched, g in allrows.groupby("scheduler"):
        g = g.sort_values("delay_ms")
        c = COLORS.get(sched, INK)
        ax1.plot(g["delay_ms"], g["mean"], color=c, marker="o", lw=2,
                 label=LABELS.get(sched, sched))
        ax1.fill_between(g["delay_ms"], g["mean"] - g["ci95"], g["mean"] + g["ci95"],
                         color=c, alpha=0.18, lw=0)
    ax1.set_xlabel("Mean server→UPF delay (ms)")
    ax1.set_ylabel("Service rate (%)")
    ax1.set_title("(a) Overall service rate vs. Rana et al. Fig. 6")
    ax1.set_xticks(delays)
    ax1.grid(alpha=0.3)
    ax1.legend(fontsize=8, loc="lower left")

    styles = {"MTC": ":", "VoIP": "--", "Video": "-"}
    for (sched, sl), g in agg[agg["slice"].isin(SLICES)].groupby(["scheduler", "slice"]):
        g = g.sort_values("delay_ms")
        ax2.errorbar(g["delay_ms"], g["mean"], yerr=g["ci95"], color=COLORS.get(sched, INK),
                     ls=styles[sl], marker="o", ms=3, capsize=2, label=f"{sched} · {sl}")
    ax2.set_xlabel("Mean server→UPF delay (ms)")
    ax2.set_ylabel("Service rate (%)")
    ax2.set_title("(b) Per slice (mine), mean ± 95 % CI")
    ax2.set_xticks(delays)
    ax2.set_ylim(-2, 102)
    ax2.grid(alpha=0.3)
    ax2.legend(fontsize=8, ncol=2, loc="lower left")
    fig.tight_layout()
    fig.savefig(out / "fig6_reproduction.png", dpi=200)
    fig.savefig(out / "fig6_reproduction.pdf")
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("raw", type=Path, help="directory with <sched>-s<seed>-*.csv")
    ap.add_argument("--out", type=Path, default=Path("."))
    ap.add_argument("--ref", type=Path,
                    default=Path(__file__).resolve().parent.parent / "reference" / "rana_fig6.csv")
    ap.add_argument("--delays", type=float, nargs="+",
                    default=[10, 20, 30, 40, 50, 60, 70, 80])
    ap.add_argument("--warmup", type=float, default=2.0, help="s discarded at the start")
    ap.add_argument("--window", type=float, default=2.0, help="averaging window (s)")
    ap.add_argument("--nwin", type=int, default=5, help="number of windows after warm-up")
    ap.add_argument("--offset-mode", choices=["window", "packet", "flow"], default="window")
    ap.add_argument("--jitter-ms", type=float, default=0.0)
    ap.add_argument("--overall", choices=["slices", "flows"], default="slices")
    ap.add_argument("--cell", choices=["macro", "small"], default=None,
                    help="keep only the flows of one cell (sensitivity check)")
    ap.add_argument("--video-plr", type=float, default=PLR_TARGET["Video"],
                    help="video PLR target (paper 1e-6 = no loss in a window); sensitivity check")
    a = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    PLR_TARGET["Video"] = a.video_plr
    a.out.mkdir(parents=True, exist_ok=True)

    runs = find_runs(a.raw)
    if not runs:
        raise SystemExit(f"no runs in {a.raw}")
    rows, ran_rows = [], []
    for sched, seed, tag in runs:
        df, flows = load_run(a.raw, tag, a.warmup, a.window, a.nwin)
        if a.cell:
            df = df[df["flow"].isin(flows.loc[flows["cell"] == a.cell, "flow"])]
        for r in ran_stats(df):
            ran_rows.append({"scheduler": sched, "seed": seed, **r})
        for d in a.delays:
            # same random offsets for every scheduler at a given (seed, delay): paired comparison
            rng = np.random.default_rng([seed, int(round(d * 10))])
            sr = service_rate(df, flows, d, rng, a.offset_mode, a.jitter_ms, a.nwin, a.overall)
            for s, v in sr.items():
                rows.append({"scheduler": sched, "seed": seed, "delay_ms": d, "slice": s,
                             "service_rate": v})
        print(f"{tag}: {len(df)} packets, overall SR at {a.delays[0]:g} ms = "
              f"{rows[-len(a.delays) * 4 + 3]['service_rate']:.1f} %")

    per_run = pd.DataFrame(rows)
    per_run.to_csv(a.out / "per_run.csv", index=False)
    agg = (per_run.groupby(["scheduler", "delay_ms", "slice"])["service_rate"]
           .agg(mean="mean", ci95=ci95, n="count").reset_index())
    agg.to_csv(a.out / "service_rate.csv", index=False)

    ran = pd.DataFrame(ran_rows)
    ran_agg = ran.groupby(["scheduler", "slice"]).agg(
        seeds=("seed", "nunique"), ran_loss_pct=("ran_loss_pct", "mean"),
        ran_mean_ms=("ran_mean_ms", "mean"), ran_p95_ms=("ran_p95_ms", "mean"),
        ran_p99_ms=("ran_p99_ms", "mean"), ran_max_ms=("ran_max_ms", "max")).reset_index()
    ran_agg.to_csv(a.out / "ran_delay.csv", index=False)

    ref = pd.read_csv(a.ref) if a.ref.exists() else pd.DataFrame({"delay_ms": []})
    plot(agg, ref, a.out, a.delays)

    # Markdown table: overall service rate, mine vs. Rana
    allv = agg[agg["slice"] == "All"].pivot(index="delay_ms", columns="scheduler")
    lines = ["| Delay (ms) | " + " | ".join(f"{s} (mine)" for s in allv["mean"].columns)
             + " | " + " | ".join(f"Rana {c}" for c in ref.columns if c != "delay_ms") + " |"]
    lines.append("|" + " --- |" * (1 + len(allv["mean"].columns) + len(ref.columns) - 1))
    for d in allv.index:
        cells = [f"{allv['mean'].loc[d, s]:.1f} ± {allv['ci95'].loc[d, s]:.1f}"
                 for s in allv["mean"].columns]
        rr = ref[ref["delay_ms"] == d]
        cells += [f"{rr[c].iloc[0]:.1f}" if len(rr) else "–"
                  for c in ref.columns if c != "delay_ms"]
        lines.append(f"| {d:g} | " + " | ".join(cells) + " |")
    n = int(agg["n"].max())
    lines.append("")
    lines.append(f"Mean ± 95 % CI over {n} seeds; offset mode '{a.offset_mode}'.")
    (a.out / "fig6_table.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    print("\nRAN only (no server delay):")
    print(ran_agg.to_string(index=False, float_format=lambda v: f"{v:.2f}"))
    print(f"\nwrote {a.out}/fig6_reproduction.png, service_rate.csv, ran_delay.csv, fig6_table.md")


if __name__ == "__main__":
    main()
