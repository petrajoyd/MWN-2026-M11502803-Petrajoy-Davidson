#!/usr/bin/env python3
"""Verify the slice-A traffic model and summarise per-slice KPIs for one A2 run.

    python3 analyze.py ../results intent-a70 --intent ../intents/intent-a70.json

Reads <tag>-tx.csv and <tag>-flowmon.xml from the results directory and writes:
    <tag>-traffic-model.png   PDF and CDF of frame size, frame inter-arrival,
                              packet size and packet inter-arrival: my run vs the 3GPP model
    <tag>-summary.md          KS tests + per-slice KPIs (+ SLA verdict for slice B)

The "3GPP model" curves are the TR 38.838 / TR 26.926 video model itself:
frame size and jitter as truncated Gaussians (exact PDF), inter-arrival and
packet-level curves from 10^6 Monte-Carlo draws of the same model.
"""
import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats

SIM = "#2a78d6"  # my ns-3 run
MODEL = "#eb6834"  # 3GPP model
INK = "#52514e"


def truncnorm(mean, std, lo, hi):
    return stats.truncnorm((lo - mean) / std, (hi - mean) / std, loc=mean, scale=std)


def model_draws(p, n, rng):
    """Monte-Carlo frames of the 3GPP model: sizes, inter-arrivals (ms), packet sizes."""
    mean = p["rate_mbps"] * 1e6 / p["fps"] / 8
    size = truncnorm(mean, p["std_ratio"] * mean, p["min_ratio"] * mean, p["max_ratio"] * mean)
    jit = truncnorm(0, p["jitter_std_ms"], -p["jitter_bound_ms"], p["jitter_bound_ms"])
    frames = np.rint(size.rvs(n, random_state=rng)).astype(int)
    j = jit.rvs(n + 1, random_state=rng)
    iat = 1e3 / p["fps"] + np.diff(j)
    full, rem = np.divmod(frames, p["max_payload"])
    pkt_sizes = np.concatenate([np.repeat(p["max_payload"], full.sum()), rem[rem > 0]])
    # packet inter-arrivals: zeros inside a frame (back-to-back), frame gap between frames
    pkts = full + (rem > 0)
    pkt_iat = np.concatenate([np.zeros(int((pkts[1:] - 1).sum())), iat[: n - 1]])
    return size, jit, frames, iat, pkt_sizes, pkt_iat


def ecdf(x):
    x = np.sort(np.asarray(x))
    return x, np.arange(1, len(x) + 1) / len(x)


def style(ax, title, xlabel, ylabel):
    ax.set_title(title, loc="left", fontsize=10, color="#0b0b0b")
    ax.set_xlabel(xlabel, color=INK, fontsize=9)
    ax.set_ylabel(ylabel, color=INK, fontsize=9)
    ax.tick_params(colors=INK, labelsize=8)
    ax.grid(alpha=0.25, linewidth=0.6)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)


def parse_flowmon(path):
    """Per-flow stats + destination port from FlowMonitor XML (times are '+123.0ns')."""
    root = ET.parse(path).getroot()
    ns = lambda v: float(v.strip("+").removesuffix("ns")) * 1e-9  # noqa: E731
    ports = {f.get("flowId"): int(f.get("destinationPort"))
             for f in root.iter("Flow") if f.get("destinationPort")}
    flows = []
    for f in root.find("FlowStats").iter("Flow"):
        dh = f.find("delayHistogram")
        hist = [] if dh is None else [(float(b.get("start")), float(b.get("width")), int(b.get("count")))
                                      for b in dh.iter("bin")]
        flows.append({
            "port": ports.get(f.get("flowId")),
            "tx": int(f.get("txPackets")), "rx": int(f.get("rxPackets")),
            "rx_bytes": int(f.get("rxBytes")),
            "delay_sum": ns(f.get("delaySum")),
            "t_first_rx": ns(f.get("timeFirstRxPacket")), "t_last_rx": ns(f.get("timeLastRxPacket")),
            "hist": hist,
        })
    return flows


def hist_percentile(hist, q):
    if not hist:
        return float("nan")
    hist = sorted(hist)
    counts = np.array([c for _, _, c in hist])
    cum = np.cumsum(counts) / counts.sum()
    i = int(np.searchsorted(cum, q))
    start, width, _ = hist[i]
    return start + width  # upper edge: conservative


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results", type=Path)
    ap.add_argument("tag")
    ap.add_argument("--intent", type=Path, help="intent JSON (for slice-B SLA verdict)")
    ap.add_argument("--rate-mbps", type=float, default=30)
    ap.add_argument("--fps", type=float, default=60)
    ap.add_argument("--max-payload", type=int, default=1400)
    ap.add_argument("--port-a", type=int, default=5000)
    ap.add_argument("--port-b", type=int, default=6000)
    a = ap.parse_args()

    intent = json.loads(a.intent.read_text()) if a.intent else None
    if intent:
        a.rate_mbps = intent["slices"]["A"]["traffic"]["rate_mbps"]
        a.fps = intent["slices"]["A"]["traffic"]["fps"]
    p = dict(rate_mbps=a.rate_mbps, fps=a.fps, std_ratio=0.105, min_ratio=0.5, max_ratio=1.5,
             jitter_std_ms=2.0, jitter_bound_ms=4.0, max_payload=a.max_payload)

    # ---- my run ----
    tx = pd.read_csv(a.results / f"{a.tag}-tx.csv")
    frames = tx[tx.pkt_idx == 0].sort_values(["ue", "time_ns"])
    f_size = frames.frame_bytes.to_numpy()
    f_iat = np.concatenate([np.diff(g.time_ns.to_numpy()) / 1e6 for _, g in frames.groupby("ue")])
    p_size = tx.pkt_bytes.to_numpy()
    p_iat = np.concatenate([np.diff(g.sort_values("time_ns").time_ns.to_numpy()) / 1e6
                            for _, g in tx.groupby("ue")])

    # ---- 3GPP model ----
    rng = np.random.default_rng(1)
    size_rv, jit_rv, m_size, m_iat, m_psize, m_piat = model_draws(p, 1_000_000, rng)

    ks_size = stats.kstest(f_size, size_rv.cdf)
    ks_iat = stats.ks_2samp(f_iat, m_iat)
    ks_jit = stats.kstest(frames.jitter_ms.to_numpy(), jit_rv.cdf)

    # ---- figure: 4 rows (quantity) x 2 cols (PDF, CDF) ----
    fig, axs = plt.subplots(4, 2, figsize=(11, 13), facecolor="#fcfcfb")
    mean = size_rv.mean()

    xs = np.linspace(p["min_ratio"] * mean, p["max_ratio"] * mean, 400)
    ax = axs[0, 0]
    ax.hist(f_size / 1e3, bins=40, density=True, color=SIM, alpha=0.75, edgecolor="#fcfcfb",
            linewidth=1, label=f"my ns-3 run (n={len(f_size)} frames)")
    ax.plot(xs / 1e3, size_rv.pdf(xs) * 1e3, color=MODEL, lw=2, label="3GPP model (exact)")
    style(ax, "Frame size: PDF", "frame size (kB)", "density (1/kB)")
    ax.legend(fontsize=8, frameon=False)
    ax = axs[0, 1]
    ax.plot(*ecdf(f_size / 1e3), color=SIM, lw=2, drawstyle="steps-post", label="my ns-3 run")
    ax.plot(xs / 1e3, size_rv.cdf(xs), color=MODEL, lw=2, ls="--", label="3GPP model")
    style(ax, f"Frame size: CDF   (KS D={ks_size.statistic:.3f}, p={ks_size.pvalue:.2f})",
          "frame size (kB)", "P(X ≤ x)")
    ax.legend(fontsize=8, frameon=False)

    bins = np.linspace(1e3 / p["fps"] - 2 * p["jitter_bound_ms"], 1e3 / p["fps"] + 2 * p["jitter_bound_ms"], 50)
    ax = axs[1, 0]
    ax.hist(f_iat, bins=bins, density=True, color=SIM, alpha=0.75, edgecolor="#fcfcfb", linewidth=1,
            label="my ns-3 run")
    mh, me = np.histogram(m_iat, bins=bins, density=True)
    ax.plot((me[1:] + me[:-1]) / 2, mh, color=MODEL, lw=2, label="3GPP model (Monte Carlo)")
    style(ax, "Frame inter-arrival time: PDF", "inter-arrival (ms)", "density (1/ms)")
    ax.legend(fontsize=8, frameon=False)
    ax = axs[1, 1]
    ax.plot(*ecdf(f_iat), color=SIM, lw=2, drawstyle="steps-post", label="my ns-3 run")
    ax.plot(*ecdf(m_iat[::50]), color=MODEL, lw=2, ls="--", label="3GPP model")
    style(ax, f"Frame inter-arrival: CDF   (KS D={ks_iat.statistic:.3f}, p={ks_iat.pvalue:.2f})",
          "inter-arrival (ms)", "P(X ≤ x)")
    ax.legend(fontsize=8, frameon=False)

    ax = axs[2, 0]
    pb = np.arange(0, p["max_payload"] + 50, 50)
    ax.hist(p_size, bins=pb, density=True, color=SIM, alpha=0.75, edgecolor="#fcfcfb", linewidth=1,
            label="my ns-3 run")
    mh, me = np.histogram(m_psize, bins=pb, density=True)
    ax.step(me[:-1], mh, where="post", color=MODEL, lw=2, label="3GPP model (Monte Carlo)")
    ax.set_yscale("log")
    style(ax, "Packet size: PDF (log scale)", "UDP payload (bytes)", "density (1/byte)")
    ax.legend(fontsize=8, frameon=False)
    ax = axs[2, 1]
    ax.plot(*ecdf(p_size), color=SIM, lw=2, drawstyle="steps-post", label="my ns-3 run")
    ax.plot(*ecdf(m_psize[::20]), color=MODEL, lw=2, ls="--", label="3GPP model")
    style(ax, "Packet size: CDF", "UDP payload (bytes)", "P(X ≤ x)")
    ax.legend(fontsize=8, frameon=False)

    ax = axs[3, 0]
    nz, mnz = p_iat[p_iat > 0], m_piat[m_piat > 0]
    ax.hist(nz, bins=bins, density=True, color=SIM, alpha=0.75, edgecolor="#fcfcfb", linewidth=1,
            label=f"my ns-3 run ({100 * (p_iat == 0).mean():.1f} % are 0 ms, not shown)")
    mh, me = np.histogram(mnz, bins=bins, density=True)
    ax.plot((me[1:] + me[:-1]) / 2, mh, color=MODEL, lw=2, label="3GPP model (Monte Carlo)")
    style(ax, "Packet inter-arrival time: PDF of the non-zero gaps", "inter-arrival (ms)",
          "density (1/ms)")
    ax.legend(fontsize=8, frameon=False)
    ax = axs[3, 1]
    ax.plot(*ecdf(p_iat), color=SIM, lw=2, drawstyle="steps-post", label="my ns-3 run")
    ax.plot(*ecdf(m_piat[::50]), color=MODEL, lw=2, ls="--", label="3GPP model")
    style(ax, "Packet inter-arrival time: CDF", "inter-arrival (ms)", "P(X ≤ x)")
    ax.legend(fontsize=8, frameon=False)

    fig.suptitle(f"Slice A traffic model check ({a.tag}): {p['rate_mbps']:.0f} Mbps, "
                 f"{p['fps']:.0f} fps, frames cut into ≤{p['max_payload']} B packets",
                 x=0.02, ha="left", fontsize=12)
    fig.tight_layout(rect=(0, 0, 1, 0.98))
    png = a.results / f"{a.tag}-traffic-model.png"
    fig.savefig(png, dpi=150)

    # ---- KPIs from FlowMonitor ----
    flows = parse_flowmon(a.results / f"{a.tag}-flowmon.xml")
    rows = []
    for name, port in (("A", a.port_a), ("B", a.port_b)):
        fl = [f for f in flows if f["port"] == port]
        if not fl:
            continue
        tx_, rx_ = sum(f["tx"] for f in fl), sum(f["rx"] for f in fl)
        dur = max(f["t_last_rx"] for f in fl) - min(f["t_first_rx"] for f in fl)
        hist = [b for f in fl for b in f["hist"]]
        rows.append({
            "slice": name, "flows": len(fl),
            "throughput_mbps": 8 * sum(f["rx_bytes"] for f in fl) / dur / 1e6 if dur > 0 else 0,
            "mean_delay_ms": 1e3 * sum(f["delay_sum"] for f in fl) / rx_ if rx_ else float("nan"),
            "p95_delay_ms": 1e3 * hist_percentile(hist, 0.95),
            "loss_pct": 100 * (tx_ - rx_) / tx_ if tx_ else 0,
        })
    kpi = pd.DataFrame(rows)

    lines = [f"# Run `{a.tag}`", "",
             f"![traffic model check]({png.name})", "",
             "## Traffic model check (slice A)", "",
             "| Quantity | Samples | My mean | 3GPP model mean | KS test |",
             "| --- | --- | --- | --- | --- |",
             f"| Frame size (B) | {len(f_size)} | {f_size.mean():.0f} | {size_rv.mean():.0f} | "
             f"D={ks_size.statistic:.3f}, p={ks_size.pvalue:.2f} |",
             f"| Frame jitter (ms) | {len(frames)} | {frames.jitter_ms.mean():.2f} | 0.00 | "
             f"D={ks_jit.statistic:.3f}, p={ks_jit.pvalue:.2f} |",
             f"| Frame inter-arrival (ms) | {len(f_iat)} | {f_iat.mean():.2f} | {m_iat.mean():.2f} | "
             f"D={ks_iat.statistic:.3f}, p={ks_iat.pvalue:.2f} (two-sample) |",
             f"| Packet size (B) | {len(p_size)} | {p_size.mean():.0f} | {m_psize.mean():.0f} | n/a |",
             f"| Packet inter-arrival (ms) | {len(p_iat)} | {p_iat.mean():.3f} | {m_piat.mean():.3f} | n/a |",
             "", "p > 0.05: no evidence that my generator differs from the model.", "",
             "## Per-slice KPIs (FlowMonitor)", "",
             "| Slice | Flows | Throughput (Mbps) | Mean delay (ms) | p95 delay (ms) | Loss (%) |",
             "| --- | --- | --- | --- | --- | --- |",
             *[f"| {r.slice} | {r.flows} | {r.throughput_mbps:.2f} | {r.mean_delay_ms:.3f} | "
               f"{r.p95_delay_ms:.2f} | {r.loss_pct:.2f} |" for r in kpi.itertuples()], ""]
    if intent and len(kpi):
        sla = intent["slices"]["B"].get("sla", {})
        b = kpi[kpi.slice == "B"].iloc[0]
        ok_d = b.p95_delay_ms <= sla.get("delay_p95_ms", float("inf"))
        ok_l = b.loss_pct <= sla.get("loss_pct", float("inf"))
        lines += ["## Slice B SLA", "",
                  f"- p95 delay {b.p95_delay_ms:.2f} ms vs target {sla.get('delay_p95_ms')} ms: "
                  f"{'met' if ok_d else 'VIOLATED'}",
                  f"- loss {b.loss_pct:.2f} % vs target {sla.get('loss_pct')} %: "
                  f"{'met' if ok_l else 'VIOLATED'}",
                  f"- **Verdict: {'SLA met' if ok_d and ok_l else 'SLA violated'}** "
                  f"(intent `{intent['intent_id']}` was accepted by the capacity-only check)", ""]
    out = a.results / f"{a.tag}-summary.md"
    out.write_text("\n".join(lines))
    print("\n".join(lines))
    print(f"\nWrote {png} and {out}")


if __name__ == "__main__":
    main()
