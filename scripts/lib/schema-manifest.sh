#!/usr/bin/env bash
# Shared manifest for kubeconform schema vendoring — sourced by
# scripts/lint-library.sh (which validates against the vendored copies) and
# scripts/vendor-schemas.sh (which (re)fetches them). Keeping both in one file
# means bumping the supported Kubernetes window or adding a fixture Kind is a
# single edit followed by a re-run of the vendor script, rather than two
# scripts silently drifting apart.
#
# To bump the supported window: update KUBE_VERSIONS below (keep it in sync
# with platform-library/Chart.yaml's kubeVersion range), then run
# scripts/vendor-schemas.sh.
#
# To add a fixture that renders a new Kind: add its schema stem to
# NATIVE_SCHEMA_KINDS (core Kubernetes) or CRD_SCHEMA_PATHS (CRD-backed), then
# run scripts/vendor-schemas.sh.

# n-2 support window (kept in sync with platform-library/Chart.yaml kubeVersion).
KUBE_VERSIONS=(1.34 1.35 1.36)

# Core Kubernetes schemas, one stem per Kind actually rendered by
# tests/fixtures/{minimal,full,stateful,daemon} across the render matrix.
# Stem format matches yannh/kubernetes-json-schema's standalone-strict layout:
# {{ .ResourceKind }}{{ .KindSuffix }} (lowercase kind, plus a group-version
# suffix for non-core groups). Fetched once per KUBE_VERSIONS entry.
NATIVE_SCHEMA_KINDS=(
  serviceaccount-v1
  service-v1
  deployment-apps-v1
  priorityclass-scheduling-v1
  networkpolicy-networking-v1
  resourcequota-v1
  poddisruptionbudget-policy-v1
  configmap-v1
  clusterrole-rbac-v1
  role-rbac-v1
  rolebinding-rbac-v1
  horizontalpodautoscaler-autoscaling-v2
  cronjob-batch-v1
  ingress-networking-v1
  job-batch-v1
  secret-v1
  persistentvolumeclaim-v1
  statefulset-apps-v1
  daemonset-apps-v1
)

# CRD schemas from datreeio/CRDs-catalog, one per {{ .Group }}/{{
# .ResourceKind }}_{{ .ResourceAPIVersion }} path. Not versioned per
# Kubernetes release (CRDs are cluster-installed, not part of core k8s), so
# fetched once regardless of KUBE_VERSIONS. Covers every CRD-backed Kind the
# "full" fixture renders: cert-manager, Gateway API, Prometheus Operator, and
# Istio.
CRD_SCHEMA_PATHS=(
  security.istio.io/authorizationpolicy_v1beta1
  cert-manager.io/certificate_v1
  gateway.networking.k8s.io/httproute_v1
  security.istio.io/peerauthentication_v1beta1
  monitoring.coreos.com/podmonitor_v1
  monitoring.coreos.com/servicemonitor_v1
)
