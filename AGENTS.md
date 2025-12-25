# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

Use 'bd' for task tracking

---

## Helm Chart Development Context

This document provides context, commands, and templating conventions for AI agents working on Helm v4 Charts. Use this for ideation, templating, and validating Kubernetes manifests.

### Build & Test Commands

- **Lint**: `helm lint .` - Checks for syntax errors and best practices
- **Render Templates (Local Debug)**: `helm template release-name . --debug` - Renders YAML to stdout without connecting to a cluster
- **Dry Run Install**: `helm install release-name . --dry-run --debug` - Simulates install against a cluster context if available
- **Update Dependencies**: `helm dependency update` - Downloads charts listed in Chart.yaml to charts/
- **Package**: `helm package .`
- **Test Release**: `helm test release-name` - Runs tests defined in templates/tests/ after installation

### Architecture Overview

- **Core**: Helm is the package manager for Kubernetes. It renders Go templates into Kubernetes manifests.
- **Version**: Helm v4.
- **Storage**: Release information is stored in Kubernetes Secrets by default (HELM_DRIVER=secret).
- **Registries**: OCI (Open Container Initiative) registries are first-class citizens.
- **Chart API**: Use `apiVersion: v2` in Chart.yaml.

### Directory Structure & Conventions

- **Chart.yaml**: Metadata. Must include `apiVersion: v2`, name, and version.
  - **Rule**: Quote the appVersion to avoid float/scientific notation parsing errors.
- **values.yaml**: Default configuration values.
  - **Style**: Prefer flat structure over deep nesting where possible.
  - **Naming**: camelCase (e.g., `serviceAccount`, `imagePullSecrets`).
- **templates/**: Contains manifest templates (.yaml) and helpers (.tpl).
  - **_helpers.tpl**: Store named templates here (e.g., `{{ define "mychart.labels" }}`).
- **NOTES.txt**: Plain text usage notes printed after install.
- **crds/**: Custom Resource Definitions. Plain YAML only. No templating allowed here in Helm 3/4.
- **charts/**: Managed by helm dependency. Do not manually modify unless vendoring.

### Templating & Built-in Objects

Helm templates use Go's text/template package extended with the Sprig function library.

#### 1. Built-in Objects

These objects are available in every template:

**Release**: Describes the release itself.

- `.Release.Name`: The release name.
- `.Release.Namespace`: The namespace the release is installed in.
- `.Release.IsInstall` / `.Release.IsUpgrade`: Boolean status.
- `.Release.Service`: The service rendering the template (always "Helm").

**Values**: Values passed into the template from values.yaml and user-supplied values (--set, -f).

**Chart**: Contents of Chart.yaml.

- `.Chart.Name`, `.Chart.Version`, `.Chart.AppVersion`.

**Files**: Access to non-template files in the chart.

- `.Files.Get "config.ini"`: Get file content as string.
- `.Files.GetBytes "image.png"`: Get file content as bytes.
- `.Files.Glob "patterns/*"`: Match files.
- `.Files.Lines "file.txt"`: Iterate line by line.
- `.Files.AsConfig` / `.Files.AsSecrets`: Helpers for ConfigMaps/Secrets.

**Capabilities**: Information about the Kubernetes cluster.

- `.Capabilities.KubeVersion.Version`: Kubernetes version (e.g., "v1.20.0").
- `.Capabilities.APIVersions.Has "batch/v1"`: Check if API version exists.

**Template**: Information about the current template.

- `.Template.Name`: Namespaced path to current file (e.g., mychart/templates/deployment.yaml).
- `.Template.BasePath`: Path to the templates directory.

#### 2. Essential Functions (Sprig + Helm)

##### Helm Specific

- **include**: Render a named template. Use this instead of template to enable pipeline processing (like indent).
  - Usage: `{{ include "template.name" context | indent 4 }}`
- **required**: Fail rendering if value is missing.
  - Usage: `{{ required "Value foo is missing" .Values.foo }}`
- **tpl**: Evaluate a string as a template inside a template.
  - Usage: `{{ tpl .Values.templateString . }}`
- **toYaml** / **fromYaml**: Convert between objects and YAML strings.
  - Usage: `{{ .Values.myObject | toYaml }}`
- **lookup**: Look up resources in the cluster (returns empty in dry-run).
  - Usage: `{{ (lookup "v1" "Namespace" "" "mynamespace").metadata.annotations }}`

##### String Manipulation

- `quote` / `squote`: Wrap in double/single quotes.
- `trim`, `trimAll`, `trimSuffix`, `trimPrefix`.
- `upper`, `lower`, `title`, `untitle`.
- `replace old new string`.
- `indent N string` / `nindent N string`: Indent lines. nindent adds a newline at the start.

##### Logic & Defaults

- **default**: Set a default value if the given value is empty.
  - Usage: `{{ .Values.foo | default "bar" }}`
- **empty**: Returns true if value is empty/null/zero.
- **coalesce**: Returns the first non-empty value from a list.
- **ternary**: Inline if/else.
  - Usage: `{{ .Values.enabled | ternary "true" "false" }}`

##### Encoding

- `b64enc` / `b64dec`: Base64 encode/decode.

##### Collections (Lists & Dicts)

- **list**: Create a list.
- **dict**: Create a dictionary (map). useful for passing multiple values to include.
  - Usage: `{{ include "my.template" (dict "val" .Values.foo "context" .) }}`
- **has**: Check if list contains element.
- **keys**, **values**: Get keys or values from map.

#### 3. Flow Control

##### If / Else

```go
{{- if .Values.enabled }}
enabled: true
{{- else if eq .Values.environment "production" }}
enabled: false
{{- else }}
enabled: false
{{- end }}
```

##### Range (Loops)

Iterates over maps or lists. Note: `.` changes scope inside the loop.

```go
{{- range $key, $value := .Values.map }}
{{ $key }}: {{ $value | quote }}
{{- end }}
```

##### With (Scope)

Restricts scope to the variable. `.` becomes the variable.

```go
{{- with .Values.ingress }}
hostname: {{ .hostname }}  {{/* Refers to .Values.ingress.hostname */}}
{{- end }}
```

##### Variables

Assign variables to persist data across scopes or simplify paths.

```go
{{- $relName := .Release.Name -}}
{{- $servicePort := .Values.service.port -}}
```

### Best Practices & Safety

**Named Templates**: Always use `include` instead of `template` to allow for proper indentation.

- Pattern: `{{ include "mychart.fullname" . | indent 4 }}`

**Labels**: Use standard Kubernetes labels in _helpers.tpl.

- `app.kubernetes.io/name`
- `app.kubernetes.io/instance`
- `app.kubernetes.io/version`
- `app.kubernetes.io/managed-by`
- `helm.sh/chart`

**Safety**:

- Use `quote` for strings that look like numbers or booleans (e.g., "true", "1.0").
- Use `required` to fail generation if a critical value is missing.

**Whitespace Control**:

- Use `{{-` (chomp left) and `-}}` (chomp right) to remove whitespace and newlines generated by logic tags.

**Root Scope**:

- Remember that `with` and `range` change the `.` scope. Use `$` to access the root scope (e.g., `$.Values`, `$.Release`, `$.Chart`) from inside a loop or with block.

### Helm v4 Specific Changes & Flags

- **Flag Renames**: Do not use the old v3 flags.
  - Use `--rollback-on-failure` instead of `--atomic`.
  - Use `--force-replace` instead of `--force`.
- **Registry Login**: `helm registry login` accepts a domain name only (no full URL schema).
- **OCI Support**: Install by digest is supported: `helm install myapp oci://registry.example.com/charts/app@sha256:....`

### Workflow Essentials

- **Scaffold**: Start with `helm create <name>` to generate directory structure.
- **Iterate**: Modify values.yaml and templates/ simultaneously.
- **Validate**: Run `helm lint` frequently.
- **Debug**: Use `helm template . --debug` to inspect generated YAML logic before attempting install.
- **Hooks**: Use annotations `helm.sh/hook` for pre/post install logic (e.g., DB migrations).
