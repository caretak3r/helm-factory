#!/bin/bash
set -e

echo "🚀 Helm Chart Factory - Jenkins Quick Start"
echo "============================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "📋 Checking prerequisites..."

MISSING_DEPS=0

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    MISSING_DEPS=1
else
    echo -e "${GREEN}✓ kubectl found${NC}"
fi

if ! command -v helm &> /dev/null && ! command -v k3s &> /dev/null; then
    echo -e "${YELLOW}⚠ helm not found (will use k3s bundled version)${NC}"
else
    echo -e "${GREEN}✓ helm/k3s found${NC}"
fi

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ python3 not found${NC}"
    MISSING_DEPS=1
else
    echo -e "${GREEN}✓ python3 found${NC}"
fi

if ! command -v uv &> /dev/null; then
    echo -e "${RED}✗ uv not found. Install from https://github.com/astral-sh/uv${NC}"
    MISSING_DEPS=1
else
    echo -e "${GREEN}✓ uv found${NC}"
fi

if [ $MISSING_DEPS -eq 1 ]; then
    echo ""
    echo -e "${RED}Please install missing dependencies and try again.${NC}"
    exit 1
fi

echo ""
echo "Step 1: Setting up k3s cluster..."
echo "---------------------------------"
./scripts/setup-k3s.sh

echo ""
echo "Step 2: Installing Python dependencies..."
echo "----------------------------------------"
cd chart-generator && uv pip install -r requirements.txt && cd ..
cd umbrella-sync && uv pip install -r requirements.txt && cd ..

echo ""
echo "Step 3: Installing Jenkins..."
echo "------------------------------"
./scripts/install-jenkins.sh

echo ""
echo "Step 4: Waiting for Jenkins to be ready..."
echo "-------------------------------------------"
kubectl wait --for=condition=ready pod -l app=jenkins -n jenkins --timeout=300s

echo ""
echo "✅ Setup complete!"
echo ""
echo "=== Access Information ==="
echo ""
echo "Jenkins URL: http://localhost:30080"
echo ""
echo "Get admin password:"
echo "  kubectl exec -n jenkins \$(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}') -- cat /var/jenkins_home/secrets/initialAdminPassword"
echo ""
echo "Or port-forward for direct access:"
echo "  kubectl port-forward -n jenkins svc/jenkins 8080:8080"
echo ""
echo "Next steps:"
echo "1. Access Jenkins at http://localhost:30080"
echo "2. Login with admin and the password above"
echo "3. Create a new Pipeline job"
echo "4. Point it to this repository's Jenkinsfile"
echo "5. Run the pipeline!"
echo ""

