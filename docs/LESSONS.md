# Lessons

Rules derived from real events. Maintained by `archivist`, read by everyone.
Keep this file near 100 lines; archive the oldest entries to
`docs/lessons/archive-<milestone>.md`.
Entries L-001 … L-008 (2026-11-02 → 2026-11-03) live in
`docs/lessons/archive-G0.md`; entries L-009 … L-012 (2026-11-04) live in
`docs/lessons/archive-G1.md`; entries L-013 … L-014 (2026-11-04) live in
`docs/lessons/archive-2026-11-04.md`; entries L-015 … L-017 (2026-11-05) and
L-024 (2026-11-05) live in `docs/lessons/archive-2026-11-05.md` (which also holds a copy of
still-active L-021). Their rules remain in force.

## L-021 — 2026-11-05 — A check that has never been observed failing is not evidence
Situation: `secrets.ps1` passed G1.9 while scanning zero files: it counted
every tracked file and regex-tested none. A planted AWS-key-shaped string
passed the gate.
Worked: planting a fixture proved the pass was empty; the fix (PR #3) reports
coverage and now fails on the same probe.
Failed: accepting a green result as evidence without ever seeing the check fail.
Rule: every gate check must be demonstrated failing once against a planted
fixture before its passing result may be recorded as evidence; a check whose
only observation is "pass" proves nothing.
Evidence: `tasks/T-0006.md:12,33`; `docs/gates/G1-result.md:14-30`; corrected
`scripts/gate/secrets.ps1:23-27,58-65,76`. Archived copy:
`docs/lessons/archive-2026-11-05.md`.

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

## L-025 — 2026-11-05 — A milestone can be signed while a gate the next milestone depends on is an unimplemented stub
Situation: G1 was signed clean, but `scripts/gate/perf.ps1` implements nothing
— it reports `blocked` for both G2.3 checks and always will, because
`scripts/perf/benchmark.tscn` does not exist and the measurement harness was
never written (the file documents the intended method at lines 4-16). Nothing
in G1 checked whether the scripts G2's criteria depend on were implemented, so
the gap surfaced only when the human verified externally after signing.
Worked: the human's external verification caught it; the script is honest
about being blocked rather than guessing a measurement.
Failed: treating "gate scripts exist on disk" as "the next gate is runnable".
Rule: before signing any gate, enumerate the gate scripts the next milestone's
criteria reference and verify each either exists with its inputs implemented
(scenes, manifests, harnesses) or is listed as a known blocker in
`docs/STATE.md` — mechanically: for every `scripts/gate/*.ps1` named in the
next gate's criteria table, grep its `blocked`/`Add-Result` paths and
`Test-Path` targets and confirm each target exists.
Evidence: `scripts/gate/perf.ps1:22-28` (both G2.3 checks report `blocked`);
`docs/gates/G2-vertical-slice.md:20` (G2.3 depends on it); `scripts/perf/`
directory absent.

## L-026 — 2026-11-05 — A pipeline verified only against fixtures is unverified
Situation: the audio pipeline (`scripts/audio/gen-sfx.ps1`, `post.ps1`,
`scripts/gate/audio.ps1`) passes 6/6 against fixtures and has never processed
real ElevenLabs output. Fixtures encode our assumptions about the vendor's
format; only a real call can falsify them.
Worked: the gap was recognised at planning time and captured as task T-0012 —
one real, cheap placeholder asset through the full pipeline and gate before
batch production, with an explicit stop-and-report rule on rejection.
Failed: treating fixture passes as pipeline passes; a fixture can only confirm
what we already assumed about the vendor.
Rule: before authorising any batch paid generation, run exactly one real,
cheap, placeholder asset through the full pipeline and its gate; if the gate
rejects the real output, stop work on that pipeline entirely and report —
never retry or loosen tolerances on the first real failure.
Evidence: `tasks/T-0015.md:11-16` (goal, budget 1, stop rule), :57-61
(rejection is a stop-work signal; brief renumbered from T-0012 by L-027);
extends L-021 from checks to whole pipelines.

## L-027 — 2026-11-05 — Task ids allocated from local memory collide with merged briefs on `origin/dev`
Situation: while planning G2, new briefs were written into `tasks/T-0011.md`
and `tasks/T-0012.md`, overwriting merged records: `origin/dev` already held
T-0011 (asset-gate fixes, PR #8), T-0012 (CI-pending reported as blocked,
PR #9) and T-0013 (single-committer process change, PR #10). The ids came
from the last id the lead had personally issued, not from the repository.
Worked: the human caught it before anything was committed; the merged briefs
were restored with `git checkout origin/dev -- …` and the new briefs
renumbered to T-0014 … T-0016 with branches rewritten.
Failed: treating local memory as the source of truth for the id sequence; a
stale local view silently reuses permanent ids.
Rule: before creating any task brief, run `git fetch`, then
`git ls-tree --name-only origin/dev tasks/` and allocate the next free id
from the highest id found there; a merged id is permanent and is never
reassigned, and a fresh brief is committed or pushed promptly so its id
becomes visible to everyone else.
Evidence: `git ls-tree --name-only origin/dev tasks/` (T-0011, T-0012,
T-0013 present); `git log --oneline -4 origin/dev` at `28251c4` (PRs #8-#10);
overwritten-then-restored briefs; renumbered `tasks/T-0014.md` …
`tasks/T-0016.md` on `dev`.
