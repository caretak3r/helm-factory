# Service Implementation Guide

This document describes the three services implemented for the Helm Chart Factory proof-of-concept.

## Overview

Three services work together to create a simple Kubernetes dashboard:

1. **Frontend** - React web application displaying Kubernetes metrics
2. **Backend** - Python Flask API that fetches metrics and stores them in database
3. **Database** - PostgreSQL database storing pod metrics

## Architecture

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Frontend   │─────▶│   Backend   │─────▶│  Database   │
│  (React)    │      │   (Flask)   │      │ (PostgreSQL) │
└─────────────┘      └─────────────┘      └─────────────┘
      │                     │
      │                     │
      │                     ▼
      │              ┌─────────────┐
      │              │ Kubernetes  │
      │              │    API     │
      │              └─────────────┘
      │
      ▼
┌─────────────┐
│   Ingress   │
│  (nginx)    │
└─────────────┘
```

## Frontend Service

### Technology Stack
- React 18
- Axios for API calls
- Nginx for serving static files

### Features
- Display deployments with replica counts
- Display pods with status, node, and age
- Real-time statistics (total deployments, pods, running/pending)
- Auto-refresh every 30 seconds
- Simple, clean UI

### Dockerfile
Multi-stage build:
1. Build stage: Node.js builds React app
2. Production stage: Nginx serves static files

### Configuration
- Image: `localhost:5000/frontend:latest`
- Port: 80
- Health checks: `/health` and `/ready`
- Ingress: Enabled with TLS (self-signed cert)

## Backend Service

### Technology Stack
- Python 3.11
- Flask for REST API
- Kubernetes Python client
- PostgreSQL client (psycopg2)

### API Endpoints

#### `GET /health`
Health check endpoint.

#### `GET /ready`
Readiness check. Verifies database connection.

#### `GET /api/stats`
Returns overall statistics:
```json
{
  "namespace": "platform",
  "totalDeployments": 3,
  "totalPods": 5,
  "runningPods": 4,
  "pendingPods": 1
}
```

#### `GET /api/deployments`
Returns list of deployments:
```json
[
  {
    "name": "frontend",
    "replicas": 2,
    "ready": 2,
    "available": 2,
    "age": "1d 2h"
  }
]
```

#### `GET /api/pods`
Returns list of pods:
```json
[
  {
    "name": "frontend-abc123",
    "podId": "uuid-here",
    "status": "Running",
    "node": "node-1",
    "age": "2h"
  }
]
```

#### `GET /api/pods/history`
Returns pod metrics history from database.

### Kubernetes Integration
- Uses in-cluster config to connect to Kubernetes API
- Reads deployments and pods from `platform` namespace
- Stores pod metrics in database

### Database Integration
- Connects to PostgreSQL database
- Stores pod metrics with pod ID, status, node, timestamp
- Uses connection pooling

### Dockerfile
- Python 3.11-slim base image
- Non-root user (UID 1000)
- Health checks configured

### Configuration
- Image: `localhost:5000/backend:latest`
- Port: 8080
- Environment variables for DB connection
- No ingress (internal service only)

## Database Service

### Technology Stack
- PostgreSQL 15 Alpine

### Schema

#### `pod_metrics` table
```sql
CREATE TABLE pod_metrics (
    id SERIAL PRIMARY KEY,
    pod_name VARCHAR(255) NOT NULL,
    pod_id VARCHAR(255) UNIQUE NOT NULL,
    status VARCHAR(50) NOT NULL,
    node_name VARCHAR(255),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Initialization
- Schema created automatically via `init.sql`
- Indexes on pod_id, timestamp, pod_name
- View for recent metrics

### Dockerfile
- PostgreSQL 15 Alpine base
- Initialization script copied to `/docker-entrypoint-initdb.d/`
- Health check using `pg_isready`

### Configuration
- Image: `localhost:5000/database:latest`
- Port: 5432
- Persistent storage: 10Gi PVC
- Storage class: `local-path` (k3s compatible)

## Local Registry Setup

All services use a local Docker registry at `localhost:5000`.

### Setup Registry
```bash
make setup-registry
```

### Build and Push Images
```bash
make build-images
```

### Configure k3s
```bash
make configure-k3s-registry
```

This configures k3s to pull from `localhost:5000`.

## Cert-Manager Setup

Self-signed certificate issuer for TLS.

### ClusterIssuer
- Name: `factory-self-ca`
- Type: Self-signed
- Used for frontend ingress TLS

### Installation
```bash
make install-cert-manager
```

## Deployment Flow

1. **Build Images**
   ```bash
   cd services/frontend && docker build -t localhost:5000/frontend:latest .
   docker push localhost:5000/frontend:latest
   ```

2. **Generate Charts**
   ```bash
   make generate-all
   ```

3. **Sync Umbrella**
   ```bash
   make sync
   ```

4. **Deploy**
   ```bash
   helm upgrade --install platform umbrella-chart/ -n platform --create-namespace
   ```

## Accessing Services

### Frontend Dashboard
```bash
# Port forward
kubectl port-forward -n platform svc/frontend 8080:80

# Or via ingress (if configured)
# Add to /etc/hosts: 127.0.0.1 frontend.local
# Visit: http://frontend.local
```

### Backend API
```bash
# Port forward
kubectl port-forward -n platform svc/backend 8081:80

# Test
curl http://localhost:8081/api/stats
```

### Database
```bash
# Port forward
kubectl port-forward -n platform svc/database 5432:5432

# Connect
psql -h localhost -U postgres -d k8s_metrics
```

## Development

### Frontend Development
```bash
cd services/frontend
npm install
npm start  # Runs on http://localhost:3000
```

### Backend Development
```bash
cd services/backend
pip install -r requirements.txt
python main.py  # Runs on http://localhost:8080
```

### Database Development
```bash
cd services/database
docker build -t localhost:5000/database:latest .
docker run -p 5432:5432 localhost:5000/database:latest
```

## Environment Variables

### Frontend
- `REACT_APP_API_URL` - Backend API URL (default: http://backend:80)

### Backend
- `DB_HOST` - Database host (default: database)
- `DB_PORT` - Database port (default: 5432)
- `DB_NAME` - Database name (default: k8s_metrics)
- `DB_USER` - Database user (default: postgres)
- `DB_PASSWORD` - Database password (default: postgres)
- `NAMESPACE` - Kubernetes namespace (default: platform)

### Database
- `POSTGRES_DB` - Database name (default: k8s_metrics)
- `POSTGRES_USER` - Database user (default: postgres)
- `POSTGRES_PASSWORD` - Database password (default: postgres)

## Troubleshooting

### Images Not Pulling
- Verify registry is running: `docker ps | grep local-registry`
- Check k3s registry config: `cat /etc/rancher/k3s/registries.yaml`
- Restart k3s: `sudo systemctl restart k3s`

### Backend Can't Connect to Database
- Check database pod: `kubectl get pods -n platform -l app.kubernetes.io/name=database`
- Check database logs: `kubectl logs -n platform -l app.kubernetes.io/name=database`
- Verify service: `kubectl get svc database -n platform`

### Backend Can't Access Kubernetes API
- Check RBAC permissions
- Verify ServiceAccount: `kubectl get sa -n platform`
- Check pod is using correct ServiceAccount

### Frontend Not Loading Data
- Check backend logs: `kubectl logs -n platform -l app.kubernetes.io/name=backend`
- Verify backend service: `kubectl get svc backend -n platform`
- Test API directly: `curl http://backend/api/stats` (from within cluster)

## Next Steps

- Add authentication
- Add more metrics (CPU, memory usage)
- Add pod logs viewer
- Add deployment history
- Add resource usage graphs
- Add namespace selector
- Add filtering and search

