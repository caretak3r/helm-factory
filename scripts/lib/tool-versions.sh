#!/usr/bin/env bash
# shellcheck disable=SC2034  # source-only library: vars are consumed by the
# scripts that `source` this file (scripts/check-tools.sh) and by
# .github/workflows/{ci,release}.yaml, not referenced directly here.
#
# THE single source of truth for the toolchain. ci.yaml and release.yaml used
# to carry duplicate install blocks — same URLs, same checksums, kept in sync
# by a comment — so a bump was three edits and a silent drift away from a red
# release. Both workflows now source this file; bumping a tool is one edit here.
#
# To bump a pinned tool: change the version AND its checksum in the same edit.
# Get the checksum from the upstream release page, never by downloading the
# artifact and hashing whatever arrives — that defeats the point of pinning.

# --- Pinned CI toolchain ------------------------------------------------------
# Checksums are for the linux-amd64 release artifacts the workflows download.
# Local installs (homebrew, pipx) are not checksummed: they carry their own
# signature chains, and pinning a macOS bottle hash here would rot weekly.

HELM_VERSION=4.2.0
HELM_SHA256_LINUX_AMD64=97dbeb971be4ac4b27e3839976d9564c0fb35c6f3b1da89dd1e292d236af4096
HELM_URL="https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz"

KUBECONFORM_VERSION=0.8.0
KUBECONFORM_SHA256_LINUX_AMD64=9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883
KUBECONFORM_URL="https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz"

CHECK_JSONSCHEMA_VERSION=0.37.4

# --- Local toolchain contract -------------------------------------------------
# One record per required tool:  name|floor|ci_pin|install hint
#
# The floor is the oldest version known to work, NOT the CI pin. They differ on
# purpose: blocking a contributor over a patch release nobody has shown to
# break anything is how a gate earns a reputation for crying wolf. The pin is
# reported next to the floor so drift stays visible without being fatal.
# An empty ci_pin means CI uses whatever the runner image ships.
REQUIRED_TOOLS=(
  "helm|4.0.0|${HELM_VERSION}|brew install helm   # or https://get.helm.sh — Helm 4 is required, a Helm 3 client cannot render this library"
  "kubeconform|0.7.0|${KUBECONFORM_VERSION}|brew install kubeconform   # or https://github.com/yannh/kubeconform/releases"
  "check-jsonschema|0.30.0|${CHECK_JSONSCHEMA_VERSION}|pipx install check-jsonschema==${CHECK_JSONSCHEMA_VERSION}   # or: brew install check-jsonschema"
  "shellcheck|0.8.0||brew install shellcheck   # or apt-get install shellcheck"
  "jq|1.6||brew install jq   # or apt-get install jq"
)
