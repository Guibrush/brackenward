# State

Only `studio-lead` writes this file. Every other agent reads it.

Last updated: 2026-11-04

## Milestone

**G0 — Concept. Signed 2026-11-04.** No gate has failed. Next: **G1 — Bootstrap**,
not started.

## Gate status

| Gate | Result | Signed by | Date |
| --- | --- | --- | --- |
| G0 Concept | pass — 14/14 script sub-checks, 5 human criteria signed | Guybrush Threepwood | 2026-11-04 |
| G1 Bootstrap | not started | — | — |
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
- **Studio core**: 8 agents, 4 commands, permission baseline, memory protocol.
- **Full roster**: the 10 specialists exist as project agents in
  `.opencode/agents/` (art/pixel, art/director, audio/sfx, audio/music,
  design/level, design/narrative, design/systems, eng/gameplay, eng/systems,
  eng/tools), alongside the global roster (studio-lead, gatekeeper, archivist,
  qa/critic, qa/reviewer, leads/*).
- **Empty Godot project**: `project.godot` exists (config_version=5, name
  `brackenward`, no main scene, no autoloads). `import.ps1` passes 2/2
  deterministically.
- **Generation pipelines**: `scripts/audio/*` and `scripts/art/build_frames.gd`
  verified against fixtures; the audio gate passes 6/6.
- **Spend to date**: 6 PixelLab generations of the 40-generation trial (31 remain);
  credits untouched at $10. ElevenLabs: 1 SFX and 1 music pass consumed.

## What does not exist yet

- **Branch protection.** Applies to `main` and `dev` (T-0004 fixed a BOM in the
  request body and a script that exited 0 on failure). Verified by `repo.ps1` 5/5.
- **A main scene**, so `--quit` cannot run until G2.
- **G1.8's integration loop** — proven by PR #1: branch `task/T-0004-protect-fix`,
  `gates` green in 31 s, squash-merged into `dev` as `7467f9e`, remote branch
  deleted. Evidence: `gh pr view 1` → `MERGED`.

## Blockers

| Blocker | Waiting on |
| --- | --- |
| No main scene | G2; `--quit` stays unusable until then |
| G1 signature | human: G1.8 (merged PR) and G1.11 (README accuracy) |

Art budget is **not** a blocker: 31 free PixelLab generations remain on top of $10
credit, and the human has confirmed credit is consumed only after the free
generations run out. Scope is not being cut. Unverified: how many generations $10
buys — the credit balance has not moved yet, so the rate is unknown until the first
paid call.

## Known divergences

- ADR-0002 changes the G2 gate text, but `docs/gates/G2-vertical-slice.md` still says
  five minutes. The rewrite happens at G2 planning and is signed there.
- ADR-0003 rewords G0.10, but `docs/gates/G0-concept.md` still says "stated calendar
  budget". G0 was signed on the ADR's reading of it.

## Next action

G1 is ready for signature on `dev @ 562572f`: every script criterion passes, and
G1.9 now rests on a scanner that has been observed failing against a planted key
(PR #3 fixed a false pass that scanned zero files). After signature: G1 retro, then
G2 planning with the leads.
