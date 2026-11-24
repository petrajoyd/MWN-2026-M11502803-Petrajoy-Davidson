#!/usr/bin/env python3
"""Per-UE and per-cell loss / RAN delay of one run, to tune coverage and load.

    python3 diag_run.py ../results/raw/smoke-Qos          (prefix of the run's files)

Packets sent in the last 0.5 s are left out (still in flight when the run stops).
"""
import sys

import numpy as np
import pandas as pd

SMALL_X = 300.0  # small-cell position in a4-rana-servicerate.cc

p = sys.argv[1]
tx = pd.read_csv(f"{p}-tx.csv")
rx = pd.read_csv(f"{p}-rx.csv")
f = pd.read_csv(f"{p}-flows.csv").set_index("flow")
tx = tx[tx.time_ns < tx.time_ns.max() - 0.5e9]
rx = rx.merge(tx[["flow", "seq"]], on=["flow", "seq"])
rx["d"] = (rx.time_ns - rx.tx_ns) / 1e6

g = (tx.groupby("flow").size().rename("tx").to_frame()
     .join(rx.groupby("flow").size().rename("rx"))
     .join(rx.groupby("flow").d.mean().rename("delay_ms"))
     .join(rx.groupby("flow").d.quantile(0.95).rename("p95_ms"))
     .join(f))
g["rx"] = g.rx.fillna(0)
g["loss%"] = 100 * (1 - g.rx / g.tx)
g["dist_m"] = np.hypot(g.x0 - np.where(g.cell == "macro", 0, SMALL_X), g.y0)
cols = ["slice", "cell", "speed_kmh", "dist_m", "tx", "rx", "loss%", "delay_ms", "p95_ms"]
print(g[cols].round(1).sort_values(["cell", "dist_m"]).to_string())
print()
c = g.groupby(["cell", "slice"]).agg(tx=("tx", "sum"), rx=("rx", "sum"),
                                     delay_ms=("delay_ms", "mean"), p95_ms=("p95_ms", "mean"))
c["loss%"] = 100 * (1 - c.rx / c.tx)
print(c.round(1).to_string())
