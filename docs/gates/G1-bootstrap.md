# G1 — Bootstrap

Status: **blocked on G0** · Signed: no
Owner of signature: human

## Purpose

Prove the whole machine works with nothing at stake: a repository with enforced
protection, CI that reproduces local gates, a pinned engine, and one complete
agent branch → pull request → green CI → merge into `dev` cycle.

If the loop does not work with an empty commit, it will not work with 4 000 lines
of game code. This gate exists to discover that cheaply.

## Criteria

| ID | Criterion | Type | Evidence |
| --- | --- | --- | --- |
| G1.1 | Public repository exists with both `main` and `dev`, named from the G0 codename | `script` | `scripts/git/init-repo.ps1` creates it; `powershell -NoProfile -File scripts/gate/repo.ps1` then verifies branches and protection independently and exits 0 |
| G1.2 | `main` protection: PR required, one approval, status checks required, no force push, no deletion | `script` | `repo.ps1` reads branch protection via `gh api` |
| G1.3 | `dev` protection: PR required, zero approvals, status checks required, no direct push, no force push | `script` | `repo.ps1` |
| G1.4 | CI workflow exists and the latest run on `dev` is green | `script` | `repo.ps1` via `gh run list` |
| G1.5 | The latest stable Godot release is installed, and the version in use is recorded | `script` | `powershell -NoProfile -File scripts/gate/engine.ps1` queries the release API, compares it with the local `--version`, and exits 0 only on a match |
| G1.6 | An empty project imports headlessly with zero script errors | `script` | `powershell -NoProfile -File scripts/gate/import.ps1` exits 0 — it runs `--import` **and** `--check-only` per script, because `--import` alone exits 0 on a parse error |
| G1.7 | The code and asset gates produce the same result locally and in CI on the same commit | `script` | `powershell -NoProfile -File scripts/gate/all.ps1 -Gate G1` matches the CI conclusion. `repo.ps1` is excluded: reading branch protection needs admin scope that a workflow token does not have, so G1.2/G1.3 are verified locally |
| G1.8 | The integration loop is proven: a task branch was pushed, a PR raised against `dev`, CI passed, and the PR was squash-merged | `human` | Look at the merged PR. Confirm it targeted `dev`, CI was green before merge, and the branch is deleted |
| G1.9 | No key-shaped strings in tracked files | `script` | `powershell -NoProfile -File scripts/gate/secrets.ps1` exits 0 |
| G1.10 | `.gitignore` covers engine cache, builds, and env files | `script` | `secrets.ps1` asserts the required patterns |
| G1.11 | The repository's README and docs describe the real process, not an aspirational one | `human` | Read it and check every claim is true today |

## Note on G1.5

This criterion fails whenever Godot publishes a new stable release, regardless of
the work in progress. That is intended — see `docs/adr/0001-engine-version-policy.md`.
The remedy is to upgrade the engine, never to weaken the check.

## The one criterion that matters

**G1.8.** Everything else can be configured; this is the only one that proves the
configuration does what we think. Do not sign G1 on a locally-created repo with
protection assumed rather than verified.

## Failure modes this gate is designed to catch

- Branch protection not actually available on the account tier, discovered at G1
  instead of after the first bad force-push.
- CI that passes locally and fails on a clean machine, usually a missing
  dependency or an absolute path.
- Agents able to push directly to `dev`, which makes review optional.
- A `.gitignore` that leaks `.env` into a public repository.

## Signature

| Field | Value |
| --- | --- |
| Signed by | — |
| Date | — |
| Commit | — |
| Repository URL | — |
| Godot version | — |
