#!/usr/bin/env bash
# Second-environment driver (2026-10-26): burst row and second-seed cells, run in parallel with phase 2 on the first environment. Waits for the cluster API before each cell, retries each cell up to 3 times.
set -uo pipefail
R="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"; mkdir -p "$R"
wait_cluster() { local i; for i in $(seq 1 720); do kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1 && return 0; [ $((i % 6)) -eq 1 ] && echo "$(date +%T) cluster unreachable, waiting"; sleep 10; done; return 1; }
cell() { local wl=$1 lvl=$2 arm=$3 seed=$4 tag=$5 try out; out="$R/$tag-$arm-s$seed"
  if ls "$out"/*/profile_export_aiperf.json >/dev/null 2>&1 && [ -s "$out/end.txt" ]; then echo "$(date +%T) === cell $tag arm=$arm already complete, skipping"; return 0; fi
  for try in 1 2 3; do wait_cluster || return 1; echo "$(date +%T) === cell $tag arm=$arm wl=$wl level=$lvl seed=$seed (try $try)"
    case "$wl" in HOTR|HOTR4) WL=$wl RATE=$lvl DURATION=600 bash "$HERE/run-cell.sh" "$arm" "$seed" "$out";; *) WL=$wl CONC=$lvl DURATION=600 bash "$HERE/run-cell.sh" "$arm" "$seed" "$out";; esac 2>&1 | cut -c1-200 | grep -E 'CELL_DONE|FAILED|requests=|error|Unable|timed out'
    if ls "$out"/*/profile_export_aiperf.json >/dev/null 2>&1; then return 0; fi; echo "$(date +%T) cell $tag $arm produced no results, retrying"; rm -rf "$out"; sleep 60
  done; echo "$(date +%T) cell $tag $arm FAILED after 3 tries"; return 1; }
burst() { local arm=$1 try out; out="$R/burst-g150-c32-$arm-s31"
  if ls "$out"/burst/profile_export_aiperf.json >/dev/null 2>&1; then echo "$(date +%T) === burst arm=$arm already complete, skipping"; return 0; fi
  for try in 1 2 3; do wait_cluster || return 1; echo "$(date +%T) === burst arm=$arm (try $try)"
    bash "$HERE/run-burst.sh" $arm 31 "$out" 2>&1 | cut -c1-200 | grep -E 'DONE|FAILED|requests=|even |burst |error|Unable|timed out'
    if ls "$out"/burst/profile_export_aiperf.json >/dev/null 2>&1; then return 0; fi; rm -rf "$out"; sleep 60
  done; return 1; }
budget() { wait_cluster && bash "$HERE/../k8s/set-budget.sh" "$1" | tail -1; }
echo "$(date +%T) ##### ENV2 burst"; for a in a w c; do burst $a; done
echo "$(date +%T) ##### ENV2 second seed: G=1 at 1.0 req/s and G=150 at 32"; for a in a w c; do cell HOTR 1.0 $a 32 g1-r1; done; for a in a w c; do cell EVEN 32 $a 32 g150-c32; done
echo "$(date +%T) ENV2_ALL_DONE"
