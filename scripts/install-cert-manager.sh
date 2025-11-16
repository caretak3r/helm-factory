#!/bin/bash
set -e

echo "📜 Installing cert-manager and self-signed issuer..."

# Check if cert-manager is already installed
if kubectl get namespace cert-manager &>/dev/null; then
    echo "✓ cert-manager namespace already exists"
else
    echo "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    
    echo "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
    echo "✓ cert-manager installed"
fi

# Install self-signed ClusterIssuer
echo ""
echo "Installing factory-self-ca ClusterIssuer..."
kubectl apply -f cert-manager/cluster-issuer.yaml

# Wait a moment for issuer to be ready
sleep 2

# Verify issuer
if kubectl get clusterissuer factory-self-ca &>/dev/null; then
    echo "✓ factory-self-ca ClusterIssuer installed"
    kubectl get clusterissuer factory-self-ca
else
    echo "⚠️  ClusterIssuer may not be ready yet"
fi

echo ""
echo "✅ cert-manager setup complete!"

