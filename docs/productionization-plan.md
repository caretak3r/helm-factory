# platform-library Productionization & Helm v4 Modernization Plan

> Status: proposed · Scope: `platform-library` (chart `platform`, v2), `scripts/`, `tests/`, `.github/`, `docs/`
> Baseline: `main` @ `4fb9386` ("platform-library v2 — capability gates + secure-by-default hardening")
> Prior review reconciled: `fable5-review.md` (2026-07-01, committed at repo root as of this branch)

## Executive summary

The v2 rewrite (`4fb9386`) already shipped the large majority of `fable5-review.md`'s P0/P1 findings: hardened security contexts, dedicated no-token-by-default ServiceAccounts, fail-closed mTLS, enforced image pinning, TLS-secret reuse via `lookup`, CI, golden-snapshot tests, and a tag-triggered OCI release workflow. The **Fable5 Review Reconciliation** table below verifies each of the 15 original findings against current `main`, file:line by file:line — 9 are fully resolved, 4 are partially resolved (the mechanism landed but a real gap remains inside it), and 2 were resolved via a different design choice than the review proposed (documented tradeoffs, not defects).

What remains is threefold:

1. **A residual security/correctness tail**: a `values.schema.reference.json` that declares JSON Schema draft 2020-12 but is validated by Helm's draft-07-ceiling engine, a ServiceAccount/pre-install-hook creation-order gap that isn't actually preventable by the documented workaround, and a couple of no-longer-optional CRD-backed Kinds missing from the capability registry.
2. **Helm v4 capability adoption that hasn't been exercised yet**: version-skew-aware tooling, Server-Side-Apply migration guidance, OCI-digest installs, and a signed/attested release pipeline (the CHANGELOG already flags cosign as deliberately deferred).
3. **A documentation and repo-hygiene debt**: 740KB of accidentally-committed full-repo dumps sitting in `docs/`, `docs/specs`/`docs/prd` describing a test harness that no longer matches `scripts/lint-library.sh`, and no public docs site despite a schema-rich, capability-gated library that badly wants one.

None of the work below requires re-doing anything already shipped. Total: 7 dimensions, 49 work items, 0 items rated P0 (nothing exploitable is currently open), 13 rated P1.

---

## Fable5 Review Reconciliation

Every finding from `fable5-review.md`, checked against `main` as of this branch.

| # | Finding | Status | Evidence |
|---|---|---|---|
| 1 | Security contexts disabled by default | **Resolved** | `platform-library/values.yaml:468-486` — `podSecurityContext.enabled: true`, `containerSecurityContext.enabled: true`, `runAsNonRoot`, `readOnlyRootFilesystem: true`, `seccompProfile.type: RuntimeDefault` all default-on |
| 2 | Hook Jobs / CronJobs unconstrained | **Resolved** (for library-managed containers) | `_helpers.tpl:688-690` (`renderHookJob` sets container securityContext), `_cronjob.yaml:55-57` (pod SC), `:79-81` (fallback container SC), `:58-64` (merged `global.imagePullSecrets` + `image.pullSecrets`), `:84-86` (`jobs.resources` on fallback container). User-supplied `cronJob.containers`/sidecars still pass through verbatim — documented trust-model decision (README.md:407-410), not a gap. |
| 3 | Self-signed TLS regenerates every render/upgrade | **Resolved** | `_tls-selfsigned.yaml:14-22` — `lookup "v1" "Secret"` reused when present; template-time regeneration is expected/documented (README.md:608-614) |
| 4 | Schema validation not enforced | **Partially open** | `values.schema.reference.json` is now copied to `values.schema.json` in scaffolded/fixture charts (CORE.md:222-225) and CI runs a metaschema check + values-schema negative tests (`lint-library.sh:203-218`). Still open: the schema declares `"$schema": "https://json-schema.org/draft/2020-12/schema"` (`values.schema.reference.json:2`) while Helm's built-in validator only understands draft-07 semantics (see **SEC-1**), and `additionalProperties: true` leaves most of the ~80 root keys unconstrained. |
| 5 | `image.tag` defaults to `latest` | **Resolved** | `values.yaml:41` (`tag: ""`, no fallback), `_helpers.tpl:63-69` (`fail` when both tag and digest empty), `values.schema.reference.json:24` (`"not": {"const": "latest"}`) |
| 6 | ServiceAccount: no dedicated SA, token always mounted, knob a no-op | **Resolved**, with a related still-open ordering gap | `values.yaml:451-453` (`create: true`, `automountServiceAccountToken: false`), rendered at `_helpers.tpl:192` (pod spec) and `_helpers.tpl:386` (SA object). See **SEC-2** for the pre-install-hook chicken-and-egg case this default combination creates. |
| 7 | mTLS wide open by default | **Resolved** | `values.yaml:302-303` (`allowedPrincipals: []`, `allowAllPrincipals: false`), `_mtls.yaml:4-9` (`fail` unless principals set or wildcard opted into) |
| 8 | Plaintext secrets flow through values | **Partially open** | `secret.existingSecret` is mutually-exclusive-enforced (`_secret.yaml:1-4`) and documented as the preferred path (README.md:449-454, schema descriptions at `values.schema.reference.json:47,58`). Still open: `secret.stringData`/`ingress.secrets` still render silently with no install-time NOTES warning, unlike the parallel `hostPath`/`privileged`/`ClusterRole` warnings that already exist (`_notes.tpl:21-30`). See **SEC-3**. |
| 9 | Escape hatches powerful and silent | **Resolved** | `allowClusterScopedExtras` gate (`values.yaml:621`, enforced `_util.tpl:98-100`); NOTES warnings for `hostPath`/`privileged`/cluster-scoped RBAC in extras (`_notes.tpl:21-30`) |
| 10 | Network exposure defaults (ingress TLS, NetworkPolicy default-deny) | **Resolved differently** | `ingress.tls` stays `false` by default but now WARN via NOTES (`_notes.tpl:14-16`, README.md:205 "deliberately not flipped"); NetworkPolicy default-deny footgun also gets a NOTES warning (`_notes.tpl:17-19`) rather than a changed default. Intentional design tradeoff — see **Decisions needed**. |
| 11 | No CI at all | **Resolved** | `.github/workflows/ci.yaml` |
| 12 | Tests assert exit codes, not output | **Resolved**, with a residual coverage gap | Golden-file diffs (`lint-library.sh:129-148`) and expected-kind-count assertions (`lint-library.sh:41-49,117-123`) now exist across 4 fixtures. Still open: no fixture/golden combines hook Jobs with StatefulSet/DaemonSet/persistence, and `jobs.postInstall` is untested by any fixture. See **TEST-1**. |
| 13 | `new-app-chart.sh` argument injection | **Resolved** | Control-char/newline rejection (`new-app-chart.sh:58,62-64`), semver charset for `--version`/`--app-version` (`:59-60,65-68`), repo scheme allowlist (`:61,69-70`) |
| 14 | No release/publish story | **Partially open** | `.github/workflows/release.yaml` exists (tag-triggered, tag-vs-`Chart.yaml` version check at `release.yaml:37-45`, full CI gate re-run, `helm package` + `helm push` to GHCR). Still open: no cosign/provenance signing — explicitly deferred (`release.yaml:74-75` comment, `CHANGELOG.md:88`). See **CI-1**. |
| 15 | Docs drift (CORE.md substantially v1) | **Resolved for CORE.md; drift reappeared elsewhere** | `CORE.md` is fully v2 (directory listing, rendering order, consumer integration all current; "Last Updated: 2026-07-04"). New drift: `docs/specs/platform-library-v2-architecture.md` and `docs/prd/platform-library-v2.md` still describe a 2-fixture test harness and pre-hardening kubeconform flags that predate the current `lint-library.sh`. See **TEST-5** / **DOC-5**. |

---

## Master prioritized table

| ID | Item | Dimension | Priority | Effort | Depends on |
|---|---|---|---|---|---|
| LAY-1 | Remove accidental Repomix dumps from `docs/` | Layout | P1 | S | — |
| LAY-3 | Gitignore Repomix output patterns | Layout | P1 | S | LAY-1 |
| SEC-1 | Fix `values.schema.reference.json` draft mismatch + widen coverage | Secure defaults | P1 | M | — |
| SEC-2 | Fix ServiceAccount / pre-install-hook creation-order gap | Secure defaults | P1 | S | — |
| SEC-3 | NOTES warning parity for `secret.stringData`/`ingress.secrets` | Secure defaults | P2 | S | — |
| CAP-9 | Add `persistentVolumeClaimRetentionPolicy` to StatefulSet | Capability registry | P1 | S | — |
| CAP-1 | Remove dead pre-1.31 apiVersion fallbacks | Capability registry | P2 | S | — |
| CAP-2 | Register MutatingAdmissionPolicy/Binding | Capability registry | P2 | S | — |
| CAP-3 | Register VolumeSnapshot family | Capability registry | P2 | S | — |
| CAP-6 | Register DRA Kinds (ResourceClaim/ResourceClaimTemplate/DeviceClass) | Capability registry | P2 | S | — |
| CAP-7 | Un-hardcode `gatewayApi.apiVersion` default | Capability registry | P2 | S | — |
| CAP-8 | Add `certificate.issuerKind` for namespaced Issuer | Capability registry | P2 | S | — |
| CAP-10 | Add `minReadySeconds` to workloads | Capability registry | P2 | S | — |
| CAP-13 | Add `tlsConfig`/`sampleLimit`/`scheme` to ServiceMonitor/PodMonitor | Capability registry | P2 | S | — |
| CAP-4 | Gateway API TCPRoute/TLSRoute/UDPRoute/BackendTLSPolicy (watch) | Capability registry | P3 | S | — |
| CAP-5 | AdminNetworkPolicy/BaselineAdminNetworkPolicy (watch) | Capability registry | P3 | S | — |
| CAP-11 | Service dual-stack/topology fields | Capability registry | P3 | M | — |
| CAP-12 | ConfigMap `binaryData` support | Capability registry | P3 | S | — |
| HV4-1 | Publish Helm↔K8s version-skew compatibility matrix | Helm v4 adoption | P1 | S | — |
| HV4-4 | Document Server-Side-Apply default + `extraObjects` conflict guidance | Helm v4 adoption | P1 | M | — |
| HV4-11 | Choose provenance/signing mechanism (feeds CI-1) | Helm v4 adoption | P1 | S | — |
| HV4-2 | CI leg pinning oldest-supported Helm 4.0.x binary | Helm v4 adoption | P2 | M | HV4-1 |
| HV4-3 | Document OCI digest installs + multi-doc values files | Helm v4 adoption | P2 | S | — |
| HV4-12 | Scaffold `helm test` support in `new-app-chart.sh` | Helm v4 adoption | P2 | S | — |
| HV4-7 | Cross-link JSON Schema draft ceiling in docs | Helm v4 adoption | P2 | S | SEC-1 |
| HV4-5 | Post-renderer-as-plugin note for future recipes | Helm v4 adoption | P3 | S | — |
| HV4-6 | Adopt renamed CLI flags in all new docs/examples | Helm v4 adoption | P3 | S | — |
| HV4-8 | Surface `.Capabilities.HelmVersion` in an optional annotation | Helm v4 adoption | P3 | S | — |
| HV4-9 | Document `--skip-schema-validation` for air-gapped consumers | Helm v4 adoption | P3 | S | — |
| HV4-10 | Watch item: Charts v3 | Helm v4 adoption | P3 | S | — |
| TEST-1 | Combined-coverage fixture (hooks × StatefulSet/DaemonSet × persistence) | Testing | P1 | M | CAP-9, SEC-2 |
| TEST-3 | Expand values-schema negative-fixture coverage | Testing | P2 | M | SEC-1 |
| TEST-4 | Per-version golden snapshots at floor (1.31) + ceiling (1.36) | Testing | P2 | M | CAP-1..CAP-13 |
| TEST-2 | Make kubeconform required-by-default locally | Testing | P2 | S | — |
| TEST-5 | Resync `docs/specs`+`docs/prd` to actual test harness | Testing | P2 | S | TEST-1 |
| TEST-6 | `helm test` golden coverage | Testing | P3 | S | HV4-12 |
| CI-1 | cosign keyless OIDC signing of pushed OCI chart | CI/CD & supply chain | P1 | M | HV4-11 |
| CI-2 | CHANGELOG/tag discipline check in release workflow | CI/CD & supply chain | P2 | S | — |
| CI-3 | SBOM generation + attestation | CI/CD & supply chain | P3 | M | CI-1 |
| LAY-2 | Archive `fable5-review.md` as superseded | Layout | P2 | S | this doc merged |
| LAY-4 | Script hardening follow-ups | Layout | P3 | S | — |
| LAY-5 | `docs/` reorg for Docusaurus IA | Layout | P2 | M | DOC-1 |
| DOC-1 | Scaffold Docusaurus site + IA | Documentation site | P1 | L | — |
| DOC-3 | GitHub Pages deploy workflow | Documentation site | P1 | M | DOC-1 |
| DOC-2 | Values-reference generation pipeline | Documentation site | P1 | M | DOC-1 |
| DOC-4 | Capability catalog page generated from registry | Documentation site | P2 | M | DOC-1, CAP-1..13 |
| DOC-6 | Security model page | Documentation site | P2 | M | DOC-1 |
| DOC-7 | Migration guide refresh (Helm-4-minor + SSA) | Documentation site | P2 | S | DOC-1, HV4-4 |
| DOC-5 | Fix remaining `docs/specs`/`docs/prd` drift (= TEST-5) | Documentation site | P2 | S | TEST-1 |

49 items: 0 P0, 13 P1, 24 P2, 12 P3. (CI-4, in Section 5, is a "no action recommended" note, not a work item, and is intentionally excluded from this table and count.)

---

## 1. Secure-by-default & one-size-fits-all defaults

The zero-config target (PSS `restricted`, pinned images, dedicated SA, no token automount, fail-closed on unsafe input) is already the default posture on `main` — see the reconciliation table above for items 1, 2, 5, 6, 7, 9. The remaining work is narrower and more surgical.

### SEC-1 — Fix `values.schema.reference.json` JSON Schema draft mismatch, widen coverage
**Problem:** `values.schema.reference.json:2` declares `"$schema": "https://json-schema.org/draft/2020-12/schema"`. Helm's built-in schema validator (`gojsonschema`, unchanged from v3 into v4) only implements draft-04 through draft-07 semantics; a GitHub issue proposing an upgrade to a current-draft library was closed as not-planned (helm/helm#13069). The schema currently only uses draft-07-compatible keywords (`if`/`then`/`allOf`/`anyOf`, `type`, `enum`, `not`), so nothing is silently broken *today*, but the `$schema` declaration actively misleads chart authors and any IDE/external validator (e.g. the JSON Schema VS Code extension) into checking against a dialect Helm doesn't enforce — a false sense of safety. Separately, `additionalProperties: true` is set on nearly every object in the schema, so ~60 of the ~80 root value keys (e.g. `podSecurityContext`, `serviceAccount.name`, `networkPolicy.ingress`/`egress`, `gatewayApi.httpRoute.matches`) have zero shape validation.
**Change:** Set `"$schema"` to `"http://json-schema.org/draft-07/schema#"` to match what Helm actually enforces (or add a comment explaining the intentional divergence if 2020-12 is kept for external tooling only — pick one, don't ship both silently). Incrementally tighten `additionalProperties`/add `enum`/`pattern` constraints for the highest-risk fields first: `networkPolicy.policyTypes`, `podSecurityContext`/`containerSecurityContext` (`enabled` + top-level shape), `serviceAccount.name` (RFC 1123 pattern), `certificate.issuer` (already partially done).
**Priority/Effort:** P1 / M. **Dependencies:** none.
**Acceptance criteria:** `$schema` matches Helm's actual validation dialect (or the divergence is documented inline); `check-jsonschema --check-metaschema` still passes in CI; at least 5 additional root keys gain non-trivial `enum`/`pattern`/`type` constraints beyond today's set; existing fixtures still validate.

### SEC-2 — Fix ServiceAccount / pre-install-hook creation-order gap
**Problem:** Per Helm's hook lifecycle (`https://helm.sh/docs/topics/charts_hooks/`), on a first `helm install`, pre-install hooks execute and are awaited *before* any normal (non-hook) resources are created. The library's `ServiceAccount` is a normal resource (`_helpers.tpl:373-388`, no hook annotation), while `jobs.preInstall` renders a hook Job (`_helpers.tpl:596-763`, `helm.sh/hook: pre-install,pre-upgrade` at `:723`) that references the same not-yet-created SA (`_helpers.tpl:737`, `serviceAccountName: {{ include "platform.serviceAccountName" $ctx }}`). With the library's own defaults (`serviceAccount.create: true`), a first install with `jobs.preInstall.enabled: true` and no override will fail pod admission because the referenced ServiceAccount doesn't exist yet. README.md:670-675 documents this as a known caveat with three manual workarounds — but nothing in the render path detects or prevents the footgun, and the *library's own defaults* are exactly the combination that triggers it.
**Change:** Detect the unsafe combination at render time and `fail` with the same actionable guidance already in the README (turn `serviceAccount.create: false`, pre-create the SA, or hook the SA itself), rather than relying on documentation alone to prevent an install-time failure. A stronger, API-breaking option — making SA creation a pre-install hook by default whenever `jobs.preInstall.enabled` is true — is called out under **Decisions needed** since it changes default rendered output.
**Priority/Effort:** P1 / S. **Dependencies:** none.
**Acceptance criteria:** rendering `jobs.preInstall.enabled: true` with `serviceAccount.create: true` (defaults) and no SA-as-hook override produces a clear `fail` at template time, not a first-install pod-admission failure; a fixture covers this combination (shared with TEST-1); README's caveat section is simplified to reference the new fail-fast message instead of the previous "just be careful" framing.

### SEC-3 — NOTES warning parity for `secret.stringData`/`ingress.secrets`
**Problem:** `_notes.tpl:21-30` already warns on `hostPath`, `privileged: true`, and cluster-scoped RBAC appearing anywhere in the escape-hatch surface. It does not warn when `secret.enabled: true` with `secret.stringData`/`secret.data` set, or `ingress.secrets` used — both of which the README (line 449-454, "Warning — secrets in values are plaintext...") and schema (`values.schema.reference.json:47,58`, which does use the word "DISCOURAGED") already flag in prose, but the render path stays silent.
**Change:** Extend `platform.notes` (`_notes.tpl`) to warn when `secret.enabled && (secret.stringData || secret.data)` is set, and when `ingress.secrets` is non-empty, mirroring the existing warning pattern and message style.
**Priority/Effort:** P2 / S. **Dependencies:** none.
**Acceptance criteria:** a fixture with `secret.stringData` set shows the new WARNING in rendered NOTES; existing warnings are unaffected; `platform.notes` output is still absent from `helm template` manifest output (per the existing invariant documented at `_notes.tpl:5-8`).

---

## 2. Helm v4 capability adoption

This is the section with the deepest research obligation. Findings below are each cited to the specific Helm v4 doc page fetched during this review (`helm.sh/docs`, version 4.2.2 as served).

### HV4-1 — Publish a Helm↔Kubernetes version-skew compatibility matrix
**Problem:** README.md/CORE.md/Chart.yaml (`kubeVersion: ">=1.31.0-0 <1.37.0-0"`) advertise support for Kubernetes 1.31–1.36 under "Helm 4.0+." Helm's own version-skew policy (`https://helm.sh/docs/topics/version_skew/`) states each Helm 4.x *minor* is compiled against a specific Kubernetes client and supports only n-3 versions back:

| Helm version | Supported Kubernetes versions |
|---|---|
| 4.0.x | 1.34.x – 1.31.x |
| 4.1.x | 1.35.x – 1.32.x |
| 4.2.x | 1.36.x – 1.33.x |

CI currently pins Helm 4.2.0 (`.github/workflows/ci.yaml:23`) and validates rendering with `--kube-version 1.31` through `1.36` (`lint-library.sh:31`). This is safe for `helm template`/lint purposes — no real cluster connection happens, so API-version negotiation is simulated regardless of the installed Helm client's compiled-in K8s version — but it means CI's simulated 1.31 pass does **not** prove a real `helm install`/`upgrade` against a live 1.31 cluster works, because Helm 4.2.x's own version-skew policy says it isn't supported against 1.31 in the first place. The gap between "renders correctly" and "safe to actually run" against the floor of the advertised range is currently undocumented.
**Change:** Add a compatibility matrix (Helm version → supported K8s versions, sourced from the table above) to README.md and the new docs site, with an explicit note: *the library's `helm template`/lint validation covers the full 1.31–1.36 matrix regardless of the Helm binary used, but consumers running real installs/upgrades against 1.31 or 1.32 clusters should use a Helm 4.0.x or 4.1.x client per Helm's version-skew policy, not 4.2.x.*
**Priority/Effort:** P1 / S. **Dependencies:** none.
**Acceptance criteria:** matrix appears in README and docs site with a citation to `helm.sh/docs/topics/version_skew`; CI workflow comment cross-references it.

### HV4-2 — CI leg pinning the oldest-supported Helm 4.0.x binary
**Problem:** Following from HV4-1, CI only ever exercises the library through a single Helm 4.2.0 binary. Template-syntax or function behavior that differs between Helm 4.0.x and 4.2.x (e.g., any function added in a later 4.x point release) would not be caught until a consumer on an older Helm binary hits it.
**Change:** Add a second CI job (or a manual local step, if a full matrix job is judged not worth the CI minutes) that runs `scripts/lint-library.sh` against a pinned Helm 4.0.x binary, at minimum for the `--kube-version 1.31` leg.
**Priority/Effort:** P2 / M. **Dependencies:** HV4-1.
**Acceptance criteria:** CI has a passing job using a Helm 4.0.x binary; failure clearly distinguishes "template incompatible with older Helm" from other lint failures.

### HV4-3 — Document OCI install-by-digest and multi-doc values files
**Problem:** Helm 4 highlights (`helm.sh/docs/overview`, "What's New" / "Summary") two consumer-facing features not currently mentioned anywhere in this repo's docs: installing charts by OCI digest (`helm install myapp oci://registry/charts/app@sha256:...`, `helm.sh/docs/topics/registries`) and splitting `values.yaml` across multiple files at install time. Both are directly relevant here: the library already enforces `image.*` digest pinning as the preferred pattern (values.yaml:35-37) — the *chart itself* being installable by digest is the same supply-chain principle applied one level up, and multi-doc values files are a natural fit for consumers with large per-environment overrides.
**Change:** Add a "Pinning the chart by digest" callout to the README Releasing section (`oci://ghcr.io/caretak3r/charts/platform@sha256:...`) and a values-file-splitting example to the docs site's Getting Started page.
**Priority/Effort:** P2 / S. **Dependencies:** none.
**Acceptance criteria:** both features documented with a working example; cross-referenced from CI-1 (the digest a consumer would pin is exactly what cosign will sign).

### HV4-4 — Document Server-Side-Apply default change and `extraObjects` conflict guidance
**Problem:** Helm 4 defaults **new** installs to Server-Side Apply (SSA); upgrades of releases first created under Helm 3 continue using client-side apply unless `--server-side` is passed explicitly (`helm.sh/docs/overview`, "Server-Side Apply" section). This is the single highest-impact Helm-v4 behavioral change for this library, because `platform.extraObjects`/`platform.extraManifests` are explicitly designed so that "whatever values say, gets created" (README.md:848-857) — including cases where two independently-installed consumer charts both declare, say, a `Role` with the same name in the same namespace via `extraObjects`. Under client-side apply this silently last-writer-wins; under SSA it produces a field-manager conflict error unless `--force-conflicts` is set. Nothing in the repo currently mentions this.
**Change:** Add a "Server-Side Apply and shared objects" note to the Security Model / trust-model section (README.md:848-857 area and the new docs site) explaining: (a) new consumer-chart installs get SSA by default in Helm 4, (b) `extraObjects`/`extraManifests` that create objects shared across multiple releases will now surface ownership conflicts instead of silently overwriting, which is a *safety improvement* but a *behavior change* consumers should expect, and (c) how to resolve a conflict (`--force-conflicts`, or scope the object to one owning release).
**Priority/Effort:** P1 / M. **Dependencies:** none.
**Acceptance criteria:** doc section published; migration guide (DOC-7) cross-references it for consumers upgrading Helm 3→4.

### HV4-11 — Choose the provenance/signing mechanism (decision, feeds CI-1)
**Problem:** Helm 4 offers no new built-in cosign/Sigstore integration — chart signing is still either (a) classic GPG provenance files (`helm package --sign`, `.tgz.prov`, `helm.sh/docs/topics/provenance`), which predates OCI and isn't documented as working with `helm push`, or (b) the third-party `helm-sigstore` plugin, or (c) signing the pushed OCI artifact directly with `cosign` (chart-agnostic, since an OCI Helm chart is just an OCI artifact — `helm.sh/docs/topics/registries`, "Helm chart manifest" section). `CHANGELOG.md:88` and `release.yaml:74-75` already flag signing as deferred future work; this item is the decision that unblocks it.
**Change:** Recommend `cosign` keyless OIDC signing of the pushed OCI artifact as the default path (no long-lived key material to manage in GitHub Actions, verification doesn't require Helm-specific tooling on the consumer side, works uniformly whether the artifact is fetched via `helm pull`/`docker pull`/`oras pull`). Confirm with the captain before implementing (see **Decisions needed**).
**Priority/Effort:** P1 / S. **Dependencies:** none.
**Acceptance criteria:** a decision is recorded (cosign keyless vs. GPG provenance vs. both); CI-1 implements it.

### HV4-12 — Scaffold `helm test` support in `new-app-chart.sh`
**Problem:** Helm's chart-test convention (`helm.sh/docs/topics/chart_tests`, `helm.sh/hook: test` annotation, run via `helm test <release>`) is a standard, expected feature of production charts. Because `platform-library` is a pure library chart with no self-rendering templates, it cannot ship a test itself — but `scripts/new-app-chart.sh`, which already scaffolds `templates/app.yaml` and `templates/NOTES.txt` for consumers (README.md:944, CORE.md:180-188), does not scaffold a `templates/tests/` directory, so every consumer chart currently starts with zero `helm test` coverage.
**Change:** Extend `new-app-chart.sh` to optionally scaffold a basic `templates/tests/test-connection.yaml` (a `wget`/`curl` Pod hitting the primary Service port, mirroring the pattern Helm's own `helm create` uses) when `service.enabled` is set in the generated values.
**Priority/Effort:** P2 / S. **Dependencies:** none.
**Acceptance criteria:** running the scaffold on a chart with `service.enabled: true` produces a working `templates/tests/test-connection.yaml`; `helm test` succeeds against a live install of the `full` fixture (or equivalent) in a manual/CI smoke check (TEST-6).

### Other Helm v4 adoption items (P2/P3, documentation-only or low-effort)
- **HV4-7** — Cross-link the JSON Schema draft-ceiling note (SEC-1) from the docs site's Values Reference and Getting Started pages, so chart authors extending the schema don't rediscover the draft-07 limitation independently.
- **HV4-5** — Helm 4 moved post-renderers to a plugin model; raw executables are no longer accepted by `--post-renderer` (`helm.sh/docs/topics/advanced`, "Breaking Changes"). The repo has no current post-render examples (grep-confirmed), so this is a pre-emptive note for the docs site's future "recipes" page, not a fix.
- **HV4-6** — Helm 4 renamed `--atomic`→`--rollback-on-failure` and `--force`→`--force-replace` (old flags still work but emit deprecation warnings). No current README/docs examples use the old names (grep-confirmed) — adopt the new names in all *new* documentation going forward.
- **HV4-8** — Optionally surface `.Capabilities.HelmVersion.Version` (unchanged object shape from v3, `helm.sh/docs/chart_template_guide/builtin_objects`) as a `platform.sh/rendered-with-helm` annotation for support/debugging. Nice-to-have.
- **HV4-9** — Document `helm lint --skip-schema-validation`/`helm install --skip-schema-validation` for air-gapped environments (`helm.sh/docs/topics/charts`, "Schema Files"). Not currently needed (the schema has no remote `$ref`s) but worth a docs-site callout since it's the standard escape hatch if that ever changes.
- **HV4-10** — Helm 4's own docs note "Charts v3: Coming soon. v2 charts continue to work unchanged." No action; add a one-line watch item to the docs site's Helm v4 compatibility page so a future contributor knows this was considered.

---

## 3. Capability registry completeness

Audited `_capabilities.tpl`'s Kind→apiVersion registry (lines 68-158) against the library's own stated floor (`Chart.yaml`: `kubeVersion: ">=1.31.0-0 <1.37.0-0"`) and current upstream API status.

### Dead fallback removal
**CAP-1 — Remove dead pre-1.31 apiVersion fallbacks.** Every one of these fallback entries targets an API version removed from Kubernetes *before* the library's stated floor of 1.31, so they can never negotiate on any supported cluster and exist only as inert bytes:
- `CronJob: [..., "batch/v1beta1/CronJob"]` (`_capabilities.tpl:92`) — `batch/v1beta1` removed in 1.25.
- `PodDisruptionBudget: [..., "policy/v1beta1/PodDisruptionBudget"]` (`_capabilities.tpl:96`) — `policy/v1beta1` removed in 1.25.
- `HorizontalPodAutoscaler: [..., "autoscaling/v2beta2/...", "autoscaling/v2beta1/..."]` (`_capabilities.tpl:94`) — both removed in 1.26.
- `Ingress: [..., "networking.k8s.io/v1beta1/Ingress", "extensions/v1beta1/Ingress"]` (`_capabilities.tpl:98`) — removed in 1.22 and earlier.
**Change:** Drop the dead entries, leaving only the GA `v1` preference for each Kind.
**Priority/Effort:** P2 / S. **Dependencies:** none.
**Acceptance criteria:** golden snapshots unchanged (these fallbacks never won negotiation on any tested version); `_capabilities.tpl` registry comment updated to note the floor-version assumption so future contributors don't re-add fallbacks below 1.31.

### Missing Kinds — new/GA within the library's own 1.31–1.36 window
- **CAP-6 — Register Dynamic Resource Allocation Kinds.** DRA's core API (`resource.k8s.io/v1`: `ResourceClaim`, `ResourceClaimTemplate`, `DeviceClass`) graduated to GA in Kubernetes 1.34 with the feature gate locked (non-disable-able) as of 1.35 — squarely inside the library's advertised 1.31–1.36 range. GPU/hardware-accelerator consumers currently have no registry entry and must manually set `apiVersion` on every `extraObjects` DRA spec. **Priority/Effort:** P2 / S.
- **CAP-2 — Register `MutatingAdmissionPolicy`/`MutatingAdmissionPolicyBinding`.** The registry already carries `ValidatingAdmissionPolicy`/`...Binding` (`_capabilities.tpl:123-124`) but not their mutating counterpart, a newer addition to the same `admissionregistration.k8s.io` family. **Priority/Effort:** P2 / S.
- **CAP-3 — Register the VolumeSnapshot family** (`snapshot.storage.k8s.io/v1`: `VolumeSnapshot`, `VolumeSnapshotClass`, `VolumeSnapshotContent`). Long-GA upstream and a natural pairing with the library's existing PVC/StatefulSet generators, but entirely absent from the registry today — any consumer using `extraObjects` for snapshot Kinds gets no negotiation and must classify `VolumeSnapshotClass`'s cluster scope manually. **Priority/Effort:** P2 / S.

### Watch items — explicitly not yet GA upstream
- **CAP-4 — Gateway API TCPRoute/TLSRoute/UDPRoute/BackendTLSPolicy.** Confirmed via Gateway API's own release notes: `HTTPRoute` and `GRPCRoute` are Standard-channel GA (GRPCRoute since v1.1), but `TCPRoute`/`TLSRoute`/`UDPRoute` remain in the **Experimental** channel as of the current Gateway API release. Do not register these yet; revisit when they graduate. **Priority/Effort:** P3 / S (a backlog note, not code, until then).
- **CAP-5 — AdminNetworkPolicy/BaselineAdminNetworkPolicy.** Confirmed still `v1alpha1` upstream (`policy.networking.k8s.io`), not GA. Same treatment as CAP-4. **Priority/Effort:** P3 / S.

### Correctness gaps found alongside the registry audit
- **CAP-7 — Un-hardcode `gatewayApi.apiVersion`'s default.** `values.yaml:242` sets `gatewayApi.apiVersion: gateway.networking.k8s.io/v1` as a hardcoded default, unlike every other CRD-backed generator (Certificate, Ingress, PDB), which leave the values-level `apiVersion` empty and let `_capabilities.tpl`'s negotiation pick the best available version. Because Gateway API v1 is correct on any reasonably current cluster this doesn't misfire today, but it silently disables capability negotiation for the one Kind that has it hardcoded — a cluster running only Gateway API v1beta1 CRDs (pre-1.0 Gateway API installs) would get a hard `apiVersion` mismatch instead of a clean skip-or-negotiate. **Change:** default `gatewayApi.apiVersion: ""` and let negotiation run, matching the pattern used everywhere else. **Priority/Effort:** P2 / S.
- **CAP-8 — Add `certificate.issuerKind`.** `_certificate.yaml:34` hardcodes `issuerRef.kind: ClusterIssuer`; multi-tenant clusters commonly scope cert-manager `Issuer` (namespaced) rather than `ClusterIssuer` per team. **Change:** add `certificate.issuerKind` (default `ClusterIssuer`, allow `Issuer`). **Priority/Effort:** P2 / S.
- **CAP-9 — Add `persistentVolumeClaimRetentionPolicy` to StatefulSet.** GA since Kubernetes 1.27, entirely absent from `_statefulset.yaml`; without it, PVCs created from `volumeClaimTemplates` are never automatically reclaimed on scale-down or StatefulSet deletion, which is surprising default behavior for a "secure/sane by default" library. **Priority/Effort:** P1 / S (bumped above the other CAP items because it's a data-lifecycle correctness gap, not just a missing knob).
- **CAP-10 — Add `minReadySeconds`.** Missing from Deployment, StatefulSet, and DaemonSet (grep-confirmed absent repo-wide); a standard rollout-safety field with no library support today. **Priority/Effort:** P2 / S.
- **CAP-13 — Add `tlsConfig`/`sampleLimit`/`scheme` to ServiceMonitor/PodMonitor.** Both generators expose selector/endpoint/relabeling fields but nothing for mTLS-scraped targets or cardinality limits — a real gap for any consumer running Prometheus Operator with mesh mTLS (which this library's own `mtls.*` feature would produce). **Priority/Effort:** P2 / S.
- **CAP-11 — Service dual-stack/topology fields** (`ipFamilyPolicy`, `ipFamilies`, `internalTrafficPolicy`, `trafficDistribution` — the last GA in 1.33, inside the library's own version window). **Priority/Effort:** P3 / M.
- **CAP-12 — ConfigMap `binaryData` support.** `_configmap.yaml` only handles string `data`; no `binaryData` field. **Priority/Effort:** P3 / S.

All CAP-2/3/6/7/8/9/10/12/13 items touch `_capabilities.tpl` and/or their respective single-Kind template file — bundle CAP-1/2/3/6 (all pure `_capabilities.tpl` registry edits) into one PR to avoid repeated merge churn on the same file; the per-Kind template edits (CAP-7 through CAP-13) can land independently.

---

## 4. Testing strategy

`scripts/lint-library.sh` already does far more than the fable5-review baseline assumed: shellcheck runs in CI (not the script itself — `ci.yaml:36-37`), `helm lint`, a JSON Schema metaschema check (`lint-library.sh:91-97`), a full k8s 1.31–1.36 render matrix (`lint-library.sh:31,111-127`), kubeconform with native + CRD schemas (native + datreeio catalog, `lint-library.sh:36,150-162`) — required in CI/release via `REQUIRE_KUBECONFORM=1` but optional locally by default (`lint-library.sh:68-77`) — golden-file diffs (`lint-library.sh:129-148`), expected-kind-count assertions per fixture (`lint-library.sh:41-49`), a negative render proving CRD-backed objects drop when their API is absent (`lint-library.sh:165-176`), image-pin enforcement (`lint-library.sh:178-201`), and values-schema/posture guardrail checks (`lint-library.sh:203-268`). Four fixtures now exist (`minimal`/`full`/`stateful`/`daemon`, each with a committed golden) instead of the two the fable5-review and `docs/specs` still describe.

### TEST-1 — Combined-coverage fixture (hooks × StatefulSet/DaemonSet × persistence)
**Problem:** Coverage is now real but siloed: `full` exercises hooks/mTLS/Certificate/Gateway/RBAC-in-extras but not persistence/StatefulSet/DaemonSet/tlsSelfSigned; `stateful` exercises persistence+probes+ConfigMap+Secret but not hooks; `daemon` exercises initContainers/sidecars/tlsSelfSigned but not hooks or persistence. No fixture exercises `jobs.postInstall` at all, and no fixture exercises the SEC-2 failure mode (hooks + default SA) in its *fixed* (fail-fast) form.
**Change:** Add a fifth fixture (`tests/fixtures/combined/`) that turns on `workload.type: StatefulSet`, `persistence.enabled`, `jobs.preInstall.enabled`, `jobs.postInstall.enabled`, and a `serviceAccount.create: false` override (to exercise the SEC-2 safe path) simultaneously, with a matching golden.
**Priority/Effort:** P1 / M. **Dependencies:** CAP-9 (so the fixture also exercises the new retention-policy field), SEC-2 (so the fixture proves the fail-fast guard doesn't fire when correctly configured).
**Acceptance criteria:** new fixture renders cleanly across the full k8s matrix; golden committed; `expected_kinds()` in `lint-library.sh:41-49` updated; a negative-path assertion proves the SEC-2 guard *does* fire when `serviceAccount.create: true` (default) is combined with `jobs.preInstall.enabled: true` and no override.

### TEST-2 — Make kubeconform required-by-default locally
**Problem:** `lint-library.sh:68-77` skips kubeconform silently unless `REQUIRE_KUBECONFORM=1` is set; only CI/release set that variable (`ci.yaml:46`, `release.yaml:57`). A contributor running `scripts/lint-library.sh` locally without kubeconform installed gets a clean pass, then a CI failure — a "works on my machine" trap.
**Change:** Flip the script's own default to required, with a clear "install kubeconform: <link>" failure message; keep an explicit opt-out env var for genuinely kubeconform-less environments.
**Priority/Effort:** P2 / S. **Dependencies:** none.
**Acceptance criteria:** running `scripts/lint-library.sh` with no env vars set and kubeconform absent fails with an actionable message instead of silently skipping.

### TEST-3 — Expand values-schema negative-fixture coverage
**Problem:** `lint-library.sh:203-218` currently asserts exactly two schema-rejection cases (lowercase `workload.type`, `image.tag: latest`). SEC-1's schema-tightening work will add several more constrained fields with no matching negative test.
**Change:** For every new `enum`/`pattern`/`required` constraint added under SEC-1, add a matching "this should fail" case to the same block.
**Priority/Effort:** P2 / M. **Dependencies:** SEC-1.
**Acceptance criteria:** 1:1 correspondence between new schema constraints and new negative-fixture assertions.

### TEST-4 — Per-version golden snapshots at floor (1.31) and ceiling (1.36)
**Problem:** The task's testing-strategy goal explicitly asks for "golden snapshots per k8s version." Today there is exactly one golden set per fixture (README.md/CORE.md describe it as pinned to k8s 1.31); the 1.32–1.36 legs of the render matrix are validated only by kind-count assertions and kubeconform, not a full-content diff. That's reasonable for the *middle* of the matrix (negotiated apiVersions rarely change release-to-release), but it means a regression at the matrix's ceiling — e.g. a new GA apiVersion for a Kind that only becomes available at 1.36 — would pass kind-count/kubeconform checks (both are apiVersion-agnostic or schema-driven) while silently changing rendered output.
**Change:** Add a second golden directory (`tests/golden-1.36/` or equivalent) capturing full-content diffs at the ceiling version, alongside the existing 1.31-floor goldens. Document explicitly (in the script and in TEST-5's docs resync) why the *middle* of the matrix intentionally stays kind-count+kubeconform-only rather than full-diff, so this isn't rediscovered as a gap later.
**Priority/Effort:** P2 / M. **Dependencies:** CAP-1 through CAP-13 landing first (so the new goldens reflect the final registry, not an interim state that needs re-golden-ing).
**Acceptance criteria:** two full golden sets exist (1.31, 1.36) per fixture; `UPDATE_GOLDEN=1` workflow documented for both; rationale for not full-diffing the middle versions is written down.

### TEST-5 — Resync `docs/specs`/`docs/prd` to the actual test harness
**Problem:** `docs/specs/platform-library-v2-architecture.md:349-357` still describes only `minimal`/`full` fixtures and calls `full` "exercises every tier-1 generator" (the exact framing the original fable5-review flagged as false, `fable5-review.md:140-142` — now doubly stale since coverage moved to `stateful`/`daemon` rather than being fixed inside `full`). The same doc's kubeconform description (`:342-343,367`) still says `-ignore-missing-schemas` — a flag that doesn't appear anywhere in current `lint-library.sh` (grep-confirmed absent); the original fable5-review additionally noted this flag was paired with a single hardcoded 1.31.0 version (`fable5-review.md:133`), a detail from the pre-hardening state that also no longer applies. `docs/prd/platform-library-v2.md:116-126`'s acceptance criteria have the same drift.
**Change:** Rewrite both docs' test-strategy sections against current `lint-library.sh` (4 fixtures + TEST-1's 5th, golden-diff mechanism, required kubeconform w/ CRD schemas, expected-kind-count, negative render, image-pin, posture guardrails).
**Priority/Effort:** P2 / S. **Dependencies:** TEST-1 (so the resync describes the final fixture set, not an interim one).
**Acceptance criteria:** no remaining references to a 2-fixture harness or unused kubeconform flags in either doc.

### TEST-6 — `helm test` golden coverage
Depends on HV4-12's scaffold work; once `new-app-chart.sh` can generate a `templates/tests/` directory, add a smoke check (manual or CI, since `helm test` requires a live install, not just `helm template`) proving the scaffolded test actually passes against a real install of one fixture. **Priority/Effort:** P3 / S.

---

## 5. CI/CD, release & supply chain

CI (`.github/workflows/ci.yaml`) and release (`.github/workflows/release.yaml`) already cover the fable5-review's #11/#14 asks (see reconciliation table). Remaining work is supply-chain hardening the CHANGELOG already flagged as deferred.

### CI-1 — cosign keyless OIDC signing of the pushed OCI chart
**Problem:** `release.yaml:66-72` pushes the packaged chart to `oci://ghcr.io/<owner>/charts` with no signature or attestation. `CHANGELOG.md:88` and a comment in `release.yaml:74-75` both already name this as deferred work.
**Change:** After `helm push`, run `cosign sign` (keyless, GitHub Actions OIDC identity — no key material to manage or rotate) against the pushed OCI artifact digest, using the `packages: write` + `id-token: write` permissions the workflow already needs. Document `cosign verify` for consumers in the README Releasing section.
**Priority/Effort:** P1 / M. **Dependencies:** HV4-11 (mechanism decision).
**Acceptance criteria:** every tagged release produces a verifiable cosign signature on the pushed OCI artifact; `cosign verify --certificate-identity-regexp ... ghcr.io/<owner>/charts/platform:<version>` documented and works; release workflow fails the release if signing fails (no unsigned releases ship silently).

### CI-2 — CHANGELOG/tag discipline check
**Problem:** The Releasing flow (README.md:946-961) is entirely manual: bump `Chart.yaml`, move `[Unreleased]` notes under a dated heading, tag. Nothing enforces that the tag being released actually has a matching `## [X.Y.Z]` heading in `CHANGELOG.md` — exactly the kind of manual-discipline gap that let the cosign "Future work" line sit unaddressed with no forcing function.
**Change:** Add a cheap check to `release.yaml` (alongside the existing tag-vs-`Chart.yaml` version check at `release.yaml:37-45`) that fails the release if `CHANGELOG.md` has no heading matching the tag version.
**Priority/Effort:** P2 / S. **Dependencies:** none.
**Acceptance criteria:** a release attempt with a missing CHANGELOG entry fails clearly before packaging/pushing.

### CI-3 — SBOM generation + attestation
**Problem:** No SBOM is generated for the packaged chart today.
**Change:** Generate an SBOM (e.g. `syft` against the packaged `.tgz`) and attach it as an OCI attestation alongside the cosign signature from CI-1.
**Priority/Effort:** P3 / M. **Dependencies:** CI-1.
**Acceptance criteria:** SBOM attestation retrievable via `cosign verify-attestation` for a released chart.

### CI-4 — GitHub Actions matrix parallelization (no action recommended)
CI is currently a single job; the k8s 1.31–1.36 matrix runs as an internal loop inside `lint-library.sh` rather than a GH Actions `strategy.matrix` (`.github/workflows/ci.yaml`, single `lint` job). Wall-clock is not currently a stated pain point. **Recommendation: no action** unless CI duration becomes a problem; noted here so it isn't rediscovered as an unaddressed gap.

---

## 6. Project layout & repo hygiene

### LAY-1 / LAY-3 — Remove accidental Repomix dumps from `docs/`
**Problem:** `docs/helm-docs.xml` (636KB, 15,749 lines) and `docs/helmet.xml` (104KB, 2,236 lines) are both full-repository dumps generated by the Repomix tool ("This file is a merged representation of the entire codebase... designed to be easily consumable by AI systems"), committed at repo root under `docs/`. They are not referenced from README.md, CORE.md, or any workflow — they appear to be accidental artifacts from an AI-assisted authoring session that were never cleaned up. Beyond bloating the repo (740KB combined) and confusing the `docs/` directory's information architecture right when it's about to become the root of a Docusaurus site (see DOC-1), they duplicate the entire tracked source as of whatever commit they were generated at and will only rot as the real source changes.
**Change:** Delete both files. Add `repomix-output*.xml`/`*.repomix.xml` patterns to `.gitignore` (currently absent — confirmed by reading `.gitignore` in full) to prevent recurrence.
**Priority/Effort:** P1 / S. **Dependencies:** none.
**Acceptance criteria:** both files removed; `.gitignore` updated; repo size drops ~740KB.

### LAY-2 — Archive `fable5-review.md` as superseded
**Problem:** `fable5-review.md` is tracked at repo root (committed as part of `4fb9386`, confirmed via `git log --oneline -- fable5-review.md`). Once this plan merges, it becomes a snapshot of a point-in-time review whose findings are now tracked (and reconciled) here — leaving it at the root with no pointer risks a future reader mistaking it for current state.
**Change:** Move to `docs/archive/fable5-review-2026-07-01.md` (or similar), with a one-line header added: "Superseded by `docs/productionization-plan.md`; kept for history."
**Priority/Effort:** P2 / S. **Dependencies:** merge of this plan.
**Acceptance criteria:** file relocated with the superseded-by note; nothing else references its old root path.

### LAY-4 — Script hardening follow-ups
`scripts/lint-library.sh` and `scripts/new-app-chart.sh` already pass shellcheck in CI (`ci.yaml:36-37`) and `new-app-chart.sh`'s injection-risk items from the fable5-review are resolved (see reconciliation table #13). No further hardening identified during this review beyond what's already covered by CI's shellcheck gate. **Priority/Effort:** P3 / S — kept as a placeholder item for any findings a future shellcheck version surfaces, not a known current gap.

### LAY-5 — `docs/` reorg for Docusaurus IA
Once LAY-1 clears the accidental dumps, `docs/` currently holds `migration/`, `prd/`, `specs/` — internal planning documents, not end-user documentation. Docusaurus (DOC-1) needs its own root (recommend `site/` to keep the distinction clear from `docs/`'s existing role as "internal specs/PRDs," rather than overloading `docs/` for both audiences). **Priority/Effort:** P2 / M. **Dependencies:** DOC-1 (the site's actual IA determines what, if anything, moves).

---

## 7. Documentation site (Docusaurus → GitHub Pages)

### DOC-1 — Scaffold the Docusaurus site and information architecture
**Problem:** No public docs site exists. README.md (989 lines) and CORE.md (349 lines) are doing the job of a full reference site inside two flat Markdown files — functional for a GitHub reader, but with no search, no generated values reference, and no room for the security-model/migration/capability-catalog depth this library actually has.
**Proposed IA** (top-level sidebar):
1. **Getting Started** — the existing README Quick Start (scaffold → dependency → entrypoint → configure → render), OCI digest install (HV4-3), multi-doc values (HV4-3).
2. **Values Reference** — auto-generated from `values.yaml` + `values.schema.reference.json` (DOC-2). This is the page most likely to go stale without automation, so it's the highest-priority generation target.
3. **Capability Catalog** — the Kind→apiVersion registry from `_capabilities.tpl`, rendered as a browsable table (DOC-4), replacing the "see architecture spec" pointer currently in the README (line 903).
4. **Migration Guide** — promote `docs/migration/v1-to-v2.md` as-is, plus the new Helm-3→4 / SSA guidance from HV4-4 (DOC-7).
5. **Security Model** — the trust-model prose currently spread across README (secret warnings, extras trust model, PSS-restricted target) consolidated into one page, plus the new SSA/extraObjects-conflict note from HV4-4 (DOC-6).
6. **Examples / Recipes** — one worked example per workload type (Deployment/StatefulSet/DaemonSet), one for Gateway API, one for the mTLS+NetworkPolicy combination, one for `extraObjects` (RBAC + PriorityClass, mirroring README's existing example).
**Change:** `npx create-docusaurus@latest site classic` (or current equivalent) under `site/`; wire the IA above as the initial sidebar; port README/CORE.md content into the matching pages rather than duplicating — README stays the GitHub-native quick-reference, the site becomes the deep reference, with README linking to it once DOC-3 ships.
**Priority/Effort:** P1 / L. **Dependencies:** none (can start immediately, in parallel with all other work).
**Acceptance criteria:** `npm run build` produces a static site locally; IA sections above exist (even if some are stubs pending DOC-2/DOC-4); README gains a "Full docs: <site URL>" link once DOC-3 ships.

### DOC-2 — Values-reference generation pipeline
**Problem:** A hand-maintained values reference will drift the moment `values.yaml` or `values.schema.reference.json` changes — exactly the doc-drift pattern already seen twice in this repo (CORE.md pre-this-plan, `docs/specs`/`docs/prd` currently). `values.yaml` has extensive inline `#` section comments (e.g. `values.yaml:1-9,190-195,306-313`) but the schema only constrains a subset of keys (`additionalProperties: true` almost everywhere) — so neither source alone is sufficient; the generator needs to combine both.
**Change:** Adopt a `values.yaml`-comment-driven generator (the `norwoodj/helm-docs`-style convention is the de facto standard for this) layered with the schema's `enum`/`description` fields where present. **Known complication to budget for:** this library's defaults live under `exports.defaults:` (`values.yaml:1-2`) rather than at the file root, which is not the layout most values-doc generators assume — the generation step will need either a pre-processing unwrap of the `exports.defaults` key or a generator with configurable root-key support; verify this during implementation rather than assuming a stock config works.
**Change (cont.):** Wire the generator into a `make docs` / `npm run docs:values` script that regenerates the Values Reference page from `platform-library/values.yaml` + `values.schema.reference.json`, and add a CI check (mirroring the golden-snapshot pattern already used for render output) that fails if the committed generated page is stale relative to the source files.
**Priority/Effort:** P1 / M. **Dependencies:** DOC-1.
**Acceptance criteria:** Values Reference page is generated, not hand-written; CI fails a PR that changes `values.yaml`/`values.schema.reference.json` without regenerating the page; the `exports.defaults` unwrapping is verified working (not assumed).

### DOC-3 — GitHub Pages deploy workflow
**Change:** Add `.github/workflows/docs.yaml` building the Docusaurus site (`site/`) on push to `main` (docs-affecting paths only, to avoid rebuilding on every template change) and deploying to GitHub Pages via `actions/deploy-pages`. Use path filters (`site/**`, `platform-library/values.yaml`, `platform-library/values.schema.reference.json`, `platform-library/templates/_capabilities.tpl`) so unrelated template-only PRs don't trigger a docs rebuild.
**Priority/Effort:** P1 / M. **Dependencies:** DOC-1.
**Acceptance criteria:** merging to `main` with docs-affecting changes publishes an updated site within one workflow run; the workflow is a separate job from `ci.yaml`/`release.yaml` so a docs build failure never blocks a chart release.

### DOC-4 — Capability catalog page generated from the registry
**Problem:** The Kind→apiVersion registry (`_capabilities.tpl:68-158`) is the single source of truth for what the library can render and how it negotiates versions, but it's currently only readable by opening the `.tpl` file directly — the README (line 903) just points to the architecture spec, which itself doesn't render it as a browsable table.
**Change:** A small build-time script parses the YAML block inside `platform.capabilities.registry` (it's already valid YAML embedded in the `define`, per `_capabilities.tpl:69-158`) and renders it as a sortable/searchable table: Kind, preferred apiVersion, fallback chain, cluster-scoped (cross-referenced with `platform.capabilities.clusterScoped`, `_capabilities.tpl:222`), and — once CAP-4/CAP-5 graduate upstream — a "planned, not yet registered" section sourced from this plan's watch-item list.
**Priority/Effort:** P2 / M. **Dependencies:** DOC-1, and ideally after CAP-1 through CAP-13 land so the first published table is accurate rather than needing an immediate follow-up edit.
**Acceptance criteria:** table auto-generated from `_capabilities.tpl`, not hand-maintained; regenerated by the same staleness-check pattern as DOC-2.

### DOC-6 — Security model page
Consolidate: PSS-restricted target and rationale (values.yaml:458-486 comments), the escape-hatch trust model (README.md:848-857), the secrets-in-values warning (README.md:449-454, extended by SEC-3's new NOTES warning), the mTLS fail-closed design (README.md:568-570), and the new SSA/extraObjects-conflict note (HV4-4). This is the page most likely to be read by a security reviewer evaluating whether to adopt the library — it deserves to be a single authoritative page rather than scattered prose. **Priority/Effort:** P2 / M. **Dependencies:** DOC-1.

### DOC-7 — Migration guide refresh
Extend the existing `docs/migration/v1-to-v2.md` (promoted into the site) with: a "Helm 3 → Helm 4" section covering the version-skew matrix (HV4-1) and SSA behavior change (HV4-4), since consumers migrating this library to v2 are exactly the population most likely to also be jumping Helm major versions at the same time. **Priority/Effort:** P2 / S. **Dependencies:** DOC-1, HV4-4.

### DOC-5 = TEST-5
Listed under Testing strategy since it's fundamentally a test-harness-accuracy fix; cross-referenced here because the same stale content (`docs/specs`, `docs/prd`) will also need to feed whatever the site's "Architecture" page ends up summarizing.

---

## Sequencing / wave plan

**Wave 0 — housekeeping (parallel, no dependencies, start immediately):**
LAY-1, LAY-3, LAY-2 (after this plan merges), CAP-1, HV4-1, CI-2, HV4-11 (decision only). None of these touch the same files as each other or as later waves; safe to run fully in parallel, including in parallel with Wave 0.5 below.

**Wave 0.5 — docs site scaffolding (parallel track, starts immediately, independent of template work):**
DOC-1, DOC-3. These don't depend on any template/CI changes below and can proceed on their own timeline; DOC-2/DOC-4/DOC-6/DOC-7 slot in once their dependencies land.

**Wave 1 — secure-defaults and single-Kind template fixes (must serialize with each other only where they touch the same file):**
SEC-1 (`values.schema.reference.json`), SEC-2 (`_helpers.tpl`/`_app.yaml`), SEC-3 (`_notes.tpl`), CAP-9 (`_statefulset.yaml`), CAP-7 (`values.yaml`/`_gateway-api.yaml`), CAP-8 (`_certificate.yaml`), CAP-10 (`_deployment.yaml`/`_statefulset.yaml`/`_daemonset.yaml`), CAP-13 (`_servicemonitor.yaml`/`_podmonitor.yaml`), HV4-4 (docs only), HV4-3 (docs only), HV4-12 (`new-app-chart.sh`). Different files mostly — the only real collision risk is SEC-2 and CAP-10 both touching `_helpers.tpl`/workload templates, so land SEC-2 first if both are in flight together.

**Wave 2 — capability registry additions (serialize with each other — all touch `_capabilities.tpl`):**
CAP-2, CAP-3, CAP-6 — bundle into one PR. CAP-11, CAP-12 can ride along or follow separately since they touch `_service.yaml`/`_configmap.yaml` instead.

**Wave 3 — testing (depends on Waves 1–2 landing so fixtures exercise final behavior):**
TEST-1 (needs SEC-2, CAP-9), TEST-3 (needs SEC-1), TEST-4 (needs CAP-1..13), TEST-2 (independent, can move to Wave 0 if preferred), TEST-5 (needs TEST-1).

**Wave 4 — supply chain (parallel with Waves 1–3, only needs the Wave 0 decision):**
CI-1 (needs HV4-11), HV4-2 (needs HV4-1), CI-3 (needs CI-1).

**Wave 5 — docs content depending on final state:**
DOC-2 (needs DOC-1; can start against current schema and re-run once SEC-1 lands), DOC-4 (needs DOC-1 + Wave 2 for an accurate first publish), DOC-6 (needs DOC-1), DOC-7 (needs DOC-1 + HV4-4), TEST-5/DOC-5 (needs TEST-1), LAY-5 (needs DOC-1's actual IA decisions).

---

## Decisions needed from the captain

These are either API-breaking (justified by the in-flight, unreleased v2.0.0 major bump — `CHANGELOG.md:10-12` still under `[Unreleased]`) or product-shaped choices this plan should not make unilaterally:

1. **Ingress TLS default posture (ties to reconciliation #10).** Current: `ingress.tls` stays `false` by default, WARN-only via NOTES. Keep as-is, or move to fail-closed (render fails when `ingress.hostname` is set with `ingress.tls` unset/false, requiring an explicit opt-out) to match the fail-closed pattern already used for mTLS/image-pinning/cluster-scoped-extras? Fail-closed is more consistent with the library's stated philosophy but is a harder break for existing consumers.
2. **NetworkPolicy default-deny footgun (reconciliation #10).** Same question: keep WARN-only, or require an explicit `networkPolicy.acknowledgeDefaultDeny: true`-style opt-in when `ingress`/`egress` are both empty?
3. **SEC-2 fix approach.** Fail-fast `fail()` guard (non-breaking, recommended in this plan) vs. making ServiceAccount creation itself a pre-install hook by default whenever `jobs.preInstall.enabled` is true (changes default rendered output for that combination — API-breaking in the strict sense, but arguably the more "it just works" fix).
4. **CAP-7's Gateway API default change.** Changing `gatewayApi.apiVersion`'s default from a hardcoded `v1` to negotiated (`""`) changes rendered output for any consumer on a pre-1.0 Gateway API install (rare, but changes behavior from "hard version mismatch" to "clean skip"). Confirm this is desired before landing.
5. **HV4-11 signing mechanism.** cosign keyless OIDC (recommended), classic GPG provenance, or both. Affects CI-1's implementation and what verification instructions ship to consumers.
6. **CAP-4/CAP-5 (pre-GA Kinds).** Register Gateway API TCPRoute/TLSRoute/AdminNetworkPolicy now against their Experimental/alpha upstream status, or strictly wait for GA as this plan recommends? A "yes, register experimental Kinds behind an opt-in flag" answer would change these from P3 watch-items to real work items.
7. **Docs site hosting.** `site/` in this repo + default `<owner>.github.io/helm-factory` GitHub Pages URL (assumed throughout this plan), or a custom domain / separate repo? Affects DOC-1/DOC-3's exact setup.

---

## Appendix: file:line index of every citation in this plan

For a reviewer who wants to jump straight to code: `values.yaml` (root defaults + comments), `values.schema.reference.json` (root schema, see SEC-1's `$schema` line 2), `templates/_capabilities.tpl` (registry lines 68-158, cluster-scoped set line 222), `templates/_helpers.tpl` (SA/pod-template/hook-Job composition, lines 157-388 and 596-763), `templates/_notes.tpl` (install-time warnings, lines 12-34), `templates/_app.yaml` (tier-1 orchestrator + `platform.render` entrypoint), `templates/_secret.yaml`, `templates/_mtls.yaml`, `templates/_tls-selfsigned.yaml`, `templates/_cronjob.yaml`, `templates/_statefulset.yaml`, `templates/_gateway-api.yaml`, `templates/_certificate.yaml`, `scripts/lint-library.sh` (lines 31-268 cover every CI gate), `scripts/new-app-chart.sh` (lines 49-90 cover input validation), `.github/workflows/ci.yaml`, `.github/workflows/release.yaml` (lines 37-75), `CHANGELOG.md` (line 88 "Future work"), `README.md` (Security Context §379-410, Secret §447-472, extras trust model §848-857, Releasing §946-968, ServiceAccount §654-676), `CORE.md` (Known Issues table §95-105), `docs/specs/platform-library-v2-architecture.md` (§8 test strategy, lines 342-367), `docs/prd/platform-library-v2.md` (acceptance criteria, lines 116-126).
