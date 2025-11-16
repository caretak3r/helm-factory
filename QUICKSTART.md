# Quick Start Guide - Complete Setup

This guide walks you through setting up the entire Helm Chart Factory system with local registry and all services.

## Prerequisites

- Docker installed and running
- Python 3.11+ with uv
- kubectl (will be installed with k3s)
- ~5GB free disk space

## Complete Setup

### Option 1: One-Command Setup

```bash
make setup-all
```

This will:
1. Install Python dependencies
2. Setup local Docker registry
3. Install cert-manager with self-signed issuer
4. Build and push all service images

### Option 2: Step-by-Step

#### 1. Install Dependencies

```bash
make setup
```

#### 2. Setup Local Registry

```bash
make setup-registry
```

This starts a local Docker registry on port 5000.

#### 3. Build and Push Images

```bash
make build-images
```

This builds and pushes:
- `localhost:5000/frontend:latest`
- `localhost:5000/backend:latest`
- `localhost:5000/database:latest`

#### 4. Setup k3s Cluster

```bash
make setup-k3s
```

#### 5. Install cert-manager

```bash
make install-cert-manager
```

#### 6. Configure k3s to Use Local Registry

```bash
# Create registry config
sudo mkdir -p /etc/rancher/k3s
cat <<EOF | sudo tee /etc/rancher/k3s/registries.yaml
mirrors:
  localhost:5000:
    endpoint:
      - "http://localhost:5000"
EOF

# Restart k3s
sudo systemctl restart k3s
```

#### 7. Generate Charts

```bash
make generate-all
```

#### 8. Sync Umbrella Chart

```bash
make sync
```

#### 9. Deploy to k3s

```bash
cd umbrella-chart
helm dependency update
helm upgrade --install platform . \
  --namespace platform \
  --create-namespace \
  --wait \
  --timeout 10m
```

## Verify Deployment

```bash
# Check pods
kubectl get pods -n platform

# Check services
kubectl get svc -n platform

# Check ingress
kubectl get ingress -n platform

# View frontend (if ingress configured)
# Add to /etc/hosts: 127.0.0.1 frontend.local
# Then visit: http://frontend.local
```

## Access Services

### Frontend Dashboard

```bash
# Port forward frontend
kubectl port-forward -n platform svc/frontend 8080:80

# Access at http://localhost:8080
```

### Backend API

```bash
# Port forward backend
kubectl port-forward -n platform svc/backend 8081:80

# Test API
curl http://localhost:8081/api/stats
```

### Database

```bash
# Port forward database
kubectl port-forward -n platform svc/database 5432:5432

# Connect with psql
psql -h localhost -U postgres -d k8s_metrics
```

## Troubleshooting

### Images Not Pulling

If k3s can't pull images from localhost:5000:

```bash
# Check registry is running
docker ps | grep local-registry

# Test registry
curl http://localhost:5000/v2/

# Restart k3s after registry config
sudo systemctl restart k3s
```

### Certificates Not Issuing

```bash
# Check cert-manager
kubectl get pods -n cert-manager

# Check ClusterIssuer
kubectl get clusterissuer factory-self-ca

# Check certificates
kubectl get certificates -n platform
```

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod <pod-name> -n platform

# Check pod logs
kubectl logs <pod-name> -n platform
```

## Development Workflow

### Update Service Code

1. Edit code in `services/<service>/`
2. Rebuild image: `docker build -t localhost:5000/<service>:latest services/<service>/`
3. Push image: `docker push localhost:5000/<service>:latest`
4. Restart deployment: `kubectl rollout restart deployment/<service> -n platform`

### Update Configuration

1. Edit `services/<service>/configuration.yml`
2. Regenerate chart: `make generate-<service>`
3. Sync umbrella: `make sync`
4. Upgrade deployment: `helm upgrade platform umbrella-chart/ -n platform`

## Cleanup

```bash
# Remove deployments
helm uninstall platform -n platform

# Remove namespace
kubectl delete namespace platform

# Stop registry
docker stop local-registry
docker rm local-registry

# Clean generated files
make clean
```
