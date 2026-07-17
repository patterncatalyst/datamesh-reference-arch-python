# Lessons learned

This document distills the hard-won lessons from building this reference,
drawn from the decisions in `_plans/archive/capstone-decisions.md`
(CAP-001 through CAP-047) and from the July 2026 smoke-test campaign that
brought the full stack up from nothing on a fresh Fedora 44 host and ran
every demo script to green (commits `5403d06`–`e22b318`). It's organised
forward-looking — what to take away when starting your own data mesh on
Kubernetes — rather than as a journal of what happened.

The structure is intentional: the architectural lessons (where you have
the most leverage to make or unmake the system) come first; the
mechanical gotchas (which cost the most time to discover the hard way)
come second; the process lessons (which make subsequent iterations
cheaper) come third.

---

## Architectural lessons — where the high-leverage choices are

### 1. Mesh selectively, not namespace-wide

The default move with Istio is to inject sidecars by labeling a namespace.
It's one line in a manifest, and it gives you the mesh's value everywhere.
It also gives you the mesh's *costs* everywhere — including in pods that
should never have a sidecar, where you'll spend serious time finding out
why.

**Two concrete pods that mustn't be meshed:**

- **Job pods** never reach `Completed` when meshed, because the sidecar
  doesn't exit when the application container does — the Job hangs at
  `1/2 running` forever. This affects every ingestion Job, every
  one-shot migration runner, every `helm test` hook. Memorialised as
  CAP-034. The fix is per-Job: annotate `sidecar.istio.io/inject: "false"`
  on the pod template.
- **Database pods managed by an operator with its own TLS** (in our
  case CloudNativePG) hit a wrapping conflict: the database's internal
  TLS collides with the sidecar's wrapping, and the cluster fails to
  bootstrap. Memorialised as CAP-038. The fix is to opt the Postgres
  namespace out of mesh injection entirely.

The lesson generalises beyond Istio: any cross-cutting platform feature
that wraps every pod (mTLS sidecars, eBPF agents, admission webhooks
with side effects) needs an explicit opt-out story for pods that don't
fit its assumptions. Designing the opt-out *into the platform's defaults*
from the start is much cheaper than discovering it the hard way.

### 2. Match the scaler to the workload

Autoscaling on CPU is the muscle-memory default, and it's almost always
wrong for the workloads in a data mesh. The interesting workloads have
clearer demand signals than CPU:

- **Event consumers** scale on consumer-group lag — the work *waiting* to
  be done, not the work currently being done. A consumer pegged at 0%
  CPU with a 10,000-message backlog needs to scale UP; CPU-based
  autoscaling will scale it down. This is CAP-025's headline finding.
- **Synchronous read gateways** scale on request volume or in-flight
  request count — what's incoming, not what's being served. KEDA's
  HTTP add-on does this; CPU does not, because a slow downstream can
  pin CPU usage at the same level whether one request is in flight or
  fifty.
- **Services subject to a canary traffic split** should NOT be
  HTTP-scaled at the same time. Canary traffic-shifting and request-
  volume-based autoscaling fight each other over the same pods. The
  reference deliberately places its HTTP scaler on the *gateway* (which
  isn't canaried) rather than on order-service (which is); CAP-025
  documents this.

The lesson generalises: figure out what the workload's *demand* actually
is, scale on that, and don't compose scalers that contend for the same
replicas.

### 3. Gateway-that-orchestrates beats true federation, until it doesn't

The data mesh literature talks about federated GraphQL — multiple
services contribute subgraphs, the gateway federates them at the schema
level. It's the right answer at scale. It's the *wrong* answer for a
reference whose audience is trying to understand the mesh's behaviour,
because federation adds a layer of indirection (Apollo, Hot Chocolate,
or similar) that obscures what's happening.

The reference takes a deliberate shortcut: the gateway's resolvers
explicitly call REST and gRPC backends; the gateway owns the GraphQL
schema; the data products underneath own their own protocols (REST,
gRPC) but not GraphQL. This is CAP-016's choice. The trade-off: at
production scale, this gateway becomes a coupling point — every new
domain field is a code change to the gateway. That's the right
trade-off for *learning*; it's the wrong trade-off for *running a
real mesh*.

The lesson generalises to "pick the right level of complexity for what
you're demonstrating, and name the trade-off so people inheriting the
choice know when to revisit it."

### 4. Layer your metadata: contracts on top, catalog on top of contracts

Two different concerns, two different systems:

- **Contracts** (OpenAPI, AsyncAPI, Protobuf, GraphQL SDL) live in a
  schema registry. The runtime question they answer: "can I deserialise
  this message I just received?" That's what makes them mandatory for
  any system using a schema-aware serialisation. Apicurio's registry
  fills this role in the reference.
- **Catalog metadata** (which products exist, who owns them, which
  consume which, what's the lineage) lives in a data-catalog tool. The
  discovery question it answers: "what data products exist, and what
  feeds what?" That's what makes it mandatory for a *mesh* specifically
  (a collection of services without discovery isn't a mesh). OpenMetadata
  fills this role.

Trying to make either tool do both jobs is a classic anti-pattern. The
schema registry isn't a catalog; the catalog isn't a runtime contract
enforcement point. Memorialised as CAP-018.

### 5. Decision-log discipline saves the next iteration

Every architectural choice in this reference has a CAP entry with
rationale and rejected alternatives. That's not bureaucracy; it's the
single most useful artifact for *future* iterations.

The pattern that emerged: every time a previous decision needed to be
revisited, the rationale was there. CAP-045 amends CAP-025 with a
specific tactical change (min replicas 0 → 1) and explains why. CAP-047
defers CAP-046 because of an upstream regression, names the upstream
issue, and documents the worked-around demo path. Without that audit
trail, each revisit becomes archaeology.

The lesson generalises beyond this project: a decision log that captures
*why* and *what was rejected* outlives the people who made the decisions.

---

## Mechanical lessons — the gotchas that cost time

### Sidecar conflicts in Jobs and managed databases

Covered under "Mesh selectively" above (CAP-034, CAP-038). Worth
repeating because these are the ones that present as mysterious — Jobs
that won't terminate, databases that won't bootstrap, with no obvious
mesh-related symptom unless you're looking for it. Mesh-membership
checks that look at `.spec.containers` miss native sidecars on Istio
1.29+ (they're `initContainer`s with `restartPolicy: Always`); use
`.spec.initContainers` instead.

### Helm-chart secret wiring is its own discipline

Three live fix cycles on OpenMetadata before the chart's expectations
clicked into place (CAP-022). The pattern of failures:

- **Name collisions** between user-supplied secrets and chart-generated
  ones. The chart's templates try to use the user-supplied secret if
  provided, but its existence check is by name; if your secret has the
  same name as the chart-generated one, you get the chart-generated
  one's structure expected against your contents.
- **Missing placeholder secrets** the chart references even when the
  corresponding feature is disabled. OpenMetadata's chart references
  `airflow-secrets` even when the Airflow pipeline client is disabled;
  you have to create an empty placeholder or override the chart's
  defaults to skip it.
- **`CreateContainerConfigError` always signals a config/secret
  reference problem**, never an application bug. The application
  hasn't started yet; kubelet can't even render the pod spec into a
  running container. When you see this error, look at the env vars
  and volume mounts referencing secrets and configmaps, not at the
  application's startup logs.

The lesson generalises: helm-chart secret wiring failures present
mysteriously and usually mean the chart's contract isn't what you
think it is. Read the chart's `_helpers.tpl` and the templates that
reference secrets before iterating on values.

### Database operations: `to_regclass` is database-scoped

A small but recurrent: in psql, `SELECT to_regclass('schema.table')` returns
NULL even when the table exists, if you didn't pass `-d <dbname>` to psql.
Without it, the query runs against the default `postgres` database.
Memorialised in CAP-022's lessons. The lesson generalises: when verifying
that a migration succeeded, always be explicit about which database you're
querying.

### Idle-node decay: minikube's kube-proxy can lose its `/dev` mounts

A long-lived minikube node (the kind you get when you're iterating on a
project over weeks) can have kube-proxy lose its `/dev` mount and stop
routing Service traffic, while every pod still reports Ready. The
diagnostic is non-obvious: pod-to-pod traffic works; Service-to-pod
traffic times out from inside the cluster. Memorialised as CAP-040. Fix:
cycle the node. Prevention: don't run minikube clusters for weeks at a
time, or check kube-proxy's state when surprising network behaviour
appears.

### PID ceiling on rootless podman nodes

The default `pids_limit` for rootless podman is 2048, which is plenty for
small workloads but gets eaten by the full data mesh once OpenMetadata
and the observability stack are running. Memorialised as CAP-041. Raise
it at node creation, not after.

### Migration tooling: init-containers beat `create_all`

The skeleton used SQLAlchemy `create_all` for r21's first service —
expedient, gets out of the migration-framework rabbit-hole on day one.
It also doesn't survive contact with reality, because the first time you
need to change a schema you discover `create_all` doesn't migrate, it
just creates-if-not-exists. Alembic via an init-container is the right
shape: the init runs `alembic upgrade head`, the service container
starts knowing the schema is at the head. Memorialised as CAP-021.

### Native sidecars in Istio 1.29+

In Istio 1.29 and later on Kubernetes 1.29+, `istio-proxy` is injected
as an `initContainer` with `restartPolicy: Always` — a native sidecar,
not a regular container. "Is this pod meshed?" checks that inspect
`.spec.containers` miss it; check `.spec.initContainers` instead. A
meshed pod still reports `2/2` because the sidecar's `Always`-restart
init-container counts. Memorialised throughout the archive's recent
CAPs.

### Rootless-podman + containerd minikube has its own image-distribution model

You can't `docker push` to localhost and expect minikube to find it,
because rootless podman's daemon isn't accessible from the cluster's
node, and minikube's containerd runtime doesn't share an image cache
with the host. The reference uses minikube's in-cluster registry as
the distribution point (build → tag for the in-cluster registry →
push → containerd pulls from inside the cluster). Memorialised as
CAP-007, CAP-009, CAP-010 — three CAPs because it took that many
iterations to land. The lesson: rootless minikube has its own
image-distribution shape and `docker push localhost:5000/img` is not it.

### A port-forward pins its pod — poll loops must re-attach under autoscalers

`kubectl port-forward svc/x` picks one pod at connect time and stays
bound to it. Under a scale-to-zero autoscaler that's a trap with several
interlocking parts, discovered when three smokes failed against a
healthy system:

- **"Rolled out" is not "still running."** Helm sets `replicas: 1`, the
  rollout gate passes, and KEDA reconciles the deployment back to 0
  within its polling interval (5s for the notification ScaledObject;
  the gateway's HTTPScaledObject has `scaledownPeriod: 30`). A rollout
  gate passing guarantees nothing seconds later. And
  `kubectl rollout status` on a 0-replica deployment succeeds
  *instantly* — it can't serve as a liveness check at all.
- **The tested event is what wakes the consumer.** With the consumer
  scaled to zero, the smoke's own order creates the lag that wakes a
  NEW pod — which consumes and persists the event while the smoke polls
  the dead tunnel to the OLD pod.
- **`curl ... || echo '[]'` turns a dead tunnel into "not consumed
  yet."** The fallback that made the poll loop robust to slow starts
  also made it blind to transport failure. The event was in Postgres
  the whole time; the smoke reported it missing.

The fixes (commits `764aa3f`, `1093d78`, `e22b318`): on curl failure,
kill and re-establish the port-forward against the Service, then treat
that attempt as "not yet"; size poll windows for scale-from-zero
(lag-poll + pod start + consumer-group join), not for a warm consumer;
and for paths that go through the KEDA HTTP interceptor, retry transient
non-200s (the 0.12.2 interceptor can 502 the first POSTs after a
scale-from-zero — CAP-046's cold-start race).

The lesson generalises twice over. Any test that tunnels into a cluster
managed by an autoscaler must treat the tunnel as unreliable — and any
fallback that silently swallows transport errors in a poll loop should
be treated as a smell. When a poll says the data never arrived, check
the datastore directly before believing it.

### Well-known local ports are booby-trapped on the verified platform

The observability smoke port-forwarded Prometheus to local 9090 — and
Fedora, the reference's verified platform, ships Cockpit listening on
host 9090 by default. The port-forward's bind failure was silenced by
`>/dev/null 2>&1`, the readiness probe's `curl` (without `-f`) was
satisfied by Cockpit's 404, and the smoke then "queried Prometheus,"
got nothing, and reported the metrics pipeline broken. Nothing was
broken.

Three small rules fall out (commit `b320e20`): don't default test
tooling to well-known ports (9090, 3000, 8080) — pick high odd ones and
make them env-overridable; always `-f` a readiness probe so a port
squatter answering 404 can't satisfy it; and when a smoke contradicts
what you can observe directly, suspect the smoke's transport before the
system under test.

### Fresh-host bring-up finds the assumptions your dev machine hides

Two bring-up blockers existed on a clean Fedora 44 host that no
long-lived dev machine would surface:

- **The CNI portmap plugin needs legacy `ip_tables`/`iptable_nat`
  kernel modules, and a rootless node can't load them.** Fedora is
  nftables-only out of the box; inside the rootless podman node,
  `modprobe` gets `Operation not permitted`, and every hostPort pod
  (starting with the registry proxy) fails sandbox creation. The host
  must load the modules — persist them via `/etc/modules-load.d/` so a
  reboot doesn't silently re-break the cluster.
- **Pinned addon image digests rot.** minikube 1.35's registry addon
  pins a `kube-registry-proxy` digest that no longer exists on gcr.io;
  the addon can never come up on that minikube version regardless of
  configuration. The fix was upgrading minikube, not debugging the
  cluster.

The lesson is CAP-044's ("test the bootstrap on a fresh profile") taken
one level further: test on a fresh *host* occasionally, because the
bootstrap also accumulates couplings to host state — loaded kernel
modules, tool versions, listening ports — that a fresh profile on the
same machine can't expose.

### `imagePullPolicy: Always` for mutable tags during development

The reference uses `:v1` as a development tag (not for production, where
content-addressable tags or proper semver belong). With a mutable tag,
kubelet's default `IfNotPresent` policy means it never re-pulls; you push
a new image and nothing changes in the cluster until you delete the pod
and let it re-roll. Set `imagePullPolicy: Always` on development services
to make every pod restart fetch the latest image. Memorialised as CAP-015.

---

## Process lessons — making the next iteration cheaper

### Walking-skeleton-first

The first vertical slice through a system — one service, end-to-end,
shippable — is worth more than the same time spent building out any
single horizontal layer. The reference's r21 brought up *one* service
(order-service) end-to-end: REST handler, database, schema, container,
manifest, helm chart, smoke test, deployed. After that, the other four
services followed a template (CAP-011) in roughly an iteration each;
every horizontal-layer concern (the Postgres operator, the in-cluster
registry, the chart structure) was already proven by the time it had
to scale to five services. Memorialised as CAP-006.

The lesson generalises: vertical slices are debt-reducing; horizontal
layers built ahead of a working slice are speculation.

### Reconciliation discipline

Claims default to `unverified` until cluster-tested. The reconciliation
file at `_plans/reconciliation.md` tracks every claim the reference
makes (in prose, in code, in diagrams) and its verification state.
Without it, prose drifts from reality silently.

The pattern that emerged: every cluster run is an opportunity to verify
or invalidate a claim. The reconciliation file makes the audit
explicit; CI can't catch a claim-versus-reality gap because the claim
is in prose.

### Diagram dual-emission

Every diagram in `assets/diagrams/` is a paired SVG + Excalidraw. SVG is
what the site embeds and what versions cleanly in git; Excalidraw is the
source-of-truth for editing. Edit the Excalidraw, re-export the SVG,
commit both. This is much better than: regenerating raster images that
look slightly different every export, or maintaining the diagram in
Visio or draw.io and hoping the export stays consistent.

### Iteration tags (rNN, rNN.M)

A single linear iteration counter for the project, with dotted suffixes
for same-iteration re-ships. r21, r22, r22.1, r23. The convention
solves a real Downloads-folder problem: when a tar gets re-shipped with
a fix during the same iteration, the dotted suffix prevents the older
download from masking the newer one. Memorialised in the archive's
later CAPs as "the rule I keep forgetting."

### Smoke suites need an explicit baseline — and more than one run order

The smokes clean up the service releases they deployed when they pass
(CAP-008). Individually that's good hygiene; as a *suite* it means every
passing smoke can remove a shared service the next smoke assumes, and a
failure then indicts the run order rather than anything the failing
smoke actually tests (demo-order 503'd twice because an earlier smoke's
cleanup had removed inventory-service). The remedy is an explicit,
idempotent baseline-restore step (`scripts/restore-baseline.sh`) run
between groups, which makes the order not matter.

The second half of the lesson: a suite that has only ever passed in one
order hasn't demonstrated order independence. The same 24 scripts were
run in a deliberately shuffled order and one more latent race fell out —
a smoke that had passed two full runs on lucky timing (demo-kafka's
dead-tunnel poll, `e22b318`). Shuffling the order is the cheapest chaos
test a suite can get.

And when a fix lands, verify it *under the conditions that failed* — the
retry paths here were confirmed by watching them fire in the logs (two
dead-tunnel attempts then success; one 502 then 200), not by a pass on a
warm cluster that might never have exercised them.

### Decision log with rejected alternatives

The most useful part of each CAP isn't the decision — it's the
**Rejected alternatives** section that says "we considered X and didn't
do it for these reasons." When the project comes back to a decision (and
it will), the rejected alternatives are the institutional memory of
what's already been thought through.

---

## What I would do differently next time

A short list:

1. **Mesh-injection opt-out in chart defaults.** The pattern of meshed
   Jobs hanging at `1/2` cost too many iterations to discover. If I
   were starting over, every chart's pod templates would carry
   `sidecar.istio.io/inject: "false"` for Job-shaped workloads from
   day one, and the prose would call out the default rather than the
   exception.

2. **Alembic from r21.** `create_all` was expedient and immediately
   limiting. Starting with Alembic in an init-container would have
   cost half a day and saved several.

3. **Catalog as a first-class service from r17.** The reference adds
   the catalog (OpenMetadata) late — after services, contracts, mesh,
   autoscaling. It would have been smaller-scoped and easier to land
   if it had been brought up alongside the schema registry early, even
   in a minimal "service inventory only" mode, with lineage added
   later. As shipped, the catalog work compressed into the late
   iterations under deadline pressure (CAP-022's three-cycle helm
   debugging).

4. **Test the bootstrap on a fresh profile every iteration.** The
   bootstrap script accumulated coupling to the cluster state it was
   developed against. Running it on a fresh minikube profile every
   couple of iterations would have caught those couplings before they
   became multi-step recovery procedures (CAP-044 was eventually the
   forcing function).

5. **Resist the pull of vendor-specific framing.** The deck was titled
   "Data Mesh on OpenShift" deliberately, but several diagrams use
   OpenShift terminology (Project, OperatorHub, SCCs) that this
   standalone repo has to either keep, contextualise, or rewrite. If
   the goal had been a vendor-neutral reference from the start, the
   diagrams would have been vendor-neutral from the start. The
   `/docs/10-summary/` page contextualises them, which is the right
   call now — but the rewrite would have been the right call earlier.

6. **Re-baseline the smokes when the platform under them changes.** The
   scale-to-zero scalers were added in r26b, but the smokes written
   before that (avro, notifications, kafka, discovery, order) kept
   assuming an always-on target — and kept passing, on lucky timing,
   until a fresh-host campaign in a different run order exposed all of
   them at once. When a cross-cutting platform behaviour changes (an
   autoscaler, a mesh policy, a new operator), re-run the *existing*
   test suite against the new reality deliberately, rather than letting
   each old assumption surface as a one-off flake months later.
