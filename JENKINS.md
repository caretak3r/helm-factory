# Jenkins Pipeline Integration

This document describes how to set up and use Jenkins pipelines for the Helm Chart Factory.

## Architecture

```
Developer commits config.yml
    ↓
GitHub/GitLab Webhook
    ↓
Jenkins Pipeline (on k3s)
    ↓
Generate Charts → Deploy to k3s → Test → Report
```

## Prerequisites

- k3s cluster running
- kubectl configured
- Helm installed (or use k3s bundled version)
- Python 3.11+ with uv

## Setup Instructions

### 1. Setup k3s Cluster

```bash
# Run the setup script
./scripts/setup-k3s.sh

# Verify cluster is running
kubectl get nodes
```

### 2. Install Cluster Dependencies

The pipeline will automatically install these, but you can pre-install:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Install ingress-nginx
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
```

### 3. Install Jenkins

```bash
# Install Jenkins on k3s
./scripts/install-jenkins.sh

# Wait for Jenkins to be ready
kubectl wait --for=condition=ready pod -l app=jenkins -n jenkins --timeout=300s
```

### 4. Access Jenkins

```bash
# Get admin password
JENKINS_POD=$(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n jenkins $JENKINS_POD -- cat /var/jenkins_home/secrets/initialAdminPassword

# Access Jenkins
open http://localhost:30080
# Or: kubectl port-forward -n jenkins svc/jenkins 8080:8080
```

### 5. Configure Jenkins Pipeline

1. **Login to Jenkins** (admin / password from step 4)

2. **Create Pipeline Job**:
   - Click "New Item"
   - Enter job name: `helm-chart-factory`
   - Select "Pipeline"
   - Click OK

3. **Configure Pipeline**:
   - **Pipeline definition**: Pipeline script from SCM
   - **SCM**: Git
   - **Repository URL**: Your repository URL (or file:// path for local)
   - **Credentials**: Add if needed
   - **Branch**: `*/main` or `*/master`
   - **Script Path**: `Jenkinsfile`
   - Click Save

4. **Configure Kubernetes Cloud** (if not auto-configured):
   - Manage Jenkins → Configure System
   - Cloud → Kubernetes
   - Kubernetes URL: `https://kubernetes.default`
   - Namespace: `jenkins`
   - Test Connection

### 6. Run Pipeline

1. Click "Build Now" on your pipeline job
2. Watch the build progress
3. Check console output for details

## Pipeline Stages

The `Jenkinsfile` includes these stages:

1. **Checkout** - Clone repository
2. **Setup Environment** - Install Python dependencies
3. **Validate Configurations** - Validate all `configuration.yml` files
4. **Generate Charts** - Generate Helm charts for all services
5. **Lint Charts** - Run `helm lint` on all charts
6. **Template Charts** - Render templates for review
7. **Setup k3s Cluster** - Ensure k3s is running
8. **Install Dependencies** - Install cert-manager, ingress-nginx
9. **Sync Umbrella Chart** - Update umbrella chart dependencies
10. **Deploy to k3s** - Install/upgrade charts on cluster
11. **Verify Deployment** - Check all resources are ready
12. **Run Tests** - Execute smoke tests

## Testing Locally

You can test the pipeline locally using Jenkins CLI or by running stages manually:

```bash
# Setup environment
cd chart-generator && uv pip install -r requirements.txt
cd ../umbrella-sync && uv pip install -r requirements.txt

# Validate configurations
python3 -c "
import yaml
from pathlib import Path
for f in Path('services').rglob('configuration.yml'):
    yaml.safe_load(open(f))
"

# Generate charts
for config in services/*/configuration.yml; do
    service=$(basename $(dirname $config))
    cd chart-generator
    python main.py --config "../$config" --library ../platform-library --output "../generated-charts/$service"
    cd ..
done

# Lint charts
for chart in generated-charts/*/; do
    helm lint "$chart"
done

# Deploy to k3s
cd umbrella-sync
python main.py --umbrella ../umbrella-chart --services ../services --library ../platform-library
cd ../umbrella-chart
helm dependency update
helm upgrade --install platform . --namespace platform --create-namespace --wait
```

## Jenkins Agent Configuration

The Jenkins configuration includes Kubernetes pod templates for:

- **jnlp** - Base Jenkins agent
- **helm** - For Helm operations
- **kubectl** - For Kubernetes operations  
- **python** - For running Python scripts

These are automatically used by the pipeline.

## Webhook Configuration

To trigger pipelines on git push:

### GitHub Webhook

1. Go to repository Settings → Webhooks
2. Add webhook:
   - **Payload URL**: `http://your-jenkins-url:30080/github-webhook/`
   - **Content type**: `application/json`
   - **Events**: Push events
   - **Active**: ✓

### GitLab Webhook

1. Go to repository Settings → Webhooks
2. Add webhook:
   - **URL**: `http://your-jenkins-url:30080/project/helm-chart-factory`
   - **Trigger**: Push events
   - **Active**: ✓

## Monitoring

### View Pipeline Status

```bash
# Get Jenkins service URL
kubectl get svc jenkins -n jenkins

# Port forward for local access
kubectl port-forward -n jenkins svc/jenkins 8080:8080
```

### Check Deployment Status

```bash
# View all resources
kubectl get all -n platform

# View pod logs
kubectl logs -n platform -l app.kubernetes.io/managed-by=Helm

# View events
kubectl get events -n platform --sort-by='.lastTimestamp'
```

## Troubleshooting

### Pipeline Fails at Setup

```bash
# Check Jenkins logs
kubectl logs -n jenkins -l app=jenkins --tail=100

# Check if Python/uv is available
kubectl exec -n jenkins <pod> -- which python3
```

### Charts Fail to Deploy

```bash
# Check Helm release status
helm list -n platform

# Check failed resources
kubectl get all -n platform

# View Helm release history
helm history platform -n platform
```

### k3s Not Accessible

```bash
# Check k3s status
sudo systemctl status k3s

# Restart k3s
sudo systemctl restart k3s

# Check kubeconfig
kubectl cluster-info
```

### Jenkins Cannot Connect to Cluster

```bash
# Verify service account permissions
kubectl auth can-i --list --as=system:serviceaccount:jenkins:jenkins

# Check RBAC
kubectl get clusterrolebinding jenkins
```

## Best Practices

1. **Use Secrets** - Store sensitive data in Kubernetes secrets
2. **Resource Limits** - Set appropriate limits for Jenkins and agents
3. **Backup** - Regularly backup Jenkins PVC
4. **Monitoring** - Set up monitoring for Jenkins and deployments
5. **Security** - Use RBAC, network policies, and TLS
6. **Testing** - Run tests in isolated namespaces
7. **Cleanup** - Clean up test namespaces after runs

## Advanced Configuration

### Custom Jenkins Image

Build a custom Jenkins image with pre-installed tools:

```dockerfile
FROM jenkins/jenkins:lts-jdk17
USER root
RUN apt-get update && apt-get install -y \
    python3 python3-pip \
    helm kubectl
USER jenkins
```

### Pipeline Libraries

Create a shared pipeline library for reusable steps:

```groovy
// vars/generateChart.groovy
def call(configPath, libraryPath, outputPath) {
    sh """
        cd chart-generator
        python main.py \
            --config $configPath \
            --library $libraryPath \
            --output $outputPath
    """
}
```

### Multi-Branch Pipelines

Configure Jenkinsfile for multi-branch:

```groovy
pipeline {
    agent any
    // ... rest of pipeline
}
```

Then create a "Multibranch Pipeline" job that scans branches.

## CI/CD Flow Example

```
Developer Workflow:
1. Edit services/my-service/configuration.yml
2. Commit and push
3. Webhook triggers Jenkins
4. Pipeline runs automatically
5. Charts deployed to k3s
6. Tests run
7. Results reported

Platform Team Workflow:
1. Update platform-library templates
2. Commit and push
3. All service charts regenerate
4. Umbrella chart updates
5. Full deployment tested
```

## Next Steps

- Set up monitoring (Prometheus/Grafana)
- Configure notifications (Slack/Email)
- Add security scanning (Trivy/Snyk)
- Implement blue/green deployments
- Add rollback capabilities
- Set up staging/production environments

