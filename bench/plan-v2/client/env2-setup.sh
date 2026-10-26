#!/usr/bin/env bash
# One-shot setup of a second A10G environment for Plan v2 and start of its driver (burst + second seed).
# usage: env2-setup.sh <env name> <bench dir> <results dir>
set -uo pipefail
NAME="$1"; B="$2"; R="$3"; export KUBECONFIG="/Users/nasbi/.kube/config.$NAME"
k() { kubectl --request-timeout=30s "$@"; }
echo "$(date +%T) env2 setup on $NAME"
k get --raw /readyz >/dev/null 2>&1 || { echo "API not reachable"; exit 1; }
echo "$(date +%T) gateway stack"; bash "$B/k8s/00-gateway.sh" 2>&1 | grep -E '^==|created|condition met|Error|error' | head -12
GW=$(k -n agentgateway-system get pods --no-headers | awk '/^inference-gateway/{print $1}' | head -1)
k -n agentgateway-system debug "$GW" -c dbg1 --image=alpine:3.21 --target=agentgateway --profile=sysadmin -- sh -c 'apk add -q util-linux; prlimit --pid 1 --nofile=524288:524288; grep "open files" /proc/1/limits' 2>&1 | grep -E 'open files|rror' | head -2
echo "$(date +%T) bench namespace"; k apply -f "$B/k8s/10-workload.yaml" 2>&1 | grep -vE 'unchanged' | tail -3
k -n bench create configmap epp-policy --from-file=worker-selection.yaml="$B/arms/arm-c-adaptive.yaml" --dry-run=client -o yaml | k apply -f - >/dev/null
k -n bench run curl-client --image=curlimages/curl:8.11.1 --restart=Never --command -- sleep 86400 >/dev/null 2>&1 || true
for i in $(seq 1 45); do w=$(k -n bench get deploy vllm-worker -o jsonpath='{.status.readyReplicas}' 2>/dev/null); echo "$(date +%T) workers ready=${w:-0}/8"; [ "${w:-0}" = "8" ] && break; sleep 60; done
bash "$B/k8s/set-arm.sh" a 2>&1 | grep -oE 'policy_class[^ ]*=[^ ]*"[a-z-]+"' | head -1
k -n bench exec curl-client -- curl -s -m 60 -o /dev/null -w 'gateway smoke: HTTP %{http_code} in %{time_total}s\n' http://inference-gateway.agentgateway-system.svc.cluster.local:80/v1/chat/completions -H 'content-type: application/json' -d '{"model":"Qwen/Qwen3-1.7B","messages":[{"role":"user","content":"hi"}],"max_tokens":8}' 2>&1 | tail -1
echo "$(date +%T) ENV2_SETUP_DONE"
