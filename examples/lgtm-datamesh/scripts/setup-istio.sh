#!/usr/bin/env bash
#
# setup-istio.sh — install the Istio control plane into the capstone cluster and
# enable sidecar injection, in preparation for the order-service v1→v2 canary
# (r26, CAP-024).
#
# Like the other capstone platform installs (Postgres/Kafka operators,
# OpenMetadata), this is a run-once-per-cluster step, separate from the app
# releases. Idempotent.
#
# What it does:
#   1. Verifies istioctl is available (the §11 base setup installs it to
#      ~/.local/bin; this script does not re-download it).
#   2. Installs Istio with the `default` profile — control plane (istiod) plus
#      the istio-ingressgateway the canary routes through. (Not `demo`, which
#      adds addons we don't need; not `minimal`, which omits the ingress
#      gateway.)
#   3. Labels the `capstone` namespace for sidecar injection.
#
# SCOPE NOTE (CAP-024): r26 meshes order-service for the canary, not the whole
# mesh. Labeling the namespace enables injection, but only pods CREATED or
# RESTARTED afterward get a sidecar — so order-service (v1 recreated + v2 new)
# joins the mesh while the already-running operator-managed infra pods
# (Postgres, Kafka, Apicurio, OpenMetadata, OpenSearch) keep running WITHOUT
# sidecars. Do NOT restart those infra pods while the label is in place unless
# you first annotate them `sidecar.istio.io/inject: "false"` — operator-managed
# stateful pods need extra care (proxy lifecycle ordering) that's out of scope
# here. Mesh-wide mTLS and observability are a later iteration.
#
# Usage (from examples/lgtm-datamesh/):
#   ./scripts/setup-istio.sh
#
# Then enable the canary (selector immutability means v1 must be recreated once):
#   kubectl delete deployment order-service -n capstone --ignore-not-found
#   helm upgrade --install capstone ./charts/capstone -n capstone
#   ./demos/demo-canary-verify.sh

set -euo pipefail

NS="capstone"
ISTIO_PROFILE="default"

# ─── Pre-flight ──────────────────────────────────────────────────────────────

command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl not in PATH.\n' >&2; exit 1; }
if ! command -v istioctl >/dev/null 2>&1; then
    printf 'ERROR: istioctl not in PATH.\n' >&2
    printf 'Install it first (see §11): run the repo-root scripts/setup-istio.sh,\n' >&2
    printf 'which downloads istioctl to ~/.local/bin, then ensure ~/.local/bin is on PATH.\n' >&2
    exit 1
fi

# istioctl and ~/.local/share/istio-current are shared with other repos on the
# host, so confirm the client matches the version this repo pins
# (ISTIO_VERSION in the repo-root scripts/setup-istio.sh) instead of installing
# whatever control plane the binary on PATH happens to carry.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PINNED_ISTIO_VERSION="${ISTIO_VERSION:-$(sed -n 's/^ISTIO_VERSION="${ISTIO_VERSION:-\([^}]*\)}"$/\1/p' "${REPO_ROOT}/scripts/setup-istio.sh")}"
if [[ -z "$PINNED_ISTIO_VERSION" ]]; then
    printf 'ERROR: cannot read ISTIO_VERSION from %s/scripts/setup-istio.sh.\n' "$REPO_ROOT" >&2
    exit 1
fi
ISTIOCTL_VERSION="$(istioctl version --remote=false 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
if [[ "$ISTIOCTL_VERSION" != "$PINNED_ISTIO_VERSION" ]]; then
    printf 'ERROR: istioctl %s does not match the pinned Istio %s.\n' "${ISTIOCTL_VERSION:-unknown}" "$PINNED_ISTIO_VERSION" >&2
    printf 'Run the repo-root scripts/setup-istio.sh to install Istio %s (istioctl + ~/.local/share/istio-current).\n' "$PINNED_ISTIO_VERSION" >&2
    exit 1
fi
printf '==> istioctl %s matches the pinned version\n' "$ISTIOCTL_VERSION"

current_context="$(kubectl config current-context 2>/dev/null || echo "")"
if [[ "$current_context" != "capstone" ]]; then
    printf 'WARNING: current kubectl context is "%s", not "capstone".\n' "$current_context" >&2
    printf 'Switch with: kubectl config use-context capstone\n' >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

# ─── 1. Install Istio (control plane + ingress gateway) ──────────────────────

printf '==> Installing Istio (profile=%s) into the capstone cluster\n' "$ISTIO_PROFILE"
istioctl install --set profile="$ISTIO_PROFILE" -y

printf '==> Waiting for istiod and the ingress gateway to be ready\n'
kubectl rollout status deployment/istiod -n istio-system --timeout=5m
kubectl rollout status deployment/istio-ingressgateway -n istio-system --timeout=5m

# Pin the ingress gateway's HTTP port (80, index 1) to a fixed NodePort so the
# canary demos reach it on NodePort 30088, published on 127.0.0.1:8088 at profile
# creation (map: demos/lib/endpoints.sh).
printf '==> Pinning istio-ingressgateway HTTP nodePort to 30088\n'
kubectl patch svc istio-ingressgateway -n istio-system --type='json' \
    -p '[{"op":"replace","path":"/spec/ports/1/nodePort","value":30088}]' \
    2>/dev/null || true

# ─── 2. Enable injection on the capstone namespace ───────────────────────────

printf '==> Labeling namespace %s for sidecar injection\n' "$NS"
kubectl label namespace "$NS" istio-injection=enabled --overwrite

# ─── Done ────────────────────────────────────────────────────────────────────

printf '\n==> Istio is installed and %s is injection-enabled.\n\n' "$NS"
printf 'Enable the order-service canary (one-time delete: the v1 selector now\n'
printf 'includes version=v1, and selectors are immutable, so the old Deployment\n'
printf 'must be recreated):\n'
printf '  kubectl delete deployment order-service -n %s --ignore-not-found\n' "$NS"
printf '  helm upgrade --install capstone ./charts/capstone -n %s\n' "$NS"
printf '\nThen run the canary demo + verification:\n'
printf '  ./demos/demo-canary-verify.sh\n'
printf '\nReminder (CAP-024 scope): do not restart the operator-managed infra pods\n'
printf '(Postgres, Kafka, Apicurio, OpenMetadata) while injection is enabled.\n'
