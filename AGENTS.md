# Project instructions

This is a Godot 4 pixel-art game project run as an AI studio. The global
`AGENTS.md` defines the studio conventions; this file covers only what is
specific to this project.

## Read before acting

1. `docs/CHARTER.md` — pillars, audience, non-goals, scope budget. Binding.
2. `docs/STATE.md` — current milestone, last gate result, open blockers.
3. `docs/LESSONS.md` — recorded rules. Cite lesson IDs when they apply.
4. `docs/OWNERSHIP.md` — which agent owns which path. Check before editing.

## Record failures immediately

A lesson is written **when the failure happens**, not at the next retro. This is a
standing rule, not a reminder for the human to repeat.

Trigger any one of these and the lesson is recorded before the next task starts:

- a command, script, or dispatch fails unexpectedly;
- a gate or check passes when it should have failed;
- a claim in a return envelope does not match the artifact;
- a process step is skipped, done twice, or done in the wrong order;
- the human has to ask for something the process should already have done.

Dispatch `archivist` with the evidence, not a summary of it. If the incident is too
small to earn a lesson on its own, append it to an existing one rather than dropping
it. The gate retro then becomes a review of lessons already recorded, not the first
time anyone writes them down.

## Dispatch table

The roster is defined by this project's pack. `studio-lead` routes from this table
and nowhere else.

| Work | Owner |
| --- | --- |
| Player mechanics, controls, feel, camera | `eng/gameplay` |
| Engine systems: save/load, input, state, events, audio bus | `eng/systems` |
| Build, import pipeline, editor tooling, profiling | `eng/tools` |
| Rules, economy, progression, tuning tables | `design/systems` |
| Level layout, encounter pacing, spatial flow | `design/level` |
| Story, dialogue, lore, tone, naming | `design/narrative` |
| Sprite, tile, UI, VFX generation | `art/pixel` |
| Art direction, style conformance, visual critique | `art/director` |
| One-shot sound effects | `audio/sfx` |
| Music loops and stingers | `audio/music` |
| Independent adversarial review of any artifact | `qa/critic` |
| Correctness review of specs, docs, and ADRs | `qa/reviewer` |
| Running the milestone gate scripts | `gatekeeper` |
| Keeping STATE, ADRs, and docs coherent | `archivist` |
| Cross-discipline scoping before a milestone | `leads/tech`, `leads/design`, `leads/art` |

## Where things live

| Path | Contents |
| --- | --- |
| `docs/` | Charter, state, decisions, gate definitions and results, lessons |
| `tasks/` | One brief per task, `T-NNNN.md` |
| `art/` | Style guide, prompt library, asset manifest |
| `assets/art/` | Generated sprites, tiles, UI, VFX |
| `assets/audio/sfx/` | One-shot sounds |
| `assets/audio/music/` | Music loops and stingers |
| `src/` | GDScript gameplay and systems code |
| `scenes/` | Godot scenes |
| `levels/` | Level and encounter layouts |
| `scripts/gate/` | Deterministic gate scripts |
| `scripts/audio/`, `scripts/art/` | Deterministic generation and post-processing helpers |

## Engine

Godot, latest stable, installed at `%LOCALAPPDATA%\Programs\Godot\<version>\`. The
version in use is recorded in `docs/STATE.md`, and CI uses that exact version.
Upgrading is routine; holding an old release is a human decision recorded in an ADR.

On Windows, headless commands must use `Godot_*_console.exe` or stdout is empty.
Use `--import` to import assets and `--check-only --script res://path.gd` to check
script syntax. `--import` alone exits 0 even when a script has a parse error, so it
is never sufficient on its own.

## Money

`art/pixel`, `audio/sfx`, and `audio/music` spend real credits. Every brief
that pays for generation states a budget, and every return reports actual spend.
Exceeding the stated budget without approval is a gate failure.

## Never

- Never edit `.env`, credential files, or anything that holds a key.
- Never commit generated binaries that the gate does not expect in the manifest.
- Never change a gate definition to make a gate pass. Gates change by human
  decision and are recorded in an ADR.
- Never rewrite a published commit or force-push.
