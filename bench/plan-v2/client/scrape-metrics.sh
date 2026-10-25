#!/usr/bin/env bash
# usage: scrape-metrics.sh <out file> ; samples every worker's /metrics every 5 s until killed. One JSON line per worker per sample.
set -uo pipefail
OUT="$1"; : > "$OUT"
while true; do
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  for p in $(kubectl -n bench get pods -l app=vllm-worker -o jsonpath='{.items[*].metadata.name}'); do
    kubectl -n bench exec "$p" -- curl -s -m 3 localhost:8000/metrics 2>/dev/null \
     | awk -v ts="$TS" -v pod="$p" '/^vllm:(num_requests_running|num_requests_waiting|prefix_cache_hits_total|prefix_cache_queries_total|num_preemptions_total)\{/ {split($1,a,"{"); m[a[1]]=$2} END {printf "{\"ts\":\"%s\",\"pod\":\"%s\",\"running\":%s,\"waiting\":%s,\"hits\":%s,\"queries\":%s,\"preemptions\":%s}\n", ts, pod, m["vllm:num_requests_running"]+0, m["vllm:num_requests_waiting"]+0, m["vllm:prefix_cache_hits_total"]+0, m["vllm:prefix_cache_queries_total"]+0, m["vllm:num_preemptions_total"]+0}' >> "$OUT" &
  done
  wait; sleep 5
done
