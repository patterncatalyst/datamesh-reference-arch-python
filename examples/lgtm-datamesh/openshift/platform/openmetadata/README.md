# OpenMetadata on OpenShift (best-effort)

This is the highest-risk authoring step in this batch: OpenSearch's fixed-UID
Bitnami image and its privileged sysctl init container are exactly the kind
of thing that behaves differently across OpenShift versions/SCC policy, and
none of this has been applied to a live cluster. Treat the VERIFY-POINTs
below as required reading before `helm upgrade --install`, not optional
footnotes.

## What's here

- `om-deps-values.yaml` — OpenMetadata dependencies chart override: OpenSearch
  single-node, MySQL disabled, Airflow disabled, plus the `openmetadata-opensearch`
  ServiceAccount wiring and a sysctl-initContainer VERIFY-POINT.
- `postgres-credentials-secret.yaml` — republishes the dedicated
  `openmetadata` login role's demo password (provisioned server-side by
  `../install-platform.sh`'s `provision_openmetadata_db`) as the
  `openmetadata-db-app-secret` Secret, since that script only does the
  SQL-side provisioning.
- `om-app-values.yaml` — OpenMetadata server chart override: Postgres backend
  pointed at the core datamesh Postgres (`postgres.datamesh.svc.cluster.local`,
  db `openmetadata`, role `openmetadata`, credentials from
  `openmetadata-db-app-secret` above), search pointed at the deps release's
  OpenSearch, Airflow/pipeline client disabled, exposed via ClusterIP (not
  NodePort).
- `opensearch-scc.yaml` — ServiceAccount + RoleBinding granting
  `system:openshift:scc:anyuid` so the Bitnami OpenSearch pod's fixed UID is
  permitted.
- `airflow-secrets.yaml` — placeholder Secret the chart's unconditional
  `AIRFLOW_PASSWORD` env var needs to exist (see the file's own comment); the
  value is never read since pipelines are disabled.
- `route.yaml` — edge Route to the server Service, port 8585.
- `ingestion-job.yaml` — ConfigMap + Job that ingests the `capstone` Postgres
  database's schemas (via the existing `datamesh-postgres-app` / `capstone_app`
  credential — a different database/role than OpenMetadata's own backend
  above), giving the catalog at least one asset.

## Prerequisites (owned by install-platform.sh / the other authoring step)

- The `openmetadata` database AND a dedicated `openmetadata` login role must
  already exist in the core Postgres — created by
  `../install-platform.sh`'s `provision_openmetadata_db` (confirmed by
  reading that script: `OPENMETADATA_DB=OPENMETADATA_ROLE="openmetadata"`,
  `OPENMETADATA_PASSWORD="openmetadata"`, a hardcoded demo value). This
  directory's own `postgres-credentials-secret.yaml` must carry the same
  password — update both if that script's password ever changes.
- Namespace `datamesh` and the `datamesh-postgres-app` Secret must already
  exist (they do — part of the verified core); `ingestion-job.yaml` uses that
  existing credential to read the `capstone` app database.

## Install order

```
oc apply -f opensearch-scc.yaml
oc apply -f airflow-secrets.yaml
oc apply -f postgres-credentials-secret.yaml

helm repo add open-metadata https://helm.open-metadata.org/
helm repo update open-metadata

helm upgrade --install openmetadata-dependencies open-metadata/openmetadata-dependencies \
  --namespace datamesh --version 1.12.8 \
  --values om-deps-values.yaml --wait --timeout 10m

# Wait for OpenSearch to actually come up healthy before installing the
# server — the server's startup probes hit the search backend and will
# crashloop-restart (not just wait) if OpenSearch isn't ready yet.
oc rollout status statefulset/openmetadata-dependencies-opensearch -n datamesh --timeout=10m
oc exec -n datamesh openmetadata-dependencies-opensearch-0 -- \
  curl -s localhost:9200/_cluster/health | grep -E '"status":"(green|yellow)"'

helm upgrade --install openmetadata open-metadata/openmetadata \
  --namespace datamesh --version 1.12.8 \
  --values om-app-values.yaml --wait --timeout 10m

oc apply -f route.yaml
oc rollout status deployment/openmetadata -n datamesh --timeout=10m

oc apply -f ingestion-job.yaml
oc wait --for=condition=complete job/om-ingest-postgres -n datamesh --timeout=5m
```

Reach the UI via the Route (`oc get route openmetadata -n datamesh`),
default login `admin@open-metadata.org` / `admin` — VERIFY-POINT: confirm
this default wasn't changed by the chart install before relying on it (the
ingestion Job also assumes it, via `OM_ADMIN_PASSWORD`).

## Known OpenShift risks

1. **OpenSearch UID / SCC.** The Bitnami OpenSearch image pins UID 1000.
   `restricted-v2` (the namespace default SCC) assigns a random UID and
   refuses a pod that insists on one — the pod will sit in
   `CreateContainerConfigError` or `Error` without `opensearch-scc.yaml`
   actually being referenced from `om-deps-values.yaml`'s
   `opensearch.serviceAccount.name`. Confirm the Bitnami OpenSearch subchart's
   actual ServiceAccount values key matches what's set there (`serviceAccount.create`/`serviceAccount.name`
   at the `opensearch:` block level) — it can drift between Bitnami chart
   releases.

2. **OpenSearch vm.max_map_count / sysctl initContainer.** Non-containerized
   OpenSearch nodes need the host kernel's `vm.max_map_count` raised to
   ~262144; the Bitnami chart normally does this via a privileged
   initContainer, which OpenShift's SCCs won't allow even with `anyuid`
   (that grant doesn't include `privileged` or `SYS_RESOURCE`). The chart's
   single-node mode is documented to treat a low `vm.max_map_count` as a
   non-fatal warning rather than refusing to start, so `om-deps-values.yaml`
   disables that initContainer. If OpenSearch still crashloops with a
   `max virtual memory areas vm.max_map_count is too low` error at startup
   (i.e. single-node mode does enforce it on the version that gets pulled),
   the fallback is a cluster-level `Tuned` CR setting
   `vm.max_map_count=262144` on the nodes that can schedule this pod —
   out of scope for this directory (cluster-admin, node-level change), but
   documented here so it isn't a mystery if OpenSearch won't start:

   ```yaml
   apiVersion: tuned.openshift.io/v1
   kind: Tuned
   metadata:
     name: openmetadata-opensearch-vm-max-map-count
     namespace: openshift-cluster-node-tuning-operator
   spec:
     profile:
       - name: openmetadata-opensearch-vm-max-map-count
         data: |
           [sysctl]
           vm.max_map_count=262144
     recommend:
       - match:
           - label: node-role.kubernetes.io/worker
         priority: 20
         profile: openmetadata-opensearch-vm-max-map-count
   ```

3. **Postgres TLS mismatch.** `om-app-values.yaml` sets `sslmode=disable`
   because this chart's plain `postgres:16-alpine` StatefulSet has no TLS
   listener (unlike the minikube source's CNPG cluster, which always presents
   a cert and needs `sslmode=require`). If the install uses a different
   Postgres than this chart's, re-check which is correct.

4. **Ingestion Job default-admin assumption.** `ingestion-job.yaml` logs in
   as `admin@open-metadata.org` / `admin` to get a bearer token — OpenMetadata's
   documented default install credential. If the server install rotates or
   disables this, the Job fails at the `get_token.py` step with a clear
   stderr message, not a silent no-op.
