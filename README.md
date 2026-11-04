# brackenward

A run-based tower defence roguelike in Godot 4. One human signs the gates; a roster
of scoped agents does the work.

**Status:** G1 — bootstrap. G0 signed 2026-11-04. The repository is public, CI is
green on `dev`, branch protection is enforced on `main` and `dev`, and Godot 4.7.2
is pinned. The game itself does not exist yet: G2 is the vertical slice.

| | |
| --- | --- |
| Repository | https://github.com/Guibrush/brackenward |
| Integration branch | `dev` — pull requests target it; work branches are `task/T-NNNN-<slug>` |
| Release branch | `main` — protected, one approval required, never pushed directly |
| Engine | Godot 4.7.2, pinned; see `docs/adr/0001-engine-version-policy.md` |

The local working folder is still named `godot-pilot` while the repository is
`brackenward`. That mismatch is intentional and harmless; the folder is not the
identity.

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
| G2 | Vertical slice: one complete run (ADR-0002), one style, 60 fps |
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
