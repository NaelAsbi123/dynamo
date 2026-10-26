#!/usr/bin/env bash
# usage: WL=HOT1 CONC=64 run-cell.sh (closed loop) or WL=HOTR RATE=1.0 run-cell.sh (open loop) <arm a|w|c> <seed> <out dir>   One grid cell: restart workers (clear prefix caches), set the arm, scrape, warm one holder per prefix, run WL at CONC for 600 s + drain (64 aiperf warm-up requests), collect.
set -euo pipefail
ARM="$1"; SEED="$2"; OUT="$3"; HERE="$(cd "$(dirname "$0")" && pwd)"; mkdir -p "$OUT"
echo "$(date +%T) [$ARM] restarting workers to clear prefix caches"
kubectl --request-timeout=30s -n bench delete jobs -l app=aiperf --ignore-not-found >/dev/null
kubectl --request-timeout=30s -n bench rollout restart deployment/vllm-worker >/dev/null
kubectl --request-timeout=30s -n bench rollout status deployment/vllm-worker --timeout=900s >/dev/null
echo "$(date +%T) [$ARM] setting arm"; SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ); bash "$HERE/../k8s/set-arm.sh" "$ARM" >/dev/null
for i in $(seq 1 60); do n=$(kubectl --request-timeout=30s -n bench logs deployment/dynamo-epp --since-time="$SINCE" 2>/dev/null | grep -c 'ZMQ listener starting'); [ "$n" -ge 8 ] && break; sleep 5; done
echo "$(date +%T) [$ARM] EPP sees $n KV listeners"
bash "$HERE/scrape-metrics.sh" "$OUT/metrics.jsonl" & SCR=$!
WL="${WL:-HOT1}"; CONC="${CONC:-64}"; WARM=WARM1; case "$WL" in HOT4|HOTR4) WARM=WARM4;; esac; WLL=$(echo "$WL" | tr A-Z a-z); WARML=$(echo "$WARM" | tr A-Z a-z)
if [ "$WL" != "EVEN" ]; then
  sleep 20   # let the new workers register their KV publishers before the first request
  WOK=0; for wtry in 1 2 3; do
    kubectl --request-timeout=30s -n bench delete job "aiperf-$ARM-$WARML-s$SEED" --ignore-not-found >/dev/null 2>&1
    bash "$HERE/run-workload.sh" "$ARM" "$WARM" "$SEED" >/dev/null
    for i in $(seq 1 72); do L=$(kubectl --request-timeout=30s -n bench logs "job/aiperf-$ARM-$WARML-s$SEED" 2>/dev/null); echo "$L" | grep -q AIPERF_DONE && { WOK=1; break; }; echo "$L" | grep -qE "requests? failed|Error Running AIPerf|validation error" && { echo "[$ARM] warm-up attempt $wtry failed:"; echo "$L" | grep -E "failed|Error" | head -2 | cut -c1-160; break; }; sleep 5; done
    [ "$WOK" = 1 ] && break; sleep 15
  done
  [ "$WOK" = 1 ] || { echo "[$ARM] WARM_FAILED"; kill $SCR; exit 1; }
fi
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/start.txt"; sleep 5
CONC="$CONC" RATE="${RATE:-}" DURATION="${DURATION:-600}" bash "$HERE/run-workload.sh" "$ARM" "$WL" "$SEED" >/dev/null; echo "$(date +%T) [$ARM] $WL at ${RATE:-$CONC} started"
for i in $(seq 1 200); do L=$(kubectl --request-timeout=30s -n bench logs "job/aiperf-$ARM-$WLL-s$SEED" 2>/dev/null); echo "$L" | grep -q AIPERF_DONE && break; echo "$L" | grep -qE "Error Running AIPerf|validation error|unrecognized arguments" && { echo "[$ARM] AIPERF_ARGS_FAILED"; echo "$L" | grep -E "Error|error" | head -3 | cut -c1-200; break; }; sleep 15; done
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/end.txt"; kill $SCR 2>/dev/null || true
STREAMS="$WLL" bash "$HERE/collect-v2.sh" "$ARM" "$SEED" "$OUT" | head -3
echo "$(date +%T) [$ARM] CELL_DONE"
