# Benchmark Plan v2 — scripts and manifests (A10G rig)

Scripts for the Benchmark Plan v2 of the adaptive-imbalance EPP policy (PR ai-dynamo/dynamo#17084).
Plan: Google Doc "Adaptive Routing for the Dynamo EPP — Benchmark Plan v2" (folder "v2 — Benchmark Plan v2 (A10G)").
Arms: `a` Stock (upstream default weights, decode active request weight 0), `w` Weight-4000 (decode weight 4000), `c` Adaptive (this PR's plugin).

## Order of operations

1. Create the env (env-in-a-click, Vanilla, `GPU.real[0].gpuProduct: A10-1`, 8 nodes); `kc add --cluster <env> --session`.
2. Patch the GPU operator ClusterPolicy: `driver.version 595.91.07`, `kernelModuleType open` (Ubuntu 24.04, kernel 7.0).
3. `k8s/00-gateway.sh` (Gateway API v1.5.1, GIE v1.2.1, agentgateway v1.0.0, Gateway `inference-gateway`).
4. Gateway fd limit: `kubectl -n agentgateway-system debug <gateway pod> --image=alpine:3.21 --target=agentgateway --profile=sysadmin -- sh -c 'apk add -q util-linux; prlimit --pid 1 --nofile=524288:524288'` (repeat after any gateway pod restart).
5. `kubectl apply -f k8s/10-workload.yaml` and `kubectl -n bench create configmap epp-policy --from-file=worker-selection.yaml=arms/arm-c-adaptive.yaml`.
6. One cell: `client/run-cell.sh <arm> <seed> <out dir>` = restart workers (clear prefix caches), `k8s/set-arm.sh <arm>`, start `client/scrape-metrics.sh`, warm one holder (`WARM1`), run `HOT1` at concurrency 64, `client/collect-v2.sh`.

## Files

| File | Purpose |
|---|---|
| `k8s/00-gateway.sh` | gateway stack, once per cluster |
| `k8s/10-workload.yaml` | 8 vLLM v0.32.0 workers (Qwen3-1.7B, `--max-num-seqs 12`, prefill budget 32768), standalone EPP, InferencePool, HTTPRoute |
| `k8s/set-arm.sh` | switch the EPP arm `a` / `w` / `c` and restart it |
| `arms/arm-c-adaptive.yaml` | Adaptive policy parameters (ConfigMap content) |
| `client/run-workload.sh` | start one aiperf Job: `HOT1`, `HOT4`, `EVEN`, `BURST`, `WARM1`, `WARM4` (sweep hot-prefix shape: 6000 prefix + 1200 unique, 1000 output) |
| `client/aiperf-job.yaml.tmpl` | aiperf 0.13.0 Job template |
| `client/scrape-metrics.sh` | per-worker `/metrics` every 5 s |
| `client/collect-v2.sh` | aiperf summaries, EPP picks per worker, per-worker running/waiting |
| `client/run-cell.sh` | one grid cell end to end |
