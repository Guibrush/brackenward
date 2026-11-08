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
##   RUNFLOW_INVENTORY {json}    the inventory snapshot a run opens with (T-0058)
##   RUNFLOW_LOADOUT_A {json}    an empty loadout table, refused with a reason
##   RUNFLOW_LOADOUT_B {json}    a loadout naming a type the catalogue lacks, refused
##   RUNFLOW_PLANTED_A {json}    a node that is visible but not selectable, refused
##   RUNFLOW_PLANTED_B {json}    completion with no level open, refused
##   RUNFLOW_PANEL {json}        the build panel's list when the first level opens
##   RUNFLOW_NON_LEVEL {json}    a non-level node resolved and the route moved onto it
##   RUNFLOW_ROUTE {json}        the route and the numbers after each level
##   RUNFLOW_AFTER_END {json}    a node entry after the run ended, refused
##   RUNFLOW_RUN {json}          the ending: status, victory, HQ, gold, route
##   RUNFLOW_SELF_TEST {json}    once, last; carries checks and failures
##
## The `RUNFLOW_LOADOUT`, `RUNFLOW_START`, `RUNFLOW_ENTER`, `RUNFLOW_COMPLETE`,
## `RUNFLOW_RUN_END`, `RUNFLOW_REFUSED`, `BUILD_PANEL_*`, `ARENA_*`, `WAVE_*` and
## `RUN_REFUSED` lines are printed by the systems under test, not by this file. The
## exit code is not evidence (L-035); `RUNFLOW_SELF_TEST` is.
##
## Waves are driven by hand in one frame per level, the way `run_demo.gd` drives
## one level: every unit is killed the tick it spawns, so no leak reaches the HQ
## and the whole 10-level route runs in seconds instead of a quarter of an hour.
## A leak would fail the HQ-carried checks, which is deliberate - the walk is
## evidence about the route, so it must not quietly absorb damage.

const ARENA_SCENE := "res://scenes/main.tscn"
const RunFlowScript := preload("res://src/gameplay/run_flow.gd")
const RunStateScript := preload("res://src/systems/run_state.gd")
const ItemCatalogueScript := preload("res://src/gameplay/item_catalogue.gd")

## A type no catalogue table holds. Used to plant the loadout refusal that names an
## entry: the check is that the sentence repeats this id, not that it fails.
const UNKNOWN_TOWER_ID := "trebuchet"

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
## Set once a non-level node has been resolved: the walk plants it on the first
## layer that offers such a node. Every type resolves since T-0049, so what the
## walk demonstrates is acceptance, not a refusal.
var _planted_non_level: bool = false

## What the inventory held the instant `map_ready` was emitted (T-0058), and
## whether the build panel has been read yet. -1 means the signal never fired.
var _towers_at_map_ready: int = -1
var _upgrades_at_map_ready: int = -1
var _build_panel_checked: bool = false


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# Nothing is safe before the tree has iterated once: a node added to `root`
	# here has not run `_ready` yet.
	await process_frame

	_flow = RunFlowScript.new()
	_flow.name = "RunFlow"
	_flow.level_scene = load(ARENA_SCENE)
	# Connected before `start_run()` so the handler reads the inventory at the
	# instant the map became ready - that is what "granted before the map is ready"
	# means, and a reading taken afterwards could not tell the two apart.
	_flow.map_ready.connect(_on_map_ready)
	root.add_child(_flow)

	if not check(_flow.start_run(SEED), "the run starts from seed %d" % SEED):
		_finish()
		return
	_hq_carried = _flow.run_state().hq_health()
	_gold_carried = _flow.run_state().gold()

	_case("the starting loadout")
	_check_starting_loadout()
	_check_empty_loadout_refused()
	_check_unknown_loadout_refused()

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


# --- the starting loadout (T-0058) ------------------------------------------

## What the inventory held at the instant `map_ready` was emitted. The grant is
## supposed to happen before that signal, so this reading is the measurement of
## "before the map is ready": one taken after `start_run()` returned could not tell
## the two orders apart.
func _on_map_ready(_seed_value: int, _selectable: Array) -> void:
	_towers_at_map_ready = _flow.inventory().tower_count() if _flow.inventory() != null else 0
	_upgrades_at_map_ready = _flow.inventory().upgrade_count() if _flow.inventory() != null else 0


## A run that starts from a seed opens holding two distinct tier-1 towers and two
## tier-1 upgrades, every one of them a pair the catalogue holds.
func _check_starting_loadout() -> void:
	var inventory = _flow.inventory()
	if not check(inventory != null, "the run opened with an inventory"):
		return
	var snapshot: Dictionary = inventory.snapshot()
	print("RUNFLOW_INVENTORY " + JSON.stringify(snapshot))

	check_eq_int(int(snapshot["tower_count"]), 2, "the run opens holding two towers")
	check_eq_int(int(snapshot["upgrade_count"]), 2, "the run opens holding two upgrades")
	check_eq_int(int(snapshot["placed_count"]), 0, "nothing is placed before the first level")
	check_eq_int(_towers_at_map_ready, 2, "both towers were granted before the map was ready")
	check_eq_int(_upgrades_at_map_ready, 2, "both upgrades were granted before the map was ready")

	var catalogue: Array = ItemCatalogueScript.entries()
	var tower_types: Array = []
	for tower in inventory.towers():
		var type_id := String(tower.type_id)
		var tier := int(tower.tier)
		tower_types.append(type_id)
		check_eq_int(tier, 1, "starting tower '%s' is tier 1" % type_id)
		check(
			not _catalogue_pair(catalogue, true, type_id, tier).is_empty(),
			"starting tower '%s' tier %d is a pair item_catalogue.gd holds" % [type_id, tier]
		)
	tower_types.sort()
	check(
		tower_types.size() == 2 and String(tower_types[0]) != String(tower_types[1]),
		"the two starting towers are distinct types: %s" % [tower_types]
	)

	for upgrade in inventory.upgrades():
		var type_id := String(upgrade.type_id)
		check(
			not _catalogue_pair(catalogue, false, type_id, 1).is_empty(),
			"starting upgrade '%s' tier 1 is a pair item_catalogue.gd holds" % type_id
		)


## Planted failure A: a run whose loadout table is empty refuses to start, with a
## reason, instead of opening a level in which nothing can be placed.
func _check_empty_loadout_refused() -> void:
	var broken = _new_refused_flow([])
	var started: bool = broken.start_run(SEED)
	var reason: String = broken.last_refusal()

	print("RUNFLOW_LOADOUT_A " + JSON.stringify({
		"loadout": broken.starting_loadout,
		"started": started,
		"reason": reason,
		"phase": broken.phase_name(),
		"map": broken.map() != null,
		"inventory": broken.inventory() != null,
		"refusals": broken.refused_count(),
	}))
	check(not started, "an empty starting loadout refuses to start the run")
	check(reason.find("loadout is empty") != -1, "the refusal says the loadout is empty")
	check(broken.map() == null, "the refused start built no map")
	check(broken.inventory() == null, "the refused start created no inventory")
	check(broken.phase_name() == "idle", "the refused start left the session idle")
	broken.free()


## Planted failure B: an entry naming a type the catalogue does not hold refuses
## the run, and the sentence names the entry so the table can be fixed by eye.
func _check_unknown_loadout_refused() -> void:
	var table: Array = [
		{"kind": "tower", "type_id": "arrow", "tier": 1},
		{"kind": "tower", "type_id": UNKNOWN_TOWER_ID, "tier": 1},
	]
	var broken = _new_refused_flow(table)
	var started: bool = broken.start_run(SEED)
	var reason: String = broken.last_refusal()

	print("RUNFLOW_LOADOUT_B " + JSON.stringify({
		"loadout": broken.starting_loadout,
		"started": started,
		"reason": reason,
		"names_entry": reason.find(UNKNOWN_TOWER_ID) != -1,
		"phase": broken.phase_name(),
		"inventory": broken.inventory() != null,
		"refusals": broken.refused_count(),
	}))
	check(not started, "a loadout naming an unknown type refuses to start the run")
	check(
		reason.find(UNKNOWN_TOWER_ID) != -1,
		"the refusal names the type the catalogue lacks ('%s')" % UNKNOWN_TOWER_ID
	)
	check(reason.find("item_catalogue") != -1, "the refusal says which table it checked")
	check(broken.inventory() == null, "the refused start created no inventory")
	broken.free()


## A session that exists only to be refused: it never enters the tree, so the
## refusal cannot leave a level or a signal behind.
func _new_refused_flow(table: Array):
	var flow = RunFlowScript.new()
	flow.name = "RunFlowRefused"
	flow.level_scene = load(ARENA_SCENE)
	flow.starting_loadout = table
	return flow


## The catalogue's entry for this (kind, id, tier), or {} when it has none. The
## demo's own copy, on purpose: asking the session the same question would let a
## bug in its lookup pass its own check.
func _catalogue_pair(catalogue: Array, want_tower: bool, type_id: String, tier: int) -> Dictionary:
	for record in catalogue:
		var candidate: Dictionary = record
		if String(candidate.get("id", "")) != type_id:
			continue
		if int(candidate.get("tier", 1)) != tier:
			continue
		if (String(candidate.get("kind", "")) == ItemCatalogueScript.KIND_TOWER) != want_tower:
			continue
		return candidate
	return {}


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

## Walks the map to the boss: resolves a non-level node where the route offers
## one (T-0049), plays every level node it can, and checks the numbers the
## completion left behind.
func _walk() -> void:
	var map = _flow.map()
	var steps := 0
	while not map.is_complete() and steps < MAX_ROUTE_STEPS:
		steps += 1
		var target := _next_level_node(map)
		# A route can pass through a non-level node (T-0049 makes every one of
		# them resolvable). The first such node on offer is demonstrated even
		# when a level is available too; a later one is taken only when it is
		# the only way forward. Either way the route moves without a level being
		# played, so the numbers a level must open with are re-read: they still
		# mean "what the route left behind".
		if target == -1 or not _planted_non_level:
			_planted_non_level = _plant_non_level(map)
			if _planted_non_level:
				_hq_carried = _flow.run_state().hq_health()
				_gold_carried = _flow.run_state().gold()
				if _flow.run_state().is_over():
					break
				continue
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
		if not _build_panel_checked:
			# The first level's build phase is the one the loadout exists for.
			_build_panel_checked = true
			await _check_build_panel()
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


## A selectable node whose type resolves inside the session rather than opening a
## level (T-0049). Entering it must succeed and move the route onto it, with no
## level opened and no completion counted: the opposite of the "not implemented"
## refusal this demo planted while some types had no effect. Returns false when
## the layer offers no such node, and the walk then takes a level instead.
func _plant_non_level(map) -> bool:
	for id in map.selectable_nodes():
		var type_id := String(map.type_of(id))
		if not RunFlowScript.NON_LEVEL_TYPES.has(type_id):
			continue
		var route_before: Array = map.route()
		var levels_before: int = _flow.run_state().level_index()
		var effects_before: int = _flow.node_effects().size()
		var entered: bool = _flow.enter_node(id)
		var recorded: Array = _flow.node_effects()
		print("RUNFLOW_NON_LEVEL " + JSON.stringify({
			"node": id,
			"type": type_id,
			"entered": entered,
			"reason": _flow.last_refusal(),
			"route_before": route_before,
			"route_after": map.route(),
			"level_open": _flow.is_in_level(),
			"levels_completed": _flow.run_state().level_index(),
			"effect": {} if recorded.is_empty() else recorded[-1],
		}))
		check(entered, "a '%s' node resolves instead of being refused" % type_id)
		check(
			map.route() == route_before + [id],
			"the '%s' node was entered and the route advanced onto it" % type_id
		)
		check(not _flow.is_in_level(), "the '%s' node opened no level" % type_id)
		check_eq_int(
			_flow.run_state().level_index(),
			levels_before,
			"the '%s' node completed no level" % type_id
		)
		check(
			recorded.size() == effects_before + 1
			and String(recorded[-1].get("type", "")) == type_id,
			"the '%s' node recorded exactly one effect, of its own type" % type_id
		)
		if _flow.event_offer() != null:
			# An event set blocks movement until one offer is taken
			# (`run_flow.gd`: a between-level offer cannot be skipped), so the
			# walk takes one and the route keeps moving.
			check(_flow.choose_event(0), "the '%s' node offers an item to take" % type_id)
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


# --- the build panel at the first level -------------------------------------

## The panel the arena ships, read when the first level opens and before its first
## wave: the list a player sees in the first build phase. T-0058 exists because
## that list was empty while the panel itself worked, so the check is the count and
## the contents, not that the panel exists.
func _check_build_panel() -> void:
	var arena = _flow.current_level()
	if not check(arena != null, "the session opened a level scene for the panel check"):
		return
	var panel = arena.get_node_or_null("BuildPanel")
	if not check(panel != null, "the level scene ships a build panel"):
		return

	# The panel queues its first draw from `_ready`, and the arena's own `_ready`
	# (which seeds the run and the inventory the draw reads) runs after its
	# children's. Two frames is the bound the walk already uses for a queued node.
	await process_frame
	await process_frame

	var rows: Array = panel.rows()
	var labels: Array = []
	var shown_types: Array = []
	for entry in rows:
		var row: Dictionary = entry
		labels.append(String(row.get("label", "")))
		if String(row.get("kind", "")) == "tower":
			shown_types.append(String(row.get("type_id", "")))
	shown_types.sort()

	var held_types: Array = []
	for tower in _flow.inventory().towers():
		held_types.append(String(tower.type_id))
	held_types.sort()

	print("RUNFLOW_PANEL " + JSON.stringify({
		"bound": panel.arena() == arena,
		"phase": panel.phase_name(),
		"row_count": panel.row_count(),
		"rows": labels,
		"tower_types": shown_types,
		"towers": _flow.inventory().tower_count(),
		"state": panel.state(),
	}))
	check(panel.arena() == arena, "the panel is bound to the level it sits in")
	check(panel.row_count() > 0, "the build panel lists something when the level opens")
	check_eq_int(
		shown_types.size(),
		_flow.inventory().tower_count(),
		"the panel has one row per tower the run holds"
	)
	check(shown_types == held_types, "the panel lists the towers the inventory holds")


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
