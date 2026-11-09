extends Control

## The blocking choice modal (T-0065): a title, one or more groups, and exactly one
## pick per group before anything is granted.
##
## CONTRACT
## --------
## * **It is a component, not the opening screen.** `open(config)` takes the whole
##   choice as data - a title, a list of groups and a selection rule - and it never
##   names a tower, an upgrade, an event or a store. The opening pick, the event
##   node and the store front will all call this same `open()` with different data.
##       config = {
##           "title":  String,
##           "rule":   "one_per_group"   (optional; the only rule implemented),
##           "groups": [{
##               "id":     String,       (unique across the whole choice)
##               "label":  String,       (the group heading, player-facing)
##               "options": [{
##                   "id":      String,  (unique inside its group)
##                   "label":   String,
##                   "detail":  String,  (optional second half of the row)
##                   "payload": any      (optional, returned untouched with the pick)
##               }],
##           }],
##       }
##   A different `rule` is **refused**, not silently treated as one-per-group: a
##   component that quietly implements the wrong selection rule is how "pick two"
##   becomes "pick one" and nobody notices until a run is short an item.
## * **Blocking.** While open it covers the screen: the backdrop consumes every
##   mouse click, and `_input` consumes every mapped key or pad event before the
##   screen underneath can see it, which is what makes the map behind it inert.
##   Nothing in this file calls the map screen; blocking is a property of being an
##   overlay, not of the screen behind it knowing about the modal.
## * **Confirm is refused until every group holds a pick**, with a printed reason
##   and no signal: `confirmed` never fires for a partial choice, so an owner
##   cannot grant one by accident.
## * **No dismiss.** `DISMISS` is translated, answered with a printed sentence and
##   a counter, and changes nothing - the choice cannot be thrown away to get back
##   to the map.
## * **`confirmed` does not close the modal.** The owner applies the picks and then
##   calls `close()`; if applying them fails, the modal is still up and the player
##   is still held by it. Closing on emit would let a failed grant leave a run with
##   no menu in front of it.
## * Input has one door, `handle_input()`, which asks `MapInput` for the intent:
##   the same four `game_*` actions the menu and the map screen use, so the modal
##   is keyboard, mouse and gamepad from the same code path.
##
## CALLERS MUST
## ------------
## * Connect `confirmed(picks)` before `open()`. Each pick is
##   `{group, group_label, id, label, payload}` in group order.
## * Apply the picks and then call `close()`. A refused apply should leave the
##   modal up (`show_reason()` says why) rather than release the player with
##   nothing granted.
## * Not call `close()` before `confirmed` arrives: there is no cancel path by
##   design.
##
## Prints on stdout, one line per event, so a headless run is evidence:
##   CHOICE_MODAL_SHOWN {json}           once per open: the title, the groups, the rows
##   CHOICE_MODAL_PICK {json}            once per pick or changed pick
##   CHOICE_MODAL_CONFIRM {json}         once per accepted confirm, with the picks
##   CHOICE_MODAL_REFUSED {json}         once per refused config or confirm
##   CHOICE_MODAL_DISMISS_REFUSED {json} once per attempted dismiss
##   CHOICE_MODAL_CLOSED {json}          once per owner close

## The choice was confirmed, every group holds exactly one pick. The modal is
## still open; the owner applies the picks and calls `close()`.
signal confirmed(picks: Array)
## A confirm was refused (a group is still unpicked) or an owner asked something
## impossible. `why` is the sentence the player is shown.
signal refused(why: String)

const MapInputScript := preload("res://src/ui/map_input.gd")

## The one selection rule this component implements. Named so a caller can say it
## and a future rule can be added without guessing which one is in force.
const RULE_ONE_PER_GROUP := "one_per_group"

const ROW_OPTION := "option"
const ROW_CONFIRM := "confirm"

const REQUIRED_GROUP_KEYS := ["id", "label", "options"]

@export_group("Layout — node paths")
@export var title_path: NodePath = ^"Center/Panel/Margin/Column/Title"
@export var rows_path: NodePath = ^"Center/Panel/Margin/Column/Rows"
@export var reason_path: NodePath = ^"Center/Panel/Margin/Column/Reason"
@export var hint_path: NodePath = ^"Center/Panel/Margin/Column/Hint"

@export_group("Copy")
## The row at the end of the list that applies the picks.
@export var confirm_label: String = "Confirm"
@export var hint_text: String = "Up/Down or D-pad moves, Enter or A picks, confirm when every group has one"
## Shown when a dismiss is attempted. The modal has no cancel path on purpose.
@export var dismiss_text: String = "this choice cannot be dismissed: pick one option in every group"
## Shape of the sentence shown when confirm is refused. One `%s`: the group names.
@export var unmet_text: String = "one pick is still missing in %s"
## Prepended to the focused row so a keyboard or pad player can see where they are.
@export var focus_marker: String = "> "
## Prepended to a row in its group that is not the pick yet.
@export var unpicked_marker: String = "[ ] "
## Prepended to the row that is this group's pick.
@export var picked_marker: String = "[x] "
## Between an option's label and its detail.
@export var field_separator: String = " · "

@export_group("Tuning — PLACEHOLDER (eng/gameplay, T-0065)")
## Height of one option row, in pixels. Range 32-56; shorter clips the font, much
## taller stops reading as a list. A designer's number, not a rule.
@export var row_min_height: int = 40

# --- the open choice ----------------------------------------------------------

var _open: bool = false
var _title: String = ""
## The validated groups, in drawing order: `{id, label, options}`.
var _groups: Array = []
## group id -> the picked option's id. Empty means "nothing picked in that group".
var _picks: Dictionary = {}

# --- rows ---------------------------------------------------------------------

## One entry per focusable row, in drawing order:
##     idx, kind ("option"|"confirm"), group, option, text, node
var _rows: Array = []
var _focus: int = -1

var _reason: String = ""
var _dismissals: int = 0
var _confirm_attempts: int = 0
var _router = MapInputScript.new()


func _ready() -> void:
	_apply_copy()
	hide()


# --- opening ------------------------------------------------------------------

## Opens the choice described by `config`. Refused (false, printed reason, stays
## closed and changes nothing) when the config cannot be drawn: no title, no
## groups, a group with no options, a duplicate id, or a rule this component does
## not implement.
func open(config: Dictionary) -> bool:
	var checked := _validate(config)
	if not bool(checked.get("ok", false)):
		_refuse_open(String(checked.get("reason", "")))
		return false

	_title = String(checked["title"])
	_groups = checked["groups"]
	_picks.clear()
	_reason = ""
	_focus = -1
	_open = true
	_rebuild_rows()
	_apply_copy()
	show()

	print("CHOICE_MODAL_SHOWN " + JSON.stringify({
		"title": _title,
		"groups": _group_summary(),
		"rows": _row_summary(),
		"rule": RULE_ONE_PER_GROUP,
		"visible": visible,
	}))
	return true


## Closes the modal after the owner has applied the picks. The only path out: the
## player cannot close it, and a partial choice never reaches here.
func close() -> void:
	if not _open:
		return
	_open = false
	hide()
	print("CHOICE_MODAL_CLOSED " + JSON.stringify({
		"title": _title,
		"picks": _picks.duplicate(true),
	}))
	_picks.clear()
	_groups = []
	_rows.clear()
	_focus = -1
	_reason = ""
	_clear_rows()
	_apply_copy()


# --- choosing -----------------------------------------------------------------

## Sets `group_id`'s pick to `option_id`, replacing that group's previous pick.
## Refused - with nothing changed - for a group or option this choice does not
## have, and while the modal is closed.
func choose(group_id: String, option_id: String) -> bool:
	if not _open:
		return _refuse_action("choose", "the modal is not open")
	var group := _group(group_id)
	if group.is_empty():
		return _refuse_action("choose in group '%s'" % group_id, "no such group in this choice")
	if _option(group, option_id).is_empty():
		return _refuse_action(
			"choose '%s' in group '%s'" % [option_id, group_id],
			"no such option in that group"
		)
	if String(_picks.get(group_id, "")) == option_id:
		return true

	_picks[group_id] = option_id
	_apply_focus()
	print("CHOICE_MODAL_PICK " + JSON.stringify({
		"group": group_id,
		"option": option_id,
		"picks": _picks.duplicate(true),
		"complete": unmet_groups().is_empty(),
	}))
	return true


## Applies the choice. Refused with a printed reason while any group has no pick,
## so a partial choice emits nothing and grants nothing.
func confirm() -> bool:
	if not _open:
		return _refuse_action("confirm", "the modal is not open")
	_confirm_attempts += 1
	var unmet := unmet_groups()
	if not unmet.is_empty():
		var names: Array = []
		for gid in unmet:
			names.append(_group_label(String(gid)))
		var why := unmet_text % ", ".join(names)
		_show_reason(why)
		_refuse_confirm(why, unmet)
		return false

	var picks := _build_picks()
	print("CHOICE_MODAL_CONFIRM " + JSON.stringify({
		"title": _title,
		"picks": picks,
		"groups": _group_summary(),
	}))
	confirmed.emit(picks)
	return true


## A dismiss attempt: counted, answered, and refused. There is deliberately no
## cancel path - the run cannot be left without the choice being made.
func dismiss() -> bool:
	if not _open:
		return false
	_dismissals += 1
	_show_reason(dismiss_text)
	print("CHOICE_MODAL_DISMISS_REFUSED " + JSON.stringify({
		"dismissals": _dismissals,
		"reason": dismiss_text,
		"picks": _picks.duplicate(true),
	}))
	return false


## Confirms the row at `index`: what a click, a confirm and a pad button all
## resolve to. An option row picks that option; the confirm row applies the choice.
func activate(index: int) -> bool:
	if not _open:
		return false
	if index < 0 or index >= _rows.size():
		return _refuse_action("activate row %d" % index, "this choice has %d row(s)" % _rows.size())

	var entry: Dictionary = _rows[index]
	_focus = index
	_apply_focus()
	if String(entry["kind"]) == ROW_CONFIRM:
		return confirm()
	return choose(String(entry["group"]), String(entry["option"]))


# --- input --------------------------------------------------------------------

## One door for input, exactly like the screens around it: `MapInput` translates
## the event, this method acts on the intent. Returns what it did so a caller (or
## a demo) can assert on the translation as well as the effect.
func handle_input(event: InputEvent) -> Dictionary:
	var result: Dictionary = _router.intent_for(event)
	var out := result.duplicate()
	out["applied"] = false
	if not (_open and visible):
		out["ignored"] = "the modal is not open"
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
			out["applied"] = dismiss()
		_:
			pass
	return out


## Keys and pad events are consumed here, before `_unhandled_input` reaches any
## screen behind the modal. Mouse events are left to the GUI layer: the backdrop
## and the panel are `MOUSE_FILTER_STOP`, so a click anywhere hits the modal or is
## swallowed by it and never reaches the map's rows.
func _input(event: InputEvent) -> void:
	if not (_open and visible):
		return
	if event is InputEventMouse:
		return
	var result: Dictionary = _router.intent_for(event)
	if int(result["intent"]) == MapInputScript.Intent.NONE:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	handle_input(event)


# --- queries ------------------------------------------------------------------

## Whether the modal is open and on screen. This is also the answer to "is the
## screen behind it inert": the modal takes every event while this is true.
func is_open() -> bool:
	return _open and visible


## The whole config the modal was opened with, as data, minus payloads. A caller
## reads this to know what it asked for.
func config() -> Dictionary:
	var groups: Array = []
	for group in _groups:
		var options: Array = []
		for option in (group as Dictionary)["options"]:
			options.append({
				"id": String((option as Dictionary)["id"]),
				"label": String((option as Dictionary)["label"]),
			})
		groups.append({
			"id": String((group as Dictionary)["id"]),
			"label": String((group as Dictionary)["label"]),
			"options": options,
		})
	return {"title": _title, "rule": RULE_ONE_PER_GROUP, "groups": groups}


## group id -> picked option id, as a copy. A group with no pick is absent.
func picks() -> Dictionary:
	return _picks.duplicate(true)


## The group ids that still have no pick, in group order. Empty means the choice
## may be confirmed.
func unmet_groups() -> Array:
	var out: Array = []
	for group in _groups:
		var gid := String((group as Dictionary)["id"])
		if String(_picks.get(gid, "")) == "":
			out.append(gid)
	return out


## The rows as drawn, without the Button references: safe to JSON.
func rows() -> Array:
	var out: Array = []
	for entry in _rows:
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		copy.erase("node")
		out.append(copy)
	return out


func row_count() -> int:
	return _rows.size()


## One row, or an empty dictionary for an index this modal does not have.
func row(index: int) -> Dictionary:
	if index < 0 or index >= _rows.size():
		return {}
	return (_rows[index] as Dictionary).duplicate(true)


func focus_index() -> int:
	return _focus


## The last sentence the modal showed, or "".
func reason() -> String:
	return _reason


## Shows `why` as the sentence under the list, changing nothing else. The owner
## uses it when applying a confirmed choice is refused: the picks stay, the player
## stays held by the choice, and the reason is the one the owner was given.
func show_reason(why: String) -> void:
	_show_reason(why)


func dismissals() -> int:
	return _dismissals


func confirm_attempts() -> int:
	return _confirm_attempts


# --- internals: validation ----------------------------------------------------

## Turns a caller's config into the validated shape the modal draws, or says why
## it cannot. One place, so every refusal is worded once.
func _validate(config: Dictionary) -> Dictionary:
	if typeof(config) != TYPE_DICTIONARY:
		return _invalid("the choice config is not a dictionary")
	var title := String(config.get("title", ""))
	if title == "":
		return _invalid("the choice has no title")

	var rule := String(config.get("rule", RULE_ONE_PER_GROUP))
	if rule != RULE_ONE_PER_GROUP:
		return _invalid(
			"selection rule '%s' is not implemented; this modal implements '%s'"
			% [rule, RULE_ONE_PER_GROUP]
		)

	var raw_groups = config.get("groups", [])
	if not (raw_groups is Array) or (raw_groups as Array).is_empty():
		return _invalid("the choice has no groups")

	var groups: Array = []
	var seen: Dictionary = {}
	for index in (raw_groups as Array).size():
		var raw = (raw_groups as Array)[index]
		if not (raw is Dictionary):
			return _invalid("group %d is not a dictionary" % index)
		var group: Dictionary = raw
		for key in REQUIRED_GROUP_KEYS:
			if not group.has(key) or str(group[key]) == "":
				return _invalid("group %d has no '%s'" % [index, key])
		var gid := String(group["id"])
		if seen.has(gid):
			return _invalid("two groups share the id '%s'" % gid)
		seen[gid] = true

		var raw_options = group["options"]
		if not (raw_options is Array) or (raw_options as Array).is_empty():
			return _invalid("group '%s' offers no options" % gid)

		var options: Array = []
		var seen_options: Dictionary = {}
		for oi in (raw_options as Array).size():
			var raw_option = (raw_options as Array)[oi]
			if not (raw_option is Dictionary):
				return _invalid("group '%s' option %d is not a dictionary" % [gid, oi])
			var option: Dictionary = raw_option
			if String(option.get("id", "")) == "" or String(option.get("label", "")) == "":
				return _invalid("group '%s' option %d has no id or label" % [gid, oi])
			var oid := String(option["id"])
			if seen_options.has(oid):
				return _invalid("group '%s' offers '%s' twice" % [gid, oid])
			seen_options[oid] = true
			options.append({
				"id": oid,
				"label": String(option["label"]),
				"detail": String(option.get("detail", "")),
				"payload": option.get("payload", null),
			})

		groups.append({"id": gid, "label": String(group["label"]), "options": options})

	return {"ok": true, "reason": "", "title": title, "groups": groups}


func _invalid(why: String) -> Dictionary:
	return {"ok": false, "reason": why, "title": "", "groups": []}


func _group(group_id: String) -> Dictionary:
	for group in _groups:
		if String((group as Dictionary)["id"]) == group_id:
			return group
	return {}


func _group_label(group_id: String) -> String:
	var group := _group(group_id)
	if group.is_empty():
		return group_id
	return String(group["label"])


func _option(group: Dictionary, option_id: String) -> Dictionary:
	for option in (group.get("options", []) as Array):
		if String((option as Dictionary)["id"]) == option_id:
			return option
	return {}


# --- internals: rows ----------------------------------------------------------

func _rebuild_rows() -> void:
	_clear_rows()
	_rows.clear()

	var list := _node(rows_path)
	for group in _groups:
		var gid := String((group as Dictionary)["id"])
		if list != null:
			var header := Label.new()
			header.name = "Group_%s" % gid
			header.text = String((group as Dictionary)["label"])
			list.add_child(header)
		for option in (group as Dictionary)["options"]:
			var entry := {
				"idx": _rows.size(),
				"kind": ROW_OPTION,
				"group": gid,
				"option": String((option as Dictionary)["id"]),
				"label": String((option as Dictionary)["label"]),
				"detail": String((option as Dictionary)["detail"]),
				"text": "",
			}
			_add_button(list, entry)
			_rows.append(entry)

	var confirm_row := {
		"idx": _rows.size(),
		"kind": ROW_CONFIRM,
		"group": "",
		"option": "",
		"label": confirm_label,
		"detail": "",
		"text": "",
	}
	_add_button(list, confirm_row)
	_rows.append(confirm_row)

	if _focus < 0 or _focus >= _rows.size():
		_focus = 0 if not _rows.is_empty() else -1
	_apply_focus()


func _add_button(list: Node, entry: Dictionary) -> void:
	if list == null:
		return
	var button := Button.new()
	button.name = "Row%d" % int(entry["idx"])
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, row_min_height)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(_on_row_pressed.bind(int(entry["idx"])))
	list.add_child(button)
	entry["node"] = button


func _row_text(entry: Dictionary) -> String:
	if String(entry["kind"]) == ROW_CONFIRM:
		return String(entry["label"])
	var picked := String(_picks.get(String(entry["group"]), "")) == String(entry["option"])
	var text := (picked_marker if picked else unpicked_marker) + String(entry["label"])
	if String(entry["detail"]) != "":
		text += field_separator + String(entry["detail"])
	return text


func _apply_focus() -> void:
	for entry in _rows:
		var text := _row_text(entry as Dictionary)
		if int((entry as Dictionary)["idx"]) == _focus:
			text = focus_marker + text
		(entry as Dictionary)["text"] = text
		if not (entry as Dictionary).has("node"):
			continue
		var button: Button = (entry as Dictionary)["node"]
		button.text = text


func _on_row_pressed(index: int) -> void:
	# A click resolves to the same call a confirm does, so there is one path in.
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
			return int(entry["idx"])
		var distance := rect.get_center().distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = int(entry["idx"])
	return best


func _clear_rows() -> void:
	var list := _node(rows_path)
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


# --- internals: the picks -----------------------------------------------------

## The picks in group order, each carrying its group and its payload untouched.
## The shape the owner applies and the shape `confirmed` carries.
func _build_picks() -> Array:
	var out: Array = []
	for group in _groups:
		var gid := String((group as Dictionary)["id"])
		var option := _option(group, String(_picks.get(gid, "")))
		if option.is_empty():
			continue
		out.append({
			"group": gid,
			"group_label": String((group as Dictionary)["label"]),
			"id": String(option["id"]),
			"label": String(option["label"]),
			"payload": option.get("payload", null),
		})
	return out


func _group_summary() -> Array:
	var out: Array = []
	for group in _groups:
		var ids: Array = []
		for option in (group as Dictionary)["options"]:
			ids.append(String((option as Dictionary)["id"]))
		out.append({
			"id": String((group as Dictionary)["id"]),
			"label": String((group as Dictionary)["label"]),
			"options": ids,
			"pick": String(_picks.get(String((group as Dictionary)["id"]), "")),
		})
	return out


func _row_summary() -> Array:
	var out: Array = []
	for entry in _rows:
		out.append({
			"idx": int(entry["idx"]),
			"kind": String(entry["kind"]),
			"group": String(entry["group"]),
			"option": String(entry["option"]),
		})
	return out


# --- internals: presentation --------------------------------------------------

func _apply_copy() -> void:
	var title := _node(title_path)
	if title != null:
		(title as Label).text = _title
	var hint := _node(hint_path)
	if hint != null:
		(hint as Label).text = hint_text
	var reason_label := _node(reason_path)
	if reason_label != null:
		(reason_label as Label).text = _reason


func _show_reason(text: String) -> void:
	_reason = text
	var label := _node(reason_path)
	if label != null:
		(label as Label).text = text


func _node(path: NodePath) -> Node:
	if path.is_empty():
		return null
	return get_node_or_null(path)


# --- internals: refusals ------------------------------------------------------

func _refuse_open(why: String) -> void:
	print("CHOICE_MODAL_REFUSED " + JSON.stringify({
		"action": "open",
		"reason": why,
		"open": _open,
	}))
	refused.emit(why)


func _refuse_confirm(why: String, unmet: Array) -> void:
	print("CHOICE_MODAL_REFUSED " + JSON.stringify({
		"action": "confirm",
		"reason": why,
		"unmet": unmet,
		"picks": _picks.duplicate(true),
		"attempts": _confirm_attempts,
	}))
	refused.emit(why)


func _refuse_action(action: String, why: String) -> bool:
	_show_reason("%s: %s" % [action, why])
	print("CHOICE_MODAL_REFUSED " + JSON.stringify({
		"action": action,
		"reason": why,
		"open": _open,
	}))
	refused.emit(why)
	return false
