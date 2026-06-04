# Getting started with the data-mesh reference architecture

> Scaffold — to be filled out during the editorial pass.
> The published site is the canonical reading order; this document is the
> "how to use this repo" companion.

---

## Three audiences, three entry points

This reference can be read three ways, depending on what you came for:

**1. The conceptual reader** wants to understand data mesh as an idea — the
four principles, the operational/analytical handoff, what distinguishes a
mesh from a service-oriented architecture. Start at the published site:

- [Concepts & principles](https://patterncatalyst.github.io/datamesh-reference-arch-python/docs/01-concepts/)
- [Anti-patterns](https://patterncatalyst.github.io/datamesh-reference-arch-python/docs/09-anti-patterns/)

Both can be read in 20–30 minutes without touching a cluster.

**2. The implementation reader** wants the design choices: why this set of
services, why these protocols, why these tools, what trade-offs were
deliberate. Read the set straight through in order from
[the index](https://patterncatalyst.github.io/datamesh-reference-arch-python/docs/00-index/).
~2 hours straight through.

**3. The builder** wants a running system. Skip to `examples/lgtm-datamesh/`
and read its `README.md` for the bootstrap procedure. You'll need a host
with the prerequisites covered there (Fedora 44 with rootless podman is the
verified configuration; other Linux distros with similar primitives should
work).

---

## Prerequisites

TODO — needs editorial pass. Roughly:

- Linux host (Fedora 44 verified; other distros likely work but unverified)
- 16 GB RAM, ~16 vCPU recommended for the full minikube profile
- Rootless podman as the container runtime
- minikube, kubectl, helm
- ~30 minutes for the bootstrap

The example tree's `README.md` is the canonical list with the exact
versions tested.

---

## The bootstrap

```bash
cd examples/lgtm-datamesh
./scripts/bootstrap-capstone.sh
./demos/walkthrough.sh
```

That's it. The bootstrap is ten steps; the walkthrough is five acts.

---

## How to navigate as a reader of source

TODO — needs editorial pass. The high-level map:

- `_docs/` is the reading set (rendered on the site as `/docs/<name>/`).
- `examples/lgtm-datamesh/` is the runnable code. Sub-trees mirror the
  reading set (charts, demos, istio, keda, observability, openmetadata,
  services, scripts).
- `assets/diagrams/` is paired SVG + Excalidraw sources for every figure.
- `presentation/` is the two paired decks.
- `_plans/` is the active decision log and reconciliation tracking;
  `_plans/archive/` is the historical material from the capstone era.

---

## Contributing

TODO — needs editorial pass. Brief: open an issue first for non-trivial
changes; the decision-log entries (`_plans/decisions.md`) are the contract
for what's intentional in the design, so changes that touch them need
discussion before code.
