#!/usr/bin/env bash
# Switch the EPP to arm a|c|w and restart the single replica.
#  a: Dynamo built-in selector ("default") with the upstream default weights credit 1.0 / prefill 1.0 / decode active request weight 0 / temperature 0
#  w: built-in selector with decode active request weight 4000 (the sweep's kv-w4000)
#  c: adaptive-imbalance policy from the ConfigMap, same baselines as arm a
# The example EPP binary links only the example catalog, so arms a/b use the built-in selector via the
# reserved override value "default" and the router's weight environment variables.
set -euo pipefail
ARM="${1:?usage: set-arm.sh a|c|w}"   # a Stock (upstream defaults, decode weight 0), c Adaptive, w Weight-4000
HERE="$(cd "$(dirname "$0")/.." && pwd)"
case "$ARM" in
  a) kubectl --request-timeout=30s -n bench set env deployment/dynamo-epp DYN_ROUTER_POLICY_CONFIG- DYN_ROUTER_WORKER_SELECTION_POLICY=default \
       DYN_ROUTER_KV_OVERLAP_SCORE_CREDIT=1.0 DYN_ROUTER_PREFILL_LOAD_SCALE=1.0 DYN_ROUTER_DECODE_ACTIVE_REQUEST_WEIGHT=0.0 DYN_ROUTER_TEMPERATURE=0.0 ;;
  w) kubectl --request-timeout=30s -n bench set env deployment/dynamo-epp DYN_ROUTER_POLICY_CONFIG- DYN_ROUTER_WORKER_SELECTION_POLICY=default \
       DYN_ROUTER_KV_OVERLAP_SCORE_CREDIT=1.0 DYN_ROUTER_PREFILL_LOAD_SCALE=1.0 DYN_ROUTER_DECODE_ACTIVE_REQUEST_WEIGHT=4000 DYN_ROUTER_TEMPERATURE=0.0 ;;
  c) kubectl --request-timeout=30s -n bench create configmap epp-policy --from-file=worker-selection.yaml="$HERE/arms/arm-c-adaptive.yaml" --dry-run=client -o yaml | kubectl apply -f -
     kubectl --request-timeout=30s -n bench set env deployment/dynamo-epp DYN_ROUTER_POLICY_CONFIG=/etc/dynamo/worker-selection.yaml DYN_ROUTER_WORKER_SELECTION_POLICY=arm-c \
       DYN_ROUTER_KV_OVERLAP_SCORE_CREDIT- DYN_ROUTER_PREFILL_LOAD_SCALE- DYN_ROUTER_DECODE_ACTIVE_REQUEST_WEIGHT- DYN_ROUTER_TEMPERATURE- ;;
  *) echo "unknown arm $ARM"; exit 1 ;;
esac
kubectl --request-timeout=30s -n bench rollout restart deployment/dynamo-epp
kubectl --request-timeout=30s -n bench rollout status deployment/dynamo-epp --timeout=240s
sleep 3
kubectl --request-timeout=30s -n bench logs deployment/dynamo-epp --tail=40 | grep -i -E "polic|worker|standalone|error|adaptive" | cut -c1-200 | head -12
