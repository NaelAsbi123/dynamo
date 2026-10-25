#!/usr/bin/env bash
# usage: run-workload.sh <arm a|b|c|w> <W1|W2|W2single|W3|W4hot|W4bg|W5hot|W5bg|W6warm|W7hot|W7bg> <seed>   400 requests each.
# W4 = start W4hot and W4bg at the same time (hot tenant + background traffic).
set -euo pipefail
ARM="${1:?arm}"; W="${2:?workload}"; SEED="${3:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
case "$W" in
  W1) PR=0.1; CONC=20; NP=50; ISL=12000 ;;
  W2) PR=0.9; CONC=24; NP=24; ISL=12000 ;;  # 24 distinct 10.8k-token prefixes: working set (260k tokens) is far above one worker cache (29k), so each prefix has one holder
  W2single) PR=0.9; CONC=24; NP=1; ISL=12000 ;;  # original single shared prefix; every worker ends up caching it
  W3) PR=0.9; CONC=32; NP=24; ISL=4000 ;;  # short prompts: ~7 concurrent per worker fit in KV, so the admission cap is not binding and a hotspot can form
  W4hot) PR=0.9; CONC=24; NP=2; ISL=12000 ;;   # hot tenant: 2 prefixes -> 2 holder workers get 24 in-flight requests while the pool could spread them
  W4bg)  PR=0.1; CONC=16; NP=50; ISL=12000 ;;  # background traffic over all workers, run concurrently with W4hot
  W5hot) PR=0.9; CONC=32; NP=2; ISL=3000 ;;
  W5bg)  PR=0.1; CONC=16; NP=50; ISL=3000 ;;
  W6warm) PR=0.9; CONC=1; NP=2; ISL=3000; REQUESTS=2 ;;
  W7hot) PR=0.9; CONC=8; NP=2; ISL=3000; OSL=1500 ;;
  W7bg)  PR=0.1; CONC=8; NP=50; ISL=3000; OSL=200 ;;
  HOT1) PR=0.8333; CONC=${CONC:-64}; NP=1; ISL=7200; OSL=1000 ;;     # sweep hot-prefix G=1: 6000 prefix + 1200 unique, 1000 out
  HOT4) PR=0.8333; CONC=${CONC:-64}; NP=4; ISL=7200; OSL=1000 ;;     # sweep hot-prefix G=4
  EVEN) PR=0.8333; CONC=${CONC:-32}; NP=150; ISL=7200; OSL=1000 ;;   # sweep hot-prefix G=150 = even load
  WARM1) PR=0.8333; CONC=1; NP=1; ISL=7200; OSL=16; REQUESTS=1 ;;    # one holder for the single hot prefix
  WARM4) PR=0.8333; CONC=1; NP=4; ISL=7200; OSL=16; REQUESTS=4 ;;    # one holder per hot prefix
  BURST) PR=0.8333; CONC=200; NP=1; ISL=7200; OSL=1000; REQUESTS=${REQUESTS:-600} ;;  # sweep burst: 200 concurrent on one prefix, run on top of EVEN
  *) echo "unknown workload $W"; exit 1 ;;
esac
GW="${GATEWAY:-inference-gateway.agentgateway-system.svc.cluster.local:80}"
[ -n "$GW" ] || { echo "gateway address empty"; exit 1; }
WL=$(echo "$W" | tr 'A-Z' 'a-z')
sed -e "s#__ARM__#$ARM#g" -e "s#__WORKLOAD__#$WL#g" -e "s#__PREFIX_RATIO__#$PR#g" -e "s#__CONCURRENCY__#$CONC#g" \
    -e "s#__REQUESTS__#${REQUESTS:-400}#g" -e "s#__OSL__#${OSL:-200}#g" -e "s#__SEED__#$SEED#g" -e "s#__NUM_PREFIX__#$NP#g" -e "s#__ISL__#$ISL#g" -e "s#__MODEL__#${MODEL:-Qwen/Qwen3-1.7B}#g" -e "s#__GATEWAY__#$GW#g" \
    "$HERE/aiperf-job.yaml.tmpl" | kubectl apply -f -
echo "started job aiperf-$ARM-$WL-s$SEED ; follow: kubectl -n bench logs -f job/aiperf-$ARM-$WL-s$SEED"
