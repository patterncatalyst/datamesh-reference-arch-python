# KEDA on OpenShift (Custom Metrics Autoscaler)

## What's here

- `kedacontroller.yaml` — the CMA operand (`KedaController`). Apply only
  after the `openshift-custom-metrics-autoscaler-operator` Subscription's
  CSV in `openshift-keda` is `Succeeded` (see
  `../subscriptions/cma-subscription.yaml`).
- `notification-scaledobject.yaml` — a core-KEDA `ScaledObject` (Kafka
  consumer-lag trigger) targeting the `notification-service` Deployment in
  `datamesh`. Ported from `examples/lgtm-datamesh/keda/notification-scaledobject.yaml`;
  see the comments in that file for where every name came from.

## Apply order

```
oc apply -f kedacontroller.yaml
oc wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True \
  kedacontroller/keda -n openshift-keda --timeout=5m
oc apply -f notification-scaledobject.yaml
oc get scaledobject -n datamesh
```

## Why there's no HTTP-scaled object here

The minikube capstone also scales `graphql-gateway` on in-flight HTTP
request volume via the **KEDA HTTP add-on** (`http.keda.sh/v1alpha1`
`HTTPScaledObject`, installed by the separate `kedacore/keda-add-ons-http`
Helm chart — see `examples/lgtm-datamesh/keda/gateway-httpscaledobject.yaml`
and `scripts/setup-keda.sh`).

The Custom Metrics Autoscaler operator packages **core KEDA only**. It does
not ship, and has no supported path to install, the HTTP add-on's CRDs,
interceptor, or scaler — that add-on is an independent upstream Helm chart,
and installing unmanaged upstream Helm charts alongside an operator-managed
KEDA operand is unsupported (the CMA operator owns the KEDA controller
lifecycle; a second, independently-installed KEDA/add-on stack would fight
it for the same CRDs). So the gateway's HTTP-request autoscaling is
intentionally **dropped** on this OpenShift port, not reimplemented.

### Alternative (out of scope here)

A Prometheus-trigger `ScaledObject` (core KEDA, no add-on needed) could scale
`graphql-gateway` on a request-rate or request-concurrency metric scraped by
OpenShift's **user-workload monitoring** stack, if `graphql-gateway` exposes
an HTTP metrics endpoint and user-workload monitoring is enabled on the
cluster. That still can't scale from a cold HTTP request the way the add-on's
interceptor does (no component holds the first request open while a
zero-replica Deployment comes up), so it is a different scaling shape, not a
drop-in replacement — left out of this authoring step as out of scope.
