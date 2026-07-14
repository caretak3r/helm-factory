# Entity: platform-library chart

The repo's single artifact: a pure Helm **library** chart at `platform-library/`. Chart **name is `platform`** (not the directory name), `type: library`, `version: 2.0.0`, `kubeVersion: ">=1.34.0-0 <1.37.0-0"` (`platform-library/Chart.yaml:2-10`).

Every template file is `_`-prefixed (`define` blocks only), so the chart renders nothing on its own — `helm lint platform-library/` passes even when generators are broken. Evidence only comes from consumer renders; see [[lint-library-gate]] and [[golden-count-oracle]].

Consumers include exactly one line, `{{ include "platform.render" . }}`, which composes three tiers (`platform-library/templates/_app.yaml:104-108`):
1. `platform.app` — ~22 opinionated objects in fixed order, each `.enabled`-gated, CRD-backed ones double-gated (`_app.yaml:1-93`); see [[strict-vs-ordefault-negotiation]].
2. `platform.extraObjects` — generic negotiated long tail (`_util.tpl:92-108`).
3. `platform.extraManifests` — raw escape hatch (`_util.tpl:115-125`); see [[values-are-code]].

Zero-config output targets PSS `restricted`; see [[fail-closed-guardrail-pattern]] and [[values-contract]]. Consumer wiring mechanics: [[exports-defaults-import-mechanics]].

Sources: raw/capabilities-design-header.md, raw/util-emit-merge-source.md, `_app.yaml` (verified 2026-07-10, HEAD 4fb9386).
