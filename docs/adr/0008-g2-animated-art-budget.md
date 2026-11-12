# ADR-0008 — Raise the G2 PixelLab generation ceiling for animated enemies

Date: 2026-11-12
Status: accepted (studio-lead; human approved the option) — **superseded in part by
ADR-0009**: G2 ships static enemy sprites; the animation budget and the 200 ceiling are
withdrawn.
Deciders: human, on studio-lead's recommendation

## Context

`docs/CHARTER.md` caps G2 at **≤60 PixelLab generations**. The vendor's `get_balance`
(2026-11-12, free call) reports the real terms:

- plan: trial, 40 generations total, **16 used, 24 remaining**;
- $10.00 credits; a 20-generation daily bonus unlocks only at zero;
- the charter's 60 was never available on that plan.

The art audit priced the animated G2 set the human requires:

- 8 enemies (5 normal, 2 sub-bosses, 1 boss), 4 directions, five clips
  (idle 2 / walk 4 / attack 4 / hurt 1 / death 4): **~168 generations**;
- 5 missing towers on the style-anchor route: **25 generations**;
- total **~193** before retries. The one shipped tower cost 7 generations against a
  2-generation budget, so retries are real and unbudgeted.

The human rejected the static-enemy cut and requires animation at G2. The cost is a
charter decision, not an art call.

## Decision

1. **The G2 PixelLab ceiling is raised from ≤60 to ≤200 generations.** The
   40-generation plan and the 20-generation daily bonus are the current funding; the
   human funds the remaining plan/credits before generation starts.
2. **The G2 art scope under the new ceiling** is 6 towers (the shipped arrow plus five
   new, style-anchor route) and 8 enemies with full 4-direction animation sets, at
   ~193 accepted generations. Retries count against the 200. If the ceiling is reached
   with art incomplete, generation **stops** and returns to the human with the balance
   and what is left; the ceiling is not raised silently.
3. **Style decisions that stand:** 4 directions; the `art/STYLE.md` animation sets;
   tower tiers as a shared pip glyph (per-tower tier silhouettes stay deferred);
   sub-boss canvas size is `art/director`'s call within 32-96 px and is recorded in the
   manifest; static single-direction towers.
4. **The ledger is the vendor counter.** The manifest's 8 recorded generations
   undercount the vendor's 16; the 8 unrecorded generations and the 6 unregistered art
   files are reconciled by `art/pixel` (registered as evidence or deleted) before the
   next batch.
5. **No generation before `get_balance` confirms the headroom.** The batch order is
   towers first (5 sprites, `art/director` review, then the atomic scene wiring), then
   enemies in normal/sub-boss/boss order.

## Consequences

**Intended:** animation ships at G2, which serves pillar 3 (readable at a glance) and
the charter's Kingdom Rush/Slay the Spire references. The spend is bounded by a ceiling
the human set, with a stop condition rather than an open tab.

**Accepted costs:** the ceiling is 3.3× the old one and the art batch is the largest
single spend of the milestone. The static plan (33 generations) is superseded for
enemies; the towers keep the static single-direction rule.

**Risks:** the measured 3.5× retry rate on the arrow tower could exhaust 200 before all
eight enemies are animated. Mitigation is the staged order and the stop condition above,
not a larger ceiling.

## Evidence

- `art/pixel` audit 2026-11-12: `get_balance` = 24 remaining / 16 used / 40 total;
  full animation ~168 gens; towers 25; minimal down-only 16-19; static set 23.
- `art/manifest.json`: arrow tower 7 generations, spend history; 8 recorded total.
- `docs/lessons/archive-G1.md:33`: the 31-generation balance on 2026-11-04.
- `art/STYLE.md`: tower 64×64, enemies 32×32, bosses 96×96, directions 4, animation
  sets 2/4/4/1/4.
