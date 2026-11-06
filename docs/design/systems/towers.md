# Towers — 6 towers, 3 tiers each

> **G2 PLACEHOLDER.** Every number in this file is a guess made before the slice
> exists, not a measurement. Nothing here is validated until a human plays a full
> run (G2.2). Each row marked `GUESS` has no data behind it; the last column names
> the observation that would replace the guess.

Owner: `design/systems`. As of T-0035, 2026-11-06.

- **Number home.** This file owns all tower numbers: damage, rate, range, cost,
  upgrade cost. `economy.md` cites them; it does not restate them.
- **Names are working labels.** Naming belongs to `design/narrative`. Renaming a
  tower here is a text change, not a design change.
- **Supersedes** the T-0025 arena placeholders (`move_speed = 200`,
  `damage_per_leak = 1`) wherever they conflict. See `enemies.md` §Legacy conflict.

## Units and rounding

| Quantity | Unit | Rounding | Why it matters |
| --- | --- | --- | --- |
| Damage | integer HP per hit | floor after modifiers | floor keeps two identical towers from rounding differently |
| Rate | seconds between shots | 2 decimals | derived DPS must be reproducible by hand |
| DPS | damage ÷ rate | 1 decimal | a check column, never a stored value |
| Range | px radius, centre to centre | integer | tile-relative arithmetic stays exact on a 32 px grid |
| Cost | gold | integer | no fractional gold anywhere in the economy |
| Slow | % of move speed, seconds | integer % | see `enemies.md` §Slow for the stacking rule |

**Armour interaction** (the rule that decides every "why did that tower stop
working" question; `enemies.md` owns the enemy armour values):

    effective_armour = round(armour × (1 − pierce))
    applied          = damage > 0 ? max(1, damage − effective_armour) : 0

The `max(1, …)` floor is load-bearing: without it a 6-damage tower against 6
armour does nothing at all and the player cannot tell why (pillar 3).

## The six towers, one line each

| Tower | Identity in one line | Verb it owns | Design job (pillar) |
| --- | --- | --- | --- |
| Arrow | Cheap, fast, unglamorous; the tower you can always afford. | shoot one thing | the baseline every other tower is read against (P3) |
| Ballista | Long reach, one heavy bolt, ignores half the armour. | delete one thing | the answer to armour and to the far side of the lane (P2) |
| Mortar | Slow lob, hits a clump; useless against a single file. | hit an area | makes swarms a choice instead of a chore (P2) |
| Rime | Barely scratches; makes everything in range slower. | buy time | converts gold into seconds, the cheapest way to make a bad line hold (P2) |
| Beacon | Never fires. Makes the towers around it better. | multiply a cluster | the reason to build a shape rather than a queue (P1, P2) |
| Bramble | Very short reach, chews everything standing on it. | hold a patch | the cheap, high-DPS, high-risk tile (P1) |

No tower is a reskin of another: each owns a different verb, and the two that
share "damage" (Arrow, Bramble) differ by 2× in range and by single-target
versus area.

## The 3-tier table

Damage, rate and range are **per hit / per shot**. `Ø` means the tower does not
fire. `Splash` is the radius that takes the listed fraction of damage.

| Tower | Tier | Damage | Rate (s) | DPS | Range (px) | Splash (px @ %) | Slow | Cost | Upgrade | Invested | Sell @ 60% |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Arrow | 1 | 10 | 0.50 | 20.0 | 96 | — | — | 70 | — | 70 | 42 |
| Arrow | 2 | 16 | 0.46 | 34.8 | 108 | — | — | — | 60 | 130 | 78 |
| Arrow | 3 | 26 | 0.42 | 61.9 | 120 | — | — | — | 110 | 240 | 144 |
| Ballista | 1 | 45 | 1.60 | 28.1 | 160 | — | — | 110 | — | 110 | 66 |
| Ballista | 2 | 70 | 1.55 | 45.2 | 176 | — | — | — | 85 | 195 | 117 |
| Ballista | 3 | 110 | 1.45 | 75.9 | 192 | — | — | — | 150 | 345 | 207 |
| Mortar | 1 | 22 | 1.90 | 11.6 | 120 | 36 @ 100% | — | 100 | — | 100 | 60 |
| Mortar | 2 | 34 | 1.85 | 18.4 | 132 | 44 @ 100% | — | — | 80 | 180 | 108 |
| Mortar | 3 | 50 | 1.75 | 28.6 | 144 | 52 @ 100% | — | — | 140 | 320 | 192 |
| Rime | 1 | 4 | 0.90 | 4.4 | 104 | — | 30% / 1.2 s | 85 | — | 85 | 51 |
| Rime | 2 | 7 | 0.90 | 7.8 | 112 | — | 40% / 1.4 s | — | 65 | 150 | 90 |
| Rime | 3 | 10 | 0.85 | 11.8 | 120 | — | 50% / 1.6 s | — | 115 | 265 | 159 |
| Beacon | 1 | Ø | — | 0 | 128 (aura) | — | — | 90 | — | 90 | 54 |
| Beacon | 2 | Ø | — | 0 | 144 (aura) | — | — | — | 70 | 160 | 96 |
| Beacon | 3 | Ø | — | 0 | 160 (aura) | — | — | — | 120 | 280 | 168 |
| Bramble | 1 | 6 | 0.40 | 15.0 | 48 (damage radius) | all in radius | — | 60 | — | 60 | 36 |
| Bramble | 2 | 10 | 0.38 | 26.3 | 52 (damage radius) | all in radius | — | — | 50 | 110 | 66 |
| Bramble | 3 | 15 | 0.35 | 42.9 | 56 (damage radius) | all in radius | — | — | 95 | 205 | 123 |

**Ballista pierce** is 50% at all tiers, and 0% for every other tower except a
Beacon-tier-3 buff (see below). It is the Ballista's identity, so it does not
need to grow with tier.

**Bramble** has no projectile: every `rate` seconds it damages **every** enemy
inside its radius for `damage`. It cannot miss and cannot overkill. Its DPS
column is *per enemy in radius*, which is why the number looks high and the
tower is still bad at range.

**Beacon** aura, by tier — applies to every tower whose centre is inside the
aura radius, including other Beacons (but a Beacon does not buff itself):

| Beacon tier | Damage | Rate | Range (to buffed towers) | Armour pierce granted |
| --- | --- | --- | --- | --- |
| 1 | +15% | +10% | — | — |
| 2 | +20% | +12% | +10% | — |
| 3 | +25% | +15% | +10% | 50% |

Aura buffs from multiple Beacons **sum** (two tier-1 Beacons = +30% damage) and
are capped with item modifiers by the global caps in `items.md` §Stacking.

## What each tier visibly changes

The charter allows one sprite per tower with an overlay or glyph, not 18 sprites
(`docs/CHARTER.md` §Scope budget). The tier must still be readable in one look
(pillar 3), so every tower carries **both** of these:

| Layer | Rule | Owner |
| --- | --- | --- |
| Tier glyph | 1 / 2 / 3 pips on the base of the silhouette, 2 px each, inked | `art/pixel` |
| Tier overlay | Exactly one added silhouette feature per tier, described below | `art/director` approves `art/pixel`'s version |

| Tower | Tier 2 overlay | Tier 3 overlay | What the player feels change |
| --- | --- | --- | --- |
| Arrow | banner pole beside the door | roof finial + lit brazier | shots come visibly faster; at T3 the range ring gains 24 px |
| Ballista | heavier winch block on the frame | second bolt rail | one bolt now removes a Shieldback instead of denting it |
| Mortar | smoke plume from the barrel | sandbags at the base + wider barrel | the crater visibly widens 8 px per tier |
| Rime | frost crystals along the eaves | hanging icicles + pale glow | the slowed enemy's own tint persists longer |
| Beacon | glass lantern lit in the doorway | second lantern + raised arm | the aura ring is visible and grows |
| Bramble | thorn posts at the corners | a second ring of brambles | the damaged patch visibly widens 4 px per tier |

**Tier deltas are not filler.** Every tier-2 step is +55% to +78% DPS and every
tier-3 step is +51% to +78%, and tier 2 additionally **unlocks the item Relic
slot** (`items.md`). No tier is a 10% nudge.

## DPS per gold — the check that no tower is a reskin

| Tower | T1 DPS | T1 cost | DPS / 100 gold at T1 | DPS / 100 gold at T3 (240–345 gold invested) |
| --- | --- | --- | --- | --- |
| Arrow | 20.0 | 70 | 28.6 | 25.8 |
| Ballista | 28.1 | 110 | 25.5 | 22.0 |
| Bramble (1 enemy) | 15.0 | 60 | 25.0 | 20.9 |
| Mortar (1 enemy) | 11.6 | 100 | 11.6 | 8.9 |
| Rime | 4.4 | 85 | 5.2 | 4.5 |
| Beacon | 0 | 90 | 0 | 0 |

Read this table as the design's honest statement of cost:

- **Arrow is the best raw damage per gold.** That is deliberate: it is the
  tower a new player should reach for, and the one that scales worst in shape.
- **Mortar and Rime look terrible by DPS per gold** because DPS per gold is the
  wrong measure for them. Mortar pays for area (value ≈ 2.5 enemies per shot on
  a swarm wave) and Rime pays for *time*, which is not on this table at all.
  A Rime tower at 30% slow on a 13 s lane adds ~4 s of coverage for every tower
  covering that lane — worth far more than its own 4.4 DPS.
- **Upgrades are slightly worse per gold than new T1 towers** (Arrow: 25.8 vs
  28.6). That is also deliberate. Upgrades buy concentration on a good tile and
  a Relic slot; new towers buy coverage. If playtesters never upgrade, the fix
  is +15% tier-2 damage, *not* removing the Relic slot — the slot is the reason
  the choice exists.
- `GUESS`: the 25.8-vs-28.6 gap. **Would settle it:** in the first full run,
  count towers upgraded to T3 vs towers built at T1. If fewer than half of
  towers are ever upgraded, close the gap.

## Targeting

The three rules are the ones T-0036 implements: **first**, **last**,
**strongest**. Each tower has a default, changeable between waves (never during
one — `docs/CHARTER.md` §Core loop).

| Tower | Default | Why |
| --- | --- | --- |
| Arrow | first | spends its shots where the next enemy will be |
| Ballista | strongest | its whole value is one big hit on the biggest thing |
| Mortar | first | aiming at the leader clumps the followers behind it |
| Rime | first | slowing the leader slows the queue behind it |
| Bramble | n/a | hits everything in radius; the rule is ignored |
| Beacon | n/a | never fires |

`strongest` means most **current** HP, not most max HP, so a damaged sub-boss
drops behind a fresh Shieldback. That is intentional (it keeps the rule
explainable in one sentence) and it is the rule that makes the Bloom
(`enemies.md`) the natural `strongest` target.

## Placing, selling, and the build-phase rule

| Rule | Value | Note |
| --- | --- | --- |
| Placement | between waves only | a refused input must say why (T-0036) |
| Buildable tiles | marked per map, never on the lane | `design/level` owns the tiles |
| Sell refund | 60% of total gold invested in that tower | floor to integer |
| Sell timing | between waves only | same refusal rule as placement |
| Items on sell | returned to the inventory, not sold | the 60% is gold only |
| Tower cap per map | 12 | `GUESS`; a readability limit, not a gold limit |
| Building on a tower with items | refused | `GUESS`; prevents accidental item loss |

Sell values are the `Sell @ 60%` column, so an upgrade is not "free scouting":
buying Arrow→T2→T3 and selling costs 240 − 144 = **96 gold**, which is the price
of changing your mind.

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| Damage 0 (Beacon) | deals 0, never the `max(1, …)` floor | the floor exists for armour, not for a tower with no gun |
| Armour ≥ damage | 1 damage per hit | a tower that does literally nothing is unreadable |
| Pierce ≥ 100% | treated as 100%: armour ignored | prevents negative effective armour granting damage |
| Rate 0 or negative | illegal; loader must reject | division by zero in DPS; a negative rate is a firing loop |
| Range 0 | illegal for all but Bramble at radius ≥ 1 | Range 0 = no targets = a decoration |
| Sell at exactly 0 invested | impossible; a tower always costs ≥ 60 | a free tower is a free reroll of the map |
| Two Beacons buffing each other | allowed, sums, capped | without the cap, 4 Beacons = +60% for 360 gold, which beats every tower |
| Upgrade during a wave | refused with a reason | charter: towers and perks are locked during a wave |
| Selling a tower whose items are equipped | items return first, then gold is paid | order matters if the inventory is full (see `items.md`) |

## Not solving

- **No flying enemies, no anti-air tower.** The slice has one lane plane; a
  flying class would need a second targeting dimension for no pillar gain.
- **No tower auras beyond the Beacon** (no "commander" stacking meta).
- **No per-tower ammo types.** The charter allows behaviour changes during a
  wave; at G2 the only behaviour is target priority.
- **No tower-specific perks** — perks are run-wide and live in
  `reroll-and-offers.md`.
- **No rebalancing of the six tower *counts*.** Six is the charter's scope
  budget; if six proves too many to learn in 30 minutes, the cut is a human
  decision, not a `design/systems` edit.
- **No art.** Overlay descriptions are semantics; `art/director` owns whether
  they read.

## Open questions for the human

1. Should a tier-3 tower show its Relic slot filled differently? Affects whether
   items need their own readable glyph layer on a 64×64 sprite.
2. Sell refund 60% or 50%? 60% makes swapping towers a real strategy; 50% makes
   the first placement a commitment. This is a taste call with a big effect on
   pillar 1.
3. Is a 12-tower cap per map acceptable, given a 32 px tile grid and a lane that
   needs to stay legible?
