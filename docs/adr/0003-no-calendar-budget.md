# ADR-0003 — No calendar budget; gated by evidence

Date: 2026-11-04
Status: accepted (2026-11-04)
Deciders: Guybrush Threepwood (human)

## Context

`docs/gates/G0-concept.md` criterion `G0.10` reads: "The charter's scope is
believable for the stated calendar budget", judged by human taste.

The charter's scope budget carried a row for "calendar time to G2". During the G0
interview the human removed that commitment: this is a self-directed project built
at the owner's own pace, with no ship date promised. Editing the charter alone
would leave `G0.10` measured against something the charter no longer states.

## Decision

1. The charter states **no calendar budget**. The scope budget table contains no
   time row, and its header says so.
2. `G0.10` is reworded when the G2 gate text is next touched, to:
   "The charter's scope is believable for a project built at the owner's pace with
   no deadline committed" — still a human taste judgement, still the criterion most
   likely to be wrong and the cheapest place to be wrong.
3. Until that wording is signed, the existing `G0.10` text stands, and the human
   signs G0 knowing it is being read in the spirit of this ADR.
4. Scope discipline does not weaken. Because no deadline applies pressure, the
   remaining protections are the non-goals, the ranked pillars, and the fixed slice
   budget — and they are enforced by the gate scripts, not by the calendar.

## Consequences

**Intended:** no gate can be hurried to hit a date, and no schedule claim appears in
the charter that the project cannot keep.

**Accepted cost:** there is no external signal that the project is running long. The
evidence for "this is taking too long" has to come from the slice itself — a run
that will not come together after the budgeted systems exist is the signal.

**Reproducibility:** gate results stay comparable across time, since none of them
depend on a date.

## Rejected alternatives

**Keep a token calendar row to satisfy `G0.10`.** That would put a number in the
charter that nobody intends to honour, which is worse than having none.

**Delete `G0.10`.** It is the only criterion asking whether the scope is buildable at
all. The criterion is sound; only its reference to a calendar is stale.
