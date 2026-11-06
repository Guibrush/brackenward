# Lessons

Rules derived from real events. Maintained by `archivist`, read by everyone.
Keep this file near 100 lines; archive the oldest entries to
`docs/lessons/archive-<milestone>.md`.
Entries L-001 … L-008 (2026-11-02 → 2026-11-03) live in
`docs/lessons/archive-G0.md`; entries L-009 … L-012 (2026-11-04) live in
`docs/lessons/archive-G1.md`; entries L-013 … L-014 (2026-11-04) live in
`docs/lessons/archive-2026-11-04.md`; entries L-015 … L-031 (2026-11-05) live
in `docs/lessons/archive-2026-11-05.md`; entries L-032 - L-035 (2026-11-05)
live in `docs/lessons/archive-2026-11-06.md`. Their rules remain in force.

## L-036 — 2026-11-06 — Identity-preserving img2img preserves the defect too
Situation: T-0032 tried to regenerate the arrow tower without the flat-cut
crown by feeding the rejected sprite as the img2img reference. At strength 220
the result was clean (36×57, 10 tones, 0 off-palette, 0 holes) but reproduced
the defect exactly: flat crown, row widths 13, 18, 25, 26, 33, 36, 36, 36. At
strength 105 identity broke instead (jagged 1-px bumps; body and door drifted).
Worked: nothing, for the defect itself — the constraint could not be expressed
through a reference image at any strength.
Failed: treating a structural defect as something a reference-faithful pass
will fix; the reference it is faithful to contains the defect.
Rule: when regenerating to fix a structural defect, express the fix as a
constraint the generator can satisfy (or author it directly in post); do not
expect a reference image to correct itself — high strength copies the flaw,
low strength abandons the identity.
Evidence: `tasks/T-0032.md` (regen brief); `art/manifest.json`
`tower-arrow-idle-south` entry; T-0032 attempt measurements (strength 220:
36×57, widths 13/18/25/26/33/36/36/36; strength 105: identity drift).

## L-037 — 2026-11-06 — A shape defect needs a named measurement, not a similarity check
Situation: the strength-220 regeneration "looked plausible at a glance" and
would have been accepted as the same tower; only the 8-row top-width profile
required by `tasks/T-0032.md` DoD item 1 exposed that it had reproduced the
flat cut. The brief had asked for that profile, which is the only reason the
defect was caught rather than shipped.
Worked: the brief's numeric DoD row-width profile — a check a glance cannot
perform.
Failed: visual similarity as the acceptance test for a shape defect; it cannot
distinguish the defect from the fix.
Rule: when a defect is measurable, the definition of done must name the
measurement that distinguishes the defect from the fix (e.g. the 8-row
top-width profile); a "looks the same" check is never evidence for or against
a shape defect.
Evidence: `tasks/T-0032.md` DoD item 1; current
`assets/art/towers/arrow/idle/south.png` first opaque row is a 12 px bar at
y=7 (verified 2026-11-06) — the flat crown shipped anyway.

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
