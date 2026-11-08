extends RefCounted

## The map screen's only door for input (T-0050).
##
## CONTRACT
## --------
## * Every action the map screen can perform is named here, as one of `Intent`.
##   A screen never reads an action or a button directly: it hands the event to
##   `intent_for()` and acts on the intent. That is what "gamepad-ready" means in
##   practice - the device is a property of the event, not a branch in the screen.
## * `intent_for()` is total: every event produces a result, and an event that
##   means nothing produces `Intent.NONE`. Nothing is asserted and nothing is
##   consumed here; this object only translates.
## * The action names are the game's own four - `game_focus_next`,
##   `game_focus_prev`, `game_confirm`, `game_dismiss` - declared in
##   `project.godot` with keyboard **and** joypad events, every event on device
##   -1 so any connected pad matches. They are deliberately not Godot's built-in
##   `ui_*` actions: measured in Godot 4.7.2, `ui_accept` and `ui_cancel` carry
##   keyboard events only, so a pad could move the focus here but could never
##   confirm or dismiss anything. Depending on that split would make the
##   charter's "playable on a gamepad" claim depend on which half of the UI a
##   screen happens to use.
## * Re-binding for a platform is an `InputMap` edit on those four names, never a
##   change in this file or in the screen - the reason the brief asks for one
##   abstraction.
## * A mouse click is translated to `Intent.CONFIRM` **with** a `pointer`
##   position, so the screen resolves "which row was clicked" and "which row is
##   confirmed" through the same call. A pointer device is thus a second source of
##   the same intent, never a second code path.
## * What a controller still needs beyond this router, and what is deliberately
##   absent: a stick axis is not bound - focus uses D-pad buttons so one press is
##   one step - and deadzone is therefore unused. The screen draws the focus ring
##   itself (`focus_marker`) and keeps it on a row that cannot be taken, which is
##   what lets a pad player ask a locked row why.
##
## The screen owns focus; this file knows nothing about rows, indices or state.

enum Intent { NONE, FOCUS_NEXT, FOCUS_PREV, CONFIRM, DISMISS }

const INTENT_NAMES: Array[String] = ["none", "focus_next", "focus_prev", "confirm", "dismiss"]

## Action names, in one table. See the header for why they are the game's own
## four rather than the built-in `ui_*` ones.
const ACTION_FOCUS_NEXT: StringName = &"game_focus_next"
const ACTION_FOCUS_PREV: StringName = &"game_focus_prev"
const ACTION_CONFIRM: StringName = &"game_confirm"
const ACTION_DISMISS: StringName = &"game_dismiss"

const DEVICE_MOUSE := "mouse"
const DEVICE_KEYBOARD := "keyboard"
const DEVICE_PAD := "joypad"
const DEVICE_SYNTHETIC := "synthetic"
const DEVICE_UNKNOWN := "unknown"


## The intent `event` carries: `{intent, name, device}` and, for a pointer press,
## `pointer` (the position in the viewport). Never null, never an error.
func intent_for(event: InputEvent) -> Dictionary:
	if event is InputEventMouseButton:
		return _mouse_intent(event as InputEventMouseButton)
	# InputEventAction (synthetic, and what a remapped device sends) answers
	# `is_action_pressed()` too, so a demo and a controller take the same path.
	if event.is_action_pressed(ACTION_CONFIRM):
		return _result(Intent.CONFIRM, _device_of(event))
	if event.is_action_pressed(ACTION_FOCUS_NEXT):
		return _result(Intent.FOCUS_NEXT, _device_of(event))
	if event.is_action_pressed(ACTION_FOCUS_PREV):
		return _result(Intent.FOCUS_PREV, _device_of(event))
	if event.is_action_pressed(ACTION_DISMISS):
		return _result(Intent.DISMISS, _device_of(event))
	return _result(Intent.NONE, _device_of(event))


func name_of(intent: int) -> String:
	if intent < 0 or intent >= INTENT_NAMES.size():
		return "unknown(%d)" % intent
	return INTENT_NAMES[intent]


## Every action name this router drives, for a demo or a settings screen to check
## the project's input map against.
func action_names() -> Array:
	return [ACTION_FOCUS_NEXT, ACTION_FOCUS_PREV, ACTION_CONFIRM, ACTION_DISMISS]


func _mouse_intent(event: InputEventMouseButton) -> Dictionary:
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return _result(Intent.NONE, DEVICE_MOUSE)
	var out := _result(Intent.CONFIRM, DEVICE_MOUSE)
	out["pointer"] = event.position
	return out


func _result(intent: int, device: String) -> Dictionary:
	return {"intent": intent, "name": name_of(intent), "device": device}


func _device_of(event: InputEvent) -> String:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return DEVICE_PAD
	if event is InputEventKey:
		return DEVICE_KEYBOARD
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return DEVICE_MOUSE
	if event is InputEventAction:
		return DEVICE_SYNTHETIC
	return DEVICE_UNKNOWN
