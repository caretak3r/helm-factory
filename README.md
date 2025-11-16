# Helm Chart Factory - Platform Best Practices

A proof-of-concept system for automatically generating Helm charts from service configurations using a shared library chart with platform best practices.

## Overview

This system allows service teams to:
- Submit a simple `configuration.yml` file (like `values.yaml`)
- Automatically generate a complete Helm chart using platform best practices
- Have their service automatically included in an umbrella chart

The platform team maintains:
- A library chart (`platform-library`) with best practices templates
- Automation to sync service configurations to umbrella chart dependencies

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Service Teams                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ Frontend     │  │ Backend      │  │ Database     │     │
│  │ config.yml   │  │ config.yml   │  │ config.yml   │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                 │                 │              │
└─────────┼─────────────────┼─────────────────┼──────────────┘
          │                 │                 │
          └─────────────────┼─────────────────┘
                            │
          ┌─────────────────▼─────────────────┐
          │     Chart Generator Tool           │
          │  (config.yml + library chart)     │
          └─────────────────┬─────────────────┘
                            │
          ┌─────────────────▼─────────────────┐
          │     Generated Service Charts       │
          │  (frontend, backend, database)     │
          └─────────────────┬─────────────────┘
                            │
          ┌─────────────────▼─────────────────┐
          │     Umbrella Chart Sync            │
          │  (Updates Chart.yaml dependencies) │
          └─────────────────┬─────────────────┘
                            │
          ┌─────────────────▼─────────────────┐
          │     Umbrella Chart                 │
          │  (All services as dependencies)    │
          └────────────────────────────────────┘
```

## Directory Structure

```
factory/
├── platform-library/          # Platform library chart with best practices
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── certificate.yaml
│       ├── mtls.yaml
│       └── ...
├── chart-generator/         # Tool to generate charts from config.yml
│   ├── main.py
│   └── requirements.txt
├── umbrella-sync/           # Tool to sync configs to umbrella chart
│   ├── main.py
│   └── requirements.txt
├── umbrella-chart/          # Umbrella chart with all services
│   ├── Chart.yaml
│   ├── values.yaml
│   └── charts/              # Generated service charts
├── services/                # Service team configurations
│   ├── frontend/
│   │   └── configuration.yml
│   ├── backend/
│   │   └── configuration.yml
│   └── database/
│       └── configuration.yml
└── .github/workflows/       # CI/CD automation
    └── sync-umbrella.yml
```

## Quick Start

### Prerequisites

- Python 3.11+
- [uv](https://github.com/astral-sh/uv) (Python package manager)
- Helm 3.x

### Setup

1. **Install dependencies:**

```bash
cd chart-generator
uv pip install -r requirements.txt

cd ../umbrella-sync
uv pip install -r requirements.txt
```

2. **Generate a service chart:**

```bash
cd chart-generator
python main.py \
  --config ../services/frontend/configuration.yml \
  --library ../platform-library \
  --output ../generated-charts/frontend \
  --name frontend
```

3. **Sync umbrella chart:**

```bash
cd umbrella-sync
python main.py \
  --umbrella ../umbrella-chart \
  --services ../services \
  --library ../platform-library \
  --generate-charts
```

## Service Configuration Format

Service teams create a `configuration.yml` file that looks like a `values.yaml`:

```yaml
service:
  name: my-service
  type: ClusterIP
  port: 80
  targetPort: 8080

deployment:
  replicas: 2
  image:
    repository: myregistry/my-service
    tag: "v1.0.0"
    pullPolicy: IfNotPresent
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: my-service.example.com
      paths:
        - path: /
          pathType: Prefix

mtls:
  enabled: true
  policy: STRICT

certificate:
  enabled: true
  issuer: letsencrypt-prod
  secretName: my-service-tls

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

version: "0.1.0"
appVersion: "1.0.0"
```

## Library Chart Features

The `platform-library` chart provides:

- **Deployment** with best practices:
  - Security contexts (non-root, read-only filesystem)
  - Resource limits and requests
  - Liveness and readiness probes
  - Pod security contexts

- **Service** with proper selectors

- **Ingress** with TLS support

- **Certificates** via cert-manager integration

- **mTLS** via Istio PeerAuthentication and AuthorizationPolicy

- **HorizontalPodAutoscaler** for automatic scaling

- **ServiceAccount** with configurable annotations

## Umbrella Chart

The umbrella chart automatically includes all services as dependencies:

```yaml
dependencies:
  - name: frontend
    version: "0.1.0"
    repository: "file://./charts/frontend"
    alias: frontend
  - name: backend
    version: "0.1.0"
    repository: "file://./charts/backend"
    alias: backend
  - name: database
    version: "0.1.0"
    repository: "file://./charts/database"
    alias: database
```

## CI/CD Integration

A GitHub Actions workflow (`sync-umbrella.yml`) automatically:
1. Detects changes to service `configuration.yml` files
2. Regenerates service charts
3. Updates umbrella chart dependencies
4. Creates a PR with the changes

## Workflow

1. **Service team creates/updates `configuration.yml`**
   - Commits to their service directory
   - Pushes to repository

2. **CI/CD detects change**
   - Runs `umbrella-sync` tool
   - Generates/updates service chart
   - Updates umbrella `Chart.yaml`

3. **PR created automatically**
   - Platform team reviews
   - Merges when approved

4. **Deployment**
   - Platform team deploys umbrella chart
   - All services deployed together

## Best Practices Enforced

The library chart enforces:

- ✅ Security contexts (non-root, read-only filesystem)
- ✅ Resource limits and requests
- ✅ Health checks (liveness/readiness probes)
- ✅ Proper labeling and annotations
- ✅ mTLS for service-to-service communication
- ✅ TLS certificates via cert-manager
- ✅ Horizontal Pod Autoscaling
- ✅ Service account best practices

## Examples

See `services/` directory for example configurations:
- `frontend/configuration.yml` - Web frontend with ingress, mTLS, certificates
- `backend/configuration.yml` - API backend with autoscaling
- `database/configuration.yml` - Database service without ingress

## Development

### Adding New Features to Library Chart

1. Update `platform-library/templates/` with new templates
2. Update `platform-library/values.yaml` with defaults
3. Update `_helpers.tpl` if needed
4. Test with example service configurations

### Testing

```bash
# Generate a test chart
cd chart-generator
python main.py \
  --config ../services/frontend/configuration.yml \
  --library ../platform-library \
  --output /tmp/test-frontend

# Validate generated chart
helm lint /tmp/test-frontend
helm template /tmp/test-frontend
```

## Jenkins Integration

This project includes complete Jenkins pipeline integration for automated CI/CD:

- **Jenkinsfile** - Complete pipeline definition
- **Jenkins on k3s** - Run Jenkins on the same k3s cluster
- **Automated testing** - Charts are deployed and tested automatically
- **Webhook support** - Automatic pipeline triggers on git push

### Quick Start with Jenkins

```bash
# Complete setup (k3s + Jenkins)
make jenkins-quickstart

# Access Jenkins
open http://localhost:30080

# Get admin password
make jenkins-password
```

See [JENKINS.md](JENKINS.md) and [INTEGRATION.md](INTEGRATION.md) for detailed documentation.

### Visual Diagrams

Comprehensive mermaid diagrams explaining all workflows and system architecture:
- **[DIAGRAMS.md](DIAGRAMS.md)** - Complete visual documentation with 12+ diagrams covering:
  - System architecture
  - Developer workflows
  - Chart generation process
  - Jenkins pipeline flow
  - Deployment flows
  - Component interactions
  - Error handling
  - And more...

## License

See LICENSE file for details.

