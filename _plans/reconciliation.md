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
| **verified** | This repo's `examples/lgtm-datamesh/` tree builds and runs the data-mesh reference end to end, producing the same five-act walkthrough verified in the parent repo as of r28 | `examples/lgtm-datamesh/` | Verified 2026-07-04/05 on a fresh Fedora 44 host (rootless podman, minikube 1.38.1, fresh `capstone` profile): `./scripts/bootstrap-capstone.sh` then `./demos/walkthrough.sh` → 5/5 acts green, twice (once in-order, once in the shuffled suite). Caveats that verification surfaced and this repo fixed: six demo-script bugs (`5403d06`–`e22b318`), plus two host prerequisites the README didn't list — legacy `ip_tables`/`iptable_nat` kernel modules loaded on the host (Fedora is nftables-only; the rootless node can't modprobe), and minikube ≥ 1.36 (1.35's registry addon pins a dead `kube-registry-proxy` digest). |
| **verified** | Every demo script passes against the bootstrapped stack: all 19 `demos/smoke-*.sh`, the `demo-canary.sh` cycle (up 90/10 → shift 50/50 → down), and the `demo-add-data-product.sh` cycle (up → down) | `examples/lgtm-datamesh/demos/` | Verified 2026-07-04/05, same host: two full-suite runs (24 scripted invocations each) green, with fixes landed and re-verified between them. Fix verification exercised the failure paths live (dead-tunnel port-forward re-attach, gateway wake from scale-to-zero, interceptor cold-start 502 retry). |
| **verified** | The smokes are order-independent when `scripts/restore-baseline.sh` is run between groups (the smokes' pass-cleanup, CAP-008, otherwise couples them) | `examples/lgtm-datamesh/scripts/restore-baseline.sh` | Verified 2026-07-05: full suite re-run in a deliberately shuffled order (gateway-heavy first, `smoke-order` immediately after the cleanup-happy group — its prior failure position) with `restore-baseline.sh` between groups → all green. The shuffle also exposed one latent race (`smoke-kafka`, fixed in `e22b318`) that two in-order runs had passed on timing. |
| **unverified** | `README.md`'s "Prerequisites (verified configuration)" section is sufficient for a fresh-host bring-up | `examples/lgtm-datamesh/README.md` | Known gap from the 2026-07 campaign: the section does not list the legacy iptables kernel modules or the minimum minikube version (see the caveats on the first row). Prose update pending; until then the bootstrap fails at tier 1 on a stock Fedora host and the fix commands live in the failure output and LESSONS-LEARNED. |
