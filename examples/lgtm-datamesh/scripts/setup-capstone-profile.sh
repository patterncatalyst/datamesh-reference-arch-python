#!/usr/bin/env bash
#
# setup-capstone-profile.sh — create (or replace) the capstone minikube
# profile sized for the full §17 stack.
#
# The capstone profile is intentionally separate from §3's `minikube`
# profile and §11's `istio` profile so the larger resource footprint
# doesn't disturb earlier sections' state. Idempotent: safe to re-run.
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
export MINIKUBE_ROOTLESS=true   # CAP-010: required so minikube uses rootless podman
                                # for host ops (status/registry), not sudo podman

PROFILE_NAME="${MINIKUBE_PROFILE:-capstone}"   # same default as EP_PROFILE in endpoints.sh
MEMORY="24g"
CPUS="16"
DISK="80g"
RUNTIME="containerd"
DRIVER="podman"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../demos/lib/endpoints.sh
source "${SCRIPT_DIR}/../demos/lib/endpoints.sh"
EP_PROFILE="$PROFILE_NAME"   # endpoints.sh helpers inspect the same container

REPLACE=0
if [[ "${1:-}" == "--replace" ]]; then
    REPLACE=1
fi

# ─── Pre-flight ──────────────────────────────────────────────────────────────

if ! command -v minikube >/dev/null 2>&1; then
    printf 'ERROR: minikube not in PATH. See §2 for installation.\n' >&2
    exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
    printf 'ERROR: podman not in PATH. See §1 for installation.\n' >&2
    exit 1
fi

# Confirm the legacy iptables NAT kernel modules are loaded on the HOST.
# Fedora is nftables-only out of the box; inside the rootless node the CNI
# portmap plugin needs the legacy ip_tables/iptable_nat modules and cannot
# modprobe them itself ("Operation not permitted") — without them, hostPort
# pods (the registry proxy first) fail sandbox creation forever. Loaded
# loadable modules and builtins both appear under /sys/module/.
missing_mods=()
for m in ip_tables iptable_nat ip6_tables; do
    [[ -d "/sys/module/${m}" ]] || missing_mods+=("$m")
done
if (( ${#missing_mods[@]} > 0 )); then
    printf 'ERROR: kernel module(s) not loaded: %s\n' "${missing_mods[*]}" >&2
    printf 'The CNI portmap plugin inside the rootless node needs them and cannot\n' >&2
    printf 'load them itself. Load now and persist across reboots:\n' >&2
    printf '  sudo sh -c '\''printf "ip_tables\\niptable_nat\\nip6_tables\\n" > /etc/modules-load.d/99-kubernetes-iptables.conf'\''\n' >&2
    printf '  sudo systemctl restart systemd-modules-load\n' >&2
    exit 1
fi
printf '==> iptables kernel modules OK (ip_tables iptable_nat ip6_tables)\n'

# Confirm minikube is new enough. 1.35's registry addon pins a
# kube-registry-proxy image digest that no longer exists on gcr.io, so
# `minikube addons enable registry` can never succeed on it.
mk_version="$(minikube version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo v0.0.0)"
if [[ "$(printf '%s\n' "v1.36.0" "$mk_version" | sort -V | head -1)" != "v1.36.0" ]]; then
    printf 'ERROR: minikube %s is too old (need >= 1.36).\n' "$mk_version" >&2
    printf '1.35'\''s registry addon pins a dead kube-registry-proxy image digest and\n' >&2
    printf 'cannot come up. Install a current minikube (e.g. to ~/.local/bin).\n' >&2
    exit 1
fi
printf '==> minikube version OK (%s)\n' "$mk_version"

# Confirm inotify limits (§1's tweak). Capstone runs many controllers; the
# Fedora default fs.inotify.max_user_instances=128 is insufficient.
inotify_instances=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)
if (( inotify_instances < 256 )); then
    printf 'ERROR: fs.inotify.max_user_instances is %d (need ≥ 256).\n' "$inotify_instances" >&2
    printf 'Apply the §1 kernel-limits tweak before continuing:\n' >&2
    printf '  sudo tee /etc/sysctl.d/99-kubernetes.conf <<EOF\n' >&2
    printf '  fs.inotify.max_user_instances = 512\n' >&2
    printf '  fs.inotify.max_user_watches = 524288\n' >&2
    printf '  EOF\n' >&2
    printf '  sudo sysctl -p /etc/sysctl.d/99-kubernetes.conf\n' >&2
    exit 1
fi

# Confirm podman's default pids_limit is raised (CAP-040). The podman driver
# creates the minikube node as a container whose ROOT cgroup pids.max is
# podman's default (--pids-limit=2048) — a cap on TOTAL processes across ALL
# pods on the node. The full meshed capstone (CNPG, Kafka, KEDA, OpenMetadata +
# OpenSearch JVMs, observability, six services, and six Envoy sidecars under
# namespace-wide injection) runs ~2000+ tasks and saturates 2048 — so the
# kubelet can't fork the last pod's init (order-service: EAGAIN, runc exit 128,
# "fork/exec ...: resource temporarily unavailable", CrashLoopBackOff/StartError).
# The node-container cgroup pids.max is NOT writable live on a rootless node
# (Operation not permitted), so the only durable fix is at CREATION time: raise
# podman's default via containers.conf before the node is built.
# Parse the effective podman default pids_limit from containers.conf (user first,
# then system). The trailing `|| true` is ESSENTIAL: under `set -e` + `pipefail`,
# a `var=$(...)` assignment aborts the whole script if the inner pipeline returns
# non-zero — and this grep chain legitimately returns non-zero when a file is
# absent or contains no match. That abort (not the arithmetic) was the real bug.
pids_limit=$(
    grep -hsE '^[[:space:]]*pids_limit[[:space:]]*=' \
        "${HOME}/.config/containers/containers.conf" \
        /etc/containers/containers.conf 2>/dev/null \
        | tail -1 | grep -oE '[0-9]+' | tail -1 || true
)
pids_limit="${pids_limit:-2048}"
pids_too_low=0
# Use `(( ))` only as an if-condition (set-e-exempt position) and only on a
# verified-numeric value.
if [[ "$pids_limit" != "0" ]] && [[ "$pids_limit" =~ ^[0-9]+$ ]]; then
    if (( pids_limit < 8192 )); then pids_too_low=1; fi
fi
if [[ "$pids_too_low" == "1" ]]; then
    printf 'ERROR: podman default pids_limit is %s (need 0=unlimited or ≥ 8192).\n' "$pids_limit" >&2
    printf 'The capstone node would be capped at %s total PIDs and the last pod\n' "$pids_limit" >&2
    printf 'would fail to fork (EAGAIN / runc exit 128). Raise it before creating the node:\n' >&2
    printf '  mkdir -p ~/.config/containers\n' >&2
    printf '  printf '\''[containers]\\npids_limit = 0\\n'\'' >> ~/.config/containers/containers.conf\n' >&2
    printf 'Then re-run this script (a node recreate is needed to pick it up).\n' >&2
    exit 1
fi
if [[ "$pids_limit" == "0" ]]; then
    pids_display="unlimited"
else
    pids_display="$pids_limit"
fi
printf '==> podman pids_limit OK (%s) — node will have PID headroom (CAP-040)\n' "$pids_display"

# Warn (don't fail) if other minikube profiles are running. Capstone wants
# the headroom.
running_profiles=$(minikube profile list -o json 2>/dev/null \
    | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for p in data.get("valid", []):
        if p["Name"] != "'"$PROFILE_NAME"'" and p.get("Status") == "Running":
            print(p["Name"])
except Exception:
    pass
' 2>/dev/null || true)

if [[ -n "$running_profiles" ]]; then
    printf 'WARNING: other minikube profiles are running and will compete for RAM:\n' >&2
    printf '%s\n' "$running_profiles" | sed 's/^/  - /' >&2
    printf 'Recommended: stop them with `minikube stop -p <name>` before continuing.\n' >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

# ─── Profile setup ───────────────────────────────────────────────────────────

if podman container exists "$PROFILE_NAME" 2>/dev/null && (( ! REPLACE )); then
    # Existing profile kept as-is: its published ports must already be right.
    check_published_ports || exit 1
    if minikube status -p "$PROFILE_NAME" >/dev/null 2>&1; then
        printf '==> Profile %s already exists and is running. Pass --replace to recreate.\n' "$PROFILE_NAME"
    else
        printf '==> Profile %s exists but is stopped. Starting it.\n' "$PROFILE_NAME"
        minikube start -p "$PROFILE_NAME"
        check_published_ports || exit 1
    fi
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
if ! command -v ss >/dev/null 2>&1; then
    printf 'ERROR: ss not in PATH (iproute2); needed to check host ports are free.\n' >&2
    exit 1
fi
own_ports=" "
if [[ "$(podman container inspect -f '{{.State.Running}}' "$PROFILE_NAME" 2>/dev/null || true)" == "true" ]]; then
    own_ports=" $(published_ports | awk '{print $2}' | tr '\n' ' ') "
fi
busy=0
IFS=',' read -ra port_specs <<<"$(node_ports_arg)"
for spec in "${port_specs[@]}"; do
    hp="$(cut -d: -f2 <<<"$spec")"
    [[ "$own_ports" == *" $hp "* ]] && continue
    if [[ -n "$(ss -Htln "sport = :$hp" 2>/dev/null)" ]]; then
        printf 'ERROR: host port %s is already in use: something else is listening; this workshop runs in isolation — stop other clusters/services.\n' "$hp" >&2
        busy=1
    fi
done
if (( busy )); then exit 1; fi

if (( REPLACE )); then
    # Idempotent: also clears minikube's own record when the container is gone.
    printf '==> Deleting existing %s profile (--replace specified; run ./scripts/bootstrap-capstone.sh afterwards)\n' "$PROFILE_NAME"
    minikube delete -p "$PROFILE_NAME"
fi

printf '==> Starting %s profile (%s RAM, %s CPUs, %s disk, %s runtime)\n' \
    "$PROFILE_NAME" "$MEMORY" "$CPUS" "$DISK" "$RUNTIME"

printf '==> Publishing NodePorts on 127.0.0.1: %s\n' "$(node_ports_arg)"

minikube start -p "$PROFILE_NAME" \
    --ports="$(node_ports_arg)" \
    --memory="$MEMORY" \
    --cpus="$CPUS" \
    --disk-size="$DISK" \
    --container-runtime="$RUNTIME" \
    --driver="$DRIVER" \
    --rootless=true \
    --addons=metrics-server

check_published_ports || {
    printf 'ERROR: the node did not publish the required NodePorts on 127.0.0.1 (loopback is required).\n' >&2
    exit 1
}

printf '==> Switching kubectl context to %s\n' "$PROFILE_NAME"
kubectl config use-context "$PROFILE_NAME"

printf '==> Creating capstone namespace\n'
kubectl create namespace capstone --dry-run=client -o yaml | kubectl apply -f -

printf '==> Verifying cluster health\n'
kubectl get nodes
kubectl get pods -n kube-system

printf '==> Persisting rootless mode in minikube config (CAP-010)\n'
minikube config set rootless true >/dev/null 2>&1 || true

printf '==> Enabling the in-cluster registry addon (CAP-009)\n'
minikube addons enable registry -p "$PROFILE_NAME"
reg_port="$(registry_host_port)"
printf '    Host pushes to 127.0.0.1:%s\n' "${reg_port:-<port>}"
printf '    Cluster pulls from localhost:5000 — build-image.sh handles both.\n'

printf '\n'
printf '==> Capstone profile is ready.\n'
printf '\n'
printf 'Next steps (per r20):\n'
printf '  1. The platform stack (Strimzi, KEDA, Istio, Apicurio, OpenMetadata,\n'
printf '     observability, Prefect, Postgres) installs in iterations r21-r27.\n'
printf '  2. To free the profile when done with §17:\n'
printf '       ./scripts/teardown.sh\n'
printf '  3. To switch back to a different profile:\n'
printf '       kubectl config use-context minikube  # (or istio, etc.)\n'
