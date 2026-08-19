#!/usr/bin/env bash
#
# tunnel-services.sh — start (or stop) SSH tunnels from localhost to NodePort
# services in the capstone minikube profile. Replaces kubectl port-forward with
# stable, long-lived connections that survive idle timeouts and load spikes.
#
# The port map and the tunnel/ssh machinery live in demos/lib/tunnels.sh — the
# ONE source of truth. This script just brings the whole set up (or tears it
# down). Individual demos bring up only the tunnels they need via ensure_tunnel.
#
# Usage:
#   ./scripts/tunnel-services.sh            # start all tunnels
#   ./scripts/tunnel-services.sh --stop     # kill all tunnels
#   ./scripts/tunnel-services.sh --status   # show which are alive

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../demos/lib/tunnels.sh
source "${SCRIPT_DIR}/../demos/lib/tunnels.sh"

PIDFILE="$TP_PIDFILE"

BOLD=""; GRN=""; RED=""; DIM=""; RST=""
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; GRN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RST=$'\033[0m'
fi

ok()   { printf '    %s✓%s %s\n' "$GRN" "$RST" "$1"; }
info() { printf '    %s%s%s\n' "$DIM" "$1" "$RST"; }

# ── --stop ───────────────────────────────────────────────────────────────────

do_stop() {
    if [[ -f "$PIDFILE" ]]; then
        local killed=0
        while IFS='|' read -r pid label _ ; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null && killed=$((killed + 1))
                info "stopped $label (pid $pid)"
            fi
        done < "$PIDFILE"
        rm -f "$PIDFILE"
        info "stopped $killed tunnel(s)"
    else
        info "no pidfile — nothing to stop"
    fi
}

# ── --status ─────────────────────────────────────────────────────────────────

do_status() {
    if [[ ! -f "$PIDFILE" ]]; then
        info "no pidfile — no tunnels tracked"
        return 0
    fi
    while IFS='|' read -r pid label url ; do
        if kill -0 "$pid" 2>/dev/null; then
            printf '    %s✓%s %-16s  %s  (pid %s)\n' "$GRN" "$RST" "$label" "$url" "$pid"
        else
            printf '    %s✗%s %-16s  dead (pid %s)\n' "$RED" "$RST" "$label" "$pid"
        fi
    done < "$PIDFILE"
}

# ── args ─────────────────────────────────────────────────────────────────────

case "${1:-start}" in
    --stop)   do_stop;   exit 0 ;;
    --status) do_status; exit 0 ;;
    start|--start) ;;
    --help|-h)
        printf 'Usage: %s [--stop | --status | --help]\n' "$(basename "$0")"
        exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1"; exit 2 ;;
esac

# resolve SSH once, up front, with a clear error if the cluster is down
if ! _tp_resolve_ssh; then
    printf '%sERROR:%s could not find SSH key/port for profile "%s"\n' "$RED" "$RST" "$TP_PROFILE"
    printf 'Is minikube running? Try: minikube start -p %s\n' "$TP_PROFILE"
    exit 1
fi

# ── kill stale tunnels from a previous run, then start fresh ──────────────────
[[ -f "$PIDFILE" ]] && do_stop >/dev/null 2>&1
: > "$PIDFILE"

started=0

# start <name> <friendly-label>  — bring up a named tunnel if its Service exists
start() {
    local name="$1" label="$2" row lp np ns svc
    row="$(_tunnel_row "$name")" || { info "$label: unknown ($name)"; return; }
    read -r lp np ns svc _ <<<"$row"
    if kubectl get svc "$svc" -n "$ns" >/dev/null 2>&1; then
        ensure_tunnel "$name" && { ok "$(printf '%-14s http://localhost:%s' "$label:" "$lp")"; started=$((started + 1)); }
    else
        info "$label: svc/$svc not found in $ns (skipped)"
    fi
}

# Persistent UIs
start grafana      "Grafana"
start prometheus   "Prometheus"
start tempo        "Tempo"
start kiali        "Kiali"
start openmetadata "OpenMetadata"
start apicurio     "Apicurio"
start kafka-ui     "Kafka UI"

# App / infra endpoints the demos drive (no more kubectl port-forward)
start order        "order-svc"
start gateway      "gateway(interceptor)"
start notification "notification-svc"
start review       "review-svc"
start inventory    "inventory-svc"
start ingress      "istio-ingress"

printf '\n'
ok "$started SSH tunnel(s) started — stable, no port-forward drops"
info "Grafana login:       admin / capstone"
info "OpenMetadata login:  admin@open-metadata.org / admin"
info "gateway is reached via the KEDA interceptor on :$TP_GATEWAY (Host: $GATEWAY_HOST)"
info "stop with: ./scripts/tunnel-services.sh --stop"
info "status:    ./scripts/tunnel-services.sh --status"
