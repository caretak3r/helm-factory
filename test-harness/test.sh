#!/bin/bash
set -e

# Configuration
CONFIG_FILE="configuration.yaml"
LIB_PATH="../platform-library"
OUTPUT_DIR="output"

echo "=== Helm Chart Test Harness ==="
echo "Configuration: $CONFIG_FILE"
echo "Library Path: $LIB_PATH"

# Check dependencies
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed."
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "Error: helm is not installed."
    exit 1
fi

# 1. Read Service Name
SERVICE_NAME=$(yq '.serviceName' "$CONFIG_FILE")
if [ "$SERVICE_NAME" == "null" ]; then
    echo "Error: serviceName not found in $CONFIG_FILE"
    exit 1
fi
echo "Target Chart Name: $SERVICE_NAME"

# 2. Generate Chart.yaml
echo "Generating Chart.yaml..."
cat <<EOF > Chart.yaml
apiVersion: v2
name: $SERVICE_NAME
description: Dynamically generated chart for testing
type: application
version: 0.1.0
appVersion: "1.0.0"
dependencies:
  - name: platform
    version: 1.0.0
    repository: "file://$LIB_PATH"
    import-values:
      - defaults
EOF

# 3. Populate Templates (The Generator Step)
echo "Populating templates based on configuration..."
rm -rf templates
mkdir -p templates

# Helper function to copy if enabled
copy_if_enabled() {
    local key=$1
    local file=$2
    local enabled=$(yq "$key" "$CONFIG_FILE")
    
    if [ "$enabled" == "true" ]; then
        if [ -f "$LIB_PATH/templates/$file" ]; then
            cp "$LIB_PATH/templates/$file" templates/
            echo "  [+] Included $file"
        else
            echo "  [!] Warning: Requested $file but it does not exist in library"
        fi
    fi
}

# Always copy helpers (underscore files)
echo "  [+] Copying helper templates..."
cp "$LIB_PATH"/templates/_*.yaml templates/

# Always copy workload (it handles its own logic)
cp "$LIB_PATH"/templates/workload.yaml templates/
echo "  [+] Included workload.yaml"

# Conditional inclusions
copy_if_enabled ".service.enabled" "service.yaml"
copy_if_enabled ".ingress.enabled" "ingress.yaml"
copy_if_enabled ".autoscaling.enabled" "hpa.yaml"
copy_if_enabled ".persistence.enabled" "pvc.yaml"
copy_if_enabled ".serviceMonitor.enabled" "servicemonitor.yaml"
copy_if_enabled ".podMonitor.enabled" "podmonitor.yaml"
copy_if_enabled ".cronJob.enabled" "cronjob.yaml"
copy_if_enabled ".serviceAccount.create" "serviceaccount.yaml"
copy_if_enabled ".networkPolicy.enabled" "networkpolicy.yaml"
copy_if_enabled ".podDisruptionBudget.enabled" "pdb.yaml"
copy_if_enabled ".secret.enabled" "secret.yaml"
copy_if_enabled ".configMap.enabled" "configmap.yaml"

# 4. Build Dependencies
echo "Building dependencies..."
helm dependency update > /dev/null

# 5. Lint
echo "Linting chart..."
helm lint . --values "$CONFIG_FILE"

# 6. Template
echo "Rendering template..."
mkdir -p "$OUTPUT_DIR"
helm template . --values "$CONFIG_FILE" > "$OUTPUT_DIR/rendered.yaml"
echo "Template rendered to $OUTPUT_DIR/rendered.yaml"

# 7. Verification
echo "Verifying output..."
ERRORS=0

# Check Workload
WORKLOAD_TYPE=$(yq '.workload.type' "$CONFIG_FILE")
if grep -q "kind: $WORKLOAD_TYPE" "$OUTPUT_DIR/rendered.yaml"; then
    echo "  [PASS] Found $WORKLOAD_TYPE"
else
    echo "  [FAIL] Missing $WORKLOAD_TYPE"
    ERRORS=$((ERRORS+1))
fi

# Check Service
if [ "$(yq '.service.enabled' "$CONFIG_FILE")" == "true" ]; then
    if grep -q "kind: Service" "$OUTPUT_DIR/rendered.yaml"; then
        echo "  [PASS] Found Service"
    else
        echo "  [FAIL] Missing Service"
        ERRORS=$((ERRORS+1))
    fi
fi

# Check Ingress
if [ "$(yq '.ingress.enabled' "$CONFIG_FILE")" == "true" ]; then
    if grep -q "kind: Ingress" "$OUTPUT_DIR/rendered.yaml"; then
        echo "  [PASS] Found Ingress"
    else
        echo "  [FAIL] Missing Ingress"
        ERRORS=$((ERRORS+1))
    fi
fi

if [ "$ERRORS" -eq 0 ]; then
    echo "Test Harness Completed Successfully."
else
    echo "Test Harness Failed with $ERRORS errors."
    exit 1
fi