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

Before running anything, verify these five prerequisites:

1. **Kernel modules** — iptables modules loaded and persisted (see
   [Kernel & container tuning](#kernel--container-tuning))
2. **inotify limits** — raised above Fedora defaults
3. **Podman pids_limit** — set to unlimited *before* creating the profile
4. **Tooling** — minikube >= 1.36, kubectl, helm, istioctl + full Istio
   distribution (see [Required tooling](#required-tooling))
5. **Bootstrap** — `./scripts/bootstrap-capstone.sh`

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
| OS | Fedora 44 | rootless podman as the container runtime |
| RAM | 64 GB | the `capstone` minikube profile uses 24 GB; rest is host headroom |
| Disk | 1 TB | ≥30 GB free for image cache + PVs |
| CPU | 16 vCPU recommended | not strictly required but the stack is heavy |

### Kernel & container tuning

**Legacy iptables modules.** Fedora is nftables-only out of the box, and
the rootless minikube node cannot `modprobe` them itself — without them
the CNI portmap plugin fails and hostPort pods (the registry proxy first)
never start:

```bash
sudo sh -c 'printf "ip_tables\niptable_nat\nip6_tables\n" \
    > /etc/modules-load.d/99-kubernetes-iptables.conf'
sudo systemctl restart systemd-modules-load
```

**inotify limits.** The capstone runs many controllers; Fedora's default
of 128 instances is not enough:

```bash
sudo sh -c 'printf "fs.inotify.max_user_instances = 512\nfs.inotify.max_user_watches = 524288\n" \
    > /etc/sysctl.d/99-kubernetes.conf'
sudo sysctl -p /etc/sysctl.d/99-kubernetes.conf
```

**Podman pids_limit.** The fully-meshed stack runs ~2000+ tasks on the
node and saturates podman's default 2048 (CAP-040). Must be set
**before** the minikube profile is created:

```bash
mkdir -p ~/.config/containers
printf '[containers]\npids_limit = 0\n' >> ~/.config/containers/containers.conf
```

The profile setup script checks both of these and prints the same fixes.

### Required tooling

| Tool | Minimum version | Notes |
|------|----------------|-------|
| minikube | **1.36** | 1.35's registry addon pins a `kube-registry-proxy` image digest that no longer exists on gcr.io |
| kubectl | (any recent) | |
| helm | 3.x | |
| istioctl | 1.26.x | needs the full Istio distribution, not just the binary — `setup-kiali.sh` applies `samples/addons/kiali.yaml` from it |

**Installing the Istio distribution:**

```bash
curl -fsSL https://github.com/istio/istio/releases/download/1.26.2/istio-1.26.2-linux-amd64.tar.gz \
    | tar xz -C ~/.local/share
ln -sfn ~/.local/share/istio-1.26.2 ~/.local/share/istio-current
cp ~/.local/share/istio-current/bin/istioctl ~/.local/bin/
```

The bootstrap script audits all prerequisites before doing any work.

## Bootstrap

Bring the whole system up on a fresh minikube profile:

```bash
./scripts/bootstrap-capstone.sh
```

Bootstrap runs 10 tiers: minikube profile + in-cluster registry, Istio
control plane, CloudNativePG operator, Postgres cluster, Kafka (Strimzi),
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

The observability tools run inside the cluster. Port-forward to reach
them from the host. Fedora ships Cockpit on port 9090, so Prometheus
uses an alternate local port.

| Tool | Port-forward command | Local URL |
|------|---------------------|-----------|
| Grafana | `kubectl port-forward -n capstone svc/grafana 3000:80` | `http://localhost:3000` |
| Prometheus | `kubectl port-forward -n capstone svc/prometheus-server 9091:80` | `http://localhost:9091` |
| Kiali | `kubectl port-forward -n istio-system svc/kiali 20001:20001` | `http://localhost:20001/kiali` |
| Tempo | (via Grafana → Explore → Tempo datasource) | — |
| OpenMetadata | `kubectl port-forward -n capstone svc/openmetadata 8585:8585` | `http://localhost:8585` |

Grafana default credentials: `admin` / the value from
`kubectl get secret grafana -n capstone -o jsonpath='{.data.admin-password}' | base64 -d`.

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
