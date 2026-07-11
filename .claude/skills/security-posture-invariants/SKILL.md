---
name: security-posture-invariants
description: Use when any change touches security contexts, ServiceAccount/token defaults, fail-closed guardrails, escape hatches (allowClusterScopedExtras, allowAllPrincipals), or when a consumer asks to relax hardening. Do not use for adding brand-new guardrails to a new Kind (see add-library-kind, which references this skill's rules).
---

# Security Posture Invariants

## First rule
Secure-by-default hardening is merge bar #2 and is never weakened in **library defaults**. When an application genuinely needs writable FS, API access, or a relaxed context, the fix is a per-field override in THAT consumer's values — never a library-default change, never `enabled: false` wholesale.

## Steps
1. Know the never-weaken surface (all in `platform-library/values.yaml` under `exports.defaults`):
   - `podSecurityContext` / `containerSecurityContext` enabled by default targeting PSS `restricted`: runAsNonRoot, seccomp RuntimeDefault, drop ALL capabilities, readOnlyRootFilesystem, no privilege escalation (`values.yaml:468-485`). Applied identically to the main workload, CronJob, and hook Job pods.
   - Dedicated ServiceAccount by default with `automountServiceAccountToken: false` on both the SA and every pod spec; `enableServiceLinks: false`.
2. Know the fail-closed guardrails; each is coupled to a negative test in `lint-library.sh` that greps its message:
   | Guardrail | Source | Negative test |
   |---|---|---|
   | Unpinned image (no tag, no digest) | `_helpers.tpl:68` | `lint-library.sh:178-185` |
   | Hook Job resolves to no pin | `_helpers.tpl:640` | `lint-library.sh:195-201` |
   | mTLS with empty `allowedPrincipals` | `_mtls.yaml:8` | `lint-library.sh:223-229` |
   | Cluster-scoped extraObjects without opt-in | `_util.tpl:99` | `lint-library.sh:240-246` |
   | `existingSecret` + inline data | `_secret.yaml:3` | `lint-library.sh:249-255` |
   | `tag: latest` / lowercase workload type | values.schema (helm-side) | `lint-library.sh:203-218` |
3. Any change to a `fail` message updates its coupled grep in the same commit — the gate breaks otherwise (by design).
4. Softer hazards warn instead of failing, via `platform.notes` (`_notes.tpl`) into the consumer's install-time NOTES.txt (plain-HTTP ingress, default-deny NetworkPolicy, hostPath/privileged/cluster-RBAC in extras). NOTES never appears in `helm template` manifest output, so goldens/counts are unaffected — a new warning belongs here when failing would break legitimate use.
5. New security-relevant behavior follows the pattern: fail-closed guardrail + prescriptive message naming the values path and the fix + negative test asserting both failure AND message text + explicit opt-out key documented in README.
6. When a consumer asks to relax something: grant the narrowest override (e.g. `containerSecurityContext.readOnlyRootFilesystem: false` in that chart's values; prefer an emptyDir scratch mount instead), state the risk in your report, and leave library defaults untouched.
7. Validate with the full gate — the posture legs are the point.

## Commands
```bash
tests/render.sh minimal --set image.tag=                      # must FAIL naming image.tag/image.digest
tests/render.sh full --set mtls.allowedPrincipals=null        # must FAIL naming mtls.allowedPrincipals
tests/render.sh full --set allowClusterScopedExtras=false     # must FAIL naming ClusterRole
tests/render.sh minimal | grep -A6 'securityContext:'         # eyeball the restricted posture
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # posture legs included; passes at HEAD 4fb9386
```

## Quality bar
(1) Gate passes including every posture/guardrail negative leg; (2) hardening strictly non-decreasing — the diff of `values.yaml:468-485`, SA/token defaults, and every `fail` call shows no loosening; (3) opt-out keys are additive consumer surface and documented, never re-defaulted to permissive.

## Verification checklist
- [ ] All three negative renders above still fail with their exact message substrings
- [ ] `git diff` over `values.yaml` security blocks, `_helpers.tpl:68`, `_helpers.tpl:640`, `_mtls.yaml`, `_util.tpl`, `_secret.yaml` shows no weakened default or deleted `fail`
- [ ] Any message text change has its matching grep updated in `lint-library.sh`
- [ ] Consumer relaxations are per-field, in the consumer's values only, with risk stated
- [ ] Gate `==> PASS`

## Stop and ask before
- changing ANY default in the never-weaken surface (step 1), even "temporarily"
- deleting or softening a `fail` guardrail or downgrading it to a NOTES warning
- defaulting `allowClusterScopedExtras`, `mtls.allowAllPrincipals`, or `automountServiceAccountToken` to permissive
- adding a library-level "disable all hardening" convenience key

## Common mistakes
- "Fixing" a consumer's crash-looping app by flipping `readOnlyRootFilesystem` in library defaults — the fix is a consumer override plus an emptyDir mount.
- Changing a `fail` message wording without updating the coupled grep — gate fails, and the temptation is then to weaken the test instead of restoring the coupling.
- Treating the schema's `latest` rejection as an inconvenience during testing — pin a real tag; the rejection is the feature.
- Putting a new hazard in a `fail` when it would break legitimate existing consumers — that class goes to NOTES warnings.
- Forgetting hook Jobs and CronJobs inherit the same contexts — a "workload-only" relaxation that edits shared helpers relaxes all three.

## Done means
- Negative-render outputs (all failing with expected messages) and gate `==> PASS` pasted; an explicit sentence: "library hardening defaults unchanged" or, for consumer overrides, the exact fields relaxed and why.
