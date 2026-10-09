#!/usr/bin/env bash
#
# show-endpoints.sh — read-only report of host access to the capstone cluster.
#
# For each endpoint: URL, whether the profile publishes its port on 127.0.0.1,
# whether the Service nodePort matches, and whether something answers.
# A Service that is absent is reported "not deployed" (a warning: review-service
# is optional, bootstrap does not deploy it and the demos remove it).
#
# Exit codes:
#   0  ok (warnings allowed: unreachable endpoint, Service not deployed)
#   1  a port is unpublished, a binding is not loopback-only, a Service has the
#      wrong type/nodePort, or the cluster is not running
#   2  bad flag
#
# Usage: ./scripts/show-endpoints.sh [--help]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../demos/lib/endpoints.sh
source "${SCRIPT_DIR}/../demos/lib/endpoints.sh"

case "${1:-}" in
    --help|-h) printf 'Usage: %s [--help]\nRead-only: shows URL, published, Service nodePort, reachable per endpoint.\nExit codes: 0 ok; 1 unpublished, non-loopback, nodePort mismatch or cluster not running; 2 bad flag.\nA Service that is absent shows "not deployed" (warning only).\n' "$(basename "$0")"; exit 0 ;;
    "") ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
esac

BOLD=""; GRN=""; RED=""; YEL=""; DIM=""; RST=""
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; GRN=$'\033[32m'; RED=$'\033[31m'; YEL=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf '%sERROR:%s python3 is required to read port bindings.\n' "$RED" "$RST"
    exit 1
fi

if ! { podman container exists "$EP_PROFILE" 2>/dev/null && \
       [[ "$(podman inspect --format '{{.State.Running}}' "$EP_PROFILE" 2>/dev/null)" == "true" ]]; }; then
    printf '%sERROR:%s cluster "%s" is not running.\n' "$RED" "$RST" "$EP_PROFILE"
    printf 'Start it with: minikube start -p %s   (or ./scripts/setup-capstone-profile.sh)\n' "$EP_PROFILE"
    exit 1
fi

pub="$(published_ports)"
bad="$(nonloopback_ports)"
fail=0; warn=0; missing_port=0; drift=0

printf '%s%-14s %-28s %-10s %-24s %s%s\n' "$BOLD" NAME URL PUBLISHED "SVC NODEPORT" REACHABLE "$RST"
for name in "${ENDPOINT_NAMES[@]}"; do
    read -r hp np ns svc _ <<<"$(_endpoint_row "$name")"

    if grep -qx "${np} ${hp}" <<<"$pub"; then p="${GRN}ok${RST}"; else p="${RED}MISSING${RST}"; fail=1; missing_port=1; fi

    out="$(kubectl --context "$EP_PROFILE" get svc -n "$ns" "$svc" \
            -o jsonpath='{.spec.type} {.spec.ports[*].nodePort}' 2>/dev/null)" || out=""
    if [[ -z "$out" ]]; then
        sraw="not deployed"; s="${YEL}${sraw}${RST}"; warn=1
    elif [[ "${out%% *}" == "NodePort" ]] && grep -qw -- "$np" <<<"${out#* }"; then
        s="${GRN}ok${RST}"; sraw="ok"
    else
        sraw="expected ${np} got ${out#* }"; s="${RED}${sraw}${RST}"; fail=1; drift=1
    fi

    if [[ "$name" == "notification" ]]; then
        r="${DIM}scaled-to-zero${RST}"
    else
        rc=0; curl -s -o /dev/null --max-time 3 "http://127.0.0.1:${hp}/" >/dev/null 2>&1 || rc=$?
        if [[ "$rc" == 7 || "$rc" == 28 ]]; then r="${YEL}no${RST}"; warn=1; else r="${GRN}ok${RST}"; fi
    fi

    # pad plain-text width manually: colour codes break printf %-Ns
    pad() { local plain="$1" w="$2"; printf '%*s' $(( w > ${#plain} ? w - ${#plain} : 0 )) ""; }
    case "$p" in *MISSING*) praw=MISSING ;; *) praw=ok ;; esac
    url="$(endpoint_url "$name")"
    printf '%-14s %-28s %s%s %s%s %s\n' "$name" "$url" "$p" "$(pad "$praw" 10)" "$s" "$(pad "$sraw" 24)" "$r"
done

if [[ -n "$bad" ]]; then
    fail=1; missing_port=1
    printf '\n%sNon-loopback bindings:%s\n' "$RED" "$RST"
    while IFS= read -r line; do printf '  container port %s\n' "$line"; done <<<"$bad"
fi

printf '\n'
if (( fail )); then
    if (( missing_port )); then
        printf '%sFAIL:%s ports are fixed at profile creation. Recreate with: ./scripts/setup-capstone-profile.sh --replace\n' "$RED" "$RST"
        printf '(--replace deletes and recreates the cluster; run ./scripts/bootstrap-capstone.sh again afterwards.)\n'
    fi
    if (( drift )); then
        printf '%sFAIL:%s a Service nodePort drifted from the map in demos/lib/endpoints.sh; re-run the relevant setup script or ./scripts/bootstrap-capstone.sh.\n' "$RED" "$RST"
    fi
    exit 1
fi
(( warn )) && printf '%sWARN:%s some endpoints are not answering yet or not deployed (optional Services such as review-service are fine).\n' "$YEL" "$RST"
exit 0
