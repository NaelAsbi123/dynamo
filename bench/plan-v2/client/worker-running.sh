#!/usr/bin/env bash
# usage: worker-running.sh <start RFC3339> <end RFC3339>
# Per vLLM worker: mean and peak of "Running: N reqs" engine-stat samples (every 10 s) inside the window.
# Hotspot view for slow workloads where the EPP pick log has too few picks per window.
set -euo pipefail
S="$1"; E="$2"
for p in $(kubectl -n bench get pods -l app=vllm-worker -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n bench logs "$p" --since-time="$S" --timestamps 2>/dev/null | awk -v e="$E" '$1<=e' \
   | grep -oE "Running: [0-9]+ reqs" | awk -v p="$p" '{n++; s+=$2; if($2>m)m=$2} END{printf "%-30s samples=%-3d mean_running=%.1f peak=%d\n", p, n, (n?s/n:0), m}'
done | sort -t= -k3 -rn
