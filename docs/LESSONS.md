# Lessons

Rules derived from real events. Maintained by `archivist`, read by everyone.
Keep this file near 100 lines; archive the oldest entries to
`docs/lessons/archive-<milestone>.md`.
Entries L-001 … L-008 (2026-11-02 → 2026-11-03) live in
`docs/lessons/archive-G0.md`; entries L-009 … L-012 (2026-11-04) live in
`docs/lessons/archive-G1.md`. Their rules remain in force.

## L-013 — 2026-11-04 — Run the gate script while authoring the document it checks
Situation: `style.ps1` at gate time failed on a missing `Character canvas` row
and a palette row with no hexes — gaps in the freshly written style guide, not
in the script.
Worked: fixing the guide to the script's schema; the script was correct.
Failed: writing the document first and discovering the gate's expectations only
when the gate ran.
Rule: while drafting a gate-checked document, run its gate script against the
draft; fix the document to the gate, never the gate to the document.
Evidence: `style.ps1` failures on `Character canvas` row and empty palette row,
resolved by editing `art/STYLE.md`.

## L-014 — 2026-11-04 — Scribing into unowned paths is allowed only if disclosed
Situation: studio-lead wrote CHARTER.md, AUDIO.md, art/STYLE.md,
art/manifest.json and OWNERSHIP.md at the human's dictation, outside its stated
writable paths. Every word was human-directed, but the exception was recorded
nowhere and surfaced only in the retro.
Worked: the retro caught it; ownership was never actually violated by content.
Failed: silently absorbing an ownership exception into normal practice.
Rule: an agent may scribe human-dictated content into a path it does not own
only when the human dictates the substance, and the exception must be disclosed
in the return envelope and in `docs/OWNERSHIP.md` (as a noted exception, not a
reassignment); an undisclosed write is an ownership violation.
Evidence: G0 retro candidate 6; the five files absent from studio-lead's
writable paths in `docs/OWNERSHIP.md`.

## L-015 — 2026-11-05 — PowerShell 5.1 `Set-Content -Encoding utf8` writes a BOM and GitHub rejects it
Situation: `protect.ps1` wrote its JSON payload with `Set-Content -Encoding
utf8`, which in Windows PowerShell 5.1 emits a UTF-8 BOM; `gh api --input`
sends the file byte for byte, so GitHub answered `400 Problems parsing JSON`
for both branches and protection never applied.
Worked: reproducing the byte-identical body against a side-effect-free
endpoint to isolate the fault to the bytes, then writing the body with
`[System.IO.File]::WriteAllText` and `UTF8Encoding($false)`.
Failed: trusting the name "utf8" — it means UTF-8 with BOM on PowerShell 5.1.
Rule: before sending any JSON via `gh api --input`, verify the file starts
with `{` or `[` (no BOM); on PowerShell 5.1 write it with
`UTF8Encoding($false)`. Prefer a fixture check for this over remembering it.
Evidence: `scripts/git/protect.ps1:58-64`; commit `7467f9e` fix message.

## L-016 — 2026-11-05 — A script ending in unconditional `exit 0` makes its caller's guard dead code
Situation: `protect.ps1` ended with an unconditional `exit 0`, so
`init-repo.ps1`'s non-zero-exit guard could never fire and a total protection
failure printed clean output.
Worked: rewriting `protect.ps1` to accumulate failures and exit 1 on any.
Failed: believing "exit code propagation" was automatic; it is only as good as
the leaf script's last statement.
Rule: a leaf script must propagate failure — derive its exit code from an
explicit failure list, never terminate with an unconditional `exit 0`. This is
mechanically checkable by grepping scripts for a bare final `exit 0` after
error paths exist.
Evidence: `scripts/git/protect.ps1` old line 95 vs `scripts/git/init-repo.ps1:141`;
extends L-005 (exit codes as evidence) with a structural cause.

## L-017 — 2026-11-05 — A dispatch can finish mid-delivery: work done, delivery step skipped
Situation: twice in G1. T-0002's agent completed its file but, with `edit`
denied, wrote it through the shell — a path the brief never authorised. T-0004's
agent fixed the bug and proved it, then stopped one command short of `git push`,
leaving the fix local until someone noticed.
Worked: catching both by comparing what the brief required against what the
remote actually contained.
Failed: treating "the task is done" as "the delivery steps are done".
Rule: every brief ends with an explicit delivery checklist (authorised tool,
commit, push, remote verified) and the caller verifies remote state — not the
envelope — before scheduling the next task.
Evidence: T-0002 envelope and unauthorised shell write; T-0004 local commit
missing from origin until pushed.

## L-018 — 2026-11-05 — Merge attempts before checks settle are refused and cost a cycle
Situation: `gh pr merge` was run while the `gates` check was still in progress;
GitHub refused with "base branch policy prohibits the merge". It succeeded
immediately once `mergeStateStatus` was `CLEAN`.
Worked: polling `gh pr view --json mergeStateStatus` and merging only on `CLEAN`.
Failed: treating a pending check as a green one because the PR looked mergeable.
Rule: before any merge, read `mergeStateStatus` and merge only when it is
`CLEAN`; a refused merge is a wasted cycle, not a retry opportunity.
Evidence: refused `gh pr merge` on PR #1; success after `mergeStateStatus: CLEAN`.

## L-019 — 2026-11-05 — A gate script that passes while emitting 93 error blocks trains people to ignore output
Situation: `secrets.ps1` printed 93 identical null-dereference blocks to stderr
(one per scanned file, from `$f.Extension.ToLower()` at line 40) and still
exited 0 with both checks PASS.
Worked: the gate result itself was correct; the noise is cosmetic.
Failed: shipping a gate whose failure-shaped output accompanies success — the
next real failure inside that noise will be missed.
Rule: gate scripts must keep stderr clean; any per-file error that does not
change the verdict must be fixed or suppressed (e.g. guard `$f.Extension` for
null) before the gate is trusted again.
Evidence: `scripts/gate/secrets.ps1:40`; 93 stderr blocks recorded in
`docs/gates/G1-result.md` alongside exit 0.

## L-020 — 2026-11-05 — A 404 from the branch-protection endpoint is ambiguous; diagnose before trusting the hint
Situation: while diagnosing the BOM failure, probing protection against a
nonexistent branch returned `404 Branch not found` regardless of body validity —
indistinguishable from the real fault. Separately, `repo.ps1` labels any
protection-endpoint failure "needs admin or a paid plan", which pointed away
from the truth that protection had never been applied.
Worked: checking branch existence (G1.1.b) before interpreting protection
results.
Failed: a canned hint that asserts a cause for a status code that has several.
Rule: never diagnose from a single endpoint's canned hint — verify the
preconditions (branch exists, repo reachable) before reading the hint, and
phrase hints as observations ("call failed with 404") rather than causes.
Evidence: `404 Branch not found` on a nonexistent branch; `repo.ps1:53` hint
while protection had simply never been applied.
