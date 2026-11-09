# Lessons

Rules derived from real events. Maintained by `archivist`, read by everyone.
Keep this file near 100 lines; archive the oldest entries to
`docs/lessons/archive-<milestone>.md`.
Entries L-001 … L-008 (2026-11-02 → 2026-11-03) live in
`docs/lessons/archive-G0.md`; entries L-009 … L-012 (2026-11-04) live in
`docs/lessons/archive-G1.md`; entries L-013 … L-014 (2026-11-04) live in
`docs/lessons/archive-2026-11-04.md`; entries L-015 … L-031 (2026-11-05) live
in `docs/lessons/archive-2026-11-05.md`; entries L-032 - L-035 (2026-11-05)
live in `docs/lessons/archive-2026-11-06.md`; entries L-036 - L-037
(2026-11-06) live in `docs/lessons/archive-2026-11-07.md`; entries L-038 - L-039
(2026-11-06) live in `docs/lessons/archive-2026-11-09.md`. Their rules remain
in force.

## L-040 — 2026-11-07 — A performance gate must record the machine's display conditions
Situation: G2.3 passed for weeks at 651 fps / 2.66 ms p99, then went red
(57.7-61 fps, p50 ~17 ms, p99 32.9 ms) with no code change: `scripts/perf/*` and
`scripts/gate/perf.ps1` untouched since commit 08b9bed, `project.godot` since
7be2990. The cause was the machine, not the code: the display now runs at 59 Hz
(Win32_VideoController: RTX 2070 SUPER, current/max refresh 59) with a Parsec
virtual display adapter present, so even with vsync off frame delivery paces to
one ~17 ms refresh period and frame misses blow the 20 ms p99 ceiling. The
gate's output names the renderer and viewport (`scripts/gate/perf.ps1:147,180`)
but not the refresh rate, so a capped machine was indistinguishable from a
regression until someone inspected the display by hand.
Worked: comparing git history for the benchmark and gate script to rule out a
code change, then measuring the display directly.
Failed: the gate recording renderer and resolution but not the refresh rate or
the presence of a virtual display adapter; the red result carried no provenance.
Rule: a performance gate must record the measurement conditions alongside the
numbers — renderer, resolution, refresh rate, and whether a virtual display
adapter is in the path — so a red result can be attributed to the code or to the
environment from the gate output alone, without a manual investigation.
Evidence: scripts/gate/perf.ps1:89,147,180 (no refresh rate anywhere); git log
--oneline -- scripts/perf scripts/gate/perf.ps1 = 08b9bed, nothing later;
Win32_VideoController 2026-11-07: RTX 2070 SUPER, current/max refresh 59; Parsec
Virtual Display Adapter present.

## L-041 — 2026-11-09 — A log line reading the model is not evidence about the visible node
Situation: T-0076 restructured `scenes/build_panel.tscn` so the column moved
from `Margin/Column/*` to `Block/Margin/Column/*` and updated `margin_path` but
not the seven exported copy paths in `src/ui/build_panel.gd:225-237`
(Title, State, Wave, Actions, Status, Reason, Hint). `_node()` returned null and
the block rendered only the scene's static text (`HQ 0/0`, `Wave 0/0`). Commit
c5536ea shipped it anyway; HEAD is 1917afa. Review passed because the demo/log
line `BUILD_PANEL_SHOWN` prints `state()` and `wave()` — live reads from the run
and arena — so the printed evidence was correct (`HQ 10/10`, `Wave 1/6`) while
the player-visible Label stayed wrong.
Worked: `src/ui/tests/inventory_migration_demo.gd` reads the label through the
same broken `state_path`, so running it today reports
`PANEL_BAR_SELF_TEST ... "failed":1, "failures":["the panel's state line still
carries HP: '<missing>'"]` with exit code 1 — the existing test caught what the
shipped log line hid.
Failed: treating a passing log line that reads the model/dictionary as evidence
about the artifact the player sees; the scene restructure updated one exported
NodePath and left seven stale with no assertion that any resolved node is
non-null.
Rule: a UI demo must assert the node the player actually sees — the Label.text
resolved through the shipped path — not the model the screen reports; a scene
restructure must update every exported NodePath, and at least one assertion must
fail if any resolved path is null or its text disagrees with the live value.
Evidence: src/ui/build_panel.gd:225-237 (paths still `Margin/Column/*` at HEAD
1917afa); commit c5536ea diff; inventory_migration_demo.gd output 2026-11-09,
exit code 1; same family as L-038 (proxy metric blessed a visible defect).

## L-042 — 2026-11-09 — A planted failure must never start in the real tree
Situation: T-0078 (`tasks/T-0078.md`, bar drag gesture) hit the 40-step builder
cap twice. On the second follow-up the builder planted the failure demonstration
directly in the real tree: in `src/ui/inventory_bar.gd` `_finish_drag()` it
inserted `if dropped:\n\t\treturn` before `tower_dropped.emit(...)`. At the cap
the mutation was still on disk — the tree was non-green and the drop signal dead
— and the planted failure had been started inside the reserved 8-step window, so
it could not be reverted by the builder. The report did name the line and say
"the tree is currently in a bad state"; studio-lead removed the `return`,
re-ran `--check-only` on `src/ui/inventory_bar.gd` and
`src/ui/tests/inventory_migration_demo.gd`, the demo
(`PANEL_BAR_SELF_TEST {"checks":152,"failed":0,...}`) and
`scripts/gate/tests.ps1` (5/5), then committed 38c1f62.
Worked: the report naming the exact mutated line let studio-lead revert in one
edit; the demo and gate script verified the restore before the commit.
Failed: `AGENTS.md` "Failure demonstrations" already requires mutations to run
through `scripts/gate/prove-failure.ps1` on a throwaway copy (copy deleted in
`finally`), with in-place mutation reserved for non-copyable cases and requiring
`.mutation-active`, a recorded SHA-256 backup and a verified restore — none of
that was used. The return also did not treat the on-disk mutation as a blocker.
Rule: a planted failure is never started in the real tree; run it through
`prove-failure.ps1` on the copy, and if the steps remaining cannot include the
revert, do not plant it at all. A return must state whether the tree is clean,
and a mutation left on disk is a blocker, not a partial.
Evidence: tasks/T-0078.md; src/ui/inventory_bar.gd `_finish_drag()` mutation
removed by studio-lead; demo PANEL_BAR_SELF_TEST checks:152 failed:0;
scripts/gate/tests.ps1 5/5; commit 38c1f62; cap metric secondary evidence: the
same brief consumed 80 steps across two dispatches for two files because the
shared demo grew to 152 checks / ~335 changed lines; T-0079 was cut to one
method and six assertions.
