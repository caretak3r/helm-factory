# Entity: platform-library chart

The repo's single artifact: a pure Helm **library** chart at `platform-library/`. Chart **name is `platform`** (not the directory name), `type: library`, `version: 2.0.0` (tagged + published to GHCR 2026-07-15; PR #39 preps 2.1.0), `kubeVersion: ">=1.34.0-0 <1.37.0-0"` (`platform-library/Chart.yaml:2-11`).

Every template file is `_`-prefixed (`define` blocks only), so the chart renders nothing on its own — `helm lint platform-library/` passes even when generators are broken. Evidence only comes from consumer renders; see [[lint-library-gate]] and [[golden-count-oracle]].

Consumers include exactly one line, `{{ include "platform.render" . }}`, which composes three tiers (`platform-library/templates/_app.yaml:116-120`):
1. `platform.app` — ~23 opinionated objects in fixed order, each `.enabled`-gated, CRD-backed ones double-gated via `platform.capabilities.gateOpen` (`_app.yaml:1-105`); includes the managed headless Service for StatefulSets (`:54-56`) and two cross-object `fail` guards — certificate+tlsSelfSigned mutual exclusion (`:21`) and ingress-without-service (`:59`); see [[strict-vs-ordefault-negotiation]].
2. `platform.extraObjects` — generic negotiated long tail (`_util.tpl:76-99`).
3. `platform.extraManifests` — raw escape hatch (`_util.tpl:101-115`); see [[values-are-code]].

Zero-config output targets PSS `restricted`; see [[fail-closed-guardrail-pattern]] and [[values-contract]]. Consumer wiring mechanics: [[exports-defaults-import-mechanics]].

Sources: raw/capabilities-design-header.md, raw/util-emit-merge-source.md, `_app.yaml` (verified 2026-07-10, HEAD 4fb9386; anchors re-verified 2026-07-19, HEAD 8d09841).
