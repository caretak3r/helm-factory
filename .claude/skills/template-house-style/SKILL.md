---
name: template-house-style
description: Use when writing or editing any file under platform-library/templates/ (_*.yaml generators or _*.tpl helpers). Do not use for deciding WHAT to build (see add-library-kind) or for values/schema design (see values-contract-change).
---

# Template House Style

## First rule
The library must never gain a non-underscore template file. `_*.yaml` = object generators (one `define "platform.<thing>"` each), `_*.tpl` = helper-only files (capabilities/util/helpers/notes). A renderable template breaks `type: library` purity and would make the chart self-render.

## Steps
1. **Emit invariant.** Every tier-1 object flows through `platform.emit` (`_util.tpl:14-20`): the wrapper in `_app.yaml` is `{{- include "platform.emit" (include "platform.<thing>" .) }}`. Generators do NOT start with `---`; emit adds it only when content is non-empty. Exception: multi-doc generators (`_mtls.yaml:24`, `_gateway-api.yaml`) put `---` *between* their own docs only.
2. **Gate placement.** `.enabled` and capability gates live in `_app.yaml` (the wrapper), AND generators usually repeat the `.enabled` guard defensively inside their own define (`_mtls.yaml:2`, `_secret.yaml:5`). Both layers. Gating must happen OUTSIDE `platform.util.merge`/`fromYaml` — `fromYaml ""` yields `{}` which becomes a bogus empty doc (documented at `_util.tpl:28-29`; the gate has a negative test for `{}` docs).
3. **Calling conventions.** Helpers needing extra args take a list — `(list $top "Kind")` unpacked with `$top := index . 0` — or a dict for named args (`dict "root" . "job" $job`, see `_app.yaml:7-8`). Never assume `.` is root inside a multi-arg helper.
4. **Namespaces.** `platform.*` defines for single-chart use; `global.*` defines for umbrella/multi-chart helpers (`_helpers.tpl:483+`). New helpers: `platform.<noun>` or `platform.capabilities.<verb>`.
5. **Labels.** Every object gets `{{- include "platform.labels" . | nindent 4 }}` plus a manual `range` over `.Values.commonLabels` (quoted values) plus block-specific labels. `platform.selectorLabels` (`_helpers.tpl:46-49`) is the immutable subset — name + instance only; `commonLabels` must never leak into workload `selector.matchLabels`. (They do leak into the Service selector today — CORE.md tracked known issue, not a pattern to copy.)
6. **Values idioms.** Holder-dict for computed values (`dict "value" ...` + `set` — `_helpers.tpl:106,306`); build lists with `append` into a variable then a single `toYaml | nindent`; probes/securityContext blocks render with `omit ... "enabled"` (`_cronjob.yaml:56,80`); user-supplied scalars quoted (`{{ $v | quote }}`); numeric-capable fields via `printf "%v"` (image tag, `_helpers.tpl:66`).
7. **Fail messages are prescriptive**: name the offending values path and state the fix (models: `_helpers.tpl:68`, `_mtls.yaml:8`, `_util.tpl:99`). Every new `fail` gets a matching negative test in `lint-library.sh` that greps its message substring — the message and the test change together.
8. After any template edit, render early and often; finish with the full gate.

## Commands
```bash
tests/render.sh minimal                                        # fast parse/emit check (3 kinds)
tests/render.sh full | grep -cE '^\{\}\s*$'                    # must be 0 (no empty docs)
tests/render.sh full --set capabilities.apiVersions=null       # gated-out generators must emit nothing
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # passes at HEAD 4fb9386
```

## Quality bar
(1) All fixtures render byte-identical to goldens across 1.34-1.36 unless the change is intended; (2) no `fail` guardrail softened, no securityContext rendering path altered; (3) helper signatures are public API for advanced consumers — changing an existing define's arguments or output shape is a contract change.

## Verification checklist
- [ ] New generator has exactly one `define`, no leading `---`, wrapped in `platform.emit` at its `_app.yaml` call site
- [ ] Gated-out state emits empty string (verified via negative render: no `{}` docs, no doc merging)
- [ ] Multi-arg helpers unpack via `index . 0` / named dict keys; no bare `.Values` reliance on wrong scope
- [ ] Labels block matches peers; nothing new added to `selectorLabels`
- [ ] Gate `==> PASS`; golden diff empty or intentional

## Stop and ask before
- adding a non-underscore template file
- changing `platform.selectorLabels` output (selector labels are immutable on live workloads — changing them breaks `helm upgrade`)
- renaming or re-signaturing any existing `define` (public API)
- weakening a `fail` message or its coupled negative test

## Common mistakes
- Forgetting the emit wrapper — the new object merges into the previous YAML document; everything renders from one consumer template file.
- Emitting whitespace or `{}` when gated out (gate inside the merge/fromYaml instead of outside).
- Wrong `nindent` depth or missing `{{- -}}` chomps — YAML parse errors reported nowhere near the actual line.
- Reading `.Values` inside a list-args helper where `.` is the args list, not root.
- Copying the Service-selector `commonLabels` leak into a new generator because it "matches existing code" — it's a tracked known issue.

## Done means
- Render output clean (no empty docs, no merged docs), gate `==> PASS` pasted, and any helper-signature or label change explicitly flagged as contract-affecting.
