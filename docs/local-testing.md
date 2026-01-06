# Aurora Gateway Helm Harness Playbook

## Prerequisites

1. Helm v4.0+ (already checked into this workspace via `helm version`).
2. Access to a Kubernetes cluster. For local testing create a kind cluster:
   ```bash
   kind create cluster --name aurora --config - <<'EOF'
   kind: Cluster
   apiVersion: kind.x-k8s.io/v1alpha4
   nodes:
     - role: control-plane
     - role: worker
   EOF
   ```
3. Docker registry credentials stored in a secret named `ghcr-creds` if you plan to pull private images.

## Configuration Workflow

1. Open `configuration.yaml` and adjust the toggles for your service. The current file is pre-populated for the `aurora-gateway` service with:
   - StatefulSet workload + PVC persistence.
   - LoadBalancer service, ingress + cert-manager certificate.
   - HPA, PDB, ConfigMap, Secret, Jobs, CronJob, ServiceMonitor, NetworkPolicy.
   - Optional frontend Deployment/Service/Ingress via the `frontend.*` section.
2. Keep `serviceName`, `pipeline.serviceVersion`, and `pipeline.chartName` in sync; the chart consumes those fields for packaging and harness defaults.

## Building the Chart

1. Ensure dependencies are wired:
   ```bash
   helm dependency update service-chart
   ```
   This packages the local `platform` library into `service-chart/charts/platform-1.0.0.tgz`.
2. (Optional) Inspect the rendered manifests quickly:
   ```bash
   helm template aurora-gateway service-chart -f configuration.yaml --debug | less
   ```

## Automated Harness

1. Run the scripted harness anytime you tweak values or templates:
   ```bash
   ./scripts/test-harness.sh
   ```
   Environment overrides:
   - `CONFIG_FILE` – alternate values file (defaults to `configuration.yaml`).
   - `CHART_DIR` – alternate chart directory (defaults to `service-chart`).
   - `RELEASE_NAME` / `NAMESPACE` – override autodetected release/namespace.
   - `OUTPUT_DIR` – where `rendered.yaml` and the dry-run log are written (defaults to `artifacts/`).
2. The harness executes:
   1. `helm dependency update` – guarantees the platform library is synced.
   2. `helm lint` – structural validation against Helm best practices.
   3. `helm template` – renders manifests into `artifacts/rendered.yaml` for diffing.
   4. `helm install ... --dry-run --debug` – full install simulation with release + namespace creation.

## Deploying to Local Kubernetes

1. With a cluster (e.g., kind) running, perform an actual install:
   ```bash
   helm install aurora-gateway service-chart \
     -n aurora-gateway-ns --create-namespace \
     -f configuration.yaml
   ```
2. Verify objects:
   ```bash
   kubectl get all -n aurora-gateway-ns
   kubectl get ingress -n aurora-gateway-ns
   kubectl describe pvc -n aurora-gateway-ns
   ```
3. Tail the StatefulSet pods to confirm readiness:
   ```bash
   kubectl logs sts/aurora-gateway -n aurora-gateway-ns -c aurora-gateway --follow
   ```
4. When finished, remove the release and cluster:
   ```bash
   helm uninstall aurora-gateway -n aurora-gateway-ns
   kind delete cluster --name aurora
   ```

## Troubleshooting Tips

| Symptom | Action |
| --- | --- |
| `helm dependency update` cannot find `platform` | Ensure the repo is cloned with `platform-library/` adjacent to `service-chart/` and rerun the command. |
| Pods stuck Pending due to PVC | Confirm the `fast-ssd` storage class exists or override `global.storageClass` to one provided by your cluster. |
| Images fail to pull | Create the `ghcr-creds` secret in the release namespace or point `global.imagePullSecrets` to an existing secret. |
| cert-manager complaints | Disable `certificate.enabled` and `ingress.tls` or install cert-manager CRDs locally. |
| Frontend disabled | Set `frontend.enabled: true` and provide `frontend.image.repository`/`tag`. |

Repeat the harness after each change to maintain parity with the configuration-driven chart generation.
