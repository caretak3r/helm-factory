# Helm Chart Generation & Testing Guide

This guide describes how to use the test harness to generate, test, and deploy a Helm chart based on the `platform-library` and a service `configuration.yaml`.

## Prerequisites

- **Helm**: v3.0+
- **yq**: v4.0+ (YAML processor)
- **Kubernetes Cluster** (Optional, for deployment): Minikube, Kind, or Docker Desktop.

## Directory Structure

- `platform-library/`: The source library chart containing templates and defaults.
- `test-harness/`: The workspace for generating and testing the service chart.
  - `configuration.yaml`: The simplified configuration for the service.
  - `test.sh`: The automation script.

## Step-by-Step Testing

### 1. Configure the Service

Edit `test-harness/configuration.yaml` to define your service requirements. This file controls which resources are generated.

Example `configuration.yaml`:
```yaml
serviceName: "my-app"
workload:
  type: Deployment
image:
  repository: nginx
  tag: latest
service:
  enabled: true
  type: ClusterIP
ingress:
  enabled: true
  hostname: my-app.local
```

### 2. Run the Test Harness

The `test.sh` script automates the generation and verification process. It performs the following:
1.  Reads `configuration.yaml`.
2.  Generates a `Chart.yaml` with the specified `serviceName`.
3.  Selectively copies templates from `platform-library` based on enabled features (e.g., if `cronJob.enabled` is false, `cronjob.yaml` is not included).
4.  Builds chart dependencies.
5.  Lints the generated chart.
6.  Renders the templates to `output/rendered.yaml`.
7.  Verifies the presence of key resources.

**Execute the script:**
```bash
cd test-harness
./test.sh
```

**Expected Output:**
```
...
Linting chart...
1 chart(s) linted, 0 chart(s) failed
Rendering template...
Verifying output...
  [PASS] Found Deployment
  [PASS] Found Service
Test Harness Completed Successfully.
```

### 3. Deploy to Local Cluster (Optional)

If you have a local Kubernetes cluster running and `kubectl` configured:

1.  **Install/Upgrade the Chart:**
    ```bash
    cd test-harness
    helm upgrade --install complex-app-v2 . -f configuration.yaml
    ```

2.  **Verify Deployment:**
    ```bash
    kubectl get all -l app.kubernetes.io/instance=complex-app-v2
    ```

3.  **Uninstall:**
    ```bash
    helm uninstall complex-app-v2
    ```

## troubleshooting

- **Missing Template:** If a resource is missing in the output, check if it is enabled in `configuration.yaml` and if the corresponding template exists in `platform-library`.
- **Lint Errors:** Check `configuration.yaml` for syntax errors or missing required fields.
