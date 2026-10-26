#!/usr/bin/env bash
# usage: run-w6.sh <arm a|b|c> <seed>   Hot-tenant benchmark with a warm holder:
#  1. W6warm: 2 sequential requests (one per hot prefix) so exactly one worker caches each prefix
#  2. wait for the KV events to land, then start W5hot (hot tenant, 32 concurrent) and W5bg (background) together
# Use a seed whose prefixes no worker has cached yet (prefixes replicate during a run).
set -euo pipefail
ARM="${1:?arm}"; SEED="${2:?seed}"; WL="${WL:-W5}"   # WL=W5 (burst) or WL=W7 (spaced, long decode)
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-$HERE/../results/run4-arm-$ARM-$(echo $WL | tr A-Z a-z)-s$SEED}"; mkdir -p "$OUT"
kubectl -n bench delete jobs -l app=aiperf --ignore-not-found >/dev/null 2>&1 || true
bash "$HERE/run-workload.sh" "$ARM" W6warm "$SEED" >/dev/null
# the warm pod spends ~70 s on pip install before its 2 requests; allow up to 10 minutes
for i in $(seq 1 120); do
  if kubectl -n bench logs "job/aiperf-$ARM-w6warm-s$SEED" 2>/dev/null | grep -q AIPERF_DONE; then break; fi
  sleep 5
done
kubectl -n bench logs "job/aiperf-$ARM-w6warm-s$SEED" 2>/dev/null | grep -q AIPERF_DONE || { echo "warm-up did not finish"; exit 1; }
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/warm-done.txt"
sleep 8
date -u +%Y-%m-%dT%H:%M:%SZ | tee "$OUT/start.txt"
bash "$HERE/run-workload.sh" "$ARM" "${WL}hot" "$SEED" >/dev/null
bash "$HERE/run-workload.sh" "$ARM" "${WL}bg" "$SEED" >/dev/null
echo "started arm $ARM seed $SEED: warm-up done at $(cat "$OUT/warm-done.txt"), burst at $(cat "$OUT/start.txt")"
