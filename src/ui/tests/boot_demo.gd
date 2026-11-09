extends SceneTree

## T-0052 DoD 2, 3, 4 and 5 - the menu and the boot flow, driven headlessly.
##
##     godot --headless --path . --script res://src/ui/tests/boot_demo.gd
##
## The demo drives the real `res://scenes/boot.tscn`, the real menu scene, the real
## map screen and the real arena. No mock screen and no mock session: the rows, the
## transitions and the printed evidence are the ones the player would get.
##
## Prints, in this order:
##   BOOT_DEMO_CASE {text}       one line per phase
##   BOOT_DEMO_MENU {json}       the menu's data and the rows it drew
##   BOOT_DEMO_FOCUS {json}      the intents the router produced, and where focus went
##   BOOT_DEMO_THIRD {json}      a third entry added at runtime: three rows, no code change
##   BOOT_DEMO_PLANTED_A {json}  Start Game removed from the data: one row, no phantom, no crash
##   BOOT_DEMO_EXIT {json}       Exit raised the quit path instead of doing nothing
##   BOOT_DEMO_START {json}      Start Game began a run and showed the map screen
##   BOOT_DEMO_AUTOSTART {json}  --autostart skipped the menu and opened a level
##   BOOT_DEMO_CYCLE {json}      level -> map -> menu when the run ended
##   BOOT_DEMO_SELF_TEST {json}  once, last; carries checks and failures
##
## The exit code is not evidence (L-035); `BOOT_DEMO_SELF_TEST` is. The
## `BOOT_*`, `MENU_*`, `MAPSCREEN_*`, `RUNFLOW_*` and `ARENA_*` lines around these
## are printed by the objects under test, not by this file.

const BOOT_SCENE := "res://scenes/boot.tscn"

## The seed the run in this demo is recorded against. A change here changes the
## map, so the evidence line prints the seed and the map's sha, not just "a run".
const SEED := 20261108

## Game time per wave-director tick while a level is played by hand: large enough
## that every tick with something queued spawns a unit.
const TICK_SECONDS := 10.0
## Guard so a wave that never finishes fails the demo instead of hanging it.
const MAX_WAVE_TICKS := 4000
const LETHAL_DAMAGE := 1000000

## The third entry DoD 2 adds at runtime. Its action is deliberately one nothing
## handles: the row must still draw, and the boot must say so rather than swallow
## it.
const THIRD_ENTRY := {"id": "settings", "label": "Settings", "action": "settings"}

var _boot = null
var _autostart_boot = null
var _configured: Array = []
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_boot_phase()


func _boot_phase() -> void:
	# Nothing is safe before the tree has iterated once.
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
	# Quitting the tree would end this demo before it reported. See the boot's
	# `set_quit_enabled_for_demo()`: the seam is named as what it is.
	_boot.set_quit_enabled_for_demo(false)
	root.add_child(_boot)
	await process_frame

	_case("the menu is data, and it lists exactly the configured entries")
	_check_menu()
	_case("focus moves, wraps, and a dismiss is accepted")
	_check_focus()
	_case("a third entry is one row, added at runtime")
	_check_third_entry()
	_case("planted failure A: Start Game removed from the data")
	_check_planted_a()
	_case("Exit raises the quit path")
	_check_exit()
	_case("Start Game begins a run and shows the map screen")
	_start_game()
	_case("--autostart skips the menu and opens a level")
	await _check_autostart()
	_case("level -> map -> menu when the run ends")
	await _check_cycle()

	_finish()


# --- DoD 2: the menu --------------------------------------------------------

func _check_menu() -> void:
	if not check(_boot.screen_name() == "menu", "the boot opens on the menu"):
		return
	var menu = _boot.menu()
	if not check(menu != null, "the boot instantiated its menu"):
		return
	check(menu.visible, "the menu is showing")
	check(_boot.map_screen() == null, "no map screen exists before a run starts")
	check(_boot.flow() == null, "no run session exists before a run starts")

	var data: Array = menu.get_entries()
	var ids: Array = menu.drawn_ids()
	_configured = data.duplicate(true)

	var shaped := true
	for entry in data:
		if not (entry is Dictionary):
			shaped = false
			continue
		for key in ["id", "label", "action"]:
			if not entry.has(key) or str(entry[key]) == "":
				shaped = false
	var labels: Array = []
	for row in menu.printable_rows():
		labels.append(String(row["label"]))
	var list = menu.get_node_or_null(menu.get("list_path"))

	print("BOOT_DEMO_MENU " + JSON.stringify({
		"entries": data,
		"ids": ids,
		"labels": labels,
		"rows": menu.row_count(),
		"list_children": list.get_child_count() if list != null else -1,
		"focus": menu.focus_index(),
		"screen": _boot.screen_name(),
	}))

	check_eq_int(data.size(), 2, "the menu's data holds two entries")
	check(ids == ["start", "exit"], "the rows are the entries, in data order: %s" % [ids])
	check_eq_int(menu.row_count(), data.size(), "one row per entry")
	check_eq_int(list.get_child_count() if list != null else -1, 2, "two rows are on screen")
	check(shaped, "every entry carries id, label and action")
	check(labels.has("Start Game"), "Start Game is one of the rows: %s" % [labels])
	check(labels.has("Exit"), "Exit is one of the rows: %s" % [labels])
	check_eq_int(menu.focus_index(), 0, "focus starts on the first row")
	var first = menu.row(0)
	check(
		first.has("node") and String(first["node"].text).begins_with(String(menu.get("focus_marker"))),
		"the focused row carries the focus marker"
	)


## DoD 2: "moving focus and confirming". Focus is moved with the same synthetic
## intent a keyboard or d-pad sends, through the same router the menu reads.
func _check_focus() -> void:
	var menu = _boot.menu()
	var start: int = menu.focus_index()
	var next: Dictionary = menu.handle_input(_action_event("game_focus_next"))
	var after_next: int = menu.focus_index()
	var wrapped: Dictionary = menu.handle_input(_action_event("game_focus_next"))
	var after_wrap: int = menu.focus_index()
	var back: Dictionary = menu.handle_input(_action_event("game_focus_prev"))
	var after_back: int = menu.focus_index()
	var dismissals_before: int = menu.dismissals()
	var dismiss: Dictionary = menu.handle_input(_action_event("game_dismiss"))

	print("BOOT_DEMO_FOCUS " + JSON.stringify({
		"start": start,
		"after_focus_next": after_next,
		"after_second_next": after_wrap,
		"after_focus_prev": after_back,
		"next": next,
		"second_next": wrapped,
		"prev": back,
		"dismiss": dismiss,
		"dismissals": menu.dismissals(),
	}))

	check(bool(next["applied"]), "focus_next is applied")
	check_eq_int(after_next, start + 1, "focus moved one row down")
	check_eq_int(after_wrap, 0, "focus wraps from the last row to the first")
	check(bool(back["applied"]), "focus_prev is applied")
	check_eq_int(after_back, menu.row_count() - 1, "focus_prev wraps backwards")
	check_eq_int(
		menu.dismissals(), dismissals_before + 1, "a dismiss is accepted and counted"
	)
	check(
		String(dismiss["name"]) == "dismiss",
		"the dismiss intent reached the menu through the router: %s" % [dismiss]
	)
	check_eq_int(menu.focus_index(), menu.row_count() - 1, "a dismiss does not move focus")


## DoD 2, last clause: a third entry is one more row, with no code change. Its
## action is one the boot does not handle, so the boot must report it rather than
## pretend the option worked.
func _check_third_entry() -> void:
	var menu = _boot.menu()
	var data: Array = _configured.duplicate(true)
	data.append(THIRD_ENTRY.duplicate(true))

	var effects_before: int = _boot.effects()
	var accepted: bool = menu.set_entries(data)
	var ids: Array = menu.drawn_ids()
	var list = menu.get_node_or_null(menu.get("list_path"))
	var third = menu.row(2)
	var activated: bool = menu.activate(2)
	var screen_after: String = _boot.screen_name()

	print("BOOT_DEMO_THIRD " + JSON.stringify({
		"accepted": accepted,
		"ids": ids,
		"rows": menu.row_count(),
		"list_children": list.get_child_count() if list != null else -1,
		"third_label": third.get("label", ""),
		"activated": activated,
		"effects_before": effects_before,
		"effects_after": _boot.effects(),
		"screen_after": screen_after,
	}))

	check(accepted, "the menu accepts a third entry at runtime")
	check_eq_int(menu.row_count(), 3, "the menu draws three rows")
	check_eq_int(list.get_child_count() if list != null else -1, 3, "three rows are on screen")
	check(ids == ["start", "exit", "settings"], "the third entry is the third row: %s" % [ids])
	check(String(third.get("label", "")) == "Settings", "the third row shows its own label")
	check(activated, "the third row can be confirmed")
	check_eq_int(_boot.effects(), effects_before, "an unhandled action is reported, not performed")
	check(screen_after == "menu", "an unhandled action leaves the screen alone")

	# Back to the configured two, so the cases after this one measure the shipped
	# menu and not the demo's.
	check(menu.set_entries(_configured.duplicate(true)), "the configured entries are restored")
	check_eq_int(menu.row_count(), 2, "the menu is back to two rows")


## DoD 4 / planted failure A: remove Start Game from the entry data. The menu must
## draw the remaining entry - not crash, and not keep a phantom row where Start
## Game was.
func _check_planted_a() -> void:
	var menu = _boot.menu()
	var only_exit: Array = []
	for entry in _configured:
		if String(entry["id"]) != "start":
			only_exit.append((entry as Dictionary).duplicate(true))
	if not check(only_exit.size() == 1, "the reduced data has exactly the Exit entry"):
		return

	var accepted: bool = menu.set_entries(only_exit)
	var list = menu.get_node_or_null(menu.get("list_path"))
	var ids: Array = menu.drawn_ids()
	var labels: Array = []
	for row in menu.printable_rows():
		labels.append(String(row["label"]))
	var texts: Array = []
	if list != null:
		for child in list.get_children():
			texts.append(String(child.text))

	var quit_before: int = _boot.quit_requests()
	var activated: bool = menu.activate(0)

	print("BOOT_DEMO_PLANTED_A " + JSON.stringify({
		"source_ids": [String(only_exit[0]["id"])],
		"accepted": accepted,
		"ids": ids,
		"labels": labels,
		"rows": menu.row_count(),
		"list_children": list.get_child_count() if list != null else -1,
		"texts": texts,
		"activated": activated,
		"quit_before": quit_before,
		"quit_after": _boot.quit_requests(),
	}))

	check(accepted, "the menu accepts data with Start Game removed")
	check_eq_int(menu.row_count(), 1, "one entry left means one row")
	check_eq_int(list.get_child_count() if list != null else -1, 1, "no phantom row is left on screen")
	check(ids == ["exit"], "the row that remains is Exit: %s" % [ids])
	check(labels == ["Exit"], "the remaining row shows its own label: %s" % [labels])
	check(
		not ids.has("start"),
		"no row is still called 'start': the removed entry left nothing behind"
	)
	check(activated, "the remaining row is live, not a dead line")
	check_eq_int(_boot.quit_requests(), quit_before + 1, "confirming it still raised its action")

	check(menu.set_entries(_configured.duplicate(true)), "the configured entries are restored")
	check_eq_int(menu.row_count(), 2, "the menu is back to two rows")


# --- DoD 2: the start path --------------------------------------------------

func _start_game() -> void:
	var menu = _boot.menu()
	var effects_before: int = _boot.effects()
	# Focus is put on Start Game with focus intents, never by calling the handler:
	# the point is that a player reaching it this way begins a run.
	while menu.focus_index() != 0:
		menu.handle_input(_action_event("game_focus_next"))
	var confirm: Dictionary = menu.handle_input(_action_event("game_confirm"))
	await process_frame

	var flow = _boot.flow()
	var screen = _boot.map_screen()
	var map_visible: bool = screen != null and screen.visible
	var rows: int = screen.row_count() if screen != null else 0

	print("BOOT_DEMO_START " + JSON.stringify({
		"intent": confirm.get("name", ""),
		"applied": bool(confirm.get("applied", false)),
		"entry": _boot.last_action(),
		"screen": _boot.screen_name(),
		"menu_visible": menu.visible,
		"map_visible": map_visible,
		"map_rows": rows,
		"phase": flow.phase_name() if flow != null else "",
		"seed": flow.map().seed_value() if flow != null else 0,
		"effects_before": effects_before,
		"effects_after": _boot.effects(),
	}))

	check(bool(confirm.get("applied", false)), "confirming Start Game is applied")
	check(_boot.last_action() == "start", "the entry's action was the boot's Start action")
	check_eq_int(_boot.effects(), effects_before + 1, "the action was handled exactly once")
	check(flow != null, "Start Game created a run session")
	check(flow != null and String(flow.phase_name()) == "on_map", "the run is on the map")
	check(flow != null and flow.run_state() != null and flow.run_state().is_in_progress(),
		"the run state is in progress")
	check(_boot.screen_name() == "map", "the boot's screen is the map")
	check(not menu.visible, "the menu hid itself when the run began")
	check(map_visible, "the map screen is showing")
	check(rows > 0, "the map screen drew the map's revealed nodes: %d row(s)" % rows)


## DoD 2 and planted failure B: Exit must raise the boot's quit path. The boot is
## told not to end the process (it would end this demo), so what is asserted is
## the request itself - a no-op Exit produces no request and fails here.
func _check_exit() -> void:
	var menu = _boot.menu()
	while menu.focus_index() != 1:
		menu.handle_input(_action_event("game_focus_next"))
	var quit_before: int = _boot.quit_requests()
	var effects_before: int = _boot.effects()
	var confirm: Dictionary = menu.handle_input(_action_event("game_confirm"))

	print("BOOT_DEMO_EXIT " + JSON.stringify({
		"intent": confirm.get("name", ""),
		"applied": bool(confirm.get("applied", false)),
		"entry": _boot.last_action(),
		"quit_before": quit_before,
		"quit_after": _boot.quit_requests(),
		"effects_before": effects_before,
		"effects_after": _boot.effects(),
		"screen": _boot.screen_name(),
	}))

	check(bool(confirm.get("applied", false)), "confirming Exit is applied")
	check(_boot.last_action() == "exit", "the entry's action was the boot's Exit action")
	check_eq_int(_boot.quit_requests(), quit_before + 1, "Exit raised the quit path")
	check_eq_int(_boot.effects(), effects_before + 1, "Exit is a handled action, not a no-op")
	check(_boot.screen_name() == "menu", "a quit request does not change the screen by itself")


# --- DoD 3: autostart -------------------------------------------------------

## A second boot instance told to autostart, the way `--autostart` tells it. It
## must skip the menu entirely and end up with a level open - the transaction the
## real command line performs is exercised end to end by the invocation recorded
## in the task's evidence.
func _check_autostart() -> void:
	var packed = load(BOOT_SCENE)
	_autostart_boot = packed.instantiate()
	_autostart_boot.run_seed = SEED
	_autostart_boot.autostart = true
	# Since T-0060 a level only auto-starts when `start_first_wave and autostart`
	# is the command line's `--autostart`; the boot sets it in `_parse_args`. This
	# demo bypasses `_parse_args`, so it sets both halves of that rule itself.
	_autostart_boot.start_first_wave = true
	_autostart_boot.set_quit_enabled_for_demo(false)
	root.add_child(_autostart_boot)
	await process_frame

	var flow = _autostart_boot.flow()
	var arena = flow.current_level() if flow != null else null
	var menu = _autostart_boot.menu()

	print("BOOT_DEMO_AUTOSTART " + JSON.stringify({
		"menu_instantiated": menu != null,
		"screen": _autostart_boot.screen_name(),
		"run": flow != null,
		"in_level": flow.is_in_level() if flow != null else false,
		"node": flow.level_node_id() if flow != null else -1,
		"level_index": flow.run_state().level_number() if flow != null else 0,
		"arena": arena != null,
		"wave_active": arena.is_wave_active() if arena != null else false,
	}))

	check(menu == null, "autostart never built the menu: the menu is skipped")
	check(flow != null, "autostart began a run")
	check(_autostart_boot.screen_name() == "level", "autostart opened a level")
	check(flow != null and flow.is_in_level(), "the session reports a level in play")
	check(arena != null, "the arena scene is the level that opened")
	check(arena != null and arena.is_wave_active(), "the level's first wave is running")


# --- the sequence: level -> map -> menu -------------------------------------

func _check_cycle() -> void:
	if not check(_autostart_boot.flow() != null, "the autostart run is still in progress"):
		return
	var flow = _autostart_boot.flow()
	var kills: int = await _play_level(flow)
	await process_frame

	var screen_after_level: String = _autostart_boot.screen_name()
	var map_screen = _autostart_boot.map_screen()
	var levels: int = flow.run_state().level_index()
	var in_level_after: bool = flow.is_in_level()

	print("BOOT_DEMO_CYCLE " + JSON.stringify({
		"phase": "after the level",
		"in_level": in_level_after,
		"levels_completed": levels,
		"kills": kills,
		"screen": screen_after_level,
		"map_visible": map_screen != null and map_screen.visible,
		"menu_visible": _autostart_boot.menu() != null and _autostart_boot.menu().visible,
	}))

	check(not in_level_after, "the level finished and control returned to the map")
	check_eq_int(levels, 1, "the completed level was counted once")
	check(screen_after_level == "map", "the boot is showing the map again")
	check(map_screen != null and map_screen.visible, "the map screen came back")

	# End the run the way a defeat would, without walking ten leaks: the state
	# owner ends the run, the session reports it, the boot returns to the menu.
	var defect: int = flow.run_state().damage_hq(1000000, "boot demo")
	await process_frame

	var menu = _autostart_boot.menu()
	print("BOOT_DEMO_CYCLE " + JSON.stringify({
		"phase": "after the run ended",
		"damage": defect,
		"screen": _autostart_boot.screen_name(),
		"run": _autostart_boot.flow() != null,
		"menu_visible": menu != null and menu.visible,
		"map": _autostart_boot.map_screen() != null,
	}))

	check(defect > 0, "the run took the damage that ends it")
	check(_autostart_boot.screen_name() == "menu", "the run ending brings the menu back")
	check(_autostart_boot.flow() == null, "the finished run's session was released")
	check(_autostart_boot.map_screen() == null, "the finished run's map screen was released")
	check(menu != null and menu.visible, "the menu is showing again")


# --- driving ----------------------------------------------------------------

## Plays the open level's waves to the end, killing every unit the tick it spawns.
## Copied in shape from `run_map_screen_demo.gd`, which is the same walk one level
## at a time; the boot is what is under test here, not the arena.
func _play_level(flow) -> int:
	var arena = flow.current_level()
	if not check(arena != null, "the session opened a level scene"):
		return 0
	var director = arena.wave_director()
	if not check(director != null, "the level has a wave director"):
		return 0
	if not director.is_active() and not director.is_level_complete():
		if not check(arena.start_wave(0), "the level's first wave starts"):
			return 0

	var paid := 0
	var ticks := 0
	while flow.is_in_level() and ticks < MAX_WAVE_TICKS:
		director.tick(TICK_SECONDS)
		ticks += 1
		for walker in director.walkers():
			if not walker.is_alive():
				continue
			paid += maxi(walker.gold_reward, 0)
			walker.take_damage(LETHAL_DAMAGE)
		if not flow.is_in_level():
			break
		if not director.is_active() and not director.is_level_complete():
			if not arena.start_wave(director.current_index() + 1):
				break
	check(not flow.is_in_level(), "the level finished inside %d ticks" % MAX_WAVE_TICKS)
	return paid


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


# --- reporting --------------------------------------------------------------

func _case(label: String) -> void:
	print("BOOT_DEMO_CASE " + label)


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
	print("BOOT_DEMO_SELF_TEST " + JSON.stringify({
		"name": "boot_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("BOOT_FAILURE " + f)
	quit(1)
