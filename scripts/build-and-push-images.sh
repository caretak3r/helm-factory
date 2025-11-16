#!/bin/bash
set -e

REGISTRY="${REGISTRY:-localhost:5000}"

echo "🏗️  Building and pushing all service images to $REGISTRY..."

# Build and push frontend
echo ""
echo "Building frontend..."
cd services/frontend
docker build -t "$REGISTRY/frontend:latest" .
docker push "$REGISTRY/frontend:latest"
echo "✓ Frontend image pushed"

# Build and push backend
echo ""
echo "Building backend..."
cd ../backend
docker build -t "$REGISTRY/backend:latest" .
docker push "$REGISTRY/backend:latest"
echo "✓ Backend image pushed"

# Build and push database
echo ""
echo "Building database..."
cd ../database
docker build -t "$REGISTRY/database:latest" .
docker push "$REGISTRY/database:latest"
echo "✓ Database image pushed"

cd ../..

echo ""
echo "✅ All images built and pushed successfully!"
echo ""
echo "Images available at:"
echo "  - $REGISTRY/frontend:latest"
echo "  - $REGISTRY/backend:latest"
echo "  - $REGISTRY/database:latest"

