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
## * NOT IMPLEMENTED YET (T-0049): `store`, `rest`, `treasure`, `event`,
##   `high_stakes_event` and `boss_preview` are recognised by type id and refused
##   with "not implemented". The route does **not** advance onto them, so a
##   refused stop cannot strand a run on a node nobody can resolve. `boss_preview`
##   plays a level in the node registry and is still refused here: its payload is
##   a preview screen, and that screen is T-0049's.
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
##   RUNFLOW_ENTER {json}     once per node entered, with the level it opened
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

## Node types this session plays as a level, by id. The registry's `plays_level`
## is not the test: it is true for `boss_preview` too, and that node's level is
## T-0049's. Adding a level type here is the whole change a new level node needs.
const LEVEL_TYPES := [
	RunMapNodeTypeScript.TYPE_MAP,
	RunMapNodeTypeScript.TYPE_ELITE,
	RunMapNodeTypeScript.TYPE_BOSS,
]
const ELITE_TYPE := RunMapNodeTypeScript.TYPE_ELITE
const BOSS_TYPE := RunMapNodeTypeScript.TYPE_BOSS

## Node types that exist on the map and are not implemented here (T-0049). Kept
## as data so a refusal names the type rather than failing on an unknown one.
const NOT_IMPLEMENTED_TYPES := [
	"store",
	"rest",
	"treasure",
	"event",
	"high_stakes_event",
	"boss_preview",
]

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
func start_run(seed_value: int) -> bool:
	if _phase == Phase.IN_LEVEL:
		return _refuse("start a run", "level %d is still open; complete it first" % _run.level_number())
	if _run != null and _run.is_in_progress():
		return _refuse("start a run", "a run is already in progress; finish it first")
	if level_scene == null:
		return _refuse(
			"start a run", "no level_scene is wired, so a level node would have nothing to open"
		)

	var map = RunMapScript.new()
	if not map.generate(seed_value):
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
## brings the player back to the map.
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
	if not LEVEL_TYPES.has(type_id):
		if NOT_IMPLEMENTED_TYPES.has(type_id):
			return _refuse(
				"enter node %d" % node_id,
				"node type '%s' is not implemented yet (T-0049); the route does not advance"
				% type_id
			)
		return _refuse("enter node %d" % node_id, "unknown node type '%s'" % type_id)

	# The map's own check runs last and is not bypassed: the route moves only
	# when `RunMap.enter()` agrees, so the session cannot invent a legal move.
	if not _map.enter(node_id):
		return _refuse("enter node %d" % node_id, _map.last_refusal())
	return _open_level(node_id, type_id)


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


# --- queries ----------------------------------------------------------------

## The map for this run. Never null after `start_run()` returned true.
func map():
	return _map


func run_state():
	return _run


func inventory():
	return _inventory


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
		"refusals": _refusals,
		"last_refusal": _last_refusal,
	}


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
