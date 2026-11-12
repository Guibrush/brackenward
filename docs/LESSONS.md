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
(2026-11-07 → 2026-11-09) live in `docs/lessons/archive-2026-11-10.md`;
entries L-043 — L-044 (2026-11-10 → 2026-11-12) live in
`docs/lessons/archive-2026-11-12.md`. Their rules remain in force.

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

## L-046 — 2026-11-12 — A generation prompt over the vendor's input limit is refused before queueing, at zero cost but zero progress
Situation: T-0095's first rime `create_image_pro_flash` call was refused by
argument validation because the `description` exceeded 2000 code points; the
job was never queued and 0 generations were charged. The same prompt re-sent
at 1890 characters succeeded and billed 5. No pre-flight length guard existed,
so the failure surfaced only as a round trip.
Worked: re-sending the identical prompt trimmed under the limit recovered
immediately with no credit loss.
Failed: dispatching a budgeted generation call without checking the prompt's
length; a validation refusal is silent progress-free, not a success.
Rule: keep generation prompts under the vendor's input limit (pro-flash:
2000 code points for `description`) and check the length before calling; a
refusal before queueing is free but costs a round trip and must not be
recorded as a completed generation.
Evidence: T-0095 first call: refused >2000 code points, 0 charged; re-sent at
1890 characters: accepted, 5 generations billed.

## L-047 — 2026-11-12 — A style flag is a request, not a result; the outline needs the same post-verification the palette gets
Situation: T-0095's rime call requested `style_options.outline: true` and the
returned sprite had 0/171 silhouette boundary pixels in ink #1b1a26 (0%
outline coverage). Every prior tower under the same flag measured 129/129,
169/172, 172/172 or 293/293. The sprite was otherwise clean (7 tones,
0 off-palette, binary alpha, 0 holes); the missing outline was caught only by
the post-check, before any post-processing.
Worked: the existing post-check measuring ink coverage of the silhouette
boundary caught the gap immediately; the call was not billed a re-run for a
defect that verification would have missed downstream.
Failed: treating `outline: true` as delivered rather than measured.
Rule: after every generation, measure ink coverage of the silhouette boundary
before post-processing and reject at 0 coverage — a style flag is a request,
not a result; the outline must pass the same verification the palette, alpha
and hole checks pass.
Evidence: T-0095 rime output: 0/171 boundary pixels in #1b1a26; prior towers
under `outline: true`: 129/129, 169/172, 172/172, 293/293.
