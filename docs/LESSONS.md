# Lessons

Rules derived from real events. Maintained by `archivist`, read by everyone.
Keep this file near 100 lines; archive the oldest entries to
`docs/lessons/archive-<milestone>.md`.
Entries L-001 … L-008 (2026-11-02 → 2026-11-03) live in
`docs/lessons/archive-G0.md`; entries L-009 … L-012 (2026-11-04) live in
`docs/lessons/archive-G1.md`; entries L-013 … L-014 (2026-11-04) live in
`docs/lessons/archive-2026-11-04.md`. Their rules remain in force.

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

## L-021 — 2026-11-05 — A check that has never been observed failing is not evidence
Situation: `secrets.ps1` passed G1.9 while scanning zero files: it built its
file list as strings, threw on `.Extension`, threw again inside `Get-Content`,
and swallowed both errors — so it counted every tracked file and regex-tested
none. A planted AWS-key-shaped string passed the gate.
Worked: planting `AKIA-EXAMPLE-NOT-A-KEY` in a tracked file proved the pass was
empty; the fix (PR #3) reports coverage (`54 files scanned, 20 skipped`) and
now fails on the same probe.
Failed: accepting a green result as evidence without ever seeing the check fail.
Rule: every gate check must be demonstrated failing once against a planted
fixture before its passing result may be recorded as evidence; a check whose
only observation is "pass" proves nothing.
Evidence: `tasks/T-0006.md:12,33`; `docs/gates/G1-result.md:14-30`; corrected
`scripts/gate/secrets.ps1:23-27,58-65,76`; distinct from L-016 (there the exit
code was honest, the coverage was empty).

## L-022 — 2026-11-05 — PowerShell `-match` is case-insensitive; placeholders must break the pattern structurally
Situation: while documenting the scanner fix, a real-looking AWS key was
replaced with a lowercase variant — which still matched `AKIA[0-9A-Z]{16}`,
because `-match` ignores case, and CI failed again on the documentation.
Worked: hyphenated placeholders (`AKIA-EXAMPLE-NOT-A-KEY`) break the pattern
structurally and pass the scanner.
Failed: assuming case is a distinguishing feature in a case-insensitive engine.
Rule: in PowerShell, any placeholder meant to dodge a regex must break the
pattern's structure (hyphens, spaces, wrong length), never rely on case; never
write a key-shaped literal into a brief, gate record, or any scanned file.
Evidence: `scripts/gate/secrets.ps1:16` (pattern `AKIA[0-9A-Z]{16}` under
case-insensitive `-match`, line 69); the passing hyphenated placeholder at
`tasks/T-0006.md:12`.

## L-023 — 2026-11-05 — Gate evidence and the signed commit must be the same commit
Situation: G1's recorded evidence was taken at `562572f`; three documentation
commits followed before the human signature, so the gate record and `dev` head
diverged. Nothing wrong was signed, but the signer had to reason about whether
the divergence mattered.
Worked: the divergence was visible in the result file itself (commit field vs.
actual head), so it could be reasoned about.
Failed: letting evidence and signature reference different commits without the
record acknowledging it.
Rule: either re-run the gate at the final commit before signing, or state the
divergence (commits since evidence, what they touched) in the result file
itself; never leave the signer to reconstruct the gap.
Evidence: `docs/gates/G1-result.md:4` (`562572f`) and :8 (`Signed: no`) —
the recorded commit predates the signature and the later docs commits are not
in the record.

## L-024 — 2026-11-05 — Lessons must be captured when the failure happens, not at retro
Situation: the human had to ask twice for lessons to be captured promptly —
once before the G1 signature, once to add a standing rule — the exact trigger
"human has to ask for something the process should already have done" from
`AGENTS.md`'s own list.
Worked: the human escalated; the standing rule now exists in `AGENTS.md` and
this record is its provenance.
Failed: treating lessons as a retro artifact, so failures sat unrecorded for
hours and the human had to notice them.
Rule: when a trigger from `AGENTS.md`'s "Record failures immediately" list
fires, dispatch `archivist` with the evidence before the next task starts;
do not batch it for the gate retro.
Evidence: `AGENTS.md:14` ("Record failures immediately"); two human requests
in this session preceding this record.
