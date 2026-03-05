# platform-library

> Helm library chart for standardized Kubernetes deployments.

`platform-library` provides a single, opinionated set of Helm templates that generate all common Kubernetes resources from one configuration file. Service teams never write templates — they fill out `configuration.yaml` and the library renders everything.

## Overview

| Feature | Description |
|---------|-------------|
| Workloads | Deployment, StatefulSet, DaemonSet |
| Networking | Service, Ingress, Gateway API (HTTPRoute / GRPCRoute), NetworkPolicy |
| Scaling | HPA, PodDisruptionBudget |
| Security | PodSecurityContext, ContainerSecurityContext, mTLS (Istio), Certificates (cert-manager), TLS self-signed |
| Observability | ServiceMonitor, PodMonitor (Prometheus Operator) |
| Config/Secrets | ConfigMap, Secret, Environment Variables |
| Storage | PersistentVolumeClaim, VolumeClaimTemplates (StatefulSet) |
| Jobs | Pre/Post-install hooks, CronJob |
| HA | Pod anti-affinity presets, topology spread constraints |

## Quick Start

### 1. Add the dependency

```yaml
# Chart.yaml
apiVersion: v2
name: my-service
version: 1.0.0
dependencies:
  - name: platform-library
    version: "^1.0.0"
    repository: "oci://registry.example.com/charts"
    alias: platform
```

### 2. Configure your service

```yaml
# configuration.yaml
serviceName: my-service
image:
  repository: gcr.io/my-project/my-service
  tag: v1.0.0

service:
  enabled: true
  ports:
    - name: http
      port: 80
      targetPort: http

ingress:
  enabled: true
  hostname: my-service.example.com
```

### 3. Render and deploy

```bash
helm dependency update .
helm template my-service . -f configuration.yaml
helm install my-service . -f configuration.yaml
```

## Installation

The chart is a **library chart** (`type: library`). It cannot be installed directly. Add it as a dependency to your service chart as shown above.

The library uses the `exports.defaults` pattern — all values are merged into the parent chart's root scope automatically.

## Configuration Reference

### Naming

Control how resources are named.

```yaml
nameOverride: ""          # Override chart name portion
fullnameOverride: ""      # Override entire resource name (max 63 chars)
```

Resource names follow the pattern `<release>-<chart>` unless overridden. Names are truncated to 63 characters per Kubernetes limits.

### Global Settings

Shared settings that apply across all resources and subcharts.

```yaml
global:
  imageRegistry: ""         # Override registry for ALL images
  imagePullPolicy: ""       # Override pull policy for ALL images
  imagePullSecrets: []      # Pull secrets applied to ALL pods
  storageClass: ""          # Default storage class for ALL PVCs
```

Global values take precedence over local values when set.

### Workload Types

Choose one workload type per service.

```yaml
workload:
  type: Deployment    # Deployment | StatefulSet | DaemonSet
```

| Type | Use Case | Scaling | Storage |
|------|----------|---------|---------|
| `Deployment` | Stateless services | HPA, replicas | Shared PVC |
| `StatefulSet` | Databases, stateful apps | Replicas | Per-pod PVCs |
| `DaemonSet` | Node agents, log collectors | One per node | Node-local |

### Container Image

```yaml
image:
  registry: docker.io
  repository: myorg/myapp       # REQUIRED
  tag: v1.0.0                   # Recommend immutable tags
  digest: ""                    # sha256:... — overrides tag if set
  pullPolicy: IfNotPresent
  pullSecrets: []               # Merged with global.imagePullSecrets
```

### Replicas & Scaling

```yaml
replicaCount: 3
revisionHistoryLimit: 10
```

When `autoscaling.enabled: true`, `replicaCount` is ignored.

### Service

Expose pods via a Kubernetes Service.

```yaml
service:
  enabled: true
  type: ClusterIP               # ClusterIP | NodePort | LoadBalancer
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
  sessionAffinity: None
  annotations: {}
```

### Ingress

Route external traffic to the service via an Ingress controller.

```yaml
ingress:
  enabled: true
  ingressClassName: nginx
  hostname: api.example.com
  path: /
  pathType: Prefix
  tls: true
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
```

Additional hosts, paths, TLS configs, and custom rules:

```yaml
ingress:
  extraHosts:
    - name: admin.example.com
      path: /
  extraTls:
    - secretName: admin-tls
      hosts:
        - admin.example.com
```

### Gateway API

Modern alternative to Ingress using the [Gateway API](https://gateway-api.sigs.k8s.io/) standard. Supports HTTPRoute (GA) and GRPCRoute.

**Prerequisites:** Gateway API CRDs installed, a Gateway resource deployed.

```yaml
gatewayApi:
  enabled: true
  parentRefs:
    - name: my-gateway
      namespace: gateway-system
  httpRoute:
    enabled: true
```

This generates an HTTPRoute that:
- Attaches to the specified Gateway via `parentRefs`
- Uses `ingress.hostname` as the hostname (if `gatewayApi.hostnames` not set)
- Routes `ingress.path` to this service's primary port
- Auto-generates `backendRefs` targeting this service

#### Explicit Configuration

```yaml
gatewayApi:
  enabled: true
  apiVersion: gateway.networking.k8s.io/v1
  hostnames:
    - api.example.com
  parentRefs:
    - name: prod-gateway
      sectionName: https
  httpRoute:
    enabled: true
    matches:
      - path:
          type: PathPrefix
          value: /api/v2
    filters:
      - type: RequestHeaderModifier
        requestHeaderModifier:
          add:
            - name: X-Forwarded-Proto
              value: https
```

#### gRPC Routing

```yaml
gatewayApi:
  enabled: true
  parentRefs:
    - name: grpc-gateway
  grpcRoute:
    enabled: true
    matches:
      - method:
          service: myapp.v1.MyService
```

#### Advanced: specOverrides

Merge arbitrary fields into the generated spec:

```yaml
gatewayApi:
  httpRoute:
    enabled: true
    specOverrides:
      timeouts:
        request: 30s
        backendRequest: 20s
```

### High Availability

Spread pods across failure domains without writing complex affinity rules.

```yaml
highAvailability:
  enabled: true
  podAntiAffinityPreset: soft      # soft | hard
  podAffinityPreset: ""            # soft | hard
  nodeAffinityPreset:
    type: soft                     # soft | hard
    key: topology.kubernetes.io/zone
    values: [us-east-1a, us-east-1b]
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
```

| Preset | Behavior |
|--------|----------|
| `soft` | Best-effort (preferredDuringScheduling) |
| `hard` | Strict (requiredDuringScheduling) — may prevent scheduling if insufficient nodes |

### Horizontal Pod Autoscaler

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPU: 80
  targetMemory: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
```

### Probes

```yaml
startupProbe:
  enabled: true
  httpGet:
    path: /healthz
    port: http
  failureThreshold: 30
  periodSeconds: 10

livenessProbe:
  enabled: true
  httpGet:
    path: /healthz
    port: http

readinessProbe:
  enabled: true
  httpGet:
    path: /ready
    port: http
```

All probe types support `httpGet`, `tcpSocket`, `exec`, and `grpc`.

### Resources

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### Security Context

```yaml
podSecurityContext:
  enabled: true
  fsGroup: 1001

containerSecurityContext:
  enabled: true
  runAsUser: 1001
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

### Environment Variables

Three methods, composable together:

```yaml
# Inline key-value or valueFrom references
envVars:
  LOG_LEVEL: info
  DATABASE_URL:
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: url

# Bulk import from ConfigMap
envVarsConfigMap: my-config

# Bulk import from Secret
envVarsSecret: my-secrets
```

### ConfigMap

```yaml
configMap:
  enabled: true
  mounted: true                 # Mount as volume in container
  mountPath: /app/config
  data:
    config.yaml: |
      server:
        port: 8080
        debug: false
```

### Secret

```yaml
secret:
  enabled: true
  type: Opaque
  stringData:
    api-key: my-secret-value
```

### Persistence / Storage

```yaml
persistence:
  enabled: true
  mountPath: /data
  storageClass: fast-ssd
  accessModes: [ReadWriteOnce]
  size: 10Gi
```

For StatefulSets, use `volumeClaimTemplates` for per-pod storage:

```yaml
workload:
  type: StatefulSet
statefulSet:
  volumeClaimTemplates:
    - name: data
      storageClassName: fast-ssd
      accessModes: [ReadWriteOnce]
      storage: 10Gi
```

### Init Containers & Sidecars

```yaml
initContainers:
  enabled: true
  containers:
    - name: init-db
      image: busybox:1.36
      command: ['sh', '-c', 'until nc -z db 5432; do sleep 1; done']

sidecars:
  enabled: true
  containers:
    - name: log-collector
      image: fluent/fluent-bit:2.0
      volumeMounts:
        - name: varlog
          mountPath: /var/log
```

### Jobs (Pre/Post Install Hooks)

Run tasks before or after Helm install/upgrade.

```yaml
jobs:
  image:
    repository: myorg/migrations
    tag: v1.0.0
  preInstall:
    enabled: true
    script: |
      #!/bin/sh
      echo "Running database migrations..."
      /app/migrate up
    hookWeight: -5
  postInstall:
    enabled: true
    command: ["/bin/sh", "-c"]
    args: ["curl -X POST http://slack-webhook/notify"]
```

### CronJob

```yaml
cronJob:
  enabled: true
  schedule: "0 2 * * *"          # Daily at 2 AM
  concurrencyPolicy: Forbid
  containers:
    - name: cleanup
      image: myorg/cleanup:v1
      command: ["/app/cleanup"]
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
```

### mTLS (Istio)

Creates PeerAuthentication and AuthorizationPolicy resources.

```yaml
mtls:
  enabled: true
  policy: STRICT
  allowedPrincipals:
    - "cluster.local/ns/frontend/sa/frontend-sa"
    - "cluster.local/ns/api-gateway/sa/gateway-sa"
```

### Certificates (cert-manager)

```yaml
certificate:
  enabled: true
  issuer: letsencrypt-prod
  dnsNames:
    - api.example.com
    - "*.api.example.com"
  duration: 2160h
  renewBefore: 360h
```

### TLS (Self-Signed)

Generate self-signed certificates for development or internal services.

```yaml
tlsSelfSigned:
  enabled: true
  commonName: my-service.default.svc
  dnsNames:
    - my-service.default.svc
    - my-service.default.svc.cluster.local
  validityDays: 365
```

### Network Policy

```yaml
networkPolicy:
  enabled: true
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: database
      ports:
        - port: 5432
```

### Service Account

```yaml
serviceAccount:
  create: true
  name: ""                       # Auto-generated from fullname
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/myapp
```

### Service Monitor / Pod Monitor (Prometheus)

```yaml
serviceMonitor:
  enabled: true
  port: http
  path: /metrics
  interval: 30s
  labels:
    release: prometheus
```

```yaml
podMonitor:
  enabled: true
  port: http
  path: /metrics
  interval: 30s
```

### Pod Disruption Budget

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1
  # OR
  # maxUnavailable: 1
```

### Service Endpoints ConfigMap

For umbrella charts — creates a ConfigMap containing all subchart service endpoints.

```yaml
serviceEndpoints:
  enabled: true
```

### Volumes

Mount additional volumes beyond ConfigMap and PVC.

```yaml
extraVolumes:
  - name: tmp
    emptyDir: {}
  - name: certs
    secret:
      secretName: tls-certs

extraVolumeMounts:
  - name: tmp
    mountPath: /tmp
  - name: certs
    mountPath: /etc/tls
    readOnly: true
```

### Command / Args Override

```yaml
command: ["/bin/custom-entrypoint"]
args: ["--config", "/app/config/config.yaml"]
```

### Lifecycle Hooks

```yaml
lifecycleHooks:
  preStop:
    httpGet:
      path: /shutdown
      port: 8080
  postStart:
    exec:
      command: ["/bin/sh", "-c", "echo started"]
```

### Pod Scheduling

```yaml
nodeSelector:
  kubernetes.io/os: linux

tolerations:
  - key: dedicated
    operator: Equal
    value: gpu
    effect: NoSchedule

affinity: {}              # Overrides HA presets when set

priorityClassName: high-priority
terminationGracePeriodSeconds: 60
```

### Labels & Annotations

```yaml
# Applied to ALL resources
commonLabels:
  team: platform
commonAnnotations:
  owner: platform-team

# Applied to workload (Deployment/StatefulSet/DaemonSet) only
labels: {}
annotations: {}

# Applied to pods only
podLabels: {}
podAnnotations: {}
```

## Migrating from Ingress to Gateway API

Gateway API is the successor to Ingress. To migrate:

### 1. Keep both running during transition

```yaml
ingress:
  enabled: true
  hostname: api.example.com

gatewayApi:
  enabled: true
  parentRefs:
    - name: prod-gateway
  httpRoute:
    enabled: true
    # Inherits hostname from ingress.hostname automatically
```

### 2. Validate Gateway API routing works

```bash
helm template my-service . -f configuration.yaml | grep -A 20 "kind: HTTPRoute"
```

### 3. Disable Ingress

```yaml
ingress:
  enabled: false

gatewayApi:
  enabled: true
  hostnames:
    - api.example.com       # Now explicit since ingress is off
  parentRefs:
    - name: prod-gateway
  httpRoute:
    enabled: true
```

### Key differences

| Aspect | Ingress | Gateway API |
|--------|---------|-------------|
| API maturity | Stable (v1) | HTTPRoute GA (v1), GRPCRoute GA |
| Route types | HTTP only | HTTP, gRPC, TCP, TLS, UDP |
| Gateway ownership | Implicit | Explicit `parentRefs` |
| Multi-tenancy | Limited | Built-in via Gateway/Route separation |
| Header matching | Controller-specific annotations | Native spec support |

## Architecture

```
configuration.yaml          ← Service team edits this
        │
        ▼
platform-library/
├── values.yaml             ← Defaults (exports.defaults pattern)
├── templates/
│   ├── _app.yaml           ← Orchestrator (calls all templates)
│   ├── _helpers.tpl        ← Shared helpers (naming, labels, image, affinity)
│   ├── _deployment.yaml    ← Deployment workload
│   ├── _statefulset.yaml   ← StatefulSet workload
│   ├── _daemonset.yaml     ← DaemonSet workload
│   ├── _service.yaml       ← Service
│   ├── _ingress.yaml       ← Ingress
│   ├── _gateway-api.yaml   ← Gateway API (HTTPRoute / GRPCRoute)
│   ├── _hpa.yaml           ← HorizontalPodAutoscaler
│   ├── _pdb.yaml           ← PodDisruptionBudget
│   ├── _networkpolicy.yaml ← NetworkPolicy
│   ├── _configmap.yaml     ← ConfigMap
│   ├── _secret.yaml        ← Secret
│   ├── _certificate.yaml   ← cert-manager Certificate
│   ├── _mtls.yaml          ← Istio mTLS policies
│   ├── _tls-secrets.yaml   ← TLS secrets (provided certs)
│   ├── _tls-selfsigned.yaml ← Self-signed TLS generation
│   ├── _pvc.yaml           ← PersistentVolumeClaim
│   ├── _cronjob.yaml       ← CronJob
│   ├── _job-*.yaml         ← Pre/Post install hook Jobs
│   ├── _servicemonitor.yaml ← Prometheus ServiceMonitor
│   └── _podmonitor.yaml    ← Prometheus PodMonitor
```

**Rendering flow:** `_app.yaml` iterates through all features, checking `.enabled` flags, and includes the corresponding template. Every `_<name>.yaml` is a `define` block — the matching `<name>.yaml` (no underscore) is the wrapper that calls `include`.

## Contributing

See [CORE.md](CORE.md) for architecture details, known issues, and maintenance guidelines.

### Adding a new resource type

1. Create `platform-library/templates/_<resource>.yaml` with a `define "platform.<resource>"` block
2. Create `platform-library/templates/<resource>.yaml` wrapper: `{{- include "platform.<resource>" . }}`
3. Add the `include` call to `_app.yaml` guarded by `.Values.<resource>.enabled`
4. Add defaults to `values.yaml` under `exports.defaults`
5. Add documented config to `configuration.yaml`
6. Update `CORE.md` rendering order and directory listing

### Validation

```bash
helm lint platform-library/
helm template test platform-library/ -f configuration.yaml
```
