# Concept: the emit invariant

The whole release renders from ONE consumer template file (`{{ include "platform.render" . }}`), so document separation is a discipline, not a given.

`platform.emit` (`_util.tpl:14-20`) prefixes `---` only when the rendered content is non-empty after trim. Every tier-1 object in `_app.yaml` is wrapped: `{{- include "platform.emit" (include "platform.<thing>" .) }}`. Generators themselves do NOT start with `---`; multi-doc generators (`_mtls.yaml:24`, `_gateway-api.yaml`) put `---` only *between* their own documents.

Failure modes the invariant prevents:
- Generator emits without the wrapper → its output **merges into the previous document** (invalid or, worse, silently wrong manifests).
- Gated-out generator still emits a separator or `{}` → bogus empty documents.

Related invariant: enable/capability gating must happen **outside** any `fromYaml` round-trip, because `fromYaml ""` yields `{}`.

Enforced by [[lint-library-gate]]'s negative render, which asserts no `^{}$` documents (`scripts/lint-library.sh:172-176`). Verified passing 2026-07-10.

Sources: raw/util-emit-merge-source.md; `_app.yaml` read 2026-07-10, HEAD 4fb9386.
