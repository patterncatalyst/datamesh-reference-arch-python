#!/usr/bin/env bash
#
# tunnels.sh — the ONE source of truth for host access to the capstone cluster.
#
# Everything that used to `kubectl port-forward` now goes through a stable SSH
# tunnel to a fixed NodePort. Port-forwards drop when the cluster quiesces or
# under load; SSH tunnels (ServerAliveInterval + ExitOnForwardFailure) do not.
#
# Source this from a demo or from scripts/tunnel-services.sh:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/tunnels.sh"    # from demos/
#   ensure_tunnel order                                        # bring up one tunnel
#   curl "http://127.0.0.1:${TP_ORDER}/orders" ...             # use the fixed local port
#
# The canonical local-port ↔ nodePort map lives here and NOWHERE ELSE. If you
# add a service, add one row to TUNNEL_MAP and (if it's one of our charts) set
# its Service nodePort to the matching value.

# ─── Canonical port allocation (local → nodePort) ────────────────────────────
# Keep in sync with README.md and the lgtm-minikube-stack skill's
# references/ports-and-endpoints.md. Local ports are what YOU curl; nodePorts
# are what the Service exposes on the minikube node.

# Persistent UIs
TP_GRAFANA=3000;      NP_GRAFANA=30300
TP_PROM=9091;         NP_PROM=30091
TP_TEMPO=3200;        NP_TEMPO=30320
TP_TEMPO_OTLP=4318;   NP_TEMPO_OTLP=30418
TP_KIALI=20001;       NP_KIALI=30201
TP_OM=8585;           NP_OM=30585
TP_APICURIO=8084;     NP_APICURIO=30084

# App / infra services
TP_ORDER=8080;        NP_ORDER=30080
TP_GATEWAY=8081;      NP_GATEWAY=30081   # KEDA interceptor proxy — gateway wake path
TP_NOTIF=8083;        NP_NOTIF=30083     # scaled-to-zero (Kafka lag)
TP_REVIEW=8086;       NP_REVIEW=30086
TP_INVENTORY=8087;    NP_INVENTORY=30087
TP_INGRESS=8088;      NP_INGRESS=30088   # istio-ingressgateway :80
TP_KAFKAUI=8089;      NP_KAFKAUI=30089   # Kafka UI (topic/schema browser)

# name → "local node namespace svc label"  (svc/namespace used only for guards)
# gateway maps to the KEDA interceptor proxy in the keda namespace.
_tunnel_row() {
    case "$1" in
        grafana)      echo "$TP_GRAFANA $NP_GRAFANA observability grafana Grafana" ;;
        prometheus)   echo "$TP_PROM $NP_PROM observability prometheus-server Prometheus" ;;
        tempo)        echo "$TP_TEMPO $NP_TEMPO observability tempo Tempo" ;;
        tempo-otlp)   echo "$TP_TEMPO_OTLP $NP_TEMPO_OTLP observability tempo Tempo-OTLP" ;;
        kiali)        echo "$TP_KIALI $NP_KIALI istio-system kiali Kiali" ;;
        openmetadata) echo "$TP_OM $NP_OM capstone openmetadata OpenMetadata" ;;
        apicurio)     echo "$TP_APICURIO $NP_APICURIO capstone apicurio Apicurio" ;;
        kafka-ui)     echo "$TP_KAFKAUI $NP_KAFKAUI capstone kafka-ui Kafka-UI" ;;
        order)        echo "$TP_ORDER $NP_ORDER capstone order-service order-service" ;;
        gateway)      echo "$TP_GATEWAY $NP_GATEWAY keda keda-add-ons-http-interceptor-proxy gateway-interceptor" ;;
        notification) echo "$TP_NOTIF $NP_NOTIF capstone notification-service notification-service" ;;
        review)       echo "$TP_REVIEW $NP_REVIEW capstone review-service review-service" ;;
        inventory)    echo "$TP_INVENTORY $NP_INVENTORY capstone inventory-service inventory-service" ;;
        ingress)      echo "$TP_INGRESS $NP_INGRESS istio-system istio-ingressgateway istio-ingressgateway" ;;
        *) return 1 ;;
    esac
}

# tunnel_port_for <name> → echoes the canonical local port (for generic demos)
tunnel_port_for() {
    local row; row="$(_tunnel_row "$1")" || return 1
    echo "${row%% *}"   # row is "local node ns svc label"; first field is the local port
}

# ─── SSH connection to the minikube VM ───────────────────────────────────────
TP_PROFILE="${MINIKUBE_PROFILE:-capstone}"
TP_PIDFILE="/tmp/capstone-tunnel.pids"
_TP_SSH_KEY=""; _TP_SSH_PORT=""

_tp_resolve_ssh() {
    [[ -n "$_TP_SSH_KEY" && -n "$_TP_SSH_PORT" ]] && return 0
    _TP_SSH_KEY="$(minikube ssh-key -p "$TP_PROFILE" 2>/dev/null)"
    _TP_SSH_PORT="$(podman port "$TP_PROFILE" 22/tcp 2>/dev/null | head -1 | cut -d: -f2)"
    [[ -n "$_TP_SSH_KEY" && -n "$_TP_SSH_PORT" ]]
}

# tunnel <local> <node> <label> [url] — start an ssh -L if one isn't already up.
# Idempotent: never tears down an existing tunnel (so demos don't kill the
# tunnels the walkthrough started).
tunnel() {
    local local_port="$1" node_port="$2" label="${3:-svc}" url="${4:-http://localhost:$1}"
    if pgrep -f "ssh.*-L ${local_port}:localhost:${node_port}" >/dev/null 2>&1; then
        return 0   # already up
    fi
    _tp_resolve_ssh || {
        printf 'tunnels: could not resolve SSH for profile %s (is minikube up?)\n' "$TP_PROFILE" >&2
        return 1
    }
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes \
        -i "$_TP_SSH_KEY" -p "$_TP_SSH_PORT" \
        -L "${local_port}:localhost:${node_port}" \
        -N -f docker@127.0.0.1 2>/dev/null || return 1
    sleep 0.3
    local pid; pid="$(pgrep -n -f "ssh.*-L ${local_port}:localhost:${node_port}" 2>/dev/null || echo "")"
    [[ -n "$pid" ]] && printf '%s|%s|%s\n' "$pid" "$label" "$url" >> "$TP_PIDFILE"
    return 0
}

# ensure_tunnel <name>[ <name> ...] — bring up one or more named tunnels.
ensure_tunnel() {
    local name row lp np ns label
    for name in "$@"; do
        row="$(_tunnel_row "$name")" || { printf 'tunnels: unknown service "%s"\n' "$name" >&2; return 2; }
        read -r lp np ns _ label <<<"$row"
        tunnel "$lp" "$np" "$label" "http://localhost:${lp}"
    done
}

# ─── Waiters ─────────────────────────────────────────────────────────────────

# wait_http <url> [timeout-seconds] [expected-codes-regex]
# Retries until curl connects (any HTTP response, or a code matching the regex).
wait_http() {
    local url="$1" budget="${2:-30}" want="${3:-}" i code
    for (( i=0; i<budget; i++ )); do
        if [[ -n "$want" ]]; then
            code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$url" 2>/dev/null || echo 000)"
            [[ "$code" =~ $want ]] && return 0
        else
            curl -s -o /dev/null --max-time 3 "$url" 2>/dev/null && return 0
        fi
        sleep 1
    done
    return 1
}

# wake_gateway — wake the KEDA-scaled-to-zero graphql-gateway the REAL way, by
# driving a request through the HTTP interceptor (Host: graphql-gateway.capstone),
# then waiting for the Deployment to be Available. Brings up the gateway tunnel
# first. Echoes nothing; returns 0 if the gateway is Available.
GATEWAY_HOST="graphql-gateway.capstone"
wake_gateway() {
    local ns="${1:-capstone}"
    ensure_tunnel gateway || return 1
    wait_http "http://127.0.0.1:${TP_GATEWAY}/" 15 || true
    # Pre-warm: this request's job is to trigger scale-from-zero; response discarded.
    curl -s -o /dev/null --max-time 60 \
        -H "Host: ${GATEWAY_HOST}" "http://127.0.0.1:${TP_GATEWAY}/health" >/dev/null 2>&1 || true
    kubectl wait -n "$ns" --for=condition=Available deploy/graphql-gateway --timeout=120s >/dev/null 2>&1
}
