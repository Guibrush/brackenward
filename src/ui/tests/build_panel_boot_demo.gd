extends SceneTree

## T-0061 DoD 2 - the build panel binds on the **real boot path**.
##
##     godot --headless --path . --script res://src/ui/tests/build_panel_boot_demo.gd
##
## The panel demos that existed before this one bind the panel by hand
## (`build_panel_demo.gd` calls `bind_arena()` itself), which is why the real game
## could ship with a panel that never bound: every green demo was passing an arena
## in. This demo never calls `bind_arena()` and never touches the level scene: it
## drives the game the way a player does - menu, Start Game, map, first node - and
## then reads the panel the level instantiated for itself.
##
## A panel that is unbound has an empty row list, `state()` and `wave()` fall back
## to their no-arena text and `_apply_copy()` prints the no-arena sentence, so the
## three checks below (bound, rows, non-empty lines) are exactly the checks the
## observed frame - hint text and nothing else - would have failed.
##
## The demo drives the game the way a player does and reads the rects the engine
## gives the panel's lines, so the viewport it asserts against has to be a
## viewport a 320 px sidebar can live in. Headless runs at 64x64 (measured
## T-0062), which no such panel fits inside, so the demo states the window it
## claims to be looking at - the project's default window size - and fails if the
## engine refuses it (see `_set_viewport`).
##
## Prints, in this order:
##   BOOT_PANEL_CASE {text}        one line per phase
##   BOOT_PANEL_MENU {json}        the menu row the demo took
##   BOOT_PANEL_MAP {json}         the map row the demo took
##   BOOT_PANEL_LEVEL {json}       the level the boot opened, and its arena
##   BOOT_PANEL_BIND {json}        is it bound, to which arena, and how many rows
##   BOOT_PANEL_LINES {json}       every line the panel puts on screen, as drawn
##   BOOT_PANEL_LAYOUT {json}      the same nodes' rects, because "the text exists"
##                                 and "the player can see it" are two claims
##   BOOT_PANEL_SELF_TEST {json}   once, last; carries checks and failures
##
## The exit code is not evidence (L-035); `BOOT_PANEL_SELF_TEST` is. `BOOT_*`,
## `MENU_*`, `RUNFLOW_*` and `ARENA_*` lines around these belong to the objects
## under test, not to this file.

const BOOT_SCENE := "res://scenes/boot.tscn"

## Recorded so the evidence names the map the demo walked, not just "a map".
const SEED := 20261108

## Frames waited after the level opens before the panel is read. The panel draws
## from a deferred call, so one frame is what the game gives it; the second is a
## margin so the assertion is not a race with the engine's own flush.
const SETTLE_FRAMES := 2

## The window the demo lays the panel out in. `--headless` gives every run a 64x64
## viewport whatever the project says, so a full-screen HUD is laid out against a
## rect no HUD fits in and every rect check becomes a statement about the dummy
## display rather than about the panel. 1152x648 is the project's default window
## (`root.content_scale_size` in the same run); the level's own board is 960x540,
## so this is the smaller of the two and still fits the whole sidebar.
const VIEWPORT := Vector2i(1152, 648)

var _boot = null
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	# After the first frame: a window size set before the engine has sized its own
	# root window is overwritten when it does (measured T-0062).
	_set_viewport()
	await process_frame

	var packed = load(BOOT_SCENE)
	if not check(packed != null, "the boot scene loads"):
		_finish()
		return
	_boot = packed.instantiate()
	if not check(_boot != null, "the boot scene instantiates"):
		_finish()
		return
	_boot.run_seed = SEED
	# Quitting the tree would end this demo before it reported.
	_boot.set_quit_enabled_for_demo(false)
	root.add_child(_boot)
	await process_frame

	_case("the boot opens on the menu, with no run and no level")
	if not _check_menu():
		_finish()
		return

	_case("Start Game opens the map")
	if not await _start_game():
		_finish()
		return

	_case("the first node opens a level, and the level's panel binds itself")
	if not await _enter_first_node():
		_finish()
		return

	_case("the panel is bound, lists Start Wave plus the loadout's towers, and its lines are filled")
	_check_panel()

	_finish()


# --- the path a player takes ------------------------------------------------

## Gives the run a window a HUD can be laid out in (see `VIEWPORT`). A window the
## engine did not accept is caught by the assertion in `_check_panel`, not here:
## this only asks, and the demo reports whether the ask was honoured.
func _set_viewport() -> void:
	root.size = VIEWPORT

func _check_menu() -> bool:
	if not check(_boot.screen_name() == "menu", "the boot opens on the menu: %s" % _boot.screen_name()):
		return false
	var menu = _boot.menu()
	if not check(menu != null, "the boot built its menu"):
		return false
	check(_boot.flow() == null, "no run session exists before Start Game")
	check(_boot.map_screen() == null, "no map screen exists before Start Game")

	var start_index := _row_index_with_id(menu, "start")
	print("BOOT_PANEL_MENU " + JSON.stringify({
		"rows": menu.row_count(),
		"ids": menu.drawn_ids(),
		"start_index": start_index,
		"focus": menu.focus_index(),
	}))
	return check(start_index >= 0, "the menu offers a Start Game row: %s" % [menu.drawn_ids()])


func _start_game() -> bool:
	var menu = _boot.menu()
	var start_index := _row_index_with_id(menu, "start")
	# Taken through the menu's own action, not by calling the boot's handler: the
	# row a player confirms is what has to work.
	var taken: bool = menu.activate(start_index)
	await process_frame

	var flow = _boot.flow()
	var screen = _boot.map_screen()
	print("BOOT_PANEL_MAP " + JSON.stringify({
		"taken": taken,
		"screen": _boot.screen_name(),
		"run": flow != null,
		"map_visible": screen != null and screen.visible,
		"map_rows": screen.row_count() if screen != null else -1,
		"selectable": flow.map().selectable_nodes() if flow != null else [],
	}))

	if not check(taken, "the Start Game row can be taken"):
		return false
	if not check(_boot.screen_name() == "map", "Start Game shows the map: %s" % _boot.screen_name()):
		return false
	return check(screen != null and screen.row_count() > 0, "the map screen drew a row")


func _enter_first_node() -> bool:
	var flow = _boot.flow()
	if not check(flow != null, "a run session is in progress"):
		return false
	var screen = _boot.map_screen()
	if not check(screen != null and screen.row_count() > 0, "the map screen has a row to take"):
		return false

	# The first selectable level node, by the map's own list, so the demo takes the
	# node a player would be offered first rather than one it chose for itself.
	var node_id := -1
	for id in flow.map().selectable_nodes():
		if flow.LEVEL_TYPES.has(String(flow.map().type_of(int(id)))):
			node_id = int(id)
			break
	if not check(node_id != -1, "the map offers a level node as the first choice"):
		return false

	var map_index := -1
	var rows: Array = screen.rows()
	for i in rows.size():
		if int(rows[i].get("id", -1)) == node_id:
			map_index = i
			break
	print("BOOT_PANEL_MAP " + JSON.stringify({
		"phase": "node",
		"node": node_id,
		"type": String(flow.map().type_of(node_id)),
		"map_index": map_index,
		"rows": rows,
	}))
	if not check(map_index != -1, "the map screen drew the level node it is offered"):
		return false

	var taken: bool = screen.activate(map_index)
	for _i in SETTLE_FRAMES:
		await process_frame

	var arena = flow.current_level()
	print("BOOT_PANEL_LEVEL " + JSON.stringify({
		"taken": taken,
		"screen": _boot.screen_name(),
		"in_level": flow.is_in_level(),
		"node": flow.level_node_id(),
		"arena": arena != null,
		"arena_name": str(arena.name) if arena != null else "",
		"phase": arena.phase_name() if arena != null else "",
		"autostart": _boot.autostart,
		"start_first_wave": _boot.start_first_wave,
	}))
	if not check(taken, "the level node can be taken"):
		return false
	if not check(_boot.screen_name() == "level", "the boot is showing the level: %s" % _boot.screen_name()):
		return false
	return check(arena != null, "the session opened the level scene")


# --- the assertions that would have caught the shipped bug ------------------

func _check_panel() -> void:
	var flow = _boot.flow()
	var arena = flow.current_level()
	var panel = _find_panel(arena)
	if not check(panel != null, "the level instantiated a build panel"):
		return

	var towers: Array = flow.inventory().towers()
	var tower_types: Array = []
	for instance in towers:
		tower_types.append(String(instance.type_id))

	var bound: bool = panel.arena() == arena
	var rows: Array = panel.rows()
	var kinds: Array = []
	for entry in rows:
		kinds.append(String(entry["kind"]))

	print("BOOT_PANEL_BIND " + JSON.stringify({
		"bound": bound,
		"arena_is_the_level": panel.arena() == arena,
		"visible": panel.visible,
		"row_count": panel.row_count(),
		"kinds": kinds,
		"tower_types": tower_types,
		"phase": panel.phase_name(),
	}))

	check(bound, "the panel is bound to the level's arena")
	check_eq_int(panel.row_count(), towers.size() + 1, "one row per loadout tower, plus Start Wave")
	check(kinds.has("start_wave"), "Start Wave is one of the rows: %s" % [kinds])
	check_eq_int(kinds.count("tower"), towers.size(), "a tower row per loadout tower: %s" % [kinds])
	var labels: Array = _labels(rows)
	for type_id in tower_types:
		var named := false
		for label in labels:
			if String(label).contains(String(type_id)):
				named = true
				break
		check(named, "a row names the loadout tower '%s': %s" % [type_id, labels])

	var lines := _lines(panel)
	print("BOOT_PANEL_LINES " + JSON.stringify(lines))

	check(String(lines["title"]) != "", "the Title line is not empty")
	check(String(lines["state"]) != "", "the State line is not empty")
	check(String(lines["wave"]) != "", "the Wave line is not empty")
	check(String(lines["hint"]) != "", "the Hint line is not empty")
	check(
		String(lines["state"]) != String(panel.no_arena_text),
		"the State line is the level's numbers, not the no-arena sentence: '%s'" % lines["state"]
	)
	check(
		String(lines["wave"]) != String(panel.no_arena_text),
		"the Wave line is the level's readout, not the no-arena sentence: '%s'" % lines["wave"]
	)
	check(
		String(lines["state"]).contains("Gold"),
		"the State line carries the run's gold: '%s'" % lines["state"]
	)
	check_eq_int(lines["rows_on_screen"], panel.row_count(), "every row is a button in the list")
	check_eq_int(lines["list_children"], panel.row_count(), "the list holds exactly the row buttons")

	# "The text exists" and "the player can see it" are two claims. The observed
	# frame showed the hint and nothing else while every row existed, so the rects
	# are printed and required to be inside the panel: a line laid out at a
	# negative y, or a zero-size panel, is invisible with correct text.
	var layout := _layout(panel)
	print("BOOT_PANEL_LAYOUT " + JSON.stringify(layout))
	check(
		float(layout["viewport"][0]) == float(VIEWPORT.x) and float(layout["viewport"][1]) == float(VIEWPORT.y),
		"the panel lays out in the window the demo asked for, not the headless dummy: asked %s, got %s"
		% [VIEWPORT, layout["viewport"]]
	)
	check(float(layout["panel"][2]) > 0.0 and float(layout["panel"][3]) > 0.0,
		"the panel itself has a size to lay its column out in: %s" % [layout["panel"]])
	for key in ["title", "state", "wave", "hint"]:
		var rect: Array = layout[key]
		check(float(rect[2]) > 0.0 and float(rect[3]) > 0.0,
			"the %s line has a drawable size: %s" % [key, rect])
		check(bool(layout["on_screen"][key]),
			"the %s line is inside the panel, where a player can see it: %s in %s"
			% [key, rect, layout["panel"]])
	check(int(layout["list_rows_visible"]) == panel.row_count(),
		"every row button is inside the panel (%d of %d): %s"
		% [layout["list_rows_visible"], panel.row_count(), layout["rows"]])


# --- reading the scene ------------------------------------------------------

## The panel the level instantiated, found by what it can do rather than by its
## node name or by being the arena's child: the demo must not be the only thing
## that knows where it lives. Since T-0062 the panel hangs under the level's
## `CanvasLayer` (so its anchors resolve against the viewport), so the search is
## over the level's whole subtree, not the arena's direct children.
func _find_panel(arena) -> Node:
	if arena == null:
		return null
	return _find_control_with(arena, "bind_arena")


func _find_control_with(node: Node, method: String) -> Node:
	if node is Control and node.has_method(method):
		return node
	for child in node.get_children():
		var found := _find_control_with(child, method)
		if found != null:
			return found
	return null


func _lines(panel) -> Dictionary:
	var node = panel.get_node_or_null(panel.title_path)
	var state = panel.get_node_or_null(panel.state_path)
	var wave = panel.get_node_or_null(panel.wave_path)
	var hint = panel.get_node_or_null(panel.hint_path)
	var list = panel.get_node_or_null(panel.tower_list_path)
	var reason = panel.get_node_or_null(panel.reason_path)
	var rows: Array = []
	if list != null:
		for child in list.get_children():
			rows.append(String(child.text) if child is Button else "%s:%s" % [child.name, child.text])
	return {
		"title": String(node.text) if node != null else "<missing>",
		"state": String(state.text) if state != null else "<missing>",
		"wave": String(wave.text) if wave != null else "<missing>",
		"hint": String(hint.text) if hint != null else "<missing>",
		"reason": String(reason.text) if reason != null else "<missing>",
		"rows_on_screen": rows.size(),
		"list_children": list.get_child_count() if list != null else -1,
		"rows": rows,
	}


## Text, position and size of the four lines and of the row list, in global
## (screen) coordinates, plus whether each one is actually inside the panel.
func _layout(panel) -> Dictionary:
	var panel_rect := _global_rect(panel)
	var out := {
		"panel": [panel_rect.position.x, panel_rect.position.y, panel_rect.size.x, panel_rect.size.y],
		"parent": String((panel as Control).get_parent().get_class()),
		"panel_min": [
			(panel as Control).get_combined_minimum_size().x,
			(panel as Control).get_combined_minimum_size().y,
		],
		"viewport": [
			(panel as Control).get_viewport_rect().size.x,
			(panel as Control).get_viewport_rect().size.y,
		],
		"on_screen": {},
		"rows": [],
	}
	var lines := {
		"title": panel.get_node_or_null(panel.title_path),
		"state": panel.get_node_or_null(panel.state_path),
		"wave": panel.get_node_or_null(panel.wave_path),
		"hint": panel.get_node_or_null(panel.hint_path),
	}
	for key in lines:
		var rect := _global_rect(lines[key])
		out[key] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		out["on_screen"][key] = _inside(panel_rect, rect)

	var visible_rows := 0
	var list = panel.get_node_or_null(panel.tower_list_path)
	if list != null:
		for child in list.get_children():
			if not child is Control:
				continue
			var rect := _global_rect(child)
			var shown := _inside(panel_rect, rect)
			if shown:
				visible_rows += 1
			out["rows"].append({
				"name": String(child.name),
				"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
				"inside": shown,
			})
	out["list_rows_visible"] = visible_rows
	return out


func _global_rect(node) -> Rect2:
	if node == null or not node is Control:
		return Rect2()
	return (node as Control).get_global_rect()


## A rect a player can see: it has area and it lies inside the panel's own rect.
## `encloses` is false for a zero-size panel, which is the shape of the bug.
func _inside(container: Rect2, rect: Rect2) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	return container.encloses(rect)


func _row_index_with_id(screen, id: String) -> int:
	var rows: Array = screen.rows()
	for i in rows.size():
		if String(rows[i].get("id", "")) == id:
			return i
	return -1


func _labels(rows: Array) -> Array:
	var out: Array = []
	for entry in rows:
		out.append(String(entry["label"]))
	return out


# --- reporting --------------------------------------------------------------

func _case(label: String) -> void:
	print("BOOT_PANEL_CASE " + label)


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
	print("BOOT_PANEL_SELF_TEST " + JSON.stringify({
		"name": "build_panel_boot_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("BOOT_PANEL_FAILURE " + f)
	quit(1)
