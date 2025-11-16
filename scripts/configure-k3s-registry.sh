#!/bin/bash
set -e

echo "⚙️  Configuring k3s to use local registry..."

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo "This script needs sudo privileges to configure k3s"
    exit 1
fi

# Create registry config directory
mkdir -p /etc/rancher/k3s

# Check if already configured
if grep -q "localhost:5000" /etc/rancher/k3s/registries.yaml 2>/dev/null; then
    echo "✓ k3s registry already configured"
    cat /etc/rancher/k3s/registries.yaml
else
    echo "Configuring k3s registry..."
    cat > /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  localhost:5000:
    endpoint:
      - "http://localhost:5000"
EOF
    
    echo "✓ Registry configuration created"
    echo ""
    echo "Configuration:"
    cat /etc/rancher/k3s/registries.yaml
    echo ""
    echo "Restarting k3s..."
    systemctl restart k3s
    
    echo "Waiting for k3s to be ready..."
    sleep 5
    
    # Verify k3s is running
    if kubectl cluster-info &>/dev/null; then
        echo "✓ k3s is running and configured"
    else
        echo "⚠️  k3s may not be ready yet"
    fi
fi

