# ADR-0004 — Loudness for sub-second assets

Date: 2026-11-05
Status: accepted
Deciders: Guybrush Threepwood (human)

## Context

EBU R128 integrates loudness over 400 ms gating blocks. A one-shot whose audible
energy is a ~20 ms transient inside a second of near-silence therefore cannot be
lifted to −16 LUFS without its peaks exceeding 0 dBTP.

That is not a tuning problem. The G2 Wave 1 audio probe measured a real
ElevenLabs UI click at **−29.1 LUFS integrated, peak −2.0 dBTP**, against a target
of −16 ±2 LUFS with a −1 dBTP ceiling. Applying the +17 dB the target implies
would put the peak at roughly +11 dBTP. No gain setting satisfies both conditions
for that asset class, and `post.ps1`'s gain-then-limit step recovered only 3.9 dB
of the 17 it tried to apply, because the limiter was doing its job.

The target was inherited from a music-mixing convention and applied to material it
does not describe. Games mix hits by peak and beds by loudness, because a hit's job
is to land inside a moment, not to average out over one.

## Decision

1. **Assets ≥ 1 s** — music loops and ambience beds — are gated on integrated
   loudness exactly as before: music −18 LUFS, ambience −20 LUFS, tolerance ±2 LU.
2. **Assets < 1 s** — one-shots — are gated on **true peak at or below −1 dBTP,
   aiming for −1.5 dBTP**. Integrated loudness does not gate them.
3. **Integrated loudness is still measured and reported for short assets**, labelled
   advisory. It must never silently disappear from the output; an advisory number a
   human can read is worth more than a check that pretends to be meaningful.
4. The master bed keeps its −16 LUFS integrated target and −1 dBTP ceiling.

## Consequences

**Intended:** one-shots become gateable at the quality they actually ship at, and
the gate measures the way the mix behaves. A click that sounds right and peaks at
−2 dBTP passes; the same click at −29.1 LUFS no longer fails a criterion that was
never about it.

**Accepted cost:** two measurement regimes in one gate. The gate must decide which
rule applies from the asset's duration, and a mis-declared duration becomes a way
to dodge the loudness check. Mitigation: duration is read from the file, not from
the manifest, and both numbers are reported for every asset either way.

**Follow-on work, required before batch audio:** `post.ps1` must peak-normalise
short clips instead of computing an EBU R128 gain — sub-400 ms input currently
returns the −70 LUFS floor and applies an enormous, meaningless gain — and it must
trim trailing silence for `kind: sfx`. The untrimmed tail is what put a 20 ms click
inside a half-second file and triggered the whole investigation.

## Rejected alternatives

**Keep −16 LUFS for everything and demand denser sounds.** Would work, at the cost
of forcing every UI tick and impact to carry 150–200 ms of body. That changes the
game's sound design to satisfy a measurement, and the human rejected it explicitly.

**Drop loudness measurement for one-shots entirely.** The advisory number and the
peak ceiling both stay; removing measurement would let a silent or clipped asset
pass.

**Normalise short assets on RMS only.** Closer to mixing practice than R128, but
RMS is trivially gamed by a single loud sample and is not what the mix decision is
made against. True peak is the constraint that actually matters for a transient.
