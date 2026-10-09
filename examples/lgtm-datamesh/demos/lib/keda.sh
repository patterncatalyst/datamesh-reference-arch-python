#!/usr/bin/env bash
#
# keda.sh — hold a KEDA-scaled workload at a fixed replica count for the
# duration of a demo.
#
# KEDA scales the Kafka consumer (notification-service) to zero when there is
# no lag, and can scale it back to zero between a demo's steps. A demo that
# talks to it over its published NodePort, or restarts it, holds its
# ScaledObject at a fixed count with KEDA's paused-replicas annotation and
# releases the hold on exit, so KEDA resumes control afterwards.
#
#   source "${ROOT}/demos/lib/keda.sh"
#   keda_hold_replicas notification-service-scaler 1 notification-service \
#       || fail "notification-service did not come up under the KEDA hold"
#
# Uses $NS for the namespace. A missing ScaledObject is not an error: without
# one nothing scales the Deployment, so there is nothing to hold.
#
# Safe to `source` under `set -euo pipefail`: only definitions, no side effects.

# keda_hold_replicas <scaledobject> <replicas> <deployment>
# Annotates the ScaledObject, installs an EXIT trap that releases it, and waits
# (up to ~120 s) for the Deployment to report <replicas> ready replicas.
# Replaces any EXIT trap the caller set; callers that need their own EXIT
# handler call keda_release from it instead.
keda_hold_replicas() {
    local so="$1" n="$2" deploy="$3" i
    kubectl -n "$NS" get scaledobject "$so" >/dev/null 2>&1 || return 0
    kubectl -n "$NS" annotate scaledobject "$so" \
        "autoscaling.keda.sh/paused-replicas=$n" --overwrite >/dev/null
    KEDA_HELD_SCALEDOBJECT="$so"
    trap 'keda_release "$KEDA_HELD_SCALEDOBJECT"' EXIT
    for i in $(seq 1 60); do
        [[ "$(kubectl -n "$NS" get deploy "$deploy" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" == "$n" ]] && return 0
        sleep 2
    done
    printf '  %s did not reach %s ready replica(s) under the KEDA hold\n' "$deploy" "$n" >&2
    return 1
}

# keda_release <scaledobject> — remove the hold; KEDA resumes scaling.
keda_release() {
    [[ -n "${1:-}" ]] || return 0
    kubectl -n "$NS" annotate scaledobject "$1" autoscaling.keda.sh/paused-replicas- >/dev/null 2>&1 || true
}
