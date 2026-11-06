# Design systems — the numbers the slice runs on

> **G2 PLACEHOLDER.** Every number in every file below is a guess made before
> the slice exists. Nothing here is validated until a human plays a full run
> (G2.2). Each file carries its own banner, its own guesses, and the observation
> that would replace each guess.

Owner: `design/systems`. Written at T-0035, 2026-11-06.

This directory is a **tuning surface**, not a specification of the finished
game. Its job is to make the slice's numbers exist in one place, so the first
playtest moves them deliberately instead of hunting for literals in code.

## The six files

| File | One-line purpose |
| --- | --- |
| [`towers.md`](towers.md) | The 6 towers and their 3 tiers: damage, rate, range, cost, upgrade cost, and what each tier visibly changes. |
| [`items.md`](items.md) | 20 tower items, their slot and stacking rules, and the proof that none is strictly better than another. |
| [`enemies.md`](enemies.md) | 5 normal enemies, 2 sub-bosses, 1 boss: speed, health, armour, threat cost, and the player behaviour each punishes. |
| [`waves.md`](waves.md) | Wave curves per level archetype and the rule that generates a wave's composition from a level's parameters. |
| [`economy.md`](economy.md) | Gold in and out, HQ health and leak damage, a reconciled worked example, and the two thresholds that decide whether the opening works. |
| [`reroll-and-offers.md`](reroll-and-offers.md) | How many offers, what weights them, what a reroll costs, and the price band that keeps the reroll a decision. |

## Conventions every file follows

| Convention | Rule |
| --- | --- |
| **One home per number** | Each number is owned by exactly one file (see below). A file that needs another's number cites it and marks the copy. If a copy and its home disagree, **the home wins**. |
| **Units** | gold: integer. damage: integer per hit, floored after modifiers. rate: seconds, 2 dp. range: px. speed: px/s. threat: 0.5 steps. |
| **`GUESS` marker** | A number with no data behind it. Every file names the observation that would settle it. |
| **No implementation** | These files say what must be true, never what a class or node is called. |

### Number ownership

| Number | Home |
| --- | --- |
| Tower damage, rate, range, cost, upgrade cost, sell refund | `towers.md` |
| Item effects, slot rules, modifier caps | `items.md` |
| Enemy HP, speed, armour, slow resistance, threat cost, pack size | `enemies.md` |
| Wave counts, budgets, spawn intervals, composition weights, unit caps | `waves.md` |
| All gold values, HQ health, leak damage, heal price | `economy.md` |
| Offer counts, offer weights, reroll prices, perk values, store prices | `reroll-and-offers.md` |

### The ten numbers the slice is actually built on

Everything else follows from these. If only ten numbers get tuned, tune these:

| # | Number | Value | Home |
| --- | --- | --- | --- |
| 1 | Starting gold | 120 | `economy.md` |
| 2 | Arrow tier-1 cost | 70 | `towers.md` |
| 3 | Arrow tier-1 DPS | 20.0 | `towers.md` |
| 4 | Grunt HP | 40 | `enemies.md` |
| 5 | Grunt speed | 60 px/s | `enemies.md` |
| 6 | Wave-1 spawn interval | 2.2 s | `waves.md` |
| 7 | Wave-1 budget | 6 threat (6 Grunts) | `waves.md` |
| 8 | HQ max health | 30 | `economy.md` |
| 9 | Wave-clear bonus | 12 gold | `economy.md` |
| 10 | First reroll price | 30 gold | `reroll-and-offers.md` |

Numbers 1–3 set the opening's affordability; 4–7 set whether one tower can hold
wave 1; 8–10 set whether a mistake is survivable and whether the between-level
choice costs anything.

## The two thresholds that break the opening

Both live in `economy.md` with their arithmetic. Summary:

| Threshold | Unwinnable if | Trivial if | Current | Healthy band |
| --- | --- | --- | --- | --- |
| **K1** — first tower cost vs gold available before wave 2 (156) | cost **≥ 157** | cost **≤ 40** | 70 (0.45 of budget) | 55–94 |
| **K2** — wave-1 spawn interval vs one tower's kill rate (0.5 kills/s) | interval **< 1.0 s** | interval **> 4.0 s** | 2.2 s | 1.6–2.6 s |

## How to tune this, in order

1. Fix the opening first (`economy.md` §Worked example, §K1, §K2). A run that
   cannot start tells you nothing about the rest.
2. Then tower identity (`towers.md` §DPS per gold). One number per tower.
3. Then waves (`waves.md`): budget before interval, because budget changes *what*
   the player must answer and interval only changes *how fast*.
4. Last, the meta layer (`items.md`, `reroll-and-offers.md`). Items and offers
   are worthless until a run survives its first level.

**Do not tune two of the ten numbers above in the same playtest.** The
diagnosis becomes unfalsifiable, and this is a project that pays for that
mistake in lessons.

## Placeholder status, tracked

| File | Placeholder banner | Worked example | Thresholds named | Edge cases | Open questions |
| --- | --- | --- | --- | --- | --- |
| `towers.md` | yes | DPS-per-gold check | no (none owned) | yes | 3 |
| `items.md` | yes | dominance check | no (none owned) | yes | 3 |
| `enemies.md` | yes | threat derivation | no (none owned) | yes | 3 |
| `waves.md` | yes | level 1, unit by unit | references K2 | yes | 3 |
| `economy.md` | yes | **waves 1–3, reconciled** | **K1, K2** | yes | 3 |
| `reroll-and-offers.md` | yes | reroll price band | reroll band | yes | 3 |

## Not solving

- **No balance passes.** Nothing here has been played.
- **No content count changes.** 6 towers, 20 items, 8 enemies, 9 maps are the
  charter's scope budget; changing them is a human decision recorded in an ADR.
- **No numbers for meta-progression** (deferred to G3), save files, menus, or
  audio.
- **No code, scenes, levels or assets.** `levels/` is `design/level`; the
  implementations are `eng/gameplay` and `eng/systems`.
