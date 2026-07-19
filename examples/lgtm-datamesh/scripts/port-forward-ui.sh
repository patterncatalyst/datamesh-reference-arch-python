#!/usr/bin/env bash
#
# port-forward-ui.sh — start (or stop) persistent background port-forwards
# for the four capstone UI services so they're reachable from the host
# immediately after bootstrap, without manual kubectl commands.
#
# The forwards are designed to outlive this script (no cleanup trap). PIDs
# are written to a pidfile so --stop can clean them up later.
#
# Usage:
#   ./scripts/port-forward-ui.sh            # start all four forwards
#   ./scripts/port-forward-ui.sh --stop     # kill all forwards
#   ./scripts/port-forward-ui.sh --status   # show which are alive

set -uo pipefail

PIDFILE="/tmp/capstone-ui-pf.pids"

BOLD=""; GRN=""; DIM=""; RST=""
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; GRN=$'\033[32m'; DIM=$'\033[2m'; RST=$'\033[0m'
fi

ok()   { printf '    %s✓%s %s\n' "$GRN" "$RST" "$1"; }
info() { printf '    %s%s%s\n' "$DIM" "$1" "$RST"; }

# ── --stop ───────────────────────────────────────────────────────────────────

do_stop() {
    if [[ ! -f "$PIDFILE" ]]; then
        info "no pidfile — nothing to stop"
        return 0
    fi
    local killed=0
    while IFS='|' read -r pid label _ ; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null && killed=$((killed + 1))
            info "stopped $label (pid $pid)"
        fi
    done < "$PIDFILE"
    rm -f "$PIDFILE"
    info "stopped $killed forward(s)"
}

# ── --status ─────────────────────────────────────────────────────────────────

do_status() {
    if [[ ! -f "$PIDFILE" ]]; then
        info "no pidfile — no forwards tracked"
        return 0
    fi
    while IFS='|' read -r pid label url ; do
        if kill -0 "$pid" 2>/dev/null; then
            printf '    %s✓%s %-16s  %s  (pid %s)\n' "$GRN" "$RST" "$label" "$url" "$pid"
        else
            printf '    ✗ %-16s  dead (pid %s)\n' "$label" "$pid"
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

# ── start ────────────────────────────────────────────────────────────────────
# Each entry: label | namespace | service | local_port | remote_port | url

FORWARDS=(
    "Grafana|observability|grafana|3000|80|http://localhost:3000"
    "Prometheus|observability|prometheus-server|9091|80|http://localhost:9091"
    "Kiali|istio-system|kiali|20001|20001|http://localhost:20001/kiali"
    "OpenMetadata|capstone|openmetadata|8585|8585|http://localhost:8585"
)

port_in_use() {
    local port="$1"
    ss -tlnp 2>/dev/null | grep -q ":${port} " && return 0
    return 1
}

# kill any stale forwards from a previous run before starting fresh
[[ -f "$PIDFILE" ]] && do_stop >/dev/null 2>&1
: > "$PIDFILE"

started=0
for entry in "${FORWARDS[@]}"; do
    IFS='|' read -r label ns svc local_port remote_port url <<< "$entry"

    if port_in_use "$local_port"; then
        info "$label: port $local_port already bound (skipped)"
        continue
    fi

    if ! kubectl get svc "$svc" -n "$ns" >/dev/null 2>&1; then
        info "$label: svc/$svc not found in $ns (skipped)"
        continue
    fi

    kubectl port-forward -n "$ns" "svc/$svc" "${local_port}:${remote_port}" >/dev/null 2>&1 &
    pf_pid=$!
    printf '%s|%s|%s\n' "$pf_pid" "$label" "$url" >> "$PIDFILE"
    started=$((started + 1))
done

# brief pause to let the forwards bind
sleep 1

printf '\n'
printf '    %s%-16s  %-40s  %s%s\n' "$BOLD" "Service" "URL" "Status" "$RST"
printf '    %-16s  %-40s  %s\n' "───────────────" "────────────────────────────────────────" "──────"
while IFS='|' read -r pid label url ; do
    if kill -0 "$pid" 2>/dev/null; then
        printf '    %s✓%s %-14s  %-40s  %slive%s\n' "$GRN" "$RST" "$label" "$url" "$GRN" "$RST"
    else
        printf '    ✗ %-14s  %-40s  failed\n' "$label" "$url"
    fi
done < "$PIDFILE"
printf '\n'

ok "$started UI port-forward(s) started (pidfile: $PIDFILE)"
info "Grafana login:      admin / capstone"
info "OpenMetadata login:  admin@open-metadata.org / admin"
info "stop with: ./scripts/port-forward-ui.sh --stop"
