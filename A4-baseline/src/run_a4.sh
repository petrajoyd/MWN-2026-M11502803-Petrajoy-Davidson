#!/usr/bin/env bash
# A4 sweep: 5G-LENA schedulers x seeds, then the analysis.
# Run on the lab VM from this directory:   bash run_a4.sh
#
# Environment overrides (examples):
#   SCHEDULERS="Qos PF" SEEDS="1 2 3 4 5 6 7 8 9 10" JOBS=6 bash run_a4.sh
#   EXTRA="--nVideo=10 --hetnet=0" bash run_a4.sh      # passed to every run
#   SMOKE=1 bash run_a4.sh                             # one 4 s run, to check build + speed
set -euo pipefail

NS3=${NS3:-$HOME/ns-3-dev}
HERE=$(cd "$(dirname "$0")" && pwd)
RAW=${RAW:-$HERE/../results/raw}
OUT=${OUT:-$HERE/../results}
SCHEDULERS=${SCHEDULERS:-"Qos PF"}
SEEDS=${SEEDS:-"1 2 3 4 5"}
JOBS=${JOBS:-5}
EXTRA=${EXTRA:-""}
PROG=a4-rana-servicerate

mkdir -p "$RAW"
cp "$HERE/$PROG.cc" "$NS3/scratch/"
(cd "$NS3" && ./ns3 build "$PROG")
BIN=$(ls "$NS3"/build/scratch/ns3.*-"$PROG"-* 2>/dev/null | head -1)
[ -x "$BIN" ] || { echo "binary not found under $NS3/build/scratch"; exit 1; }

if [ "${SMOKE:-0}" = 1 ]; then
  /usr/bin/time -v "$BIN" --scheduler=Qos --RngRun=1 --simTime=4s --simTag=smoke \
      --outputDir="$RAW" $EXTRA 2>&1 | grep -E "MTC|VoIP|Video|A4 run|Elapsed|Maximum resident"
  echo "-> a 22.5 s run takes about (Elapsed x 22.5/4). Delete $RAW/smoke-* before the sweep."
  exit 0
fi

echo "$(date) start: schedulers [$SCHEDULERS], seeds [$SEEDS], $JOBS in parallel, extra [$EXTRA]"
for s in $SCHEDULERS; do for r in $SEEDS; do echo "$s $r"; done; done |
  xargs -P "$JOBS" -L 1 bash -c '
    sched=$0; seed=$1
    tag="$sched-s$seed"
    if [ -s "'"$RAW"'/$tag-flows.csv" ] && [ -s "'"$RAW"'/$tag-summary.txt" ]; then
      echo "skip $tag (done)"; exit 0; fi
    start=$(date +%s)
    nice "'"$BIN"'" --scheduler="$sched" --RngRun="$seed" --simTag="$tag" \
         --outputDir="'"$RAW"'" '"$EXTRA"' > "'"$RAW"'/$tag-stdout.txt" 2>&1 \
      && echo "$(date +%T) done $tag in $(( $(date +%s) - start )) s" \
      || echo "$(date +%T) FAILED $tag, see $tag-stdout.txt"'

echo "$(date) simulations finished"
python3 "$HERE/analyze_a4.py" "$RAW" --out "$OUT"
