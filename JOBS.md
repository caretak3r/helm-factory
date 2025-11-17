# Kubernetes Jobs Guide

This guide explains how to use pre-install and post-install Kubernetes Jobs in the Helm Chart Factory system.

## Overview

The platform library chart supports Kubernetes Jobs that run at specific points in the Helm deployment lifecycle:
- **Pre-install Jobs**: Run before the main deployment is created
- **Post-install Jobs**: Run after the main deployment is ready

Both job types use Helm hooks to ensure they run at the correct time.

## Use Cases

### Pre-install Jobs

Use pre-install jobs for:
- Database migrations
- Schema setup
- Pre-deployment validation
- Resource preparation
- Configuration checks

### Post-install Jobs

Use post-install jobs for:
- Smoke tests
- Health check verification
- Post-deployment validation
- Integration tests
- Notification sending

## Configuration

### Option 1: Inline Script (Recommended for Simple Scripts)

```yaml
job:
  # Pre-install job with inline script
  preInstall:
    enabled: true
    image:
      repository: busybox
      tag: "latest"
    script: |
      #!/bin/sh
      echo "Running pre-install setup"
      # Add your script commands here
      exit 0
  
  # Post-install job with inline script
  postInstall:
    enabled: true
    image:
      repository: busybox
      tag: "latest"
    script: |
      #!/bin/sh
      echo "Running post-install verification"
      # Add your script commands here
      exit 0
```

**Or as an array:**
```yaml
job:
  preInstall:
    enabled: true
    image:
      repository: busybox
      tag: "latest"
    script:
      - "#!/bin/sh"
      - "echo 'Running pre-install setup'"
      - "exit 0"
```

### Option 2: Script File from Repository (Recommended for Complex Scripts)

```yaml
job:
  # Pre-install job using script file
  preInstall:
    enabled: true
    image:
      repository: busybox
      tag: "latest"
    scriptFile: scripts/pre-install.sh  # Relative to repository root
  
  # Post-install job using script file
  postInstall:
    enabled: true
    image:
      repository: busybox
      tag: "latest"
    scriptFile: scripts/post-install.sh  # Relative to repository root
```

**Script file location:**
- Place script files in your repository (e.g., `scripts/pre-install.sh`)
- The chart generator will copy them to the generated chart
- Scripts are automatically mounted as ConfigMaps and executed

### Option 3: Custom Command and Args (Legacy)

```yaml
job:
  # Pre-install job
  preInstall:
    enabled: true
    image:
      repository: busybox
      tag: "latest"
    command:
      - /bin/sh
      - -c
    args:
      - echo "Running pre-install setup"
  
  # Post-install job
  postInstall:
    enabled: true
    image:
      repository: busybox
      tag: "latest"
    command:
      - /bin/sh
      - -c
    args:
      - echo "Running post-install verification"
```

### Advanced Configuration

```yaml
job:
  # Common settings (applied to both jobs)
  image:
    repository: myregistry/job-image
    tag: "v1.0.0"
    pullPolicy: IfNotPresent
  backoffLimit: 3
  completions: 1
  parallelism: 1
  restartPolicy: Never
  activeDeadlineSeconds: 300
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  
  # Pre-install job
  preInstall:
    enabled: true
    hookWeight: -5  # Lower weight = runs earlier
    # Override common settings if needed
    image:
      repository: myregistry/pre-install-job
      tag: "v1.0.0"
    command:
      - /bin/sh
      - -c
    args:
      - |
        echo "Running pre-install setup"
        # Add your pre-install logic here
    env:
      - name: NAMESPACE
        value: "platform"
      - name: DB_HOST
        value: "database"
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 1000m
        memory: 512Mi
  
  # Post-install job
  postInstall:
    enabled: true
    hookWeight: 5  # Higher weight = runs later
    # Override common settings if needed
    image:
      repository: myregistry/post-install-job
      tag: "v1.0.0"
    command:
      - /bin/sh
      - -c
    args:
      - |
        echo "Running post-install verification"
        # Add your post-install logic here
    env:
      - name: SERVICE_URL
        value: "http://frontend:80"
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

## Configuration Options

### Common Job Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `image.repository` | string | `""` | Container image repository |
| `image.tag` | string | `"latest"` | Container image tag |
| `image.pullPolicy` | string | `"IfNotPresent"` | Image pull policy |
| `backoffLimit` | int | `3` | Number of retries before marking job as failed |
| `completions` | int | `1` | Number of successful completions required |
| `parallelism` | int | `1` | Number of pods to run in parallel |
| `restartPolicy` | string | `"Never"` | Pod restart policy (Never or OnFailure) |
| `activeDeadlineSeconds` | int | `300` | Maximum time job can run (seconds) |
| `command` | array | `[]` | Container command (ignored if script/scriptFile is set) |
| `args` | array | `[]` | Container arguments (ignored if script/scriptFile is set) |
| `script` | string/array | `null` | Inline script content (creates ConfigMap) |
| `scriptFile` | string | `null` | Path to script file in repository (relative to repo root) |
| `env` | array | `[]` | Environment variables |
| `resources` | object | See defaults | Resource requests and limits |
| `volumeMounts` | array | `[]` | Volume mounts |
| `volumes` | array | `[]` | Volumes |

### Pre-install Job Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `preInstall.enabled` | bool | `false` | Enable pre-install job |
| `preInstall.hookWeight` | int | `-5` | Helm hook weight (lower = earlier) |

### Post-install Job Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `postInstall.enabled` | bool | `false` | Enable post-install job |
| `postInstall.hookWeight` | int | `5` | Helm hook weight (higher = later) |

## Examples

### Database Migration (Pre-install) - Using Inline Script

```yaml
job:
  preInstall:
    enabled: true
    image:
      repository: postgres
      tag: "15-alpine"
    script: |
      #!/bin/sh
      set -e
      echo "Running database migrations..."
      psql $DATABASE_URL -f /migrations/schema.sql
      echo "Migrations completed successfully"
    env:
      - name: DATABASE_URL
        valueFrom:
          secretKeyRef:
            name: db-secret
            key: url
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

### Database Migration (Pre-install) - Using Script File

**configuration.yml:**
```yaml
job:
  preInstall:
    enabled: true
    image:
      repository: postgres
      tag: "15-alpine"
    scriptFile: scripts/migrate-db.sh
    env:
      - name: DATABASE_URL
        valueFrom:
          secretKeyRef:
            name: db-secret
            key: url
```

**scripts/migrate-db.sh:**
```bash
#!/bin/sh
set -e
echo "Running database migrations..."
psql $DATABASE_URL -f /migrations/schema.sql
echo "Migrations completed successfully"
```

### Health Check Verification (Post-install)

```yaml
job:
  postInstall:
    enabled: true
    image:
      repository: curlimages/curl
      tag: "latest"
    command:
      - /bin/sh
      - -c
    args:
      - |
        echo "Verifying service health..."
        curl -f http://frontend:80/health || exit 1
        echo "Service is healthy!"
    env:
      - name: SERVICE_URL
        value: "http://frontend:80"
    resources:
      requests:
        cpu: 100m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 128Mi
```

### Both Pre-install and Post-install - Using Scripts

```yaml
job:
  preInstall:
    enabled: true
    image:
      repository: busybox
      tag: "latest"
    script: |
      #!/bin/sh
      echo "Pre-install: Setting up resources"
      # Add setup logic here
  
  postInstall:
    enabled: true
    image:
      repository: busybox
      tag: "latest"
    script: |
      #!/bin/sh
      echo "Post-install: Verifying deployment"
      # Add verification logic here
```

### Mixed: Inline Script + Script File

```yaml
job:
  preInstall:
    enabled: true
    image:
      repository: busybox
      tag: "latest"
    script: |
      #!/bin/sh
      echo "Quick pre-install check"
  
  postInstall:
    enabled: true
    image:
      repository: busybox
      tag: "latest"
    scriptFile: scripts/complex-verification.sh  # Use file for complex logic
```

### Using Volumes

```yaml
job:
  preInstall:
    enabled: true
    image:
      repository: myregistry/setup-job
      tag: "v1.0.0"
    command:
      - /bin/sh
      - -c
    args:
      - |
        echo "Setting up shared volume"
        echo "data" > /shared/data.txt
    volumeMounts:
      - name: shared-data
        mountPath: /shared
    volumes:
      - name: shared-data
        emptyDir: {}
```

## Helm Hooks

Jobs use Helm hooks to run at specific lifecycle points:

### Pre-install Hook
- **Hook**: `pre-install, pre-upgrade`
- **Weight**: `-5` (default, can be customized)
- **Delete Policy**: `before-hook-creation, hook-succeeded`
- **Runs**: Before the main deployment is created

### Post-install Hook
- **Hook**: `post-install, post-upgrade`
- **Weight**: `5` (default, can be customized)
- **Delete Policy**: `before-hook-creation, hook-succeeded`
- **Runs**: After the main deployment is ready

### Hook Weight

Hook weights control execution order:
- **Lower weights run first** (e.g., -10 runs before -5)
- **Higher weights run later** (e.g., 10 runs after 5)
- Use different weights if you have multiple pre-install or post-install jobs

## Job Lifecycle

1. **Pre-install Job**:
   - Runs before deployment
   - Must complete successfully for deployment to proceed
   - Deleted after successful completion

2. **Main Deployment**:
   - Created after pre-install job succeeds
   - Waits for pods to be ready

3. **Post-install Job**:
   - Runs after deployment is ready
   - Can verify deployment health
   - Deleted after successful completion

## Troubleshooting

### Job Not Running

**Check:**
- `enabled: true` is set
- Image repository and tag are correct
- Command/args are valid
- Resources are sufficient

**Debug:**
```bash
# Check job status
kubectl get jobs -n platform

# View job logs
kubectl logs job/<service-name>-preinstall -n platform
kubectl logs job/<service-name>-postinstall -n platform

# Describe job for events
kubectl describe job/<service-name>-preinstall -n platform
```

### Job Failing

**Common Issues:**
- Image pull errors → Check image repository and credentials
- Command errors → Verify command and args syntax
- Resource limits → Increase resources if needed
- Timeout → Increase `activeDeadlineSeconds`

**Debug:**
```bash
# Check job events
kubectl describe job/<service-name>-preinstall -n platform

# Check pod logs
kubectl logs job/<service-name>-preinstall -n platform

# Check pod status
kubectl get pods -n platform -l app.kubernetes.io/component=job-preinstall
```

### Job Running Multiple Times

**Cause:** Hook delete policy not set correctly

**Solution:** Ensure `hook-delete-policy` includes `hook-succeeded`:
```yaml
hookAnnotations:
  helm.sh/hook-delete-policy: "before-hook-creation,hook-succeeded"
```

## Best Practices

1. **Keep jobs idempotent** - Jobs should be safe to run multiple times
2. **Set appropriate timeouts** - Use `activeDeadlineSeconds` to prevent hanging jobs
3. **Use proper resources** - Don't over-allocate, but ensure sufficient resources
4. **Handle failures gracefully** - Set appropriate `backoffLimit`
5. **Use environment variables** - Pass configuration via env vars, not hardcoded values
6. **Test jobs independently** - Test job images before enabling in chart
7. **Monitor job execution** - Check job logs and status regularly
8. **Clean up completed jobs** - Jobs are auto-deleted, but verify cleanup

## Integration with Other Features

Jobs work seamlessly with:
- **Service Accounts** - Jobs use the same service account as the deployment
- **Security Contexts** - Jobs inherit pod and container security contexts
- **Volumes** - Jobs can mount volumes for shared data
- **Environment Variables** - Jobs can access the same env vars as deployments

## Limitations

- Jobs run as part of Helm release lifecycle
- Pre-install jobs block deployment if they fail
- Post-install jobs don't block deployment (run asynchronously)
- Jobs are deleted after successful completion (by default)
- Multiple jobs of the same type run in parallel (use hook weights for ordering)

