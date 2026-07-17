# datamesh-reference-arch-python

A working, runnable reference implementation of a **data mesh** in Python —
five domain services and a GraphQL gateway across REST, gRPC, GraphQL, and
Kafka, deployed via helm to Kubernetes, with versioned contracts, a data
catalog with cross-product lineage, progressive delivery through a service
mesh, event-driven autoscaling, and end-to-end observability. It fits on a
laptop while remaining recognisable as the same shape you'd run in
production.

The published site at
[patterncatalyst.github.io/datamesh-reference-arch-python](https://patterncatalyst.github.io/datamesh-reference-arch-python/)
is the reading set; the tree under `examples/lgtm-datamesh/` is the
runnable system it describes.

## What this is

Most data-mesh material is conceptual; this one is runnable. And most
runnable material is either too small to show the cross-product behavior
that defines a mesh, or too production-scaled to run on a single host.
This reference threads that gap: it takes Zhamak Dehghani's four
data-mesh principles and shows what each looks like as running pods,
YAML, and live traffic —

- **Domain ownership** — five domain services (order, inventory, payment,
  shipping, notification), each owning its own schema in an
  operator-managed Postgres, its own contract, and its own lifecycle.
- **Data as a product** — each service publishes a versioned, discoverable
  interface: OpenAPI for REST, Protobuf for gRPC, GraphQL SDL at the read
  surface, and Avro for events — all registered in a schema registry, all
  catalogued with ownership and lineage.
- **Self-serve platform** — the platform capabilities (mesh, autoscaling,
  observability, database and Kafka operators) are installed once and
  consumed by every product; adding a new data product to the mesh is a
  replayable, scripted workflow (`demo-add-data-product.sh`).
- **Federated computational governance** — the contracts registry and the
  catalog make the governance surfaces *computational*: schema
  compatibility is checked by the registry, and cross-product lineage is
  declared and queryable rather than tribal knowledge.

The reading set builds this up over ten pages — concepts, the Kubernetes
substrate, services and data products, contracts and the catalog, the data
planes, progressive delivery with mTLS, elasticity, observability,
anti-patterns, and a principle-by-principle summary.

## What it demonstrates

The system's headline behaviors, each runnable as a demo (they are the
five acts of `demos/walkthrough.sh`, plus the two phase demos):

1. **A trace across products** — one GraphQL query at the gateway fans out
   to order-service (REST) and inventory-service (gRPC), and all three
   spans land in Tempo stitched by a shared trace id. The mesh's
   interesting behavior lives *between* products; this makes it legible.
2. **Elastic data products** — KEDA scales notification-service on Kafka
   consumer lag (zero → up → zero: an event consumer runs only as much as
   its backlog warrants) and the GraphQL gateway on HTTP demand (scale to
   zero when idle, wake on the first request).
3. **Canary of a contract, not just a binary** — order-service evolves its
   API v1 → v2 (an additive `currency` field) and Istio shifts a
   controllable fraction of live traffic to the new contract version —
   90/10, then 50/50, then a clean rollback — with no flag-day break.
4. **Cross-product lineage** — OpenMetadata shows the operational spine
   (`orders` table → `order-placed` topic → `notifications` table) as
   declared, queryable lineage across three products' boundaries.
5. **Live mesh topology** — Kiali renders the running mesh graph with the
   canary split visible, backed by the same Prometheus the dashboards use.

Plus the two replayable workflow demos: **adding a data product to the
mesh** (deploy review-service → publish its contract → catalog it with
lineage → back it all out), and the **contract canary** as a
presenter-driven up/shift/down cycle.

Every claim is demo-tested: 20 `demo-*.sh` scripts cover each capability
end to end, verified order-independent (see
`_plans/reconciliation.md` for what's been cluster-verified and when).

## Tech stack

| Layer | Technology | Role |
|---|---|---|
| Services | Python 3.12, FastAPI, SQLAlchemy + Alembic, Poetry | Five domain services + GraphQL gateway; migrations via init-containers |
| Protocols | REST (OpenAPI), gRPC (Protobuf/buf), GraphQL (SDL), Kafka (Avro) | The deliberate protocol mix: cross-product APIs, hot paths, read surface, async spine |
| Packaging | Helm (umbrella chart + per-service subcharts), podman | One chart tree for the whole system; images built on the host, pushed to the in-cluster registry |
| Substrate | Kubernetes v1.32 on minikube (rootless podman driver, containerd) | The whole system on one 24 GB profile |
| Database | CloudNativePG operator, PostgreSQL | One shared cluster, schema-per-service ownership |
| Events | Strimzi operator, Apache Kafka | The asynchronous spine (`order-placed` topic) |
| Contracts | Apicurio Registry | OpenAPI + Protobuf + GraphQL SDL (discovery) and Avro (runtime, Confluent-compatible API) |
| Catalog | OpenMetadata (+ OpenSearch) | Service inventory, ownership, cross-product lineage |
| Mesh | Istio | mTLS, traffic splitting for the v1→v2 contract canary |
| Autoscaling | KEDA (core + HTTP add-on) | Consumer-lag scaling for event consumers, request-based scale-to-zero for the gateway |
| Observability | Prometheus, Tempo, Grafana, Kiali, OpenTelemetry | Metrics, cross-product traces, dashboards, live mesh topology |
| Site | Jekyll / GitHub Pages | The ten-page reading set with paired SVG + Excalidraw diagrams |

## What's here

- **`_docs/`** — the ten reading-set pages (00-index through 10-summary).
  The published site renders these at `https://patterncatalyst.github.io/datamesh-reference-arch-python/docs/<name>/`.
- **`examples/lgtm-datamesh/`** — the runnable code: five domain services
  plus a GraphQL gateway, helm charts, Kafka and Postgres operators,
  Istio service mesh, KEDA autoscaling, Prometheus/Tempo/Grafana/Kiali
  observability, and the demo scripts that exercise it end to end.
- **`presentation/`** — two paired decks: *Data Mesh 101* (the
  conceptual deck) and *Data Mesh on OpenShift* (the implementation deck).
- **`assets/diagrams/`** — paired SVG + Excalidraw sources for every figure.
- **`_plans/`** — active decisions and reconciliation tracking.
  Historical material from the capstone era is preserved under
  `_plans/archive/`.
- **`scripts/`** — top-level helper scripts: cross-reference and Liquid
  collision linters, a Fedora prerequisites audit, setup helpers for
  Istio / KEDA / Strimzi, and the diagram-splicing utility.
- **`onboarding/`** — the orientation guide and the lessons-learned
  distillation.

## Getting started

**To read:** start at the published site's
[reading guide](https://patterncatalyst.github.io/datamesh-reference-arch-python/docs/00-index/),
or read [`onboarding/GETTING-STARTED.md`](onboarding/GETTING-STARTED.md)
for repo orientation.

**To run:** the operational entry point is
[`examples/lgtm-datamesh/README.md`](examples/lgtm-datamesh/README.md) —
check the prerequisites there (or run `./scripts/audit-fedora-prereqs.sh`
for a read-only host check), then:

```bash
cd examples/lgtm-datamesh
./scripts/bootstrap-capstone.sh   # the whole stack, ten gated tiers
./demos/walkthrough.sh            # the five-act presenter walkthrough
```

The verified configuration is Fedora with rootless podman, 64 GB RAM
(24 GB for the minikube profile), and minikube ≥ 1.36.

## Origin

This repo is a fork of the §17 capstone from
[`patterncatalyst/minikube-on-fedora`](https://github.com/patterncatalyst/minikube-on-fedora).
The parent repo's tutorial (§1–§16) remains the canonical Minikube-on-Fedora
guide; this repo is the data-mesh reference broken out for its own audience.
The fork was made as of r28 of the parent (June 2026).
