---
title: "Decisions"
render_with_liquid: false
---

# Decisions

This is the active decision log for the data-mesh reference architecture as
a standalone repo. Each significant architectural or editorial choice gets a
numbered entry below, with rationale and rejected alternatives.

The historical decisions from the project's earlier life as the §17 capstone
of `patterncatalyst/minikube-on-fedora` are preserved in
`_plans/archive/capstone-decisions.md`. New decisions specific to this
repo's standalone life start from DRA-001 below to avoid number-collisions
with the archive's CAP-NNN series.

---

## DRA-001 — Extract the data-mesh reference as its own repo

**Status:** decided; this commit is the materialization.

**Context.** The data-mesh reference originally lived as §17 of the
`patterncatalyst/minikube-on-fedora` tutorial. Over the course of the
project (CAP-001 through CAP-047 in the archived decision log), it grew
into a substantial standalone artifact: nine reading-set pages, a complete
runnable example tree, two presentations, and a comprehensive diagram set.
The §17-of-a-bigger-tutorial framing started to limit it — readers who
wanted just the data mesh had to navigate from a Minikube-on-Fedora landing
page, and the build's audience (people thinking about data mesh, not
specifically people learning minikube) was a mismatch with the parent
project's title.

**Decision.** Fork the data-mesh content into its own repo:
`patterncatalyst/datamesh-reference-arch-python`. The capstone-era pages
become this repo's primary content collection. The runnable example tree
moves to `examples/lgtm-datamesh/`. Presentations and assets come along.
The historical decision log lives at `_plans/archive/capstone-decisions.md`
as the audit trail of how the implementation was built.

**Consequences.**

- The new repo's `_docs/` collection is the data mesh; URLs are
  `/docs/01-concepts/` rather than `/capstone/data-mesh/01-concepts/`.
- The new repo's `index.html` is the data-mesh hero page (formerly
  `capstone/data-mesh.html` in the parent repo).
- The `lgtm-datamesh` rename of the example tree (formerly `17-capstone`)
  disambiguates it from the parent repo's `17-capstone` example, which
  still exists for readers who arrive via the minikube tutorial.
- New decisions in this repo are tracked here with `DRA-NNN` numbering;
  the `CAP-NNN` series is closed.

---

## DRA-002 — A dedicated `openshift/helm/datamesh` chart, not the umbrella chart + OLM operators

**Status:** decided; implemented at `examples/lgtm-datamesh/openshift/helm/datamesh/`.

**Context.** The minikube path this capstone uses elsewhere in the reading set
(Chapter 3) ships one umbrella Helm chart built around plain-Kubernetes
assumptions — pinned `runAsUser` values, NodePort exposure, an external local
registry. OpenShift's SCC, Route, and registry model (documented in this
appendix's "What changes" section) is incompatible with several of those
assumptions throughout the chart, not in one or two isolated spots.

**Decision.** Author a second, dedicated chart,
`openshift/helm/datamesh/`, scoped to the live core (seven services, Postgres,
Kafka, Apicurio) and built from the start around `restricted-v2`/`nonroot-v2`,
Routes, and the integrated registry — mirroring the equivalent appendix and
chart structure in the `modernizing-enterprise-applications` repo rather than
inventing a different shape for the same problem.

**Rejected alternative.** Retrofit the umbrella chart in place with
OpenShift-only overlays and OLM-installed operators (CNPG/Strimzi) standing in
for the plain StatefulSets — rejected because the retrofit would touch nearly
every template (every Deployment's `securityContext`, every Service exposure
pattern, every image reference) for a platform the umbrella chart was never
designed around, while a second dedicated chart keeps the minikube path
unchanged for readers who never touch OpenShift.

**Consequences.**

- Two charts now exist for the same seven-service system; `values.yaml`
  divergence between them is intentional and should not be "fixed" by merging.
- The OpenShift chart's `Chart.yaml` explicitly scopes out OpenMetadata,
  Prefect, LGTM, KEDA, and Istio — see DRA-006.

---

## DRA-003 — Postgres and Kafka as plain StatefulSets under `datamesh-infra`/`nonroot-v2`, not CNPG/Strimzi

**Status:** decided; implemented at `templates/postgres.yaml`,
`templates/kafka.yaml`, `templates/serviceaccount-infra.yaml`.

**Context.** The presentation deck at `presentation/data-mesh-openshift/`
speaks in terms of the operator-managed path — CNPG for Postgres, AMQ
Streams/Strimzi for Kafka — which is the production-grade OpenShift answer.
But this chart targets a bare CRC instance with nothing pre-installed beyond
OpenShift itself, and a 20 GB CRC budget (DRA-006) has little headroom for two
additional operators' control-plane pods on top of the live core.

**Decision.** Ship Postgres and Kafka as plain StatefulSets, run under a
dedicated `datamesh-infra` ServiceAccount bound to the `nonroot-v2` SCC via a
RoleBinding to the cluster-generated `system:openshift:scc:nonroot-v2`
ClusterRole, with `runAsUser: 70` (Postgres) and `runAsUser: 1000` (Kafka)
pinned explicitly.

**Rejected alternative.** Install CloudNativePG and Strimzi via OperatorHub/OLM
and depend on their CRs — rejected for this appendix because it would require
every reader to install two more operators before `helm install` even starts,
contradicting the "no other external dependencies" promise in the
prerequisites, and because the decked operator path remains documented
separately as the production recommendation.

**Consequences.**

- This chart's Postgres/Kafka are not HA and have no operator-managed
  backup/rotation story — acceptable for a local reference, not for production.
- The deck's CNPG/Strimzi vocabulary and this chart's plain-StatefulSet
  implementation now intentionally diverge; readers moving from deck to chart
  should expect that gap and not read it as an inconsistency.

---

## DRA-004 — App pods drop `runAsUser`; `restricted-v2` assigns the UID

**Status:** decided; implemented at `templates/app-deployment.yaml`.

**Context.** The seven Python services' Containerfiles declare `USER 1001:0`
for plain-Kubernetes deployment, where that UID is pinned directly in the
Deployment spec. OpenShift's default SCC, `restricted-v2`, rejects any pod
whose spec demands a specific `runAsUser` rather than letting the SCC assign
one from the namespace's allocated range.

**Decision.** For the seven app Deployments, set `runAsNonRoot: true` only —
no `runAsUser` key anywhere in the pod's `securityContext` — so
`restricted-v2` assigns the UID, confirmed live as `1000650000` for all seven.

**Rejected alternative.** Keep `runAsUser: 1001` pinned, matching the
Containerfile's `USER` directive exactly as the minikube chart does — rejected
because it simply does not admit under `restricted-v2`; the images are already
built group-`0`-readable/writable for the express purpose of running under
whatever UID the platform assigns, so pinning one gains nothing and breaks
admission.

**Consequences.**

- Postgres and Kafka are the deliberate exception (DRA-003): their upstream
  images own fixed UIDs on disk, so they pin `runAsUser` under `nonroot-v2`
  instead of taking an assigned one.
- A reader porting a service from the minikube chart to the OpenShift chart
  must drop any pinned `runAsUser` as part of that port, not just change the
  image reference.

---

## DRA-005 — Routes and the internal registry, not NodePort/external registry

**Status:** decided; implemented at `templates/route.yaml`,
`templates/apicurio.yaml` (Route block), and `openshift/build-and-push.sh`.

**Context.** The minikube path reaches services over NodePorts published
to `127.0.0.1` at profile creation (DRA-017), because minikube has no
cluster-native router or easy-to-reach internal registry. OpenShift ships both: a Route object with a
real external hostname served by the cluster router, and an integrated image
registry addressed in-cluster at
`image-registry.openshift-image-registry.svc:5000`.

**Decision.** Expose `graphql-gateway` and `apicurio` via edge-TLS Routes
(`edge/Redirect`) and nothing else; build and push all nine images to the
integrated registry via `build-and-push.sh`, authenticated with an
`oc whoami -t` token rather than any external registry account.

**Rejected alternative.** Reproduce the minikube published-NodePort
pattern on OpenShift — rejected because it ignores two capabilities the
platform already provides natively, adds a host-port publishing step
OpenShift doesn't need, and would require readers to manage external registry
credentials for images that never need to leave the cluster.

**Consequences.**

- Every other in-cluster service stays `ClusterIP`-only with no Route, exactly
  as it would on minikube without a NodePort — the Route surface is
  deliberately minimal.
- `build-and-push.sh` needs the registry's default Route exposed
  (`defaultRoute: true` on the image-registry operator config) purely for the
  host-side `podman push`; in-cluster image pulls never traverse that Route.

---

## DRA-006 — Core-vs-document-only tiering to fit the 20 GB CRC budget

**Status:** decided; recorded in `Chart.yaml` and this appendix's
"document-only counterparts" section.

**Context.** The full minikube stack this capstone documents elsewhere
includes the live core (seven services, Postgres, Kafka, Apicurio) plus
OpenMetadata, Prefect, the full LGTM observability stack, KEDA, and Istio.
Sizing a single CRC instance to run all of that concurrently with OpenShift's
own control plane would require far more than a laptop reasonably offers.

**Decision.** This chart ships only the live core. OpenMetadata, Prefect,
LGTM, KEDA, and Istio are documented as OpenShift-native counterparts
(OpenShift Service Mesh, Custom Metrics Autoscaler, cluster/user-workload
monitoring, same OpenMetadata Deployment resized) rather than applied, with
the reasoning stated in both `Chart.yaml` and the appendix narrative.

**Rejected alternative.** Size CRC well past the documented 20 GB / 8 vCPU / 80
GB footprint to run everything concurrently — rejected as a reference-quality
decision because it would turn "runnable on a laptop" into "requires a
workstation-class host," defeating the point of using CRC at all for this
appendix.

**Consequences.**

- A reader who wants the full stack on OpenShift has a documented starting
  point for each of the four document-only layers, but none of them were
  applied or verified against the live cluster for this appendix.
- Future chapters adding to the document-only tier should keep the same
  "document the OpenShift-native counterpart, don't apply it" pattern rather
  than silently growing the verified chart's footprint.

---

## DRA-007 — Grow the CRC disk to 80 GB

**Status:** decided; implemented in this appendix's prerequisites
(`crc config set disk-size 80`).

**Context.** The live-apply run against CRC's default ~32 GB disk hit
`DiskPressure` (27 GB used) once the nine images for this chart (seven app
images plus the mirrored `postgres`/`kafka` infra images) were pushed into the
integrated registry, whose storage lives on the node's own disk. Every pod
sat `Pending` behind a `node.kubernetes.io/disk-pressure:NoSchedule` taint
until the disk was grown and the instance restarted.

**Decision.** Set `crc config set disk-size 80` alongside the existing memory
and CPU bumps, before the first `crc start` — CRC can only grow disk size
while the instance is stopped, so this has to be a prerequisites-stage step,
not a live-apply remediation.

**Rejected alternative.** Keep the default disk size and instruct readers to
prune unused images/build caches to stay under the DiskPressure threshold —
rejected because it trades a one-time host-sizing command for an ongoing
manual-maintenance burden, and because the registry alone (not build caches)
accounts for the overage, so pruning caches wouldn't reliably prevent a recurrence.

**Consequences.**

- The prerequisites section's host-sizing step now sets memory, CPU, and disk
  together, matching how this appendix was actually run end to end.
- The disk-pressure taint and its fix are also documented in "What broke on
  live apply" as a learning, not just folded silently into the prerequisites,
  so a reader who hits it mid-deploy (e.g. on a cluster set up before this
  decision) can self-diagnose from the symptom.

---

## DRA-008 — Resize CRC to 32 GB / 14 vCPU / 100 GB for the platform tier

**Status:** decided; supersedes DRA-007's disk-only bump.

**Context.** DRA-006/DRA-007 sized CRC for the **live core only**: 7 app
services, Postgres, Kafka, Apicurio, at 16 GB memory / 6 vCPU / 80 GB disk.
This appendix adds a full platform tier on top of that core — the OSSM3
(Sail) Istio control plane plus a per-pod Envoy sidecar on all 7 services
and the order-service canary, the otel-lgtm all-in-one observability
backend, the Custom Metrics Autoscaler (KEDA) controller, and (via the
concurrently-authored `platform/prefect/` and `platform/openmetadata/`)
a Prefect server+worker and an OpenMetadata+OpenSearch stack — none of
which existed when DRA-006/007 set their budget. Sidecars alone add a
non-trivial fixed memory/CPU cost per pod across 8+ meshed workloads, and
OpenSearch (OpenMetadata's backing store) is itself one of the heavier
single components in the whole stack.

**Decision.** Resize the CRC instance to `crc config set memory 32768`,
`crc config set cpus 14`, `crc config set disk-size 100` before first
`crc start` of this appendix — one combined host-sizing step, matching how
DRA-007 already treats disk sizing as a stop-the-instance, prerequisites-stage
command.

**Rejected alternative.** Keep DRA-007's 16 GB/6 vCPU/80 GB footprint and
try to fit the platform tier into it by trimming replica counts or
resource requests further — rejected because the live core's own pods
(DRA-003's Postgres/Kafka StatefulSets, the 7 app Deployments) already sit
near their documented floor, and the mesh sidecars' and OpenSearch's
resource needs are fixed costs of the components themselves, not knobs this
appendix controls.

**Consequences.**

- This is now a bigger ask than "runs on a laptop" (DRA-006's original
  framing) — readers following the platform-tier appendix need a
  workstation-class host or a laptop with headroom well past the live-core
  prerequisites.
- The live-core-only deploy (DRA-002..007) is unaffected: a reader who never
  applies `openshift/platform/` can stay on the smaller 16/6/80 footprint.

---

## DRA-009 — `openshift/platform/` tree + default-OFF chart flags, not a second chart

**Status:** decided; implemented at `openshift/platform/mesh/`,
`openshift/platform/observability/`, `openshift/helm/datamesh/values.yaml`
(`mesh.enabled`, `observability.otlp.enabled`), and
`openshift/platform/install-platform.sh`.

**Context.** DRA-006 drew a hard line: the verified `openshift/helm/datamesh`
chart ships the live core only, and Istio/LGTM/KEDA/Prefect/OpenMetadata are
"document-only appendix material." This appendix needs to actually apply
the mesh and observability layers (and, via a second concurrently-authored
set of directories, KEDA/Prefect/OpenMetadata) against the same verified
core, without regressing DRA-006's guarantee that a plain
`helm install datamesh` still renders the exact live-core-only chart a
reader following the base README gets today.

**Decision.** Add the platform layer as plain Kubernetes manifests under a
new `openshift/platform/{mesh,observability,keda,prefect,openmetadata}/`
tree (parallel to the already-existing `openshift/platform/subscriptions/`),
applied by its own `install-platform.sh` orchestrator — and add exactly two
new chart knobs, both defaulting OFF: `mesh.enabled` (adds the
`istio.io/rev` pod-template label + the order-service `version: v1` label)
and `observability.otlp.enabled` (adds the five `OTEL_*` env vars). Neither
flag changes the chart's rendered output when left at its default, verified
by `helm template` before/after diffing to nothing.

**Rejected alternative 1.** Fork a third Helm chart
(`openshift/helm/datamesh-meshed/`) that always renders with mesh+OTLP on —
rejected because it would duplicate the entire 7-service
`app-deployment.yaml` template for a two-label, five-env-var delta, and
would immediately diverge from the verified chart on every future core
change.

**Rejected alternative 2.** Bake the mesh label and OTEL env into the core
chart unconditionally (always on) — rejected because it breaks DRA-006's
explicit scope line on a cluster where Istio/otel-lgtm aren't applied: an
unmeshed pod carrying `istio.io/rev` does nothing harmful, but OTEL env
pointed at a nonexistent `lgtm` Service would make every app container's
`opentelemetry-instrument` entrypoint retry/fail its exporter on an
unreachable endpoint for readers who only want the live core.

**Consequences.**

- `openshift/helm/datamesh/Chart.yaml`'s "OUT of scope" language is now only
  true for a default install — a reader applying `openshift/platform/` on
  top opts into the Istio/LGTM counterparts described there. Chart.yaml's
  wording was deliberately left unedited in this pass (not part of this
  appendix's file list); a later doc pass should reconcile it rather than
  leave it silently stale.
- `install-platform.sh`'s one-time `oc delete deploy order-service` step
  runs before every meshed `helm upgrade`, mirroring the minikube
  `scripts/setup-istio.sh` canary-enablement flow, even though (unlike that
  flow) this chart's Deployment selector never changes — see the script's
  inline comment for why it's kept anyway.

---

## DRA-010 — OSSM3/Sail `Istio` CR with pod-LABEL injection + IstioCNI

**Status:** decided; implemented at `openshift/platform/mesh/istio.yaml`,
`istio-cni.yaml`, `namespaces.yaml`, and the `istio.io/rev` label in
`openshift/helm/datamesh/templates/app-deployment.yaml`.

**Context.** The two prior Istio integrations in this project's history used
different injection mechanisms: the minikube canary
(`examples/lgtm-datamesh/scripts/setup-istio.sh`) labels the whole namespace
`istio-injection=enabled` (classic istioctl-profile injection), while the
`istio/order-service-v2.yaml` overlay instead sets the pod ANNOTATION
`sidecar.istio.io/inject: "true"`. OSSM3 — the Red Hat operator this
project's subscriptions already install (`servicemeshoperator3`, Sail-based)
— manages Istio as a revisioned control plane via a `sailoperator.io/v1
Istio` CR, and Sail's injection webhook is revision-aware: it selects pods
by the `istio.io/rev` (or `istio-injection`) pod LABEL, not by the legacy
`sidecar.istio.io/inject` annotation alone. Separately, OpenShift's default
`restricted-v2` SCC (DRA-004) blocks the classic istio-init
NET_ADMIN/NET_RAW init container every non-CNI Istio install relies on to
redirect pod traffic into the sidecar.

**Decision.** Use the Sail `Istio` CR (`spec.updateStrategy.type: InPlace`,
single `default` revision) and set `mesh.enabled`'s pod-template LABEL
`istio.io/rev: {{ .Values.mesh.revision }}` (default `"default"`) on all 7
app Deployments plus the order-service canary — a LABEL, never the
`sidecar.istio.io/inject` annotation the minikube overlay used, because that
annotation alone does not reliably trigger Sail's revisioned webhook. Pair
it with a separate `sailoperator.io/v1 IstioCNI` CR (`istio-cni.yaml`) so
pod-traffic redirection happens from a privileged DaemonSet outside the app
pods' SCC, keeping every meshed app pod on `restricted-v2` with no elevated
capabilities of its own.

**Rejected alternative.** Reuse the minikube pattern verbatim — namespace-level
`istio-injection=enabled` label or per-pod `sidecar.istio.io/inject`
annotation, with the classic istio-init approach to traffic redirection —
rejected because the first targets non-revisioned (istioctl/IstioOperator)
installs that OSSM3/Sail doesn't use the same way, the second is an
annotation where Sail's revisioned webhook expects a label, and the
istio-init approach's NET_ADMIN requirement does not admit under
`restricted-v2` at all.

**Consequences.**

- `openshift/platform/mesh/istio.yaml`'s `spec.version` is left as a comment
  placeholder (`# version: v1.NN-NNN ...`), not a real value — it must be
  filled from a live `oc get packagemanifest servicemeshoperator3` /
  `oc explain istio.spec.version` check against the actual installed
  channel, which this authoring-only pass had no cluster access to confirm.
- `openshift/platform/mesh/ingress-route.yaml`'s target Service name
  (`istio-ingressgateway`) and port name (`http2`) are likewise unconfirmed
  live placeholders — Sail does not provision a default ingress gateway the
  way istioctl's `default` profile does, so whether/how one exists must be
  confirmed against the live cluster before the canary Route resolves.

---

## DRA-011 — otel-lgtm all-in-one; re-enable OTLP, traces only

**Status:** decided; implemented at `openshift/platform/observability/`,
`openshift/helm/datamesh/values.yaml` (`observability.otlp`), and the
`OTEL_*` env block in `templates/app-deployment.yaml`.

**Context.** The OpenShift README's "What changes" section (point 5) states
plainly that "tracing is off" for this chart — the OTEL_* env vars are
omitted because no LGTM stack is deployed. This appendix's platform tier
changes that: it deploys an observability backend and wants that
"tracing is off" default reversed, but a full split Loki+Grafana+Tempo+Mimir
deployment (the shape `charts/capstone/`'s minikube path and the
`modernizing-enterprise-applications` repo's earlier, pre-all-in-one history
both used in places) is more moving parts than this reference build's
platform tier needs, and the live core already runs un-instrumented — there
is no existing metrics pipeline this tier needs to preserve compatibility
with.

**Decision.** Deploy the single `docker.io/grafana/otel-lgtm` all-in-one
image (Collector + Tempo + Loki + Mimir + Grafana in one container, same
choice `modernizing-enterprise-applications/deploy/k8s/observability/`
already made) as one Deployment, and re-enable OTLP export from the app
containers scoped to **traces only**:
`OTEL_TRACES_SAMPLER=always_on` + `OTEL_METRICS_EXPORTER=none`. No
otelcol-configmap.yaml / grafana-datasources-configmap.yaml is mounted —
the image's built-in default Collector config and built-in default Grafana
datasources already do everything a traces-only pipeline needs; the
modernization source's one addition over those defaults (a
`prometheus/istio-mesh` scrape config, plus the `lgtm` ServiceAccount/RBAC
it requires for Kubernetes service-discovery) is metrics-only and out of
scope here.

**Rejected alternative 1.** Port the modernization source's
otelcol-configmap.yaml / grafana-datasources-configmap.yaml verbatim,
including the Istio mesh-metrics Prometheus scrape — rejected as scope
creep: this decision re-enables tracing, not mesh metrics, and the extra
ServiceAccount/ClusterRole/ClusterRoleBinding the scrape config needs would
be unused infrastructure against a traces-only goal.

**Rejected alternative 2.** Re-enable full OTLP (traces + metrics + logs)
rather than traces only — rejected to keep load off a single-replica,
1Gi/2Gi-bounded backend (DRA-008's resize already accounts for Istio
sidecars and OpenSearch; adding unbounded per-service metrics volume on top
wasn't budgeted) and because no consumer of those metrics (dashboards,
alerts) exists yet in this build to justify the cost.

**Consequences.**

- `OTEL_METRICS_EXPORTER=none` means Mimir inside the all-in-one image
  receives nothing from the app tier; only Istio's own trace spans
  (`../mesh/istio.yaml`'s `otel` extensionProvider) and the apps' trace
  spans land in Tempo. A future iteration that wants mesh/app metrics needs
  to revisit this decision's otelcol-configmap rejection, not just flip an
  env var.
- The observability backend itself is deliberately left unmeshed (no
  `istio.io/rev` label on the `lgtm` Deployment) — same reasoning as
  Postgres/Kafka/Apicurio: it's the destination for mesh+app telemetry, not
  a participant being observed.

---

## DRA-012 — KEDA via the Custom Metrics Autoscaler; Kafka-lag ScaledObject only, HTTP add-on dropped

**Status:** decided; implemented at `openshift/platform/keda/`.

**Context.** The minikube capstone scales two workloads with KEDA: core
KEDA's Kafka-lag trigger scales `notification-service` on consumer-group
backlog, and the separate `kedacore/keda-add-ons-http` Helm chart scales
`graphql-gateway` on in-flight HTTP request concurrency, including from
zero (`examples/lgtm-datamesh/keda/{notification-scaledobject,gateway-httpscaledobject}.yaml`,
`scripts/setup-keda.sh`). OpenShift's supported path is the Custom Metrics
Autoscaler (CMA) operator — Red Hat's packaged KEDA distribution, already
subscribed via `openshift/platform/subscriptions/cma-subscription.yaml` —
which installs and lifecycle-manages **core KEDA only**.

**Decision.** Author a `KedaController` operand (`kedacontroller.yaml`) and
port only the Kafka consumer-lag `ScaledObject` for `notification-service`
(`notification-scaledobject.yaml`) — same KEDA API (`keda.sh/v1alpha1`,
unchanged across the upstream/CMA distributions), retargeted to the
`datamesh` namespace and this chart's plain-StatefulSet Kafka Service
(`kafka.datamesh.svc.cluster.local:9092`, confirmed in
`openshift/helm/datamesh/templates/kafka.yaml`), consumer group
`notification-service` and topic `order-placed` (both confirmed in
`services/notification-service/app/config.py` and restated in
`openshift/helm/datamesh/templates/configmap-app.yaml`). The
`graphql-gateway` HTTP-request autoscaling is **not** reimplemented.

**Rejected alternative.** Install the upstream `kedacore/keda-add-ons-http`
Helm chart alongside the CMA operand to recreate the gateway's HTTP scaling
— rejected because the add-on is an independent, unmanaged Helm release
installing its own CRDs/interceptor on top of an operator-owned KEDA
controller lifecycle; running both against the same cluster risks the two
installs fighting over the same `ScaledObject`/webhook surface, and CMA's
supportability guarantee only covers what the operator itself ships.

**Consequences.**

- `graphql-gateway` has no scale-to-zero-on-HTTP-traffic behavior on
  OpenShift; it runs at whatever replica count the core chart sets
  (`orderService`/etc. `scaling:` values in the minikube chart don't apply
  here — this chart doesn't template per-service KEDA scaling at all).
- `openshift/platform/keda/README.md` documents a Prometheus-trigger
  alternative (core KEDA, no add-on) as a future option if OpenShift
  user-workload monitoring is enabled — not implemented here, since it
  can't replicate the add-on's cold-start request-holding behavior and so
  isn't a drop-in replacement.

---

## DRA-013 — Prefect reuses the core Postgres (separate database + dedicated role), not a bundled Postgres

**Status:** decided; implemented at `openshift/platform/prefect/`.

**Context.** Prefect 3.x OSS needs a Postgres backend for flow/task-run
state. The minikube capstone's `charts/capstone/values.yaml` `prefect` block
already documents the same choice there ("shares the capstone-postgres
cluster, separate database"), rather than bundling Prefect's own Postgres
instance — consistent with this chart's existing DRA-003 stance of one
shared Postgres per cluster.

**Decision.** Point the Prefect server at the core `postgres` StatefulSet
Service (`postgres.datamesh.svc.cluster.local:5432`) with a dedicated
`prefect` database and a dedicated `prefect` login role — both provisioned
by `../install-platform.sh`'s `provision_prefect_db` (SQL against the
`postgres-0` pod, confirmed by reading that script: `PREFECT_DB=PREFECT_ROLE=
"prefect"`, `PREFECT_PASSWORD="prefect"`, a hardcoded demo value). Since that
script only does the SQL-side provisioning and creates no Kubernetes Secret,
`platform/prefect/postgres-credentials-secret.yaml` republishes the same
literal demo password as a Secret (`prefect-postgres-app`) the server
Deployment reads via `secretKeyRef`, assembling the asyncpg connection URL
through Kubernetes' `$(VAR_NAME)` env-interpolation so the credential never
appears as a literal in the Deployment manifest itself.

**Rejected alternative 1.** Bundle a second Postgres instance (its own
StatefulSet) dedicated to Prefect — rejected as the same unnecessary
resource duplication DRA-003 already rejected for the app services
themselves; one Postgres instance with a schema/database-per-consumer
pattern is this reference's established convention.

**Rejected alternative 2.** Reuse the shared `capstone_app` role (the
`datamesh-postgres-app` Secret) for Prefect's database instead of a
dedicated role — rejected because `../install-platform.sh` (authored
concurrently, owned by a different authoring step) already provisions a
dedicated `prefect` role scoped to only the `prefect` database; matching
that ground truth — confirmed by reading the script directly rather than
assuming the brief's original "reuse the core app secret" framing — avoids
authoring a manifest that references credentials which don't actually exist
on a live cluster.

**Consequences.**

- Two literal demo passwords now exist in git for this platform tier (the
  `prefect` role's, republished in `postgres-credentials-secret.yaml`, and
  DRA-014's `openmetadata` role's, below) — acceptable for this reference
  build's existing "DEMO password, not production" posture (same as
  `datamesh-postgres-app`), but both must be rotated together with
  `install-platform.sh`'s hardcoded values if this ever moves past a demo.
- `example-flow-configmap.yaml`'s proof-of-life flow validates the
  server+worker+Postgres wiring end-to-end without needing any app-tier
  change — Prefect is additive to the verified core, not a dependency of it.

---

## DRA-014 — OpenMetadata: single-node OpenSearch + anyuid ServiceAccount, best-effort/unverified

**Status:** decided; implemented at `openshift/platform/openmetadata/`;
**not applied to a live cluster** — authored offline, same posture as
DRA-010's Istio placeholders.

**Context.** The minikube capstone's OpenMetadata deploy (CAP-022,
`examples/lgtm-datamesh/openmetadata/`, `scripts/setup-openmetadata.sh`)
already established the shape this chart ports: MySQL and Airflow disabled,
a single-node Bitnami OpenSearch for search, Postgres reused as the backend
database via a dedicated `openmetadata` role, and a placeholder
`airflow-secrets` Secret working around the chart's unconditional
`AIRFLOW_PASSWORD` env var. OpenShift adds two platform-specific
obstacles that minikube's plain Kubernetes doesn't: the Bitnami OpenSearch
image's fixed UID doesn't admit under `restricted-v2`, and that image's
privileged sysctl initContainer (for raising `vm.max_map_count`) doesn't
admit under any SCC short of `privileged`.

**Decision.** Port the dependencies/server Helm values
(`om-deps-values.yaml`/`om-app-values.yaml`) with the backend retargeted to
this chart's plain-StatefulSet Postgres Service
(`postgres.datamesh.svc.cluster.local`) and a dedicated `openmetadata`
database + login role — both provisioned by `../install-platform.sh`'s
`provision_openmetadata_db` (confirmed by reading that script:
`OPENMETADATA_DB=OPENMETADATA_ROLE="openmetadata"`,
`OPENMETADATA_PASSWORD="openmetadata"`), with the matching Kubernetes Secret
(`openmetadata-db-app-secret`, since that script doesn't create one)
authored alongside it as `postgres-credentials-secret.yaml`. Grant the
OpenSearch sub-release's pods `system:openshift:scc:anyuid` via a dedicated
`openmetadata-opensearch` ServiceAccount (`opensearch-scc.yaml`) and disable
the sysctl initContainer in `om-deps-values.yaml`, relying on single-node
OpenSearch's documented non-fatal handling of a low `vm.max_map_count`
rather than raising the host kernel setting.

**Rejected alternative.** Raise `vm.max_map_count` cluster-wide via a
`Tuned` CR as the primary fix, rather than disabling the sysctl
initContainer and relying on single-node's non-fatal fallback — rejected as
the primary approach because it's a cluster-admin, node-level change this
authoring step has no way to apply or verify, and because the chart's own
single-node mode is documented not to need it; the `Tuned` CR is kept as a
**documented fallback only** (`openshift/platform/openmetadata/README.md`)
if OpenSearch still crashloops on the live cluster.

**Consequences.**

- This is explicitly the highest-risk, least-verified directory in this
  authoring pass — none of `om-deps-values.yaml`'s `opensearch.sysctlImage.enabled`
  / `opensearch.sysctl.enabled` keys, `opensearch.serviceAccount.*` keys, or
  the OpenSearch single-node non-fatal-`vm.max_map_count` behavior itself
  were confirmed against the actual pulled chart version (1.12.8) — all
  flagged as VERIFY-POINTs in the file comments and
  `openshift/platform/openmetadata/README.md`, to be resolved the first time
  this is actually applied to a live CRC/OpenShift cluster.
- `ingestion-job.yaml` ingests the `capstone` app database using the
  existing `datamesh-postgres-app`/`capstone_app` credential — a
  deliberately different database and role than OpenMetadata's own backend
  database above, mirroring the minikube source's same separation (the
  catalog doesn't catalog itself).
- Three literal demo passwords now exist in git across this platform tier
  (`capstone_app`'s pre-existing one, DRA-013's `prefect`, and this
  decision's `openmetadata`) — see DRA-013's consequences for the shared
  rotation caveat.

---

## DRA-015 — Gateway-scoped `PERMISSIVE` `PeerAuthentication` exception under namespace `STRICT` mTLS

**Status:** decided; implemented at
`openshift/platform/mesh/peer-authentication.yaml`; confirmed live 2026-10-07
against the resized (32 GB/14 vCPU/100 GB) CRC instance.

**Context.** DRA-010 put the seven app Deployments behind Sail/OSSM3's
revisioned sidecar injection. Once a namespace-wide `PeerAuthentication`
named `default` was applied with `mtls.mode: STRICT` — the mTLS posture this
reference's minikube mesh chapter (`_docs/06-progressive-delivery-mtls.md`)
already teaches — the live cluster's `graphql-gateway` Route started
returning `502` from the
OpenShift router. The cause: the router is not a mesh participant and
delivers plain HTTP to the gateway's sidecar; `STRICT` mode rejects any
inbound connection that isn't mTLS, so the router's own plaintext request
never reached the gateway container at all. This is not a bug in the mesh or
the Route — it is `STRICT` doing exactly what it's supposed to do to a
connection with no client certificate.

**Decision.** Keep the namespace-wide `default` `PeerAuthentication` at
`STRICT` for every mesh-internal hop, and add a second, narrowly scoped
`PeerAuthentication` (`graphql-gateway-permissive`) selecting only
`app.kubernetes.io/name: graphql-gateway`, set to `PERMISSIVE`. `PERMISSIVE`
accepts both mTLS and plaintext on the same port, so the Route's plaintext
traffic is admitted while every other service-to-service call in the mesh —
including calls *to* `graphql-gateway` from inside the mesh — continues
negotiating mTLS as normal, since in-mesh callers still present a client
certificate `PERMISSIVE` is happy to accept.

**Rejected alternative.** Set the namespace default to `PERMISSIVE` instead
of `STRICT`, then tighten individual services — rejected because it inverts
the reference's established "secure by default, carve out named exceptions"
posture (this reference's minikube mTLS chapter already teaches `STRICT` as
the baseline) into "insecure by default, remember to lock down everything
else," which fails open for any future service the chart adds and nobody
remembers to re-tighten.

**Consequences.**

- This is the one piece of this appendix's mesh configuration that a reader
  is likely to hit as a visible failure (a 502 through the public Route)
  rather than a silent misconfiguration, so it's called out both in the
  manifest's own comments and in "The full platform tier, live" section of
  this appendix, not just left to be rediscovered.
- A production deployment would more likely front the mesh with an Istio
  ingress gateway and terminate mTLS there instead of carving out a
  per-service `PERMISSIVE` exception — noted as a comment in
  `peer-authentication.yaml` but not implemented, since OSSM3/Sail
  provisions no default ingress gateway (DRA-010) and standing one up was
  out of scope for this appendix.

---

## DRA-016 — otel-lgtm under `anyuid`: `runAsUser: 0` only, no `seccompProfile`/`capabilities`

**Status:** decided; implemented at
`openshift/platform/observability/lgtm-deployment.yaml`; confirmed live
2026-10-07.

**Context.** DRA-011 chose the `grafana/otel-lgtm` all-in-one image, whose
data directories are owned by UID 0, admitted via the `anyuid` SCC under a
dedicated `lgtm` ServiceAccount rather than `restricted-v2` (which rejects
root outright). While authoring the pod's `securityContext`, the
instinctive hardening move — adding `seccompProfile: { type: RuntimeDefault
}` and `capabilities: { drop: ["ALL"] }`, the same pattern
`app-deployment.yaml` already uses for the seven app pods under
`restricted-v2` — was tried first. Applied live, the pod did not fail to
admit loudly; it silently landed on `restricted-v2` instead of `anyuid`
(because `anyuid`'s allowed seccomp-profile list is empty, so a pod
requesting a non-empty one doesn't match that SCC and falls through to the
next one it does match), picked up a random UID there, and hung forever at
"Waiting for Grafana to start up..." because that UID couldn't write
`/data`. No SCC-denial event pointed at the cause — the pod looked like it
just failed to start.

**Decision.** Set only `runAsUser: 0` in the `lgtm` container's
`securityContext` — no `seccompProfile`, no `capabilities` block of any
kind — and document the omission inline in the manifest as deliberate, not
an oversight a later hardening pass should "fix."

**Rejected alternative.** Keep the hardened `securityContext`
(`seccompProfile`/`capabilities`) and instead grant a custom SCC that
permits both root *and* a restricted seccomp profile — rejected as
unnecessary complexity for a single, non-production observability backend:
`anyuid` already exists, is already subscribed on this cluster via
`openshift/platform/subscriptions/`, and the only thing standing between it
and admission was the extra hardening fields this decision removes.

**Consequences.**

- This is now the second "silent SCC fallback" lesson in this appendix,
  after DRA-004's loud-rejection case for `restricted-v2` — worth
  remembering that SCC admission can fail *quietly* into a worse-matching
  SCC rather than rejecting the pod outright, which is harder to debug from
  `oc describe pod` alone than a `CreateContainerConfigError`.
- Any future addition to `lgtm-deployment.yaml`'s `securityContext` should
  be tested against a live `oc get pod lgtm-... -o jsonpath='{.metadata.annotations.openshift\.io/scc}'`
  check before assuming it's harmless — the rendered YAML looks
  more secure with the extra fields, but the live SCC assignment is what
  actually determines whether Grafana can write its data directory.

---

## DRA-017 — Host access: NodePorts published on 127.0.0.1 at profile creation

**Status:** decided; implemented in `examples/lgtm-datamesh/demos/lib/endpoints.sh`,
`scripts/setup-capstone-profile.sh`, and `scripts/show-endpoints.sh`; enforced by
`scripts/forbidden-syntax.sh`.

**Context.** Host access to the capstone minikube cluster (profile `capstone`,
rootless podman) used SSH tunnels and `kubectl port-forward`. <!-- forbidden-ok -->
Both break or disconnect: a forwarded connection pins one pod and dies when it
is replaced, and a tunnel process drops when the cluster idles or is under <!-- forbidden-ok -->
load. The failures surfaced as flaky smokes and dead UIs, not as clear errors
(see the lessons-learned entry on pinned pods).

**Decision.** Every host-facing service is a fixed NodePort, and the profile
publishes each one to the host when it is created:
`minikube start -p capstone --ports=127.0.0.1:<hostPort>:<nodePort>,...`. The
host:nodePort pairs come from the single map in
`examples/lgtm-datamesh/demos/lib/endpoints.sh`. Host ports and URLs are
unchanged (Grafana stays at `http://127.0.0.1:3000`). Every pair carries the
`127.0.0.1:` prefix, because the bare form (`--ports=a:b`) binds `0.0.0.0` and <!-- forbidden-ok -->
exposes the cluster to the network. `./scripts/show-endpoints.sh` prints a
status table of what is published and reachable.

**Rejected alternatives.**

- Supervised SSH tunnels (a watchdog that restarts them) — rejected because it <!-- forbidden-ok -->
  keeps the moving part and adds a supervisor to maintain. <!-- forbidden-ok -->
- `kubectl port-forward` retry loops — rejected because they re-attach to one <!-- forbidden-ok -->
  pod at a time and still lose the connection between retries.
- `minikube tunnel` with `LoadBalancer` Services — rejected because it needs a <!-- forbidden-ok -->
  privileged long-running process and does not fit rootless podman.
- Bare `--ports=a:b` — rejected because it binds `0.0.0.0`. <!-- forbidden-ok -->
- Renumbering host ports to match nodePorts — rejected because every URL in
  the docs, site, deck, and demos would change for no gain.

**Consequences.**

- Published ports are fixed at creation. Adding a port means recreating the
  profile; `setup-capstone-profile.sh` refuses an older profile without the
  ports, and `./scripts/setup-capstone-profile.sh --replace` recreates it.
- `scripts/forbidden-syntax.sh` runs in CI and fails on tunnel and <!-- forbidden-ok -->
  port-forward wording, the retired helper names, and `--ports` values without <!-- forbidden-ok -->
  a `127.0.0.1:` prefix. A line that must mention them (stating the
  prohibition, or a historical lesson) carries the marker `forbidden-ok`.
- Workshops run in isolation: shut down CRC, other minikube profiles, and
  other workloads before starting, so the published host ports are free.
- `_plans/archive/` and `*.archive.md` are the historical record. They are
  unchanged, describe superseded host access, and are excluded from the gate.
