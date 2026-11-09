extends SceneTree

## T-0065 DoD 2-5 - the opening choice, driven through the real boot path.
##
##     godot --headless --path . --script res://src/ui/tests/choice_modal_demo.gd
##
## Start Game is a real `game_confirm` pushed into the root viewport, the way the
## OS delivers one. The two planted failures and both picks are real left clicks
## pushed through the same door (`get_root().push_input()`), so every assertion is
## made after the event has travelled
##     menu -> Start Game -> boot -> map screen (inert) -> modal rows
## No check calls `activate()`, `choose()`, `confirm()`, `dismiss()` or
## `enter_node()`: each one asserts on what the pushed event did.
##
## The cases, in order:
##   1. the modal is up over the map, and the run has granted nothing;
##   2. a real click where a map row is does nothing - route unchanged, nothing
##      entered - because the modal swallows the pointer;
##   3. PLANTED FAILURE A: confirm with the upgrade group unpicked is refused,
##      the reason is printed, and nothing lands in the inventory;
##   4. PLANTED FAILURE B: a dismiss (Escape, `game_dismiss`) is refused, printed,
##      and the modal stays up;
##   5. one tower and one upgrade clicked, confirm clicked: the inventory holds
##      exactly those two, and a real click on the map now enters a node.
##
## The acceptance frame (DoD 5) is produced with `--frame=<path>`: after the
## choice is on screen the demo waits for `RenderingServer.frame_post_draw` and
## writes the viewport image there. The same run works under `--write-movie`, in
## which case the open modal is held for `MOVIE_HOLD_FRAMES` so the writer flushes
## it:
##
##     godot --path . --write-movie <out>/choice.png --fixed-fps 30 \
##         --script res://src/ui/tests/choice_modal_demo.gd -- --frame=<out>/choice_open.png
##
## Prints, in this order:
##   CHOICE_DEMO_CASE {text}        one line per case
##   CHOICE_DEMO_EVENT {json}       every pushed device event, with what it means
##   CHOICE_DEMO_MODAL {json}       the modal as drawn: rows, groups, picks, player copy
##   CHOICE_DEMO_BLOCKED {json}     the map click the modal swallowed, and the route
##   CHOICE_DEMO_REFUSED {json}     each planted failure with its reason and the inventory
##   CHOICE_DEMO_INVENTORY {json}   the inventory after the pick, item by item
##   CHOICE_DEMO_FRAME {json}       only with --frame=: where the image went
##   CHOICE_MODAL_SELF_TEST {json}  once, last; carries checks and failures
##
## The prefix above is `CHOICE_DEMO_*`, not `CHOICE_MODAL_*`: the component prints
## its own `CHOICE_MODAL_SHOWN|PICK|CONFIRM|REFUSED|DISMISS_REFUSED|CLOSED` lines,
## and two line families under one prefix would make "the last one wins" ambiguous
## (L-038's lesson, applied to a log). `BOOT_*`, `MENU_*`, `RUNFLOW_*` and
## `MAPSCREEN_*` lines around these belong to the objects under test.
##
## The exit code follows the self-test line (L-035: the line is the evidence, the
## code is a convenience for a caller that only wants pass/fail).

const BOOT_SCENE := "res://scenes/boot.tscn"

## The map every UI demo walks, so they all talk about one run.
const SEED := 20261108

## The window the modal is laid out in; `--headless` gives every run a 64x64
## viewport whatever the project says (measured T-0062), so it is set explicitly.
const VIEWPORT := Vector2i(1152, 648)

const SETTLE_FRAMES := 2

## Frames the open modal is held for under `--write-movie`, so the movie writer
## flushes the frame the human judges.
const MOVIE_HOLD_FRAMES := 12

## How far inside a map row the blocked click lands, in pixels. The left margin of
## the map screen is 40, and the modal's panel is centred and 640 wide, so this
## point is inside the row the player would have taken and outside the modal's
## panel: the click hits the modal's backdrop, which is the whole point.
const ROW_INSET := 8.0

## The words a refused confirm must carry: the group still missing a pick, in the
## player's words as the boot names it. Duplicated here on purpose - a demo that
## read its expectations off the modal under test could not catch the modal
## renaming the group.
const UNMET_WORD_TOWER := "Tower"
const UNMET_WORD_UPGRADE := "Upgrade"

var _boot = null
var _modal = null
var _flow = null
var _map_screen = null

## Kept after the boot releases the modal, so the demo can prove it is gone.
var _modal_ref = null

var _checks: int = 0
var _failures: Array[String] = []

## Set only when the last case has run. A case that throws aborts the coroutine and
## `await` then hands `_run()` a null, which would otherwise read as "the demo is
## done": this flag is what makes a dead coroutine a failure instead of a green run.
var _reached_end: bool = false


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
	if not check(_boot != null, "the boot scene instantiates"):
		_finish()
		return
	_boot.run_seed = SEED
	# Quitting the tree would end this demo before it reported.
	_boot.set_quit_enabled_for_demo(false)
	root.add_child(_boot)
	await _settle()

	if not await _start_game():
		_finish()
		return
	if not await _swallowed_click():
		_finish()
		return
	if not await _planted_failure_a():
		_finish()
		return
	if not await _planted_failure_b():
		_finish()
		return
	if not await _pick_and_confirm():
		_finish()
		return
	await _map_is_interactive_again()

	_reached_end = true
	_finish()


# --- 1. Start Game, and the choice over the map ------------------------------

func _start_game() -> bool:
	_case("Start Game is a real game_confirm; the boot opens the map with the choice on top")

	if not check(_boot.screen_name() == "menu", "the boot opens on the menu: %s" % _boot.screen_name()):
		return false
	var menu = _boot.menu()
	if not check(menu != null, "the menu is up"):
		return false
	if not check_eq_int(menu.focus_index(), 0, "the menu focuses row 0"):
		return false
	var first_row: Dictionary = menu.row(0)
	if not check(
		String(first_row.get("id", "")) == "start",
		"row 0 is Start Game: '%s'" % String(first_row.get("id", ""))
	):
		return false

	await _press(KEY_ENTER, "game_confirm (Enter) on menu row 0 'Start Game'")

	if not check(_boot.screen_name() == "map", "Enter on the menu opened the map: %s" % _boot.screen_name()):
		return false
	_flow = _boot.flow()
	_map_screen = _boot.map_screen()
	_modal = _boot.opening_modal()
	_modal_ref = _modal
	if not check(_flow != null, "the run session is up"):
		return false
	if not check(_map_screen != null, "the map screen is up"):
		return false
	if not check(_modal != null, "the boot mounted the opening choice modal"):
		return false
	return await _assert_over_the_map()


func _assert_over_the_map() -> bool:
	_case("the choice is over the map, and the run has granted nothing")

	check(_modal.is_open(), "the modal reports itself open")
	check((_modal as CanvasItem).visible, "the modal is on screen")
	check((_map_screen as CanvasItem).visible, "the map is still visible under the modal")
	var screens := _screens_layer()
	if not check(screens != null, "the boot's screens layer is reachable"):
		return false
	check(
		_modal.get_index() > _map_screen.get_index(),
		"the modal is a later sibling of the map screen, so it draws over it (%d > %d)"
		% [_modal.get_index(), _map_screen.get_index()]
	)
	var modal_rect: Rect2 = (_modal as Control).get_global_rect()
	var map_rect: Rect2 = (_map_screen as Control).get_global_rect()
	check(modal_rect.encloses(map_rect), "the modal covers the whole map screen: %s over %s" % [modal_rect, map_rect])

	if not check_eq_int(_modal.row_count(), 5, "the modal drew 2 tower rows, 2 upgrade rows and Confirm"):
		return false
	if not check_eq_int(_flow.inventory().tower_count(), 0, "no tower is granted before the choice"):
		return false
	if not check_eq_int(_flow.inventory().upgrade_count(), 0, "no upgrade is granted before the choice"):
		return false
	if not check(_flow.opening_pending(), "the run reports the opening choice as pending"):
		return false

	var config: Dictionary = _modal.config()
	var groups: Array = config.get("groups", [])
	if not check_eq_int(groups.size(), 2, "the opening choice has two groups"):
		return false
	check(
		String((groups[0] as Dictionary).get("label", "")) == UNMET_WORD_TOWER,
		"group 1 is the tower group: '%s'" % String((groups[0] as Dictionary).get("label", ""))
	)
	check(
		String((groups[1] as Dictionary).get("label", "")) == UNMET_WORD_UPGRADE,
		"group 2 is the upgrade group: '%s'" % String((groups[1] as Dictionary).get("label", ""))
	)
	check(
		((groups[0] as Dictionary).get("options", []) as Array).size() == 2,
		"the tower group offers two towers"
	)
	check(
		((groups[1] as Dictionary).get("options", []) as Array).size() == 2,
		"the upgrade group offers two upgrades"
	)
	check(
		String((_modal.get_node_or_null(_modal.title_path) as Label).text) == String(config.get("title", "")),
		"the title on screen is the title the modal was opened with"
	)

	print("CHOICE_DEMO_MODAL " + JSON.stringify({
		"case": "opened",
		"open": _modal.is_open(),
		"visible": (_modal as CanvasItem).visible,
		"map_visible": (_map_screen as CanvasItem).visible,
		"sibling_index": [_map_screen.get_index(), _modal.get_index()],
		"title_on_screen": String((_modal.get_node_or_null(_modal.title_path) as Label).text),
		"groups": config.get("groups", []),
		"rows": _modal.rows(),
		"picks": _modal.picks(),
		"towers": _flow.inventory().tower_count(),
		"upgrades": _flow.inventory().upgrade_count(),
		"pending": _flow.opening_pending(),
	}))

	# --- the acceptance frame, taken while the choice is open and unpicked ---
	var frame_path := _frame_arg()
	if frame_path != "":
		await _capture_frame(frame_path)
	if _is_movie():
		_case("the open choice is held for the movie writer")
		await _hold(MOVIE_HOLD_FRAMES)
	return true


# --- 2. the map is inert under the modal -------------------------------------

func _swallowed_click() -> bool:
	_case("a real click where a map row is does nothing while the choice is open")

	var target := _selectable_row()
	if not check(not target.is_empty(), "the map offers a selectable row to aim at"):
		return false
	var rect: Rect2 = (target["node"] as Control).get_global_rect()
	var point := Vector2(rect.position.x + ROW_INSET, rect.get_center().y)

	check(rect.has_point(point), "the aimed point is inside map row %d: %s in %s" % [int(target["index"]), point, rect])
	check(not _inside_any_modal_row(point), "the aimed point is not on a modal row, so it can only hit the modal's backdrop")

	var route_before: Array = _flow.map().route()
	var inventory_before := _inventory_view()
	var picks_before: Dictionary = _modal.picks()
	var levels_before: int = _flow.run_state().level_index()
	var session_refusals_before: int = _flow.refused_count()

	await _click(point, "left click on map row %d (%s) under the modal" % [int(target["index"]), String(target["type"])])

	var route_after: Array = _flow.map().route()
	var inventory_after := _inventory_view()
	var picks_after: Dictionary = _modal.picks()

	check(route_after == route_before, "the route did not move: %s -> %s" % [route_before, route_after])
	check(not _flow.is_in_level(), "no level opened under the modal")
	check_eq_int(_flow.run_state().level_index(), levels_before, "no level was completed")
	check_eq_int(_flow.refused_count(), session_refusals_before, "the session was never asked to enter a node")
	check(inventory_after == inventory_before, "the inventory did not change: %s" % [inventory_after])
	check(picks_after == picks_before, "the click did not pick anything in the modal: %s" % [picks_after])
	check(_modal.is_open(), "the modal is still up after the click")
	check(_boot.screen_name() == "map", "the boot is still on the map: %s" % _boot.screen_name())

	print("CHOICE_DEMO_BLOCKED " + JSON.stringify({
		"row": int(target["index"]),
		"node": int(target["id"]),
		"type": String(target["type"]),
		"point": [point.x, point.y],
		"row_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"route_before": route_before,
		"route_after": route_after,
		"inventory": inventory_after,
		"session_refusals": _flow.refused_count(),
		"modal_open": _modal.is_open(),
	}))
	return true


# --- 3. planted failure A: confirm with a group unpicked ---------------------

func _planted_failure_a() -> bool:
	_case("PLANTED FAILURE A: confirming with the upgrade group unpicked is refused and grants nothing")

	var tower_pick := _group_option(0, -1)
	var upgrade_group := _group_option(1, -1)
	if not check(not tower_pick.is_empty() and not upgrade_group.is_empty(), "both groups have an option to click"):
		return false

	var tower_row := _modal_row_index(String(tower_pick["group"]), String(tower_pick["option"]))
	if not check(tower_row >= 0, "the tower option has a row to click"):
		return false
	await _click_row(tower_row, "left click on tower row %d (%s)" % [tower_row, String(tower_pick["option"])])
	if not check(_modal.is_open(), "the modal is still up after the pick"):
		return false
	check_eq_int(_modal.picks().size(), 1, "one group holds a pick")

	var inventory_before := _inventory_view()
	var attempts_before: int = _modal.confirm_attempts()
	var confirm_row := _confirm_row_index()
	if not check(confirm_row >= 0, "the modal has a Confirm row to click"):
		return false

	await _click_row(confirm_row, "left click on Confirm while the upgrade group is unpicked")

	var reason: String = _modal.reason()
	var unmet: Array = _modal.unmet_groups()
	check_eq_int(_modal.confirm_attempts(), attempts_before + 1, "the click reached confirm exactly once")
	check(not unmet.is_empty(), "the modal still reports an unpicked group: %s" % [unmet])
	check(reason.contains(UNMET_WORD_UPGRADE), "the printed reason names the unpicked group: '%s'" % reason)
	check(_modal.is_open(), "the refused confirm left the modal up")
	check(_flow.opening_pending(), "the run is still waiting for its choice")
	check(_inventory_view() == inventory_before, "the refused confirm granted nothing: %s" % [_inventory_view()])
	check_eq_int(_flow.inventory().tower_count(), 0, "no tower was granted by the refused confirm")
	check_eq_int(_flow.inventory().upgrade_count(), 0, "no upgrade was granted by the refused confirm")
	check_eq_int(_boot.runs_started(), 1, "the refused confirm did not start a second run")

	print("CHOICE_DEMO_REFUSED " + JSON.stringify({
		"case": "confirm_with_unpicked_group",
		"reason_on_screen": reason,
		"unmet": unmet,
		"attempts": _modal.confirm_attempts(),
		"picks": _modal.picks(),
		"pending": _flow.opening_pending(),
		"inventory": _inventory_view(),
	}))
	return true


# --- 4. planted failure B: the modal cannot be dismissed --------------------

func _planted_failure_b() -> bool:
	_case("PLANTED FAILURE B: a dismiss is refused, printed, and the modal stays up")

	var inventory_before := _inventory_view()
	var picks_before: Dictionary = _modal.picks()
	var dismissals_before: int = _modal.dismissals()
	var route_before: Array = _flow.map().route()

	await _press(KEY_ESCAPE, "game_dismiss (Escape) on the open choice")

	check_eq_int(_modal.dismissals(), dismissals_before + 1, "the Escape reached the modal's dismiss")
	check_eq_int(_modal.dismissals(), 1, "exactly one dismiss attempt was counted")
	check(_modal.is_open(), "the modal is still up after the dismiss")
	check_eq_int(_modal.picks().size(), picks_before.size(), "the dismiss cleared no pick")
	check(_modal.reason() == String(_modal.dismiss_text), "the modal says why it cannot be dismissed: '%s'" % _modal.reason())
	check(_inventory_view() == inventory_before, "the dismiss granted nothing: %s" % [_inventory_view()])
	check(_flow.opening_pending(), "the run is still held by the choice")
	check(_flow.map().route() == route_before, "the route did not move: %s" % [_flow.map().route()])
	check(_boot.screen_name() == "map", "the boot did not leave the map: %s" % _boot.screen_name())
	check_eq_int(_boot.runs_started(), 1, "the dismiss did not start a second run")

	print("CHOICE_DEMO_REFUSED " + JSON.stringify({
		"case": "dismiss",
		"reason_on_screen": _modal.reason(),
		"dismissals": _modal.dismissals(),
		"picks": _modal.picks(),
		"open": _modal.is_open(),
		"inventory": _inventory_view(),
		"route": _flow.map().route(),
	}))
	return true


# --- 5. the pick, and the map becoming interactive again --------------------

func _pick_and_confirm() -> bool:
	_case("one tower and one upgrade by real clicks; confirm lands exactly those two")

	var tower := _group_option(0, -1)
	var upgrade := _group_option(1, -1)
	if not check(not tower.is_empty() and not upgrade.is_empty(), "both groups have an option to click"):
		return false

	# The tower is already picked by failure A; picking the other one proves the
	# click changes the pick rather than only the first option being reachable.
	var tower_choice := _group_option(0, 1)
	var upgrade_choice := _group_option(1, 0)
	if tower_choice.is_empty():
		tower_choice = tower
	if upgrade_choice.is_empty():
		upgrade_choice = upgrade

	var tower_row := _modal_row_index(String(tower_choice["group"]), String(tower_choice["option"]))
	var upgrade_row := _modal_row_index(String(upgrade_choice["group"]), String(upgrade_choice["option"]))
	if not check(tower_row >= 0 and upgrade_row >= 0, "both chosen options have rows to click"):
		return false

	await _click_row(tower_row, "left click on tower row %d (%s)" % [tower_row, String(tower_choice["option"])])
	await _click_row(upgrade_row, "left click on upgrade row %d (%s)" % [upgrade_row, String(upgrade_choice["option"])])

	check_eq_int(_modal.picks().size(), 2, "both groups now hold a pick")
	check(
		String(_modal.picks().get("tower", "")) == String(tower_choice["option"]),
		"the tower group holds the clicked tower: '%s'" % String(_modal.picks().get("tower", ""))
	)
	check(
		String(_modal.picks().get("upgrade", "")) == String(upgrade_choice["option"]),
		"the upgrade group holds the clicked upgrade: '%s'" % String(_modal.picks().get("upgrade", ""))
	)
	check(_modal.unmet_groups().is_empty(), "no group is left unpicked")

	var confirm_row := _confirm_row_index()
	if not check(confirm_row >= 0, "the modal has a Confirm row to click"):
		return false
	# Read the offered-but-unpicked ids before the confirm closes the modal and
	# its config is released.
	var tower_left := _other_option_id(0, String(tower_choice["option"]))
	var upgrade_left := _other_option_id(1, String(upgrade_choice["option"]))
	check(tower_left != "" and upgrade_left != "", "each group offered an option that was not picked")
	# The boot releases the modal as soon as the grant lands, so the picks are
	# copied here: reading the modal after this click reads a freed object.
	var picks_at_confirm: Dictionary = _modal.picks()
	await _click_row(confirm_row, "left click on Confirm with both groups picked")

	# --- what the run holds now ---------------------------------------------
	check(not _flow.opening_pending(), "the run no longer reports the choice as pending")
	check(_boot.opening_modal() == null, "the boot released the modal once the grant landed")
	check(
		not is_instance_valid(_modal_ref) or not _modal_ref.is_open(),
		"the released modal is closed"
	)

	var towers: Array = _flow.inventory().towers()
	var upgrades: Array = _flow.inventory().upgrades()
	check_eq_int(_flow.inventory().tower_count(), 1, "the inventory holds exactly one tower")
	check_eq_int(_flow.inventory().upgrade_count(), 1, "the inventory holds exactly one upgrade")
	if not check(towers.size() == 1 and upgrades.size() == 1, "the inventory lists one tower and one upgrade"):
		return false
	check(
		String((towers[0] as RefCounted).type_id) == String(tower_choice["option"]),
		"the tower in hand is the one clicked: '%s'" % String((towers[0] as RefCounted).type_id)
	)
	check(
		String((upgrades[0] as RefCounted).type_id) == String(upgrade_choice["option"]),
		"the upgrade in hand is the one clicked: '%s'" % String((upgrades[0] as RefCounted).type_id)
	)
	check(
		String((towers[0] as RefCounted).type_id) != tower_left,
		"the tower left behind ('%s') was NOT granted" % tower_left
	)
	check(
		String((upgrades[0] as RefCounted).type_id) != upgrade_left,
		"the upgrade left behind ('%s') was NOT granted" % upgrade_left
	)

	# The map screen read the run's numbers before the grant; a snapshot that no
	# longer agrees with the session is refused by the screen itself, so the map
	# being usable again depends on this being fresh.
	var map_state: Dictionary = _map_screen.state()
	check(not bool(map_state["stale"]), "the map screen's numbers agree with the session: %s" % [map_state["mismatch"]])
	check_eq_int(int((map_state["shown"] as Dictionary).get("towers", -1)), 1, "the map screen shows one tower")

	print("CHOICE_DEMO_INVENTORY " + JSON.stringify({
		"case": "after_confirm",
		"picks": picks_at_confirm,
		"picked_tower": String(tower_choice["id"]),
		"picked_upgrade": String(upgrade_choice["id"]),
		"towers": _inventory_view()["towers"],
		"upgrades": _inventory_view()["upgrades"],
		"tower_count": _flow.inventory().tower_count(),
		"upgrade_count": _flow.inventory().upgrade_count(),
		"pending": _flow.opening_pending(),
		"state_line": String(map_state["label"]),
	}))
	return true


func _map_is_interactive_again() -> void:
	_case("a real click on the map now enters a node")

	# The modal is queued for deletion; give the frame a chance to finish it.
	await _settle()

	var target := _selectable_row()
	if not check(not target.is_empty(), "the map still offers a selectable row"):
		return
	if not check(_flow.map().selectable_nodes().has(int(target["id"])), "the aimed row is one of the next choices"):
		return

	var rect: Rect2 = (target["node"] as Control).get_global_rect()
	var point := rect.get_center()
	check(not _inside_any_modal_row(point), "no modal row is over the map any more")

	var route_before: Array = _flow.map().route()
	await _click(point, "left click on map row %d (%s)" % [int(target["index"]), String(target["type"])])

	var route_after: Array = _flow.map().route()
	check(route_after.size() == route_before.size() + 1, "the click moved the route by exactly one node: %s -> %s" % [route_before, route_after])
	check(route_after.has(int(target["id"])), "the route now contains the clicked node %d" % int(target["id"]))
	check(String(_map_screen.reason()) == "", "the map screen accepted the click instead of refusing it: '%s'" % String(_map_screen.reason()))
	check(_flow.map().route().size() == 1, "exactly one node was taken, not two: %s" % [_flow.map().route()])

	print("CHOICE_DEMO_INVENTORY " + JSON.stringify({
		"case": "after_map_click",
		"node": int(target["id"]),
		"type": String(target["type"]),
		"route_before": route_before,
		"route_after": route_after,
		"level_open": _flow.is_in_level(),
		"phase": _flow.phase_name(),
		"screens": _boot.screen_name(),
		"inventory": _inventory_view(),
	}))


# --- reading the run ---------------------------------------------------------

func _inventory_view() -> Dictionary:
	if _flow == null:
		return {}
	var towers: Array = []
	for tower in _flow.inventory().towers():
		towers.append({
			"type": String((tower as RefCounted).type_id),
			"tier": int((tower as RefCounted).tier),
		})
	var upgrades: Array = []
	for upgrade in _flow.inventory().upgrades():
		upgrades.append({"type": String((upgrade as RefCounted).type_id)})
	return {"towers": towers, "upgrades": upgrades}


func _screens_layer() -> Node:
	var path = _boot.screens_path
	if path == null or path.is_empty():
		return null
	return _boot.get_node_or_null(path)


## The first selectable row the map screen drew, with its Button, so a click can
## aim at a node the map would really accept.
func _selectable_row() -> Dictionary:
	for entry in _map_screen.rows():
		if bool((entry as Dictionary).get("selectable", false)) and entry.has("node"):
			return entry
	return {}


## Group `group_index`'s option at `option_index` (or its last option for -1), as
## `{group, option, id}` read off the modal's own config: the demo clicks a row, it
## does not call `choose()`.
func _group_option(group_index: int, option_index: int) -> Dictionary:
	var config: Dictionary = _modal.config()
	var groups: Array = config.get("groups", [])
	if group_index < 0 or group_index >= groups.size():
		return {}
	var group: Dictionary = groups[group_index]
	if option_index < 0:
		option_index = (group.get("options", []) as Array).size() - 1
	var options: Array = group.get("options", [])
	if option_index < 0 or option_index >= options.size():
		return {}
	var option: Dictionary = options[option_index]
	return {
		"group": String(group["id"]),
		"option": String(option["id"]),
		"label": String(option["label"]),
		"id": String(option["id"]),
	}


func _other_option(group_index: int) -> Dictionary:
	return _group_option(group_index, 0)


## The id in `group_index`'s offers that is not `picked_id`, or "" when the group
## offers nothing else. Read before the confirm, because closing releases the config.
func _other_option_id(group_index: int, picked_id: String) -> String:
	var config: Dictionary = _modal.config()
	var groups: Array = config.get("groups", [])
	if group_index < 0 or group_index >= groups.size():
		return ""
	for option in ((groups[group_index] as Dictionary).get("options", []) as Array):
		var id := String((option as Dictionary)["id"])
		if id != picked_id:
			return id
	return ""


func _modal_row_index(group_id: String, option_id: String) -> int:
	for entry in _modal.rows():
		if String(entry["kind"]) != "option":
			continue
		if String(entry["group"]) == group_id and String(entry["option"]) == option_id:
			return int(entry["idx"])
	return -1


func _confirm_row_index() -> int:
	for entry in _modal.rows():
		if String(entry["kind"]) == "confirm":
			return int(entry["idx"])
	return -1


func _inside_any_modal_row(point: Vector2) -> bool:
	if _modal == null or not is_instance_valid(_modal) or not _modal.is_open():
		return false
	for entry in _modal.rows():
		var node = _modal.row(int(entry["idx"])).get("node", null)
		if node == null or not (node is Control):
			continue
		if (node as Control).get_global_rect().has_point(point):
			return true
	return false


# --- pushing events the way the OS does -------------------------------------

func _press(keycode: int, what: String) -> void:
	print("CHOICE_DEMO_EVENT " + JSON.stringify({"device": "key", "key": OS.get_keycode_string(keycode), "what": what}))
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
	print("CHOICE_DEMO_EVENT " + JSON.stringify({
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


func _click_row(index: int, what: String) -> void:
	var node = _modal.row(index).get("node", null)
	if not (node is Control):
		# A missing button is a wiring fault, not a skipped click: record it.
		check(false, "modal row %d has a button to click (%s)" % [index, what])
		return
	await _click((node as Control).get_global_rect().get_center(), what)


func _settle(frames: int = SETTLE_FRAMES) -> void:
	await _hold(frames)


func _hold(frames: int) -> void:
	for _i in frames:
		await process_frame


# --- the acceptance frame ----------------------------------------------------

## `--frame=<path>`, as an engine arg or after `--`, so the same file is the demo
## and the frame without a second mode to keep in step.
func _frame_arg() -> String:
	for arg in _argv():
		var text := String(arg)
		if text.begins_with("--frame="):
			return text.trim_prefix("--frame=")
	return ""


func _is_movie() -> bool:
	for arg in OS.get_cmdline_args():
		if String(arg).begins_with("--write-movie"):
			return true
	return false


func _argv() -> Array:
	var out: Array = []
	out.append_array(OS.get_cmdline_args())
	out.append_array(OS.get_cmdline_user_args())
	return out


## The frame the human judges: taken after the renderer has finished a frame, and
## saved outside the repo.
##
## The headless renderer draws nothing and never emits `frame_post_draw`, so a
## `--frame=` request in that mode would wait forever for a frame that cannot
## exist. It is refused here instead of hanging, and refused *loudly*: an image
## that was not written must never be reported as one that was.
func _capture_frame(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("CHOICE_DEMO_FRAME " + JSON.stringify({
			"path": path,
			"saved": false,
			"size": [0, 0],
			"headless": true,
			"why": "the headless renderer draws nothing; run without --headless to capture a frame",
		}))
		check(false, "'%s' was NOT written: --headless renders no frame to capture" % path)
		return
	await RenderingServer.frame_post_draw
	var image: Image = null
	var texture := get_root().get_texture()
	if texture != null:
		image = texture.get_image()
	var saved := false
	var size := [0, 0]
	if image != null and not image.is_empty():
		size = [image.get_width(), image.get_height()]
		saved = image.save_png(path) == OK
	print("CHOICE_DEMO_FRAME " + JSON.stringify({
		"path": path,
		"saved": saved,
		"size": size,
		"headless": false,
		"open": _modal.is_open() if _modal != null and is_instance_valid(_modal) else false,
	}))
	check(saved, "the frame was written to '%s'" % path)


# --- reporting ---------------------------------------------------------------

func _case(label: String) -> void:
	print("CHOICE_DEMO_CASE " + label)


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


## Exactly one self-test line, last. A demo that recorded no checks fails, and so
## does one that stopped before its last case - an aborted coroutine must never
## read as a pass.
func _finish() -> void:
	if _checks == 0 and _failures.is_empty():
		_failures.append("the demo recorded no checks")
	if not _reached_end:
		_failures.append("the demo stopped before its last case: the run did not complete")

	var passed := _failures.is_empty()
	print("CHOICE_MODAL_SELF_TEST " + JSON.stringify({
		"name": "choice_modal_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
		"inventory": _inventory_view(),
		"pending": _flow.opening_pending() if _flow != null else null,
		"movie": _is_movie(),
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("CHOICE_MODAL_FAILURE " + f)
	quit(1)
