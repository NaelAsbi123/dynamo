#!/usr/bin/env bash
# Live progress of the unattended Plan v2 run: cells done / 31, current step and cell. Refreshes every 20 s.
T="$1"; TOTAL=31; DONE_BEFORE="${2:-0}"   # cells completed by an earlier driver
while true; do
  done_cells=$(grep -cE 'CELL_DONE' "$T" 2>/dev/null); done_cells=$(( ${done_cells:-0} + DONE_BEFORE ))
  step=$(grep -oE '##### STEP [0-9]+' "$T" 2>/dev/null | tail -1 | awk '{print $3}')
  cell=$(grep -oE '=== (cell|burst) .*' "$T" 2>/dev/null | tail -1 | cut -c5-80)
  phase=$(grep -oE '\[[acw]\] [A-Za-z0-9 ]+(started|restarting workers to clear prefix caches|setting arm|EPP sees [0-9]+ KV listeners)' "$T" 2>/dev/null | tail -1)
  smoke=$(grep -oE 'SMOKE_OK|SMOKE_FAILED_AGAIN' "$T" 2>/dev/null | tail -1)
  fail=$(grep -cE 'FAILED|ABORT' "$T" 2>/dev/null)
  pct=$(( done_cells * 100 / TOTAL )); filled=$(( done_cells * 30 / TOTAL ))
  bar=$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' $((30 - filled)) '' | tr ' ' '.')
  clear
  echo "Benchmark Plan v2  (A10G, nasbi-run-51708-a10)        $(date +%H:%M:%S)"
  echo
  echo "  [$bar] $done_cells/$TOTAL cells  ($pct%)"
  echo
  [ -n "$smoke" ] && echo "  smoke test : $smoke"
  echo "  step       : ${step:-starting}"
  echo "  cell       : ${cell:-}"
  echo "  phase      : ${phase:-}"
  [ "${fail:-0}" -gt 0 ] && echo "  !! failures in log: $fail  (see $T)"
  grep -q ALL_STEPS_DONE "$T" 2>/dev/null && { echo; echo "  ALL STEPS DONE"; }
  echo
  echo "  last lines:"; grep -E 'requests=|CELL_DONE|STEP[0-9]_DONE|STEP1_DONE' "$T" 2>/dev/null | tail -5 | cut -c1-110 | sed 's/^/    /'
  sleep 20
done
