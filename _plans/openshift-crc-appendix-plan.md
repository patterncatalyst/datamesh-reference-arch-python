---
title: "Plan — OpenShift/CRC appendix"
render_with_liquid: false
---

# Plan — Appendix chapter "Running on OpenShift (CRC) locally" + runnable CRC assets

Status: APPROVED by user 2026-10-07. Built via lgtm-relay (Opus plan → Sonnet build → Opus gate).
Branch: `feat/openshift-crc-appendix`.

## Goal
Add an appendix chapter to the datamesh-reference-arch-python tutorial teaching how to run the
existing capstone (today: minikube via helm) on a local **CRC / OpenShift Local** cluster,
adapting to OpenShift idioms, and **LIVE-VERIFIED** on the local CRC instance. Modeled on the
modernizing-enterprise-applications Part 9 deployment chapters (real runnable assets, applied
live, documenting "dry-run passed / live apply broke" learnings).

## Approach (REVISED 2026-10-07 — mirror the modernization OpenShift appendix)
User direction: "use the modernization project as an example" / "we just did this with the
modernization project." The modernization repo's PR #16 shipped a verified-on-CRC appendix:
`_docs/33-appendix-openshift.md` + a dedicated **`openshift/helm/mea/`** chart (data-driven:
ONE `app-deployment.yaml` ranging a `services:` map in values.yaml), **plain Postgres + Kafka
StatefulSets (NO operators)**, a `mea-infra` ServiceAccount bound to the `nonroot-v2` SCC for the
infra pods, app pods that **drop `runAsUser`** (restricted-v2 assigns a high UID), **Routes**
(edge/Redirect TLS), images via the **internal registry**, plus `openshift/gitops/application.yaml`
and `openshift/evidence/verification.txt`.

**This SUPERSEDES the original "reuse umbrella chart + values-openshift.yaml + OLM operators"
approach.** Instead: build a dedicated **`openshift/helm/datamesh/` chart** mirroring the
modernization structure, adapted to the 7 Python/FastAPI services. Postgres + Kafka as plain
StatefulSets (no CNPG/Strimzi/AMQ-Streams operator installs — avoids OLM complexity on CRC and
matches what the user already did). Apicurio kept in the live core (contracts are central to the
datamesh; light image). Rationale: the user explicitly pointed at this template; it is simpler,
self-contained, and already proven on this exact CRC (2.64 / OCP 4.22.14 / 20GB / 8 vCPU).

OpenShift delta vs the existing minikube helm path: (a) plain StatefulSets vs operator CRs for
Postgres/Kafka; (b) Service NodePort→ClusterIP + Route objects; (c) image refs → internal
registry (`image-registry.openshift-image-registry.svc:5000`); (d) drop `runAsUser` on apps +
`nonroot-v2` infra SA; (e) config/endpoints templated off `{{ .Release.Namespace }}` (project
`datamesh`); (f) anticipate the CRC-can't-reach-Docker-Hub snag → mirror postgres/kafka images
through the host (a real learning from the modernization run).

### Scope tiering (20GB CRC budget; bump to 24GB)
- Core, live-verified: `datamesh` Project, CNPG Postgres, single-broker Kafka, Apicurio, the 7
  services, a Route on graphql-gateway. Live check = GraphQL query through the Route hitting
  order→inventory→Postgres + an `order.placed` to Kafka.
- Document-only (runnable, unverified): Istio/Service Mesh canary, KEDA/Custom Metrics
  Autoscaler, Kiali, LGTM observability. OpenMetadata OMITTED (heaviest, lowest value on CRC).

### Rejected alternatives
- New kustomize overlay — re-expresses chart logic that already renders; values-file reuse = less duplication.
- All operators manual — OpenShift's point is OLM; use Subscriptions, manual only as fallback.
- Istio+KEDA+OpenMetadata live — won't fit 20GB with Postgres+Kafka+7 svcs; document-only keeps honest.
- In-cluster BuildConfig for images — 7 builds slow/fragile; push prebuilt to internal-registry route.
- Project `capstone` — chose `datamesh` (matches deck vocabulary; override hardcoded `.capstone.svc`).

## Steps
0. Pull-secret gate (user) — RESOLVED: user confirms CRC + pull secret already set up on machine.
1. Author runnable assets (Sonnet, no cluster) — mirror modernization `openshift/` tree:
   dedicated chart `examples/lgtm-datamesh/openshift/helm/datamesh/` (Chart.yaml, values.yaml with
   `services:` map for the 7 services, templates/: app-deployment.yaml [data-driven, drop runAsUser],
   app-service.yaml [ClusterIP], configmap-app.yaml, secret-app.yaml, postgres.yaml [StatefulSet],
   kafka.yaml [StatefulSet KRaft], apicurio.yaml, route.yaml [graphql-gateway + apicurio], 
   serviceaccount-infra.yaml [+ nonroot-v2 SCC binding], _helpers.tpl, NOTES.txt); `openshift/README.md`
   (crc + build/push loop + image-mirror + helm install + verify commands); `openshift/gitops/application.yaml`;
   `openshift/build-and-push.sh`; `openshift/evidence/` placeholder. `helm template` renders clean; `bash -n` script.
2. Draft chapter `_docs/11-running-on-openshift-crc.md` (order 12, ~3-5k words) + paired
   `assets/diagrams/18-*.svg`+`.excalidraw`; placeholders for live learnings.
3. Live bring-up (serial, needs crc start): bump memory 24576, crc start, oc login, project,
   expose registry route, OLM Subscriptions, oc wait CSVs Succeeded, apply Postgres+Kafka CRs Ready.
4. Images + app deploy + debug (serial): crc-build-push 7 images; helm install -f values-openshift;
   apply Routes; fix SCC/ImagePull/injection breakages; record each learning.
5. Live verify + evidence (serial): all core pods Running; curl gateway Route 200 GraphQL; capture
   evidence into `examples/lgtm-datamesh/openshift/evidence/`.
6. Fold evidence + learnings into chapter; add `_plans/decisions.md` DRA entries; jekyll build +
   check-liquid-collisions.sh + check-cross-references.sh.

## Acceptance criteria
- `_docs/11-running-on-openshift-crc.md` order 12, sorts after summary (order 11); jekyll build green; in nav.
- Chapter ≥2000 words; ≥1 paired `assets/diagrams/18-*.svg`+`.excalidraw` (both parse).
- Explicit dry-run-vs-live scope note + populated "what broke on live apply" section.
- `helm template -f values-openshift.yaml` → ClusterIP + internal-registry refs, `oc apply --dry-run=client` clean.
- `bash -n` clean on crc-up.sh / crc-build-push.sh / crc-teardown.sh.
- Live: all core pods Running/Ready; operator CSVs Succeeded.
- Live: `curl -k https://graphql-gateway-datamesh.apps-crc.testing/<path>` → 200 GraphQL across ≥2 products.
- `openshift/evidence/` populated; `_plans/decisions.md` DRA entries; cross-ref + liquid checks pass.

## Risks
- Pull secret missing → crc start aborts (RESOLVED per user).
- CRC OOM → pods Pending Insufficient memory → bump 24576, heavy tier doc-only, single-broker/1-instance.
- SCC restricted-v2 denials (most likely live break) on apicurio/kafka-ui → scoped anyuid on specific SA only, document.
- Image push auth/registry route → ImagePullBackOff/401 → defaultRoute patch + podman login $(oc whoami -t) --tls-verify=false.
- Istio annotation-vs-label trap (silent, no sidecar) → use pod-template label form; mesh doc-only.
- Hardcoded `.capstone.svc` endpoints leak → grep rendered template before apply.
- CNPG/AMQ Streams CRD drift → oc apply schema rejection → verify apiVersion vs installed operator.
- Operator not in catalogs → Subscription no CSV → verify redhat-operators + community-operators CatalogSources.

---

## PHASE 2 — Full platform tier (added 2026-10-07, user: "full set incl OpenMetadata", 32GB)
APPROVED (OM best-effort). Opus plan returned; CRC resized to 32GB/14cpu/100GB (core green).
Layers: KEDA (Custom Metrics Autoscaler + Kafka-lag ScaledObject on notification), Istio (OSSM3
Sail operator + IstioCNI, pod-label injection on 7 services, canary + STRICT mTLS, edge Route),
observability (grafana/otel-lgtm all-in-one + re-enable OTLP env), Prefect (server+worker, reuse
core Postgres), OpenMetadata (OpenSearch single-node + OM server, anyuid SA, best-effort).
Assets: new examples/lgtm-datamesh/openshift/platform/ tree + install-platform.sh; app-chart
mesh.enabled/observability.otlp.enabled flags (default off); chapter "full platform tier, live"
section + flipped footer; DRA-008..014; per-layer evidence. Order: operators -> mesh CP ->
observability -> meshed rollout (2/2) -> mTLS -> canary -> trace -> KEDA -> Prefect -> OM last.
