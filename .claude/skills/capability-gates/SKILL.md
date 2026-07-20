---
name: capability-gates
description: Use when touching platform-library/templates/_capabilities.tpl, changing apiVersion negotiation, adding registry entries, or explaining why objects render differently offline (helm template) vs on a real cluster. Do not use for general render debugging (see debug-render-failure) unless the cause is confirmed to be capability negotiation.
---

# Capability Gates

## First rule
There are exactly two negotiation modes and the choice is a contract, not a preference. `apiVersionFor` is strict — returns `""` when no listed API is served, so the object is skipped (CRDs: never conflict on deploy). `apiVersionForOrDefault` never returns empty — falls back to the first registry preference (built-ins: never drop a core workload from a bare `helm template`). Swapping them in either direction is a bug.

## Steps
1. Understand the split before editing: under `helm template` with no cluster, `.Capabilities.APIVersions` is a minimal static set — no CRDs, not even all built-in groups. On a real cluster it is live discovery. This is why offline and on-cluster renders differ, and why CI bridges it with force-assume values (`tests/fixtures/full/values.yaml:83-87`) or `--api-versions` flags. Asymmetry (verified by render): the *values* list matches `group/version` or `group/version/Kind`; the helm CLI flag only satisfies the gate in the full `group/version/Kind` form, because `has` checks `.Capabilities.APIVersions.Has` with the full gvk string.
2. The moving parts, all in `_capabilities.tpl`:
   - `has` (`:27-45`): true when `$top.Capabilities.APIVersions.Has $gvk` OR the entry appears in `.Values.capabilities.apiVersions` (matching `group/version` or `group/version/Kind`).
   - `registry` (`:76-176`): Kind → ordered apiVersion preference list, newest GA first. It is a YAML document inside a define, parsed with `fromYaml` at every call site — one malformed line breaks every render.
   - `apiVersionFor` (`:183-191`) strict; `apiVersionForOrDefault` (`:202-213`) with fallback.
   - `isStable` (`:222-233`): Kind's first-preference group ∈ the hardcoded built-in group list → "true". This is the selector `platform.genericResource` (`_util.tpl:36-41`) uses to pick the mode for extraObjects automatically.
   - `gatedKinds` (`:259-265`): Kind → values-block-name map for the five gated CRD features; `gateOpen` (`:273-280`) folds the block's `.enabled` and the strict `apiVersionFor` gate into one check, and the same map drives the NOTES skipped-Kind warnings (`skippedKinds`, `:288+`). A gated Kind missing from this map never renders.
   - `clusterScoped` set (`:304-306`): drives namespace stamping and the extras gate.
3. When adding a registry entry: order preferences newest-GA-first (the first entry is also the OrDefault fallback, so it must be the version you want emitted offline). Add cluster-scoped Kinds to the set.
4. When changing preference order (e.g. an apiVersion went GA): remember goldens snapshot the negotiated version at k8s 1.34 — an order change is a golden change; review the diff.
5. In `_app.yaml`, CRD-backed generators are wrapped in `platform.capabilities.gateOpen` (pattern: `_app.yaml:24,36,66,86,90`). Inside a generator body, OrDefault is acceptable for a CRD only because the wrapper's gate already proved availability (`_mtls.yaml:11` does this).
6. Prove behavior with the negative render (below) after any change.

## Commands
```bash
tests/render.sh full --set capabilities.apiVersions=null      # CRD-backed kinds must vanish (full renders 6 of the 7 the gate greps — no GRPCRoute), no {} docs
tests/render.sh full | grep -E '^(apiVersion|kind):'          # inspect negotiated versions (26 objects)
tests/render.sh minimal --set serviceMonitor.enabled=true --api-versions monitoring.coreos.com/v1/ServiceMonitor   # CLI force-assume: full group/version/Kind required
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # full proof; passes at HEAD 8d09841 (strict gate re-run 2026-07-19: ==> PASS)
```

## Quality bar
(1) Negative render clean AND full render correct across the 1.34-1.36 matrix; (2) no gate removed, no CRD switched to OrDefault, no guardrail bypassed to make offline output "complete" — completeness offline comes from force-assume, never from weakening; (3) `capabilities.apiVersions` values semantics (group/version and group/version/Kind both match) unchanged — consumers depend on them.

## Verification checklist
- [ ] `tests/render.sh full --set capabilities.apiVersions=null` shows zero Certificate/HTTPRoute/GRPCRoute/PeerAuthentication/AuthorizationPolicy/ServiceMonitor/PodMonitor kinds and zero `{}` docs
- [ ] Full fixture still renders 26 objects with force-assume intact
- [ ] Registry still parses: any single fixture render exits 0 (a registry YAML error breaks all of them)
- [ ] Golden diff after preference reordering reviewed and intentional
- [ ] Gate `==> PASS`

## Stop and ask before
- changing strict↔OrDefault mode for any existing Kind
- editing the `isStable` built-in group list (`:222-233`) — it silently flips gate modes for every extraObjects Kind in affected groups
- removing a registry preference entry (consumers on older clusters may be relying on the fallback chain)
- changing the force-assume matching semantics in `has`

## Common mistakes
- Treating template-vs-cluster differences as a bug: `helm template` sees no CRDs by design; the on-cluster deploy is the source of truth for availability.
- Using strict `apiVersionFor` for a built-in Kind — it silently disappears from every bare `helm template` because Helm's offline discovery set is minimal.
- Malformed registry YAML (stray tab, unbalanced bracket) — every render breaks with an error pointing nowhere near the registry.
- Force-assume entry with a version the registry does not list — `has` matches nothing, object still skipped; entries must correspond to registry preferences.
- Passing `--api-versions group/version` on the CLI and concluding the gate is broken — verified: `--api-versions monitoring.coreos.com/v1` renders no ServiceMonitor (exit 0, silent skip); `--api-versions monitoring.coreos.com/v1/ServiceMonitor` renders it. Only the values force-assume list accepts the bare `group/version` form.
- Forgetting that changing a first preference changes offline output (OrDefault fallback) even on clusters that serve the older version.

## Done means
- Negative render output (zero CRD kinds) and full render count pasted, gate `==> PASS` pasted, and any mode/order/registry change called out explicitly with its consumer-visible effect.
