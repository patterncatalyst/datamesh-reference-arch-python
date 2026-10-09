#!/usr/bin/env bash
#
# images.sh — image pipeline helpers for the capstone cluster.
#
# There is no registry. Images are built on the host with `docker build`,
# loaded into the node's containerd with `minikube image load`, and named
# capstone/<svc>:v1. Charts reference them with `imagePullPolicy: Never`, so
# the kubelet only ever uses what was loaded into the profile.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/images.sh"
#   docker_engine_ok || exit 1
#   image_in_profile order-service || echo "not loaded"
#
# Safe to `source` under `set -euo pipefail`: only definitions, no side effects.

IMAGE_PREFIX="capstone"
IMAGE_TAG_DEFAULT="v1"
IMAGE_PROFILE="${MINIKUBE_PROFILE:-capstone}"

CAPSTONE_SERVICES=(graphql-gateway inventory-service notification-service
                   order-service payment-service shipping-service)

# image_ref <svc> [tag] → capstone/<svc>:<tag>
image_ref() { printf '%s/%s:%s\n' "$IMAGE_PREFIX" "$1" "${2:-$IMAGE_TAG_DEFAULT}"; }

# image_in_profile <svc> [tag] → 0 if the image is loaded in the profile's containerd
image_in_profile() {
    local svc="$1" tag="${2:-$IMAGE_TAG_DEFAULT}" re
    re="(docker\\.io/)?$(_ere_escape "$IMAGE_PREFIX")/$(_ere_escape "$svc"):$(_ere_escape "$tag")"
    minikube -p "$IMAGE_PROFILE" image ls 2>/dev/null | grep -qxE "$re"
}

# _ere_escape <text> → text with ERE metacharacters backslash-escaped
_ere_escape() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|/]/\\&/g'; }

# docker_engine_ok → 0 if the Docker Engine answers; else a hint on stderr, 1
docker_engine_ok() {
    docker info >/dev/null 2>&1 && return 0
    local ctx
    ctx="$(docker context show 2>/dev/null || true)"
    printf 'Docker Engine is not reachable (context: %s). Run: sudo systemctl start docker; make sure your user is in the docker group (sudo usermod -aG docker $USER, then log in again); docker context use default.\n' "${ctx:-unknown}" >&2
    return 1
}

# chart_repo_ok <values-file> <svc> → 0 if image.repository is capstone/<svc>
# and pullPolicy is Never; else prints what was found on stderr and returns 1.
chart_repo_ok() {
    local file="$1" svc="$2" repo pol
    if [[ ! -r "$file" ]]; then
        printf 'chart_repo_ok: cannot read %s\n' "$file" >&2
        return 1
    fi
    read -r repo pol < <(awk '
        /^image:[[:space:]]*$/ { inimg = 1; next }
        inimg && /^[^[:space:]#]/ { inimg = 0 }
        inimg && $1 == "repository:" { r = $2 }
        inimg && $1 == "pullPolicy:" { p = $2 }
        END { print (r == "" ? "-" : r), (p == "" ? "-" : p) }' "$file")
    repo="${repo//\"/}"; pol="${pol//\"/}"
    [[ "$repo" == "${IMAGE_PREFIX}/${svc}" && "$pol" == "Never" ]] && return 0
    printf '%s: image.repository=%s pullPolicy=%s (want %s/%s and Never)\n' \
        "$file" "$repo" "$pol" "$IMAGE_PREFIX" "$svc" >&2
    return 1
}
