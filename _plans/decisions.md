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

## DRA-002 — Add a Quarkus (JVM) port of the runnable example

**Status:** decided; implemented in `examples/lgtm-datamesh-quarkus/`.

**Context.** The reference's central claim is that data-mesh *architecture* —
domain ownership, data-as-a-product, a self-serve platform, federated
governance — is independent of any one language or framework. The only
runnable example was Python/FastAPI, which leaves that claim implicit. A second
implementation of the *same* architecture, demos, and wire contracts on a
different stack makes the claim concrete and gives JVM-shop readers a starting
point in their own ecosystem. Quarkus is a strong fit: it has first-class,
built-in support for every protocol the reference uses (REST, gRPC, GraphQL,
Kafka) plus reactive Postgres, Avro/Apicurio, health, config, and — unlike the
Python services — native OpenTelemetry tracing and Micrometer/Prometheus
metrics.

**Decision.** Add a parallel example tree `examples/lgtm-datamesh-quarkus/` that
mirrors the Python tree's layout and behaviour. The Python example is left
byte-for-byte unchanged; the two sit side by side. Specifics:

- **Full 1:1 service set** — all seven services (order, inventory, payment,
  shipping, notification, review) plus the GraphQL gateway, as Quarkus modules
  under a Maven aggregator.
- **Reactive throughout** — Hibernate Reactive Panache + the Vert.x reactive
  Postgres client mirror the Python async model; SmallRye Reactive Messaging
  carries Kafka.
- **JVM mode by default**, native (GraalVM) documented as an optional showcase
  (Java 21 on UBI 9 `openjdk-21`, the analog of CAP-005's `python-312`).
- **Identical wire contracts** so the platform layer, KEDA scalers, Istio
  canary, and Apicurio subjects are reused unchanged: gRPC on `:50051`, topic
  `order-placed`, Avro subject `order-placed-value`, the same CNPG-secret env
  contract, and the `/version` canary signal (v2 adds `currency`).
- **Richer observability** — every Quarkus service exports OTLP traces to the
  shared Tempo and Prometheus metrics at `/q/metrics` (the chart adds scrape
  annotations). The Python tree relies on Istio sidecar metrics only.

**Consequences / accepted divergences from the CAP-era choices.**

- **gRPC stubs are generated at build time** from each service's
  `src/main/proto` via `quarkus-grpc`, rather than committed per service
  (CAP-013). Still "codegen in-process", but no stubs are committed;
  `scripts/sync-protos.sh` keeps each service's proto copy in sync with the
  canonical `proto/`.
- **Apicurio is pinned to 2.6.x** (the Python tree uses 3.2.4) to match the
  Apicurio Avro serde client bundled with Quarkus 3.15 (v2 REST API). This is
  self-contained to the Quarkus tree.
- **Health/SDL/OpenAPI paths follow Quarkus conventions** — `/q/health/live`,
  `/q/health/ready`, OpenAPI at `/q/openapi`, GraphQL SDL at
  `/graphql/schema.graphql` (vs the Python `/health`, `/healthz`,
  `/openapi.json`, `/sdl`). The chart probes and demo scripts are adapted.
- **Schema management** mirrors the Python intent: services that seed
  deterministic data (inventory, review) or evolve schema (notification, like
  the Python Alembic choice) use Flyway; schema-only services use Hibernate
  generation. The per-service Postgres schema boundary (CAP-003) is preserved.
- **Tests use Quarkus Dev Services** (Testcontainers Postgres/Kafka/Apicurio)
  rather than the Python tree's SQLite-in-memory; this needs a container
  runtime, which the repo already assumes.

This is consistent with the PRD's "reference implementation, not a framework"
non-goal: it is a second concrete implementation, not an abstraction layer over
both.

---

## DRA-003 — *(reserved for the next decision)*
