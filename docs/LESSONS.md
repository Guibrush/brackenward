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
(2026-11-06) live in `docs/lessons/archive-2026-11-09.md`; entries L-040 — L-042
(2026-11-07 → 2026-11-09) live in `docs/lessons/archive-2026-11-10.md`. Their
rules remain in force.

## L-043 — 2026-11-10 — A windowed demo run is not deterministic on its first launch
Situation: T-0082 changed the build panel's action row (no autowrap, block at
min-width) and captured the acceptance frame with a windowed `--write-movie`
run of `src/ui/tests/inventory_migration_demo.gd`. The first run produced 95
PNGs and `PANEL_BAR_SELF_TEST {"checks":9,"failed":1,"failures":["every group
holds a pick after the clicks: unmet [\"tower\"]"],"movie":true,...,
"status":"fail"}` plus `ERROR: PANEL_BAR_FAILURE`, exit non-zero. The identical
command re-run with a fresh temp dir produced 180 PNGs, `{"checks":187,
"failed":0,...,"movie":true,"status":"pass"}` and exit 0. The `eng/gameplay`
builder had seen the same thing independently: its first windowed run failed at
9 checks with the same opening-choice message, its repeat passed. Headless runs
of the demo were green at 187 every time. The failing check is in the
opening-choice walk (the demo clicks groups and confirms), not in the build
panel; the block does not exist on that screen.
Worked: recognising the signature (9 checks, same unmet ["tower"] message,
movie:true) as one already seen independently by another agent, and re-running
with a fresh temp dir before drawing any conclusion.
Failed: a single windowed run of a modal-dependent demo being treated as
provable evidence in either direction; movie/frame output carried no record of
how many runs it took.
Rule: a windowed demo run that depends on the opening-choice modal is not
deterministic on its first launch — a red first run with exactly this signature
(9 checks, `every group holds a pick ... unmet ["tower"]`, movie:true) must be
re-run before it is reported as a product defect, and movie/frame evidence must
name how many runs it took; never present a single windowed run as the frame's
provenance. Fixing the demo's timing is its own task.
Evidence: T-0082 first windowed run: 95 PNGs, checks:9 failed:1
unmet ["tower"], exit non-zero; identical command re-run: 180 PNGs,
checks:187 failed:0, exit 0; eng/gameplay independent first-run fail at 9
checks, repeat pass; headless runs green at 187 every time.

## L-044 — 2026-11-12 — A second windowed-demo first-run flake signature (drag count drift); generalises L-043
Situation: T-0090 added the bar's controller focus and captured the acceptance
frame with a windowed `--write-movie` run of
`src/ui/tests/inventory_migration_demo.gd`. The first run wrote 253 PNGs,
exited 1 and printed `PANEL_BAR_SELF_TEST {"checks":292,"failed":2,"failures":
["a press alone announces no drag: this could still be a click
(tower_drag_started): expected 0, got 1","the motion past the threshold
announced the drag exactly once (tower_drag_started): expected 1,
got 2"],"movie":true,"status":"fail"}`. The identical command in a fresh temp
dir wrote 253 PNGs, exited 0 and printed `{"checks":293,"failed":0,"failures":
[],"movie":true,"status":"pass"}`. Headless runs of the same demo were 285/285
twice, byte-identical focus lines. This is not the L-043 signature (9 checks,
opening-choice `unmet ["tower"]`); it is drag-announcement count drift in the
same demo under windowed timing.
Worked: the builder applied L-043's spirit without being told — re-ran once in
a fresh temp dir, got green, and did not report a product defect.
Failed: L-043's rule was written to one signature, so a second, different
first-run failure could have been misread as a real defect.
Rule: a windowed demo run has more than one known first-run flake signature
(L-043 opening-choice, L-044 drag count drift) — any windowed-only failure
that does not reproduce headless is timing evidence, not a product defect;
re-run once with a fresh temp dir before diagnosis, and movie evidence must
name the run count. Fixing the demo's wall-clock timing remains its own task.
Supersedes: L-043's signature-specific scope (its rule now holds via this
general rule); L-043 remains as the first evidence record.
Evidence: T-0090 first windowed run: 253 PNGs, checks:292 failed:2 (drag
count drift), exit 1; identical command fresh temp dir: 253 PNGs,
checks:293 failed:0, exit 0; headless 285/285 twice, byte-identical focus
lines.

## L-045 — 2026-11-12 — The style anchor's ground pad leaks into tower generations asked to "fill the frame"
Situation: T-0094 generated the mortar tower with `create_image_pro_flash`,
using `art/style/anchor.png` (native 64x64) as the style reference, the locked
16-colour palette, max_colors 12. The prompt asked for "a broad flat footing
slab ... the footing filling the canvas almost side to side" plus an explicit
"No grass, no ground tile, no plinth". Output was technically clean — 10 tones,
0 off-palette, binary alpha, 0 holes, strong squat silhouette — but carried 466
pixels of leaf #6f8f4a (234) and deep green #3a4a3a (232) in rows 49-63,
columns 2-60, tapering to a point: the anchor's own grass diamond leaked into
the base. The drum and sandbag blocks stand on it, so cropping would mean
repainting the base, i.e. authoring, not post. Rejected; 5 generations spent;
the sibling rime call was not made per the task's stop condition.
Worked: rejecting on the pad-green scan instead of cropping; the approved
ballista prompt ("low stone footing block at the base only", no side-to-side
wording) shows the wording that avoids the leak.
Failed: a "filling the canvas almost side to side" footing prompt reproduced
the anchor pad's isometric shape; the explicit negative prohibition ("no grass,
no ground tile, no plinth") did not override it. The anchor deliberately keeps
its grass pad (manifest note).
Rule: when the style anchor carries a ground pad, a tower prompt must never
ask for a slab/footing that fills the frame — ask for a narrow footing **block**
and no ground; scan every pro-flash tower output for the three pad greens
(#3a4a3a, #6f8f4a, #9ab55c) before any post pass, and reject rather than crop
when the sprite stands on them.
Evidence: art/candidates/tower-mortar-candidate-raw.png (466 pad px, rows
49-63); manifest entry `tower-mortar-candidate-raw`; art/STYLE.md ground-pad
rule; T-0094. Spend reported inconsistently by the dispatcher: brief body says
19→14, evidence line says 21→26 — to be reconciled by studio-lead before the
next generation task.
