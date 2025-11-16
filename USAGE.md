# Usage Guide

## For Service Teams

### Creating a New Service Configuration

1. Create a directory for your service:
```bash
mkdir -p services/my-service
```

2. Create `configuration.yml`:
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

version: "0.1.0"
appVersion: "1.0.0"
```

3. Commit and push:
```bash
git add services/my-service/configuration.yml
git commit -m "Add my-service configuration"
git push
```

4. CI/CD will automatically:
   - Generate your Helm chart
   - Add it to the umbrella chart
   - Create a PR for review

### Updating Service Configuration

Simply edit `services/my-service/configuration.yml` and push. The system will automatically regenerate your chart and update the umbrella chart.

## For Platform Team

### Manual Chart Generation

```bash
# Generate a single service chart
cd chart-generator
python main.py \
  --config ../services/frontend/configuration.yml \
  --library ../platform-library \
  --output ../generated-charts/frontend \
  --name frontend
```

### Manual Umbrella Sync

```bash
# Sync all services to umbrella chart
cd umbrella-sync
python main.py \
  --umbrella ../umbrella-chart \
  --services ../services \
  --library ../platform-library \
  --generate-charts
```

### Deploying Umbrella Chart

```bash
cd umbrella-chart

# Update dependencies
helm dependency update

# Install/upgrade
helm upgrade --install platform . \
  --namespace platform \
  --create-namespace \
  --values values.yaml \
  --values values-frontend.yaml \
  --values values-backend.yaml \
  --values values-database.yaml
```

### Validating Generated Charts

```bash
# Lint a generated chart
helm lint generated-charts/frontend

# Dry-run template rendering
helm template generated-charts/frontend

# Test with values
helm template generated-charts/frontend \
  --values services/frontend/configuration.yml
```

## Configuration Reference

### Required Fields

- `service.name` - Service name (used for chart name)
- `deployment.image.repository` - Container image repository
- `deployment.image.tag` - Container image tag

### Optional Fields

#### Ingress
```yaml
ingress:
  enabled: true
  className: nginx
  annotations: {}
  hosts:
    - host: example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: tls-secret
      hosts:
        - example.com
```

#### mTLS
```yaml
mtls:
  enabled: true
  policy: STRICT  # STRICT, PERMISSIVE, or DISABLE
```

#### Certificates
```yaml
certificate:
  enabled: true
  issuer: letsencrypt-prod
  secretName: my-service-tls
```

#### Autoscaling
```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
```

#### Resources
```yaml
deployment:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

#### Health Checks
```yaml
deployment:
  livenessProbe:
    enabled: true
    path: /health
    port: 8080
    initialDelaySeconds: 30
    periodSeconds: 10
  readinessProbe:
    enabled: true
    path: /ready
    port: 8080
    initialDelaySeconds: 10
    periodSeconds: 5
```

## Troubleshooting

### Chart Generation Fails

**Error: Missing required fields**
- Ensure `service.name` and `deployment.image.repository` are set

**Error: Invalid YAML**
- Validate your `configuration.yml` syntax
- Use a YAML linter

### Umbrella Sync Issues

**No dependencies found**
- Check that `configuration.yml` files exist in `services/` subdirectories
- Verify `service.name` is set in each configuration

**Dependency update fails**
- Run `helm dependency update` in umbrella chart directory
- Check that generated charts are valid: `helm lint charts/<service-name>`

### Deployment Issues

**Resources not created**
- Check that library chart templates are correct
- Verify values are merged correctly: `helm template . --debug`

**Ingress not working**
- Verify ingress controller is installed
- Check ingress annotations are correct
- Validate certificate issuer exists

## Advanced Usage

### Custom Labels and Annotations

```yaml
labels:
  app.kubernetes.io/component: frontend
  team: platform

annotations:
  deployment.kubernetes.io/revision: "1"
  prometheus.io/scrape: "true"
```

### Environment Variables

Add to your configuration (will be merged into deployment template):
```yaml
deployment:
  env:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: url
```

### Service Account

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/my-role
```

