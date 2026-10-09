#!/usr/bin/env bash
#
# setup-capstone-profile.sh — create (or replace) the capstone minikube
# profile sized for the full §17 stack.
#
# Toolchain: Docker Engine with `--driver=docker --container-runtime=containerd`
# (runc inside the node). Supported on Fedora and RHEL hosts (bare metal or VM). A VM-based engine
# (for example Docker Desktop) works if its VM is sized for the node.
#
# The capstone profile is intentionally separate from §3's `minikube` profile
# and §11's `istio` profile so the larger resource footprint doesn't disturb
# earlier sections' state. Idempotent: safe to re-run.
#
# Overrides (environment):
#   MINIKUBE_MEMORY   node memory           (default 24g)
#   MINIKUBE_CPUS     node CPUs             (default 16)
#   MINIKUBE_DISK     node disk size        (default 80g)
#   MINIKUBE_PROFILE  profile name          (default capstone)
#   KUBE_VERSION      Kubernetes version    (default v1.36.5, the newest minor
#                     every platform component supports)
# The docker driver ignores --disk-size: node data lives under the
# engine's data root (/var/lib/docker by default), so keep about 100 GB free there.
#
# Host access: every host-facing NodePort (see demos/lib/endpoints.sh) is
# published to 127.0.0.1 when the profile is created, via
# `minikube start --ports=127.0.0.1:<hostPort>:<nodePort>,...`. The published
# ports are fixed for the profile's life; to change them, recreate the profile
# with --replace. Nothing else needs to run on the host for access.
#
# Usage:
#   ./setup-capstone-profile.sh             # start (or do nothing if running)
#   ./setup-capstone-profile.sh --replace   # delete first, then start fresh
#                                           # (deletes and recreates the cluster:
#                                           # run ./scripts/bootstrap-capstone.sh again)

set -euo pipefail

MEMORY="${MINIKUBE_MEMORY:-24g}"
CPUS="${MINIKUBE_CPUS:-16}"
DISK="${MINIKUBE_DISK:-80g}"
RUNTIME="containerd"
DRIVER="docker"
KUBE_VERSION="${KUBE_VERSION:-v1.36.5}"   # pinned; minikube 1.39.0 supports it
PROFILE_NAME="${MINIKUBE_PROFILE:-capstone}"   # same default as EP_PROFILE in endpoints.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../demos/lib/endpoints.sh
source "${SCRIPT_DIR}/../demos/lib/endpoints.sh"
# shellcheck source=../demos/lib/images.sh
source "${SCRIPT_DIR}/../demos/lib/images.sh"
EP_PROFILE="$PROFILE_NAME"   # endpoints.sh helpers inspect the same container

REPLACE=0
if [[ "${1:-}" == "--replace" ]]; then
    REPLACE=1
fi

# ─── Pre-flight ──────────────────────────────────────────────────────────────

# 0. Supported hosts: Fedora and RHEL (bare metal or VM). The scripts use ss,
# GNU coreutils and Linux sysctls.
if [[ "$(uname -s)" != "Linux" ]]; then
    printf 'ERROR: the capstone scripts are supported on Fedora and RHEL hosts (bare metal or VM).\n' >&2
    exit 1
fi
host_id="$( . /etc/os-release 2>/dev/null && printf '%s %s' "${ID:-}" "${ID_LIKE:-}" )" || host_id=""
case " $host_id " in
    *" fedora "*|*" rhel "*) ;;
    *) printf 'WARNING: the capstone scripts are supported on Fedora and RHEL hosts (bare metal or VM); continuing anyway.\n' >&2 ;;
esac

# 1. Validate EXTRA_NODE_PORTS up front, before anything is deleted or started.
PORTS_ARG="$(node_ports_arg)" || { printf 'ERROR: fix EXTRA_NODE_PORTS; nothing was changed.\n' >&2; exit 1; }

# 2. Required tools.
if ! command -v minikube >/dev/null 2>&1; then
    printf 'ERROR: minikube not in PATH. See §2 for installation.\n' >&2
    exit 1
fi
if ! command -v kubectl >/dev/null 2>&1; then
    printf 'ERROR: kubectl not in PATH. See §2 for installation.\n' >&2
    exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
    printf 'ERROR: docker not in PATH. See §1 for installation.\n' >&2
    exit 1
fi

# 3. The engine must answer.
docker_engine_ok || exit 1

# 4. Rootless mode is not supported.  # forbidden-ok
if [[ "$(minikube config get rootless 2>/dev/null || true)" == "true" ]] || [[ -n "${MINIKUBE_ROOTLESS:-}" ]]; then  # forbidden-ok
    printf 'ERROR: minikube is configured for rootless mode, which this profile does not use.\n' >&2  # forbidden-ok
    printf 'Upgrading from an earlier (rootless podman) profile: delete the old profile first,\n' >&2  # forbidden-ok
    printf '  MINIKUBE_ROOTLESS=true minikube delete -p %s\n' "$PROFILE_NAME" >&2  # forbidden-ok
    printf 'then: minikube config unset rootless; unset MINIKUBE_ROOTLESS; and re-run this script.\n' >&2  # forbidden-ok
    exit 1
fi
if [[ "$(docker info --format '{{.SecurityOptions}}' 2>/dev/null || true)" == *rootless* ]]; then  # forbidden-ok
    printf 'ERROR: rootless Docker is not supported; use the system Docker Engine.\n' >&2  # forbidden-ok
    exit 1
fi

# 5. Engine capacity: the node cannot be larger than the engine (or its VM).
read -r engine_cpus engine_mem <<<"$(docker info --format '{{.NCPU}} {{.MemTotal}}' 2>/dev/null || true)"
mem_bytes=""
mem_lc="$(printf '%s' "$MEMORY" | tr '[:upper:]' '[:lower:]')"
if [[ "$mem_lc" =~ ^([0-9]+)(g|gb|gi)$ ]]; then
    mem_bytes=$(( 10#${BASH_REMATCH[1]} * 1024 * 1024 * 1024 ))
elif [[ "$mem_lc" =~ ^([0-9]+)(m|mb|mi)$ ]]; then
    mem_bytes=$(( 10#${BASH_REMATCH[1]} * 1024 * 1024 ))
elif [[ "$mem_lc" =~ ^[0-9]+$ ]]; then
    mem_bytes=$(( 10#$mem_lc * 1024 * 1024 ))   # plain number means MB
else
    printf 'ERROR: cannot parse MINIKUBE_MEMORY=%s (use for example 24g, 24GB, 24Gi, 24576m or 24576).\n' "$MEMORY" >&2
    exit 1
fi
capacity_bad=0
if [[ "${engine_cpus:-}" =~ ^[0-9]+$ && "$CPUS" =~ ^[0-9]+$ ]] && (( CPUS > engine_cpus )); then
    printf 'ERROR: MINIKUBE_CPUS=%s exceeds the %s CPUs the Docker engine reports.\n' "$CPUS" "$engine_cpus" >&2
    capacity_bad=1
fi
if [[ "${engine_mem:-}" =~ ^[0-9]+$ ]] && (( mem_bytes > engine_mem )); then
    printf 'ERROR: MINIKUBE_MEMORY=%s exceeds the %d MiB the Docker engine reports.\n' "$MEMORY" "$(( engine_mem / 1024 / 1024 ))" >&2
    capacity_bad=1
fi
if (( capacity_bad )); then
    printf 'Lower MINIKUBE_CPUS / MINIKUBE_MEMORY to fit. VM-based engines (for example\n' >&2
    printf 'Docker Desktop) need their VM sized larger than the node.\n' >&2
    exit 1
fi
printf '==> Docker engine capacity OK (%s CPUs, %s MiB; node wants %s CPUs, %s)\n' \
    "${engine_cpus:-?}" "$(( ${engine_mem:-0} / 1024 / 1024 ))" "$CPUS" "$MEMORY"

# 6. VM-based engines keep the node inside a VM: host sysctls do not apply.
VM_ENGINE=0
engine_os="$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || true)"
engine_kernel="$(docker info --format '{{.KernelVersion}}' 2>/dev/null || true)"
# Primary signal: the engine's kernel differs from the host kernel, so the node
# runs inside a VM. Secondary: the engine names a known VM-based product.
if [[ -n "$engine_kernel" && "$engine_kernel" != "$(uname -r)" ]]; then
    VM_ENGINE=1
elif [[ "$engine_os" =~ ([Dd]ocker[[:space:]]+[Dd]esktop|[Cc]olima|[Rr]ancher|[Bb]oot2[Dd]ocker) ]]; then
    VM_ENGINE=1
fi
if (( VM_ENGINE )); then
    printf 'NOTE: %s (kernel %s) runs in a VM (engine kernel differs from the host). The node runs inside its VM, so size the VM\n' "${engine_os:-the engine}" "${engine_kernel:-?}"
    printf '      for the node and expect inotify limits to be checked inside the node.\n'
fi

# 7. Host inotify limits (§1's tweak). Capstone runs many controllers; the
# Fedora default fs.inotify.max_user_instances=128 is insufficient. Only
# meaningful when the node shares the host kernel.
if (( VM_ENGINE == 0 )); then
    inotify_instances=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)
    if (( inotify_instances < 256 )); then
        printf 'ERROR: fs.inotify.max_user_instances is %d (need >= 256).\n' "$inotify_instances" >&2
        printf 'Apply the §1 kernel-limits tweak before continuing:\n' >&2
        printf '  sudo tee /etc/sysctl.d/99-kubernetes.conf <<EOF\n' >&2
        printf '  fs.inotify.max_user_instances = 512\n' >&2
        printf '  fs.inotify.max_user_watches = 524288\n' >&2
        printf '  EOF\n' >&2
        printf '  sudo sysctl -p /etc/sysctl.d/99-kubernetes.conf\n' >&2
        exit 1
    fi
fi

# 8. minikube version floor: 1.39.0 is the first release that supports the
# pinned Kubernetes v1.36.5.
mk_version="$(minikube version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo v0.0.0)"
if [[ "$(printf '%s\n' "v1.39.0" "$mk_version" | sort -V | head -1)" != "v1.39.0" ]]; then
    printf 'ERROR: minikube %s is too old (need >= 1.39.0 for Kubernetes %s).\n' "$mk_version" "$KUBE_VERSION" >&2
    printf 'Install a current minikube (e.g. to ~/.local/bin).\n' >&2
    exit 1
fi
printf '==> minikube version OK (%s)\n' "$mk_version"

# 9. An existing profile must already use the docker driver, containerd and
# the pinned Kubernetes version.
if (( ! REPLACE )); then
    prof_mismatch="$(minikube profile list -o json 2>/dev/null \
        | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for p in data.get("valid", []):
        if p.get("Name") == sys.argv[1]:
            cfg = p.get("Config") or {}
            drv = cfg.get("Driver", "")
            kc = cfg.get("KubernetesConfig") or {}
            rt = kc.get("ContainerRuntime", "")
            kv = kc.get("KubernetesVersion", "")
            if drv != "docker" or rt != "containerd" or kv != sys.argv[2]:
                print("%s/%s/%s" % (drv or "?", rt or "?", kv or "?"))
except Exception:
    pass
' "$PROFILE_NAME" "$KUBE_VERSION" 2>/dev/null || true)"
    if [[ -n "$prof_mismatch" ]]; then
        printf 'ERROR: profile %s was created with %s (want docker/containerd/%s); recreate it: ./scripts/setup-capstone-profile.sh --replace (or minikube delete -p %s)\n' \
            "$PROFILE_NAME" "$prof_mismatch" "$KUBE_VERSION" "$PROFILE_NAME" >&2
        exit 1
    fi
fi

# 10. Warn (don't fail) if other minikube profiles are running. Capstone wants
# the headroom.
running_profiles=$(minikube profile list -o json 2>/dev/null \
    | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for p in data.get("valid", []):
        if p["Name"] != sys.argv[1] and p.get("Status") == "Running":
            print(p["Name"])
except Exception:
    pass
' "$PROFILE_NAME" 2>/dev/null || true)

if [[ -n "$running_profiles" ]]; then
    printf 'WARNING: other minikube profiles are running and will compete for RAM:\n' >&2
    printf '%s\n' "$running_profiles" | sed 's/^/  - /' >&2
    printf 'Recommended: stop them with `minikube stop -p <name>` before continuing.\n' >&2
    if [[ -t 0 ]]; then
        printf 'Continue anyway? [y/N] ' >&2
        read -r answer
        [[ "$answer" =~ ^[Yy] ]] || exit 1
    else
        printf 'No terminal for a prompt; continuing anyway.\n' >&2
    fi
fi

# ─── Profile setup ───────────────────────────────────────────────────────────

if profile_container_exists && (( ! REPLACE )); then
    # Existing profile kept as-is: its published ports must already be right.
    check_published_ports || exit 1
    if profile_container_running; then
        printf '==> Profile %s already exists and is running. Pass --replace to recreate (deletes the cluster; re-run ./scripts/bootstrap-capstone.sh afterwards).\n' "$PROFILE_NAME"
    else
        printf '==> Profile %s exists but is stopped. Starting it.\n' "$PROFILE_NAME"
        # A stopped profile holds no listeners: every host port must be free.
        assert_host_ports_free "" || exit 1
        minikube start -p "$PROFILE_NAME"
        check_published_ports || exit 1
    fi
    ensure_node_forwarding
    printf '==> Switching kubectl context to %s\n' "$PROFILE_NAME"
    kubectl config use-context "$PROFILE_NAME"
    printf '==> Done. Current nodes:\n'
    kubectl get nodes
    exit 0
fi

# Create path (fresh or --replace). Pre-flight BEFORE any delete: every host
# port must be free, except ports this same profile currently publishes while
# it is RUNNING (a --replace frees those itself). A stopped profile holds no
# listeners, so every port must be free.
own_ports=""
if profile_container_running; then
    own_ports="$(published_ports | awk '{print $2}' | tr '\n' ' ')"
fi
assert_host_ports_free "$own_ports" || exit 1

if (( REPLACE )); then
    # Idempotent: also clears minikube's own record when the container is gone.
    printf '==> Deleting existing %s profile (--replace specified; run ./scripts/bootstrap-capstone.sh afterwards)\n' "$PROFILE_NAME"
    minikube delete -p "$PROFILE_NAME"
fi

printf '==> Starting %s profile (Kubernetes %s, %s RAM, %s CPUs, %s disk, %s driver, %s runtime)\n' \
    "$PROFILE_NAME" "$KUBE_VERSION" "$MEMORY" "$CPUS" "$DISK" "$DRIVER" "$RUNTIME"

printf '==> Publishing NodePorts on 127.0.0.1: %s\n' "$PORTS_ARG"

minikube start -p "$PROFILE_NAME" \
    --ports="$PORTS_ARG" \
    --memory="$MEMORY" \
    --cpus="$CPUS" \
    --disk-size="$DISK" \
    --driver="$DRIVER" \
    --container-runtime="$RUNTIME" \
    --kubernetes-version="$KUBE_VERSION" \
    --addons=metrics-server

check_published_ports || {
    printf 'ERROR: the node did not publish the required NodePorts on 127.0.0.1 (loopback is required).\n' >&2
    exit 1
}

printf '==> Checking node pod networking\n'
ensure_node_forwarding

# The node container's PID cap bounds TOTAL processes across all pods. The full
# meshed capstone runs ~2000+ tasks; a low cap makes the kubelet fail to fork
# (EAGAIN, "resource temporarily unavailable"). Warn only: the fix is an engine
# setting, applied before the node is created.
pids_limit="$(docker inspect -f '{{.HostConfig.PidsLimit}}' "$PROFILE_NAME" 2>/dev/null || true)"
case "$pids_limit" in
    ""|"<no value>"|0|-1) ;;
    *[!0-9-]*) ;;
    *)
        if (( pids_limit < 8192 )); then
            printf 'WARNING: node container PID limit is %s (want unlimited or >= 8192); the last pods may fail to fork.\n' "$pids_limit" >&2
            printf '  Set "default-pids-limit": -1 in /etc/docker/daemon.json, restart Docker, then run with --replace.\n' >&2
        fi
        ;;
esac

if (( VM_ENGINE )); then
    node_inotify="$(docker exec "$PROFILE_NAME" cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || true)"
    if [[ "$node_inotify" =~ ^[0-9]+$ ]] && (( node_inotify < 256 )); then
        printf 'WARNING: fs.inotify.max_user_instances is %s inside the node (want >= 256).\n' "$node_inotify" >&2
        printf '  Raise it in the engine VM (sysctl fs.inotify.max_user_instances=512), then restart the node.\n' >&2
    fi
fi

printf '==> Switching kubectl context to %s\n' "$PROFILE_NAME"
kubectl config use-context "$PROFILE_NAME"

printf '==> Creating capstone namespace\n'
kubectl create namespace capstone --dry-run=client -o yaml | kubectl apply -f -

printf '==> Verifying cluster health\n'
kubectl get nodes
kubectl get pods -n kube-system

printf '\n'
printf '==> Capstone profile is ready.\n'
printf '\n'
printf 'Next steps:\n'
printf '  1. Service images: ./scripts/build-image.sh services/<svc> <svc> v1\n'
printf '     (docker build + minikube image load); ./scripts/bootstrap-capstone.sh\n'
printf '     does this for you.\n'
printf '  2. To free the profile when done with §17:\n'
printf '       ./scripts/teardown.sh\n'
printf '  3. To switch back to a different profile:\n'
printf '       kubectl config use-context minikube  # (or istio, etc.)\n'
