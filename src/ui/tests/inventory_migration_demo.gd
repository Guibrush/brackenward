extends SceneTree

## T-0068 - one inventory view, not two.
##
##     godot --headless --path . --script res://src/ui/tests/inventory_migration_demo.gd
##
## Everything here goes through the **real boot path**: the boot scene is
## instantiated, the menu, the opening choice, the map and the level are traversed
## with events pushed into the root viewport (`get_root().push_input()`), and every
## assertion is made on the panel and the bar the run itself mounted. Nothing calls
## `bind_arena()`, `activate()` or `_select()` to arrange a state.
##
## What it proves, in order:
##   1. the panel lists no tower rows and shows no gold, while the bar shows both;
##   2. a real click on a tower in the bar selects it in the panel, and (T-0074)
##      opens the tower window; Escape closes the window and both views keep the
##      selection behind it;
##   3. a real click on a placed tower in the level selects it in the bar, and
##      Escape clears the selection in both - after closing the window that same
##      click raised (T-0074);
##   4. a click on the bar does not reach the board - and, at the panel's own action
##      door, a bar-owned point is answered `guard` rather than as a board click.
##      Point 4 is the planted-failure target: with `add_pointer_guard()` removed
##      from a copy, the same call answers `tile` and the panel handles the click
##      the bar already handled;
##   5. the panel's last line sits above the bar, not under it.
##
## The same file produces the acceptance frame. With `--write-movie` on the command
## line it holds the final state for `MOVIE_HOLD_FRAMES`, so the last PNG the movie
## writer emits shows the level, the panel and the bar together:
##
##     godot --path . --write-movie <out>/panel-bar.png --fixed-fps 30 \
##         --script res://src/ui/tests/inventory_migration_demo.gd
##
## Prints:
##   PANEL_BAR_CASE {text}        one line per case
##   PANEL_BAR_EVENT {json}       every event pushed, and where it was aimed
##   PANEL_BAR_STATE {json}       what the panel and the bar each report
##   PANEL_BAR_GEOMETRY {json}    the rects the overlap case is decided on
##   PANEL_BAR_FRAME {json}       the movie is holding the frame
##   PANEL_BAR_SELF_TEST {json}   once, last; carries checks and failures
##
## The exit code is not evidence (L-035); `PANEL_BAR_SELF_TEST` is. `BOOT_*`,
## `ARENA_*`, `BUILD_PANEL_*` and `INVENTORY_BAR_*` lines around these belong to the
## objects under test.

const BOOT_SCENE := "res://scenes/boot.tscn"

## The map this demo walks - the seed `armed_feedback_demo.gd` uses, so the two
## demos talk about one run.
const SEED := 20261108

## The window the panel and the bar are laid out in. A windowed run is required for
## the acceptance frame; `--headless` gives every run the same layout but cannot
## render one.
const VIEWPORT := Vector2i(1152, 648)

const SETTLE_FRAMES := 2
const MOVIE_HOLD_FRAMES := 12

## How many pushes the map walk to a level may take, counted **after** the opening
## choice is resolved. A map that needs more than this to open a level is not the
## path a player takes - it is a stuck screen, and the demo says so. The choice is
## not counted here: it is not a number of Enter presses but one pick per group and
## a Confirm, and `_confirm_opening_choice()` drives it that way.
const MAX_WALK_PRESSES := 4

## The row kinds the panel is still allowed to draw (T-0068). Duplicated here on
## purpose: a demo that reads its expectations off the panel under test cannot catch
## the panel growing a row back.
const ALLOWED_KINDS: Array[String] = ["start_wave", "upgrade", "take_back"]

var _boot = null
var _panel = null
var _bar = null
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

	# --- 1. one inventory, in one place ------------------------------------
	_case("the panel lists no towers and no gold; the bar shows both")
	var kinds := _kinds()
	_state_evidence("level opened")
	check(not kinds.has("tower"), "the panel draws no tower row: %s" % [kinds])
	for kind in kinds:
		check(ALLOWED_KINDS.has(String(kind)), "the panel's rows are only actions: '%s' in %s" % [String(kind), kinds])
	check(kinds.has("start_wave"), "the panel still offers Start Wave: %s" % [kinds])

	var state_on_screen := _label_text(_panel.state_path)
	check(not state_on_screen.to_lower().contains("gold"),
		"the panel's state line carries no gold: '%s'" % state_on_screen)
	check(state_on_screen.to_lower().contains("hp"),
		"the panel's state line still carries HP: '%s'" % state_on_screen)
	check(_label_text(_panel.wave_path) != "", "the panel still draws the wave readout")

	var bar_state: Dictionary = _bar.state()
	check(int(bar_state["tower_count"]) >= 1, "the bar shows the towers: %d" % int(bar_state["tower_count"]))
	check(String(bar_state["gold_label"]).to_lower().contains("gold"),
		"the bar shows gold: '%s'" % String(bar_state["gold_label"]))
	var run = _flow.run_state()
	check(int(bar_state["gold"]) == int(run.gold()),
		"the bar's gold is the run's gold: %d vs %d" % [int(bar_state["gold"]), int(run.gold())])
	check(not bool(bar_state["stale"]), "the bar's view agrees with the session: stale=%s" % [bar_state["stale"]])

	var tower_rect: Rect2 = _bar.slot_rect("towers", 0)
	if not check(tower_rect.size.x > 0.0 and tower_rect.size.y > 0.0, "the bar has a tower slot with a rect to click"):
		_finish()
		return
	var picked: Dictionary = (_bar.state()["towers"] as Array)[0]
	var picked_id := int(picked["id"])

	# --- 2. bar -> panel ----------------------------------------------------
	_case("a real click on a tower in the bar selects it in the panel")
	await _click(tower_rect.get_center(), "left click on bar slot %d (%s)" % [picked_id, String(picked["type_id"])])
	_state_evidence("bar click")
	check_eq_int(int(_bar.selected_instance()), picked_id, "the bar marks the tower selected")
	check_eq_int(int(_panel.selected_instance()), picked_id, "the panel shows the same tower selected")
	check(String(_panel.reason()) == "", "the click on the bar invented no refusal in the panel: '%s'" % String(_panel.reason()))

	# T-0074: the bar's selection is also the window's door, so this click opens
	# the tower window. It is asserted (that is the new behaviour) and then closed
	# with the key a player uses, and the selection behind it is checked intact -
	# closing a view must not be a deselection.
	var window = _window()
	if check(window != null, "the run mounted a tower window"):
		check(window.is_open(), "the click on the bar opened the tower window (T-0074)")
		check_eq_int(int(window.opened_instance()), picked_id, "the window opened on the tower the bar selected")
	await _press(KEY_ESCAPE, "game_dismiss (Escape): close the tower window")
	_state_evidence("tower window closed")
	check(not _window_open(window), "Escape closed the tower window")
	check_eq_int(int(_bar.selected_instance()), picked_id, "closing the window left the bar's selection alone")
	check_eq_int(int(_panel.selected_instance()), picked_id, "closing the window left the panel's selection alone")

	# --- 3. the board did not hear it --------------------------------------
	_case("the click on the bar did not reach the board")
	var free_before: int = _arena.free_slot_count()
	var refusals_before: int = _arena.refused_count()
	await _click(tower_rect.get_center() + Vector2(0, -6), "left click on the bar, near the same slot")
	check_eq_int(int(_arena.free_slot_count()), free_before, "the board kept its free tiles")
	check_eq_int(int(_arena.refused_count()), refusals_before, "the arena was never asked about a bar click")
	check(String(_panel.reason()) == "", "the panel did not answer the bar's click: '%s'" % String(_panel.reason()))

	# The same real event, handed to the panel's own door. This is where the guard
	# is load-bearing: `_input()` may be reached before or after the bar's, and this
	# is the panel's decision either way. A planted copy without the guard answers
	# `tile` here - one click, handled twice.
	var door_point: Vector2 = tower_rect.get_center()
	var outcome: Dictionary = _panel.handle_input(_mouse_press(door_point))
	_state_evidence("guard at the panel door")
	check(String(outcome.get("target", "")) == "guard",
		"the panel reports the bar as the owner of its point: %s" % [outcome])
	check(not bool(outcome.get("applied", false)), "the panel applied nothing for a bar-owned point: %s" % [outcome])
	check_eq_int(int(_arena.free_slot_count()), free_before, "still no board action from a bar-owned point")
	check(String(_panel.reason()) == "", "still no refusal sentence from a bar-owned point: '%s'" % String(_panel.reason()))

	# That click is a bar selection too, so it re-opened the window. Closed here so
	# the board click below is the panel's to answer.
	await _close_window("close the window the second bar click opened")

	# --- 4. panel -> bar ---------------------------------------------------
	_case("a real click on a build tile places the armed tower and the bar follows the selection")
	var slot := _free_slot()
	if not check(not slot.is_empty(), "the level has a free build tile"):
		_finish()
		return
	# The panel drops confirms during its settle window (T-0071) - a click that
	# predates the level belongs to the screen that was up then. A headless demo
	# fires its clicks far faster than a player, so it waits the window out rather
	# than hoping the frame budget outlasts it; no click is skipped or faked.
	await _wait_for_settle("before the first board click")
	await _click(_canvas_point(slot["position"]), "left click on tile %s" % String(slot["name"]))
	_state_evidence("placed")
	var placed_item := _bar_tower(picked_id)
	check(bool(placed_item.get("placed", false)),
		"the tower the click placed is marked placed in the bar: %s" % [placed_item])
	check(_arena_has_tower(picked_id), "the board holds a tower for that instance: %d" % picked_id)
	check_eq_int(int(_panel.selected_instance()), picked_id, "the panel selected the tower it placed")
	check_eq_int(int(_bar.selected_instance()), picked_id, "the bar shows the placed tower selected")

	_case("a real click on the placed tower in the level selects it in the bar")
	await _press(KEY_ESCAPE, "game_dismiss (Escape): drop the selection")
	_state_evidence("after Escape")
	check_eq_int(int(_panel.selected_instance()), -1, "Escape cleared the panel's selection")
	check_eq_int(int(_bar.selected_instance()), -1, "Escape cleared the bar's selection too")

	var placed_point := _canvas_point(slot["position"])
	await _wait_for_settle("before the placed-tower click")
	await _click(placed_point, "left click on the placed tower at %s" % String(slot["name"]))
	_state_evidence("placed tower clicked")
	# T-0074: selecting a placed tower raises `tower_inspected`, and the boot opens
	# the window on it. That is what this click now means; the selection is asserted
	# after the window is closed, because the window owns the keyboard while it is up.
	var placed_window = _window()
	if check(placed_window != null, "the run mounted a tower window"):
		check(placed_window.is_open(), "the click on the placed tower opened the tower window (T-0074)")
		check_eq_int(int(placed_window.opened_instance()), picked_id,
			"the window opened on the tower standing there")
	await _press(KEY_ESCAPE, "game_dismiss (Escape): close the tower window")
	_state_evidence("placed tower window closed")
	check(not _window_open(placed_window), "Escape closed the placed tower's window")
	check_eq_int(int(_panel.selected_instance()), picked_id, "the panel selected the tower standing there")
	check_eq_int(int(_bar.selected_instance()), picked_id, "the bar was told by the panel, not by a click on itself")
	check(not _kinds().has("tower"), "the selection still draws no tower row in the panel: %s" % [_kinds()])

	# --- 5. no overlap -----------------------------------------------------
	_case("the panel's content stops above the bar")
	var geometry := _geometry()
	print("PANEL_BAR_GEOMETRY " + JSON.stringify(geometry))
	var hint_rect: Rect2 = geometry["hint"]
	var bar_rect: Rect2 = geometry["bar"]
	var column_rect: Rect2 = geometry["column"]
	check(bar_rect.size.y > 0.0, "the bar has a height to clear: %s" % [bar_rect])
	check(hint_rect.end.y <= bar_rect.position.y,
		"the panel's hint line ends above the bar's top edge: hint %.1f <= bar %.1f"
		% [hint_rect.end.y, bar_rect.position.y])
	check(not hint_rect.intersects(bar_rect), "the hint line's rect does not intersect the bar's")
	check(column_rect.end.y <= bar_rect.position.y,
		"the panel's whole column stops above the bar: column %.1f <= bar %.1f"
		% [column_rect.end.y, bar_rect.position.y])
	check(int(_panel.content_reserve()) == int(bar_rect.size.y) + int(_panel.bar_gap),
		"the reserve is the bar's measured height plus the gap: %d vs %d + %d"
		% [int(_panel.content_reserve()), int(bar_rect.size.y), int(_panel.bar_gap)])

	# --- the frame the human judges ----------------------------------------
	if _is_movie():
		_case("the frame is held for the movie writer")
		print("PANEL_BAR_FRAME " + JSON.stringify({
			"viewport": [root.size.x, root.size.y],
			"bar": _rect_json(bar_rect),
			"hint": _rect_json(hint_rect),
			"screen": _boot.screen_name(),
			"hold_frames": MOVIE_HOLD_FRAMES,
		}))
		await _hold(MOVIE_HOLD_FRAMES)

	_finish()


# --- the path a player takes ------------------------------------------------

func _walk_to_level() -> bool:
	if not check(_boot.screen_name() == "menu", "the boot opens on the menu: %s" % _boot.screen_name()):
		return false

	await _press(KEY_ENTER, "game_confirm (Enter) on the menu: start the run")
	# The map is up but inert: the opening choice is in front of it and holds the
	# run until every group has a pick. Pressing Enter at it only re-picks the row
	# that already has focus, which is why the choice is driven row by row here.
	if not await _confirm_opening_choice():
		return false

	var presses := 0
	while _boot.screen_name() != "level" and presses < MAX_WALK_PRESSES:
		presses += 1
		await _press(KEY_ENTER, "game_confirm (Enter), screen '%s', modal=%s"
			% [_boot.screen_name(), str(_boot.opening_modal() != null)])
	if not check(_boot.screen_name() == "level",
		"real input walked menu -> choice -> map -> level, in %d map press(es) after the choice: %s"
		% [presses, _boot.screen_name()]):
		return false

	_flow = _boot.flow()
	_arena = _flow.current_level() if _flow != null else null
	if not check(_arena != null, "the session opened the level scene"):
		return false
	_panel = _find_with(_arena, "bind_arena")
	_bar = _boot.inventory_bar()
	if not check(_panel != null and _panel.visible, "the level instanced a visible build panel"):
		return false
	if not check(_bar != null and _bar.visible, "the run's inventory bar is mounted and visible"):
		return false
	return check(_bar.flow() == _flow, "the bar is bound to this run's session")


## The opening choice, driven the way a player drives it: a click on one option row
## in every group, then a click on Confirm. The modal is the real control tree the
## boot mounted, so these are the clicks a mouse delivers; nothing here calls
## `choose()` or `confirm()` to arrange a state. The map behind it answers nothing
## until the last click lands, which is the point of walking it at all.
func _confirm_opening_choice() -> bool:
	var modal = _boot.opening_modal()
	if not check(modal != null and modal.is_open(),
		"the opening choice is up between the menu and the map: %s" % [modal]):
		return false
	var groups: Array = modal.config().get("groups", [])
	if not check(not groups.is_empty(), "the opening choice asks for something: %s" % [groups]):
		return false

	for group in groups:
		var gid := String((group as Dictionary)["id"])
		var index := _row_index(modal, gid, "")
		if not check(index >= 0, "the choice draws a row for group '%s': %s" % [gid, modal.rows()]):
			return false
		var rect := _row_rect(modal, index)
		if not check(rect.size.x > 0.0 and rect.size.y > 0.0,
			"the '%s' row has a rect to click: %s" % [gid, rect]):
			return false
		await _click(rect.get_center(), "left click on the '%s' row (row %d)" % [gid, index])

	if not check((modal.unmet_groups() as Array).is_empty(),
		"every group holds a pick after the clicks: unmet %s" % [modal.unmet_groups()]):
		return false

	var confirm_index := _row_index(modal, "", "confirm")
	if not check(confirm_index >= 0, "the choice draws a Confirm row: %s" % [modal.rows()]):
		return false
	var confirm_rect := _row_rect(modal, confirm_index)
	if not check(confirm_rect.size.x > 0.0 and confirm_rect.size.y > 0.0,
		"the Confirm row has a rect to click: %s" % [confirm_rect]):
		return false
	await _click(confirm_rect.get_center(), "left click on Confirm (row %d)" % confirm_index)

	if not check(_boot.opening_modal() == null, "Confirm released the opening choice"):
		return false
	return check(_boot.screen_name() == "map",
		"the choice is made over the map, not instead of it: %s" % _boot.screen_name())


## The index of the first row of `group_id` (or of `kind`, when `group_id` is ""),
## read from the modal's own row list. -1 for a row the choice does not draw.
func _row_index(modal, group_id: String, kind: String) -> int:
	for entry in modal.rows():
		var row: Dictionary = entry
		if group_id != "" and String(row["group"]) != group_id:
			continue
		if kind != "" and String(row["kind"]) != kind:
			continue
		return int(row["idx"])
	return -1


## The rect of the button the modal drew for row `index`, read off the node it
## built: the click goes to the real control, and no layout is assumed here.
func _row_rect(modal, index: int) -> Rect2:
	var list = modal.get_node_or_null(modal.rows_path)
	if list == null:
		return Rect2()
	var button = list.get_node_or_null("Row%d" % index)
	if button is Control:
		return (button as Control).get_global_rect()
	return Rect2()


# --- pushing events the way the OS does ------------------------------------

func _press(keycode: int, what: String) -> void:
	print("PANEL_BAR_EVENT " + JSON.stringify({"device": "key", "key": OS.get_keycode_string(keycode), "what": what}))
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
	print("PANEL_BAR_EVENT " + JSON.stringify({
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


## The same left press a click produces, not pushed: handed to the panel's door so a
## demo can ask "what would you do with this point". The event is real; only its
## delivery is direct, and the case that uses it says so.
func _mouse_press(point: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.device = -1
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = point
	ev.global_position = point
	return ev


func _settle(frames: int = SETTLE_FRAMES) -> void:
	await _hold(frames)


## Waits out the build panel's settle window (T-0071), which drops a confirm that
## arrives while the panel has just appeared. That window is wall-clock; a headless
## demo's frames are much faster than a player's, so a demo that wants a board click
## to land has to wait for it explicitly. It is not a fake input: the same click is
## delivered after, through `push_input`.
func _wait_for_settle(what: String) -> void:
	if _panel == null or not _panel.has_method("settle_left_msec"):
		return
	var left := int(_panel.settle_left_msec())
	if left <= 0:
		return
	print("PANEL_BAR_EVENT " + JSON.stringify({"device": "wait", "what": what, "settle_ms": left}))
	await create_timer(float(left) / 1000.0 + 0.05).timeout
	await _settle()


# --- the tower window (T-0074) ----------------------------------------------

## The run's tower window, found by what it can do (`open_for`) rather than by a
## node path: the boot owns where it lives, and this file must not be a second one
## that knows.
func _window():
	return _find_with(_boot, "open_for")


## True while `window` is valid and open. A null ref is closed, not an error.
func _window_open(window) -> bool:
	return window != null and is_instance_valid(window) and window.is_open()


## Closes the tower window with Escape - the key a player uses - and checks it
## closed. A window that is already shut is a no-op, so this is safe to call after
## any step whose click may or may not have opened one.
func _close_window(what: String) -> void:
	var window = _window()
	if not _window_open(window):
		return
	await _press(KEY_ESCAPE, "game_dismiss (Escape): %s" % what)
	check(not _window_open(window), "%s: Escape closed it" % what)


## One tower as the bar draws it, by inventory id; {} when it is not listed.
func _bar_tower(instance_id: int) -> Dictionary:
	for raw in _bar.state().get("towers", []):
		if int((raw as Dictionary).get("id", -1)) == instance_id:
			return raw
	return {}


## True when the level holds a tower node for `instance_id`. The board's own
## answer, so "placed" in the bar is checked against the scene, not against itself.
func _arena_has_tower(instance_id: int) -> bool:
	if not _arena.has_method("tower_for_instance"):
		return false
	return _arena.tower_for_instance(instance_id) != null


func _hold(frames: int) -> void:
	for _i in frames:
		await process_frame


func _is_movie() -> bool:
	for arg in OS.get_cmdline_args():
		if String(arg).begins_with("--write-movie"):
			return true
	return false


# --- reading what the player sees ------------------------------------------

func _find_with(node, method: String) -> Node:
	if node is Control and node.has_method(method):
		return node
	for child in node.get_children():
		var found := _find_with(child, method)
		if found != null:
			return found
	return null


func _kinds() -> Array:
	var out: Array = []
	for entry in _panel.rows():
		out.append(String(entry["kind"]))
	return out


func _label_text(path: NodePath) -> String:
	var node = _panel.get_node_or_null(path)
	if node == null or not node is Label:
		return "<missing>"
	return String((node as Label).text)


func _geometry() -> Dictionary:
	var margin = _panel.get_node_or_null(_panel.margin_path)
	var column = null
	var hint = _panel.get_node_or_null(_panel.hint_path)
	if margin != null:
		column = margin.get_node_or_null("Column")
	return {
		"bar": _bar.get_global_rect(),
		"panel": _panel.get_global_rect(),
		"column": (column as Control).get_global_rect() if column is Control else Rect2(),
		"hint": (hint as Control).get_global_rect() if hint is Control else Rect2(),
		"reserve": int(_panel.content_reserve()),
	}


func _rect_json(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


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
	print("PANEL_BAR_CASE " + label)


func _state_evidence(label: String) -> void:
	if _panel == null or _bar == null:
		return
	print("PANEL_BAR_STATE " + JSON.stringify({
		"case": label,
		"panel": {
			"kinds": _kinds(),
			"state": _label_text(_panel.state_path),
			"wave": _label_text(_panel.wave_path),
			"status": _label_text(_panel.status_path),
			"selected": int(_panel.selected_instance()),
			"armed": int(_panel.armed_instance()),
			"reason": String(_panel.reason()),
		},
		"bar": {
			"selected": int(_bar.selected_instance()),
			"gold": String(_bar.state()["gold_label"]),
			"tower_count": int(_bar.state()["tower_count"]),
			"upgrade_count": int(_bar.state()["upgrade_count"]),
			"stale": bool(_bar.state()["stale"]),
		},
	}))


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
	print("PANEL_BAR_SELF_TEST " + JSON.stringify({
		"name": "inventory_migration_demo",
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
		push_error("PANEL_BAR_FAILURE " + f)
	quit(1)
