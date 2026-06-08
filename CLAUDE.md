# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Two artifacts that live side by side:

1. **A Jekyll documentation site** (`_docs/`, `_layouts/`, `_includes/`, `index.html`) published to GitHub Pages at `patterncatalyst.github.io/datamesh-reference-arch-python`. The ten pages in `_docs/` are the canonical reading set for the data-mesh reference.

2. **A runnable Kubernetes example** (`examples/lgtm-datamesh/`) — five Python/FastAPI domain services plus a GraphQL gateway, deployed via helm to a dedicated minikube profile, with Istio, KEDA, Kafka (Strimzi), observability (Prometheus/Tempo/Grafana/Kiali), contracts (Apicurio), and a catalog (OpenMetadata).

## Jekyll site

```bash
bundle install                          # install Ruby gems
bundle exec jekyll serve --baseurl ""   # local dev at http://localhost:4000
bundle exec jekyll build                # production build → _site/
```

`_config.yml` excludes `examples/` and `scripts/` from the Jekyll build. The `_docs` and `_plans` collections are non-standard; they're enabled explicitly in `_config.yml`. CI deploys via `.github/workflows/pages.yml` on every push to `main`.

**Content linting** — run these before pushing doc changes:

```bash
./scripts/check-cross-references.sh   # verifies all internal /docs/SLUG/ and /assets/ links resolve
./scripts/check-liquid-collisions.sh  # catches Go-template syntax in _docs that Liquid would misparse
```

**Diagrams** — `assets/diagrams/` holds paired `.excalidraw` + `.svg` files. Always edit the `.excalidraw` source, re-export the SVG, and commit both.

## Runnable example: `examples/lgtm-datamesh/`

### Architecture

Six Python services, each using **FastAPI + Poetry**:

| Service | Protocols | Notes |
|---|---|---|
| `order-service` | REST, gRPC client, Kafka producer | Postgres-backed; calls inventory via gRPC |
| `inventory-service` | gRPC server, REST | Postgres-backed |
| `payment-service` | REST, Kafka consumer | |
| `shipping-service` | REST, Kafka consumer | |
| `notification-service` | Kafka consumer | |
| `graphql-gateway` | GraphQL (Strawberry), gRPC client | Federated read layer over order + inventory |
| `review-service` | REST | |

Protocol mix is deliberate: REST for cross-product APIs, gRPC for service-to-service hot paths, GraphQL at the synchronous read surface, Kafka on the asynchronous spine.

**Platform components** (installed separately from the umbrella chart — they are cluster infrastructure):
- Istio (mTLS, canary delivery)
- Strimzi (Kafka operator)
- KEDA (event-driven autoscaling — Kafka lag for consumers, HTTP request volume for the gateway)
- CloudNativePG (Postgres operator)

**Application components** (helm umbrella chart at `charts/capstone/`):
- Domain services + GraphQL gateway (subcharts under `charts/capstone/charts/`)
- Apicurio (schema/contract registry)
- Postgres cluster CR
- Kafka cluster CR
- OpenMetadata (catalog)
- Observability stack (OTEL Collector, Prometheus, Tempo, Grafana, Kiali)

### Per-service development

Each service uses **Poetry**. From inside a service directory:

```bash
poetry install                  # install deps
poetry run pytest               # run unit tests (SQLite in-memory, no cluster needed)
poetry run pytest tests/test_foo.py::test_name  # run a single test
poetry run uvicorn app.main:app --reload        # run the service locally
```

Unit tests (`tests/`) use SQLite in-memory via `aiosqlite` — no Postgres required. In-cluster smoke tests (`demos/smoke-*.sh`) exercise the real Postgres path.

### Protobuf

Proto definitions live in `proto/capstone/`. Generated stubs land in `services/<name>/gen/`. Regenerate with:

```bash
cd examples/lgtm-datamesh
./scripts/gen-protos.sh
```

Managed by `buf` (`buf.yaml`, `buf.gen.yaml` at the `lgtm-datamesh` root).

### Cluster bring-up (minikube on Fedora 44 + rootless podman)

```bash
cd examples/lgtm-datamesh
./scripts/bootstrap-capstone.sh   # ~25 min first run; idempotent
./demos/walkthrough.sh            # five-act end-to-end presenter demo
```

Individual smoke tests: `demos/smoke-*.sh`. Individual platform setups: `scripts/setup-*.sh`.

Tear down with `./scripts/teardown.sh` or `minikube delete -p capstone`.

### Helm umbrella chart

`charts/capstone/values.yaml` has `enabled: true/false` feature flags for every component — useful for partial-stack deploys or RAM-constrained hosts. The platform control planes (Istio, Strimzi, KEDA) are NOT part of this chart; they're separate helm releases.

## Decision log

`_plans/decisions.md` — active decisions, `DRA-NNN` numbered. Anything that touches these commitments needs an issue before a PR. Historical decisions from the capstone era (`CAP-NNN`) are at `_plans/archive/capstone-decisions.md`.
