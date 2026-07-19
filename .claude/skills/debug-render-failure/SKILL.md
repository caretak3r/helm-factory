---
name: debug-render-failure
description: Use when helm template or tests/render.sh fails, or when an expected object is missing from rendered output. Do not use for gate/count/golden failures with a clean render (see validate-factory) or for designing new capability behavior (see capability-gates).
---

# Debug a Render Failure

## First rule
Reproduce before you guess. Run the exact failing command yourself and read the full error. This repo's failures fall into four distinct classes with four distinct fixes — classifying first prevents the classic mistake of "fixing" the library when the render was correct.

## Steps
1. Reproduce: `tests/render.sh <fixture>` (or `helm template <name> <dir>` for external consumers), capturing stderr.
2. Classify the failure:
   - **Class A — intentional `fail` guardrail.** Error text names a values path and states the fix (e.g. "…tag and …digest are both empty", "mtls.allowedPrincipals is empty", "cluster-scoped Kind", "mutually exclusive", "Script file not found", "both target the Secret" for certificate+tlsSelfSigned both enabled, "would not exist" for ingress enabled without service). The message IS the fix — change the consumer values it names. Never weaken the guardrail. Sources: `_helpers.tpl:111`, `_helpers.tpl:747`, `_mtls.yaml:8`, `_util.tpl:83`, `_secret.yaml:3`, `_configmap-script.yaml:58`, `_app.yaml:21`, `_app.yaml:59`.
   - **Class B — helm-side schema rejection.** Error cites a JSON-pointer path like `workload/type` or `image/tag`. The consumer's values violate `values.schema.json` (enums are exact-case: `Deployment|StatefulSet|DaemonSet`; `tag: latest` is rejected). Fix the values; if the schema itself is wrong, that's a values-contract-change.
   - **Class C — object silently missing, no error.** Almost always a capability skip: CRD-backed Kinds (Certificate, HTTPRoute, GRPCRoute, PeerAuthentication, AuthorizationPolicy, ServiceMonitor, PodMonitor) vanish by design under `helm template` without force-assume. Fix: add the group to `capabilities.apiVersions` in values (matches `group/version` or `group/version/Kind`); the CLI equivalent `--api-versions` only works in the full `group/version/Kind` form (a bare `group/version` flag still skips, silently). NOT a bug; never remove the gate or switch it to OrDefault. Other causes, in order: `.enabled` false after coalescing; missing `import-values: [defaults]` (everything empty); missing registry entry (`_capabilities.tpl:76-176`) making `apiVersionFor` return "".
   - **Class D — template/whitespace/YAML error.** Cryptic parse errors. Check, in order: malformed YAML inside the registry define (breaks every render, error far from the edit); missing `platform.emit` wrapper (docs merged together); wrong `nindent` depth; missing `{{- -}}` chomps; a helper emitting `{}` when gated out (`fromYaml ""` → `{}`; the gate must sit outside any `fromYaml` round-trip).
3. Make ONE change, re-run the same command, compare. Repeat.
4. If you changed library templates, finish with the full gate (validate-factory).

## Commands
```bash
tests/render.sh <fixture> 2>&1 | tail -20                     # reproduce
tests/render.sh full | grep '^kind:'                          # what actually rendered (expect 26)
tests/render.sh full --set capabilities.apiVersions=null      # prove CRD kinds drop (Class C check)
tests/render.sh <fixture> --kube-version 1.34 --api-versions cert-manager.io/v1/Certificate   # force one API (CLI needs full group/version/Kind)
helm template t tests/fixtures/<fixture> --debug 2>&1 | tail -30   # after render.sh has built charts/; shows partial render
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # if library templates changed
```

## Quality bar
(1) The fix keeps all four fixtures rendering across k8s 1.34-1.36 (gate `==> PASS`); (2) no guardrail, schema constraint, or capability gate was weakened to make the error go away — the error is usually correct behavior pointed at wrong input; (3) no values key renamed as a "fix".

## Verification checklist
- [ ] Failure reproduced verbatim before any edit; class (A/B/C/D) stated
- [ ] Fix targets the class (values for A/B, capabilities for C, template mechanics for D)
- [ ] The originally failing command now exits 0 with the expected object present
- [ ] Library changes: full gate `==> PASS`; goldens/counts unchanged unless intended
- [ ] For Class C: object present WITH force-assume and absent WITHOUT — both verified

## Stop and ask before
- deleting or softening any `fail` call or its message text (each is coupled to a negative test in `lint-library.sh` that greps the message — change both together, and only with cause)
- switching a CRD Kind from `apiVersionFor` to `apiVersionForOrDefault`
- editing `tests/golden/*.yaml` by hand or "fixing" `normalize_render`
- disabling schema copy in `tests/render.sh:16` to bypass a schema rejection

## Common mistakes
- Misdiagnosing a Class C capability skip as a bug and "fixing" the gate — the objects are absent offline by design.
- Editing fixture `charts/` or `values.schema.json` (regenerated, gitignored — your edit evaporates on the next render).
- Chasing tlsSelfSigned cert differences between renders: a fresh cert per offline render is expected (`lookup` is empty under template); goldens redact it.
- Fixing the symptom in one fixture's values when the actual bug is in a generator (check whether other fixtures show it too).
- Two failed fix attempts on the same hypothesis: stop, re-read the whole generator top-down, restate where your model was wrong.

## Done means
- Failure class named, root cause stated in one sentence, fix applied at the right layer, the originally failing command's clean output pasted, and (for library edits) gate `==> PASS` pasted.
