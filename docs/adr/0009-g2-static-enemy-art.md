# ADR-0009 — G2 ships static enemy sprites; animation waits for approval

Date: 2026-11-12
Status: accepted (studio-lead; human decision)
Deciders: human
Supersedes: ADR-0008, animation part only

## Context

ADR-0008 raised the G2 generation ceiling to ≤200 to fund full 4-direction enemy
animation (~168 generations) on top of five tower sprites. On reflection the human
reversed that: animating all eight enemies before the static sprites have been seen and
approved is the wrong order. Animation is deferred until the static set is approved.

The audit's pricing makes the revised scope cheap: eight static enemies as
`create_character` sets (4 directions per call, 1 generation each) is **8 generations**,
not 23 individual images and certainly not 168 clips. With the five tower sprites
(~25 on the style-anchor route) the G2 art batch is **~33 accepted generations plus
retries**, which fits the charter's original ≤60 ceiling.

## Decision

1. **G2 enemy art is static.** One accepted sprite set per enemy (5 normal, 2 sub-bosses,
   1 boss), 4 directions, generated with `create_character` so the stored characters are
   the base for later animation. **No animation clips are generated at G2.**
2. **The G2 PixelLab ceiling returns to ≤60** (the charter row reverts from ADR-0008's
   200). Animation's budget belongs to the milestone that ships it, under its own ADR.
3. **Order of work:** five tower sprites (style-anchor route) → `art/director` and human
   review → atomic tower wiring; then eight static enemy sets → review → atomic enemy
   wiring. Animation is a later batch, after the static sprites are approved.
4. **The vendor balance still needs a small top-up.** 24 generations remain; the static
   batch is ~33 accepted plus retries. The human funds enough headroom (suggested ≥50
   remaining) before generation starts.
5. Tier pips and the sub-boss canvas decision stand as in ADR-0008; the per-tower tier
   silhouettes remain deferred.

## Consequences

**Intended:** the human sees and approves every static silhouette before any frame is
animated; the G2 ceiling stays honest at 60; the stored characters make the later
animation batch a matter of clips, not identity.

**Removed:** ~168 generations of enemy animation from G2. A later ADR re-prices it
against the then-current plan.

## Evidence

- `art/pixel` audit 2026-11-12: `create_character` static = 1 generation for a 4-direction
  set; full animation ≈168; towers 25 on the anchor route.
- Human decision 2026-11-12: static sprites first, animation later.
- `docs/adr/0008-g2-animated-art-budget.md` (superseded in part).
