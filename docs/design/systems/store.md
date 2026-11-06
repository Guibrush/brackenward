# Store — five slots, tier-weighted, with a second-half floor

> **G2 PLACEHOLDER.** Every number in this file is a theory-crafting default written
> before the slice exists, not a measurement. Nothing here is validated until a human
> plays a full run (G2.2). Rows marked `GUESS` have no data behind them; the last column
> names the observation that would replace the guess.

Owner: `design/systems`. Written at T-0038, 2026-11-06.

- **Number home.** This file owns store stock size, category mix, tier weights, the
  second-half guarantee, the store price premium, and the store's own reroll ladder. Tower
  and upgrade *costs* are `towers.md`; the offer-set reroll ladder is `reroll-and-offers.md`;
  node weights that decide *whether* a store appears are `nodes.md`.
- **`DATADRIVEN`** marks a named field meant to be tuned by data, never by code.
- **This is the game's only way to buy a tower.** Placement is free and levels drop upgrades
  only (`items.md`), so if the store's stock is wrong, the build is wrong. Every number here
  is load-bearing.

## What a store is

A store is a **node on the run map** (`nodes.md`), resolved between levels. It sells tower
copies and upgrade copies. It is where gold becomes a build.

| Property | Value | Marker | Reason for the bound |
| --- | --- | --- | --- |
| Stock size | **5** items on the shelf | `store.stock_size = 5`, `DATADRIVEN`, band 3–7 | below 3 a reroll has nothing to improve; above 7 the shelf stops being readable in one look (pillar 3) |
| Purchases per visit | **unlimited** — gold is the limit | `store.purchases_per_visit = 0` (0 = unlimited), `DATADRIVEN` | a per-visit cap turns gold into a second currency with a hidden exchange rate |
| Rerolls per visit | **3** maximum | `store.rerolls_per_visit = 3`, `DATADRIVEN` | same shape as the offer ladder; a cap keeps the gold decision real |
| Reroll enabled | **per site**, default on | `store.reroll_enabled` on the node, `DATADRIVEN` | the brief asks for a per-site toggle; some stores are meant to be a fixed hand |
| Items removed on purchase | Yes — the slot empties | — | a purchased item must not be re-buyable at the same visit |
| Leaving | Free, at any time, before the next layer | — | the store is not a commitment |
| Determinism | Stock is a pure function of `run_seed`, `layer` and `visit_index` | — | a seed must reproduce a run exactly |

**Duplicates are legal on the shelf.** Two Arrows in one stock is a normal, good roll: it is
how a player who wants a wall of Arrows builds one. There is **no "already owned" filter** —
the T-0035 rule that removed an owned category is dead, because with duplicates allowed no
category can ever be exhausted.

## Price — the store's premium

A store price is derived from the item's **path cost** (`towers.md`), so there is exactly one
place to change a cost:

    store_price(item, tier) = path_cost(item, tier) × premium
    premium = 1.00 for tier 1,  1.25 for tier 2 and tier 3
    result rounded to the nearest 5 gold (half rounds up)

| Field | Value | Range | `DATADRIVEN` | Reason for the bound |
| --- | --- | --- | --- | --- |
| `store.premium_t2_plus` | **1.25** | 1.10–1.50 | yes | at 1.10 the store undercuts the in-level tier-ups and the build screen dies; at 1.50 no one buys a tier from a store and tiers become in-level only |

**Why a premium at all.** A tier-1 item has no in-level path to go around, so it sells at
cost. A tier-2 or tier-3 item **skips two or three gold sinks** the player would otherwise pay
inside a level, so the store charges for the skip. Without it, buying a tier-3 Arrow at a
store for its 240 path cost would make every in-level tier-up strictly pointless.

| Item | Tier 1 | Tier 2 | Tier 3 |
| --- | --- | --- | --- |
| Arrow | 70 | 165 | 300 |
| Bramble | 60 | 140 | 255 |
| Rime | 85 | 190 | 330 |
| Beacon | 90 | 200 | 350 |
| Mortar | 100 | 225 | 400 |
| Ballista | 110 | 245 | 430 |
| Rune upgrade (any of 12) | 60 | 130 | 230 |
| Relic upgrade (any of 8) | 90 | 200 | 350 |

Full range: **60–430**. The cheapest item costs less than one level's kill gold; the most
expensive costs more than a whole early level's income. That spread is deliberate: a tier-3
Ballista is a *decision about the rest of the run*, not a purchase.

## Stock generation — tier, category, item

Each of the 5 slots draws independently: **a tier, then a category, then an item**, then the
second-half guarantee is applied as a post-pass over the finished shelf.

### Tier weights

| Half of the run | Tier 1 | Tier 2 | Tier 3 |
| --- | --- | --- | --- |
| First half (layers 1–4 of 9) | **70%** | 26% | 4% |
| Second half (layers 5–9 of 9) | **45%** | 47% | 8% |

**"Half of the run" is defined arithmetically**, so it can be computed and tested:

    second_half  ⇔  layer > run_layers ÷ 2          (9 layers → layers 5–9)

| Field | Value | Range | `DATADRIVEN` | Reason for the bound |
| --- | --- | --- | --- | --- |
| `store.tier_weights_first` | 70 / 26 / 4 | any, sums to 100 | yes | 4% for tier 3 gives an expected **0.2** tier-3 items per first-half visit — rare enough to be an event, common enough to be seen once a run |
| `store.tier_weights_second` | 45 / 47 / 8 | any, sums to 100 | yes | the shift is the run getting *deeper*, not the player getting richer — it is difficulty-adjacent content, not a catch-up mechanic |

The second-half shift exists because a build that is still assembling tier-1 items at layer 7
is not interesting. It is **not** anti-snowball: it applies identically to a player who is
winning and one who is losing, and it hands out no gold.

### Category mix

| Category | Weight | Legal always | Notes |
| --- | --- | --- | --- |
| Tower copy | **60%** | yes | 6 types × 3 tiers = 18 combinations |
| Rune upgrade copy | **25%** | yes | 12 items × 3 tiers = 36 combinations |
| Relic upgrade copy | **15%** | yes | 8 items × 3 tiers = 24 combinations |

`GUESS` all three. **Would settle it:** the ratio of tower copies to upgrade copies bought
across a run. The target is **1.5–2.0 upgrades per tower**; below 1.0 the player is starved of
towers and the run is a one-tower run, above 3.0 the shelf is all upgrades and a second tower
never arrives.

### The second-half guarantee

> A store visited in the second half of the run **guarantees at least one tier-2-or-better
> item**.

| Property | Rule | Marker |
| --- | --- | --- |
| Condition | `layer > run_layers ÷ 2` | — |
| Test | after all 5 slots are drawn, count items with `tier ≥ 2` | — |
| Repair, if zero | replace the **highest-priced tier-1 slot** with a tier-2 item drawn by the category weights | — |
| Repair count | at most one slot is repaired | `store.guarantee_repairs = 1`, `DATADRIVEN` |
| First half | no guarantee; a first-half shelf may be all tier 1 | — |
| Rerolls | the guarantee **re-applies after every reroll** | — |

**Why the highest-priced tier-1 slot.** Repairing the cheapest slot would leave the shelf's
value almost unchanged and the player would see a tier-2 label on a trinket. Repairing the
most expensive keeps the shelf's total value roughly stable, so the guarantee is a change of
*shape*, not a gift.

The guarantee is a hidden rule the human adopted. It is not shown to the player as a badge;
it is felt as "late stores are never junk", which is exactly the kind of felt-but-unstated
rule the charter's hidden-information principle allows.

## What a shelf is worth

`fill_rate` in `economy.md` §K1′ is measured against the shelf's total value, so both halves
need a stated mean price. Derived from the price table, the category mix and the tier weights:

| Half | Mean item price | Shelf value (× 5) |
| --- | --- | --- |
| First half | **115** | **575** |
| Second half | **145** | **725** |

The first-half figure is the one K1′ tests against, because the first store a player meets is
in the first half.

## Reroll

The store's reroll competes with purchases for the same gold. It has its own ladder, separate
from the offer-set ladder in `reroll-and-offers.md`, because a shelf of five is a bigger and
noisier gamble than a choice of three.

| Reroll in a visit | Cost | Cumulative | Share of level-1 income (275) |
| --- | --- | --- | --- |
| 1st | **25** | 25 | 9% |
| 2nd | **40** | 65 | 24% |
| 3rd | **55** | 120 | 44% |
| 4th+ | refused | — | — |

| Rule | Statement |
| --- | --- |
| Scope | Replaces **all five** slots, and re-applies the guarantee and the no-repeat rule |
| No-repeat | A reroll cannot re-offer any (item, tier) discarded earlier **in the same visit**, across all four draws |
| Counter | Resets on every visit; it never carries between stores |
| Toggle | Refused with a reason when `reroll_enabled` is false on that node, and the refusal says the site is fixed |
| Order | Purchases and rerolls may be interleaved; a purchased slot stays empty after a reroll? **No** — a reroll refills the whole shelf, and already-bought items are not refunded or re-offered |
| Free reroll token | A `boss_preview` node grants one (`nodes.md`); spending it does **not** advance the ladder |

`GUESS` 25 / 40 / 55. **Would settle it:** the share of store visits where at least one
reroll is bought. Target **25–45%**. Below 15% the price is too high or the shelves are too
good; above 60% the shelves are noise and the tier weights need flattening.

**Why the store ladder is cheaper than the offer ladder at the first step.** The offer set is
three cards and a forced pick; the shelf is five items and no obligation. At 30 the first
offer reroll costs more than a first store reroll *and* buys less information, because the
offer is a smaller gamble. The ladders are the right way round.

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| Gold below the cheapest item | The store opens and shows the shelf; purchases are refused with a reason | an empty-handed visit must still be legible, and the shelf tells the player what to save for |
| Purchase exactly equals balance | Allowed; balance hits 0 | `economy.md` §Edge cases |
| Purchasing the same (item, tier) twice when the shelf holds two | Allowed — they are two distinct slots and two distinct copies | duplicates are the design |
| A shelf holding 3+ of the same (item, tier) | Illegal at generation: at most **2** per (item, tier) | `store.max_per_item_tier = 2`, `DATADRIVEN`; a shelf of five identical Arrows is a bug the player reads as a bug |
| Reroll when the remaining pool cannot fill 5 slots | Impossible: 78 legal combinations exist; the pool is never exhausted | the old "all items owned" edge case is deleted, not handled |
| Second-half guarantee with zero tier-1 slots to repair | Impossible: the repair target is the highest-priced tier-1 slot, and a shelf with 5 tier-2+ items already passes | a guarantee must not have a branch that does nothing |
| Store visited with no gold and no reroll | Legal: leave, nothing happens | the node is a lost level opportunity, which is the player's own arithmetic |
| Two stores in one run on the same layer | Impossible: one node per layer | `run-map.md` |
| Buying a tower copy with a full inventory cap | Refused **before** gold moves, with a reason | `towers.md` §Edge cases |
| Reroll on a fixed site (`reroll_enabled = false`) | Refused with a reason naming the site | the toggle must be visible, not silent |
| Determinism across a reroll | The stock is a pure function of seed, layer, visit index **and reroll count** | a seed must reproduce the run, including the screens the player saw |
| Store stock generated but never visited | Nothing is written; a store's shelf only exists once resolved | a shelf the player never saw must not consume randomness |

## Not solving

- **No haggling, discounts, or price that moves with `level_index`.** One price list.
- **No limited stock across visits.** The next store is a new shelf, not a restock timer.
- **No selling back to the store.** Removed with the placement model (`towers.md`).
- **No store UI, art, or animation timing.** Those are `eng/gameplay` and `art`.
- **No guarantee that a run contains a store at all.** That is `run-map.md`'s weights; see
  `hidden-rules.md` §Known limitation for what happens when a run has none.
- **No new item types.** 6 towers, 20 upgrades — the charter's budget.

## Open questions for the human

1. **Should the store show its stock before the player commits to the node?** Currently no:
   the node shows "store" and the shelf is revealed on arrival. Showing it earlier would turn
   the route into a shopping list and remove the reroll's reason to exist. This is a taste
   call with a large effect on pillar 2.
2. **Is 5 the right shelf size**, given the guarantee and a 3-reroll cap? 4 makes a reroll
   cheaper and the shelf more readable; 6 makes the second-half guarantee almost automatic
   (it would fire only on the worst rolls).
3. **Should the second-half guarantee be visible** as a small marker on the node once the
   player is in the second half? Pillar 3 says yes; the hidden-rule framing says no. This is
   the one adopted hidden rule whose *effect* might be worth advertising.
