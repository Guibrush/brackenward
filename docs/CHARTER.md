# Charter

Status: **signed at G0 — 2026-11-04**
Owner: human. Agents may propose edits; only the human approves them.

Everything in this document is binding on every agent. If a task contradicts
it, the task is wrong, not the charter.

---

## One-line pitch

> A run-based tower defence: each run is a defence you draft from nothing, and when
> the line breaks you lose the layout, not the knowledge.

## Audience and platform

- Who plays this, and in what mood: Sitting-room players, controller in hand, in a
  calm evening session after work. Easy to start with no homework, and deep enough
  at the far end that a motivated player sinks dozens of hours into it.
- Platform: Windows on Steam first. Nintendo Switch is a stretch goal, not a
  commitment. Built in Godot.
- Session length: 15–30 minutes is the norm, one run per sitting; a motivated player
  can chain runs for several hours without the game asking them to stop.
- Comparable games (chosen per discipline rather than one pair, because the genre
  fusion needs a reference on each side plus one for feel):
  - **Primary — Slay the Spire.** The run *is* the reference: a sequence of discrete
    levels, procedural branching choices between them, a build that grows by
    choosing between legible but partly hidden options. Information asymmetry is
    what makes the choice interesting, not what makes it fair.
  - Tower defence — **Kingdom Rush**, **Bloons TD 6**: readable lanes, escalating
    waves, towers identifiable from a silhouette.
  - Feel and art — **Kingdom Rush**, **Stardew Valley**: warm, legible, handmade;
    nothing grimdark for its own sake.

Design constraint carried by the above: the game must be fully playable on a
gamepad from the first prototype, since console is the stated mood and Switch is
the stretch goal. Keyboard and mouse are an equal port, not an afterthought.

## Three pillars

What the game is *for*. Every feature must serve at least one. A feature that
serves none is cut.

**Ranked.** When two pillars conflict, the lower number wins: 1 beats 2, 2 beats 3,
and 1 beats 3. The ranking is what makes this list binding instead of decorative.

1. **The run is the build.** Your defence is drafted wave by wave and dies with the
   run; what carries over is your judgement, not your towers. *Felt as:* "this
   layout is mine, and next run I'll build it differently."
2. **One more run.** Depth comes from how a small set of towers, perks, and enemies
   interlock, not from a long unlock list. *Felt as:* the itch to try "what if these
   two together", and the next plan forming before the current run has ended.
3. **Readable at a glance.** Threat, coverage, and the weakest point in the line are
   legible in one look, with no tooltip archaeology. *Felt as:* confidence — you lose
   because you chose wrong, not because you could not see.

### Meta-progression (a commitment, deliberately not a pillar)

Permanent unlocks — perks, abilities, and towers — carry over between runs. This is
not in the pitch or the pillar list because it is not what the game is *for*; it is
how session 20 stays interesting. It is budgeted in Scope budget below, and it must
never outrank the pillars in a conflict.

**Skill ceiling rule:** a player with deep knowledge of the game must be able to win
a run with no unlocks at all. Unlocks widen the options available; they are never
the reason a run becomes winnable. Judgement and knowledge remain what carries
over, which is what keeps pillar 1 first.

## Non-goals

Explicitly not being built. This list protects the schedule more than the
pillars do. Add to it freely; remove from it deliberately.

- No story campaign, cutscenes, or dialogue. Narrative is names, flavour text, and
  enemy silhouettes at most.
- No multiplayer, co-op, or online leaderboards before G2.
- No live-service hooks: no dailies, seasons, battle pass, or rotating shop.
- No mod support or user-generated content.
- No mobile or web build. Switch happens after G2, and only if the Windows build is
  already solid.
- No 3D, no HD-2D, no shader work that fights the pixel-art look.
- No large meta-progression catalogue at G2. Permanent unlocks stay a small set,
  but their *shape* — flat list, tree, shop, something else — is deliberately
  undecided at G0 and is a design decision, not a charter commitment.
- No systems that need netcode or persistence beyond a local save file.

## Core loop

> Pick a route between levels, commit to what the run offers you, then defend the
> map you landed on — planning freely between waves, holding the line during them —
> and carry the build you earned into the next one.

### Run structure (settled at G0)

- A **run** is 5–10 levels on a branching map with routes, in the manner of Slay
  the Spire. Both numbers are rough: level count is a placeholder to be re-measured
  once something is playable.
- A **level** is one hand-made tower defence map, cleared by surviving a fixed
  number of waves. The player's HQ sits at the end of the path; each enemy that
  reaches it takes health from it, and at zero health the level — and therefore the
  run — is lost.
- **Failing a level ends the run.** There is no retry inside a run.
- **HQ health carries for the whole run.** Damage taken at level 2 is still missing at
  level 5, so healing competes directly with buying upgrades between levels.
- **The run ends at a final level holding a boss wave.** What that wave contains — one
  boss unit, or a boss plus escorts — is deliberately undecided at G0; it gets
  settled by playing. The final level and its boss need not be the same every run,
  and a run may offer more than one boss level to choose between.
- **Between waves** the player plans without time pressure: place, move, sell,
  upgrade, change composition.
- **During a wave** towers and perks are locked; only behaviour changes are allowed
  (target priority, ammo type, and similar).
- **The build grows in two places.** Inside levels: waves drop gold and, rarely,
  upgrades or perks that go straight to the inventory without a choice. Outside
  levels: events (bosses, heroes) grant a pick from a randomly offered set of
  towers, perks, or upgrades, and the player may visit stores.
- **Drops reinforce, events define.** Enemy drops strengthen the build the player
  already has; event picks are what set the build's playstyle.
- **Between-level offers cannot be skipped** — one must be chosen; they may be
  rerolled for gold.
- **Currencies.** Gold exists only inside a run and is lost when the run ends
  (whether remnants convert into anything is undecided). At least one persistent
  currency funds out-of-run spending; probably more than one.
- **Hidden information is deliberate** and serves pillar 2: the effect of a choice
  is visible, the specific thing you get may not be.
- **The map is revealed as you go**, but always with enough lookahead to choose with
  partial knowledge. A few nodes are visible from the start regardless of distance:
  lures that pull the player toward a route without revealing the path between.

## Fun hypothesis

The single claim this prototype exists to test, written so it could be proven
wrong.

> Players will treat the decisions that shape and then apply a build — what they
> choose between levels, and what they do with it between waves — as the
> interesting part of a run rather than an interruption between fights, because
> those decisions visibly change what the next defence can be. Observable by
> testers explaining a lost run in terms of route, build, and wave plan rather than
> a misclicked tower, and by them giving those decisions real thinking time instead
> of clicking through them.

If the vertical slice shows this is false, the design changes. That is the
prototype succeeding, not failing.

### How it gets tested at G2

- **Five testers**, friends and family for now. At least three with no tower defence
  experience, so the readability pillar is tested and not assumed.
- **Talk-aloud sessions**, notes taken in writing, one line per observation.
- **Behaviour over opinion.** Record time spent on between-level and between-wave
  decisions, and count voluntary restarts. Friends and family will say they enjoyed
  it; what they *do* is the evidence.
- **The failure signal** is unambiguous: testers describe their runs purely in terms
  of tower placement, and the map reads to them as a menu between fights. If that
  happens, the fusion is not doing its job and the design changes before G3.

## Scope budget

Everything below is scoped to **the G2 vertical slice**, not to the finished game.
Content volume for G3–G5 is decided after the slice, because the slice is the
experiment that answers how much content the game actually needs.

| Item | Budget | Notes |
| --- | --- | --- |
| Playable length at G2 | one complete run | 15–30 minutes is a design guideline, not a gate criterion |
| Towers | 6, each with 3 tiers | tier shown as an overlay or glyph on one sprite, not 18 sprites |
| Tower items | 20 | mix-and-match, equipped on towers |
| Enemies | 5 normal, 1 boss, 2 sub-bosses, 1 HQ | 9 sprite sets |
| Distinct levels | 9 | 8 standard maps plus 1 boss map |
| Music tracks | 4 | menu, tower defence levels, branching map, boss |
| Sound effects | 48 | UI 10, towers 10, enemies and bosses 8, economy 4, flow 5, status effects 6, map 3, plus 2 variants |
| Generation budget at G2 | ≤200 PixelLab generations (ADR-0008, raised from ≤60), ≤52 ElevenLabs calls | current plan 40 generations + $10 credit; the human funds the balance before generation. 52 calls = 48 one-shots + 4 music tracks |
| Systems (mechanics that need code) | 10 | each one is a risk, and none is cut at G0 |

**No calendar commitment.** This is a self-directed project run at its owner's pace.
Progress is gated by evidence, not by dates, and no deadline is promised to anyone.
See ADR-0003.

**The 10 systems**, in build order: wave spawner; map node graph with progressive
reveal and permanent lures; tower placement and tier upgrades; item equip system;
enemy pathing, leaks, and HQ health carried across the run; between-level choice
generation with reroll; economy and store; meta-progression persistence for
permanent unlocks and persistent currency; boss and sub-boss behaviour; run
lifecycle and level transitions.

**Map reuse is deliberate.** A run is 5–10 levels against 9 maps, so maps repeat
within a run. That is a bet the slice is meant to test: whether different wave
compositions and entry points on a reused map still read as fresh. If they do not,
the fix is more maps or shorter runs, and that is a scope decision taken with
evidence.

**Cost note, measured 2026-11-12.** The vendor's `get_balance` reported a trial plan of
40 generations (16 used, 24 remaining) with $10.00 credits, and the per-generation credit
price is not exposed by any image tool. ADR-0008 raises the G2 ceiling to ≤200 for the
animated enemy set and records the stop condition; topping up the plan is a human action,
not assumed by this table.

## Codename candidates

The repository name comes from this list, chosen at G0. It should describe the
prototype without committing to a genre.

**Chosen at G0: `brackenward`.**

1. **`brackenward`** — chosen. Overgrown ground and a warding defence in one word;
   reads as a place, which suits a game about holding a series of them. Valid as a
   repository name: lowercase, single word, no punctuation.
2. **`peatlight`** — warm and quiet, but a low-energy name for a game with a boss.
3. **`fenward`** — clear and clean, though the connotation is damp and muted.

**Name check (2026-11-04).** Web search found no existing video game under any of
the three. This is *no obvious collision*, not trademark clearance: search cannot
prove a mark is unregistered. A proper check (USPTO/EUIPO, Steam name availability)
belongs before the name is used publicly, and before G1 creates the repository.
Rejected on collision grounds during the check: `lantern-run`, `bramblehold`,
`wavewright`, `wickward`, `mothkeep`, `tallowgate`, `copperlane`, `rushlight`.

## Decisions

Architecture and design decisions live in `docs/adr/`. This document holds only
the commitments above.
