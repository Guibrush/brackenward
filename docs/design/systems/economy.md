# Economy — gold, HQ, and the arithmetic of the first three waves

> **G2 PLACEHOLDER.** Every number in this file is a guess made before the slice
> exists. Nothing here is validated until a human plays a full run (G2.2). Rows
> marked `GUESS` have no data behind them; the last column names what would
> replace the guess.

Owner: `design/systems`. As of T-0035, 2026-11-06.

- **Number home.** This file owns gold (all sources and sinks), HQ health, leak
  damage, heal price, wave-clear and level-completion bonuses. Tower costs are
  cited from `towers.md`; enemy stats from `enemies.md`; reroll prices from
  `reroll-and-offers.md`.
- **One worked example is authoritative.** §Worked example is computed from
  `waves.md` §Level 1. If that table changes, this section is recomputed before
  anything else is tuned against it.
- **Two thresholds decide whether the opening works at all** (§K1, §K2). They
  are the reason this file exists before the code does.

## Currencies and lifetime

| Currency | Earned | Spent | Lifetime |
| --- | --- | --- | --- |
| Gold | kills, wave clears, level completion | towers, upgrades, heals, rerolls, store | **one run**, reset at the start of a new run (charter) |
| HQ health | heals | enemy leaks | **one run**, carried level to level inside it |

There is **no gold cap** and no persistent currency at G2 (meta-progression is
deferred to G3 — T-0037). Nothing is banked across a run: leftover gold dies
with it.

## Gold in

| Source | Value | When | Note |
| --- | --- | --- | --- |
| Starting gold | 120 | run start | the "one tower and a mistake" budget |
| Grunt kill | 4 | on death | baseline: 1 gold per 10 HP |
| Runner kill | 5 | on death | 1.25× a Grunt for 0.6× the HP — speed is paid for |
| Shieldback kill | 8 | on death | armour is paid for |
| Swarmling kill | 1 | on death, each | a pack of 6 pays 6 |
| Bloom kill | 10 | on death | the healer pays best, so it is worth diving for |
| Bulwark kill | 30 | on death | sub-boss |
| Herald kill | 20 | on death | sub-boss |
| Warden kill | 100 | on death | the boss pays for the next run's start, which does not exist yet — it is a trophy |
| Wave clear | 12 | wave ends, **leaked or not** | an income floor that does not punish learning |
| Level complete | 40 (standard), 80 (boss level) | level ends | the level-transition buffer |

`GUESS` every gold value. **Would settle it:** the "unspent gold at the end of
each level" measurement in §Run-level check — if players finish levels holding
more than one tower's cost, kill gold is ~15% too high.

**A leaked enemy pays nothing.** This is the single most important economic
rule: leaking costs a point *and* the kill gold, so a leak is a double loss and
a bad first wave compounds. It is also why §K1 and §K2 use the *shortest* wave
as their test case (L-030): a weak opening cannot recover, it only falls behind.

## Gold out

| Sink | Cost | When | Source |
| --- | --- | --- | --- |
| Arrow tower | 70 | build phase | `towers.md` |
| Ballista tower | 110 | build phase | `towers.md` |
| Mortar tower | 100 | build phase | `towers.md` |
| Rime tower | 85 | build phase | `towers.md` |
| Beacon tower | 90 | build phase | `towers.md` |
| Bramble tower | 60 | build phase | `towers.md` |
| Upgrades | 50–150 per step | build phase | `towers.md` |
| Sell refund | **60% of invested** | build phase | `towers.md` |
| Heal the line | 40 gold for **+5 HQ** | between levels only, max 2 per step | this file |
| Reroll an offer set | 30 / 45 / 60 (3rd reroll) | between levels | `reroll-and-offers.md` |
| Store item | 60 / 75 / 90 by rarity | between levels | `reroll-and-offers.md` |

`GUESS` the heal at 40 for 5. **Would settle it:** count heals bought per run in
the first playtest. Zero heals means HQ is too generous; more than four means
HQ is too thin and the run is being lost to chip damage rather than to a
decision.

## HQ health and leak damage

| Quantity | Value | Reason for the number |
| --- | --- | --- |
| HQ max health | **30** | see the leak-budget check below |
| HQ regen inside a level | **none** | damage taken is real; only gold undoes it |
| Heal between levels | 5 per 40 gold, max 2 per step | competes directly with an upgrade |
| HQ at 0 | level lost → **run lost** | charter: failing a level ends the run |

Leak damage by enemy (source: `enemies.md`; restated because the economy is what
it costs):

| Enemy | Leak damage | Share of full HQ | Note |
| --- | --- | --- | --- |
| Grunt, Runner, Shieldback, Swarmling, Bloom | 1 | 3.3% | 30 leaks end the run |
| Bulwark | 3 | 10% | a sub-boss leaking is a real loss |
| Herald | 3 | 10% | same |
| Warden | 10 | 33% | the boss leaking is survivable **once** |

**HQ budget check** — the arithmetic that picked 30. A typical 8-level run's
"expected leak allowance" per archetype:

| Archetype | Levels in an 8-level path | Leaks each | Total |
| --- | --- | --- | --- |
| Opening | 2 | 0–2 | 0–4 |
| Pressure | 3 | 2–3 | 6–9 |
| Peak | 2 | 3–5 | 6–10 |
| Boss | 1 | 0–6 trash | 0–6 |
| **Total** | 8 | | **12–29** |

HQ 30 against an expected 12–29 means an **average player finishes the run with
1–18 points left and never has to heal**, while a sloppy one must spend 40–80
gold on heals — which is one upgrade, not a whole tower. That is the intended
tension. If playtesting shows the average player finishing below 8 HQ, HQ should
be 35; if nobody ever heals, it should be 25.

## Worked example — level 1, waves 1 to 3, average play

**Definition of "average play"** used here: clears each wave with **0–2 leaks**,
buys the cheapest useful thing in each build phase, and does not reroll.
Level 1's composition is fixed in `waves.md` §Level 1; gold values above.

### The ledger

| Step | Action | Gold in | Gold out | Gold left |
| --- | --- | --- | --- | --- |
| Run start | — | +120 | — | **120** |
| Build phase 1 | Arrow tower (70) | — | 70 | **50** |
| Wave 1 | 6 Grunts × 4, plus wave clear 12 | +36 | — | **86** |
| Build phase 2 | Arrow tower (70) | — | 70 | **16** |
| Wave 2 | 6 Grunts × 4 + 3 Runners × 5, plus clear 12 | +51 | — | **67** |
| Build phase 3 | Arrow #1 → tier 2 (60) | — | 60 | **7** |
| Wave 3 | 8 Grunts × 4 + 1 Shieldback × 8, plus clear 12 | +52 | — | **59** |

### The totals, reconciled

| Line | Value |
| --- | --- |
| Opening balance | 120 |
| Gold earned in waves 1–3 | 36 + 51 + 52 = **139** |
| Total available | 120 + 139 = **259** |
| Gold spent | 70 + 70 + 60 = **200** |
| Closing balance | **59** |
| **Check** | 259 − 200 = 59 ✓ |

No gold is earned outside these three lines, and no gold is spent outside those
three purchases. **The totals reconcile to the unit.**

### The same three waves with two leaks

The variant matters because it is the case that decides whether the opening
forgives a mistake. Two of wave 3's eight Grunts leak: 6 die, 6 pay, and each
leak costs a point of HQ.

| Line | Clean | 2 Grunts leak in wave 3 |
| --- | --- | --- |
| Opening balance | 120 | 120 |
| Wave 1 income | 36 | 36 |
| Wave 2 income | 51 | 51 |
| Wave 3 income (6 × 4 + 8 + 12) | 52 | **44** |
| Gold earned, waves 1–3 | 139 | **131** |
| Total available | 259 | **251** |
| Gold spent | 200 | 200 |
| Closing balance | **59** | **51** |
| HQ after wave 3 | 30 | **28** |

The double loss is visible in one comparison: **−8 gold and −2 HQ for the same
two enemies**, and the gold is what would have bought the wave-4 tower. A single
leak in wave 1 is worth more than a mistake in wave 6, because it is the gold
that compounds.

## What an average player can afford by wave N (level 1)

Cumulative gold, ignoring nothing and assuming the purchases in the ledger
above:

| Before wave | Gold available | Can afford | Leaves |
| --- | --- | --- | --- |
| 1 | 120 | 1 Arrow (70) | 50 |
| 2 | 156 | 2 Arrows (140), or Arrow + Bramble (130) | 16 |
| 3 | 207 | 2 Arrows + one tier-2 upgrade (200) | 7 |
| 4 | 259 | 3 towers (240), or 2 towers + 1 upgrade (200) | 59 |
| 5 | 322 | 4 towers (310) | 12 |
| 6 | 406 | 5 towers (390), or 4 towers + 1 upgrade | 16 |
| after 6 | 550 | 5 towers + 2 upgrades (~500) or 4 towers + 3 (~510) | ~40 |

Read the table as the answer to "is the player ever stuck?" — **no**, but at
waves 2 and 3 they are within 20 gold of a decision's edge, which is the squeeze
this design wants (pillar 1: the layout is a choice, not a purchase list).

## K1 — the first tower must be affordable, and not free

**The number under test:** `C_first`, the cost of the tower a sane player opens
with — **Arrow, 70 gold**. (`C_min` is Bramble at 60, but Bramble is not an
opener; see K2's weakest case.)

**The budget it is tested against:** gold available before wave 2,
`start_gold + wave-1 income = 120 + 36 = 156`.

| Direction | Threshold | What happens if crossed | Current value |
| --- | --- | --- | --- |
| **Too expensive → unwinnable** | `C_first ≥ 157` | no tower can be placed before wave 2; wave 1 leaks all 6 (HQ 30 → 24, −20%) and pays 12 gold instead of 36; wave 2 is then unaffordable too; the run dies inside level 1 | 70 (2.2× under the line) |
| **Too cheap → trivial** | `C_first ≤ 40` (`start_gold / 3`) | three towers before wave 1; wave 1's 240 HP dies to 60 DPS in 4 s of fire; waves 1–3 need no decision at all, so the pillar-1 choice does not happen | 70 (1.75× over the line) |

**Healthy band:** 55–94 gold, expressed as `C_first / (start + wave-1 income)`
between **0.35 and 0.60**. At 70 the ratio is **0.45** — mid-band.

`GUESS` the band. **Would settle it:** a player who buys the wrong first tower
(this is the *weakest* case, L-030) should lose the level, not the run. If they
lose the run, the band is too tight at the top; if they recover without
changing anything, it is too tight at the bottom.

## K2 — wave 1 must be holdable by exactly one tower, and not by half a tower

This is the threshold that decides whether the game has a first minute.

**Kill capacity.** One Arrow tier 1 kills a Grunt in `40 / 20 = 2.0 s`. A Grunt
spends `181 / 60 = 3.0 s` inside that tower's 96 px range (`enemies.md` §Time on
the lane). So one tower processes **1.5 kills per coverage window**, i.e.
**0.5 kills/s** while the stream is inside its range.

**Arrivals.** `1 / spawn_interval`. Wave 1 uses **2.2 s** → **0.4545/s**.

| Direction | Threshold | What happens if crossed | Current value |
| --- | --- | --- | --- |
| **Too tight → unwinnable** | `spawn_interval < 1.0 s` (arrivals ≥ 2× capacity) | with only one tower affordable, half of every wave leaks; wave 1 loses 3 of 6 (HQ 30 → 27) *and* 12 gold, so the second tower never arrives; the level dies at wave 3 | 2.2 s (2.2× the line) |
| **Too loose → trivial** | `spawn_interval > 4.0 s` (arrivals ≤ 0.5× capacity) | the tower is idle half the time; waves 1–3 clear with zero purchases, so the player never learns placement or income | 2.2 s (0.55× the line) |

**The same threshold as an HP-pool check**, which is how a designer will
actually look at it: one Arrow tier 1 delivers **60 damage per pass** (`20 DPS ×
3.0 s`), so wave 1's **240 HP** pool must sit between **192 HP** (every enemy
dies in under half a pass: no decision) and **480 HP** (`8 enemies × 60`: no
enemy can be one-passed by a single tower). At 240 it is **50%** — one clean
pass per kill, no overkill, and any second tower is slack rather than a rescue.

**Weakest case (L-030), and it fails deliberately.** The cheapest tower,
Bramble at 60, is the *wrong* opener: its 48 px radius cuts a 72 px chord of a
lane 32 px away, giving 1.19 s of contact against a 2.67 s time-to-kill. It
cannot kill a single Grunt in one pass, so a player who opens with the cheap
tower loses wave 1's kills. Two rulings follow, both for the human:

1. **Accept it.** Bramble is an area tool; its tile must show the damage radius
   plainly so the choice is informed (pillar 3), and the shop line must say
   "area, very short range".
2. **Do not accept it.** Raise Bramble's tier-1 radius to 64 px, which makes it
   a slower, shorter Arrow with area upside. That is a real tower identity loss.

Recommendation: **1**, because a cheap trap that is *visibly* short-ranged is a
readability success, not a fairness failure.

## Run-level check — income versus sinks

Placed towers **do not carry between levels** (see Open questions — this is an
assumption, and the whole economy rests on it). The player re-buys a layout each
level; gold, owned tower types and items carry.

| Depth | Archetype | Level income (estimate) | Cost of the level's layout | Headroom |
| --- | --- | --- | --- | --- |
| 1 | opening ×1.00 | 430 | 240 (3 towers) | +190 |
| 2 | opening ×1.10 | 462 | 330 (3 towers + 1 upgrade) | +132 |
| 3 | pressure ×1.00 | 722 | 430 | +292 |
| 4 | pressure ×1.08 | 769 | 520 | +249 |
| 5 | pressure ×1.16 | 818 | 640 | +178 |
| 6 | peak ×1.00 | 1195 | 800 | +395 |
| 7 | peak ×1.08 | 1279 | 900 | +379 |
| 8 | boss ×1.00 | 1051 | 1050 | +1 |
| **Total** | | **6726** | **4910** | **+1816** |

Add ~300 of optional spending (two heals, three rerolls, one store item) and the
run closes at **≈1.29 gold in for every gold out**.

| Check | Target band | Current | Verdict |
| --- | --- | --- | --- |
| Income / mandatory sinks | 1.10–1.30 | 1.37 | one notch generous |
| Income / all sinks | 1.10–1.30 | 1.29 | inside the band |
| Unspent gold at level end | ≤ 1 tower's cost (≤ 110) | 130–400 | **too rich late** |

`GUESS` all of it. **Would settle it:** measure unspent gold at the end of each
level in the first full run. If it exceeds 110 at more than two levels, the dial
is **kill gold −10%** (not tower cost — that would move K1).

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| Gold would go negative | illegal: the purchase is refused with a reason, gold unchanged | a negative balance makes every later check meaningless |
| Purchase exactly equals balance | allowed; balance hits 0 | refusing an exact buy is the most common off-by-one in economy code |
| Sell refund rounding | `floor(0.60 × invested)`; every current tower already yields an integer | a 0.5 gold coin is a UI problem and a test flake |
| Leak on the last enemy of a wave | the wave-clear bonus is still paid | the player's income floor must not depend on a coin-flip kill |
| HQ reaches 0 mid-wave | the level ends immediately; no further kills pay, no wave bonus | otherwise a dead run can still earn gold |
| Kill gold on overkill | paid once per enemy, at death | two towers claiming one kill is a ledger bug |
| Wave 0 / level 0 / negative wave index | illegal; the loader rejects | index arithmetic on an empty wave divides by zero in `1/interval` |
| Selling every tower mid-level | legal, and the player then has only gold and the lane | must not crash the wave scheduler (the wave still runs) |
| Zero gold at a build phase | legal: the player watches | the game must never present a purchase it will refuse silently |
| Gold at run end | discarded | charter: gold lives only inside a run |
| HQ heal above max | clamp at max, and do **not** charge the excess | charging for nothing is the worst possible bug to a player |
| Two heals in one step | allowed (max 2); a third is refused with a reason | max 2 keeps the price an upgrade's rival |

## Not solving

- **No persistent/meta currency.** Deferred to G3 (T-0037, charter).
- **No interest, no gold gift between levels, no sell-back of items.**
- **No store economy beyond three fixed shelves** (`reroll-and-offers.md`).
- **No difficulty-scaled prices.** One price list.
- **No balancing of a 10-level run.** The run-level check is computed for the
  8-level path in `waves.md`; a 9- or 10-level path needs its own table.
- **No answer to whether leftover gold converts to anything at run end** — the
  charter leaves it undecided, and it is a G3 question.

## Open questions for the human

1. **Do placed towers carry between levels?** The charter says "carry the build
   you earned into the next one", but every level is a different map with
   different buildable tiles, and this whole economy assumes a **fresh layout
   each level**. If towers *do* carry, per-level sinks collapse and the income
   table above is roughly 3× too generous. This is the highest-impact unknown
   in the file.
2. **Is 120 starting gold right for a player's second run** (no meta-progression
   at G2, so every run starts identically)? A higher start makes the opening
   softer for everyone; a lower one makes K1 the whole first level.
3. **Should the wave-clear bonus be flat** (12) or scale with the wave index?
   Flat is readable and does not reward fast clearing; scaling rewards good
   play but makes the arithmetic in this file a moving target.
