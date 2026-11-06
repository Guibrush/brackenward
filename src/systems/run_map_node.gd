class_name RunMapNode
extends RefCounted

## One node on a generated run map (T-0040).
##
## CONTRACT
## --------
## * A node is a value: after `RunMap.generate()` returns true nothing but
##   `lure` is written, and that is written once, during generation. The owner of
##   this object is the `RunMap` that created it; no other object mutates a node.
## * A node holds what the map is allowed to know about a stop on the route:
##   where it sits (`layer`, `index`), what it is (`type_id`), which level it
##   plays (`level_id`, empty when the type plays no level), that level's
##   `base_active_tiles` and `dominant_enemy_types`, and its outgoing edges
##   (`children`).
## * A node **never** holds wave composition. There is no field for it and none
##   is coming: what spawns in a wave is derived by the wave system from the
##   level's parameters at the moment the level is played. `serialise()` is the
##   proof — its key set is fixed, and `RunMap` asserts it.
## * `dominant_enemy_types` is the 1-2 enemy type ids a level's waves lean on, as
##   the map reveals them; it is not a wave manifest. `base_active_tiles` is the
##   number of build tiles the level offers before any in-run bonus.
##
## Layer indices are 0-based; a player-facing layer number is `layer + 1`.

var id: int = -1
var layer: int = -1
var index: int = 0
var type_id: String = ""
var level_id: String = ""
var base_active_tiles: int = 0
var dominant_enemy_types: Array = []
## Node ids this node leads to, ascending. Empty only on the final (boss) layer.
var children: Array = []
## Visible from the start regardless of distance, and still entered only through
## the normal rule: a lure is selectable when it is a legal child of the node the
## route is on, never merely because it is visible (CHARTER: "a few nodes are
## visible from the start ... lures that pull the player toward a route without
## revealing the path between"). Visibility is the whole of what `lure` changes.
var lure: bool = false


## The canonical form. The map hashes a list of these, so the key set here is
## part of the determinism contract: adding a field changes every map's hash.
func serialise() -> Dictionary:
	return {
		"id": id,
		"layer": layer,
		"index": index,
		"type": type_id,
		"level": level_id,
		"tiles": base_active_tiles,
		"enemies": dominant_enemy_types.duplicate(),
		"children": children.duplicate(),
		"lure": lure,
	}


func plays_level() -> bool:
	return level_id != ""


## One line for a log: "L3N2 elite map-07". Deliberately not a substitute for
## `serialise()`; it drops the level's parameters.
func describe() -> String:
	var text := "L%dN%d %s" % [layer + 1, index + 1, type_id]
	if level_id != "":
		text += " %s" % level_id
	if lure:
		text += " (lure)"
	return text
