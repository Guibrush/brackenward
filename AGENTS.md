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

## Dispatch discipline

Builders (`eng/*`, `design/*`, `art/*`) get **40 steps**. Everyone else keeps their own cap; the archivist stays at 20.

**Reserve the last 8 steps** for verification and the envelope. If you reach that reserve
with work unfinished: stop writing, verify what exists, and return `VERDICT: revise`
listing what parses, what is unverified, and what remains. Never be cut off mid-write — a
deliberate partial with an honest report is usable; a truncated one is wasted.

**Split a brief** when it needs more than **two files or more than one demonstration**.
File count alone is the wrong proxy: demonstrations are what consume steps. A brief that
still hits 40 is evidence the brief was too big, and that is recorded rather than repeated.

**Cap-hit rate is a metric**, not a feeling: target under 10%, with the current rate
recorded in `docs/STATE.md` so the next decision on caps has evidence.

## Failure demonstrations

A failure demonstration runs through `scripts/gate/prove-failure.ps1`, which mutates a
throwaway **copy** of the project, verifies the gate resolved the copy as its root, and
deletes the copy in `finally` — including on exception.

In-place mutation is reserved for cases that cannot be copied. It requires
`.mutation-active` written before the first edit, a recorded backup with the original
SHA-256, and a verified `scripts/gate/restore.ps1` before any commit. A sentinel left
behind fails the whole suite, which is deliberate: a mutated tree must never pass a gate
or reach a commit.

Demonstrations are never skipped to save steps. They have found every real gate bug so
far; an undemonstrated failure path is a claim, not evidence (L-021).

## Art tasks

Every file an art task creates is either **registered in `art/manifest.json`** (with
licence, prompt, generator and spend) or **deleted** before the task is marked done. A
task that leaves unregistered images on disk is not finished, even if the gate passes
over them.

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
