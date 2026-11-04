# Ownership

One writer per path. If a task needs a path owned by someone else, the task is
split or the work is serialised. Two agents writing one file is the most
expensive failure mode in this studio, because it produces silent loss rather
than an error.

`studio-lead` checks this table before every dispatch, and verifies the
`FILES TOUCHED` line of every return against it.

## Code and engine

| Path | Owner |
| --- | --- |
| `src/player/**`, `src/gameplay/**` | `eng/gameplay` |
| `src/systems/**`, `src/save/**`, `src/audio/**`, `src/core/**` | `eng/systems` |
| `src/ui/**` | `eng/gameplay` |
| `scenes/**` | `eng/gameplay` |
| `levels/**` | `design/level` |
| `project.godot`, `export_presets.cfg` | `eng/tools` — single writer, always |
| `.gitignore` | `eng/tools` |
| `.github/workflows/**` | `eng/tools` |

## Assets

| Path | Owner |
| --- | --- |
| `assets/art/**` | `art/pixel` |
| `assets/audio/sfx/**` | `audio/sfx` |
| `assets/audio/music/**` | `audio/music` |
| `art/manifest.json`, `art/prompts/**` | `art/pixel` |
| `art/style/**` | `art/pixel` writes candidates; the human promotes one to `art/style/anchor.png` |
| `audio/manifest.json` | `audio/sfx` and `audio/music`, disjoint entries only |

## Process and documentation

| Path | Owner |
| --- | --- |
| `AGENTS.md` | human — project instructions, dispatched from the studio conventions |
| `docs/STATE.md`, `docs/adr/**`, `tasks/**` | `studio-lead` |
| `docs/LESSONS.md`, `docs/lessons/**` | `archivist` |
| `docs/design/systems/**` | `design/systems` |
| `docs/design/levels/**` | `design/level` |
| `docs/design/narrative/**` | `design/narrative` |
| `docs/gates/*-result.md` | `gatekeeper` |
| `docs/gates/G[0-5]*.md` (the definitions) | human |
| `docs/CHARTER.md`, `docs/AUDIO.md`, `art/STYLE.md` | human |
| `docs/{OWNERSHIP,MODELS,GIT,NIGHTSHIFT}.md` | human |
| `README.md` | `studio-lead` |
| `opencode.jsonc`, `.opencode/agents/**` | human — agents must not edit the config that grants them permissions or the prompts that govern other agents |
| `docs/reviews/**` | `qa/critic` |
| `scripts/gate/**`, `scripts/build/**` | `eng/tools` |
| `scripts/audio/**`, `scripts/art/**` | `eng/tools` |
| `scripts/git/**`, `scripts/lib/**` | `eng/tools` |

## Noted exceptions

Writes performed outside an agent's normal ownership, recorded so they are never
mistaken for routine practice (see L-014).

| Date | Agent | Paths | Why |
| --- | --- | --- | --- |
| 2026-11-04 | `studio-lead` | `docs/CHARTER.md`, `docs/AUDIO.md`, `art/STYLE.md`, `art/manifest.json`, this file, `docs/gates/G0-concept.md` signature block | G0 interview: the human dictated every substantive decision and approved each edit; studio-lead acted as scribe. Ownership of these paths is unchanged — the human still owns them, and this row records an exception, not a reassignment. |
| 2026-11-05 | `studio-lead` | `AGENTS.md`, this file, `docs/gates/G1-bootstrap.md` signature block | The human instructed a standing rule ("record a lesson any time something fails") and signed G1 in session; the lead scribed the wording, the ownership row, and the signature block. Substance is the human's. |

## Unassigned paths

A path not listed here has no owner. Do not edit it. Report it to
`studio-lead`, who either assigns it in this table or asks the human to.
