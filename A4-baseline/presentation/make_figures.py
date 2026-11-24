#!/usr/bin/env python3
"""Figures for the A4 slides, from the A4 results.  python3 make_figures.py"""
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
from PIL import Image

HERE = Path(__file__).resolve().parent
A4 = HERE.parent
RES = A4 / "results"
FIG = HERE / "figures"
FIG.mkdir(exist_ok=True)
plt.rcParams.update({"font.size": 13, "font.family": "Calibri"})

# 1) Rana Fig. 6 only (top part of the A3 screenshot)
src = Image.open(A4.parent / "A3-literature-review/presentation/figures/rana-fig6-fig7.png")
w, h = src.size
src.crop((0, 0, w, int(h * 0.475))).save(FIG / "rana-fig6.png")

# 2) Scenario map from the UE start positions of one run
fl = pd.read_csv(RES / "raw/PF-s1-flows.csv")
fig, ax = plt.subplots(figsize=(6.4, 6.0))
ax.add_patch(plt.Rectangle((-300, -300), 600, 600, fill=False, ec="#1F4E79", lw=1.5))
ax.add_patch(plt.Rectangle((190, -110), 220, 220, fill=False, ec="#C55A11", lw=1.5, ls="--"))
ax.plot(0, 0, "^", color="#1F4E79", ms=16)
ax.plot(300, 0, "^", color="#C55A11", ms=13)
ax.text(0, -35, "Macro gNB\n3.7 GHz, 43 dBm", ha="center", va="top", fontsize=11, color="#1F4E79")
ax.text(300, 120, "Small cell\n28 GHz, 30 dBm", ha="center", va="bottom", fontsize=11, color="#C55A11")
mk = {"MTC": "s", "VoIP": "o", "Video": "D"}
col = {"MTC": "#3a9e5b", "VoIP": "#7f7f7f", "Video": "#2a78d6"}
for s in ["MTC", "VoIP", "Video"]:
    for fast in [False, True]:
        d = fl[(fl.slice == s) & ((fl.speed_kmh > 50) == fast)]
        if len(d):
            ax.scatter(d.x0, d.y0, marker=mk[s], s=70, c="white" if fast else col[s],
                       edgecolors=col[s], linewidths=1.8,
                       label=f"{s} ({'100' if fast else '3'} km/h)")
ax.set_xlim(-330, 450); ax.set_ylim(-330, 330); ax.set_aspect("equal")
ax.set_xlabel("x (m)"); ax.set_ylabel("y (m)")
ax.legend(fontsize=10, loc="upper center", bbox_to_anchor=(0.5, -0.12), ncol=3, frameon=False)
ax.grid(alpha=0.25)
fig.tight_layout(); fig.savefig(FIG / "scenario.png", dpi=220); plt.close(fig)

# 3) Overall service rate vs Rana, large
agg = pd.read_csv(RES / "service_rate.csv")
ref = pd.read_csv(A4 / "reference/rana_fig6.csv")
fig, ax = plt.subplots(figsize=(8, 4.8))
for name, c, m in [("Proposed", "#8e44ad", "+"), ("FLS", "#5bb5d9", "s"), ("CBAP", "#1f8a70", "x")]:
    ax.plot(ref.delay_ms, ref[name], ls="--", color=c, marker=m, lw=1.3, label=f"Rana: {name}")
for sch, c, lab in [("PF", "#eb6834", "Mine: 5G-LENA PF"), ("Qos", "#2a78d6", "Mine: 5G-LENA QoS")]:
    g = agg[(agg.slice == "All") & (agg.scheduler == sch)].sort_values("delay_ms")
    ax.plot(g.delay_ms, g["mean"], color=c, marker="o", lw=2.4, label=lab)
    ax.fill_between(g.delay_ms, g["mean"] - g.ci95, g["mean"] + g.ci95, color=c, alpha=0.15, lw=0)
ax.set_xlabel("Mean server → UPF delay (ms)"); ax.set_ylabel("Service rate (%)")
ax.set_xticks(ref.delay_ms); ax.set_ylim(30, 100); ax.grid(alpha=0.3)
ax.legend(fontsize=10, loc="lower left", ncol=2, frameon=False)
fig.tight_layout(); fig.savefig(FIG / "fig6-mine-vs-rana.png", dpi=220); plt.close(fig)

# 4) Same, macro UEs only (sensitivity)
m = pd.read_csv(RES / "sens-macro/service_rate.csv")
fig, ax = plt.subplots(figsize=(8, 4.8))
ax.plot(ref.delay_ms, ref["FLS"], ls="--", color="#5bb5d9", marker="s", lw=1.3, label="Rana: FLS")
ax.plot(ref.delay_ms, ref["CBAP"], ls="--", color="#1f8a70", marker="x", lw=1.3, label="Rana: CBAP")
for d, ls, lab in [(agg, ":", "PF, all UEs"), (m, "-", "PF, macro UEs only")]:
    g = d[(d.slice == "All") & (d.scheduler == "PF")].sort_values("delay_ms")
    ax.plot(g.delay_ms, g["mean"], color="#eb6834", ls=ls, marker="o", lw=2.4, label=lab)
ax.set_xlabel("Mean server → UPF delay (ms)"); ax.set_ylabel("Service rate (%)")
ax.set_xticks(ref.delay_ms); ax.set_ylim(30, 100); ax.grid(alpha=0.3)
ax.legend(fontsize=10, loc="lower left", frameon=False)
fig.tight_layout(); fig.savefig(FIG / "fig6-macro-only.png", dpi=220); plt.close(fig)
print("figures in", FIG)
