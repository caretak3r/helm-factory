#!/bin/bash
set -e

echo "🚀 Installing Jenkins on k3s cluster..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl or setup k3s first."
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cannot connect to cluster. Please setup k3s first."
    exit 1
fi

# Create namespace
echo "📦 Creating Jenkins namespace..."
kubectl apply -f jenkins/namespace.yaml

# Create PVC
echo "💾 Creating persistent volume claim..."
kubectl apply -f jenkins/jenkins-pvc.yaml

# Create RBAC
echo "🔐 Setting up RBAC..."
kubectl apply -f jenkins/jenkins-rbac.yaml

# Create ConfigMap
echo "⚙️  Creating ConfigMap..."
kubectl apply -f jenkins/jenkins-config.yaml

# Create Service
echo "🌐 Creating service..."
kubectl apply -f jenkins/jenkins-service.yaml

# Create Deployment
echo "🚢 Deploying Jenkins..."
kubectl apply -f jenkins/jenkins-deployment.yaml

# Wait for Jenkins to be ready
echo "⏳ Waiting for Jenkins to be ready..."
kubectl wait --for=condition=available \
    --timeout=300s \
    deployment/jenkins \
    -n jenkins

# Get Jenkins admin password
echo "🔑 Getting Jenkins admin password..."
JENKINS_POD=$(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}')
if [ -n "$JENKINS_POD" ]; then
    echo "Jenkins pod: $JENKINS_POD"
    echo "Waiting for pod to be ready..."
    kubectl wait --for=condition=ready pod/$JENKINS_POD -n jenkins --timeout=300s
    
    echo ""
    echo "=== Jenkins Admin Password ==="
    kubectl exec -n jenkins $JENKINS_POD -- cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || \
    echo "Password will be available once Jenkins is fully initialized"
    echo ""
fi

# Get service URL
echo "=== Jenkins Access Information ==="
echo "Jenkins URL: http://localhost:30080"
echo "NodePort: 30080"
echo ""
echo "To access from outside:"
kubectl get svc jenkins -n jenkins

echo ""
echo "✅ Jenkins installation complete!"
echo ""
echo "Next steps:"
echo "1. Access Jenkins at http://localhost:30080"
echo "2. Get admin password: kubectl exec -n jenkins <pod-name> -- cat /var/jenkins_home/secrets/initialAdminPassword"
echo "3. Install recommended plugins"
echo "4. Create a new pipeline job pointing to this repository"

