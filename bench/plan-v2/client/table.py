#!/usr/bin/env python3
"""Render the results table (markdown) from summary.jsonl: one row per arm x workload."""
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
order = {"W1": 0, "W2": 1, "W2single": 2}
rows.sort(key=lambda r: (order.get(r["workload"], 9), r["arm"]))
print("| Workload | Arm | Requests | TTFT p50 ms | TTFT p99 ms | ITL p50 ms | req/s | Max worker share | Loop engaged / updates |")
print("|---|---|---|---|---|---|---|---|---|")
for r in rows:
    a = r.get("adaptive", {})
    print(f"| {r['workload']} | {r['arm'].upper()} | {int(r.get('request_count') or 0)} | {r['ttft_p50_ms']} | {r['ttft_p99_ms']} | {r['itl_p50_ms']} | {r['req_per_s']} | {r['max_share']} | {a.get('engaged',0)} / {a.get('updates',0)} |")
