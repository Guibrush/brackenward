# G2 — Vertical slice

Status: **draft — rewritten for ADR-0002, requires human merge** · Signed: no
Owner of signature: human

> **This file was changed at G2 planning to implement ADR-0002.** Gate definitions
> are human-owned. The change is proposed in a pull request and does not take effect
> until the human merges it. Until then the previous gate text governs and no G2 task
> may be marked complete against a criterion in this file that ADR-0002 has replaced.

## Purpose

Answer the only question that matters at this stage: is the core loop worth
building a game around, at production quality and production framerate?

A vertical slice is one complete vertical of the game — every discipline
represented, nothing cut for convenience. Per ADR-0002 it is **one complete run**,
not an excerpt: "*The G2 vertical slice is **one complete run**, start to boss, in
the session length the charter states. It is not a five-minute excerpt.*"

## Criteria

| ID | Criterion | Type | Evidence |
| --- | --- | --- | --- |
| G2.1 | A headless stability run of at least 300 s completes without a crash or an error line | `script` | `powershell -NoProfile -File scripts/gate/smoke.ps1` runs the main scene headless for 300 s, exit 0 and no error lines |
| G2.2 | One complete run is played from first level to boss, by a human, to its end; anything that stopped play is noted in one line each | `human` | Play it. Note anything that felt broken or blocked the run, in one line each |
| G2.3 | 60 fps average on the target machine at the declared resolution, 1 % low no worse than 45 fps | `script` | `powershell -NoProfile -File scripts/gate/perf.ps1` within budget, measured on the **real scene** at signature time — not on `scripts/perf/benchmark.tscn` |
| G2.4 | Every declared character has every declared direction and action; every asset has a manifest entry and every entry a file | `script` | `powershell -NoProfile -File scripts/gate/assets.ps1` exits 0 |
| G2.5 | Asset palette conforms to `art/STYLE.md`; no unregistered colours in shipped sprites | `script` | `assets.ps1` palette check |
| G2.6 | The art reads as one game, not a collection of assets | `taste` | `art/director` findings plus your own eyes |
| G2.7 | Every audio asset passes format, loudness, peak, and loop-seam checks | `script` | `powershell -NoProfile -File scripts/gate/audio.ps1` exits 0 |
| G2.8 | Music sits under effects and nothing clips in the busiest moment | `human` | Play the busiest thirty seconds and listen |
| G2.9 | The test suite is green | `script` | `powershell -NoProfile -File scripts/gate/tests.ps1` exits 0 |
| G2.10 | No open P0 issues | `human` | `docs/STATE.md` blocker list is empty |
| G2.11 | The fun hypothesis was tested and the result recorded, whichever way it went | `human` | Read the ADR or report that records the test and its outcome |
| G2.12 | G0 and G1 criteria still hold after the work | `script` | `powershell -NoProfile -File scripts/gate/all.ps1` |

## Changes from the previous version, and the ADR line each implements

| Change | ADR-0002 decision |
| --- | --- |
| G2.1 is now a **stability** criterion — 300 s headless, no crash, no error line — instead of "the full loop for five minutes" | "*`G2.1` is rewritten at G2 planning time as a **stability** criterion: a headless run of at least 300 s completes without a crash or error line. Its purpose is unchanged — catching engine-level breakage cheaply — and it stays cheap on purpose. It no longer claims to be 'the full loop'.*" |
| G2.2 is now "one complete run, first level to boss, played to its end" instead of "genuinely playable for five minutes" | "*`G2.2` is rewritten at G2 planning time as a **human** criterion: one complete run from first level to boss, played to its end, noting anything that stopped play in one line each.*" |
| G2.3 now says explicitly that the measurement at signature time is taken on the real scene, not the benchmark | "*The G2 vertical slice is **one complete run**…*" — a benchmark scene cannot measure a game that does not exist yet, and G2.3's number must describe the slice |
| Every other criterion is unchanged | "*No other G2 criterion changes as a result of this decision.*" |

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
