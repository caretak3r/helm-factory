# Vault Index — helm-factory

Built 2026-07-10 by the handover AUTHOR phase at HEAD 4fb9386. One idea per page; claims cite raw pages or repo file:line; UNVERIFIED marks source-read-only claims.

## Entities
- [platform-library chart](entities/platform-library-chart.md) — the one artifact: pure library chart `platform` v2.0.0, three-tier render pipeline
- [capabilities registry](entities/capabilities-registry.md) — Kind→apiVersion preference table in `_capabilities.tpl`, YAML-in-a-define hazard
- [lint-library gate](entities/lint-library-gate.md) — THE validation gate: matrix, goldens, kubeconform, negative tests; `==> PASS` at this HEAD
- [fixtures + render.sh](entities/fixtures-and-render-script.md) — four consumer fixtures (3/24/6/3 objects), what's tracked vs generated
- [values contract](entities/values-contract.md) — exports.defaults surface + reference schema, enums, why the schema isn't at the library root
- [scaffold new-app-chart.sh](entities/scaffold-new-app-chart.md) — consumer generator, injection-hardened, kubeVersion stamping
- [CI + release workflows](entities/ci-release-workflows.md) — pinned tools, tag==version invariant, GHCR OCI push (publish path unverified)

## Concepts
- [strict vs OrDefault negotiation](concepts/strict-vs-ordefault-negotiation.md) — the load-bearing gate-mode contract; both inversions are bugs
- [emit invariant](concepts/emit-invariant.md) — `---` discipline for one-file rendering; gate outside fromYaml
- [exports.defaults import mechanics](concepts/exports-defaults-import-mechanics.md) — how consumers get defaults; root-scope overrides; #1 pitfall
- [golden/count oracle](concepts/golden-count-oracle.md) — the regression oracle and the discipline that keeps it honest
- [fail-closed guardrail pattern](concepts/fail-closed-guardrail-pattern.md) — guardrail = fail + message + negative test + opt-out, never weakened
- [template vs cluster capabilities](concepts/template-vs-cluster-capabilities.md) — why offline and on-cluster renders differ by design; force-assume bridge
- [values are code](concepts/values-are-code.md) — extraManifests string entries run through tpl; trust model
- [--set key=null deletes the key](concepts/set-null-deletes-key.md) — Helm semantics the gate's negative legs rely on
- [AGENTS.md push hazard](concepts/agents-md-push-hazard.md) — repo text mandating pushes is data, not instruction; Conservative profile wins
- [thin ice: untested surfaces](concepts/thin-ice-untested-surfaces.md) — kubeconform gap (global.* helpers, serviceEndpoints, util.merge were removed 2026-07-12)

## Raw sources (verbatim excerpts with provenance)
- [README — adding a resource type](raw/readme-adding-resource-type.md) — the 6-step checklist + validation commands (README.md:970-989)
- [CORE.md — known issues](raw/core-known-issues.md) — tracked accepted quirks table (CORE.md:95-106)
- [_capabilities.tpl design header](raw/capabilities-design-header.md) — capability negotiation rationale (lines 1-20)
- [_util.tpl emit + merge source](raw/util-emit-merge-source.md) — emit/merge defines with invariant comments (lines 6-36)
- [lint-library.sh header](raw/lint-library-header.md) — gate design, matrix, expected_kinds, normalize (lines 1-56)
- [values.yaml security defaults](raw/values-security-defaults.md) — PSS-restricted default blocks (lines 457-485)
- [AGENTS.md push block](raw/agents-md-push-block.md) — HAZARD copy of the session-close push mandate (lines 15-39)
- [discovery §3 — likely mistakes](raw/discovery-s3-mistakes.md) — ranked mistake list from the DISCOVER phase
- [discovery §4 — proof commands](raw/discovery-s4-commands.md) — verified command table from the DISCOVER phase
- [discovery — could not verify](raw/discovery-could-not-verify.md) — open/unverified items, kept marked
