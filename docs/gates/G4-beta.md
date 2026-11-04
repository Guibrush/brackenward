# G4 — Beta

Status: **not started** · Signed: no
Owner of signature: human

## Purpose

Content complete. From here, only fixes and polish — no new features, no new
systems, no new content categories. Tightened at G3.

## Criteria

| ID | Criterion | Type | Evidence |
| --- | --- | --- | --- |
| G4.1 | All planned content is present and reachable | `human` | Walk the content checklist from G3.3 |
| G4.2 | Balance pass completed from recorded play sessions, with changes documented | `human` | Read the balance notes and the diff of tuning values |
| G4.3 | Accessibility minimum: input remapping, readable contrast, no colour-only signalling, subtitle or caption support where voice exists | `human` | Attempt each in-game; list what is missing |
| G4.4 | All player-facing strings are externalised and no hardcoded text ships | `script` | `powershell -NoProfile -File scripts/gate/strings.ps1` exits 0 |
| G4.5 | A thirty-minute headless session completes without a crash | `script` | `powershell -NoProfile -File scripts/gate/smoke.ps1 --duration 1800` exits 0 |
| G4.6 | Thirty minutes of your own play completes without a blocker | `human` | Play it. Note anything that stopped you, in one line each |
| G4.7 | No open P0 or P1 issues | `human` | `docs/STATE.md` |
| G4.8 | Every asset in both manifests is final, none marked placeholder | `script` | `assets.ps1 --placeholders-forbidden`, `audio.ps1` |
| G4.9 | G0–G3 criteria still hold | `script` | `all.ps1` |

## Signature

| Field | Value |
| --- | --- |
| Signed by | — |
| Date | — |
| Commit | — |
| Open P2 issues | — |
