# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions track the `platform-library` chart version (`platform-library/Chart.yaml`);
releases are tagged `vX.Y.Z` and published to `oci://ghcr.io/caretak3r/charts`.

## [Unreleased]

The v2 rewrite. Everything below ships together as **2.0.0**.

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
- Hook script ConfigMaps fail with an actionable message when the referenced
  script file is missing (previously silently skipped).

### Removed

- The v1 root-level chart layout and the root `configuration.yaml` v1 artifact.
  Consumer configuration lives in the consumer chart's `values.yaml` (see the
  README Quick Start or `scripts/new-app-chart.sh`).

### Future work

- Sign pushed charts (cosign, keyless OIDC) and attach provenance to OCI
  releases.
