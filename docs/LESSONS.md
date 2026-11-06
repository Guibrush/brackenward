# Lessons

Rules derived from real events. Maintained by `archivist`, read by everyone.
Keep this file near 100 lines; archive the oldest entries to
`docs/lessons/archive-<milestone>.md`.
Entries L-001 … L-008 (2026-11-02 → 2026-11-03) live in
`docs/lessons/archive-G0.md`; entries L-009 … L-012 (2026-11-04) live in
`docs/lessons/archive-G1.md`; entries L-013 … L-014 (2026-11-04) live in
`docs/lessons/archive-2026-11-04.md`; entries L-015 … L-031 (2026-11-05) live
in `docs/lessons/archive-2026-11-05.md`; entries L-032 … L-033 (2026-11-05)
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

## L-034 — 2026-11-05 — A generated sprite's raw bounding box is meaningless
Situation: two tower candidates measured an identical **48×58** raw bounding
box on a 64×64 canvas, which looked like a tie. After removing the generator's
ground pad they were **30×53** and **38×56**: not a tie at all, and the
smaller one was top-heavy with a wide canopy.
Worked: measuring content with the ground removed before comparing candidates.
Failed: comparing raw bounding boxes, where the grass pad is the widest and
tallest element and therefore dominates every measurement.
Rule: compare generated sprites only after the generator ground is removed;
report the pad-free content box, and never select between candidates on a raw
box. Same family as L-010 (the generator returns what it wants, not what you
asked for).
Evidence: `assets/art/towers/arrow/idle/south-v2-raw.png` (30×53 pad-free),
`south-v3-raw.png` (38×56 pad-free), both 48×58 raw.

## L-035 — 2026-11-05 — A runtime that exits 0 while printing errors defeats an exit-code gate
Situation: the arena scene quits on its run timer with `quit(0)` and reports
failures through `push_error` and a `stuck` counter. With the walker's despawn
handler disabled it produced three `ARENA_STUCK` lines and three `ERROR:` lines
and still exited **0**.
Worked: reading the output, not the status code, separated the broken run
(`stuck: 3`, `despawned: 0`) from the good one (`stuck: 0`, `despawned: 3`).
Failed: assuming a gate that checks `$LASTEXITCODE` can police a runtime whose
normal path is a clean exit.
Rule: a gate wrapping a self-quitting runtime must assert on its output —
specific lines and counted values — as well as its exit code; state in the gate
which lines are failure signals. Distinct from L-016: there the script never
propagated failure, here a healthy exit code coexists with errors.
Evidence: `tasks/T-0026.md` (the required contract); commit `0bd657b` message;
arena run with `_despawn()` disabled, exit 0 with three `ERROR:` lines.
