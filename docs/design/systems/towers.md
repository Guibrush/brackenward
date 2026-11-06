# Towers — 6 towers, 3 tiers, an inventory you place for free

> **G2 PLACEHOLDER.** Every number in this file is a theory-crafting default written
> before the slice exists, not a measurement. Nothing here is validated until a human
> plays a full run (G2.2). Rows marked `GUESS` have no data behind them; the last
> column names the observation that would replace the guess.

Owner: `design/systems`. Rewritten at T-0038, 2026-11-06. Supersedes T-0035 entirely.

- **Number home.** This file owns tower stats (damage, rate, range, splash, slow),
  tier-up costs, the tier-1 acquisition price, the upgrade-slot count, and the
  duplicate and permanence rules for upgrades. `store.md` derives store prices from
  the `Path cost` column here; `economy.md` cites gold; `items.md` owns upgrade effects.
- **Names are working labels.** Naming belongs to `design/narrative`.
- **What T-0038 changed.** The old model charged gold per *placement* and refunded 60%
  on sell. That model is dead. Towers are now **items in an inventory**; **placement is
  free**; gold buys **acquisition** and **tiers**. §What changed is the migration table.

## `DATADRIVEN` — the marker in this file

**`DATADRIVEN`** marks a named field that is meant to be tuned by changing data, never
by changing code. A row marked `DATADRIVEN` must be reachable from the tuning file with
no rebuild. The value shown is a theory-crafting default, not a commitment.

A value that is *not* marked `DATADRIVEN` may still change, but changing it changes the
shape of the game, so it needs a design decision first.

## What changed from the T-0035 model

| Concern | T-0035 (dead) | T-0038 (this file) |
| --- | --- | --- |
| How a tower exists | Bought and built in one action, on a tile | **Acquired** as an inventory copy (gold), then **placed** on a tile (free) |
| What gold buys | Placement cost, upgrade cost, heal, reroll, store | **Store items, rerolls, tower tiers, upgrade tiers** — never placement, never equipping |
| Reconfiguration | Sell for 60%, buy again | **Free**: pick up, place elsewhere, re-equip, between waves and between levels |
| A second tower of the same type | Impossible (6 types, 6 towers) | **Allowed**: duplicates are a normal purchase |
| Tier axis | Towers only | **Two axes**: tower tier (1–3) and each upgrade's tier (1–3) |
| When tiers are bought | Any build phase after buying | **In-level between waves only**, on the build screen |
| Upgrades | Equipped and unequipped freely, refunded to the inventory | **Permanent for the run**; a replaced upgrade is destroyed; a removal switch exists but ships off |
| Difficulty response | Layout cost re-paid each level | **Level index only**; no anti-snowball, broken builds are the point |

The cost *arithmetic* did not change: the old `Invested` column (cost to reach a tier)
is exactly the new `Path cost`. What changed is **when and where** gold leaves the
player's hands.

## Units and rounding

| Quantity | Unit | Rounding | Why it matters |
| --- | --- | --- | --- |
| Damage | integer HP per hit | floor after modifiers | two identical towers must not round differently |
| Rate | seconds between shots | 2 decimals | derived DPS must be reproducible by hand |
| DPS | damage ÷ rate | 1 decimal | a check column, never a stored value |
| Range | px radius, centre to centre | integer | tile-relative arithmetic stays exact on a 32 px grid |
| Gold | integer | integer | no fractional gold anywhere in the economy |
| Slow | % of move speed, seconds | integer % | `enemies.md` owns the stacking rule |
| Tier | 1, 2 or 3 | integer | `0` and `4` are illegal, not "uncapped" |

**Armour interaction** (the rule that decides every "why did that tower stop working"
question; `enemies.md` owns the enemy armour values):

    effective_armour = round(armour × (1 − pierce))
    applied          = damage > 0 ? max(1, damage − effective_armour) : 0

The `max(1, …)` floor is load-bearing: without it a 6-damage tower against 6 armour does
nothing at all and the player cannot tell why (pillar 3).

## The six towers, one line each

| Tower | Identity in one line | Verb it owns | Design job (pillar) |
| --- | --- | --- | --- |
| Arrow | Cheap, fast, unglamorous; the tower you can always afford. | shoot one thing | the baseline every other tower is read against (P3) |
| Ballista | Long reach, one heavy bolt, ignores half the armour. | delete one thing | the answer to armour and to the far side of the lane (P2) |
| Mortar | Slow lob, hits a clump; useless against a single file. | hit an area | makes swarms a choice instead of a chore (P2) |
| Rime | Barely scratches; makes everything in range slower. | buy time | converts gold into seconds, the cheapest way to make a bad line hold (P2) |
| Beacon | Never fires. Makes the towers around it better. | multiply a cluster | the reason to build a shape rather than a queue (P1, P2) |
| Bramble | Very short reach, chews everything standing on it. | hold a patch | the cheap, high-DPS, high-risk tile (P1) |

No tower is a reskin of another: each owns a different verb, and the two that share
"damage" (Arrow, Bramble) differ by 2× in range and by single-target versus area.

## The 3-tier table

`Acquire` is the **tier-1** price: what a copy costs to put in the inventory.
`Tier-up` is the cost of moving an *owned* copy up one tier, paid in-level.
`Path cost` is `Acquire + all tier-ups` — the total gold in one copy at that tier, and
the number `store.md` multiplies to get a store price.

| Tower | Tier | Damage | Rate (s) | DPS | Range (px) | Splash (px @ %) | Slow | Acquire | Tier-up | Path cost |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Arrow | 1 | 10 | 0.50 | 20.0 | 96 | — | — | 70 | — | 70 |
| Arrow | 2 | 16 | 0.46 | 34.8 | 108 | — | — | — | 60 | 130 |
| Arrow | 3 | 26 | 0.42 | 61.9 | 120 | — | — | — | 110 | 240 |
| Ballista | 1 | 45 | 1.60 | 28.1 | 160 | — | — | 110 | — | 110 |
| Ballista | 2 | 70 | 1.55 | 45.2 | 176 | — | — | — | 85 | 195 |
| Ballista | 3 | 110 | 1.45 | 75.9 | 192 | — | — | — | 150 | 345 |
| Mortar | 1 | 22 | 1.90 | 11.6 | 120 | 36 @ 100% | — | 100 | — | 100 |
| Mortar | 2 | 34 | 1.85 | 18.4 | 132 | 44 @ 100% | — | — | 80 | 180 |
| Mortar | 3 | 50 | 1.75 | 28.6 | 144 | 52 @ 100% | — | — | 140 | 320 |
| Rime | 1 | 4 | 0.90 | 4.4 | 104 | — | 30% / 1.2 s | 85 | — | 85 |
| Rime | 2 | 7 | 0.90 | 7.8 | 112 | — | 40% / 1.4 s | — | 65 | 150 |
| Rime | 3 | 10 | 0.85 | 11.8 | 120 | — | 50% / 1.6 s | — | 115 | 265 |
| Beacon | 1 | Ø | — | 0 | 128 (aura) | — | — | 90 | — | 90 |
| Beacon | 2 | Ø | — | 0 | 144 (aura) | — | — | — | 70 | 160 |
| Beacon | 3 | Ø | — | 0 | 160 (aura) | — | — | — | 120 | 280 |
| Bramble | 1 | 6 | 0.40 | 15.0 | 48 (damage radius) | all in radius | — | 60 | — | 60 |
| Bramble | 2 | 10 | 0.38 | 26.3 | 52 (damage radius) | all in radius | — | — | 50 | 110 |
| Bramble | 3 | 15 | 0.35 | 42.9 | 56 (damage radius) | all in radius | — | — | 95 | 205 |

`GUESS` every cost and every stat. **Would settle it:** the acquisition ledger in
`economy.md` §Run-level check — if a run ends with more than one store's stock unspent,
`Path cost` is too low for the income curve, and the dial is `Acquire`, not the tier-ups.

**Ballista pierce** is 50% at all tiers, and 0% for every other tower except a
Beacon-tier-3 buff. It is the Ballista's identity, so it does not grow with tier.

**Bramble** has no projectile: every `rate` seconds it damages **every** enemy inside its
radius for `damage`. It cannot miss and cannot overkill. Its DPS column is *per enemy in
radius*, which is why the number looks high and the tower is still bad at range.

**Beacon** aura, by tier — applies to every tower whose centre is inside the aura radius,
including other Beacons (but a Beacon does not buff itself):

| Beacon tier | Damage | Rate | Range (to buffed towers) | Armour pierce granted |
| --- | --- | --- | --- | --- |
| 1 | +15% | +10% | — | — |
| 2 | +20% | +12% | +10% | — |
| 3 | +25% | +15% | +10% | 50% |

Aura buffs from multiple Beacons **sum** (two tier-1 Beacons = +30% damage) and are
bounded with item modifiers by the global caps in `items.md` §Stacking.

## A tower copy is one placeable instance

This is the sentence the whole economy hangs on. If it is misread, every number below is
wrong.

| Rule | Statement |
| --- | --- |
| A copy is an instance | Buying "Arrow" puts **one** Arrow in the inventory. It can be placed **once** |
| Placing a second Arrow | Requires a **second Arrow copy**, not a second tile |
| Tiers live on the copy | A tier-2 copy is a distinct object from a tier-1 copy; both may sit in the inventory |
| Upgrades live on the placed tower | A copy's upgrades travel with the copy, not with the tile |
| Removing a tower | The copy (with tier and upgrades) returns to the inventory. **No gold moves.** There is no sell refund and no sell penalty |
| Copies are not consumed by a level | The same copy is placed again on the next level, on that level's tiles |
| Inventory cap | **`inventory_cap = 0`** (0 = uncapped), `DATADRIVEN` — the cap exists in the rules and ships disabled |
| Tower copies on one map | **`tower_cap_per_map = 12`**, `DATADRIVEN` — a readability limit, not a gold limit |

**Duplicates are the design, not a bug.** Six tower *types* with an unlimited number of
*copies* means a player may own five Arrows and never a Mortar. That is a legal build, and
if it loses, it lost to a choice (pillar 1). Never add an "own one of each" rule.

**Placement is free, so tiles are the power cap.** The number of **active tiles** on a map
(`design/level` owns the map data; a standard map carries 8–12) is now the binding limit on
how many towers a player can field, not gold. See `nodes.md` §Active tiles.

## The two tier axes

The axes are independent. Axe A is the tower's own tier. Axe B is the tier of each upgrade
applied to it. Neither requires the other, with one exception: the Relic slot needs tower
tier 2 (`items.md`).

| Axis | Tiers | Bought | Paid from | Cost ladder |
| --- | --- | --- | --- | --- |
| Tower tier | 3 | In-level, between waves, on the build screen | Gold, `Tier-up` column | 50–150 per step |
| Upgrade tier | 3 | In-level, between waves, on the build screen | Gold | Rune 45 / 80; Relic 70 / 120 |

| Rule | Statement | Why |
| --- | --- | --- |
| Tier purchase timing | **Between waves, in-level only.** Never at a store, never on the map | The mid-level decision needs a buyer; the store is the acquisition decision |
| Store-sold tiers | A store may stock a **tier-2 or tier-3 copy**. The tier is part of the purchase; it is not a "tier purchase" | Letting the store sell a tier is the premium in `store.md` |
| Downgrading | Illegal, at any time, by any path | A refundable tier is a free reroll of every tier decision |
| Tier on an unplaced copy | Legal: tier it up in the inventory, place it later at that tier | Reconfiguration is free; the player should not have to re-place |
| Tier during a wave | Refused with a reason | charter: towers are locked during a wave |
| Two copies, one tiered | The other stays at its own tier | Tiers are per copy, never per type |

**Upgrade tier effect.** An upgrade's tier scales the *magnitude* of its own effect, and
leaves its **penalty flat** (`items.md` §The 20 items owns each effect and each cost):

| Upgrade tier | Effect multiplier | Penalty multiplier | Tier-up cost (Rune / Relic) |
| --- | --- | --- | --- |
| 1 | ×1.00 | ×1.00 | — |
| 2 | ×1.55 | ×1.00 | 45 / 70 |
| 3 | ×2.10 | ×1.00 | 80 / 120 |

A flat penalty against a growing effect is deliberate: gold is the price of growth, so a
tier-3 rune is a *worse deal per gold* than the tier-1 of a different rune but a *better
use of a slot*. The `items.md` dominance check compares items at **equal tier**; it is not
invalidated by this ladder.

`GUESS` the ×1.55 / ×2.10 steps. **Would settle it:** count how often a player with gold
to spare tiers an *upgrade* rather than a *tower*. Below 25%, the steps are too small and
the ladder should be ×1.7 / ×2.5.

## Upgrade slots, duplicates, permanence

| Rule | Value | Marker |
| --- | --- | --- |
| Slots per tower | **2** | `upgrade_slots_per_tower = 2`, `DATADRIVEN` — 1–3 is a legal range; above 3 a tooltip stops being readable |
| Slot 1 accepts | Rune-type upgrades, any tier | `items.md` |
| Slot 2 accepts | Relic-type upgrades, tower tier ≥ 2 | `items.md` |
| Duplicate upgrade on one tower | **Allowed** — two copies of the same upgrade in the two slots | `allow_duplicate_upgrade_on_same_tower = true`, `DATADRIVEN` |
| Duplicate upgrade across towers | Allowed without limit | — |
| Applying an upgrade | Free of gold. Occupies a slot | charter: equipping is not a gold sink |
| Permanence | **An applied upgrade is permanent for the run** | `upgrades_permanent = true`, `DATADRIVEN` |
| Replacing an applied upgrade | Legal in-level between waves. **The replaced upgrade is destroyed** | — |
| Removal switch | The rules must expose a removal path, **shipped disabled** | `upgrade_removal_enabled = false`, `DATADRIVEN` |
| Moving an upgrade between towers | Illegal while `upgrade_removal_enabled = false` | see §Open questions |

**Duplicates stack additively, once.** Two tier-1 Whetstones on one tower are +50% damage
and −20% rate, summed once per `items.md` §Stacking rule 1, then bounded by the global caps
(damage ×2.5, rate ×2.0). The caps are what make the duplicate toggle safe: without them,
two tier-3 Whetstones would be +262% damage on one tower.

**Permanence is a decision, not a punishment.** Because applying is free and irreversible,
the build phase has a real second decision ("is this the tower that gets the Relic?") that
survives the whole run. The replacement rule keeps a mistake recoverable at the price of
the upgrade itself, which is why the switch exists: if playtests say the loss is invisible,
flip `upgrade_removal_enabled` and measure again.

## What each tier visibly changes

The charter allows one sprite per tower with an overlay or glyph, not 18 sprites. The tier
must still be readable in one look (pillar 3), so every tower carries both layers:

| Layer | Rule | Owner |
| --- | --- | --- |
| Tower tier glyph | 1 / 2 / 3 pips on the base of the silhouette, 2 px each, inked | `art/pixel` |
| Tower tier overlay | Exactly one added silhouette feature per tier, below | `art/director` approves |
| Upgrade tier mark | A ring on the slot's item mark: 1 / 2 / 3 segments | `art/director` — **unresolved**, see Open questions |

| Tower | Tier 2 overlay | Tier 3 overlay | What the player feels change |
| --- | --- | --- | --- |
| Arrow | banner pole beside the door | roof finial + lit brazier | shots come visibly faster; at T3 the range ring gains 24 px |
| Ballista | heavier winch block on the frame | second bolt rail | one bolt now removes a Shieldback instead of denting it |
| Mortar | smoke plume from the barrel | sandbags at the base + wider barrel | the crater visibly widens 8 px per tier |
| Rime | frost crystals along the eaves | hanging icicles + pale glow | the slowed enemy's own tint persists longer |
| Beacon | glass lantern lit in the doorway | second lantern + raised arm | the aura ring is visible and grows |
| Bramble | thorn posts at the corners | a second ring of brambles | the damaged patch visibly widens 4 px per tier |

**Tier deltas are not filler.** Every tier-2 step is +55% to +78% DPS and every tier-3 step
is +51% to +78%. No tier is a 10% nudge.

## Value per gold — now measured against the path

| Tower | T1 DPS | Acquire | DPS / 100 gold at T1 | T3 DPS | Path cost at T3 | DPS / 100 gold at T3 |
| --- | --- | --- | --- | --- | --- | --- |
| Arrow | 20.0 | 70 | 28.6 | 61.9 | 240 | 25.8 |
| Ballista | 28.1 | 110 | 25.5 | 75.9 | 345 | 22.0 |
| Bramble (1 enemy) | 15.0 | 60 | 25.0 | 42.9 | 205 | 20.9 |
| Mortar (1 enemy) | 11.6 | 100 | 11.6 | 28.6 | 320 | 8.9 |
| Rime | 4.4 | 85 | 5.2 | 11.8 | 265 | 4.5 |
| Beacon | 0 | 90 | 0 | 0 | 280 | 0 |

Read this as the design's honest statement of cost:

- **Arrow is the best raw damage per gold.** Deliberate: it is the tower a new player
  reaches for, and the one that scales worst in shape.
- **Mortar and Rime look terrible by DPS per gold** because DPS per gold is the wrong
  measure. Mortar pays for area (≈2.5 enemies per shot on a swarm); Rime pays for *time*,
  which is not on this table at all. A Rime at 30% slow on a 13 s lane adds ~4 s of
  coverage for every tower covering that lane.
- **Tiering a copy is slightly worse per gold than acquiring a second copy** (25.8 vs
  28.6). Also deliberate, and it is now a *supply* question as well: a copy costs a store
  slot, a tier costs gold. If playtesters never tier, the fix is +15% tier-2 damage, not
  removing the upgrade slots.

## Targeting

The three rules are **first**, **last**, **strongest**. Each tower has a default, changeable
between waves (never during one — charter).

| Tower | Default | Why |
| --- | --- | --- |
| Arrow | first | spends its shots where the next enemy will be |
| Ballista | strongest | its whole value is one big hit on the biggest thing |
| Mortar | first | aiming at the leader clumps the followers behind it |
| Rime | first | slowing the leader slows the queue behind it |
| Bramble | n/a | hits everything in radius; the rule is ignored |
| Beacon | n/a | never fires |

`strongest` means most **current** HP, not most max HP, so a damaged sub-boss drops behind
a fresh Shieldback. Intentional: it keeps the rule explainable in one sentence, and it makes
the Bloom (`enemies.md`) the natural `strongest` target.

## Reconfiguration — the free verb

| Action | Cost | When | Notes |
| --- | --- | --- | --- |
| Place a tower copy on an active tile | **0** | between waves, between levels | the tile must be active and empty |
| Pick a tower back up | **0** | between waves, between levels | the copy returns with tier and upgrades |
| Move a tower to another tile | **0** | between waves | one pick-up, one place |
| Re-apply targeting priority | **0** | between waves | locked during a wave |
| Apply an upgrade | **0** gold | between waves | the upgrade leaves the inventory permanently |
| Tier up a tower or an upgrade | Gold | **in-level between waves only** | the only gold action on the build screen |
| Anything during a wave | Refused | — | the refusal must name the reason (T-0036 keeps this) |

Because placement is free, **there is no sell.** The old 60% refund, its rounding rule, and
its "upgrade is not free scouting" arithmetic are deleted. A player who wants a different
layout picks towers up and puts them down; the only thing a change of mind costs is the
tier gold already spent, which is the intended and legible price.

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| Inventory cap reached (`inventory_cap > 0`) | A purchase is refused with a reason before gold moves | a silent loss is the worst outcome in an inventory game |
| Inventory cap 0 | Means **uncapped**, never "full" | the shipped default; `0 = full` is the classic off-by-one |
| Placing a copy twice | Refused: one copy, one tile | the copy is an instance, not a type |
| No active tile free | Placement refused with a reason; the copy stays in the inventory | the tile count, not gold, is the cap |
| Tower cap reached (12) | Placement refused with a reason | same |
| Damage 0 (Beacon) | Deals 0, never the `max(1, …)` floor | the floor exists for armour, not for a tower with no gun |
| Armour ≥ damage | 1 damage per hit | a tower that does literally nothing is unreadable |
| Pierce ≥ 100% | Treated as 100%: armour ignored | negative effective armour would *add* damage |
| Rate 0 or negative | Illegal; the loader rejects | division by zero in DPS |
| Range 0 | Illegal for all but Bramble at radius ≥ 1 | range 0 = no targets = decoration |
| Tier 0, tier 4, non-integer tier | Illegal; the loader rejects | the ladder is closed at both ends |
| Tier up a copy that is placed | Legal, between waves; the placed tower updates | the player should not have to pick it up |
| Tier up with exactly enough gold | Allowed; balance hits 0 | refusing an exact buy is the classic economy bug |
| Two copies of the same upgrade on one tower | Allowed while the duplicate toggle is on; refused when off | the toggle is the rule |
| Duplicate upgrade with a capped buff | Buff clamps at the global cap; **both penalties still apply** | `items.md` stacking rule 3 |
| Replace an applied upgrade | The new one takes the slot; the old is destroyed | permanence |
| Remove an upgrade while `upgrade_removal_enabled = false` | Refused with a reason | the switch exists so this can be answered without code |
| Upgrade applied, then the tower copy is removed from the board | The upgrade travels with the copy | upgrades live on the copy, not the tile |
| Beacon buffing itself | Never | a self-buff makes a lone Beacon a tower |
| Two Beacons buffing each other | Allowed, sums, capped | without the cap, 4 Beacons = +60% for 360 gold, beating every tower |

## Not solving

- **No flying enemies, no anti-air tower.** One lane plane; a flying class buys no pillar.
- **No tower auras beyond the Beacon.**
- **No per-tower ammo types.** At G2 the only behaviour change is target priority.
- **No tower-specific perks.** Perks are run-wide (`reroll-and-offers.md`).
- **No sell, no refund, no trade-in.** Deleted with the placement cost model.
- **No rebalancing of the six tower *types*.** Six is the charter's scope budget.
- **No art.** Overlay descriptions are semantics; `art/director` owns whether they read.
- **No change to `items.md`'s catalogue.** This file supersedes `items.md` §The slot model
  (duplicate, unequip and inventory-size rows) and nothing else.

## Open questions for the human

1. **Can an applied upgrade be moved to another tower?** The brief says equipping is free
   and also that applied upgrades are permanent. This file reads those together as
   "**free to apply, permanent once applied**", with a replacement destroying the old
   upgrade. The alternative reading — free to move forever, destroying only on overwrite —
   is a one-field flip (`upgrade_removal_enabled`). It changes whether upgrades are
   resources or furniture.
2. **Should the upgrade tier read on the sprite at all?** Two axes of tier on one 64×64
   sprite is a lot of marks. Pillar 3 says show it; the canvas says pick one. This is an
   `art/director` question with a design cost.
3. **Is 12 copies per map the right readability cap**, given a 32 px grid and a lane that
   must stay legible? The tile count already caps at 8–12 per map, so this may be dead.
