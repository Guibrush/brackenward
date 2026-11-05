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
- **G2 Wave 1 probes**: tower sprite accepted by `assets.ps1` (10 tones, zero
  off-palette); UI click regenerated and passing the peak rule at −1.5 dBTP.
- **Perf harness**: `scripts/gate/perf.ps1` measures a rendered windowed scene at
  1920×1080/2× — 651.5 fps at 1000 entities, and 21.7 fps when stressed, both
  observed. G2.3 is a measurement now, not a stub.
- **Audio gate (ADR-0004)**: one-shots gate on true peak, beds on integrated LUFS,
  with LUFS printed as advisory; a check with nothing to check reports N/A.
- **Spend to date**: 10 PixelLab generations of 40 used (30 free remain), credits
  untouched at $10. ElevenLabs: 3 SFX passes and 1 music pass consumed.

## What does not exist yet

- **A main scene**, so `--quit`, `smoke.ps1`, and `tests.ps1` stay blocked until G2.
- **The game itself**: no towers, waves, map graph, or run loop yet.

## Blockers

| Blocker | Waiting on |
| --- | --- |
| Batch art blocked on quality, not mechanics | one more probe to solve canvas fill before 30 sprites inherit a squat silhouette |
| G2.3 is measured on a synthetic scene | the real scene must be measured at its own entity count before the gate is signed |
| G2.9 and G2.1 blocked | a main scene, which is G2 work |

## Known divergences

- ADR-0002 changes the G2 gate text, but `docs/gates/G2-vertical-slice.md` still says
  five minutes. The rewrite happens at G2 planning and is signed there.
- ADR-0003 rewords G0.10, but `docs/gates/G0-concept.md` still says "stated calendar
  budget". G0 was signed on the ADR's reading of it.

## Next action

Three human decisions unblock G2: own `scripts/perf/**` and permit `eng/tools` to
write it; decide the loudness target for sub-second SFX; decide whether the asset gate
scans placeholders. Once the first is done, T-0014 re-dispatches immediately — its
method, flags and load curve are already verified. Batch art and batch audio stay
stopped until their blockers clear.
