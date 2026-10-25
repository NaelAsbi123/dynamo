#!/usr/bin/env bash
# usage: WL=HOT1 CONC=64 run-cell.sh (closed loop) or WL=HOTR RATE=1.0 run-cell.sh (open loop) <arm a|w|c> <seed> <out dir>   One grid cell: restart workers (clear prefix caches), set the arm, scrape, warm one holder per prefix, run WL at CONC for 600 s + drain (64 aiperf warm-up requests), collect.
set -euo pipefail
ARM="$1"; SEED="$2"; OUT="$3"; HERE="$(cd "$(dirname "$0")" && pwd)"; mkdir -p "$OUT"
echo "$(date +%T) [$ARM] restarting workers to clear prefix caches"
kubectl -n bench delete jobs -l app=aiperf --ignore-not-found >/dev/null
kubectl -n bench rollout restart deployment/vllm-worker >/dev/null
kubectl -n bench rollout status deployment/vllm-worker --timeout=900s >/dev/null
echo "$(date +%T) [$ARM] setting arm"; bash "$HERE/../k8s/set-arm.sh" "$ARM" >/dev/null
for i in $(seq 1 30); do n=$(kubectl -n bench logs deployment/dynamo-epp --tail=400 2>/dev/null | grep -c 'ZMQ listener starting'); [ "$n" -ge 8 ] && break; sleep 5; done
echo "$(date +%T) [$ARM] EPP sees $n KV listeners"
bash "$HERE/scrape-metrics.sh" "$OUT/metrics.jsonl" & SCR=$!
WL="${WL:-HOT1}"; CONC="${CONC:-64}"; WARM=WARM1; case "$WL" in HOT4|HOTR4) WARM=WARM4;; esac; WLL=$(echo "$WL" | tr A-Z a-z); WARML=$(echo "$WARM" | tr A-Z a-z)
if [ "$WL" != "EVEN" ]; then
  bash "$HERE/run-workload.sh" "$ARM" "$WARM" "$SEED" >/dev/null
  for i in $(seq 1 120); do kubectl -n bench logs "job/aiperf-$ARM-$WARML-s$SEED" 2>/dev/null | grep -q AIPERF_DONE && break; sleep 5; done
  kubectl -n bench logs "job/aiperf-$ARM-$WARML-s$SEED" 2>/dev/null | grep -q AIPERF_DONE || { echo "[$ARM] WARM_FAILED"; kill $SCR; exit 1; }
fi
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/start.txt"; sleep 5
CONC="$CONC" RATE="${RATE:-}" DURATION="${DURATION:-600}" bash "$HERE/run-workload.sh" "$ARM" "$WL" "$SEED" >/dev/null; echo "$(date +%T) [$ARM] $WL at ${RATE:-$CONC} started"
for i in $(seq 1 200); do L=$(kubectl -n bench logs "job/aiperf-$ARM-$WLL-s$SEED" 2>/dev/null); echo "$L" | grep -q AIPERF_DONE && break; echo "$L" | grep -qE "Error Running AIPerf|validation error|unrecognized arguments" && { echo "[$ARM] AIPERF_ARGS_FAILED"; echo "$L" | grep -E "Error|error" | head -3 | cut -c1-200; break; }; sleep 15; done
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/end.txt"; kill $SCR 2>/dev/null || true
STREAMS="$WLL" bash "$HERE/collect-v2.sh" "$ARM" "$SEED" "$OUT" | head -3
echo "$(date +%T) [$ARM] CELL_DONE"
