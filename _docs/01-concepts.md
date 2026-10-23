---
title: "Concepts & principles"
order: 2
description: What a data mesh is, operational vs. analytical data, and Dehghani's four principles. The conceptual grounding before any commands.
duration: 20 min
---

## Learning objectives

By the end of this chapter you can:

- State what a data mesh is and the failure it responds to, in your own words.
- Distinguish operational data from analytical data and explain how a mesh
  reorganizes that boundary by domain rather than by technology layer.
- Name Dehghani's four principles and give a one-line example of each from this
  build.
- Recognize the difference between the data-mesh pattern and the specific tools this
  reference uses to express it.

## Why this matters

The order domain owns orders. Nothing else touches that data directly. By
the end of this page you'll see why that single fact, repeated across five domains,
is most of what a data mesh is.

The [previous page]({{ '/docs/01-data-architectures/' | relative_url }}) covered the
landscape of data architectures (pipelines, warehouses, lakes) and where the mesh sits
relative to all of them. This page goes deeper into what a data mesh actually is and
the four principles it rests on.

The term gets attached to a lot of things it isn't, so it's worth being precise before
any commands show up. This page is a working grounding in the idea and its four
principles, enough to make the rest of the set make sense. It's brief. If you want the
full conceptual treatment (the history, the operating-model shifts, the worked argument
for decentralization), that's what the *Data Mesh 101* material in the presentation is
for. Here we cover just enough to build on.

## What a data mesh is

The term **data mesh** was coined by Zhamak Dehghani in 2019 and formalized in *Data
Mesh: Delivering Data-Driven Value at Scale* (O'Reilly, 2022). It's a response to a
recurring failure: centralized data platforms (the monolithic data lake, the
monolithic warehouse, the sprawl of ETL pipelines feeding them) stop scaling once an
organization has enough data sources, enough consumers, and enough use cases. The
bottleneck isn't the technology. It's that one central team ends up owning all the
data but understanding none of the domains it came from.

The shift a data mesh proposes is from "centralize the data, then carve out access"
to **decentralize ownership: let each domain own its data as a product**, with a
shared platform providing the substrate those products use to publish, discover, and
govern themselves. The analogy that lands hardest is microservices. Just as a
monolithic application gets refactored into bounded contexts owned by domain teams, a
monolithic data platform gets refactored into bounded *data products* owned by domain
teams. The mesh is the network of those products, plus the platform and standards that
let them interoperate.

![From a monolithic data platform to a mesh of data products]({{ '/assets/diagrams/17-monolith-to-mesh.svg' | relative_url }})

## Operational vs. analytical data

One distinction underlies everything here, and blurring it is itself a common mistake.
**Operational data** is the current-state data behind a domain's running services: the
rows a microservice reads and writes to do its job, transactional and live.
**Analytical data** is the historical, aggregated view used to make decisions, train
models, and understand the business over time. Traditionally these live in separate
worlds joined by a tangle of pipelines, operational databases on one side, a lake or
warehouse on the other, with ETL shuttling between them on a delay.

A data mesh doesn't erase the distinction, but it reorganizes it by *domain* rather
than by *technology layer*. Instead of "all operational data here, all analytical data
there, pipelines between," each domain owns both its operational systems and the
analytical products derived from them, and publishes those products for other domains
to consume. The aim is to close the loop between the two planes within each domain,
rather than leaving analytical data as a stale downstream copy.

![Operational vs. analytical data planes]({{ '/assets/diagrams/17-operational-vs-analytical.svg' | relative_url }})

This final project models the **operational** side concretely: services that own their
data and emit events. It shows how analytical consumers attach to that operational flow
through the event backbone, rather than through a nightly extract. That's the loop the
mesh is meant to keep closed.

## The four principles

Dehghani's data mesh rests on four interlocking principles. They depend on each other:
implement one without the others and you get a distributed mess rather than a mesh. All
four show up explicitly in this final project.

![The four principles and how they map to Kubernetes primitives]({{ '/assets/diagrams/17-data-mesh-four-principles.svg' | relative_url }})

**Domain ownership.** In this build the order domain owns orders and inventory owns
stock, and nothing reaches across that boundary to mutate another domain's data
directly. That's domain ownership: data owned, end to end, by the domain team that
produces it. There's no central team that "owns the warehouse." Each domain owns the
whole arc of its data: the schema, the lifecycle, how it evolves.

**Data as a product.** Each domain service here publishes its API contracts to a
registry and its metadata to a catalog. A consumer can look up what the service does
and build against it without ever talking to the team that owns it (the subject of the
[contracts & catalog page]({{ '/docs/04-contracts-and-catalog/' | relative_url }})).
That's what makes it a product rather than a renamed table: it's held to the same
standards as any other software product, discoverable, addressable, trustworthy,
self-describing, with explicit expectations about quality and availability.

**Self-serve data platform.** The event backbone, the observability stack, the
registry, the catalog, and autoscaling are all platform infrastructure shared by the
services in this build, not things any one domain team built itself. That's the point
of a self-serve platform: domain teams shouldn't each build their own event streaming,
observability, registry, or catalog. The platform provides these as shared
infrastructure every domain consumes, so a domain team can stand up a data product
without first becoming experts in running Kafka or Prometheus.
[Kubernetes as the substrate]({{ '/docs/02-kubernetes-substrate/' | relative_url }})
covers exactly how Kubernetes makes that self-serve layer real.

**Federated computational governance.** The service mesh in this build enforces mutual
TLS between services automatically, the registry rejects schema-incompatible contract
changes at publish time, and lineage gets recorded as part of deploying rather than as
a separate audit. That's governance enforced *computationally*, by the platform,
automatically, rather than by review meetings and policy documents. A small set of
global rules keeps independent products interoperable, and the platform enforces them.
The
[anti-patterns page]({{ '/docs/09-anti-patterns/' | relative_url }})
covers what happens when governance instead gets bolted on from outside, or
re-centralized into an approval bottleneck.

## The pattern is not the tools

A data mesh isn't a product, a tool, or a vendor offering. It's an organizational and
architectural pattern. The tools this final project uses are *expressions* of the
pattern, chosen because each one makes a principle concrete and runnable, not because
any of them *is* the mesh. That distinction matters enough that it's the first
[anti-pattern]({{ '/docs/09-anti-patterns/' | relative_url }}): the most
common way these efforts fail is mistaking the tooling for the transformation.

With the vocabulary in place, the next page looks at why Kubernetes is a natural
substrate for all of this, and how each of the four principles maps onto concrete
Kubernetes primitives.

## For deeper coverage

- *Data Mesh* by Zhamak Dehghani: the primary source for the four principles and the
  domain-ownership argument this page summarizes.
- *Learning Domain-Driven Design* by Vlad Khononov: the bounded-context thinking
  behind domain ownership and why a data product maps to a domain, not a table.
- *Implementing Domain-Driven Design* by Vaughn Vernon: a deeper, implementation-level
  treatment of the same domain boundaries.
- *Designing Data-Intensive Applications, 2nd ed.* by Martin Kleppmann & Chris
  Riccomini: the operational-versus-analytical data distinction from the systems
  side.
- *Cloud Native Patterns* by Cornelia Davis: the self-serve platform principle made
  concrete in cloud-native infrastructure terms.
