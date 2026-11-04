# G1 — Bootstrap — Gate Result (RE-RUN)

Date: 2026-11-05
Commit: `562572f12551e03b1dd242ce077c3b3ff66de1af` (`562572f`)
Branch: `dev`
Repository: `https://github.com/Guibrush/brackenward`
Run by: gatekeeper (subagent)
Signed: **no** — awaiting human signature

---

## Why this is a re-run (must be stated plainly)

The first G1 recording passed **G1.9** on a scanner that scanned nothing.
`scripts/gate/secrets.ps1` listed tracked files as strings and then called
`.Extension` / `.FullName` on them, throwing per file and swallowing the error,
so it counted 94 files and regex-tested none. That was proven by planting
`AKIA-EXAMPLE-NOT-A-KEY` in a tracked file: the gate still passed.

This is **false evidence**, not a report. The earlier G1 pass was invalid and
must not be relied upon.

Fixed in **PR #3**, merged as **`562572f`**. The corrected scanner reports
`54 files scanned, 20 skipped by extension`, and the same planted-key test now
yields `[FAIL] AWS access key in .secret-probe.txt`, exit 1.

The G1.9 evidence in this run rests on a check that **has been observed
failing** — the corrected scanner was verified to reject a planted key before
it was accepted as a passing check. This is the difference between evidence and
a report, and it is the reason the gate was not signed on the first pass.

---

## Automated criteria

| ID | Criterion | Type | Command | Exit Code | Result | Verbatim Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| G1.1 | Public repository exists with both `main` and `dev` | `script` | `powershell -NoProfile -File scripts/gate/repo.ps1` | 0 | pass | `[PASS ] G1.1 Repository exists and is reachable - Guibrush/brackenward` |
| G1.1.b | `dev` branch exists | `script` | `powershell -NoProfile -File scripts/gate/repo.ps1` | 0 | pass | `[PASS ] G1.1.b dev branch exists - dev` |
| G1.2 | `main` protection: PR required, one approval, status checks required, no force push, no deletion | `script` | `powershell -NoProfile -File scripts/gate/repo.ps1` | 0 | pass | `[PASS ] G1.2 main is protected - PR, checks, no force push, no delete` |
| G1.3 | `dev` protection: PR required, zero approvals, status checks required, no direct push, no force push | `script` | `powershell -NoProfile -File scripts/gate/repo.ps1` | 0 | pass | `[PASS ] G1.3 dev is protected - PR, checks, no force push, no delete` |
| G1.4 | CI workflow exists and latest run on `dev` is green | `script` | `powershell -NoProfile -File scripts/gate/repo.ps1` | 0 | pass | `[PASS ] G1.4 CI is green on dev - gates @ 562572f` |
| G1.5 | Latest stable Godot release installed and version recorded | `script` | `powershell -NoProfile -File scripts/gate/engine.ps1` | 0 | pass | `[PASS ] G1.5 Latest stable release installed - 4.7.2 matches 4.7.2` |
| G1.6 | Empty project imports headlessly with zero script errors | `script` | `powershell -NoProfile -File scripts/gate/import.ps1` | 0 | pass | `[PASS ] G1.6 Asset import succeeds` |
| G1.6.s | Script syntax check (supplementary to G1.6) | `script` | `powershell -NoProfile -File scripts/gate/import.ps1` | 0 | pass | `[PASS ] G1.6.s Script syntax check - 1 scripts parsed` |
| G1.7 | Local and CI gates produce same result on same commit | `script` | `powershell -NoProfile -File scripts/gate/all.ps1 -Gate G1` | 0 | pass | `Summary: 7 scripts, 0 fail, 0 blocked, 0 error` (CI for `562572f` also concluded success) |
| G1.9 | No key-shaped strings in tracked files | `script` | `powershell -NoProfile -File scripts/gate/secrets.ps1` | 0 | pass | `[PASS ] G1.9 No key-shaped strings in tracked files - 54 files scanned, 20 skipped by extension` |
| G1.10 | `.gitignore` covers engine cache, builds, and env files | `script` | `powershell -NoProfile -File scripts/gate/secrets.ps1` | 0 | pass | `[PASS ] G1.10 .gitignore covers engine cache, builds, and env files` |

### G1.9 verification note (corrected scanner)

The scanner's list of tracked files is now supplied directly by the scanner's
primary mechanism. The fallback-to-`Get-ChildItem` path is **no longer what
supplies the list**. The scanned/skipped counts are recorded verbatim:

> `54 files scanned, 20 skipped by extension`

The check has been observed failing against a planted key
(`[FAIL] AWS access key in .secret-probe.txt`, exit 1) — it is no longer
trusting a silent pass to mean "clean". The evidence here rests on that
verified failure behavior.

---

## Human criteria — UNSIGNED

| ID | Criterion | Type | Status | Verbatim Quote / Notes |
| --- | --- | --- | --- | --- |
| G1.8 | The integration loop is proven: a task branch was pushed, a PR raised against `dev`, CI passed, and the PR was squash-merged | `human` | **UNSIGNED** | Quote: *"Look at the merged PR. Confirm it targeted `dev`, CI was green before merge, and the branch is deleted."* Verifiable facts: PR #1 was merged, its branch was deleted, and the `gates` check was green before merge. PRs #2 and #3 followed the same path. Human must still sign off. |
| G1.11 | The repository's README and docs describe the real process, not an aspirational one | `human` | **UNSIGNED** | Quote: *"Read it and check every claim is true today."* Human must read `README.md` on `dev` and confirm every claim matches the actual current state of the repository. Human must sign off. |

---

## Signature

| Field | Value |
| --- | --- |
| Signed by | — (human required) |
| Date | — |
| Commit | `562572f12551e03b1dd242ce077c3b3ff66de1af` |
| Repository URL | `https://github.com/Guibrush/brackenward` |
| Godot version | `4.7.2-stable` (local: `4.7.2.stable.official.ed1daf0bf`) |
