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
| `docs/ASSETS.md` | human — the manifest schema the gates enforce |
| `README.md` | `studio-lead` |
| `opencode.jsonc`, `.opencode/agents/**` | human — agents must not edit the config that grants them permissions or the prompts that govern other agents |
| `docs/reviews/**` | `qa/critic` |
| `scripts/**` | `eng/tools` — every script is tooling; one owner, no drift when a directory is added |

## Noted exceptions

Writes performed outside an agent's normal ownership, recorded so they are never
mistaken for routine practice (see L-014).

| Date | Agent | Paths | Why |
| --- | --- | --- | --- |
| 2026-11-04 | `studio-lead` | `docs/CHARTER.md`, `docs/AUDIO.md`, `art/STYLE.md`, `art/manifest.json`, this file, `docs/gates/G0-concept.md` signature block | G0 interview: the human dictated every substantive decision and approved each edit; studio-lead acted as scribe. Ownership of these paths is unchanged — the human still owns them, and this row records an exception, not a reassignment. |
| 2026-11-05 | `studio-lead` | `AGENTS.md`, this file, `docs/gates/G1-bootstrap.md` signature block | The human instructed a standing rule ("record a lesson any time something fails") and signed G1 in session; the lead scribed the wording, the ownership row, and the signature block. Substance is the human's. |
| 2026-11-05 | `studio-lead` | `docs/AUDIO.md` loudness table, `.opencode/agents/eng/tools.md` permission line | The human dictated ADR-0004 and its audio-guide change, and confirmed `scripts/perf/**` belongs to `eng/tools` (already covered by the `scripts/**` row); the lead scribed the table and the one explicit permission line that makes T-0014 executable. Substantive decisions are the human's. |
| 2026-11-05 | `studio-lead` | `docs/gates/G2-vertical-slice.md`, `docs/gates/G0-concept.md` note under G0.10 | The human instructed the G2 gate text be rewritten against ADR-0002 (unsigned gate) and left unmerged pending their read, and that the signed G0 gate be annotated rather than rewritten. The human then authorised the merge themselves. |
| 2026-11-06 | `studio-lead` | `AGENTS.md`, `art/STYLE.md` | The human approved a standing rule for failure demonstrations and an art-task file-hygiene rule (both in `AGENTS.md`), and approved the canvas-fill definition (height ≥ 85%, width ≥ one tile) that the lead recommended after the pad-free measurements. Lead scribed the wording. |

## Unassigned paths

A path not listed here has no owner. Do not edit it. Report it to
`studio-lead`, who either assigns it in this table or asks the human to.
