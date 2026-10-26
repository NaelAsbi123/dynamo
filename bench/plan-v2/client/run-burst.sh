#!/usr/bin/env bash
# usage: run-burst.sh <arm a|w|c> <seed> <out dir>   Burst cell: restart workers, set the arm, scrape, start EVEN at 32 for 1200 s,
# 600 s in start BURST (200 concurrent on one 6000-token prefix, 180 s), wait for both, collect both streams and the pre/burst/post windows.
set -uo pipefail   # no -e: every failure is handled explicitly; a failing kubectl in a $(...) must not abort the cell
ARM="$1"; SEED="$2"; OUT="$3"; HERE="$(cd "$(dirname "$0")" && pwd)"; mkdir -p "$OUT"
kubectl --request-timeout=30s -n bench delete jobs -l app=aiperf --ignore-not-found >/dev/null
kubectl --request-timeout=30s -n bench rollout restart deployment/vllm-worker >/dev/null; kubectl --request-timeout=30s -n bench rollout status deployment/vllm-worker --timeout=900s >/dev/null
bash "$HERE/../k8s/set-arm.sh" "$ARM" >/dev/null
bash "$HERE/scrape-metrics.sh" "$OUT/metrics.jsonl" >/dev/null 2>&1 & SCR=$!
trap 'kill $SCR 2>/dev/null; pkill -P $SCR 2>/dev/null' EXIT
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/start.txt"
CONC=32 DURATION=1200 GRACE=900 bash "$HERE/run-workload.sh" "$ARM" EVEN "$SEED" >/dev/null; echo "$(date +%T) [$ARM] EVEN at 32 started"
sleep 600
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/burst-start.txt"
bash "$HERE/run-workload.sh" "$ARM" BURST "$((SEED+1000))" >/dev/null; echo "$(date +%T) [$ARM] BURST started"
for i in $(seq 1 200); do a=$(kubectl --request-timeout=30s -n bench logs "job/aiperf-$ARM-even-s$SEED" 2>/dev/null | grep -c AIPERF_DONE); b=$(kubectl --request-timeout=30s -n bench logs "job/aiperf-$ARM-burst-s$((SEED+1000))" 2>/dev/null | grep -c AIPERF_DONE); [ "$a" -ge 1 ] && [ "$b" -ge 1 ] && break; sleep 15; done
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/end.txt"; kill $SCR 2>/dev/null || true
STREAMS="even" bash "$HERE/collect-v2.sh" "$ARM" "$SEED" "$OUT" | head -2
STREAMS="burst" bash "$HERE/collect-v2.sh" "$ARM" "$((SEED+1000))" "$OUT" | head -2
python3 "$HERE/burst-windows.py" "$OUT"
echo "$(date +%T) [$ARM] BURST_CELL_DONE"
