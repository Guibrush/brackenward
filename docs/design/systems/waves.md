# Waves — one curve, indexed by level, and the two run lengths

> **G2 PLACEHOLDER.** Every number in this file is a theory-crafting default written
> before the slice exists, not a measurement. Nothing here is validated until a human
> plays a full run (G2.2). Rows marked `GUESS` have no data behind them; the last
> column names the observation that would replace the guess.

Owner: `design/systems`. Rewritten at T-0038, 2026-11-06. Supersedes T-0035 entirely.

- **Number home.** This file owns wave counts, wave budgets (in threat), spawn intervals,
  composition weights, unit caps, the level-index growth curve, sub-boss placement and the
  elite finale. Enemy stats and threat costs live in `enemies.md`; gold and HQ in
  `economy.md`; which node is a level in `nodes.md` / `run-map.md`.
- **Threat is the budget currency.** One threat ≈ 40 effective HP (`enemies.md` §Threat
  cost). A wave is "spend N threat on allowed enemies".
- **`DATADRIVEN`** marks a named field meant to be tuned by data, never by code. The value
  shown is a default, not a commitment.

## What T-0038 changed

The old model picked a level's shape from its **depth archetype** (opening / pressure /
peak / boss) on an assumed 8-level path. That is dead: a run is now 5–10 levels of the
player's own choosing, on a 9-layer map, in any order of node types. A level cannot know
which archetype it "is".

| Concern | T-0035 (dead) | T-0038 (this file) |
| --- | --- | --- |
| What a level scales on | Its depth window and an archetype table | **`level_index` only** — the count of levels already played this run |
| Wave count | Fixed per archetype (6 / 7 / 8 / 6+boss) | A function of `level_index` (6 / 7 / 8) |
| Budget curve | Four hand-written archetype rows | One geometric curve and one per-wave split |
| Interval | A 4×8 lookup table | Three numbers: a base ladder, one tighten ratio, one floor |
| Elite levels | A "peak" archetype with a wave-5 sub-boss | A **standard map whose final wave carries one sub-boss** (`nodes.md`) |
| Run length | Assumed 8 | 5–10; the curve is identical for every length |

**The rule, stated once, for the whole file:** difficulty is a function of `level_index`
and of nothing else. Not of gold, not of HQ, not of tower count, not of leaks, not of the
run's remaining length. The human's instruction is explicit: let players build broken
combinations, add **no anti-snowball mechanics**, no rubber-banding, no mercy scaling.

## The scale — three numbers

    level_index  i = levels already played this run + 1        (1-based, integer)
    total_threat(i) = round(82 × 1.20^(i−1))                  (levels 1–9)
    waves(i)       = 6 if i ≤ 3, 7 if i ≤ 6, 8 otherwise

| Field | Value | Range | `DATADRIVEN` | Reason for the bound |
| --- | --- | --- | --- | --- |
| `level1_threat` | 82 | 60–110 | yes | below 60 level 1 teaches nothing; above 110 a first level needs two towers it cannot own |
| `level_growth` | 1.20 | 1.12–1.30 | yes | 1.20 makes level 9 ≈ 4.3× level 1; below 1.12 the run stops escalating; above 1.30 the curve arrives at the boss unaffordable |
| `wave_ramp` | 1.32 | 1.20–1.45 | yes | the geometric ratio between consecutive waves inside a level; 1.32 reproduces the old calibrated opening (w6 ≈ 4.1× w1) |

**`level_growth = 1.20` is the single most important number in this file.** It is the whole
difficulty of the run. It is also the number most likely to be wrong, and it must be moved
alone (see `README.md` §How to tune this, in order).

| `level_index` | Waves | Total threat | Growth over level 1 |
| --- | --- | --- | --- |
| 1 | 6 | 82 | ×1.00 |
| 2 | 6 | 98 | ×1.20 |
| 3 | 6 | 118 | ×1.44 |
| 4 | 7 | 142 | ×1.73 |
| 5 | 7 | 170 | ×2.07 |
| 6 | 7 | 204 | ×2.49 |
| 7 | 8 | 245 | ×2.99 |
| 8 | 8 | 294 | ×3.59 |
| 9 | 8 | 353 | ×4.30 |
| boss | 7 | 340 trash + Warden + escorts | see §The boss level |

`GUESS` every row. **Would settle it:** the level at which runs end. If runs end at level 3
or 4, growth is too steep; if a run of 8 levels is finished by more than half of testers,
it is too flat. The target is **runs ending at level 5–7 for an average player**.

## What a wave is made of — the split

A level's total threat is divided between its waves by a **geometric ramp**, so the wave
shape is one number rather than a table of eight:

    share(w) = wave_ramp^(w−1) / Σ(k = 1…W) wave_ramp^(k−1)
    wave_budget(w) = round_to_0.5( total_threat(i) × share(w) )

| Waves in the level | w1 | w2 | w3 | w4 | w5 | w6 | w7 | w8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 6 (levels 1–3) | 7.5% | 9.9% | 13.0% | 17.2% | 22.7% | 29.9% | — | — |
| 7 (levels 4–6) | 5.3% | 7.1% | 9.3% | 12.3% | 16.2% | 21.4% | 28.3% | — |
| 8 (levels 7–9) | 3.9% | 5.1% | 6.8% | 9.0% | 11.8% | 15.6% | 20.6% | 27.2% |

The last wave is always the largest and the first is always the smallest. That is the
readability rule: **a wave 1 that leaks means the level is mis-scaled, never that the wave
was hard** (pillar 3 — the player must be able to tell which).

Worked budgets, rounded to 0.5, for five levels across the curve:

| `level_index` | w1 | w2 | w3 | w4 | w5 | w6 | w7 | w8 | Sum |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 (82) | 6.0 | 8.0 | 10.5 | 14.0 | 18.5 | 25.0 | — | — | 82.0 |
| 3 (118) | 9.0 | 11.5 | 15.5 | 20.0 | 26.5 | 35.5 | — | — | 118.0 |
| 5 (170) | 9.0 | 12.0 | 16.0 | 21.0 | 27.5 | 36.5 | 48.0 | — | 170.0 |
| 7 (245) | 9.5 | 12.5 | 16.5 | 22.0 | 29.0 | 38.0 | 50.5 | 67.0 | 245.0 |
| 9 (353) | 13.5 | 18.0 | 24.0 | 31.5 | 41.5 | 55.0 | 72.5 | 97.0 | 353.0 |

## Spawn interval

Interval converts a budget into **arrivals per second**, which is what a tower's kill rate
is compared against (`enemies.md` §Time on the lane). It is the second half of difficulty
and it is deliberately a consequence of position, not of enemy type:

    base_interval = [2.2, 2.0, 1.9, 1.7, 1.5, 1.3, 1.2, 1.1]     indexed by wave number
    interval(w, i) = clamp( base_interval[w] × tighten^(i−1), 0.5, 2.6 )

| Field | Value | Range | `DATADRIVEN` | Reason for the bound |
| --- | --- | --- | --- | --- |
| `tighten` | 0.94 | 0.88–1.00 | yes | at 0.94, level 9 is 0.57× level 1's spacing — a 1.26 s wave 1 becomes 0.63 s by w8 |
| `interval_floor` | 0.5 s | 0.4–0.8 | yes | below 0.5 s two enemies occupy the same 32 px of lane and cannot be counted (pillar 3) |
| `interval_ceiling` | 2.6 s | 2.0–3.5 | yes | above 2.6 s a six-unit wave trickles for 16 s and reads as a bug |

| `level_index` | w1 | w2 | w3 | w4 | w5 | w6 | w7 | w8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 2.20 | 2.00 | 1.90 | 1.70 | 1.50 | 1.30 | — | — |
| 3 | 1.94 | 1.77 | 1.68 | 1.50 | 1.33 | 1.15 | — | — |
| 5 | 1.72 | 1.56 | 1.48 | 1.33 | 1.17 | 1.01 | 0.94 | — |
| 7 | 1.51 | 1.38 | 1.31 | 1.17 | 1.03 | 0.90 | 0.83 | 0.76 |
| 9 | 1.26 | 1.15 | 1.09 | 0.97 | 0.86 | 0.75 | 0.69 | 0.63 |

Level 1's row is **identical to the T-0035 calibration**, deliberately: the opening is the
one level whose numbers were checked against a tower's kill rate by hand
(`economy.md` §K2′), and rewriting the curve must not move it.

## The composition rule

Given a wave with budget `B`, `level_index i`, and allowed enemy set `P`:

1. **Allowed set** — `P` is fixed by `level_index`, one new enemy per level, in the order in
   `enemies.md` §Introduction schedule. That table's *order* is unchanged; only its row
   labels are re-indexed from "depth" to `level_index`. A level never introduces two
   enemies it has never shown.
2. **Pick the type count.** Waves 1–2: one type. Waves 3–4: up to two. Wave 5 onward: up to
   three. Never more than three — a fourth type is a shape the player cannot read in one
   look.
3. **Draw types** with the weights below (relative; drop any type not in `P` and
   renormalise).
4. **Split the budget** with a cap: no type may take more than **60%** of `B` before wave
   5, or **70%** after.
5. **Round into legal packs.** Swarmlings come in packs of 6 (3 threat); everything else in
   ones. Round *down*, spend the remainder on the heaviest affordable type, and discard a
   remainder below the cheapest legal pack (0.5). **Never carry budget between waves.**
6. **Order the spawns** by descending threat per unit, interleaved in blocks of three when
   two or more types are present. The biggest thing is never hidden behind ten grunts.
7. **Apply the caps.** At most **`unit_cap_per_wave = 40`** (`DATADRIVEN`, range 30–60; a
   performance and readability limit, measured by G2.3). If `B` cannot be spent under the
   cap, replace cheap units with heavier types. **Do not raise the cap.**

| `level_index` band | Grunt | Runner | Shieldback | Swarmling | Bloom |
| --- | --- | --- | --- | --- | --- |
| 1–2 | 70 | 30 | — | — | — |
| 2 | 60 | 25 | — | 15 | — |
| 3–4 | 35 | 25 | 30 | 10 | — |
| 5–6 | 25 | 20 | 25 | 15 | 15 |
| 7–9 | 20 | 20 | 25 | 20 | 15 |

Weights are the *share of the budget*, not of the unit count. A Bloom-heavy wave is fewer,
heavier units at the same threat — that is the point of paying for behaviour.

`GUESS` every weight. **Would settle it:** which enemy each run-ending leak was. If Grunts
cause most losses, the budget is too high; if Shieldbacks do, the build had no armour
answer and the *introduction* order is wrong, not the weight.

## Level 1, fully specified (the calibration level)

Level 1 is the only level written out unit by unit. Every other wave is generated by the
rule. **Changing this table changes `economy.md` §Worked example.** Allowed set: Grunt and
Runner only (`enemies.md`, level 1). Kill values from `economy.md`: Grunt 2, Runner 3.

| Wave | Budget | Spent | Composition | Units | HP pool | Kill gold |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 6.0 | 6.0 | 6 Grunt | 6 | 240 | 12 |
| 2 | 8.0 | 8.0 | 6 Grunt, 2 Runner | 8 | 288 | 18 |
| 3 | 10.5 | 10.0 | 8 Grunt, 2 Runner | 10 | 368 | 22 |
| 4 | 14.0 | 14.0 | 10 Grunt, 4 Runner | 14 | 496 | 32 |
| 5 | 18.5 | 18.0 | 12 Grunt, 6 Runner | 18 | 624 | 42 |
| 6 | 25.0 | 25.0 | 15 Grunt, 10 Runner | 25 | 840 | 60 |
| **Total** | **82.0** | **81.0** | | **81** | **2856** | **186** |

Wave 3 spends 10.0 of 10.5 and discards 0.5 (below the cheapest legal pack). Wave 5 spends
18.0 of 18.5 for the same reason. **A level's spend is never exactly its budget**, and the
gap is never carried forward.

Duration: spawn blocks total 131 s (`units × interval`, wave by wave), plus ~48 s of tails
and six build phases at 15 s ≈ **4.5 minutes**. See §Run length and the session.

## The elite finale

An **elite** node is a standard map — same budget curve, same intervals, same composition
rule — with one change to its **final wave**:

| Property | Rule | Marker |
| --- | --- | --- |
| Sub-boss | Exactly **one**, chosen uniformly at random from Bulwark and Herald *at generation time*, so it is fixed before the player commits | `elite_sub_boss_pool = [Bulwark, Herald]` |
| Trash in the final wave | Reduced to **60%** of that wave's generated budget | `elite_final_trash_fraction = 0.60`, `DATADRIVEN` |
| Sub-boss budget | **Not** bought from the wave budget; it is added on top | `enemies.md` §Sub-bosses |
| Sub-boss HP scaling | **None** — 900 / 450 at every `level_index` (range: 0–0.15 per index) | `sub_boss_scale_per_level = 0.0`, `DATADRIVEN` |
| Completion gold | **45** instead of 30 | `economy.md` |
| Reveal | The node shows "elite" and the map, **never which sub-boss** | `nodes.md` §Reveal |

| Level of the elite | Final wave (normal) | Final wave (elite) | Added threat |
| --- | --- | --- | --- |
| 3 (118, w6 = 35.5) | 35.5 trash | 21.3 trash + Bulwark/Herald | +23.7 |
| 6 (204, w7 = 43.7) | 43.7 trash | 26.2 trash + Bulwark/Herald | +16.3 |
| 9 (353, w8 = 97.0) | 97.0 trash | 58.2 trash + Bulwark/Herald | +40.8 |

The **fixed sub-boss** is deliberate and unusual, so it needs its reason: the sub-boss is
the run's only *non-scaling* wall. An elite taken at level 3 is a real gamble (a 900 HP
Bulwark against a level-3 build), and an elite at level 9 is a formality. That asymmetry is
the elite's entire design — it is a **route choice priced in the currency of "how strong am
I right now"**, which is pillar 2 and nothing else. If it turns out elites are never taken
early, the fix is to scale HP, and that switch is the field above.

`GUESS` the 0.60 trash fraction. **Would settle it:** whether an elite taken at level 3
ends the run for more than one tester in three. If it does, the fraction moves to 0.45 or
the HP scale moves to 0.08 per index — not both.

## The boss level

The boss level is layer 10 of the run map: unique, final, unavoidable, and it cannot be
rerolled (`run-map.md`).

| Property | Value | Marker |
| --- | --- | --- |
| Trash waves | **6**, total **340** threat | `boss_trash_threat = 340`, `DATADRIVEN` |
| Boss wave | The Warden (140 threat, `enemies.md`), spawning 2.0 s after wave 6 is cleared | — |
| Escorts | **60%** of wave 6's budget, added on top of the Warden | `boss_escort_fraction = 0.60`, `DATADRIVEN` |
| Phase 2 | At 50% HP: +20% speed, 4 Runners spawn at its position | `enemies.md` |
| Total threat | 340 + 140 + 61 ≈ **541** | — |
| Waves | 7 (6 trash + the boss wave) | — |
| Intervals | The standard ladder at the boss's own `level_index` | see below |
| Completion gold | 60 | `economy.md` |

**The boss's body is fixed; its pacing is not.** A 5-level run meets a fixed 541-threat boss
at `level_index` 5 (intervals ×0.78); a 10-level run meets the *same* body at `level_index`
10 (intervals ×0.54). This is the difficulty rule applied with no exception: `level_index`
sets everything, including the boss. It also means a short run meets a slower boss, which
partly offsets the smaller build a short run owns — the two effects are not balanced against
each other, and that is a stated open question, not an oversight.

## Run length and the session

Level duration is an estimate, not a promise: **spawn blocks + tails (8 s per wave) + build
phases (15 s each)**, with unit counts derived from threat at an average of 1.0 threat per
unit at level 1 rising to 1.6 by level 9 as heavier types enter.

| `level_index` | Estimated minutes | Unit estimate | Spawn block total |
| --- | --- | --- | --- |
| 1 | 4.6 | 81 | 131 s |
| 3 | 4.7 | 90 | 141 s |
| 5 | 5.0 | 126 | 139 s |
| 7 | 5.6 | 160 | 168 s |
| 9 | 7.1 | 221 | 243 s |
| boss | 7.1 | 214 + Warden | 250 s |

| A run of | Levels incl. boss | Level time | Plus map and store time | Total |
| --- | --- | --- | --- | --- |
| 5 | 4 + boss | 18.6 + 7.1 = 25.7 min | +5 min | **≈ 31 min** |
| 6 | 5 + boss | 23.6 + 7.1 = 30.7 min | +5 min | ≈ 36 min |
| 7 | 6 + boss | 28.9 + 7.1 = 36.0 min | +6 min | ≈ 42 min |
| 8 | 7 + boss | 34.5 + 7.1 = 41.6 min | +6 min | ≈ 48 min |
| 10 | 9 + boss | 47.8 + 7.1 = 54.9 min | +7 min | ≈ **62 min** |

**This is a finding, not a table.** The charter's session is 15–30 minutes for "one run per
sitting", and at these defaults **no run fits it** — the shortest legal run is ≈31 minutes.
Three ways out, all one-field changes:

| Option | Change | Effect on a 10-level run | Cost |
| --- | --- | --- | --- |
| A | `level_growth` 1.20 → 1.15 | ≈ 50 min | late levels stop feeling like a wall of units |
| B | waves 8 → 6 for levels 7–9 | ≈ 45 min | the last third loses its escalation rhythm |
| C | accept it; runs are 5–7 levels in practice, 8–10 is a deliberate "long haul" | unchanged | the charter's 15–30 min becomes "20–40 min" |

Recommendation: **C, decided after one playtest.** The charter also says a motivated player
"can chain runs for several hours without the game asking them to stop", so a long run is
not a charter violation — a long *unavoidable* run would be. This file's job is to make the
choice visible before code hardcodes it.

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| `level_index` 0 or negative | Illegal; the loader rejects | `1.20^(−1)` would make level "zero" the easiest wave in the game |
| `level_index` > 10 | Clamp at 10 and log; the run cannot legally get there | a map bug that keeps counting must not spawn a 10 000-unit wave |
| Budget 0 | Legal: an empty "breathing" wave; still pays the wave-clear bonus | a designer may want a pause, and the economy must not divide by zero |
| Budget negative | Illegal; clamp to 0 and log | a negative budget spawns a negative wave |
| Budget below the cheapest pack (0.5) | Spawn one Grunt, or skip | a wave that spends nothing is a bug, not a pause |
| Allowed set has one type | Weight step skipped, not divided by zero | single-type levels are legal at low index |
| Unit cap reached with budget unspent | Swap to heavier types; never exceed 40 | G2.3 is measured on the real scene; the cap is the safety margin |
| Interval below 0.5 s | Clamp and log | units overlap and counting breaks (pillar 3) |
| Interval above 2.6 s | Clamp and log | the wave reads as a bug |
| Level with fewer waves than its band | Legal; use the first N rows of the ladder | a short map is a `design/level` choice |
| Elite with no sub-boss | Illegal: the generator rejects the node | an elite with no wall is a map node with a worse reward |
| Two sub-bosses on one elite | Illegal | `enemies.md`: the charter budgets two sub-boss types, not per level |
| Boss level with no boss wave | Illegal; the run cannot end | the run lifecycle depends on a terminal wave |
| A leak during the spawn window | Waves keep spawning; only HQ death stops the level | the failure must be legible, not an abrupt cut |
| Boss wave spawns while trash is alive | Illegal: the Warden spawns 2.0 s after wave 6 is *cleared* | an escort pile behind a boss is unreadable |
| Player pauses for an hour mid-level | Legal; nothing scales with real time | no mechanic may depend on the player's clock |

## Not solving

- **No anti-snowball, no rubber-banding, no mercy scaling.** Explicit human instruction.
  A player who breaks the game breaks the game.
- **No difficulty selection.** One curve; an easier first run is a human decision.
- **No wave preview.** A level's composition is never stored on the run map
  (`nodes.md` §Reveal); only the level's dominant enemy types are.
- **No endless mode.** 10 levels is the ceiling, the boss is the last wave.
- **No new enemies.** Five normals, two sub-bosses, one boss — the charter's budget.
- **No rebalancing of `enemies.md`.** If a wave is unholdable, the dial is this file's
  budget, not the enemy's HP.

## Open questions for the human

1. **Session length (the finding above).** Should a 10-level run really take ≈62 minutes?
   Options A, B and C are priced in the table. This is the highest-impact taste call in the
   file and it decides whether the 5–10 spread means "short and long" or "short and very
   long".
2. **Is a fixed boss body right?** A short run meets a fixed wall with a small build; a long
   run meets the same wall with a large one. The alternative is scaling the boss by
   `level_index` like everything else (which would make short runs strictly easier and so
   *optimal*). Recommendation: keep it fixed and let the elite's non-scaling sub-boss carry
   the same idea earlier.
3. **Should a wave ever be empty?** A "breathing" wave is a strong pacing tool but reads as
   a bug the first time.
