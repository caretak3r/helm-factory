# Frontend Service - Kubernetes Dashboard

A simple React-based Kubernetes dashboard displaying deployment and pod metrics.

## Features

- View all deployments in the platform namespace
- View all pods with status, node, and age
- Real-time metrics (total deployments, pods, running/pending counts)
- Auto-refresh every 30 seconds
- Simple, clean UI

## Building

```bash
# Install dependencies
npm install

# Development
npm start

# Production build
npm run build
```

## Docker Build

```bash
# Build image
docker build -t localhost:5000/frontend:latest .

# Push to local registry
docker push localhost:5000/frontend:latest
```

## Environment Variables

- `REACT_APP_API_URL` - Backend API URL (default: http://backend:80)

## Health Checks

- `/health` - Health check endpoint
- `/ready` - Readiness check endpoint

