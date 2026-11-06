# Nodes — eight types, what each offers, and what the player is allowed to know

> **G2 PLACEHOLDER.** Every number in this file is a theory-crafting default written
> before the slice exists, not a measurement. Nothing here is validated until a human
> plays a full run (G2.2). Rows marked `GUESS` have no data behind them; the last column
> names the observation that would replace the guess.

Owner: `design/systems`. Written at T-0038, 2026-11-06.

- **Number home.** This file owns node types, node weights per layer band, node payloads
  (except gold values, which are `economy.md`'s), and the **reveal rule**. Layer count,
  nodes per layer, adjacency and the map-selection rule are `run-map.md`.
- **`DATADRIVEN`** marks a named field meant to be tuned by data, never by code. Weights are
  a **table keyed by node type**, so adding a ninth type is a row, not a refactor.
- **One node per layer.** A layer offers 2–3 nodes; the player takes exactly one. Nodes in a
  layer are alternatives, never a sequence.

## The eight types

| Type | What it offers | Is it a level? | Player verb | Failure state |
| --- | --- | --- | --- | --- |
| **map** | A tower defence level on a map from the run's pool | **yes** | defend | the run ends if the HQ falls |
| **store** | A shelf of 5 items to buy (`store.md`) | no | choose what to buy, or save | leave with gold unspent and a build that never grew |
| **elite** | A standard map whose **final wave carries one sub-boss**, chosen at random | **yes** | gamble | the sub-boss is a wall the build cannot answer, and the run ends |
| **boss preview** | Information about the boss level, plus one free reroll token | no | plan | spend the information on a build that cannot act on it |
| **treasure** | Gold, `90 + 15 × layer` (`economy.md`) | no | collect | taking gold when the build needed a store |
| **rest** | **+6 HQ**, free, once | no | recover | resting at full HQ wastes the node |
| **event** | Choose **1 of 3** towers or upgrades, free of gold | no | draft | take a card that duplicates what you already cannot place |
| **high-stakes event** | A **blind roll on arrival**: HQ damage, or a free tower tier-up | no | commit blind | 50% of the time the run loses a quarter of its HQ for nothing |

Every type names its verb, its feedback and its failure state. A node type with no failure
state would be a free reward, and a map full of free rewards is not a route.

**Only map and elite nodes are levels.** The other six are "non-level nodes", and this is the
number that decides a run's length: **levels = layers taken as levels + 1 boss**, and every
non-level node taken costs one level (`run-map.md` §The 5-vs-10 spread).

## Weights

A layer's first slot is **always a map node** (the `map_nodes_per_layer ≥ 1` rule). Every
remaining slot draws from this table, renormalised over the types legal in that layer band,
excluding types already present in the layer.

| Type | Layers 1–2 | Layers 3–4 | Layers 5–6 | Layers 7–8 | Layer 9 |
| --- | --- | --- | --- | --- | --- |
| map | **50** | 40 | 35 | 36 | 40 |
| store | 20 | 18 | 15 | 12 | 10 |
| treasure | 10 | 10 | 12 | 12 | 10 |
| rest | 8 | 8 | 8 | 8 | 12 |
| event | 12 | 14 | 12 | 10 | 8 |
| elite | 0 | 6 | 10 | 12 | 10 |
| boss preview | 0 | 0 | 3 | 4 | 5 |
| high-stakes event | 0 | 4 | 5 | 6 | 5 |
| **Sum** | **100** | **100** | **100** | **100** | **100** |

| Field | Value | `DATADRIVEN` | Reason for the bound |
| --- | --- | --- | --- |
| `node_weights` | the table above | yes, per type per band | weights are the only difficulty-of-route dial that does not touch the wave curve |
| `elite_min_layer` | 3 | yes | an elite at layer 1 is a guaranteed loss (a 900 HP Bulwark against a one-tower build) |
| `boss_preview_min_layer` | 5 | yes | previewing the boss before the run has a shape is noise |
| `high_stakes_min_layer` | 3 | yes | losing 8 HQ at layer 2 is a run-ending coin flip before the player has agency |
| `nodes_without_duplicate_type` | true | yes | two stores in one layer halves the route decision |

### Why each type sits where it does

| Type | Reasoning |
| --- | --- |
| map | The most common node by a wide margin at every layer. If a player ever feels *forced* into a non-level node, the route stopped being a choice |
| store | 20 at the start, 10 at the end. Early stores are the difference between a build and a loadout; late stores are worth less because the run is nearly over |
| treasure | Flat. Gold is never the wrong thing, so it is never the *best* thing either |
| rest | Flat at 8 until layer 9 (12), because the boss needs the option to arrive healthy |
| event | Peaks at layers 3–4, when the build is still choosing its verbs |
| elite | Ramp to 12. An elite is the only node that offers a *level* with a bonus and a wall, so it becomes viable as the build matures |
| boss preview | Never 0 after layer 5 — the player must be able to buy information about the last level |
| high-stakes event | Its weight is low because its expected value is designed to be near zero. It exists for the player who wants a coin flip, not for the player who needs one |

`GUESS` every weight. **Would settle it:** the count of each node type *taken* across the five
tester runs. Target: **6–8 map levels, 2–3 non-level nodes, 1 elite**. If runs take 3+ elites,
the elite weight is too high or the reward is too good. If no one ever takes a high-stakes
node, it is priced correctly and should be watched, not cut.

### Expected offers per run

With 2 nodes in layers 1–4 and 3 in layers 5–9, a 9-layer map offers ~23 nodes and ~14
non-map draws. From the weights:

| Type | Expected offers per run | Expected taken per run (design intent) |
| --- | --- | --- |
| map | 9 (guaranteed, one per layer) | 6–7 |
| store | ≈3.7 | 2 |
| treasure | ≈1.6 | 1 |
| event | ≈1.9 | 1 |
| elite | ≈1.9 | 0–1 |
| rest | ≈1.2 | 0–1 |
| high-stakes event | ≈0.9 | 0–1 |
| boss preview | ≈0.6 | 0–1 |
| **Total** | **≈23** | **9** |

The gap between "offered" and "taken" is the design: a store is always *available* and almost
never *free*, because taking it costs a level.

## Payloads in detail

### map

- Runs the level described by `waves.md` at that level's `level_index`.
- Pays level income (`economy.md`) and one **upgrade drop** on the wave at `ceil(waves × 0.75)`
  (`items.md` §Acquisition). A drop is not a choice; it goes to the inventory.
- Reveal: type, map, active tiles, dominant enemy types. **Not** waves, composition or counts.

### elite

- A map node with three differences: **one sub-boss on the final wave** (Bulwark or Herald,
  50/50, fixed at generation), the final wave's trash cut to **60%**, and **+15 completion
  gold** (45 instead of 30). All in `waves.md` §The elite finale.
- The sub-boss identity is **never revealed** before the level starts. That is the node's whole
  price: the player knows a wall is coming, not which wall.
- Failure state: an elite taken too early is a run-ender, on purpose.

### store

- A shelf of 5 (`store.md`). The shelf is **not** revealed until the node is entered.
- Reveal: type only.

### boss preview

| Property | Rule | Marker |
| --- | --- | --- |
| Reveals | The boss map, its **wave count**, its **dominant enemy types**, and the Warden's phase-2 behaviour | — |
| Grants | **One free reroll token**, usable at any later store or offer site, without advancing that site's ladder | `boss_preview_free_rerolls = 1`, `DATADRIVEN` |
| Does not reveal | The boss's total budget, its escort fraction, or its final-wave composition | — |
| Failure state | Information the player cannot act on, because they took it instead of a store | — |

This is the node the charter's hidden-information principle is *tested* by: it is the only
place where the game sells foresight instead of power, and if no one takes it, foresight is
worth nothing and the node should be cut.

### treasure

- Gold, `90 + 15 × layer`, paid on arrival, no choice (`economy.md` owns the value).
- Failure state: gold is the **only** node reward that does not grow a build, so a route with
  two treasures and one store ends gold-rich and item-poor (`economy.md` §Run-level check).
- Reveals its value on arrival only; the node shows "treasure".

### rest

- **+6 HQ**, free, once. If HQ is at max, the heal is lost — it is not banked.
- No failure state of its own, and that is why it is the least-weighted node type: a free heal
  is only a decision when HQ is low, i.e. when the player has already made a mistake.

### event

- **Choose exactly 1 of 3** offered towers or upgrades. Free: no gold changes hands.
- The set is generated with `reroll-and-offers.md`'s category weights and guarantees; it can be
  rerolled with that file's ladder (30 / 45 / 60).
- The pick cannot be declined — a player who dislikes all three must reroll or take one
  (charter: between-level offers cannot be skipped).
- Reveal on arrival; the set is not previewed on the map.

### high-stakes event

| Property | Rule | Marker |
| --- | --- | --- |
| Timing | The roll happens **on arrival**, i.e. after the player has committed to the node | — |
| Odds | 50 / 50 | `high_stakes.good_chance = 0.5`, `DATADRIVEN`, band 0.4–0.6 |
| Bad outcome | **HQ −8** (27% of max) | `high_stakes.hq_damage = 8`, `DATADRIVEN`, band 5–12 |
| Good outcome | One **free tower tier-up**, applied to a copy the player **chooses after the roll** | `high_stakes.reward = tower_tier_up`, `DATADRIVEN` |
| Reroll | **Not rerollable.** The node is a roll, not an offer | — |
| Reveal | Type only — including that it is high-stakes. The player commits knowing the odds, never the outcome | — |

**Blind consequence, informed application.** The roll is blind; the target is not. That
combination is the whole design: the player cannot dodge the coin flip, but if it lands well
they are allowed to place the win where their build needs it, which keeps the outcome a
*decision* rather than a lottery payout.

## The reveal rule

> When a node is revealed on the map, the player knows **its type**, and for a level node
> **its map, its active-tile count, and its dominant enemy types**. Wave composition is
> never stored on the map.

| Field revealed | map / elite | store | treasure | rest | event | high-stakes | boss preview |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `node_type` | yes | yes | yes | yes | yes | yes | yes |
| `map_id` | yes | — | — | — | — | — | — |
| `active_tiles` (count) | yes | — | — | — | — | — | — |
| `dominant_enemies` (0–2 types) | yes | — | — | — | — | — | — |
| `is_elite` | yes | — | — | — | — | — | — |
| sub-boss identity | **never** | — | — | — | — | — | — |
| wave count | **no** | — | — | — | — | — | boss only |
| wave composition, unit counts | **never** | — | — | — | — | — | **never** |
| shelf contents | — | **on arrival** | — | — | — | — | — |
| event offer set | — | — | — | — | **on arrival** | — | — |
| gold value | — | — | **on arrival** | — | — | — | — |

**Definitions, so this is testable rather than a vibe:**

| Term | Definition |
| --- | --- |
| `active_tiles` | The count of buildable tiles the map offers on this visit, **including** the familiar-ground bonus when the map is the one just played (`hidden-rules.md`) |
| `dominant_enemies` | The **two** enemy types with the largest share of the level's threat budget, in that order. One type if the allowed set has one; never three |
| "on arrival" | Revealed when the node is resolved, not when it is offered |
| "never" | Not stored on the map object at all, so a UI bug cannot leak it |

**Why `active_tiles` is revealed but wave composition is not.** The tile count answers "can my
inventory fit here", which is a *build* question and the thing the player is deciding. The wave
composition answers "will my build survive", which is the *level's* question, and the charter
puts that on the far side of the information line. One sentence: **the map shows you the board,
never the enemy.**

**Why dominant enemy types, and only two.** A level's allowed set at `level_index` 7 is five
types; listing five is a menu, not a warning. Two names is enough to say "this is where armour
matters" or "this is where swarms matter" and short enough to read in one look (pillar 3).

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| A layer with no map node | Illegal: the generator rejects the layer, with a printed reason | `run-map.md`; a map-reachability bug must fail loudly |
| Two nodes of the same type in one layer | Illegal at generation (except map, which is guaranteed and never duplicated as a choice) | two stores in one layer halves the route decision |
| A node type not in the weight table | Illegal: the loader rejects the node | weights must be total, or a new type draws 0 forever |
| All non-map weights 0 in a layer | Illegal: at least one non-map weight must be > 0 | a layer of 1 node is not 2–3 nodes |
| `high_stakes` good outcome with every copy at tier 3 | Falls back to a **free upgrade tier-up**; if every upgrade is also at tier 3, pays **120 gold** instead | a reward with no legal target must degrade, never dead-end |
| `high_stakes` bad outcome at HQ 8 or below | Legal: the run can end on the node | the player committed knowing the odds |
| `high_stakes` rolled at HQ 1 | Legal | same; a blind roll must not be soft-gated or it is not blind |
| Rest node at full HQ | The +6 is lost, not banked | see `economy.md` §Edge cases |
| Event set with fewer than 3 legal cards | Illegal: the set is completed from remaining pools; duplicates are legal items so the pool cannot empty | a 2-card "choice" reads as a bug |
| Event at a point where the player owns everything | Impossible: duplicates are legal | the T-0035 "everything owned" branch is deleted, not handled |
| Boss preview taken twice in one run | Impossible: at most one boss preview node is generated per run | two previews would double the free reroll token for no decision |
| Boss preview taken after the boss is already revealed | Impossible: it cannot appear on layer 9 after the boss level is reached | `run-map.md` |
| Elite on the same layer as the boss node | Impossible: the boss layer holds a single node | `run-map.md` |
| Node revealed then the run ends before it resolves | Nothing is written; the node pays nothing | a reward must not be paid for a level never played |

## Not solving

- **No ninth node type at G2.** The eight are the brief's list; the weight table is shaped so a
  ninth is a row.
- **No node modifiers** ("a store with 20% off", "a cursed map"). That is a second axis and the
  slice has one.
- **No fog-of-war animation or map art.** `art/` and `eng/gameplay` own how reveal looks.
- **No wave preview of any kind, on any node except boss preview's summary.** This is the
  charter's line between a choice being visible and its effect being visible.
- **No gold values here.** Treasure and the empty-handed bonus are priced in `economy.md`.

## Open questions for the human

1. **Should the high-stakes node show its odds** (a 50/50 marker) or just its danger? Showing
   the odds makes it a rational gamble; hiding them makes it a story. Currently it shows
   "high-stakes" and nothing else, and the odds are in this file, not on the screen.
2. **Is a boss preview worth a layer?** It is the only node that trades power for foresight.
   If testers never take it, cut it and redistribute its weight — it is the cheapest type to
   remove, and removing it changes no threshold anywhere.
3. **Should `active_tiles` be a count or a shape?** A count is what the reveal rule promises; a
   thumbnail of the tile layout would answer "can my inventory fit" better, at the cost of
   making the map screen a deck of maps. Taste call.
