# fable5-review.md — helm-factory security & quality review

Reviewed: 2026-07-01 · Scope: `platform-library` (chart `platform`, v2), `scripts/`, `tests/`, docs.
Goal: make the library **secure by default** and raise engineering quality. Findings verified against source at the cited file:line.

> **Repo-state note (do this first):** the entire v2 refactor is *uncommitted* on branch
> `feat/platform-library-v2-capability-gates` — `_capabilities.tpl`, `_util.tpl`, `scripts/`, `tests/`,
> `docs/specs|migration|prd` are untracked, 25 non-underscore templates staged as deleted, and the
> core templates modified-unstaged. Until this lands, none of the fixes below have a stable base.

---

## P0 — Secure-by-default gaps (highest impact)

### 1. Security contexts ship disabled — the hardened defaults are dead code
`platform-library/values.yaml:421-433`: `podSecurityContext.enabled: false` and
`containerSecurityContext.enabled: false`. The gates at `_helpers.tpl:200-210` mean **no**
securityContext is emitted by default, so the good sub-values (`runAsNonRoot: true`,
`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`) never take effect. Default pods run as
whatever the image says (often root), with escalation allowed and full capabilities.

**Change:**
- Flip both `enabled` defaults to `true`.
- Add `seccompProfile: {type: RuntimeDefault}` to both contexts.
- Add `runAsNonRoot: true` to `podSecurityContext`.
- Flip `readOnlyRootFilesystem: false` → `true` (values.yaml:429); consumers with writable-FS needs opt out.
- This aligns default output with the Pod Security Standard **restricted** profile — document that as the target.

### 2. Hook Jobs and CronJobs run completely unconstrained
- `_helpers.tpl` (`platform.renderHookJob`, ~662-729): pre/post-install Job pods get resources but **no
  pod or container securityContext** — hooks run as root even when the main app is hardened.
- `_cronjob.yaml`: no `securityContext` anywhere in the pod spec; user `cronJob.containers` pass through
  verbatim; the fallback default container has **no securityContext and no resources**; pull secrets only
  honor `global.imagePullSecrets`, ignoring `image.pullSecrets`.

**Change:** apply the same `podSecurityContext`/`containerSecurityContext` (post-fix #1 defaults) and the
`jobs.resources` defaults to hook Job and CronJob pods; merge `image.pullSecrets` into CronJob pull secrets.

### 3. Self-signed TLS: new CA + key generated on every render/upgrade
`_tls-selfsigned.yaml:8-9` calls `genCA`/`genSignedCert` unconditionally — no `lookup` of the existing
Secret. Every `helm upgrade` rotates the CA and private key: clients pinning the cert break, and a fresh
private key is stored in every release revision.

**Change:** `lookup` the existing `<fullname>-tls` Secret and reuse `tls.crt`/`tls.key` when present
(regenerate only when absent or near expiry). At minimum, mark `tlsSelfSigned` **dev-only** in README
and steer production to `certificate` (cert-manager), which the library already supports.

### 4. Schema validation is not actually enforced
Only `values.schema.reference.json` exists; Helm enforces **only** a file literally named
`values.schema.json`, so the library and every hand-migrated consumer get zero install-time validation.
The scaffold copies it into *generated* charts only (`new-app-chart.sh:125-127`), and the test fixtures
are never schema-validated.

**Change:**
- Keep the reference file as source of truth, but publish/copy it as `values.schema.json` in generated
  charts (already done) **and** add a lint step validating each fixture's effective root values against it
  (e.g. `check-jsonschema`).
- Tighten the schema itself: enums for `image.pullPolicy`, `service.type`, `mtls.policy`,
  `workload.type`; reject `image.tag: "latest"`; require `parentRefs` when a gateway route is enabled.

### 5. `image.tag` defaults to `latest`
`values.yaml:38` and `values.yaml:296` (`jobs.image.tag`), with a `latest` fallback in `_helpers.tpl:63`.
Unpinned images defeat reproducibility and rollback, and are a supply-chain risk.

**Change:** default `tag: ""` and fail with a clear `required` message when neither `tag` nor `digest`
is set; document `digest` as the preferred pin. (Digest support already exists — make it the paved road.)

---

## P1 — Security posture improvements

### 6. ServiceAccount defaults: no dedicated SA, token always mounted, knob is a no-op
`values.yaml:410-414`: `serviceAccount.create: false` → pods run under the namespace `default` SA.
`automountServiceAccountToken: true` is declared but **never rendered** — neither the SA template nor the
pod spec emits the field, so the "off" setting cannot even be selected.

**Change:** render `automountServiceAccountToken` on both the ServiceAccount and pod spec; default it to
`false` (apps that call the API opt in); default `serviceAccount.create: true` so every app gets a
dedicated least-privilege identity. Also set `enableServiceLinks: false` in the pod spec (currently every
Service in the namespace leaks host/port env vars into pods).

### 7. mTLS authorization is wide open when enabled
`values.yaml:278-279` defaults `allowedPrincipals: ["cluster.local/ns/*/sa/*"]`, rendered into an ALLOW
AuthorizationPolicy (`_mtls.yaml:29-33`). Enabling mTLS yields mutual TLS with **no meaningful authz** —
any workload in the mesh is allowed.

**Change:** default `allowedPrincipals: []` and **fail closed**: `fail` with a helpful message (or skip the
AuthorizationPolicy) unless principals are explicitly listed; offer a same-namespace default as the easy
opt-in.

### 8. Plaintext secrets flow through values
`secret.stringData` (`values.yaml:191`, `_secret.yaml:33-34`) and raw cert/key in `_tls-secrets.yaml:22-23`
steer consumers toward committing secrets to git and storing them in release manifests.

**Change:** first-class `existingSecret` reference pattern everywhere a secret is consumed; document
External Secrets / SealedSecrets as the production path; add a README warning box on `secret.stringData`.

### 9. Escape hatches are powerful and silent
- `extraManifests` strings run through `tpl` with full root context (`_util.tpl:114-115`) — unbounded
  template execution from values.
- `extraObjects` renders any Kind including `ClusterRole(Binding)`, webhooks, etc. verbatim
  (`_util.tpl:46-103`, cluster-scoped set at `_capabilities.tpl:222`).
- `sidecars`/`initContainers`/`extraVolumes` pass through verbatim — a sidecar can be `privileged: true`
  or mount `hostPath` with no warning.

This is by design, but "any values layer can mint ClusterRoleBindings" deserves a guardrail.

**Change:** document the trust model explicitly; add an opt-in flag (e.g. `allowClusterScopedExtras: false`)
gating cluster-scoped Kinds in `extraObjects`; optionally NOTES.txt/`fail`-level warnings when extras
contain `hostPath`, `privileged`, or cluster-scoped RBAC.

### 10. Network exposure defaults
`networkPolicy.enabled: false` (values.yaml:506) and `ingress.tls: false` (values.yaml:212) are open by
default. Conversely, enabling NetworkPolicy with the empty default rules (`_networkpolicy.yaml:26-31`)
silently produces **default-deny** — a foot-gun in the other direction.

**Change:** default `ingress.tls: true` when a hostname is set; document a recommended default-deny +
allow-list baseline; warn (NOTES.txt) when NetworkPolicy is enabled with empty ingress/egress rules.

---

## P2 — Quality: tests, CI, tooling

### 11. No CI at all
There is no `.github/` directory. `scripts/lint-library.sh` is a decent local gate but nothing runs it.

**Change:** add a workflow running, on every PR:
1. `shellcheck scripts/*.sh tests/render.sh`
2. `helm lint platform-library/`
3. `lint-library.sh` render matrix across `--kube-version` 1.31→1.36 and the `--api-versions` sets
4. `kubeconform` as a **required** step (not skipped-when-absent), across the version matrix, with
   `-schema-location` for CRDs (cert-manager, Gateway API, Prometheus Operator, Istio) — today
   `-ignore-missing-schemas` at a single hardcoded 1.31.0 (`lint-library.sh:37-41`) means CRD-backed
   objects are never validated at all
5. On tag: `helm package` + OCI push (see #14)

### 12. Tests assert exit codes, not output
- `lint-library.sh:30-35` counts rendered kinds but never compares to an expectation — a generator that
  silently stops emitting still passes.
- The "full" fixture doesn't exercise StatefulSet, DaemonSet, hook Jobs, persistence, configMap, secret,
  tlsSelfSigned, probes, initContainers, or sidecars — despite the v2 spec claiming it "exercises every
  tier-1 generator" (`docs/specs/platform-library-v2-architecture.md:349-351`).

**Change:** add golden-file snapshots (committed expected output, `diff` in CI) or at minimum per-fixture
expected-kind-count assertions; add fixtures or `--set` matrix legs for StatefulSet/DaemonSet/hooks/
persistence/secret/configmap/tlsSelfSigned. Also stop swallowing `helm dependency update` errors in
`tests/render.sh:11`.

### 13. `new-app-chart.sh` argument injection
`--repo`, `--version`, `--app-version` are interpolated into generated `Chart.yaml` via heredoc with no
validation (`new-app-chart.sh:56-72`); a newline-bearing value injects arbitrary YAML keys. Only `name`
is validated.

**Change:** validate `--version`/`--app-version` against a semver charset, `--repo` against a scheme
allowlist (`oci://`, `https://`, `file://`), and reject control characters/newlines in all three.
Minor: fix the SC2015 `&&…||` pattern at line 44; guard `jq` like kubeconform in `lint-library.sh:25`.

### 14. No release/publish story
Docs advertise `oci://registry.example.com/charts`, but there's no packaging script, no CHANGELOG, no
tags, no release automation; the scaffold's default repo is `file://../platform-library` (dev-only).

**Change:** add a tag-triggered release workflow (`helm package` + `helm push` to OCI, provenance/signing
via `helm push` + cosign if desired), a CHANGELOG, and semver tags matching `Chart.yaml`.

### 15. Docs drift (CORE.md is substantially v1)
- `CORE.md:111-142` directory listing shows files at repo root (they live under `platform-library/`),
  lists non-existent templates (`_job.yaml`, `_tls.yaml`, `_serviceaccount.yaml`), and omits
  `_capabilities.tpl`/`_util.tpl`.
- `CORE.md:144-217` consumer integration is entirely v1 (dependency `platform-library` `^1.0.0`, YAML
  anchors, `configuration.yaml` flow) and contradicts the v2 model in the same file's header.
- `CORE.md:88-97` known-issue line numbers predate the v2 rewrite.
- Root `configuration.yaml` is a v1 artifact (lowercase workload types, `service.port`, v1 ingress shape)
  that no longer matches the schema or values — either regenerate it from v2 values or delete it in favor
  of the scaffold.

**Change:** rewrite CORE.md's structure/integration/known-issues sections against v2; make doc examples
match the schema enums (`Deployment` vs `deployment`).

---

## Suggested order of attack

| # | Action | Why first |
|---|--------|-----------|
| 1 | Commit the v2 branch | Everything else needs a stable base |
| 2 | Fix #1/#2 (securityContext defaults incl. hooks/cron) + #6 (SA/automount) | Biggest default-posture win, purely template+values |
| 3 | Fix #3 (TLS lookup) and #5 (latest tag) | Small diffs, high blast-radius bugs |
| 4 | Add CI (#11) + golden tests (#12) | Locks in the above before more churn |
| 5 | Schema enforcement (#4) + scaffold validation (#13) | Guardrails for consumers |
| 6 | mTLS fail-closed (#7), secrets guidance (#8), escape-hatch gating (#9), network defaults (#10) | Posture polish |
| 7 | Release automation (#14) + docs rewrite (#15) | Ship it properly |

**A note on philosophy:** the library's whole pitch is "service teams set values and get correct
manifests." That pitch is strongest when the *zero-config* output already passes the PSS-restricted
profile, pins images, uses a dedicated SA with no token automount, and refuses obviously unsafe input at
`helm template` time. Every default above should be judged by one question: *what does a consumer who
sets nothing get?* Today the answer is root pods, `latest` images, the `default` SA with a mounted token,
and no schema check. All of it is fixable without breaking the API — flags stay, only defaults move
(a major-version bump is already in flight, so v2.0.0 is exactly the moment to do it).
