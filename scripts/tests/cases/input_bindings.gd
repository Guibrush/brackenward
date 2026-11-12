extends "res://scripts/tests/lib/suite.gd"

## Headless proof for the placement input map (T-0088): the two horizontal
## actions the controller placement mode needs exist as DATA, bound on both
## keyboard and pad, and the four menu actions from T-0051 are unchanged.
##
##     powershell -NoProfile -File scripts/tests/run.ps1 -Filter input_bindings
##
## The subject is `project.godot`'s `[input]` section as the engine loaded it,
## read through `InputMap` and nothing else: this case asserts the resolved map,
## not the file's text, so a binding that parses but does not register cannot
## pass. Pure data, so `_boot()` is replaced with a direct `run_case()` exactly
## as `systems_inventory.gd` does - no scene boots and no frame is awaited. The
## single `TEST_RESULT` line and the exit code still come from the inherited
## `_finish()`.
##
## What is asserted, per action in `EXPECTED_ACTIONS`:
##
##   * the action exists in the map;
##   * it carries exactly the physical keycodes and the exact pad button
##     indices in `EXPECTED_KEYS` / `EXPECTED_PAD_BUTTONS` - an exact set, so a
##     silent rebind, an extra convenience key, or a duplicate event fails;
##   * it carries both device kinds, which is the charter's "gamepad and
##     keyboard are equal ports": a menu action a pad cannot press is not bound;
##   * deadzone is 0.5, the engine default the T-0051 comment records.
##
## The existing four are checked with the same exactness, which is what makes
## "no silent rebind" a fact rather than a promise. The two new actions are
## checked further: every one of their events is a key or a pad BUTTON (no axis,
## so one press is one step) and every event is on device -1 (any connected pad).
##
## One `INPUT_ACTION` line per action prints its device kinds and its codes, so
## the report names the binding rather than only asserting it.

## The six menu/placement actions this project owns. Up and down stay on the
## focus pair; the horizontal pair is what T-0088 adds.
const EXPECTED_ACTIONS: Array[String] = [
	"game_focus_next",
	"game_focus_prev",
	"game_confirm",
	"game_dismiss",
	"game_move_left",
	"game_move_right",
]

## `physical_keycode` values each action must carry, exactly. Literals rather
## than `KEY_*` constants so the numbers in `project.godot`, the brief and this
## case can be compared by eye: 4194305 Escape, 4194309 Enter, 4194319 Left,
## 4194320 Up, 4194321 Right, 4194322 Down, 32 Space, 65 A, 68 D.
const EXPECTED_KEYS := {
	"game_focus_next": [4194322],
	"game_focus_prev": [4194320],
	"game_confirm": [4194309, 32],
	"game_dismiss": [4194305],
	"game_move_left": [4194319, 65],
	"game_move_right": [4194321, 68],
}

## `button_index` values each action must carry, exactly. 0 pad-A/cross, 1
## pad-B/circle, 11 D-pad up, 12 D-pad down, 13 D-pad left, 14 D-pad right.
const EXPECTED_PAD_BUTTONS := {
	"game_focus_next": [12],
	"game_focus_prev": [11],
	"game_confirm": [0],
	"game_dismiss": [1],
	"game_move_left": [13],
	"game_move_right": [14],
}

## The actions T-0088 adds; only these get the axis and device assertions.
const NEW_ACTIONS: Array[String] = ["game_move_left", "game_move_right"]

const DEADZONE := 0.5
const ANY_DEVICE := -1


func case_name() -> String:
	return "input: placement actions bind keyboard and pad, the menu four unchanged"


## Pure data, so there is no arena to boot: this replaces the harness's scene
## load with the case itself. The result line, the exit code and the zero-check
## guard are still the base's `_finish()`.
func _boot() -> void:
	run_case()
	_finish()


func run_case() -> void:
	for action in EXPECTED_ACTIONS:
		_prove_action(action)


# --- one action ---------------------------------------------------------------

func _prove_action(action: String) -> void:
	if not check(InputMap.has_action(action), "%s exists in the input map" % action):
		# Reading events of a missing action would print an engine ERROR: line,
		# which the runner treats as a contradiction of a pass; say it once here
		# instead and move on to the next action.
		return

	var events := InputMap.action_get_events(action)
	var keys := _physical_keycodes(events)
	var pads := _pad_buttons(events)
	var expected_keys: Array = EXPECTED_KEYS[action].duplicate()
	var expected_pads: Array = EXPECTED_PAD_BUTTONS[action].duplicate()
	# The const tables are written in the brief's order (Left then A); the actual
	# arrays are sorted, so sort the expectations rather than demand an order the
	# input map does not promise.
	expected_keys.sort()
	expected_pads.sort()

	# Both ports, explicitly: this is the point of the binding, not a bonus.
	check(keys.size() > 0, "%s carries at least one InputEventKey" % action)
	check(pads.size() > 0, "%s carries at least one InputEventJoypadButton" % action)

	# Exact sets: sorted and compared whole, so an extra key, a duplicate event
	# or a swapped code fails here instead of going unnoticed.
	check(
		keys == expected_keys,
		"%s carries exactly the physical keys %s (got %s)" % [action, str(expected_keys), str(keys)]
	)
	check(
		pads == expected_pads,
		"%s carries exactly the pad buttons %s (got %s)" % [action, str(expected_pads), str(pads)]
	)
	check(
		is_equal_approx(InputMap.action_get_deadzone(action), DEADZONE),
		"%s deadzone is %.1f (got %.3f)" % [action, DEADZONE, InputMap.action_get_deadzone(action)]
	)

	if NEW_ACTIONS.has(action):
		# No axis on the placement pair: a stick would move the cursor by an
		# amount, and a placement cursor needs one press to be one tile.
		check_eq_int(
			_axis_count(events), 0, "%s binds no joypad axis (one press is one step)" % action
		)
		check(
			keys.size() + pads.size() == events.size(),
			"%s carries only key and pad-button events (%d events, %d counted)"
			% [action, events.size(), keys.size() + pads.size()]
		)
		var off_device := _events_not_on_device(events, ANY_DEVICE)
		check_eq_int(
			off_device, 0, "%s events are all on device %d (any connected pad)" % [action, ANY_DEVICE]
		)

	var devices := _device_kinds(keys, pads, _axis_count(events))
	print("INPUT_ACTION " + JSON.stringify({
		"action": action,
		"devices": devices,
		"physical_keys": keys,
		"pad_buttons": pads,
		"deadzone": InputMap.action_get_deadzone(action),
		"events": events.size(),
	}))
	check(devices == "keyboard+joypad", "%s reports both device kinds (got %s)" % [action, devices])


# --- helpers ------------------------------------------------------------------

## Physical keycodes of the key events, sorted. Physical rather than logical
## because that is what `project.godot` binds: A is the same key on AZERTY.
func _physical_keycodes(events: Array) -> Array:
	var codes: Array = []
	for event in events:
		if event is InputEventKey:
			codes.append(int((event as InputEventKey).physical_keycode))
	codes.sort()
	return codes


func _pad_buttons(events: Array) -> Array:
	var buttons: Array = []
	for event in events:
		if event is InputEventJoypadButton:
			buttons.append(int((event as InputEventJoypadButton).button_index))
	buttons.sort()
	return buttons


func _axis_count(events: Array) -> int:
	var count := 0
	for event in events:
		if event is InputEventJoypadMotion:
			count += 1
	return count


func _events_not_on_device(events: Array, device: int) -> int:
	var count := 0
	for event in events:
		if int(event.device) != device:
			count += 1
	return count


## "keyboard+joypad", "keyboard", "joypad" or "none", plus "+axis" when a stick
## event is bound. Built from the events actually present, never from the action
## name, so the printed line can disagree with the intent.
func _device_kinds(keys: Array, pads: Array, axes: int) -> String:
	var kinds: Array[String] = []
	if keys.size() > 0:
		kinds.append("keyboard")
	if pads.size() > 0 or axes > 0:
		kinds.append("joypad")
	if kinds.is_empty():
		return "none"
	var text := ""
	for kind in kinds:
		if text != "":
			text += "+"
		text += kind
	if axes > 0:
		text += "+axis"
	return text
