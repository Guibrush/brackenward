# ADR-0006 — A run's level count is a route outcome, not a constructor argument

Date: 2026-11-06
Status: accepted (studio-lead; human review welcome)
Deciders: studio-lead, on the human's instruction to settle it before wiring

## Context

`RunState.start(level_count, hq_max, starting_gold)` takes a level count up front and
treats "final level" as a number reached. That matched the earlier model, where a run was
a fixed sequence of levels.

It no longer matches the game. A run traverses a **generated map** of nine layers, and
only some node types are levels: `store`, `rest`, `treasure`, `event` and the boss preview
are visited but are not played. So:

- the number of levels in a run is a property of the **route the player takes**, not
  something knowable when the run starts;
- `run_map.max_levels()` is a **ceiling** (ten, at best), not a count;
- a map's **layer index** is not a **level index** — visiting two stores in a row leaves
  the level index untouched.

Wiring `RunState` into the arena against the old signature would implement the wrong
model, and the tests written against it would then encode the mistake.

## Decision

1. **`RunState.start()` takes no level count.** It takes `hq_max` and `starting_gold` only.
2. **`RunState` counts levels completed, never a total.** `level_index()` means "how many
   levels have been finished", and it increments only when a level-type node is completed.
3. **The map is the authority on progress.** Entering or completing `store`, `rest`,
   `treasure`, `event` and `boss_preview` nodes does not touch the level index.
4. **Victory is completing the boss node**, not reaching a count. `RunState` exposes
   `complete_level()` and `win_run()`; the map decides when the boss node has been
   finished and calls it.
5. **`run_map.max_levels()` is advisory**: it exists for UI ("up to ten levels") and for
   sanity checks in tests, never as a loop bound.
6. Existing tests that assert on a fixed count are updated to assert on the sequence of
   completions instead.

## Consequences

**Intended:** the run state stops encoding an assumption the design has already left
behind. A five-level route and a ten-level route are the same code path, differing only in
how many map nodes the player took.

**Accepted cost:** `RunState` no longer knows when a run is "almost over", so anything
wanting a progress bar must ask the map. That is correct — the map is the only object that
knows both the route and the remaining layers.

**Test impact:** `run_state_selftest.gd` currently starts runs with a level count; its
cases are rewritten to drive completions through the map object or through explicit
`complete_level()`/`win_run()` calls.

## Rejected alternatives

**Keep `level_count` and compute it from the route at start time.** The count is knowable
only after the route is chosen, which is after the run has begun, and it changes if the
map allows re-routing. A fixed count that can move is worse than none.

**Let layer index double as level index.** Wrong by construction: store and rest layers
are not played, so a layer-derived index would skip levels the player never fought.
