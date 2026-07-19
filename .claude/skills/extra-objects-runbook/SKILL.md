---
name: extra-objects-runbook
description: Use when a consumer chart needs a Kubernetes object the library has no opinionated generator for (RBAC, PriorityClass, CRDs, webhooks, anything in the long tail). Do not use when the object type deserves first-class library support with defaults and schema (see add-library-kind).
---

# Extra Objects Runbook

## First rule
Escalate through the tiers in order: tier-1 opinionated block if one exists → `extraObjects` (negotiated, labelled, gated) → `extraManifests` (raw, verbatim) only when extraObjects cannot express it. Never reach for extraManifests first — it bypasses apiVersion negotiation, label stamping, and the cluster-scope gate.

## Steps
1. Check the registry (`_capabilities.tpl:76-176`) covers the Kind. Registered Kinds get automatic apiVersion negotiation; an unregistered Kind renders only if the spec carries an explicit `apiVersion`, and gets no negotiation.
2. Write the spec under `.Values.extraObjects` — a map of `Kind -> [specs]`:
   ```yaml
   extraObjects:
     Role:
       - name: myapp-reader        # required; fail message names the Kind if missing (_util.tpl:47)
         rules:
           - apiGroups: [""]
             resources: ["configmaps"]
             verbs: ["get", "list"]
   ```
   Reserved keys handled by the renderer: `name`, `namespace`, `labels`, `annotations`, `apiVersion`, `kind`, `clusterScoped`, `metadata`. Every other top-level key passes through verbatim (`_util.tpl:60`), so rules/subjects/roleRef/spec/data/webhooks all work.
3. Gate mode is automatic (`_util.tpl:36-41`): built-in group Kinds (per `isStable`) negotiate with OrDefault fallback — always render; CRD-family Kinds are strict — silently skipped offline unless the group is force-assumed in `capabilities.apiVersions`.
4. Cluster-scoped Kinds (the set at `_capabilities.tpl:304-306`, or `clusterScoped: true` on the spec) `fail` the render unless the consumer sets `allowClusterScopedExtras: true` (`_util.tpl:82-83`). Namespace is stamped only on namespaced Kinds.
5. `extraManifests` (`_util.tpl:101-115`) is the last resort: a list of full manifests. Map entries emit via `toYaml`; **string entries run through `tpl` with the full root context** — values are code. Arbitrary template execution lives here; treat consumer values files as trusted input only, and prefer map form. Entries that render to nothing (empty string or `{}`) are skipped rather than emitted as empty docs (`_util.tpl:110`).
6. Render and inspect the emitted object: negotiated apiVersion, standard labels, namespace presence/absence.

## Commands
```bash
tests/render.sh full | grep -B1 -A12 '^kind: Role'            # working example from the full fixture
tests/render.sh full --set allowClusterScopedExtras=false     # must FAIL naming ClusterRole (gate demo)
helm template myapp /path/to/myapp | grep -A15 '^kind: <Kind>' # verify your consumer's extra object
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # if fixtures changed; passes at HEAD 8d09841 (strict gate re-run 2026-07-19: ==> PASS)
```

## Quality bar
(1) The consumer renders clean across k8s 1.34-1.36 with the object present (or intentionally skipped offline, stated); (2) the cluster-scope gate and hazard NOTES (hostPath/privileged/cluster-RBAC warnings in `_notes.tpl`) stay intact — enabling `allowClusterScopedExtras` is a consumer decision with stated justification; (3) no ad-hoc keys invented — unknown spec keys pass through to the manifest, so a typoed key becomes an invalid object kubeconform must catch.

## Verification checklist
- [ ] Object appears in render with correct apiVersion, `platform.labels`, and namespace handling
- [ ] `name` present on every spec (the renderer `required`-fails without it)
- [ ] CRD-family Kind: force-assume entry added for offline/CI renders, and behavior without it understood
- [ ] Cluster-scoped: `allowClusterScopedExtras: true` set consciously, justification recorded
- [ ] kubeconform passes over the render (the gate runs it for fixtures)

## Stop and ask before
- using a string entry in `extraManifests` (template execution surface) when a map would do
- setting `allowClusterScopedExtras: true` in a shared/base values file rather than one consumer
- adding RBAC that grants cluster-wide write/escalate verbs
- promoting to extraManifests to bypass a `fail` from the extraObjects gate

## Common mistakes
- Putting extras under `resources:` — the key is deliberately `extraObjects` to avoid colliding with container `resources:`.
- Expecting a CRD-family extra (e.g. PrometheusRule, VirtualService) in offline output without force-assume — strict gate skips it silently.
- Supplying `metadata:` on the spec — it's reserved-and-ignored; use top-level `name`/`namespace`/`labels`/`annotations`.
- Forgetting `clusterScoped: true` for a cluster-scoped Kind missing from the built-in set — it gets a namespace stamped and the API server rejects it.
- Using extraObjects for the workload/service/ingress the library already models — you lose hardening, probes, and the values contract.

## Done means
- Render output showing the emitted object pasted; tier choice (extraObjects vs extraManifests) justified in one sentence; cluster-scope and force-assume decisions stated; fixture changes gated `==> PASS`.
