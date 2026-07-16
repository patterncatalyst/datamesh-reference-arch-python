---
title: "Summary — the four principles, realized"
order: 11
description: A closing summary — for each of the four data-mesh principles, the value it delivers, the implementation pieces that realize it, and what happens without it.
duration: 10 min
---

The reading set has worked through the data mesh implementation by
*concern* — substrate, services, contracts, planes, mesh, scaling,
observability, failure modes. This closing page reorganizes the same
material by *principle*. For each of Dehghani's four principles, you'll
see the value the principle delivers when it's honored, the concrete
implementation pieces in this reference that realize it, and the failure
mode that shows up when the principle is missing.

The diagrams on this page are reproduced from the implementation deck at
`presentation/data-mesh-openshift/`. Because the deck pairs this reference
with OpenShift specifically, the diagrams use OpenShift vocabulary in a few
places — *Project* for namespace, *SCCs* for PodSecurity, *OperatorHub /
OLM* for the operator install path, *AMQ Streams* for Strimzi, *CNPG* for
CloudNativePG. The principles and the implementation pieces themselves are
runtime-agnostic; the OpenShift framing is one concrete instance of the
same shape. If your runtime is something else (vanilla Kubernetes, EKS,
GKE, AKS, minikube), the substitutions are direct: read *Project* as
namespace, *SCCs* as PodSecurity, *OperatorHub* as `helm install` of the
relevant operators, and so on.

The reference's own runnable implementation lives in
`examples/lgtm-datamesh/` and runs on a minikube profile — verified
configuration for laptop reproducibility — but every choice it makes is
recognizable on any compliant Kubernetes cluster.

## Principle 01 — Domain ownership

Each domain ships its data product on its own, with a clear owner and an
enforced boundary. No central data team sits in the path between the
domain that produces the data and the domains that consume it. The
platform's job is to enforce the boundaries; the domain's job is to fill
them with a working product.

The value of getting this right is that ownership is unambiguous. There's
one team responsible for the customer data product, one team responsible
for orders, one team responsible for inventory. Decisions about what
those products look like, how they evolve, and what guarantees they
provide are made by the people closest to the work.

![Principle 01 realized — domain ownership and the implementation pieces that deliver it]({{ '/assets/diagrams/17-value-domain-ownership.svg' | relative_url }})

In Kubernetes terms, the boundary is the *namespace*. Each domain gets a
namespace (an OpenShift Project, on that runtime), and the platform
enforces ownership through namespace-scoped RBAC (the domain team owns
inside, nothing reaches across), pod security policies (PodSecurity
admission on vanilla K8s, Security Context Constraints on OpenShift) that
constrain what the domain's workloads may do on the node, and
ResourceQuotas that prevent any single domain from starving the cluster
of capacity another domain needs.

The reference's order, inventory, payment, shipping, and notification
domains each live in their own namespace. The reference uses a single
shared `capstone` namespace for the demo's clarity, but the production
shape is one namespace per domain — the reference's helm chart structure
supports that directly.

Without this principle: fuzzy boundaries and ownership vacuums. Data that
nobody owns is modeled three different ways by three different teams. The
mesh becomes a misnomer; it's a centralized data lake with extra steps.

## Principle 02 — Data as a product

A data product is *discoverable*, *addressable*, *trustworthy*, and
*self-describing*. Consumers find it through a catalog rather than
through a relationship with the producing team. They depend on it
through a versioned contract rather than a phone call. They trust it
because the platform — not a tribal knowledge channel — enforces the
guarantees.

The value of getting this right is that consumption decouples from
production. A consumer doesn't need to know which team owns a data
product; they need to know what the product is, what it guarantees,
and how to address it.

![Principle 02 realized — data as a product and the implementation pieces that deliver it]({{ '/assets/diagrams/17-value-data-product.svg' | relative_url }})

The implementation pieces that realize this in the reference: every
service's Deployment + Service makes the product *addressable* — a
domain consumer reaches `order-service.capstone.svc.cluster.local` and
gets the order product. The Apicurio schema registry holds the
*versioned contracts* — OpenAPI for REST, Protobuf for gRPC, AsyncAPI
for the Kafka events — and rejects breaking changes at registration
time. OpenMetadata is the catalog of *discoverability*: every product
in the mesh is listed, with its owner, its schema, its lineage, and
its consumption pattern. CRDs (custom resource definitions) carry
*domain-specific types* declared like any other Kubernetes object, so
the platform's admission policies can enforce mesh-wide standards
about what a data product must look like before it's deployable.

The four pieces together make a product self-describing: you can
discover it (catalog), depend on its shape (contract), reach it
(addressable Service), and verify it conforms to mesh standards (CRD +
admission).

Without this principle: "dumb" data products — renamed tables with no
contract that can't serve themselves, govern themselves, or describe
themselves to consumers. Discovery becomes a Slack channel; trust
becomes word-of-mouth; governance has nowhere to live.

## Principle 03 — Self-serve data platform

Domains consume the platform's capabilities (streaming, databases,
scaling, the mesh itself) *by declaration*. They don't operate the
substrate. The platform team's job is to make the right things easy
and the wrong things hard; the domain team's job is to declare what
its product needs and let the platform deliver it.

The value of getting this right is that the platform stops being a
bottleneck. Each domain can ship without waiting for the platform team
to provision a queue, stand up a database, configure scaling, or wire
in observability. The declarative pattern means the platform team
scales by *adding capabilities*, not by *processing tickets*.

![Principle 03 realized — self-serve platform and the implementation pieces that deliver it]({{ '/assets/diagrams/17-value-self-serve.svg' | relative_url }})

The implementation pieces: the operator pattern (OperatorHub / OLM on
OpenShift; `helm install` of upstream operators on other runtimes)
makes platform capabilities *curated and lifecycle-managed* — install
once, every domain consumes by declaration. Strimzi (AMQ Streams on
OpenShift) makes Kafka available *as a custom resource*: a domain
declares its consumer group; the operator handles the cluster.
CloudNativePG (CNPG) does the same for Postgres: a domain declares its
database; the operator handles the cluster, the backups, the failover.
KEDA makes elastic scaling — including scale-to-zero — available as a
ScaledObject, the same way: declare the demand signal, the operator
handles the scaling. GitOps closes the loop by making the whole mesh
*reproducible from Git*: every namespace, every operator, every
ScaledObject, every Istio policy lives in a repo and is the source of
truth.

Without this principle: every domain reinvents the same infrastructure
badly. Ownership fragments into shadow platform teams — each domain
builds its own Kafka cluster, its own database, its own scaling logic
— and the cost of the duplication is hidden in domain budgets where
nobody sees it as a platform-investment problem.

## Principle 04 — Federated computational governance

Global rules (security policy, contract-versioning rules, observability
standards, data-classification rules) are enforced *by the platform*,
*automatically*, *at the boundary*. Standards hold across the mesh
while ownership stays decentralized. Governance isn't a review meeting
after the fact; it's code that runs at the points where data products
enter the system.

The value of getting this right is that decentralization doesn't
require giving up consistency. Every domain can ship independently
*because* the platform is enforcing the shared rules automatically.

![Principle 04 realized — federated computational governance and the implementation pieces that deliver it]({{ '/assets/diagrams/17-value-governance.svg' | relative_url }})

The implementation pieces: service-mesh mTLS makes every product-to-product
call authenticated and encrypted, without any application code knowing
about TLS. Istio's traffic-management primitives (VirtualService,
DestinationRule, the canary subset routing the reference uses for the
v1→v2 contract demo) make *progressive delivery* a platform capability —
a contract evolves under controlled traffic, weight-shifted live, with
the application layer unchanged. Kubernetes admission policies (ValidatingAdmissionPolicy
on modern K8s, OPA/Gatekeeper or Kyverno on older clusters) enforce
mesh-wide invariants: every data product carries an owner annotation,
every namespace carries a domain label, every Deployment has its
resource requests set. Prometheus/Tempo/Grafana/Kiali make governance
*observable*: the metrics show the mesh's behavior, the traces show
cross-product dependencies, the topology shows who's calling whom in
real time. That visibility is the feedback loop that makes governance
actually work — without it, governance is theatre.

Without this principle: governance bolted on from outside the platform
never fits, or worse, re-centralizes into an approval bottleneck — the
mesh's own anti-pattern of "federated governance" implemented as a
review board. The
[anti-patterns page]({{ '/docs/09-anti-patterns/' | relative_url }})
walks through this failure mode in more detail.

## A trusted base for every data product

One more piece, beyond the four principles: the supply chain. Every
data product in the mesh ships as a container image, and the platform's
job extends to giving every domain a *trusted base* to layer on.

![A trusted base for every data product — the supply chain the platform gives each domain]({{ '/assets/diagrams/17-trusted-supply-chain.svg' | relative_url }})

The deck pairs this reference with OpenShift's specific supply chain:
Red Hat Universal Base Image (UBI) — `ubi9/python-311` is the base for
every Python service in the reference. UBI is freely redistributable
and enterprise-maintained, which means a domain team gets a base image
they can use without licensing constraints and that's patched on a
regular cadence by Red Hat. Language dependencies come from Red Hat's
verified channels or PyPI, with known provenance; the resulting images
are signed and have an SBOM, and admission policies verify both before
the image runs. The domain's data product layers its FastAPI / gRPC /
Strawberry code on top of the trusted base — the domain owns its
application; the platform owns the base.

On other runtimes, the supply-chain shape is the same: a curated base
image (Distroless, Chainguard, Alpine, plain Debian — choose by your
trust model), language dependencies from controlled channels, signed
images, an SBOM at build time, and admission policies that verify both.
The reference's bootstrap uses UBI because the implementation deck
pairs with OpenShift; the substitution to another base is a single
line in each service's Dockerfile.

The reason the supply chain belongs in this summary is that it's the
piece of the mesh that's most often missed in discussion. Domains can
own their products, products can be discoverable and self-describing,
the platform can be self-serve, and governance can be federated — and
none of that matters if the base images are unpatched. The mesh's
weakest link is the layer underneath everyone's application code.

## Where to go from here

This reference is one worked example. The principles it implements are
runtime-agnostic; the specific implementation pieces are one good
choice among several reasonable choices for each. If you're starting
your own data mesh on Kubernetes, the pattern is:

1. **Read this set straight through once** for the shape of the system,
   then once more for the trade-offs.
2. **Run the example tree** to see the cross-product behaviors live —
   the trace tree across three products, the canary contract evolution
   under live traffic, the autoscaler reacting to a Kafka backlog.
3. **Use the decision log** at `_plans/archive/capstone-decisions.md`
   to understand the *reasoning* for each implementation choice, not
   just the choice itself. The rejected alternatives are where the
   institutional memory of the build lives.
4. **Adapt to your runtime** by swapping the substitutions: namespace
   for Project, PodSecurity for SCCs, `helm install` for OperatorHub.
   The reference's chart structure is set up to make this tractable;
   the bootstrap script is one of the natural places to fork.

The reference's most important property is that the principles and
their implementation pieces are *visible together*. Conceptual material
gives you the principles; vendor material gives you the pieces. This
reference's job is to be the bridge — concrete enough to be runnable,
explicit enough about its choices to be portable.
