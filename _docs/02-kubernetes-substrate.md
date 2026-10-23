---
title: "Kubernetes as the substrate"
order: 3
description: Why Kubernetes is a natural substrate for a data mesh, and how the four principles map onto namespaces, operators, RBAC, and platform primitives.
duration: 15 min
---

## Learning objectives

By the end of this chapter you can:

- Map each of Dehghani's four principles to the specific Kubernetes primitive that
  realizes it (namespaces/RBAC, Deployments/CRDs, operators, admission control).
- Describe the three horizontal tiers of this final project's architecture and which
  protocol crosses each boundary.
- Explain why this final project runs on minikube with the docker driver and containerd
  runtime, and what trade-off a single-node cluster makes.
- State how the final project exposes host access (NodePorts published on `127.0.0.1` at
  profile creation) and what command recreates the profile if the published ports
  need to change.

## Why this matters

A domain team that needs Kafka in this build doesn't learn to operate Kafka. It asks
the platform's Kafka operator for a cluster and gets one. That's one of four principles
this page maps onto a concrete Kubernetes primitive, and it's a good preview of the
whole argument.

The [previous page]({{ '/docs/01-concepts/' | relative_url }}) ended on a claim: a data
mesh is a pattern, not a tool, and the tools are expressions of it. So why build the
final project on Kubernetes at all? Because the four principles map onto Kubernetes
primitives unusually cleanly, cleanly enough that "implement a data mesh on Kubernetes"
stops feeling like a translation exercise and starts feeling like the primitives were
waiting for it. This page makes that mapping explicit, then shows the shape of the
system you'll build on top of it.

## Why the alignment is so good

Kubernetes was designed around multi-tenancy, declarative resources, an extensible
type system, and operators that turn operational knowledge into software. Those happen
to be exactly the capabilities a data mesh needs: a place for each domain to own its
slice, a way to express a data product as a deployable artifact with a contract, a
shared platform layer domains consume without building it themselves, and a boundary
where standards get enforced automatically. You *can* build a data mesh without
Kubernetes, and you can certainly run Kubernetes without building a mesh. But the
alignment is strong enough that each principle has a natural home in Kubernetes
primitives you already know.

## The four principles, mapped to primitives

**Domain ownership maps to namespaces, ServiceAccounts, RBAC, quotas.** The unit of
tenancy in Kubernetes is the namespace. It carries identities through ServiceAccounts,
permissions through Roles and RoleBindings, and a resource budget through quotas, all
scoped to that one namespace. That's precisely the boundary a domain needs: a place it
owns, with access it controls and a budget it lives within, isolated from other domains
by default. A domain team gets a namespace the way a microservice team gets a
repository.

**Data as a product maps to Deployments, Services, and CRDs.** A data product is a
deployable artifact that exposes a contract, which is exactly what a Deployment plus a
Service *is*. The Deployment runs the product; the Service is its stable address. And
because Kubernetes lets you extend its own type system with Custom Resource
Definitions, the platform can offer domain-specific types (a Kafka `Topic`, a Postgres
`Cluster`, a schema registration) that a domain declares the same way it declares a
Deployment. The data product becomes a first-class, declarable thing rather than an
informal collection of scripts.

**Self-serve data platform maps to operators and shared cluster infrastructure.** A
domain team that needs Kafka doesn't learn to operate Kafka here. It asks the
platform's Kafka operator for a cluster and gets one. That's where Kubernetes operators
deliver the most value for a self-serve platform: an *operator* packages the knowledge
of how to run a complex stateful system (Kafka, Postgres, autoscaling, a service mesh)
into a controller that reconciles a simple declarative request into a running system.
In this build the event backbone (via its operator), the database (via its operator),
autoscaling, the service mesh, and the observability stack are all shared platform
infrastructure the domains consume by declaration. That's the self-serve principle made
literal.

![The three planes of the self-serve data platform]({{ '/assets/diagrams/17-platform-planes.svg' | relative_url }})

**Federated computational governance maps to admission control, policy engines, mesh
policy, CRD validation.** Governance in a mesh is supposed to be enforced by the
platform, automatically, at the boundary, not by review meetings after the fact.
Kubernetes has several boundaries where that enforcement lives: admission controllers
and policy engines that accept or reject resources as they're created, service-mesh
authorization and mutual-TLS policies that govern traffic between products, and the
schema validation built into every CRD. The rules become code that runs at the edge of
the system, which is exactly what "computational governance" means.

![Each of the four principles and the OpenShift/Kubernetes pieces that deliver it: one picture of the mapping]({{ '/assets/diagrams/17-principles-to-pieces.svg' | relative_url }})

## The shape of the system

With the mapping in hand, here's the system this final project builds. Three
horizontal tiers: **external clients** at the top, the **service mesh** running the
domain services in the middle, and the **self-serve platform** providing shared
infrastructure underneath.

![The final project's architecture: data mesh on minikube]({{ '/assets/diagrams/17-final-project-data-mesh.svg' | relative_url }})

The diagram doubles as a map of the protocol decisions, which the
[data planes page]({{ '/docs/05-data-planes/' | relative_url }}) develops
in full: REST crosses the ingress between external clients and services, gRPC flows
synchronously between services inside the mesh, GraphQL composes reads across services
through a dedicated gateway, and the event backbone carries events asynchronously from
producers to consumers. Telemetry flows out of every service to the observability
stack, the subject of the
[observability page]({{ '/docs/08-observability/' | relative_url }}).

Read top to bottom, and the diagram is the four principles again: external clients
consume products through stable contracts (data as a product), the domain services each
own their slice of the mesh (domain ownership), the platform tier underneath is shared
and consumed by declaration (self-serve platform), and the mesh and policy layers
enforce the rules on the traffic between everything (federated governance). It's the
picture to return to as the rest of the set works through the parts.

## A note on minikube specifically

This final project runs on minikube, a single-node Kubernetes cluster, which is the
right choice for *learning* the pattern and wrong for running it in production. A
single node means every tier shares one machine's resources. That keeps the whole mesh
runnable on a laptop, but it also concentrates failure modes that a real multi-node
cluster would spread out.

Where those single-node realities bite (resource ceilings, node-level decay, the
operational care a long-lived single-node cluster needs), they're collected as
operational gotchas rather than mixed into the conceptual material here, because
they're particular to this deployment choice rather than to data mesh as a pattern.

The profile itself is a Docker container (the docker driver) running containerd with
the runc runtime, sized by `MINIKUBE_MEMORY`, `MINIKUBE_CPUS` and `MINIKUBE_DISK`.

### Host access

Host access follows the same single-node logic. The final project's UIs and service
endpoints are NodePorts published on `127.0.0.1` when the minikube profile is created
(`--ports=127.0.0.1:<hostPort>:<nodePort>`), never SSH tunnels or port-forwarding. <!-- forbidden-ok -->

The ports are fixed at creation, so changing the published set means recreating the
profile with `./scripts/setup-datamesh-profile.sh --replace`. `--replace` deletes and
recreates the cluster, so run `./scripts/bootstrap-datamesh.sh` again afterwards.

Run the workshop in isolation: shut down CRC, other minikube profiles, and other
workloads first, so the host ports are free. `./scripts/show-endpoints.sh` prints what
is published and reachable.

## For deeper coverage

- [*Kubernetes Patterns*](https://www.oreilly.com/library/view/-/9781098131678/) by Bilgin Ibryam & Roland Huß: the primitive-by-primitive
  treatment (namespaces, operators, CRDs) this chapter's mapping draws on.
- [*Platform Engineering on Kubernetes*](https://www.manning.com/books/platform-engineering-on-kubernetes) by Mauricio Salatino: the self-serve platform
  principle built out as an operating model, not just a set of operators.
- [*Cloud Native Patterns*](https://www.manning.com/books/cloud-native-patterns) by Cornelia Davis: the broader cloud-native platform
  patterns this final project's shared infrastructure tier follows.
- [Kubernetes documentation](https://kubernetes.io/docs/): namespaces, RBAC, CRDs,
  and admission control, straight from the source.
- [minikube documentation](https://minikube.sigs.k8s.io/docs/): driver and runtime
  options, including the docker driver and containerd runtime this final project uses.

Next, the services themselves: what a data product looks like in this build, the
order-service template the others follow, and how each one is packaged and shipped.
