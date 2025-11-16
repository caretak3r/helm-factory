#!/bin/bash
set -e

NAMESPACE="${1:-platform}"

echo "🧪 Running tests for namespace: $NAMESPACE"

# Test 1: Check all pods are running
echo "Test 1: Checking pod status..."
FAILED_PODS=$(kubectl get pods -n "$NAMESPACE" -o json | \
    jq -r '.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | .metadata.name')

if [ -n "$FAILED_PODS" ]; then
    echo "❌ Failed pods found:"
    echo "$FAILED_PODS"
    exit 1
fi
echo "✅ All pods are running"

# Test 2: Check deployments are ready
echo "Test 2: Checking deployment readiness..."
NOT_READY=$(kubectl get deployments -n "$NAMESPACE" -o json | \
    jq -r '.items[] | select(.status.readyReplicas != .spec.replicas) | .metadata.name')

if [ -n "$NOT_READY" ]; then
    echo "❌ Deployments not ready:"
    echo "$NOT_READY"
    exit 1
fi
echo "✅ All deployments are ready"

# Test 3: Check services have endpoints
echo "Test 3: Checking service endpoints..."
SERVICES=$(kubectl get svc -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

for svc in $SERVICES; do
    ENDPOINTS=$(kubectl get endpoints "$svc" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
    if [ -z "$ENDPOINTS" ] && [ "$svc" != "kubernetes" ]; then
        echo "⚠️  Service $svc has no endpoints"
    fi
done
echo "✅ Service endpoints checked"

# Test 4: Check ingress (if any)
echo "Test 4: Checking ingress..."
INGRESS_COUNT=$(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$INGRESS_COUNT" -gt 0 ]; then
    echo "✅ Found $INGRESS_COUNT ingress resource(s)"
    kubectl get ingress -n "$NAMESPACE"
else
    echo "ℹ️  No ingress resources found"
fi

# Test 5: Health check endpoints (if available)
echo "Test 5: Checking health endpoints..."
PODS=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

for pod in $PODS; do
    # Try to check if pod responds to health checks
    READY=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$READY" != "True" ]; then
        echo "⚠️  Pod $pod is not ready"
    fi
done
echo "✅ Health checks completed"

# Test 6: Resource usage check
echo "Test 6: Checking resource usage..."
kubectl top pods -n "$NAMESPACE" 2>/dev/null || echo "ℹ️  Metrics server not available"

echo "✅ All tests passed!"

