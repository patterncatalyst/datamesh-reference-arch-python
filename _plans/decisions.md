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

**Context.** The minikube path reaches services over NodePort through a
stable SSH tunnel, because minikube has no cluster-native router or
easy-to-reach internal registry. OpenShift ships both: a Route object with a
real external hostname served by the cluster router, and an integrated image
registry addressed in-cluster at
`image-registry.openshift-image-registry.svc:5000`.

**Decision.** Expose `graphql-gateway` and `apicurio` via edge-TLS Routes
(`edge/Redirect`) and nothing else; build and push all nine images to the
integrated registry via `build-and-push.sh`, authenticated with an
`oc whoami -t` token rather than any external registry account.

**Rejected alternative.** Reproduce the minikube NodePort-plus-SSH-tunnel
pattern on OpenShift — rejected because it ignores two capabilities the
platform already provides natively, adds a tunnel-keep-alive dependency
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
