# State

Only `studio-lead` writes this file. Every other agent reads it.

Last updated: 2026-11-05

## Milestone

**G1 — Bootstrap. Signed 2026-11-05.** No gate has failed. Next: **G2 — Vertical
slice**, not started. Session paused at the human's request; G2 planning has not
begun.

## Gate status

| Gate | Result | Signed by | Date |
| --- | --- | --- | --- |
| G0 Concept | pass — 14/14 script sub-checks, 5 human criteria signed | Guybrush Threepwood | 2026-11-04 |
| G1 Bootstrap | pass — 11 script criteria, 2 human criteria signed; evidence at `889d7dc` | Guybrush Threepwood | 2026-11-05 |
| G2 Vertical slice | not started | — | — |
| G3 Alpha | not started | — | — |
| G4 Beta | not started | — | — |
| G5 Gold | not started | — | — |

## What exists

- **Charter**, signed: pitch, audience, three ranked pillars (1 beats 2 beats 3),
  non-goals, core loop plus run structure, fun hypothesis with a test protocol,
  scope budget scoped to the G2 slice, codename `brackenward`.
- **Style lock**, signed: isometric 3/4 sprites on a square 32×32 grid, 16-hex
  palette, approved anchor at `art/style/anchor.png`.
- **Audio guide**, signed: 4 music tracks (menu, level, map, boss), 48 one-shots,
  loudness targets, loop policy, 52-call G2 ceiling.
- **ADRs**: 0001 engine version policy (accepted), 0002 G2 slice is one complete run
  (accepted), 0003 no calendar budget (accepted).
- **Gate evidence**: `docs/gates/G0-result.md`.
- **Repository**: `https://github.com/Guibrush/brackenward` — public, `main` and
  `dev` exist, default branch `dev`, 92 files in the initial commit `ee2efb4`.
- **CI**: `.github/workflows/gates.yml` runs on `dev`, `main`, and PRs to `dev`; the
  `gates` check is registered and green on both branches.
- **Studio core**: 8 agents, 5 commands, permission baseline, memory protocol.
- **Full roster**: the 10 specialists exist as project agents in
  `.opencode/agents/` (art/pixel, art/director, audio/sfx, audio/music,
  design/level, design/narrative, design/systems, eng/gameplay, eng/systems,
  eng/tools), alongside the global roster (studio-lead, gatekeeper, archivist,
  qa/critic, qa/reviewer, leads/*).
- **Empty Godot project**: `project.godot` exists (config_version=5, name
  `brackenward`, no main scene, no autoloads). `import.ps1` passes 2/2
  deterministically.
- **Generation pipelines**: `scripts/audio/*` and `scripts/art/build_frames.gd`
  verified against fixtures. **One real asset has now been through each pipeline
  (G2 Wave 1), and neither passed cleanly** — see blockers.
- **Main scene**: `scenes/main.tscn` with a lane, an HQ and walkers. Headless-clean,
  leaks cost exactly one point, despawn watchdog verified by planted failure.
- **Gates that can fail**: `smoke.ps1` (four assertions: exit 0, no error lines,
  `stuck == 0`, ≥298 s of 300) and `tests.ps1` (runs real cases, names failures, treats
  a parse error as failure). Both demonstrated failing on purpose.
- **N/A counted**: every gate summary prints `pass / fail / blocked / n/a`.
- **Failure demonstrations are copy-based**: `prove-failure.ps1` mutates a throwaway
  copy and deletes it in `finally`; `mutation.ps1` fails the suite if
  `.mutation-active` exists; `restore.ps1` restores from a recorded backup and
  re-verifies SHA-256. In-place mutation is now structurally avoidable.
- **Full G2 run**: 13 scripts, 0 fail, 0 blocked (the earlier 1-blocked run was
  `G1 repo` while CI was still settling on the merge commit; `repo.ps1` is 5/5 now).
- **Spend to date**: 12 PixelLab generations of 40 used (28 free remain), credits
  untouched at $10. ElevenLabs: 3 SFX passes and 1 music pass consumed.

## What does not exist yet

- **The game itself**: no towers, waves, map graph, between-level choices, or run loop.
  Only the scene and the gates that will check them.
- **Batch art and batch audio**: both remain blocked on their probes.

## Metrics

| Metric | Baseline | Target | How it is counted |
| --- | --- | --- | --- |
| Dispatch cap-hit rate | **~90%** — every builder dispatch since the change hit 40 steps (2026-11-08) | **under 10%** | envelopes whose final line is a step-cap notice |
| Usable-delivery rate under a cap hit | **100%** — every one of those returns still produced verified work | keep at 100% | a cap-hit envelope whose files parse and whose evidence is present |

The reserve rule works and the cap did not. Since 2026-11-06 almost every builder dispatch
has still reached 40 steps, so by the standing rule **the briefs are still too big** — the
change converted waste into usable partials, it did not stop the ceiling being hit. The next
step is not a higher cap but smaller briefs: the ones that completed cleanly were the single
-file, single-demonstration ones.

## Blockers
| Blocker | Waiting on |
| --- | --- |
| Batch music | ADR-0005 accepted **and** implemented (loop-seam measurement) |
| G1 repo in a full run | only when CI is mid-run on the merge commit; `repo.ps1` is 5/5 once settled |

**G2.3 is green on an idle machine and was never broken.** Both failures came from a game
(World of Warcraft, 78% GPU utilisation) running alongside the benchmark: 77–82 fps while it
ran, 687–693 fps with it closed. Screen and GPU pinning changed nothing, and the earlier
attribution to Parsec was wrong — no Parsec process was running on either occasion. The
physical monitor does run at 59.98 Hz.

**Full G2 run on 2026-11-08: 13 scripts, 0 fail, 0 blocked, 0 error.** Every scripted
criterion passes; the human criteria (G2.2 playable run, G2.6 art reads as one game, G2.8
audio in the busiest moment, G2.11 fun hypothesis) are untouched by scripted progress.

**Batch art is unblocked.** `art/director` accepted
`assets/art/towers/arrow/idle/south.png` as the quality bar (36×57, 10 tones, zero
off-palette, fill rule met) with two rules for the batch: fill enclosed alpha holes,
and keep the 1px ink on the whole outer silhouette including recesses.

## Known divergences

- ADR-0003 rewords G0.10, but `docs/gates/G0-concept.md` still says "stated calendar
  budget". G0 was signed on the ADR's reading, and a note under the criterion records
  it.

## Next action

Three human decisions unblock G2: own `scripts/perf/**` and permit `eng/tools` to
write it; decide the loudness target for sub-second SFX; decide whether the asset gate
scans placeholders. Once the first is done, T-0014 re-dispatches immediately — its
method, flags and load curve are already verified. Batch art and batch audio stay
stopped until their blockers clear.
