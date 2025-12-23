# Helm Library Chart Generator

A system for automatically generating Helm charts from service configuration files using a shared platform library chart.

## Quick Start

1. **Install dependencies:**
   ```bash
   ./setup.sh
   ```

2. **Create a service configuration file** (`service-config.yml`):
   ```yaml
   service:
     name: my-service
   deployment:
     image: my-registry/my-service:latest
     replicas: 2
   ```

3. **Generate your Helm chart:**
   ```bash
   cd chart-generator
   python main.py --config ../service-config.yml --library ../platform-library --output ../my-service-chart
   ```

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Service Config  │───▶│ Chart Generator  │───▶│ Generated Chart │
│ configuration.yml│    │ (Python Script)  │    │ My Service      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
                                              ┌─────────────────┐
                                              │ Platform Library│
                                              │ Best Practices   │
                                              └─────────────────┘
```

## Components

### Platform Library (`platform-library/`)
- **Type**: Library chart
- **Purpose**: Contains reusable Helm templates with platform best practices
- **Features**:
  - Deployments, StatefulSets, DaemonSets
  - Services, Ingress, Certificates
  - mTLS configuration
  - Service Accounts
  - Horizontal Pod Autoscaling
  - Pre/Post-install jobs

### Chart Generator (`chart-generator/main.py`)
- **Purpose**: Converts service configuration into complete Helm charts
- **Input**: `configuration.yml` file
- **Output**: Complete Helm chart that uses the platform library

## Configuration Example

```yaml
# service-config.yml
service:
  name: webapp
  namespace: production

deployment:
  image: nginx:1.21
  replicas: 3
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

service:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 8080

ingress:
  enabled: true
  hosts:
    - webapp.example.com
  paths:
    - path: /
      pathType: Prefix

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

## Usage

Service teams only need to maintain a single `configuration.yml` file with their service specifications. The chart generator will:

1. Validate the configuration
2. Merge with platform library defaults
3. Generate a complete Helm chart
4. Include the platform library as a dependency

The generated chart includes all Kubernetes resources needed for the service following platform best practices.

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

# Workload type: Deployment (default), StatefulSet, or DaemonSet
workload:
  type: Deployment

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

- **Multiple Workload Types**:
  - **Deployment** (default) - For stateless applications
  - **StatefulSet** - For stateful applications with persistent storage
  - **DaemonSet** - For node-level agents

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

- **Jobs** with Helm hooks:
  - Pre-install jobs (run before deployment)
  - Post-install jobs (run after deployment)
  - Configurable hook weights for ordering
  - Automatic cleanup after completion

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
- ✅ Horizontal Pod Autoscaling (Deployment and StatefulSet)
- ✅ Service account best practices
- ✅ Multiple workload types (Deployment, StatefulSet, DaemonSet)
- ✅ Pre-install and Post-install Jobs (Helm hooks)

## Examples

See `services/` directory for example configurations:
- `frontend/configuration.yml` - Web frontend with ingress, mTLS, certificates (Deployment)
- `backend/configuration.yml` - API backend (Deployment)
- `database/configuration.yml` - Database service with StatefulSet and persistent storage (includes job examples)

For detailed job configuration examples, see [JOBS.md](JOBS.md).

## Development

### Adding New Features to Library Chart

1. Update `platform-library/templates/` with new templates
2. Update `platform-library/values.yaml` with defaults
3. Update `_helpers.tpl` if needed
4. Test with example service configurations

### Workload Types

See [WORKLOAD_TYPES.md](WORKLOAD_TYPES.md) for detailed information about:
- When to use each workload type (Deployment, StatefulSet, DaemonSet)
- Configuration examples
- Migration guides
- Best practices

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

- **Jenkinsfile.service** - Pipeline for individual service repositories
- **Jenkinsfile.umbrella** - Pipeline for umbrella chart repository
- **Jenkins on k3s** - Run Jenkins on the same k3s cluster
- **Automated testing** - Charts are deployed and tested automatically
- **Webhook support** - Automatic pipeline triggers on git push
- **Multi-repository support** - Works with separate GitHub repositories

### Repository Structure

The system uses multiple GitHub repositories:
- **platform-library** - Platform team's library chart
- **service repositories** - Each service has its own repo (frontend-service, backend-service, etc.)
- **umbrella-chart** - Umbrella chart repository
- **helm-chart-factory** - This repository with tools and documentation

### Pull Request Workflow

The system uses a PR-based workflow:
1. **Service Changes**: Developer updates `configuration.yml` and creates PR in service repo
2. **Service PR Merged**: Triggers service pipeline which creates PR to umbrella-chart repo
3. **Umbrella PR Created**: Triggers umbrella pipeline for validation (no deployment)
4. **Umbrella PR Merged**: Triggers umbrella pipeline for deployment to k3s

See [REPOSITORY_STRUCTURE.md](REPOSITORY_STRUCTURE.md), [REPOSITORY_SETUP.md](REPOSITORY_SETUP.md), and [PR_WORKFLOW.md](PR_WORKFLOW.md) for detailed setup instructions and workflow documentation.

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

### Architecture Decision Records

Documentation of key architectural decisions and their rationale:
- **[ADR.md](ADR.md)** - Architecture Decision Records covering:
  - Library chart pattern for standardization
  - Multi-repository architecture
  - Configuration-driven chart generation
  - Pull request-based workflow
  - Multiple workload types support
  - Stage toggles for pipeline flexibility
  - Umbrella chart orchestration
  - Local development with k3s

### Visual Diagrams

Comprehensive mermaid diagrams explaining all workflows and system architecture:
- **[DIAGRAMS.md](DIAGRAMS.md)** - Complete visual documentation with 15+ diagrams covering:
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

