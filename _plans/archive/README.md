---
title: "Archive — decisions and reconciliation from the capstone era"
render_with_liquid: false
---

# Archive — capstone-era plans

These files are the historical decision log and reconciliation record from
when the data-mesh reference architecture lived inside the `minikube-on-fedora`
tutorial as its §17 capstone. They're preserved here for the audit trail —
how each design choice was made, the reasoning behind it, and the verification
status of each claim at the time the work was done.

They are NOT the active plans for this repo. Active decision log and
reconciliation tracking lives in `_plans/decisions.md` and
`_plans/reconciliation.md` (alongside this directory).

Cross-references in these archived files may point at paths that don't exist
in this repo (e.g. `/docs/12-keda/`) — that's expected; those links were to
the parent tutorial's content, which isn't part of this repo.

The files:

- `capstone-decisions.md` — the architectural and editorial decisions from
  CAP-001 through CAP-047, with rationale, evidence, and rejected
  alternatives for each.
- `reconciliation-plan.md` — the reconciliation rows tracking which
  claims were `unverified` / `verified (Fedora 44)` / `superseded` at each
  iteration of the build.
- `capstone-roadmap.md`, `iteration-plan.md`, `phase-c-plan.md`,
  `phase-d-deck-plan.md`, `prd-reconciliation.md` — phase plans and the
  PRD reconciliation from the original project.

The original repo (`patterncatalyst/minikube-on-fedora`) remains canonical
for the parent tutorial; this archive captures the §17 capstone slice as it
stood when it was forked into this standalone reference.
