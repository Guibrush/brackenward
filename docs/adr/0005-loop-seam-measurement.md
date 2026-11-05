# ADR-0005 — Loop seam measurement for music beds

Date: 2026-11-05
Status: proposed — awaiting human acceptance
Deciders: human

## Context

`scripts/gate/audio.ps1` measures a loop seam by comparing one adjacent-sample step
across the seam against the file's own p99.9 step, and fails if the seam step
exceeds it. That rule is phase-dependent by construction: if the seam happens to land
where the waveform is steep, a perfectly good loop fails.

It has been observed. Five correctly processed beds — same pipeline, same targets,
all −17.9 LUFS — produced seam values of **12, 34, 367, 656, 1019** against a p99.9
of roughly 716. Two of those five would fail, and nothing about their audio differs
in kind: only the phase of the cut.

This is not a tuning problem. Lowering the threshold makes it worse; raising it lets
a real click through. The metric itself measures the wrong thing.

## Decision (proposed — not implemented)

Replace the single-sample-step rule with a **windowed** comparison, using either:

1. **Derivative energy either side of the seam.** Take 5–10 ms before the seam and
   5–10 ms after it, compute derivative energy (sum of squared successive-sample
   differences, normalised by window length), and compare that pair against the same
   statistic computed from several windows sampled from the file body. Fail only when
   the seam's energy exceeds a stated multiple of the body distribution.
2. **Cross-correlation.** Correlate the last 20 ms of the loop with the first 20 ms
   and require the normalised correlation peak to exceed a stated threshold.

Either is acceptable; the ADR does not pick one, and the implementer must justify the
choice with measurements from the five known-good beds.

## Acceptance rule

The replacement must, before it is accepted:

1. **Pass all five good beds** — the same five that produced 12/34/367/656/1019. All
   five, not four.
2. **Fail a deliberately cut loop** — a bed with its tail truncated by 20–50 ms, and
   a bed with a hard discontinuity inserted at the seam. Both must fail.
3. **Report the statistic**, not just the verdict, so a human can see how far a pass
   or fail sat from the threshold.
4. Keep the existing requirement that the seam is measured **after** processing
   (L-006/L-007), never on the raw vendor output.

If a candidate rule cannot satisfy 1 and 2 simultaneously, that is evidence the
measurement approach is wrong, not that the thresholds need loosening.

## Consequences

**Intended:** a correct loop passes regardless of where its zero crossing lands, and a
genuinely bad loop still fails. Batch music production can start.

**Accepted cost:** the gate becomes more complex, and window size, statistic and
multiple must be justified rather than inherited. The numbers in this ADR are
starting points, not specifications.

**Blocking state:** batch music stays blocked until this ADR is accepted **and**
implemented. Do not tune the current rule in the meantime — a tuned version of a
phase-dependent metric is still phase-dependent, and would pass review while teaching
the gate nothing.

## Rejected alternatives

**Raise the p99.9 multiple.** Moves the failure threshold without changing what is
measured; a real click at a gentle phase would still pass.

**Normalise the bed so the seam always falls on a zero crossing.** Cannot be done
after the fact without shifting the loop point, which is itself an audible artefact,
and it optimises the file for the metric rather than for the listener.

**Drop seam checking.** The seam is the one audio defect a listener notices
immediately and a gate can catch without hearing. Removing it trades a noisy check
for no check.
