# Database Service

PostgreSQL database for storing Kubernetes pod metrics.

## Schema

### pod_metrics table

- `id` - Primary key
- `pod_name` - Pod name
- `pod_id` - Pod UID (unique)
- `status` - Pod status (Running, Pending, etc.)
- `node_name` - Node where pod is running
- `timestamp` - When metric was recorded

## Initialization

The database is automatically initialized with the schema when the container starts using `init.sql`.

## Building

```bash
# Build image
docker build -t localhost:5000/database:latest .

# Push to local registry
docker push localhost:5000/database:latest
```

## Environment Variables

- `POSTGRES_DB` - Database name (default: k8s_metrics)
- `POSTGRES_USER` - Database user (default: postgres)
- `POSTGRES_PASSWORD` - Database password (default: postgres)

## Data Persistence

Data is persisted using a PersistentVolumeClaim. The storage class `local-path` is used for k3s compatibility.

