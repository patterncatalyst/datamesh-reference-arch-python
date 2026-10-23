---
title: "Data architectures: from pipelines to mesh"
order: 1
description: "The landscape: data pipelines, data warehouses, data lakes, and data mesh. What each pattern is, the problem it solves, and why the mesh is a different kind of answer."
duration: 25 min
---

## Learning objectives

By the end of this chapter you can:

- Describe data pipelines, data warehouses, and data lakes: the problem each pattern
  solves and the limitation that bounds it.
- Explain why pipeline count grows as the product of sources and destinations, not
  the sum, and why that growth is called pipeline sprawl.
- Contrast schema-on-write and schema-on-read, and say which pattern uses each.
- Match an organization's bottleneck (movement, truth, flexibility, or organizational
  scaling) to the pattern built to solve it.

## Why this matters

Before we pin down what a data mesh actually is, it helps to see where it came from.
The mesh didn't appear out of nowhere. It's a response to organizational scaling
problems that three earlier architectures, each a real attempt at the same underlying
problem, left unsolved.

And each of those earlier patterns is still the right answer when its problem is the
dominant one. Seeing what came before, and what each pattern does well, is
what makes the mesh's value proposition concrete instead of abstract.

## Data pipelines

Picture fifteen operational systems, each one feeding five analytical consumers. The
oldest problem in data architecture is movement: operational systems produce data,
analytical systems consume it, and something has to get it from one place to the
other. That something is a **data pipeline**, a sequence of steps that extracts data
from a source, transforms it into a shape the destination can use, and loads it into
the target store. The two canonical patterns are **ETL** (extract-transform-load),
where transformation happens in transit before the data lands, and **ELT**
(extract-load-transform), where raw data lands first and gets transformed in place
afterward. The distinction matters for latency, cost, and where your business logic
lives, but both are pipelines: linear flows from a known source to a known destination,
processing data in batches on a schedule or streaming it near-real-time.

Pipelines are point-to-point by nature. Each one knows its source, its destination, and
its transformations. When you have a handful of operational databases feeding one
analytical warehouse, that directness is a virtue: the flow is legible, the ownership
is clear, and debugging means following a straight line. The trouble starts when the
number of sources and destinations grows. Each new source-destination pair typically
needs its own pipeline, and the total count grows as the product of sources and
destinations, not the sum. Back to that company with fifteen operational systems and
five analytical consumers: it doesn't end up with twenty pipelines, it ends up with
something closer to seventy-five, each with its own schedule, its own transformation
logic, and its own failure modes.

That's **pipeline sprawl**, and it's the defining limitation of the pattern. Nobody
"owns" the data flowing through a pipeline. The pipeline is plumbing, not a product.
When something breaks in the middle of one at 2 a.m., the question "whose problem is
this?" rarely has a clear answer. The data team owns the pipeline, but the domain team
owns the semantics, and neither has full context. It was exactly this sprawl, and the
operational fragility riding along with it, that the data warehouse was built to tame.

{% include excalidraw.html file="01-data-pipeline-architecture" alt="A network of point-to-point pipelines connecting operational systems to analytical consumers, illustrating the combinatorial growth of pipeline sprawl" caption="Figure 1.1: Pipeline sprawl: each source-destination pair requires its own pipeline, and the total grows as the product of sources and destinations." %}

## Data warehouses

Say the logistics domain needs a new dimension added to the warehouse. The request
goes to a central team, who have to learn enough about logistics to model it correctly,
weigh it against requests from every other domain, and land the schema change without
breaking downstream consumers. That request is the warehouse's whole story in
miniature.

A **data warehouse** is a centralized analytical store, purpose-built for structured
queries across the entire business. Where pipelines are plumbing, the warehouse is a
destination: a single place where data from every operational system arrives, gets
cleaned, modeled into a consistent schema, and becomes queryable by anyone with the
right access. The intellectual heritage runs through Kimball's dimensional modeling and
Inmon's enterprise data warehouse, with **star schemas**, **fact tables**, and
**dimension tables** all optimized for the aggregations and joins that business
intelligence tools need.

The warehouse's defining characteristic is **schema-on-write**. Data gets modeled and
validated before it's stored. That rigidity is a feature: it forces consistency, makes
the warehouse a governed single source of truth, and means that when two teams query
"total revenue last quarter," they get the same number. The warehouse solved the truth
problem pipeline sprawl created. Instead of every consumer building its own
understanding of the data from raw pipeline output, everyone queries the same curated
model.

But the limitation is organizational, not technical. The warehouse is owned by a
central data team (sometimes called the BI team, the analytics engineering team, or
the data platform team), and that team becomes a bottleneck in direct proportion to
the organization's growth. It owns all the data and understands none of the domains
that produced it.

Back to that logistics request: the analytical view stays hours or days behind the
operational truth, because the ingestion pipelines run on a schedule, and the central
team's capacity to model new data is the constraint on how fast the warehouse can grow.
As the organization adds domains and use cases, the central team processes more
requests than it can understand, and the queue itself becomes the bottleneck.

{% include excalidraw.html file="01-data-warehouse-architecture" alt="A centralized data warehouse receiving data from multiple operational systems through ingestion pipelines, with a central team owning the schema and all analytical consumers querying one governed store" caption="Figure 1.2: The data warehouse: a centralized, schema-on-write analytical store that solves the truth problem but concentrates ownership in a single team." %}

## Data lakes

A Kafka topic full of JSON events, a directory of Parquet files from a data science
experiment, a bucket of images for a computer vision model: none of that fits cleanly
into a warehouse. The **data lake** emerged as a response to exactly this format
rigidity. Where a warehouse demands that data conform to a schema before it can be
stored, a lake accepts data in any format (structured tables, semi-structured JSON and
XML, unstructured logs and text, binary blobs like images and sensor readings) and
defers schema decisions to the point of consumption. That's **schema-on-read**: the
data lands as-is, and the consumer applies a schema when querying it.

A well-run lake is organized into zones that reflect the data's maturity. The
**raw zone** (sometimes called the landing zone) holds data exactly as it arrived from
the source systems: untouched, append-only, the system of record. The **curated zone**
holds data that's been cleaned, validated, deduplicated, and enriched, still at its
original grain but trustworthy. The **refined zone** holds data that's been modeled
and aggregated for specific consumption patterns such as analytics, dashboards, or ML
feature stores. Raw to curated to refined is a progression of increasing transformation
and decreasing generality.

The lake solved the warehouse's most visible problem. At massive scale, with cheap
object storage, it makes it economically feasible to keep *everything* and decide
later what's worth querying. That flexibility unlocked machine learning, unstructured
analytics, and exploratory data science, workloads warehouses were never built for.

But the limitation is governance. Without active curation, a lake becomes the **data
swamp**, a term so common in the field it's practically a synonym for a poorly-run one.
Undocumented datasets pile up. Nobody knows which version of the customer table is
authoritative, which datasets are stale, which ones duplicate each other under
different names.

The curation effort needed to keep a lake useful re-creates much of the warehouse's
modeling and governance work, just without the warehouse's enforcement mechanisms.
And the organizational problem doesn't go away: a central team still owns the lake,
still can't understand every domain's data, still bottlenecks on the same requests.
The technology changed, from rigid schema to flexible storage, but the shape of the
organization didn't.

{% include excalidraw.html file="01-data-lake-architecture" alt="A data lake with raw, curated, and refined zones, showing heterogeneous data formats flowing in and the risk of the lake becoming a swamp without active governance" caption="Figure 1.3: The data lake: schema-on-read and format flexibility, but without governance, the lake becomes a swamp, and the central-team bottleneck remains." %}

## How data mesh differs

Three patterns so far (pipelines, warehouses, lakes), and all three centralize data and
hand ownership to a single team. The technology improves with each generation: bespoke
point-to-point plumbing, then a governed analytical store, then a flexible
format-agnostic lake.

But the organizational shape stays the same every time. One team at the center,
receiving requests from every domain, owning data it didn't produce, modeling concepts
it doesn't deeply understand, and scaling its capacity linearly while the demands on it
grow combinatorially.

The **data mesh** proposes a different axis of change entirely. Instead of building a
better center, it decentralizes ownership to the domain teams that produce the data.
Each domain owns its data as a product: discoverable, addressable, trustworthy,
self-describing, and published for other domains to consume.

A shared **self-serve data platform** provides the infrastructure every domain needs
(streaming, storage, observability, schema registries) so domain teams don't each build
their own. And **federated computational governance** keeps the independently-owned
products interoperable, not through review boards and policy documents but through
standards the platform enforces automatically.

That's a different kind of answer because it changes the organizational shape, not
just the technology. A domain team that understands its own data curates it, models
it, documents it, and stands behind it the way a product team stands behind a product.
The central team's role shifts from owning every dataset to providing the platform and
enforcing the standards: a fundamentally different scaling model.

One clarification worth making explicit: the mesh isn't a replacement for warehouses
or lakes. A domain may still use a warehouse or a lake internally. The order-analytics
domain might store its refined data in a Parquet-based lakehouse, and that's fine. The
reorganization is about *who owns the data*, not which storage technology to use. The
mesh answers "how does this organization scale its data architecture?", not "which
database should this team pick?"

The mesh's complexity pays off in organizations with many domains, many data
consumers, and the operational maturity to sustain federated ownership. For smaller
teams, simpler data flows, or organizations where the central team isn't yet the
bottleneck, a well-run warehouse or a governed lake may be exactly the right answer.
The mesh isn't an upgrade in a linear progression. It's a different tool for a
different problem.

{% include excalidraw.html file="01-data-mesh-decentralized" alt="A data mesh with domain teams owning their data as products, a shared self-serve platform underneath, and federated governance keeping the products interoperable" caption="Figure 1.4: The data mesh: domain teams own their data as products, a shared platform provides infrastructure, and federated governance keeps the products interoperable." %}

## The evolution, and when each pattern fits

The progression from pipelines to warehouses to lakes to mesh isn't a replacement
chain where each generation obsoletes the last. It's an expansion of the problem
space. Pipelines solved the **movement problem**: getting data from where it's
produced to where it's consumed. Warehouses solved the **truth problem**: creating a
single governed view of the business from the chaos of independent pipelines. Lakes
solved the **flexibility problem**: accommodating the formats and workloads that
warehouses were too rigid to handle. The mesh solves the **organizational scaling
problem**: restructuring ownership so the central team is no longer the bottleneck on
every domain's data needs.

Each pattern is still valid when its problem is the dominant one. The choice depends
on the organization's scale, its data landscape, and where the bottleneck actually
sits:

- **Pipelines** are the right answer when you have a small number of well-understood
  integrations, the data flows are stable, and there is no pressing need for
  centralized cross-domain analytics. The plumbing is simple enough that the sprawl
  hasn't started.

- **A data warehouse** fits when the organization needs a reliable, governed
  analytical view of the business (BI dashboards, executive reporting, structured
  decision-making) and a central team has the capacity to curate and model the data.
  The bottleneck is not yet the central team's bandwidth but the absence of a single
  source of truth.

- **A data lake** fits when the data is heterogeneous (logs, events, unstructured
  content, ML training sets) and the scale or the workload patterns (exploratory
  analysis, feature engineering, large-scale batch processing) exceed what a
  warehouse handles well. The bottleneck is format rigidity, not organizational
  ownership.

- **A data mesh** fits when the organization has many domains, many data consumers,
  and the central team has become the constraint. The bottleneck is organizational
  (who owns what, who can ship what, who understands what), not technical. The
  organization needs the maturity to operate federated ownership: domain teams that
  can treat data as a product, a platform team that can provide self-serve
  infrastructure, and a governance model that works through automation rather than
  approvals.

{% include excalidraw.html file="01-architecture-evolution" alt="The evolution from pipelines to warehouses to lakes to mesh, showing the problem each pattern solves and the bottleneck each one leaves behind" caption="Figure 1.5: The evolution: each pattern solves a different problem, and each remains the right answer when that problem is the dominant one." %}

With this landscape in place, the next page defines data mesh precisely: what
Dehghani's four principles are, how they interlock, and why implementing one without
the others produces a distributed mess rather than a mesh.

[Concepts & principles]({{ '/docs/01-concepts/' | relative_url }}).

## For deeper coverage

- [*Data Mesh*](https://www.oreilly.com/library/view/data-mesh/9781492092384/) by Zhamak Dehghani: the full argument for why pipelines, warehouses,
  and lakes hit an organizational ceiling, and what the mesh changes.
- [*Designing Data-Intensive Applications, 2nd ed.*](https://www.oreilly.com/library/view/designing-data-intensive-applications/9781098119058/) by Martin Kleppmann & Chris
  Riccomini: the systems-level treatment of batch and stream processing, ETL/ELT,
  and the storage engines behind warehouses and lakes.
- [*Cloud Native Anti-Patterns*](https://www.packtpub.com/en-us/product/cloud-native-anti-patterns-9781836200581) by Gerald Bachlmayr et al.: common organizational and
  architectural failure modes, including the centralized-ownership trap this chapter
  describes.
- [*Cloud Native Patterns*](https://www.manning.com/books/cloud-native-patterns) by Cornelia Davis: the platform-level patterns a self-serve
  data platform draws on once the organizational shift is underway.
