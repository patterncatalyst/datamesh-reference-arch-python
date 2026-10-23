---
title: "The data mesh — start here"
order: 0
description: "The map — what this reference builds, the reading order, and a link to each page in the set. Start here."
duration: 5 min
---

## Learning objectives

By the end of this chapter you can:

- Name the four movements the reference set is organized into and which pages fall
  into each one.
- Pick the reading order that matches how you want to use the set — straight through,
  or jumping to one topic.
- Identify the three pages that cover the pattern's shape if you only have time for a
  few.
- Locate the page that answers a specific question without re-reading the whole set.

## Why this matters

This is the reading guide for the data-mesh reference — the map of what the set covers
and the order to read it in. The reference builds one working system end to end: a data
mesh of services that own their data as products, talk over a deliberate mix of
protocols, evolve their contracts safely, scale to demand, and stay observable
throughout.

The set is written to be read straight through the first time. Each page picks up where
the last left off, and the cross-references assume you've seen the earlier material. If
you're returning to find one thing, the descriptions below will point you at the right
page.

## How the set is organized

The eleven pages fall into four movements. The **conceptual grounding** (pages 1–3)
establishes the landscape of data architectures, what a data mesh is, and why Kubernetes
is a natural substrate for one. The **implementation** (pages 4–9) builds the system:
the services and their data products, the contracts and catalog that make them
discoverable, the data planes they communicate over, progressive delivery with mutual
TLS, elastic scaling and recovery, and the observability to see it all. The **failure
modes** (page 10) steps back to the conceptual and organizational anti-patterns that
derail data-mesh efforts even when the technology is sound. The **summary** (page 11)
closes by reorganizing the same material by principle — for each of the four principles,
the value it delivers and the implementation pieces that realize it.

## The pages

- [**1 · Data architectures**]({{ '/docs/01-data-architectures/' | relative_url }}) —
  The landscape from pipelines to lakes to mesh — what each pattern is, the problem
  it solves, and why the mesh is a different kind of answer.
- [**2 · Concepts & principles**]({{ '/docs/01-concepts/' | relative_url }}) —
  What a data mesh is, operational versus analytical data, and Dehghani's four
  principles. The grounding before any commands.
- [**3 · Kubernetes as the substrate**]({{ '/docs/02-kubernetes-substrate/' | relative_url }}) —
  Why the four principles map cleanly onto namespaces, operators, RBAC, and platform
  primitives, and the shape of the system you'll build.
- [**4 · Services & data products**]({{ '/docs/03-services-and-data-products/' | relative_url }}) —
  The anatomy of a data product, the five domain services plus the gateway, and the
  order-service template the others follow.
- [**5 · Contracts & the catalog**]({{ '/docs/04-contracts-and-catalog/' | relative_url }}) —
  Versioned contracts in a registry, the runtime-versus-discovery distinction, and why a
  catalog is a mesh requirement rather than an add-on.
- [**6 · The data planes**]({{ '/docs/05-data-planes/' | relative_url }}) —
  The synchronous read layer (REST, gRPC, a GraphQL gateway) and the asynchronous event
  backbone — and why the final project uses all of them.
- [**7 · Progressive delivery & mTLS**]({{ '/docs/06-progressive-delivery-mtls/' | relative_url }}) —
  Evolving a contract in the open with a v1→v2 canary, mTLS with no application changes, and the decision to
  mesh selectively rather than namespace-wide.
- [**8 · Elastic & resilient**]({{ '/docs/07-elastic-and-resilient/' | relative_url }}) —
  Scaling to demand and to zero with KEDA, and the cloud-native recoverability the
  platform provides.
- [**9 · Observability**]({{ '/docs/08-observability/' | relative_url }}) —
  Metrics, distributed traces across products, and the live view of traffic moving
  through the mesh.
- [**10 · Anti-patterns**]({{ '/docs/09-anti-patterns/' | relative_url }}) —
  The conceptual and organizational ways data-mesh efforts go wrong, drawn from the
  literature, so you can recognize them early.
- [**11 · Summary**]({{ '/docs/10-summary/' | relative_url }}) —
  Each principle, reorganized: the value it delivers, the implementation pieces that
  realize it, and the failure mode when it's missing.

## If you have time for only a few

Read [**concepts**]({{ '/docs/01-concepts/' | relative_url }}) for the
vocabulary, [**contracts & the catalog**]({{ '/docs/04-contracts-and-catalog/' | relative_url }})
for the idea that holds a mesh together, and
[**anti-patterns**]({{ '/docs/09-anti-patterns/' | relative_url }}) for what
to avoid. Those three cover the shape of the thing without the full implementation
depth.

Start with [concepts & principles]({{ '/docs/01-concepts/' | relative_url }}).

## For deeper coverage

- *Data Mesh* by Zhamak Dehghani — the full argument this reference implements, including
  the history and the operating-model shifts this set only summarizes.
- *Designing Data-Intensive Applications, 2nd ed.* by Martin Kleppmann & Chris
  Riccomini — the data-systems foundations (storage, replication, consistency) that sit
  underneath every data product in this build.
- *Cloud Native Patterns* by Cornelia Davis — the platform patterns this reference's
  self-serve tier draws on.
- *Kubernetes Patterns* by Bilgin Ibryam & Roland Huß — the Kubernetes-native building
  blocks the implementation pages rely on throughout.
