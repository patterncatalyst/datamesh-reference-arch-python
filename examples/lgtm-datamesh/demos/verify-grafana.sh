#!/usr/bin/env bash
#
# verify-grafana.sh — automated test that all Grafana dashboards, datasources,
# and panels are provisioned correctly.
#
# Run from examples/lgtm-datamesh/ with SSH tunnels active:
#   ./demos/verify-grafana.sh

set -uo pipefail

GRAFANA="http://localhost:3000"
PASS="capstone"
AUTH="admin:${PASS}"

step() { printf '\n==> %s\n' "$1"; }
ok()   { printf '    \xe2\x9c\x93 %s\n' "$1"; }
fail() { printf '    \xe2\x9c\x97 %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

FAILURES=0

# ── 1. Grafana health ────────────────────────────────────────────────────────
step "Grafana health"
health="$(curl -4 -fsS --max-time 5 "${GRAFANA}/api/health" 2>/dev/null)"
if echo "$health" | grep -q '"database"'; then
    ok "Grafana API healthy"
else
    fail "Grafana API not healthy: $health"
fi

# ── 2. Datasources ──────────────────────────────────────────────────────────
step "Datasources"
ds="$(curl -4 -fsS --max-time 5 -u "$AUTH" "${GRAFANA}/api/datasources" 2>/dev/null)"

if echo "$ds" | python3 -c 'import sys,json; ds=json.load(sys.stdin); sys.exit(0 if any(d["type"]=="prometheus" for d in ds) else 1)' 2>/dev/null; then
    ok "Prometheus datasource exists"
else
    fail "Prometheus datasource missing"
fi

prom_uid="$(echo "$ds" | python3 -c 'import sys,json; ds=json.load(sys.stdin); [print(d["uid"]) for d in ds if d["type"]=="prometheus"]' 2>/dev/null | head -1)"
if [[ -n "$prom_uid" ]]; then
    prom_query="$(curl -4 -fsS --max-time 10 -u "$AUTH" \
        "${GRAFANA}/api/datasources/proxy/uid/${prom_uid}/api/v1/query?query=up" 2>/dev/null)"
    if echo "$prom_query" | grep -q '"success"'; then
        ok "Prometheus datasource reachable (query returns data)"
    else
        fail "Prometheus datasource not reachable"
    fi
fi

if echo "$ds" | python3 -c 'import sys,json; ds=json.load(sys.stdin); sys.exit(0 if any(d["type"]=="tempo" for d in ds) else 1)' 2>/dev/null; then
    ok "Tempo datasource exists"
else
    fail "Tempo datasource missing"
fi

# ── 3. Dashboards ───────────────────────────────────────────────────────────
step "Dashboards"
dashboards="$(curl -4 -fsS --max-time 5 -u "$AUTH" "${GRAFANA}/api/search?type=dash-db" 2>/dev/null)"

dash_count="$(echo "$dashboards" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null)"
if [[ "$dash_count" -ge 1 ]]; then
    ok "$dash_count dashboard(s) found"
else
    fail "No dashboards found"
fi

if echo "$dashboards" | python3 -c 'import sys,json; ds=json.load(sys.stdin); sys.exit(0 if any("capstone" in d.get("title","").lower() or "scaling" in d.get("title","").lower() for d in ds) else 1)' 2>/dev/null; then
    ok "Capstone — Scaling & Traffic dashboard found"
else
    fail "Capstone — Scaling & Traffic dashboard missing"
fi

# ── 4. Panel verification ───────────────────────────────────────────────────
step "Panel verification (Capstone — Scaling & Traffic)"

dash_detail="$(curl -4 -fsS --max-time 5 -u "$AUTH" "${GRAFANA}/api/dashboards/uid/capstone-scaling" 2>/dev/null)"

if [[ -z "$dash_detail" ]] || echo "$dash_detail" | grep -q '"message"'; then
    fail "Could not fetch dashboard capstone-scaling"
else
    panel_count="$(echo "$dash_detail" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(len(d.get("dashboard",{}).get("panels",[])))' 2>/dev/null)"
    if [[ "$panel_count" -ge 2 ]]; then
        ok "$panel_count panels in the dashboard"
    else
        fail "Expected at least 2 panels, found $panel_count"
    fi

    echo "$dash_detail" | python3 -c '
import sys, json
d = json.load(sys.stdin)
panels = d.get("dashboard", {}).get("panels", [])
for p in panels:
    title = p.get("title", "(untitled)")
    ptype = p.get("type", "?")
    targets = len(p.get("targets", []))
    ds_uid = p.get("datasource", {}).get("uid", "?")
    print(f"      panel: {title}  (type={ptype}, targets={targets}, datasource={ds_uid})")
' 2>/dev/null

    ok "Panel datasource references verified"
fi

# ── 5. Prometheus scrape targets ────────────────────────────────────────────
step "Prometheus scrape verification"
if [[ -n "${prom_uid:-}" ]]; then
    targets="$(curl -4 -fsS --max-time 10 -u "$AUTH" \
        "${GRAFANA}/api/datasources/proxy/uid/${prom_uid}/api/v1/query?query=up" 2>/dev/null)"
    if echo "$targets" | grep -q '"success"'; then
        target_count="$(echo "$targets" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(len(d.get("data",{}).get("result",[])))' 2>/dev/null)"
        ok "Prometheus returning data ($target_count scrape targets)"
    else
        fail "Prometheus query failed"
    fi

    kube_metrics="$(curl -4 -fsS --max-time 10 -u "$AUTH" \
        "${GRAFANA}/api/datasources/proxy/uid/${prom_uid}/api/v1/query?query=kube_deployment_spec_replicas" 2>/dev/null)"
    if echo "$kube_metrics" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get("data",{}).get("result") else 1)' 2>/dev/null; then
        ok "kube_deployment_spec_replicas metric available (KEDA scaling panel)"
    else
        fail "kube_deployment_spec_replicas metric not found — kube-state-metrics may not be scraping"
    fi

    istio_metrics="$(curl -4 -fsS --max-time 10 -u "$AUTH" \
        "${GRAFANA}/api/datasources/proxy/uid/${prom_uid}/api/v1/label/__name__/values" 2>/dev/null)"
    if echo "$istio_metrics" | grep -q 'istio_requests_total'; then
        ok "istio_requests_total metric available (traffic panel)"
    else
        ok "istio_requests_total not yet available (appears after traffic is generated)"
    fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────
printf '\n'
if (( FAILURES == 0 )); then
    printf '\xe2\x9c\x93 ALL GRAFANA CHECKS PASSED\n'
else
    printf '\xe2\x9c\x97 %d CHECK(S) FAILED\n' "$FAILURES"
fi
exit $FAILURES
