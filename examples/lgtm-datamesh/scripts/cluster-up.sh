#!/usr/bin/env bash
#
# cluster-up.sh — bring the capstone cluster up cleanly, and heal the two
# failure modes that bit us hard during r29c:
#
#   1. A wedged control plane. After a long uptime with many redeploys, etcd can
#      crashloop in place on "bind: address already in use" (:2380), taking the
#      scheduler/controller-manager down with it. The cure is a node cycle
#      (minikube stop/start), which clears the stuck port and preserves etcd's
#      data dir. This script detects the wedge and cycles automatically.
#
#   2. Images missing after --replace or on a fresh profile. Images are loaded
#      into the node's containerd (no registry) and persist across
#      `minikube stop/start`, but a deleted/recreated profile starts empty and
#      pods land in ErrImageNeverPull. This script checks each service image in
#      the profile and rebuilds + loads ONLY the missing ones, then bounces
#      stuck pods.
#
# This is for an ALREADY-PROVISIONED cluster (operators + helm releases installed
# by the first-time setup-* sequence; they survive a node cycle). It does not
# re-install operators. For a fresh machine, run the setup-* scripts first
# (see §1 / the README), then use this for every subsequent bring-up.
#
# Idempotent. Safe to re-run. Run from examples/lgtm-datamesh/:
#   ./scripts/cluster-up.sh

set -uo pipefail
PROFILE="${MINIKUBE_PROFILE:-capstone}"
TAG="v1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"; cd "$ROOT"   # build-image.sh takes cwd-relative services/<svc>

step() { printf '\n==> %s\n' "$1"; }
ok()   { printf '    \xe2\x9c\x93 %s\n' "$1"; }
warn() { printf '    \xe2\x9a\xa0 %s\n' "$1"; }
fail() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }

command -v minikube >/dev/null || fail "minikube not in PATH"
command -v kubectl  >/dev/null || fail "kubectl not in PATH"
command -v docker   >/dev/null || fail "docker not in PATH"

# shellcheck source=../demos/lib/endpoints.sh
source "${SCRIPT_DIR}/../demos/lib/endpoints.sh"
# shellcheck source=../demos/lib/images.sh
source "${SCRIPT_DIR}/../demos/lib/images.sh"
docker_engine_ok || exit 1

# ─── 1. Ensure the profile is running ────────────────────────────────────────
step "Ensuring the '$PROFILE' profile is running"
EP_PROFILE="$PROFILE"
if minikube status -p "$PROFILE" >/dev/null 2>&1; then
    ok "profile already running"
else
    # A stopped profile keeps the ports it was created with: fail fast, before
    # spending minutes starting a node that can never be reached from the host.
    if profile_container_exists; then
        check_published_ports \
            || fail "stopped profile does not publish the required NodePorts on 127.0.0.1 — recreate it (deletes the cluster; re-run ./scripts/bootstrap-capstone.sh afterwards): ./scripts/setup-capstone-profile.sh --replace"
    fi
    # A stopped profile holds no listeners: every host port must be free, or
    # docker fails with a raw bind error.
    assert_host_ports_free "" || fail "host ports are not free (see above); stop other clusters and compose stacks, then re-run"
    printf '    starting (this also clears a stopped/wedged node)...\n'
    minikube start -p "$PROFILE" >/dev/null 2>&1 \
        || fail "minikube start failed — run ./scripts/setup-capstone-profile.sh for first-time provisioning"
    ok "profile started"
fi

# Host access is NodePorts published on 127.0.0.1 at profile creation; verify.
check_published_ports \
    || fail "profile does not publish the required NodePorts on 127.0.0.1 — recreate it with ./scripts/setup-capstone-profile.sh --replace (deletes the cluster; re-run ./scripts/bootstrap-capstone.sh afterwards)"
ok "NodePorts published on 127.0.0.1"
ensure_node_forwarding || fail "could not reset the node FORWARD policy (pod traffic would be dropped)"

# ─── 2. Control-plane health, with auto-cycle on a wedge ─────────────────────
cp_healthy() {
    kubectl get --raw='/readyz' >/dev/null 2>&1 || return 1
    # etcd specifically — the wedge we hit. Ready=true on the etcd static pod.
    kubectl get pods -n kube-system -l component=etcd \
        -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null \
        | grep -q true
}
wait_cp() {  # wait up to $1 seconds for the control plane to be healthy
    local deadline=$(( SECONDS + $1 ))
    while (( SECONDS < deadline )); do
        cp_healthy && return 0
        sleep 4
    done
    return 1
}

step "Checking control-plane health"
if wait_cp 60; then
    ok "control plane healthy (API server + etcd)"
else
    warn "control plane not healthy after 60s — likely a wedged etcd. Cycling the node..."
    minikube stop -p "$PROFILE"  >/dev/null 2>&1 || fail "minikube stop failed"
    assert_host_ports_free "" || fail "host ports are not free after the stop (see above); stop other clusters and compose stacks, then re-run"
    minikube start -p "$PROFILE" >/dev/null 2>&1 || fail "minikube start failed"
    if wait_cp 180; then
        ok "control plane recovered after node cycle"
    else
        fail "control plane still unhealthy after a cycle — inspect: kubectl get pods -n kube-system; kubectl logs -n kube-system etcd-$PROFILE --previous"
    fi
fi

# ─── 3. Rebuild + load ONLY images missing from the profile ──────────────────
step "Checking the profile for missing service images"
missing=()
for svc in "${CAPSTONE_SERVICES[@]}"; do
    image_in_profile "$svc" "$TAG" || missing+=("$svc")
done

if [[ ${#missing[@]} -eq 0 ]]; then
    ok "all ${#CAPSTONE_SERVICES[@]} images present (:${TAG}) — nothing to rebuild"
else
    warn "missing: ${missing[*]} — rebuilding (only these)"
    for svc in "${missing[@]}"; do
        printf '\n    --- rebuilding %s ---\n' "$svc"
        "${SCRIPT_DIR}/build-image.sh" "services/${svc}" "$svc" "$TAG" \
            || fail "build-image.sh failed for $svc"
    done
    ok "rebuilt ${#missing[@]} image(s)"
fi

# ─── 4. Bounce pods stuck on image pulls so they pick up now-loaded images ───
step "Restarting any pods stuck on image pulls"
stuck="$(kubectl get pods -n capstone 2>/dev/null \
    | grep -iE 'ImagePullBackOff|ErrImagePull|ErrImageNeverPull' | awk '{print $1}' || true)"
if [[ -n "$stuck" ]]; then
    printf '%s\n' "$stuck" | while read -r pod; do
        [[ -n "$pod" ]] && kubectl delete pod -n capstone "$pod" >/dev/null 2>&1 \
            && printf '    restarted %s\n' "$pod"
    done
    ok "bounced stuck pods (they will start from the loaded images)"
else
    ok "no pods stuck on image pulls"
fi

# ─── 5. Wait for workloads to settle ─────────────────────────────────────────
step "Waiting for workloads to settle (up to 4 min)"
deadline=$(( SECONDS + 240 ))
while (( SECONDS < deadline )); do
    bad_pods="$(kubectl get pods -A 2>/dev/null | tail -n +2 \
        | grep -ivE 'Running|Completed' || true)"
    [[ -z "$bad_pods" ]] && break
    sleep 6
done
if [[ -z "${bad_pods:-}" ]]; then
    ok "all pods Running/Completed"
else
    warn "some pods still settling after 4 min (the status report below has details)"
fi

# ─── 6. Endpoints ────────────────────────────────────────────────────────────
step "Endpoints"
"${SCRIPT_DIR}/show-endpoints.sh" || warn "some endpoints are unpublished or unreachable (see above; services may still be starting)"

# ─── 7. Final status report ──────────────────────────────────────────────────
step "Status report"
bash "${SCRIPT_DIR}/cluster-status.sh" || true

printf '\n==> Done. If status is green, demo/smoke away (e.g. ./demos/demo-trace-flow.sh).\n'
