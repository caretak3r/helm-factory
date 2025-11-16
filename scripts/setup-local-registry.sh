#!/bin/bash
set -e

echo "🐳 Setting up local Docker registry..."

# Check if registry container is running
if docker ps | grep -q registry:2; then
    echo "✓ Local registry already running"
else
    echo "Starting local registry..."
    docker run -d \
        --name local-registry \
        --restart=always \
        -p 5000:5000 \
        registry:2
    echo "✓ Local registry started"
fi

# Wait for registry to be ready
echo "Waiting for registry to be ready..."
sleep 2

# Verify registry is accessible
if curl -s http://localhost:5000/v2/ > /dev/null; then
    echo "✓ Registry is accessible at http://localhost:5000"
else
    echo "⚠️  Registry may not be ready yet"
fi

echo ""
echo "✅ Local registry setup complete!"
echo ""
echo "Registry URL: http://localhost:5000"
echo ""
echo "To build and push images:"
echo "  cd services/frontend && docker build -t localhost:5000/frontend:latest ."
echo "  docker push localhost:5000/frontend:latest"
echo ""
echo "  cd services/backend && docker build -t localhost:5000/backend:latest ."
echo "  docker push localhost:5000/backend:latest"
echo ""
echo "  cd services/database && docker build -t localhost:5000/database:latest ."
echo "  docker push localhost:5000/database:latest"

