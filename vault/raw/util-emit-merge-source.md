# Raw: _util.tpl — emit + merge source

Provenance: verbatim copy of `platform-library/templates/_util.tpl` lines 6-36, taken 2026-07-10 at HEAD 4fb9386 (branch handover/2026-07-10). Not edited.

```text

{{/*
platform.emit — prefix a rendered manifest string with a document separator,
but only when it is non-empty (after trimming). Because platform.render
concatenates many generators into a single template file, every top-level
object must carry its own leading "---" or adjacent docs merge into one.
Usage: include "platform.emit" (include "platform.service" .)
*/}}
{{- define "platform.emit" -}}
{{- $content := . | trim -}}
{{- if $content }}
---
{{ $content }}
{{- end }}
{{- end -}}

{{/*
platform.util.merge — merge a consumer-supplied override template over a base
template (bitnami/common style) and emit the result. Takes a list:
  0: the top context ($)
  1: template name of the overrides (destination)
  2: template name of the base (source)
IMPORTANT: capability/enable gating must happen in the *wrapper* before calling
this, never here — fromYaml "" yields {} which would emit a bogus empty doc.
*/}}
{{- define "platform.util.merge" -}}
{{- $top := first . -}}
{{- $overrides := fromYaml (include (index . 1) $top) | default (dict) -}}
{{- $tpl := fromYaml (include (index . 2) $top) | default (dict) -}}
{{- toYaml (mergeOverwrite $tpl $overrides) -}}
{{- end -}}
```
