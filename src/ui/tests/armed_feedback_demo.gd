extends SceneTree

## T-0064 DoD 2 - "armed" is **visible**, not merely set.
##
##     godot --headless --path . --script res://src/ui/tests/armed_feedback_demo.gd
##
## T-0063 proved that a click on a row arms it. The human still said "clicking did
## nothing", because the only feedback was a text suffix. So this demo does not
## assert on the panel's fields: it asserts on what the player's eye gets -
##   * the armed row's **band** (background and border) differs from every other
##     row's, and so does its **text colour**;
##   * the armed row carries a **marker** that is not colour;
##   * the **status line** on screen names the next action.
## A demo that only read `armed_instance()` would have passed the shipped bug.
##
## Every event is pushed into the root viewport (`get_root().push_input()`), the
## same entry point the OS uses, and every assertion is made after the event has
## travelled menu -> Start Game -> map -> first node -> the level the session
## opened -> the panel that level instanced for itself. No check calls
## `handle_input()`, `activate()` or `bind_arena()`.
##
## The same file produces the acceptance frame. With `--write-movie` on the command
## line it holds the armed state for `MOVIE_HOLD_FRAMES` before quitting, so the
## last PNG the movie writer emits is the frame the human judges:
##
##     godot --path . --write-movie <out>/armed.png --fixed-fps 30 \
##         --script res://src/ui/tests/armed_feedback_demo.gd
##
## Prints, in this order:
##   ARMED_FEEDBACK_CASE {text}       one line per case
##   ARMED_FEEDBACK_CUE {json}        every row as drawn: band, border, colour,
##                                    text - the evidence, not a summary of it
##   ARMED_FEEDBACK_STATUS {json}     the status line, as drawn, and what it says
##   ARMED_FEEDBACK_FRAME {json}      the movie is holding the armed frame
##   ARMED_FEEDBACK_SELF_TEST {json}  once, last; carries checks and failures
##
## The exit code is not evidence (L-035); `ARMED_FEEDBACK_SELF_TEST` is. `BOOT_*`,
## `MENU_*`, `RUNFLOW_*`, `ARENA_*` and `BUILD_PANEL_*` lines around these belong
## to the objects under test, not to this file.

const BOOT_SCENE := "res://scenes/boot.tscn"

## The map this demo walks, the same seed both panel demos already use, so all
## three talk about one run.
const SEED := 20261108

## The window the panel is laid out in; `--headless` gives every run a 64x64
## viewport whatever the project says (measured T-0062).
const VIEWPORT := Vector2i(1152, 648)

const SETTLE_FRAMES := 2

## Frames the armed state is held for under `--write-movie`. Ten is more than the
## movie writer needs to flush a frame at any fps the project uses, and short
## enough that the run is over in under a second.
const MOVIE_HOLD_FRAMES := 12

## Words the status line must carry for each state: the state itself, and the
## action the player has left to take. Duplicated here on purpose - a demo that
## reads its expectations off the panel under test cannot catch the panel
## renaming them.
const STATUS_ARMED_WORDS: Array[String] = ["armed", "click a build tile"]
const STATUS_SELECTED_WORDS: Array[String] = ["selected", "actions"]

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

	_case("the demo walks the boot to a level, the way a player does")
	if not await _walk_to_level():
		_finish()
		return

	# --- 1. idle: nothing is dressed ----------------------------------------
	_case("nothing armed, nothing selected: no row is dressed and the prompt is quiet")
	var dressed := _dressed_indices()
	check(dressed.is_empty(), "no row carries a cue before any click: %s" % [dressed])
	var idle_status := _status_on_screen()
	check(idle_status == String(_panel.status_idle_text), "the prompt is quiet while idle: '%s'" % idle_status)
	_cue_evidence("idle")

	# --- 2. a real click on the tower row arms it, visibly -------------------
	_case("a real left click on the arrow row makes one row unmistakable")
	var tower_row := _row_of_kind("tower")
	if not check(not tower_row.is_empty(), "the panel has a tower row to click"):
		_finish()
		return
	var row_index := int(tower_row["index"])
	var wanted_id := int(tower_row["id"])
	var point: Vector2 = (tower_row["node"] as Control).get_global_rect().get_center()
	await _click(point, "left click on row %d (%s)" % [row_index, String(tower_row["type_id"])])

	check_eq_int(_panel.armed_instance(), wanted_id, "the click armed instance %d" % wanted_id)
	check(_differs_from_every_other_row(row_index), "the armed row is visually distinguishable: its band "
		+ "and text colour differ from every other row's (%s)" % [_cue(row_index)])
	check(String(_cue(row_index)["bg"]) != "none", "the armed row's band has a fill: %s" % [_cue(row_index)])
	check(String(_cue(row_index)["border"]) != "none", "the armed row's band has a border: %s" % [_cue(row_index)])
	var armed_text := String(_cue(row_index)["text"])
	check(armed_text.contains(String(_panel.armed_marker)),
		"the armed row's text says it is armed: '%s'" % armed_text)
	check(armed_text.contains(String(_panel.armed_prefix)),
		"the armed row carries a marker that is not colour: '%s'" % armed_text)

	var status := _status_on_screen()
	print("ARMED_FEEDBACK_STATUS " + JSON.stringify({
		"case": "armed",
		"on_screen": status,
		"reported": String(_panel.status()["label"]),
		"armed": _panel.armed_instance(),
		"status_node": _panel.get_node_or_null(_panel.status_path) != null,
	}))
	check(_panel.get_node_or_null(_panel.status_path) != null,
		"the status line has a node to draw into: %s" % String(_panel.status_path))
	check(status == String(_panel.status()["label"]), "the status line on screen is the one the panel reports")
	for word in STATUS_ARMED_WORDS:
		check(status.contains(word), "the status line names the next action ('%s'): '%s'" % [word, status])
	check(status.contains(String(tower_row["type_id"])), "the status line names the armed tower: '%s'" % status)
	_cue_evidence("armed")

	# --- the frame the human judges ----------------------------------------
	if _is_movie():
		_case("the armed frame is held for the movie writer")
		print("ARMED_FEEDBACK_FRAME " + JSON.stringify({
			"armed": _panel.armed_instance(),
			"row": row_index,
			"status": status,
			"viewport": [root.size.x, root.size.y],
			"hold_frames": MOVIE_HOLD_FRAMES,
		}))
		await _hold(MOVIE_HOLD_FRAMES)
		_finish()
		return

	# --- 3. placing it hands the screen to the selection -------------------
	_case("a real click on a build tile places it and shows whose actions are on screen")
	var slot := _free_slot()
	if not check(not slot.is_empty(), "the level has a free build tile"):
		_finish()
		return
	await _click(_canvas_point(slot["position"]), "left click on tile %s" % String(slot["name"]))
	check_eq_int(_panel.armed_instance(), -1, "placing disarms: the tower is on the board now")
	check_eq_int(_panel.selected_instance(), wanted_id, "the placed tower is selected")

	var placed_row := _row_of_instance(wanted_id)
	if not check(not placed_row.is_empty(), "the placed tower still has its row"):
		_finish()
		return
	var placed_index := int(placed_row["index"])
	check(_differs_from_idle_rows(placed_index), "the selected tower's row is visually distinguishable "
		+ "from the rows that are not part of the selection: %s" % [_cue(placed_index)])
	check(not _dressed_indices().is_empty(), "something is dressed while a tower is selected: %s" % [_dressed_indices()])

	status = _status_on_screen()
	print("ARMED_FEEDBACK_STATUS " + JSON.stringify({
		"case": "selected",
		"on_screen": status,
		"reported": String(_panel.status()["label"]),
		"selected": _panel.selected_instance(),
		"kinds": _kinds(),
	}))
	for word in STATUS_SELECTED_WORDS:
		check(status.contains(word), "the status line names the selected tower's actions ('%s'): '%s'" % [word, status])
	_cue_evidence("selected")

	# --- 4. the cue is not sticky ------------------------------------------
	_case("Escape clears the cue, so a click that changed nothing cannot look like one that did")
	await _press(KEY_ESCAPE, "game_dismiss (Escape)")
	check_eq_int(_panel.selected_instance(), -1, "Escape closed the selection")
	check(_dressed_indices().is_empty(), "no row is dressed after Escape: %s" % [_dressed_indices()])
	check(_status_on_screen() == String(_panel.status_idle_text), "the prompt is quiet again: '%s'" % [_status_on_screen()])

	_finish()


# --- the path a player takes ------------------------------------------------

func _walk_to_level() -> bool:
	if not check(_boot.screen_name() == "menu", "the boot opens on the menu: %s" % _boot.screen_name()):
		return false
	await _press(KEY_ENTER, "game_confirm (Enter), menu row %d" % _boot.menu().focus_index())
	if not check(_boot.screen_name() == "map", "Enter on the menu opened the map: %s" % _boot.screen_name()):
		return false
	_flow = _boot.flow()

	var screen = _boot.map_screen()
	if not check(screen != null and screen.row_count() > 0, "the map screen has a row to take"):
		return false
	if not check(_first_level_node() != -1, "the map offers a level node as its first choice"):
		return false
	await _press(KEY_ENTER, "game_confirm (Enter), map row %d" % screen.focus_index())
	await _settle()
	if not check(_boot.screen_name() == "level", "Enter on the map opened the level: %s" % _boot.screen_name()):
		return false

	_arena = _flow.current_level()
	if not check(_arena != null, "the session opened the level scene"):
		return false
	_panel = _find_panel(_arena)
	if not check(_panel != null and _panel.visible, "the level instanced a visible build panel"):
		return false
	return check(_panel.row_count() >= 2, "the panel drew Start Wave and the loadout's towers: %d rows" % _panel.row_count())


func _first_level_node() -> int:
	for id in _flow.map().selectable_nodes():
		if _flow.LEVEL_TYPES.has(String(_flow.map().type_of(int(id)))):
			return int(id)
	return -1


# --- pushing events the way the OS does ------------------------------------

func _press(keycode: int, what: String) -> void:
	print("ARMED_FEEDBACK_EVENT " + JSON.stringify({"device": "key", "key": OS.get_keycode_string(keycode), "what": what}))
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
	print("ARMED_FEEDBACK_EVENT " + JSON.stringify({
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


func _settle(frames: int = SETTLE_FRAMES) -> void:
	await _hold(frames)


func _hold(frames: int) -> void:
	for _i in frames:
		await process_frame


## True when the engine was started in Movie Maker mode. Read from the command
## line rather than from an exported flag, so the same file is the demo and the
## frame without a second mode to keep in step.
func _is_movie() -> bool:
	for arg in OS.get_cmdline_args():
		if String(arg).begins_with("--write-movie"):
			return true
	return false


# --- reading what the player sees ------------------------------------------

## The panel the level instanced, found by what it can do rather than by its node
## name: the demo must not be the only thing that knows where it lives (same
## search as `build_panel_boot_demo.gd`).
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


## One row exactly as it is drawn: the band's fill and border, the text colour and
## the text itself. This is the thing the human's eye gets, read off the nodes -
## not the entry dictionary, which says what the row *means* rather than what it
## looks like.
func _cue(index: int) -> Dictionary:
	var entry: Dictionary = _panel.row(index)
	var node = entry.get("node", null)
	var out := {"index": index, "kind": String(entry.get("kind", "")), "bg": "none", "border": "none", "font": "none", "text": ""}
	if node == null or not node is Control:
		return out
	var box = (node as Control).get_theme_stylebox("panel")
	if box is StyleBoxFlat:
		out["bg"] = (box as StyleBoxFlat).bg_color.to_html(false)
		out["border"] = (box as StyleBoxFlat).border_color.to_html(false)
	var label := _label_in(node)
	if label != null:
		out["text"] = String(label.text)
		out["font"] = label.get_theme_color("font_color").to_html(false)
	return out


func _label_in(node) -> Label:
	if node is Label:
		return node as Label
	for child in node.get_children():
		var found := _label_in(child)
		if found != null:
			return found
	return null


## True when the row at `index` differs from **every** other row in both the band
## it draws and the colour of its text. Both, deliberately: a fill alone can be
## missed by a colourblind eye, and a colour alone is not a band.
func _differs_from_every_other_row(index: int) -> bool:
	var mine := _cue(index)
	if String(mine["bg"]) == "none" and String(mine["font"]) == "none":
		return false
	for i in _panel.row_count():
		if i == index:
			continue
		var other := _cue(i)
		if String(other["bg"]) == String(mine["bg"]):
			return false
		if String(other["font"]) == String(mine["font"]):
			return false
	return true


## True when the row at `index` differs from the rows that are neither armed nor
## part of the selection - the comparison a selection cue has to win.
func _differs_from_idle_rows(index: int) -> bool:
	var mine := _cue(index)
	var compared := 0
	for i in _panel.row_count():
		if i == index:
			continue
		var entry: Dictionary = _panel.row(i)
		if bool(entry.get("armed", false)) or bool(entry.get("selected", false)):
			continue
		compared += 1
		var other := _cue(i)
		if String(other["bg"]) == String(mine["bg"]) and String(other["font"]) == String(mine["font"]):
			return false
	return compared > 0 and String(mine["bg"]) != "none"


## The indices of the rows that carry a cue: a band that is not empty.
func _dressed_indices() -> Array:
	var out: Array = []
	for i in _panel.row_count():
		if String(_cue(i)["bg"]) != "none":
			out.append(i)
	return out


func _status_on_screen() -> String:
	var label = _panel.get_node_or_null(_panel.status_path)
	if label == null:
		return "<missing>"
	return String((label as Label).text)


func _kinds() -> Array:
	var out: Array = []
	for entry in _panel.rows():
		out.append(String(entry["kind"]))
	return out


func _row_of_kind(kind: String) -> Dictionary:
	for entry in _panel.rows():
		if String(entry["kind"]) == kind and not bool(entry["placed"]):
			return entry
	for entry in _panel.rows():
		if String(entry["kind"]) == kind:
			return entry
	return {}


func _row_of_instance(instance_id: int) -> Dictionary:
	for entry in _panel.rows():
		if String(entry["kind"]) == "tower" and int(entry["id"]) == instance_id:
			return entry
	return {}


func _free_slot() -> Dictionary:
	for slot in _arena.build_slots():
		if bool(slot["free"]):
			return slot
	return {}


## A world point on the board as a viewport point, read from the arena's own
## transform rather than assumed: the level may be drawn through a camera.
func _canvas_point(world: Vector2) -> Vector2:
	return (_arena as CanvasItem).get_global_transform_with_canvas() * world


# --- reporting --------------------------------------------------------------

func _case(label: String) -> void:
	print("ARMED_FEEDBACK_CASE " + label)


## Every row as drawn, printed where it matters rather than only at the end: a
## demo that fails on row 3 must still show the reader what row 3 looked like.
func _cue_evidence(label: String) -> void:
	if _panel == null:
		return
	var rows: Array = []
	for i in _panel.row_count():
		rows.append(_cue(i))
	print("ARMED_FEEDBACK_CUE " + JSON.stringify({"case": label, "rows": rows}))


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

	_cue_evidence("final")
	var passed := _failures.is_empty()
	print("ARMED_FEEDBACK_SELF_TEST " + JSON.stringify({
		"name": "armed_feedback_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
		"movie": _is_movie(),
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("ARMED_FEEDBACK_FAILURE " + f)
	quit(1)
