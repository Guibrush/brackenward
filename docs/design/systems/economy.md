# Economy — gold for acquisition, and the arithmetic of the first store

> **G2 PLACEHOLDER.** Every number in this file is a theory-crafting default written
> before the slice exists, not a measurement. Nothing here is validated until a human
> plays a full run (G2.2). Rows marked `GUESS` have no data behind them; the last column
> names the observation that would replace the guess.

Owner: `design/systems`. Rewritten at T-0038, 2026-11-06. Supersedes T-0035 entirely.

- **Number home.** This file owns all gold: kill values, wave-clear, level completion,
  treasure, the empty-handed bonus, starting gold. It owns HQ health, leak damage and the
  rest heal. Tower and upgrade costs are cited from `towers.md`; store stock and store
  reroll prices from `store.md`; offer reroll prices from `reroll-and-offers.md`.
- **One worked example is authoritative.** §Worked example is computed from `waves.md`
  §Level 1 and `store.md` §Stock. If either changes, this section is recomputed before
  anything else is tuned against it.
- **Two thresholds decide whether the *new* model works** (§K1′, §K2′). Both are new,
  because the old ones tested placement cost and spawn interval against a market that no
  longer exists.
- **`DATADRIVEN`** marks a named field meant to be tuned by data, never by code.

## What the model is now

Placement is free. A tower copy is bought **once** and placed on every level of the run.
Therefore:

| Consequence | Statement |
| --- | --- |
| Gold buys **supply** | Each purchase is a permanent addition to the inventory, not a per-level rental |
| Gold buys **depth** | Tiers are bought in-level, between waves, and are permanent for the run |
| Gold never buys **position** | Placement, pick-up, re-placement and equipping are all free, always |
| The binding limit per level | Is **active tiles**, not gold (`nodes.md` §Active tiles) |
| The rhythm of the run | **Earn during levels, spend at nodes.** Between waves the only gold action is a tier-up |
| Failure mode to watch | A player with gold and nothing to buy — i.e. too few acquisition sites, not too little money |

That last row is the whole reason this file was rewritten. Under the placement model, surplus
gold was harmless because the next level would eat a layout's worth of it. Under the
acquisition model, **surplus gold is dead weight unless a store appears**, and the number of
stores is set by the map, not by the player's spending.

## Currencies and lifetime

| Currency | Earned | Spent | Lifetime |
| --- | --- | --- | --- |
| Gold | kills, wave clears, level completion, treasure nodes, the empty-handed bonus | store items, store rerolls, offer rerolls, tower tier-ups, upgrade tier-ups | **one run**, reset at the next run's start |
| HQ health | rest nodes only | enemy leaks | **one run**, carried level to level |
| Tower copies | starting loadout, store, event, high-stakes event | never spent — a copy is not consumed | **one run** |
| Upgrade copies | starting loadout, level drops, store, event, high-stakes event | consumed when applied (`towers.md` §Upgrade slots) | **one run** |

There is **no gold cap** and no persistent currency at G2 (meta-progression is deferred to
G3). Leftover gold dies with the run.

**There is no paid heal.** Gold's sink list is closed: **store items, rerolls, tower tiers,
upgrade tiers.** HQ is healed by the **rest node** (+6) and by nothing else. This is a
deliberate consequence of the closed sink list, it changes the shape of the run (HQ damage is
now close to permanent), and it is listed in §Open questions for confirmation rather than
assumed quietly.

## Gold in

| Source | Value | When | Marker |
| --- | --- | --- | --- |
| Starting gold | **120** | run start | `DATADRIVEN`, band 90–160 |
| Grunt kill | 2 | on death | `kill_gold.Grunt` |
| Runner kill | 3 | on death | 1.5× a Grunt for 0.6× the HP — speed is paid for |
| Shieldback kill | 6 | on death | 3× a Grunt for 2.25× the HP — armour is paid for |
| Swarmling kill | 1 | on death, each | a pack of 6 pays 6 |
| Bloom kill | 9 | on death | the healer pays best, so it is worth diving for |
| Bulwark kill | 60 | on death | sub-boss |
| Herald kill | 45 | on death | sub-boss |
| Warden kill | 300 | on death | the boss; paid, but the run is over |
| Wave clear | **10** | wave ends, leaked or not | `DATADRIVEN`, band 8–14 — an income floor that does not punish learning |
| Level complete | **30** | level ends | `DATADRIVEN`, band 20–45 |
| Elite level complete | **45** | elite level ends | 1.5× a level |
| Boss level complete | **60** | boss level ends | the last paycheque |
| Treasure node | **90 + 15 × layer** | on arrival | layer 2 → 120, layer 9 → 225; `treasure_base` / `treasure_per_layer` |
| Empty-handed bonus | **90** | the next level node after 3 layers without a store | `hidden-rules.md` owns the threshold; the value is here |

Kill values average **2.3 gold per threat**, which is the invariant to preserve if enemy HP
changes: the curve is priced in threat, so re-deriving gold from HP keeps the whole file
valid.

`GUESS` every value. **Would settle it:** the unspent-gold measurement in §Run-level check. If
a player finishes the boss holding more than one store's stock, kill gold is ~15% too high
*or* the map has too few stores — and those two causes are told apart by whether they also
had items they could not afford.

**A leaked enemy pays nothing.** The single most important economic rule: a leak costs a
point of HQ *and* the kill gold, so it is a double loss and a bad first wave compounds.
§Worked example shows the double loss in one comparison.

## Gold out

| Sink | Cost | When | Source |
| --- | --- | --- | --- |
| Tower copy, tier 1 | 60–110 | between levels, at a store or event | `towers.md` `Acquire` |
| Tower copy, tier 2 / 3 | `Path cost × 1.25`, rounded to 5 | between levels, at a store | `store.md` §Price |
| Rune upgrade copy, tier 1 | 60 | between levels, at a store or event | `towers.md` §The two tier axes |
| Relic upgrade copy, tier 1 | 90 | between levels, at a store or event | `towers.md` §The two tier axes |
| Tower tier-up | 50–150 per step | **in-level, between waves only** | `towers.md` `Tier-up` column |
| Rune tier-up | 45 then 80 | **in-level, between waves only** | `towers.md` §The two tier axes |
| Relic tier-up | 70 then 120 | **in-level, between waves only** | `towers.md` §The two tier axes |
| Offer reroll | 30 / 45 / 60 | between levels | `reroll-and-offers.md` |
| Store reroll | 25 / 40 / 55 | at a store, if enabled for that site | `store.md` §Reroll |
| Placement, pick-up, equipping | **0** | always | `towers.md` §Reconfiguration |
| Heal | **not purchasable** | — | rest nodes only |

The two timing columns are the load-bearing part. **Acquisition happens at nodes; depth
happens inside levels.** A player who leaves a store with 400 gold and no purchases has made
a mistake the game can show them; a player who cannot spend during a wave is not being
punished, they are being *paced*.

## HQ health and leak damage

| Quantity | Value | Reason for the number |
| --- | --- | --- |
| HQ max health | **30** | see the leak-budget check below |
| Regen inside a level | **none** | damage taken is real |
| Rest node heal | **+6**, free | the only heal; `nodes.md` |
| HQ at 0 | level lost → **run lost** | charter: failing a level ends the run |

Leak damage by enemy (source: `enemies.md`; restated because the economy is what it costs):

| Enemy | Leak damage | Share of full HQ | Note |
| --- | --- | --- | --- |
| Grunt, Runner, Shieldback, Swarmling, Bloom | 1 | 3.3% | 30 leaks end the run |
| Bulwark, Herald | 3 | 10% | a leaking sub-boss is a real loss |
| Warden | 10 | 33% | the boss leaking is survivable **once** |

**Leak budget check** — the arithmetic that keeps 30. Because healing is now the rest node
only, HQ is much closer to a hard budget than it was under the placement model:

| Run shape | Levels | Expected leaks, average play | Rest heals reachable | Verdict |
| --- | --- | --- | --- | --- |
| 5 levels (4 + boss) | 4 | 4–8, plus 0–10 from the boss | 1–2 nodes, +6 to +12 | 30 is generous; the run is not lost to chip damage |
| 7 levels (6 + boss) | 6 | 6–12, plus 0–10 | 0–2 nodes, +0 to +12 | tight when the boss leaks once |
| 10 levels (9 + boss) | 9 | 9–18, plus 0–10 | **0 nodes** — every layer is a level | a leak-heavy 10-level run **cannot be healed at all** |

The last row is a finding, not a table entry: a maximal run trades away every rest node, so
its HQ is a spend-once resource. That is a legitimate reason to take fewer levels, and it is
one of the two mechanisms that make the run-length spread a real decision (the other is
`waves.md` §Run length and the session).

`GUESS` 30 and +6. **Would settle it:** the HQ a player finishes the boss with. Below 8, HQ
should be 35; if nobody ever takes a rest node, it should be 25 and the rest node is dead.

## Worked example — level 1 and the first store, average play

**Definition of "average play"** here: clears each wave with **no leaks**, buys the single
tier-up the level actually demands at the wave that demands it, and then buys **three items
and one reroll** at the first store. Level 1's composition is fixed in `waves.md` §Level 1;
gold values are above; stock and prices are `store.md` §Stock.

Starting loadout (free, no gold moves): **one tier-1 tower copy** (Arrow, chosen from two
offers) and **one tier-1 upgrade copy** (Whetstone, chosen from two offers). Both are placed
and equipped for free.

### The ledger

| Step | Action | Gold in | Gold out | Gold left |
| --- | --- | --- | --- | --- |
| Run start | starting gold | +120 | — | **120** |
| Loadout | Arrow T1 + Whetstone T1, placed and equipped | 0 | 0 | **120** |
| Wave 1 | 6 Grunt × 2, plus wave clear 10 | +22 | — | **142** |
| Build phase 1 | Arrow T1 → T2 (the tier-up wave 4 demands) | — | 60 | **82** |
| Wave 2 | 6 Grunt × 2 + 2 Runner × 3, plus clear 10 | +28 | — | **110** |
| Wave 3 | 8 Grunt × 2 + 2 Runner × 3, plus clear 10 | +32 | — | **142** |
| Wave 4 | 10 Grunt × 2 + 4 Runner × 3, plus clear 10 | +42 | — | **184** |
| Wave 5 | 12 Grunt × 2 + 6 Runner × 3, plus clear 10 | +52 | — | **236** |
| Wave 6 | 15 Grunt × 2 + 10 Runner × 3, plus clear 10 | +70 | — | **306** |
| Level complete | completion bonus | +30 | — | **336** |
| Store, layer 2 | Arrow T1 copy (a second placeable tower) | — | 70 | **266** |
| Store, layer 2 | Piercer, Rune T1 copy | — | 60 | **206** |
| Store, layer 2 | one Relic T1 copy | — | 90 | **116** |
| Store, layer 2 | first store reroll | — | 25 | **91** |

### The totals, reconciled

| Line | Value |
| --- | --- |
| Opening balance | 120 |
| Kills in waves 1–6 | 12 + 18 + 22 + 32 + 42 + 60 = **186** |
| Wave clears, 6 × 10 | **60** |
| Level completion | **30** |
| Gold earned inside level 1 | 186 + 60 + 30 = **276** |
| Total available | 120 + 276 = **396** |
| Gold spent | 60 + 70 + 60 + 90 + 25 = **305** |
| Closing balance | **91** |
| **Check** | 396 − 305 = 91 ✓ |

No gold is earned outside those lines and none is spent outside those purchases. **The totals
reconcile to the unit.** Note what is *absent*: no placement cost, no sell refund, no heal.
The only in-level purchase is one tier-up of 60.

### The same level with two leaks

Two of wave 5's six Runners leak. They pay nothing, and each takes a point of HQ.

| Line | Clean | 2 Runners leak in wave 5 |
| --- | --- | --- |
| Kills, waves 1–6 | 186 | **180** (wave 5 pays 36 not 42) |
| Gold earned inside level 1 | 276 | **270** |
| Total available | 396 | **390** |
| Gold spent | 305 | 305 |
| Closing balance | **91** | **85** |
| HQ after level 1 | 30 | **28** |

**−6 gold and −2 HQ for the same two enemies.** The gold is what would have paid for the
fourth store item; the HQ is what a rest node would have refunded. A leak in wave 5 of level
1 is worth more than a mistake in wave 7, because it is the gold that compounds.

## K1′ — the first store must be a choice of two, not a wall and not a buffet

Under the placement model the critical question was "can the player afford their first
tower". Placement is free now, so that question is answered by a free starting loadout. The
question that replaces it is: **at the first store, can the player afford a real choice of
two items, but not the shelf?**

**The measurement.** `fill_rate = gold in hand at the first store ÷ (stock_size × mean stock
price)`. With `stock_size = 5` and a mean stock price of **115** (`store.md` §Stock derives
it from the tier weights and the price table), the full stock is worth **575**.

In the worked example, gold in hand at the store is **336** → `fill_rate = 336 ÷ 575 = 0.584`.

| Direction | Threshold | What happens if crossed | Current value |
| --- | --- | --- | --- |
| **Too poor → the run cannot grow** | `fill_rate < 0.25` (under **144** gold) | the player buys one cheap item, keeps the starting loadout all run, and never assembles a second tower copy; every level is fought with the same one or two towers and the run dies at level 3–4 without a decision having been made | 0.584 (2.3× over the line) |
| **Too rich → the store is a buffet** | `fill_rate > 0.80` (over **460** gold) | the player buys four of five items every visit; the only remaining decision is which store, not what to buy, and pillar 1's draft collapses into a shopping list | 0.584 (1.4× under the line) |

**Healthy band: 0.35–0.70**, i.e. **201–403 gold** at a first store. At 336 the player
affords two comfortable purchases plus a reroll, and must still leave something on the shelf.

`GUESS` the band. **Would settle it:** count items left unbought on the first store's shelf.
The target is **2–3 of 5**. Zero or five means the price band is wrong; four means the
stock's tier weights are too generous early (`store.md` §Tier weights).

## K2′ — the first tier-up must be affordable before the wave that needs it

This is the threshold that decides whether the build screen has anything to decide at
`level_index` 1. Because acquisition happens at nodes and never mid-level, **the tier-up is
the only mid-level power lever in the game.**

**The kill-capacity arithmetic.** One Arrow tier 1 kills a Grunt in `40 ÷ 20 = 2.0 s`. A
Grunt spends `181 ÷ 60 = 3.0 s` inside that tower's 96 px range (`enemies.md` §Time on the
lane). So one tower processes **1.5 kills per coverage window**, i.e. **0.5 kills/s**.

Level 1's wave 4 is the first wave that outruns it: 14 units at 1.7 s spacing → **0.588
arrivals/s**, a deficit of 0.088 kills/s. Arrow tier 2 (34.8 DPS, 1.15 s per Grunt) processes
**0.87 kills/s** — it clears the same wave with margin.

**The measurement.** `tier_up_pressure = cost of the first demanding tier-up ÷ gold banked
before the wave that demands it`. In the worked example: **60 ÷ 142 = 0.423**. Gold banked
before wave 4 is the starting 120, plus waves 1–3's kills (52) and clears (30), minus the
tier-up itself — measured *before* paying, it is 142.

| Direction | Threshold | What happens if crossed | Current value |
| --- | --- | --- | --- |
| **Too tight → unwinnable** | `> 0.80` (needs over **114** gold by wave 4) | the player reaches wave 4 with a tier-1 tower and no way to tier up; wave 4 leaks 4 of 14 (HQ 30 → 26) and pays 8 gold less, so wave 5 is worse and the level is lost to arithmetic rather than to a choice | 0.423 (1.9× under the line) |
| **Too loose → no decision** | `< 0.20` (under **28** gold) | the tier-up is bought reflexively at wave 1, the build screen has nothing to decide, and every player enters level 2 with the same tier-2 tower | 0.423 (2.1× over the line) |

**Healthy band: 0.25–0.65**, i.e. the first tier-up costs **25–65%** of the gold the level
has paid out by the wave that needs it.

`GUESS` the band. **Would settle it:** the leaks on level 1 wave 4 with **exactly one tower
and exactly one tier-up available**. The target is **0–2 leaks**. More than 4 means the
interval ladder is too tight; a clean wave with the tier-1 tower still in place means the
tier-up is not needed and the wave 4 budget should rise.

**The weakest case, and it fails deliberately.** Bramble at 60 has a 48 px radius, which
cuts a 72 px chord of a lane 32 px away — 1.19 s of contact against a 2.67 s time-to-kill. It
cannot kill a single Grunt in one pass, so a player who *chooses* Bramble in the starting
loadout loses wave 1's kills. That is legal and intended: Bramble is an area tool, its tile
must show the damage radius plainly so the choice is informed (pillar 3), and the store line
must read "area, very short range". If the starting pair offers Bramble next to Arrow, that is
the opening's first real lesson.

## Run-level check — income versus sinks, for three run shapes

Income per level, from `waves.md`'s curve, at **2.25 kill gold per threat** (the level-1
fixture gives 186 ÷ 82 = 2.27; the small drift is rounding inside the fixture):

| `level_index` | Waves | Threat | Kill gold | Clears | Completion | Level income | Cumulative |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 6 | 82 | 185 | 60 | 30 | 275 | 275 |
| 2 | 6 | 98 | 220 | 60 | 30 | 310 | 585 |
| 3 | 6 | 118 | 265 | 60 | 30 | 355 | 940 |
| 4 | 7 | 142 | 320 | 70 | 30 | 420 | 1360 |
| 5 | 7 | 170 | 385 | 70 | 30 | 485 | 1845 |
| 6 | 7 | 204 | 460 | 70 | 30 | 560 | 2405 |
| 7 | 8 | 245 | 550 | 80 | 30 | 660 | 3065 |
| 8 | 8 | 294 | 660 | 80 | 30 | 770 | 3835 |
| 9 | 8 | 353 | 795 | 80 | 30 | 905 | 4740 |
| boss | 7 | 541 | 1200 | 70 | 60 | 1330 | 6070 |

A run's shape decides how many **acquisition sites** it has, and acquisition — not gold — is
what a build is made of. Items per shape, assuming one drop per level (`items.md`), ~2.5
purchases per store visit, and 1 pick per event:

| Run shape | Levels | Non-level nodes | Tower copies | Upgrade copies | Gold available | Gold per item |
| --- | --- | --- | --- | --- | --- | --- |
| 5 levels | 4 + boss | 5 (≈3 stores, 1 event, 1 treasure) | ≈6 | ≈7 | ≈3170 | 244 |
| 7 levels | 6 + boss | 3 (≈2 stores, 1 event) | ≈5 | ≈9 | ≈4000 | 286 |
| 10 levels | 9 + boss | 0 | **1** | ≈10 | ≈6370 | 579 |

| Run shape | Acquisition | Tier-ups to T3 | Total sinks | Income ÷ sinks | Unspent at the boss | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| 5 levels | 1014 | 2119 | 3133 | **1.01** | ≈37 | too tight — every purchase is forced |
| 7 levels | 1073 | 2263 | 3336 | **1.20** | ≈664 | in band; residual ≈ one stock |
| 10 levels | 805 | 1740 | 2545 | **2.50** | ≈3825 | **gold-rich, item-poor: unspendable** |

Target band **income ÷ all sinks = 1.10–1.35**. The 7-level shape sits inside it. Both
extremes fail in opposite directions, and **that is the design**: the run-length spread is
the player's control over whether they are short of gold or short of things to spend it on.

| Extra check | Target | Current | Verdict |
| --- | --- | --- | --- |
| Unspent gold at the boss | ≤ one store's stock (575 first half, 725 second half) | 37 / 664 / 3825 | the 10-level run fails: 5–6 stocks' worth of dead gold |
| Gold per item owned | 200–350 | 244 / 286 / 579 | 5 and 7 in band; 10 is the failure |
| A shop-less run is playable at all | 3+ tower copies by level 5 | 1 copy | **fails** — see `hidden-rules.md` §Known limitation |

`GUESS` all of it. **Would settle it:** measure unspent gold and item count at the boss in
the first full run. If unspent gold exceeds 725 at more than one run shape, the dial is
**kill gold −10%** (not tower cost — that would move K1′), or the map needs more store
weight (`run-map.md`).

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| Gold would go negative | Illegal: the purchase is refused with a reason, gold unchanged | a negative balance makes every later check meaningless |
| Purchase exactly equals balance | Allowed; balance hits 0 | refusing an exact buy is the most common off-by-one in economy code |
| A leaked enemy's kill gold | Not paid. Ever. Not partially | two towers claiming one kill, or a leak paying, is a ledger bug |
| Kill gold on overkill | Paid once per enemy, at death | the same |
| Leak on the last enemy of a wave | The wave-clear bonus is still paid | the income floor must not depend on a coin-flip kill |
| HQ reaches 0 mid-wave | The level ends immediately; no further kills pay, no wave bonus | a dead run must not earn gold |
| Wave 0 / level index 0 / negative | Illegal; the loader rejects | index arithmetic on an empty wave divides by zero |
| Treasure node on the last layer | Legal | the gold is spent at the boss level's build phases |
| Treasure value when the layer is unknown | Illegal: layer is always known | a formula with a missing term silently pays 90 |
| Empty-handed bonus on a run with no stores at all | Fires every 3 layers, as written | see `hidden-rules.md`; it is the only compensation for that route |
| Rest node at full HQ | The +6 is lost, not banked | banking a heal is a free resource with no decision |
| HQ heal above max from a rest node | Clamp at max; the node is still consumed | charging for nothing is the worst possible bug to a player |
| Zero gold at a build phase | Legal: the player watches | the game must never present a purchase it will refuse silently |
| Gold at run end | Discarded | charter: gold lives only inside a run |
| Buying a tower copy with a full inventory cap | Refused before gold moves | `towers.md` §Edge cases |
| A second copy of a tower already owned | Allowed, at full price | duplicates are the design |
| Two identical items in one store's stock | Allowed up to 2 per (item, tier) | `store.md` §Stock; beyond 2 it is a wasted shelf |

## Not solving

- **No persistent or meta currency.** Deferred to G3 (charter).
- **No interest, no gold gifts between levels, no item resale.** Gold only ever flows through
  the five sinks listed.
- **No paid heals.** Deliberate, per the closed sink list — pending human confirmation.
- **No difficulty-scaled prices.** One price list for every `level_index`; difficulty scales
  on the wave curve only.
- **No anti-snowball economics.** No tax on a rich player, no bonus for a poor one.
- **No answer to whether leftover gold converts at run end** — the charter leaves it
  undecided and it is a G3 question.
- **No store or offer pricing.** `store.md` and `reroll-and-offers.md` own those.

## Open questions for the human

1. **Is healing really only the rest node?** The brief's sink list omits heals, and this file
   takes that literally. The consequence is that HQ damage is close to permanent, rest nodes
   become the most valuable non-level node, and a 10-level run cannot heal at all. If a paid
   heal should survive, it needs a price and it becomes a sixth sink.
2. **Is 120 starting gold right when the loadout is free?** Under the placement model 120
   bought "one tower and a mistake". Now it only buys store items, and the first store is a
   whole layer away. 90 makes the opening store a two-item choice; 160 makes it a four-item
   one and pushes K1′ toward its ceiling.
3. **Should the wave-clear bonus be flat (10) or scale with `level_index`?** Flat is readable;
   scaling would keep the *ratio* of clear bonus to kill gold constant as threat grows, which
   is currently 60 ÷ 185 = 32% at level 1 and 80 ÷ 795 = 10% at level 9.
