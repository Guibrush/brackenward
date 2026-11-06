# Art style

Status: **locked and signed at G0 — 2026-11-04** · palette approved against
`art/style/anchor.png`

The single source of truth for every generated asset. `art/pixel` reads it before
generating, `art/director` judges against it, and `gate/assets.ps1` checks what can
be checked mechanically.

## Locked parameters

| Parameter | Value | Why it is locked |
| --- | --- | --- |
| Art form | Pixel art | PixelLab is the generator; it does one thing well |
| Tile size | 32×32 | A 30×18 board at 32px is 960×576, shown at 2× in a 1080p window. 16px would force 4× zoom and leave no room for three tower tiers to read |
| Tower canvas | 64×64 | Towers need height and a visible three-tier difference; centred, feet on the tile |
| Character canvas | 32×32 enemies, 96×96 bosses | Enemies match the tile so pathing and silhouettes stay honest; bosses must dwarf the board without breaking the grid |
| Canvas fill | Flat-topped towers: height ≥ 85% of the canvas, width ≥ 32 px (one tile). **Roofed towers: height ≥ 80%, widest row ≥ 24 px** | Measured on the pad-free content box (L-034), **including the 1 px `#1b1a26` ink outline** — the outline is part of the sprite and the figure is otherwise ambiguous by 2 px per side. A roof tapers, so it cannot occupy a full tile width — the original floor was calibrated on flat-topped battlements and made roofed towers unshippable. Below these numbers a sprite reads squat and fails the readability pillar |
| Palette | 16, fixed: `#1b1a26` `#2e2a3b` `#4a3b52` `#6b4a5a` `#8c5a4a` `#b06a3b` `#d08a4a` `#edb05f` `#f6d9a0` `#fff4d6` `#2f4a55` `#5b8a8c` `#3a4a3a` `#8b8291` `#6f8f4a` `#9ab55c` | Warm dusk, three greens, one cool grey. Kingdom Rush's warmth without its saturation |
| Max colours per sprite | 12 of the 16 | Leaves 4 shared accent colours across the set |
| Outline | 1px, single colour `#1b1a26`, **selective** | Full outlining turns 32px sprites to mush; inner detail stays lineless |
| Light direction | Top-left, always | Mixed lighting makes sprites look pasted on |
| Projection | Isometric 3/4 sprites on a **square** 32×32 grid | `create_map_object` only produces 3/4; square tiles keep level layout and pathing simple. Ground art stays flat and neutral so the two read together |
| Directions | 4: down, left, right, up | 8 triples the art bill on a board where enemies mostly walk toward or away from you |

## Palette — "bracken dusk" (16)

The `Palette` row in the table above is the lock. This table assigns roles to the
same hexes; if the two ever disagree, the row above wins and this table gets fixed.

| Hex | Name | Role |
| --- | --- | --- |
| `#1b1a26` | ink | Outline, deepest shadow |
| `#2e2a3b` | shadow | Shadow block, UI backing |
| `#4a3b52` | dusk | Mid shadow, stone in shade |
| `#6b4a5a` | mauve | Warm mid-shadow, cloth |
| `#8c5a4a` | rust | Metal in shade, leather |
| `#b06a3b` | clay | Wood, roofs, terrain |
| `#d08a4a` | amber | Warm midtone, gold |
| `#edb05f` | candlelight | Lit surfaces, UI accent |
| `#f6d9a0` | parchment | Skin, paper, highlights |
| `#fff4d6` | highlight | Brightest point, sparingly |
| `#2f4a55` | deep teal | Water, deep shade, night sky |
| `#5b8a8c` | slate | Cold midtone, metal highlight |
| `#3a4a3a` | deep green | Foliage shadow, moss |
| `#8b8291` | stone | Cool neutral midtone: masonry, cold metal, the only grey the palette has |
| `#6f8f4a` | leaf | Grass light, foliage |
| `#9ab55c` | sunleaf | Sunlit foliage, brightest green |

No colour outside this list may appear in a shipped asset. A new colour means
editing this table, which is a human decision, not an agent's.

**Water requirement.** `#2f4a55` deep teal and `#5b8a8c` slate are reserved for
water and are not expendable — some levels have water. When a hex is needed
elsewhere, the mid-greens are what gets sacrificed, not the cool ramp. `#8b8291`
stone replaced the former `#4f6b3f` moss for exactly that reason (option 1,
2026-11-04); greens remain a three-step ramp.

## Style reference

One approved image anchors every subsequent generation. Save it as
`art/style/anchor.png` and pass it as the style reference on every call. Without an
anchor, each call invents its own look and the set drifts.

The anchor must show, in one image: a tower silhouette against ground, the palette
at work, the top-left light, and the 3/4 projection. A sample that does not carry all
four is not an anchor.

## Animation sets

| Action | Enemies (frames) | Towers (frames) | Loop |
| --- | --- | --- | --- |
| idle | 2 | 3 | yes |
| walk | 4 | — | yes |
| attack | 4 | 4 | no |
| hurt | 1 | — | no |
| death | 4 | — | no |

Enemies: 5 normal + 2 sub-bosses + 1 boss. Frame cost at 4 directions is
15 frames per direction set for a normal enemy, so 5 × 4 × 15 = 300 frames before
the bosses. This number is why directions are 4 and not 8.

Towers are single-direction and do not walk. Six towers × 3 tiers, tiers drawn as
an overlay or glyph on one sprite rather than 18 unique sprites.

## Not decided yet

- **Enemy locomotion is not a style rule.** Whether enemies walk orthogonally along
  grid paths or move on diagonals is decided by testing once enemies exist. Only the
  4 declared directions are locked; do not write movement rules before the test.

## Pipeline facts (learned the hard way, 4 samples, 6 generations)

- **`view` is not a control surface.** `create_map_object` offers
  `low top-down | high top-down | side`; all three return isometric 3/4. Stop trying
  to select projection with the parameter. Isometric 3/4 is the projection, and the
  lock now says so.
- **`create_map_object` ignores palettes in the prompt.** It returned 45 distinct
  colours for a 16-colour brief, and 41 and 44 on later attempts. Palette conformance
  is a *post-processing* guarantee: snap with the free workbench (`edit --changes
  map_colors`, 0 generations), which preserves luminance order and does not band.
  Palette snapping has not damaged any sample yet.
- **Ground pads are always included.** Every `create_map_object` render arrives on a
  grass diamond. Crop it in post. This is not tidying: an uncropped pad puts a
  second, incompatible grid under every sprite.
- **The 1px outline is usually missing or incomplete.** Expect to add it
  (`edit --changes outline`, free) and to verify silhouette-boundary coverage by
  script afterwards.
- **The pro model (`create_object_pro_flash`, 5 generations) is rejected for now.**
  It honours a palette argument (7 colours, 0 off-palette) and produces grid-aligned
  square footprints, but its output is a flat front elevation with no readable top
  surface, and at 5 generations per asset it budgets out at roughly 195 generations
  for the slice against 31 remaining.
- **One asset ≈ 1 generation** on the isometric route, plus several free post steps.
  This is the cost model the scope budget assumes.

## Ground pad rule

No shipped sprite may contain generator ground: no grass tiles, no diamond plinths,
no base shadow ellipses. The engine draws the ground. A sprite that carries its own
ground fails review regardless of how good it looks in isolation.

## Silhouette rules

- Readable at 1× scale, in one colour, against both light and dark backgrounds.
- No detail smaller than one pixel that is not load-bearing.
- Every character silhouette must be distinguishable from every other character
  at thumbnail size.
- A tower must be identifiable by silhouette alone, since the player reads the board
  at a glance (pillar 3).

## What good looks like

- Consistent palette across every asset, with no new colours introduced casually.
- Consistent light direction, so a row of sprites reads as one scene.
- Deliberate asymmetry rather than mirrored default poses.
- Placeholder assets are named as placeholders in `art/manifest.json` and never
  quietly accepted as final.

## Prohibited

- Mixing pixel scales in one scene (a 16px sprite next to a 32px sprite).
- Anti-aliased edges, soft gradients, or photographic textures.
- Generating without a style anchor once an anchor exists.
- Editing a shipped asset in place instead of adding a variant.
- Colours outside the 16 above.
