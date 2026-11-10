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
##   5. (T-0078) the drag gesture: a press on a tower **in hand** starts a drag whose
##      ghost is a drawn, visible node centred under the pointer and carrying the
##      tower's type and tier; a release 200 px onto the board raises
##      `tower_dropped` **once** with that id and that point; a release inside the
##      bar - with or without passing `drag_threshold_px` - raises nothing and leaves
##      the selection standing; a **placed** tower's slot starts no drag; and
##      `set_wave_locked(true)` suppresses the drag until it is turned off. The boot
##      wires the bar's release to the panel (T-0080), so the drop is refused by the
##      arena when it lands on bare ground; and the click-then-tile path still places
##      afterwards;
##   6. (T-0079) the panel is the drop's receiving end, wired by the boot (T-0080) and
##      reached by a real release with nothing here calling the receiver: the tower
##      stands on the free tile nearest the point the bar raised (checked against the
##      arena's own slot list), the bar's slot is drawn placed with the placed border,
##      gold is unchanged, the panel selects what it placed, the drag announcement
##      closes the window the press opened, a second drop and a drop released over the
##      bar are both refused without the arena being asked, and the panel's own
##      take-back returns the tower so the cases below run as they did;
##   7. the panel's last line sits above the bar, not under it.
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
##   PANEL_BAR_DRAG {json}        the live drag and the ghost, mid-gesture
##   PANEL_BAR_DROP {json}        every tower_dropped the bar raised, with its point
##   PANEL_BAR_REFUSED {json}     the bare-ground release the arena refused, and what
##                                the panel and the bar show afterwards
##   PANEL_BAR_GEOMETRY {json}    the rects the overlap case is decided on
##   PANEL_BAR_FRAME {json}       the movie is holding the frame
##   PANEL_BAR_SELF_TEST {json}   once, last; carries checks and failures
##
## The exit code is not evidence (L-035); `PANEL_BAR_SELF_TEST` is. `BOOT_*`,
## `ARENA_*`, `BUILD_PANEL_*`, `TOWER_WINDOW_*` and `INVENTORY_BAR_*` lines around
## these belong to the objects under test.

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

## Where the receiver case (T-0079) lets the tower go, relative to the tile the level
## calls `TowerSlot`: 6 px right and 5 px down from its centre. Off the centre so
## "the nearest free tile" is an answer the arena has to compute - a release on the
## centre would place on the tile whether or not it snapped at all - and inside the
## tile's 24 px snap radius by a wide margin.
const DROP_OFFSET := Vector2(6, 5)

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

## What the block must say (T-0081), duplicated here on purpose for the same reason:
## a demo that reads its expectations off the panel under test agrees with the panel
## it is supposed to catch. The first level of `SEED` opens on `HQ 10/10`, wave 1 of
## 6, and nothing has started a wave here.
const EXPECTED_COLUMN: Array[String] = ["State", "Wave", "Actions"]
const EXPECTED_STATE_TEXT := "HQ 10/10"
const EXPECTED_WAVE_TEXT := "Wave 1/6"
const EXPECTED_START_WAVE_TEXT := "Start Wave"

var _boot = null
var _panel = null
var _bar = null
var _arena = null
var _flow = null

var _checks: int = 0
var _failures: Array[String] = []

## Every `tower_dropped` the bar raised, in order: `{id, point}`. Recorded from the
## signal itself, so the count the demo asserts is the count the bar emitted.
var _drops: Array = []
## Every `tower_drag_started` the bar raised, in order: the instance ids. Same rule:
## recorded from the signal, not from the bar's own state.
var _starts: Array = []
var _signals_connected: bool = false
## Where the demo last put the mouse, so a motion event carries a real `relative`.
var _pointer: Vector2 = Vector2.ZERO


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

	# The label the player reads, resolved through the path this file ships, against
	# the number the panel reports (T-0077, applying L-041). Reading `state()` alone
	# is what let the block render `HQ 0/0` for a release: the dictionary was live
	# and the Label under it was never written.
	var live_state: Dictionary = _panel.state()
	var live_wave: Dictionary = _panel.wave()
	var state_on_screen := _label_text(_panel.state_path)
	check(state_on_screen == String(live_state["label"]),
		"the panel's state label shows the live HQ value: '%s' != '%s'"
		% [state_on_screen, String(live_state["label"])])
	check(not state_on_screen.to_lower().contains("gold"),
		"the panel's state line carries no gold: '%s'" % state_on_screen)
	# "HQ", not the pre-T-0076 "HP": this assertion was stale and is corrected to
	# what ships rather than the other way round.
	check(state_on_screen.to_lower().contains("hq"),
		"the panel's state line still carries HQ: '%s'" % state_on_screen)

	var wave_on_screen := _label_text(_panel.wave_path)
	check(wave_on_screen == String(live_wave["label"]),
		"the panel's wave label shows the live readout: '%s' != '%s'"
		% [wave_on_screen, String(live_wave["label"])])
	check(wave_on_screen != "", "the panel still draws the wave readout")

	# All three exported copy paths resolve to the node the scene actually has. The
	# restructure that broke the block updated one of eight paths and nothing noticed
	# (L-041), so this is the assertion that fails when it happens again.
	_check_copy_paths()

	# --- 1a. the block is three elements (T-0081) ---------------------------
	# The human asked for the numbers back: the HQ, the wave and Start Wave, and no
	# title, phase, enemies-left, status line, refusal sentence or hint. These are
	# read off the nodes the player sees, not off the panel's dictionaries (L-041).
	_case("the block is exactly three elements: HQ, wave, Start Wave")
	var column_children := _column_children()
	check(column_children.size() == 3,
		"the block's column has exactly three children: %s" % [column_children])
	check(column_children == EXPECTED_COLUMN,
		"the column is State, Wave, Actions and nothing else: %s" % [column_children])
	check(state_on_screen == EXPECTED_STATE_TEXT,
		"the state line is exactly '%s': '%s'" % [EXPECTED_STATE_TEXT, state_on_screen])
	check(wave_on_screen == EXPECTED_WAVE_TEXT,
		"the wave line is exactly '%s': '%s'" % [EXPECTED_WAVE_TEXT, wave_on_screen])
	check(not wave_on_screen.to_lower().contains("phase"),
		"the wave line carries no phase: '%s'" % wave_on_screen)
	check(not wave_on_screen.to_lower().contains("enemies"),
		"the wave line carries no enemies-left count: '%s'" % wave_on_screen)
	check(not wave_on_screen.to_lower().contains("cleared"),
		"the wave line carries no 'every wave cleared': '%s'" % wave_on_screen)
	check(_row_count_drawn() == 1,
		"the action list holds one row: %d" % _row_count_drawn())
	var start_wave_drawn := _row_text(0)
	check(start_wave_drawn == EXPECTED_START_WAVE_TEXT,
		"the Start Wave row's label is exactly '%s': '%s'"
		% [EXPECTED_START_WAVE_TEXT, start_wave_drawn])
	check(bool(_panel.row(0).get("available", false)),
		"Start Wave is available in the build phase: %s" % [_panel.row(0)])
	print("PANEL_BAR_BLOCK " + JSON.stringify({
		"column": column_children,
		"state": state_on_screen,
		"wave": wave_on_screen,
		"rows": _row_count_drawn(),
		"start_wave": start_wave_drawn,
	}))

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

	# --- 1b. a number that changes reaches the label ------------------------
	# The block must follow the run, not a copy of it (T-0077). The demo damages the
	# HQ through the run - the same door a leak uses - and reads the Label back with
	# no call to `refresh()` anywhere in between: the panel's own signal handler is
	# the only thing that can have written it.
	_case("a live number the demo changes reaches the label with no refresh call")
	var run_state = _flow.run_state()
	var hq_before := int(run_state.hq_health())
	var hq_max := int(run_state.hq_max_health())
	if check(hq_before > 1, "the run has HQ left to damage: %d/%d" % [hq_before, hq_max]):
		var applied := int(run_state.damage_hq(1, "inventory_migration_demo"))
		await process_frame
		check_eq_int(applied, 1, "the run took one point of damage")
		check_eq_int(int(run_state.hq_health()), hq_before - 1, "the run's HQ is one lower")
		var damaged := _label_text(_panel.state_path)
		_state_evidence("HQ damaged")
		check(damaged == String(_panel.state()["label"]),
			"the state label followed the damage without a refresh call: '%s' != '%s'"
			% [damaged, String(_panel.state()["label"])])
		check(damaged.contains("%d/%d" % [hq_before - 1, hq_max]),
			"the visible line carries the wounded number: '%s'" % damaged)

		# Healed back, because the frame below is the level as it is played (HQ 10/10
		# in the acceptance frame) and because the label must follow a rise as well as
		# a fall.
		var restored_points := int(run_state.heal_hq(1))
		await process_frame
		check_eq_int(restored_points, 1, "the run restored the point")
		var restored := _label_text(_panel.state_path)
		_state_evidence("HQ healed")
		check(restored == String(_panel.state()["label"]),
			"the state label followed the heal without a refresh call: '%s' != '%s'"
			% [restored, String(_panel.state()["label"])])
		check(restored.contains("%d/%d" % [hq_before, hq_max]),
			"the visible line carries the restored number: '%s'" % restored)

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

	# --- 4b. the drag gesture (T-0078) -------------------------------------
	# Everything below is pushed into the root viewport as the OS delivers it - a
	# move, the press, real motion, the release - and every assertion reads a node
	# or a read-back off the bar the run itself mounted. The ghost is asserted as a
	# rect and a Label text, not as a flag (L-041).
	_case("the bar carries the drag contract (T-0078)")
	check(_bar.has_signal("tower_dropped"), "the bar carries the tower_dropped signal")
	check(_bar.has_signal("tower_drag_started"), "the bar carries the tower_drag_started signal (T-0080)")
	if not _signals_connected:
		if _bar.has_signal("tower_dropped"):
			_bar.connect("tower_dropped", _on_tower_dropped)
		if _bar.has_signal("tower_drag_started"):
			_bar.connect("tower_drag_started", _on_tower_drag_started)
		_signals_connected = true
	check(_signals_connected, "this demo is listening to both drag signals")
	check_eq_int(_drops.size(), 0, "no drop has been raised yet")
	check_eq_int(_starts.size(), 0, "no drag has been announced yet")
	check(not _bar.drag_active(), "no drag is live before the first press")

	# The tower the case above placed, pressed in its own slot: the click meaning it
	# has today, with no drag behind it - and therefore no `tower_drag_started`.
	_case("a placed tower's slot starts no drag")
	var placed_rect: Rect2 = _bar.slot_rect("towers", 0)
	check(_bar.slot_state("towers", 0) == "placed",
		"the slot this case presses holds the placed tower: '%s'" % _bar.slot_state("towers", 0))
	await _drag_press(placed_rect.get_center(), "left press on the placed tower's slot")
	check(not _bar.drag_active(), "the placed slot started no drag: %s" % [_drag_json()])
	check(_bar.ghost_rect().size.x <= 0.0, "no ghost was drawn for a placed tower: %s" % [_bar.ghost_rect()])
	check_eq_int(_starts.size(), 0, "a placed slot announced no drag start")
	await _drag_release(placed_rect.get_center(), "release on the placed tower's own slot")
	check_eq_int(_drops.size(), 0, "a release on the placed slot raised no drop")

	# A drag needs a tower in hand and this run holds one tower, so the player's own
	# route back - the window's Take back row - is the route taken here. The drag is
	# then proved on a tower the player really has, in hand, on the real boot path.
	# The window is still up: the press that selected the placed tower opened it, and
	# that is asserted here rather than assumed.
	_case("the placed tower is taken back, so there is a tower in hand to drag")
	var take_back_window = _window()
	if check(_window_open(take_back_window), "the press on the placed slot opened its window"):
		var take_back_row := _window_row_index(take_back_window, "take_back")
		if check(take_back_row >= 0, "the window offers taking it back: %s" % [take_back_window.rows()]):
			var row_point: Vector2 = take_back_window.row_rect(take_back_row).get_center()
			check(not _bar.claim_point(row_point),
				"the window's row is off the bar, so that click is the window's: %s" % [row_point])
			await _click(row_point, "left click on the window's Take back row")
	await _close_window("close the window after taking the tower back")
	_state_evidence("taken back")
	check(_bar.slot_state("towers", 0) == "in_hand",
		"the slot holds a tower in hand again: '%s'" % _bar.slot_state("towers", 0))
	check(not _arena_has_tower(picked_id), "the board no longer holds the tower: %d" % picked_id)
	check_eq_int(_starts.size(), 0, "the press on a placed slot announced no drag start")

	_case("press on an in-hand slot and drag the tower 200 px onto the board")
	var hand_rect: Rect2 = _bar.slot_rect("towers", 0)
	var press_point: Vector2 = hand_rect.get_center()
	var drop_point: Vector2 = press_point + Vector2(0, -200)
	check(not _bar.get_global_rect().has_point(drop_point),
		"the drop point is off the bar: %s in %s" % [drop_point, _bar.get_global_rect()])
	await _drag_press(press_point, "left press on the in-hand tower at (%.0f, %.0f)" % [press_point.x, press_point.y])
	check(_bar.drag_active(), "the press on a tower in hand starts a drag: %s" % [_drag_json()])
	check_eq_int(int(_bar.drag_instance()), picked_id, "the drag carries the tower that was pressed")
	check_eq_int(_starts.size(), 0,
		"a press alone announces no drag: this could still be a click (tower_drag_started)")
	var ghost_pressed: Rect2 = _bar.ghost_rect()
	check(ghost_pressed.size.x > 0.0, "the ghost is a drawn node from the press: %s" % [ghost_pressed])
	check(absf(ghost_pressed.size.x - float(_bar.slot_side)) <= 1.0,
		"the ghost is one slot square: %.1f vs %d" % [ghost_pressed.size.x, int(_bar.slot_side)])
	check(ghost_pressed.get_center().distance_to(press_point) <= 2.0,
		"the ghost is centred on the press: %s vs %s" % [ghost_pressed.get_center(), press_point])

	await _drag_move(drop_point, "drag 200 px up onto the board")
	var ghost: Rect2 = _bar.ghost_rect()
	check(_bar.drag_active(), "the drag is still live after the motion: %s" % [_drag_json()])
	check(_bar.drag_point().distance_to(drop_point) <= 1.0,
		"the drag's point follows the pointer: %s vs %s" % [_bar.drag_point(), drop_point])
	check(ghost.size.x > 0.0, "the ghost is still drawn while the drag is live: %s" % [ghost])
	check(ghost.get_center().distance_to(drop_point) <= 2.0,
		"the ghost is centred within 2 px of the pointer: %s vs %s" % [ghost.get_center(), drop_point])
	var ghost_text := String(_bar.ghost_text())
	check_eq_int(_starts.size(), 1,
		"the motion past the threshold announced the drag exactly once (tower_drag_started)")
	if _starts.size() == 1:
		check_eq_int(int(_starts[0]), picked_id, "the announced drag names the tower carried")
	check(ghost_text.contains(String(picked["type_id"])),
		"the ghost names the tower: '%s' carries '%s'" % [ghost_text, String(picked["type_id"])])
	check(ghost_text.contains(String(picked["tier_text"])),
		"the ghost names the tier: '%s' carries '%s'" % [ghost_text, String(picked["tier_text"])])
	print("PANEL_BAR_DRAG " + JSON.stringify({
		"case": "dragging",
		"instance": int(_bar.drag_instance()),
		"point": [_bar.drag_point().x, _bar.drag_point().y],
		"ghost": _rect_json(ghost),
		"ghost_text": ghost_text,
	}))

	# The arena's refusal count before the release below: with the drop wired (T-0080)
	# the count rising by one is what proves the release reached the board's own door.
	var ground_refusals := int(_arena.refused_count())
	await _drag_release(drop_point, "release the tower on the board")
	check_eq_int(_drops.size(), 1, "the release raised tower_dropped exactly once")
	if _drops.size() == 1:
		check_eq_int(int(_drops[0]["id"]), picked_id, "the drop names the tower the drag carried")
		var dropped_at: Vector2 = _drops[0]["point"]
		check(dropped_at.distance_to(drop_point) <= 1.0,
			"the drop point is the release point: %s vs %s" % [dropped_at, drop_point])
		print("PANEL_BAR_DROP " + JSON.stringify({
			"case": "board release",
			"count": _drops.size(),
			"instance": int(_drops[0]["id"]),
			"point": [dropped_at.x, dropped_at.y],
			"release": [drop_point.x, drop_point.y],
			"window_open": _window_open(_window()),
		}))
	check(not _bar.drag_active(), "the release ended the drag")
	check(_bar.ghost_rect().size.x <= 0.0, "the ghost is hidden after the release: %s" % [_bar.ghost_rect()])
	# Wired by the boot (T-0080), this release does reach the arena - and the arena
	# refuses it: the point is bare ground, 335.9 px from the nearest tile. The tower
	# therefore stays in hand, nothing stands, and the panel shows the arena's own
	# sentence rather than the bar-owned one, which is how "it got there" is proved.
	check(not _arena_has_tower(picked_id), "bare ground placed no tower: %d" % picked_id)
	check(_bar.slot_state("towers", 0) == "in_hand",
		"the tower is still in hand after the bare-ground refusal: '%s'" % _bar.slot_state("towers", 0))
	check_eq_int(int(_arena.refused_count()), ground_refusals + 1,
		"the bare-ground release reached the arena's door: refused_count +1")
	check(String(_panel.reason()) == String(_arena.last_refusal()),
		"the panel shows the arena's refusal for bare ground: '%s' vs '%s'"
		% [String(_panel.reason()), String(_arena.last_refusal())])
	check(String(_panel.reason()) != String(_panel.drop_off_board_text),
		"the refusal is not the panel's bar-owned sentence: '%s'" % String(_panel.reason()))
	print("PANEL_BAR_REFUSED " + JSON.stringify({
		"case": "bare ground",
		"held": _bar.slot_state("towers", 0),
		"placed": _arena_has_tower(picked_id),
		"reason": String(_panel.reason()),
		"arena_reason": String(_arena.last_refusal()),
		"arena_refusals": int(_arena.refused_count()),
	}))

	# --- 4c. the panel is the drop's receiving end (T-0079) -----------------
	# The release above landed at (44, 387.5): 335.9 px from the nearest tile this
	# level has (TowerSlot2 at (300, 170)), against a 24 px snap radius, so the arena
	# answers that point as bare ground - a real drop, but not one over a build tile.
	# The receiver is therefore proved with a second real drag, released on the board,
	# and the point handed over is the one **that** release raised, recorded from the
	# signal exactly like the first. Nothing here calls `_select()` or `activate()`.
	_case("the panel receives the bar's drop and places on the nearest tile (T-0079)")
	await _close_window("close the window the T-0078 drag press opened")
	# The bar's own slot as it is drawn *now*: placing a tower rebuilds that slot, and
	# a rect read from a node the container has not laid out yet is not a point a
	# player can click - the second refusal below read one and aimed nowhere.
	var bar_slot_point: Vector2 = _bar.slot_rect("towers", 0).get_center()
	var gold_before_drop := int(_arena.gold())
	var free_before_drop := int(_arena.free_slot_count())
	# Off the tile's centre on purpose: "nearest tile" is only a claim a test can
	# check when the release point is not already the answer.
	var release: Vector2 = _canvas_point(slot["position"]) + DROP_OFFSET
	check(not _bar.get_global_rect().has_point(release),
		"the release point is off the bar: %s in %s" % [release, _bar.get_global_rect()])
	var drops_before := _drops.size()
	# What the arena should answer, built from the arena's own slot list **before**
	# the release: the placement happens inside `_drag_release` now (T-0080), so a
	# list read afterwards would already have the tower standing on the tile.
	var expected := _nearest_free_slot(_world_point(release))
	await _drag_press(bar_slot_point,
		"left press on the tower in hand, for the drop")
	# The press selected the tower, and selecting it opened the window over it - a
	# click's meaning, asserted here so the close below has something to close.
	var press_window = _window()
	check(_window_open(press_window), "the drop's press opened the tower window")
	await _drag_move(release, "drag the tower onto the board at (%.0f, %.0f)" % [release.x, release.y])
	# T-0080: the drag announcement is what puts that window away, before the release
	# can place under it. This is the visible half of the wiring.
	check(not _window_open(press_window),
		"the drag announcement closed the window the press opened: window_open=%s" % _window_open(press_window))
	print("PANEL_BAR_DRAG " + JSON.stringify({
		"case": "drop drag",
		"instance": int(_bar.drag_instance()),
		"point": [_bar.drag_point().x, _bar.drag_point().y],
		"ghost": _rect_json(_bar.ghost_rect()),
		"window_open": _window_open(press_window),
		"starts": _starts.size(),
	}))
	await _drag_release(release, "release the tower over the board")
	check_eq_int(_drops.size(), drops_before + 1, "the release raised one drop for the receiver")
	await _close_window("close the window the drop's press opened")
	if _drops.size() == drops_before + 1:
		# The payload the bar raised, not a reconstruction of it.
		var dropped_entry: Dictionary = _drops[drops_before]
		var released_point: Vector2 = dropped_entry["point"]
		var released_id := int(dropped_entry["id"])
		check_eq_int(released_id, picked_id, "the drop names the tower the drag carried")
		check(released_point.distance_to(release) <= 1.0,
			"the drop's point is the release point: %s vs %s" % [released_point, release])
		# The expectation was built above, before the release placed anything.
		check(not expected.is_empty(),
			"the release point is within a free tile's reach: %s" % [released_point])
		# The boot connected the bar's release to the panel's receiver (T-0080), so
		# nothing here calls it: the placement below happened during `_drag_release`.
		# "Placed" is the board's answer, never a return value this demo obtained.
		var placed_by_drop: bool = _arena_has_tower(released_id)
		check(placed_by_drop,
			"the panel placed the tower the bar dropped: %d at %s" % [released_id, released_point])
		# The inventory signal rebuilds the bar's slot row inside `place_tower()`; let
		# the container lay the new node out before any rect is read from it.
		await _settle()
		_state_evidence("dropped")

		# 1. the tile the arena assigned is the nearest free one to the release.
		var standing := _slot_holding(released_id)
		check(String(standing.get("name", "<no tile>")) == String(expected.get("name", "<no tile>")),
			"the tower stands on the nearest free tile to the release: '%s' vs '%s'"
			% [String(standing.get("name", "<no tile>")), String(expected.get("name", "<no tile>"))])
		check(_arena_has_tower(released_id), "the board holds the dropped tower: %d" % released_id)
		print("PANEL_BAR_DROP " + JSON.stringify({
			"case": "receiving end",
			"instance": released_id,
			"point": [released_point.x, released_point.y],
			"release": [release.x, release.y],
			"expected_slot": String(expected.get("name", "<no tile>")),
			"slot": String(standing.get("name", "<no tile>")),
			"placed": placed_by_drop,
			"reason": String(_panel.reason()),
		}))
		# 2. the slot the player drags is drawn as placed, with the placed border.
		check(_bar.slot_state("towers", 0) == "placed",
			"the bar's slot reports the tower placed: '%s'" % _bar.slot_state("towers", 0))
		check(_bar.slot_border("towers", 0).is_equal_approx(_bar.placed_border_colour),
			"the slot is drawn with the placed border colour: %s vs %s"
			% [_bar.slot_border("towers", 0), _bar.placed_border_colour])
		# 3. free, and the panel's selection is the tower it placed.
		check_eq_int(int(_arena.gold()), gold_before_drop, "the drop took no gold")
		check_eq_int(int(_arena.free_slot_count()), free_before_drop - 1,
			"the drop filled exactly one tile")
		check_eq_int(int(_panel.selected_instance()), released_id,
			"the panel selected the tower the drop placed")
		# 4. a second drop of the same tower is refused and places nothing.
		var refusals_before_second := int(_arena.refused_count())
		var free_before_second := int(_arena.free_slot_count())
		check(not _panel.drop_tower(released_id, released_point),
			"a second drop of the same tower is refused")
		check(String(_panel.reason()) == String(_panel.drop_already_placed_text),
			"the second drop is refused as already placed: '%s'" % String(_panel.reason()))
		check_eq_int(int(_arena.refused_count()), refusals_before_second,
			"the second drop was refused by the panel, not by the arena")
		check_eq_int(int(_arena.free_slot_count()), free_before_second,
			"the second drop placed nothing")
		# 5. a point inside the bar is refused before the arena is asked. The point is
		# the slot's centre captured before the drop: the rebuilt slot is the node the
		# player now sees, but its rect is only valid after layout.
		var in_bar: Vector2 = bar_slot_point
		check(_bar.claim_point(in_bar), "the point this case drops on is the bar's: %s" % [in_bar])
		var refusals_before_bar := int(_arena.refused_count())
		check(not _panel.drop_tower(released_id, in_bar), "a drop released on the bar is refused")
		check(String(_panel.reason()) == String(_panel.drop_off_board_text),
			"the bar-owned drop is refused as off the board: '%s'" % String(_panel.reason()))
		check_eq_int(int(_arena.refused_count()), refusals_before_bar,
			"the bar-owned drop never reached the arena: refused_count unchanged")
		check_eq_int(int(_arena.free_slot_count()), free_before_second,
			"that refusal placed nothing")
		# 6. taken back through the panel, so the cases below start where they did:
		# one tower, in hand, nothing on the board.
		check(_panel.take_back_selected(), "the panel takes the dropped tower back")
		await _settle()
		check(_bar.slot_state("towers", 0) == "in_hand",
			"the slot holds the tower in hand again: '%s'" % _bar.slot_state("towers", 0))
		check(not _arena_has_tower(released_id),
			"the board no longer holds the tower after the take-back: %d" % released_id)
		check_eq_int(int(_arena.gold()), gold_before_drop, "the take-back took no gold either")
		_state_evidence("taken back after the drop")

	_case("a press and release inside the bar is a click, not a drop")
	await _close_window("close the window the drag press opened")
	var before_inside: int = _drops.size()
	var starts_before_click: int = _starts.size()
	var inside: Vector2 = _bar.slot_rect("towers", 0).get_center()
	await _drag_press(inside, "left press on the in-hand tower")
	check(_bar.drag_active(), "the press still starts a drag")
	await _drag_release(inside, "release without moving")
	check_eq_int(_drops.size(), before_inside, "a release without motion raised no drop")
	check_eq_int(_starts.size(), starts_before_click,
		"a press that never moved announced no drag, so the window it opened stays up")
	check(not _bar.drag_active(), "the release ended the drag")
	check(_bar.ghost_rect().size.x <= 0.0, "the ghost is hidden again: %s" % [_bar.ghost_rect()])
	check_eq_int(int(_bar.selected_instance()), picked_id, "the click's selection stands")
	await _close_window("close the window that click opened")

	# Far enough to pass the threshold, but released inside the bar: the "outside"
	# half of the rule alone, with the distance half satisfied.
	var far_inside: Vector2 = inside + Vector2(0, -(float(_bar.drag_threshold_px) + 20.0))
	check(_bar.get_global_rect().has_point(far_inside),
		"the far-inside point is still in the bar: %s in %s" % [far_inside, _bar.get_global_rect()])
	await _drag_press(inside, "left press on the in-hand tower again")
	await _drag_move(far_inside, "drag past the threshold, staying inside the bar")
	check_eq_int(_starts.size(), starts_before_click + 1,
		"a motion past the threshold inside the bar does announce a drag")
	await _drag_release(far_inside, "release inside the bar, past the threshold")
	check_eq_int(_drops.size(), before_inside,
		"a release inside the bar raised no drop, however far it travelled")
	check(not _bar.drag_active(), "that release ended the drag too")
	await _close_window("close the window the second in-bar press opened")

	_case("the wave lock suppresses the drag and unlocking restores it (T-0078)")
	var before_lock: int = _drops.size()
	var starts_before_lock: int = _starts.size()
	# `set_wave_locked()` rebuilds the slot row, so the demo lets the container lay
	# it out before aiming a real press at it: a press at a rect from before the
	# rebuild would land nowhere and prove nothing about the lock.
	_bar.set_wave_locked(true)
	await _settle()
	_state_evidence("wave lock on")
	check(_bar.wave_locked(), "the bar reports the wave lock")
	var locked_point: Vector2 = _bar.slot_rect("towers", 0).get_center()
	await _drag_press(locked_point, "left press on the in-hand tower while locked")
	check(not _bar.drag_active(), "no drag starts while the wave lock is on: %s" % [_drag_json()])
	check(_window_open(_window()),
		"the locked press still selected the tower it landed on: its window opened")
	check(_bar.ghost_rect().size.x <= 0.0, "no ghost is drawn while locked: %s" % [_bar.ghost_rect()])
	await _drag_move(locked_point + Vector2(0, -200), "drag 200 px up while locked")
	check_eq_int(_starts.size(), starts_before_lock, "a locked press announced no drag")
	check(_bar.ghost_rect().size.x <= 0.0, "a locked drag draws no ghost either: %s" % [_bar.ghost_rect()])
	await _drag_release(_bar.slot_rect("towers", 0).get_center(), "release while locked")
	check_eq_int(_drops.size(), before_lock, "a locked press raised no drop")
	await _close_window("close the window the locked press opened")
	_bar.set_wave_locked(false)
	await _settle()
	_state_evidence("wave lock off")
	var unlocked_point: Vector2 = _bar.slot_rect("towers", 0).get_center()
	await _drag_press(unlocked_point, "left press on the in-hand tower, lock off")
	check(_bar.drag_active(), "with the lock off the same press drags again: %s" % [_drag_json()])
	await _drag_release(unlocked_point, "release inside the bar")
	check_eq_int(_drops.size(), before_lock, "that release inside the bar raised no drop")
	check_eq_int(_starts.size(), starts_before_lock,
		"unlocking restores the press, and a press that never moved still announces nothing")
	check(not _bar.drag_active(), "the release ended the drag")
	await _close_window("close the window the unlocked press opened")

	# The drag changed what a press on a slot means, so the path it must not have
	# broken is proved last: click a tower in hand, click a tile, see it stand.
	_case("the click-then-tile path still places a tower after the drag (T-0078)")
	await _wait_for_settle("before the re-place click")
	await _click(_bar.slot_rect("towers", 0).get_center(), "left click on the tower in hand")
	await _close_window("close the window that click opened")
	await _wait_for_settle("before the re-place tile click")
	await _click(_canvas_point(slot["position"]), "left click on tile %s" % String(slot["name"]))
	_state_evidence("placed again")
	var replanted := _bar_tower(picked_id)
	check(bool(replanted.get("placed", false)), "the tile click placed the tower again: %s" % [replanted])
	check(_arena_has_tower(picked_id), "the board holds it again: %d" % picked_id)
	check_eq_int(_drops.size(), before_lock, "the click-then-tile path raised no drop")

	# --- 5. no overlap -----------------------------------------------------
	_case("the panel's content stops above the bar")
	var geometry := _geometry()
	print("PANEL_BAR_GEOMETRY " + JSON.stringify(geometry))
	var actions_rect: Rect2 = geometry["actions"]
	var bar_rect: Rect2 = geometry["bar"]
	var column_rect: Rect2 = geometry["column"]
	check(bar_rect.size.y > 0.0, "the bar has a height to clear: %s" % [bar_rect])
	check(actions_rect.end.y <= bar_rect.position.y,
		"the block's last element ends above the bar's top edge: actions %.1f <= bar %.1f"
		% [actions_rect.end.y, bar_rect.position.y])
	check(not actions_rect.intersects(bar_rect), "the action list's rect does not intersect the bar's")
	check(column_rect.end.y <= bar_rect.position.y,
		"the panel's whole column stops above the bar: column %.1f <= bar %.1f"
		% [column_rect.end.y, bar_rect.position.y])
	check(int(_panel.content_reserve()) == int(bar_rect.size.y) + int(_panel.bar_gap),
		"the reserve is the bar's measured height plus the gap: %d vs %d + %d"
		% [int(_panel.content_reserve()), int(bar_rect.size.y), int(_panel.bar_gap)])

	# --- the frame the human judges ----------------------------------------
	if _is_movie():
		_case("the frame is held for the movie writer")
		# The two lines read back off the Labels through the shipped paths, so the
		# frame's evidence and the frame itself are the same artifact (T-0077, L-041).
		print("PANEL_BAR_FRAME " + JSON.stringify({
			"viewport": [root.size.x, root.size.y],
			"bar": _rect_json(bar_rect),
			"actions": _rect_json(actions_rect),
			"screen": _boot.screen_name(),
			"state": _label_text(_panel.state_path),
			"wave": _label_text(_panel.wave_path),
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


## A left press, pushed the way the OS delivers it: a move first (so the GUI
## hit-tester has a hovered control), then the press. The release is a separate call,
## because a drag is a press, then motion, then a release (T-0078).
func _drag_press(point: Vector2, what: String) -> void:
	print("PANEL_BAR_EVENT " + JSON.stringify({
		"device": "mouse",
		"what": what,
		"press": [point.x, point.y],
	}))
	await _mouse_move(point)
	var ev := InputEventMouseButton.new()
	ev.device = -1
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = point
	ev.global_position = point
	get_root().push_input(ev)
	await process_frame
	await _settle()


## A motion event with the left button held: what the OS sends between a drag's press
## and its release. Pushed, never handed to a private method.
func _drag_move(point: Vector2, what: String) -> void:
	print("PANEL_BAR_EVENT " + JSON.stringify({
		"device": "mouse",
		"what": what,
		"move": [point.x, point.y],
	}))
	await _mouse_move(point, MOUSE_BUTTON_MASK_LEFT)
	await _settle()


## The left release that ends a gesture, at `point`.
func _drag_release(point: Vector2, what: String) -> void:
	print("PANEL_BAR_EVENT " + JSON.stringify({
		"device": "mouse",
		"what": what,
		"release": [point.x, point.y],
	}))
	var ev := InputEventMouseButton.new()
	ev.device = -1
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.button_mask = 0
	ev.position = point
	ev.global_position = point
	get_root().push_input(ev)
	await process_frame
	await _settle()


## One pointer move, with `mask` as the held buttons. `relative` is a real delta from
## the last point this demo pushed, so the event is shaped like the OS's.
func _mouse_move(point: Vector2, mask: int = 0) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.button_mask = mask
	motion.relative = point - _pointer
	_pointer = point
	get_root().push_input(motion)
	await process_frame


## Every `tower_dropped` the bar raises, recorded from the signal: the count, the id
## and the point the demo asserts are the ones the bar emitted, not a reconstruction.
func _on_tower_dropped(instance_id: int, screen_point: Vector2) -> void:
	_drops.append({"id": instance_id, "point": screen_point})
	print("PANEL_BAR_DROP " + JSON.stringify({
		"case": "signal",
		"instance": instance_id,
		"point": [screen_point.x, screen_point.y],
		"count": _drops.size(),
	}))


## Every `tower_drag_started` the bar raises: the id it announced, so "one drag
## began" is the bar's own count and not the demo's belief.
func _on_tower_drag_started(instance_id: int) -> void:
	_starts.append(instance_id)
	print("PANEL_BAR_START " + JSON.stringify({
		"instance": instance_id,
		"count": _starts.size(),
	}))


## The bar's drag state as one dictionary, for a failure message: what is being
## carried, where the pointer is, and the ghost's rect and text as drawn.
func _drag_json() -> Dictionary:
	return {
		"active": _bar.drag_active(),
		"instance": int(_bar.drag_instance()),
		"point": [_bar.drag_point().x, _bar.drag_point().y],
		"ghost": _rect_json(_bar.ghost_rect()),
		"ghost_text": String(_bar.ghost_text()),
	}


## The index of the first row of `kind` in the tower window's drawn row list, read
## from the window's own `rows()`. -1 for a row it does not draw. The same shape as
## `_row_index()` for the opening modal, and for the same reason: the demo aims at
## what the window drew, never at a layout it assumed.
func _window_row_index(window, kind: String) -> int:
	for entry in window.rows():
		var row: Dictionary = entry
		if String(row["kind"]) == kind:
			return int(row["index"])
	return -1


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


## True when the run is writing a movie. `Engine.get_write_movie_path()` is the only
## reliable source: Godot strips its own arguments from `OS.get_cmdline_args()`
## (4.7.2 hands the script back only `--script res://...`), so the argument scan
## this used never matched and the hold below never ran (T-0077).
func _is_movie() -> bool:
	var path := String(Engine.get_write_movie_path())
	return path != "" and path.to_lower() != "disabled"


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


## Every exported copy path, read off the panel's own exports, resolves to the node
## class it is drawn with. A scene restructure that updates seven of eight paths
## used to fail on the human's screen and nowhere else; here it fails the demo
## (L-041). Read from the exports on purpose: a demo carrying its own copy of the
## paths would agree with a stale panel.
func _check_copy_paths() -> void:
	var labels := {
		"state_path": _panel.state_path,
		"wave_path": _panel.wave_path,
	}
	for key in labels:
		var path: NodePath = labels[key]
		var node = _panel.get_node_or_null(path)
		check(node is Label, "the exported %s resolves to a Label: '%s' -> %s"
			% [String(key), String(path), node])
	var list_path: NodePath = _panel.action_list_path
	var list = _panel.get_node_or_null(list_path)
	check(list is VBoxContainer,
		"the exported action_list_path resolves to the row list: '%s' -> %s"
		% [String(list_path), list])


## The names of the block's column children, in scene order. The T-0081 contract is
## "three elements and nothing else", so this is the assertion that catches a fourth
## node whether it was added to the scene or left behind by a restructure.
func _column_children() -> Array[String]:
	var out: Array[String] = []
	var margin = _panel.get_node_or_null(_panel.margin_path)
	var column = margin.get_node_or_null("Column") if margin != null else null
	if column == null:
		return out
	for child in column.get_children():
		out.append(String(child.name))
	return out


## How many rows the action list draws. One, after T-0081: Start Wave.
func _row_count_drawn() -> int:
	var list = _panel.get_node_or_null(_panel.action_list_path)
	return list.get_child_count() if list != null else -1


## The text of row `index` as drawn: the Label inside the row the panel built, not
## the dictionary the panel reports (L-041).
func _row_text(index: int) -> String:
	var list = _panel.get_node_or_null(_panel.action_list_path)
	if list == null:
		return ""
	var row = list.get_node_or_null("Row%d" % index)
	if row == null:
		return ""
	var label = row.get_node_or_null("Text")
	return String((label as Label).text) if label is Label else ""


func _geometry() -> Dictionary:
	var margin = _panel.get_node_or_null(_panel.margin_path)
	var column = null
	var actions = _panel.get_node_or_null(_panel.action_list_path)
	if margin != null:
		column = margin.get_node_or_null("Column")
	return {
		"bar": _bar.get_global_rect(),
		"panel": _panel.get_global_rect(),
		"column": (column as Control).get_global_rect() if column is Control else Rect2(),
		"actions": (actions as Control).get_global_rect() if actions is Control else Rect2(),
		"reserve": int(_panel.content_reserve()),
	}


func _rect_json(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _free_slot() -> Dictionary:
	for slot in _arena.build_slots():
		if bool(slot["free"]):
			return slot
	return {}


## The free build tile nearest `world`, read from the arena's own slot list and each
## tile's own `snap_radius_px` - the expectation is built beside the panel, from the
## level's data, and never borrowed from the panel under test. `{}` when no free tile
## is within reach of the point.
func _nearest_free_slot(world: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for slot in _arena.build_slots():
		if not bool(slot["free"]):
			continue
		var distance: float = (slot["position"] as Vector2).distance_to(world)
		if distance > float(slot["snap_radius_px"]) or distance >= best_distance:
			continue
		best = slot
		best_distance = distance
	return best


## The build tile the arena reports for `instance_id`, from its own slot list; `{}`
## while that tower is in hand.
func _slot_holding(instance_id: int) -> Dictionary:
	for slot in _arena.build_slots():
		if int(slot.get("instance_id", 0)) == instance_id:
			return slot
	return {}


## A viewport point as the arena's world point, through the arena's own transform:
## the demo's inverse of `_canvas_point()`, so the expectation and the click speak the
## same coordinates.
func _world_point(point: Vector2) -> Vector2:
	return (_arena as CanvasItem).get_global_transform_with_canvas().affine_inverse() * point


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
