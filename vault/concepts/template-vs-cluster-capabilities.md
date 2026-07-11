# Concept: template-vs-cluster capabilities split

The behavioral split the owner flagged as the v2 rework's sharpest edge.

Under `helm template` / `helm lint` (no cluster), `.Capabilities.APIVersions` is a **minimal static set**: no CRDs, and not even all built-in groups. On a real cluster it is live API discovery. Therefore the same chart renders different object sets offline vs on-cluster — **by design**, via [[strict-vs-ordefault-negotiation]]:

- Offline, strict-gated CRD Kinds (Certificate, HTTPRoute, GRPCRoute, PeerAuthentication, AuthorizationPolicy, ServiceMonitor, PodMonitor) silently vanish.
- Offline, OrDefault-gated built-ins render with the registry's first preference regardless of discovery.

The bridge for offline/CI rendering is **force-assume**: list served APIs under `.Values.capabilities.apiVersions` (entries match `group/version` or `group/version/Kind`, `_capabilities.tpl:27-45`) or pass `--api-versions` to helm. The full fixture does exactly this (`tests/fixtures/full/values.yaml:75-80`). Caveat (render-verified 2026-07-10): the CLI flag satisfies the gate only in the full `group/version/Kind` form — `has` checks `.Capabilities.APIVersions.Has` with the full gvk string, and only the *values* list gets the bare `group/version` match.

Executor rules derived from this:
- A "missing" CRD object offline is not a bug; the fix is force-assume, never gate removal.
- CI greenness says nothing about a cluster serving the CRDs; the strict gate is what makes deploys safe there.
- UNVERIFIED: live-cluster discovery behavior and `lookup`-based tlsSelfSigned reuse have never been executed in this environment (no cluster) — claims come from source comments and the spec (raw/discovery-could-not-verify.md).

Related: `lookup` returns empty under template, which is why tlsSelfSigned mints a fresh throwaway cert per offline render ([[golden-count-oracle]] redaction).

Sources: raw/capabilities-design-header.md; negative render executed (0 CRD kinds) 2026-07-10, HEAD 4fb9386.
