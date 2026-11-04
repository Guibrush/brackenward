# G2 — Vertical slice

Status: **not started** · Signed: no
Owner of signature: human

## Purpose

Answer the only question that matters at this stage: is the core loop worth
building a game around, at production quality and production framerate?

A vertical slice is one complete vertical of the game — every discipline
represented, nothing cut for convenience.

## Criteria

| ID | Criterion | Type | Evidence |
| --- | --- | --- | --- |
| G2.1 | One scene runs the full loop for five minutes without a crash or a soft-lock | `script` | `powershell -NoProfile -File scripts/gate/smoke.ps1` runs the scene headless for 300 s, exit 0 and no error lines |
| G2.2 | The same scene is genuinely playable by a human for five minutes | `human` | Play it. Note anything that felt broken, in one line each |
| G2.3 | 60 fps average on the target machine at the declared resolution, 1 % low no worse than 45 fps | `script` | `powershell -NoProfile -File scripts/gate/perf.ps1` within budget |
| G2.4 | Every declared character has every declared direction and action; every asset has a manifest entry and every entry a file | `script` | `powershell -NoProfile -File scripts/gate/assets.ps1` exits 0 |
| G2.5 | Asset palette conforms to `art/STYLE.md`; no unregistered colours in shipped sprites | `script` | `assets.ps1` palette check |
| G2.6 | The art reads as one game, not a collection of assets | `taste` | `art/director` findings plus your own eyes |
| G2.7 | Every audio asset passes format, loudness, peak, and loop-seam checks | `script` | `powershell -NoProfile -File scripts/gate/audio.ps1` exits 0 |
| G2.8 | Music sits under effects and nothing clips in the busiest moment | `human` | Play the busiest thirty seconds and listen |
| G2.9 | The test suite is green | `script` | `powershell -NoProfile -File scripts/gate/tests.ps1` exits 0 |
| G2.10 | No open P0 issues | `human` | `docs/STATE.md` blocker list is empty |
| G2.11 | The fun hypothesis was tested and the result recorded, whichever way it went | `human` | Read the ADR or report that records the test and its outcome |
| G2.12 | G0 and G1 criteria still hold after the work | `script` | `powershell -NoProfile -File scripts/gate/all.ps1` |

## What is deliberately not required

No menus, no save system, no options screen, no localisation, no controller
support beyond what the loop needs. Those are G3.

## The honest failure mode

A slice that is fun but runs at 35 fps has failed G2.9/G2.3, not "mostly passed".
Performance discovered at G3 costs a rewrite of the systems that caused it.

## Signature

| Field | Value |
| --- | --- |
| Signed by | — |
| Date | — |
| Commit | — |
| Fun hypothesis outcome | confirmed / refuted / inconclusive |
| Perf measured | — fps average / — fps 1 % low |
