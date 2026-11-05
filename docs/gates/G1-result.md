# G1 — Bootstrap — Gate Result (final re-record)

> **Signature:** this gate was signed on 2026-11-05 by Guybrush Threepwood in
> `docs/gates/G1-bootstrap.md`, which holds the canonical signature record. This file is the
> evidence snapshot and is not re-signed. See "Where the signature lives" in
> `docs/gates/README.md`.

Date: 2026-11-05
Commit: `889d7dc27828597fbabe3b450f4abae6dc847dca` (`889d7dc`)
Branch: `dev`
Repository: `https://github.com/Guibrush/brackenward`
Run by: gatekeeper (subagent)
Signed: **no** — awaiting human signature

---

## Why this record exists (L-023)

The previous G1 evidence was captured at `562572f`. Documentation commits
followed (`c095b98`, `889d7dc`, plus the lessons commit), so the evidence
commit and the `dev` head diverged before signature. Lesson L-023 requires
that this never be left for the signer to reconstruct. **Both remedies are
applied here:** the gate was re-run in full at the final commit `889d7dc`,
and the divergence is stated in the Signature state section below.

---

## Commands run, verbatim, with exit codes

| # | Command | Exit code |
| --- | --- | --- |
| 1 | `powershell -NoProfile -File scripts/gate/all.ps1 -Gate G1` | 0 |
| 2 | `powershell -NoProfile -File scripts/gate/repo.ps1` | 0 |
| 3 | `powershell -NoProfile -File scripts/gate/engine.ps1` | 0 |
| 4 | `powershell -NoProfile -File scripts/gate/import.ps1` | 0 |
| 5 | `powershell -NoProfile -File scripts/gate/secrets.ps1` | 0 |

### Verbatim output

**1. `powershell -NoProfile -File scripts/gate/all.ps1 -Gate G1` — exit 0**

```
Running gates G0..G1

  G0 charter      pass
  G0 style        pass
  G0 audio_spec   pass
  G1 engine       pass
  G1 import       pass
  G1 repo         pass
  G1 secrets      pass

Summary: 7 scripts, 0 fail, 0 blocked, 0 error
Signature is still required from the human.
```

**2. `powershell -NoProfile -File scripts/gate/repo.ps1` — exit 0**

```
G1 - repository
  repository: Guibrush/brackenward (PUBLIC)
  [PASS ] G1.1    Repository exists and is reachable - Guibrush/brackenward
  [PASS ] G1.1.b  dev branch exists - dev
  [PASS ] G1.2    main is protected - PR, checks, no force push, no delete
  [PASS ] G1.3    dev is protected - PR, checks, no force push, no delete
  [PASS ] G1.4    CI is green on dev - gates @ 889d7dc

G1 repo: 5 pass, 0 fail, 0 blocked
```

**3. `powershell -NoProfile -File scripts/gate/engine.ps1` — exit 0**

```
G1 - engine version
  engine: C:\Users\guibr\AppData\Local\Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe
  local:  4.7.2.stable.official.ed1daf0bf
  latest: 4.7.2-stable
  [PASS ] G1.5    Latest stable release installed - 4.7.2 matches 4.7.2

G1 engine: 1 pass, 0 fail, 0 blocked
```

**4. `powershell -NoProfile -File scripts/gate/import.ps1` — exit 0**

```
G1 - headless import
  [PASS ] G1.6    Asset import succeeds
  [PASS ] G1.6.s  Script syntax check - 1 scripts parsed

G1 import: 2 pass, 0 fail, 0 blocked
```

**5. `powershell -NoProfile -File scripts/gate/secrets.ps1` — exit 0**

```
G1 - secrets and ignore rules
  [PASS ] G1.9    No key-shaped strings in tracked files - 58 files scanned, 20 skipped by extension
  [PASS ] G1.10   .gitignore covers engine cache, builds, and env files

G1 secrets: 2 pass, 0 fail, 0 blocked
```

---

## Per-ID results

| ID | Criterion | Type | Command | Exit Code | Result | Verbatim Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| G1.1 | Public repository exists with both `main` and `dev` | `script` | `powershell -NoProfile -File scripts/gate/repo.ps1` | 0 | pass | `[PASS ] G1.1    Repository exists and is reachable - Guibrush/brackenward` |
| G1.1.b | `dev` branch exists | `script` | `powershell -NoProfile -File scripts/gate/repo.ps1` | 0 | pass | `[PASS ] G1.1.b  dev branch exists - dev` |
| G1.2 | `main` protection: PR required, one approval, status checks required, no force push, no deletion | `script` | `powershell -NoProfile -File scripts/gate/repo.ps1` | 0 | pass | `[PASS ] G1.2    main is protected - PR, checks, no force push, no delete` |
| G1.3 | `dev` protection: PR required, zero approvals, status checks required, no direct push, no force push | `script` | `powershell -NoProfile -File scripts/gate/repo.ps1` | 0 | pass | `[PASS ] G1.3    dev is protected - PR, checks, no force push, no delete` |
| G1.4 | CI workflow exists and the latest run on `dev` is green | `script` | `powershell -NoProfile -File scripts/gate/repo.ps1` | 0 | pass | `[PASS ] G1.4    CI is green on dev - gates @ 889d7dc` |
| G1.5 | Latest stable Godot release is installed, and the version in use is recorded | `script` | `powershell -NoProfile -File scripts/gate/engine.ps1` | 0 | pass | `[PASS ] G1.5    Latest stable release installed - 4.7.2 matches 4.7.2` |
| G1.6 | Empty project imports headlessly with zero script errors | `script` | `powershell -NoProfile -File scripts/gate/import.ps1` | 0 | pass | `[PASS ] G1.6    Asset import succeeds` |
| G1.6.s | Script syntax check (supplementary to G1.6) | `script` | `powershell -NoProfile -File scripts/gate/import.ps1` | 0 | pass | `[PASS ] G1.6.s  Script syntax check - 1 scripts parsed` |
| G1.7 | Code and asset gates produce the same result locally and in CI on the same commit | `script` | `powershell -NoProfile -File scripts/gate/all.ps1 -Gate G1` | 0 | pass | `Summary: 7 scripts, 0 fail, 0 blocked, 0 error` (CI for `889d7dc` is green — G1.4 above) |
| G1.9 | No key-shaped strings in tracked files | `script` | `powershell -NoProfile -File scripts/gate/secrets.ps1` | 0 | pass | `[PASS ] G1.9    No key-shaped strings in tracked files - 58 files scanned, 20 skipped by extension` |
| G1.10 | `.gitignore` covers engine cache, builds, and env files | `script` | `powershell -NoProfile -File scripts/gate/secrets.ps1` | 0 | pass | `[PASS ] G1.10   .gitignore covers engine cache, builds, and env files` |

The scanned-file count grew from 54 (previous record) to 58 because the
documentation commits added tracked files. That is expected; the scanner
lists tracked files directly.

---

## G1.9 evidence note (L-021)

G1.9's evidence rests on a scanner that **has been observed failing** against
a planted key (`AKIA-EXAMPLE-NOT-A-KEY` in a tracked file produced
`[FAIL] AWS access key in .secret-probe.txt`, exit 1) before its passing
result was accepted. The earlier G1.9 pass was produced by a scanner that
scanned zero files — counted 94 and regex-tested none — and was **false
evidence**, retracted in the previous record. It must not be relied upon.

---

## Signature state

- **Evidence captured at commit:** `889d7dc27828597fbabe3b450f4abae6dc847dca`
  (`889d7dc`), the `dev` head at the time of the run.
- **Divergence since the previous recording** — actual output of
  `git diff --stat 562572f..HEAD`:

```
 AGENTS.md                          |  18 ++++
 docs/LESSONS.md                    | 208 ++++++++++++++++++++++++-------------
 docs/OWNERSHIP.md                  |   2 +
 docs/STATE.md                      |  10 +-
 docs/gates/G1-result.md            |  82 +++++++++++++++
 docs/lessons/archive-2026-11-04.md |  30 ++++++
 docs/lessons/archive-G1.md         |  54 ++++++++++
 tasks/T-0006.md                    |  67 ++++++++++++
 8 files changed, 396 insertions(+), 75 deletions(-)
```

  Every changed file is documentation or process record (`AGENTS.md`,
  `docs/`, `tasks/`). No source code, scenes, assets, or gate scripts
  changed between `562572f` and `889d7dc`.
- **Signature target:** the signature will be applied to the commit
  containing this file. The only delta between the captured commit
  (`889d7dc`) and that commit is **this document**
  (`docs/gates/G1-result.md`). Nothing else changes.
- **Re-run after signature:** the gate was **not** re-run after the
  signature, and it does **not** need to be re-run — no code or gate change
  is involved; the delta between the evidence commit and the signed commit
  is this document only. This is stated explicitly, not implied.

---

## Human criteria — UNSIGNED

| ID | Criterion | Type | Status | Verifiable facts |
| --- | --- | --- | --- | --- |
| G1.8 | "The integration loop is proven: a task branch was pushed, a PR raised against `dev`, CI passed, and the PR was squash-merged" — *"Look at the merged PR. Confirm it targeted `dev`, CI was green before merge, and the branch is deleted."* | `human` | **UNSIGNED** | PR #1 was squash-merged into `dev` with the `gates` check green before merge, and its branch was deleted. PRs #2, #3, #4, and #5 followed the same path: task branch → PR against `dev` → green `gates` → squash-merge → branch deleted. Human sign-off still required. |
| G1.11 | "The repository's README and docs describe the real process, not an aspirational one" — *"Read it and check every claim is true today."* | `human` | **UNSIGNED** | The README on `dev` states the real repository, the real branches, and the G2 scope per ADR-0002. Human must read it and confirm every claim is true today, then sign off. |

---

## Signature

| Field | Value |
| --- | --- |
| Signed by | — (human required; no agent may sign) |
| Date | — |
| Commit | the commit containing this file (delta from `889d7dc` is this document only) |
| Repository URL | `https://github.com/Guibrush/brackenward` |
| Godot version | `4.7.2-stable` (local: `4.7.2.stable.official.ed1daf0bf`) |

Spend: none.

Evidence: pass on all scripted criteria, awaiting human signature. This report
does not sign the gate and does not declare it passed.
