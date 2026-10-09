#!/usr/bin/env bash
#
# endpoints.sh — the ONE source of truth for host access to the capstone cluster.
#
# Every host-facing service is a fixed NodePort. The minikube profile publishes
# each NodePort to the host on loopback when the profile is created:
#   minikube start -p capstone --ports=127.0.0.1:<hostPort>:<nodePort>,...
# so `http://127.0.0.1:<hostPort>` reaches the Service directly. No helper
# process runs and nothing needs to be brought up per demo.
#
# Source this from a demo or from a script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/endpoints.sh"   # from demos/
#   ensure_endpoint order                                       # verify one endpoint
#   curl "http://127.0.0.1:${TP_ORDER}/orders" ...              # use the fixed host port
#
# The canonical host-port <-> nodePort map lives here and NOWHERE ELSE. If you
# add a service, add one row to _endpoint_row, its name to ENDPOINT_NAMES, and
# (if it's one of our charts) set its Service nodePort to the matching value.
# Published ports are fixed at profile creation: changing the map requires
# recreating the profile (./scripts/setup-capstone-profile.sh --replace), which
# deletes and recreates the cluster, so run ./scripts/bootstrap-capstone.sh again.
#
# Safe to `source` under `set -euo pipefail`: only definitions, no side effects.

# ─── Canonical port allocation (host → nodePort) ─────────────────────────────
# Keep in sync with README.md and the lgtm-minikube-stack skill's
# references/ports-and-endpoints.md. TP_* is the host port published on
# 127.0.0.1 (what YOU curl); NP_* is the nodePort the Service exposes.

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

EP_PROFILE="${MINIKUBE_PROFILE:-capstone}"

ENDPOINT_NAMES=(grafana prometheus tempo tempo-otlp kiali openmetadata apicurio
                kafka-ui order gateway notification review inventory ingress)

# name → "host node namespace svc label"  (svc/namespace used for Service checks)
# gateway maps to the KEDA interceptor proxy in the keda namespace.
_endpoint_row() {
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

# endpoint_port <name> → echoes the canonical host port (for generic demos)
endpoint_port() {
    local row; row="$(_endpoint_row "$1")" || return 1
    echo "${row%% *}"   # row is "host node ns svc label"; first field is the host port
}

# endpoint_url <name> → http://127.0.0.1:<host>
endpoint_url() {
    local p; p="$(endpoint_port "$1")" || return 1
    echo "http://127.0.0.1:${p}"
}

# _extra_pairs → lines "<host> <node>" for EXTRA_NODE_PORTS. Items may be
# "hp:np", "127.0.0.1:hp:np" (prefix stripped) or a bare "p" meaning p:p.
_extra_pairs() {
    local item IFS=','
    local -a extra
    read -ra extra <<<"${EXTRA_NODE_PORTS:-}"
    for item in "${extra[@]}"; do
        [[ -z "$item" ]] && continue
        item="${item#127.0.0.1:}"
        if [[ "$item" == *:* ]]; then echo "${item%%:*} ${item##*:}"; else echo "$item $item"; fi
    done
}

# node_ports_arg → "127.0.0.1:<host>:<node>,..." for `minikube start --ports=`.
# EXTRA_NODE_PORTS ("hp:np,hp:np", "127.0.0.1:hp:np" or bare "p" meaning p:p)
# is appended.
node_ports_arg() {
    local name row hp np out=() line
    for name in "${ENDPOINT_NAMES[@]}"; do
        row="$(_endpoint_row "$name")"
        read -r hp np _ <<<"$row"
        out+=("127.0.0.1:${hp}:${np}")
    done
    while IFS= read -r line; do
        [[ -n "$line" ]] && out+=("127.0.0.1:${line% *}:${line#* }")
    done < <(_extra_pairs)
    local IFS=','
    echo "${out[*]}"
}

# ─── Published-port inspection ───────────────────────────────────────────────

# _port_bindings_json → PortBindings JSON of the profile container (empty on error)
_port_bindings_json() {
    # The capstone profile is rootless podman (setup-capstone-profile.sh).
    podman container inspect --format '{{json .HostConfig.PortBindings}}' "$EP_PROFILE" 2>/dev/null || true
}

# _parse_bindings <loopback|other> — reads PortBindings JSON on stdin.
#   loopback → "<containerPort> <hostPort>" for HostIp == 127.0.0.1, HostPort set
#   other    → "<containerPort> <HostIp>:<HostPort>" for any other HostIp
_parse_bindings() {
    python3 -c '
import json, sys
mode = sys.argv[1]
try:
    data = json.loads(sys.stdin.read() or "null") or {}
except Exception:
    sys.exit(0)
for key, binds in sorted(data.items()):
    port = key.split("/")[0]
    for b in binds or []:
        ip, hp = b.get("HostIp", ""), b.get("HostPort", "")
        if mode == "loopback" and ip == "127.0.0.1" and hp:
            print(port, hp)
        elif mode == "other" and ip != "127.0.0.1":
            print(port, "%s:%s" % (ip, hp))
' "$1" 2>/dev/null || true
}

# published_ports → lines "<nodePort> <hostPort>" bound on 127.0.0.1
published_ports() { _port_bindings_json | _parse_bindings loopback; return 0; }

# nonloopback_ports → lines "<containerPort> <HostIp>:<HostPort>" not on 127.0.0.1
nonloopback_ports() { _port_bindings_json | _parse_bindings other; return 0; }

# registry_host_port → host port bound to container 5000/tcp (empty if none)
registry_host_port() { published_ports | awk '$1 == 5000 { print $2; exit }'; return 0; }

# _require_python → 0 if python3 exists, else prints why and returns 1
_require_python() {
    command -v python3 >/dev/null 2>&1 && return 0
    printf 'endpoints: python3 is required to read port bindings\n' >&2
    return 1
}

# check_published_ports — verify every required pair is published on loopback
# and nothing is bound off-loopback. Returns 1 with a hint on any problem.
check_published_ports() {
    local pub bad name row hp np msg="" line
    _require_python || return 1
    pub="$(published_ports)"
    bad="$(nonloopback_ports)"
    local pairs=()
    for name in "${ENDPOINT_NAMES[@]}"; do
        row="$(_endpoint_row "$name")"; read -r hp np _ <<<"$row"
        pairs+=("$hp $np")
    done
    while IFS= read -r line; do [[ -n "$line" ]] && pairs+=("$line"); done < <(_extra_pairs)
    local p
    for p in "${pairs[@]}"; do
        hp="${p%% *}"; np="${p##* }"
        grep -qx "${np} ${hp}" <<<"$pub" || msg+="  missing: 127.0.0.1:${hp} -> nodePort ${np}"$'\n'
    done
    [[ -n "$bad" ]] && while IFS= read -r line; do msg+="  not loopback-only: container port ${line}"$'\n'; done <<<"$bad"
    [[ -z "$msg" ]] && return 0
    {
        printf 'endpoints: profile "%s" does not publish the required ports:\n' "$EP_PROFILE"
        printf '%s' "$msg"
        printf 'Ports are fixed when the profile is created and cannot be added to a running one.\n'
        printf 'Recreate it with: ./scripts/setup-capstone-profile.sh --replace\n'
        printf '(--replace deletes and recreates the cluster; run ./scripts/bootstrap-capstone.sh again afterwards.)\n'
    } >&2
    return 1
}

# ensure_endpoint <name>[ <name> ...] — verify named endpoints are usable.
# Checks every name (does not stop at the first failure). Returns 0 ok, 1 if any
# port is unpublished or a Service does not match, 2 if a name is unknown (and
# no earlier check failed otherwise). A published port whose Service matches but
# does not answer yet is only a warning (stderr, rc 0): the pod may still be
# rolling out and callers do their own wait_http.
# Reach retries: EP_REACH_TRIES (default 5) attempts, EP_REACH_DELAY s apart.
ensure_endpoint() {
    local name row hp np ns svc label out rc stype nports try overall=0
    local tries="${EP_REACH_TRIES:-5}" delay="${EP_REACH_DELAY:-2}"
    _require_python || return 1
    for name in "$@"; do
        row="$(_endpoint_row "$name")" || { printf 'endpoints: unknown service "%s"\n' "$name" >&2; (( overall < 2 )) && overall=2; continue; }
        read -r hp np ns svc label <<<"$row"
        if ! published_ports | grep -qx "${np} ${hp}"; then
            printf 'endpoints: %s: 127.0.0.1:%s -> nodePort %s is not published by profile "%s"\n' \
                "$name" "$hp" "$np" "$EP_PROFILE" >&2
            printf 'Recreate it with: ./scripts/setup-capstone-profile.sh --replace\n' >&2
            printf '(--replace deletes and recreates the cluster; run ./scripts/bootstrap-capstone.sh again afterwards.)\n' >&2
            overall=1; continue
        fi
        out="$(kubectl --context "$EP_PROFILE" get svc -n "$ns" "$svc" \
                -o jsonpath='{.spec.type} {.spec.ports[*].nodePort}' 2>/dev/null)" || out=""
        stype="${out%% *}"; nports="${out#* }"
        if [[ "$stype" != "NodePort" ]] || ! grep -qw -- "$np" <<<"$nports"; then
            printf 'endpoints: %s: svc/%s in %s: expected NodePort %s, got "%s"\n' \
                "$name" "$svc" "$ns" "$np" "${out:-<not found>}" >&2
            overall=1; continue
        fi
        [[ "$name" == "notification" ]] && continue   # scales to zero; nothing listens
        rc=0
        for (( try=1; try<=tries; try++ )); do
            rc=0
            curl -s -o /dev/null --max-time 3 "http://127.0.0.1:${hp}/" >/dev/null 2>&1 || rc=$?
            [[ "$rc" != 7 && "$rc" != 28 ]] && break
            (( try < tries )) && sleep "$delay"
        done
        if [[ "$rc" == 7 || "$rc" == 28 ]]; then
            printf 'endpoints: warning: %s: http://127.0.0.1:%s not answering after %s tries (curl exit %s); continuing\n' \
                "$name" "$hp" "$tries" "$rc" >&2
        fi
    done
    return "$overall"
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
# then waiting for the Deployment to be Available. Verifies the gateway endpoint
# first. Echoes nothing; returns 0 if the gateway is Available.
GATEWAY_HOST="graphql-gateway.capstone"
wake_gateway() {
    local ns="${1:-capstone}"
    ensure_endpoint gateway || return 1
    wait_http "http://127.0.0.1:${TP_GATEWAY}/" 15 || true
    # Pre-warm: this request's job is to trigger scale-from-zero; response and
    # exit status (including curl 28, a slow interceptor) are discarded — the
    # kubectl wait below is the real readiness check.
    local wrc=0
    curl -s -o /dev/null --max-time 60 \
        -H "Host: ${GATEWAY_HOST}" "http://127.0.0.1:${TP_GATEWAY}/health" >/dev/null 2>&1 || wrc=$?
    [[ "$wrc" == 0 || "$wrc" == 28 ]] || sleep 2   # connect-level failure: give the interceptor a moment
    kubectl wait -n "$ns" --for=condition=Available deploy/graphql-gateway --timeout=120s >/dev/null 2>&1
}
