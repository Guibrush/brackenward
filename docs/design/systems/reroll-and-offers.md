# Offers and rerolls — the between-level choice

> **G2 PLACEHOLDER.** Every number in this file is a guess made before the slice
> exists. Nothing here is validated until a human plays a full run (G2.2). Rows
> marked `GUESS` have no data behind them; the last column names what would
> replace the guess.

Owner: `design/systems`. As of T-0035, 2026-11-06.

> **PARTLY SUPERSEDED AT T-0038.** The **offer-set** reroll ladder (30 / 45 / 60),
> the offer weights and the perks below still stand, and the ladder now applies to
> **event nodes and the starting loadout** (`nodes.md`). §Store is superseded
> entirely by `store.md` (five tier-weighted slots, a per-site reroll toggle, its
> own 25 / 40 / 55 ladder and a second-half guarantee). This file's reroll ladder
> governs **offer sets only**; `store.md`'s governs **store visits**. A follow-up
> `design/systems` task owns moving the offer set onto the node model.

- **Number home.** This file owns offer counts, offer weights, reroll prices,
  perk values and store prices. Item effects live in `items.md`; tower and
  upgrade costs in `towers.md`; gold income in `economy.md`.
- **This is the pillar-1 system.** The charter says the run *is* the build and
  that between-level offers cannot be skipped, only rerolled. So the 90 seconds
  spent here is the game's thesis. Every number below should be judged by
  whether it makes that choice slow.

## Where the choice sits in the loop

| Step | When | Skippable | Costs gold |
| --- | --- | --- | --- |
| 1. Level completes (or a boss is killed) | level end | — | — |
| 2. **Offer set** — 3 options, pick exactly 1 | immediately | **never** | no (the pick is free) |
| 3. Optional store visit | after the pick | yes | yes |
| 4. Optional heals | after the pick | yes | yes, 40 per +5 HQ |
| 5. Next level | — | — | — |

"Not skippable" is enforced in code, not in the UI: there is no cancel. A player
who dislikes all three must reroll or take one.

## The offer set

| Property | Value | Reason |
| --- | --- | --- |
| Offers per set | **3** | three is the smallest number that makes "the best of two bad options" possible; four is a list, not a choice |
| Picks | exactly 1 | charter |
| Duplicates within a set | forbidden | two identical offers is one offer and a wasted slot |
| Rerolls per set | **3** maximum | a cap keeps the gold decision real; see §Reroll |
| Set generated | at the moment the level ends | so the guarantee below can read the current build |

## Weights

Each offer slot draws a category, then an item from that category. Weights are
relative and **renormalised over the categories that are still legal** (a
category with nothing left to offer is removed and its weight redistributed
proportionally).

| Category | Weight | Legal when | Notes |
| --- | --- | --- | --- |
| **New tower** | 30 | at least one of the 6 towers is unowned | this is how a build acquires a verb |
| **Rune item** | 25 | the Rune pool has an item not already owned ×2 | `items.md` I-01…I-12 |
| **Relic item** | 15 | the Relic pool has an item not already owned ×2 | `items.md` I-13…I-20 |
| **Perk** | 20 | at least one perk in the pool is unowned | run-wide modifiers, §Perks |
| **Heal** | 10 | HQ is below max | +5 HQ, free of charge as a perk-style offer |

`GUESS` all five weights. **Would settle it:** in the first run, record which
category each pick came from. If new towers are taken more than 50% of the time,
the build is starving for verbs and the tower weight is right; if items are
taken more than 60% of the time, towers are too expensive to buy and the offer
is the only way to spend gold.

### Guarantees (beyond the weights)

| Guarantee | Rule | Why |
| --- | --- | --- |
| First verb | until the player owns **4** tower types, at least **one** offer is an unowned tower | the run must be able to grow in more than one direction before level 4 |
| Something to slot | until the player owns **3** items, at least one offer is an item | an item slot with nothing to put in it is a rule the player cannot see |
| No dead offers | never offer a Relic the player cannot equip (no tower at tier 2 yet) **unless** it is offered alongside a tower upgrade as a separate offer | avoids "useless right now" without hiding relics entirely |
| Boss level | the offer before a boss level **guarantees** one tower or one Relic | the boss must be answerable with something the player could see coming |

`GUESS` the "4 towers" and "3 items" thresholds. **Would settle it:** count how
often a player takes a 4th/5th tower type. If a build is always 2 towers by
level 5, the guarantee is too weak and the draft is not happening.

## Reroll

| Reroll in a set | Cost | Cumulative | Share of a level-1 income (430) |
| --- | --- | --- | --- |
| 1st | 30 | 30 | 7.0% |
| 2nd | 45 | 75 | 17.4% |
| 3rd | 60 | 135 | 31.4% |
| 4th+ | refused | — | — |

- A reroll **replaces all three offers** and re-applies the guarantees and the
  no-duplicate rule.
- A reroll **cannot** re-offer any of the three options just discarded (per set,
  across all four draws). Without this rule a reroll is a 1-in-N coin flip and
  the player learns to distrust it.
- The counter resets for each level's offer set.
- The reroll is refused, with a reason, if gold is below the price.

`GUESS` 30/45/60. **Would settle it:** the share of offer sets that get at least
one reroll. Target **30–50%**. Under 20% and the price is too high or the offers
are too good; over 70% and the offers are too flat.

### Reroll thresholds — the price band

Reroll cost is tested against **one level's income** (`economy.md`), because
that is what the player is spending instead of a tower.

| Direction | Threshold | What happens if crossed | Current value |
| --- | --- | --- | --- |
| **Too cheap → offers become a shop** | first reroll ≤ **12** (3% of 430) | rerolling is free in practice; a player rerolls until the pool is exhausted and the "choice" is "pick the best of everything", which collapses pillar 1 into a shopping list | 30 (2.5× over the line) |
| **Too expensive → the mechanic is dead** | first reroll ≥ **108** (25% of 430) | no player ever rerolls, so the set is a forced pick and the only real decision left is the store | 30 (3.6× under the line) |

Healthy band: **13–107 gold**, i.e. **3%–25%** of a level's income. At 30 the
first reroll is **7%** — deliberately cheap, because the point of the reroll is
to make the first bad offer set recoverable. The escalation (45, 60) is what
stops it becoming a slot machine.

The third reroll at 135 cumulative is **31% of a level's income**: one reroll
spree costs more than a Mortar tower. That is the intended ceiling — the player
may do it once per run and remember it.

## Perks (the run-wide offer category)

Perks are permanent for the run, do not occupy a slot, and stack with each other
unless stated. Six is enough to make the pool feel varied; more is catalogue.

| Perk | Effect | Repeatable | Suits a player who |
| --- | --- | --- | --- |
| Patch the Line | +5 HQ (max 2 in the run) | no | is bleeding HQ to chip damage |
| Field Smithy | all towers cost **−10%** | no | wants their gold to go further, not their towers to be stronger |
| Long Watch | all towers gain **+8% range** | no | has a map with bad tiles |
| Tally | **+3 gold** per wave clear | no | is playing an economy build |
| Hardened Line | **+10% damage** to all towers | no | has the shape right and the numbers wrong |
| Second Wind | the first level after this one **cannot end the run**: HQ cannot fall below 1 | no | is about to take a route they are unsure of |

`GUESS` every value. **Would settle it:** if a perk is taken in more than one
run out of three, it is too good; if never, it is invisible. Field Smithy (−10%
cost) is the one most likely to be mispriced, because it competes directly with
the K1 threshold in `economy.md` — a −10% arrow is 63 gold, still inside the
55–94 band, so it is safe by construction. State any future cost perk against
that band before shipping it.

## Store (optional node)

| Shelf | Contents | Price |
| --- | --- | --- |
| 1 | a Rune the player does not own | 60 |
| 2 | a Rune or Relic the player does not own | 75 |
| 3 | a Relic the player does not own | 90 |

- Three shelves, one purchase per shelf, no reroll, leaves when the level starts.
- The store is the **gold sink with a price**, and it is what makes K1's surplus
  matter at high depth.
- **Cut candidate.** If the slice is short on systems budget, the store goes
  before the reroll does. Reasons: the reroll is the pillar-1 mechanic; the
  store is a convenience. Cutting it changes no threshold in this file.

`GUESS` the three prices. **Would settle it:** whether a player ever buys from
shelf 3 (90 gold). If not, the relic price is a wall and shelf 3 should be a
perk instead.

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| Gold below the first reroll price | reroll refused with a reason; the offers stand | the player must never be unable to act without being told why |
| Pool empty for a category | category removed, weights renormalised | otherwise a weight of 30 is spent on nothing |
| **All 6 towers owned** | the tower category is removed entirely; weight goes to items and perks | the endgame draft is about items, not verbs |
| All 20 items owned | item categories removed; weight goes to perks and towers | avoids an offer set of three empty cards |
| Everything owned (all towers, all items, all perks) | the set offers **heals and gold** (`+80 gold`) | a legal, boring set beats a crash |
| Reroll into the same three offers | forbidden by the no-repeat rule across the set | the worst possible player experience in this screen |
| Reroll with exactly enough gold | allowed; balance hits 0 | see `economy.md` §Edge cases |
| The player quits before picking | the run is not advanced and nothing is spent | no state is written on a closed window |
| Two offers of the same tower | impossible: duplicates forbidden within a set | two identical cards is a wasted slot |
| A Relic offered with no tier-2 tower | allowed only if a tower or upgrade is a separate offer | see §Guarantees |
| Heal offered at full HQ | illegal to generate; weight renormalises | a dead option the player cannot take |
| Perk that reduces tower cost, in a run with the −10% perk already taken | not repeatable; only one copy exists | stacking cost reductions breaks K1 by construction |
| The last offer before the boss level | a tower or Relic is guaranteed | the boss must have an answer the player could see |

## Not solving

- **No offer preview of the next level's waves.** Hidden information is about
  what you get, not what is coming (charter).
- **No choice of three then a queue.** One pick, one set, gone.
- **No offer of a specific *upgrade*** (e.g. "Arrow tier 2 for free"). That would
  collide with the gold sink in `economy.md` and make K1 untestable.
- **No currency cost for the pick itself.** The charter says offers may be
  rerolled for gold, not bought.
- **No pity timer or rarity weighting beyond the guarantees.** At 20 items the
  pool is small enough that a pity timer is invisible.
- **No shop UI, no card art, no animation timing.** Those are `eng/gameplay` and
  `art` questions; this file only fixes the numbers.

## Open questions for the human

1. **Is a reroll too cheap at 30?** Measured against a level-1 income of 430 it
   is 7%, which means most players will reroll any set they dislike. That is
   either "the offer is always interesting" or "the offer is never binding".
   Taste call.
2. **Should the pick be forced before the store**, or may the player shop first
   and then pick knowing what they bought? Ordering changes whether the store is
   a panic button or a plan.
3. **Is a "Second Wind" perk acceptable at G2?** It is the only perk that saves
   a run, which is a strong promise for a system the slice is still testing. It
   is also the cheapest way to keep five testers playing past level 5.
