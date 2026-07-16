# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions track the `platform-library` chart version (`platform-library/Chart.yaml`);
releases are tagged `vX.Y.Z` and published to `oci://ghcr.io/caretak3r/charts`.

## [Unreleased]

### Fixed — workload templates

- Config/Secret checksum rollout annotations (`checksum/config`,
  `checksum/secret`) now apply to StatefulSet and DaemonSet pod templates, not
  just Deployments — previously a `helm upgrade` changing `configMap.data` or
  `secret.stringData` left StatefulSet/DaemonSet pods running stale config
  until manually rolled. The helper is renamed
  `platform.rolloutAnnotations`; `platform.deployment.rolloutAnnotations`
  remains as a deprecated alias. The full fixture now enables `configMap` to
  snapshot the Deployment path, and `scripts/lint-library.sh` gained a
  `rollout checksum` gate asserting the annotations reach the full and
  stateful pod templates (hf-bk0).
- `imagePullSecrets` are now deduped by name across `global.imagePullSecrets`
  and `image.pullSecrets` (global entries first) in all three pod specs that
  aggregate them — workload pod template, CronJob, and hook Job. A secret
  named in both values paths previously rendered twice.
  `scripts/lint-library.sh` gained a dedupe/ordering gate covering all three
  sites (hf-k9c).

### Fixed — annotation precedence (Ingress, Gateway API)

- Resource-specific annotations now override `commonAnnotations` on Ingress,
  HTTPRoute, and GRPCRoute (and `gatewayApi.annotations` now overrides
  `commonAnnotations` in the shared Gateway API map), matching every other
  object in the library (Service, Secret, ConfigMap, PVC, ...). These four
  sites used Sprig `merge`, which keeps existing keys, so `commonAnnotations`
  silently won any collision. **Behavior change:** only consumers setting the
  same annotation key in both `commonAnnotations` and the resource-specific
  block are affected — previously the common value rendered (the bug), now the
  specific value wins. `scripts/lint-library.sh` gained an
  `annotation precedence` gate asserting the specific value renders (hf-tyw).

### Fixed — CI/tooling

- `scripts/lint-library.sh`: the negative-render check was a bare
  command-substitution assignment under `set -euo pipefail`, so a render failure
  there aborted the whole script at that line — silently skipping every later
  check (image-pin enforcement, schema enforcement, posture/hardening guardrails,
  hook ordering) with stderr discarded. Wrapped it in the script's guarded
  `if ! neg=$(...)` idiom and kept stderr, so a broken negative render now reports
  `FAIL`, the rest of the gate still runs, and the script exits 1 (hf-tgh).

## [2.0.0] - 2026-07-14

The v2 rewrite — the first published release of this chart. Everything below
ships together.

### Changed (breaking) — pod selectors

- Every pod selector now carries `app.kubernetes.io/component`, and
  `commonLabels` no longer appear in any selector. This fixes two defects that
  were live on the library's default values:
  - **The Service routed traffic to the wrong pods.** `platform.selectorLabels`
    emitted only `name` + `instance`, and the same pair was stamped on CronJob
    pods and pre/post-install hook-Job pods. With `commonLabels` unset (the
    default) the Service selector matched them, so a scheduled job or an
    install hook could receive live traffic. The PodDisruptionBudget counted
    them too, skewing node-drain math. CronJob pods are now
    `component: cronjob`, hook-Job pods `component: preinstall`/`postinstall`,
    and the main workload `component: app`.
  - **Changing a `commonLabel` orphaned the Service.** The Service selector
    included `commonLabels` (the workload selectors correctly did not), so
    editing one instantly de-selected every running pod and dropped the Service
    to zero endpoints until the rollout completed. Selectors are now built only
    from stable, chart-derived labels. `commonLabels` still apply to object and
    pod *metadata*, which is what they are for.

  **Upgrade impact:** `spec.selector.matchLabels` is immutable on Deployment,
  StatefulSet, and DaemonSet, so this cannot be applied by `helm upgrade` to a
  release created before this change — the API server rejects it. Any such
  release must be uninstalled and reinstalled. This is why the change lands in
  2.0.0, before the chart has ever been published: there are no existing
  installs to migrate.

  `scripts/lint-library.sh` gained a `selector stability` gate asserting that no
  user-settable label can reach a selector and that job pods stay distinguishable
  from workload pods.

### Removed (breaking)

- Removed the `serviceEndpoints` feature (`serviceEndpoints.enabled`, the
  `<fullname>-service-endpoints` ConfigMap, and `platform.serviceEndpoints.configmap`).
  It inferred "subcharts" by ranging over every map-valued key in `.Values`, a
  heuristic that was coherent under v1's nested-subchart model but is meaningless
  under v2's flattened `import-values: [defaults]` contract — every defaults block
  looks like a subchart. Enabling it emitted entries like
  `podSecurityContext-endpoint: podSecurityContext.default.svc.cluster.local:80`.
  It had zero test coverage. Repairing it would require a real subchart registry
  that v2 does not have, so it was removed rather than patched.
- Removed the umbrella helpers it depended on, all of which had zero call sites:
  `global.enabledSubcharts`, `global.allEndpointsDynamic`, `global.allEndpoints`,
  `global.subchartEndpoint`, `platform.service.endpoint`.
- Removed `platform.util.merge` (`_util.tpl`), a bitnami-common style overlay
  helper documented as public API for advanced consumers. It had no call sites
  anywhere in the library. The "gate outside `fromYaml`" invariant it was
  documented alongside still holds and is unchanged.
- Removed dead values keys that no template ever read: `global.storageClass`,
  `serviceAccount.labels`, `cronJob.sidecars`. (`persistence.storageClass` is
  unaffected and still works.)

Golden snapshots were byte-identical across all four fixtures after these
removals, confirming the code was genuinely unreachable.

### Fixed

- `podDisruptionBudget.maxUnavailable` is now selectable. It was previously
  unreachable: `minAvailable` defaulted to `1`, and the template's
  `if minAvailable / else if maxUnavailable` chain meant the `maxUnavailable`
  branch could never be taken. `minAvailable` and `maxUnavailable` now both
  default to empty, are declared in `values.yaml`, fail closed if both are set,
  and fall back to `minAvailable: 1` when neither is — preserving the previous
  default output.

- `updateStrategy.type: Recreate` (Deployment) and `OnDelete`
  (StatefulSet/DaemonSet) no longer emit a `rollingUpdate` block. The templates
  passed the whole values map through `toYaml`, and the library ships
  `rollingUpdate` defaults, so flipping only `.type` produced an object the API
  server rejects with "may not be specified when strategy type is ..." —
  `helm template` passed, `helm install` failed. The `rollingUpdate` sub-key is
  now dropped whenever `.type` is anything other than `RollingUpdate`; consumers
  no longer have to null it out themselves. `scripts/lint-library.sh` gained an
  `updateStrategy compatibility` gate covering all three workload kinds.

- User-supplied containers are now hardened by default. `sidecars.containers`,
  `initContainers.containers`, `cronJob.containers`/`cronJob.initContainers`, and
  hook-Job sidecars/initContainers were passed straight through with `toYaml` and
  received no `containerSecurityContext`, so they ran as root with
  `allowPrivilegeEscalation` unset while the library's own container was
  hardened. Pod Security Standards are evaluated *per container*, so a single
  bare sidecar sank the whole pod's `restricted` posture — the library's
  headline "PSS-restricted by default" claim was false for every container a
  consumer supplied. The library's `containerSecurityContext` is now merged into
  each of them as a **default**, with the container's own `securityContext` keys
  winning on conflict, so an intentional relaxation (say a sidecar that needs its
  own `runAsUser`) still works and the escape hatch
  (`containerSecurityContext.enabled: false`) is unchanged.

  **Upgrade impact:** a sidecar/initContainer that silently relied on running as
  root, or on a writable root filesystem, will now start with the restricted
  context and may fail. The fix is a per-container `securityContext` override in
  that container's spec — not disabling the library default. `scripts/lint-library.sh`
  gained a `container hardening posture` gate proving a bare container of each of
  the four kinds cannot render unhardened, that an explicit override survives the
  merge, and that `containerSecurityContext.enabled: false` still injects nothing.

- A pre-install hook Job no longer deadlocks a fresh `helm install`. The Job is a
  `pre-install` hook, but the script ConfigMap it mounts and the ServiceAccount it
  referenced were plain resources — and Helm creates a release's normal resources
  only *after* the pre-install hooks have run. On a fresh install the hook pod had
  no ConfigMap to mount, and the ServiceAccount admission controller rejected it
  for a missing ServiceAccount (which it does regardless of
  `automountServiceAccountToken`), so the install hung until the hook timed out and
  then failed. The script ConfigMap now joins the same hook phase one weight ahead
  of the Job, and when the library creates the ServiceAccount, the pre-install Job
  gets a hook-scoped copy of it (`<fullname>-preinstall`, carrying
  `serviceAccount.annotations` so IRSA/Workload Identity still work). Both are
  reaped by `hook-delete-policy: before-hook-creation,hook-succeeded`. The hook copy
  is deliberately *not* named after the release ServiceAccount: a same-named copy
  would make `before-hook-creation` delete the live ServiceAccount on every
  `helm upgrade`, invalidating the bound tokens of the pods still running.
  `post-install` hooks were never affected (they run after the normal resources) and
  their script ConfigMap stays a release-tracked normal resource.

  `helm template` executes no hooks, so no golden or render test could ever have
  caught this; `scripts/lint-library.sh` gained a `hook Job dependency ordering`
  gate asserting the hook annotations and the weight ordering directly, including
  when a consumer overrides `jobs.preInstall.hookWeight`.

### Added

- `NOTES.txt` now warns when a Kind is enabled in values but was **not rendered**
  because the target cluster does not serve its API. Capability gating skips
  `Certificate`, `PeerAuthentication`, `HTTPRoute`, `ServiceMonitor` and
  `PodMonitor` when their CRDs are absent, and until now it did so in complete
  silence: an operator could set `certificate.enabled=true`, see a successful
  install, and believe cert-manager was issuing a certificate that does not exist.
  The warning names each skipped Kind, the apiVersions that were tried, and the
  `capabilities.apiVersions` / `--api-versions` escape hatch. The gate conditions
  in `platform.app` and the warning now read one shared table
  (`platform.capabilities.gatedKinds`), so a future gated feature cannot be wired
  into the emitter and forgotten in the warning — `scripts/lint-library.sh`
  asserts the two stay in sync. Manifest output is unchanged.

- Declared three values keys that templates already read but `values.yaml` and
  the schema never documented, so consumers could not discover them:
  root-level `topologySpreadConstraints` (takes precedence over
  `highAvailability.topologySpreadConstraints`), `daemonSet.tolerations`, and
  `podDisruptionBudget.maxUnavailable`. All three are now typed in
  `values.schema.reference.json` (and therefore in the `values.schema.json`
  copied into consumers), so a malformed value is rejected at render time
  instead of being silently ignored. `podDisruptionBudget.minAvailable` is
  typed alongside its mutually exclusive sibling.

### Changed (breaking)

- Tightened the supported Kubernetes window to an n-2 policy — the latest
  supported minor plus two behind it, currently **1.34–1.36**. `Chart.yaml`
  now enforces `kubeVersion: ">=1.34.0-0 <1.37.0-0"`, so consumers on
  Kubernetes 1.33 or older can no longer install charts built on this library
  and must stay on a pre-tightening release or upgrade their clusters. The CI
  render/kubeconform matrix, golden snapshots (now rendered at 1.34), and docs
  were narrowed to match, and the dead `flowcontrol.apiserver.k8s.io/v1beta3`
  fallbacks (removed upstream in 1.32) were pruned from the capability registry.
- Rewrote `platform-library` as a pure, capability-gated common library (chart
  `platform`, v2): no self-rendering stub templates. Consumers depend on it with
  `import-values: [defaults]` and render everything through the single public
  entrypoint `{{ include "platform.render" . }}`.
- Every generator negotiates the best available `apiVersion` through the
  Kind→apiVersion registry in `_capabilities.tpl` and skips CRD-backed objects
  whose API is absent. Targets Kubernetes 1.34–1.36 and Helm 4.
- Security defaults pass the Pod Security Standards "restricted" profile out of
  the box: `podSecurityContext`/`containerSecurityContext` enabled by default
  (runAsNonRoot, seccompProfile RuntimeDefault, readOnlyRootFilesystem).
- Hook Jobs and CronJobs are hardened the same way: pod + container security
  contexts, merged image pull secrets, and `jobs.resources` on the fallback
  container.
- ServiceAccount defaults: `serviceAccount.create: true` with
  `automountServiceAccountToken: false` rendered on the ServiceAccount and every
  pod spec; `enableServiceLinks: false`.
- Image pinning is enforced: rendering fails when `image.tag` and `image.digest`
  are both empty, and the values schema rejects the floating tag `latest`.
- mTLS fails closed: `mtls.allowedPrincipals` is required when `mtls.enabled=true`;
  `mtls.allowAllPrincipals: true` is the explicit wildcard opt-in.
- Cluster-scoped Kinds in `extraObjects` are refused unless
  `allowClusterScopedExtras: true` (the failure names the offending Kind).

### Added

- `extraObjects` — render any Kubernetes Kind through one capability-gated
  generic renderer — and `extraManifests` — raw (optionally templated) manifests.
- `scripts/new-app-chart.sh` scaffold: generates a consumer chart (dependency +
  `import-values`, `templates/app.yaml`, `templates/NOTES.txt`, overrides-only
  `values.yaml`, `values.schema.json`) with validated inputs (semver charsets,
  repo scheme allowlist, control-character/newline rejection).
- Values contract: `platform-library/values.schema.reference.json` (enums for
  `workload.type`, `image.pullPolicy`, `service.type`, `mtls.policy`,
  `networkPolicy.policyTypes`; conditional Gateway API `parentRefs`; typed,
  pattern-constrained shapes for `podSecurityContext`, `containerSecurityContext`,
  `serviceAccount.name`, and `ingress.hostname`), copied into fixtures and
  scaffolded charts as `values.schema.json` so Helm enforces the coalesced
  post-import values. Declared as draft-07 (`$schema`), matching the dialect
  Helm's built-in `gojsonschema` validator actually implements (helm/helm#13069).
- `secret.existingSecret` to reference a pre-created Secret; mutually exclusive
  with inline `data`/`stringData`; suppresses the chart-managed Secret and its
  rollout checksum.
- Self-signed TLS Secret reuse across upgrades via `lookup` — no certificate
  churn on `helm upgrade`.
- Install-time `NOTES.txt` warnings (`platform.notes`): plain-HTTP ingress,
  default-deny NetworkPolicy, hostPath / privileged / cluster-scoped RBAC
  content in the extras escape hatches, and plaintext secret material under
  `secret.stringData`/`secret.data` or inline TLS material under
  `ingress.secrets`.
- CI (`.github/workflows/ci.yaml`): shellcheck, `helm lint`, metaschema check,
  and `scripts/lint-library.sh` — fixture render matrix across k8s 1.34–1.36
  with expected-object-count assertions, committed golden snapshots,
  kubeconform (native + datreeio CRD schemas) across the matrix, a negative
  render proving CRD-backed objects drop when their API is absent, image-pin
  enforcement, and posture guardrail checks.
- Vendored kubeconform schemas (`tests/schemas/`): the exact core Kubernetes
  (1.34–1.36) and CRD schemas the render matrix and fixtures exercise, with
  provenance recorded in `tests/schemas/README.md` and refreshed by
  `scripts/vendor-schemas.sh`. `scripts/lint-library.sh` validates against
  these local copies only — see Fixed below.
- Test fixtures (`tests/fixtures/`): `minimal`, `full`, `stateful`, `daemon`
  consumer charts with golden snapshots under `tests/golden/`.
- Release automation (`.github/workflows/release.yaml`): semver-tag-triggered;
  verifies the tag against `Chart.yaml`, reruns the full CI gate, then
  `helm package` + `helm push` to `oci://ghcr.io/<owner>/charts`. This CHANGELOG.
- `statefulSet.persistentVolumeClaimRetentionPolicy.whenDeleted` /
  `.whenScaled` — reclaim `volumeClaimTemplates` PVCs on scale-down or
  StatefulSet deletion; unset (default) preserves Kubernetes' implicit
  `Retain`/`Retain` behavior.
- `certificate.issuerKind` — defaults to `ClusterIssuer`; set to `Issuer` to
  reference a namespaced cert-manager Issuer in multi-tenant clusters.
- Root-level `minReadySeconds` (default `0`, omitted from the manifest) for
  Deployment, StatefulSet, and DaemonSet.
- `serviceMonitor`/`podMonitor` `scheme`, `tlsConfig` (mTLS-scraped targets),
  and `sampleLimit` (per-target series cap).
- Documentation site (`site/`): a Docusaurus site with Getting Started and
  Migration Guide ported from the README/`docs/migration/v1-to-v2.md`, plus
  stubs for Values Reference, Capability Catalog, Security Model, and Examples
  & Recipes pending their own follow-up work. Deployed to GitHub Pages by
  `.github/workflows/docs.yaml`, kept separate from `ci.yaml`/`release.yaml` so
  a docs build failure never blocks a chart release.

### Fixed

- Gateway API HTTPRoute path match type is `PathPrefix` (was the invalid
  `ImplementationSpecific`).
- `full` fixture `mtls.mode` → `mtls.policy` typo.
- `tests/render.sh` no longer swallows `helm dependency update` errors.
- `scripts/lint-library.sh` kubeconform legs validate each matrix version's own
  render (previously the canonical 1.31 render was re-validated against every
  version's schemas, under-validating version-specific negotiation).
- Hook script ConfigMaps fail with an actionable message when the referenced
  script file is missing (previously silently skipped).
- Recurring kubeconform CI flake: schema validation fetched schemas from the
  jsdelivr CDN mirror at test time, which intermittently returned hard HTTP
  403s that survived retries. Schemas are now vendored into `tests/schemas/`
  and `scripts/lint-library.sh` makes zero network requests; the retry/backoff
  loop that papered over the CDN flakiness has been removed.
- `certificate.enabled` and `tlsSelfSigned.enabled` fail closed when both are
  `true` (previously both silently targeted the same Secret `<fullname>-tls`
  and collided).
- Self-signed TLS Secret reuse now rotates near expiry instead of reusing the
  cert forever: generation stamps the annotation `platform/tls-not-after`
  (RFC3339, since Helm/sprig cannot parse x509 NotAfter from the looked-up
  cert), and reuse is skipped once within the new `tlsSelfSigned.renewBeforeDays`
  (default `30`) of that recorded expiry. A legacy Secret with no
  `platform/tls-not-after` annotation regenerates once, acquiring rotation
  metadata for subsequent upgrades.

### Removed

- The v1 root-level chart layout and the root `configuration.yaml` v1 artifact.
  Consumer configuration lives in the consumer chart's `values.yaml` (see the
  README Quick Start or `scripts/new-app-chart.sh`).

### Future work

- Sign pushed charts (cosign, keyless OIDC) and attach provenance to OCI
  releases.
