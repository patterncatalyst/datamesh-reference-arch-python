# Deploying the capstone data mesh to OpenShift

This directory is the **OpenShift counterpart** to [`charts/capstone/`](../charts/capstone/).
The `charts/capstone/` umbrella chart runs the full §17 capstone stack — 7
data-product services, Strimzi Kafka, CloudNativePG Postgres, Apicurio,
OpenMetadata, Prefect, the LGTM observability stack, KEDA autoscaling, and
Istio — on minikube. This tree runs only the **live core** of that system —
the 7 services + Postgres + Kafka + Apicurio — on OpenShift, packaged as a
**Helm chart** (`helm/datamesh/`).

OpenMetadata, Prefect, the LGTM stack, KEDA, and Istio are intentionally
**out of scope** here — they're appendix material the tutorial's chapter
author covers separately, not part of this runnable OpenShift core.

## What's here

```
openshift/
├── helm/datamesh/             # one Helm chart, the live-core topology
│   ├── Chart.yaml
│   ├── values.yaml            # the 7 services described as data; image + infra knobs
│   └── templates/
│       ├── _helpers.tpl           # labels + namespace-portable cluster DNS
│       ├── configmap-app.yaml     # shared env contract (Kafka/Apicurio/gRPC addresses)
│       ├── secret-app.yaml        # dev-only Postgres credential
│       ├── serviceaccount-infra.yaml  # SA + SCC binding for postgres/kafka
│       ├── app-deployment.yaml    # ONE template, ranged over values.services → 7 Deployments
│       ├── app-service.yaml       # → 7 Services
│       ├── route.yaml             # Route for graphql-gateway (route: true in values)
│       ├── postgres.yaml          # Postgres StatefulSet (+ initdb ConfigMap, Service)
│       ├── kafka.yaml             # single-broker KRaft Kafka StatefulSet (+ Service)
│       ├── apicurio.yaml          # Apicurio Deployment + Service + Route
│       └── NOTES.txt
├── gitops/application.yaml    # illustrative Argo CD Application (not part of the verified deploy)
├── build-and-push.sh          # builds the 7 service images, pushes to the cluster registry
└── evidence/                  # live CRC verification output (captured separately)
```

## What changes from `charts/capstone/` → OpenShift

1. **No operators assumed.** `charts/capstone/` relies on the Strimzi Kafka
   operator and the CloudNativePG Postgres operator both being pre-installed.
   This chart doesn't assume either is on the target cluster: Postgres and
   Kafka are **plain StatefulSets** (single-broker KRaft for Kafka, no
   ZooKeeper), not operator CRs.
2. **Security Context Constraints (SCC).** The 7 service images already run
   as `USER 1001:0` (see `services/<svc>/Containerfile`), which is exactly
   what OpenShift's default `restricted-v2` SCC expects — an arbitrary
   assigned UID, group 0. So the app Deployments here **set no `runAsUser`**
   and let the platform assign one. Postgres and Kafka *do* need specific
   UIDs (70 / 1000) their upstream images hardcode, so they run under a
   dedicated ServiceAccount (`datamesh-infra`) bound to the `nonroot-v2` SCC.
3. **Routes, not NodePorts.** On minikube, `charts/capstone/` exposes services
   via NodePorts published to 127.0.0.1 (minikube has no router).
   OpenShift has one: external access here is two `Route` objects
   (graphql-gateway, apicurio) served by the cluster's router.
4. **The integrated registry.** Images are pushed to OpenShift's internal
   registry (`image-registry.openshift-image-registry.svc:5000/datamesh/...`)
   and referenced from there, instead of the minikube-profile local registry
   (`localhost:5000/...`) `charts/capstone/` subcharts use.
5. **Tracing is off.** `charts/capstone/` wires every service to OTLP/Tempo.
   Since the LGTM stack isn't deployed here, the OTEL_* env vars are simply
   omitted — the services' `opentelemetry-instrument` entrypoint (where
   present) is a documented no-op with no OTEL_* env set.

Everything else — the shared env contract, per-service schema wiring, the
Kafka producer/consumer pair (order-service → `order-placed` →
notification-service), the Apicurio-registered Avro contract, the health
probes — is carried over unchanged.

## Prerequisites

- An OpenShift cluster and `oc`/`helm` (v3+; this was authored against
  `helm` v4). For a laptop, **OpenShift Local (CRC)**:

  ```sh
  crc setup
  crc config set memory 16384
  crc config set cpus 6
  crc start
  eval "$(crc oc-env)"
  oc login -u developer https://api.crc.testing:6443
  ```

- The integrated registry's default route exposed (CRC disables it by
  default):

  ```sh
  oc patch configs.imageregistry.operator.openshift.io/cluster \
    --type merge -p '{"spec":{"defaultRoute":true}}'
  REG=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
  podman login -u "$(oc whoami)" -p "$(oc whoami -t)" --tls-verify=false "$REG"
  ```

- The project/namespace created up front (the Helm chart does not create it):

  ```sh
  oc new-project datamesh   # or: oc project datamesh
  ```

## Build and push the 7 service images

```sh
./openshift/build-and-push.sh -r "$REG" -n datamesh
```

This builds each `services/<svc>/Containerfile` with podman and pushes it to
`$REG/datamesh/<svc>:v1` — the exact ref `values.yaml`'s
`image.registry`/`image.tag` compose.

If the cluster's CRC VM has no Docker Hub egress, mirror the postgres/kafka
images into the same registry namespace instead of pulling them live:

```sh
./openshift/build-and-push.sh -r "$REG" -n datamesh --mirror-infra
```

(On a cluster *with* Docker Hub egress, skip `--mirror-infra` and uncomment
the upstream `docker.io/...` refs in `values.yaml` for `postgres.image` /
`kafka.image` instead.)

## Install

```sh
helm upgrade --install datamesh openshift/helm/datamesh --namespace datamesh
oc get pods -n datamesh -w            # watch infra, then the 7 services, go Ready
```

Reach the system through its Routes:

```sh
oc get route graphql-gateway -n datamesh -o jsonpath='{.spec.host}'   # GraphQL query edge
oc get route apicurio        -n datamesh -o jsonpath='{.spec.host}'   # schema registry UI/API
```

Verify:

```sh
curl -ks "https://$(oc get route graphql-gateway -n datamesh -o jsonpath='{.spec.host}')/health"
curl -ksI "https://$(oc get route apicurio -n datamesh -o jsonpath='{.spec.host}')/"   # apicurio's exact health path wasn't verified for this chart; a 200/302 on / confirms it's up
```

## Uninstall

```sh
helm uninstall datamesh -n datamesh
# PVCs (postgres-data, kafka-data) are retained by design; delete them to wipe state:
oc delete pvc -l app.kubernetes.io/part-of=capstone -n datamesh
```
