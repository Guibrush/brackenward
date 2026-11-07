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
(2026-11-06) live in `docs/lessons/archive-2026-11-07.md`. Their rules remain
in force.

## L-038 — 2026-11-06 — A passing proxy metric is not appearance evidence
Situation: after the flat-crown rejection, a metric was invented for the fix:
the first opaque rows must show separated merlon runs, not one flat bar. Three
hand-authored merlons passed it exactly (runs `[4,4,4]` over four rows, 52 px
changed, none below the crown), the asset gate went green, and the sprite
shipped. The human rejected it again: the top is a flat quad with no far wall,
so the merlons read as three free-standing blocks — the metric counted
separated runs, not "looks like a battlement". The sprite was reverted.
Worked: the human's second rejection, which caught what the metric could not.
Failed: treating a derived statistic as the definition of the fix, and gating
appearance on it without showing the result to the human first.
Rule: a metric invented for a visual defect must be validated against a case
the human has already rejected (here: the flat crown should have been shown
failing the merlon check) before it can gate anything, and the human's eye on
the actual image remains the acceptance test for appearance — show the
candidate to the human for approval before shipping; a green gate is never
that approval.
Evidence: `tasks/T-0032.md` DoD item 1 (the profile that caught the first
regen but blessed the second); L-037 for the converse; reverted sprite in
`art/manifest.json` `tower-arrow-idle-south`.

## L-039 — 2026-11-06 - A mark on a 3/4-projected face must follow that face's projection
Situation: T-0034 tried to fix the roofed tower's flat body by post-passing
masonry detail onto the existing sprite: horizontal course joints and short
vertical seams in locked palette tones, silhouette untouched, 73 px changed.
Every measured check passed (0 boundary pixels changed, 8 tones, 0
off-palette, mask and fill identical), and the human still rejected both
passes: the straight horizontal course lines read as ruled lines laid over
the sprite, not as masonry courses, because the tower's faces are in 3/4
perspective - and on the shaded right face the same straight lines were
applied to a second plane with a different direction.
Worked: nothing; the rejection was purely visual and mechanical checks could
not have caught it.
Failed: treating an appearance-only edit as verified by per-pixel invariants
(palette, boundary, layout); those checks measure what did not change, not
whether the change is drawn correctly on a projected surface.
Rule: on a 3/4 or isometric sprite, any mark intended to follow a surface
must follow that surface's projection - courses converge or step per face,
and a mark carried around a corner changes direction with the plane; a
straight horizontal rule is only correct on a face drawn head-on. Per-pixel
checks cannot catch this class of defect, so a face-detail edit needs the
human's eye on the image before it ships (per L-038; second case today).
Evidence: tasks/T-0034.md (status: rejected); human rejection of both
passes: "It added straight lines to the faces of the tower that are in
perspective. It is wrong."; art/manifest.json tower-arrow-idle-south entry.

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
