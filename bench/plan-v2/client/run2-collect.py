#!/usr/bin/env python3
"""Collect run-2 W4 results for arms present under results/run2-arm-<x>-w4 into results/run2-results.json."""
import json, os, re, sys, collections
from datetime import datetime
B = sys.argv[1]
def pct(v, p): return v[min(len(v) - 1, int(round(p / 100 * (len(v) - 1))))]
def ttfts(p):
    out = []
    for l in open(p):
        if l.strip():
            m = json.loads(l).get("metrics", {}); v = m.get("time_to_first_token")
            if isinstance(v, dict): v = v.get("value")
            if isinstance(v, (int, float)): out.append(v)
    return sorted(out)
def agg(p):
    r = json.load(open(p)); g = lambda k, s: round(r[k][s], 1) if k in r and s in r[k] else None
    return {"requests": r["request_count"]["avg"], "errors": r.get("error_request_count", {}).get("avg", 0),
            "ttft_p50": g("time_to_first_token", "p50"), "ttft_p99": g("time_to_first_token", "p99"),
            "itl_p50": g("inter_token_latency", "p50"), "itl_p99": g("inter_token_latency", "p99"),
            "req_per_s": g("request_throughput", "avg"), "out_tok_per_s": g("output_token_throughput", "avg"),
            "duration_s": round(r["benchmark_duration"]["avg"] / 1000, 1) if "benchmark_duration" in r else None}
res = {}
for arm in ("a", "b", "c"):
    d = f"{B}/results/run2-arm-{arm}-w4"
    if not os.path.exists(f"{d}/end.txt"): continue
    row = {"streams": {}}
    for w in ("w4hot", "w4bg"):
        row["streams"][w] = agg(f"{d}/{w}/profile_export_aiperf.json")
        v = ttfts(f"{d}/{w}/profile_export.jsonl")
        row["streams"][w]["ttft_pcts"] = {str(p): round(pct(v, p)) for p in (50, 90, 95, 99)} | {"max": round(v[-1])}
    picks = []; events = []; updates = []
    for line in open(f"{d}/epp.log", errors="replace"):
        m = re.search(r"^(\S+Z).*Selected worker .*?worker_id=(\d+)", line)
        if m: picks.append((datetime.fromisoformat(m.group(1).replace("Z", "+00:00")).timestamp(), m.group(2)))
        m = re.search(r"^(\S+Z).*adaptive-imbalance: (engaged|disengaged) imbalance=([\d.]+)", line)
        if m: events.append((m.group(1), m.group(2), float(m.group(3))))
        m = re.search(r"weights updated imbalance=([\d.]+) split=([\d.]+) overlap_score_credit=([\d.]+) prefill_load_scale=([\d.]+) decode_active_request_weight=([\d.]+)", line)
        if m: updates.append([float(x) for x in m.groups()])
    t0 = picks[0][0]; win = collections.defaultdict(collections.Counter)
    for t, w in picks: win[int((t - t0) // 10)][w] += 1
    shares = [(k * 10, sum(c.values()), round(c.most_common(1)[0][1] / sum(c.values()), 2)) for k, c in sorted(win.items()) if sum(c.values()) >= 8]
    tot = collections.Counter(w for _, w in picks)
    row["picks_total"] = len(picks); row["picks_per_worker_sorted"] = sorted(tot.values(), reverse=True)
    row["worst_window_share"] = max(s for _, _, s in shares); row["window_shares"] = shares
    row["first_pick"] = picks[0][0]; row["last_pick"] = picks[-1][0]
    eng = []; cur = None
    for ts, kind, imb in events:
        t = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
        if kind == "engaged": cur = [round(t - t0), None, imb, None]
        elif cur: cur[1] = round(t - t0); cur[3] = imb; eng.append(cur); cur = None
    if cur: cur[1] = round(picks[-1][0] - t0); eng.append(cur)
    row["engagements"] = [{"from_s": a, "to_s": b, "imbalance_in": i, "imbalance_out": o} for a, b, i, o in eng]
    row["engaged_seconds"] = sum(b - a for a, b, _, _ in eng); row["traffic_seconds"] = round(picks[-1][0] - t0)
    row["updates"] = len(updates)
    if updates:
        col = lambda i: sorted(u[i] for u in updates)
        row["update_stats"] = {k: {"min": round(col(i)[0], 3), "median": round(col(i)[len(updates) // 2], 3), "max": round(col(i)[-1], 3)} for i, k in enumerate(("imbalance", "split", "overlap_score_credit", "prefill_load_scale", "decode_active_request_weight"))}
    res[arm] = row
json.dump(res, open(f"{B}/results/run2-results.json", "w"), indent=1)
for a, r in res.items():
    print(a, {w: (s["ttft_p50"], s["ttft_p99"], s["req_per_s"]) for w, s in r["streams"].items()}, "worst_share", r["worst_window_share"], "engaged", r["engaged_seconds"], "/", r["traffic_seconds"], "s", "updates", r["updates"])
