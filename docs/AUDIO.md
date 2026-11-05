# Audio guide

Status: **signed at G0 — 2026-11-04**

## Format rules

| Use | Format | Why |
| --- | --- | --- |
| One-shots (events, UI, impacts) | `.wav`, 48 kHz, mono where sensible | Instant playback, no decode cost, small at short lengths |
| Music beds and ambience loops | `.ogg` Vorbis, 48 kHz, loop enabled | Compressed, seamless when crossfaded before encoding |
| Voice or long ambience (if ever) | `.ogg` | Same |

ElevenLabs returns MP3, so conversion is mandatory and happens in
`scripts/audio/post.ps1`. Nothing enters `assets/audio/` without passing through
the post step.

## Loudness

| Element | Target | Peak |
| --- | --- | --- |
| Music bed (≥ 1 s) | −18 LUFS integrated | ≤ −1 dBTP |
| Ambience (≥ 1 s) | −20 LUFS integrated | ≤ −1 dBTP |
| One-shot SFX (< 1 s) | integrated LUFS **advisory only** — does not gate | ≤ −1 dBTP, aim −1.5 |
| Master | −16 LUFS | ≤ −1 dBTP |

Since ADR-0004, integrated loudness gates beds and loops only. One-shots are gated
on true peak, because R128 integrates over 400 ms gating blocks and a transient is
not describable that way: the first real probe measured −29.1 LUFS for a 20 ms
click whose peak was already −2.0 dBTP. Short assets still have their LUFS
measured and printed, labelled advisory — an unreadable number is worse than none,
but a number that silently gates would be worse still. Duration is read from the
file, not from the manifest.

Music sits under effects. Mixing by ear at the end is what makes a game sound
amateur; these numbers are the baseline, and the gate checks them.

## Loops

Generated music is **not** loopable as delivered: it typically opens with
10–20 ms of near-silence and ends quieter than it started.

`post.ps1` trims trailing and leading silence, crossfades roughly 100 ms of the
tail into the head, normalises, then encodes. `gate/audio.ps1` re-measures the
seam **after** processing. A loop that only looks seamless before processing is
a failed loop.

## Naming

`<category>_<subject>_<variant>.wav` — `sfx_coin_pickup_01.wav`,
`sfx_hit_heavy_02.wav`. Music: `mus_<place>_<mood>.ogg` — `mus_forest_calm.ogg`.

Number variants from `01`. Never overwrite a shipped sound; add a variant.

## Sound identity

Folk warmth with chiptune restraint. Plucked strings, small woodwinds, hand
percussion, and a light low-end; one clear melodic voice at a time. Not orchestral,
not pure 8-bit, nothing that sounds like a trailer. The reference is Kingdom Rush's
warmth with Stardew's cosiness: the music should make a lost run feel like an
evening rather than a defeat.

Percussion carries tempo information deliberately: the player reads wave pressure
partly by ear, so the level track must not fight the gameplay's own cues.

## What ships at G2

| Asset | Count | Notes |
| --- | --- | --- |
| Menu loop | 1 | `mus_menu_calm.ogg` |
| Tower defence level loop | 1 | `mus_level_defend.ogg`, shared across all 9 maps |
| Branching map loop | 1 | `mus_map_route.ogg`, the quiet planning state |
| Boss loop | 1 | `mus_boss_siege.ogg`, same instrument palette, more percussion |
| One-shots | 48 | UI 10, towers 10, enemies and bosses 8, economy 4, flow 5, status effects 6, map 3, plus 2 variants |

Boss waves use the boss loop. A separate boss *stinger* is a one-shot, not a fifth
track, and is counted in the flow group.

## Two known traps, recorded so they are not rediscovered

- **L-006 — single-pass loudnorm undershoots.** A single `loudnorm=I=-16` pass missed
  by 3.3 LU on a short clip. Always measure with `print_format=json`, then apply the
  measured values in a second pass, then verify with the gate. Never trust the
  filter to hit its target in one go.
- **L-007 — measure the format you ship.** A stereo measurement corrected and then
  encoded to mono landed 4 LU off. Fix sample rate and channel layout *before*
  measuring, and never put a format conversion between the measurement and the
  encode.

## Budgets

Every audio brief states a budget in calls or credits, and reports actual spend in
the return envelope. Music is expensive per minute; one-shots are cheap per call but
there are many of them.

G2 ceiling: **52 ElevenLabs calls** — 48 one-shots and 4 music tracks — against the
current $10 credit plus free capacity. Music is generated at 60–90 seconds per loop
and never longer; a three-minute bed costs three times as much and loops no better.

## Review limits

No model in this stack can hear. Audio review is objective only: codec, sample
rate, channels, duration, loudness, peak, loop-seam evidence, manifest entry.
Aesthetic judgement is the human's, always.
