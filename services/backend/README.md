# Backend Service

Python Flask service that acts as middleware between frontend and database, and fetches metrics from Kubernetes API.

## Features

- Fetches deployment and pod metrics from Kubernetes API
- Stores pod metrics in PostgreSQL database
- Provides REST API for frontend
- Handles database connection and error handling

## API Endpoints

- `GET /health` - Health check
- `GET /ready` - Readiness check (checks DB connection)
- `GET /api/stats` - Overall statistics
- `GET /api/deployments` - List all deployments
- `GET /api/pods` - List all pods
- `GET /api/pods/history` - Pod metrics history from database

## Environment Variables

- `DB_HOST` - Database host (default: database)
- `DB_PORT` - Database port (default: 5432)
- `DB_NAME` - Database name (default: k8s_metrics)
- `DB_USER` - Database user (default: postgres)
- `DB_PASSWORD` - Database password (default: postgres)
- `NAMESPACE` - Kubernetes namespace (default: platform)

## Building

```bash
# Build image
docker build -t localhost:5000/backend:latest .

# Push to local registry
docker push localhost:5000/backend:latest
```

## Running Locally

```bash
# Install dependencies
pip install -r requirements.txt

# Run
python main.py
```

## Kubernetes RBAC

The backend service needs RBAC permissions to read deployments and pods. This is configured in the deployment's ServiceAccount.

