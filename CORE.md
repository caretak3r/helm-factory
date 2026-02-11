# CORE.md — helm-factory

## Project Purpose
- Helm library chart (`platform-library`) providing standardized K8s resource templates
- Service teams use a single `configuration.yaml` to configure their deployments
- The library renders: Deployments, StatefulSets, DaemonSets, Services, Ingress, Gateway API (HTTPRoute/GRPCRoute), Jobs, CronJobs, ConfigMaps, Secrets, PVCs, HPA, PDB, NetworkPolicy, ServiceMonitor, PodMonitor, Certificates, mTLS policies

## Architecture
- Library chart type — cannot be installed directly
- Consumer charts import via `exports.defaults` pattern in `values.yaml`
- `_app.yaml` is the orchestrator template — calls all other templates via `include`
- `_helpers.tpl` contains all helper/composition templates (~670 lines)

## Template Rendering Order
`_app.yaml` calls (in order):
1. `platform.configmap` (if configMap.enabled)
2. `platform.configmap.script` (for pre/post install scripts)
3. `platform.secret` (if secret.enabled)
4. `platform.certificate` (if certificate.enabled)
5. `platform.tls.secrets` / `platform.tls.selfsigned`
6. `platform.mtls` (if mtls.enabled)
7. `platform.pvc` (if persistence.enabled)
8. `platform.workload` (always — dispatches to deployment/statefulset/daemonset)
9. `platform.hpa` (if autoscaling.enabled)
10. `platform.service` (if service.enabled)
11. `platform.ingress` (if ingress.enabled)
12. `platform.gatewayApi` (if gatewayApi.enabled)
13. `platform.networkpolicy` (if networkPolicy.enabled)
14. `platform.pdb` (if podDisruptionBudget.enabled)
15. `platform.serviceAccount` (if create or name set)
16. `platform.servicemonitor` / `platform.podmonitor`
17. `platform.cronjob` (if cronJob.enabled)
18. `platform.job.preinstall` / `platform.job.postinstall`
19. `platform.serviceEndpoints.configmap` (if serviceEndpoints.enabled)

## Helper Composition Hierarchy (_helpers.tpl)
- `platform.name` — chart name with nameOverride
- `platform.fullname` — release-prefixed name with fullnameOverride
- `platform.chart` — chart name + version
- `platform.labels` — common labels (helm.sh/chart, selector labels, version, managed-by)
- `platform.selectorLabels` — app name + instance
- `platform.image` — full image reference (registry/repo:tag or registry/repo@digest)
- `platform.imagePullPolicy` — pull policy with global override
- `platform.envVars` — env vars from map or slice
- `platform.primaryServicePort` — first service port or default
- `platform.buildAffinity` — HA preset-based affinity builder
- `platform.podTemplateSpec` — shared pod template across all workload types
- `platform.serviceAccountName` — SA name resolution
- `platform.autoscaling` — HPA definition
- `platform.workload` — workload type dispatcher
- `platform.service.endpoint` — service endpoint URL
- `global.subchartEndpoint` — subchart endpoint for umbrella charts
- `global.enabledSubcharts` — list enabled subcharts dynamically
- `global.allEndpointsDynamic` — all service endpoint URLs
- `platform.serviceEndpoints.configmap` — ConfigMap with endpoint URLs
- `platform.renderHookJob` — hook job (pre/post install) renderer

## Configuration Flow
1. Service team fills out `configuration.yaml` (single source of truth)
2. Consumer chart's `Chart.yaml` declares `platform-library` as dependency
3. `values.yaml` uses `exports.defaults` pattern to merge library defaults with service config
4. During `helm template/install`, `_app.yaml` orchestrates all resource generation

## Naming Conventions
- `_*.yaml` — implementation templates (underscore-prefixed, not rendered directly)
- Templates without underscore — wrapper templates that include implementation
- `platform.*` — templates for single-chart use
- `global.*` — templates for umbrella/multi-chart use

## Key Design Patterns
- **Feature toggles:** Every resource gated by `.enabled` flag
- **Global overrides:** `global.imageRegistry`, `global.imagePullPolicy`, `global.imagePullSecrets` override per-chart settings
- **HA presets:** `highAvailability` section generates pod/node affinity from simple presets (soft/hard)
- **Holder-dict pattern:** Used for computed values that need mutation (e.g., `$holder := dict "value" ...`)
- **Probe omit pattern:** Probes use `omit .Values.livenessProbe "enabled"` to strip the enabled flag before rendering
- **Pull secrets aggregation:** Both `global.imagePullSecrets` and `image.pullSecrets` are merged

## Known Issues (Tracked)
These are lower-priority issues identified during code review but not yet fixed:

| Issue | File:Line | Impact |
|-------|-----------|--------|
| Probe condition redundancy | `_helpers.tpl:224,227,230` | `omit` returns dict (always truthy); `and enabled (omit ...)` is just `enabled` — works but misleading |
| Service selector includes mutable labels | `_service.yaml:53-55` | `commonLabels` in Service selector can break if labels change (selectors are immutable) |
| No else/warning for unknown workload type | `_helpers.tpl:420-427` | Invalid `workload.type` silently falls through to Deployment |
| DaemonSet + HPA guard missing | `_hpa.yaml:2` | HPA checks workload type but `_app.yaml:42` doesn't — HPA can be created for DaemonSet |
| Duplicate imagePullSecrets possible | `_helpers.tpl:174-180` | Same secret in global + image lists appears twice |

## Fixed Issues (This Review)
| Bug | Severity | Files Changed |
|-----|----------|---------------|
| Image template leading-newline | P0/Critical | `_helpers.tpl` |
| `fullnameOverride` defined but never used | P0/Critical | `_helpers.tpl` |
| Tautological condition in enabledSubcharts/allEndpointsDynamic | P0/Critical | `_helpers.tpl` |
| Unsafe `$chartValues.service.name` access | P0/Critical | `_helpers.tpl` |
| Silent script-file failure | P1/High | `_configmap-script.yaml` |
| Service endpoints ConfigMap always created | P1/High | `_app.yaml`, `values.yaml` |
| mTLS hardcoded wildcard principals | P2/Medium | `_mtls.yaml`, `values.yaml` |
| Hook jobs missing image-specific pull secrets | P2/Medium | `_helpers.tpl` |

## Directory Structure
```
helm-factory/
├── Chart.yaml                    # Library chart metadata
├── values.yaml                   # Default values + exports.defaults
├── templates/
│   ├── _app.yaml                 # Main orchestrator (calls all templates)
│   ├── _helpers.tpl              # All helper templates (~670 lines)
│   ├── _certificate.yaml         # cert-manager Certificate resources
│   ├── _configmap.yaml           # ConfigMap for application config
│   ├── _configmap-script.yaml    # ConfigMap for hook scripts
│   ├── _cronjob.yaml             # CronJob workload
│   ├── _daemonset.yaml           # DaemonSet workload
│   ├── _deployment.yaml          # Deployment workload (default)
│   ├── _gateway-api.yaml         # Gateway API HTTPRoute/GRPCRoute
│   ├── _hpa.yaml                 # HorizontalPodAutoscaler
│   ├── _ingress.yaml             # Ingress resource
│   ├── _job.yaml                 # Job (pre/post install hooks)
│   ├── _mtls.yaml                # mTLS PeerAuthentication + AuthorizationPolicy
│   ├── _networkpolicy.yaml       # NetworkPolicy
│   ├── _pdb.yaml                 # PodDisruptionBudget
│   ├── _podmonitor.yaml          # Prometheus PodMonitor
│   ├── _pvc.yaml                 # PersistentVolumeClaim
│   ├── _secret.yaml              # Secret for sensitive data
│   ├── _service.yaml             # Service resource
│   ├── _serviceaccount.yaml      # ServiceAccount
│   ├── _servicemonitor.yaml      # Prometheus ServiceMonitor
│   ├── _statefulset.yaml         # StatefulSet workload
│   └── _tls.yaml                 # TLS secret generation
├── configuration.yaml            # Example service configuration
└── CORE.md                       # This file
```

## Consumer Chart Integration

### Chart.yaml
```yaml
apiVersion: v2
name: my-service
version: 1.0.0
dependencies:
  - name: platform-library
    version: "^1.0.0"
    repository: "oci://registry.example.com/charts"
```

### values.yaml
```yaml
exports:
  defaults:
    <<: *default-values
    serviceName: my-service
    chartName: my-service
    image:
      repository: my-service
      tag: v1.0.0
    service:
      enabled: true
      port: 8080
```

### configuration.yaml (Service Team File)
```yaml
serviceName: my-service
chartName: my-service
image:
  repository: gcr.io/my-project/my-service
  tag: v2.3.1
  pullPolicy: IfNotPresent

workload:
  type: deployment
  replicas: 3

service:
  enabled: true
  type: ClusterIP
  port: 8080
  targetPort: http

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: my-service.example.com
      paths:
        - path: /
          pathType: Prefix

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

highAvailability:
  podAntiAffinityPreset: soft
  nodeAffinityPreset: soft

resources:
  limits:
    memory: 512Mi
    cpu: 500m
  requests:
    memory: 256Mi
    cpu: 100m
```

## Workload Type Decision Tree
```
workload.type
├── deployment (default)
│   ├── Supports: HPA, rolling updates, surge/unavailable
│   └── Use for: stateless services
├── statefulset
│   ├── Supports: ordered deployment, persistent storage per pod, stable network IDs
│   └── Use for: databases, stateful apps
├── daemonset
│   ├── Supports: one pod per node, node selection
│   └── Use for: logging agents, node monitoring
├── cronjob
│   ├── Supports: scheduled execution, concurrency policy
│   └── Use for: batch jobs, periodic tasks
└── job (via hooks)
    ├── Supports: pre-install, post-install hooks
    └── Use for: migrations, setup scripts
```

## HA Strategy Matrix

| Preset | podAntiAffinityPreset | nodeAffinityPreset | Result |
|--------|------------------------|---------------------|--------|
| soft/soft | preferredDuringScheduling | preferredDuringScheduling | Best-effort spread across nodes/zones |
| hard/soft | requiredDuringScheduling | preferredDuringScheduling | Pods MUST be on different nodes, prefer different zones |
| soft/hard | preferredDuringScheduling | requiredDuringScheduling | Prefer different nodes, MUST be in specific zones |
| hard/hard | requiredDuringScheduling | requiredDuringScheduling | Strict: different nodes AND specific zones (requires sufficient node capacity) |

## Global vs Local Overrides

| Setting | Global | Local | Precedence |
|---------|--------|-------|------------|
| imageRegistry | `global.imageRegistry` | `image.registry` | Global overrides if set |
| imagePullPolicy | `global.imagePullPolicy` | `image.pullPolicy` | Global overrides if set |
| imagePullSecrets | `global.imagePullSecrets` | `image.pullSecrets` | Merged (both applied) |
| storageClass | `global.storageClass` | `persistence.storageClass` | Global overrides if set |

## Feature Flag Checklist
Before enabling a feature, ensure dependencies are met:

- ✅ `autoscaling.enabled` → requires `workload.type: deployment` or `statefulset`
- ✅ `ingress.enabled` → requires `service.enabled: true`
- ✅ `gatewayApi.enabled` → requires Gateway API CRDs installed; `parentRefs` required when route enabled
- ✅ `servicemonitor.enabled` → requires Prometheus Operator CRDs installed
- ✅ `podmonitor.enabled` → requires Prometheus Operator CRDs installed
- ✅ `certificate.enabled` → requires cert-manager CRDs installed
- ✅ `mtls.enabled` → requires Istio installed
- ✅ `networkPolicy.enabled` → requires CNI supporting NetworkPolicy
- ✅ `persistence.enabled` → StatefulSet: auto-creates PVCs; Deployment/DaemonSet: requires manual PVC or `persistence.create: true`

## Debug Commands

### Render templates locally
```bash
helm template my-service . -f configuration.yaml
```

### Validate against K8s API
```bash
helm template my-service . -f configuration.yaml | kubectl apply --dry-run=client -f -
```

### Inspect specific template
```bash
helm template my-service . -f configuration.yaml -s templates/_deployment.yaml
```

### Show computed values
```bash
helm template my-service . -f configuration.yaml --debug 2>&1 | grep -A 50 "COMPUTED VALUES"
```

### Test with different workload types
```bash
helm template my-service . -f configuration.yaml --set workload.type=statefulset
```

## Common Pitfalls

### 1. fullnameOverride Length
K8s resource names limited to 63 characters. If `fullnameOverride` + namespace + resource type suffix exceeds limit, manifest will fail.

**Fix:** Keep `fullnameOverride` ≤ 30 chars.

### 2. Changing Service Selector Labels
Service selector includes `commonLabels`. If you change `commonLabels`, Service won't match existing Pods (selectors are immutable).

**Fix:** Delete and recreate Service, or don't use mutable labels in `commonLabels`.

### 3. Invalid Workload Type
Setting `workload.type: foobar` silently falls back to Deployment (no error).

**Fix:** Use only: `deployment`, `statefulset`, `daemonset`, `cronjob`.

### 4. HPA + DaemonSet
`autoscaling.enabled: true` with `workload.type: daemonset` creates invalid HPA (DaemonSets don't scale horizontally).

**Fix:** Disable HPA for DaemonSets.

### 5. Missing Script Files
If `configMap.script.preInstall.path` references non-existent file, template silently skips it.

**Fix:** Ensure script files exist in chart directory before referencing.

## Maintenance Notes

### Adding New Resources
1. Create `_<resource>.yaml` in `templates/`
2. Add helper template to `_helpers.tpl` if complex logic needed
3. Add `include "platform.<resource>"` call to `_app.yaml` in appropriate order
4. Add feature flag to `values.yaml` with `.enabled: false` default
5. Document in this file under "Template Rendering Order"

### Deprecating Features
1. Mark as deprecated in `values.yaml` comments
2. Add migration guide to this file
3. Log warning during template render (use `fail` or `required` with helpful message)
4. Remove after 2 major versions

### Breaking Changes
Follow semver:
- Patch (1.0.x): Bug fixes, no config changes
- Minor (1.x.0): New features, backward-compatible
- Major (x.0.0): Breaking changes to `values.yaml` schema

---

**Last Updated:** 2026-02-07
**Maintainer:** Rohit Gudi (@caretak3r)
**License:** MIT
