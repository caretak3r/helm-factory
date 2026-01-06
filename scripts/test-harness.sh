#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

CHART_DIR=${CHART_DIR:-service-chart}
CONFIG_FILE=${CONFIG_FILE:-configuration.yaml}
RELEASE_NAME=${RELEASE_NAME:-}
NAMESPACE=${NAMESPACE:-}
OUTPUT_DIR=${OUTPUT_DIR:-artifacts}

if [[ ! -d "${CHART_DIR}" ]]; then
  echo "[error] chart directory '${CHART_DIR}' not found" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "[error] configuration file '${CONFIG_FILE}' not found" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"

if [[ -z "${RELEASE_NAME}" ]]; then
  RELEASE_NAME=$(awk -F ':' '/^serviceName:/ {gsub(/"|[[:space:]]/, "", $2); print $2; exit}' "${CONFIG_FILE}" ) || true
  if [[ -z "${RELEASE_NAME}" ]]; then
    RELEASE_NAME="aurora-gateway"
  fi
fi

if [[ -z "${NAMESPACE}" ]]; then
  NAMESPACE="${RELEASE_NAME}-ns"
fi

echo "[info] Using release='${RELEASE_NAME}' namespace='${NAMESPACE}' chart='${CHART_DIR}'"

echo "[step] Updating Helm dependencies"
helm dependency update "${CHART_DIR}"

echo "[step] Linting chart"
helm lint "${CHART_DIR}" -f "${CONFIG_FILE}"

echo "[step] Rendering manifests"
helm template "${RELEASE_NAME}" "${CHART_DIR}" -f "${CONFIG_FILE}" -n "${NAMESPACE}" --debug > "${OUTPUT_DIR}/rendered.yaml"

echo "[step] Performing dry-run install"
helm install "${RELEASE_NAME}" "${CHART_DIR}" -f "${CONFIG_FILE}" -n "${NAMESPACE}" --create-namespace --dry-run --debug > "${OUTPUT_DIR}/install.log"

echo "[done] Harness completed. Rendered manifests at ${OUTPUT_DIR}/rendered.yaml"
