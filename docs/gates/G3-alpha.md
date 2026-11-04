# G3 — Alpha

Status: **not started** · Signed: no
Owner of signature: human

## Purpose

All systems present, wired together, and reachable from normal play. Content is
incomplete and ugly in places; that is expected. What is not acceptable is a
system that exists in code but cannot be reached in the game.

Tightened at G2: this file is reviewed when G2 is signed.

## Criteria

| ID | Criterion | Type | Evidence |
| --- | --- | --- | --- |
| G3.1 | Every system named in the charter exists, is reachable from play, and is listed in `docs/STATE.md` with its owner | `human` | Walk the list; open each system in-game |
| G3.2 | Save and load round-trip correctly, including after quitting the process | `script` | `powershell -NoProfile -File scripts/gate/save.ps1` exits 0 |
| G3.3 | A content-complete plan exists, naming every asset still to be produced with its budget | `human` | Read the plan; confirm the asset list matches the design |
| G3.4 | Performance holds at the declared budget with the full scene population, not a test scene | `script` | `perf.ps1 --scene full` within budget |
| G3.5 | No P1 issue open for more than seven days | `human` | `docs/STATE.md` plus the issue list |
| G3.6 | Every major technical decision has an ADR in `docs/adr/` | `human` | Check that the decisions you remember making are recorded |
| G3.7 | Audio and art coverage is planned for all remaining content, with budgets | `human` | Read `art/manifest.json` and `audio/manifest.json` for planned entries |
| G3.8 | G0–G2 criteria still hold | `script` | `all.ps1` |

## Signature

| Field | Value |
| --- | --- |
| Signed by | — |
| Date | — |
| Commit | — |
| Systems complete | — of — |
