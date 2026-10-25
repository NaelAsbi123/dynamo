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
6. Prefill budget: `k8s/set-budget.sh 32768` (stage 2 decides) or `k8s/set-budget.sh 8192` (the sweep's value, Dynamo as deployed); it patches the workers and the EPP together.
7. One grid cell: `WL=HOT1 CONC=64 client/run-cell.sh <arm> <seed> <out dir>` = restart workers (clear prefix caches), `k8s/set-arm.sh <arm>`, start `client/scrape-metrics.sh`, warm one holder per hot prefix (`WARM1` / `WARM4`, skipped for `EVEN`), run `WL` at `CONC` for 600 s dispatch + 900 s drain with 64 aiperf warm-up requests, `client/collect-v2.sh`.
8. Burst cell: `client/run-burst.sh <arm> <seed> <out dir>` = `EVEN` at 32 for 1200 s, `BURST` (200 concurrent, 180 s) started 600 s in, both streams collected, `client/burst-windows.py` prints pre / burst / post TTFT and writes 10 s buckets.

vLLM flags follow the sweep where the hardware allows: `--gpu-memory-utilization 0.90 --enable-prefix-caching --enable-chunked-prefill --enforce-eager`, `--max-num-seqs 12` (A10G slot cap), block size 16, `--max-model-len 16384`.

## Files

| File | Purpose |
|---|---|
| `k8s/00-gateway.sh` | gateway stack, once per cluster |
| `k8s/10-workload.yaml` | 8 vLLM v0.32.0 workers (Qwen3-1.7B, `--max-num-seqs 12`, prefill budget 32768), standalone EPP, InferencePool, HTTPRoute |
| `k8s/set-arm.sh` | switch the EPP arm `a` / `w` / `c` and restart it |
| `k8s/set-budget.sh` | set the prefill budget (8192 or 32768) on workers and EPP |
| `arms/arm-c-adaptive.yaml` | Adaptive policy parameters (ConfigMap content) |
| `client/run-workload.sh` | start one aiperf Job: `HOT1`, `HOT4`, `EVEN`, `BURST`, `WARM1`, `WARM4` (sweep hot-prefix shape: 6000 prefix + 1200 unique, 1000 output); duration mode by default, `REQUESTS=<n>` for a fixed count |
| `client/aiperf-job.yaml.tmpl` | aiperf 0.13.0 Job template |
| `client/scrape-metrics.sh` | per-worker `/metrics` (running, waiting, KV usage, prefix hits/queries, preemptions) and `nvidia-smi` (GPU util, memory) every 5 s |
| `client/collect-v2.sh` | aiperf summaries per stream (`STREAMS`), EPP picks per worker, per-worker running/waiting, scrape summary (peak running/waiting/KV, GPU util, prefix hit rate) |
| `client/run-cell.sh` | one grid cell end to end (`WL`, `CONC`, `DURATION`) |
| `client/run-burst.sh` | the burst cell end to end |
| `client/burst-windows.py` | pre / burst / post windows and 10 s buckets |
