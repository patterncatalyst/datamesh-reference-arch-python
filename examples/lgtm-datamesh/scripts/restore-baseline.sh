#!/usr/bin/env bash
#
# restore-baseline.sh — put the capstone workloads back in their bootstrap
# state: all six service releases installed and the two KEDA scalers applied.
#
# Why this exists: the smokes clean up the service releases they deployed when
# they PASS (CAP-008), so after any passing smoke the cluster can be missing
# shared services — and the next smoke that assumes them fails for reasons that
# have nothing to do with what it tests (e.g. demo-order 503s when
# demo-discovery's cleanup removed inventory-service). Run this between smokes
# (or between groups of a suite) to make the run order not matter.
#
# Scope: bootstrap tier 8 only (services + scalers). The platform tiers
# (Postgres, Kafka, Apicurio, observability, OpenMetadata) are checked and
# warned about, not installed — that's bootstrap-capstone.sh's job.
#
# Idempotent: helm upgrade --install + kubectl apply throughout.
#
# Run from examples/lgtm-datamesh/:  ./scripts/restore-baseline.sh

set -uo pipefail

NS="capstone"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"

SERVICES=(graphql-gateway inventory-service notification-service order-service payment-service shipping-service)
# KEDA-managed deployments settle at 0 replicas when idle — a rollout gate on
# them would hang or mislead, so they are excluded from the wait below.
KEDA_MANAGED=(graphql-gateway notification-service)

step() { printf '\n==> %s\n' "$1"; }
ok()   { printf '    \xe2\x9c\x93 %s\n' "$1"; }
warn() { printf '    \xe2\x9a\xa0 %s\n' "$1"; }
fail() { printf '\n\xe2\x9c\x97 %s\n' "$1" >&2; exit 1; }

is_keda_managed() {
    local svc="$1" k
    for k in "${KEDA_MANAGED[@]}"; do [[ "$k" == "$svc" ]] && return 0; done
    return 1
}

kubectl get ns "$NS" >/dev/null 2>&1 || fail "namespace $NS not found — run bootstrap-capstone.sh first"

# ── platform sanity (warn only) ───────────────────────────────────────────────
step "Platform check (warn-only — bootstrap owns these tiers)"
kubectl get pods -n "$NS" -l "cnpg.io/cluster=capstone-postgres,role=primary" --no-headers 2>/dev/null | grep -q Running \
    && ok "Postgres primary Running" || warn "Postgres primary not Running — re-run bootstrap-capstone.sh"
kubectl get kafka capstone-kafka -n "$NS" >/dev/null 2>&1 \
    && ok "Kafka CR present" || warn "Kafka CR missing — re-run bootstrap-capstone.sh"
kubectl get deploy apicurio -n "$NS" >/dev/null 2>&1 \
    && ok "Apicurio present" || warn "Apicurio missing — re-run bootstrap-capstone.sh (or demo-discovery.sh deploys it)"

# ── the six service releases ──────────────────────────────────────────────────
step "Installing/refreshing the six service releases"
for svc in "${SERVICES[@]}"; do
    helm upgrade --install "$svc" "charts/capstone/charts/$svc" -n "$NS" >/dev/null \
        || fail "$svc install failed"
    ok "$svc"
done

# ── the KEDA scalers (bootstrap applies these; baseline includes them) ────────
step "Applying the KEDA scalers"
kubectl apply -f keda/notification-scaledobject.yaml >/dev/null || fail "notification ScaledObject apply failed"
kubectl apply -f keda/gateway-httpscaledobject.yaml >/dev/null || fail "gateway HTTPScaledObject apply failed"
ok "notification-service ScaledObject + graphql-gateway HTTPScaledObject"

# ── rollout gates for the always-on services ──────────────────────────────────
step "Waiting for the always-on services to be Ready"
for svc in "${SERVICES[@]}"; do
    if is_keda_managed "$svc"; then
        printf '    - %s: KEDA-managed, may settle at 0 replicas (skipped)\n' "$svc"
        continue
    fi
    kubectl rollout status "deploy/$svc" -n "$NS" --timeout=240s >/dev/null \
        || fail "$svc did not become Ready"
    ok "$svc Ready"
done

step "Baseline restored — smokes can run in any order from here."
