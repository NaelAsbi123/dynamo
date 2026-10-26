#!/usr/bin/env bash
# Live progress of the unattended Plan v2 run: cells done / 31, current step and cell. Refreshes every 20 s.
T="$1"; RES="${2:-}"; TOTAL="${3:-31}"   # RES = results root; cells are counted from result directories that hold a summary
while true; do
  done_cells=0; [ -n "$RES" ] && done_cells=$(ls -d "$RES"/*/ 2>/dev/null | while read d; do [ -f "$d/end.txt" ] && ls "$d"/*/profile_export_aiperf.json >/dev/null 2>&1 && echo x; done | wc -l | tr -d ' ')
  step=$(grep -oE '##### (STEP|PHASE) [0-9a-z]+[^(]*' "$T" 2>/dev/null | tail -1 | sed 's/##### //' | cut -c1-60)
  cell=$(grep -oE '=== (cell|burst) .*' "$T" 2>/dev/null | tail -1 | cut -c5-80)
  phase=$(grep -oE '\[[acw]\] [A-Za-z0-9 ]+(started|restarting workers to clear prefix caches|setting arm|EPP sees [0-9]+ KV listeners)' "$T" 2>/dev/null | tail -1)
  smoke=$(grep -oE 'SMOKE_OK|SMOKE_FAILED_AGAIN' "$T" 2>/dev/null | tail -1)
  fail=$(grep -cE 'retrying|FAILED after' "$T" 2>/dev/null)
  pct=$(( done_cells * 100 / TOTAL )); filled=$(( done_cells * 30 / TOTAL ))
  bar=$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' $((30 - filled)) '' | tr ' ' '.')
  clear
  echo "Benchmark Plan v2  ${4:-env 1 nasbi-run-51708-a10}        $(date +%H:%M:%S)"
  echo
  echo "  [$bar] $done_cells/$TOTAL cells  ($pct%)"
  echo
  [ -n "$smoke" ] && echo "  smoke test : $smoke"
  echo "  step       : ${step:-starting}"
  echo "  cell       : ${cell:-}"
  echo "  phase      : ${phase:-}"
  [ "${fail:-0}" -gt 0 ] && echo "  retries so far: $fail"
  grep -q ALL_STEPS_DONE "$T" 2>/dev/null && { echo; echo "  ALL STEPS DONE"; }
  echo
  echo "  completed cells:"; [ -n "$RES" ] && ls -d "$RES"/*/ 2>/dev/null | while read d; do [ -f "$d/end.txt" ] && ls "$d"/*/profile_export_aiperf.json >/dev/null 2>&1 && basename "$d"; done | sed 's/^/    /' | tail -12
  sleep 20
done
