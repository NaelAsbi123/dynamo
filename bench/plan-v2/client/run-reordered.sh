#!/usr/bin/env bash
# Reordered unattended run (2026-10-25 16:00): hotspot rows first (G=1 at 16 and 32), then the rest of Plan v2 section 7.
# Already done before this script: the whole g1-c64 row (Stock, Weight-4000, Adaptive) = steps 1 and 2.
# Every cell waits for the cluster API to answer and retries up to 3 times (laptop sleep / VPN drops break kubectl, not the in-cluster jobs).
set -uo pipefail
R="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"; mkdir -p "$R"
wait_cluster() { local i; for i in $(seq 1 720); do kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1 && return 0; [ $((i % 6)) -eq 1 ] && echo "$(date +%T) cluster unreachable, waiting (laptop asleep or VPN down?)"; sleep 10; done; echo "$(date +%T) cluster unreachable for 2 h, giving up"; return 1; }
cell() { local wl=$1 conc=$2 arm=$3 seed=$4 tag=$5 try out; out="$R/$tag-$arm-s$seed"
  for try in 1 2 3; do wait_cluster || return 1
    echo "$(date +%T) === cell $tag arm=$arm wl=$wl conc=$conc seed=$seed (try $try)"
    WL=$wl CONC=$conc DURATION=600 bash "$HERE/run-cell.sh" "$arm" "$seed" "$out" 2>&1 | cut -c1-200 | grep -E 'CELL_DONE|FAILED|requests=|error|Unable|timed out'
    if ls "$out"/*/profile_export_aiperf.json >/dev/null 2>&1 && grep -q . "$out/end.txt" 2>/dev/null; then return 0; fi
    echo "$(date +%T) cell $tag $arm did not produce results, retrying"; rm -rf "$out"; sleep 60
  done; echo "$(date +%T) cell $tag $arm FAILED after 3 tries"; return 1; }
burst() { local arm=$1 try out; out="$R/burst-g150-c32-$arm-s31"
  for try in 1 2 3; do wait_cluster || return 1; echo "$(date +%T) === burst arm=$arm (try $try)"
    bash "$HERE/run-burst.sh" $arm 31 "$out" 2>&1 | cut -c1-200 | grep -E 'DONE|FAILED|requests=|even |burst |error|Unable|timed out'
    if ls "$out"/burst/profile_export_aiperf.json >/dev/null 2>&1; then return 0; fi; echo "$(date +%T) burst $arm did not produce results, retrying"; rm -rf "$out"; sleep 60
  done; return 1; }
budget() { wait_cluster && bash "$HERE/../k8s/set-budget.sh" "$1" | tail -1; }
echo "$(date +%T) ##### STEP 5a hotspot rows"; for a in a w c; do cell HOT1 16 $a 31 g1-c16; done; for a in a w c; do cell HOT1 32 $a 31 g1-c32; done
echo "$(date +%T) ##### STEP 3"; for a in a w c; do cell EVEN 32 $a 31 g150-c32; done
echo "$(date +%T) ##### STEP 4"; budget 8192; for a in a c; do cell HOT1 16 $a 31 g1-c16-b8192; done; for a in a c; do cell EVEN 32 $a 31 g150-c32-b8192; done; budget 32768
echo "$(date +%T) ##### STEP 5b"; for a in a w c; do cell HOT4 64 $a 31 g4-c64; done; for a in a w c; do cell EVEN 64 $a 31 g150-c64; done
echo "$(date +%T) ##### STEP 6"; for a in a w c; do burst $a; done
echo "$(date +%T) ##### STEP 7 second seed"; for a in a w c; do cell HOT1 16 $a 32 g1-c16; done; for a in a w c; do cell EVEN 32 $a 32 g150-c32; done
echo "$(date +%T) ALL_STEPS_DONE"
