extends Control

## The run map screen: what the player sees between levels, and the only place a
## node is chosen (T-0050).
##
## CONTRACT
## --------
## * One screen per run. `bind_run(flow)` is the only way in: it connects the
##   session's signals, captures the run state and draws the revealed nodes. The
##   screen owns no run state of its own - it reads `RunFlow.run_state()`,
##   `RunFlow.inventory()` and `RunFlow.map()` and copies nothing back.
## * It shows the **revealed** nodes and nothing else: `RunMap.visible_nodes()` is
##   the list, `RunMap.knowledge()` is the content, and a node the map has not
##   revealed is not drawn even if the screen was told its id.
## * Only a **selectable** node can be taken. Every row stays askable - a click or
##   a confirm on a visible-but-unselectable row says why it cannot be taken and
##   changes nothing (`reason_for()`), because the brief asks the screen to show
##   `not selectable` and explain it rather than hide it. Taking a node means
##   calling `RunFlow.enter_node()`; the screen never advances the route itself.
## * A row the screen refuses never reaches `enter_node()`. `RunFlow.refused_count()`
##   is therefore unchanged by a refused row, which is how the demo proves the
##   refusal happened in this file and not in the session.
## * The state line (HQ current/max, gold, towers owned) is read from the session
##   and **verified against it on every read** (`state()`). A binding that points
##   at a state the session no longer agrees with is reported as stale with the
##   mismatched fields, the lagging numbers are not displayed, and a choice is
##   refused until the screen is refreshed: a screen that can display a wrong HQ
##   is worse than a screen that says it cannot show one.
## * It yields to the level: `RunFlow.level_opened` hides the screen and
##   `level_completed` (or `map_ready`) brings it back with a fresh read. It is
##   never hidden by the level itself, so a level that forgets to report leaves a
##   hidden screen rather than a map the player can act on mid-level.
## * Input comes through one door, `handle_input()`, which asks `MapInput` for the
##   intent. Nothing in this file reads a key, an action or a button directly.
##
## CALLERS MUST
## ------------
## * Call `bind_run(flow)` - the flow may be bound before `start_run()`, which is
##   the order that exercises the `map_ready` hook; the screen shows itself when
##   the run begins.
## * Check the bool from `activate()` and show `reason()` when it is false. A
##   false return is a refusal the player can read, not an error.
## * Not call `enter_node()` on the session directly while this screen is bound:
##   the screen would keep showing a route the player has already left.
##
## Prints on stdout, one line per event, so a headless run is evidence:
##   MAPSCREEN_SHOWN {json}     once per draw: rows, state, position
##   MAPSCREEN_YIELD {json}     once per level opened; the screen hid itself
##   MAPSCREEN_RETURN {json}    once per level completed; the screen came back
##   MAPSCREEN_CHOOSE {json}    once per node taken, with the route before/after
##   MAPSCREEN_REFUSED {json}   once per row this screen refused, with the reason
##   MAPSCREEN_STALE {json}     once per stale snapshot caught, with the mismatch
##   MAPSCREEN_ENDED {json}     once when the run ended under the screen
##
## `RUNFLOW_*` lines in the same output are printed by the session, not by this
## file.

const MapInputScript := preload("res://src/ui/map_input.gd")

## A node was taken: the session moved the route onto it (`enter_node()` said
## true). The screen has already refreshed; a level-type node has also hidden it.
signal node_chosen(node_id: int)
## A row was refused by this screen, with the sentence the player is shown. No
## session call was made.
signal choice_refused(node_id: int, reason: String)

@export_group("Layout — node paths")
## Where the labels live. Exported rather than hardcoded so the scene can be
## rearranged without touching behaviour (eng/gameplay rule 3).
@export var title_path: NodePath = ^"Margin/Column/Title"
@export var state_path: NodePath = ^"Margin/Column/State"
@export var position_path: NodePath = ^"Margin/Column/Position"
@export var node_list_path: NodePath = ^"Margin/Column/Nodes"
@export var reason_path: NodePath = ^"Margin/Column/Reason"
@export var hint_path: NodePath = ^"Margin/Column/Hint"

@export_group("Copy")
## The screen title. "Run map" matches `docs/design/systems/nodes.md`'s wording.
@export var title_text: String = "Run map"
## The state line's shape. Four numbers: HQ current, HQ max, gold, towers owned.
@export var state_format: String = "HQ %d/%d    Gold %d    Towers %d"
## What a blind node shows instead of its payload (`nodes.md`: reveals its type).
@export var hidden_detail_text: String = "unknown until entered"
## The reason shown for a visible node that is not one of the next choices.
@export var locked_marker: String = "locked"
## The hint under the list: what the controls are, in one sentence.
@export var hint_text: String = "D-pad or Up/Down picks a node, A or Enter takes it, click takes it"
## Shown instead of any number when the state binding is stale.
@export var stale_text: String = "run state unavailable: the snapshot is stale"
## Appended to `stale_text` when a choice is refused for that reason.
@export var stale_hint_text: String = "refresh and choose again"
@export var no_run_text: String = "no run has started"
@export var no_nodes_text: String = "no node is revealed yet"
## Between fields of a row's text: "Layer 2 · Map · map-04 · 11 tiles".
@export var field_separator: String = " · "
## Prepended to the focused row so a keyboard or pad player can see where they are.
@export var focus_marker: String = "> "

@export_group("Tuning — PLACEHOLDER (design/systems/nodes.md)")
## Height of one node row, in pixels. Range 28-56; a row shorter than the font
## clips, a row much taller stops reading as a list.
@export var row_min_height: int = 36

# --- session ----------------------------------------------------------------

var _flow: Node = null
var _router = MapInputScript.new()

# --- rows -------------------------------------------------------------------

## One entry per drawn row, in map order:
##     id, index, node (Button), label, type, type_name, layer, selectable,
##     visible, lure, level, active_tiles, dominant_enemies, detail, reason
var _rows: Array = []
var _focus: int = -1

# --- state line -------------------------------------------------------------

## What the state line is displaying. Captured from the session on `refresh()`
## unless a demo has planted a different view; either way `state()` compares it
## with the session before it is trusted.
var _shown: Dictionary = {}
## The planted view, for the stale-binding demonstration only. Empty in play.
var _forced: Dictionary = {}
var _stale_reported: bool = false

var _reason: String = ""


func _ready() -> void:
	_apply_copy()


# --- binding ----------------------------------------------------------------

## Wires the screen to one run session and draws it. Refused (returns false, with
## a printed reason) when the same screen is already bound to a different session:
## one screen per run is the contract.
func bind_run(flow: Node) -> bool:
	if flow == null:
		_reject("bind the map screen", "no run session was handed over")
		return false
	if _flow != null and _flow != flow:
		_reject("bind the map screen", "this screen is already bound to another run")
		return false

	if _flow != null:
		_disconnect_all(_flow)
	_flow = flow
	_connect(_flow, "map_ready", _on_map_ready)
	_connect(_flow, "level_opened", _on_level_opened)
	_connect(_flow, "level_completed", _on_level_completed)
	_connect(_flow, "run_ended", _on_run_ended)

	refresh()
	# Nothing to show before `start_run()`: the screen is a map, and there is no
	# map. It appears on `map_ready`.
	visible = not _capture_shown_state().is_empty()
	return true


func flow() -> Node:
	return _flow


# --- drawing ----------------------------------------------------------------

## Rebuilds the rows and the state line from the session. Visibility is left
## alone except before a run exists, so a refresh during a level cannot un-hide a
## screen the level hid.
func refresh() -> void:
	if not _bound():
		_rows.clear()
		_shown = {}
		_clear_list()
		_apply_copy()
		return

	_rebuild_rows()
	_shown = _forced.duplicate(true) if not _forced.is_empty() else _capture_shown_state()
	_apply_copy()
	_apply_focus()

	var st := state()
	if bool(st["stale"]):
		if not _stale_reported:
			_stale_reported = true
			print("MAPSCREEN_STALE " + JSON.stringify({
				"mismatch": st["mismatch"],
				"shown": st["shown"],
				"live": st["live"],
			}))
	else:
		_stale_reported = false

	print("MAPSCREEN_SHOWN " + JSON.stringify({
		"rows": _row_ids(),
		"selectable": state_selectable_ids(),
		"state": st["label"],
		"stale": st["stale"],
		"position": _position_text(),
		"phase": _flow.phase_name() if _flow.has_method("phase_name") else "",
		"visible": visible,
	}))


## The rows as the screen drew them: a copy, so a caller cannot edit the list.
func rows() -> Array:
	return _rows.duplicate(true)


func row_count() -> int:
	return _rows.size()


## One row, or an empty dictionary for an index the screen does not have.
func row(index: int) -> Dictionary:
	if index < 0 or index >= _rows.size():
		return {}
	return (_rows[index] as Dictionary).duplicate(true)


## Why the row at `index` cannot be taken, in the player's words. Empty for a
## selectable row. Never calls the session: asking is free and changes nothing.
func reason_for(index: int) -> String:
	var entry := row(index)
	if entry.is_empty():
		return no_run_text
	return _reason_for(int(entry["id"]))


## The last sentence the screen showed the player, or "".
func reason() -> String:
	return _reason


func focus_index() -> int:
	return _focus


## The row ids on screen, in drawing order. Equals `RunMap.visible_nodes()` -
## that equality is the whole of "it lists exactly the revealed nodes".
func drawn_ids() -> Array:
	return _row_ids()


# --- the state binding ------------------------------------------------------

## The numbers as displayed, checked against the session on every read:
##     {hq, hq_max, gold, towers, levels_completed, label, stale, mismatch,
##      shown, live}
## `stale` is true when the displayed view disagrees with the session; `mismatch`
## names each field and both values, so a caller can report the disagreement
## instead of showing the lagging number. `label` is what the screen prints: the
## numbers when they are trusted, `stale_text` when they are not.
func state() -> Dictionary:
	var shown := _shown.duplicate(true)
	var live := _capture_shown_state()
	var out := {
		"shown": shown,
		"live": live,
		"stale": false,
		"mismatch": {},
		"label": _state_label(shown),
	}
	var bad: Dictionary = {}
	if not shown.is_empty() and not live.is_empty():
		for key in shown.keys():
			if key == "levels_completed" or not live.has(key):
				continue
			if int(shown[key]) != int(live[key]):
				bad[key] = {"shown": int(shown[key]), "live": int(live[key])}
	if not bad.is_empty():
		out["stale"] = true
		out["mismatch"] = bad
		out["label"] = stale_text
	return out


## DEMO ONLY, and named as such: points the state line at a view the session no
## longer agrees with, which is the failure the brief asks this screen to catch.
## Play never calls this; `T-0050` uses it to prove the mismatch is reported.
func force_shown_state_for_demo(view: Dictionary) -> void:
	_forced = view.duplicate(true)


## Drops a planted view and shows the session's numbers again.
func use_live_state() -> void:
	_forced = {}
	_stale_reported = false


# --- choosing ---------------------------------------------------------------

## Takes the node in row `index`: what a click, a confirm and a pad button all
## resolve to.
##
## Returns false and shows the reason - without calling the session - when the
## row is not selectable, when the run is over, or when the state on screen is
## stale. Returns true only when `RunFlow.enter_node()` did.
func activate(index: int) -> bool:
	if not _bound():
		_show_reason(no_run_text)
		return false
	if index < 0 or index >= _rows.size():
		_show_reason(no_nodes_text if _rows.is_empty() else "no node at row %d" % index)
		return false

	var entry: Dictionary = _rows[index]
	_focus = index
	_apply_focus()
	var node_id := int(entry["id"])

	if not bool(entry["selectable"]):
		var why := _reason_for(node_id)
		_show_reason(why)
		_refuse_row(node_id, why)
		return false

	var st := state()
	if bool(st["stale"]):
		var why := "%s; %s" % [stale_text, stale_hint_text]
		_show_reason(why)
		_print_stale(node_id, st)
		_refuse_row(node_id, why)
		return false

	var route_before: Array = _flow.map().route()
	if not _flow.enter_node(node_id):
		var why: String = _flow.last_refusal()
		_show_reason(why)
		_refuse_row(node_id, why)
		return false

	_show_reason("")
	var route_after: Array = _flow.map().route()
	print("MAPSCREEN_CHOOSE " + JSON.stringify({
		"node": node_id,
		"type": String(entry["type"]),
		"layer": int(entry["layer"]),
		"route_before": route_before,
		"route_after": route_after,
		"level_open": _flow.is_in_level(),
		"levels_completed": _flow.run_state().level_index(),
		"hq": _flow.run_state().hq_health(),
		"gold": _flow.run_state().gold(),
	}))
	node_chosen.emit(node_id)
	refresh()
	return true


## One door for input. The event is translated by `MapInput`; this method only
## moves focus or chooses, and returns what it did so a caller (or a demo) can
## assert on the translation as well as the effect.
func handle_input(event: InputEvent) -> Dictionary:
	var result: Dictionary = _router.intent_for(event)
	var out := result.duplicate()
	out["applied"] = false
	if not visible:
		out["ignored"] = "the screen is not showing"
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
			_show_reason("")
			out["applied"] = false
		_:
			pass
	return out


func _unhandled_input(event: InputEvent) -> void:
	# The focused row is drawn by this screen, not by a Button that takes focus,
	# so unconsumed key and pad events arrive here and nowhere else.
	handle_input(event)


# --- internals: rows --------------------------------------------------------

func _rebuild_rows() -> void:
	var previous_id := -1
	if _focus >= 0 and _focus < _rows.size():
		previous_id = int(_rows[_focus]["id"])
	_clear_list()
	_rows.clear()

	var map = _flow.map()
	if map == null:
		_focus = -1
		return

	var list := _node(node_list_path)
	for id in map.visible_nodes():
		var info: Dictionary = map.knowledge(id)
		if info.is_empty():
			# `knowledge()` answered empty for a node the map called visible: that
			# is the map contradicting itself, and the screen must not invent a
			# row for a node it does not know.
			continue
		var selectable := bool(map.is_selectable(id))
		var entry := {
			"index": _rows.size(),
			"id": int(id),
			"layer": int(info.get("layer", 0)),
			"type": String(info.get("type", "")),
			"type_name": String(info.get("type_name", "")),
			"selectable": selectable,
			"visible": true,
			"lure": bool(info.get("lure", false)),
			"detail": String(info.get("detail", "")),
			"level": String(info.get("level", "")),
			"active_tiles": int(info.get("active_tiles", 0)),
			"dominant_enemies": (info.get("dominant_enemies", []) as Array).duplicate(),
			"reason": "" if selectable else _reason_for(int(id)),
		}
		entry["label"] = _row_text(entry)
		if list != null:
			var button := Button.new()
			button.name = "Row%d" % int(id)
			button.focus_mode = Control.FOCUS_NONE
			button.custom_minimum_size = Vector2(0, row_min_height)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.mouse_filter = Control.MOUSE_FILTER_STOP
			button.pressed.connect(_on_row_pressed.bind(int(entry["index"])))
			list.add_child(button)
			entry["node"] = button
		_rows.append(entry)
		if previous_id == int(id):
			_focus = int(entry["index"])

	if _focus < 0 or _focus >= _rows.size():
		_focus = 0 if not _rows.is_empty() else -1
	_apply_focus()


func _row_text(entry: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append("Layer %d" % int(entry["layer"]))
	parts.append(String(entry["type_name"]))
	if String(entry["level"]) != "":
		parts.append(String(entry["level"]))
		parts.append("%d tiles" % int(entry["active_tiles"]))
		parts.append(", ".join(entry["dominant_enemies"]))
	if String(entry["detail"]) == "hidden_until_entry":
		parts.append(hidden_detail_text)
	if not bool(entry["selectable"]):
		parts.append(locked_marker)
	return field_separator.join(parts)


func _apply_focus() -> void:
	for entry in _rows:
		if not entry.has("node"):
			continue
		var button: Button = entry["node"]
		var text := String(entry["label"])
		if int(entry["index"]) == _focus:
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
	var count := _rows.size()
	if _focus < 0:
		_focus = 0
	else:
		_focus = int(posmod(_focus + delta, count))
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
	var list := _node(node_list_path)
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _row_ids() -> Array:
	var ids: Array = []
	for entry in _rows:
		ids.append(int(entry["id"]))
	return ids


func state_selectable_ids() -> Array:
	var ids: Array = []
	for entry in _rows:
		if bool(entry["selectable"]):
			ids.append(int(entry["id"]))
	return ids


# --- internals: reasons -----------------------------------------------------

## Why `node_id` cannot be taken, in the player's words, from the map's own rules.
## Empty when it can. This is the sentence the screen shows; it is not
## `RunFlow.last_refusal()`, because asking must not require a refused call.
func _reason_for(node_id: int) -> String:
	if not _bound():
		return no_run_text
	var map = _flow.map()
	var run = _flow.run_state()
	if map == null:
		return no_run_text
	if run != null and run.is_over():
		return "the run is over (%s)" % run.status_name()
	if map.is_selectable(node_id):
		return ""
	var node = map.node(node_id)
	if node == null:
		return "no node %d on this map" % node_id
	if map.route().has(node_id):
		return "already taken: the route has been through this node"
	if map.is_lure(node_id) and int(node.layer) + 1 > map.current_layer() + 1:
		return (
			"revealed as a lure; it is on layer %d and the next choice is on layer %d"
			% [int(node.layer) + 1, map.current_layer() + 1]
		)
	if int(node.layer) != map.current_layer():
		return (
			"it is on layer %d; the next choice is on layer %d"
			% [int(node.layer) + 1, map.current_layer() + 1]
		)
	return "it is visible but not one of the next choices %s" % [map.selectable_nodes()]


# --- internals: state -------------------------------------------------------

func _capture_shown_state() -> Dictionary:
	if not _bound():
		return {}
	var run = _flow.run_state()
	var inventory = _flow.inventory()
	if run == null or inventory == null:
		return {}
	return {
		"hq": run.hq_health(),
		"hq_max": run.hq_max_health(),
		"gold": run.gold(),
		"towers": inventory.tower_count(),
		"levels_completed": run.level_index(),
	}


func _state_label(view: Dictionary) -> String:
	if view.is_empty():
		return no_run_text
	return state_format % [
		int(view.get("hq", 0)),
		int(view.get("hq_max", 0)),
		int(view.get("gold", 0)),
		int(view.get("towers", 0)),
	]


func _position_text() -> String:
	if not _bound():
		return no_run_text
	var map = _flow.map()
	if map == null:
		return no_run_text
	var snapshot: Dictionary = map.snapshot()
	var route_text := str(snapshot.get("route", []))
	return "Layer %d of %d%sroute: %s" % [
		int(snapshot.get("current_layer", 0)),
		int(snapshot.get("layers", 0)),
		field_separator,
		route_text,
	]


# --- internals: presentation ------------------------------------------------

func _apply_copy() -> void:
	var title := _node(title_path)
	if title != null:
		(title as Label).text = title_text
	var st := _node(state_path)
	if st != null:
		(st as Label).text = state().get("label", no_run_text)
	var position := _node(position_path)
	if position != null:
		(position as Label).text = _position_text()
	var hint := _node(hint_path)
	if hint != null:
		(hint as Label).text = hint_text
	var reason_label := _node(reason_path)
	if reason_label != null:
		(reason_label as Label).text = _reason
	_sync_empty_label()


## The list's placeholder, kept in one place: shown when no row is drawn and
## removed the moment one is, so a refresh cannot stack placeholders.
func _sync_empty_label() -> void:
	var list := _node(node_list_path)
	if list == null:
		return
	var existing := list.get_node_or_null("Empty")
	if _rows.is_empty():
		if existing == null:
			var empty := Label.new()
			empty.name = "Empty"
			empty.text = no_nodes_text if _bound() else no_run_text
			list.add_child(empty)
		return
	if existing != null:
		list.remove_child(existing)
		existing.queue_free()


func _show_reason(text: String) -> void:
	_reason = text
	var label := _node(reason_path)
	if label != null:
		(label as Label).text = text


func _refuse_row(node_id: int, why: String) -> void:
	# `session_refusals` is the count the session has recorded. A refused row must
	# leave it unchanged: this screen refused the node, and `enter_node()` never
	# saw it.
	print("MAPSCREEN_REFUSED " + JSON.stringify({
		"node": node_id,
		"reason": why,
		"session_refusals": _flow.refused_count() if _flow != null else 0,
	}))
	choice_refused.emit(node_id, why)


func _print_stale(node_id: int, st: Dictionary) -> void:
	print("MAPSCREEN_STALE " + JSON.stringify({
		"node": node_id,
		"mismatch": st["mismatch"],
		"shown": st["shown"],
		"live": st["live"],
	}))


func _reject(action: String, why: String) -> void:
	_show_reason("%s: %s" % [action, why])
	print("MAPSCREEN_REJECTED " + JSON.stringify({"action": action, "reason": why}))


func _node(path: NodePath) -> Node:
	if path.is_empty():
		return null
	return get_node_or_null(path)


# --- internals: signals -----------------------------------------------------

func _bound() -> bool:
	return _flow != null and is_instance_valid(_flow) and _flow.has_method("map")


func _connect(target: Node, signal_name: String, handler: Callable) -> void:
	if target.has_signal(signal_name) and not target.is_connected(signal_name, handler):
		target.connect(signal_name, handler)


func _disconnect_all(target: Node) -> void:
	for pair in [
		["map_ready", _on_map_ready],
		["level_opened", _on_level_opened],
		["level_completed", _on_level_completed],
		["run_ended", _on_run_ended],
	]:
		if target.has_signal(String(pair[0])) and target.is_connected(String(pair[0]), pair[1]):
			target.disconnect(String(pair[0]), pair[1])


func _on_map_ready(seed_value: int, selectable: Array) -> void:
	refresh()
	show()
	# A different prefix from MAPSCREEN_SHOWN on purpose: `refresh()` has already
	# printed the full draw, and two lines under one prefix would make "the last
	# SHOWN line wins" ambiguous (L-038's lesson, applied to a log).
	print("MAPSCREEN_READY " + JSON.stringify({
		"seed": seed_value,
		"selectable": selectable,
		"visible": visible,
		"rows": _row_ids(),
	}))


func _on_level_opened(node_id: int, level_index: int, elite: bool) -> void:
	hide()
	print("MAPSCREEN_YIELD " + JSON.stringify({
		"node": node_id,
		"level_index": level_index,
		"elite": elite,
		"visible": visible,
	}))


func _on_level_completed(node_id: int, levels_completed: int, boss: bool) -> void:
	refresh()
	show()
	print("MAPSCREEN_RETURN " + JSON.stringify({
		"node": node_id,
		"levels_completed": levels_completed,
		"boss": boss,
		"visible": visible,
		"state": state()["label"],
	}))


func _on_run_ended(victory: bool, why: String) -> void:
	refresh()
	show()
	print("MAPSCREEN_ENDED " + JSON.stringify({
		"victory": victory,
		"reason": why,
		"state": state()["label"],
	}))
