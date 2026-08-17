#!/usr/bin/env bash
#
# tunnel-services.sh — start (or stop) SSH tunnels from localhost to NodePort
# services in the capstone minikube profile. Replaces kubectl port-forward with
# stable, long-lived connections that survive idle timeouts and load spikes.
#
# How it works:
#   1. Services are exposed as NodePort with fixed ports (30xxx range).
#   2. An SSH tunnel connects localhost:<friendly-port> to the minikube VM's
#      <nodePort> via the minikube SSH key.
#   3. ServerAliveInterval=30 keeps the tunnel alive; ExitOnForwardFailure=yes
#      makes failures explicit.
#
# Usage:
#   ./scripts/tunnel-services.sh            # start all tunnels
#   ./scripts/tunnel-services.sh --stop     # kill all tunnels
#   ./scripts/tunnel-services.sh --status   # show which are alive

set -uo pipefail

PROFILE="${MINIKUBE_PROFILE:-capstone}"
PIDFILE="/tmp/capstone-tunnel.pids"

BOLD=""; GRN=""; RED=""; DIM=""; RST=""
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; GRN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RST=$'\033[0m'
fi

ok()   { printf '    %s✓%s %s\n' "$GRN" "$RST" "$1"; }
info() { printf '    %s%s%s\n' "$DIM" "$1" "$RST"; }

# ── --stop ───────────────────────────────────────────────────────────────────

do_stop() {
    # Kill SSH tunnels tracked in pidfile
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

# ── resolve SSH connection details ───────────────────────────────────────────

SSH_KEY="$(minikube ssh-key -p "$PROFILE" 2>/dev/null)"
if [[ -z "$SSH_KEY" ]]; then
    printf '%sERROR:%s could not find SSH key for profile "%s"\n' "$RED" "$RST" "$PROFILE"
    printf 'Is minikube running? Try: minikube start -p %s\n' "$PROFILE"
    exit 1
fi

SSH_PORT="$(podman port "$PROFILE" 22/tcp 2>/dev/null | head -1 | cut -d: -f2)"
if [[ -z "$SSH_PORT" ]]; then
    printf '%sERROR:%s could not detect SSH port for profile "%s"\n' "$RED" "$RST" "$PROFILE"
    printf 'Is minikube running? Try: minikube start -p %s\n' "$PROFILE"
    exit 1
fi

# ── kill stale tunnels from a previous run ───────────────────────────────────

[[ -f "$PIDFILE" ]] && do_stop >/dev/null 2>&1
: > "$PIDFILE"

# ── start tunnels ────────────────────────────────────────────────────────────

tunnel() {
    local local_port=$1 node_port=$2 label=$3 url=$4
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes \
        -i "$SSH_KEY" -p "$SSH_PORT" \
        -L "${local_port}:localhost:${node_port}" \
        -N -f docker@127.0.0.1
    # ssh -f daemonizes itself (no shell $!). Find the PID via pgrep.
    sleep 0.3
    local pid
    pid="$(pgrep -n -f "ssh.*-L ${local_port}:localhost:${node_port}" 2>/dev/null || echo "")"
    if [[ -n "$pid" ]]; then
        printf '%s|%s|%s\n' "$pid" "$label" "$url" >> "$PIDFILE"
    fi
}

started=0

# Grafana
if kubectl get svc grafana -n observability >/dev/null 2>&1; then
    tunnel 3000 30300 "Grafana" "http://localhost:3000"
    ok "Grafana:          http://localhost:3000"
    started=$((started + 1))
else
    info "Grafana: svc/grafana not found (skipped)"
fi

# Prometheus (9091 to avoid Fedora Cockpit on 9090)
if kubectl get svc prometheus-server -n observability >/dev/null 2>&1; then
    tunnel 9091 30091 "Prometheus" "http://localhost:9091"
    ok "Prometheus:       http://localhost:9091"
    started=$((started + 1))
else
    info "Prometheus: svc/prometheus-server not found (skipped)"
fi

# Tempo
if kubectl get svc tempo -n observability >/dev/null 2>&1; then
    tunnel 3200 30320 "Tempo" "http://localhost:3200"
    ok "Tempo:            http://localhost:3200"
    started=$((started + 1))
else
    info "Tempo: svc/tempo not found (skipped)"
fi

# Kiali
if kubectl get svc kiali -n istio-system >/dev/null 2>&1; then
    tunnel 20001 30201 "Kiali" "http://localhost:20001/kiali"
    ok "Kiali:            http://localhost:20001/kiali"
    started=$((started + 1))
else
    info "Kiali: svc/kiali not found (skipped)"
fi

# OpenMetadata
if kubectl get svc openmetadata -n capstone >/dev/null 2>&1; then
    tunnel 8585 30585 "OpenMetadata" "http://localhost:8585"
    ok "OpenMetadata:     http://localhost:8585"
    started=$((started + 1))
else
    info "OpenMetadata: svc/openmetadata not found (skipped)"
fi

printf '\n'
ok "$started SSH tunnel(s) started — stable, no port-forward drops"
info "Grafana login:       admin / capstone"
info "OpenMetadata login:  admin@open-metadata.org / admin"
info "stop with: ./scripts/tunnel-services.sh --stop"
info "status:    ./scripts/tunnel-services.sh --status"
