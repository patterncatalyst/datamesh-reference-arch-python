# Product Requirements Document — datamesh-reference-arch-python

This PRD captures what this project is, who it's for, what success looks
like, and what's deliberately excluded. It's a living document — changes
that touch its commitments (especially the goals and non-goals in §3, and
the scope in §5) should be discussed in an issue before they ship.

---

## 1. Summary

**One sentence.** A working, runnable reference implementation of a data
mesh in Python — domain services across REST, gRPC, GraphQL, and Kafka,
deployed via helm to Kubernetes, with versioned contracts, a catalog,
progressive delivery via a service mesh, event-driven autoscaling, and
end-to-end observability — that fits on a laptop while remaining
recognisable as the same shape you'd run in production.

**One paragraph.** This reference takes Zhamak Dehghani's four data-mesh
principles (domain ownership, data as a product, self-serve platform,
federated computational governance) and shows what they look like as a
running system on Kubernetes. Five Python domain services (order,
inventory, payment, shipping, notification) plus a GraphQL gateway
communicate through a deliberate protocol mix: REST for cross-product
APIs, gRPC for service-to-service hot paths, GraphQL at the synchronous
read surface, Kafka events on the asynchronous spine. Versioned contracts
live in a registry; an OpenMetadata catalog publishes service inventory
and cross-product lineage; Istio canaries a v1→v2 contract change live;
KEDA scales workloads on the *demand they actually face* (Kafka lag for
consumers, request volume for the gateway, neither for the canaried
service); Prometheus, Tempo, Grafana, and Kiali make the cross-product
behavior legible. The whole system runs on a minikube profile on a
single host, brought up by one bootstrap script and exercised end-to-end
by a five-act presenter walkthrough.

It exists because most data-mesh material is conceptual; this one is
runnable. And because most runnable material is either too small to show
the cross-product behavior that defines a mesh, or too production-scaled
to run on a laptop. The reference threads that gap.

---

## 2. Problem statement

### Who is the reader?

Three audiences, with overlapping needs:

The **platform engineer** at a mid-to-large organisation has been asked to
either build a data mesh on Kubernetes, or evaluate whether one is the
right shape for their org. They have working knowledge of Kubernetes
(pods, deployments, services, ingress) and probably some service-mesh
exposure. They've read Dehghani's book or skimmed it. They need to bridge
"the four principles" to "what this actually looks like in YAML and
running pods" — and they need a concrete reference they can adapt rather
than a slideware vision they have to imagine.

The **data engineer / analytics engineer** at the same kind of organisation
has been told "we're going to data mesh." They know the analytical side
(warehouses, lakes, tools like dbt) but the operational side is fuzzier —
events, services, schema registries, mesh, mTLS. They need a worked
example of how the operational side connects to the analytical side
through events and lineage, in language that doesn't assume they're a
Kubernetes operator.

The **architect or technical lead** is making the decision about whether a
data mesh fits their organisation. They need the failure modes (the
anti-patterns page) as much as the success path, in concrete terms drawn
from the reference's own implementation choices rather than theoretical
warnings.

All three benefit from a reference where every concept ties back to
specific code and specific manifests, and where the trade-offs are named
in the prose rather than hidden in the implementation.

### What's their pain today?

Existing data-mesh material splits roughly into two categories. The
**conceptual** material — Dehghani's book, the principles deck circuit,
vendor whitepapers — is good at *what* and *why* but rarely concrete about
*how*. Readers come away with a vocabulary and a vision but not a starting
point. The **vendor-marketing** material is concrete about *how* but tied
to a specific product, and is usually positioned to make the vendor's
product look inevitable; the trade-offs and rejected alternatives don't
make it into the slides.

What's missing in the middle is a vendor-neutral, runnable reference that
makes the architectural choices visible — not as a prescription, but as
*one* worked example, with the reasoning for each choice and the failure
modes called out. That's what this reference is trying to be.

### Why now?

Dehghani's *Data Mesh* is three years past publication. The discourse has
shifted from "what is a data mesh" to "how do you actually build one,"
and several real implementations have been written up since. Tooling has
matured: schema registries, service meshes, distributed-tracing stacks,
data catalogs, and event-driven autoscalers are all production-ready in
ways they weren't when the term was coined. The right moment for a
runnable reference is now, while the concepts are well-understood and the
tools have stabilised, before the patterns get fragmented across vendor
forks.

---

## 3. Goals and non-goals

### Goals (testable)

- A reader who finishes the reading set understands the four principles
  concretely enough to recognise them — or their absence — in their own
  architecture, not just abstractly.
- A reader who runs the example tree gets a working data mesh on their
  laptop: five services, contracts, catalog, canary, autoscaling,
  observability, all green within ~30 minutes of bootstrap on the
  verified configuration.
- A reader can demonstrate the cross-product behaviours that make a
  collection of services a *mesh*: a single GraphQL query producing a
  trace tree across three products, a contract canary shifting live
  traffic by weight without application code changes, a Kafka-lag
  scaler waking and quiescing an event consumer.
- The runnable examples build and run end to end on a Fedora-on-rootless-podman
  minikube setup with one bootstrap command. CAP-047 of the historical
  decision log documents the one deferred component (the KEDA HTTP
  add-on's interceptor on the gateway scale-from-zero path) and the
  worked-around demo path that keeps the walkthrough 5-of-5 green.

### Non-goals (deliberate exclusions)

- **Production deployment guidance.** This reference is for *learning*
  and *evaluating*. Production data mesh on Kubernetes is its own much
  larger topic — capacity planning, HA, backup/recovery, security
  hardening, multi-tenant isolation, cost management — and the
  reference's simplifying choices (single-node Postgres, single-node
  OpenSearch, dev-mode catalog) are appropriate for a laptop and
  inappropriate for production. The reference says so explicitly where
  it matters.
- **Comparative coverage of data-mesh products or approaches.** No
  vendor comparisons, no "X versus Y" frames, no positioning against
  competing patterns (data fabric, data lakehouse, etc.). Readers can
  draw their own comparisons; the reference's job is to be a clear
  worked example of one approach.
- **Deep coverage of analytical-side technologies.** The reference uses
  a small Postgres-and-Kafka spine to demonstrate the operational-to-analytical
  handoff (events publish from operational stores; lineage tracks them
  through the catalog). It doesn't take positions on Iceberg vs. Delta,
  Snowflake vs. BigQuery vs. Databricks, dbt vs. SQLMesh, or warehouse
  shape. Those choices are downstream of the mesh; this reference stops
  at the boundary.
- **Coverage of every Kubernetes runtime.** The verified configuration
  is minikube on Fedora 44. The reference is portable in principle to
  OpenShift (where the implementation deck pairs it explicitly), EKS,
  GKE, AKS, and vanilla K8s, but the bootstrap and chart values are
  written for the verified runtime. Adapting to other runtimes is left
  to readers as a known and welcome contribution path.
- **Building a generic "data mesh framework."** This is a reference
  implementation, not a framework. There's no abstraction layer
  intended for reuse across organisations; the value is in seeing one
  concrete shape end to end, not in extracting a meta-pattern.

---

## 4. Audience details

### Primary audience

Platform engineers and architects evaluating or building a data mesh on
Kubernetes. They have working K8s knowledge, have read at least the
introduction to Dehghani's book or its equivalent, and are trying to
bridge concept to implementation. They run Linux laptops or workstations
with 32+ GB RAM, or have access to a development cluster they can adapt
the example to.

### Secondary audience

Data engineers, analytics engineers, and data architects who are being
asked to participate in a data-mesh adoption and want to understand the
operational side they'll be integrating with. They may not run the
example themselves but want to read the prose and understand the
diagrams.

Conference presenters and instructors who want a vendor-neutral concrete
example they can demo or refer to in talks. The two paired decks
(`presentation/data-mesh-101/` and `presentation/data-mesh-openshift/`)
are intended to be usable directly with attribution.

### Audience explicitly NOT served

People looking for production guidance, people who want a comparison of
data-mesh products, people who want only the analytical-side story,
people who don't have at least working Kubernetes knowledge. The
reference will frustrate any of those audiences because it deliberately
doesn't try to serve them; the
[anti-patterns page](https://patterncatalyst.github.io/datamesh-reference-arch-python/docs/09-anti-patterns/)
is the closest thing to a "should you do this at all" treatment.

---

## 5. Scope

The reference's scope is the system shown in the published reading set:

| § | Title                          | What it covers                                                             |
|---|--------------------------------|----------------------------------------------------------------------------|
| 0 | Index                          | Map and reading order                                                      |
| 1 | Concepts & principles          | What a data mesh is; the four principles                                   |
| 2 | Kubernetes as the substrate    | Why K8s fits; principles mapped to K8s primitives                          |
| 3 | Services & data products       | Five domain services + gateway; the data-product anatomy                   |
| 4 | Contracts & the catalog        | Versioned contracts in a registry; OpenMetadata for discovery + lineage    |
| 5 | The data planes                | Synchronous read layer (REST/gRPC/GraphQL); async event backbone           |
| 6 | Progressive delivery & mTLS    | Canarying a v1→v2 contract with Istio; selective mesh injection            |
| 7 | Elastic & resilient            | KEDA scaling on the right demand signal; platform recoverability           |
| 8 | Observability                  | Metrics, traces, the live topology view                                    |
| 9 | Anti-patterns                  | Failure modes — conceptual and organisational — drawn from the literature  |
| 10 | Summary                       | What each principle delivers; the implementation pieces that realise it    |

The runnable code in `examples/lgtm-datamesh/` ships everything to bring
the reference's described system up on a minikube profile and exercise it
end to end. Specifically:

- five Python services and the GraphQL gateway as source
- helm charts for every component (services, gateway, contracts registry,
  catalog, Postgres operator, Kafka operator, service mesh, autoscaler,
  observability stack)
- protobuf definitions for the gRPC interfaces
- demo scripts: per-component smokes plus the five-act walkthrough
- bootstrap, setup-per-component, and teardown scripts

---

## 6. Runnable examples

The reference ships ONE runnable example tree at
`examples/lgtm-datamesh/`. Principal entry points:

- **`scripts/bootstrap-capstone.sh`** — brings the whole system up on a
  fresh minikube profile in ten steps. Each step has a success criterion
  printed; the script stops on first failure with a fix hint.
- **`demos/walkthrough.sh`** — the five-act presenter walkthrough that
  exercises every cross-product behaviour the reference describes.
- Per-component **`demos/smoke-*.sh`** scripts for verifying individual
  pieces without running the full walkthrough.

The verification model: each smoke script is its own gate (it returns
non-zero on failure with a useful message). The walkthrough orchestrator
runs them in sequence with presenter-driven pacing.

---

## 7. Diagrams

The reference uses paired SVG + Excalidraw sources for every figure. SVG
is what the site embeds and what versions cleanly in git; Excalidraw is
the source-of-truth for editing. All diagrams live in `assets/diagrams/`
with the naming convention `<section-num>-<slug>.svg` + matching
`.excalidraw`. The `scripts/splice-diagrams.sh` workflow regenerates
diagrams that have changed.

---

## 8. Success metrics

### Verification metrics (project-controlled)

- The presenter walkthrough runs 5-of-5 green on the verified runtime
  (Fedora 44 + rootless podman + minikube), as documented in the
  reconciliation file at `_plans/reconciliation.md`.
- All internal links resolve (`scripts/check-cross-references.sh` exits 0).
- All `{{ }}` Liquid expressions in `_plans/*.md` are properly fenced
  (`scripts/check-liquid-collisions.sh` exits 0).
- The Jekyll site builds cleanly in CI (`.github/workflows/pages.yml`).
- The bootstrap script's ten steps each report success with verifiable
  criteria, not silent passes.

### Adoption metrics (external, indicative)

These depend on factors outside the reference itself and shouldn't drive
day-to-day decisions, but are useful as a long-range health check:

- Stars, forks, and watchers on the GitHub repo (slow signal).
- Issues that demonstrate engagement (questions, bug reports,
  contribution offers) versus issues that show confusion (the reference
  isn't doing its job).
- Talks, blog posts, or other references that point to this repo as a
  concrete example.

---

## 9. Constraints and dependencies

### Technical constraints

- **Kubernetes is the substrate model.** Anything that contradicts
  upstream Kubernetes idioms (operators, CRDs, RBAC, service mesh) is
  out of scope.
- **The verified runtime is minikube on Fedora 44 with rootless podman.**
  Other runtimes are documented as portable in principle; verifying
  them is a contribution path.
- **Vendor-neutral language.** Where multiple tools could fit a slot
  (e.g. Strimzi vs. AMQ Streams vs. Confluent for Kafka, OpenMetadata
  vs. DataHub for catalog), the reference picks one *implementation*
  and names the choice, but the prose treats the *role* generically
  ("the Kafka operator," "the catalog") so the discussion transfers.
- **The runnable code requires real platform pieces.** No mocks of
  Kafka, Postgres, or the service mesh. The point is to see real
  behaviour.

### Editorial constraints

- Prose uses "you" for the reader and either passive voice or
  third-person for the system. No "we" voice.
- Code examples are copy-pasteable without modification when run from
  the documented working directory.
- Diagrams are SVG (vector, hi-DPI clean) with paired Excalidraw
  sources for editing.
- Each significant architectural choice gets a decision-log entry in
  `_plans/decisions.md` with rationale, evidence, and rejected
  alternatives.

### Dependencies

The runnable code depends on the upstream releases of: minikube, helm,
Istio, Strimzi, CloudNativePG, KEDA (and its HTTP add-on), Apicurio
schema registry, OpenMetadata, Prometheus, Tempo, Grafana, Kiali.
Version pins live in the bootstrap and setup scripts; the reconciliation
file tracks any deferred upgrades.

The historical decision log at `_plans/archive/capstone-decisions.md`
captures every version choice with rationale.

---

## 10. Risks and mitigations

| Risk                                                | Impact | Likelihood | Mitigation                                                                    |
|-----------------------------------------------------|--------|------------|-------------------------------------------------------------------------------|
| Upstream tool changes break the bootstrap mid-life  | High   | Medium     | Pinned versions in setup scripts; reconciliation file tracks upstream issues  |
| Readers conflate "minikube" with "the reference"    | Medium | Medium     | Explicit minikube/Kubernetes framing in the index, summary, and onboarding    |
| Production-readers misuse the reference's choices   | High   | Low        | Explicit non-goal in §3; section prose calls out development-only choices     |
| The reference goes stale as the data-mesh discourse | Medium | Eventual   | Decision log makes the *reasoning* legible; updates are tractable             |
|   evolves                                           |        |            | rather than archaeological                                                    |

---

## 11. Timeline and milestones

This reference was extracted from
`patterncatalyst/minikube-on-fedora`'s §17 capstone as of that repo's r28
(June 2026). The original build's milestones (CAP-001 through CAP-047)
are preserved in `_plans/archive/`. Forward milestones for this repo are
tracked in `_plans/decisions.md` starting from DRA-001 (the extraction
itself).

---

## 12. Open questions

- **Which (if any) non-minikube runtimes get sibling bootstrap scripts?**
  OpenShift Local is the most natural candidate given the implementation
  deck's pairing. EKS, GKE, AKS are all candidates but each is a real
  iteration to do well. Tracking as a possible DRA-NNN entry.
- **Should the catalog go beyond OpenMetadata in dev mode?** A
  more-production-shaped catalog deployment (single-node OpenSearch is
  the dev-mode simplification) would make the reference's catalog story
  closer to what readers would deploy — but at meaningful additional
  resource cost on the laptop. Trade-off documented; decision deferred.
- **What's the right shape for adding analytical-side content without
  scope-creeping into warehouse coverage?** Possibly a §11 page that
  shows operational events arriving at a dbt-style analytical layer
  *without* taking a position on the analytical-side stack — i.e. focus
  on the handoff and the lineage, not on the destination.

---

## 13. Decision log pointer

Active decisions live in `_plans/decisions.md`, numbered from DRA-001.
Historical decisions from the capstone era live in
`_plans/archive/capstone-decisions.md`, numbered CAP-001 through CAP-047.
The two series are deliberately distinct to keep the audit trail
unambiguous.

---

## 14. How this PRD is used

This document is read at the start of each work session for context, and
referenced when scope-creep tempts (if the change isn't covered by §5 or
the open questions in §12, it needs an issue and probably a DRA entry
before it ships). When something significant changes — a goal shifts, a
non-goal becomes a goal, a constraint relaxes — the relevant section is
updated and the change is committed with a clear message. The audit trail
between this document and the decision log is the project's institutional
memory.
