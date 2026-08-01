# Entity: capabilities registry (_capabilities.tpl)

`platform.capabilities.registry` (`platform-library/templates/_capabilities.tpl:76-176`) is the canonical Kind → ordered apiVersion preference table: every built-in Kubernetes Kind creatable via manifest, plus four CRD families (Gateway API, cert-manager, Istio, Prometheus Operator). First entry per Kind = preferred/newest GA, and also the offline fallback for OrDefault mode ([[strict-vs-ordefault-negotiation]]).

Structural hazard: it is a **YAML document inside a `define`**, parsed with `fromYaml` at every call site (`_capabilities.tpl:186,205,226,244`; the `features` registry is parsed the same way at `:300,347,398`, and the lint gate parses its literal-YAML shape with sed/grep). One malformed line breaks every render, with an error nowhere near the edit.

Companion helpers in the same file:
- `has` (`:27-45`) — cluster discovery OR force-assume list `.Values.capabilities.apiVersions`; entries match `group/version` or `group/version/Kind`. See [[template-vs-cluster-capabilities]].
- `apiVersionFor` (`:183-191`) strict / `apiVersionForOrDefault` (`:202-213`) fallback.
- `isStable` (`:222-233`) — hardcoded built-in group list; auto-selects the gate mode inside `platform.genericResource` for extraObjects (`_util.tpl:36-41`).
- `features` (`:271`) / `kindRequires` (`:297`) / `featureEnabled` (`:314`) / `kindAvailable` (`:344`) / `gateOpen` (`:372`) / `skippedKinds` (`:395`) — added post-discovery, restructured by plan 010: one registry keyed by values block, carrying the FULL Kind set each feature's generator can emit (first Kind = the representative gated in `_app.yaml`), a `composition` policy (`atomic` = all-or-nothing, `independent` = per-Kind skip), and an optional `requires` override for Kinds enabled by their own sub-block (`GRPCRoute` → `gatewayApi.grpcRoute`). It drives tier-1 CRD emitter gates (`gateOpen` = `featureEnabled` + `kindAvailable`) AND the NOTES.txt warning, which is `gateOpen`'s exact per-Kind complement — so an atomic Kind held back by a missing partner API is warned about, not silently absent. A new gated Kind must be added here too, or it gates but never warns; the lint gate's content anti-drift check now fails on any partial wiring.
- `clusterScoped` set (`:304-306`, membership helper `isClusterScoped` `:312`) — drives namespace stamping and the cluster-scope extras gate (`_util.tpl:78-83`).

A Kind missing from the registry: `apiVersionFor` returns `""` → the object silently never renders. This is the #1 silent failure when adding Kinds.

Sources: raw/capabilities-design-header.md; file read in full 2026-07-10, HEAD 4fb9386; anchors re-verified 2026-07-19, HEAD 8d09841.
