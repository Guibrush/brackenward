# G5 — Gold

Status: **not started** · Signed: no
Owner of signature: human

## Purpose

Shippable, reproducible, and legally clean. Tightened at G4.

## Criteria

| ID | Criterion | Type | Evidence |
| --- | --- | --- | --- |
| G5.1 | All gates G0–G4 re-run and green on the release commit | `script` | `powershell -NoProfile -File scripts/gate/all.ps1` on a clean clone |
| G5.2 | A build from a clean clone reproduces byte-identical output | `script` | `powershell -NoProfile -File scripts/gate/repro.ps1` compares two builds |
| G5.3 | No open P0 or P1 issues | `human` | `docs/STATE.md` |
| G5.4 | Every third-party asset, model, and library has its licence recorded | `script` | `powershell -NoProfile -File scripts/gate/licenses.ps1` exits 0 |
| G5.5 | No key-shaped strings or credentials in the repository or the build | `script` | `secrets.ps1 --include build/` |
| G5.6 | Store assets complete: capsule, screenshots, description, requirements | `human` | Review the store page draft |
| G5.7 | Release tag created on `main` by the human | `human` | Tag exists, matches the signed commit |
| G5.8 | The version in the build matches the tag | `script` | `repro.ps1` reads the engine version string |
| G5.9 | You would let a stranger play this without apologising for it | `taste` | Your call. This criterion is the real one |

## Signature

| Field | Value |
| --- | --- |
| Signed by | — |
| Date | — |
| Release commit | — |
| Tag | — |
| Build hash | — |
