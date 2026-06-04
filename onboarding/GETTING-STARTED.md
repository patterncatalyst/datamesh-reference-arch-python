# Getting started with the data-mesh reference architecture

This document is the orientation guide for using this repo. The published
site is the canonical reading order; this document is the "how to use this
repo" companion that points you at the right entry point depending on what
you came for.

---

## What this reference is, and isn't

The reference is a working, runnable implementation of a data mesh in
Python — five domain services plus a GraphQL gateway, communicating over a
deliberate mix of REST, gRPC, GraphQL, and Kafka events, with versioned
contracts, a discovery catalog, progressive delivery via a service mesh,
event-driven autoscaling, and end-to-end observability.

**The model is Kubernetes.** Every architectural choice (namespaces as
tenancy boundaries, operators delivering platform services, CRDs as
declarative APIs, a service mesh for cross-product policy and tracing) is
made in terms of Kubernetes primitives. Anything that runs vanilla
Kubernetes runs this reference conceptually — OpenShift, EKS, GKE, AKS,
vanilla K8s on bare metal — with adaptation for the specifics each runtime
inherits.

**The verified runtime is minikube.** The exact implementation in
`examples/lgtm-datamesh/` was developed and tested on minikube on Fedora 44
with rootless podman. The bootstrap script knows that environment well, the
chart values are sized for it, the demos are tuned to it. Other runtimes
will work, but the bootstrap will need translation; the chart values may
need re-sizing; some operator install steps will be different.

**The implementation deck pairs this with OpenShift.** The deck under
`presentation/data-mesh-openshift/` works through the same reference
with OpenShift-specific vocabulary — Projects (instead of namespaces),
OperatorHub and OLM (instead of `helm install` of upstream operators),
Red Hat OpenShift Service Mesh (instead of stock Istio), AMQ Streams
(instead of Strimzi), and so on. The principles are identical; the platform
names differ. The closing summary section of the reading set (`/docs/10-summary/`)
includes the implementation-deck diagrams as a worked example of "what the
same principles look like in OpenShift vocabulary."

If your platform is OpenShift, the deck plus the reading set together are
the resource. If your platform is something else, the reading set is the
resource and the example tree is the laptop-runnable starting point you
adapt.

---

## Three audiences, three entry points

**1. The conceptual reader** wants to understand data mesh as an idea — the
four principles, the operational/analytical handoff, what distinguishes a
mesh from a service-oriented architecture. Read the conceptual pages on the
published site:

- [Concepts & principles](https://patterncatalyst.github.io/datamesh-reference-arch-python/docs/01-concepts/)
- [Anti-patterns](https://patterncatalyst.github.io/datamesh-reference-arch-python/docs/09-anti-patterns/)
- [Summary](https://patterncatalyst.github.io/datamesh-reference-arch-python/docs/10-summary/)

20–30 minutes total. No cluster required.

**2. The implementation reader** wants the design choices: why this set of
services, why these protocols, why these tools, what trade-offs were
deliberate. Read the set straight through from
[the index](https://patterncatalyst.github.io/datamesh-reference-arch-python/docs/00-index/).
About 2 hours of reading; the prose calls out runtime-portable choices versus
minikube-specific ones where the distinction matters.

**3. The builder** wants a running system on a laptop. Skip ahead to
`examples/lgtm-datamesh/` and follow the README there. The bootstrap is
ten steps and brings up the whole stack on a minikube profile sized for
the workload.

---

## Prerequisites for the runnable code

What's verified to work end to end:

- **Host:** Fedora 44 with rootless podman as the container runtime
- **Memory:** 64 GB RAM (the `capstone` minikube profile uses 24 GB; the
  rest is host headroom for IDEs, browsers, and host services)
- **Disk:** 1 TB total, with ≥30 GB free for image cache and persistent
  volumes
- **Kernel:** `fs.inotify.max_user_instances` raised (the bootstrap audits
  this and prints the exact `sysctl` command if it isn't)
- **Tooling:** minikube, kubectl, helm
- **Network:** outbound HTTPS to pull images, charts, and operators

What probably works but isn't verified: other Fedora versions, RHEL,
Ubuntu, macOS via Lima or Docker Desktop, and any host with enough RAM and
a rootless container runtime. If you're on one of those, the bootstrap may
need small adaptations; read it before running it.

What won't work: anything with less than ~24 GB free RAM for the cluster,
or runtimes without rootless containers (the chart assumes them).

---

## The bootstrap

```bash
cd examples/lgtm-datamesh
./scripts/bootstrap-capstone.sh
```

Ten steps; ~25 minutes on a warm cache, longer on the first run while
images download. Each step's success criterion is printed, and the script
stops on the first failure with a hint about what to look at next.

Once the bootstrap is green, the five-act presenter walkthrough exercises
the whole system end to end:

```bash
./demos/walkthrough.sh
```

Press Enter between acts. The five acts (trace, scale, canary, lineage,
topology) correspond directly to the "what you can see it do" section of
the implementation deck.

---

## How to navigate as a reader of source

The high-level map of the repo:

- **`_docs/`** is the reading set, rendered on the published site at
  `/docs/<name>/`.
- **`examples/lgtm-datamesh/`** is the runnable code. The sub-trees mirror
  the reading set's concerns: `charts/` for helm; `services/` for the five
  domain services plus gateway; `istio/`, `keda/`, `observability/`,
  `openmetadata/` for the platform components; `demos/` for the smoke
  scripts and the walkthrough orchestrator; `scripts/` for bootstrap,
  per-component setup, and teardown.
- **`assets/diagrams/`** holds paired SVG + Excalidraw sources for every
  figure on the site. Edit the `.excalidraw` source, re-export the SVG,
  commit both.
- **`presentation/`** holds two paired decks: the conceptual
  *Data Mesh 101* and the implementation *Data Mesh on OpenShift*. Both
  are .pptx with speaker notes; the OpenShift deck's speaker notes
  document the current demo state including any deferred upstream issues.
- **`_plans/`** is decision-log and reconciliation tracking. Active
  decisions live in `_plans/decisions.md` (DRA-001 forward); historical
  decisions from when this lived as the §17 capstone of
  `minikube-on-fedora` are preserved at `_plans/archive/` for the audit
  trail.

---

## How to contribute

For non-trivial changes, open an issue first. The decision-log entries in
`_plans/decisions.md` are the contract for what's intentional in the
design — anything that touches that contract needs discussion before
code. Small fixes, doc improvements, typos, and additions to the
runnable examples that match existing patterns are welcome as direct PRs.

If you're proposing a non-minikube runtime (e.g. EKS or OpenShift
local), the most useful contribution is a sibling to
`examples/lgtm-datamesh/scripts/bootstrap-capstone.sh` that does the
runtime-specific setup, plus a `README.md` documenting any deltas. The
existing bootstrap can serve as the template.
