#!/usr/bin/env bash
# usage: STREAMS="hot1" collect-v2.sh <arm> <seed> <out dir>   (after every stream printed AIPERF_DONE; start.txt/end.txt in out dir)
# STREAMS = lower-case workload names of the aiperf jobs to collect (default "hot1"; e.g. "even burst" for the burst cell)
set -euo pipefail
ARM="$1"; SEED="$2"; OUT="$3"; START=$(cat "$OUT/start.txt"); END=$(cat "$OUT/end.txt"); STREAMS="${STREAMS:-hot1}"
for W in $STREAMS; do
  mkdir -p "$OUT/$W"; POD=$(kubectl -n bench get pods -l app=aiperf,arm=$ARM,workload=$W --no-headers | awk '{print $1}' | head -1)
  for f in profile_export_aiperf.json profile_export.jsonl inputs.json; do
    kubectl -n bench exec "$POD" -- cat "/artifacts/$ARM-$W-s$SEED/$f" > "$OUT/$W/$f" 2>/dev/null || echo "missing $W/$f"
  done
done
# EPP picks in the window
kubectl -n bench logs deployment/dynamo-epp --since-time="$START" --timestamps > "$OUT/epp.log" 2>/dev/null
awk -v e="$END" '$1<=e' "$OUT/epp.log" | grep -i 'Selected worker' | grep -oE 'worker_id[^ ]*=[^ ]*[0-9]+' | sort | uniq -c | sort -rn > "$OUT/picks.txt" || true
# per-worker engine stats (running + waiting) in the window
for p in $(kubectl -n bench get pods -l app=vllm-worker -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n bench logs "$p" --since-time="$START" --timestamps 2>/dev/null | awk -v e="$END" '$1<=e' \
   | grep -oE "Running: [0-9]+ reqs, Waiting: [0-9]+ reqs" \
   | awk -v p="$p" '{n++; r+=$2; if($2>mr)mr=$2; if($5>mw)mw=$5; w+=$5} END{printf "%-30s samples=%-3d mean_running=%.1f peak_running=%d mean_waiting=%.1f peak_waiting=%d\n", p, n, (n?r/n:0), mr, (n?w/n:0), mw}'
done | sort -t= -k4 -rn > "$OUT/engine.txt"
python3 - "$OUT" $STREAMS <<'PY'
import json,sys; O=sys.argv[1]
def g(r,k,s): v=r.get(k,{}); return round(v[s],1) if isinstance(v,dict) and s in v else None
for W in sys.argv[2:]:
    try: r=json.load(open(f"{O}/{W}/profile_export_aiperf.json")); r=r.get("records",r)
    except Exception as e: print(W,"no summary",e); continue
    print(f"{W}: requests={r.get('request_count',{}).get('avg')} errors={r.get('error_request_count',{}).get('avg',0)} "
          f"ttft_p50={g(r,'time_to_first_token','p50')} ttft_p99={g(r,'time_to_first_token','p99')} itl_p50={g(r,'inter_token_latency','p50')} "
          f"out_tok_s={g(r,'output_token_throughput','avg')} dur_s={round(r['benchmark_duration']['avg']/1000,1) if 'benchmark_duration' in r else None}")
PY
echo "--- picks"; cat "$OUT/picks.txt"; echo "--- engine"; cat "$OUT/engine.txt"
