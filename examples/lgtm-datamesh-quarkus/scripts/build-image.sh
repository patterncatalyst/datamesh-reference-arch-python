#!/usr/bin/env bash
#
# build-image.sh — build a Quarkus service's JVM image and push it to the
# capstone minikube profile's in-cluster registry.
#
# Unlike the Python tree (which builds everything inside the Containerfile),
# the Quarkus fast-jar is built on the host with Maven first, then copied into
# a small UBI OpenJDK runtime image (src/main/docker/Dockerfile.jvm). This keeps
# the image-build context tiny and fast.
#
# WHY THE REGISTRY (CAP-007): under the rootless-podman driver with containerd,
# neither `minikube image build` nor `minikube image load` reliably places an
# image where the kubelet can pull it. The robust answer is minikube's registry
# addon: build on the host, push to the registry, pull from it like any image.
#
# THE PORT ASYMMETRY (CAP-009):
#   - From the HOST (podman push):    127.0.0.1:<host-port>   (e.g. 41685)
#   - From INSIDE the cluster (pull): localhost:5000
# Same registry, two addresses. The chart's image.repository uses the in-cluster
# address (localhost:5000/<name>).
#
# Usage:
#   ./scripts/build-image.sh <service-dir> <image-name> [tag]
# Example:
#   ./scripts/build-image.sh services/order-service order-service v1

set -euo pipefail
export MINIKUBE_ROOTLESS=true

PROFILE="capstone"
CONTEXT="${1:?usage: build-image.sh <service-dir> <image-name> [tag]}"
NAME="${2:?usage: build-image.sh <service-dir> <image-name> [tag]}"
TAG="${3:-v1}"
DOCKERFILE="${CONTEXT}/src/main/docker/Dockerfile.jvm"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

[[ -d "$CONTEXT" ]]    || fail "service dir $CONTEXT not found"
[[ -f "$DOCKERFILE" ]] || fail "$DOCKERFILE not found"
command -v podman >/dev/null   || fail "podman not in PATH"
command -v minikube >/dev/null || fail "minikube not in PATH"

# ─── Build the Quarkus fast-jar on the host ──────────────────────────────────
# Uses the Maven wrapper at the example root. -am also builds any local
# dependency modules; -pl restricts the reactor to this service.
step "Building the Quarkus fast-jar for ${NAME} with Maven"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
( cd "$ROOT_DIR" && ./mvnw -q -pl "$CONTEXT" -am package -DskipTests )
[[ -f "${CONTEXT}/target/quarkus-app/quarkus-run.jar" ]] \
    || fail "expected ${CONTEXT}/target/quarkus-app/quarkus-run.jar — did the Maven build succeed?"

# ─── Discover the host-side registry port ────────────────────────────────────
step "Discovering the host registry port"
HOST_PORT=$(podman port "$PROFILE" 2>/dev/null | awk -F'[:]' '/5000\/tcp/ {print $NF; exit}')
[[ -n "$HOST_PORT" ]] || fail "could not find the host port mapped to registry :5000 — is the registry addon enabled? (minikube addons enable registry -p $PROFILE)"
HOST_REG="127.0.0.1:${HOST_PORT}"
printf '    host registry: %s  (cluster pulls from localhost:5000)\n' "$HOST_REG"

# ─── Build, tag, push the image ──────────────────────────────────────────────
step "Building ${NAME}:${TAG} image on the host with podman"
podman build -t "${NAME}:${TAG}" -f "$DOCKERFILE" "$CONTEXT"

step "Tagging for the host registry"
podman tag "${NAME}:${TAG}" "${HOST_REG}/${NAME}:${TAG}"

step "Pushing to ${HOST_REG} (plain HTTP registry; --tls-verify=false)"
podman push --tls-verify=false "${HOST_REG}/${NAME}:${TAG}"

step "Verifying ${NAME} is in the registry catalog"
if curl -fsS "http://${HOST_REG}/v2/_catalog" | grep -q "\"${NAME}\""; then
    printf '    ✓ %s present in registry\n' "$NAME"
else
    fail "${NAME} not found in registry catalog after push"
fi

printf '\n==> Done. Deployments should reference: localhost:5000/%s:%s\n' "$NAME" "$TAG"
