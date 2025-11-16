# Jenkins on k3s

This directory contains Kubernetes manifests for running Jenkins on a k3s cluster.

## Quick Start

### 1. Setup k3s Cluster

```bash
./scripts/setup-k3s.sh
```

### 2. Install Jenkins

```bash
./scripts/install-jenkins.sh
```

### 3. Access Jenkins

Jenkins will be available at:
- **URL**: http://localhost:30080
- **NodePort**: 30080

### 4. Get Admin Password

```bash
# Get Jenkins pod name
kubectl get pods -n jenkins

# Get admin password
kubectl exec -n jenkins <pod-name> -- cat /var/jenkins_home/secrets/initialAdminPassword
```

### 5. Configure Jenkins

1. Login with admin user and the password from step 4
2. Install recommended plugins
3. Create a new pipeline job:
   - Go to "New Item"
   - Select "Pipeline"
   - Configure:
     - **Pipeline definition**: Pipeline script from SCM
     - **SCM**: Git
     - **Repository URL**: Your repository URL
     - **Script Path**: `Jenkinsfile`

## Components

### Namespace
- `namespace.yaml` - Creates the `jenkins` namespace

### Service Account & RBAC
- `jenkins-rbac.yaml` - ServiceAccount with cluster-wide permissions for Jenkins

### Storage
- `jenkins-pvc.yaml` - PersistentVolumeClaim for Jenkins data (20Gi)

### Service
- `jenkins-service.yaml` - NodePort service exposing Jenkins on ports 30080 (HTTP) and 30050 (agent)

### Deployment
- `jenkins-deployment.yaml` - Jenkins LTS deployment with:
  - Java 17
  - Setup wizard disabled
  - Health checks
  - Resource limits

### Configuration
- `jenkins-config.yaml` - ConfigMap with Jenkins configuration:
  - Security realm
  - Kubernetes cloud configuration
  - Agent templates (jnlp, helm, kubectl, python)

## Jenkins Agent Pod Templates

The Jenkins configuration includes pod templates for:

1. **jnlp** - Jenkins agent base image
2. **helm** - Alpine Helm image for chart operations
3. **kubectl** - Bitnami kubectl image for Kubernetes operations
4. **python** - Python 3.11 for running chart generator scripts

## Pipeline Integration

The `Jenkinsfile` in the root directory is configured to:
1. Checkout code
2. Generate Helm charts from configurations
3. Deploy to k3s cluster
4. Run tests
5. Cleanup

## Troubleshooting

### Jenkins not starting

```bash
# Check pod status
kubectl get pods -n jenkins

# Check logs
kubectl logs -n jenkins -l app=jenkins

# Check events
kubectl get events -n jenkins --sort-by='.lastTimestamp'
```

### Cannot connect to cluster

```bash
# Verify kubeconfig
kubectl cluster-info

# Check service account permissions
kubectl auth can-i --list --as=system:serviceaccount:jenkins:jenkins
```

### PVC not bound

```bash
# Check PVC status
kubectl get pvc -n jenkins

# Check storage class
kubectl get storageclass
```

## Security Notes

- Jenkins runs with a ServiceAccount that has cluster-wide permissions
- In production, restrict permissions to specific namespaces
- Change default admin password after first login
- Enable authentication and authorization
- Use HTTPS with proper certificates

## Scaling

To scale Jenkins:

```bash
kubectl scale deployment jenkins -n jenkins --replicas=2
```

Note: Only one Jenkins instance should be active at a time unless using shared storage.

