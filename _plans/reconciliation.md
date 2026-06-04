---
title: "Reconciliation"
render_with_liquid: false
---

# Reconciliation

Active reconciliation tracking for the data-mesh reference architecture in
its standalone form. Each row records a claim made by this repo (in prose,
in code, in a diagram) and its verification state. The pattern matches the
archived plan: claims default to `unverified` until cluster-tested.

The historical reconciliation rows from the capstone era are preserved in
`_plans/archive/reconciliation-plan.md`.

| Status | Claim | Where | Verification |
|---|---|---|---|
| **unverified** | This repo's `examples/lgtm-datamesh/` tree builds and runs the data-mesh reference end to end, producing the same five-act walkthrough verified in the parent repo as of r28 | `examples/lgtm-datamesh/` | Cluster-verifiable: from a fresh minikube profile, `./scripts/bootstrap-capstone.sh` followed by `./demos/walkthrough.sh` should produce 5/5 acts green. (Same verification procedure as the parent repo's r28.) |
