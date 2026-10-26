#!/usr/bin/env bash
# usage: scrape-metrics.sh <out file> ; every 5 s, one JSON line per worker: vLLM running / waiting / KV usage / prefix hits / queries / preemptions and nvidia-smi GPU util / memory.
set -uo pipefail
OUT="$1"; : > "$OUT"
while true; do
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  for p in $(kubectl --request-timeout=30s -n bench get pods -l app=vllm-worker -o jsonpath='{.items[*].metadata.name}'); do
    ( M=$(kubectl --request-timeout=30s -n bench exec "$p" -- sh -c 'curl -s -m 3 localhost:8000/metrics | grep -E "^vllm:(num_requests_running|num_requests_waiting|kv_cache_usage_perc|prefix_cache_hits_total|prefix_cache_queries_total|num_preemptions_total)\{"; echo GPU; nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null' 2>/dev/null)
      echo "$M" | awk -v ts="$TS" -v pod="$p" 'BEGIN{g=0} /^GPU$/{g=1; next} g==1{split($0,x,","); gpu=x[1]+0; mem=x[2]+0; next} /^vllm:/{split($1,a,"{"); m[a[1]]=$2} END {printf "{\"ts\":\"%s\",\"pod\":\"%s\",\"running\":%s,\"waiting\":%s,\"kv_usage\":%s,\"hits\":%s,\"queries\":%s,\"preemptions\":%s,\"gpu_util\":%s,\"gpu_mem_mib\":%s}\n", ts, pod, m["vllm:num_requests_running"]+0, m["vllm:num_requests_waiting"]+0, m["vllm:kv_cache_usage_perc"]+0, m["vllm:prefix_cache_hits_total"]+0, m["vllm:prefix_cache_queries_total"]+0, m["vllm:num_preemptions_total"]+0, gpu+0, mem+0}' >> "$OUT" ) &
  done
  wait; sleep 5
done
