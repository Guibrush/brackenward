# Tower items — 20 items, 2 slots, no item wins everywhere

> **G2 PLACEHOLDER.** Every number in this file is a guess made before the slice
> exists. Nothing here is validated until a human plays a full run (G2.2). Rows
> marked `GUESS` have no data behind them; the last column names what would
> replace the guess.

Owner: `design/systems`. As of T-0035, 2026-11-06.

> **PARTLY SUPERSEDED AT T-0038.** The effects, costs and global caps below still
> stand. Three things no longer do, and `towers.md` wins where they disagree:
> §The slot model's "unequipping is free and returns the item to the inventory"
> (applied upgrades are now **permanent for the run**, and a replaced upgrade is
> destroyed), its inventory-size row (see `towers.md` `inventory_cap`), and
> §Acquisition's "store" row (the store is now `store.md`, five tier-weighted
> slots). Upgrades also now have **3 tiers** (`towers.md` §The two tier axes,
> ×1.00 / ×1.55 / ×2.10 on the effect, penalty flat), which this catalogue has not
> yet been re-expressed for. A follow-up `design/systems` task owns that pass.

- **Number home.** This file owns item effects, slot rules, stacking rules and
  the global modifier caps. Dropping rates live in `reroll-and-offers.md`;
  tower base stats in `towers.md`.
- **The rule this file exists to enforce:** *no item may be strictly better than
  another at everything.* Every item below pays for what it gives, and the
  §Dominance check names the price.

## The slot model

| Slot | Unlocked at | Count per tower | What may go in it |
| --- | --- | --- | --- |
| **Rune** | tier 1 | 1 | numeric modifiers (`R` in the table) |
| **Relic** | **tier 2** | 1 | behavioural changes (`L` in the table) |

Two slots per tower, never more. **Tier 2 unlocking the Relic slot is the reason
to upgrade** (`towers.md` §DPS per gold): a tier-1 tower with a 34 DPS body and
no behaviour loses to a tier-2 tower with 61 DPS and a Chain Link.

| Rule | Statement |
| --- | --- |
| Equipping | between waves only; locked during a wave (charter) |
| Unequipping | between waves only, free, item returns to the inventory |
| Moving between towers | one unequip + one equip, both between waves |
| Duplicates on one tower | **forbidden** — one copy of each named item per tower |
| Duplicates across towers | allowed without limit (six Whetstones on six towers is legal) |
| Items on sell | returned to the inventory; not refunded in gold (`towers.md`) |
| Inventory size | unlimited at G2 (`GUESS`; a cap is a G3 question) |
| Items per tower totals | never more than 2, so a tooltip is never longer than two lines |

## The 20 items

`Effect` applies to the equipped tower. `Cost` is what the player gives up — it
is not optional, and it is the whole reason the item is a choice.

### Runes — numeric modifiers (12)

| ID | Item | Effect | Cost | Suits | Hook |
| --- | --- | --- | --- | --- | --- |
| I-01 | Whetstone | +25% damage | −10% fire rate | ST, AR | stats only |
| I-02 | Greased Winch | +20% fire rate | −10% damage | AR, CS | stats only |
| I-03 | Long Eye | +30% range | −10% damage | ST, CS | stats only |
| I-04 | Heavy Bolt | +40% damage | −20% range | ST | stats only |
| I-05 | Split Case | attacks splash 28 px for 60% damage | −15% damage | ST | per-shot |
| I-06 | Piercer | 50% armour pierce | −15% fire rate | ST | per-shot |
| I-07 | Rime Coat | hits apply a 20% slow for 1.0 s | −20% damage | AR (many hits) | per-shot |
| I-08 | Ember Load | hits burn for 3 damage/s for 2 s; does not stack | −25% damage | AR | per-shot + tick |
| I-09 | Toll | +2 gold per kill this tower makes | −20% damage | any | on-kill |
| I-10 | Short Brace | +10 flat damage per hit | −25% fire rate | ST vs armour | stats only |
| I-11 | Vantage | +20% damage against targets further than 96 px | −10% fire rate | ST | per-shot |
| I-12 | Crowd Sigil | +6% damage per other tower within 96 px, max +30% | −10% range | CS | recompute on build |

### Relics — behavioural changes (8)

| ID | Item | Effect | Cost | Suits | Hook |
| --- | --- | --- | --- | --- | --- |
| I-13 | Chain Link | a hit arcs to 1 extra enemy for 40% damage | −10% damage | ST | per-shot |
| I-14 | Sniper's Mark | the target takes +15% damage from all sources for 1.5 s | −10% fire rate | ST | per-shot + aura |
| I-15 | Banner | other towers within 96 px gain +8% damage | this tower deals −10% damage | CS | aura |
| I-16 | Overwatch | +30% fire rate for 5 s after any leak | nothing while the line holds | AR | on-leak |
| I-17 | Last Stand | +1% fire rate per HQ point lost, cap +25% | a dead stat at full HQ | any | HQ read |
| I-18 | Vigil | +3 damage on the first shot after 3 s with no target | −5% damage | ST | per-shot |
| I-19 | Twin Shot | fires two shots at 60% damage each | worse against armour (two hits pay armour twice) | AR | per-shot |
| I-20 | Ward Stone | enemies in range move 10% slower | −20% damage | CS | aura |

`GUESS` every magnitude. **Would settle it:** the pick rate. An item taken in
under 10% of offers is priced too high; over 60% is priced too low. The first
run should move no more than three items, or the table is noise.

## Stacking — the four rules that stop the numbers exploding

1. **Same stat, additive, once.** Every percentage modifier to the same stat
   sums first, then multiplies the base once. `+25%` and `+20%` damage is `+45%`,
   not `×1.5×`. Aura buffs (Beacon, Banner, Crowd Sigil) are in the same sum.
2. **Global caps** (applied after summing, before armour):

   | Stat | Cap | Why the cap is there |
   | --- | --- | --- |
   | damage multiplier | ×2.5 | beyond this a single tower one-shots sub-bosses and the wave curve stops mattering |
   | fire-rate multiplier | ×2.0 | beyond this the shot interval is under two frames and reads as an error |
   | range multiplier | ×2.0 | a tower covering the whole lane removes placement as a decision |
   | accumulated slow on one enemy | 60% | 100% slow is a permanent stop, which is a different game |
   | armour pierce | 100% | negative effective armour would *add* damage (see `towers.md`) |

3. **Penalties are not capped and do not stack away.** A penalty applies at full
   value even if the buff it came with is capped. Otherwise capping a buff
   quietly cancels the cost.
4. **Duplicates forbidden on one tower, so no item can be stacked with itself.**
   The only stacking is across towers and across *different* items, which the
   caps bound.

## Dominance check — no item wins at everything

Each row below is a pair that could collapse into "one is better". The third
column is the case where the *weaker-looking* item wins.

| Pair | The apparent winner | Where the other one wins |
| --- | --- | --- |
| Whetstone (I-01) vs Heavy Bolt (I-04) | Heavy Bolt: more damage for one item | Whetstone keeps range and rate, so it works on a Mortar; Heavy Bolt at −20% range does not reach the lane on many tiles |
| Greased Winch (I-02) vs Whetstone (I-01) | Whetstone: rate is a multiplier on damage anyway | against Swarmlings and Bloomy packs, more *shots* means more separate hits, and rate also re-applies Rime Coat and Ember Load |
| Long Eye (I-03) vs Heavy Bolt (I-04) | Heavy Bolt, on a Ballista | Long Eye on a Beacon (+10% range to every tower in aura) or a Bramble placed one tile further from the lane |
| Piercer (I-06) vs Short Brace (I-10) | Piercer, against a Bulwark | Short Brace against many small enemies: +10 flat beats −15% rate when the base damage is 6 |
| Split Case (I-05) vs Ember Load (I-08) | Ember Load: damage over time never misses | Split Case against a single file of Runners: 60% of a big hit lands now, a burn ticks after the enemy has passed the tower |
| Toll (I-09) vs Whetstone (I-01) | Whetstone: kills pay more than tolls | a Poison/Toll build on a lane the player is losing: gold now is a tower sooner |
| Twin Shot (I-19) vs Greased Winch (I-02) | Winch: same DPS, no downside | Twin Shot against Swarmlings (two separate kills per volley) and with Rime Coat (two slow applications) |
| Banner (I-15) vs Beacon | Beacon: bigger aura, no self-penalty | Banner on a tower that is already placed inside a cluster and cannot afford a second tower (90 gold) |

If two items ever end up with the same "gives" and the same "cost", cut one.
Twenty items is the charter's budget, not a quota to fill.

## Acquisition

| Source | Pool | Rate | Why |
| --- | --- | --- | --- |
| In-level drop | **Runes only** | one per level, on the wave at `ceil(waves × 0.75)` — w5 of 6, w6 of 7, w6 of 8 | runes are toys that reinforce; the charter says drops reinforce |
| Between-level offer | Runes and Relics | 1 of 3 offers is an item, weighted | relics define a build, so they come from the choice, not the drop |
| Store | Runes and Relics | 3 shelves, 60/75/90 gold | see `reroll-and-offers.md` |

A drop is **not a choice**: it goes to the inventory (charter: "waves drop gold
and, rarely, upgrades or perks that go straight to the inventory without a
choice"). The player chooses what to equip it to, which is where the decision
lives.

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| Equipping a Relic on a tier-1 tower | refused with a reason; the slot does not exist yet | silently dropping an item is the worst possible outcome |
| Equipping during a wave | refused with a reason | charter locks towers and perks during a wave |
| The same item offered twice in one offer set | legal; two copies = two towers' worth | refusing would make the pool feel smaller than it is |
| Two copies on the *same* tower | refused | the duplicate rule, enforced at equip time, not at offer time |
| Damage reduced to 0 or below by penalties | floor the **multiplier** at 0.1× base, never 0 | a 0-damage tower is a bug the player will report as "my tower stopped working" |
| Penalty applied when the buff is capped | penalty still applies in full | see stacking rule 3 |
| Rime Coat on a Bramble | allowed: every tick applies a slow to everything in radius | this is strong but the inventory cost is one of Bramble's two slots |
| Ember Load on a Mortar | allowed: the burn applies to the splash targets | intended; the burn does not stack beyond one instance per enemy |
| Item on a tower that is sold | item returns to inventory **before** gold is paid | an item lost to a sell is an unrecoverable player loss |
| All 20 items owned | offers stop offering items; weight redistributes to perks/towers | see `reroll-and-offers.md` §Pool exhaustion |
| A Relic that reads HQ (I-17) at 0 HQ | the run is already over; no evaluation | avoid a divide or a negative multiplier at the defeat frame |

## Not solving

- **No item upgrading or combining.** Twenty items, flat.
- **No item rarity beyond the store's three prices.** A rarity system that does
  not change behaviour is a UI cost with no design return.
- **No items that target the HQ or the map** (no "towers cost less", no "extra
  buildable tile"). Those are *perks*, and perks belong to the between-level
  choice, not the tower.
- **No negative items, no cursed items.** A trap on a random drop punishes the
  player for the RNG, not for the choice.
- **No synergy table.** The interactions that matter (Rime Coat + Bramble, Ember
  Load + Mortar) are emergent from the rules above and must not be enumerated in
  code.

## Open questions for the human

1. **Runes from drops, Relics from offers** is a deliberate split. Does it make
   the between-level choice feel more important, or does it make the wave drop
   feel like filler? This is the pillar-1 question in item form.
2. Twelve of the twenty need a per-shot hook (Split Case, Rime Coat, Ember Load,
   Chain Link, Vigil, Twin Shot…) and eight are stat-only. If the slice is cut
   for time, **ship the eight stat-only items plus I-09 and I-19**, which is 10
   items — half the charter's 20. That is a scope call, not a design call.
3. Should an equipped item show on the tower sprite (a tiny mark), or only in
   the inspect panel? Pillar 3 argues for a mark; the 64×64 canvas argues
   against it.
