# Run map — nine layers, one boss, and the arithmetic of run length

> **G2 PLACEHOLDER.** Every number in this file is a theory-crafting default written
> before the slice exists, not a measurement. Nothing here is validated until a human
> plays a full run (G2.2). Rows marked `GUESS` have no data behind them; the last column
> names the observation that would replace the guess.

Owner: `design/systems`. Written at T-0038, 2026-11-06.

- **Number home.** This file owns the layer count, nodes per layer, adjacency, the map-node
  guarantee, map-selection weights (including the previous-map weight), the boss-final rule,
  lookahead and lures. Node types, weights and payloads are `nodes.md`; level difficulty is
  `waves.md`.
- **`DATADRIVEN`** marks a named field meant to be tuned by data, never by code.

## The shape

```
start → layer 1 → layer 2 → … → layer 9 → boss (layer 10)
        2–3 nodes per layer, at least one of them a map node
        one node taken per layer
```

| Property | Value | Marker | Reason for the bound |
| --- | --- | --- | --- |
| Layers between start and boss | **9** | `run.layers = 9`, `DATADRIVEN`, band 6–10 | 9 layers is the charter's map-reuse bet (9 maps exist); fewer and a run cannot reach 5 levels |
| Nodes per layer | **2–3** | `run.nodes_per_layer = [2, 3]`, `DATADRIVEN`, band 2–4 | 1 node is not a choice; 4 is a menu and the map stops being readable in one look (pillar 3) |
| Map nodes per layer | **≥ 1, guaranteed** | `run.min_map_nodes_per_layer = 1` | the route must never be unable to give the player a level |
| Nodes taken per layer | **exactly 1** | — | nodes in a layer are alternatives, never a sequence |
| Boss layer | **layer 10, exactly one node, always the boss** | `run.boss_is_final = true` | the run needs a terminal node that cannot be dodged |
| Minimum levels before the boss | **4** | `run.min_levels = 4`, `DATADRIVEN` | below 4 a run is a loadout, not a build: one store visit cannot make a second tower affordable |
| Standard maps in the pool | **8** (+1 boss map) | charter scope budget | reuse within a run is deliberate |
| Determinism | The whole map is a pure function of `run_seed` | — | a seed must reproduce a run exactly |

### Adjacency

Layer `L` has `n` nodes; layer `L+1` has `m`. Node `j` of layer `L` connects to nodes
`j` and `j+1` of layer `L+1`, **clamped to `[0, m−1]`**. Every layer-9 node connects to the
single boss node.

| Rule | Why |
| --- | --- |
| Adjacency is clamped, not wrapped | wrapping draws a crossing line on the map and the route stops being legible |
| Every node is reachable from the start | a node nobody can reach is a node that should not exist; the generator must assert it (T-0040) |
| No diagonal-only nodes | with 2–3 nodes and a `j / j+1` rule, the graph is always connected without a special case |
| Backwards edges | none. The map is a descent, never a loop |

## The 5-vs-10 spread, and the arithmetic behind it

**This is the part that is easy to get wrong, so it is stated as arithmetic first.**

    levels_in_run = (layers taken as a level) + 1 boss

    maximum: 9 layers all taken as levels   → 10 levels
    minimum: 4 layers taken as levels       →  5 levels
    every non-level node taken             →  costs exactly one level

| Non-level nodes taken | Layers taken as levels | Levels incl. boss | What the run is |
| --- | --- | --- | --- |
| 0 | 9 | **10** | gold-rich, item-poor — and it cannot buy a second tower at all |
| 1 | 8 | 9 | one acquisition site; a build that never gets wide |
| 2 | 7 | 8 | the narrow end of viable |
| 3 | 6 | **7** | the balanced shape: income ÷ sinks = 1.20 |
| 4 | 5 | 6 | item-rich, gold-poor |
| 5 | 4 | **5** | the greedy end: everything bought, nothing fully tiered |

**The two extremes fail in opposite directions, and that is the design.** `economy.md`
§Run-level check prices it: the 5-level run returns income ÷ sinks = **1.01** (every purchase
forced, nothing spare) and the 10-level run returns **2.50** with ~3 800 unspendable gold and
**one tower copy in the inventory** — because levels drop upgrades, not towers (`items.md`),
so a run with no store cannot grow a build. Both are legitimate ways to lose, and neither is
punished by a mechanic. The middle is where the game is won.

**Why "one node per layer" and not "2–3 levels per layer".** A layer is a *decision*, not a
sequence: the player looks at 2–3 alternatives, takes one, and the other two cease to exist.
That is the same shape as the between-level choice the charter describes, with the reward
being a whole level instead of a card.

### The `min_levels` guarantee

`min_levels = 4` must be enforced at generation, not hoped for:

> At layer `L` (1-based), if `levels_taken + (9 − L) < min_levels`, the layer's node set
> contains **only level types** (map and elite), so the next node taken must be a level.

At layer 6 with no levels taken, `0 + 3 = 3 < 4`, so layers 6–9 are all levels. The player
still chose to spend layers 1–5 on nodes; the guarantee only prevents a *zero-level* run.

| Case | Behaviour |
| --- | --- |
| The guarantee fires on a layer that already had 3 nodes | all three become level types; `nodes_without_duplicate_type` still holds, so at most one is an elite |
| The guarantee fires and the player has no affordable tower | legal — they are being pushed into the content they skipped |
| `min_levels` set to 9 | every layer is a level; the run is always 10 levels. A human tuning decision, not a code change |

## Map selection — the previous map has the lowest non-zero weight

Every level node carries a map from the pool. The **immediately previous played map** is never
excluded and is never favoured:

| Candidate map | Weight | Note |
| --- | --- | --- |
| The map just played | **5** | the lowest weight a map can have; still non-zero, so a repeat is possible |
| Any other standard map | **20** | a map played two or more layers ago is already here — no decay |
| Any map when the player has played no level yet | 20 each | there is no previous map on layer 1 |

| Field | Value | Range | `DATADRIVEN` | Reason for the bound |
| --- | --- | --- | --- | --- |
| `run.previous_map_weight` | **5** | 3–15 | yes | at 3 a repeat is a rumour; at 15 familiar ground fires in most runs and the map pool stops feeling like a pool |
| `run.other_map_weight` | **20** | 15–25 | yes | relative only; the ratio to `previous_map_weight` is the real dial |

With 8 standard maps, the previous map's share is `5 ÷ (5 + 7 × 20) = 3.4%` per level draw.
A run makes ~7 level draws, so **familiar ground fires in roughly one run in four** at these
weights. At `previous_map_weight = 15` it is ~9.7% per draw, i.e. most runs. That is the whole
tuning question for the hidden rule: `hidden-rules.md` owns what happens when it fires, this
file owns how often.

`GUESS` 5 and 20. **Would settle it:** the count of testers who *noticed* a repeat. The target
is **one or two of five**. None means the weight is too low and a designed rule is invisible;
all five means the pool is too small and reuse reads as laziness rather than as familiarity.

### Resolution order (determinism)

Map assignment is resolved **layer by layer, in order**, at generation time:

1. Assign each layer's node types from `nodes.md`'s weights.
2. Walk the layers in order. For each level node, assign a map using the weights above, where
   "previous" is the last map assigned to a level node in an *earlier* layer (not the last one
   *played* — the map is generated before the player plays it).
3. The boss layer's map is always the boss map.

Because "previous" is resolvable during generation, **the map stays a pure function of the
seed**, which is what T-0040 needs. The cost is a small honesty gap: the generator means
"previous *offered* level", not "previous *played* level". Since a level node the player skips
is never played, the two differ only on routes where the player passed a level. Stated here so
nobody discovers it as a bug: **`familiar ground` triggers on the generator's notion of
previous, and the two notions can differ by one layer.**

## Reveal and lures

| Property | Rule | Marker |
| --- | --- | --- |
| Lookahead | The current layer and the **next 2 layers** are visible | `run.lookahead_layers = 2`, `DATADRIVEN`, band 1–3 |
| Reveal depth | Which layers are *offered* is known; each revealed node's content follows `nodes.md` §The reveal rule | — |
| Lures | **2 nodes** anywhere in layers 6–9 are visible **from run start**, regardless of distance | `run.lure_count = 2`, `DATADRIVEN`, band 0–3 |
| What a lure shows | Its type, and if it is a level, the map, active tiles and dominant enemy types | — |
| What a lure hides | Everything else, and the whole path that would reach it | charter: "lures that pull the player toward a route without revealing the path between" |
| Boss node | Shows "boss" and nothing else, **unless** a `boss_preview` node was taken (`nodes.md`) | — |

The lures are the reason the route is a decision rather than a reaction: a visible elite on
layer 8 with a map you like is worth crossing four layers for, and the player commits to the
*shape* of a route without knowing the nodes in between.

`GUESS` 2 and 2. **Would settle it:** whether testers name a lure when explaining their route.
If a route is ever described purely as "I took the leftmost node", the lures are too few or too
far and the lookahead is too short.

## The boss is final, unique, and undodgeable

| Rule | Statement | Why |
| --- | --- | --- |
| One boss node | Layer 10 has exactly one node. There is no alternative | a route that can skip the exam is not a run |
| Always reachable | Every layer-9 node connects to it | the run must be able to end |
| No reroll | The boss node cannot be rerolled or exchanged | a rerollable loser is not a loss |
| No preview unless bought | The map, wave count and phase behaviour are hidden unless a `boss_preview` node was taken | the charter's information line |
| Ends the run | Win or lose, the run is over when the boss level resolves | the lifecycle needs one terminal event |
| Fixed body, indexed pacing | 340 trash threat + Warden + 60% escorts, at the boss's own `level_index` | `waves.md` §The boss level |

The boss level's `level_index` is `levels played + 1`, so it is 10 in a 10-level run and 5 in a
5-level run. The wall is the same height; the run that reaches it is not.

## Edge cases

| Case | Rule | Why it is stated |
| --- | --- | --- |
| A layer generated with no map node | Illegal: the generator rejects it and says which layer | the guarantee is the map's spine; a silent miss produces a level-less run |
| A layer with 1 node | Illegal | 2–3 is the shape; a 1-node layer has no decision |
| A layer with 4+ nodes | Illegal at G2 | readability and screen space |
| Two nodes of the same non-map type in a layer | Illegal at generation | `nodes.md` |
| `min_levels` not reachable from the current layer | The generator forces level nodes on every remaining layer | see §The `min_levels` guarantee |
| Player reaches layer 9 with 0 levels played | Impossible: the guarantee fired at layer 6 | a zero-level run is a bug, not a strategy |
| Player takes 9 levels (10-level run) | Legal; it is the gold-rich trap, not a crash | the extreme must be playable and losable |
| `run_seed` reused across two runs | Identical maps, different play | determinism is the test harness's tool |
| A lure node is on a layer the player reaches with the node already revealed | It is not revealed twice; the lure simply becomes a normal revealed node | double reveal is a UI cost with no information |
| All 8 maps have been played and a level node must be assigned | The previous map is still weighted 5, so a repeat is legal and expected | a run cannot always offer 8 distinct maps |
| Boss preview taken on layer 9 | Legal | the information still applies before the boss build phases |
| The run map exceeds 9 layers after a tuning change | `min_levels` is re-checked against the new layer count; levels still cap at `layers + 1` | the arithmetic, not a constant, is the rule |

## Not solving

- **No branching beyond a layer's node count.** No "skip a layer" edge, no hub, no wrap-around.
- **No map uniqueness guarantee.** Reuse is the charter's deliberate bet, and the previous-map
  weight exists to make reuse *possible*, not to prevent it.
- **No difficulty selection at run start.** One curve, one map, one boss.
- **No run seed UI.** `eng/systems` owns whether the seed is shown; this file only requires that
  the map is reproducible from it.
- **No map art, layout or route drawing.** `art/` and `eng/gameplay` own how this reads.
- **No ninth layer of special nodes.** Layer 9 is an ordinary layer; only the boss layer is
  special.

## Open questions for the human

1. **Does the 10-level run need to exist?** It is arithmetically the maximum and economically a
   trap (one tower copy, ~3 800 dead gold). If a run that cannot succeed should not be
   *offered*, the fix is one field — `min_levels = 4` is already there, and adding
   `min_non_level_nodes = 2` caps a run at 8 levels. That contradicts "a maximal run reaches 10
   levels", so it is your call, not a default I should take.
2. **Should the previous-map weight count the last map *offered* or *played*?** The generator
   can only use "offered" without breaking determinism. Making it "played" would make the map a
   function of the route as well as the seed, which is more honest to the rule and harder to
   test. Currently: offered.
3. **Is 2 lookahead layers right, or should the player see the whole layer ahead only?** Two
   layers is enough to plan a two-step route and short enough that the lures matter.
