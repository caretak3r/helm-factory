# Concept: values are code (extraManifests trust model)

`platform.extraManifests` (`_util.tpl:115-125`) is the tier-3 raw escape hatch: a list of full manifests emitted verbatim. **String entries run through `tpl` with the full root context** (`_util.tpl:120`) — meaning a consumer values file can execute arbitrary template expressions, including reads of any value, `.Files`, and (on-cluster) `lookup`.

Implications:
- Consumer values files are a code-execution surface, not inert config. Treat third-party or generated values with the same suspicion as a template file.
- Prefer the tiers in order: opinionated block → `extraObjects` (negotiated, labelled, gated — [[strict-vs-ordefault-negotiation]]) → `extraManifests` map form → string form last.
- The extraObjects tier deliberately constrains this: reserved keys, automatic labels/namespace, and the cluster-scope fail-closed gate (`_util.tpl:98-99`, [[fail-closed-guardrail-pattern]]). extraManifests bypasses all of it.
- Softer hazards in extras (hostPath, privileged, cluster-RBAC) surface as install-time NOTES warnings via `_notes.tpl`, not failures.

This is by design (documented in the source comment: "Strings are passed through tpl so they may contain template expressions") — the mitigation is review discipline on values, not a library change.

Sources: raw/util-emit-merge-source.md context; `_util.tpl` read 2026-07-10, HEAD 4fb9386.
