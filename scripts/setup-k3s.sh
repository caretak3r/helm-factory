#!/bin/bash
set -e

K3S_CLUSTER_NAME="${K3S_CLUSTER_NAME:-helm-factory-cluster}"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

echo "🚀 Setting up k3s cluster: $K3S_CLUSTER_NAME"

# Check if k3s is already installed
if command -v k3s &> /dev/null; then
    echo "✓ k3s is installed"
else
    echo "📥 Installing k3s..."
    curl -sfL https://get.k3s.io | sh -
fi

# Check if k3s is running
if sudo systemctl is-active --quiet k3s || sudo systemctl is-active --quiet k3s-agent; then
    echo "✓ k3s is already running"
else
    echo "🔧 Starting k3s..."
    sudo systemctl start k3s || sudo k3s server &
    sleep 10
fi

# Wait for k3s to be ready
echo "⏳ Waiting for k3s to be ready..."
timeout=60
elapsed=0
while ! sudo k3s kubectl get nodes &>/dev/null; do
    if [ $elapsed -ge $timeout ]; then
        echo "❌ Timeout waiting for k3s to be ready"
        exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

# Setup kubeconfig
echo "📝 Setting up kubeconfig..."
mkdir -p "$(dirname "$KUBECONFIG")"
sudo k3s kubectl config view --raw > "$KUBECONFIG"
chmod 600 "$KUBECONFIG"

# Verify cluster access
echo "✅ Verifying cluster access..."
export KUBECONFIG="$KUBECONFIG"
kubectl cluster-info
kubectl get nodes

echo "✅ k3s cluster is ready!"
echo "KUBECONFIG=$KUBECONFIG"

