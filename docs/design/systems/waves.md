# Waves — curves per level archetype, and the composition rule

> **G2 PLACEHOLDER.** Every number in this file is a guess made before the slice
> exists. Nothing here is validated until a human plays a full run (G2.2). Rows
> marked `GUESS` have no data behind them; the last column names what would
> replace the guess.

Owner: `design/systems`. As of T-0035, 2026-11-06.

- **Number home.** This file owns wave counts, wave budgets (in threat), spawn
  intervals, composition weights, unit caps and sub-boss placement. Enemy stats
  and threat costs live in `enemies.md`; gold and HQ live in `economy.md`.
- **Threat is the budget currency.** One threat ≈ 40 effective HP
  (`enemies.md` §Threat cost). A wave is "spend N threat on allowed enemies".
- **Session constraint.** The charter asks for a 15–30 minute run of 5–10
  levels. At 6–8 waves of 20–35 s plus a build phase, a level is **2.5–4
  minutes**, so a **7–8 level path is the maximum** that fits the stated
  session. A 9-level path lands at 30–36 minutes. **This is a human decision**
  (see Open questions).

## Level archetypes

A level's archetype is chosen by its **depth on the run path**, not by which map
it is (maps repeat — `docs/CHARTER.md` §Scope budget).

| Archetype | Depths | Waves | Its job | Failure it must produce |
| --- | --- | --- | --- | --- |
| Opening | 1–2 | 6 | teach placement, one tower, one runner | a player who buys nothing loses 2–3 HQ, not the level |
| Pressure | 3–5 | 7 | the build starts costing gold; armour and packs appear | a player who never upgraded leaks 4+ here |
| Peak | 6–7 | 8 (wave 5 is a sub-boss) | the build is tested on its weakest axis | a one-note build is found out |
| Boss | 8 | 6 + boss wave | the run's exam | a build with a hole loses the run here |

**Level scale.** Within a window the later levels are harder
(`budget = base × scale`):

| Position in window | Scale | Why |
| --- | --- | --- |
| 1st | ×1.00 | the introduction |
| 2nd | ×1.08 (opening ×1.10) | the same map, learned |
| 3rd | ×1.16 | the last pressure level before the archetype changes |

`GUESS` the ×1.08/×1.16 steps. **Would settle it:** if a player's second pass at
the same archetype feels identical, raise the second step to ×1.15. If the third
pressure level is where runs end, lower it to ×1.10.

## Budget curves, per wave

Each cell is a wave's **threat budget** (before level scale). Compositions are
built from these by the rule below; they are not lists of enemies.

| Archetype | w1 | w2 | w3 | w4 | w5 | w6 | w7 | w8 | Total |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Opening | 6 | 9 | 10.5 | 14.5 | 18 | 24 | — | — | 82 |
| Pressure | 12 | 16 | 19 | 23 | 27 | 32 | 37 | — | 166 |
| Peak | 20 | 24 | 28 | 33 | **38 + Bulwark** | 44 | 50 | 57 | 294 + 25 |
| Boss | 26 | 30 | 35 | **40 + Herald** | 46 | 52 | boss wave | — | 229 + 19 + 140 |

The curve shape is deliberate: **roughly +25% to +40% per wave, with the
biggest jump into the last two waves**. Wave 1 of every archetype is *lower*
than the previous level's last wave — the level starts with room to breathe and
the player re-reads the map. `GUESS` the exact shape; if playtesters report the
middle of a level as flat, add the missing threat to w4–w5 and not to w1.

## Spawn interval, per wave

Interval is the **primary difficulty dial at the opening**, because it converts
directly into arrivals per second, which is what a tower's kill rate is compared
against (`enemies.md` §Time on the lane). Budget decides *what* arrives; interval
decides *whether a single tower can hold*.

| Archetype | w1 | w2 | w3 | w4 | w5 | w6 | w7 | w8 | Floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Opening | 2.2 | 2.0 | 1.9 | 1.7 | 1.5 | 1.3 | — | — | 1.3 |
| Pressure | 2.0 | 1.8 | 1.7 | 1.5 | 1.4 | 1.2 | 1.0 | — | 1.0 |
| Peak | 1.6 | 1.5 | 1.4 | 1.2 | 1.1 | 0.9 | 0.8 | 0.7 | 0.7 |
| Boss | 1.6 | 1.5 | 1.4 | 1.2 | 1.1 | 0.9 | — | — | 0.7 |

Hard floor **0.5 s** for any wave, any archetype. Below that, two enemies occupy
the same 32 px of lane and the player cannot count them (pillar 3).

`GUESS` every interval. **Would settle it:** the K2 measurement in
`economy.md` — count leaks on wave 1 of level 1 with exactly one Arrow tower. The
target is **0 leaks, one wave of slack**. More than 2 leaks means the interval is
too tight; zero pressure at all (nothing reaches the HQ) means it is too loose.

## The composition rule

Given a wave with budget `B`, archetype `A`, and allowed enemy set `P` (from
`enemies.md` §Introduction schedule):

1. **Pick the type count.** Waves 1–2: one type. Waves 3–4: up to two. Wave 5
   onward: up to three. Never more than three — a fourth type is a shape the
   player cannot read in one look.
2. **Draw types** from `P` with the weights below (weights are relative; drop any
   type not in `P` and renormalise).
3. **Split the budget** by the drawn types' weights, with a cap: no type may
   take more than **60%** of `B` before wave 5, or **70%** after.
4. **Round into legal packs.** Swarmlings are bought in packs of **6** (3 threat
   per pack) and everything else in ones. Round *down*, then spend the remainder
   on the heaviest affordable type; a remainder smaller than the cheapest legal
   pack (0.5) is discarded, not carried over.
5. **Order the spawns** by descending threat per unit, interleaved in blocks of
   three when two or more types are present. The biggest thing is never hidden
   behind ten grunts: the player must see the Shieldback while there is still
   time to answer it.
6. **Apply the caps.** Maximum **40 units** in a wave (`GUESS`, a performance
   and readability limit — G2.3 measures 60 fps against it). If `B` cannot be
   spent under the cap, replace the cheapest units with heavier types until it
   fits; do **not** raise the cap.
7. **Set the interval** from the archetype's interval row, adjusted by
   `interval = base_interval × (units / 24)` clamped to the table's floor — a
   wave of 8 units should not trickle for 40 s, and a wave of 30 should not
   arrive as a wall. `GUESS` the 24-unit reference.

| Archetype | Grunt | Runner | Shieldback | Swarmling | Bloom |
| --- | --- | --- | --- | --- | --- |
| Opening | 60 | 20 | 10 | 10 | 0 |
| Pressure | 30 | 25 | 20 | 15 | 10 |
| Peak | 20 | 20 | 25 | 20 | 15 |
| Boss | 20 | 20 | 25 | 15 | 20 |

Weights are the *share of the budget*, not of the unit count. A Bloom-heavy peak
wave is fewer units than a grunt-heavy one at the same budget — that is the
point of paying for behaviour.

## Level 1, fully specified (the calibration level)

Level 1 is the only level whose composition is written out unit by unit. Every
other wave is generated by the rule; this one is the fixture the economy's
worked example and the K2 threshold are computed from. **Changing this table
changes `economy.md` §Worked example.**

| Wave | Budget | Interval | Composition | Units | HP pool |
| --- | --- | --- | --- | --- | --- |
| 1 | 6 | 2.2 s | 6 Grunt | 6 | 240 |
| 2 | 9 | 2.0 s | 6 Grunt, 3 Runner | 9 | 312 |
| 3 | 10.5 | 1.9 s | 8 Grunt, 1 Shieldback | 9 | 410 |
| 4 | 14.5 | 1.7 s | 8 Grunt, 1 Runner, 1 Shieldback, 1 Swarmling pack | 16 | 482 |
| 5 | 18 | 1.5 s | 9 Grunt, 4 Runner, 2 Shieldback | 15 | 636 |
| 6 | 24 | 1.3 s | 10 Grunt, 6 Runner, 2 Shieldback, 1 Swarmling pack | 24 | 772 |

The HP pool is raw HP; armour makes w3 onward ~5–10% more expensive in practice.
Wave 1 = **240 HP**, which is the number `economy.md` §K2 uses.

Duration check: w6 is 24 units at 1.3 s ≈ 31 s of spawns, plus a 13 s grunt tail
≈ **44 s**. Within the 40 s spawn target? No — the block is 31 s, the tail is
outside it. State the target as *spawn window ≤ 35 s*; w6 passes.

## Sub-boss and boss waves

| Wave | Composition | Rule |
| --- | --- | --- |
| Peak w5 | Bulwark + 50% of the wave's budget as trash | the sub-boss is added; the budget halves |
| Boss-level w4 | Herald + 60% of the wave's budget as trash | same |
| Boss level, final wave | Warden alone, spawning 2.0 s after w6 is fully cleared | no escorts at spawn; phase 2 adds 4 Runners |
| Boss wave target | the Warden should die at 60–90% of the lane | if it dies before half, the boss is soft; if it leaks from full HP on an average build, it is a wall |

`GUESS` the 50%/60% trash fractions and the "dies at 60–90%" target.
**Would settle it:** the boss's leak-or-die position in the first completed run.

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| Budget 0 | legal: an empty "breathing" wave; still pays the wave-clear bonus | a designer may want a pause, and the economy must not divide by zero |
| Budget negative | illegal; clamp to 0 and log | a negative budget would spawn a negative wave |
| Budget below the cheapest legal pack (0.5) | spawn one Grunt, or skip | a wave that spends nothing is a bug, not a pause |
| Allowed set has one type | weight step is skipped, not divided by zero | level 1 allows two types; a single-type level is legal |
| Unit cap reached with budget unspent | swap to heavier types; never exceed 40 | G2.3 is measured on the real scene; the cap is the safety margin |
| `level_scale` 0 or negative | illegal; clamp at 0.5 | a scale of 0 is twelve empty waves |
| Level with fewer waves than the archetype | legal; use the first N rows | the map decides length within 6–8 |
| Boss level with no boss wave | illegal; the run cannot end | the run lifecycle (`src/systems`) depends on a terminal wave |
| Interval below the 0.5 s floor | clamp, and log | units overlap visually and the count becomes unreadable |
| Two sub-bosses in one level | illegal at G2 | the charter budgets two sub-bosses total, not per level |
| A leak during the spawn window | waves keep spawning; only HQ death stops the level | the player's failure must be legible, not an abrupt cut |

## What is not in the wave curve

- **No difficulty selection.** One curve; the human may add an easier first run
  later.
- **No wave preview UI.** `design/level` and `eng/gameplay` own whether the next
  wave's composition is shown; this file only guarantees the *next* wave is
  knowable.
- **No dynamic difficulty.** A wave does not scale with the player's gold or
  leaks. The charter's hidden information is about *offers*, not about waves.
- **No endless mode, no wave 10+.** Six to eight waves per level is the budget.

## Open questions for the human

1. **Run length vs session length.** 8 levels × 3.3 min = 26 min; 9 levels =
   30 min plus between-level choice time. The charter says 15–30 minutes and 9
   maps exist. Options: (a) 8-level path, 9 maps, reuse 1; (b) 9 levels and
   accept 32–36 min; (c) 7 levels. Recommendation: (a) until a human has played
   it once.
2. **Should a wave ever be empty?** A "breathing" wave between pressure spikes
   is a strong pacing tool but reads as a bug the first time.
3. **Is the `+25–40%` per-wave ramp too steep for a first-time player?** The
   alternative is a flatter curve with tougher enemies, which changes the feel
   from "the wave is bigger" to "the wave is nastier". This is a taste call.
