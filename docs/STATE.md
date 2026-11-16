# State

Only `studio-lead` writes this file. Every other agent reads it.

Last updated: 2026-11-16

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
  anchored non-modal tower popover with equip, tier-up and take-back, and controller
  placement: left/right focuses the bar, confirm arms, directions move a tile cursor,
  confirm places, dismiss cancels. The game presents at a 960x540 logical viewport in a
  windowed 1920x1080 surface (integer 2x).
- **Art**: six tower sprites (arrow, ballista, mortar, rime, beacon, bramble) and eight
  enemy sets (grunt, runner, shieldback, swarmling, bloom, bulwark, herald, warden),
  static, four directions, wired into `tower.tscn` and `enemy_walker.tscn`. Animation is
  deferred by ADR-0009. All of this sits on `task/T-0093-ballista-candidate` / draft PR
  #95, not yet merged to `dev`.
- **Gates**: 13 scripts green, 6 suite cases (~5800+ checks), assets 4/4; smoke 4/4 at
  300 s and perf 687 fps are the last measurements and predate the 2x display.

## Known broken or unfinished

| Item | State |
| --- | --- |
| Upgrade slot label wraps mid-word | square slot is narrow; clip or shorten |
| Map-screen drag is inert | the bar is drawn on the map; a drag there shows the ghost and raises a drop with no level to receive it |
| Stale demo walks | `armed_feedback_demo`, `input_route_demo`, `build_panel_demo`, `build_panel_boot_demo` are red before this milestone's UI tasks (opening-choice modal, tower rows removed in T-0068); each needs its walk repaired or retired |
| Tower window behaviour proven | component and wiring exist, no demo proves equip/tier-up/read-only |
| Square-slot demo, frame, planted failure | owed for T-0075 |
| Art integration | The static set is generated, director-approved and wired on `task/T-0093` (PR #95, draft); it awaits human review and merge. Animation deferred (ADR-0009). Known quality notes: runner north/south views are thin (8 px), herald/warden read as horned humanoids rather than mantis/root titan, grunt is a pale-headed robed humanoid rather than a tusked goblin. Tower tier pips are still the placeholder amber square |
| Display scale | Windowed 2x at a 960x540 logical viewport is in the art branch; `smoke.ps1` and `perf.ps1` have not been rerun under it, and the demo viewport constants moved with it |
| Content | 9 maps, 6 towers, 20 items, 5 enemies + bosses exist as tables, not content |
| Audio batch | 4 tracks + ~48 one-shots unbuilt; music blocked on ADR-0005 |
| Fun hypothesis test | not run — G2.11 |

## Next action

1. Human review of the art set (contact sheet `%TEMP%\opencode\g2_art_set.png`), then mark
   PR #95 ready, run the gates on its final head and merge it to `dev`.
2. Content: turn the 9 maps, 6 towers, 20 items and 8 enemies from tables into actual
   content; then the audio batch.
3. The five testers and the fun-hypothesis test (G2.11).
4. Before G2 is signed: repair the stale demo walks, prove the tower window's read-only
   path against a real wave, deliver T-0075's demo/frame, add `docs/LICENSES.md`, and
   rerun smoke/perf on the 2x display.

## Metrics

| Metric | Value | Note |
| --- | --- | --- |
| Builder cap-hit rate | 10 of 16 dispatches on 2026-11-12 (63%) | T-0077, T-0080, T-0082, T-0088 and T-0089 fit; T-0090 overran its 30-step brief without hitting 40; the rest capped. The lead finished the partials. Not updated for the 2026-11-15/16 art dispatches, most of which capped or partially returned. |
| Art generation spend | credits $9.87 left; plan 48 used / 0 remaining, daily bonus pools used | About $0.15 of credit across towers and enemies; one concurrent-dispatch collision wasted 3 generations (L-050). No top-up was needed. |
| Usable delivery under a cap hit | 100% | T-0078's second cap left a planted mutation on disk; L-042 now forbids that and requires copy-only demonstrations. |
