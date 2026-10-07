---
title: "Appendix: Running on OpenShift (CRC) locally"
order: 12
description: "The same seven-service data mesh, redeployed to OpenShift Local: a Helm chart, Security Context Constraints, Routes, and the integrated registry."
duration: 40 min
---

[Chapter 3]({{ '/docs/02-kubernetes-substrate/' | relative_url }}) built the case for
Kubernetes as the mesh's substrate and brought the capstone up on minikube via Helm —
NodePorts, a stable SSH tunnel, a local image registry. That's a real deployment, and
everything in the reading set up to the [summary]({{ '/docs/10-summary/' | relative_url }})
assumes it. But "deploy it to Kubernetes" and "deploy it to OpenShift" are not the same
sentence. OpenShift adds opinions on top of plain Kubernetes — Security Context
Constraints that reject a pod demanding a specific UID, Routes instead of hand-rolled
ingress, an integrated image registry with no external account — and those opinions are
exactly what a chart has to be built around if it's going to run there at all.

This appendix runs the same seven-service system — the GraphQL gateway, the six
data-product services, Postgres, Kafka, and Apicurio — on **OpenShift Local (CRC)**, a
real single-node OpenShift cluster you run on a laptop. The implementation deck at
`presentation/data-mesh-openshift/` already speaks OpenShift's vocabulary in its
diagrams — *Project* for namespace, *SCCs* for pod security, *OperatorHub/OLM* for the
operator install path, *AMQ Streams* for Strimzi, *CNPG* for CloudNativePG — because the
deck was written to pair this reference with OpenShift specifically. This appendix is
what makes that pairing runnable: a Helm chart under
[`examples/lgtm-datamesh/openshift/helm/datamesh/`](https://github.com/patterncatalyst/datamesh-reference-arch-python/tree/main/examples/lgtm-datamesh/openshift/helm/datamesh),
built to the three constraints OpenShift imposes, plus the build/push/deploy sequence
that gets it running.

One scoping note up front, visible in the chart's own `Chart.yaml`: this is the **live
core** of the capstone — the seven services, Postgres, Kafka, and Apicurio — not the
full minikube stack. OpenMetadata, Prefect, the LGTM observability stack, KEDA
autoscaling, and the Istio mesh are intentionally out of this chart. The last section of
this appendix explains why and what their OpenShift-native counterparts would be.

![The chart's topology on CRC — app pods under restricted-v2, infra pods under nonroot-v2, the integrated registry, and two edge-TLS Routes]({% raw %}{{ '/assets/diagrams/18-crc-openshift-topology.svg' | relative_url }}{% endraw %})

## Prerequisites

You don't need a paid subscription or a cloud account. **OpenShift Local** (CRC —
"CodeReady Containers") runs a real, single-node OpenShift cluster in a local VM.

1. **Create a free Red Hat Developer account.** Go to
   [developers.redhat.com](https://developers.redhat.com), register or log in. It's free
   and gives you access to OpenShift Local and the pull secret.
2. **Download OpenShift Local and its pull secret** from
   [console.redhat.com/openshift/create/local](https://console.redhat.com/openshift/create/local):
   the `crc` binary for your platform, and the pull secret (a small JSON file). Save the
   pull secret somewhere you can reference it, e.g. `~/Downloads/pull-secret.txt`.
3. **Install `crc`.** Extract the archive and put the `crc` binary on your `PATH`. This
   appendix was authored against **CRC 2.64.0**, which bundles **OpenShift 4.22.14**.
4. **Size the host.** CRC's defaults are not enough for seven Python services plus
   Postgres, Kafka, and Apicurio plus OpenShift's own control plane — the infra pods will
   sit `Pending` with `Insufficient memory` on the defaults, and the default disk will run
   into `DiskPressure` once the nine images in this appendix are pushed to the integrated
   registry (see "What broke on live apply" below). Give it more of all three, while the
   instance is still stopped — CRC can only grow disk size before the first `crc start`:

   ```sh
   crc config set memory 20480   # 20 GB
   crc config set cpus 8
   crc config set disk-size 80   # 80 GB — the default ~32 GB fills once 9 images are pushed
   ```

5. **Set it up and start it.**

   ```sh
   crc setup                                               # one-time; configures the VM + networking
   crc start --pull-secret-file ~/Downloads/pull-secret.txt
   ```

   `crc setup` needs root for a couple of steps (a small setuid helper, the libvirt
   network), so run it where `sudo` can prompt you. The first `crc start` provisions the
   VM and waits for the cluster to settle — budget 10–15 minutes. When it finishes it
   prints the `kubeadmin` console URL and credentials.

6. **Get `oc` and log in.** CRC ships a version-matched `oc`; `eval $(crc oc-env)` puts
   it on your `PATH`.

   ```sh
   eval $(crc oc-env)
   oc login -u kubeadmin -p <printed-password> https://api.crc.testing:6443
   ```

   Right after `crc start` returns, the API server can briefly reset connections while
   its operators roll out — if `oc login` fails with `EOF`, wait a minute and retry.

7. **Install `helm`** (v3 or later). The chart has no other external dependencies — no
   operators are assumed to be pre-installed on the target cluster.

## What changes when the target is OpenShift

The chart in `openshift/helm/datamesh/` exists because three assumptions a plain
Kubernetes deployment makes do not survive contact with OpenShift.

### 1. SCC/restricted-v2 rejects pinned UIDs

Every pod OpenShift admits is run through a **Security Context Constraint (SCC)**. The
default, `restricted-v2`, *assigns* each pod a high UID from a per-namespace range and
**rejects** a pod that demands a specific one via `runAsUser`. A container built around
`USER 1000` on plain Kubernetes, pinned in its Deployment spec, simply never admits on
OpenShift.

The seven Python services are built for exactly this. Their `services/<svc>/Containerfile`
images already declare `USER 1001:0` — an arbitrary UID in group `0`, with the
application's files group-readable and group-writable — which is precisely what
`restricted-v2` expects: it doesn't care *which* UID a pod runs as, only that the pod
isn't demanding one it assigned instead. So the fix for the app Deployments is to **drop
`runAsUser` entirely** and let OpenShift pick. `templates/app-deployment.yaml` sets
`runAsNonRoot: true` and nothing else UID-related — no `runAsUser` key appears anywhere
in the pod's `securityContext`. Whatever UID `restricted-v2` assigns, the image already
works under it.

Postgres and Kafka are the exception, and the chart treats them as one. Their upstream
images hardcode specific non-root UIDs that own their data directories — Postgres as
`70`, the Apache Kafka image as `1000` — so dropping `runAsUser` for them would be wrong:
whatever UID `restricted-v2` assigned instead wouldn't own `/var/lib/postgresql/data` or
`/var/lib/kafka/data`, and the containers would fail to start. For these two, the chart
grants an SCC that *allows* their UID instead of letting the default one assign a
different one. `templates/serviceaccount-infra.yaml` creates a ServiceAccount,
`datamesh-infra`, and binds it to the `nonroot-v2` SCC; `postgres.yaml` and `kafka.yaml`
run their StatefulSets under that account with `runAsUser: 70` and `runAsUser: 1000`
respectively, pinned explicitly, now legally.

The binding is the one piece of OpenShift RBAC worth internalizing on its own: OpenShift
auto-generates a ClusterRole named `system:openshift:scc:<scc-name>` for every SCC on the
cluster, whose single permission is "use this SCC." Binding a ServiceAccount to that
ClusterRole via a RoleBinding is what grants the SCC — there's no separate "SCC
assignment" API, it's ordinary RBAC pointed at a cluster-generated role:

{% raw %}
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ .Values.infra.serviceAccountName }}-scc
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:openshift:scc:{{ .Values.infra.scc }}
subjects:
  - kind: ServiceAccount
    name: {{ .Values.infra.serviceAccountName }}
    namespace: {{ .Release.Namespace }}
```
{% endraw %}

The CLI shorthand for the same grant is `oc adm policy add-scc-to-user nonroot-v2 -z
datamesh-infra`, which is worth knowing when debugging a pod stuck in
`CreateContainerConfigError` with an SCC-related event — it's the same RoleBinding under
the hood.

### 2. Routes, not port-forward/NodePort

The minikube path this capstone uses elsewhere in the reading set exposes services via
NodePort, reached over a stable SSH tunnel because minikube has no cluster-native router.
OpenShift has one built in: a `Route` object hands a Service a real external hostname,
served by the cluster's router, with no tunnel to keep alive. The chart defines two —
`templates/route.yaml` ranges over the same `services:` map and emits a Route for any
service with `route: true` set (currently just `graphql-gateway`), and `apicurio.yaml`
wires its own Route directly since Apicurio isn't part of that map:

```
graphql-gateway   graphql-gateway-datamesh.apps-crc.testing   edge/Redirect
apicurio          apicurio-datamesh.apps-crc.testing          edge/Redirect
```

`edge/Redirect` means TLS terminates at the router and plain HTTP is redirected to
HTTPS — no certificate handling in the application at all. Every other service
(inventory-service, order-service, the rest) stays `ClusterIP`-only, reachable in-cluster
but with no Route, exactly as it would on minikube without a NodePort.

### 3. The integrated registry

OpenShift runs its own image registry inside the cluster, addressed in-cluster by its
Service DNS: `image-registry.openshift-image-registry.svc:5000`. `values.yaml`'s
`image.registry` points there by default. No external registry account, and no
Docker-Hub-style push credentials, are required for a local cluster — the only
credential involved is an `oc whoami -t` token used to `podman login` to the registry's
*external* route when you need to push from outside the cluster, which the build step
below does.

## The chart: one data-driven template, seven services

The chart does not carry seven near-identical Deployment manifests. It carries **one**,
`templates/app-deployment.yaml`, and describes the seven workloads as *data* in
`values.yaml`:

```yaml
services:
  graphql-gateway:
    port: 8080
    probe: http
    size: small
    route: true
  inventory-service:
    port: 8080
    grpcPort: 50051
    probe: http
    size: large
    db: inventory
  notification-service:
    port: 8080
    probe: http
    size: large
    db: notifications
    kafka: true          # Kafka consumer (order-placed) → graceful-shutdown window
    migrate: true         # Alembic `upgrade head` init container
  order-service:
    port: 8080
    probe: http
    size: large
    db: orders
    kafka: true           # Kafka producer (order-placed)
  # payment-service, review-service, shipping-service follow the same shape
```

Each key captures only what differs between services: its port (all seven are `uvicorn`
on `:8080`), whether it exposes a second gRPC port (inventory-service's `:50051`),
whether it owns a Postgres schema, whether it's a Kafka participant needing a graceful
shutdown window, whether it needs an Alembic migration init container ahead of the app
container, and its resource tier. `templates/app-deployment.yaml` then ranges over that
map once, and the interesting part is the conditionals built from it — this is where
"the template is driven by data" earns its keep:

{% raw %}
```yaml
{{- range $name, $svc := .Values.services }}
    spec:
      {{- if $svc.kafka }}
      terminationGracePeriodSeconds: 45     # let in-flight records send/commit
      {{- end }}
      containers:
        - name: {{ $name }}
          image: "{{ $root.Values.image.registry }}/{{ $name }}:{{ $root.Values.image.tag }}"
          {{- if $svc.grpcPort }}
          ports:
            - name: grpc
              containerPort: {{ $svc.grpcPort }}
          {{- end }}
          {{- if eq $svc.probe "http" }}
          readinessProbe:
            httpGet: { path: /healthz, port: http }
          {{- else }}
          readinessProbe:
            tcpSocket: { port: http }
          {{- end }}
          securityContext:
            runAsNonRoot: true            # NOTE: no runAsUser — restricted-v2 assigns it
            allowPrivilegeEscalation: false
            capabilities: { drop: ["ALL"] }
            seccompProfile: { type: RuntimeDefault }
{{- end }}
```
{% endraw %}

Every service in this system ships `/health` as its liveness check and `/healthz` as its
readiness check — all seven are `probe: http` in practice, but the conditional exists
because the chart is carried over from a sibling project where some services shipped
without a health-check library and needed a bare TCP probe instead; it costs nothing to
keep the branch here even though every current service takes the `http` path.

`notification-service` adds one more wrinkle worth calling out: `migrate: true` adds an
`initContainer` running `alembic upgrade head` against the same database before the
`uvicorn` container starts, so the schema exists before the app issues a single query —
no `CREATE TABLE` happens on the hot path.

The shared environment contract — the Kafka bootstrap address, the Apicurio URL, the
gRPC coordinate for `inventory-service`, the gateway's downstream REST URL — is one
ConfigMap, `templates/configmap-app.yaml`. The one detail worth noting is that every
in-cluster address it builds is namespace-relative:

{% raw %}
```yaml
data:
  KAFKA_BOOTSTRAP: "kafka.{{ .Release.Namespace }}.svc.cluster.local:9092"
  APICURIO_URL: "http://apicurio.{{ .Release.Namespace }}.svc.cluster.local:8080"
  INVENTORY_GRPC_ADDR: "inventory-service.{{ .Release.Namespace }}.svc.cluster.local:50051"
```
{% endraw %}

so the chart installs cleanly into any namespace — `datamesh`, as this appendix does, or
anything else — without a single hardcoded string to edit.

Postgres and Kafka are plain StatefulSets, not operator-managed CRs — `templates/postgres.yaml`
and `templates/kafka.yaml` don't assume the CloudNativePG or Strimzi operators are
installed on the target cluster, since this is meant to run on a bare CRC instance with
nothing pre-installed beyond OpenShift itself. Kafka runs single-broker KRaft (no
ZooKeeper), self-referencing its own pod-stable DNS (`kafka-0.kafka.<ns>.svc...:9093`) as
its quorum voter, with `publishNotReadyAddresses: true` on its headless Service — a
single-node KRaft broker has to resolve its own controller address to become ready in
the first place, so the Service has to advertise it before it's marked ready. Both
StatefulSets run under `datamesh-infra` with `fsGroup` set to match their UID, so their
PersistentVolumeClaims are writable from the first mount.

## Building and pushing the images

The seven services each ship a `services/<svc>/Containerfile`. `openshift/build-and-push.sh`
builds and pushes all seven to the internal registry, after you expose its default route
and log `podman` in:

```sh
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type merge -p '{"spec":{"defaultRoute":true}}'
REG=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
podman login -u "$(oc whoami)" -p "$(oc whoami -t)" --tls-verify=false "$REG"

oc new-project datamesh
./openshift/build-and-push.sh -r "$REG" -n datamesh
```

The script loops `podman build` over each `services/<svc>/Containerfile`, then tags and
pushes to `$REG/datamesh/<svc>:v1` — exactly the reference `values.yaml`'s
`image.registry`/`image.tag` compose, so a plain `helm upgrade --install` finds the
images with no further wiring. Pushing auto-creates an ImageStream per image in the
namespace, which is how the internal registry tracks what it's holding.

**One real snag worth planning for.** The CRC VM's outbound networking does not
necessarily reach Docker Hub — a direct `podman pull docker.io/library/postgres:16-alpine`
run *inside* the cluster's image-pull path can fail with something like `dial tcp
registry-1.docker.io:443: i/o timeout`, which shows up as `postgres-0`/`kafka-0` stuck in
`ImagePullBackOff` after `helm install`. The *host* running `podman`/`oc`, by contrast,
usually has ordinary internet access. The fix is to mirror the two upstream images
through the host into the internal registry, rather than letting the cluster pull them
directly:

```sh
./openshift/build-and-push.sh -r "$REG" -n datamesh --mirror-infra
```

which pulls `docker.io/library/postgres:16-alpine` and `docker.io/apache/kafka:3.8.0` on
the host, retags them into `$REG/datamesh/postgres:16-alpine` and
`$REG/datamesh/kafka:3.8.0`, and pushes — exactly the refs `values.yaml`'s
`postgres.image`/`kafka.image` default to. On a cluster whose CRC VM *does* have Docker
Hub egress, skip `--mirror-infra` and uncomment the commented upstream `docker.io/...`
lines in `values.yaml` instead; both forms are left in the file, one active.

Apicurio needs no such mirror: its image lives on `quay.io`
(`quay.io/apicurio/apicurio-registry:3.2.4`), which CRC's networking reaches directly, so
`apicurio.yaml`'s Deployment references it unmirrored.

![Building and pushing: the host bridges the CRC VM's Docker Hub egress gap; Apicurio pulls from quay.io directly]({% raw %}{{ '/assets/diagrams/19-crc-image-delivery.svg' | relative_url }}{% endraw %})

## Deploying, and watching it come up

```sh
oc new-project datamesh   # skip if you already created it above
helm upgrade --install datamesh openshift/helm/datamesh --namespace datamesh
oc get pods -n datamesh -w
```

```
NAME                                    READY   STATUS    RESTARTS        AGE
apicurio-b8496b8d4-gsqxz                1/1     Running   0               12m
graphql-gateway-7b4b45db4b-pb86w        1/1     Running   0               12m
inventory-service-86bd746bb9-5gsr7      1/1     Running   2 (2m51s ago)   12m
kafka-0                                 1/1     Running   0               12m
notification-service-78c57864b8-rsh9g   1/1     Running   0               12m
order-service-5b6b895cf8-lsgsc          1/1     Running   0               12m
payment-service-7666685477-4cxsv        1/1     Running   3 (3m2s ago)    12m
postgres-0                              1/1     Running   0               12m
review-service-64fc9f7c5f-9gjml         1/1     Running   3 (3m7s ago)    12m
shipping-service-c8c94685b-vzs8l        1/1     Running   3 (2m58s ago)   12m
```

That's the live run, twelve minutes after `helm upgrade --install`: all ten workloads
`1/1`. The 2–3 restarts on `inventory-service`, `payment-service`, `review-service`, and
`shipping-service` are exactly the convergence described above, not a defect —
those four happened to lose the race against `postgres-0` reaching `Ready` on this
particular run; `graphql-gateway`, `order-service`, and `notification-service` happened
to win it. Re-running the same `helm install` against a fresh `crc start` will likely
distribute the restarts across a different subset of services — which four crash-loop
is a function of scheduling order and Postgres's own startup time, not something the
chart controls or needs to.

Expect the app pods to **crash-loop before the infrastructure is ready**, and expect
that to be fine. `notification-service`'s migrate init container, and every service's
database connection on first boot, depend on Postgres and Kafka already being reachable.
A pod that starts before its StatefulSet dependency is `Ready` fails fast — a DNS lookup
with no ready endpoints behind it, then connection refused — and restarts on the normal
back-off schedule. As `postgres-0` and `kafka-0` reach `1/1`, each service recovers on
its next attempt. The restart counts you see in `oc get pods` are the scar tissue of that
ordering, not a sign anything is actually broken; the end state is all green regardless
of how many restarts it took to get there. (If you want a clean start with no restart
churn, install the infra StatefulSets' templates first and wait for them before letting
the app Deployments roll out — but the self-healing path above is what a plain `helm
install` does, and it converges on its own.)

If you skipped the memory bump in the prerequisites, the infra pods sit `Pending`
instead — `oc describe pod postgres-0` reports `Insufficient memory`, and `oc describe
node`'s "Allocated resources" section shows memory requests near 100%. Stop the cluster,
raise `crc config set memory`, and `crc start` again; the pods schedule once there's
room.

## Verifying it works

Health, through the GraphQL gateway's Route (edge TLS):

```sh
curl -sk https://$(oc get route graphql-gateway -n datamesh -o jsonpath='{.spec.host}')/healthz
```

```sh
$ curl -sk https://graphql-gateway-datamesh.apps-crc.testing/healthz
{"status":"ready","service":"graphql-gateway"}
```

And a real query through the gateway spanning two or more of the underlying products —
the point of a GraphQL gateway is composing reads across services the caller never talks
to directly, so the query worth running is one that can only succeed if that composition
actually works, for example an order placed through `order-service` with its live stock
level attached from `inventory-service`:

```sh
curl -sk https://$(oc get route graphql-gateway -n datamesh -o jsonpath='{.spec.host}')/graphql \
  -H 'content-type: application/json' \
  -d '{"query":"{ order(id: \"6c5a7fb2-a9d6-44dd-bbe1-eef95c5bdb5e\") { id customerId itemSku quantity status amount stock { sku quantityOnHand available } } }"}'
```

```json
{"data": {"order": {"id": "6c5a7fb2-a9d6-44dd-bbe1-eef95c5bdb5e", "customerId": "cust-openshift", "itemSku": "WIDGET-001", "quantity": 2, "status": "placed", "amount": "19.98", "stock": {"sku": "WIDGET-001", "quantityOnHand": 50, "available": true}}}}
```

The top-level `order` fields — `customerId`, `itemSku`, `quantity`, `status`, `amount` —
come straight from `order-service`'s own Postgres row; the nested `stock` object is a
second, independent hop the gateway makes over gRPC to `inventory-service`'s `:50051`
port to resolve `quantityOnHand`/`available` for that same SKU. A 200 with both halves
populated — the order half and the `stock` half — confirms the Route, the SCC-assigned
UID, the ConfigMap wiring (`INVENTORY_GRPC_ADDR`), and the gateway's REST-plus-gRPC
fan-out to two independent services are all working together, not just that one pod
answers its own health check.

The same placed order also proves out the event-driven path end to end, off the Route
entirely: `order-service` publishes an Avro-encoded `order.placed` event (schema
registered in Apicurio) to Kafka when the order above was created, and
`notification-service` consumed it, Apicurio-deserialized it, and exposed the decoded
record on its own debug endpoint:

```sh
$ curl notification-service:8080/received
[{"order_id": "6c5a7fb2-a9d6-44dd-bbe1-eef95c5bdb5e", "event_type": "order.placed", "customer_id": "cust-openshift", "item_sku": "WIDGET-001", "quantity": 2, "amount": "19.98", "status": "OrderStatus.placed", "created_at": "2026-10-07T16:20:12.074293+00:00"}]
```

Same order ID, same SKU, same quantity — one `order.placed` write landed through two
independent consumers of the mesh: the GraphQL gateway's synchronous read path above,
and Kafka's asynchronous one. Together the two checks exercise everything the chart
wires up except the document-only tier described below: Route → REST → gRPC on one
side, Route-independent Kafka produce/consume with schema-registry-backed Avro on the
other.

### What broke on live apply

Two things went wrong on the actual run against CRC, neither in the chart's design —
both in the tooling around it — plus one thing worth stating plainly because it did
*not* break: the SCC assignment this appendix spent most of its length justifying.

**1. All ten pods stuck `Pending` behind a `disk-pressure` taint.** Partway through
`helm upgrade --install`, every pod sat `Pending` with a
`node.kubernetes.io/disk-pressure:NoSchedule` taint and no obvious resource request
problem — `oc describe node` wasn't short on memory or CPU. The cause was the registry
push that happens just before deployment: `build-and-push.sh` had already pushed all
nine images (seven app images plus the mirrored `postgres`/`kafka` infra images) into
the integrated registry, and that registry's storage lives on the CRC node's own disk.
CRC's *default* VM disk is a modest ~32 GB, and nine images pushed into it was enough
to cross the kubelet's disk-pressure eviction threshold (27 GB used on a 32 GB disk).
Once a node is under `DiskPressure`, the scheduler taints it and nothing new schedules —
not a Kubernetes misconfiguration, just the VM running out of room for what this chart
actually ships. The fix is the same host-sizing move as the memory and CPU bump in the
prerequisites, just for disk:

```sh
crc stop
crc config set disk-size 80
crc start --pull-secret-file ~/Downloads/pull-secret.txt
```

After the restart the taint cleared and all ten pods scheduled and converged to `1/1`
on their own — this appendix's prerequisites section above already reflects the `80`
value for exactly this reason; a reader following it from a stopped state should never
hit the taint in the first place. (This is also why `crc config set disk-size` is worth
setting *before* the first `crc start` rather than discovering it mid-deploy: CRC disk
size can only be grown while the instance is stopped.)

**2. `build-and-push.sh` exited `2` after every image had already pushed.** The script's
final step prints a one-line hint for the `--mirror-infra` flag described earlier in
this appendix. That hint line is passed to `printf` with a leading `--mirror-infra ...`
string, which `printf` parses as an option flag rather than a format string — an exit
code `2` with no images actually affected, since the build-and-push loop itself had
already completed and returned before the hint line ran. The fix is the standard
`printf`-no-longer-takes-flags-after-this idiom, `printf -- '%s\n' "..."`, which forces
everything after `--` to be treated as data. Purely cosmetic: by the time the script
exits non-zero, the registry already has all nine images, which `oc get istag -n
datamesh` confirms independent of the script's own exit status.

**What didn't break: the SCC assignment.** The entire premise of the "what changes on
OpenShift" section above — drop `runAsUser` for the seven Python app images and let
`restricted-v2` assign a UID, pin `runAsUser` for Postgres and Kafka under a
`datamesh-infra` ServiceAccount bound to `nonroot-v2` — held exactly as designed on the
first deploy, no iteration needed. The live SCC/UID table earlier in this appendix is
the proof: all seven app pods landed on `restricted-v2` with the same OpenShift-assigned
UID, `1000650000` (the images' `USER 1001:0` made them agnostic to whichever UID that
turned out to be), while `postgres-0` kept its required `70` and `kafka-0` its required
`1000`, both legally, both under `nonroot-v2` via the `datamesh-infra` RoleBinding. The
two breakages above were the registry-storage footprint and a shell quoting bug — not
the admission model this appendix is actually about.

## The document-only counterparts

Four layers covered elsewhere in this reading set are intentionally **not** part of this
chart, for the reason stated plainly in `Chart.yaml`: a CRC instance's 20 GB budget
covers seven services plus Postgres, Kafka, and Apicurio comfortably, but doesn't leave
headroom for a service mesh, an autoscaler, a full observability stack, and a data
catalog on top — not without either starving the live core or sizing CRC well past what
a laptop reasonably offers. Rather than cut corners on all five, this appendix documents
each layer's OpenShift-native counterpart as a starting point and keeps the verified core
to what actually fits.

- **The mesh** ([chapter 6]({{ '/docs/06-progressive-delivery-mtls/' | relative_url }})). On
  vanilla Kubernetes this capstone uses Istio directly. **OpenShift Service Mesh** is
  Red Hat's supported distribution of Istio, installed through OperatorHub/OLM rather
  than a raw `istioctl install` — the same `DestinationRule`/`VirtualService` canary
  mechanics this reference already teaches carry over unchanged once the operator is in
  place.
- **Autoscaling** ([chapter 7]({{ '/docs/07-elastic-and-resilient/' | relative_url }})).
  KEDA itself *is* the OpenShift-native answer here, but OpenShift packages it as the
  **Custom Metrics Autoscaler** operator rather than a standalone Helm install — same
  `ScaledObject` CRD, same scale-to-zero behavior, different install path.
- **Observability** ([chapter 8]({{ '/docs/08-observability/' | relative_url }})). In
  place of standing up the full LGTM stack (Loki/Grafana/Tempo/Mimir) as this capstone
  does on minikube, OpenShift ships **cluster monitoring** out of the box and
  **user-workload monitoring** as an opt-in extension of it — a Prometheus-compatible
  path for the services' own metrics without installing anything beyond enabling the
  feature.
- **The catalog** ([chapter 4]({{ '/docs/04-contracts-and-catalog/' | relative_url }})).
  **OpenMetadata** is the same tool this capstone already uses on minikube; nothing about
  it is Kubernetes-distribution-specific, so the OpenShift counterpart is the same
  Deployment, sized to fit alongside the live core rather than run concurrently with it
  on a single CRC instance.

None of these four were applied against the live cluster for this appendix — they're
authored as the next step for a reader who wants the full stack on OpenShift, not as
something this appendix claims to have verified.

## GitOps and Pipelines: the managed counterpart

Everything above is imperative: you ran `helm upgrade --install` by hand. The
OpenShift-native way to *keep* a cluster matching the chart is **OpenShift GitOps**
(Argo CD) — an `Application` object points at the chart in this repo, and Argo
continuously reconciles the cluster to it, pruning drift and self-healing. A starter
manifest is committed at
[`openshift/gitops/application.yaml`](https://github.com/patterncatalyst/datamesh-reference-arch-python/blob/main/examples/lgtm-datamesh/openshift/gitops/application.yaml):

{% raw %}
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: datamesh
  namespace: openshift-gitops
spec:
  source:
    repoURL: https://github.com/patterncatalyst/datamesh-reference-arch-python.git
    targetRevision: main
    path: examples/lgtm-datamesh/openshift/helm/datamesh
  destination:
    server: https://kubernetes.default.svc
    namespace: datamesh
  syncPolicy:
    automated: { prune: true, selfHeal: true }
```
{% endraw %}

Its symmetric partner on the build side is **OpenShift Pipelines** (Tekton): the
`podman build`/`push` loop in `build-and-push.sh` becomes a `Pipeline` triggered on
push, so a commit to a service's source produces a new image in the internal registry
without a human running the script. Both are deliberately left as starting points rather
than part of the verified deploy in this appendix — each needs its operator installed
(OpenShift GitOps, OpenShift Pipelines), and GitOps additionally needs this repo
reachable from the cluster. Neither was applied for this appendix's verification pass.

---

*Verification status: **verified live**, 2026-10-07, on OpenShift Local (CRC 2.64.0,
OpenShift 4.22.14, single node, 20 GB RAM / 8 vCPU / 80 GB disk). All ten workloads —
the seven application Deployments, Apicurio, and the Postgres and Kafka StatefulSets —
reached `1/1 Running` in Project `datamesh`. SCC behavior was confirmed by reading each
pod's effective SCC and runtime UID: the seven app pods under `restricted-v2` with
OpenShift-assigned UID `1000650000`, `postgres-0` under `nonroot-v2` with UID `70`, and
`kafka-0` under `nonroot-v2` with UID `1000`, both infra pods running under the
`datamesh-infra` ServiceAccount. The GraphQL gateway's Route returned
`{"status":"ready","service":"graphql-gateway"}` from `/healthz`, and a cross-service
`/graphql` query through that same Route returned a populated `order` object from
`order-service` joined to a populated `stock` object resolved over gRPC from
`inventory-service` — the Route, the SCC-assigned UID, the ConfigMap wiring, and the
gateway's REST-plus-gRPC fan-out, all exercised together. The Kafka path was confirmed
independently: the same order's `order.placed` event, Avro-encoded against the Apicurio
schema registry, was observed decoded on `notification-service`'s own endpoint. The full
capture is committed at
[`examples/lgtm-datamesh/openshift/evidence/verification.txt`](https://github.com/patterncatalyst/datamesh-reference-arch-python/blob/main/examples/lgtm-datamesh/openshift/evidence/verification.txt).
**Not verified:** the document-only tier (Service Mesh, Custom Metrics Autoscaler,
cluster/user-workload observability, OpenMetadata) and the GitOps `Application` plus
Tekton pipeline were authored but not applied against this cluster — no operators for
any of them were installed for this verification pass. Re-confirm by re-running `helm
upgrade --install` against a fresh `crc start`, then re-driving the two Route `curl`s
and re-reading each pod's SCC annotation — the assigned app UID will differ per cluster,
but the SCC names, the infra UIDs, and the 200s should not.*
