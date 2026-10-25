#!/usr/bin/env bash
# usage: run-step.sh <2|3|4|5|6|7> <results root>   Runs one step of Plan v2 section 7 unattended (cells in sequence, seed 31; step 7 = seed 32).
set -uo pipefail
STEP="$1"; R="$2"; HERE="$(cd "$(dirname "$0")" && pwd)"; mkdir -p "$R"
cell() { local wl=$1 conc=$2 arm=$3 seed=$4 tag=$5; echo "$(date +%T) === cell $tag arm=$arm wl=$wl conc=$conc seed=$seed"; WL=$wl CONC=$conc DURATION=600 bash "$HERE/run-cell.sh" "$arm" "$seed" "$R/$tag-$arm-s$seed" 2>&1 | cut -c1-200 | grep -E '===|CELL_DONE|FAILED|requests=|error' ; }
case "$STEP" in
  2) for a in w c; do cell HOT1 64 $a 31 g1-c64; done ;;
  3) for a in a w c; do cell EVEN 32 $a 31 g150-c32; done ;;
  4) bash "$HERE/../k8s/set-budget.sh" 8192 | tail -1; for a in a c; do cell HOT1 64 $a 31 g1-c64-b8192; done; for a in a c; do cell EVEN 32 $a 31 g150-c32-b8192; done; bash "$HERE/../k8s/set-budget.sh" 32768 | tail -1 ;;
  5) for a in a w c; do cell HOT1 16 $a 31 g1-c16; done; for a in a w c; do cell HOT1 32 $a 31 g1-c32; done; for a in a w c; do cell HOT4 64 $a 31 g4-c64; done; for a in a w c; do cell EVEN 64 $a 31 g150-c64; done ;;
  6) for a in a w c; do echo "$(date +%T) === burst arm=$a"; bash "$HERE/run-burst.sh" $a 31 "$R/burst-g150-c32-$a-s31" 2>&1 | cut -c1-200 | grep -E '===|DONE|FAILED|requests=|even |burst |error'; done ;;
  7) for a in a w c; do cell HOT1 64 $a 32 g1-c64; done; for a in a w c; do cell EVEN 32 $a 32 g150-c32; done ;;
  *) echo "unknown step $STEP"; exit 1 ;;
esac
echo "$(date +%T) STEP${STEP}_DONE"
