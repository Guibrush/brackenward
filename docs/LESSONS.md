# Lessons

Rules derived from real events. Maintained by `archivist`, read by everyone.
Keep this file near 100 lines; archive the oldest entries to
`docs/lessons/archive-<milestone>.md`.
Entries L-001 … L-008 (2026-11-02 → 2026-11-03) live in
`docs/lessons/archive-G0.md`; entries L-009 … L-012 (2026-11-04) live in
`docs/lessons/archive-G1.md`; entries L-013 … L-014 (2026-11-04) live in
`docs/lessons/archive-2026-11-04.md`; entries L-015 … L-026 (2026-11-05) live
in `docs/lessons/archive-2026-11-05.md`; entries L-027 … L-028 (2026-11-05)
live in `docs/lessons/archive-2026-11-05.md`. Their rules remain in force.

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

## L-032 — 2026-11-05 — A transient vendor outage presented as a red gate on a pull request
Situation: PR #12 failed CI twice; the first failure was not its contents.
The "Install Godot 4.7.2" step runs `Invoke-WebRequest` against the GitHub
release asset with no retry (`.github/workflows/gates.yml:65` — the workflow
contains no retry anywhere), the runner got `504 Gateway Time-out`, `gh pr
checks 12` reported `gates fail` and `mergeStateStatus` went `BLOCKED`. A
re-run with no code change produced `gates pass 30s` and a clean merge.
Worked: reading the failing step's log identified the fault as external, and
the re-run remedied it.
Failed: a red gate whose only distinction between "our code is broken" and
"the vendor was down" lives inside a step log; an unretimed single external
fetch sits on the critical path of the gate.
Rule: every external fetch on a gate's critical path must make transient
failure distinguishable from a code failure — a small bounded retry (e.g. 3
attempts) plus a step-level marker for retryable errors — so a red gate can
be classified without opening logs; re-running the job is an acceptable
remedy only when the failure is provably external (vendor error status in
the step log), never for a gate that failed on its own checks.
Evidence: `.github/workflows/gates.yml:65` (`Invoke-WebRequest`, no retry in
the workflow); `gh run list --branch task/T-0016-art-probe` showing run
42046676819 pass 35s after the failed run; PR #12 `mergeStateStatus: BLOCKED`
then clean on re-run.
