# Lessons archive — through G1 (entries L-009 … L-012)

Moved from `docs/LESSONS.md` on 2026-11-05 after the G1 retro to keep the main
file near 100 lines. Rules remain in force; consult this file when an old rule
may apply.

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

## L-012 — 2026-11-04 — Step caps silently truncate dispatched work
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
