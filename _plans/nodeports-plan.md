# Plan: published loopback NodePorts replace SSH tunnels / port-forward

Branch `fix/nodeports-no-tunnels`. `EX/` = `examples/lgtm-datamesh/`. Planned 2026-10-08 (Opus).
Move this file to `_plans/archive/` once executed (its own text would fail the forbidden-syntax gate).

## Revision 2026-10-08 (user direction) — supersedes conflicting text below

- **Host ports do not change.** Every URL stays the same (Grafana `127.0.0.1:3000`, order `:8080`, Kiali `:20001`, …).
  Publish as `--ports=127.0.0.1:<hostPort>:<nodePort>` (e.g. `127.0.0.1:3000:30300`), and keep the existing
  `TP_*` (host port) / `NP_*` (node port) pairs and values. Only the transport changes, so docs keep the same URLs.
- **Keep the `TP_*` variable names** to minimise churn. Their comments now read "host port published on 127.0.0.1",
  and the scanner does not flag `TP_`. `ensure_tunnel` / `tunnel_port_for` still get renamed (`ensure_endpoint` /
  `endpoint_port`).
- `published_ports` checks that container port `<np>/tcp` is bound to HostIp 127.0.0.1 **and** HostPort == the mapped host port.
- **Workshops run in isolation.** Before a live run, everything else is shut down (CRC, other minikube profiles,
  Docker Desktop), so there are no host-port collisions with helm4dev. Keep the free-port pre-flight as a cheap guard.
- Rootless podman minikube is proven on this host in other projects. The 127.0.0.1 binding check is a verification
  step, not an expected problem.
- `EX/examples/17-capstone/`: delete vs convert is pending the user's answer.

## Approach

All 14 host-facing services are already NodePorts, so only the transport changes. The
`capstone` profile publishes them at creation: `minikube start --ports=127.0.0.1:<np>:<np>,...`.
Host port = nodePort, and clients use `http://127.0.0.1:<np>`.

- `EX/demos/lib/endpoints.sh` replaces `tunnels.sh` and holds the only port list. The setup script and
  the demos both read it.
- The setup script refuses any existing profile (running or stopped) whose `podman inspect`
  PortBindings lack a 127.0.0.1 binding for every listed port, and points to `--replace`.
- `scripts/forbidden-syntax.sh` gates CI.

Rejected:
- autossh, a port-forward respawn loop, `minikube tunnel` with LB: all are tunnels.
- Bare `--ports=np:np`: binds 0.0.0.0.
- Keeping the old low host ports: they collide with other local services, and the skill says host = nodePort.
- kvm2 with `minikube ip`: loses the rootless podman tuning.
- One ingress port routed by Host header: too much churn for now.
- `TP_*` aliases: the name is wrong.

## Design decisions

1. **Names.** Drop `TP_*` with no aliases. Keep the `NP_*` names and values.
   `endpoints.sh` provides:
   - `_endpoint_row <name>`, returning "np ns svc label", for the same 14 names.
   - `ENDPOINT_NAMES`.
   - `CAPSTONE_NODE_PORTS`, derived from the table, plus `EXTRA_NODE_PORTS`.
   - `endpoint_port`, `endpoint_url`, `node_ports_arg`.
   - `published_ports`: podman inspect `.HostConfig.PortBindings`, counting only HostIp 127.0.0.1;
     a missing container means an empty set.
   - `nonloopback_ports`: hard fail if any port is published on another address.
   - `check_published_ports`: lists what's missing and prints the `--replace` hint.
   - `ensure_endpoint <name>...`, which checks three things:
     - the port is published;
     - the Service type and nodePort match;
     - a TCP reach, skipped for scaled-to-zero notification.
   - `wait_http`, `wake_gateway` and `GATEWAY_HOST`, carried over.
   - Optionally, `registry_host_port`.
2. **One list.** `setup-capstone-profile.sh` sources `../demos/lib/endpoints.sh` and builds
   `--ports="$(node_ports_arg)"`. Scan 5 of forbidden-syntax checks that chart and patch nodePorts match
   the map.
3. **Rootless podman.** minikube documents `--ports` for docker and podman, and the node already
   publishes 22, 2376, 5000, 8443 and 32443 on 127.0.0.1. Risks:
   - the IP is dropped, or the flag is ignored;
   - `minikube start` on an existing profile ignores `--ports`.

   Mitigation: inspect the bindings before and after start, and require `--replace`. Live acceptance 9
   checks it.
4. **Registry.** Leave it as is: minikube puts 5000 on a random loopback port, and it's discovered
   dynamically. Pinning 5000 would collide with helm4dev.

## NodePorts (14)

| NodePort | Name | Service / ns | How it becomes NodePort |
|---|---|---|---|
| 30300 | grafana | grafana / observability | grafana-values.yaml |
| 30091 | prometheus | prometheus-server / observability | prometheus-values.yaml |
| 30320 | tempo | tempo / observability | tempo-values + JSON patch (index 2) in setup-observability.sh |
| 30418 | tempo-otlp | tempo / observability | same patch (index 9) |
| 30201 | kiali | kiali / istio-system | patch in setup-kiali.sh |
| 30585 | openmetadata | openmetadata / capstone | om-app-values + patch in setup-openmetadata.sh |
| 30084 | apicurio | apicurio / capstone | chart values |
| 30089 | kafka-ui | kafka-ui / capstone | chart values |
| 30080 | order | order-service / capstone | chart values |
| 30081 | gateway | keda-add-ons-http-interceptor-proxy / keda | setup-keda.sh patch, re-pinned in bootstrap |
| 30083 | notification | notification-service / capstone | chart values (scales to zero) |
| 30086 | review | review-service / capstone | chart values |
| 30087 | inventory | inventory-service / capstone | chart values |
| 30088 | ingress | istio-ingressgateway / istio-system | setup-istio.sh patch (index 1), re-pinned in bootstrap |

These stay in-cluster: graphql-gateway (reached via the interceptor), payment, shipping, Postgres, Kafka.
helm4dev also binds 30080, 30081, 30300 and 5000, so the two profiles must never run together. A
pre-flight check makes sure every port is free.

## Inventory / steps

1. **Foundation.**
   - `EX/demos/lib/endpoints.sh`.
   - `EX/scripts/show-endpoints.sh`: a read-only table of URL, svc type/np, published, and reachable.
     Exits 1 if anything is unpublished or wrong.
   - 1b, in parallel: `scripts/forbidden-syntax.sh`.
2. **Machinery.**
   - `setup-capstone-profile.sh`:
     - source endpoints.sh;
     - run the free-port pre-flight on create (`ss -Htln`);
     - if `podman container exists`, run `check_published_ports` without `--replace`, so a stopped
       profile is covered too;
     - start with `--ports`;
     - check after start;
     - print the published list.
   - `cluster-up.sh`: `check_published_ports`.
   - `cluster-status.sh`: endpoints section.
   - `teardown.sh`: drop the tunnel stop line.
   - `bootstrap-capstone.sh`: `ensure_endpoint` and `NP_*`, a "show endpoints" step, a final URL block
     on 127.0.0.1 NodePorts.
3. **Demos A.** order, grpc, graphql, kafka, avro, notifications, discovery, service, reviews,
   add-data-product (rename `pf()` to `ep()`). The change is mechanical:
   - `TP_*` to `NP_*`
   - `ensure_tunnel` to `ensure_endpoint`
   - `tunnel_port_for` to `endpoint_port`
   - reworded step text
4. **Demos B.** openmetadata, om-lineage, observability, tracing, trace-flow, keda-http (reword the
   idle-connection text), kiali, canary (`curl 127.0.0.1:30088/version`), canary-verify,
   verify-grafana, walkthrough (show-endpoints; Kiali at `127.0.0.1:30201/kiali`; the stale act-1
   port-forward comment now describes the interceptor).
5. **Setup scripts and config comments.**
   - Scripts:
     - setup-observability;
     - setup-kiali, with functional `GRAFANA_EXT_URL=http://127.0.0.1:30300`;
     - setup-istio, setup-keda;
     - setup-openmetadata, ingest-openmetadata;
     - publish-discovery-contracts;
     - scaffold-service (local Postgres container).
   - Comments in the 6 chart values files, grafana-values, istio/routing.yaml,
     keda/gateway-httpscaledobject.yaml, reviews_lineage.py and the 5 service config.py files.
   - `services/order-service/README.md`: local Postgres on 127.0.0.1:5432.
   - The 4 openshift files: contrast wording only (Routes vs published NodePorts).
   - `git rm -r EX/examples/17-capstone`, a stale r0 snapshot that nothing references and that holds a
     real port-forward.
6. **Delete** `EX/demos/lib/tunnels.sh` and `EX/scripts/tunnel-services.sh` (after 2–5).
7. **Docs, deck, CI.**
   - Docs:
     - `EX/README.md`: access model, URL table, show-endpoints, the `--replace` rule.
     - `setup.html` "Accessing the tools" and `demos.html`.
     - `_docs/06` line 40.
     - `_docs/11`: line 10, and lines 171–176 under "Routes, not published NodePorts".
     - `_docs/02`: a host-access paragraph.
     - `onboarding/LESSONS-LEARNED.md`: the lessons, reframed as the reason; any remaining lines get
       `forbidden-ok`.
     - `_plans/decisions.md`: edit DRA-005, add **DRA-017**.
     - `_plans/reconciliation.md`: reword the row, add a DRA-017 row.
     - `_plans/archive/README.md`: banner.
   - Deck: patch speaker notes 33 and 49 of `presentation/data-mesh-openshift/Data_Mesh_on_OpenShift.pptx`
     with python-pptx (notes only), and note the post-build patch in the deck README.
   - CI:
     - `forbidden-syntax.sh`: scans 1–5 (wording; `TP_`/ensure_tunnel; non-loopback `--ports`; pptx
       slide and notes XML; nodePort consistency). Excludes `_plans/archive/`, `*.archive.md`,
       node_modules, .venv and itself. Allow marker `forbidden-ok`.
     - New `.github/workflows/checks.yml` (PR and push): forbidden-syntax plus `bash -n`.
     - Add the same gate to `pages.yml` before the build.
8. **Static gate.** Acceptance 1–8, then move this plan to the archive.
9. **Live re-check.** Record it in reconciliation and promote DRA-017.

Archive rule: `_plans/archive/` and `*.archive.md` are history. Their wording isn't changed, they're
excluded from the scanner and the Jekyll build, and they're never linked as current guidance.

## Acceptance criteria

1. `bash scripts/forbidden-syntax.sh` prints "forbidden-syntax: OK". Negative test: a planted
   port-forward line fails, and the same line with `forbidden-ok` passes.
2. A broad grep for tunnel/port-forward finds 0 lines outside the archive and `forbidden-ok` lines.
3. 0 hits for `\bTP_[A-Z]|ensure_tunnel|tunnel-services|tunnels\.sh|tunnel_port_for|_tp_resolve_ssh`.
4. tunnels.sh, tunnel-services.sh and `EX/examples/17-capstone` are gone.
5. Sourcing endpoints.sh gives 14 ports, and `node_ports_arg` has 0 items without the `127.0.0.1:` prefix.
6. Every former `ensure_tunnel` file now uses `ensure_endpoint`.
7. setup-kiali `GRAFANA_EXT_URL=http://127.0.0.1:30300`.
8. `bash -n` passes on changed scripts, and the CI checks and pages build are green.
9. After `--replace`:
   - `podman port capstone` shows 14 `-> 127.0.0.1:` lines and no 0.0.0.0;
   - `ss` shows them on loopback only;
   - LAN-IP curl fails.
10. `EXTRA_NODE_PORTS=30999` exits 1 and names the port and `--replace`, whether the profile is
    running or stopped.
11. If a port is busy, the pre-flight exits 1 before any delete.
12. `show-endpoints.sh` exits 0 with 14 rows (notification may be scaled to zero).
13. The live demo set passes, and walkthrough passes 5/5.

## Live re-check

1. Stop CRC. Check that datamesh and helm4dev are stopped. If less than about 30 GB is available,
   quit Docker Desktop. Remove leftover ssh forwards and `/tmp/capstone-tunnel.pids`.
2. `MINIKUBE_ROOTLESS=true ./scripts/setup-capstone-profile.sh --replace`, then acceptance 9.
   Stop if this fails.
3. `./scripts/bootstrap-capstone.sh`, then show-endpoints and acceptance 10.
4. Run demos: order, reviews, service inventory-service, notifications, keda-http, discovery,
   observability, tracing, kiali, openmetadata, canary-verify. Curl kafka-ui. Run walkthrough.
5. `minikube stop -p capstone && ./scripts/cluster-up.sh`, then show-endpoints again.
6. Recommended full suite: canary cycle, add-data-product cycle, om-lineage, avro, graphql, grpc,
   kafka, trace-flow, verify-grafana.
7. Record the results, then `minikube stop -p capstone`.

## Risks

- minikube with rootless podman may ignore the IP or the flag. Mitigation: the post-start hard fail.
  Don't ship until it's resolved.
- An existing profile ignores new ports. Mitigation: inspect it before start and require `--replace`.
- Port collisions with helm4dev. Mitigation: the pre-flight check and one cluster at a time.
- Index-based patches can drift. Mitigation: `ensure_endpoint` checks the actual nodePort.
- Scaled-to-zero services refuse connections when idle. Mitigation: keep the wake and retry logic.
- User URLs change (3000 to 30300, and so on), and the Kiali external Grafana link has to follow.
- The pptx notes are hand-patched and drift from build-deck.js. Mitigation: the CI pptx scan.
- The broad `tunnel` rule needs `forbidden-ok` on prohibition and lesson lines.
- Memory: the profile needs 24 GB, so stop CRC and quit Docker Desktop if needed.
