# State

Only `studio-lead` writes this file. Every other agent reads it.

Last updated: 2026-11-10

## Milestone

**G2 — Vertical slice, in progress.** G0 and G1 signed. The full gate suite passes
(13 scripts, 0 fail); the slice is playable but not yet a game.

## Gate status

| Gate | Result | Signed by | Date |
| --- | --- | --- | --- |
| G0 Concept | pass | Guybrush Threepwood | 2026-11-04 |
| G1 Bootstrap | pass | Guybrush Threepwood | 2026-11-05 |
| G2 Vertical slice | **not signed** — scripted criteria green, human criteria outstanding | — | — |

## What exists and works

- **Run**: 9-layer branching map, node types, store and offers, run state with carried HQ,
  inventory, choice modal for the opening pick and for events.
- **Level**: tower placement, three tiers, targeting, wave director with escalating waves,
  Start Wave control, HQ leaks, defeat and completion.
- **UI**: main menu, map screen, corner block with exactly HQ / wave number / Start Wave,
  square inventory bar with paging and gold, drag-and-drop placement from the bar,
  tower window with equip and tier-up.
- **Gates**: 13 scripts green, 5 suite cases (~5800 checks), smoke 4/4 at 300 s, perf 687 fps
  (last measurement; see L-040 for the display provenance).

## Known broken or unfinished

| Item | State |
| --- | --- |
| Upgrade slot label wraps mid-word | square slot is narrow; clip or shorten |
| Anchored, non-modal tower window | window exists but opens centred/full; must anchor near the icon and close on outside interaction |
| Map-screen drag is inert | the bar is drawn on the map; a drag there shows the ghost and raises a drop with no level to receive it |
| `armed_feedback_demo` is red | already red at HEAD before T-0081: unresolved opening-choice modal and tower rows removed in T-0068; update or retire it |
| Controller placing mode | not built; drag-and-drop is mouse-only, pad keeps click-then-tile |
| Tower window behaviour proven | component and wiring exist, no demo proves equip/tier-up/read-only |
| Square-slot demo, frame, planted failure | owed for T-0075 |
| Art integration | towers and enemies are still polygons; one tower sprite is shipped and unwired |
| Content | 9 maps, 6 towers, 20 items, 5 enemies + bosses exist as tables, not content |
| Audio batch | 4 tracks + ~48 one-shots unbuilt; music blocked on ADR-0005 |
| Fun hypothesis test | not run — G2.11 |

## Next action

1. Anchor the tower window near its slot and make it non-modal (it must not open centred).
2. Controller placing mode, bindings in data.
3. Art integration, then content, then audio, then the five testers.

## Metrics

| Metric | Value | Note |
| --- | --- | --- |
| Builder cap-hit rate | 3 of 5 dispatches on 2026-11-10 (60%) | T-0077 and T-0080 fit; T-0078 capped twice and T-0079 once. Single-method briefs still cap when the shared demo grows. |
| Usable delivery under a cap hit | 100% | T-0078's second cap left a planted mutation on disk; L-042 now forbids that and requires copy-only demonstrations. |
