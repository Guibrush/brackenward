class_name RunMapNodeType
extends RefCounted

## One entry in the run map's node-type registry (T-0040).
##
## CONTRACT
## --------
## * A node type is **data**. Everything the generator and the reveal rule need
##   to know about a type lives here: how often it is drawn (`weight`), the first
##   layer it may appear on (`earliest_layer`), whether entering it plays a level
##   (`plays_level`), whether it is the single final node (`is_boss`), whether its
##   content stays unknown until it is entered (`hidden_until_entry`), and whether
##   it telegraphs the boss (`telegraphs_boss`).
## * Adding a type is one line before `RunMap.generate()`:
##       map.node_types["shop"] = RunMapNodeType.create({
##           "id": "shop", "display_name": "Shop", "weight": 8.0,
##       })
##   `run_map.gd` never draws a type by name, never special-cases one in the draw,
##   and derives the boss from `is_boss`, so a new type needs no edit there. Only
##   the client that resolves the type's payload (the store screen, the event
##   screen) has to learn about it — the payload is not this object's business.
## * `weight` is relative and unitless, in the same units as every other type's
##   weight: two types at 12 are drawn equally often, and the weight's absolute
##   value means nothing. `0` means never drawn. The boss has weight 0 because the
##   generator places it structurally on the final layer; a non-zero weight would
##   let a boss be drawn, and "unique and final" would stop being true.
## * `earliest_layer` is 1-based, matching the layer numbers a player sees; the
##   generator's own layer indices are 0-based internally.
##
## PLACEHOLDER numbers
## -------------------
## Every weight and every `earliest_layer` default below is a guess made before
## the map has been played. `docs/design/systems/nodes.md` (T-0038) owns the real
## ones. Each carries the marker so replacing it is a search, not a hunt.

## The keys `create()` requires. A missing key is a programmer error and asserts
## in a development build; the value falls back to a default in release so a
## mistyped table cannot crash a run on a player's machine.
const REQUIRED_KEYS := ["id", "display_name", "weight"]

## PLACEHOLDER (T-0038 nodes.md): relative draw weight of a standard map level.
const WEIGHT_MAP := 30.0
## PLACEHOLDER (T-0038 nodes.md): relative draw weight of a store.
const WEIGHT_STORE := 12.0
## PLACEHOLDER (T-0038 nodes.md): relative draw weight of an elite level.
const WEIGHT_ELITE := 10.0
## PLACEHOLDER (T-0038 nodes.md): relative draw weight of a boss preview.
const WEIGHT_BOSS_PREVIEW := 6.0
## PLACEHOLDER (T-0038 nodes.md): relative draw weight of a treasure node.
const WEIGHT_TREASURE := 10.0
## PLACEHOLDER (T-0038 nodes.md): relative draw weight of a rest node.
const WEIGHT_REST := 10.0
## PLACEHOLDER (T-0038 nodes.md): relative draw weight of an event node.
const WEIGHT_EVENT := 12.0
## PLACEHOLDER (T-0038 nodes.md): relative draw weight of a high-stakes event.
const WEIGHT_HIGH_STAKES_EVENT := 6.0

## PLACEHOLDER (T-0038 nodes.md): the first layer a type may appear on, 1-based.
## Layer 1 is the opening choice; a sub-boss on the opening level would be a
## difficulty spike the design does not ask for, and a boss preview is worth more
## once the boss is close.
const EARLIEST_ELITE := 2
const EARLIEST_BOSS_PREVIEW := 4
const EARLIEST_HIGH_STAKES_EVENT := 1
## The boss layer, 1-based: the final layer of the run. The boss is placed there,
## never drawn, so this is only the floor that keeps it out of the draw.
const EARLIEST_BOSS := 9

## Type ids the generator names directly. Everything else is looked up by the id
## stored on the node, so these two are the only names `run_map.gd` depends on:
## the guaranteed map node and the structural boss.
const TYPE_MAP := "map"
const TYPE_BOSS := "boss"
const TYPE_ELITE := "elite"


var id: String = ""
var display_name: String = ""
var weight: float = 0.0
var plays_level: bool = false
var earliest_layer: int = 0
var is_boss: bool = false
var hidden_until_entry: bool = false
var telegraphs_boss: bool = false


## Builds one definition from a table row. Unknown keys are ignored on purpose:
## a table written for a later version of this class still loads.
static func create(config: Dictionary) -> RunMapNodeType:
	for key in REQUIRED_KEYS:
		assert(
			config.has(key),
			"RunMapNodeType.create: missing required key '%s' in %s" % [key, config]
		)
	var def := RunMapNodeType.new()
	def.id = str(config.get("id", ""))
	def.display_name = str(config.get("display_name", def.id))
	def.weight = float(config.get("weight", 0.0))
	def.plays_level = bool(config.get("plays_level", false))
	def.earliest_layer = int(config.get("earliest_layer", 0))
	def.is_boss = bool(config.get("is_boss", false))
	def.hidden_until_entry = bool(config.get("hidden_until_entry", false))
	def.telegraphs_boss = bool(config.get("telegraphs_boss", false))
	assert(def.id != "", "RunMapNodeType.create: id cannot be empty")
	assert(def.weight >= 0.0, "RunMapNodeType.create: '%s' has a negative weight" % def.id)
	assert(
		not def.is_boss or def.weight == 0.0,
		"RunMapNodeType.create: boss '%s' must have weight 0; it is placed, not drawn" % def.id
	)
	return def


## The eight node types the design names, in table order. Order does not affect
## generation (the draw sorts its candidates), but it is the order a log prints.
static func build_default_registry() -> Dictionary:
	var registry := {}
	registry[TYPE_MAP] = create({
		"id": TYPE_MAP,
		"display_name": "Map",
		"weight": WEIGHT_MAP,
		"plays_level": true,
	})
	registry["store"] = create({
		"id": "store",
		"display_name": "Store",
		"weight": WEIGHT_STORE,
	})
	registry[TYPE_ELITE] = create({
		"id": TYPE_ELITE,
		"display_name": "Elite",
		"weight": WEIGHT_ELITE,
		"plays_level": true,
		"earliest_layer": EARLIEST_ELITE,
	})
	registry["boss_preview"] = create({
		"id": "boss_preview",
		"display_name": "Boss preview",
		"weight": WEIGHT_BOSS_PREVIEW,
		"plays_level": true,
		"earliest_layer": EARLIEST_BOSS_PREVIEW,
		"telegraphs_boss": true,
	})
	registry["treasure"] = create({
		"id": "treasure",
		"display_name": "Treasure",
		"weight": WEIGHT_TREASURE,
	})
	registry["rest"] = create({
		"id": "rest",
		"display_name": "Rest",
		"weight": WEIGHT_REST,
	})
	registry["event"] = create({
		"id": "event",
		"display_name": "Event",
		"weight": WEIGHT_EVENT,
	})
	registry["high_stakes_event"] = create({
		"id": "high_stakes_event",
		"display_name": "High-stakes event",
		"weight": WEIGHT_HIGH_STAKES_EVENT,
		"earliest_layer": EARLIEST_HIGH_STAKES_EVENT,
		# A blind roll: what it gives (HQ damage or an upgrade) is not on the map.
		"hidden_until_entry": true,
	})
	registry[TYPE_BOSS] = create({
		"id": TYPE_BOSS,
		"display_name": "Boss",
		"weight": 0.0,
		"plays_level": true,
		"earliest_layer": EARLIEST_BOSS,
		"is_boss": true,
	})
	return registry


## Everything this definition claims about itself, for a log line or a test.
func snapshot() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"weight": weight,
		"plays_level": plays_level,
		"earliest_layer": earliest_layer,
		"is_boss": is_boss,
		"hidden_until_entry": hidden_until_entry,
		"telegraphs_boss": telegraphs_boss,
	}
