# lgtm-datamesh — the runnable data-mesh reference

The full implementation of the data-mesh reference: five Python/FastAPI
services exposing REST, gRPC, GraphQL, and Kafka interfaces, deployed via
helm to a dedicated minikube profile, with full observability, contracts
and a catalog, Istio service mesh with canary delivery, KEDA autoscaling,
and an end-to-end presenter walkthrough that exercises all of it.

This is the **runnable counterpart** to the reading set on the published
site (`_docs/00-index.md` through `_docs/09-anti-patterns.md`). Read the
reading set for the conceptual and design background; this README is the
operational entry point for actually running the system.

The example tree was originally `examples/17-capstone/` in the parent
repo `patterncatalyst/minikube-on-fedora`; it was renamed to
`lgtm-datamesh` when this repo was forked out, to disambiguate it from
the parent's `17-capstone` example (which still exists for readers
arriving via the minikube tutorial).

## Quick start

The bootstrap script brings the whole system up on a fresh minikube
profile in ten steps:

```bash
./scripts/bootstrap-capstone.sh
```

Once that's green, the presenter walkthrough exercises end-to-end
behavior across five acts (trace, scale, canary, lineage, topology):

```bash
./demos/walkthrough.sh
```

Each act presses Enter to advance; the trace act is currently bypassing
the KEDA HTTP add-on's interceptor (see CAP-047 in the decision-log
archive) and port-forwards to the gateway directly — the trace itself
still demonstrates spans across three products in Tempo.

## Directory layout

```
examples/lgtm-datamesh/
├── README.md                ← this file
├── README.archive.md        ← the original capstone-era README
├── charts/                  ← helm charts for every component
│   └── capstone/            ← umbrella chart (subchart name kept from
│                              the original to avoid breaking internal
│                              references inside the chart tree)
├── scripts/                 ← bootstrap, setup-* helpers per component,
│                              teardown
├── proto/                   ← protobuf definitions for the gRPC services
├── postman/                 ← Postman collection for live API demos
├── demos/                   ← smoke-* scripts + walkthrough.sh orchestrator
└── services/                ← source for the 5 services + GraphQL gateway
    ├── order-service/
    ├── inventory-service/
    ├── payment-service/
    ├── shipping-service/
    ├── notification-service/
    └── graphql-gateway/
```

## Configuration

The umbrella chart's `values.yaml` has feature flags for every component;
set any to `enabled: false` for a partial-stack deploy. Useful when
debugging a specific service in isolation or when the host is
RAM-constrained.

## Prerequisites (verified configuration)

- Fedora 44 with rootless podman as the container runtime
- 64 GB RAM (the `capstone` minikube profile uses 24 GB; the rest is host
  headroom)
- 1 TB disk (≥30 GB free for image cache + PVs)
- Kernel `fs.inotify.max_user_instances` raised (the bootstrap checks
  this and tells you the fix command)
- Standard tooling: minikube, kubectl, helm

The bootstrap script audits prerequisites before doing any work.

## Where to learn more

- The reading set (`_docs/`) — the canonical narrative explanation of
  why each component is here and how they fit together.
- The historical decision log (`_plans/archive/capstone-decisions.md`
  at the repo root) — every architectural choice from CAP-001 through
  CAP-047 with rationale and rejected alternatives.
- The active decision log (`_plans/decisions.md` at the repo root) —
  decisions made in this repo's standalone life, starting from DRA-001.
