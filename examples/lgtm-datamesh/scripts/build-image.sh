#!/usr/bin/env bash
#
# build-image.sh — build a service image with Docker and load it into the
# capstone minikube profile. There is no registry.
#
# WHY `minikube image load`: it works the same with a native Docker Engine
# (Linux) and a VM-based one (Docker Desktop is one example), because the
# image is streamed into the node's containerd rather than pulled over a
# network address. Loaded images persist across `minikube stop` / `start`.
# Charts reference capstone/<name>:<tag> with imagePullPolicy: Never, so the
# kubelet only ever uses what was loaded into the profile.
# (CAP-007, CAP-009 and CAP-010 are superseded by DRA-019.)
#
# Usage:
#   ./scripts/build-image.sh <context-dir> <image-name> [tag]
# Example:
#   ./scripts/build-image.sh services/order-service order-service v1
#
# Environment:
#   SKIP_BUILD=1             skip `docker build`; load the existing local image
#   BUILD_IMAGE_NO_RESTART=1 do not restart Deployments that use the image
#   MINIKUBE_PROFILE         minikube profile (default: capstone)
#   NS                       namespace of the Deployments to restart (default: capstone)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../demos/lib/images.sh
source "${SCRIPT_DIR}/../demos/lib/images.sh"

CONTEXT="${1:?usage: build-image.sh <context-dir> <image-name> [tag]}"
NAME="${2:?usage: build-image.sh <context-dir> <image-name> [tag]}"
TAG="${3:-v1}"
PROFILE="${MINIKUBE_PROFILE:-capstone}"
NS="${NS:-capstone}"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

for tool in docker minikube kubectl; do
    command -v "$tool" >/dev/null || fail "$tool not in PATH"
done
docker_engine_ok || exit 1
minikube status -p "$PROFILE" >/dev/null 2>&1 \
    || fail "minikube profile '$PROFILE' is not running (minikube start -p $PROFILE)"

[[ -d "$CONTEXT" ]] || fail "context dir $CONTEXT not found"
if [[ -f "$CONTEXT/Containerfile" ]]; then
    BUILD_FILE="$CONTEXT/Containerfile"
elif [[ -f "$CONTEXT/Dockerfile" ]]; then
    BUILD_FILE="$CONTEXT/Dockerfile"
else
    fail "neither $CONTEXT/Containerfile nor $CONTEXT/Dockerfile found"
fi

IMAGE="$(image_ref "$NAME" "$TAG")"

# ─── Build ───────────────────────────────────────────────────────────────────
if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
    step "SKIP_BUILD=1 — not building ${IMAGE}"
else
    step "Building ${IMAGE} with docker"
    docker build -f "$BUILD_FILE" -t "$IMAGE" "$CONTEXT"
fi

# ─── Load into the profile ───────────────────────────────────────────────────
step "Loading ${IMAGE} into minikube profile ${PROFILE}"
minikube -p "$PROFILE" image rm "$IMAGE" >/dev/null 2>&1 || true

tmp=""
trap '[[ -n "$tmp" ]] && rm -f "$tmp"' EXIT

if ! minikube -p "$PROFILE" image load "$IMAGE" || ! image_in_profile "$NAME" "$TAG"; then
    step "Direct load did not land the image; falling back to a tar archive"
    tmp="$(mktemp --suffix=.tar)"
    docker image save -o "$tmp" "$IMAGE"
    minikube -p "$PROFILE" image load "$tmp"
fi

image_in_profile "$NAME" "$TAG" \
    || fail "${IMAGE} not present in profile ${PROFILE} after load"
printf '    %s loaded in profile %s\n' "$IMAGE" "$PROFILE"

# ─── Restart Deployments that use the image ──────────────────────────────────
if [[ "${BUILD_IMAGE_NO_RESTART:-0}" != "1" ]]; then
    step "Restarting Deployments in ${NS} that reference ${IMAGE}"
    restarted=()
    while IFS=$'\t' read -r dep images; do
        [[ -n "$dep" ]] || continue
        for img in $images; do
            if [[ "$img" == "$IMAGE" || "$img" == "docker.io/$IMAGE" ]]; then
                kubectl rollout restart "deploy/${dep}" -n "$NS"
                restarted+=("$dep")
                break
            fi
        done
    done < <(kubectl get deploy -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[*].image} {.spec.template.spec.initContainers[*].image}{"\n"}{end}')
    if ((${#restarted[@]})); then
        printf '    restarted: %s\n' "${restarted[*]}"
    else
        printf '    no Deployments in %s reference %s\n' "$NS" "$IMAGE"
    fi
fi

printf '\n==> Done. Deployments reference %s (imagePullPolicy: Never)\n' "$IMAGE"
