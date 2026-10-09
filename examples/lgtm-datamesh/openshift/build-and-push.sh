#!/usr/bin/env bash
#
# build-and-push.sh — build the 7 capstone Python service images and push
# them (plus mirrored copies of the postgres/kafka infra images) to an
# OpenShift cluster's integrated image registry.
#
# Mirrors the modernizing-enterprise-applications openshift/README.md build
# loop, adapted to this repo's services/<svc>/Containerfile layout
# (services/graphql-gateway, services/inventory-service, etc. — see
# scripts/build-image.sh for the minikube path (docker build + minikube image load)).
#
# Podman is used only for this OpenShift/CRC path.
#
# Prerequisites (not performed by this script):
#   - `oc login` to the target cluster, logged into project/namespace NS (see -n)
#   - the integrated registry's default route exposed:
#       oc patch configs.imageregistry.operator.openshift.io/cluster \
#         --type merge -p '{"spec":{"defaultRoute":true}}'
#   - `podman login` to that route, e.g.:
#       podman login -u "$(oc whoami)" -p "$(oc whoami -t)" --tls-verify=false "$REG"
#
# Usage:
#   ./openshift/build-and-push.sh [-r REGISTRY] [-n NAMESPACE] [-t TAG] [--mirror-infra]
#
# Examples:
#   # Build + push the 7 app images only (default):
#   ./openshift/build-and-push.sh -r default-route-openshift-image-registry.apps-crc.testing -n datamesh
#
#   # Also mirror postgres:18.6-alpine and apache/kafka:4.3.1 from Docker Hub into
#   # the same registry/namespace, for clusters where the CRC VM has no Docker
#   # Hub egress (see openshift/helm/datamesh/values.yaml postgres.image / kafka.image):
#   ./openshift/build-and-push.sh -r default-route-openshift-image-registry.apps-crc.testing -n datamesh --mirror-infra

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REG=""
NAMESPACE="datamesh"
TAG="v1"
MIRROR_INFRA="false"

usage() {
  printf 'Usage: %s -r REGISTRY_HOST [-n NAMESPACE] [-t TAG] [--mirror-infra]\n' "$0" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r) REG="$2"; shift 2 ;;
    -n) NAMESPACE="$2"; shift 2 ;;
    -t) TAG="$2"; shift 2 ;;
    --mirror-infra) MIRROR_INFRA="true"; shift ;;
    -h|--help) usage ;;
    *) printf 'ERROR: unknown argument %s\n' "$1" >&2; usage ;;
  esac
done

[[ -n "$REG" ]] || usage
command -v podman >/dev/null || { printf 'ERROR: podman not in PATH\n' >&2; exit 1; }

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

SERVICES=(
  graphql-gateway
  inventory-service
  notification-service
  order-service
  payment-service
  review-service
  shipping-service
)

step "Building + pushing ${#SERVICES[@]} service images to ${REG}/${NAMESPACE}"
for svc in "${SERVICES[@]}"; do
  CONTEXT="${REPO_ROOT}/services/${svc}"
  [[ -f "${CONTEXT}/Containerfile" ]] || fail "${CONTEXT}/Containerfile not found"

  step "Building ${svc}:${TAG}"
  podman build -t "${svc}:${TAG}" -f "${CONTEXT}/Containerfile" "${CONTEXT}"

  step "Tagging + pushing ${svc}:${TAG} -> ${REG}/${NAMESPACE}/${svc}:${TAG}"
  podman tag "${svc}:${TAG}" "${REG}/${NAMESPACE}/${svc}:${TAG}"
  podman push --tls-verify=false "${REG}/${NAMESPACE}/${svc}:${TAG}"
done

if [[ "$MIRROR_INFRA" == "true" ]]; then
  step "Mirroring infra images (Docker Hub egress fallback)"
  declare -A INFRA_IMAGES=(
    [postgres]="docker.io/library/postgres:18.6-alpine"
    [kafka]="docker.io/apache/kafka:4.3.1"
  )
  for name in "${!INFRA_IMAGES[@]}"; do
    upstream="${INFRA_IMAGES[$name]}"
    tag="${upstream##*:}"

    step "Pulling ${upstream}"
    podman pull "$upstream"

    step "Tagging + pushing ${upstream} -> ${REG}/${NAMESPACE}/${name}:${tag}"
    podman tag "$upstream" "${REG}/${NAMESPACE}/${name}:${tag}"
    podman push --tls-verify=false "${REG}/${NAMESPACE}/${name}:${tag}"
  done
  printf '\nMirrored images match the defaults in openshift/helm/datamesh/values.yaml\n'
  printf '(postgres.image, kafka.image). On a cluster WITH Docker Hub egress, skip\n'
  printf -- '--mirror-infra and uncomment the upstream refs in values.yaml instead.\n'
fi

printf '\n==> Done. helm upgrade --install will pull from %s/%s/<name>:%s\n' "$REG" "$NAMESPACE" "$TAG"
