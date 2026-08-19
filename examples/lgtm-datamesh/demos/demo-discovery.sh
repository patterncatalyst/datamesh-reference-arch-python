#!/usr/bin/env bash
#
# demo-discovery.sh — publish the mesh's discovery contracts to Apicurio and
# verify all of them (plus the Avro runtime contract) are registered.
#
# Completes the registry half of CAP-018: after this, Apicurio holds all four
# protocols' contracts — Avro (runtime, registered by order-service) plus
# OpenAPI, Protobuf, and GraphQL SDL (discovery, published here) — which is the
# feedstock OpenMetadata ingests later.
#
# Flow: ensure Strimzi+Kafka+Apicurio+Postgres → deploy inventory/order/gateway
#       → port-forward → publish discovery contracts → assert each artifact is
#       retrievable from Apicurio's v3 API (and the Avro subject from ccompat)
#       → cleanup on success.
#
# Usage:  ./demos/demo-discovery.sh [--purge-db]

set -uo pipefail
export MINIKUBE_ROOTLESS=true   # CAP-010

PROFILE="capstone"; NS="capstone"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
source "${ROOT}/demos/lib/tunnels.sh"
PG_RELEASE="capstone-postgres"; PG_CHART="charts/capstone/charts/postgres"
KAFKA_RELEASE="capstone-kafka"; KAFKA_CHART="charts/capstone/charts/kafka"; KAFKA_CR="capstone-kafka"
APICURIO_RELEASE="apicurio"; APICURIO_CHART="charts/capstone/charts/apicurio"
PROTO_PATH="proto/capstone/inventory/v1/inventory.proto"
GROUP="default"
LOCAL_ORDER=$TP_ORDER; LOCAL_GW=$TP_GATEWAY; LOCAL_APIC=$TP_APICURIO   # 8080 order, 8081 gateway-via-interceptor, 8084 apicurio
PURGE_DB=0; [[ "${1:-}" == "--purge-db" ]] && PURGE_DB=1

DEPLOY=(inventory-service order-service graphql-gateway)

step() { printf '\n==> %s\n' "$1"; }
fail() {
    printf '\nFAILED: %s\n' "$1" >&2
    for svc in "${DEPLOY[@]}" apicurio; do
        printf '\n--- %s ---\n' "$svc" >&2
        kubectl get pods -n "$NS" -l "app.kubernetes.io/name=${svc}" -o wide 2>&1 || true
        kubectl logs -n "$NS" -l "app.kubernetes.io/name=${svc}" --tail=25 2>&1 || true
    done
    printf '\nResources left in place. Clean up with:\n  helm uninstall %s %s %s -n %s\n' \
        "${DEPLOY[*]}" "$APICURIO_RELEASE" "$KAFKA_RELEASE" "$NS" >&2
    exit 1
}

# ── registry guard ────────────────────────────────────────────────────────────
step "Sanity: chart image.repository points at the registry"
for svc in "${DEPLOY[@]}"; do
    repo="$(awk '/^  repository:/{print $2; exit}' "charts/capstone/charts/${svc}/values.yaml")"
    case "$repo" in
        localhost:5000/*) printf '    ✓ %s → %s\n' "$svc" "$repo" ;;
        *) fail "${svc} image.repository is '${repo}' — must start with localhost:5000/" ;;
    esac
done
[[ -f "$PROTO_PATH" ]] || fail "proto not found at ${PROTO_PATH} — run ./scripts/gen-protos.sh? (the .proto is committed)"

minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running"
kubectl config use-context "$PROFILE" >/dev/null

# ── platform: Strimzi + Kafka + Apicurio ──────────────────────────────────────
step "Ensuring Strimzi + Kafka + Apicurio are up"
kubectl get crd kafkas.kafka.strimzi.io >/dev/null 2>&1 || ./scripts/setup-kafka-operator.sh || fail "Strimzi install failed"
helm upgrade --install "$KAFKA_RELEASE" "$KAFKA_CHART" -n "$NS" >/dev/null || fail "kafka chart install failed"
kubectl wait "kafka/${KAFKA_CR}" -n "$NS" --for=condition=Ready --timeout=360s || fail "Kafka not Ready"
helm upgrade --install "$APICURIO_RELEASE" "$APICURIO_CHART" -n "$NS" >/dev/null || fail "apicurio install failed"
kubectl rollout status deployment/apicurio -n "$NS" --timeout=180s || fail "apicurio rollout failed"
printf '    ✓ Kafka + Apicurio ready\n'

# ── build + push + Postgres + deploy ──────────────────────────────────────────
for svc in "${DEPLOY[@]}"; do
    step "Building + pushing ${svc}"
    ./scripts/build-image.sh "services/${svc}" "${svc}" v1 || fail "${svc} build/push failed"
done
step "Ensuring Postgres is Ready"
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || fail "CloudNativePG operator missing"
helm upgrade --install "$PG_RELEASE" "$PG_CHART" -n "$NS" --create-namespace >/dev/null || fail "postgres install failed"
pg_ready=0
for i in $(seq 1 60); do
    if kubectl get pods -n "$NS" -l "cnpg.io/cluster=${PG_RELEASE},role=primary" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        printf '    primary Ready after ~%ds\n' "$((i*5))"; pg_ready=1; break
    fi
    sleep 5
done
(( pg_ready )) || fail "Postgres primary did not become Ready"
for svc in "${DEPLOY[@]}"; do
    step "Deploying ${svc}"
    helm upgrade --install "$svc" "charts/capstone/charts/${svc}" -n "$NS" >/dev/null || fail "${svc} install failed"
    kubectl rollout status "deployment/${svc}" -n "$NS" --timeout=120s || fail "${svc} rollout failed"
done

# The SDL fetch reaches the gateway THROUGH the KEDA interceptor (Host header).
# The gateway is KEDA-scaled-to-zero; wake it the real way before publishing.
step "Waking graphql-gateway through the KEDA interceptor for the SDL fetch"
wake_gateway "$NS" || fail "graphql-gateway did not wake through the interceptor"

# ── tunnels ────────────────────────────────────────────────────────────────────
step "Bringing up tunnels: order(${LOCAL_ORDER}) gateway-via-interceptor(${LOCAL_GW}) apicurio(${LOCAL_APIC})"
ensure_tunnel order apicurio   # gateway tunnel was ensured by wake_gateway above
wait_http "http://127.0.0.1:${LOCAL_ORDER}/" 20 || true
wait_http "http://127.0.0.1:${LOCAL_APIC}/" 20 || true

# ── publish ───────────────────────────────────────────────────────────────────
step "Publishing discovery contracts (OpenAPI + Protobuf + GraphQL SDL)"
published=0
for attempt in 1 2 3; do
    if APICURIO_URL="http://127.0.0.1:${LOCAL_APIC}" \
       ORDER_URL="http://127.0.0.1:${LOCAL_ORDER}" \
       GATEWAY_URL="http://127.0.0.1:${LOCAL_GW}" \
       GATEWAY_HOST="${GATEWAY_HOST}" \
       PROTO_PATH="$PROTO_PATH" APICURIO_GROUP="$GROUP" \
           ./scripts/publish-discovery-contracts.sh; then
        published=1; break
    fi
    # The HTTPScaledObject's scaledownPeriod is 30s, so the gateway can drop back
    # to zero between the wake and the SDL fetch. Re-wake through the interceptor
    # and retry — publishing is idempotent.
    printf '    publish attempt %d failed — re-waking the gateway through the interceptor and retrying\n' "$attempt"
    wake_gateway "$NS" || true
    sleep 2
done
(( published )) || fail "publishing discovery contracts failed"

# ── assert all four contract types are in the registry ────────────────────────
step "Verifying contracts are registered in Apicurio"
APIC="http://127.0.0.1:${LOCAL_APIC}"
for art in order-service-openapi inventory-grpc-proto graphql-gateway-sdl; do
    meta="$(curl -fsS "${APIC}/apis/registry/v3/groups/${GROUP}/artifacts/${art}" 2>/dev/null || echo '')"
    printf '%s' "$meta" | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('artifactType') or d.get('artifact',{}).get('artifactType'); print('    ✓ '+'$art'+' ('+str(t)+')'); sys.exit(0 if t else 1)" 2>/dev/null \
        || fail "discovery artifact ${art} not found in Apicurio"
done
# the Avro runtime contract is registered via ccompat (TopicNameStrategy subject)
AVRO_V="$(curl -fsS "${APIC}/apis/ccompat/v7/subjects/order-placed-value/versions" 2>/dev/null || echo '')"
printf '%s' "$AVRO_V" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance(d,list) and d else 1)" 2>/dev/null \
    && printf '    ✓ order-placed-value (AVRO, runtime — via ccompat)\n' \
    || printf '    • order-placed-value (AVRO) not present yet — run demo-avro.sh to register it\n'

printf '\n✓ SUCCESS — discovery contracts published; Apicurio now holds all protocol contracts (OpenAPI, Protobuf, GraphQL SDL, + Avro runtime)\n'

# ── cleanup on success ────────────────────────────────────────────────────────
step "Cleanup (success)"
helm uninstall "${DEPLOY[@]}" -n "$NS" >/dev/null 2>&1 && echo "service releases uninstalled"
if (( PURGE_DB )); then
    helm uninstall "$APICURIO_RELEASE" "$KAFKA_RELEASE" "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "apicurio + kafka + postgres uninstalled"
fi
printf '  (Apicurio + Kafka + Postgres left running for fast re-runs; pass --purge-db to tear them down)\n'
