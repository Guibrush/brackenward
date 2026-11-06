# Enemies — 5 normal, 2 sub-bosses, 1 boss

> **G2 PLACEHOLDER.** Every number in this file is a guess made before the slice
> exists. Nothing here is validated until a human plays a full run (G2.2). Rows
> marked `GUESS` have no data behind them; the last column of each table names
> what would replace the guess.

Owner: `design/systems`. As of T-0035, 2026-11-06.

- **Number home.** This file owns enemy HP, speed, armour, slow resistance,
  behaviour, pack size and **threat cost**. Gold per kill and leak damage live in
  `economy.md` (they are economy knobs; `economy.md` §Kill gold is the source).
- **Names are working labels.** `design/narrative` owns naming.
- **Lane reference.** All transit and coverage arithmetic below assumes an
  **800 px lane** and a tower **32 px off the lane** with **96 px range**, which
  gives a **181 px coverage window**. Re-derive per map before trusting a wave
  timing; the numbers here are calibration, not constants.

## The eight enemies

| Enemy | Class | Speed (px/s) | HP | Armour | Slow resist | Leak dmg | Threat | Pack size |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Grunt | normal | 60 | 40 | 0 | 0% | 1 | 1.0 | 1 |
| Runner | normal | 110 | 24 | 0 | 0% | 1 | 1.0 | 1 |
| Shieldback | normal | 45 | 90 | 3 | 0% | 1 | 2.5 | 1 |
| Swarmling | normal | 75 | 8 | 0 | 0% | 1 | 0.5 | 6 |
| Bloom | normal | 50 | 120 | 1 | 0% | 1 | 4.0 | 1 |
| Bulwark | sub-boss | 35 | 900 | 6 | 50% | 3 | 25 | 1 |
| Herald | sub-boss | 90 | 450 | 2 | 50% | 3 | 19 | 1 |
| Warden | boss | 30 | 3500 | 5 | 50% | 10 | 140 | 1 |

`GUESS` for every HP and speed value. **Would settle it:** the per-enemy
time-to-kill measured in the first full run (G2.2) against the wave budgets in
`waves.md`; if a wave clears in under half its spawn window, raise that enemy's
HP by 20% rather than raising the wave count.

## Time on the lane — the number that makes speed legible

| Enemy | Crosses 800 px in | Time inside a 96 px tower's coverage (181 px window) | Reads to the player as |
| --- | --- | --- | --- |
| Grunt | 13.3 s | 3.0 s | the measurement everything else is compared to |
| Runner | 7.3 s | 1.6 s | "it got past the back tower" |
| Shieldback | 17.8 s | 4.0 s | "it is taking forever to die" |
| Swarmling | 10.7 s | 2.4 s | "there are so many of them" |
| Bloom | 16.0 s | 3.6 s | "why is nothing dying" |
| Bulwark | 22.9 s | 5.2 s | "it is not stopping" |
| Herald | 8.9 s | 2.0 s | "it is already at the HQ" |
| Warden | 26.7 s | 6.0 s | "this is the whole level" |

A tower's kill capacity is `coverage_time ÷ time_to_kill`, and its arrival rate
is `1 ÷ spawn_interval`. **Kills per coverage window ≥ 1 ÷ spawn interval** is
the leak-free condition; `economy.md` §K2 turns that into a threshold. This is
the single most useful sentence in this file for whoever tunes waves.

## Behaviour, and the player behaviour each one punishes

| Enemy | Behaviour (what must be true in code) | Player behaviour it punishes | The counter the player can see |
| --- | --- | --- | --- |
| Grunt | none; walks and dies | nothing — it is the calibration unit | anything at all |
| Runner | none; speed is the behaviour | one slow, expensive, high-damage tower at the back; long reloads | fast cheap shots, a slow effect, coverage near the start |
| Shieldback | armour 3, flat per hit; shield reads as cracked at 50% HP | many small hits; a wall of Brambles; Swarmling-clearing builds | Ballista, Piercer, Short Brace, a Beacon aura |
| Swarmling | arrives as one pack of 6, all at the same instant | single-target towers, overkill, any build with no area damage | Mortar, Bramble, a slow at the chokepoint |
| Bloom | heals every other enemy within 96 px for 6 HP/s while alive; does not heal itself | low-DPS spread, "damage everywhere", ignoring the middle of the pack | `strongest` priority (it has the most HP of any normal), Ballista, burst |
| Bulwark | armour 6; drops to armour 3 at 50% HP; 50% slow resistance | chip damage and control-only builds | armour pierce, one big hit, patience |
| Herald | grants +25% move speed to enemies within 128 px (not itself); aura ends on death | slow coverage gaps and back-loaded towers; it arrives with escorts | long range, kill it first, `strongest` or `last` |
| Warden | armour 5, 50% slow resist; at 50% HP: +20% speed and spawns 4 Runners at its position | a build tuned only for armour, or only for swarms, or only for slow | mixed damage, area for the Runners, pierce for the body |

None of the eight punishes "playing well". Each punishes one *specific*
over-investment, which is what makes a build a set of choices (pillar 2).

## Threat cost — how much of a wave each enemy is worth

Threat is the currency `waves.md` spends. It is **derived**, not invented, so
adding an enemy later is mechanical:

    effective_hp  = HP × speed_factor × armour_factor × behaviour_factor
    threat        = round_to_0.5( effective_hp / 40 ),  minimum 0.5

| Factor | Value | Reason |
| --- | --- | --- |
| speed ≤ 40 | 0.8 | slower than baseline is worth less |
| speed 41–70 | 1.0 | baseline band |
| speed 71–100 | 1.25 | fast enemies deny the player coverage time |
| speed > 100 | 1.6 | a Runner is worth more than its 24 HP suggests |
| armour | `1 + armour / 15` | armour 3 → 1.20, armour 6 → 1.40 |
| heals others | 1.3 | the Bloom is a force multiplier |
| speed aura | 1.2 | the Herald multiplies the pack it arrives with |
| boss phase | 1.5 | the Warden gets faster and splits at half HP |

Worked examples: Grunt `40 × 1.0 × 1.0 × 1.0 = 40 → 1.0`. Shieldback
`90 × 1.0 × 1.20 = 108 → 2.5` (2.7 rounded down to the nearest 0.5, because
armour is situational — a Ballista build pays no tax for it). Bloom
`120 × 1.0 × 1.07 × 1.3 = 166 → 4.0`.

`GUESS` the constant 40. **Would settle it:** playtest wave-for-wave — if wave 4
of a pressure level is the first wave that leaks, its budget was 22 threat and
the true constant is ~45 HP per threat. Adjust the constant, not the enemy list.

## Damage rules the whole bestiary depends on

| Rule | Statement | Failure it prevents |
| --- | --- | --- |
| Armour is flat per hit | `applied = max(1, damage − armour)` (`towers.md` §Units) | per-hit armour makes armour a percentage in disguise |
| Slow does not stack | strongest slow wins; re-applying refreshes its duration | two Rimes freezing the lane permanently |
| Slow resistance multiplies | Bulwark/Herald/Warden at 50%: a 30% slow becomes 15% | a control build trivialising a boss |
| Healing does not resurrect | a dead enemy is out of the heal set | a Bloom healing past the kill ledger |
| Pack spawn is one event | one pack of 6 = one spawn tick, one `ARENA_LEAK` per member | six spawn intervals of pacing dead time |
| Leak damage is a property of the enemy | the arena's single scalar is a fallback for the test scene only | the whole bestiary costing the same 1 point |

## Introduction schedule — one new idea per level

| Level depth | Archetype | Enemies allowed | New this level |
| --- | --- | --- | --- |
| 1 | opening | Grunt, Runner | Grunt (w1), Runner (w2) |
| 2 | opening | Grunt, Runner, Swarmling | Swarmling (w4) |
| 3–5 | pressure | + Shieldback | Shieldback (w2 of the first pressure level) |
| 5–7 | pressure/peak | + Bloom | Bloom (w4 of the first level that allows it) |
| 6–7 | peak | all normals + Bulwark | Bulwark as the sub-boss of wave 5 |
| 8 | boss | all + Herald + Warden | Herald (w4), Warden (final) |

The rule is **one new enemy per level, introduced with escorts it already
beats**, so the player learns a counter while the wave is still survivable
(pillar 3). A level must not introduce two enemies it has never shown.

## Sub-bosses and the boss

| Enemy | Where it appears | Escort | Design intent |
| --- | --- | --- | --- |
| Bulwark | peak level, wave 5 (of 6–8) | 50% of that wave's budget as trash | the mid-run armour check; if the build has no pierce, this is where it is found out |
| Herald | boss level, wave 4 (of 6) | 60% of that wave's budget | a preview of the boss's speed pressure, scaled down |
| Warden | boss level, final wave (7th) | 4 Runners from phase 2 only | the run's exam: needs mixed damage, area and pierce |

**Sub-bosses and the boss are not bought from a wave budget.** They are named
waves. `waves.md` §Sub-boss waves states what trash accompanies them. Their
threat column exists so a future level can decide "this sub-boss is worth two
waves" without inventing a number.

Boss phase 2 numbers: at 50% HP, +20% speed (30 → 36 px/s) and 4 Runners spawn
at its position. Total boss leak damage is 10 (a third of HQ), so leaking the
boss is survivable **once** — and a second run does not get the same mercy.

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| HP 0 or negative | illegal; loader rejects | an enemy that dies on spawn is a wave that never happens |
| Armour ≥ incoming damage | 1 damage per hit, never 0 | see `towers.md` §Edge cases |
| Speed 0 | illegal for a spawned enemy | it never reaches the HQ, so the wave never ends |
| Speed > 200 px/s | out of band; `GUESS` limit | above this the coverage window is under 1 s and no tower is readable |
| Bloom alone on the lane | heals nobody (`does not heal itself`) | otherwise it is an unkillable healer at low DPS |
| Two Blooms | healing does not stack; strongest heals | stacking healers make a 0-leak requirement invisible |
| Slow resistance > 100% | illegal; clamp at 100% | negative slow would speed enemies up |
| Boss leaks twice in one run | impossible; one boss per boss level | the second leak would end the run from full |
| A pack of 6 leaks | 6 separate points of damage | a pack is 6 enemies, not one event |
| Pre-50% and post-50% boss both trigger | trigger once, latched | a boss that re-triggers its phase is a chained runner spam |

## Legacy conflict — the T-0025 arena placeholders

The test scene currently carries `move_speed = 200`, `damage_per_leak = 1` and
`max_health = 10` (`src/gameplay/lane_walker.gd`, `arena.gd`, `hq.gd`). This file
and `economy.md` supersede them for the slice:

| Constant | T-0025 (test scene) | This design | Note |
| --- | --- | --- | --- |
| Enemy speed | 200 px/s | per-enemy, 30–110 px/s | the 200 value was tuned for an 800 px test lane and one enemy type |
| HQ health | 10 | 30 | see `economy.md` §HQ |
| Leak damage | 1 per any enemy | per-enemy, 1–10 | the arena scalar becomes a fallback for the single-type scene |

The existing tests read `damage_per_leak` from the scene rather than a literal
(`scripts/tests/cases/leak_damage.gd`), so changing the value does not break
G2.9. Leave the test scene alone; change the run's constants.

## Not solving

- **No flying class, no armour types (fire/cold/lightning).** Two damage
  dimensions is one more than the slice can teach in 30 minutes.
- **No enemy abilities beyond the five stated.** No burrowing, no path
  switching, no shields that regenerate.
- **No elite variants.** Threat variation is spent on composition, not on
  modifiers, so the silhouette always means the same thing (pillar 3).
- **No respawn or wave retry.** A leaked enemy is gone.
- **No pathing work.** Every enemy walks the same lane for a level; two-lane
  maps are `design/level`'s scope and reuse these stats unchanged.

## Open questions for the human

1. The Bloom's heal (6 HP/s, 96 px) is the only enemy behaviour that rewards
   *doing nothing* if the player cannot reach it. Is a healer too much for the
   first slice, or is it the cheapest way to make the middle of a pack matter?
2. Should the Warden's phase 2 spawn Runners (more units) or drop armour
   (easier, same units)? The first is more memorable; the second is fairer.
3. Bulwark at 900 HP is 23 s on the lane. Is a 23-second sub-boss acceptable
   pacing in a 3-minute level, or should it be faster and softer?
