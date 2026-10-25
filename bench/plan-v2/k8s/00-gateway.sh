#!/usr/bin/env bash
# Gateway API + GIE CRDs + agentgateway with the inference extension, pinned to the versions Dynamo's own
# deploy/inference-gateway/scripts/install_gaie_crd_agentgateway.sh uses at commit 3763cee. Idempotent.
set -euo pipefail
AGW_NAMESPACE="${AGW_NAMESPACE:-agentgateway-system}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.5.1}"
IGW_RELEASE="${IGW_RELEASE:-v1.2.1}"
AGW_VERSION="${AGW_VERSION:-v1.0.0}"
step() { printf '\n== %s\n' "$*"; }
step "Gateway API $GATEWAY_API_VERSION CRDs"
kubectl apply --server-side --force-conflicts -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
step "GIE $IGW_RELEASE CRDs"
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${IGW_RELEASE}/manifests.yaml"
step "agentgateway $AGW_VERSION"
helm upgrade -i --create-namespace --namespace "$AGW_NAMESPACE" --version "$AGW_VERSION" agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds
helm upgrade -i --namespace "$AGW_NAMESPACE" --version "$AGW_VERSION" agentgateway oci://cr.agentgateway.dev/charts/agentgateway --set inferenceExtension.enabled=true --wait --timeout 5m
step "Gateway inference-gateway"
kubectl apply --server-side -n "$AGW_NAMESPACE" -f - <<'YAML'
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayParameters
metadata:
  name: inference-gateway-params
spec:
  deployment:
    spec:
      template:
        metadata:
          annotations:
            sidecar.istio.io/inject: "false"
YAML
kubectl apply -n "$AGW_NAMESPACE" -f - <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: inference-gateway
spec:
  gatewayClassName: agentgateway
  infrastructure:
    parametersRef:
      group: agentgateway.dev
      kind: AgentgatewayParameters
      name: inference-gateway-params
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
YAML
kubectl -n "$AGW_NAMESPACE" wait --for=condition=Programmed gateway/inference-gateway --timeout=300s || kubectl -n "$AGW_NAMESPACE" get gateway inference-gateway -o yaml | tail -30
