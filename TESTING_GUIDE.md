# Helm Chart Testing and Verification Guide

This guide details the steps to configure, build, and test the service Helm chart using the `platform-library` and a custom configuration.

## Overview

The process involves:
1.  Configuring the service requirements in `configuration.yaml`.
2.  Generating a standard Helm chart structure that depends on the `platform-library`.
3.  Building the chart dependencies (linking the local library).
4.  Rendering the chart templates to verify the Kubernetes manifests.

## Prerequisites

-   **Helm v3** installed (`brew install helm` on macOS).
-   Access to the `platform-library` directory.

## Step-by-Step Instructions

### 1. Configure the Service

Edit the `configuration.yaml` file to define your service's requirements.

**Key Fields:**
-   `serviceName`: Defines the name of the Helm chart and the service.
-   `libraryVersion`: Specifies the version of the platform library to use.
-   `service.name`: The name of the Kubernetes Service resource.
-   `deployment.image.repository` & `tag`: Your application's container image.

**Example `configuration.yaml` snippet:**
```yaml
serviceName: "my-cool-service"
libraryVersion: "1.0.0"

service:
  name: "my-cool-service"
  port: 80
  targetPort: 3000

deployment:
  replicas: 2
  image:
    repository: "my-org/my-app"
    tag: "v1.2.3"
```

### 2. Create the Test Harness

We use a script to automate the chart creation and testing process. This script mocks the behavior of a CI/CD pipeline or a developer scaffolding tool.

**File: `test-harness.sh`**

```bash
#!/bin/bash
set -e

# Read serviceName from configuration.yaml
SERVICE_NAME=$(grep "^serviceName:" configuration.yaml | cut -d '"' -f 2)

if [ -z "$SERVICE_NAME" ]; then
  echo "Error: serviceName not found in configuration.yaml"
  exit 1
fi

echo "Setting up test harness for service: $SERVICE_NAME"

# Clean up existing directory
rm -rf "$SERVICE_NAME"

# Create directory structure
mkdir -p "$SERVICE_NAME/templates"

# Create Chart.yaml
cat <<EOF > "$SERVICE_NAME/Chart.yaml"
apiVersion: v2
name: $SERVICE_NAME
description: A Helm chart for $SERVICE_NAME
type: application
version: 0.1.0
appVersion: "1.0.0"
dependencies:
  - name: platform
    version: 1.0.0
    repository: file://../platform-library
    import-values:
      - defaults
EOF

# Copy configuration.yaml to values.yaml
cp configuration.yaml "$SERVICE_NAME/values.yaml"

# Create templates/all.yaml to include platform templates
cat <<EOF > "$SERVICE_NAME/templates/all.yaml"
{{- include "platform.workload" . }}
---
{{- include "platform.service" . }}
---
{{- include "platform.ingress" . }}
---
{{- include "platform.serviceAccount" . }}
---
{{- include "platform.autoscaling" . }}
---
{{- include "platform.job.preinstall" . }}
---
{{- include "platform.job.postinstall" . }}
---
{{- include "platform.configmap.postinstall-script" . }}
EOF

# Build dependencies manually (bypassing Helm repo issues for local testing)
echo "Building dependencies manually..."
mkdir -p "$SERVICE_NAME/charts"
cp -r platform-library "$SERVICE_NAME/charts/platform"

echo "Rendering template..."
cd "$SERVICE_NAME"
helm template . > rendered.yaml

if [ -s rendered.yaml ]; then
  echo "Success! Template rendered to $SERVICE_NAME/rendered.yaml"
else
  echo "Error: Template rendering failed."
  exit 1
fi
```

### 3. Run the Test

Execute the harness script to generate and test the chart.

```bash
chmod +x test-harness.sh
./test-harness.sh
```

### 4. Verify Output

Check the generated `rendered.yaml` file in the service directory (e.g., `my-test-service/rendered.yaml`) to ensure the Kubernetes manifests are correct and match your configuration.

```bash
cat my-test-service/rendered.yaml
```

## Deployment to Local Kubernetes (Optional)

To deploy the generated chart to a local cluster (like Minikube, Kind, or Docker Desktop):

1.  Ensure your kubecontext is set to your local cluster.
    ```bash
    kubectl config current-context
    ```

2.  Install the chart using Helm.
    ```bash
    helm install my-test-service ./my-test-service
    ```

3.  Verify the running resources.
    ```bash
    kubectl get all -l app.kubernetes.io/instance=my-test-service
    ```
