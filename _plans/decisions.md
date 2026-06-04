---
title: "Decisions"
render_with_liquid: false
---

# Decisions

This is the active decision log for the data-mesh reference architecture as
a standalone repo. Each significant architectural or editorial choice gets a
numbered entry below, with rationale and rejected alternatives.

The historical decisions from the project's earlier life as the §17 capstone
of `patterncatalyst/minikube-on-fedora` are preserved in
`_plans/archive/capstone-decisions.md`. New decisions specific to this
repo's standalone life start from DRA-001 below to avoid number-collisions
with the archive's CAP-NNN series.

---

## DRA-001 — Extract the data-mesh reference as its own repo

**Status:** decided; this commit is the materialization.

**Context.** The data-mesh reference originally lived as §17 of the
`patterncatalyst/minikube-on-fedora` tutorial. Over the course of the
project (CAP-001 through CAP-047 in the archived decision log), it grew
into a substantial standalone artifact: nine reading-set pages, a complete
runnable example tree, two presentations, and a comprehensive diagram set.
The §17-of-a-bigger-tutorial framing started to limit it — readers who
wanted just the data mesh had to navigate from a Minikube-on-Fedora landing
page, and the build's audience (people thinking about data mesh, not
specifically people learning minikube) was a mismatch with the parent
project's title.

**Decision.** Fork the data-mesh content into its own repo:
`patterncatalyst/datamesh-reference-arch-python`. The capstone-era pages
become this repo's primary content collection. The runnable example tree
moves to `examples/lgtm-datamesh/`. Presentations and assets come along.
The historical decision log lives at `_plans/archive/capstone-decisions.md`
as the audit trail of how the implementation was built.

**Consequences.**

- The new repo's `_docs/` collection is the data mesh; URLs are
  `/docs/01-concepts/` rather than `/capstone/data-mesh/01-concepts/`.
- The new repo's `index.html` is the data-mesh hero page (formerly
  `capstone/data-mesh.html` in the parent repo).
- The `lgtm-datamesh` rename of the example tree (formerly `17-capstone`)
  disambiguates it from the parent repo's `17-capstone` example, which
  still exists for readers who arrive via the minikube tutorial.
- New decisions in this repo are tracked here with `DRA-NNN` numbering;
  the `CAP-NNN` series is closed.

---

## DRA-002 — *(reserved for the next decision)*
