#!/usr/bin/env python3
"""Summarize one run: aiperf profile_export_aiperf.json + EPP log window -> one JSON line and a readable table.
usage: summarize.py <arm> <workload> <aiperf_json> <epp_log> [out.json]"""
import json, re, sys, collections
arm, wl, ajson, elog = sys.argv[1:5]
out = sys.argv[5] if len(sys.argv) > 5 else None
d = json.load(open(ajson))
recs = d.get("records", d)
def pick(name):
    for k, v in recs.items():
        if k == name and isinstance(v, dict):
            return v
    return {}
def stat(name, key):
    v = pick(name).get(key)
    return round(v, 2) if isinstance(v, (int, float)) else None
summary = {
    "arm": arm, "workload": wl,
    "ttft_p50_ms": stat("time_to_first_token", "p50"), "ttft_p99_ms": stat("time_to_first_token", "p99"), "ttft_avg_ms": stat("time_to_first_token", "avg"),
    "itl_p50_ms": stat("inter_token_latency", "p50"), "itl_p99_ms": stat("inter_token_latency", "p99"),
    "req_latency_p99_ms": stat("request_latency", "p99"),
    "req_per_s": stat("request_throughput", "avg"), "out_tok_per_s": stat("output_token_throughput", "avg"),
    "request_count": stat("request_count", "avg") or recs.get("request_count"),
}
picks = collections.Counter(); logits = []
for line in open(elog, errors="replace"):
    m = re.search(r"Selected worker .*?worker_id=(\d+)", line)
    if m:
        picks[m.group(1)] += 1
        lg = re.search(r"logit=([-\d.eE]+)", line)
        if lg: logits.append(float(lg.group(1)))
adaptive = {"engaged": 0, "disengaged": 0, "updates": 0}
for line in open(elog, errors="replace"):
    if "adaptive-imbalance: engaged" in line: adaptive["engaged"] += 1
    if "adaptive-imbalance: disengaged" in line: adaptive["disengaged"] += 1
    if "weights updated" in line: adaptive["updates"] += 1
n = sum(picks.values()) or 1
summary["selections"] = n
summary["picks_per_worker"] = dict(sorted(picks.items(), key=lambda kv: -kv[1]))
summary["max_share"] = round(max(picks.values()) / n, 3) if picks else None
summary["adaptive"] = adaptive
print(json.dumps(summary, indent=1))
if out:
    with open(out, "a") as f: f.write(json.dumps(summary) + "\n")
