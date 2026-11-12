extends SceneTree

## T-0063 DoD - the build panel's input is **delivered**, not just implemented.
##
##     godot --headless --path . --script res://src/ui/tests/input_route_demo.gd
##
## Every assertion in this file is made after an event has travelled the route a
## player's event travels: menu -> Start Game -> map -> first node -> the level the
## session opened -> the panel that level instanced for itself. No check calls
## `handle_input()`, `activate()`, `place_at()` or `_input()`; a check that did
## would be testing the method, which is exactly how the "clicking does nothing"
## bug stayed green (`build_panel_demo.gd` and `build_panel_boot_demo.gd` both bind
## or call the panel by hand).
##
## The events are pushed into the root viewport (`get_root().push_input()`, the
## same entry point the OS uses), so they pass through the GUI hit-tester and the
## panel's own `_input` exactly like a mouse or a key does.
##
## Prints, in this order:
##   INPUT_ROUTE_CASE {text}      one line per case
##   INPUT_ROUTE_INTENT {json}    one line per event handed to `MapInput` in the
##                                horizontal-pair case (T-0089)
##   INPUT_ROUTE_EVENT {json}     one line per pushed event: what was sent, where
##   INPUT_ROUTE_STATE {json}     the panel's own answer after each case: rows,
##                                armed, selected, focus, free tiles, reason
##   INPUT_ROUTE_SELF_TEST {json} once, last; carries checks and failures
##
## The exit code is not evidence (L-035); `INPUT_ROUTE_SELF_TEST` is. `BOOT_*`,
## `MENU_*`, `MAPSCREEN_*`, `RUNFLOW_*` and `BUILD_PANEL_*` lines around these belong
## to the objects under test, not to this file.

const BOOT_SCENE := "res://scenes/boot.tscn"

const MapInputScript := preload("res://src/ui/map_input.gd")

## The map this demo walks, recorded so the evidence names it (the same seed
## `build_panel_boot_demo.gd` uses, so both demos talk about one run).
const SEED := 20261108

## The window the panel is laid out in. `--headless` gives every run a 64x64
## viewport whatever the project says (measured T-0062), and a click can only be
## aimed at a rect a HUD fits in. 1152x648 is the project's default window.
const VIEWPORT := Vector2i(1152, 648)

const SETTLE_FRAMES := 2

var _boot = null
var _panel = null
var _arena = null
var _flow = null

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = VIEWPORT
	await process_frame

	# Runs before the walk: the router is the door every later case goes
	# through, so a missing branch is named here and not in a screen.
	_check_horizontal_intents()

	var packed = load(BOOT_SCENE)
	if not check(packed != null, "the boot scene loads"):
		_finish()
		return
	_boot = packed.instantiate()
	_boot.run_seed = SEED
	# Quitting the tree would end this demo before it reported.
	_boot.set_quit_enabled_for_demo(false)
	root.add_child(_boot)
	await process_frame

	_case("DoD 4a: the first real game_confirm takes Start Game from the menu")
	if not check(_boot.screen_name() == "menu", "the boot opens on the menu: %s" % _boot.screen_name()):
		_finish()
		return
	await _press(KEY_ENTER, "game_confirm (Enter), menu row %d" % _boot.menu().focus_index())
	if not check(_boot.screen_name() == "map", "Enter on the menu opened the map: %s" % _boot.screen_name()):
		_finish()
		return
	_flow = _boot.flow()

	_case("DoD 4b: the second real game_confirm takes the map's first level node")
	var screen = _boot.map_screen()
	var node_id := _first_level_node()
	if not check(node_id != -1, "the map offers a level node as its first choice"):
		_finish()
		return
	await _press(KEY_ENTER, "game_confirm (Enter), map row %d" % screen.focus_index())
	await _settle()
	if not check(_boot.screen_name() == "level", "Enter on the map opened the level: %s" % _boot.screen_name()):
		_finish()
		return

	_arena = _flow.current_level()
	if not check(_arena != null, "the session opened the level scene"):
		_finish()
		return
	_panel = _find_panel(_arena)
	if not check(_panel != null and _panel.visible, "the level instanced a visible build panel"):
		_finish()
		return
	_state("level open")
	check(_panel.row_count() >= 3, "the panel drew Start Wave and the loadout's towers: %d rows" % _panel.row_count())

	# --- 1. a real click on a tower row arms it -------------------------------
	_case("DoD 2: a real left click on the arrow row arms it")
	var tower_row := _row_of_kind("tower")
	if not check(not tower_row.is_empty(), "the panel has a tower row to click"):
		_finish()
		return
	var wanted_id := int(tower_row["id"])
	var point: Vector2 = (tower_row["node"] as Control).get_global_rect().get_center()
	check_eq_int(_panel.armed_instance(), -1, "nothing is armed before the click")
	await _click(point, "left click on row %d (%s)" % [int(tower_row["index"]), String(tower_row["type_id"])])
	check_eq_int(_panel.armed_instance(), wanted_id, "the click armed instance %d" % wanted_id)
	check_eq_int(_panel.selected_instance(), wanted_id, "the click selected the same instance")
	check_eq_int(_panel.focus_index(), int(tower_row["index"]), "the click moved the focus to that row")
	_state("after the row click")

	# --- 2. a real click on a build tile places it ----------------------------
	_case("DoD 3: a real left click on a build tile places the armed tower")
	var slot := _free_slot()
	if not check(not slot.is_empty(), "the level has a free build tile"):
		_finish()
		return
	var free_before: int = _arena.free_slot_count()
	var tile_point: Vector2 = _canvas_point(slot["position"])
	await _click(tile_point, "left click on tile %s at %s" % [String(slot["name"]), tile_point])
	check_eq_int(_arena.free_slot_count(), free_before - 1, "the tile is no longer free")
	check_eq_int(_panel.armed_instance(), -1, "placing disarms: the tower is on the board now")
	check_eq_int(_panel.selected_instance(), wanted_id, "the placed tower stays selected")
	check(_panel.reason() == "", "placing with a tower armed is not refused: '%s'" % _panel.reason())
	check(_kinds().has("upgrade"), "the placed tower offers Upgrade: %s" % [_kinds()])
	check(_kinds().has("take_back"), "the placed tower offers Take back: %s" % [_kinds()])
	var placed_row := _row_of_instance(wanted_id)
	check(not placed_row.is_empty() and bool(placed_row["placed"]),
		"the tower's row says it is placed: %s" % [placed_row.get("label", "")])
	_state("after the tile click")

	# --- 3. a real click on a placed tower opens its actions ------------------
	_case("DoD 1: a real left click on the placed tower opens its actions")
	await _press(KEY_ESCAPE, "game_dismiss (Escape), to close the action rows")
	check_eq_int(_panel.selected_instance(), -1, "Escape closed the selected tower's actions")
	check(not _kinds().has("upgrade"), "the action rows are gone: %s" % [_kinds()])
	await _click(tile_point, "left click on the placed tower at %s" % tile_point)
	check_eq_int(_panel.selected_instance(), wanted_id, "the click selected the tower standing there")
	check_eq_int(_panel.armed_instance(), -1, "clicking a placed tower arms nothing")
	check(_kinds().has("upgrade"), "its actions are back: %s" % [_kinds()])
	_state("after the tower click")

	# --- 4. keyboard: focus, confirm, dismiss through game_* -----------------
	_case("DoD 1/2: Up/Down move the focus and Enter confirms, through game_*")
	await _press(KEY_DOWN, "game_focus_next (Down)")
	var focus_after_down: int = _panel.focus_index()
	check(focus_after_down != int(placed_row.get("index", -1)),
		"Down moved the focus off the row it was on: now %d" % focus_after_down)
	await _press(KEY_UP, "game_focus_prev (Up)")
	check(focus_after_down != _panel.focus_index(), "Up moved it again: now %d" % _panel.focus_index())
	# Put the focus on the in-hand tower and confirm it.
	var in_hand := _row_of_kind_unplaced()
	if not check(not in_hand.is_empty(), "the loadout still holds a tower in hand"):
		_finish()
		return
	await _focus_row(int(in_hand["index"]))
	await _press(KEY_ENTER, "game_confirm (Enter) on row %d" % int(in_hand["index"]))
	check_eq_int(_panel.armed_instance(), int(in_hand["id"]),
		"Enter armed the focused in-hand tower %d" % int(in_hand["id"]))
	_state("after the keyboard confirm")
	await _press(KEY_ESCAPE, "game_dismiss (Escape), to disarm")
	check_eq_int(_panel.armed_instance(), -1, "Escape disarmed the tower")
	_state("after Escape")

	# --- 5. the panel owns the whole level, not just its rows ----------------
	_case("one owner: a click on bare sidebar space is answered, not silently lost")
	await _click(Vector2(160, 600), "left click on empty sidebar, nothing armed")
	check(_panel.reason() != "", "the panel answered the click: '%s'" % _panel.reason())
	_state("after the bare click")

	_finish()


# --- what the router translates, before any screen is involved ---------------

## T-0089: `game_move_left` / `game_move_right` are the placement pair, and they
## are their own intents - the four focus/confirm/dismiss intents must not have
## moved to make room for them. The events are real `InputEventKey` presses
## matched by the project's own input map (never `InputEventAction`, which would
## let a hand-written action name stand in for a binding), so a branch deleted
## from `intent_for()` fails here.
func _check_horizontal_intents() -> void:
	_case("T-0089: KEY_LEFT / KEY_RIGHT are the placement pair, KEY_UP is still focus")
	var router: RefCounted = MapInputScript.new()
	var left := _intent_of(router, _key_press(KEY_LEFT), "KEY_LEFT")
	var right := _intent_of(router, _key_press(KEY_RIGHT), "KEY_RIGHT")
	var up := _intent_of(router, _key_press(KEY_UP), "KEY_UP")

	check_eq_int(int(left["intent"]), MapInputScript.Intent.MOVE_LEFT, "KEY_LEFT is MOVE_LEFT")
	check(String(left["device"]) == MapInputScript.DEVICE_KEYBOARD,
		"KEY_LEFT arrives as a keyboard event: %s" % String(left["device"]))
	check_eq_int(int(right["intent"]), MapInputScript.Intent.MOVE_RIGHT, "KEY_RIGHT is MOVE_RIGHT")
	check(String(right["device"]) == MapInputScript.DEVICE_KEYBOARD,
		"KEY_RIGHT arrives as a keyboard event: %s" % String(right["device"]))
	check_eq_int(int(up["intent"]), MapInputScript.Intent.FOCUS_PREV,
		"KEY_UP still returns FOCUS_PREV, not a placement step")

	# The router names both actions, so a caller checking the input map against
	# `action_names()` sees the pair too.
	var names: Array = router.action_names()
	check(names.has(MapInputScript.ACTION_MOVE_LEFT) and names.has(MapInputScript.ACTION_MOVE_RIGHT),
		"action_names() names the placement pair: %s" % [names])


## One real key press, as the OS would deliver it: a physical keycode matched to
## a `game_*` action by the project's input map.
func _key_press(keycode: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.device = -1
	ev.physical_keycode = keycode
	ev.pressed = true
	return ev


## The router's answer for one event, printed as it is read.
func _intent_of(router: RefCounted, event: InputEvent, keyname: String) -> Dictionary:
	var result: Dictionary = router.intent_for(event)
	print("INPUT_ROUTE_INTENT " + JSON.stringify({
		"key": keyname,
		"intent": String(result["name"]),
		"device": String(result["device"]),
	}))
	return result


# --- the path a player takes ------------------------------------------------

func _first_level_node() -> int:
	for id in _flow.map().selectable_nodes():
		if _flow.LEVEL_TYPES.has(String(_flow.map().type_of(int(id)))):
			return int(id)
	return -1


# --- pushing events the way the OS does ------------------------------------

## One key press and its release, both pushed into the root viewport. `Key` is a
## Godot key constant (`KEY_ENTER`, `KEY_UP`, ...), so the event is matched to a
## `game_*` action by the project's own input map rather than by an action name
## this demo invented.
func _press(keycode: int, what: String) -> void:
	print("INPUT_ROUTE_EVENT " + JSON.stringify({"device": "key", "key": OS.get_keycode_string(keycode), "what": what}))
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.device = -1
		ev.physical_keycode = keycode
		ev.pressed = pressed
		get_root().push_input(ev)
		await process_frame
	await _settle()


## One left click: a move to the point, the press, then the release - the order a
## mouse produces, so the GUI hit-tester has a hovered control before the press.
func _click(point: Vector2, what: String) -> void:
	print("INPUT_ROUTE_EVENT " + JSON.stringify({
		"device": "mouse",
		"what": what,
		"point": [point.x, point.y],
	}))
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_root().push_input(motion)
	await process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.device = -1
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.position = point
		ev.global_position = point
		get_root().push_input(ev)
		await process_frame
	await _settle()


## Down to the row at `index` with real `game_focus_next` presses, never by setting
## the panel's focus directly.
func _focus_row(index: int) -> void:
	var guard := 0
	while _panel.focus_index() != index and guard < _panel.row_count() + 1:
		guard += 1
		await _press(KEY_DOWN, "game_focus_next (Down) to reach row %d" % index)


func _settle(frames: int = SETTLE_FRAMES) -> void:
	for _i in frames:
		await process_frame


# --- reading the level ------------------------------------------------------

## The panel the level instanced, found by what it can do rather than by its node
## name or by being the arena's child: the demo must not be the only thing that
## knows where it lives (same search as `build_panel_boot_demo.gd`).
func _find_panel(arena) -> Node:
	return _find_control_with(arena, "bind_arena")


func _find_control_with(node, method: String) -> Node:
	if node is Control and node.has_method(method):
		return node
	for child in node.get_children():
		var found := _find_control_with(child, method)
		if found != null:
			return found
	return null


func _rows() -> Array:
	return _panel.rows()


func _row_of_kind(kind: String) -> Dictionary:
	for entry in _rows():
		if String(entry["kind"]) == kind and not bool(entry["placed"]):
			return entry
	for entry in _rows():
		if String(entry["kind"]) == kind:
			return entry
	return {}


func _row_of_kind_unplaced() -> Dictionary:
	for entry in _rows():
		if String(entry["kind"]) == "tower" and not bool(entry["placed"]):
			return entry
	return {}


func _row_of_instance(instance_id: int) -> Dictionary:
	for entry in _rows():
		if String(entry["kind"]) == "tower" and int(entry["id"]) == instance_id:
			return entry
	return {}


func _kinds() -> Array:
	var out: Array = []
	for entry in _rows():
		out.append(String(entry["kind"]))
	return out


func _free_slot() -> Dictionary:
	var slots: Array = _arena.build_slots()
	for slot in slots:
		if bool(slot["free"]):
			return slot
	return {}


## A world point on the board as a viewport point, read from the arena's own
## transform rather than assumed: the level may be drawn through a camera.
func _canvas_point(world: Vector2) -> Vector2:
	return (_arena as CanvasItem).get_global_transform_with_canvas() * world


func _state(label: String) -> void:
	print("INPUT_ROUTE_STATE " + JSON.stringify({
		"case": label,
		"screen": _boot.screen_name(),
		"rows": _kinds(),
		"armed": _panel.armed_instance(),
		"selected": _panel.selected_instance(),
		"focus": _panel.focus_index(),
		"free_tiles": _arena.free_slot_count(),
		"gold": _arena.gold(),
		"reason": _panel.reason(),
	}))


# --- reporting --------------------------------------------------------------

func _case(label: String) -> void:
	print("INPUT_ROUTE_CASE " + label)


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
	print("INPUT_ROUTE_SELF_TEST " + JSON.stringify({
		"name": "input_route_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("INPUT_ROUTE_FAILURE " + f)
	quit(1)
