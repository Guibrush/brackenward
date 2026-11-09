extends SceneTree

## T-0050 DoD 2, 3 and 4 - the map screen, driven headlessly, in one run.
##
##     godot --headless --path . --script res://src/ui/tests/run_map_screen_demo.gd
##
## The demo drives the real `RunFlow`, the real `res://scenes/run_map_screen.tscn`
## and the real `res://scenes/main.tscn` for the level it opens. No mock screen, no
## mock session: the list, the refusals and the numbers are the ones the player
## would see.
##
## Prints, in this order:
##   MAPSCREEN_CASE {text}          one line per phase
##   MAPSCREEN_ROWS {json}          the list against the map's visible set
##   MAPSCREEN_STATE {json}         HQ/gold/towers shown against RunState's snapshot
##   MAPSCREEN_INPUT {json}         the intents the router produced, per device
##   MAPSCREEN_PLANTED_A {json}     a visible-but-unselectable node listed, asked
##                                  why, and refused without the route moving
##   MAPSCREEN_ROUTE {json}         a chosen node: the route advanced, the screen
##                                  yielded to the level and came back
##   MAPSCREEN_PLANTED_B {json}     a stale state binding caught, not displayed
##   MAPSCREEN_SELF_TEST {json}     once, last; carries checks and failures
##
## The exit code is not evidence (L-035); `MAPSCREEN_SELF_TEST` is. The
## `MAPSCREEN_*` lines the screen prints as it works are the screen's own, not
## this file's; `RUNFLOW_*`, `ARENA_*` and `WAVE_*` belong to the systems under
## test.

const ARENA_SCENE := "res://scenes/main.tscn"
const SCREEN_SCENE := "res://scenes/run_map_screen.tscn"
const RunFlowScript := preload("res://src/gameplay/run_flow.gd")
const RunStateScript := preload("res://src/systems/run_state.gd")
const MapInputScript := preload("res://src/ui/map_input.gd")

## The seed the walk is recorded against. A change here changes the route, so the
## printed sha in RUNFLOW_START is what a reader compares, not this number.
const SEED := 20261108

## Game time per wave-director tick while the level is played by hand: large
## enough that every tick with something queued spawns a unit.
const TICK_SECONDS := 10.0
## Guard so a wave that never finishes fails the demo instead of hanging it
## (`run_flow_demo.gd` uses the same bound for the same reason).
const MAX_WAVE_TICKS := 4000
const LETHAL_DAMAGE := 1000000

var _flow = null
var _screen = null
var _router = null
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# Nothing is safe before the tree has iterated once.
	await process_frame

	_flow = RunFlowScript.new()
	_flow.name = "RunFlow"
	_flow.level_scene = load(ARENA_SCENE)
	root.add_child(_flow)

	var packed = load(SCREEN_SCENE)
	if not check(packed != null, "the map screen scene loads"):
		_finish()
		return
	_screen = packed.instantiate()
	if not check(_screen != null, "the map screen scene instantiates"):
		_finish()
		return
	root.add_child(_screen)
	await process_frame

	_router = MapInputScript.new()

	_case("binding, before the run starts")
	if not check(_screen.bind_run(_flow), "the screen binds to the session"):
		_finish()
		return
	check(not _screen.visible, "with no run there is no map, so the screen shows nothing")

	_case("the run begins; map_ready brings the screen up")
	if not check(_flow.start_run(SEED), "the run starts from seed %d" % SEED):
		_finish()
		return
	await process_frame
	check(_screen.visible, "map_ready shows the screen")
	_check_rows()
	_check_state()
	_check_input()

	_case("planted failure A: visible, not selectable")
	_planted_failure_a()

	_case("choosing a node, and the level taking the screen")
	await _choose_and_play_level()

	_case("planted failure B: a stale state binding")
	_planted_failure_b()

	_finish()


# --- the list ---------------------------------------------------------------

## DoD 2, first half: the screen lists exactly the map's visible nodes, with the
## type, dominant enemies and active tiles the map says they have.
func _check_rows() -> void:
	var map = _flow.map()
	var drawn: Array = _screen.drawn_ids()
	var visible: Array = map.visible_nodes()
	var rows: Array = _screen.rows()
	var labelled := true
	var leveled := true
	var hidden := true
	var selectable_ok := true
	for entry in rows:
		var id := int(entry["id"])
		if String(entry["type_name"]) == "" or String(entry["label"]) == "":
			labelled = false
		var info: Dictionary = map.knowledge(id)
		if info.has("level"):
			if int(entry["active_tiles"]) <= 0 or (entry["dominant_enemies"] as Array).is_empty():
				leveled = false
			if String(entry["level"]) != String(info["level"]):
				leveled = false
		if String(info.get("detail", "")) == "hidden_until_entry":
			if String(entry["detail"]) != "hidden_until_entry":
				hidden = false
			if String(entry["level"]) != "":
				hidden = false
		if bool(entry["selectable"]) != bool(map.is_selectable(id)):
			selectable_ok = false

	print("MAPSCREEN_ROWS " + JSON.stringify({
		"visible": visible,
		"drawn": drawn,
		"count": rows.size(),
		"selectable": _screen.state_selectable_ids(),
		"rows": _printable_rows(rows),
	}))
	check(drawn == visible, "the screen lists exactly the map's visible nodes, in map order")
	check_eq_int(rows.size(), visible.size(), "one row per visible node")
	check(labelled, "every row shows a type name and text")
	check(leveled, "every level row shows its map, tile count and dominant enemies")
	check(hidden, "a blind node shows that its content is unknown, and no level")
	check(
		_screen.state_selectable_ids() == map.selectable_nodes(),
		"the rows marked selectable are exactly the map's next choices"
	)
	check(selectable_ok, "every row's selectable flag matches the map's")


## DoD 2, second half: HQ current/max and gold on screen are `RunState`'s, and
## the tower count is the inventory's.
func _check_state() -> void:
	var run = _flow.run_state()
	var snapshot: Dictionary = run.snapshot()
	var st: Dictionary = _screen.state()
	var shown: Dictionary = st["shown"]

	print("MAPSCREEN_STATE " + JSON.stringify({
		"shown": shown,
		"label": st["label"],
		"stale": st["stale"],
		"run_snapshot": snapshot,
		"towers": _flow.inventory().tower_count(),
	}))
	check_eq_int(int(shown.get("hq", -1)), int(snapshot["hq"]), "HQ shown matches RunState")
	check_eq_int(
		int(shown.get("hq_max", -1)), int(snapshot["hq_max"]), "HQ max shown matches RunState"
	)
	check_eq_int(int(shown.get("gold", -1)), int(snapshot["gold"]), "gold shown matches RunState")
	check_eq_int(
		int(shown.get("towers", -1)),
		_flow.inventory().tower_count(),
		"towers shown matches the inventory"
	)
	check(not bool(st["stale"]), "the state line is not stale")
	check(
		String(st["label"]).find("%d/%d" % [int(snapshot["hq"]), int(snapshot["hq_max"])]) != -1,
		"the state line prints HQ current/max"
	)
	var label_node = _screen.get_node_or_null(_screen.get("state_path"))
	check(
		label_node != null and String(label_node.text) == String(st["label"]),
		"the label on screen is the state the screen reports"
	)


## The input abstraction: every action the screen performs comes from an intent,
## and every action the screen names is one of the game's own four, each bound to
## a keyboard key **and** a joypad button in `project.godot`.
##
## This is the assertion that was false before T-0050's fix: it asked the same
## question of Godot's built-in `ui_accept`/`ui_cancel`, which carry keyboard
## events only, so a pad could move the focus but never confirm. The router now
## names `game_*`, so the check measures what the screen actually reads.
func _check_input() -> void:
	var confirm: Dictionary = _router.intent_for(_action_event(MapInputScript.ACTION_CONFIRM))
	var next: Dictionary = _router.intent_for(_action_event(MapInputScript.ACTION_FOCUS_NEXT))
	var prev: Dictionary = _router.intent_for(_action_event(MapInputScript.ACTION_FOCUS_PREV))
	var dismiss: Dictionary = _router.intent_for(_action_event(MapInputScript.ACTION_DISMISS))
	var mouse: Dictionary = _router.intent_for(_click_event(Vector2(20, 20)))

	var names: Array = _router.action_names()
	var pad_missing: Array = []
	var key_missing: Array = []
	for action in names:
		if not _has_joypad_binding(action):
			pad_missing.append(String(action))
		if not _has_keyboard_binding(action):
			key_missing.append(String(action))
	var builtin: Array = names.filter(func(action): return String(action).begins_with("ui_"))

	print("MAPSCREEN_INPUT " + JSON.stringify({
		"confirm": confirm,
		"focus_next": next,
		"focus_prev": prev,
		"dismiss": dismiss,
		"mouse": mouse,
		"actions": names,
		"keyboard_missing": key_missing,
		"joypad_missing": pad_missing,
		"builtin_actions": builtin,
		"focus_after_moves": _screen.focus_index(),
	}))
	check(int(confirm["intent"]) == MapInputScript.Intent.CONFIRM, "game_confirm is CONFIRM")
	check(int(next["intent"]) == MapInputScript.Intent.FOCUS_NEXT, "game_focus_next is FOCUS_NEXT")
	check(int(prev["intent"]) == MapInputScript.Intent.FOCUS_PREV, "game_focus_prev is FOCUS_PREV")
	check(int(dismiss["intent"]) == MapInputScript.Intent.DISMISS, "game_dismiss is DISMISS")
	check(
		int(mouse["intent"]) == MapInputScript.Intent.CONFIRM and mouse.has("pointer"),
		"a left click is CONFIRM carrying the pointer position"
	)
	check(builtin.is_empty(), "the screen names no built-in ui_* action: %s" % [builtin])
	check(
		key_missing.is_empty(),
		"every action the screen names carries a keyboard binding: %s" % [key_missing]
	)
	check(
		pad_missing.is_empty(),
		"every action the screen names carries a joypad binding: %s" % [pad_missing]
	)


# --- planted failures -------------------------------------------------------

## DoD 3. A node the map reveals but does not offer - a lure - is drawn, refused
## with a reason, and never reaches `enter_node()`: the session's refusal count
## and the route are both unchanged.
func _planted_failure_a() -> void:
	var map = _flow.map()
	var target := -1
	var index := -1
	var rows: Array = _screen.rows()
	for i in rows.size():
		if not bool(rows[i]["selectable"]):
			target = int(rows[i]["id"])
			index = i
			break
	if not check(target != -1, "the map reveals a node that is not a next choice (a lure)"):
		return

	var route_before: Array = map.route()
	var refusals_before: int = _flow.refused_count()
	var gold_before: int = _flow.run_state().gold()
	var hq_before: int = _flow.run_state().hq_health()
	var listed: bool = _screen.drawn_ids().has(target)
	var reason: String = _screen.reason_for(index)

	var focused := _focus_row(index)
	var result: Dictionary = _screen.handle_input(_action_event(MapInputScript.ACTION_CONFIRM))

	print("MAPSCREEN_PLANTED_A " + JSON.stringify({
		"node": target,
		"row": index,
		"type": String(rows[index]["type"]),
		"layer": int(rows[index]["layer"]),
		"listed": listed,
		"selectable": bool(rows[index]["selectable"]),
		"focused": focused,
		"reason": reason,
		"screen_reason": _screen.reason(),
		"intent": result.get("name", ""),
		"applied": bool(result.get("applied", false)),
		"route_before": route_before,
		"route_after": map.route(),
		"session_refusals_before": refusals_before,
		"session_refusals_after": _flow.refused_count(),
		"level_open": _flow.is_in_level(),
		"gold_before": gold_before,
		"gold": _flow.run_state().gold(),
		"hq_before": hq_before,
		"hq": _flow.run_state().hq_health(),
	}))
	check(listed, "the unselectable node is still listed")
	check(not bool(rows[index]["selectable"]), "the row is marked not selectable")
	check(reason != "", "the screen says why the node cannot be taken")
	check(
		reason.find("lure") != -1 or reason.find("next choice") != -1,
		"the reason names the rule that refuses it"
	)
	check(focused, "the row can be focused, so it can be asked about")
	check(not bool(result.get("applied", false)), "confirming it is refused")
	check(map.route() == route_before, "the refused node did not advance the route")
	check_eq_int(
		_flow.refused_count(),
		refusals_before,
		"the refusal happened in the screen: enter_node() was never called"
	)
	check(not _flow.is_in_level(), "the refused node opened no level")
	check_eq_int(_flow.run_state().gold(), gold_before, "the refused node moved no gold")
	check_eq_int(_flow.run_state().hq_health(), hq_before, "the refused node moved no HQ")
	check(_screen.visible, "the screen is still showing after refusing")


## DoD 2's successful choice plus DoD 4's yield: choose a level node through the
## input path, watch the screen hide when the level opens, play the level, and
## watch it come back with fresh numbers.
func _choose_and_play_level() -> void:
	var map = _flow.map()
	var index := -1
	var rows: Array = _screen.rows()
	for i in rows.size():
		if bool(rows[i]["selectable"]) and RunFlowScript.LEVEL_TYPES.has(String(rows[i]["type"])):
			index = i
			break
	if not check(index != -1, "a level node is among the next choices"):
		return

	var target := int(rows[index]["id"])
	var route_before: Array = map.route()
	var gold_before: int = _flow.run_state().gold()

	if not check(_focus_row(index), "the level node can be focused"):
		return
	var result: Dictionary = _screen.handle_input(_action_event(MapInputScript.ACTION_CONFIRM))

	print("MAPSCREEN_ROUTE " + JSON.stringify({
		"node": target,
		"row": index,
		"type": String(rows[index]["type"]),
		"intent": result.get("name", ""),
		"applied": bool(result.get("applied", false)),
		"route_before": route_before,
		"route_after": map.route(),
		"level_open": _flow.is_in_level(),
		"screen_visible": _screen.visible,
	}))
	check(bool(result.get("applied", false)), "confirming a selectable node is applied")
	check(map.route() == route_before + [target], "the route advanced onto the chosen node")
	check(_flow.is_in_level(), "the chosen node opened its level")
	check(not _screen.visible, "the screen yielded when the level opened")

	var kills: int = await _play_level()
	await process_frame

	print("MAPSCREEN_ROUTE " + JSON.stringify({
		"completed": target,
		"levels_completed": _flow.run_state().level_index(),
		"gold_before": gold_before,
		"gold": _flow.run_state().gold(),
		"kills": kills,
		"screen_visible": _screen.visible,
		"rows": _screen.drawn_ids(),
		"visible": map.visible_nodes(),
		"state": _screen.state()["label"],
	}))
	check(not _flow.is_in_level(), "the level finished and control returned to the map")
	check(_screen.visible, "the screen came back when the level completed")
	check_eq_int(_flow.run_state().level_index(), 1, "the completed level was counted once")
	check(
		_screen.drawn_ids() == map.visible_nodes(),
		"the returned screen lists the newly revealed nodes"
	)
	check(
		int(_screen.state()["shown"]["levels_completed"]) == 1,
		"the returned state line carries the new progress"
	)
	check_eq_int(
		_flow.run_state().gold(),
		gold_before + kills + RunStateScript.GOLD_PER_LEVEL_CLEAR,
		"gold shown is the run's: carried plus kills plus the level clear"
	)


## DoD 4. The state binding is pointed at the numbers from before the level. The
## screen reports the mismatch instead of the wrong numbers, refuses a choice
## while it cannot trust its own display, and recovers when told to re-read.
func _planted_failure_b() -> void:
	var live: Dictionary = _flow.run_state().snapshot()
	var stale := {
		"hq": int(live["hq"]),
		"hq_max": int(live["hq_max"]),
		"gold": int(live["gold"]) - 7,
		"towers": _flow.inventory().tower_count(),
		"levels_completed": int(live["levels_completed"]),
	}
	_screen.force_shown_state_for_demo(stale)
	_screen.refresh()

	var st: Dictionary = _screen.state()
	var label_node = _screen.get_node_or_null(_screen.get("state_path"))
	var shown_on_screen := "" if label_node == null else String(label_node.text)

	var map = _flow.map()
	var index := -1
	var rows: Array = _screen.rows()
	for i in rows.size():
		if bool(rows[i]["selectable"]):
			index = i
			break
	var route_before: Array = map.route()
	var refusals_before: int = _flow.refused_count()
	var applied := false
	if index != -1:
		applied = _screen.activate(index)

	print("MAPSCREEN_PLANTED_B " + JSON.stringify({
		"stale_binding": stale,
		"live": live,
		"stale": st["stale"],
		"mismatch": st["mismatch"],
		"label": st["label"],
		"shown_on_screen": shown_on_screen,
		"row": index,
		"applied": applied,
		"reason": _screen.reason(),
		"route_before": route_before,
		"route_after": map.route(),
		"session_refusals_before": refusals_before,
		"session_refusals_after": _flow.refused_count(),
	}))
	check(bool(st["stale"]), "the screen catches that its state view is stale")
	check(
		(st["mismatch"] as Dictionary).has("gold"),
		"the mismatch names the field that disagrees: gold"
	)
	if (st["mismatch"] as Dictionary).has("gold"):
		check_eq_int(
			int(st["mismatch"]["gold"]["shown"]),
			int(stale["gold"]),
			"the mismatch reports the number that was about to be shown"
		)
		check_eq_int(
			int(st["mismatch"]["gold"]["live"]),
			int(live["gold"]),
			"the mismatch reports the session's real number"
		)
	check(
		String(st["label"]) == String(_screen.stale_text),
		"the state line says it cannot be trusted instead of printing numbers"
	)
	check(
		shown_on_screen == String(_screen.stale_text),
		"the label on screen is the refusal, not the stale number"
	)
	check(
		shown_on_screen.find(str(int(stale["gold"]))) == -1,
		"the stale gold is not displayed at all"
	)
	check(not applied, "a choice is refused while the state cannot be trusted")
	check(
		String(_screen.reason()).find("stale") != -1,
		"the refusal says the snapshot is stale"
	)
	check(map.route() == route_before, "the refused choice did not advance the route")
	check_eq_int(
		_flow.refused_count(),
		refusals_before,
		"the stale refusal happened in the screen: enter_node() was never called"
	)

	_case("the binding recovers when it re-reads")
	_screen.use_live_state()
	_screen.refresh()
	var recovered: Dictionary = _screen.state()
	var recovered_label = _screen.get_node_or_null(_screen.get("state_path"))
	print("MAPSCREEN_PLANTED_B " + JSON.stringify({
		"recovered_stale": recovered["stale"],
		"recovered_label": recovered["label"],
	}))
	check(not bool(recovered["stale"]), "re-reading the session clears the stale flag")
	check(
		recovered_label != null and String(recovered_label.text) == String(recovered["label"]),
		"the state line shows the session's numbers again"
	)
	check(
		String(recovered["label"]).find(str(int(live["gold"]))) != -1,
		"the recovered state line prints the run's gold"
	)


# --- driving ----------------------------------------------------------------

## Plays the open level's waves to the end, killing every unit the tick it spawns.
## Copied in shape from `run_flow_demo.gd`, which is the same walk one level at a
## time; the screen is what is under test here, not the arena.
func _play_level() -> int:
	var arena = _flow.current_level()
	if not check(arena != null, "the session opened a level scene"):
		return 0
	var director = arena.wave_director()
	if not check(director != null, "the level has a wave director"):
		return 0
	if not check(arena.start_wave(0), "the level's first wave starts"):
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
			if not arena.start_wave(director.current_index() + 1):
				break
	check(not _flow.is_in_level(), "the level finished inside %d ticks" % MAX_WAVE_TICKS)
	return paid


## Moves the screen's focus to row `index` with the same intent a d-pad sends,
## wrapping at most once. Returns whether the row got focus.
func _focus_row(index: int) -> bool:
	var rows: int = _screen.row_count()
	if rows == 0 or index < 0 or index >= rows:
		return false
	for i in rows + 1:
		if _screen.focus_index() == index:
			return true
		_screen.handle_input(_action_event(MapInputScript.ACTION_FOCUS_NEXT))
	return _screen.focus_index() == index


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _click_event(point: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	return event


## A row with its `node` reference removed: a Button is not JSON, and printing one
## would either fail or leak a node handle into the evidence line.
func _printable_rows(rows: Array) -> Array:
	var out: Array = []
	for entry in rows:
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		copy.erase("node")
		out.append(copy)
	return out


## Whether `action` carries at least one joypad event in the project's input map.
## This is the honest half of "gamepad-ready": the actions the router names are
## bound to a pad, and the screen reads only those actions.
func _has_joypad_binding(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


## The other half: a pad-only binding would make the screen unplayable on a
## keyboard, so a keyboard event is required too.
func _has_keyboard_binding(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return true
	return false


# --- reporting --------------------------------------------------------------

func _case(label: String) -> void:
	print("MAPSCREEN_CASE " + label)


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


## Exactly one self-test line, last. A demo that recorded no checks fails.
func _finish() -> void:
	if _checks == 0 and _failures.is_empty():
		_failures.append("the demo recorded no checks")

	var passed := _failures.is_empty()
	print("MAPSCREEN_SELF_TEST " + JSON.stringify({
		"name": "run_map_screen_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("MAPSCREEN_FAILURE " + f)
	quit(1)
