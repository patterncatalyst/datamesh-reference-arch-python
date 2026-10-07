#!/usr/bin/env bash
#
# install-platform.sh — serial orchestrator for the OpenShift platform tier
# that sits on top of the already-verified live-core chart
# (../helm/datamesh/). Brings up the Istio mesh (OSSM3/Sail) and the
# otel-lgtm observability backend, flips the core chart's mesh/OTLP flags on,
# applies the order-service canary, and provisions the Postgres databases
# the keda/prefect/openmetadata sub-tiers need.
#
# Mirrors the conventions of ../build-and-push.sh (set -euo pipefail, step()
# echoes, idempotent re-apply) and the minikube scripts/setup-*.sh family
# (scripts/setup-istio.sh, scripts/setup-openmetadata.sh) — same shape,
# retargeted to `oc`/Sail/OSSM3 instead of `kubectl`/istioctl/CNPG.
#
# SCOPE: this script owns mesh/ and observability/ only. KEDA, Prefect, and
# OpenMetadata are authored by a second, concurrently-developed set of
# directories (platform/keda/, platform/prefect/, platform/openmetadata/) —
# this script does NOT apply those manifests (see the final section), it
# only provisions the two Postgres databases Prefect and OpenMetadata need
# in the core `postgres` StatefulSet, since that's a core-Postgres change.
#
# Idempotent: every `oc apply` is declarative, the one `oc delete deploy` is
# `--ignore-not-found`, `helm upgrade --install` is safe to re-run, and the
# DB-provisioning functions use the same CREATE-IF-NOT-EXISTS pattern as
# scripts/setup-openmetadata.sh.
#
# Prerequisites:
#   - oc login'd to the target cluster, project `datamesh` already created
#     (see ../README.md), the live-core chart already installed
#     (helm upgrade --install datamesh ../helm/datamesh --namespace datamesh)
#   - subscriptions/ already applied (servicemeshoperator3, the Custom
#     Metrics Autoscaler) — this script waits on their CSVs, it doesn't
#     create the Subscriptions themselves.
#
# Usage (from examples/lgtm-datamesh/openshift/platform/):
#   ./install-platform.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_CHART="$SCRIPT_DIR/../helm/datamesh"

NS="datamesh"
MESH_SYSTEM_NS="istio-system"
CNI_NS="istio-cni"

# The core Postgres StatefulSet (../helm/datamesh/templates/postgres.yaml)
# pod is always "postgres-0" (replicas: 1). Its initdb superuser is NOT
# "postgres" — the upstream postgres image's POSTGRES_USER env makes the
# *named* user the superuser, and values.yaml sets that to "capstone_app".
PG_POD="postgres-0"
PG_CONTAINER="postgres"
PG_SUPERUSER="capstone_app"   # ../helm/datamesh/values.yaml postgres.username
PG_SUPERDB="capstone"         # ../helm/datamesh/values.yaml postgres.database — connect here to CREATE DATABASE

# DEMO passwords — fine for a local reference build, not production (same
# caveat as scripts/setup-openmetadata.sh's OM_PASSWORD).
PREFECT_DB="prefect"
PREFECT_ROLE="prefect"
PREFECT_PASSWORD="prefect"

OPENMETADATA_DB="openmetadata"
OPENMETADATA_ROLE="openmetadata"
OPENMETADATA_PASSWORD="openmetadata"

APP_SERVICES=(
  graphql-gateway
  inventory-service
  notification-service
  order-service
  payment-service
  review-service
  shipping-service
)

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────

for tool in oc helm; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool not in PATH."
done

# ─── Helpers ─────────────────────────────────────────────────────────────────

# wait_for_csv NAMESPACE NAME_PREFIX [TIMEOUT_SECONDS]
# Polls `oc get csv` until a CSV whose name starts with NAME_PREFIX reports
# phase Succeeded. The subscriptions (subscriptions/*.yaml) are assumed
# already applied — this only waits for OLM to finish installing them.
wait_for_csv() {
  local ns="$1" prefix="$2" timeout="${3:-300}" waited=0 line name phase
  step "Waiting for CSV '${prefix}*' to reach Succeeded in ${ns}"
  while (( waited < timeout )); do
    line="$(oc get csv -n "$ns" --no-headers 2>/dev/null \
      | awk -v p="$prefix" '$1 ~ ("^" p) {print $1, $NF; exit}')"
    if [[ -n "$line" ]]; then
      name="${line% *}"
      phase="${line##* }"
      if [[ "$phase" == "Succeeded" ]]; then
        printf '    %s: Succeeded\n' "$name"
        return 0
      fi
    fi
    sleep 5
    waited=$((waited + 5))
  done
  fail "CSV '${prefix}*' in namespace '${ns}' did not reach Succeeded within ${timeout}s."
}

# provision_db DB_NAME ROLE_NAME PASSWORD
# CREATE DATABASE cannot run inside a transaction or take IF NOT EXISTS, so
# it's generated conditionally and run with \gexec — identical pattern to
# scripts/setup-openmetadata.sh's database-provisioning step, just pointed
# at the plain-StatefulSet `postgres-0` pod instead of a CNPG primary.
provision_db() {
  local db="$1" role="$2" password="$3"
  step "Provisioning database '${db}' / role '${role}' in ${PG_POD} (idempotent)"
  oc exec -i -n "$NS" "$PG_POD" -c "$PG_CONTAINER" -- \
    psql -U "$PG_SUPERUSER" -d "$PG_SUPERDB" -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${role}') THEN
    CREATE ROLE ${role} LOGIN PASSWORD '${password}';
  ELSE
    ALTER ROLE ${role} LOGIN PASSWORD '${password}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${db} OWNER ${role}'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db}')\gexec
SQL
  printf '    database "%s" / role "%s" ready\n' "$db" "$role"
}

provision_prefect_db() { provision_db "$PREFECT_DB" "$PREFECT_ROLE" "$PREFECT_PASSWORD"; }
provision_openmetadata_db() { provision_db "$OPENMETADATA_DB" "$OPENMETADATA_ROLE" "$OPENMETADATA_PASSWORD"; }

# ─── 1. Operator readiness ───────────────────────────────────────────────────

wait_for_csv openshift-operators servicemeshoperator3
wait_for_csv openshift-keda openshift-custom-metrics-autoscaler-operator

# ─── 2. Mesh: namespaces, Istio control plane, IstioCNI ──────────────────────

step "Applying mesh namespaces (${MESH_SYSTEM_NS}, ${CNI_NS})"
oc apply -f "$SCRIPT_DIR/mesh/namespaces.yaml"

step "Applying the OSSM3/Sail Istio control-plane CR"
oc apply -f "$SCRIPT_DIR/mesh/istio.yaml"

step "Applying the IstioCNI CR"
oc apply -f "$SCRIPT_DIR/mesh/istio-cni.yaml"

step "Waiting for istiod"
# Sail's revisioned install may name this Deployment istiod-default on some
# OSSM3 versions rather than plain istiod (istio.yaml's `metadata.name:
# default` + updateStrategy.type: InPlace is the single-revision case this
# assumes) — confirm the live Deployment name if this wait fails.
oc rollout status deployment/istiod -n "$MESH_SYSTEM_NS" --timeout=5m

step "Waiting for the istio-cni-node DaemonSet"
oc rollout status daemonset/istio-cni-node -n "$CNI_NS" --timeout=5m

# ─── 3. Observability: otel-lgtm all-in-one ──────────────────────────────────

step "Applying observability (otel-lgtm all-in-one, traces only — DRA-011)"
oc apply -f "$SCRIPT_DIR/observability/lgtm-deployment.yaml"
oc apply -f "$SCRIPT_DIR/observability/lgtm-service.yaml"
oc apply -f "$SCRIPT_DIR/observability/lgtm-route.yaml"

step "Waiting for the lgtm rollout"
oc rollout status deployment/lgtm -n "$NS" --timeout=5m

# ─── 4. Re-deploy the app tier meshed + traced ───────────────────────────────

step "One-time: recreating order-service so its new pod picks up the mesh label"
# Not strictly required by a selector change (app-deployment.yaml only adds
# `istio.io/rev`/`version` to the pod TEMPLATE, never to the Deployment's
# `spec.selector`, which stays immutable and untouched) — a plain rolling
# update would pick up the new template on its own. Kept anyway for
# operational parity with the verified minikube flow (scripts/setup-istio.sh)
# and as a defensive no-surprises step before the meshed helm upgrade below.
oc delete deploy order-service -n "$NS" --ignore-not-found

step "helm upgrade: enabling mesh.enabled + observability.otlp.enabled"
helm upgrade --install datamesh "$HELM_CHART" \
  --namespace "$NS" \
  --set mesh.enabled=true \
  --set observability.otlp.enabled=true

step "Waiting for the 7 app Deployments to roll out meshed"
for svc in "${APP_SERVICES[@]}"; do
  oc rollout status "deploy/${svc}" -n "$NS" --timeout=5m
done

# ─── 5. mTLS + mesh tracing (apply only after the green rollout above) ──────

step "Applying PeerAuthentication (STRICT mTLS) + Telemetry (OTEL tracing)"
oc apply -f "$SCRIPT_DIR/mesh/peer-authentication.yaml"
oc apply -f "$SCRIPT_DIR/mesh/telemetry.yaml"

# ─── 6. order-service v1/v2 canary ───────────────────────────────────────────

step "Applying the order-service v2 canary"
oc apply -f "$SCRIPT_DIR/mesh/order-service-v2.yaml"
oc rollout status deploy/order-service-v2 -n "$NS" --timeout=5m

step "Applying canary routing (Gateway/VirtualService/DestinationRule) + ingress Route"
oc apply -f "$SCRIPT_DIR/mesh/routing.yaml"
oc apply -f "$SCRIPT_DIR/mesh/ingress-route.yaml"

# ─── 7. Provision the Prefect + OpenMetadata databases ──────────────────────
# These two sub-tiers (platform/prefect/, platform/openmetadata/) reuse the
# core `postgres` StatefulSet as their backend rather than standing up their
# own databases, same pattern as scripts/setup-openmetadata.sh on minikube.
# Provisioning the databases is this script's job (it already owns the core
# Postgres pod); applying the Prefect/OpenMetadata Helm releases themselves
# is NOT — see the next section.

provision_prefect_db
provision_openmetadata_db

# ─── keda / prefect / openmetadata (NOT applied by this script) ────────────
# These three sub-tiers are authored and applied independently, each from
# its own directory:
#   platform/keda/          — ScaledObjects etc. for the Custom Metrics
#                              Autoscaler operator this script already
#                              waited on (step 1).
#   platform/prefect/       — Prefect server + worker, backed by the
#                              "prefect" database provisioned above.
#   platform/openmetadata/  — OpenMetadata + OpenSearch, backed by the
#                              "openmetadata" database provisioned above.
# Apply each with its own install script / manifests once authored, e.g.:
#   oc apply -k platform/keda/
#   ./platform/prefect/install-prefect.sh
#   ./platform/openmetadata/install-openmetadata.sh
# (exact entry points are that tier's own decision, not this script's).

printf '\n==> Platform mesh + observability layer applied.\n'
printf 'Reach Grafana:        oc get route lgtm-grafana -n %s -o jsonpath="{.spec.host}"\n' "$NS"
printf 'Reach the canary:     oc get route order-service-canary -n %s -o jsonpath="{.spec.host}"\n' "$MESH_SYSTEM_NS"
printf 'Shift the canary split by editing the weights in mesh/routing.yaml and re-applying.\n'
