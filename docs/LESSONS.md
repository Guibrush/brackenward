# Lessons

Rules derived from real events. Maintained by `archivist`, read by everyone.
Keep this file near 100 lines; archive the oldest entries to
`docs/lessons/archive-<milestone>.md`.
Entries L-001 … L-008 (2026-11-02 → 2026-11-03) live in
`docs/lessons/archive-G0.md`; entries L-009 … L-012 (2026-11-04) live in
`docs/lessons/archive-G1.md`; entries L-013 … L-014 (2026-11-04) live in
`docs/lessons/archive-2026-11-04.md`; entries L-015 … L-026 (2026-11-05) live
in `docs/lessons/archive-2026-11-05.md`. Their rules remain in force.

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

## L-028 — 2026-11-05 — A task dispatched without a brief has no definition of done
Situation: T-0005, T-0007, T-0008, T-0009 and T-0010 were dispatched without
briefs; no such files were ever committed, and `git log --diff-filter=D` is
empty — they never existed, so nothing was lost. The commits are the only
evidence of what those tasks were.
Worked: git archaeology (`ls-tree` against `origin/dev`, the deletion log)
established the gap honestly instead of reconstructing the briefs.
Failed: treating "the work looks obvious" as a substitute for a written brief.
Rule: write the brief before dispatch, even when the work looks obvious — a
task without a brief has no definition of done and its acceptance cannot be
reviewed; never backfill a missing brief, because a reconstructed one
fabricates evidence.
Evidence: `git ls-tree --name-only origin/dev tasks/` (T-0005, T-0007 …
T-0010 absent; T-0006 present); empty `git log --oneline --diff-filter=D -- tasks/`.

## L-029 — 2026-11-05 — A brief granted a path that no owner and no permission allows
Situation: T-0014 granted `scripts/perf/**` in prose; `docs/OWNERSHIP.md` has
no row for it and `.opencode/agents/eng/tools.md` denies `edit` there. The
agent correctly blocked rather than routing around the permission. Same
family as L-025: runnability assumed, not checked.
Worked: the agent blocked on the missing ownership row instead of
improvising an unauthorised write path.
Failed: granting a path in a brief without making it real in ownership and
permissions in the same change.
Rule: a brief that grants a new path must add the `docs/OWNERSHIP.md` row and
the agent permission line in the same change, and the dispatcher verifies
both before dispatch.
Evidence: `tasks/T-0014.md` (grants `scripts/perf/**`); `docs/OWNERSHIP.md`
(no row for the path); `.opencode/agents/eng/tools.md` (`edit` denied there).

## L-030 — 2026-11-05 — A loudness target was arithmetically unreachable for the shortest asset class
Situation: one real ElevenLabs click measured −29.1 LUFS against the −16 ±2
LUFS target: a 20 ms transient inside a 400 ms gating block cannot be lifted
to −16 without peaks exceeding +11 dBTP. Format, sample rate and peak checks
passed; loudness could not pass. `post.ps1`'s gain-then-limit undid 13.1 of
the needed 17 dB.
Worked: the one-real-asset probe (per L-026) exposed the impossibility
instead of a paid batch finding out.
Failed: writing a loudness target into a style guide and gate without
validating it against the shortest asset the game ships.
Rule: before a loudness target is written into a style guide or gated,
validate it against the shortest asset class the game will ship using one
real example; if the arithmetic says unreachable, change the target or the
gate, not the asset.
Evidence: measured −29.1 LUFS vs −16 ±2 target; 20 ms transient in a 400 ms
gating block; `post.ps1` gain-then-limit recovers only 3.9 of 17 dB.

## L-031 — 2026-11-05 — A gate that exempts placeholders cannot police placeholders
Situation: `scripts/gate/assets.ps1:133` skips assets marked
`placeholder: true`, and every G2 asset except the anchor is a placeholder,
so the green G2.5 run scanned exactly one image.
Worked: reading the gate against the manifest showed the pass covered a
single file.
Failed: an exemption flag able to make an entire category invisible to the
gate it is supposed to police.
Rule: an exemption flag must not be able to make a whole category invisible
to a gate; if placeholders are exempt, the gate (or a named companion check)
must state what checks them instead.
Evidence: `scripts/gate/assets.ps1:133` (`placeholder: true` skip); manifest
in which all assets but the anchor are placeholders; G2.5 green with one
image scanned.
