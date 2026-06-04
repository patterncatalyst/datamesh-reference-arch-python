# Lessons learned

> Scaffold — to be filled out during the editorial pass with content drawn
> from `_plans/archive/capstone-decisions.md`. The capstone era produced a
> lot of hard-won lessons (CAP-001 through CAP-047) that are worth
> distilling into a forward-facing "things we learned" document for this
> repo's readers.

---

## The biggest single lesson

TODO — pick the headline lesson. Strong candidates from the archive:

- *Mesh selectively, not namespace-wide* (CAP-038). The most architecturally
  important judgment in the build — and the one most likely to be skipped
  by people new to Istio because the namespace-wide default is much easier
  to type. The reasons for opting out (Job pods, operator-managed
  databases with their own TLS, control-plane coupling) are concrete and
  show up in real systems.

- *Match the scaler to the workload* (CAP-025, CAP-045). KEDA on Kafka lag
  for event consumers; KEDA HTTP for read gateways. Each scaler suits a
  specific demand signal; mixing them — or using one for both — produces
  cascading failures.

- *Operational vs. analytical, but on the same plane* (across the build).
  The data mesh idea most often misread: the operational/analytical
  distinction is about *what kind of question is being asked*, not about
  separate systems.

---

## Mechanical lessons (hard-won, easily missed)

TODO — needs editorial pass. Roughly:

- *Sidecar-vs-Job conflict* — meshed Jobs never terminate. Specifically
  affected the OpenMetadata ingestion path.
- *Sidecar-vs-managed-database TLS conflict* — the database's internal TLS
  collides with the injected sidecar's wrapping. Specifically affected
  CloudNativePG.
- *Helm secret wiring* — three live fix cycles on OpenMetadata before the
  chart's expectations clicked into place. The pattern: name collisions
  between user-supplied and chart-generated secrets, missing placeholder
  secrets the chart references even with features disabled,
  `CreateContainerConfigError` always signaling config, never application.
- *Node idle-decay on long-lived minikube profiles* — kube-proxy can lose
  its `/dev` mounts and stop routing Service traffic. Cycling the node
  resolves it.
- *Native sidecars in Istio 1.29+* — `istio-proxy` is an `initContainer`
  with `restartPolicy: Always`, not a regular container. Mesh-membership
  checks that look at `.spec.containers` miss it.

---

## Editorial / process lessons

TODO. Roughly:

- Decision-log discipline — every architectural choice gets an entry with
  rationale, evidence, and rejected alternatives. Without it, decisions
  get unmade by accident in subsequent iterations.
- Reconciliation tracking — claims default to `unverified` until cluster-
  tested. The pattern caught real drift between prose and reality
  repeatedly.
- Diagram dual-emission — paired SVG and Excalidraw, generated from one
  spec. SVG embeds; Excalidraw edits. Both ship.
- Iteration tags (rNN, rNN.M) — a single linear iteration counter, with
  dotted suffixes for same-iteration re-ships, prevents the "which tar
  in Downloads is the right one" problem.
