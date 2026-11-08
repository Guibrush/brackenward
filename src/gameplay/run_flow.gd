class_name RunFlow
extends Node

## The run session: one object owns the map, the run state and the inventory for
## exactly one run, and walks the player from node to node (T-0048).
##
## CONTRACT
## --------
## * A caller creates one `RunFlow` per run, adds it to the tree, wires
##   `level_scene`, and keeps the reference for the life of that run. It is the
##   only object that holds the `RunMap`, the `RunState` and the `Inventory`
##   together; nothing else owns progress, gold, HQ health or the towers.
## * Two entry points, and no third way in:
##       start_run(seed)     builds the map for `seed` and starts the run
##       enter_node(node_id) moves the player onto a node and, for a level-type
##                           node, opens the level scene
##   `complete_level()` is the completion handover (below), not a third entry
##   point: it is what the level scene's `level_cleared` signal calls, and a
##   caller may drive it directly only to prove a refusal.
## * Custody of the level (T-0045 -> T-0048). The level scene is a child of this
##   node while it plays. It is handed the run and the inventory through
##   `bind_run()` **before** it enters the tree, so `_ready` seeds HQ and gold
##   from the run; it is told to take its level number from the run (ADR-0006),
##   and whether the level is elite comes from the node's type. When its last
##   wave clears it emits `level_cleared` and does nothing else: this session is
##   the only caller of `RunState.complete_level()`, so a level is counted
##   exactly once, and this session - not the level - calls `win_run()` when the
##   completed node is the boss.
## * Refusals are loud and printed: `RUNFLOW_REFUSED {json}`, with the reason
##   also kept in `last_refusal()`. Entering a node that is not visible or not
##   selectable, completing a level that was never entered, and entering a node
##   after the run ended all leave the run exactly as it was.
## * Non-level nodes (T-0049). `store`, `rest`, `treasure`, `event`,
##   `high_stakes_event` and `boss_preview` resolve on entry and the route advances
##   onto them, exactly as a level node does. The effect belongs to this session
##   (`nodes.md` §Payloads), never to the map: the map shows the node, the session
##   resolves it. Per node:
##       store              draws a shelf; `store()` reads it, `buy(slot)` spends
##                          gold and lands the item, `reroll_store()` obeys the
##                          site's own switch and ladder
##       rest               heals HQ by `rest_heal`, never above the maximum; at
##                          full HQ nothing changes and the line says so
##       treasure           pays `treasure_base_gold + treasure_gold_per_layer ×
##                          layer`, on arrival
##       event              draws `event_offer_count` offers; `choose_event(slot)`
##                          lands exactly one and closes the set, once
##       high_stakes_event  a **blind** roll: the odds are public, the outcome is
##                          not. It is drawn at the moment the node is chosen, kept
##                          in one place, and never re-drawn - reading it again
##                          (`high_stakes_outcome`) returns the same value. HQ
##                          damage applies on arrival; a good roll leaves a tier-up
##                          pending for `claim_high_stakes_tier_up(tower_id)`, and
##                          degrades to `high_stakes_gold_fallback` when the
##                          inventory holds no copy below tier 3 (`nodes.md` §Edge
##                          cases)
##       boss_preview       reveals the boss map, its tile count and its dominant
##                          enemies through `revealed_boss()`; it changes no state
##                            beyond that (`nodes.md`: no gold, no HQ, no level)
##   A refusal (no gold, a switched-on inventory cap, a spent reroll ladder) leaves
##   gold, the shelf and the inventory exactly as they were.
##
## KNOWN GAP, reported to `eng/systems` rather than worked around
## -------------------------------------------------------------
## `UpgradeInstance` carries `type_id` and nothing else, so a tier-2 or tier-3 rune
## or relic bought at a store lands in the inventory as its tier-1 identity: the
## tier the shelf charged for is not stored. Towers keep their tier (the instance
## has one). This session records the shelf's tier in the print line and in the
## purchase record so the gap is visible, and never invents a tier the inventory
## cannot hold.
##
## CALLERS MUST
## ------------
## * Check the bool returned by `start_run()`, `enter_node()` and
##   `complete_level()`, and show `last_refusal()` instead of retrying silently.
## * Open the level's first wave through the level itself
##   (`Arena.start_level()`): the session opens a level in the build phase and
##   does not start a wave, because before wave 1 the player plans freely
##   (CHARTER) and that decision belongs to the player, not to the map.
## * Read gold, HQ and progress from `run_state()`, the map from `map()` and the
##   towers from `inventory()`. This object exposes them and copies none of them.
##
## Prints on stdout, in this order:
##   RUNFLOW_START {json}     once, when a run begins: seed, map sha, opening numbers
##   RUNFLOW_ENTER {json}     once per level node entered, with the level it opened
##   RUNFLOW_NODE {json}      once per non-level node entered, with its effect
##   RUNFLOW_BUY {json}       once per accepted store purchase
##   RUNFLOW_STORE_REROLL {json}  once per accepted store reroll
##   RUNFLOW_EVENT_PICK {json}    once per event item taken
##   RUNFLOW_EVENT_REROLL {json}  once per accepted event reroll
##   RUNFLOW_TIER_UP {json}   once per high-stakes tier-up applied
##   RUNFLOW_COMPLETE {json}  once per completed level, with the numbers carried on
##   RUNFLOW_RUN_END {json}   once, when `RunState` ends the run (win or defeat)
##   RUNFLOW_REFUSED {json}   every refusal, with its reason
##
## The `ARENA_*`, `WAVE_*` and `RUN_REFUSED` lines in the same output are printed
## by the systems under test, not by this file.

## The level scene has been opened for `node_id` and is the run's `level_index`.
signal level_opened(node_id: int, level_index: int, elite: bool)
## A level finished and control returned to the map. `levels_completed` is the
## run's count after the completion (ADR-0006: a count, never an index into a
## fixed list); `boss` marks the ending node.
signal level_completed(node_id: int, levels_completed: int, boss: bool)
## `RunState` ended the run. Emitted once, by whichever call ended it.
signal run_ended(victory: bool, reason: String)

# Preloaded rather than referenced by class name, for the reason `inventory.gd`
# gives: `--check-only` must not depend on the global class cache having been
# built by a prior `--import`.
const RunMapScript := preload("res://src/systems/run_map.gd")
const RunStateScript := preload("res://src/systems/run_state.gd")
const InventoryScript := preload("res://src/systems/inventory.gd")
const RunMapNodeTypeScript := preload("res://src/systems/run_map_types.gd")
# OfferSite before Store: `Store` extends it, and the preload order is the only
# order that is guaranteed inside one file.
const OfferSiteScript := preload("res://src/systems/offers.gd")
const StoreScript := preload("res://src/systems/store.gd")
const ItemCatalogueScript := preload("res://src/gameplay/item_catalogue.gd")

## Node types this session plays as a level, by id. The registry's `plays_level`
## is not the test: it is true for `boss_preview` too, and that node reveals the
## boss instead of playing a level (T-0049). Adding a level type here is the whole
## change a new level node needs.
const LEVEL_TYPES := [
	RunMapNodeTypeScript.TYPE_MAP,
	RunMapNodeTypeScript.TYPE_ELITE,
	RunMapNodeTypeScript.TYPE_BOSS,
]
const ELITE_TYPE := RunMapNodeTypeScript.TYPE_ELITE
const BOSS_TYPE := RunMapNodeTypeScript.TYPE_BOSS

## Node types that resolve inside this session instead of opening a level
## (`nodes.md` §The eight types). Ids match `run_map_types.gd`'s registry; they are
## named here so a branch reads as a name and a refusal can print one.
const STORE_TYPE := "store"
const REST_TYPE := "rest"
const TREASURE_TYPE := "treasure"
const EVENT_TYPE := "event"
const HIGH_STAKES_TYPE := "high_stakes_event"
const BOSS_PREVIEW_TYPE := "boss_preview"
const NON_LEVEL_TYPES := [
	STORE_TYPE,
	REST_TYPE,
	TREASURE_TYPE,
	EVENT_TYPE,
	HIGH_STAKES_TYPE,
	BOSS_PREVIEW_TYPE,
]

## A tower cannot go past this tier (`towers.md`: 0 and 4 are illegal). The
## high-stakes tier-up has to know where the ladder ends to degrade instead of
## dead-ending (`nodes.md` §Edge cases).
const MAX_TOWER_TIER := 3

## PLACEHOLDER (nodes.md §Payloads, band 5-12): HQ the high-stakes roll can take.
const DEFAULT_HIGH_STAKES_HQ_DAMAGE := 8
## PLACEHOLDER (nodes.md §Payloads, band 0.4-0.6): chance the blind roll is good.
const DEFAULT_HIGH_STAKES_GOOD_CHANCE := 0.5
## PLACEHOLDER (nodes.md §Edge cases): gold paid when a good roll finds no copy
## below tier 3 to raise. A reward must degrade, never dead-end.
const DEFAULT_HIGH_STAKES_GOLD_FALLBACK := 120
## PLACEHOLDER (economy.md §Gold in): treasure pays `base + per_layer × layer`.
const DEFAULT_TREASURE_BASE_GOLD := 90
const DEFAULT_TREASURE_GOLD_PER_LAYER := 15
## PLACEHOLDER (economy.md §HQ: the only heal in the game): +6, free, once.
const DEFAULT_REST_HEAL := 6

enum Phase { IDLE, ON_MAP, IN_LEVEL, FINISHED }
const PHASE_NAMES: Array[String] = ["idle", "on_map", "in_level", "finished"]

## The scene opened for a level node. Wired by whoever creates the session; a
## session with no scene refuses to start a run rather than opening a node it
## cannot play.
@export var level_scene: PackedScene

@export_group("Opening purse — PLACEHOLDER (design/systems economy.md)")
## HQ health and gold a run begins with. Defaulted from `RunState` so the two
## agree by construction; a designer moves these, not the scene.
@export var starting_hq_max: int = RunStateScript.DEFAULT_HQ_MAX
@export var starting_gold: int = RunStateScript.STARTING_GOLD

@export_group("Non-level nodes — PLACEHOLDER (design/systems nodes.md, economy.md)")
## HQ a rest node restores. The only heal in the game; never above the maximum and
## never banked (`economy.md` §HQ). Range 4-10.
@export var rest_heal: int = DEFAULT_REST_HEAL
## Gold a treasure node pays: `base + per_layer × layer`, layer 1-based. Range
## 60-120 base, 10-20 per layer (`economy.md` §Gold in).
@export var treasure_base_gold: int = DEFAULT_TREASURE_BASE_GOLD
@export var treasure_gold_per_layer: int = DEFAULT_TREASURE_GOLD_PER_LAYER
## Offers an event node draws. Three is the smallest number that makes "the best
## of two bad options" possible (`nodes.md` §event). Range 2-5.
@export var event_offer_count: int = OfferSiteScript.OFFER_COUNT
## The per-site reroll switch for every store this run opens (`store.md`
## §Reroll). Off means the shelf is a fixed hand for the whole visit.
@export var store_reroll_enabled: bool = true
## Chance the high-stakes roll is the good outcome. Range 0.4-0.6.
@export_range(0.0, 1.0, 0.05) var high_stakes_good_chance: float = DEFAULT_HIGH_STAKES_GOOD_CHANCE
## HQ the high-stakes bad outcome takes. Range 5-12.
@export var high_stakes_hq_damage: int = DEFAULT_HIGH_STAKES_HQ_DAMAGE
## Gold paid when a good roll has no copy below tier 3 to raise. Range 90-150.
@export var high_stakes_gold_fallback: int = DEFAULT_HIGH_STAKES_GOLD_FALLBACK

## Untyped on purpose: `_map`, `_run` and `_inventory` are preloaded scripts, and
## a statically typed base would have to name every method they have
## (`run_demo.gd` records the same reason).
var _map = null
var _run = null
var _inventory = null

## The level scene while one is open, and the node that opened it. Null/-1 on the
## map: those two values are what `complete_level()` tests, so a completion can
## never be counted for a level that was not entered.
var _level = null
var _level_node_id: int = -1

## The open non-level visit, if any. `_store` is a `Store`, `_event` an
## `OfferSite`; both are cleared when the route moves onto another node, because a
## visit is what happens between two nodes and not a second permanent owner of the
## run. An open event is the one visit that blocks movement: the charter says a
## between-level offer cannot be skipped, so `enter_node` refuses until one of its
## offers is taken.
var _store = null
var _event = null
## Visit counters, part of each site's draw key (`Offers.derive_seed`). They are a
## property of this run, so two stores at the same layer still draw differently.
var _store_visits: int = 0
var _event_visits: int = 0
## High-stakes outcomes, by node id: `{node_id: {good, kind, ...}}`. Written once,
## at the moment the node is chosen, and only read afterwards - this dictionary is
## what "the roll is not re-rolled" means in code.
var _rolls: Dictionary = {}
## Node whose good high-stakes roll is still waiting for a tower to raise, or -1.
var _pending_tier_up_node: int = -1
## What `boss_preview` revealed, or {} before any preview.
var _revealed_boss: Dictionary = {}
## One record per resolved non-level node, oldest first, for a demo or a HUD.
var _node_effects: Array = []

var _phase: int = Phase.IDLE
## Completions this session has handed to `RunState`. Compared against
## `RunState.level_index()` by the demo: the two must stay equal, which is what
## "exactly once per level" means.
var _completions: int = 0
var _refusals: int = 0
var _last_refusal: String = ""


# --- entry points -----------------------------------------------------------

## Builds the map for `seed_value`, starts a run and puts the player on the map.
## Refused while a level is open, while another run is in progress, when no level
## scene is wired, or when the map refuses the seed (the map's own reason is
## carried through).
##
## `map_overrides` is authoring and test input, exactly as
## `RunMap.generate(seed, overrides)` defines it — `{"forced_types": {layer:
## [type_id, ...]}}` pins a layer's node types. Play never passes it; a demo uses
## it to guarantee a route that contains every node type.
func start_run(seed_value: int, map_overrides: Dictionary = {}) -> bool:
	if _phase == Phase.IN_LEVEL:
		return _refuse("start a run", "level %d is still open; complete it first" % _run.level_number())
	if _run != null and _run.is_in_progress():
		return _refuse("start a run", "a run is already in progress; finish it first")
	if level_scene == null:
		return _refuse(
			"start a run", "no level_scene is wired, so a level node would have nothing to open"
		)

	var map = RunMapScript.new()
	if not map.generate(seed_value, map_overrides):
		return _refuse(
			"start a run", "the map refused seed %d: %s" % [seed_value, map.last_refusal()]
		)
	var run = RunStateScript.new()
	if not run.start(starting_hq_max, starting_gold):
		return _refuse("start a run", run.last_refusal())

	_map = map
	_run = run
	_inventory = InventoryScript.new()
	_run.run_ended.connect(_on_run_ended)
	_level = null
	_level_node_id = -1
	_store = null
	_event = null
	_store_visits = 0
	_event_visits = 0
	_rolls.clear()
	_pending_tier_up_node = -1
	_revealed_boss = {}
	_node_effects.clear()
	_completions = 0
	_phase = Phase.ON_MAP
	_last_refusal = ""

	print("RUNFLOW_START " + JSON.stringify({
		"seed": seed_value,
		"sha": _map.sha(),
		"layers": _map.total_layers(),
		"nodes": _map.node_count(),
		"hq": _run.hq_health(),
		"hq_max": _run.hq_max_health(),
		"gold": _run.gold(),
		"selectable": _map.selectable_nodes(),
	}))
	return true


## Moves the player onto `node_id`. Legal only for a visible node that is one of
## the map's next choices and whose type this session can resolve; anything else
## is refused with a printed reason and changes nothing. A level-type node opens
## its level and returns true with the level running; `complete_level()` is what
## brings the player back to the map. Every other type resolves here and returns
## true with the run still on the map.
func enter_node(node_id: int) -> bool:
	if _map == null or _run == null:
		return _refuse("enter node %d" % node_id, "no run has started")
	if _phase == Phase.IN_LEVEL:
		return _refuse(
			"enter node %d" % node_id,
			"level %d is still open; complete it before choosing another node"
			% _run.level_number()
		)
	if _run.is_over():
		return _refuse(
			"enter node %d" % node_id,
			"the run is over (%s): %s" % [_run.status_name(), _run.end_reason()]
		)
	if _map.is_complete():
		return _refuse(
			"enter node %d" % node_id, "the route is complete; the boss is already entered"
		)
	if _event != null:
		# The charter: between-level offers cannot be skipped. The route is a
		# sequence, so an untaken offer would be lost rather than deferred.
		return _refuse(
			"enter node %d" % node_id,
			"the event is unresolved: choose one of its %d offers first" % _event.stock().size()
		)
	if _map.node(node_id) == null:
		return _refuse("enter node %d" % node_id, "no node %d on this map" % node_id)
	if not _map.is_visible(node_id):
		return _refuse(
			"enter node %d" % node_id,
			"the node is not visible: it is not entered, not a next choice and not a lure"
		)
	if not _map.is_selectable(node_id):
		return _refuse(
			"enter node %d" % node_id,
			"the node is visible but not selectable: it is not one of the next choices %s"
			% [_map.selectable_nodes()]
		)

	var type_id := String(_map.type_of(node_id))
	if not LEVEL_TYPES.has(type_id) and not NON_LEVEL_TYPES.has(type_id):
		return _refuse("enter node %d" % node_id, "unknown node type '%s'" % type_id)

	# The map's own check runs last and is not bypassed: the route moves only
	# when `RunMap.enter()` agrees, so the session cannot invent a legal move.
	if not _map.enter(node_id):
		return _refuse("enter node %d" % node_id, _map.last_refusal())

	# The previous non-level visit is over: a visit is what happens between two
	# nodes, and leaving a store is free and always legal (`store.md`). The event
	# guard above is the one visit that cannot be left unresolved.
	_store = null

	if LEVEL_TYPES.has(type_id):
		return _open_level(node_id, type_id)
	return _resolve_non_level(node_id, type_id)


## Finishes the open level: counts it through `RunState.complete_level()` exactly
## once, closes the level scene and returns control to the map. Refused - with
## nothing changed and `RunState.complete_level()` not called - when no level is
## open or the run has already ended.
##
## This is the level scene's `level_cleared` handler, and the only caller of
## `RunState.complete_level()` for a played level (ADR-0006). It is public so a
## harness can plant the "completion without a level" failure.
func complete_level() -> bool:
	if _run == null:
		return _refuse("complete the level", "no run has started")
	if _phase != Phase.IN_LEVEL or _level == null:
		return _refuse(
			"complete the level",
			"no level is open: nothing has been entered, so nothing can be completed"
		)
	if _run.is_over():
		return _refuse(
			"complete the level",
			"the run is over (%s): %s" % [_run.status_name(), _run.end_reason()]
		)

	var node_id := _level_node_id
	var boss := String(_map.type_of(node_id)) == BOSS_TYPE
	if not _run.complete_level():
		return _refuse("complete the level", _run.last_refusal())
	_completions += 1

	# Control returns to the map, so the level scene's job is over. Queued, never
	# freed: this call arrives from inside the level's own signal, and the level
	# still has code to finish in the frame it cleared.
	_level.queue_free()
	_level = null
	_level_node_id = -1
	_phase = Phase.ON_MAP

	if boss:
		# The session's call, never the level's (ADR-0006): the arena cannot know
		# which node it is playing. `win_run()` ends the run and reaches
		# `_on_run_ended`, which is what prints RUNFLOW_RUN_END.
		if not _run.win_run("the boss node was completed"):
			return _refuse("win the run", _run.last_refusal())

	print("RUNFLOW_COMPLETE " + JSON.stringify({
		"node": node_id,
		"boss": boss,
		"level_index": _run.level_index(),
		"levels_completed": _run.level_index(),
		"hq": _run.hq_health(),
		"hq_max": _run.hq_max_health(),
		"gold": _run.gold(),
		"status": _run.status_name(),
		"victory": _run.is_victory(),
		"route": _map.route(),
		"phase": phase_name(),
	}))
	level_completed.emit(node_id, _run.level_index(), boss)
	return true


# --- non-level node actions -------------------------------------------------

## Buys the item in `slot_index` of the open shelf.
##
## The inventory cap is checked **before** the store is asked to charge, because
## `Store` owns no inventory and cannot refuse on its behalf (`store.gd`
## CONTRACT): a refused purchase must not be able to cost gold. The charge seam is
## `RunState.spend_gold()`, which returns false without debiting when the balance
## is short, so "no gold" also leaves the shelf and the purse untouched.
func buy(slot_index: int) -> bool:
	if _store == null:
		return _refuse(
			"buy from the store",
			"no store visit is open: enter a store node and read its shelf first"
		)
	var entry: Dictionary = _store.slot(slot_index)
	if OfferSiteScript.is_empty_slot(entry):
		return _refuse(
			"buy slot %d" % slot_index, "the slot is empty or does not exist on this shelf"
		)

	var kind := String(entry.get("kind", ""))
	var item_id := String(entry.get("id", ""))
	var tier := int(entry.get("tier", 1))
	if kind == OfferSiteScript.KIND_TOWER and _inventory.is_at_cap():
		# Player-facing, so printed and stored like every other refusal: the cap is
		# a rule the player can hit in normal play (`inventory.gd`).
		return _refuse(
			"buy %s (tier %d)" % [item_id, tier],
			"the inventory holds %d of %d towers (cap on); nothing was bought and no gold moved"
			% [_inventory.tower_count(), _inventory.tower_cap]
		)

	var gold_before: int = _run.gold()
	var result: Dictionary = _store.purchase(slot_index, _charge_seam("store purchase"))
	if not bool(result.get("ok", false)):
		return _refuse("buy %s (tier %d)" % [item_id, tier], String(result.get("text", "")))

	var landed := _add_item(entry, "store purchase")
	if not bool(landed.get("ok", false)):
		# Unreachable while the cap is checked above: the only way `add` can fail
		# is the cap or a bad id, and the catalogue's ids are validated. Loud
		# because gold has already moved.
		push_error(
			"RUNFLOW_ERROR store charged %d for %s but the inventory refused it: %s"
			% [int(result.get("cost", 0)), item_id, String(landed.get("reason", ""))]
		)
		return _refuse("add %s to the inventory" % item_id, String(landed.get("reason", "")))

	print("RUNFLOW_BUY " + JSON.stringify({
		"slot": slot_index,
		"id": item_id,
		"kind": kind,
		"tier": tier,
		"cost": int(result.get("cost", 0)),
		"gold_before": gold_before,
		"gold": _run.gold(),
		"tower_id": int(landed.get("tower_id", 0)),
		"upgrade_id": int(landed.get("upgrade_id", 0)),
		"towers": _inventory.tower_count(),
		"upgrades": _inventory.upgrade_count(),
	}))
	return true


## Replaces the open shelf, charging the store's own ladder. The site's switch is
## read from the site, not from this session's export: `store().set_reroll_enabled
## (false)` on the node is what "per-site" means (`store.md` §Reroll).
func reroll_store() -> bool:
	if _store == null:
		return _refuse("reroll the store", "no store visit is open")
	var gold_before: int = _run.gold()
	var result: Dictionary = _store.reroll(_charge_seam("store reroll"))
	if not bool(result.get("ok", false)):
		return _refuse("reroll the store", String(result.get("text", "")))

	print("RUNFLOW_STORE_REROLL " + JSON.stringify({
		"cost": int(result.get("cost", 0)),
		"gold_before": gold_before,
		"gold": _run.gold(),
		"reroll_index": int(result.get("reroll_index", 0)),
		"rerolls_left": _store.rerolls_left(),
		"stock": _shelf_summary(),
	}))
	return true


## Takes exactly one offer from the open event set. The set closes on success, so
## a second call is refused rather than paying twice for one node.
func choose_event(slot_index: int) -> bool:
	if _event == null:
		return _refuse(
			"choose an event offer",
			"no event is open: the set was never drawn, or its pick was already made"
		)
	var entry: Dictionary = _event.slot(slot_index)
	if OfferSiteScript.is_empty_slot(entry):
		return _refuse(
			"choose event slot %d" % slot_index, "there is no offer in that slot"
		)

	var landed := _add_item(entry, "event pick")
	if not bool(landed.get("ok", false)):
		# An event costs no gold, so a refused pick loses nothing; the set stays
		# open so the player can take a different offer.
		return _refuse(
			"take %s from the event" % String(entry.get("id", "")),
			String(landed.get("reason", ""))
		)

	_event = null
	print("RUNFLOW_EVENT_PICK " + JSON.stringify({
		"slot": slot_index,
		"id": String(entry.get("id", "")),
		"kind": String(entry.get("kind", "")),
		"tier": int(entry.get("tier", 1)),
		"tower_id": int(landed.get("tower_id", 0)),
		"upgrade_id": int(landed.get("upgrade_id", 0)),
		"towers": _inventory.tower_count(),
		"upgrades": _inventory.upgrade_count(),
	}))
	return true


## Replaces the open event set, on the offer ladder (30 / 45 / 60) and the same
## per-site switch (`nodes.md` §event: the set "can be rerolled with that file's
## ladder").
func reroll_event() -> bool:
	if _event == null:
		return _refuse("reroll the event", "no event is open")
	var gold_before: int = _run.gold()
	var result: Dictionary = _event.reroll(_charge_seam("event reroll"))
	if not bool(result.get("ok", false)):
		return _refuse("reroll the event", String(result.get("text", "")))

	print("RUNFLOW_EVENT_REROLL " + JSON.stringify({
		"cost": int(result.get("cost", 0)),
		"gold_before": gold_before,
		"gold": _run.gold(),
		"reroll_index": int(result.get("reroll_index", 0)),
		"rerolls_left": _event.rerolls_left(),
		"stock": _event.stock(),
	}))
	return true


## Applies a high-stakes good roll to one tower copy: +1 tier, once. Refused with
## the reason kept pending when the copy is already at `MAX_TOWER_TIER`, because
## the player picks the target and a refusal must not consume the reward.
func claim_high_stakes_tier_up(tower_id: int) -> bool:
	if _pending_tier_up_node == -1:
		return _refuse("claim the high-stakes tier-up", "no tier-up is pending")
	var tower = _inventory.find_tower(tower_id)
	if tower == null:
		return _refuse(
			"claim the tier-up for tower %d" % tower_id, "no such tower in the inventory"
		)
	if int(tower.tier) >= MAX_TOWER_TIER:
		return _refuse(
			"raise tower %d" % tower_id,
			"it is already at tier %d, the highest a copy can reach; choose another copy"
			% MAX_TOWER_TIER
		)

	var before_tier := int(tower.tier)
	var new_tier: int = _inventory.raise_tower_tier(tower_id, 1)
	if new_tier == 0:
		return _refuse("raise tower %d" % tower_id, _inventory.last_refusal())

	var node_id := _pending_tier_up_node
	_pending_tier_up_node = -1
	print("RUNFLOW_TIER_UP " + JSON.stringify({
		"node": node_id,
		"tower_id": tower_id,
		"type_id": String(tower.type_id),
		"tier_before": before_tier,
		"tier": new_tier,
	}))
	return true


# --- queries ----------------------------------------------------------------

## The map for this run. Never null after `start_run()` returned true.
func map():
	return _map


func run_state():
	return _run


func inventory():
	return _inventory


## The open store's shelf, or null when no store visit is open. The caller reads
## slots (`slot(i)`, `stock()`) and may flip the site's own reroll switch; buying
## goes through `buy()` so the cap and the purse are checked in one place.
func store():
	return _store


## The open event set, or null. Read slots with `slot(i)`/`stock()`; taking one
## goes through `choose_event()`.
func event_offer():
	return _event


## What the last boss preview revealed: `{boss_node, level, active_tiles,
## dominant_enemies, telegraph}`, or {} before any preview. Empty is the honest
## answer to "what does the player know", and a UI shows nothing for it.
func revealed_boss() -> Dictionary:
	return _revealed_boss.duplicate(true)


## The high-stakes outcome for `node_id`, if it has been rolled.
##
## Reading this **never rolls**: before the node is entered it answers
## `{"node": id, "rolled": false}`, so a map screen that called it by accident
## would learn nothing and change nothing. After entry it returns the one recorded
## roll, so re-reading cannot re-roll it and no caller can tell a read from a draw.
func high_stakes_outcome(node_id: int) -> Dictionary:
	if not _rolls.has(node_id):
		return {"node": node_id, "rolled": false}
	return (_rolls[node_id] as Dictionary).duplicate(true)


## The node whose good high-stakes roll still needs a tower chosen, or -1. A UI
## uses this to open the "pick a copy" step; the player then calls
## `claim_high_stakes_tier_up(tower_id)`.
func pending_tier_up_node() -> int:
	return _pending_tier_up_node


## One record per resolved non-level node, oldest first: the same dictionaries the
## `RUNFLOW_NODE` lines carried. A copy, so a caller cannot rewrite history.
func node_effects() -> Array:
	return _node_effects.duplicate(true)


## The level scene while one is open, null on the map. The caller may drive it
## (`start_level()`), and must not free it: `complete_level()` does.
func current_level():
	return _level


func level_node_id() -> int:
	return _level_node_id


func is_in_level() -> bool:
	return _phase == Phase.IN_LEVEL


func phase() -> int:
	return _phase


func phase_name() -> String:
	if _phase < 0 or _phase >= PHASE_NAMES.size():
		return "unknown(%d)" % _phase
	return PHASE_NAMES[_phase]


## Levels this session has completed. Equal to `run_state().level_index()` while
## the session is the only completer, which is the invariant "exactly once".
func completion_count() -> int:
	return _completions


func refused_count() -> int:
	return _refusals


## Why the most recent call was refused, verbatim, or "" when none was. Printed
## as `RUNFLOW_REFUSED` at the time, and kept readable so a harness asserts on
## the words and not only on a counter.
func last_refusal() -> String:
	return _last_refusal


## Everything a map screen, a HUD or a test wants, in one dictionary.
func snapshot() -> Dictionary:
	return {
		"phase": phase_name(),
		"seed": _map.seed_value() if _map != null else 0,
		"sha": _map.sha() if _map != null else "",
		"route": _map.route() if _map != null else [],
		"map_complete": _map.is_complete() if _map != null else false,
		"selectable": _map.selectable_nodes() if _map != null else [],
		"level_node": _level_node_id,
		"level_open": _phase == Phase.IN_LEVEL,
		"completions": _completions,
		"run": _run.snapshot() if _run != null else {},
		"inventory": _inventory.snapshot() if _inventory != null else {},
		"store": _store.snapshot() if _store != null else {},
		"event": _event.snapshot() if _event != null else {},
		"store_visits": _store_visits,
		"event_visits": _event_visits,
		"high_stakes": _rolls.duplicate(true),
		"pending_tier_up": _pending_tier_up_node,
		"revealed_boss": _revealed_boss.duplicate(true),
		"node_effects": _node_effects.duplicate(true),
		"refusals": _refusals,
		"last_refusal": _last_refusal,
	}


# --- internals: the non-level nodes -----------------------------------------

## One place that turns a node type into its effect. The route has already moved
## onto `node_id` when this runs, so an effect that fails (a shelf that cannot be
## drawn) refuses loudly and leaves the run where it is - there is no "un-enter".
func _resolve_non_level(node_id: int, type_id: String) -> bool:
	match type_id:
		STORE_TYPE:
			return _open_store(node_id)
		REST_TYPE:
			return _resolve_rest(node_id)
		TREASURE_TYPE:
			return _resolve_treasure(node_id)
		EVENT_TYPE:
			return _open_event(node_id)
		HIGH_STAKES_TYPE:
			return _resolve_high_stakes(node_id)
		BOSS_PREVIEW_TYPE:
			return _resolve_boss_preview(node_id)
	return _refuse("resolve node %d" % node_id, "no effect is defined for type '%s'" % type_id)


func _open_store(node_id: int) -> bool:
	var layer := _layer_of(node_id)
	var site = StoreScript.new(
		_map.seed_value(),
		layer,
		_store_visits,
		ItemCatalogueScript.entries(),
		# store.md's second half is defined over the run's choice layers ("layers
		# 5-9 of 9"); the map's total_layers() includes the boss layer, which is the
		# end and not a choice. Derived from the map rather than hardcoded (ADR-0006).
		maxi(_map.total_layers() - 1, 1)
	)
	site.set_reroll_enabled(store_reroll_enabled)
	_store_visits += 1

	var drawn: Dictionary = site.draw()
	if not bool(drawn.get("ok", false)):
		return _refuse("open the store at node %d" % node_id, String(drawn.get("text", "")))

	_store = site
	_record_node_effect(node_id, STORE_TYPE, {
		"stock": _shelf_summary(),
		"second_half": site.is_second_half(),
		"guarantee_checked": site.guarantee_checked,
		"guarantee_repaired": site.guarantee_repaired,
		"reroll_enabled": site.is_reroll_enabled(),
		"next_reroll_cost": site.next_reroll_cost(),
	})
	return true


## The rest node's whole effect. `heal_hq()` clamps at the maximum and returns what
## it actually applied, so a rest at full HQ is a printed no-op rather than a
## silent one (`economy.md` §Edge cases: the heal is lost, never banked).
func _resolve_rest(node_id: int) -> bool:
	var before: int = _run.hq_health()
	var healed: int = _run.heal_hq(rest_heal)
	var effect := {
		"rest_heal": rest_heal,
		"healed": healed,
		"hq_before": before,
		"no_effect": healed == 0,
	}
	if healed == 0:
		effect["why"] = "the HQ was already at its maximum; the heal is lost, not banked"
	_record_node_effect(node_id, REST_TYPE, effect)
	return true


func _resolve_treasure(node_id: int) -> bool:
	var layer := _layer_of(node_id)
	var amount := treasure_base_gold + treasure_gold_per_layer * layer
	var before: int = _run.gold()
	var paid: int = _run.add_gold(amount, "treasure node %d" % node_id)
	if paid == 0:
		return _refuse("collect the treasure at node %d" % node_id, _run.last_refusal())
	_record_node_effect(node_id, TREASURE_TYPE, {
		"amount": amount,
		"gold_before": before,
		"gold_delta": paid,
	})
	return true


func _open_event(node_id: int) -> bool:
	var layer := _layer_of(node_id)
	var site = OfferSiteScript.new(
		_map.seed_value(), layer, _event_visits, ItemCatalogueScript.entries()
	)
	_event_visits += 1

	var drawn: Dictionary = site.draw(event_offer_count)
	if not bool(drawn.get("ok", false)):
		return _refuse("open the event at node %d" % node_id, String(drawn.get("text", "")))

	_event = site
	_record_node_effect(node_id, EVENT_TYPE, {
		"offers": site.stock(),
		"count": site.stock().size(),
		"next_reroll_cost": site.next_reroll_cost(),
		"reroll_enabled": site.is_reroll_enabled(),
	})
	return true


## The blind roll. `_roll_high_stakes()` is the only writer of `_rolls`, and this
## is its only caller: the outcome exists from the moment the node is chosen and
## from nowhere earlier. A good roll either leaves a tier-up pending for the player
## to place or, with no copy below tier 3 to raise, degrades to gold
## (`nodes.md` §Edge cases: a reward must degrade, never dead-end).
func _resolve_high_stakes(node_id: int) -> bool:
	var outcome := _roll_high_stakes(node_id)
	var effect := outcome.duplicate(true)
	var gold_before: int = _run.gold()
	effect["gold_before"] = gold_before

	if bool(outcome["good"]):
		var target := _lowest_tier_tower_id()
		if target == 0:
			var paid: int = _run.add_gold(
				high_stakes_gold_fallback, "high-stakes fallback (no copy below tier %d)" % MAX_TOWER_TIER
			)
			effect["reward"] = "gold"
			effect["reward_gold"] = paid
		else:
			_pending_tier_up_node = node_id
			effect["reward"] = "tier_up"
			effect["reward_target"] = target
	else:
		var applied: int = _run.damage_hq(
			high_stakes_hq_damage, "high-stakes node %d" % node_id
		)
		effect["reward"] = "none"
		effect["hq_damage"] = applied

	effect["gold_delta"] = int(_run.gold()) - gold_before
	effect["run_over"] = _run.is_over()
	_record_node_effect(node_id, HIGH_STAKES_TYPE, effect)
	return true


## Draws and records the one roll for `node_id`. The outcome is a pure function of
## the run seed, the layer and the node id (`OfferSite.derive_seed`), so it is
## reproducible across processes, and it is written to `_rolls` so no read can
## produce a second one. Called only on entry.
func _roll_high_stakes(node_id: int) -> Dictionary:
	if _rolls.has(node_id):
		return (_rolls[node_id] as Dictionary).duplicate(true)

	var layer := _layer_of(node_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = OfferSiteScript.derive_seed(
		_map.seed_value(), StringName("high_stakes"), layer, node_id, 0
	)
	var good := rng.randf() < high_stakes_good_chance
	var outcome := {
		"node": node_id,
		"layer": layer,
		"rolled": true,
		"good": good,
		"kind": "tier_up" if good else "hq_damage",
		"hq_damage_roll": 0 if good else high_stakes_hq_damage,
	}
	_rolls[node_id] = outcome
	return outcome.duplicate(true)


## Reveals the boss and nothing else: no gold, no HQ, no level index, no item
## (`nodes.md` §boss preview: "Does not reveal" lists the rest, and the brief says
## no state change beyond the reveal).
func _resolve_boss_preview(node_id: int) -> bool:
	var boss_id := -1
	for id in _map.node_ids():
		if String(_map.type_of(int(id))) == BOSS_TYPE:
			boss_id = int(id)
			break
	if boss_id == -1:
		return _refuse("preview the boss at node %d" % node_id, "this map has no boss node")

	var boss = _map.node(boss_id)
	_revealed_boss = {
		"boss_node": boss_id,
		"level": String(boss.level_id),
		"active_tiles": _map.active_tile_count(boss_id),
		"dominant_enemies": boss.dominant_enemy_types.duplicate(),
		"telegraph": RunMapScript.BOSS_ENEMY,
		# nodes.md also asks for the boss's wave count. It is not here on purpose:
		# the boss's level index depends on how many levels the route took
		# (ADR-0006: there is no level total), so at preview time it cannot be
		# known. Reported rather than guessed.
		"wave_count_known": false,
	}
	var effect := _revealed_boss.duplicate(true)
	effect["state_changed"] = false
	_record_node_effect(node_id, BOSS_PREVIEW_TYPE, effect)
	return true


## Lands a shelf or event entry in the inventory. The single place an item becomes
## owned: a tower keeps its tier (the instance has one), an upgrade instance is
## identity only, so a tier-2 rune lands as its type id and the tier is recorded in
## the print line only (see the header's KNOWN GAP).
func _add_item(entry: Dictionary, source: String) -> Dictionary:
	var kind := String(entry.get("kind", ""))
	var item_id := String(entry.get("id", ""))
	var tier := int(entry.get("tier", 1))
	if kind == OfferSiteScript.KIND_TOWER:
		var tower = _inventory.add_tower(item_id, tier)
		if tower == null:
			return {"ok": false, "reason": _inventory.last_refusal(), "source": source}
		return {
			"ok": true,
			"kind": kind,
			"id": item_id,
			"tier": tier,
			"tower_id": int(tower.id),
		}
	var upgrade = _inventory.add_upgrade(item_id)
	if upgrade == null:
		return {"ok": false, "reason": _inventory.last_refusal(), "source": source}
	return {
		"ok": true,
		"kind": kind,
		"id": item_id,
		"tier": tier,
		"upgrade_id": int(upgrade.id),
	}


## The charge seam the offer and store systems take: `func(amount: int) -> bool`
## that returns false **without debiting** when the balance is short. `spend_gold`
## has exactly that behaviour, and binding the reason keeps the ledger readable.
func _charge_seam(purpose: String) -> Callable:
	return Callable(_run, "spend_gold").bind(purpose)


## The shelf as a compact, JSON-safe list: one entry per slot, empty slots
## included, so a reader can tell "bought" from "the shelf moved".
func _shelf_summary() -> Array:
	var out: Array = []
	if _store == null:
		return out
	var slots: Array = _store.stock()
	for i in slots.size():
		var entry: Dictionary = slots[i]
		if OfferSiteScript.is_empty_slot(entry):
			out.append({"slot": i, "empty": true})
			continue
		out.append({
			"slot": i,
			"id": String(entry.get("id", "")),
			"kind": String(entry.get("kind", "")),
			"tier": int(entry.get("tier", 1)),
			"price": int(entry.get("price", 0)),
		})
	return out


## The id of the copy a tier-up should probably go to: the lowest tier, first come.
## A suggestion for a HUD, never the rule - the player names the copy through
## `claim_high_stakes_tier_up()`. 0 means "no copy below tier 3 exists", which is
## the case that degrades to gold.
func _lowest_tier_tower_id() -> int:
	var best := 0
	var best_tier := 0
	for tower in _inventory.towers():
		var tier := int(tower.tier)
		if tier >= MAX_TOWER_TIER:
			continue
		if best == 0 or tier < best_tier:
			best = int(tower.id)
			best_tier = tier
	return best


## The layer the player sees: 1-based, matching `nodes.md`'s tables and the store's
## own layer arithmetic.
func _layer_of(node_id: int) -> int:
	var node = _map.node(node_id)
	return 1 if node == null else int(node.layer) + 1


## Records a resolved node in one place and prints it. `RUNFLOW_NODE` is the
## evidence line for every non-level effect: the effect's own keys plus where the
## run stands after it.
func _record_node_effect(node_id: int, type_id: String, effect: Dictionary) -> void:
	var record := {
		"node": node_id,
		"type": type_id,
		"layer": _layer_of(node_id),
		"hq": _run.hq_health(),
		"hq_max": _run.hq_max_health(),
		"gold": _run.gold(),
		"levels_completed": _run.level_index(),
		"route": _map.route(),
		"next": _map.selectable_nodes(),
	}
	for key in effect.keys():
		record[key] = effect[key]
	_node_effects.append(record)
	print("RUNFLOW_NODE " + JSON.stringify(record))


# --- internals: the level handover ------------------------------------------

## Opens the level for `node_id`. The scene is seeded from the run before it
## enters the tree: HQ and gold are the run's, the level number is the run's
## (ADR-0006, so `level_from_run`), and only the elite flag comes from the node.
func _open_level(node_id: int, type_id: String) -> bool:
	var elite := type_id == ELITE_TYPE
	var arena = level_scene.instantiate()
	if arena == null:
		# The route has already moved onto this node and there is no way back, so
		# this is a wiring failure and says so. It is not a refusal a player can
		# recover from, and it must never be silent.
		push_error("RUNFLOW_ERROR level_scene did not instantiate; node %d has no level" % node_id)
		return _refuse("open node %d" % node_id, "the level scene did not instantiate")
	if not arena.has_signal("level_cleared"):
		arena.free()
		push_error(
			"RUNFLOW_ERROR the level scene has no 'level_cleared' signal; a completion cannot return"
		)
		return _refuse("open node %d" % node_id, "the level scene cannot hand a completion back")

	arena.name = "Level%d" % _run.level_number()
	# Before the node enters the tree, so `_ready` builds the plan and prints
	# ARENA_START with the values actually in force.
	arena.set("level_from_run", true)
	arena.set("elite_level", elite)
	if not arena.bind_run(_run, _inventory):
		arena.free()
		return _refuse("open node %d" % node_id, "the level scene refused the run and inventory")
	arena.level_cleared.connect(_on_level_cleared)

	add_child(arena)
	_level = arena
	_level_node_id = node_id
	_phase = Phase.IN_LEVEL

	print("RUNFLOW_ENTER " + JSON.stringify({
		"node": node_id,
		"layer": int(_map.node(node_id).layer) + 1,
		"type": type_id,
		"level": String(_map.node(node_id).level_id),
		"active_tiles": _map.active_tile_count(node_id),
		"elite": elite,
		"level_index": _run.level_number(),
		"hq": _run.hq_health(),
		"gold": _run.gold(),
		"route": _map.route(),
		"next": _map.selectable_nodes(),
	}))
	level_opened.emit(node_id, _run.level_number(), elite)
	return true


## The level scene's single report: its last wave is clear. The session does the
## counting, so a level that reported twice would be refused the second time
## (the first completion closed it) rather than counted twice.
func _on_level_cleared(_level_index: int, _elite: bool) -> void:
	if _level == null or _phase != Phase.IN_LEVEL:
		_refuse(
			"complete the level",
			"the level reported a clear with no level open; nothing was counted"
		)
		return
	# A refused completion has already printed its reason.
	complete_level()


## `RunState` ended the run: victory from `win_run()` above, or defeat when the
## HQ reached zero mid-level. One place closes the level and announces it.
func _on_run_ended(victory: bool, reason: String) -> void:
	_phase = Phase.FINISHED
	if _level != null:
		_level.queue_free()
		_level = null
		_level_node_id = -1

	print("RUNFLOW_RUN_END " + JSON.stringify({
		"victory": victory,
		"reason": reason,
		"status": _run.status_name(),
		"levels_completed": _run.level_index(),
		"hq": _run.hq_health(),
		"hq_max": _run.hq_max_health(),
		"gold": _run.gold(),
		"route": _map.route() if _map != null else [],
		"map_complete": _map.is_complete() if _map != null else false,
	}))
	run_ended.emit(victory, reason)


## One place where refusals are worded, stored and printed. Returns false so a
## caller can `return _refuse(...)`. Printed, never `push_error`: a refused move
## is expected play, and an ERROR line would make `smoke.ps1` red for a working
## game (`arena.gd` sets the same precedent).
func _refuse(action: String, why: String) -> bool:
	_refusals += 1
	_last_refusal = "cannot %s: %s" % [action, why]
	print("RUNFLOW_REFUSED " + JSON.stringify({
		"action": action,
		"reason": why,
		"phase": phase_name(),
		"route": _map.route() if _map != null else [],
		"levels_completed": _run.level_index() if _run != null else 0,
	}))
	return false
