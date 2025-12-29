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

# Create templates/all.yaml
# We include all available templates from the platform-library.
# The templates themselves handle enabled/disabled logic based on values.
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

echo "Chart structure created."

# Build dependencies manually to bypass helm repo issues
echo "Building dependencies manually..."
mkdir -p "$SERVICE_NAME/charts"
cp -r platform-library "$SERVICE_NAME/charts/platform"

# Verify manual copy
if [ -d "$SERVICE_NAME/charts/platform" ]; then
    echo "Dependency 'platform' copied successfully."
else
    echo "Error: Failed to copy platform dependency."
    exit 1
fi

cd "$SERVICE_NAME"

# Render template to verify
echo "Rendering template..."
helm template . > rendered.yaml

if [ -s rendered.yaml ]; then
  echo "Template rendered successfully. Output saved to $SERVICE_NAME/rendered.yaml"
  echo "Preview of rendered content:"
  head -n 20 rendered.yaml
else
  echo "Error: Template rendering failed or produced empty output."
  exit 1
fi

echo "Test harness complete."
