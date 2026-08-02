# Plan 006: Cache the fixture dependency build — cut ~97% of gate render overhead

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 583b401..HEAD -- tests/render.sh .gitignore tests/fixtures`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (touches the render path every gate assertion depends on)
- **Depends on**: none (soft ordering: land before plans/007, which adds more
  renders and benefits from the speedup; no code dependency)
- **Category**: dx / perf
- **Planned at**: commit `583b401`, 2026-07-28

## Why this matters

Every one of the ~60 renders in the full lint gate pays a full dependency
rebuild: measured ≈2.77s for `rm -rf charts && helm dependency update` versus
≈0.035s for the `helm template` itself — the rebuild is ~97% of per-render
cost and ≈168s of the ~4-minute local gate wall time. The dependency being
rebuilt is always the same artifact: the local `platform-library/` packaged
into the fixture's `charts/` directory. Packaging it once per
library-content-state and copying the cached archive makes the warm-path
render ~30x faster, shortens every local iteration, and makes future
guardrail additions (plans/007) nearly free. Correctness must be preserved
exactly: identical rendered bytes, correct behavior when `platform-library/`
changes mid-iteration, and no breakage of `UPDATE_GOLDEN`, subset `FIXTURES=`
runs, or standalone `tests/render.sh` use.

## Current state

- `tests/render.sh` — the single render entrypoint used by the gate, by
  `UPDATE_GOLDEN` refreshes, and standalone. Full current content (18 lines):

```bash
#!/usr/bin/env bash
# Rebuild the platform-library dependency into a fixture and render it.
# Usage: tests/render.sh <fixture> [helm template extra args...]
#   tests/render.sh full
#   tests/render.sh full --kube-version 1.34 --api-versions cert-manager.io/v1/Certificate
# NOTE: --api-versions needs the full group/version/Kind form; a bare
# group/version does NOT satisfy the capability gate (silent skip, exit 0).
# Only the capabilities.apiVersions values list accepts bare group/version.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="${1:?usage: render.sh <fixture> [helm args...]}"; shift || true
dir="$here/fixtures/$fixture"
rm -rf "$dir/charts" "$dir/Chart.lock"
# Enforce the root values contract exactly like a generated consumer chart:
# Helm validates values.schema.json against the coalesced (post-import) values.
cp "$here/../platform-library/values.schema.reference.json" "$dir/values.schema.json"
helm dependency update "$dir" >/dev/null
helm template t "$dir" "$@"
```

- Every fixture (`tests/fixtures/{minimal,full,stateful,daemon}/Chart.yaml`)
  declares the dependency as a **local file reference** — e.g.
  `tests/fixtures/full/Chart.yaml:7-12`:

```yaml
dependencies:
  - name: platform
    version: ">=2.0.0-0"
    repository: file://../../../platform-library
    import-values:
      - defaults
```

- `platform-library/Chart.yaml:5` → `version: 2.1.0`, so `helm package` /
  `helm dependency update` produce `platform-2.1.0.tgz`. Do not hardcode the
  version anywhere — glob `platform-*.tgz`.
- `platform-library/` contains ONLY `Chart.yaml`, `templates/`, `values.yaml`,
  `values.schema.reference.json` — no `.helmignore`, so `helm package` and
  `helm dependency update` package identical content.
- Helm satisfies dependencies from an existing `charts/` directory (tgz or
  unpacked) without needing `Chart.lock`.
- `.gitignore` already ignores `charts/`, `*.tgz`, `Chart.lock` (lines 12-15);
  the new cache directory still gets its own explicit entry.
- The gate (`scripts/lint-library.sh`) calls render via `$RENDER` ≈60 times;
  `UPDATE_GOLDEN=1 scripts/lint-library.sh` rewrites goldens through the same
  path. Design invariant 4: goldens are byte-exact contract — this plan must
  produce ZERO golden diffs.
- Known timing baseline (measured at `583b401` — do not re-measure the old
  path beyond the comparison step below): per-render dep rebuild ≈2.77s;
  `helm template` alone ≈0.035s; full local gate ≈4 min; the same gate on
  GitHub Actions ≈26s (beefier I/O — CI benefit is smaller but real).
- Concurrency reality: sibling agents/sessions may run renders at the same
  time (the repo has a known fixture-artifact race for concurrent full-gate
  runs). The cache is new SHARED state and must be written atomically; cache
  reads must only ever see absent-or-complete entries.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| THE gate (definition of done) | `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` | ends `==> PASS`, exit 0 |
| Fast subset loop | `FIXTURES=minimal scripts/lint-library.sh` | ends `==> PASS (subset)` |
| Render one fixture | `tests/render.sh <fixture> [args...]` | manifests on stdout |
| Golden refresh (idempotence check only) | `UPDATE_GOLDEN=1 scripts/lint-library.sh` | ends `==> PASS`; `git diff` clean after |
| Shellcheck | `shellcheck -x scripts/*.sh tests/render.sh` | exit 0 |
| Golden diff check | `git diff --exit-code tests/golden/` | exit 0 |
| Timing | `time tests/render.sh full >/dev/null` | see Step 4 targets |

## Scope

**In scope** (the only files you should modify):
- `tests/render.sh`
- `.gitignore` (one line)

**Out of scope** (do NOT touch):
- `scripts/lint-library.sh` — it consumes `$RENDER` unchanged; the speedup is
  entirely inside render.sh.
- `tests/fixtures/*/Chart.yaml` — the dependency declaration stays as-is.
- `tests/golden/*.yaml` — must not change; never run `UPDATE_GOLDEN` except
  for the idempotence check in Step 6 (which must produce zero diffs).
- `platform-library/**` — except the temporary, reverted cache-bust edit in
  Step 5.
- Any CI workflow — CI picks the speedup up for free through render.sh.

## Git workflow

- Branch: `advisor/006-gate-render-speed` off `main`.
- Conventional Commits, e.g.
  `perf(tests): cache packaged platform-library dep across renders`.
- Repo rule is PR-only main with squash-merge; do NOT push or open a PR
  unless the operator instructed it.

## Steps

### Step 1: Add the content-addressed package cache to `tests/render.sh`

Design (all inside render.sh — it must stay standalone-usable):

- **Cache location**: `tests/.dep-cache/<key>/platform-<version>.tgz`.
- **Key**: sha256 over the sorted (path, content-hash) list of every file
  under `platform-library/` — any content change (including Chart.yaml
  version bumps) produces a new key, which is the staleness guarantee for
  mid-iteration library edits.
- **Build**: on cache miss, `helm package platform-library` into a temp dir
  under the cache root, then a two-step rename into place. The final
  `mv` within one directory is atomic; racing writers produce identical
  bytes (the key IS the content hash), so a lost race is harmless.
- **Consume**: keep `rm -rf "$dir/charts" "$dir/Chart.lock"`, then
  `mkdir -p "$dir/charts"` and `cp` the cached tgz in. Helm satisfies the
  dependency from `charts/` without `Chart.lock`.
- **Escape hatch**: `RENDER_DEP_CACHE=0` falls back to the old
  `helm dependency update` path (debugging aid and behavior oracle for
  Step 3).

Target content (replace the body after the `cp ... values.schema.json` line;
keep the existing header comments and add cache notes to them):

```bash
#!/usr/bin/env bash
# Rebuild the platform-library dependency into a fixture and render it.
# Usage: tests/render.sh <fixture> [helm template extra args...]
#   tests/render.sh full
#   tests/render.sh full --kube-version 1.34 --api-versions cert-manager.io/v1/Certificate
# NOTE: --api-versions needs the full group/version/Kind form; a bare
# group/version does NOT satisfy the capability gate (silent skip, exit 0).
# Only the capabilities.apiVersions values list accepts bare group/version.
#
# The library dependency is served from a content-addressed package cache
# (tests/.dep-cache/<sha256-of-library-contents>/platform-*.tgz) so ~60 gate
# renders don't each pay a full `helm dependency update` (~2.8s -> ~0.1s).
# Any edit under platform-library/ changes the key and forces a repackage.
# RENDER_DEP_CACHE=0 bypasses the cache (plain helm dependency update).
# Safe to `rm -rf tests/.dep-cache` at any time.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="${1:?usage: render.sh <fixture> [helm args...]}"; shift || true
dir="$here/fixtures/$fixture"
lib="$here/../platform-library"
rm -rf "$dir/charts" "$dir/Chart.lock"
# Enforce the root values contract exactly like a generated consumer chart:
# Helm validates values.schema.json against the coalesced (post-import) values.
cp "$lib/values.schema.reference.json" "$dir/values.schema.json"
if [[ "${RENDER_DEP_CACHE:-1}" == "0" ]]; then
  helm dependency update "$dir" >/dev/null
else
  cache_root="$here/.dep-cache"
  key=$( (cd "$lib/.." && find platform-library -type f -print0 \
      | LC_ALL=C sort -z | xargs -0 shasum -a 256) | shasum -a 256 | awk '{print $1}')
  entry="$cache_root/$key"
  if ! ls "$entry"/platform-*.tgz >/dev/null 2>&1; then
    mkdir -p "$entry"
    tmp=$(mktemp -d "$cache_root/.tmp.XXXXXX")
    helm package "$lib" -d "$tmp" >/dev/null
    tgz=$(basename "$tmp"/platform-*.tgz)
    # Two-step rename: readers only ever see an absent or complete file.
    # A lost race overwrites with identical bytes (key == content hash).
    mv "$tmp/$tgz" "$entry/.$tgz.$$.partial"
    mv "$entry/.$tgz.$$.partial" "$entry/$tgz"
    rm -rf "$tmp"
  fi
  mkdir -p "$dir/charts"
  cp "$entry"/platform-*.tgz "$dir/charts/"
fi
helm template t "$dir" "$@"
```

Notes for the executor:
- `shasum` exists on both macOS (this repo's dev platform) and
  ubuntu runners; do not switch to `sha256sum`.
- Keep `LC_ALL=C sort -z` — locale-dependent sort order would make the key
  machine-dependent.
- The `(cd "$lib/.." && find platform-library ...)` form makes hashed paths
  relative, so the key doesn't depend on the checkout location.

**Verify**: `bash -n tests/render.sh` → exit 0;
`shellcheck -x tests/render.sh` → exit 0, no output.

### Step 2: Gitignore the cache

Add to `.gitignore`, next to the existing Helm block (after the
`tests/fixtures/*/values.schema.json` line):

```
tests/.dep-cache/
```

**Verify**: `tests/render.sh minimal >/dev/null && git status --short` →
shows only the two edited files (`tests/render.sh`, `.gitignore`); no
`.dep-cache` paths listed.

### Step 3: Prove byte-identical output old-path vs new-path

For every fixture, render through the legacy path and the cache path and
byte-compare:

```bash
for fx in minimal full stateful daemon; do
  RENDER_DEP_CACHE=0 tests/render.sh "$fx" > "/tmp/006-old-$fx.yaml"
  tests/render.sh "$fx" > "/tmp/006-new-$fx.yaml"
  diff "/tmp/006-old-$fx.yaml" "/tmp/006-new-$fx.yaml" && echo "$fx identical"
done
```

**Verify**: four `<fx> identical` lines, no diff output, exit 0.

### Step 4: Timing comparison

```bash
rm -rf tests/.dep-cache
time tests/render.sh full >/dev/null   # cold: builds cache once (~old cost)
time tests/render.sh full >/dev/null   # warm
```

**Verify**: warm run `real` < 0.5s (baseline old path ≈2.8s). Then time the
full gate once (Step 7 run doubles as this) and record the wall time in your
completion report next to the known ≈4 min baseline — expect roughly 1.5-2.5
min locally.

### Step 5: Prove staleness safety (cache-bust behavioral test)

The cache must repackage when `platform-library/` changes mid-iteration.
This is this plan's mutation-style proof (it adds no lint-gate assertions,
so invariant 5's gate-mutation rule does not apply; this behavioral RED/GREEN
is the equivalent):

```bash
rm -rf tests/.dep-cache
tests/render.sh minimal >/dev/null
ls tests/.dep-cache | wc -l                      # -> 1
printf '\n# cache-bust test\n' >> platform-library/values.yaml
tests/render.sh minimal >/dev/null
ls tests/.dep-cache | wc -l                      # -> 2 (new key, repackaged)
tests/render.sh minimal | grep -c 'cache-bust' || true   # comment is not rendered; the KEY change is the proof
git checkout -- platform-library/values.yaml
rm -rf tests/.dep-cache
```

Also prove the edit actually flows through to output when it is a real
change: repeat with a rendered field, e.g.
`--set` is not enough (bypasses cache by design — values are not cached);
instead temporarily change a default in `platform-library/values.yaml` that
appears in minimal's output? Keep it simple: the two-entry cache listing above
IS the staleness proof (key covers all file content). Skip the rendered-field
variant.

**Verify**: the `wc -l` outputs are `1` then `2`;
`git status --short` afterwards shows only `tests/render.sh` and `.gitignore`
modified.

### Step 6: UPDATE_GOLDEN idempotence and subset mode

```bash
UPDATE_GOLDEN=1 scripts/lint-library.sh
git diff --exit-code tests/golden/
FIXTURES=minimal scripts/lint-library.sh
```

**Verify**: first command ends `==> PASS`; the golden diff exits 0 (refresh
through the cached path reproduces the committed goldens byte-for-byte —
invariant 4); subset run ends `==> PASS (subset)`.

### Step 7: Full gate

**Verify**:
`REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh`
→ ends `==> PASS`, exit 0. Record the wall time. Then
`git diff --exit-code tests/golden/` → exit 0.

## Test plan

This plan adds no new gate sections; its verification is equivalence-based:

- Byte-identical renders old-path vs new-path, all four fixtures (Step 3).
- Golden idempotence under `UPDATE_GOLDEN` (Step 6) — the strongest
  contract check available (invariant 4).
- Cache staleness RED/GREEN via content-key change (Step 5).
- Full gate `==> PASS` with zero golden diffs (Step 7).
- No CHANGELOG entry: test tooling only, no consumer-visible change — state
  this in the completion report.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` ends `==> PASS`, exit 0
- [ ] `git diff --exit-code tests/golden/` exits 0
- [ ] Step 3 diff loop: zero byte differences across all four fixtures
- [ ] Warm `time tests/render.sh full >/dev/null` real < 0.5s
- [ ] `UPDATE_GOLDEN=1` run followed by `git diff --exit-code tests/golden/` exits 0
- [ ] `FIXTURES=minimal scripts/lint-library.sh` ends `==> PASS (subset)`
- [ ] `shellcheck -x scripts/*.sh tests/render.sh` exits 0
- [ ] `git status --short` shows only `tests/render.sh` and `.gitignore` modified
- [ ] Completion report records the measured full-gate wall time vs the ≈4 min baseline

## STOP conditions

Stop and report back (do not improvise) if:

- Step 3 shows ANY byte difference between old-path and new-path renders —
  the core equivalence assumption failed (e.g. `helm package` vs
  `helm dependency update` divergence).
- `helm template` errors about the dependency (e.g. "missing in charts/
  directory" or a version-constraint complaint) when consuming the cached
  tgz without `Chart.lock`.
- Any golden diff appears at any point.
- A `.helmignore` file exists in `platform-library/` (it did not at
  `583b401`) — the package-content-equivalence reasoning must be re-checked.
- The live `tests/render.sh` differs from the 18-line excerpt above.

## Maintenance notes

- The cache has no garbage collection by design — entries are tiny tgz files
  and `rm -rf tests/.dep-cache` is always safe. If entry count ever becomes
  a nuisance, add an age-based prune; do not add locking.
- If a fixture ever gains a SECOND dependency (beyond `platform`), the
  cache-consume branch must be revisited — it only populates
  `charts/platform-*.tgz`. A reviewer should scrutinize this assumption.
- If `platform-library/` ever gains a `.helmignore`, `helm package` still
  honors it (same as dependency update) — but re-run Step 3's equivalence
  loop to confirm.
- plans/007 adds kubeconform to guardrail renders; its added cost is
  affordable precisely because of this plan — note the interaction in
  review.
