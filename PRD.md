# Product Requirements Document — datamesh-reference-arch-python

> This PRD is being written from scratch for the standalone repo.
> The parent project's PRD (in `patterncatalyst/minikube-on-fedora`) covers
> the broader Minikube-on-Fedora tutorial; that's a different product with
> a different audience. This document is data-mesh-focused throughout.
>
> Sections marked `TODO` will be filled in during the editorial pass.

---

## 1. Summary

**One sentence:** A working data-mesh reference implementation in Python
that demonstrates the four principles of data mesh (domain ownership, data
as a product, self-serve platform, federated computational governance) end
to end on Kubernetes — and is reproducible on a single laptop.

**One paragraph:** This reference takes Zhamak Dehghani's four data-mesh
principles and shows what they look like as a running system: five Python
domain services (order, inventory, payment, shipping, notification) plus a
GraphQL gateway, communicating through a deliberate mix of REST, gRPC,
GraphQL, and Kafka events, deployed via helm onto a Kubernetes cluster
(minikube during development, anything else with the same primitives in
production), with versioned contracts in a registry, a discovery and
lineage catalog, Istio service mesh for progressive delivery and mTLS,
KEDA autoscaling for elastic data products, and a Prometheus/Tempo/Grafana/Kiali
observability stack that lets you watch the mesh actually behave like a
mesh. It exists because most data-mesh material is conceptual; this one is
runnable.

---

## 2. Problem statement

**Who is the reader?** TODO — needs editorial pass.

**What's their pain today?** TODO — drafted from memory: existing data-mesh
content is mostly slideware or vendor-marketing; the runnable examples that
exist tend to be either toy demos that don't show the cross-product behavior
or production-grade systems that can't run on a laptop.

**Why now?** TODO — Dehghani's *Data Mesh* book is three years out; the
discourse has shifted from "what is a data mesh" to "how do you actually
build one"; this reference shows one concrete answer.

---

## 3. Goals and non-goals

### Goals

- A reader who finishes the set understands the four principles concretely
  enough to recognize them in their own architecture, not just abstractly.
- A reader who runs the example tree gets a working data mesh on their
  laptop — five services, contracts, catalog, canary, autoscaling,
  observability — and can demonstrate the cross-product behaviors that make
  it a mesh rather than a pile of services.
- The runnable examples build and run end to end on a Fedora-on-rootless-podman
  minikube setup with one command.
- TODO — refine and add measurable goals.

### Non-goals

- Production deployment guidance. The reference is for *learning*; production
  data mesh on Kubernetes is its own (much larger) topic.
- A comparison of data-mesh products / vendors / approaches.
- Coverage of analytical-side technologies in depth (Delta Lake, Iceberg,
  Snowflake, etc.). The reference uses a small Postgres-and-Kafka spine to
  demonstrate operational-to-analytical handoff without taking a position on
  the analytical-side stack.
- TODO — others.

---

## 4. Audience

TODO — needs editorial pass.

---

## 5. Scope and section outline

The published site's nine pages, in reading order:

| §  | Title                          | Purpose                                                         |
|----|--------------------------------|-----------------------------------------------------------------|
| 0  | Index                          | The map and reading order                                       |
| 1  | Concepts & principles          | What a data mesh is, the four principles                        |
| 2  | Kubernetes as the substrate    | Why K8s is a natural home for the four principles               |
| 3  | Services & data products       | The services and the anatomy of a data product                  |
| 4  | Contracts & the catalog        | Versioned contracts, registry, and OpenMetadata catalog         |
| 5  | The data planes                | Sync read layer (REST/gRPC/GraphQL) + async event backbone      |
| 6  | Progressive delivery & mTLS    | Canarying contracts with Istio; selective injection             |
| 7  | Elastic & resilient            | KEDA autoscaling and platform recoverability                    |
| 8  | Observability                  | Metrics, distributed traces, and the live mesh view             |
| 9  | Anti-patterns                  | The failure modes to recognize early                            |

The runnable code lives in `examples/lgtm-datamesh/`. Its layout mirrors
the reading-set sections: each chart, each smoke script, each demo
corresponds to one of the pages above.

---

## 6. Runnable examples

The reference ships ONE runnable example tree at
`examples/lgtm-datamesh/`, with sub-directories per concern (charts/,
demos/, istio/, keda/, observability/, openmetadata/, scripts/, services/).
The principal entry points are:

- `scripts/bootstrap-capstone.sh` — brings the whole system up on a
  fresh minikube profile in ten steps.
- `demos/walkthrough.sh` — the five-act presenter walkthrough
  (trace, scale, canary, lineage, topology) that exercises everything.
- Individual smoke scripts under `demos/` for component-by-component
  verification.

Test strategy: each smoke script is its own verification gate, and the
walkthrough orchestrator runs them in sequence with presenter-driven
pacing.

---

## 7. Diagrams

The reference uses paired SVG + Excalidraw sources for every figure,
generated via the `scripts/splice-diagrams.sh` workflow. All diagrams live
in `assets/diagrams/` with the convention `<section-num>-<slug>.svg`
matching `<section-num>-<slug>.excalidraw`.

---

## 8-14

TODO — these sections need the editorial pass. The skeleton tracks the
parent repo's PRD structure (which itself was structured around a
tutorial-skeleton template), but the content needs rewriting for this
repo's data-mesh-only audience.

The historical PRD reconciliation is in `_plans/archive/prd-reconciliation.md`
and is worth reading as the audit trail of how the capstone-era PRD's
predictions matched what was actually shipped.
