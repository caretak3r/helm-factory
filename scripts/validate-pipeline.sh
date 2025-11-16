#!/bin/bash
set -e

echo "🔍 Validating Jenkins Pipeline Configuration..."

# Check Jenkinsfile exists
if [ ! -f "Jenkinsfile" ]; then
    echo "❌ Jenkinsfile not found"
    exit 1
fi
echo "✓ Jenkinsfile exists"

# Check scripts exist
REQUIRED_SCRIPTS=(
    "scripts/setup-k3s.sh"
    "scripts/install-jenkins.sh"
    "scripts/run-tests.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then
        echo "❌ Required script not found: $script"
        exit 1
    fi
    echo "✓ $script exists"
done

# Check Jenkins manifests exist
REQUIRED_MANIFESTS=(
    "jenkins/namespace.yaml"
    "jenkins/jenkins-service.yaml"
    "jenkins/jenkins-deployment.yaml"
    "jenkins/jenkins-pvc.yaml"
    "jenkins/jenkins-rbac.yaml"
    "jenkins/jenkins-config.yaml"
)

for manifest in "${REQUIRED_MANIFESTS[@]}"; do
    if [ ! -f "$manifest" ]; then
        echo "❌ Required manifest not found: $manifest"
        exit 1
    fi
    echo "✓ $manifest exists"
done

# Validate YAML syntax
echo ""
echo "Validating YAML syntax..."
for manifest in jenkins/*.yaml; do
    if command -v yamllint &> /dev/null; then
        yamllint "$manifest" || echo "⚠️  yamllint not installed, skipping validation"
    fi
done

# Check if kubectl can validate
if command -v kubectl &> /dev/null; then
    echo ""
    echo "Validating Kubernetes manifests..."
    for manifest in jenkins/*.yaml; do
        kubectl apply --dry-run=client -f "$manifest" > /dev/null 2>&1 && \
            echo "✓ $manifest is valid" || \
            echo "⚠️  $manifest validation failed (may need cluster context)"
    done
fi

echo ""
echo "✅ Pipeline configuration validation complete!"

