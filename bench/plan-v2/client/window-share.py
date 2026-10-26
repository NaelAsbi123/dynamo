#!/usr/bin/env python3
"""Hotspot view of one run: per 10 s window, how many picks went to the busiest worker.
usage: window-share.py <epp_log (ANSI stripped)> [window_s=10]"""
import re, sys, collections
from datetime import datetime
log = sys.argv[1]; win = float(sys.argv[2]) if len(sys.argv) > 2 else 10.0
picks = []
for line in open(log, errors="replace"):
    m = re.search(r"^(\S+Z).*Selected worker .*?worker_id=(\d+)", line)
    if m:
        picks.append((datetime.fromisoformat(m.group(1).replace("Z", "+00:00")).timestamp(), m.group(2)))
if not picks:
    print("no selections"); sys.exit(0)
t0 = picks[0][0]
windows = collections.defaultdict(collections.Counter)
for t, w in picks:
    windows[int((t - t0) // win)][w] += 1
print(f"{'window':>7} {'picks':>5} {'max share':>9}  busiest worker")
worst = 0.0
for k in sorted(windows):
    c = windows[k]; n = sum(c.values()); w, m = c.most_common(1)[0]
    share = m / n; worst = max(worst, share) if n >= 8 else worst
    print(f"{k*win:>6.0f}s {n:>5} {share:>9.2f}  {w}")
print(f"worst window share (windows with >=8 picks): {worst:.2f} ; total picks {len(picks)} ; workers {len({w for _, w in picks})}")
