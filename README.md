# platform-library

> Capability-gated Helm common library — the basis for generating product charts.

`platform-library` (chart name `platform`, `type: library`, **v2**) is a **pure** Helm library chart: it ships no installable templates of its own. Product charts depend on it and render everything through a single entrypoint, `platform.render`. Service teams never write manifests — they set values and the library generates the resources.

**Two things make v2 different from an ordinary helper library:**

1. **Capability gates.** Every generator negotiates the best `apiVersion` the target cluster actually serves (e.g. `autoscaling/v2` → `v2beta2`) and **silently skips** CRD-backed objects whose API is absent — so a rendered chart never conflicts on deploy. Built-in Kinds always render with their best version; CRD/optional Kinds skip when missing. See [`docs/specs/platform-library-v2-architecture.md`](docs/specs/platform-library-v2-architecture.md).
2. **Comprehensive coverage.** Beyond the opinionated primary-app objects below, `extraObjects` renders *any* Kubernetes Kind (RBAC, StorageClass, PriorityClass, admission webhooks, CRDs, …) through one capability-gated generic renderer, and `extraManifests` is a raw escape hatch.

Targets **Kubernetes 1.31–1.36** and **Helm 4.0+**. Migrating from v1? See [`docs/migration/v1-to-v2.md`](docs/migration/v1-to-v2.md).

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
| **Everything else** | **`extraObjects` (any Kind, capability-gated) + `extraManifests` (raw)** |

## Quick Start

### Fastest: scaffold a new chart

```bash
scripts/new-app-chart.sh my-service --repo oci://ghcr.io/caretak3r/charts --version "^2.0.0"
helm dependency update my-service
helm template my-service my-service
```

This generates a chart already wired to the library (dependency + `import-values`, an entrypoint template, an overrides-only `values.yaml`, and a `values.schema.json`). Or do it by hand:

### 1. Add the dependency

```yaml
# Chart.yaml
apiVersion: v2
name: my-service
version: 1.0.0
dependencies:
  - name: platform                     # the chart name, not "platform-library"
    version: "^2.0.0"
    repository: "oci://ghcr.io/caretak3r/charts"
    import-values:                     # REQUIRED — without this the library
      - defaults                       # defaults never reach your root values
```

### 2. Add the entrypoint template

The library is pure; your chart renders it. Create exactly one template:

```yaml
# templates/app.yaml
{{ include "platform.render" . }}
```

### 3. Configure your service

```yaml
# values.yaml  (values land at the root because of import-values: [defaults])
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

# When rendering in CI (no cluster), force-assume CRD groups you use so their
# objects are not skipped:
# capabilities:
#   apiVersions: [cert-manager.io/v1, monitoring.coreos.com/v1]
```

### 4. Render and deploy

```bash
helm dependency update .
helm template my-service .
helm install my-service .
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

A **tag or digest is required** — there is no `latest` fallback, and rendering
fails with a clear error when neither is set. **Digest is the preferred pin**
(immutable, survives tag mutation, exact rollbacks); when both are set the
digest wins.

```yaml
image:
  registry: docker.io
  repository: myorg/myapp       # REQUIRED
  tag: v1.0.0                   # REQUIRED unless digest is set; quote numeric tags
  digest: ""                    # sha256:... — preferred pin, overrides tag if set
  pullPolicy: IfNotPresent
  pullSecrets: []               # Merged with global.imagePullSecrets
```

### Replicas & Scaling

```yaml
replicaCount: 3
revisionHistoryLimit: 10
minReadySeconds: 0             # Deployment/StatefulSet/DaemonSet; 0 omits the field (Kubernetes default)
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

`ingress.tls` defaults to `false` and is deliberately not flipped: when `true`, the Ingress
references `ingress.existingSecret` or the conventional `<hostname>-tls` Secret, which **must be
provisioned** — by cert-manager (the `certificate` block or a cert-manager ingress annotation),
`ingress.existingSecret`, or `ingress.secrets`. Enabling an ingress hostname without TLS prints an
install-time `WARNING:` in the release notes.

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

> **TLS secrets:** prefer cert-manager (see the `certificate` block) or a pre-created Secret via
> `ingress.existingSecret`. `ingress.secrets` embeds raw cert/key material in values — same caveats
> as `secret.stringData` above.

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

Pod and container security contexts are **enabled by default**, and the defaults
target the [Pod Security Standards `restricted`](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
profile: non-root user, no privilege escalation, all capabilities dropped,
`RuntimeDefault` seccomp, and a read-only root filesystem. The same contexts are
applied to the main workload, CronJob, and pre/post-install hook Job pods.

```yaml
podSecurityContext:
  enabled: true                  # set false to emit no pod securityContext at all
  fsGroup: 1001
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  enabled: true                  # set false to emit no container securityContext at all
  runAsUser: 1001
  runAsNonRoot: true
  readOnlyRootFilesystem: true   # apps that write to / must opt out or mount an emptyDir
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
  seccompProfile:
    type: RuntimeDefault
```

Every key except `enabled` is rendered verbatim, so individual fields can be
overridden without disabling the whole block. User-supplied `sidecars`,
`initContainers`, and `cronJob.containers` are rendered verbatim and must bring
their own `securityContext`.

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

> **Warning — secrets in values are plaintext.** Anything under `secret.data`/`secret.stringData`
> (and raw cert/key material under `ingress.secrets`) ends up in your values files (git) and in the
> Helm release manifest (a Secret in the release namespace). For production, create the Secret
> out-of-band — [External Secrets Operator](https://external-secrets.io/),
> [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets), or SOPS — and point the chart at
> it with `secret.existingSecret`. The chart then renders **no** Secret.

```yaml
# Recommended: reference a pre-created Secret
secret:
  existingSecret: my-app-secrets   # chart renders no Secret; conflicts with data/stringData
envVarsSecret: my-app-secrets      # bulk-import it as environment variables

# Dev/test only: chart-managed Secret from values
secret:
  enabled: true
  type: Opaque
  stringData:
    api-key: my-secret-value
```

The chart-managed Secret is named `<fullname>-secret`; it is not mounted or injected
automatically — reference it explicitly via `envVarsSecret` or `envVars` `valueFrom`.
For TLS, the equivalent pattern already exists: `ingress.existingSecret` (see Ingress).

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

By default PVCs from `volumeClaimTemplates` are never auto-deleted (Kubernetes'
implicit `Retain`/`Retain`). To reclaim them on scale-down or StatefulSet
deletion, set `persistentVolumeClaimRetentionPolicy` (valid values: `Retain`,
`Delete`):

```yaml
statefulSet:
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain
    whenScaled: Delete
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

`jobs.image` inherits from the main `image:` block: an empty `repository`
inherits the main repository, and when neither `jobs.image.tag` nor
`jobs.image.digest` is set the main pin is inherited (the main **digest** is
only inherited when the repositories match — digests are repository-specific).
If the effective hook image ends up with neither a tag nor a digest, rendering
fails.

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

**Fail-closed:** when `mtls.enabled: true`, `allowedPrincipals` must list the SPIFFE
principals allowed to call this workload — rendering fails otherwise. The easy
same-namespace default is `cluster.local/ns/<your-namespace>/sa/*`.

```yaml
mtls:
  enabled: true
  policy: STRICT
  allowedPrincipals:
    - "cluster.local/ns/frontend/sa/frontend-sa"
    - "cluster.local/ns/api-gateway/sa/gateway-sa"
```

To explicitly allow **every** workload in the mesh (mutual TLS with no meaningful
authorization — the pre-2.x behavior), opt in with:

```yaml
mtls:
  enabled: true
  allowAllPrincipals: true   # renders principal "cluster.local/ns/*/sa/*"
```

### Certificates (cert-manager)

```yaml
certificate:
  enabled: true
  issuer: letsencrypt-prod
  issuerKind: ClusterIssuer      # ClusterIssuer (default) | Issuer (namespaced, multi-tenant)
  dnsNames:
    - api.example.com
    - "*.api.example.com"
  duration: 2160h
  renewBefore: 360h
```

### TLS (Self-Signed) — dev only

> **Dev-only.** For production TLS use the [cert-manager `certificate` block](#certificates-cert-manager),
> which handles issuance, renewal, and rotation properly.

Generates a self-signed CA and certificate into the Secret `<fullname>-tls`.
On `helm install`/`helm upgrade` against a real cluster the chart **looks up the
existing Secret and reuses its `tls.crt`/`tls.key`/`ca.crt`**, so the CA and key
are stable across upgrades. Under `helm template` or client-side `--dry-run`
Helm's `lookup` returns nothing, so a fresh throwaway certificate is generated
on every render — fine for dev/CI, and another reason not to rely on this in
production. To force rotation, delete the Secret and upgrade.

```yaml
tlsSelfSigned:
  enabled: true
  commonName: my-service.default.svc
  dnsNames:
    - my-service.default.svc
    - my-service.default.svc.cluster.local
  validityDays: 365   # only applies when the cert is (re)generated
```

### Network Policy

> **Default-deny footgun:** `networkPolicy.enabled: true` with empty `ingress`/`egress` rules
> renders a policy that selects the app pods with `policyTypes: [Ingress, Egress]` and no allow
> rules — i.e. **all traffic to and from the pods is denied, including DNS**. That is a valid
> hardening baseline, but if it is not what you meant, add allow rules like the example below.
> An install-time `WARNING:` is printed in the release notes when this shape is detected.

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

A dedicated ServiceAccount is created by default (`create: true`) and the API
token is **not** mounted (`automountServiceAccountToken: false` is set on both
the ServiceAccount and every pod spec). Pods also run with
`enableServiceLinks: false`. Apps that call the Kubernetes API must opt in:

```yaml
serviceAccount:
  create: true
  name: ""                       # Auto-generated from fullname
  automountServiceAccountToken: true   # only if the app talks to the API server
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/myapp
```

> **Pre-install hooks caveat:** hook Job pods run under the same ServiceAccount.
> On a *first* install, pre-install hooks run before regular resources exist, so
> the SA is not yet created. If you enable `jobs.preInstall`, either set
> `serviceAccount.create: false`, pre-create the SA, or turn the SA into a hook
> itself via `serviceAccount.annotations` (`helm.sh/hook: pre-install,pre-upgrade`,
> `helm.sh/hook-weight: "-10"`, `helm.sh/hook-delete-policy: before-hook-creation`).

### Service Monitor / Pod Monitor (Prometheus)

```yaml
serviceMonitor:
  enabled: true
  port: http
  path: /metrics
  scheme: https                 # optional; pairs with mTLS-scraped targets
  tlsConfig:                    # optional Prometheus Operator TLSConfig
    insecureSkipVerify: false
  interval: 30s
  sampleLimit: 0                # optional per-target series cap; 0 = no limit
  labels:
    release: prometheus
```

```yaml
podMonitor:
  enabled: true
  port: http
  path: /metrics
  scheme: https                 # optional; pairs with mTLS-scraped targets
  tlsConfig:                    # optional Prometheus Operator TLSConfig
    insecureSkipVerify: false
  interval: 30s
  sampleLimit: 0                # optional per-target series cap; 0 = no limit
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
helm template my-service . | grep -A 20 "kind: HTTPRoute"
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

## Extending: any Kubernetes object

Beyond the opinionated blocks above, `extraObjects` renders **any** Kind through one capability-gated generic renderer. It is a map of `Kind → list of specs`; each spec's `name` is required, and every field other than `name`/`namespace`/`labels`/`annotations`/`apiVersion`/`kind`/`clusterScoped` is passed through verbatim. Standard labels are added, namespace is stamped for namespaced Kinds, and the object is skipped if no supported `apiVersion` is present.

> **Trust model — values are code.** `extraObjects`, `extraManifests`, `sidecars`, `initContainers`,
> and `extraVolumes` are verbatim escape hatches: whoever writes those values authors arbitrary
> Kubernetes objects (and, for `extraManifests` strings, arbitrary template code executed with the
> full chart context). Review values changes like code changes. Two guardrails apply:
>
> - Cluster-scoped Kinds in `extraObjects` **fail rendering** unless you set
>   `allowClusterScopedExtras: true` (the failure names the offending Kind). Unknown cluster-scoped
>   CRD Kinds can only be caught when you mark them `clusterScoped: true` on the spec.
> - Install-time `WARNING:` notes are printed (via `NOTES.txt`) when extras contain `hostPath`
>   volumes, `privileged: true` containers, or cluster-scoped RBAC.

```yaml
allowClusterScopedExtras: true   # PriorityClass/StorageClass below are cluster-scoped
extraObjects:
  Role:
    - name: app-reader
      rules:
        - apiGroups: [""]
          resources: [configmaps, secrets]
          verbs: [get, list, watch]
  PriorityClass:
    - name: app-high            # cluster-scoped Kinds skip the namespace automatically
      value: 1000000
      globalDefault: false
  StorageClass:
    - name: fast
      provisioner: kubernetes.io/aws-ebs
      parameters: { type: gp3 }
```

For anything the library does not model, `extraManifests` renders raw manifests (maps or `tpl` strings) verbatim:

```yaml
extraManifests:
  - apiVersion: v1
    kind: ConfigMap
    metadata: { name: raw-config }
    data: { raw: "true" }
```

## Capability gating

Every generator picks the best `apiVersion` the target cluster serves and skips CRD-backed objects whose API is absent — charts never conflict on deploy. Built-in Kinds always render (best version, GA fallback); CRD/optional Kinds skip when their API is missing.

When rendering **without a cluster** (`helm template`, CI), Helm's API discovery is minimal, so CRD-backed objects would be skipped. Force-assume the groups you use:

```yaml
capabilities:
  apiVersions:
    - gateway.networking.k8s.io/v1
    - cert-manager.io/v1
    - monitoring.coreos.com/v1
    - security.istio.io/v1beta1
```

Equivalently, pass `helm template --api-versions <group/version>` (and `--kube-version <x.y>` to set `.Capabilities.KubeVersion`). See [`docs/specs/platform-library-v2-architecture.md`](docs/specs/platform-library-v2-architecture.md) for the full Kind→apiVersion registry and negotiation rules.

## Architecture

```
my-service/values.yaml      ← Service team edits this (overrides only)
        │  (defaults imported at root via import-values: [defaults])
        ▼
platform-library/
├── Chart.yaml              ← chart name `platform`, type: library
├── values.yaml             ← Defaults (exports.defaults pattern)
├── values.schema.reference.json ← Root values contract (copied into consumers)
├── templates/
│   ├── _app.yaml           ← Orchestrator + `platform.render` entrypoint
│   ├── _capabilities.tpl   ← Kind→apiVersion registry, negotiation & gating
│   ├── _util.tpl           ← emit, deep-merge, genericResource, extraObjects/extraManifests
│   ├── _helpers.tpl        ← Shared helpers (naming, labels, image, pod template, affinity)
│   ├── _notes.tpl          ← Install-time security warnings (consumer NOTES.txt)
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
│   ├── _configmap-script.yaml ← Hook script ConfigMaps
│   ├── _secret.yaml        ← Secret
│   ├── _certificate.yaml   ← cert-manager Certificate
│   ├── _mtls.yaml          ← Istio mTLS policies
│   ├── _tls-secrets.yaml   ← TLS secrets (provided certs)
│   ├── _tls-selfsigned.yaml ← Self-signed TLS generation
│   ├── _pvc.yaml           ← PersistentVolumeClaim
│   ├── _cronjob.yaml       ← CronJob
│   ├── _job-preinstall.yaml / _job-postinstall.yaml ← Hook Jobs
│   ├── _servicemonitor.yaml ← Prometheus ServiceMonitor
│   └── _podmonitor.yaml    ← Prometheus PodMonitor
```

**Rendering flow:** the consumer's `templates/app.yaml` includes `platform.render`, which composes `platform.app` (the tier-1 orchestrator in `_app.yaml` — checks each feature's `.enabled` flag and capability gate, then emits the object), `platform.extraObjects`, and `platform.extraManifests`. Every template is an underscore-prefixed `define` block; the library ships no directly-rendered templates.

## Releasing

Releases are cut from semver tags and published as an OCI chart to
**`oci://ghcr.io/caretak3r/charts`** (the production repository; consumers set
`repository: "oci://ghcr.io/caretak3r/charts"` in their dependency). The
scaffold's default `--repo file://../platform-library` is for local development
only.

Flow (see `.github/workflows/release.yaml`):

1. Bump `version:` in `platform-library/Chart.yaml` (semver — major for any
   breaking values/template change).
2. Move the `[Unreleased]` notes in `CHANGELOG.md` under a new
   `## [X.Y.Z] - YYYY-MM-DD` heading.
3. Commit via PR; CI must pass.
4. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.

The release workflow refuses tags that do not match the chart version, reruns
the full CI gate (shellcheck, `helm lint`, schema metaschema check,
`scripts/lint-library.sh` with kubeconform + check-jsonschema required), then
runs `helm package` and `helm push` to GHCR using the workflow's
`GITHUB_TOKEN` (`packages: write`). Chart signing/provenance (cosign) is
tracked as future work (bead `hf-j30`).

## Contributing

See [CORE.md](CORE.md) for architecture details, known issues, and maintenance guidelines.

Open work is tracked with [Beads](https://github.com/steveyegge/beads) under the `hf`
issue prefix: run `bd ready` to find available work, or read the git-tracked seed at
[`.beads/issues.jsonl`](.beads/issues.jsonl). Check the "Beads tracker notes" section
of [AGENTS.md](AGENTS.md) before running `bd sync`.

### Adding a new resource type

1. Create `platform-library/templates/_<resource>.yaml` with a `define "platform.<resource>"` block
2. If the Kind is CRD-backed or version-negotiated, register it in the Kind→apiVersion registry in `_capabilities.tpl`
3. Add the `include` call to `_app.yaml` guarded by `.Values.<resource>.enabled` (and a capability gate for CRD-backed Kinds)
4. Add defaults to `values.yaml` under `exports.defaults` and extend `values.schema.reference.json`
5. Cover it in a fixture under `tests/fixtures/`, bump `expected_kinds` in `scripts/lint-library.sh`, and regenerate goldens: `UPDATE_GOLDEN=1 scripts/lint-library.sh`
6. Update `CORE.md` rendering order and directory listing

### Validation

```bash
helm lint platform-library/
scripts/lint-library.sh              # render matrix, goldens, kubeconform, guardrails
UPDATE_GOLDEN=1 scripts/lint-library.sh   # accept intentional render changes
```
