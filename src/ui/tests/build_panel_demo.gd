extends SceneTree

## T-0057 DoD 2, 3, 4 and 5 - the build panel, driven headlessly, in one run.
##
##     godot --headless --path . --script res://src/ui/tests/build_panel_demo.gd
##
## The demo drives the real arena (`res://scenes/main.tscn`), the real panel that
## ships inside it, the real `RunState` and the real `Inventory`. No mock panel and
## no mock arena: the rows, the numbers and the refusal sentences are the ones a
## player would see.
##
## Prints, in this order:
##   BUILD_PANEL_CASE {text}        one line per phase
##   BUILD_PANEL_ROWS {json}        the list against the inventory, before anything moves
##   BUILD_PANEL_STATE {json}       the always-visible line against RunState
##   BUILD_PANEL_INPUT {json}       the intents the router produced, per device
##   BUILD_PANEL_POSITIVE {json}    arm -> place -> upgrade -> take back, with the gold ledger
##   BUILD_PANEL_PLANTED_A {json}   placing with nothing armed: refused here, never asked of
##                                  the arena, gold and towers unchanged
##   BUILD_PANEL_PLANTED_B {json}   upgrading during a wave: refused with the arena's own
##                                  reason, gold unchanged
##   BUILD_PANEL_PLANTED_C {json}   upgrading without the gold: refused, gold unchanged
##   BUILD_PANEL_SELF_TEST {json}   once, last; carries checks and failures
##
## The exit code is not evidence (L-035); `BUILD_PANEL_SELF_TEST` is. The
## `BUILD_PANEL_SHOWN`/`_SELECT`/`_PLACED`/... lines are the panel's own, and
## `ARENA_*` lines belong to the arena under test.

const ARENA_SCENE := "res://scenes/main.tscn"
const RunStateScript := preload("res://src/systems/run_state.gd")
const InventoryScript := preload("res://src/systems/inventory.gd")
const MapInputScript := preload("res://src/ui/map_input.gd")

## Row kinds, spelled as the panel spells them. Duplicated here on purpose: a demo
## that reads its constants off the panel under test cannot catch the panel
## renaming them.
const KIND_TOWER := "tower"
const KIND_UPGRADE := "upgrade"
const KIND_TAKE_BACK := "take_back"

## The run this level is part of: enough gold to buy one upgrade (60) and still be
## short of a second, so the shortfall in planted failure C is a real number.
const STARTING_GOLD := 500
const STARTING_HQ := 10
## What gold is drained to before planted failure C: below the 60 gold tier-1
## upgrade, and not zero, so "refused for want of gold" cannot be confused with
## "refused because there is no economy left".
const SHORT_GOLD := 5

var _run = null
var _inventory = null
var _arena = null
var _panel = null
var _router = null
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# Nothing is safe before the tree has iterated once.
	await process_frame

	_run = RunStateScript.new()
	if not check(_run.start(STARTING_HQ, STARTING_GOLD), "the run starts with %d gold" % STARTING_GOLD):
		_finish()
		return
	_inventory = InventoryScript.new()
	var first = _inventory.add_tower("arrow")
	var second = _inventory.add_tower("arrow")
	if not check(first != null and second != null, "the inventory holds two towers"):
		_finish()
		return
	var upgrade = _inventory.add_upgrade("piercer")
	if not check(upgrade != null, "an upgrade is in hand"):
		_finish()
		return
	check(
		_inventory.apply_upgrade_to_tower(second.id, upgrade.id),
		"the second tower carries an equipped upgrade: %s" % [_inventory.last_refusal()]
	)

	var packed = load(ARENA_SCENE)
	if not check(packed != null, "the arena scene loads"):
		_finish()
		return
	_arena = packed.instantiate()
	if not check(_arena != null, "the arena scene instantiates"):
		_finish()
		return
	# Bound before the node enters the tree, which is the arena's documented order.
	if not check(_arena.bind_run(_run, _inventory), "the arena accepts the run and the inventory"):
		_finish()
		return
	root.add_child(_arena)
	await process_frame

	_panel = _arena.get_node_or_null("BuildPanel")
	if not check(_panel != null, "the panel ships inside the level scene"):
		_finish()
		return
	# The panel auto-binds to its parent arena in `_ready`; binding again is the
	# documented idempotent case and makes the demo independent of scene wiring.
	check(_panel.bind_arena(_arena), "the panel binds to the arena")
	check(_panel.arena() == _arena, "the panel is bound to this arena")
	check(_panel.visible, "the panel is showing over the level")
	_panel.refresh(true)
	await process_frame

	_router = MapInputScript.new()

	_case("the list, the state line, and the input route")
	_check_rows()
	_check_state()
	_check_input()

	_case("the positive path: arm, place, upgrade, take back")
	_check_positive_path()

	_case("planted failure A: placing with nothing armed")
	_planted_failure_a()

	_case("planted failure B: upgrading during a wave")
	_planted_failure_b()

	_case("planted failure C: upgrading without the gold")
	_planted_failure_c()

	_finish()


# --- the list ---------------------------------------------------------------

## DoD 1: every tower the player owns is listed, with its tier and its equipped
## upgrades, and the list says which of them is already on a tile.
func _check_rows() -> void:
	var rows: Array = _panel.rows()
	var inventory_towers: Array = _inventory.towers()
	var ids: Array = []
	for entry in rows:
		ids.append(int(entry["id"]))

	var counts: Dictionary = {}
	for entry in rows:
		counts[String(entry["kind"])] = int(counts.get(String(entry["kind"]), 0)) + 1

	var tiers_ok := true
	var upgrades_ok := true
	var labels_ok := true
	for entry in rows:
		var instance = _inventory.find_tower(int(entry["id"]))
		if instance == null:
			tiers_ok = false
			continue
		if int(entry["tier"]) != int(instance.tier):
			tiers_ok = false
		if (entry["upgrades"] as Array) != instance.upgrade_type_ids():
			upgrades_ok = false
		if String(entry["label"]) == "":
			labels_ok = false

	print("BUILD_PANEL_ROWS " + JSON.stringify({
		"rows": _printable_rows(rows),
		"count": rows.size(),
		"inventory": inventory_towers.size(),
		"kinds": counts,
		"armed": _panel.armed_instance(),
		"selected": _panel.selected_instance(),
	}))
	check_eq_int(rows.size(), inventory_towers.size(), "one row per owned tower, and nothing else yet")
	check(ids == [int(inventory_towers[0].id), int(inventory_towers[1].id)], "the rows are the inventory's towers, in order")
	check(tiers_ok, "every row shows the instance's tier")
	check(upgrades_ok, "every row shows the upgrades the instance carries")
	check(labels_ok, "every row has text")
	var second: Dictionary = rows[1]
	check(
		(second["upgrades"] as Array).size() == 1,
		"the tower with an equipped upgrade lists it: %s" % [second["upgrades"]]
	)
	check(
		String(second["label"]).find("piercer") != -1,
		"the upgrade is named in the row: %s" % second["label"]
	)
	check(not bool(second["placed"]), "a tower in hand is not marked as placed")
	check_eq_int(int(counts.get(KIND_UPGRADE, 0)), 0, "no action rows before a tower is placed")


## DoD 4 (the always-visible half): gold, HQ current/max and the phase, read from
## the run and the arena, and actually on the label the player sees.
func _check_state() -> void:
	var st: Dictionary = _panel.state()
	var label = _panel.get_node_or_null(_panel.state_path)
	var on_screen := "" if label == null else String(label.text)

	print("BUILD_PANEL_STATE " + JSON.stringify({
		"state": st,
		"on_screen": on_screen,
		"run": _run.snapshot(),
		"arena_gold": _arena.gold(),
		"phase": _arena.phase_name(),
	}))
	check_eq_int(int(st["gold"]), _run.gold(), "the gold shown is the run's")
	check_eq_int(int(st["gold"]), _arena.gold(), "the gold shown is the arena's balance")
	check_eq_int(int(st["hq"]), _run.hq_health(), "the HQ shown is the run's")
	check_eq_int(int(st["hq_max"]), _run.hq_max_health(), "the HQ maximum shown is the run's")
	check(String(st["phase"]) == _arena.phase_name(), "the phase shown is the arena's")
	check(on_screen == String(st["label"]), "the label on screen is the state the panel reports")
	check(on_screen.find("Gold %d" % _run.gold()) != -1, "the state line names the gold: %s" % on_screen)
	check(
		on_screen.find("%d/%d" % [_run.hq_health(), _run.hq_max_health()]) != -1,
		"the state line names HQ current/max: %s" % on_screen
	)
	check(on_screen.find(_arena.phase_name()) != -1, "the state line names the phase: %s" % on_screen)


## DoD 5: input comes through `MapInput`, and the actions the router names carry a
## keyboard and a joypad binding, so a pad is reachable by construction.
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

	# Focus moves through the same door a d-pad uses; dismiss is what un-arms a
	# placement the player started and does not want.
	var focus_before: int = _panel.focus_index()
	var moved: Dictionary = _panel.handle_input(_action_event(MapInputScript.ACTION_FOCUS_NEXT))
	var focus_after: int = _panel.focus_index()
	_panel.activate(0)
	var armed_before: int = _panel.armed_instance()
	_panel.handle_input(_action_event(MapInputScript.ACTION_DISMISS))
	var armed_after: int = _panel.armed_instance()

	print("BUILD_PANEL_INPUT " + JSON.stringify({
		"confirm": confirm,
		"focus_next": next,
		"focus_prev": prev,
		"dismiss": dismiss,
		"mouse": mouse,
		"actions": names,
		"keyboard_missing": key_missing,
		"joypad_missing": pad_missing,
		"focus_before": focus_before,
		"focus_after": focus_after,
		"focus_applied": moved.get("applied", false),
		"armed_before_dismiss": armed_before,
		"armed_after_dismiss": armed_after,
	}))
	check(int(confirm["intent"]) == MapInputScript.Intent.CONFIRM, "game_confirm is CONFIRM")
	check(int(next["intent"]) == MapInputScript.Intent.FOCUS_NEXT, "game_focus_next is FOCUS_NEXT")
	check(int(prev["intent"]) == MapInputScript.Intent.FOCUS_PREV, "game_focus_prev is FOCUS_PREV")
	check(int(dismiss["intent"]) == MapInputScript.Intent.DISMISS, "game_dismiss is DISMISS")
	check(
		int(mouse["intent"]) == MapInputScript.Intent.CONFIRM and mouse.has("pointer"),
		"a left click is CONFIRM carrying the pointer position"
	)
	check(key_missing.is_empty(), "every action the panel names carries a keyboard binding: %s" % [key_missing])
	check(pad_missing.is_empty(), "every action the panel names carries a joypad binding: %s" % [pad_missing])
	check(bool(moved.get("applied", false)), "a focus intent moves the focus")
	check(focus_after != focus_before or _panel.row_count() == 1, "the focus actually moved")
	check(armed_before != -1, "selecting an in-hand tower arms it")
	check_eq_int(armed_after, -1, "dismiss un-arms the placement")


# --- the positive path ------------------------------------------------------

## DoD 2: arm, place (free), upgrade (gold falls by the cost), take back (tile
## free, instance back in the inventory at its tier).
func _check_positive_path() -> void:
	var tower_id := int(_inventory.towers()[0].id)
	var row := _row_for_kind(KIND_TOWER, tower_id)
	if not check(row != -1, "the first tower has a row"):
		return

	var armed_ok: bool = _panel.activate(row)
	var armed: int = _panel.armed_instance()
	check(armed_ok, "selecting an in-hand tower is applied")
	check_eq_int(armed, tower_id, "the tower is armed for placement")

	var slot := _first_free_slot()
	if not check(not slot.is_empty(), "the level has a free build tile"):
		return
	var gold_before: int = _arena.gold()
	var free_before: int = _arena.free_slot_count()
	var placed: bool = _panel.place_at(slot["position"])
	var tower = _arena.tower_for_instance(tower_id)

	print("BUILD_PANEL_POSITIVE " + JSON.stringify({
		"case": "place",
		"tower": tower_id,
		"tile": String(slot["name"]),
		"placed": placed,
		"towers_on_board": _arena.towers().size(),
		"gold_before": gold_before,
		"gold": _arena.gold(),
		"free_before": free_before,
		"free": _arena.free_slot_count(),
		"armed": _panel.armed_instance(),
		"instance_placed": bool(_inventory.find_tower(tower_id).placed),
		"instance_location": String(_inventory.find_tower(tower_id).location),
	}))
	check(placed, "the armed tower is placed")
	check(tower != null, "the placed tower is on the board")
	check_eq_int(_arena.towers().size(), 1, "one tower on the board")
	check_eq_int(_arena.gold(), gold_before, "placement is free: gold unchanged")
	check_eq_int(_arena.free_slot_count(), free_before - 1, "the tile is taken")
	check_eq_int(_panel.armed_instance(), -1, "the arm is spent by the placement")
	check(bool(_inventory.find_tower(tower_id).placed), "the instance is marked placed")

	# Selecting the placed tower offers its actions.
	var placed_row := _row_for_kind(KIND_TOWER, tower_id)
	_panel.activate(placed_row)
	check_eq_int(_panel.armed_instance(), -1, "selecting a placed tower does not arm placement")
	check_eq_int(_panel.selected_instance(), tower_id, "the placed tower is selected")
	var upgrade_row := _row_for_kind(KIND_UPGRADE, tower_id)
	var take_back_row := _row_for_kind(KIND_TAKE_BACK, tower_id)
	check(upgrade_row != -1, "a placed tower offers an upgrade")
	check(take_back_row != -1, "a placed tower offers taking back")
	var cost: int = tower.upgrade_cost()
	check(
		upgrade_row != -1 and String(_panel.row(upgrade_row)["label"]).find(str(cost)) != -1,
		"the upgrade row names its price: %s" % [cost]
	)

	gold_before = _arena.gold()
	var tier_before: int = tower.tier()
	var upgraded: bool = _panel.upgrade_selected()

	print("BUILD_PANEL_POSITIVE " + JSON.stringify({
		"case": "upgrade",
		"tower": tower_id,
		"upgraded": upgraded,
		"tier_before": tier_before,
		"tier": tower.tier(),
		"instance_tier": int(_inventory.find_tower(tower_id).tier),
		"cost": cost,
		"gold_before": gold_before,
		"gold": _arena.gold(),
	}))
	check(upgraded, "the upgrade is bought")
	check_eq_int(tower.tier(), tier_before + 1, "the tower node is one tier higher")
	check_eq_int(int(_inventory.find_tower(tower_id).tier), tier_before + 1, "the instance carries the tier")
	check_eq_int(_arena.gold(), gold_before - cost, "gold fell by the upgrade's cost")

	free_before = _arena.free_slot_count()
	gold_before = _arena.gold()
	var taken_back: bool = _panel.take_back_selected()
	var after = _inventory.find_tower(tower_id)

	print("BUILD_PANEL_POSITIVE " + JSON.stringify({
		"case": "take_back",
		"tower": tower_id,
		"taken_back": taken_back,
		"towers_on_board": _arena.towers().size(),
		"instance_placed": bool(after.placed),
		"instance_tier": int(after.tier),
		"instance_upgrades": after.upgrade_type_ids(),
		"free_before": free_before,
		"free": _arena.free_slot_count(),
		"gold_before": gold_before,
		"gold": _arena.gold(),
		"selected": _panel.selected_instance(),
	}))
	check(taken_back, "the tower is taken back")
	check_eq_int(_arena.towers().size(), 0, "the board is empty again")
	check_eq_int(_arena.free_slot_count(), free_before + 1, "the tile is free again")
	check(not bool(after.placed), "the instance is back in the inventory")
	check_eq_int(int(after.tier), tier_before + 1, "it comes back at the tier it reached")
	check_eq_int(_arena.gold(), gold_before, "taking back moves no gold")
	check_eq_int(_panel.selected_instance(), -1, "nothing is selected after taking back")


# --- planted failures -------------------------------------------------------

## DoD 3. Placing with nothing armed is refused by the panel, with a printed
## reason, and never reaches the arena: its refusal count, gold and tower count are
## all unchanged.
func _planted_failure_a() -> void:
	var slot := _first_free_slot()
	if not check(not slot.is_empty(), "a free tile is still available"):
		return
	check_eq_int(_panel.armed_instance(), -1, "nothing is armed")
	var refusals_before: int = _arena.refused_count()
	var gold_before: int = _arena.gold()
	var free_before: int = _arena.free_slot_count()

	var placed: bool = _panel.place_at(slot["position"])

	print("BUILD_PANEL_PLANTED_A " + JSON.stringify({
		"armed": _panel.armed_instance(),
		"placed": placed,
		"reason": _panel.reason(),
		"arena_refusals_before": refusals_before,
		"arena_refusals": _arena.refused_count(),
		"towers": _arena.towers().size(),
		"free_before": free_before,
		"free": _arena.free_slot_count(),
		"gold_before": gold_before,
		"gold": _arena.gold(),
		"phase": _arena.phase_name(),
	}))
	check(not placed, "placing with nothing armed is refused")
	check(String(_panel.reason()) != "", "the refusal has a printed reason")
	check(
		String(_panel.reason()) == String(_panel.nothing_armed_text),
		"the reason names the mistake: nothing is armed"
	)
	check_eq_int(_arena.refused_count(), refusals_before, "the refusal never reached the arena")
	check_eq_int(_arena.towers().size(), 0, "no tower appeared")
	check_eq_int(_arena.free_slot_count(), free_before, "no tile was taken")
	check_eq_int(_arena.gold(), gold_before, "no gold moved")


## DoD 4. A wave locks the build phase. The upgrade is asked for, refused by the
## arena with its own sentence, and the gold does not move.
func _planted_failure_b() -> void:
	var tower_id := int(_inventory.towers()[0].id)
	var slot := _first_free_slot()
	if not check(not slot.is_empty(), "a free tile is available for the wave test"):
		return
	var in_hand_row := _row_for_kind(KIND_TOWER, tower_id)
	if not check(in_hand_row != -1, "the in-hand tower has a row"):
		return
	_panel.activate(in_hand_row)
	if not check(_panel.place_at(slot["position"]), "a tower is placed before the wave"):
		return
	_panel.activate(_row_for_kind(KIND_TOWER, tower_id))
	var tower = _arena.tower_for_instance(tower_id)
	if not check(tower != null, "the placed tower is selectable"):
		return

	# A real wave, started by the arena: the phase is the wave phase and the
	# director is live. The demo never ticks it, so nothing spawns on the lane.
	var wave_ok: bool = _arena.start_wave(0)
	check(wave_ok, "the first wave starts")
	check(_arena.is_wave_active(), "the arena is in the wave phase")
	var phase_state: Dictionary = _panel.state()

	var refusals_before: int = _arena.refused_count()
	var gold_before: int = _arena.gold()
	var tier_before: int = tower.tier()
	var upgraded: bool = _panel.upgrade_selected()

	print("BUILD_PANEL_PLANTED_B " + JSON.stringify({
		"phase": _arena.phase_name(),
		"state": phase_state["label"],
		"upgraded": upgraded,
		"reason": _panel.reason(),
		"arena_reason": _arena.last_refusal(),
		"same_sentence": String(_panel.reason()) == String(_arena.last_refusal()),
		"arena_refusals_before": refusals_before,
		"arena_refusals": _arena.refused_count(),
		"tier_before": tier_before,
		"tier": tower.tier(),
		"gold_before": gold_before,
		"gold": _arena.gold(),
	}))
	check(String(phase_state["phase"]) == _arena.phase_name(), "the panel names the wave phase")
	check(String(phase_state["label"]).find("wave") != -1, "the state line says it is the wave phase")
	check(not upgraded, "upgrading during a wave is refused")
	check(
		String(_panel.reason()) == String(_arena.last_refusal()),
		"the refusal is the arena's own sentence, not a new one"
	)
	check(
		String(_panel.reason()).find("locked during a wave") != -1,
		"the reason says the build is locked: %s" % _panel.reason()
	)
	check_eq_int(_arena.refused_count(), refusals_before + 1, "the refusal came from the arena")
	check_eq_int(tower.tier(), tier_before, "the tower did not gain a tier")
	check_eq_int(_arena.gold(), gold_before, "no gold was spent")

	# Back to the build phase for the last planted failure.
	_arena.end_wave()
	check(not _arena.is_wave_active(), "the wave is over and the build phase is back")


## DoD 5. Enough gold is drained that the 60 gold upgrade cannot be paid for. The
## arena refuses with its own reason and the balance is untouched - a refused
## upgrade must not part-charge.
func _planted_failure_c() -> void:
	var tower_id := int(_selected_placed_id())
	var tower = _arena.tower_for_instance(tower_id)
	if not check(tower != null, "the placed tower is selected for the shortfall test"):
		return
	var cost: int = tower.upgrade_cost()
	var drain: int = _arena.gold() - SHORT_GOLD
	if drain > 0:
		check(_run.spend_gold(drain, "demo: drain the wallet to prove the shortfall"), "the wallet is drained")
	_panel.refresh()

	var refusals_before: int = _arena.refused_count()
	var gold_before: int = _arena.gold()
	var tier_before: int = tower.tier()
	var upgraded: bool = _panel.upgrade_selected()

	print("BUILD_PANEL_PLANTED_C " + JSON.stringify({
		"gold_at_start": gold_before,
		"cost": cost,
		"upgraded": upgraded,
		"reason": _panel.reason(),
		"arena_reason": _arena.last_refusal(),
		"arena_refusals_before": refusals_before,
		"arena_refusals": _arena.refused_count(),
		"tier_before": tier_before,
		"tier": tower.tier(),
		"gold": _arena.gold(),
	}))
	check_eq_int(gold_before, SHORT_GOLD, "the wallet is below the upgrade's price")
	check_not_affordable(gold_before, cost)
	check(not upgraded, "upgrading without the gold is refused")
	check(
		String(_panel.reason()).find("not enough gold") != -1,
		"the reason says the gold is short: %s" % _panel.reason()
	)
	check_eq_int(_arena.refused_count(), refusals_before + 1, "the refusal came from the arena")
	check_eq_int(tower.tier(), tier_before, "the tower did not gain a tier")
	check_eq_int(_arena.gold(), gold_before, "the refused upgrade took no gold")


# --- helpers ----------------------------------------------------------------

func _selected_placed_id() -> int:
	var selected: int = _panel.selected_instance()
	if selected != -1:
		return selected
	var placed: Array = _arena.towers()
	if placed.is_empty():
		return -1
	return int(placed[0].instance.id)


func _row_for_kind(kind: String, instance_id: int) -> int:
	var rows: Array = _panel.rows()
	for i in rows.size():
		if String(rows[i]["kind"]) == kind and int(rows[i]["id"]) == instance_id:
			return i
	return -1


func _first_free_slot() -> Dictionary:
	for slot in _arena.build_slots():
		if bool(slot["free"]):
			return slot
	return {}


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


## The rows with their Button references dropped: a node is not JSON.
func _printable_rows(rows: Array) -> Array:
	var out: Array = []
	for entry in rows:
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		copy.erase("node")
		out.append(copy)
	return out


func _has_joypad_binding(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


func _has_keyboard_binding(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return true
	return false


# --- reporting --------------------------------------------------------------

func _case(label: String) -> void:
	print("BUILD_PANEL_CASE " + label)


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


func check_not_affordable(gold: int, cost: int) -> bool:
	_checks += 1
	if gold >= cost:
		_failures.append("gold %d is not below the cost %d" % [gold, cost])
		return false
	return true


## Exactly one self-test line, last. A demo that recorded no checks fails.
func _finish() -> void:
	if _checks == 0 and _failures.is_empty():
		_failures.append("the demo recorded no checks")

	var passed := _failures.is_empty()
	print("BUILD_PANEL_SELF_TEST " + JSON.stringify({
		"name": "build_panel_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("BUILD_PANEL_FAILURE " + f)
	quit(1)
