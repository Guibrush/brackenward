# G0 — Concept

Status: **signed 2026-11-04** · Signed: yes
Owner of signature: human

## Purpose

Establish what the game is, what it deliberately is not, and the one claim the
prototype exists to test. Nothing is built before this gate closes: no
repository, no engine install, no generated assets.

## Criteria

| ID | Criterion | Type | Evidence |
| --- | --- | --- | --- |
| G0.1 | Charter is complete: pitch, audience, three pillars, non-goals, core loop, fun hypothesis, scope budget, codename candidates | `script` | `powershell -NoProfile -File scripts/gate/charter.ps1` exits 0 (no `TODO` markers, all required sections present) |
| G0.2 | The three pillars are distinct and each names how the player feels it | `human` | Read the charter; state in one line per pillar why it is not a restatement of another |
| G0.3 | The fun hypothesis could be proven wrong | `human` | Point to the observation that would falsify it |
| G0.4 | Scope budget contains numbers, not intentions | `script` | `charter.ps1` checks the budget table has no empty or placeholder cells |
| G0.5 | Non-goals has at least three entries | `script` | `charter.ps1` counts list items in the non-goals section |
| G0.6 | Style is locked: palette hexes, tile size, outline rule, light direction, projection, max colours | `script` | `powershell -NoProfile -File scripts/gate/style.ps1` exits 0 |
| G0.7 | The locked palette is coherent and the projection suits the intended gameplay | `taste` | Human inspects `art/STYLE.md` and one sample sprite |
| G0.8 | Audio guide is complete: format rules, loudness targets, loop policy, naming, budgets | `script` | `powershell -NoProfile -File scripts/gate/audio_spec.ps1` exits 0 |
| G0.9 | Three codename candidates exist, each valid as a repository name (lowercase, hyphenated, no trademark) | `human` | Read the codename section; reject any name you would not want public |
| G0.10 | The charter's scope is believable for the stated calendar budget | `taste` | Human judgement. This is the criterion most likely to be wrong, and the cheapest place to be wrong |

## Why these are mostly human

G0 is judgement, not measurement. A script can confirm the document is filled in;
only you can decide whether the fun hypothesis is worth a month of work.

## On closing

1. `gatekeeper` runs the three scripts and writes `docs/gates/G0-result.md`.
2. You read the charter once more, then write the signature line yourself.
3. `studio-lead` updates `docs/STATE.md`: G0 signed, codename chosen, next action
   is G1.
4. The chosen codename becomes the repository name and the folder name.

## Signature

| Field | Value |
| --- | --- |
| Signed by | Guybrush Threepwood |
| Date | 2026-11-04 |
| Commit | n/a — no repository exists until G1 |
| Codename chosen | brackenward |
