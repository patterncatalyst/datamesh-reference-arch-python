# datamesh-reference-arch-python

A working data-mesh reference implementation in Python — services across
REST, gRPC, GraphQL, and Kafka, deployed via helm, with contracts, a
catalog, progressive delivery, autoscaling, and full observability.

This is the standalone home of the data-mesh reference that previously
lived as §17 of [`patterncatalyst/minikube-on-fedora`](https://github.com/patterncatalyst/minikube-on-fedora).
It contains the complete reading set, the runnable example tree, the
presentations, the diagrams, and the historical decision log.

## What's here

- **`_docs/`** — the nine reading-set pages (00-index through 09-anti-patterns).
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
  collision linters, setup helpers for Istio / KEDA / Strimzi, and
  the diagram-splicing utility.

## Getting started

Read [`onboarding/GETTING-STARTED.md`](onboarding/GETTING-STARTED.md) for
the orientation guide. The published site at
[patterncatalyst.github.io/datamesh-reference-arch-python](https://patterncatalyst.github.io/datamesh-reference-arch-python/)
is the canonical reading order; the runnable example tree under
`examples/lgtm-datamesh/` is the canonical build target.

## Origin

This repo is a fork of the §17 capstone from
[`patterncatalyst/minikube-on-fedora`](https://github.com/patterncatalyst/minikube-on-fedora).
The parent repo's tutorial (§1–§16) remains the canonical Minikube-on-Fedora
guide; this repo is the data-mesh reference broken out for its own audience.
The fork was made as of r28 of the parent (June 2026).
