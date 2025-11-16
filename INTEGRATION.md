# Complete Integration Guide

This guide walks through the complete end-to-end flow from developer submission to deployment.

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Developer Workflow                        │
│                                                              │
│  1. Edit configuration.yml                                  │
│  2. Commit & Push                                            │
│  3. Webhook triggers Jenkins                                 │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                  Jenkins Pipeline (on k3s)                   │
│                                                              │
│  • Validate configurations                                   │
│  • Generate Helm charts                                      │
│  • Lint & template charts                                    │
│  • Deploy to k3s cluster                                     │
│  • Run tests                                                 │
│  • Report results                                            │
└─────────────────────────────────────────────────────────────┘
```

## Complete Setup

### Prerequisites

- macOS/Linux system
- sudo access
- Internet connection
- ~10GB free disk space

### Step 1: Clone and Setup

```bash
# Clone repository
git clone <your-repo-url>
cd factory

# Run quickstart (sets up everything)
make jenkins-quickstart

# Or step by step:
make setup-k3s
make install-jenkins
```

### Step 2: Access Jenkins

```bash
# Get admin password
make jenkins-password

# Access Jenkins
open http://localhost:30080
# Or: kubectl port-forward -n jenkins svc/jenkins 8080:8080
```

### Step 3: Create Pipeline Job

1. Login to Jenkins (admin / password from step 2)
2. Click "New Item"
3. Name: `helm-chart-factory`
4. Type: Pipeline
5. Configure:
   - **Pipeline definition**: Pipeline script from SCM
   - **SCM**: Git
   - **Repository URL**: `file:///Users/rohit/Documents/questionable/factory` (or your repo URL)
   - **Script Path**: `Jenkinsfile`
6. Save

### Step 4: Run Pipeline

1. Click "Build Now"
2. Watch console output
3. Verify deployment

## Developer Workflow

### Adding a New Service

1. **Create configuration**:
```bash
mkdir -p services/my-new-service
cat > services/my-new-service/configuration.yml <<EOF
service:
  name: my-new-service
  type: ClusterIP
  port: 80
  targetPort: 8080

deployment:
  replicas: 2
  image:
    repository: myregistry/my-new-service
    tag: "v1.0.0"
    pullPolicy: IfNotPresent
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

version: "0.1.0"
appVersion: "1.0.0"
EOF
```

2. **Commit and push**:
```bash
git add services/my-new-service/configuration.yml
git commit -m "Add my-new-service configuration"
git push
```

3. **Pipeline runs automatically** (if webhook configured) or trigger manually

4. **Verify deployment**:
```bash
kubectl get pods -n platform
kubectl get svc -n platform
```

### Updating a Service

1. Edit `services/<service-name>/configuration.yml`
2. Commit and push
3. Pipeline regenerates chart and redeploys

### Updating Library Chart

1. Edit `platform-library/templates/*.yaml`
2. Commit and push
3. Pipeline regenerates all service charts with new templates

## Pipeline Stages Explained

### 1. Checkout
- Clones repository
- Checks out the branch that triggered the build

### 2. Setup Environment
- Installs Python dependencies (uv, click, pyyaml, rich)
- Verifies Helm installation

### 3. Validate Configurations
- Validates all `configuration.yml` files
- Checks required fields (service.name, deployment.image.repository)
- Exits early if validation fails

### 4. Generate Charts
- Runs chart-generator for each service
- Creates Helm charts in `generated-charts/`

### 5. Lint Charts
- Runs `helm lint` on all generated charts
- Catches template errors early

### 6. Template Charts
- Renders templates to `rendered-manifests/`
- Allows review of generated Kubernetes resources

### 7. Setup k3s Cluster
- Ensures k3s is running
- Waits for cluster to be ready
- Creates namespace

### 8. Install Dependencies
- Installs cert-manager (for certificates)
- Installs ingress-nginx (for ingress)

### 9. Sync Umbrella Chart
- Updates umbrella chart dependencies
- Generates service charts
- Updates Chart.yaml

### 10. Deploy to k3s
- Runs `helm upgrade --install`
- Waits for all resources
- Uses atomic flag for rollback on failure

### 11. Verify Deployment
- Checks all deployments are available
- Verifies pods are running
- Checks services and ingress

### 12. Run Tests
- Executes smoke tests
- Verifies pod health
- Checks service endpoints

## Testing Locally

### Manual Testing

```bash
# Setup
make setup

# Generate charts
make generate-all

# Sync umbrella
make sync

# Deploy locally
cd umbrella-chart
helm dependency update
helm upgrade --install platform . --namespace platform --create-namespace

# Test
./scripts/run-tests.sh platform
```

### Pipeline Testing

```bash
# Validate pipeline config
./scripts/validate-pipeline.sh

# Run individual stages manually
# (see Jenkinsfile for commands)
```

## Monitoring

### View Pipeline Status

```bash
# Jenkins UI
open http://localhost:30080

# Or CLI
kubectl get pods -n jenkins
kubectl logs -n jenkins -l app=jenkins
```

### View Deployments

```bash
# All resources
kubectl get all -n platform

# Specific service
kubectl get all -n platform -l app.kubernetes.io/name=frontend

# Pod logs
kubectl logs -n platform -l app.kubernetes.io/name=frontend
```

### View Events

```bash
kubectl get events -n platform --sort-by='.lastTimestamp'
```

## Troubleshooting

### Pipeline Fails at Setup

```bash
# Check Jenkins logs
make jenkins-logs

# Check Python installation
kubectl exec -n jenkins <pod> -- python3 --version
```

### Charts Fail to Deploy

```bash
# Check Helm release
helm list -n platform
helm status platform -n platform

# Check failed resources
kubectl get all -n platform
kubectl describe deployment -n platform

# View events
kubectl get events -n platform
```

### k3s Issues

```bash
# Check k3s status
sudo systemctl status k3s

# Restart k3s
sudo systemctl restart k3s

# Check nodes
kubectl get nodes
```

### Jenkins Issues

```bash
# Check Jenkins pod
kubectl get pods -n jenkins

# View logs
kubectl logs -n jenkins -l app=jenkins

# Restart Jenkins
kubectl rollout restart deployment/jenkins -n jenkins
```

## Webhook Configuration

### GitHub Webhook

1. Repository → Settings → Webhooks
2. Add webhook:
   - URL: `http://<jenkins-url>:30080/github-webhook/`
   - Content type: `application/json`
   - Events: Push
   - Active: ✓

### GitLab Webhook

1. Repository → Settings → Webhooks
2. Add webhook:
   - URL: `http://<jenkins-url>:30080/project/helm-chart-factory`
   - Trigger: Push events
   - Active: ✓

## Advanced Usage

### Custom Jenkins Agents

Edit `jenkins/jenkins-config.yaml` to add custom pod templates:

```yaml
templates:
  - name: "custom-agent"
    label: "custom"
    containers:
      - name: "custom-tool"
        image: "custom/image:tag"
```

### Multi-Environment

Create separate namespaces:

```bash
kubectl create namespace staging
kubectl create namespace production
```

Update Jenkinsfile to deploy to different namespaces based on branch.

### Blue/Green Deployments

Modify pipeline to:
1. Deploy to blue namespace
2. Run tests
3. Switch traffic to blue
4. Keep green as backup

### Rollback

```bash
# Rollback Helm release
helm rollback platform -n platform

# Or specific revision
helm rollback platform <revision> -n platform
```

## Security Considerations

1. **RBAC**: Jenkins service account has cluster-wide permissions
2. **Secrets**: Store sensitive data in Kubernetes secrets
3. **Network Policies**: Restrict pod-to-pod communication
4. **TLS**: Use TLS for Jenkins and ingress
5. **Authentication**: Enable proper Jenkins authentication
6. **Image Security**: Scan container images for vulnerabilities

## Performance Optimization

1. **Parallel Stages**: Run chart generation in parallel
2. **Caching**: Cache Python dependencies
3. **Resource Limits**: Set appropriate limits
4. **Node Affinity**: Pin Jenkins to specific nodes
5. **PVC Size**: Adjust PVC size based on usage

## Next Steps

- [ ] Set up monitoring (Prometheus/Grafana)
- [ ] Configure notifications (Slack/Email)
- [ ] Add security scanning
- [ ] Implement blue/green deployments
- [ ] Add staging/production environments
- [ ] Set up backup/restore procedures
- [ ] Document runbooks
- [ ] Create dashboards

