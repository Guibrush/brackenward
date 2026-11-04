# Lessons

Rules derived from real events. Maintained by `archivist`, read by everyone.
Keep this file near 100 lines; archive the oldest entries to
`docs/lessons/archive-<milestone>.md`.
Entries L-001 … L-008 (2026-11-02 → 2026-11-03) live in
`docs/lessons/archive-G0.md`; their rules remain in force.

## L-009 — 2026-11-04 — A subagent's prose claim is not evidence
Situation: an `art/pixel` dispatch returned "Task 1 done, palette synced" in its
envelope. A re-read of `art/manifest.json` showed the palette unchanged and moss
still present — the claim was false.
Worked: re-reading the artifact the claim was about, not the message.
Failed: treating a confident natural-language report as if it were a result.
Rule: verify every subagent self-report against the artifact it describes (file
contents, manifest, command output) before accepting it; prose is never evidence.
Evidence: `art/manifest.json` unchanged despite "palette synced" in the envelope.

## L-010 — 2026-11-04 — PixelLab ignores palettes and its `view` flag does not steer projection
Situation: generation was asked for palette-locked, `low top-down` map objects.
Four samples across six generations showed the palette ignored and every
"top-down" request returning isometric output regardless of `view`.
Worked: generating cheap samples and inspecting them before committing the
pipeline to the tool.
Failed: assuming prompt parameters describe what the tool actually returns.
Rule: never spend a budget on prompt instructions for palette conformance or
projection — apply both as post-processing or via a dedicated pipeline, and
probe the tool's real output with samples before planning around its parameters.
Evidence: four sample images from six `create_map_object` generations, all
isometric with off-palette colours.

## L-011 — 2026-11-04 — Price the generation rate before adopting a model
Situation: the pro model honoured the palette and gave grid-aligned footprints,
the best quality of any option, but it produced flat front elevations and
consumed 5 generations per asset. At that rate the 31-generation G2 balance
would cost roughly 195 generations against a ≤60 budget.
Worked: computing generations-per-asset × asset count against the charter budget
instead of judging samples on quality alone.
Failed: treating quality and projection as the only decision inputs.
Rule: before adopting a generation model, multiply its measured generations per
asset by the asset count and compare against the budget; reject on cost even
when quality is right.
Evidence: 5 generations/asset measured; ~195 vs ≤60 (`docs/CHARTER.md` Scope
budget row "Generation budget at G2").

## L-012 — 2026-11-04 — Step caps silently truncate dispatched generation work
Situation: two `art/pixel` dispatches ended mid-task at "Maximum steps reached",
each with partial results; one left 11 scratch scripts in the project tree.
Worked: reading the end of each envelope for the truncation marker and cleaning
the tree afterwards.
Failed: assuming a dispatch either completes its brief or fails loudly.
Rule: brief generation work as one asset per dispatch, state cleanup of scratch
files as an explicit step in every brief, and check each return for step-cap
truncation before scheduling the next.
Evidence: two envelopes ending "Maximum steps reached"; 11 scratch scripts
removed from the project tree.

## L-013 — 2026-11-04 — Run the gate script while authoring the document it checks
Situation: `style.ps1` at gate time failed on a missing `Character canvas` row
and a palette row with no hexes — gaps in the freshly written style guide, not
in the script.
Worked: fixing the guide to the script's schema; the script was correct.
Failed: writing the document first and discovering the gate's expectations only
when the gate ran.
Rule: while drafting a gate-checked document, run its gate script against the
draft; fix the document to the gate, never the gate to the document.
Evidence: `style.ps1` failures on `Character canvas` row and empty palette row,
resolved by editing `art/STYLE.md`.

## L-014 — 2026-11-04 — Scribing into unowned paths is allowed only if disclosed
Situation: studio-lead wrote CHARTER.md, AUDIO.md, art/STYLE.md,
art/manifest.json and OWNERSHIP.md at the human's dictation, outside its stated
writable paths. Every word was human-directed, but the exception was recorded
nowhere and surfaced only in the retro.
Worked: the retro caught it; ownership was never actually violated by content.
Failed: silently absorbing an ownership exception into normal practice.
Rule: an agent may scribe human-dictated content into a path it does not own
only when the human dictates the substance, and the exception must be disclosed
in the return envelope and in `docs/OWNERSHIP.md` (as a noted exception, not a
reassignment); an undisclosed write is an ownership violation.
Evidence: G0 retro candidate 6; the five files absent from studio-lead's
writable paths in `docs/OWNERSHIP.md`.
