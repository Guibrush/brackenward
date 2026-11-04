# ADR-0002 — The G2 vertical slice is one complete run

Date: 2026-11-04
Status: accepted (2026-11-04)
Deciders: Guybrush Threepwood (human)

## Context

The gate definition `docs/gates/G2-vertical-slice.md` gates the slice on five
minutes of play:

- `G2.1` — a headless smoke run of 300 s exits 0 with no error lines.
- `G2.2` — a human plays the same scene for five minutes and notes what felt
  broken.

During the G0 charter interview the run structure was settled as a branching map
of 5–10 levels with HQ health carrying between levels, failing a level ending the
run, and a boss level at the end of the map. Session length was set at 15–30
minutes, one run per sitting.

A five-minute slice cannot demonstrate the thing the game is: the arc from a
fragile opening defence to a build that either holds or snaps, and the routing and
upgrade choices that produce it. Prototyping one third of a run and calling it the
vertical slice would test the tower defence and not the roguelike.

## Decision

1. The G2 vertical slice is **one complete run**, start to boss, in the session
   length the charter states. It is not a five-minute excerpt.
2. `G2.1` is rewritten at G2 planning time as a **stability** criterion: a headless
   run of at least 300 s completes without a crash or error line. Its purpose is
   unchanged — catching engine-level breakage cheaply — and it stays cheap on
   purpose. It no longer claims to be "the full loop".
3. `G2.2` is rewritten at G2 planning time as a **human** criterion: one complete
   run from first level to boss, played to its end, noting anything that stopped
   play in one line each.
4. Both rewrites are recorded as gate changes in this ADR and signed by the human
   before the G2 gate is run. Until that signature exists, the gate text in
   `docs/gates/G2-vertical-slice.md` stands unchanged and G2 cannot pass.
5. No other G2 criterion changes as a result of this decision.

## Consequences

**Intended:** the slice proves the run, not just the combat. Failure modes that only
appear across levels — HQ health attrition, a build that never comes together, a map
that offers no real routing choice — become visible at G2 instead of at G3.

**Accepted cost:** G2 becomes materially larger. A complete run requires a branching
map, several hand-made level layouts, the between-level choice system, a store, and
a boss, where five minutes required one map. The scope budget in
`docs/CHARTER.md` is set with that cost in mind, and the level count per run is
explicitly a placeholder until something is playable.

**Cost of being wrong:** if a complete run at G2 proves too large, the remedy is a
new ADR that narrows the slice, signed by the human. It is not a quiet edit to the
gate text, and it is not a criterion bent to make the gate pass.

## Rejected alternatives

**Keep the five-minute gate and build a partial run.** Cheapest, and rejected
because it leaves the roguelike structure — the actual design risk — untested at the
first gate that exists to test it.

**Leave the gate text alone and let the slice exceed it.** The gate would pass while
measuring something narrower than what shipped, which is the kind of contradiction
that gets discovered on the day the gate is run.

**Gate on elapsed run time instead of completion.** Ambiguous: a run that stalls at
level 3 for twenty minutes would satisfy it. Completion is the observable, not
duration.
