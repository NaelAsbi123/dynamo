#!/usr/bin/env bash
# usage: set-budget.sh 8192|32768   Set the prefill budget on both sides: vLLM --max-num-batched-tokens and the EPP's
# DYN_EPP_MAX_NUM_BATCHED_TOKENS (stage-1 eligibility). Restarts workers and EPP; wait for Ready before running a cell.
set -euo pipefail
B="${1:?usage: set-budget.sh 8192|32768}"
IDX=$(kubectl --request-timeout=30s -n bench get deployment vllm-worker -o jsonpath='{.spec.template.spec.containers[0].args}' | python3 -c "import json,sys; a=json.load(sys.stdin); print(a.index('--max-num-batched-tokens')+1)")
kubectl --request-timeout=30s -n bench patch deployment vllm-worker --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args/$IDX\",\"value\":\"$B\"}]"
kubectl --request-timeout=30s -n bench set env deployment/dynamo-epp DYN_EPP_MAX_NUM_BATCHED_TOKENS="$B"
kubectl --request-timeout=30s -n bench rollout status deployment/vllm-worker --timeout=900s
kubectl --request-timeout=30s -n bench rollout status deployment/dynamo-epp --timeout=240s
echo "budget $B on workers and EPP"
