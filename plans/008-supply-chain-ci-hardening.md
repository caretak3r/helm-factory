# Plan 008: Supply-chain pinning + CI hygiene for workflows and vendored schema sources

> **BEAD OVERLAP — READ FIRST**: This plan overlaps the existing bead
> **`hf-ocq`** (CI/supply-chain hardening). The orchestrator will UPDATE that
> bead to point at this plan — do NOT create a duplicate bead, and do NOT
> close `hf-ocq` yourself unless the orchestrator's dispatch says you own it.

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 583b401..HEAD -- .github/workflows scripts/vendor-schemas.sh scripts/new-app-chart.sh tests/schemas CHANGELOG.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW-MED (workflow changes are only provable end-to-end on a PR
  run; everything else verifies locally)
- **Depends on**: none. Interaction: plans/007 RUNS `scripts/vendor-schemas.sh`;
  if this plan lands first, 007 benefits from pinned sources — coordinate but
  don't block.
- **Category**: security / dx
- **Planned at**: commit `583b401`, 2026-07-28

## Why this matters

The release pipeline publishes a chart consumed by every downstream app team,
but its own inputs are unpinned (survey findings #8, #14, #20): helm and
kubeconform are curl'd with no checksum, GitHub Actions ride floating tags,
the schema vendoring script fetches `@master`/`@main`, and `pipx install` is
versionless. A compromised or substituted upstream artifact would flow
straight into the gate that decides what gets published — and in release.yaml
that job also holds `packages: write`. Separately, docs.yaml grants
`pages: write` + `id-token: write` workflow-wide, including to the PR build
job that runs `npm ci` over a dependency tree with 23 high advisories —
untrusted-adjacent code running with deploy-capable permissions. Finally, CI
hygiene gaps: no concurrency cancellation, `scripts/lib/*.sh` outside the
direct shellcheck glob, the scaffolder never smoke-tested, and no pre-tag
validation (release gates run only AFTER the tag exists; a bad tag needs
manual deletion).

## Current state

Files and roles:

- `.github/workflows/ci.yaml` (47 lines) — PR/main gate: shellcheck, helm
  lint, metaschema check, full lint gate.
- `.github/workflows/release.yaml` (85 lines) — tag-triggered: same gates,
  then GHCR push. Workflow-wide `permissions: contents: read, packages: write`
  (`:8-10`).
- `.github/workflows/docs.yaml` (104 lines) — Docusaurus build/deploy.
- `scripts/vendor-schemas.sh` — downloads JSON schemas into `tests/schemas/`;
  regenerates `tests/schemas/README.md`.
- `scripts/new-app-chart.sh` (167 lines) — consumer-chart scaffolder; takes
  `--dir`, `--repo`, `--version`, `--app-version`; default repo is the
  RELATIVE `file://../platform-library` (matters for the smoke test).
- `scripts/lint-library.sh` sources `scripts/lib/schema-manifest.sh`;
  shellcheck currently reaches `scripts/lib/` only transitively via `-x`
  from sourcing scripts (`shellcheck -x scripts/*.sh tests/render.sh`,
  ci.yaml:37) — a NEW file under `scripts/lib/` not yet sourced anywhere
  would go unlinted.

### Unpinned tool downloads (identical blocks in ci.yaml:21-34 and release.yaml:22-35)

```yaml
# Tool versions mirror .github/workflows/ci.yaml exactly — keep in sync.   <- release.yaml:21
- name: Install helm
  run: |
    curl -fsSL https://get.helm.sh/helm-v4.2.0-linux-amd64.tar.gz | tar -xz -C /tmp
    sudo install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
    helm version --short

- name: Install kubeconform
  run: |
    curl -fsSL https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz | tar -xz -C /tmp kubeconform
    sudo install -m 0755 /tmp/kubeconform /usr/local/bin/kubeconform
    kubeconform -v

- name: Install check-jsonschema
  run: pipx install check-jsonschema
```

### Floating action tags (all `uses:` sites in the repo)

```
ci.yaml:18       actions/checkout@v4
release.yaml:19  actions/checkout@v4
docs.yaml:38,74  actions/checkout@v4
docs.yaml:41,77  actions/setup-node@v4
docs.yaml:56     actions/configure-pages@v5
docs.yaml:63     actions/upload-pages-artifact@v3
docs.yaml:103    actions/deploy-pages@v4
```

### docs.yaml permissions (`:21-28`)

```yaml
permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false
```

Jobs: `build` (main only; runs `npm ci`+build, `configure-pages` with
`enablement: true`, uploads artifact), `build-pr` (PR only; `npm ci`+build —
inherits the workflow-wide write perms it does not need), `deploy`
(main only, `environment: github-pages`, `deploy-pages`).

### vendor-schemas.sh floating refs (`:28-29`)

```bash
NATIVE_SOURCE_BASE='https://cdn.jsdelivr.net/gh/yannh/kubernetes-json-schema@master'
CRD_SOURCE_BASE='https://cdn.jsdelivr.net/gh/datreeio/CRDs-catalog@main'
```

### Release-order gotcha (repo CLAUDE.md)

"Gates run AFTER the tag exists — a bad tag needs manual deletion before
retry." release.yaml:37-54 verifies tag↔Chart.yaml version and the CHANGELOG
heading — post-tag. Nothing runs those checks pre-tag today.

### Deliberately out of scope in release.yaml (`:83-84`)

Cosign signing is named future work (tracked as bead `hf-j30`) — do not
implement it here.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| THE gate (definition of done) | `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` | ends `==> PASS`, exit 0 |
| Shellcheck (new glob) | `shellcheck -x scripts/*.sh scripts/lib/*.sh tests/render.sh` | exit 0 |
| Workflow lint (if installed) | `actionlint .github/workflows/*.yaml` | exit 0 (else: `yq . <file>` parses) |
| Resolve a tag to a SHA | `git ls-remote https://github.com/actions/checkout refs/tags/v4\*` | tag→SHA lines |
| Re-vendor schemas (network) | `scripts/vendor-schemas.sh` | exit 0 |
| Golden diff check | `git diff --exit-code tests/golden/` | exit 0 |

## Scope

**In scope** (the only files you should modify):
- `.github/workflows/ci.yaml`
- `.github/workflows/release.yaml`
- `.github/workflows/docs.yaml`
- `scripts/vendor-schemas.sh`
- `scripts/preflight-release.sh` (create)
- `tests/schemas/**` (only as `scripts/vendor-schemas.sh` output)
- `CHANGELOG.md` (`[Unreleased]` release-process note)

**Out of scope** (do NOT touch):
- Cosign signing / provenance (bead `hf-j30`; release.yaml:83-84).
- `site/` npm dependency remediation (the 23 high advisories) — separate
  effort; this plan only removes the excess permissions around it.
- `scripts/new-app-chart.sh` — the smoke test CALLS it; don't modify it.
- `scripts/lint-library.sh`, `tests/render.sh`, `platform-library/**`,
  `tests/golden/**`.
- Tool VERSION bumps (helm v4.2.0, kubeconform v0.8.0 stay; this plan adds
  integrity pins, not upgrades).

## Git workflow

- Branch: `advisor/008-supply-chain-ci-hardening` off `main`.
- Conventional Commits, e.g. `ci: checksum-pin tool downloads and SHA-pin actions`,
  `build(schemas): pin vendor sources to commit SHAs`.
- Repo rule is PR-only main with squash-merge; do NOT push or open a PR
  unless the operator instructed it. The PR run itself is the end-to-end
  proof for workflow edits — say so in the handoff.

## Steps

### Step 1: Checksum-pin the helm and kubeconform downloads (ci.yaml + release.yaml)

Obtain the official checksums (record where each came from in the commit
message):

```bash
curl -fsSL https://get.helm.sh/helm-v4.2.0-linux-amd64.tar.gz.sha256sum
# helm publishes "<sha256>  helm-v4.2.0-linux-amd64.tar.gz"
curl -fsSL -o /tmp/kc-checksums https://github.com/yannh/kubeconform/releases/download/v0.8.0/CHECKSUMS
grep 'kubeconform-linux-amd64.tar.gz' /tmp/kc-checksums
```

Cross-check each by downloading the artifact and computing
`shasum -a 256 <file>` — the vendor-published and computed values MUST match
(mismatch = STOP condition, not a value to "correct").

Replace both install steps in BOTH workflows (keep the mirror-comment at
release.yaml:21 and extend it: "…exactly — keep in sync, including
checksums."). Target shape:

```yaml
- name: Install helm
  run: |
    curl -fsSL -o /tmp/helm.tgz https://get.helm.sh/helm-v4.2.0-linux-amd64.tar.gz
    echo "<sha256-from-vendor>  /tmp/helm.tgz" | sha256sum -c -
    tar -xz -C /tmp -f /tmp/helm.tgz
    sudo install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
    helm version --short

- name: Install kubeconform
  run: |
    curl -fsSL -o /tmp/kubeconform.tgz https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz
    echo "<sha256-from-vendor>  /tmp/kubeconform.tgz" | sha256sum -c -
    tar -xz -C /tmp -f /tmp/kubeconform.tgz kubeconform
    sudo install -m 0755 /tmp/kubeconform /usr/local/bin/kubeconform
    kubeconform -v
```

(ubuntu runners have `sha256sum`; do not use macOS-only `shasum` in
workflows.)

**Verify** (local mutation test — the workflow can't run locally): execute
the exact download+verify lines in a shell with the REAL checksum → `OK`,
exit 0. Then repeat with one hex digit flipped → `FAILED`, non-zero exit.
Paste both results in the completion report.

### Step 2: Pin check-jsonschema in both workflows

Determine the current released version (`pipx install check-jsonschema`
locally reports it, or check PyPI at implementation time), then in
ci.yaml:34 and release.yaml:35:

```yaml
- name: Install check-jsonschema
  run: pipx install check-jsonschema==<version>
```

**Verify**: `grep -n 'check-jsonschema==' .github/workflows/*.yaml` → 2 hits
with identical versions.

### Step 3: Pin all actions to full commit SHAs

For each action listed in "Current state", resolve the LATEST tag of the
currently-used major to its commit SHA:

```bash
git ls-remote https://github.com/actions/checkout refs/tags/v4\*
# pick the newest v4.x.y; a tag may be annotated — prefer the ^{} (peeled) line's SHA when present
```

Rewrite every `uses:` as `<owner>/<repo>@<40-hex-sha> # vX.Y.Z` (the trailing
comment is the human-readable version, kept accurate for Dependabot-style
review). Nine sites across the three workflows.

**Verify**:
`grep -rn 'uses:' .github/workflows/ | grep -v '@[0-9a-f]\{40\}'` → no output
(every `uses:` is SHA-pinned). Spot-check one: re-run `git ls-remote` for the
tag in the comment and confirm the SHA matches.

### Step 4: Pin vendor-schemas.sh source refs and re-vendor

Resolve current HEADs:

```bash
git ls-remote https://github.com/yannh/kubernetes-json-schema refs/heads/master
git ls-remote https://github.com/datreeio/CRDs-catalog refs/heads/main
```

Replace `@master`/`@main` in `scripts/vendor-schemas.sh:28-29` with
`@<full-sha>`, each with a comment noting the ref and pin date, e.g.:

```bash
# Pinned 2026-07-XX (master); bump deliberately, then re-run this script.
NATIVE_SOURCE_BASE='https://cdn.jsdelivr.net/gh/yannh/kubernetes-json-schema@<sha>'
```

Then run `scripts/vendor-schemas.sh` and inspect `git diff tests/schemas/`.
Expected: empty apart from README regeneration. If any schema file changed,
upstream moved since the original vendoring — the pin is now capturing that
new state: run the full gate; if it PASSES, keep the updated schemas and note
the upstream drift in the commit message; if it FAILS, STOP.

**Verify**: `scripts/vendor-schemas.sh` exits 0;
`REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh`
→ `==> PASS`; `git diff --exit-code tests/golden/` → exit 0.

### Step 5: Scope docs.yaml permissions per job

Replace the workflow-level block so write permissions exist only where used
(`configure-pages` with `enablement: true` needs `pages: write`;
`deploy-pages` needs `pages: write` + `id-token: write`):

```yaml
permissions:
  contents: read
```

then per job:

```yaml
jobs:
  build:
    permissions:
      contents: read
      pages: write        # configure-pages enablement:true
  build-pr:
    permissions:
      contents: read      # npm ci over an advisory-laden tree gets nothing else
  deploy:
    permissions:
      pages: write
      id-token: write
```

Keep the `:19-20` "docs build failure must never block a chart release"
comment and the existing `concurrency: pages` block.

**Verify**: `actionlint .github/workflows/docs.yaml` → exit 0 (or `yq`
parse); `grep -A3 'build-pr:' .github/workflows/docs.yaml | grep -c 'write'`
→ `0`.

### Step 6: CI hygiene in ci.yaml

6a. Concurrency (cancel superseded PR runs, never main):

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

6b. Direct shellcheck coverage for `scripts/lib/` (ci.yaml:37 AND the
mirrored step at release.yaml:58):

```yaml
run: shellcheck -x scripts/*.sh scripts/lib/*.sh tests/render.sh
```

6c. Scaffolder smoke test — new step after the lint-library step. The
scaffolder's DEFAULT repo is relative (`file://../platform-library`), which
breaks outside the repo root, so pass an absolute one:

```yaml
- name: scaffolder smoke test
  run: |
    scripts/new-app-chart.sh smoke --dir "$RUNNER_TEMP/smoke" --repo "file://$GITHUB_WORKSPACE/platform-library"
    helm dependency update "$RUNNER_TEMP/smoke" >/dev/null
    helm template smoke "$RUNNER_TEMP/smoke" | grep -q '^kind: Deployment'
```

Deliberate rejection (record, don't implement): actions/cache for the tool
downloads — the whole CI gate is ≈26s; caching adds surface for negligible
gain. Note this in the completion report so finding #20's caching leg isn't
re-audited.

**Verify** (locally, same commands the step runs):

```bash
tmp=$(mktemp -d)
scripts/new-app-chart.sh smoke --dir "$tmp/smoke" --repo "file://$PWD/platform-library"
helm dependency update "$tmp/smoke" >/dev/null
helm template smoke "$tmp/smoke" | grep -c '^kind: Deployment'
```

→ scaffold banner, then `1`. Also `rm -rf "$tmp"` after.

### Step 7: Pre-tag validation script

Create `scripts/preflight-release.sh` replicating release.yaml:37-54's checks
BEFORE a tag exists (usage: run on the release-prep branch; catches the
"bad tag needs manual deletion" failure class). Follow the repo's script
style (`set -euo pipefail`, `die()` helper — model on
`scripts/new-app-chart.sh:23,34`). Checks, against the intended version read
from `platform-library/Chart.yaml`:

1. `version:` parses from Chart.yaml (same awk as release.yaml:39).
2. `CHANGELOG.md` has a `## [<version>]` heading (same grep as
   release.yaml:50, escaped dots).
3. `git tag -l "v<version>"` is empty (tag not already taken).
4. Prints `preflight OK: ready to tag v<version>` on success; `die`s with
   the specific failure otherwise.

**Verify**: `scripts/preflight-release.sh` at `583b401`-era state → exits
non-zero complaining `## [2.1.0]`… wait — 2.1.0 IS released and its heading
exists, and tag v2.1.0 exists → check 3 must FAIL. That is correct behavior
(current version is already tagged; preflight is for the NEXT release).
Confirm: run it → expect `die` naming the existing tag `v2.1.0`, non-zero
exit. Then mutation-style positive check: temporarily bump
`platform-library/Chart.yaml` version to `9.9.9` and add a `## [9.9.9]`
CHANGELOG heading → script exits 0 with `preflight OK` → revert both edits
(`git checkout -- platform-library/Chart.yaml CHANGELOG.md`).
`shellcheck -x scripts/preflight-release.sh` → exit 0.

### Step 8: CHANGELOG note + final sweep

Add under `## [Unreleased]` (create the subsection if plans/005's entry
already restructured it — append, don't clobber):

```markdown
### Changed — release engineering

- CI/release/docs workflows now checksum-pin the helm and kubeconform
  downloads, pin all GitHub Actions to commit SHAs, and pin
  `check-jsonschema`; schema vendoring sources are pinned to commit SHAs.
  Docs workflow permissions are scoped per job. New
  `scripts/preflight-release.sh` validates tag readiness before tagging.
```

**Verify** (full sweep):
`REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` →
`==> PASS`; `shellcheck -x scripts/*.sh scripts/lib/*.sh tests/render.sh` →
exit 0; `actionlint .github/workflows/*.yaml` → exit 0 (or yq parse of all
three); `git diff --exit-code tests/golden/` → exit 0.

## Test plan

Workflow YAML cannot be executed locally; the layered proof is:

- Local execution of every embedded shell block (checksum verify + flipped-
  digit mutation in Step 1; scaffolder smoke in Step 6; preflight negative +
  positive in Step 7).
- `actionlint` (available via homebrew) or `yq` parse across all three
  workflows.
- Full gate + golden check unchanged (Step 4/8) — proves the re-vendored
  schemas didn't shift gate behavior.
- End-to-end proof lands with the PR's own CI run — state in the handoff
  that the PR checks (including the new smoke step) are the final gate.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `grep -rn 'uses:' .github/workflows/ | grep -v '@[0-9a-f]\{40\}'` → empty
- [ ] `grep -c 'sha256sum -c' .github/workflows/ci.yaml` → 2; same for release.yaml
- [ ] `grep -c 'check-jsonschema==' .github/workflows/*.yaml` total → 2
- [ ] `grep -cE '@(master|main)' scripts/vendor-schemas.sh` → 0
- [ ] docs.yaml `build-pr` job has no `write` permission
- [ ] Step 1 flipped-digit mutation demonstrated FAILED locally
- [ ] Scaffolder smoke commands succeed locally (`kind: Deployment` found)
- [ ] `scripts/preflight-release.sh` exists; negative + positive behavior demonstrated; shellcheck-clean
- [ ] `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` ends `==> PASS`, exit 0
- [ ] `git diff --exit-code tests/golden/` exits 0
- [ ] CHANGELOG `[Unreleased]` has the release-engineering note
- [ ] Only in-scope files modified (`git status`)

## STOP conditions

Stop and report back (do not improvise) if:

- A vendor-published checksum does NOT match the computed hash of the
  downloaded artifact — possible supply-chain event; do not ship the
  computed value as the pin. Report both values and the URLs.
- Re-vendoring under pinned SHAs changes gate outcome (`==> FAIL`) — the
  upstream schema drift is semantic; report the failing section and diff.
- A `git ls-remote` tag resolution is ambiguous (tag moved, or annotated-tag
  peel missing) — report rather than guessing which SHA to pin.
- `configure-pages`/`deploy-pages` demonstrably need permissions beyond
  Step 5's grants (only provable on a real run — if the PR's docs check
  fails on permissions, report; do not restore workflow-wide writes).
- The live workflow files differ from the excerpts (drift since `583b401`).

## Maintenance notes

- Pins are now deliberate debt: bumping helm/kubeconform/actions/schema
  sources means updating SHA + checksum together (the mirror-comment in
  release.yaml:21 now covers checksums too). Consider Dependabot/Renovate
  for `.github/workflows` as a follow-up — both understand SHA-pins with
  version comments.
- `scripts/preflight-release.sh` should be wired into the
  `release-platform-library` skill's checklist (skill edit deferred out of
  this plan).
- Deferred, per scope: `site/` npm advisory remediation (finding #14's other
  half), cosign signing (`hf-j30`), tool version upgrades.
- Reviewer scrutiny: the two workflows' install blocks must stay
  byte-mirrored; the smoke test must keep using an ABSOLUTE `--repo` path;
  release.yaml `packages: write` remains workflow-wide only because the
  single job needs it — if a second job is ever added there, scope it then.
