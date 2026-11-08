extends SceneTree

## T-0048 DoD 2, 3 and 4 - the run session walks a complete route, in one headless
## run.
##
##     godot --headless --path . --script res://src/gameplay/tests/run_flow_demo.gd
##
## The demo drives the real `RunFlow` (`src/gameplay/run_flow.gd`) and the real
## `res://scenes/main.tscn` for every level of the route. No mock session, no
## mock arena: the walk is the thing the game will do.
##
## Prints, in this order:
##   RUNFLOW_CASE {text}         one line per phase of the walk
##   RUNFLOW_PLANTED_A {json}    a node that is visible but not selectable, refused
##   RUNFLOW_PLANTED_B {json}    completion with no level open, refused
##   RUNFLOW_NOT_IMPLEMENTED {json}  a T-0049 node type, refused and not entered
##   RUNFLOW_ROUTE {json}        the route and the numbers after each level
##   RUNFLOW_AFTER_END {json}    a node entry after the run ended, refused
##   RUNFLOW_RUN {json}          the ending: status, victory, HQ, gold, route
##   RUNFLOW_SELF_TEST {json}    once, last; carries checks and failures
##
## The `RUNFLOW_ENTER`, `RUNFLOW_COMPLETE`, `RUNFLOW_RUN_END`, `RUNFLOW_REFUSED`,
## `ARENA_*`, `WAVE_*` and `RUN_REFUSED` lines are printed by the systems under
## test, not by this file. The exit code is not evidence (L-035);
## `RUNFLOW_SELF_TEST` is.
##
## Waves are driven by hand in one frame per level, the way `run_demo.gd` drives
## one level: every unit is killed the tick it spawns, so no leak reaches the HQ
## and the whole 10-level route runs in seconds instead of a quarter of an hour.
## A leak would fail the HQ-carried checks, which is deliberate - the walk is
## evidence about the route, so it must not quietly absorb damage.

const ARENA_SCENE := "res://scenes/main.tscn"
const RunFlowScript := preload("res://src/gameplay/run_flow.gd")
const RunStateScript := preload("res://src/systems/run_state.gd")

## The seed the walk is recorded against. A change here changes the route, so the
## printed sha in RUNFLOW_START is what a reader compares, not this number.
const SEED := 20261108

## Game time per director tick while a level is played by hand. Large enough that
## every tick with something queued spawns a unit: `WaveDirector.tick()` spawns at
## most one per call, so the unit count - not the clock - bounds the loop.
const TICK_SECONDS := 10.0
## Guard so a wave that never finishes fails the demo instead of hanging it. A
## level is at most 8 waves of at most 40 units, and each unit costs two ticks
## (spawn, then die), so 4000 is roughly three levels of headroom.
const MAX_WAVE_TICKS := 4000
## A level per route layer plus slack; a loop that runs past this is a bug.
const MAX_ROUTE_STEPS := 20

const LETHAL_DAMAGE := 1000000

var _flow = null
var _checks: int = 0
var _failures: Array[String] = []

## The numbers the previous level left behind: the next level must open with
## exactly these, which is what "carried" means.
var _hq_carried: int = 0
var _gold_carried: int = 0
var _levels_played: int = 0
## Set once the "not implemented" refusal has been demonstrated: the walk plants
## it on the first layer that offers such a node.
var _planted_not_implemented: bool = false


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# Nothing is safe before the tree has iterated once: a node added to `root`
	# here has not run `_ready` yet.
	await process_frame

	_flow = RunFlowScript.new()
	_flow.name = "RunFlow"
	_flow.level_scene = load(ARENA_SCENE)
	root.add_child(_flow)

	if not check(_flow.start_run(SEED), "the run starts from seed %d" % SEED):
		_finish()
		return
	_hq_carried = _flow.run_state().hq_health()
	_gold_carried = _flow.run_state().gold()

	_case("planted failures")
	_planted_failure_a()
	_planted_failure_b()

	_case("the route, node by node")
	await _walk()
	if _levels_played == 0:
		_finish()
		return

	_case("the ending")
	_after_end()
	_finish()


# --- planted failures -------------------------------------------------------

## Entering a node that is visible but is not one of the next choices. The map
## shows lures one layer ahead; a lure that is not a child of the node the route
## is on is exactly this case, and the run must not move onto it.
func _planted_failure_a() -> void:
	var map = _flow.map()
	var target := -1
	for id in map.visible_nodes():
		if not map.is_selectable(id):
			target = id
			break
	if not check(
		target != -1, "the map shows a visible node that is not a next choice (a lure)"
	):
		return

	var route_before: Array = map.route()
	var levels_before: int = _flow.run_state().level_index()
	var entered: bool = _flow.enter_node(target)

	print("RUNFLOW_PLANTED_A " + JSON.stringify({
		"node": target,
		"type": map.type_of(target),
		"layer": int(map.node(target).layer) + 1,
		"visible": map.is_visible(target),
		"selectable": map.is_selectable(target),
		"entered": entered,
		"reason": _flow.last_refusal(),
		"route_before": route_before,
		"route_after": map.route(),
		"level_open": _flow.is_in_level(),
		"levels_completed": _flow.run_state().level_index(),
	}))
	check(not entered, "entering a node that is not selectable is refused")
	check(
		_flow.last_refusal().find("not selectable") != -1,
		"the refusal says the node is not selectable"
	)
	check(map.route() == route_before, "the refused entry did not advance the route")
	check_eq_int(
		_flow.run_state().level_index(), levels_before, "the refused entry completed no level"
	)
	check(not _flow.is_in_level(), "the refused entry opened no level")


## Completion with no level open: nothing was entered, so nothing can finish.
## `RunState.complete_level()` must not be called - checked through the level
## index, which is what it moves, and through the level-clear gold it pays.
func _planted_failure_b() -> void:
	var levels_before: int = _flow.run_state().level_index()
	var gold_before: int = _flow.run_state().gold()
	var completed: bool = _flow.complete_level()

	print("RUNFLOW_PLANTED_B " + JSON.stringify({
		"completed": completed,
		"reason": _flow.last_refusal(),
		"levels_before": levels_before,
		"levels_completed": _flow.run_state().level_index(),
		"gold_before": gold_before,
		"gold": _flow.run_state().gold(),
		"phase": _flow.phase_name(),
	}))
	check(not completed, "completing a level that was never entered is refused")
	check(
		_flow.last_refusal().find("no level is open") != -1,
		"the refusal says no level is open"
	)
	check_eq_int(
		_flow.run_state().level_index(), levels_before, "RunState.complete_level() was not called"
	)
	check_eq_int(_flow.run_state().gold(), gold_before, "no level-clear gold was paid")


# --- the walk ---------------------------------------------------------------

## Enters one level node per layer until the map is complete, playing each level
## and checking the numbers the completion left behind.
func _walk() -> void:
	var map = _flow.map()
	var steps := 0
	while not map.is_complete() and steps < MAX_ROUTE_STEPS:
		steps += 1
		if not _planted_not_implemented:
			_planted_not_implemented = _plant_not_implemented(map)
		var target := _next_level_node(map)
		if not check(
			target != -1, "layer %d offers a level node to enter" % (map.current_layer() + 1)
		):
			return

		var levels_before: int = _flow.run_state().level_index()
		var gold_before: int = _flow.run_state().gold()
		var hq_before: int = _flow.run_state().hq_health()
		# Carried in: the level opens with what the route had, not with a reset.
		check_eq_int(
			hq_before, _hq_carried, "level %d opens carrying HQ %d" % [levels_before + 1, _hq_carried]
		)
		check_eq_int(
			gold_before,
			_gold_carried,
			"level %d opens carrying %d gold" % [levels_before + 1, _gold_carried]
		)

		if not check(_flow.enter_node(target), "node %d is entered" % target):
			return
		_levels_played += 1
		var type_id: String = map.type_of(target)
		print("RUNFLOW_ROUTE " + JSON.stringify({
			"entered": target,
			"type": type_id,
			"layer": levels_before + 1,
			"level_index": _flow.run_state().level_number(),
			"hq": _flow.run_state().hq_health(),
			"gold": _flow.run_state().gold(),
		}))

		var kills: int = await _play_level(type_id)
		if not check(not _flow.is_in_level(), "level %d returned control to the map" % (levels_before + 1)):
			return

		# After the completion: the level index moved by exactly one, and the run
		# paid the clear on top of the kills the level itself paid.
		check_eq_int(
			_flow.run_state().level_index(),
			levels_before + 1,
			"the completion advanced the level index by exactly one"
		)
		check_eq_int(
			_flow.completion_count(),
			_flow.run_state().level_index(),
			"the session called complete_level() exactly once per level"
		)
		check_eq_int(
			_flow.run_state().gold(),
			gold_before + kills + RunStateScript.GOLD_PER_LEVEL_CLEAR,
			"gold carried plus %d from kills plus %d for the clear"
			% [kills, RunStateScript.GOLD_PER_LEVEL_CLEAR]
		)
		print("RUNFLOW_ROUTE " + JSON.stringify({
			"completed": target,
			"type": type_id,
			"level_index": _flow.run_state().level_index(),
			"levels_completed": _flow.run_state().level_index(),
			"hq": _flow.run_state().hq_health(),
			"gold": _flow.run_state().gold(),
			"status": _flow.run_state().status_name(),
		}))

		_hq_carried = _flow.run_state().hq_health()
		_gold_carried = _flow.run_state().gold()
		if _flow.run_state().is_over():
			break

	check(
		map.is_complete(),
		"the walk reached the boss in %d step(s)" % MAX_ROUTE_STEPS
	)


## The first selectable node this session plays as a level, preferring an elite
## when the layer offers one. Every layer holds at least one `map` node, so a
## route of level nodes always exists; preferring the elite is the choice that
## exercises the elite flag the node hands the arena.
func _next_level_node(map) -> int:
	var fallback := -1
	for id in map.selectable_nodes():
		var type_id := String(map.type_of(id))
		if not RunFlowScript.LEVEL_TYPES.has(type_id):
			continue
		if type_id == RunFlowScript.ELITE_TYPE:
			return id
		if fallback == -1:
			fallback = id
	return fallback


## A selectable node whose type belongs to T-0049. Entering it must be refused
## with "not implemented" and must not move the route: a stop nobody can resolve
## would strand the run on it.
func _plant_not_implemented(map) -> bool:
	for id in map.selectable_nodes():
		var type_id := String(map.type_of(id))
		if not RunFlowScript.NOT_IMPLEMENTED_TYPES.has(type_id):
			continue
		var route_before: Array = map.route()
		var entered: bool = _flow.enter_node(id)
		print("RUNFLOW_NOT_IMPLEMENTED " + JSON.stringify({
			"node": id,
			"type": type_id,
			"entered": entered,
			"reason": _flow.last_refusal(),
			"route_before": route_before,
			"route_after": map.route(),
			"level_open": _flow.is_in_level(),
		}))
		check(not entered, "a '%s' node is refused, not entered" % type_id)
		check(
			_flow.last_refusal().find("not implemented") != -1,
			"the refusal says the type is not implemented"
		)
		check(map.route() == route_before, "the refused '%s' node did not advance the route" % type_id)
		check(not _flow.is_in_level(), "the refused '%s' node opened no level" % type_id)
		return true
	return false


## Plays the open level's waves to the end, killing every unit the tick it
## spawns, and returns the gold those kills paid.
func _play_level(type_id: String) -> int:
	var arena = _flow.current_level()
	if not check(arena != null, "the session opened a level scene"):
		return 0

	# Handed in: the level number is the run's, the elite flag is the node's, and
	# the HQ and gold the level shows are the run's.
	check_eq_int(
		arena.effective_level_index(),
		_flow.run_state().level_number(),
		"the arena plays the run's level number"
	)
	check(
		bool(arena.get("elite_level")) == (type_id == RunFlowScript.ELITE_TYPE),
		"the arena took the elite flag from the node (elite=%s)" % type_id
	)
	check_eq_int(arena.gold(), _flow.run_state().gold(), "the level opened with the run's gold")
	var hq = arena.get_node_or_null(arena.get("hq_path"))
	if check(hq != null, "the level has an HQ"):
		check_eq_int(
			hq.health(), _flow.run_state().hq_health(), "the level's HQ carries the run's health"
		)

	var director = arena.wave_director()
	if not check(director != null, "the level has a wave director"):
		return 0
	if not check(arena.start_level(), "the level's first wave starts"):
		return 0

	var paid := 0
	var ticks := 0
	while _flow.is_in_level() and ticks < MAX_WAVE_TICKS:
		director.tick(TICK_SECONDS)
		ticks += 1
		for walker in director.walkers():
			if not walker.is_alive():
				continue
			paid += maxi(walker.gold_reward, 0)
			walker.take_damage(LETHAL_DAMAGE)
		if not _flow.is_in_level():
			break
		if not director.is_active() and not director.is_level_complete():
			# Waves do not auto-advance; the level's owner starts the next one.
			if not arena.start_wave(director.current_index() + 1):
				break

	if not check(
		not _flow.is_in_level(),
		"the level finished inside %d ticks" % MAX_WAVE_TICKS
	):
		return paid
	# Two frames, so the level scene the session queued for deletion is really
	# gone before the next one opens.
	await process_frame
	await process_frame
	check(_flow.current_level() == null, "no level scene is left open on the map")
	return paid


# --- the ending -------------------------------------------------------------

## Entering a node after the run ended is refused, and the route does not move.
func _after_end() -> void:
	var map = _flow.map()
	var route_before: Array = map.route()
	var entered: bool = _flow.enter_node(map.current_node_id())
	print("RUNFLOW_AFTER_END " + JSON.stringify({
		"node": map.current_node_id(),
		"entered": entered,
		"reason": _flow.last_refusal(),
		"route_unchanged": map.route() == route_before,
	}))
	check(not entered, "entering a node after the run ended is refused")
	check(
		_flow.last_refusal().find("the run is over") != -1,
		"the refusal says the run is over"
	)
	check(map.route() == route_before, "the refused entry left the route where it was")

	var run = _flow.run_state()
	print("RUNFLOW_RUN " + JSON.stringify({
		"seed": SEED,
		"sha": map.sha(),
		"route": map.route(),
		"nodes": map.node_count(),
		"elite_nodes": _count_type(map, RunFlowScript.ELITE_TYPE),
		"levels_played": _levels_played,
		"levels_completed": run.level_index(),
		"completions": _flow.completion_count(),
		"hq": run.hq_health(),
		"hq_max": run.hq_max_health(),
		"gold": run.gold(),
		"status": run.status_name(),
		"victory": run.is_victory(),
		"is_over": run.is_over(),
		"end_reason": run.end_reason(),
		"map_complete": map.is_complete(),
		"phase": _flow.phase_name(),
	}))
	check(run.is_victory(), "the run ends as a victory")
	check(run.is_over(), "the run is over")
	check(map.is_complete(), "the route ended on the boss")
	check(
		run.end_reason().find("boss") != -1, "the ending's reason names the boss node"
	)
	check_eq_int(run.level_index(), _levels_played, "every level played was counted")
	check_eq_int(
		_flow.completion_count(), _levels_played, "complete_level() ran exactly once per level"
	)
	check(
		not run.is_defeated(), "no defeat: nothing leaked past the HQ during the walk"
	)
	check(_flow.phase_name() == "finished", "the session is finished, not on the map")


## How many nodes of `type_id` the whole map holds, chosen or not. Read into
## RUNFLOW_RUN so "no elite level was played" can be told apart from "the map had
## no elite level", which are different gaps in the evidence.
func _count_type(map, type_id: String) -> int:
	var count := 0
	for id in map.node_ids():
		if String(map.type_of(id)) == type_id:
			count += 1
	return count


# --- reporting --------------------------------------------------------------

func _case(label: String) -> void:
	print("RUNFLOW_CASE " + label)


func check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
	return condition


func check_eq_int(actual: int, expected: int, message: String) -> bool:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %d, got %d" % [message, expected, actual])
		return false
	return true


## Exactly one self-test line, last. A demo that recorded no checks fails: it
## proved nothing, and "no assertions" must never look like a pass.
func _finish() -> void:
	if _checks == 0 and _failures.is_empty():
		_failures.append("the demo recorded no checks")

	var passed := _failures.is_empty()
	print("RUNFLOW_SELF_TEST " + JSON.stringify({
		"name": "run_flow_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("RUNFLOW_FAILURE " + f)
	quit(1)
