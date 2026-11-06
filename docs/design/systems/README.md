# Design systems — the numbers the slice runs on

> **G2 PLACEHOLDER.** Every number in every file below is a theory-crafting default made
> before the slice exists. Nothing here is validated until a human plays a full run
> (G2.2). Each file carries its own banner, its own guesses, and the observation that
> would replace each guess.

Owner: `design/systems`. Written at T-0035, 2026-11-06; **re-cut at T-0038, 2026-11-06**
for the inventory and run-map model.

This directory is a **tuning surface**, not a specification of the finished game. Its job is
to make the slice's numbers exist in one place, so the first playtest moves them deliberately
instead of hunting for literals in code.

## The ten files

| File | One-line purpose |
| --- | --- |
| [`towers.md`](towers.md) | The 6 towers, their 3 tiers, the tier-up ladder, the 2 upgrade slots, duplicates, permanence, and free placement. |
| [`items.md`](items.md) | 20 upgrades (Runes and Relics): effects, costs, the modifier caps, and the proof that none is strictly better than another. **T-0035 text — its slot rules are superseded by `towers.md`.** |
| [`enemies.md`](enemies.md) | 5 normal enemies, 2 sub-bosses, 1 boss: speed, health, armour, threat cost, and the player behaviour each punishes. |
| [`waves.md`](waves.md) | One difficulty curve indexed by level, the composition rule, the elite finale, the boss level, and what each run length costs in minutes. |
| [`economy.md`](economy.md) | Gold in and out under the acquisition model, HQ and leaks, a reconciled worked example, and the two thresholds that decide whether the model works. |
| [`store.md`](store.md) | Five-slot stock, tier weights, the second-half guarantee, the store's reroll ladder, and the price premium over in-level tier-ups. |
| [`nodes.md`](nodes.md) | The 8 node types, their weights per layer, their payloads, and the reveal rule that decides what a player may know. |
| [`run-map.md`](run-map.md) | 9 layers, 2–3 nodes each, adjacency, the previous-map weight, the boss-final rule, lures, and how the 5-vs-10 spread is reached. |
| [`hidden-rules.md`](hidden-rules.md) | The two adopted hidden rules with parameters, and the three rejected ones with their reasons. |
| [`reroll-and-offers.md`](reroll-and-offers.md) | Offer counts, offer weights, the **offer-set** reroll ladder, and perks. **T-0035 text — its store section is superseded by `store.md`.** |

## What T-0038 changed, in one table

The old model charged gold **per placement** and refunded 60% on sell. Towers are now items in
an inventory; placement, pick-up and equipping are free; gold buys **acquisition** and **tiers**;
runs are 5–10 levels on a 9-layer procedural map.

| Concern | T-0035 | T-0038 |
| --- | --- | --- |
| Where gold goes | placement, upgrades, heal, reroll, store | **store items, rerolls, tower tiers, upgrade tiers** — never placement or equipping |
| When gold goes | any build phase | **acquisition at nodes; tiers in-level between waves** |
| What a tower is | a thing you build | **an inventory copy you place for free** |
| Difficulty | depth archetypes on an assumed 8-level path | **`level_index` only**, no anti-snowball |
| Between levels | a 3-card offer set | **a map node**: level, store, elite, treasure, rest, event, high-stakes, boss preview |
| Heal | 40 gold for +5 HQ | **rest node only** (+6); no paid heal |
| Sell | 60% refund | **no sell at all**; the copy returns to the inventory |

## Conventions every file follows

| Convention | Rule |
| --- | --- |
| **One home per number** | Each number is owned by exactly one file (see below). A file that needs another's number cites it and marks the copy. If a copy and its home disagree, **the home wins**. |
| **Units** | gold: integer. damage: integer per hit, floored after modifiers. rate: seconds, 2 dp. range: px. speed: px/s. threat: 0.5 steps. tiles: integer. |
| **`GUESS` marker** | A number with no data behind it. Every file names the observation that would settle it. |
| **`DATADRIVEN` marker** | A named field meant to be changed **without touching code**. The value shown is a default, not a commitment. §Switchable values lists every one. |
| **No implementation** | These files say what must be true, never what a class or node is called. |

### Number ownership

| Number | Home |
| --- | --- |
| Tower damage, rate, range, tier-up costs, tier-1 acquire price, path cost | `towers.md` |
| Upgrade slot count, duplicate toggle, permanence and removal switch | `towers.md` |
| Upgrade effects, penalties, modifier caps, Rune/Relic split | `items.md` (effects) + `towers.md` (tiers) |
| Enemy HP, speed, armour, slow resistance, threat cost, pack size | `enemies.md` |
| Wave counts, wave budgets, level-index curve, spawn intervals, composition weights, unit cap, elite finale, boss level | `waves.md` |
| All gold values, HQ health, leak damage, rest heal | `economy.md` |
| Store stock size, category mix, tier weights, guarantee, price premium, store reroll | `store.md` |
| Node types, node weights, node payloads, reveal rule | `nodes.md` |
| Layer count, nodes per layer, adjacency, map weights, boss-final rule, lookahead, lures | `run-map.md` |
| Hidden-rule triggers and parameters | `hidden-rules.md` |
| Offer counts, offer weights, offer reroll ladder, perk values | `reroll-and-offers.md` |

### The switchable values, in one place

Every field below is meant to be tuned **by data**. The code tasks should be able to change
each of these without a rebuild.

| Field | File | Default | Why it is switchable |
| --- | --- | --- | --- |
| `inventory_cap` | `towers.md` | 0 (uncapped) | the human asked for a cap setting; ships off |
| `upgrade_slots_per_tower` | `towers.md` | 2 | data-driven slot count, 1–3 legal |
| `allow_duplicate_upgrade_on_same_tower` | `towers.md` | true | the human's duplicate toggle |
| `upgrades_permanent` | `towers.md` | true | permanence rule |
| `upgrade_removal_enabled` | `towers.md` | false | the removal switch the code must keep |
| `tower_cap_per_map` | `towers.md` | 12 | readability limit |
| `tier_up_cost[tower][step]` | `towers.md` | 50–150 | the in-level sink |
| `upgrade_tier_multiplier` | `towers.md` | 1.00 / 1.55 / 2.10 | upgrade depth ladder |
| `store.stock_size` | `store.md` | 5 | the human's max-5 stock |
| `store.purchases_per_visit` | `store.md` | 0 (unlimited) | per-visit purchase cap |
| `store.tier_weights_first` | `store.md` | 70 / 26 / 4 | early-run tier rarity |
| `store.tier_weights_second` | `store.md` | 45 / 47 / 8 | late-run tier rarity |
| `store.category_mix` | `store.md` | 60 / 25 / 15 | towers vs runes vs relics |
| `store.premium_t2_plus` | `store.md` | 1.25 | store price over path cost |
| `store.guarantee_repairs` | `store.md` | 1 | second-half guarantee |
| `store.reroll_enabled` (per node) | `store.md` | true | the human's per-site reroll toggle |
| `store.rerolls_per_visit` | `store.md` | 3 | reroll cap |
| `store.reroll_costs` | `store.md` | 25 / 40 / 55 | store reroll ladder |
| `store.max_per_item_tier` | `store.md` | 2 | duplicate cap on one shelf |
| `node_weights[type][band]` | `nodes.md` | §table | route shape |
| `elite_min_layer` / `high_stakes_min_layer` / `boss_preview_min_layer` | `nodes.md` | 3 / 3 / 5 | node availability gates |
| `high_stakes.good_chance` / `.hq_damage` | `nodes.md` | 0.5 / 8 | the blind roll |
| `boss_preview_free_rerolls` | `nodes.md` | 1 | preview payload |
| `run.layers` | `run-map.md` | 9 | map depth |
| `run.nodes_per_layer` | `run-map.md` | 2–3 | the human's 2–3 nodes |
| `run.min_levels` | `run-map.md` | 4 | the 5-level floor |
| `run.previous_map_weight` / `other_map_weight` | `run-map.md` | 5 / 20 | familiar-ground frequency |
| `run.lookahead_layers` / `lure_count` | `run-map.md` | 2 / 2 | reveal and lures |
| `level1_threat` / `level_growth` | `waves.md` | 82 / 1.20 | the whole difficulty curve |
| `wave_ramp` | `waves.md` | 1.32 | wave shape inside a level |
| `tighten` / `interval_floor` / `interval_ceiling` | `waves.md` | 0.94 / 0.5 / 2.6 | pacing |
| `unit_cap_per_wave` | `waves.md` | 40 | readability and performance |
| `elite_final_trash_fraction` / `sub_boss_scale_per_level` | `waves.md` | 0.60 / 0.0 | elite difficulty |
| `boss_trash_threat` / `boss_escort_fraction` | `waves.md` | 340 / 0.60 | boss level |
| `build_phase_seconds` | `waves.md` | 15 | level duration |
| `starting_gold` / `wave_clear` / `level_complete` / `elite_complete` / `boss_complete` | `economy.md` | 120 / 10 / 30 / 45 / 60 | income |
| `kill_gold[enemy]` | `economy.md` | 1–300 | income shape |
| `treasure_base` / `treasure_per_layer` | `economy.md` | 90 / 15 | node income |
| `hq_max` / `rest_heal` | `economy.md` | 30 / 6 | HQ budget |
| `familiar_ground_bonus_tiles` | `hidden-rules.md` | 1 | the human's extra tile |
| `empty_handed_threshold` | `hidden-rules.md` | 3 | the human's 3-layer threshold |
| `empty_handed_bonus_gold` | `economy.md` | 90 | bonus value |
| `empty_handed_max_triggers` | `hidden-rules.md` | 0 (unlimited) | repeat policy |
| `build_tiles_per_map` | `design/level` map data | 8–12 | **the real cap on placed towers** |
| `familiar_ground` bonus tile index | `design/level` map data | 1 per map | where the extra tile is |

### The ten numbers the slice is actually built on

Everything else follows from these. If only ten numbers get tuned, tune these:

| # | Number | Value | Home |
| --- | --- | --- | --- |
| 1 | Level growth per level index | ×1.20 | `waves.md` |
| 2 | Level-1 total threat | 82 | `waves.md` |
| 3 | Arrow tier-1 DPS | 20.0 | `towers.md` |
| 4 | Arrow tier-1 acquire price | 70 | `towers.md` |
| 5 | Starting gold | 120 | `economy.md` |
| 6 | Grunt HP | 40 | `enemies.md` |
| 7 | Grunt speed | 60 px/s | `enemies.md` |
| 8 | Store stock size | 5 | `store.md` |
| 9 | Store price premium (tier 2+) | ×1.25 | `store.md` |
| 10 | Empty-handed threshold | 3 layers | `hidden-rules.md` |

Numbers 1–2 are the difficulty of the whole run. 3–4 set whether the opening level is holdable
by one tower. 5–9 set whether a build can grow. 10 sets how hard a store-less route is
punished.

## The two thresholds that break the new model

Both live in `economy.md` with their arithmetic. The old K1/K2 tested placement cost and spawn
interval against a market that no longer exists; both are replaced.

| Threshold | Fails low if | Fails high if | Current | Healthy band |
| --- | --- | --- | --- | --- |
| **K1′** — store fill rate: gold in hand ÷ stock value (575) | **< 0.25** — the run never grows a second tower | **> 0.80** — the store is a buffet, not a choice | **0.58** | 0.35–0.70 |
| **K2′** — tier-up pressure: first demanding tier-up ÷ gold banked before the wave that needs it | **< 0.20** — the build screen has nothing to decide | **> 0.80** — the level is unwinnable by arithmetic | **0.42** | 0.25–0.65 |

## How to tune this, in order

1. **`waves.md` §The scale.** `level_growth` alone is the run's difficulty. Move it first and
   alone; nothing else in this directory has as much effect.
2. **The opening.** `waves.md` §Level 1 and `economy.md` §K2′: can one tower with one tier-up
   hold level 1 wave 4? The target is 0–2 leaks.
3. **Acquisition.** `economy.md` §K1′ and `store.md` §What a shelf is worth: can the player buy
   two items at the first store and not five?
4. **Tower identity.** `towers.md` §Value per gold: one number per tower.
5. **Route shape.** `nodes.md` weights and `run-map.md` map weights: does a run take 6–7 levels
   and 2–3 non-level nodes?
6. **Hidden rules last.** They are feel, and they are the easiest thing to mistake for a fix.

**Do not tune two of the ten numbers above in the same playtest.** The diagnosis becomes
unfalsifiable, and this is a project that pays for that mistake in lessons.

## Placeholder status, tracked

| File | Placeholder banner | Worked example | Thresholds named | Edge cases | Open questions |
| --- | --- | --- | --- | --- | --- |
| `towers.md` | yes | value-per-gold check | no (cites K1′) | yes | 3 |
| `items.md` | yes | dominance check | no | yes | 3 |
| `enemies.md` | yes | threat derivation | no | yes | 3 |
| `waves.md` | yes | level 1, unit by unit; run-length durations | references K2′ | yes | 3 |
| `economy.md` | yes | **level 1 + first store, reconciled** | **K1′, K2′** | yes | 3 |
| `store.md` | yes | shelf value derivation | cites K1′ | yes | 3 |
| `nodes.md` | yes | expected offers per run | no | yes | 3 |
| `run-map.md` | yes | 5-vs-10 spread, levels per shape | no | yes | 3 |
| `hidden-rules.md` | yes | empty-handed exchange rate | no | yes | 3 |
| `reroll-and-offers.md` | yes | reroll price band | reroll band | yes | 3 |

## Known divergences in this directory

| Divergence | Status |
| --- | --- |
| `items.md` §The slot model says upgrades can be unequipped freely and returns them to the inventory; `towers.md` makes applied upgrades permanent for the run | **`towers.md` wins.** `items.md` carries a supersede banner and needs a full T-0035 → T-0038 pass, including 3-tier upgrade effects |
| `items.md` §Acquisition says "3 shelves, 60/75/90 gold"; `store.md` replaces the store entirely | **`store.md` wins.** Same follow-up pass |
| `reroll-and-offers.md` §Store describes three fixed shelves; `store.md` replaces it | **`store.md` wins.** Its offer-set ladder and perks still stand |
| `enemies.md` §Introduction schedule is labelled by "level depth" and archetype; `waves.md` re-indexes the same order onto `level_index` | **Same schedule, new labels.** No substance changed; the follow-up pass may relabel |
| `enemies.md` §Legacy conflict still describes the T-0025 test scene | Still true and still the reference for those three constants |

A follow-up `design/systems` task is needed to bring `items.md` and `reroll-and-offers.md` fully
into the T-0038 model. Nothing else in the directory cites their stale rows as authority.

## Not solving

- **No balance passes.** Nothing here has been played.
- **No content count changes.** 6 towers, 20 upgrades, 8 enemies, 9 maps are the charter's scope
  budget; changing one is a human decision recorded in an ADR.
- **No numbers for meta-progression** (deferred to G3), save files, menus, or audio.
- **No code, scenes, levels or assets.** `levels/` is `design/level`; the implementations are
  `eng/gameplay` and `eng/systems`.
