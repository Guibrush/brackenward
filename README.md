# Godot pilot

An AI studio building a 2D pixel-art game in Godot 4 (latest stable, currently
4.7.2). One human signs the gates; a roster of scoped agents does the work.

**Status:** G0 — concept. The charter is a template and the game has no name yet.
The folder name is provisional and is renamed at G1 when the codename exists.

## Start here

| Document | Purpose |
| --- | --- |
| `docs/CHARTER.md` | Pillars, non-goals, scope budget. Binding on every agent. |
| `docs/STATE.md` | Current milestone, gate results, blockers |
| `docs/LESSONS.md` | Rules learned the hard way. Cite them; do not repeat the mistakes |
| `docs/OWNERSHIP.md` | Which agent owns which path |
| `docs/MODELS.md` | Which model runs each role, and how to swap |
| `docs/GIT.md` | Branch model, PR protocol, protection |
| `docs/AUDIO.md`, `art/STYLE.md` | Production rules for sound and pixels |
| `docs/gates/` | Gate criteria G0–G5 and their results |
| `docs/NIGHTSHIFT.md` | Deferred: unattended operation, and why it waits |

## Gates

| Gate | Meaning |
| --- | --- |
| G0 | Concept signed: charter, style lock, audio guide, three codenames |
| G1 | Bootstrap: repository, protection, CI green, Godot pinned, loop proven |
| G2 | Vertical slice: 5 minutes of playable game, one complete style, 60 fps |
| G3 | Alpha: all systems present |
| G4 | Beta: content complete, balanced, accessible |
| G5 | Gold: reproducible, shippable |

Only the human signs a gate. `gatekeeper` produces evidence; it never grants a
signature.

## Working in the studio

```
/status            report state, tasks, and the next action
/brief <work>      write a reviewable task brief
/review <artifact> independent adversarial review
/gate G2           run a gate and record the evidence
/retro             record lessons and prune the memory file
```

## Tooling verified

PixelLab MCP for sprites and animation, ElevenLabs REST for SFX and music,
ffmpeg 9.0.2 for conversion and loop processing, GitHub CLI for repository work.
