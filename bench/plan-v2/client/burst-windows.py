#!/usr/bin/env python3
"""usage: burst-windows.py <out dir>  Pre / burst / post windows of the EVEN stream, split at the burst client's first and last request, plus 10 s buckets."""
import json, sys, statistics as st
O = sys.argv[1]
def recs(p):
    out = []
    for l in open(p):
        if not l.strip(): continue
        r = json.loads(l); m = r.get("metrics", {}); t = r.get("timestamp_ns") or r.get("start_time_ns") or r.get("request_start_ns")
        v = m.get("time_to_first_token"); v = v.get("value") if isinstance(v, dict) else v
        if t and isinstance(v, (int, float)): out.append((t / 1e9, v))
    return sorted(out)
even = recs(f"{O}/even/profile_export.jsonl"); burst = recs(f"{O}/burst/profile_export.jsonl")
if not burst: print("no burst records"); sys.exit(0)
b0, b1 = burst[0][0], burst[-1][0]
def pct(v, p): v = sorted(v); return v[min(len(v) - 1, int(round(p / 100 * (len(v) - 1))))] if v else None
for name, sel in (("pre", lambda t: t < b0), ("burst", lambda t: b0 <= t <= b1), ("post", lambda t: t > b1)):
    v = [x for t, x in even if sel(t)]
    print(f"even {name:5s} n={len(v):4d} ttft_p50={pct(v,50)} ttft_p99={pct(v,99)}")
v = [x for _, x in burst]; print(f"burst       n={len(v):4d} ttft_p50={pct(v,50)} ttft_p99={pct(v,99)}")
t0 = min(even[0][0], b0); buckets = {}
for t, x in even + burst: buckets.setdefault(int((t - t0) // 10), []).append(x)
with open(f"{O}/buckets-10s.txt", "w") as f:
    for k in sorted(buckets): f.write(f"{k*10:5d}s n={len(buckets[k]):4d} ttft_p50={pct(buckets[k],50)}\n")
print(f"10 s buckets written to {O}/buckets-10s.txt")
