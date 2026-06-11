# lgtm-datamesh-quarkus — the data-mesh reference, on Quarkus (JVM)

A **Quarkus/JVM port** of the runnable data-mesh reference that lives next door
in [`examples/lgtm-datamesh/`](../lgtm-datamesh/) (Python/FastAPI). Same
architecture, same five-act demo, same wire contracts — a different stack. It
exists to make the reference's central claim concrete: data-mesh *architecture*
(domain ownership, data-as-a-product, self-serve platform, federated
governance) is independent of any one language or framework.

Read the published reading set (`_docs/00-index.md` … `_docs/10-summary.md`) for
the conceptual background; this README is the operational entry point for the
Quarkus implementation. See **DRA-002** in `_plans/decisions.md` for why this
port exists and how it differs from the Python tree.

## Why Quarkus

Quarkus has first-class, built-in support for every protocol and concern the
reference uses, so the port is idiomatic rather than bolted-on:

| Concern | Python (FastAPI) | Quarkus |
|---|---|---|
| REST | FastAPI + uvicorn | `quarkus-rest` (+ Jackson) |
| Reactive Postgres | SQLAlchemy async + asyncpg | Hibernate Reactive Panache + reactive PG client |
| gRPC | grpcio + committed stubs | `quarkus-grpc` (stubs generated at build) |
| GraphQL | Strawberry | SmallRye GraphQL |
| Kafka + Avro | aiokafka + fastavro | SmallRye Reactive Messaging + Apicurio Avro serde |
| Health | hand-rolled `/health`, `/healthz` | SmallRye Health `/q/health/{live,ready}` |
| Migrations | Alembic (notification) | Flyway |
| **Traces + metrics** | none (Istio sidecar only) | **native OTLP → Tempo + Micrometer `/q/metrics`** |

The last row is the standout: every Quarkus service emits distributed traces
and Prometheus metrics out of the box, so the observability story is richer than
the Python tree's — using the *same* Tempo/Prometheus/Grafana/Kiali stack.

## Quick start

Prereqs: a JDK 21 and the platform tooling the Python example assumes (minikube,
kubectl, helm, rootless podman). The Maven wrapper (`./mvnw`) fetches Maven.

```bash
# 1. Build + test every service (Dev Services spins up Postgres/Kafka/Apicurio
#    via Testcontainers — needs a container runtime).
./mvnw verify

# 2. Bring the whole system up on a fresh minikube profile (same ten-step
#    flow as the Python tree; builds JVM images, deploys the umbrella chart).
./scripts/bootstrap-capstone.sh

# 3. Run the five-act presenter walkthrough (trace, scale, canary, lineage,
#    topology).
./demos/walkthrough.sh
```

Individual feature checks live in `demos/smoke-*.sh`.

## Directory layout

```
examples/lgtm-datamesh-quarkus/
├── README.md                ← this file
├── pom.xml                  ← Maven aggregator (pins the Quarkus platform BOM)
├── mvnw, .mvn/              ← Maven wrapper
├── proto/                   ← canonical protobuf (synced into services by sync-protos.sh)
├── charts/capstone/         ← helm umbrella chart (platform subcharts + 7 services)
├── scripts/                 ← bootstrap, build-image, sync-protos, setup-*, teardown
├── demos/                   ← smoke-* scripts + walkthrough.sh
├── istio/ keda/ observability/ openmetadata/   ← platform config (language-agnostic)
└── services/                ← 7 Quarkus modules
    ├── order-service/        REST + gRPC client + reactive Postgres + Kafka/Avro producer
    ├── inventory-service/    gRPC server (CheckStock :50051) + reactive Postgres
    ├── notification-service/ Kafka consumer (Avro) + reactive Postgres (Flyway)
    ├── graphql-gateway/      SmallRye GraphQL federating REST (order) + gRPC (inventory)
    ├── review-service/       REST CRUD data product
    ├── payment-service/      skeleton (owns its schema, health/metrics)
    └── shipping-service/     skeleton
```

Each service is a standard Quarkus module: source under
`src/main/java`, config in `src/main/resources/application.properties`, the JVM
image in `src/main/docker/Dockerfile.jvm`, and tests under `src/test/java`.

## Per-service development

```bash
cd services/order-service
../../mvnw quarkus:dev        # live-reload dev mode (Dev Services starts deps)
../../mvnw test               # @QuarkusTest component tests
```

## How it stays compatible with the platform

The wire contracts are identical to the Python tree, so the Istio canary, KEDA
scalers, Apicurio subjects, and the CloudNativePG/Strimzi CRs are reused
unchanged:

- gRPC `InventoryService.CheckStock` on **`:50051`**;
- Kafka topic **`order-placed`**, Avro subject **`order-placed-value`**;
- the CNPG app-Secret env contract (`PG_HOST`/`PG_PORT`/`PG_DATABASE`/`PG_USER`/
  `PG_PASSWORD`) and per-service `SERVICE_SCHEMA` (CAP-003);
- the `/version` canary signal (v2 advertises an additive `currency` field).

Endpoints follow Quarkus conventions: health at `/q/health/live` and
`/q/health/ready`, metrics at `/q/metrics`, OpenAPI at `/q/openapi`, and the
GraphQL SDL at `/graphql/schema.graphql`.

## Native images (optional showcase)

JVM mode is the default (fast, reliable builds; mirrors the Python container
approach). To build a tiny, fast-starting GraalVM native image for a service:

```bash
# Container build — no local GraalVM needed.
./mvnw -pl services/order-service -am package -Dnative \
    -Dquarkus.native.container-build=true
```

Then point that service's `Dockerfile` at the native binary
(`ubi9-minimal` + `application` runner). Native best showcases Quarkus and
improves scale-to-zero, at the cost of slower, heavier builds — which is why it
is not wired into the default bootstrap.

## Notes / differences from the Python tree

- **gRPC stubs** are generated at build time (`quarkus-grpc`) rather than
  committed; run `./scripts/sync-protos.sh` after editing `proto/`.
- **Apicurio is pinned to 2.6.x** to match the serde client in Quarkus 3.15
  (the Python tree uses 3.x). See DRA-002.
- **Tests use Quarkus Dev Services** (Testcontainers) instead of SQLite —
  `./mvnw verify` needs a running container runtime (podman/docker). If
  Testcontainers can't reach the daemon, set `DOCKER_HOST` and, on very new
  daemons, `DOCKER_API_VERSION` (e.g. `1.41`).

## Where to learn more

- The reading set (`_docs/`) — the canonical narrative.
- `_plans/decisions.md` (**DRA-002**) — why this port exists and its accepted
  divergences; `_plans/archive/capstone-decisions.md` (CAP-NNN) for the original
  implementation's rationale, which this port deliberately tracks.
