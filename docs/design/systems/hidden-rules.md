# Hidden rules — two adopted, three rejected, and why

> **G2 PLACEHOLDER.** Every number in this file is a theory-crafting default written
> before the slice exists, not a measurement. Nothing here is validated until a human
> plays a full run (G2.2). Rows marked `GUESS` have no data behind them; the last column
> names the observation that would replace the guess.

Owner: `design/systems`. Written at T-0038, 2026-11-06.

- **Number home.** This file owns the two adopted rules' triggers and parameters. The gold
  values they pay live in `economy.md`; the map weight that makes one of them possible is
  `run-map.md`; the store weights that trigger the other are `nodes.md`.
- **`DATADRIVEN`** marks a named field meant to be tuned by data, never by code.
- **Provenance.** The two adopted rules are the human's, recorded in `tasks/T-0038.md`. The
  three rejected rows are the brief's "three rejected" without restated content, so the wording
  below is `design/systems`' reconstruction of the discussion, kept so the ideas are not
  rediscovered. **Confirm or replace those three rows** — §DECISIONS_NEEDED, item 1.

## What a hidden rule is, and the discipline it must obey

A hidden rule is a **consistent, unstated adjustment** the player learns by playing. It exists
to give a run a texture that a tooltip would flatten. It is *not* a secret penalty.

| Discipline | Rule | Why |
| --- | --- | --- |
| Stated trigger | Every hidden rule has a condition written in data, computable in one expression | a rule that only lives in a designer's head cannot be tested and will drift |
| Never required to win | Removing the rule must leave a winnable game | the charter's skill-ceiling rule: knowledge and judgement carry a run, not a bonus |
| Observable | Each rule has an observation that proves it fired | `qa/critic` must be able to prove it exists |
| No punishment | Both adopted rules are **bonuses**. No hidden rule may take something away | a hidden loss reads as a bug, and the player is right |
| Felt, not advertised | The effect is shown when it happens, never as a standing promise | advertising it turns a texture into a farming route |

The last two rows are the reason the rejected list exists: each rejected candidate broke one of
them, and a studio that forgets *why* a rule was rejected ships it in the next milestone.

## Adopted 1 — Familiar ground

> **Revisiting a map in the same run activates one extra build tile.**

| Property | Value | Marker |
| --- | --- | --- |
| Name | `familiar_ground` | — |
| Trigger | A level node whose map equals the map of the **immediately previous played level** in this run | — |
| Effect | That level's `active_tiles` **+1** for this visit | `familiar_ground_bonus_tiles = 1`, `DATADRIVEN`, band 1–2 |
| Which tile | The map's **designated bonus tile** — a fixed tile in the map data, chosen by `design/level`, not by the player | `design/level` owns the tile |
| Stacking | Never accumulates across visits: a map played three times gets +1 on the second and third visits, never +2 | — |
| First visit to a map | No bonus, even if the map was played by a *different* run | the rule is per run |
| Reveal | The node's `active_tiles` **includes** the bonus, so the player sees it before committing | pillar 3 |
| Frequency | ~3.4% per level draw at `run-map.md`'s weights, i.e. **about one run in four** | `run-map.md` §Map selection |
| Failure state | None — and that is its weakness. It is a pure bonus, so it can only ever be *invisible* |

**Why it exists.** The charter bets that reusing a map with a different wave composition still
reads as fresh. Familiar ground is the *positive* half of that bet: seeing a map again is not
merely tolerable, it is a small gift. It converts reuse from an apology into a reward, which is
exactly what a map pool of 8 needs to survive a 9-layer run.

**Why it pays in tiles and not gold.** Gold is the acquisition currency and every gold source is
already a knob. A tile is the one thing the economy cannot buy (placement is free; tiles are
capped by the map), so a tile is the only reward that does not perturb `economy.md` §K1′ or the
run-level check. This is the design's cleanest bonus for exactly that reason.

**Proving it fired.** A headless check: play the same map twice in one run, and the second
visit's `active_tiles` must be exactly one greater than the first, with the extra tile at the
map's designated index. Nothing else about the level may change.

`GUESS` +1. **Would settle it:** whether a tester who *noticed* a repeat describes it as a gift
or as an error. If it reads as an error, the tile is too small to answer the feeling and the
rule should be +2 tiles or +1 tile and +15 gold — but not both, and not gold alone.

## Adopted 2 — Empty-handed bonus

> **After 3 layers without a store, the next map node grants bonus gold.**

| Property | Value | Marker |
| --- | --- | --- |
| Name | `empty_handed` | — |
| Counter | `layers_since_store`, starts at **0** at run start | — |
| Increment | +1 for every layer resolved **without visiting a store** | — |
| Reset | Set to 0 when a store node is resolved, bonus or no bonus | — |
| Threshold | Fires when the counter reaches **3** | `empty_handed_threshold = 3`, `DATADRIVEN`, band 2–5 |
| Trigger | The **next map node** (a level) pays the bonus, and the counter resets | — |
| Value | **90 gold** | `economy.md` owns the value |
| Repeatability | Every time the threshold is reached; no per-run cap | `empty_handed_max_triggers = 0` (0 = unlimited), `DATADRIVEN` |
| Reveal | Shown **when it fires**, never announced in advance | the reward must not become a target |
| Failure state | It can fire and still not save the run — see §Known limitation |

**Why it exists.** The acquisition model's failure mode is not poverty, it is *nothing to buy*:
a route of levels and no store ends with thousands of unspendable gold and a one-tower build
(`economy.md` §Run-level check). The empty-handed bonus is the only compensation in the design
for that route, and it is deliberately a *soft* one.

**Why it does not need anti-farm code.** Farming it means refusing stores, and refusing three
layers of stores to collect 90 gold costs three shelves — about 575 gold of stock each and 2–3
purchases per visit. The exchange rate is roughly **−900 gold of items for +90 gold**. The
mechanic is self-limiting by arithmetic, so it must not also be limited by a cap that would
make a genuinely unlucky route ineligible.

### Known limitation — stated, not hidden

**Gold cannot buy a tower without a store.** Levels drop upgrades, not towers (`items.md`), so a
run with **zero** store nodes keeps the single tower copy from its loadout no matter how much
gold the bonus pays. The empty-handed bonus therefore helps a run with **one or two** stores
(it pays for tier-ups and makes a late store affordable) far more than a run with **none**.

| Route | Stores | Bonus triggers | What the gold can actually buy |
| --- | --- | --- | --- |
| 7 levels | 2 | 1–2 (180 max) | two tier-ups or one late store purchase — **useful** |
| 8–10 levels | 0–1 | 2–3 (270 max) | only tier-ups on items already owned — **partially useful** |
| 5 levels | 3 | 0 | nothing; the rule never fires — **inert** |

This is a real weakness of the adopted rule and it is recorded rather than smoothed over. The
fix, if the human wants one, is not a bigger number: it is letting the bonus *take the form of*
a tier-1 tower pick when the run has no store at all. That is a design change and it is listed
in §Open questions, not smuggled into the default.

## Rejected 1 — Interest on unspent gold

| | |
| --- | --- |
| | **Rule as proposed** | Unspent gold earns **+10% at the end of each layer** |
| **Why it looked attractive** | It makes saving a decision, and it answers "gold has nowhere to go" without adding a node type |
| **Why it was rejected** | It pays for **not playing**. The acquisition model's entire claim is that gold becomes a build; interest makes holding gold outperform spending it, which inverts the pillar-1 loop. It also compounds: +10% per layer on gold held from layer 1 is **×2.36 by layer 9**, which is a second, invisible difficulty curve running against `waves.md`'s single index curve. And it lands hardest on exactly the route the design wants to punish — the store-less run — so it erases the route decision instead of rewarding a good one |
| **What would make it viable later** | Nothing that keeps "difficulty scales on level index only". A *spend-it-or-lose-it* alternative (gold above a cap converts to HQ at 25:1) keeps one curve and adds no compounding, and would need its own threshold |

## Rejected 2 — Perfect-clear bonus

| | |
| --- | --- |
| | **Rule as proposed** | **+25 gold** when a level ends with zero leaks |
| **Why it looked attractive** | It rewards clean play, and it is one line of code |
| **Why it was rejected** | A leak is already a **double loss** — no kill gold *and* an HQ point (`economy.md` §Worked example: −6 gold and −2 HQ for two leaking Runners). A bonus on top of that triples the compounding, and it makes one unlucky wave at level 2 decide the run's economy. That is precisely the failure the charter's fun hypothesis warns against: the player must lose to a choice, not to a wave they could not see. It is also a **run-long** reward for a **level-local** achievement: +25 gold at level 1 is 9% of that level's 275 income and inflates the 1.20 income-to-sinks ratio for good players only, pushing K1′ toward its ceiling through feedback rather than through choice |
| **What would make it viable later** | If clean play needs rewarding, reward it *inside* the level — an extra tier-up the level pays for — so the reward is spent where it was earned and no run-long curve moves. That is a different system, not a tweak |

## Rejected 3 — Elite telegraph

| | |
| --- | --- |
| **Rule as proposed** | An elite node reveals **which sub-boss** it carries before the player commits |
| **Why it looked attractive** | It converts a coin flip into an informed choice, which sounds strictly fairer |
| **Why it was rejected** | The elite's only decision is *"am I strong enough right now"* (`waves.md` §The elite finale). Knowing the wall turns that into an arithmetic check and the node into a fixed reward: players would take Bulwark elites with a pierce build and skip Herald elites, so one node type becomes two predictable ones. The reveal rule already gives the honest middle — the level's **dominant enemy types** — so the player knows the *shape* of the threat without being told its identity |
| **What would make it viable later** | If elites are never taken early, the fix is `sub_boss_scale_per_level` (HP scaling), which costs the gamble but keeps the node. Information is the wrong lever |

## Interaction matrix

The two adopted rules touch different systems and must not double-count:

| Situation | familiar_ground | empty_handed | Net |
| --- | --- | --- | --- |
| Revisit a map after a store | +1 tile | counter reset to 0 | tile only |
| Revisit a map on a store-less route | +1 tile | may also fire (+90) | tile + gold; legal, and the intended rescue |
| New map after 3 store-less layers | — | +90 gold | gold only |
| Store visited, then 3 levels without one | — | fires again at the fourth level | no cap |
| Two visits to the same map in a row (generator repeat) | +1 tile on visit 2 | unaffected | tile only; the second visit is not "familiar" to visit 2's own count |

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| Familiar ground on the very first level | Impossible: there is no previous played level | the trigger requires a prior level |
| Familiar ground where the map has no spare inactive tile | The bonus tile is defined in the map data, so it always exists | a bonus that cannot be applied must be caught at map authoring, not at runtime |
| Familiar ground with `familiar_ground_bonus_tiles = 0` | The rule is off; nothing else changes | the switch is the field, not a code branch |
| Elite node on a familiar map | Both apply: +1 tile and a sub-boss | they are independent rewards |
| Empty-handed counter 0 and a store is the *current* node | Visiting the store resets to 0; the node is not a level so no bonus is due | the bonus triggers on a level, never on the store itself |
| Empty-handed threshold reached during the boss layer | The boss is a level node, so it pays | the last paycheque is the one the player most needs |
| `empty_handed_threshold = 0` | Fires on every level node; legal but degenerate | a documented tuning extreme, not an error |
| A store is offered but not taken | The counter **does not** reset — visiting is resolving | "offered" is not "used"; otherwise the counter could never reach the threshold on a store-rich map |
| The run ends before the bonus triggers | Nothing is paid | no payment for a level never played |
| Both rules plus a treasure node on one layer | Legal; treasure is a separate payload | three small rewards is a good layer |

## Not solving

- **No third adopted rule at G2.** Two is the brief's number.
- **No hidden penalty of any kind.** The discipline table forbids it.
- **No hidden rule that affects the wave curve.** `waves.md` scales on `level_index` and nothing
  else; a hidden wave modifier would break that guarantee.
- **No tutorial hint, tooltip or achievement** that explains either rule. They are hidden by
  definition; showing them is a design change, not a copy change.
- **No meta-progression interaction.** These are per-run rules and G2 has no meta layer.

## Open questions for the human

1. **Confirm the three rejected rows.** The brief records that three were rejected but not their
   content, so the rows above are a reconstruction. If the actual three were different, replace
   them — the value of the list is that nobody re-proposes the same idea.
2. **Does the empty-handed bonus need to be able to grant a tower?** The known limitation is
   real: a run with no store cannot grow a build at 90 gold per three layers. Granting a tier-1
   tower pick after the second trigger would fix it and would be the first hidden rule with a
   *build* effect rather than a resource effect.
3. **Should familiar ground be visible as a marker on the node**, e.g. a small "known ground"
   glyph? It is currently folded into `active_tiles` and therefore invisible as a *rule*, which
   is correct for a hidden rule but wrong for pillar 3. This is the sharpest taste call in the
   file.
