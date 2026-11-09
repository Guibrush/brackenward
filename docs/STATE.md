# State

Only `studio-lead` writes this file. Every other agent reads it.

Last updated: 2026-11-09

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
- **UI**: main menu, map screen, corner block (HQ / wave / Start Wave), square inventory bar
  with paging and gold, tower window with equip and tier-up.
- **Gates**: 13 scripts green, 5 suite cases (~5800 checks), smoke 4/4 at 300 s, perf 687 fps.

## Known broken or unfinished

| Item | State |
| --- | --- |
| Corner block reads `HQ 0/0` and `Wave 0/0` | **regression from T-0076** — renders but does not refresh after binding. Fix first. |
| Upgrade slot label wraps mid-word | square slot is narrow; clip or shorten |
| Drag-and-drop placement | not built |
| Anchored, non-modal tower window | window exists but opens centred/full; must anchor near the icon and close on outside interaction |
| Controller placing mode | not built |
| Tower window behaviour proven | component and wiring exist, no demo proves equip/tier-up/read-only |
| Square-slot demo, frame, planted failure | owed for T-0075 |
| Art integration | towers and enemies are still polygons; one tower sprite is shipped and unwired |
| Content | 9 maps, 6 towers, 20 items, 5 enemies + bosses exist as tables, not content |
| Audio batch | 4 tracks + ~48 one-shots unbuilt; music blocked on ADR-0005 |
| Fun hypothesis test | not run — G2.11 |

## Next action

1. Fix the corner block's binding (`HQ 0/0`), then drag-and-drop placement from the bar.
2. Anchor the tower window near its slot and make it non-modal.
3. Controller placing mode, bindings in data.
4. Art integration, then content, then audio, then the five testers.

## Metrics

| Metric | Value | Note |
| --- | --- | --- |
| Builder cap-hit rate | ~90% of dispatches hit 40 steps | briefs still too big; the ones that fit are single-file, single-demo |
| Usable delivery under a cap hit | 100% | the reserve rule works; the cap does not |
