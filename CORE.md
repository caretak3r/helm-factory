# CORE.md — helm-factory

> **v2 (current):** the library is a **pure, capability-gated common library**.
> For the v2 architecture in full — capability negotiation, the generic
> `extraObjects` renderer, the `platform.render` entrypoint, and the pure-library
> model — see [`docs/specs/platform-library-v2-architecture.md`](docs/specs/platform-library-v2-architecture.md).
> Migrating a consumer from v1: [`docs/migration/v1-to-v2.md`](docs/migration/v1-to-v2.md).
> Release history: [`CHANGELOG.md`](CHANGELOG.md).

## Project Purpose
- Capability-gated Helm library chart (`platform-library/`, chart name `platform`) that is the basis for generating product charts
- Consumer charts depend on it (`import-values: [defaults]`) and render via `{{ include "platform.render" . }}`; the `scripts/new-app-chart.sh` generator scaffolds one
- Renders the opinionated primary-app objects (Deployments, StatefulSets, DaemonSets, Services, Ingress, Gateway API, hook Jobs, CronJobs, ConfigMaps, Secrets, PVCs, HPA, PDB, NetworkPolicy, ServiceMonitor, PodMonitor, Certificates, mTLS) **plus** any other Kind via `extraObjects` and raw manifests via `extraManifests`

## Architecture
- Library chart type — cannot be installed directly; pure (no self-rendering stub templates as of v2)
- Consumer charts import via `exports.defaults` + `import-values: [defaults]` — library defaults land at the **root** of the consumer's values scope
- `platform.render` (in `_app.yaml`) is the single public entrypoint: `platform.app` (tier-1) + `platform.extraObjects` (tier-2 generic) + `platform.extraManifests` (raw)
- `_app.yaml` is the tier-1 orchestrator — routes each object through `platform.emit` (adds the `---` separator) via `include`
- `_capabilities.tpl` — the Kind→apiVersion registry and negotiation/gating helpers (`platform.capabilities.apiVersionFor`, `...has`, `...isClusterScoped`, …)
- `_util.tpl` — `platform.emit`, `platform.util.merge`, the generic `platform.genericResource` renderer, and `platform.extraObjects`/`platform.extraManifests`
- `_helpers.tpl` — naming/labels/image/podTemplate composition helpers
- `_notes.tpl` — `platform.notes`, install-time security warnings for the consumer's `NOTES.txt`

## Template Rendering Order
`platform.app` (in `_app.yaml`) emits, in order (each gated as noted):
1. ConfigMap — `configMap.enabled`
2. Hook script ConfigMaps — `jobs.preInstall/postInstall.enabled` + `script`/`scriptFile`
3. Secret — `secret.enabled` (suppressed by `secret.existingSecret`)
4. Certificate — `certificate.enabled` + capability gate (`Certificate`)
5. TLS Secrets (provided certs) — `ingress.enabled` + `ingress.secrets`
6. Self-signed TLS — `tlsSelfSigned.enabled` (reuses the existing Secret via `lookup` on upgrade)
7. mTLS (PeerAuthentication + AuthorizationPolicy) — `mtls.enabled` + capability gate; fails closed without `mtls.allowedPrincipals` unless `mtls.allowAllPrincipals: true`
8. PVC — `persistence.enabled` (skipped when `persistence.existingClaim` is set)
9. Workload — always; `platform.workload` dispatches on `workload.type` (`Deployment` default, `StatefulSet`, `DaemonSet`)
10. HPA — `autoscaling.enabled`; only for `Deployment`/`StatefulSet` (`_hpa.yaml` guards, DaemonSet is skipped)
11. Service — `service.enabled`
12. Ingress — `ingress.enabled`
13. Gateway API (HTTPRoute/GRPCRoute) — `gatewayApi.enabled` + capability gate (`HTTPRoute`)
14. NetworkPolicy — `networkPolicy.enabled`
15. PodDisruptionBudget — `podDisruptionBudget.enabled`
16. ServiceAccount — `serviceAccount.create` or `serviceAccount.name`
17. ServiceMonitor — `serviceMonitor.enabled` + capability gate
18. PodMonitor — `podMonitor.enabled` + capability gate
19. CronJob — `cronJob.enabled`
20. Pre-install Job, then post-install Job — `jobs.preInstall/postInstall.enabled`
21. Service-endpoints ConfigMap — `serviceEndpoints.enabled`

`platform.render` then appends `platform.extraObjects` (any Kind, capability-negotiated, cluster-scoped Kinds gated by `allowClusterScopedExtras`) and `platform.extraManifests` (raw maps or `tpl` strings).

## Helper Composition Hierarchy
`_helpers.tpl`:
- `platform.name` / `platform.fullname` / `platform.chart` — naming (nameOverride/fullnameOverride aware)
- `platform.labels` / `platform.selectorLabels` — common + selector labels
- `platform.image` — full image reference (`registry/repo:tag` or `registry/repo@digest`); **fails** when tag and digest are both empty
- `platform.imagePullPolicy` — pull policy with global override
- `platform.envVars` — env vars from map or slice
- `platform.primaryServicePort` — first service port or default
- `platform.buildAffinity` — explicit `affinity` passthrough, else `highAvailability` preset-based builder
- `platform.podTemplateSpec` — shared pod template across all workloads (security contexts, SA, pull secrets, probes, init containers, sidecars, volumes)
- `platform.serviceAccountName` / `platform.serviceAccount` — SA name resolution and the ServiceAccount object
- `platform.autoscaling` — HPA definition
- `platform.workload` — workload dispatcher on `workload.type`
- `platform.deployment.rolloutAnnotations` — checksum annotations for config/secret-driven rollouts
- `platform.service.endpoint`, `global.subchartEndpoint`, `global.enabledSubcharts`, `global.allEndpointsDynamic`, `global.allEndpoints`, `platform.serviceEndpoints.configmap` — service-endpoint helpers (single and umbrella charts)
- `platform.renderHookJob` — pre/post-install hook Job renderer

`_capabilities.tpl`: `platform.capabilities.has`, `.apiVersion`, `.registry`, `.apiVersionFor`, `.apiVersionForOrDefault`, `.isStable`, `.clusterScoped`, `.isClusterScoped`.
`_util.tpl`: `platform.emit`, `platform.util.merge`, `platform.genericResource`, `platform.extraObjects`, `platform.extraManifests`.
`_notes.tpl`: `platform.notes`.

## Configuration Flow
1. Scaffold a consumer chart: `scripts/new-app-chart.sh <name>` (or write the three files by hand — see below)
2. The consumer's `Chart.yaml` declares the `platform` dependency with `import-values: [defaults]`; library defaults merge under the consumer's root values
3. Service teams set **overrides only** in the consumer chart's `values.yaml`
4. `values.schema.json` (copied from `values.schema.reference.json`) makes Helm validate the coalesced post-import values at render time
5. `helm template`/`install` renders everything through `{{ include "platform.render" . }}`

## Naming Conventions
- `_*.yaml` — generator templates (underscore-prefixed `define` blocks; never rendered directly — the library ships **no** non-underscore templates)
- `_*.tpl` — helper-only files (capabilities, util, helpers, notes)
- `platform.*` — templates for single-chart use
- `global.*` — templates for umbrella/multi-chart use

## Key Design Patterns
- **Feature toggles:** every resource gated by an `.enabled` flag
- **Capability gates:** CRD-backed generators render only when the Kind's apiVersion is served (or force-assumed via `capabilities.apiVersions` / `--api-versions`)
- **Global overrides:** `global.imageRegistry`, `global.imagePullPolicy`, `global.imagePullSecrets`, `global.storageClass`
- **HA presets:** `highAvailability` (must be `enabled: true`) builds affinity from presets; explicit `affinity` wins outright
- **Holder-dict pattern:** computed values needing mutation use `dict` holders
- **Probe omit pattern:** probes use `omit .Values.livenessProbe "enabled"` to strip the flag before rendering
- **Pull secrets aggregation:** `global.imagePullSecrets` and `image.pullSecrets` are concatenated
- **Fail-closed guardrails:** unpinned images, mTLS without principals, `existingSecret` + inline data, and cluster-scoped extras (without opt-in) all `fail` at render time with actionable messages

## Known Issues (Tracked)
Tracked in the Beads issue tracker (`bd ready`, `bd show <id>`; the git-tracked seed
is [`.beads/issues.jsonl`](.beads/issues.jsonl)). The long-standing ones below were
re-verified still present at these locations:

| Issue | Bead | File:Line | Impact |
|-------|------|-----------|--------|
| Probe render condition is subtle | `hf-d97` | `_helpers.tpl:244-251` | `omit ... "enabled"` yields an empty dict when the probe carries no other keys, and Go templates treat an empty dict as false — so `and enabled (omit ...)` is a real guard against emitting an empty probe, not a redundancy. Worth a comment or a clearer helper |
| Service selector includes mutable labels | `hf-7a1` | `_service.yaml:51-55` | `commonLabels` are added to the Service selector; selectors are immutable, so changing `commonLabels` breaks the Service |
| Unknown workload type silently falls back to Deployment | `hf-klw` | `_helpers.tpl:440-448` | Mitigated: `values.schema.json` (fixtures/scaffold) rejects anything outside the `Deployment`/`StatefulSet`/`DaemonSet` enum at render time; only consumers without the schema hit the silent fallback |
| Duplicate imagePullSecrets possible | `hf-k9c` | `_helpers.tpl:194-206` | The same secret listed in both `global.imagePullSecrets` and `image.pullSecrets` appears twice |

Fixed since the v1 review (no longer issues): DaemonSet+HPA (guarded in `_hpa.yaml:2`), silent hook-script skip (fails with a message in `_configmap-script.yaml:41`). Full history: [`CHANGELOG.md`](CHANGELOG.md) and `fable5-review.md`. For the current reconciliation of `fable5-review.md` against `main`, plus the outstanding productionization/Helm-v4-modernization backlog, see [`docs/productionization-plan.md`](docs/productionization-plan.md).

## Directory Structure
```
helm-factory/
├── .github/workflows/
│   ├── ci.yaml                   # PR/main gate: shellcheck, lint, schema, lint-library.sh
│   └── release.yaml              # Tag-triggered: gate + helm package/push to GHCR (OCI)
├── CHANGELOG.md                  # Keep-a-Changelog release notes
├── CORE.md                       # This file
├── README.md                     # Consumer-facing reference
├── docs/
│   ├── migration/v1-to-v2.md
│   └── specs/platform-library-v2-architecture.md
├── platform-library/             # The library chart (name: platform, type: library)
│   ├── Chart.yaml
│   ├── values.yaml               # Defaults under exports.defaults
│   ├── values.schema.reference.json  # Root values contract (copied to consumers)
│   └── templates/
│       ├── _app.yaml             # Tier-1 orchestrator + platform.render entrypoint
│       ├── _capabilities.tpl     # Kind→apiVersion registry + negotiation/gating
│       ├── _util.tpl             # emit, merge, genericResource, extraObjects/Manifests
│       ├── _helpers.tpl          # Naming, labels, image, pod template, affinity, hooks
│       ├── _notes.tpl            # platform.notes install-time warnings
│       ├── _deployment.yaml      # Deployment workload
│       ├── _statefulset.yaml     # StatefulSet workload
│       ├── _daemonset.yaml       # DaemonSet workload
│       ├── _service.yaml         # Service
│       ├── _ingress.yaml         # Ingress
│       ├── _gateway-api.yaml     # Gateway API HTTPRoute/GRPCRoute
│       ├── _hpa.yaml             # HorizontalPodAutoscaler
│       ├── _pdb.yaml             # PodDisruptionBudget
│       ├── _networkpolicy.yaml   # NetworkPolicy
│       ├── _configmap.yaml       # ConfigMap
│       ├── _configmap-script.yaml # Hook script ConfigMaps
│       ├── _secret.yaml          # Secret (existingSecret aware)
│       ├── _certificate.yaml     # cert-manager Certificate
│       ├── _mtls.yaml            # Istio PeerAuthentication + AuthorizationPolicy
│       ├── _tls-secrets.yaml     # TLS Secrets from provided certs
│       ├── _tls-selfsigned.yaml  # Self-signed TLS (lookup-reused on upgrade)
│       ├── _pvc.yaml             # PersistentVolumeClaim
│       ├── _cronjob.yaml         # CronJob
│       ├── _job-preinstall.yaml  # Pre-install hook Job
│       ├── _job-postinstall.yaml # Post-install hook Job
│       ├── _servicemonitor.yaml  # Prometheus ServiceMonitor
│       └── _podmonitor.yaml      # Prometheus PodMonitor
├── scripts/
│   ├── new-app-chart.sh          # Consumer chart scaffold
│   └── lint-library.sh           # Full validation gate (matrix, goldens, kubeconform)
└── tests/
    ├── render.sh                 # Renders a fixture with the schema enforced
    ├── fixtures/                 # minimal, full, stateful, daemon consumer charts
    └── golden/                   # Committed golden snapshots (k8s 1.31)
```

## Consumer Chart Integration
Exactly what `scripts/new-app-chart.sh` generates and `tests/fixtures/*` use.

### Chart.yaml
```yaml
apiVersion: v2
name: my-service
description: my-service — generated from platform-library
type: application
version: 0.1.0
appVersion: "1.0.0"
kubeVersion: ">=1.31.0-0 <1.37.0-0"
dependencies:
  - name: platform                       # the chart name, not "platform-library"
    version: ">=2.0.0-0"
    repository: "oci://ghcr.io/caretak3r/charts"   # dev: file://../platform-library
    import-values:                       # REQUIRED — without this the library
      - defaults                         # defaults never reach your root values
```

### templates/app.yaml
```yaml
{{ include "platform.render" . }}
```

### templates/NOTES.txt
```yaml
{{ include "platform.notes" . }}
```

### values.yaml (overrides only — defaults are imported at the root)
```yaml
image:
  repository: gcr.io/my-project/my-service
  tag: "1.0.0"          # or digest: "sha256:<64-hex>"; unpinned images fail, latest is rejected

workload:
  type: Deployment       # Deployment | StatefulSet | DaemonSet (schema enum)

service:
  enabled: true
  ports:
    - name: http
      port: 8080
      targetPort: http
      protocol: TCP

ingress:
  enabled: true
  hostname: my-service.example.com

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPU: 70

# When rendering without a cluster (CI), force-assume the CRD groups you use:
# capabilities:
#   apiVersions: [cert-manager.io/v1, monitoring.coreos.com/v1]
```

### values.schema.json
Copy `platform-library/values.schema.reference.json` into the consumer chart as
`values.schema.json` (the scaffold does this) so Helm rejects invalid coalesced
values at render time.

## Workload Type Decision Tree
```
workload.type (schema enum — case-sensitive)
├── Deployment (default)
│   ├── Supports: HPA, rolling updates, config/secret checksum rollouts
│   └── Use for: stateless services
├── StatefulSet
│   ├── Supports: HPA, statefulSet.volumeClaimTemplates, stable network IDs
│   └── Use for: databases, stateful apps
└── DaemonSet
    ├── Supports: one pod per node (HPA is skipped)
    └── Use for: logging agents, node monitoring

Not workload types (separate features):
├── cronJob.enabled  → CronJob alongside the workload
└── jobs.preInstall / jobs.postInstall → helm-hook Jobs (migrations, setup)
```

## HA Strategy Matrix
`highAvailability.enabled: true` is required; an explicit `affinity:` value overrides all presets.

| Setting | Values | Result |
|---------|--------|--------|
| `podAntiAffinityPreset` | `soft` / `hard` | preferred / required anti-affinity on `kubernetes.io/hostname` |
| `podAffinityPreset` | `soft` / `hard` | preferred / required co-location on `kubernetes.io/hostname` |
| `nodeAffinityPreset` | `{type: soft|hard, key: <label>, values: [...]}` | node affinity; only applies when `type` **and** non-empty `values` are set |

## Global vs Local Overrides

| Setting | Global | Local | Precedence |
|---------|--------|-------|------------|
| imageRegistry | `global.imageRegistry` | `image.registry` | Global overrides if set |
| imagePullPolicy | `global.imagePullPolicy` | `image.pullPolicy` | Global overrides if set |
| imagePullSecrets | `global.imagePullSecrets` | `image.pullSecrets` | Merged (both applied) |
| storageClass | `global.storageClass` | `persistence.storageClass` | Global overrides if set |

## Feature Flag Checklist
- `autoscaling.enabled` → only renders for `workload.type: Deployment` or `StatefulSet` (DaemonSet silently skipped)
- `ingress.enabled` → requires `service.enabled: true`
- `gatewayApi.enabled` → capability-gated on Gateway API CRDs; `parentRefs` required when a route is enabled
- `serviceMonitor.enabled` / `podMonitor.enabled` → capability-gated on Prometheus Operator CRDs
- `certificate.enabled` → capability-gated on cert-manager CRDs
- `mtls.enabled` → capability-gated on Istio; requires `mtls.allowedPrincipals` (or explicit `mtls.allowAllPrincipals: true`)
- `networkPolicy.enabled` → requires a CNI supporting NetworkPolicy; empty ingress+egress = default-deny (NOTES warning)
- `persistence.enabled` → creates a PVC unless `persistence.existingClaim` is set; StatefulSets can use `statefulSet.volumeClaimTemplates` instead
- `extraObjects` with cluster-scoped Kinds → requires `allowClusterScopedExtras: true`

## Debug Commands

### Render a test fixture (schema-enforced, like a real consumer)
```bash
tests/render.sh full
tests/render.sh full --kube-version 1.31 --api-versions cert-manager.io/v1
```

### Run the full validation gate
```bash
scripts/lint-library.sh                 # matrix, goldens, kubeconform, guardrails
UPDATE_GOLDEN=1 scripts/lint-library.sh # accept intentional render changes
```

### Render a consumer chart
```bash
helm dependency update ./my-service
helm template my-service ./my-service
helm template my-service ./my-service --set workload.type=StatefulSet
```

### Validate rendered output against the K8s API
```bash
helm template my-service ./my-service | kubectl apply --dry-run=client -f -
```

## Common Pitfalls

### 1. Missing `import-values: [defaults]`
Without it the library defaults never reach the root values scope and every generator sees empty values. It is REQUIRED on the dependency.

### 2. Unpinned images
Rendering fails when `image.tag` and `image.digest` are both empty, and the schema rejects `tag: latest`. Pin a tag or (preferred) a digest.

### 3. CRD-backed objects disappear under `helm template`
Without a cluster, Helm's API discovery is minimal, so Certificates, HTTPRoutes, monitors, and mTLS objects are capability-skipped. Force-assume the groups via `capabilities.apiVersions` or `--api-versions`.

### 4. Invalid workload type
`values.schema.json` rejects anything outside `Deployment`/`StatefulSet`/`DaemonSet` (case-sensitive). Consumers rendering without the schema fall back silently to Deployment.

### 5. fullnameOverride length
K8s names are limited to 63 characters; keep `fullnameOverride` ≤ 30 chars to leave room for suffixes.

### 6. Changing Service selector labels
`commonLabels` are included in the Service selector, and selectors are immutable — changing them orphans the Service. Keep `commonLabels` stable or recreate the Service.

### 7. mTLS fails closed
`mtls.enabled: true` with empty `mtls.allowedPrincipals` fails the render. List principals, or opt into the wildcard with `mtls.allowAllPrincipals: true`.

## Maintenance Notes

### Adding a new generator
1. Create `platform-library/templates/_<resource>.yaml` with a `define "platform.<resource>"` block
2. If the Kind is CRD-backed or version-negotiated, add it to the registry in `_capabilities.tpl`
3. Wire it into `_app.yaml` through `platform.emit`, gated on `.Values.<resource>.enabled` (plus `platform.capabilities.apiVersionFor` for CRD-backed Kinds)
4. Add defaults under `exports.defaults` in `values.yaml` and extend `values.schema.reference.json`
5. Cover it in a fixture, bump `expected_kinds` in `scripts/lint-library.sh`, regenerate goldens (`UPDATE_GOLDEN=1 scripts/lint-library.sh`)
6. Update this file (rendering order, directory structure) and the README

### Deprecating features
1. Mark as deprecated in `values.yaml` comments
2. Add migration notes to `docs/migration/`
3. Warn at render time (NOTES warning or `fail` for hard removals)
4. Remove after 2 major versions

### Releasing
See the README **Releasing** section and `.github/workflows/release.yaml`: bump
`platform-library/Chart.yaml` version, update `CHANGELOG.md`, tag `vX.Y.Z`, push.
Semver: patch = fixes, minor = backward-compatible features, major = breaking
values/template changes.

---

**Last Updated:** 2026-07-04
**Maintainer:** Rohit Gudi (@caretak3r)
**License:** MIT
