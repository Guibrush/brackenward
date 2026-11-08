extends Control

## The main menu (T-0052): the game's first screen.
##
## CONTRACT
## --------
## * **The menu is data.** `entries` is the whole menu: a list of
##   `{id, label, action}` rows, drawn in order. Nothing in this file names a
##   row or knows what a row means: the screen draws the list and reports which
##   entry was confirmed, and `action` is an opaque string the owner interprets
##   (the boot scene is the owner; `_handlers()` there is the table that gives an
##   action a behaviour). A third option is one more entry, and this file does not
##   change - which is exactly what T-0052 DoD 2 asserts at runtime.
## * **A missing row cannot leave a phantom.** `set_entries()` rebuilds the list
##   from the data every time: remove an entry and its row is gone, leaving the
##   remaining rows in data order. Nothing is cached between redraws except the
##   focused row's `id`, and only so a refresh does not move the player's focus.
##   An empty list is an authoring error, not a crash: it draws no row and says so.
## * **Input has one door.** `handle_input()` asks `MapInput` for the intent;
##   nothing here reads a key, an action or a button directly. It is the same
##   router the map screen uses, so "menu on a gamepad" and "map on a gamepad" are
##   the same claim. Focus wraps in both directions. Dismiss is translated and
##   accepted - it clears the message line - but it does not leave the menu: the
##   main menu is the bottom of the screen stack, so there is nothing behind it.
## * **The menu acts on nothing.** It never starts a run, never quits, and never
##   changes the game. It emits `option_chosen(entry_id, action)`; an action the
##   owner does not handle is the owner's problem to report, and a menu that
##   quietly swallowed it would make a dead option look like a live one.
## * A pointer click is a second source of the same intent, never a second path:
##   the row's own `pressed` signal resolves to the same `activate()` a confirm
##   does.
##
## CALLERS MUST
## ------------
## * Listen to `option_chosen` and give the actions a meaning. The menu cannot
##   tell whether an action did anything.
## * Replace the data with `set_entries()` (a copy is taken); never edit the array
##   returned by `entries()` and expect a redraw.
##
## Prints on stdout, one line per event, so a headless run is evidence:
##   MENU_DATA {json}      once per redraw: the entries as data and as rows
##   MENU_CHOOSE {json}    once per confirmed entry, with the action it carried
##   MENU_DISMISS {json}   once per accepted dismiss
##   MENU_REFUSED {json}   once per refused data set or out-of-range confirm
##
## The row's `node` key is a Button and is not JSON: use `printable_rows()` for
## evidence lines.

## An entry was confirmed. `action` is the entry's own data, passed through
## untouched; `entry_id` is its `id`.
signal option_chosen(entry_id: String, action: String)

const MapInputScript := preload("res://src/ui/map_input.gd")

## The keys an entry must have. `action` is optional: an entry without one draws
## and is reported as unhandled when confirmed, which is the loud-but-not-fatal
## outcome a half-written option should have.
const REQUIRED_KEYS := ["id", "label"]

@export_group("Layout — node paths")
## Where each part of the screen lives. Exported rather than hardcoded so the
## scene can be rearranged without touching behaviour.
@export var title_path: NodePath = ^"Margin/Column/Title"
@export var list_path: NodePath = ^"Margin/Column/Entries"
@export var reason_path: NodePath = ^"Margin/Column/Reason"
@export var hint_path: NodePath = ^"Margin/Column/Hint"

@export_group("Menu data")
## The menu, in drawing order. Today: Start Game, Exit. Adding an option is one
## entry here; `action` is interpreted by the owner (`src/ui/boot.gd`).
@export var entries: Array[Dictionary] = [
	{"id": "start", "label": "Start Game", "action": "start"},
	{"id": "exit", "label": "Exit", "action": "exit"},
]

@export_group("Copy")
## The game's name, as the charter spells it.
@export var title_text: String = "brackenward"
## What the controls are, in one sentence.
@export var hint_text: String = "Up/Down or D-pad picks, Enter or A confirms"
## Shown when the data produced no rows at all.
@export var no_entries_text: String = "this menu has no options"
## `dismiss_text` explains why Esc/B does nothing here.
@export var dismiss_text: String = "the main menu is the bottom of the stack"
## Prepended to the focused row so a keyboard or pad player can see where they are.
@export var focus_marker: String = "> "

@export_group("Tuning — PLACEHOLDER (T-0052)")
## Height of one row, in pixels. Range 32-56; a row shorter than the font clips,
## a row much taller stops reading as a list. A designer's number, not a rule.
@export var row_min_height: int = 40

# --- rows -------------------------------------------------------------------

## One entry per drawn row, in data order: `{index, id, label, action, node}`.
## `node` is the Button, present unless the scene has no list container.
var _rows: Array = []
var _focus: int = -1
var _reason: String = ""
var _dismissals: int = 0


func _ready() -> void:
	refresh()


# --- data -------------------------------------------------------------------

## Replaces the menu's data and redraws. Takes a copy. Refused - with the current
## rows left exactly as they were - when an entry is not a dictionary or is
## missing an `id` or a `label`: a menu with a broken row is worse than no redraw.
func set_entries(new_entries: Array) -> bool:
	var checked: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw in new_entries:
		if not (raw is Dictionary):
			return _refuse_data("entry %d is not a dictionary" % checked.size())
		var entry: Dictionary = raw
		for key in REQUIRED_KEYS:
			if not entry.has(key) or str(entry[key]) == "":
				return _refuse_data("entry %d has no '%s'" % [checked.size(), key])
		var id := str(entry["id"])
		if seen.has(id):
			return _refuse_data("two entries share the id '%s'" % id)
		seen[id] = true
		checked.append({
			"id": id,
			"label": str(entry["label"]),
			"action": str(entry.get("action", "")),
		})

	entries = checked
	_rebuild_rows()
	refresh()
	return true


## The menu's data, as a copy. Named `get_entries()` rather than `entries()`
## because a method cannot share a name with the exported property it reads.
func get_entries() -> Array:
	return entries.duplicate(true)


## The rows as drawn, `node` included. Use `printable_rows()` for evidence.
func rows() -> Array:
	return _rows.duplicate(true)


## The rows as drawn, without the Button references: safe to JSON.
func printable_rows() -> Array:
	var out: Array = []
	for entry in _rows:
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		copy.erase("node")
		out.append(copy)
	return out


func row_count() -> int:
	return _rows.size()


## One row, or an empty dictionary for an index this menu does not have.
func row(index: int) -> Dictionary:
	if index < 0 or index >= _rows.size():
		return {}
	return (_rows[index] as Dictionary).duplicate(true)


## The row ids on screen, in drawing order. Equals the entry ids, in data order -
## that equality is the whole of "it lists exactly the configured entries".
func drawn_ids() -> Array:
	var ids: Array = []
	for entry in _rows:
		ids.append(String(entry["id"]))
	return ids


func focus_index() -> int:
	return _focus


## Why the screen last said something, or "".
func reason() -> String:
	return _reason


## Dismiss intents accepted since the screen was created.
func dismissals() -> int:
	return _dismissals


# --- drawing ----------------------------------------------------------------

## Redraws the copy and the rows from the data. `set_entries()` calls this; a
## caller may call it again after changing exports, and nothing is lost: the focus
## follows its row's id, not its index.
func refresh() -> void:
	_rebuild_rows()
	_apply_copy()
	print("MENU_DATA " + JSON.stringify({
		"entries": entries,
		"rows": printable_rows(),
		"ids": drawn_ids(),
		"count": _rows.size(),
		"focus": _focus,
		"visible": visible,
	}))


# --- choosing ---------------------------------------------------------------

## Confirms the row at `index`: what a click, a confirm and a pad button all
## resolve to. Emits `option_chosen` and returns true for a row this menu has;
## false - with a printed reason - for an index it does not.
##
## It deliberately does **not** decide whether the action meant anything: a menu
## that hid an unhandled action would be the failure T-0052 DoD 5 plants.
func activate(index: int) -> bool:
	if index < 0 or index >= _rows.size():
		_refuse("confirm row %d" % index, "this menu has %d row(s)" % _rows.size())
		return false

	var entry: Dictionary = _rows[index]
	_focus = index
	_apply_focus()
	_reason = ""
	_apply_copy()

	print("MENU_CHOOSE " + JSON.stringify({
		"id": String(entry["id"]),
		"label": String(entry["label"]),
		"action": String(entry["action"]),
		"row": index,
	}))
	option_chosen.emit(String(entry["id"]), String(entry["action"]))
	return true


## One door for input. The event is translated by `MapInput`; this method only
## moves focus or chooses, and returns what it did so a caller (or a demo) can
## assert on the translation as well as the effect.
func handle_input(event: InputEvent) -> Dictionary:
	var router = MapInputScript.new()
	var result: Dictionary = router.intent_for(event)
	var out := result.duplicate()
	out["applied"] = false
	if not visible:
		out["ignored"] = "the menu is not showing"
		return out

	match int(result["intent"]):
		MapInputScript.Intent.FOCUS_NEXT:
			out["applied"] = _move_focus(1)
		MapInputScript.Intent.FOCUS_PREV:
			out["applied"] = _move_focus(-1)
		MapInputScript.Intent.CONFIRM:
			var index := _focus
			if result.has("pointer"):
				index = _index_at(result["pointer"])
			out["index"] = index
			out["applied"] = activate(index)
		MapInputScript.Intent.DISMISS:
			# Accepted, not refused: a pad player pressing B should get an answer,
			# and the answer is that there is nothing behind this screen.
			_dismissals += 1
			_reason = ""
			_apply_copy()
			print("MENU_DISMISS " + JSON.stringify({
				"dismissals": _dismissals,
				"reason": dismiss_text,
			}))
		_:
			pass
	return out


func _unhandled_input(event: InputEvent) -> void:
	# The focused row is drawn by this screen, not by a Button that takes focus,
	# so unconsumed key and pad events arrive here and nowhere else.
	handle_input(event)


# --- internals: rows --------------------------------------------------------

func _rebuild_rows() -> void:
	var previous_id := ""
	if _focus >= 0 and _focus < _rows.size():
		previous_id = String(_rows[_focus]["id"])
	_clear_list()
	_rows.clear()

	var list := _node(list_path)
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var row := {
			"index": i,
			"id": str(entry.get("id", "")),
			"label": str(entry.get("label", "")),
			"action": str(entry.get("action", "")),
		}
		if list != null:
			var button := Button.new()
			button.name = "Entry%d" % i
			button.focus_mode = Control.FOCUS_NONE
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(0, row_min_height)
			button.mouse_filter = Control.MOUSE_FILTER_STOP
			button.pressed.connect(_on_row_pressed.bind(i))
			list.add_child(button)
			row["node"] = button
		_rows.append(row)
		if previous_id != "" and previous_id == String(row["id"]):
			_focus = i

	if _focus < 0 or _focus >= _rows.size():
		_focus = 0 if not _rows.is_empty() else -1
	if _rows.is_empty() and _reason == "":
		_reason = no_entries_text
	_apply_focus()


func _apply_focus() -> void:
	for entry in _rows:
		if not entry.has("node"):
			continue
		var button: Button = entry["node"]
		var text := String(entry["label"])
		if int(entry["index"]) == _focus and _focus >= 0:
			text = focus_marker + text
		button.text = text


func _on_row_pressed(index: int) -> void:
	# A click is a pointer event that happened to be hit-tested by the row. It
	# resolves to the same call as a confirm, so there is one choosing path.
	_focus = index
	activate(index)


func _move_focus(delta: int) -> bool:
	if _rows.is_empty():
		return false
	if _focus < 0:
		_focus = 0
	else:
		_focus = int(posmod(_focus + delta, _rows.size()))
	_apply_focus()
	return true


func _index_at(point: Vector2) -> int:
	if _rows.is_empty():
		return -1
	var best := -1
	var best_distance := INF
	for entry in _rows:
		if not entry.has("node"):
			continue
		var rect: Rect2 = (entry["node"] as Control).get_global_rect()
		if rect.has_point(point):
			return int(entry["index"])
		var distance := rect.get_center().distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = int(entry["index"])
	return best


func _clear_list() -> void:
	var list := _node(list_path)
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


# --- internals: presentation ------------------------------------------------

func _apply_copy() -> void:
	var title := _node(title_path)
	if title != null:
		(title as Label).text = title_text
	var hint := _node(hint_path)
	if hint != null:
		(hint as Label).text = hint_text
	var reason_label := _node(reason_path)
	if reason_label != null:
		(reason_label as Label).text = _reason


func _node(path: NodePath) -> Node:
	if path.is_empty():
		return null
	return get_node_or_null(path)


# --- internals: refusals ----------------------------------------------------

func _refuse_data(why: String) -> bool:
	_refuse("set the menu data", why)
	# The rows on screen are the ones from the last accepted data: a refused
	# redraw changes nothing, so what the player sees is never a half-built list.
	return false


func _refuse(action: String, why: String) -> void:
	# Printed, never `push_error`: a refused confirm is expected play (an empty
	# menu, a click below the last row), and an ERROR line would make the gates
	# red for a working screen (`arena.gd` sets the same precedent).
	_reason = "%s: %s" % [action, why]
	_apply_copy()
	print("MENU_REFUSED " + JSON.stringify({"action": action, "reason": why}))
