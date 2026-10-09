# lgtm-datamesh — the runnable data-mesh reference

The full implementation of the data-mesh reference: seven Python/FastAPI
services exposing REST, gRPC, GraphQL, and Kafka interfaces, deployed via
helm to a dedicated minikube profile, with full observability, contracts
and a catalog, Istio service mesh with canary delivery, KEDA autoscaling,
and an end-to-end presenter walkthrough that exercises all of it.

This is the **runnable counterpart** to the reading set on the published
site (`_docs/00-index.md` through `_docs/10-summary.md`). Read the
reading set for the conceptual and design background; this README is the
operational entry point for actually running the system.

The example tree was originally `examples/17-capstone/` in the parent
repo `patterncatalyst/minikube-on-fedora`; it was renamed to
`lgtm-datamesh` when this repo was forked out, to disambiguate it from
the parent's `17-capstone` example (which still exists for readers
arriving via the minikube tutorial).

## Quick-start checklist

Before running anything, verify these four prerequisites:

1. **Docker Engine** — running, with your user in the `docker` group
2. **inotify limits** — raised above Fedora defaults
3. **Tooling** — minikube >= 1.39.0, kubectl 1.36, helm, istioctl 1.31.1 + full Istio
   distribution (see [Required tooling](#required-tooling))
4. **Bootstrap** — `./scripts/bootstrap-capstone.sh`

Once that's green, the presenter walkthrough exercises end-to-end
behavior across five acts (trace, scale, canary, lineage, topology):

```bash
./demos/walkthrough.sh
```

Each act presses Enter to advance.

## Directory layout

```
examples/lgtm-datamesh/
├── README.md                ← this file
├── README.archive.md        ← the original capstone-era README
├── charts/                  ← helm charts for every component
│   └── capstone/            ← umbrella chart
├── scripts/                 ← bootstrap, setup-* helpers per component,
│                              restore-baseline, teardown
├── proto/                   ← protobuf definitions for the gRPC services
├── postman/                 ← Postman collection for live API demos
├── demos/                   ← demo-* scripts + walkthrough.sh orchestrator
└── services/                ← source for the 7 services + GraphQL gateway
    ├── order-service/
    ├── inventory-service/
    ├── payment-service/
    ├── shipping-service/
    ├── notification-service/
    ├── review-service/
    └── graphql-gateway/
```

## Configuration

The umbrella chart's `values.yaml` has feature flags for every component;
set any to `enabled: false` for a partial-stack deploy. Useful when
debugging a specific service in isolation or when the host is
RAM-constrained.

## Prerequisites (verified configuration)

### Hardware & OS

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| OS | Fedora 44 | Docker Engine (docker-ce) as the container runtime |
| RAM | 64 GB | the `capstone` minikube profile uses 24 GB; rest is host headroom |
| Disk | 1 TB | about 100 GB free under the Docker data root (`/var/lib/docker`) |
| CPU | 16 vCPU recommended | not strictly required but the stack is heavy |

### Container engine & host tuning

The capstone runs on **Docker Engine** (native docker-ce). The
scripts are supported on Fedora and RHEL hosts (bare metal or VM). A VM-based
engine such as Docker Desktop also works if its VM is sized for the node; it
is never required.
Start flags: `--driver=docker --container-runtime=containerd
--addons=metrics-server`. Docker group membership is root-equivalent on the
host.
Podman: used only by the optional OpenShift (CRC) appendix. <!-- forbidden-ok -->

**Upgrading from an earlier (rootless podman) capstone profile.** <!-- forbidden-ok -->
Delete the old profile first, then clear the setting, then run setup: <!-- forbidden-ok -->

```bash
MINIKUBE_ROOTLESS=true minikube delete -p capstone   # forbidden-ok
minikube config unset rootless                        # forbidden-ok
./scripts/setup-capstone-profile.sh
```

Profile sizing defaults can be overridden before bootstrap:

```bash
MINIKUBE_CPUS=16 MINIKUBE_MEMORY=24g MINIKUBE_DISK=80g ./scripts/bootstrap-capstone.sh
```

**inotify limits.** The capstone runs many controllers; Fedora's default
of 128 instances is not enough:

```bash
sudo sh -c 'printf "fs.inotify.max_user_instances = 512\nfs.inotify.max_user_watches = 524288\n" \
    > /etc/sysctl.d/99-kubernetes.conf'
sudo sysctl -p /etc/sysctl.d/99-kubernetes.conf
```

The profile setup script checks the engine and the inotify limits and prints the same fixes.

### Required tooling

| Tool | Minimum version | Notes |
|------|----------------|-------|
| minikube | **1.39.0** | the profile pins Kubernetes v1.36.5 (`KUBE_VERSION` overrides it) |
| kubectl | 1.36.x | match the cluster's minor (v1.36.5) |
| helm | 3.x | |
| istioctl | **1.31.1** | `setup-istio.sh` refuses any other client version; needs the full Istio distribution, not just the binary — `setup-kiali.sh` applies `samples/addons/kiali.yaml` from it |

Every platform component is pinned to an exact release (newest stable as of
2026-10-09, DRA-020): KEDA 2.21.0 + HTTP add-on 0.16.0, Strimzi 1.2.0 with
Kafka 4.3.1, CloudNativePG chart 0.29.1 (operator 1.30.1) with
`postgresql:18.6-standard-trixie`, Apicurio 3.3.3, OpenMetadata 2.0.5 with
OpenSearch 3.4.0, and the prometheus 29.36.1 / grafana 13.4.0 / tempo 3.1.0
charts. Services build on `ubi10/python-314-minimal`.

**Installing the Istio distribution:**

```bash
curl -fsSL https://github.com/istio/istio/releases/download/1.31.1/istio-1.31.1-linux-amd64.tar.gz \
    | tar xz -C ~/.local/share
ln -sfn ~/.local/share/istio-1.31.1 ~/.local/share/istio-current
cp ~/.local/share/istio-current/bin/istioctl ~/.local/bin/
```

The bootstrap script audits all prerequisites before doing any work.

## Bootstrap

Bring the whole system up on a fresh minikube profile:

```bash
./scripts/bootstrap-capstone.sh
```

Bootstrap runs 10 tiers: minikube profile (images are then built and loaded with
`minikube image load`), Istio control plane, CloudNativePG operator, Postgres cluster, Kafka (Strimzi),
KEDA + HTTP add-on, OpenMetadata + observability, all services + scalers
+ seed data, Kiali, and catalog ingestion + lineage.

### Verifying the stack

```bash
./scripts/cluster-status.sh
```

Three quick demos to confirm the stack is alive:

1. `./demos/demo-order.sh` — creates an order via REST, confirms it in Postgres
2. `./demos/demo-service.sh inventory` — builds, deploys, and health-checks a service
3. `./demos/demo-observability.sh` — verifies Prometheus is scraping and Grafana is provisioned

## Running the demos

### The walkthrough

`walkthrough.sh` orchestrates five acts — trace, scale, canary, lineage,
topology — each shelling out to an existing demo script with narration
between them. Press Enter to advance.

```bash
./demos/walkthrough.sh
```

### Individual demos

All demos assume you are in the `examples/lgtm-datamesh/` directory with
kubectl context set to `capstone`.

| Script | What it demonstrates | Principle | Tutorial page |
|--------|---------------------|-----------|---------------|
| **Domain ownership** | | | |
| `demo-order.sh` | Order-service walking skeleton: build, deploy, REST round-trip | Domain ownership | §4 |
| `demo-grpc.sh` | Cross-service gRPC (order → inventory CheckStock) | Domain ownership | §4, §6 |
| `demo-service.sh <name>` | Generic service build, deploy, and health check | Domain ownership | §4 |
| **Data as a product** | | | |
| `demo-avro.sh` | Avro schema registered in Apicurio; notification-service decodes by ID | Data as a product | §5 |
| `demo-discovery.sh` | Publish OpenAPI, Protobuf, GraphQL SDL, Avro to Apicurio | Data as a product | §5 |
| `demo-graphql.sh` | GraphQL gateway stitches order (REST) + stock (gRPC) | Data as a product | §6 |
| `demo-reviews.sh` | Review-service REST surface end to end | Data as a product | §4 |
| `demo-add-data-product.sh` | Full add-to-mesh / rollback lifecycle | Data as a product | §5 |
| `demo-openmetadata.sh` | OpenMetadata catalog server health | Data as a product | §5 |
| `demo-om-lineage.sh` | Cross-product lineage (orders → topic → notifications) | Data as a product | §5 |
| **Self-serve platform** | | | |
| `demo-kafka.sh` | Async spine: order.placed → notification-service | Self-serve platform | §6 |
| `demo-notifications.sh` | Durable notifications: Alembic migration, Postgres persistence | Self-serve platform | §4, §6 |
| `demo-keda-kafka.sh` | Kafka consumer-lag scaling (0 → up → 0) | Self-serve platform | §8 |
| `demo-keda-http.sh` | HTTP request scaling via KEDA HTTP add-on (0 → up → 0) | Self-serve platform | §8 |
| `demo-observability.sh` | Prometheus scraping, Grafana dashboard provisioned | Self-serve platform | §9 |
| `demo-tracing.sh` | Tempo backend health: synthetic span ingested and queried | Self-serve platform | §9 |
| `demo-trace-flow.sh` | End-to-end trace: GraphQL → 3 services → Tempo | Self-serve platform | §9 |
| **Federated governance** | | | |
| `demo-canary-verify.sh` | Canary contract evolution: v1/v2 meshed, weight splits asserted | Federated governance | §7 |
| `demo-canary.sh` | Canary demo: up, shift weight, tear back to v1 baseline | Federated governance | §7 |
| `demo-kiali.sh` | Kiali mesh topology: API health, Prometheus wired, graph visible | Federated governance | §7, §9 |

### Observing the results

Host access uses NodePorts published on `127.0.0.1` when the `capstone`
minikube profile is created (`--ports=127.0.0.1:<hostPort>:<nodePort>`,
built from `demos/lib/endpoints.sh`). Nothing runs in the background and
nothing needs to be started per demo. Ports are fixed at creation, so an
older profile without them is refused by `scripts/setup-capstone-profile.sh`;
recreate it with `./scripts/setup-capstone-profile.sh --replace`. `--replace` deletes and recreates the cluster, so run `./scripts/bootstrap-capstone.sh` again afterwards. Run the
workshop in isolation: shut down CRC, other minikube profiles, and other
workloads first so the host ports are free.

| Tool | Local URL | Notes |
|------|-----------|-------|
| Grafana | `http://127.0.0.1:3000` | |
| Prometheus | `http://127.0.0.1:9091` | Port 9091 avoids Fedora Cockpit on 9090 |
| Tempo | `http://127.0.0.1:3200` | Trace query API; also accessible via Grafana Explore |
| Kiali | `http://127.0.0.1:20001/kiali` | |
| OpenMetadata | `http://127.0.0.1:8585` | |
| Apicurio | `http://127.0.0.1:8084` | Schema registry UI + API (`/apis/registry/v3`) |
| Kafka UI | `http://127.0.0.1:8089` | Browse Kafka topics, messages, consumer groups, schemas |

```bash
./scripts/show-endpoints.sh   # status table: which endpoints are published and reachable
```

Default credentials:

| Tool | User | Password |
|------|------|----------|
| Grafana | `admin` | `capstone` |
| OpenMetadata | `admin@open-metadata.org` | `admin` |

## Restoring baseline

The demo scripts clean up their own releases on success (CAP-008), so
after running several, shared services may be missing (e.g.
`demo-discovery` removes inventory-service). To put all workloads back
in their bootstrap state (all seven services + KEDA scalers + seed data):

```bash
./scripts/restore-baseline.sh
```

Run this between demo groups to ensure each demo starts from a known
state.

## Where to learn more

- The reading set (`_docs/`) — the canonical narrative explanation of
  why each component is here and how they fit together.
- The [setup & prerequisites](/setup/) page on the published site —
  the same prerequisites as above, formatted for the web.
- The [demo & example reference](/demos/) page — every demo mapped to
  its data-mesh principle with descriptions and source links.
- The historical decision log (`_plans/archive/capstone-decisions.md`
  at the repo root) — every architectural choice from CAP-001 through
  CAP-047 with rationale and rejected alternatives.
- The active decision log (`_plans/decisions.md` at the repo root) —
  decisions made in this repo's standalone life, starting from DRA-001.
