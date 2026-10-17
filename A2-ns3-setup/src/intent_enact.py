#!/usr/bin/env python3
"""Intent -> enactment for the A2 two-slice scenario.

Reads a slice intent (JSON), runs the capacity-only feasibility check that today's
intent pipelines use (the A1 baseline: "does it fit?"), translates the intent into
ns-3 arguments, and optionally runs the simulation.

    python3 intent_enact.py ../intents/intent-a70.json --ns3 ~/ns-3-dev --out ../results --run

The QoS-aware check from my proposal is NOT here yet (final project). This script
enacts every intent that fits, which is exactly the behaviour the project will improve.
"""
import argparse
import json
import math
import shlex
import subprocess
import sys
from pathlib import Path

SCS_KHZ = {0: 15, 1: 30, 2: 60, 3: 120, 4: 240}
MIN_RB_PER_SLICE = 11  # my threshold: below this a BWP is too small to schedule anything useful


def rbs(bandwidth_hz: float, numerology: int) -> int:
    return math.floor(bandwidth_hz / (12 * SCS_KHZ[numerology] * 1e3))


def capacity_check(intent: dict, numerology: int) -> list[str]:
    """Capacity-only feasibility: shares are valid, sum to <= 1, every slice gets >= MIN_RB."""
    problems = []
    slices = intent["slices"]
    if set(slices) != {"A", "B"}:
        problems.append("this scenario has exactly two slices, A and B")
        return problems
    total_hz = intent["total_bandwidth_mhz"] * 1e6
    share_sum = sum(s["bw_share"] for s in slices.values())
    if share_sum > 1 + 1e-9:
        problems.append(f"bandwidth shares sum to {share_sum:.2f} > 1")
    for name, s in slices.items():
        if not 0 < s["bw_share"] < 1:
            problems.append(f"slice {name}: bw_share must be in (0, 1)")
            continue
        n = rbs(total_hz * s["bw_share"], numerology)
        if n < MIN_RB_PER_SLICE:
            problems.append(f"slice {name}: {n} RBs < {MIN_RB_PER_SLICE}")
    return problems


def to_ns3_args(intent: dict, numerology: int, out_dir: str, sim_time: float) -> list[str]:
    a, b = intent["slices"]["A"], intent["slices"]["B"]
    args = {
        "intentId": intent["intent_id"],
        "totalBandwidth": intent["total_bandwidth_mhz"] * 1e6,
        "sliceAShare": a["bw_share"],
        "uesSliceA": a["ues"],
        "uesSliceB": b["ues"],
        "videoRateMbps": a["traffic"]["rate_mbps"],
        "videoFps": a["traffic"]["fps"],
        "llPacketBytes": b["traffic"]["packet_bytes"],
        "llPeriodMs": b["traffic"]["period_ms"],
        "numerology": numerology,
        "simTime": f"{sim_time}s",
        "simTag": f"intent-{intent['intent_id']}",
        "outputDir": out_dir,
    }
    return [f"--{k}={v}" for k, v in args.items()]


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("intent", type=Path)
    p.add_argument("--ns3", type=Path, default=Path.home() / "ns-3-dev", help="ns-3 root")
    p.add_argument("--out", type=Path, default=Path("results"), help="output directory")
    p.add_argument("--numerology", type=int, default=2)
    p.add_argument("--sim-time", type=float, default=6.0, help="seconds")
    p.add_argument("--run", action="store_true", help="run the simulation (otherwise only print the command)")
    args = p.parse_args()

    intent = json.loads(args.intent.read_text())
    problems = capacity_check(intent, args.numerology)
    total_hz = intent["total_bandwidth_mhz"] * 1e6
    print(f"Intent {intent['intent_id']}: {intent.get('statement', '')}")
    for name, s in intent["slices"].items():
        print(f"  slice {name}: {s['bw_share'] * 100:.0f} % = {total_hz * s['bw_share'] / 1e6:.0f} MHz"
              f" = {rbs(total_hz * s['bw_share'], args.numerology)} RBs (numerology {args.numerology})")
    if problems:
        print("Capacity check: REJECT")
        for msg in problems:
            print(f"  - {msg}")
        return 1
    print("Capacity check: ACCEPT (fits in the carrier; QoS impact not checked)")

    args.out.mkdir(parents=True, exist_ok=True)
    out_dir = str(args.out.resolve())
    run_arg = "a2-intent-slicing " + " ".join(to_ns3_args(intent, args.numerology, out_dir, args.sim_time))
    cmd = ["./ns3", "run", run_arg]
    print("Enactment command (run from the ns-3 root):")
    print("  " + " ".join(shlex.quote(c) for c in cmd))

    record = {"intent": intent, "capacity_check": "accept", "ns3_command": cmd}
    (args.out / f"intent-{intent['intent_id']}-enactment.json").write_text(json.dumps(record, indent=2))

    if args.run:
        return subprocess.call(cmd, cwd=args.ns3)
    return 0


if __name__ == "__main__":
    sys.exit(main())
