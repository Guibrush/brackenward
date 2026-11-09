extends Control

## The always-visible bottom inventory bar (T-0066).
##
## CONTRACT
## --------
## * **This bar is the inventory view.** Towers and upgrades are two separate
##   groups, each item carries its tier, each group is paged (`page_size` per page,
##   8 by default, exposed as a setting) with a page indicator, and the run's gold
##   sits beside them. The build panel keeps HP, the wave readout, Start Wave and
##   the armed status line; it no longer lists the inventory (T-0066 moved the
##   list here), because two lists of one inventory is a second place to go stale.
## * **One instance, both screens.** The boot mounts one bar per run in the HUD
##   layer and binds it to the run's session, so the map screen and every level
##   read the same object and the same session. "Same data on both screens" is
##   therefore structural, not a synchronisation problem: there is nothing to
##   copy and nothing to keep in step.
## * **Equipped upgrades are absent by construction.** The upgrades group is built
##   from `Inventory.upgrades()`, which is the pool *in hand* - an applied upgrade
##   lives on its `TowerInstance` and has left that pool. The bar never filters a
##   second time, so an equipped upgrade cannot be shown here by a stale flag or a
##   forgotten branch.
## * **Tier comes from the item, never from a table here.** A tower's tier is
##   `TowerInstance.tier`. An upgrade instance carries identity only (no tier is
##   stored; `run_flow.gd` records that divergence for design/systems), so the bar
##   prints `upgrade_tier_text` rather than inventing a number, and honours a
##   `tier` property the day the instance grows one.
## * **The bar verifies what it draws against the session on every read.** A list
##   built once and trusted is a list that can show a tower the player no longer
##   owns. `refresh()` captures the view, `verify()` compares it with the live
##   inventory and gold, and a disagreement is reported (`INVENTORY_BAR_STALE`)
##   and *not displayed*: a bar that can show a wrong inventory is worse than one
##   that says it cannot show one.
## * **No modifying actions.** Selecting a tower is the only thing a click here
##   does; the floating tower window is the next task, so this file raises
##   `tower_selected` and marks the selection, and builds no window. During a wave
##   the bar stays drawn and readable for the same reason: with no modifying
##   action of its own, there is nothing here to lock.
## * **Input comes through one door**, `handle_input()`, which asks `MapInput` for
##   the intent. The bar acts on a pointer `CONFIRM` that lands on one of its own
##   slots or page controls and on nothing else - it never moves focus and never
##   takes a key, so the level's panel keeps owning the keyboard. A click it does
##   take is marked handled in `_input` (through `claim_point()`), which is what
##   stops the map screen underneath from reading the same click as a node choice.
##   The build panel asks `claim_point()` before it answers a pointer, because
##   `_input` reaches it first (see `add_pointer_guard()` there).
##
## Prints on stdout, one line per event:
##   INVENTORY_BAR_SHOWN {json}    once per draw whose content changed
##   INVENTORY_BAR_STALE {json}    once per distinct stale mismatch caught
##   INVENTORY_BAR_PAGE {json}     once per page change, with the page before/after
##   INVENTORY_BAR_SELECT {json}   once per tower selected
##   INVENTORY_BAR_REJECTED {json} a bind or call this bar refused

const MapInputScript := preload("res://src/ui/map_input.gd")

## The towers group's id, and the upgrades group's: the same strings the session's
## own offer table uses for a kind, so a caller can talk about them by name.
const GROUP_TOWERS := "towers"
const GROUP_UPGRADES := "upgrades"

## A tower in the bar was selected. `instance_id` is the inventory's id. The
## floating tower window (next task) listens here; this task only raises it.
signal tower_selected(instance_id: int)
## A group moved to another page.
signal page_changed(group_id: String, page: int, pages: int)

@export_group("Layout — node paths")
## The row the groups are built into. Exported rather than hardcoded so the scene
## can be rearranged without touching behaviour (eng/gameplay rule 3).
@export var row_path: NodePath = ^"Margin/Row"

@export_group("Paging")
## Slots per page, per group. The human's decision is 8; a designer changes this
## number, not the code, so it is a setting rather than a constant.
@export var page_size: int = 8

@export_group("Copy")
@export var towers_label: String = "Towers"
@export var upgrades_label: String = "Upgrades"
## The page indicator: current page out of the group's page count.
@export var page_format: String = "%d/%d"
## The two page controls. Text, so a designer can make them arrows or words.
@export var page_prev_text: String = "<"
@export var page_next_text: String = ">"
## How gold is written beside the groups.
@export var gold_format: String = "Gold %d"
## A tower's tier, next to its type.
@export var tier_format: String = "T%d"
## An upgrade's tier, when the instance does not carry one. The inventory does not
## store an upgrade's tier today (`run_flow.gd` records the divergence), so this is
## a statement about the data, not a zero.
@export var upgrade_tier_text: String = "T?"
## Appended to a tower's slot while it is standing on the board.
@export var placed_marker: String = "placed"
## Prepended to the selected tower's slot. Not colour, so the state survives a
## colourblind eye and a greyscale screenshot.
@export var selected_prefix: String = "\u25C6 "
## Between fields of a slot's text: "arrow · T2 · placed".
@export var field_separator: String = " \u00B7 "
## Shown inside a group with nothing in it.
@export var no_towers_text: String = "no towers"
@export var no_upgrades_text: String = "no upgrades in hand"
## Shown instead of the items when the captured view disagrees with the session.
@export var stale_text: String = "inventory unavailable: the view is stale"
## Shown instead of any number when no session is bound.
@export var no_session_text: String = "no run"

@export_group("Tuning — slot layout (PLACEHOLDER)")
## Minimum height of one slot, in pixels. Range 36-72; shorter clips two lines of
## text, much taller and the bar eats the board.
@export var slot_min_height: int = 46
## Gap between slots in a group, in pixels. Range 0-12.
@export var slot_separation: int = 4
## Gap between the two groups and the gold label, in pixels. Range 8-32.
@export var group_separation: int = 18

@export_group("Tuning — the selected cue (PLACEHOLDER)")
## Text colour of the selected tower's slot, and the border of its band. The same
## cool tint the build panel uses for a selection, so one state keeps one look.
@export var selected_colour: Color = Color(0.55, 0.86, 1.0, 1.0)
## Fill behind the selected slot. Same hue as `selected_colour`, darker than the
## text or the text stops reading.
@export var selected_fill: Color = Color(0.05, 0.2, 0.3, 0.92)
## Text colour of a slot in neither state.
@export var idle_colour: Color = Color(0.86, 0.88, 0.84, 1.0)
## Text colour of a page control or group heading.
@export var label_colour: Color = Color(0.62, 0.68, 0.63, 1.0)
## Border thickness of a slot's band, in pixels. Range 0-4.
@export var slot_border_width: int = 1
## Corner radius of a slot's band, in pixels. Range 0-6.
@export var slot_corner_radius: int = 2
## Inside padding of a slot, in pixels. Range 0-10.
@export var slot_padding: int = 4

var _flow = null
var _router = MapInputScript.new()

## What the bar is drawing: `{bound, gold, towers, upgrades}`. Captured from the
## session on every refresh unless a demo has planted a view; `verify()` compares
## it with the live session before anything is trusted.
var _shown: Dictionary = {}
## The planted view, for the stale demonstration only. Empty in play.
var _forced: Dictionary = {}
## The mismatch last printed, so one stale condition prints one line.
var _stale_signature: String = ""

## Group id -> its controls: `{box, name, count, prev, page, next, slots}`. Built
## once in `_build()` and re-filled on every draw.
var _group_nodes: Dictionary = {}
## Group id -> current page index (0-based).
var _pages: Dictionary = {}

## One entry per drawn slot, in drawing order:
##     group, index (within the page), item, id, type_id, tier, placed, node
var _slots: Array = []
## One entry per page control: `{group, dir, page, node}`.
var _page_controls: Array = []

var _selected_id: int = -1
var _stale: bool = false
var _last_signature: String = ""


func _ready() -> void:
	_build()
	_apply_copy()
	call_deferred("_deferred_refresh")


# --- binding ----------------------------------------------------------------

## Wires the bar to one run session and draws it. Needs `inventory()` and
## `run_state()`, which is what a run session is; a second session is refused
## rather than silently replacing the first, because one bar shows one run.
func bind_session(flow) -> bool:
	if flow == null:
		return _reject("bind the inventory bar", "no run session was handed over")
	if _flow != null and is_instance_valid(_flow) and _flow != flow:
		return _reject("bind the inventory bar", "this bar is already bound to another run")
	_flow = flow
	_connect_session()
	_pages.clear()
	_pages[GROUP_TOWERS] = 0
	_pages[GROUP_UPGRADES] = 0
	_selected_id = -1
	refresh()
	return true


func unbind() -> void:
	_disconnect_session()
	_flow = null
	_shown = {}
	_forced = {}
	_stale = false
	_selected_id = -1
	_slots.clear()
	_page_controls.clear()
	_last_signature = ""
	refresh()


func flow():
	return _flow


# --- drawing ----------------------------------------------------------------

## Captures the session's inventory and gold, verifies it, and draws it. Prints
## `INVENTORY_BAR_SHOWN` only when what is drawn differs from the previous draw,
## so a signal that fires twice for one action does not produce two lines.
func refresh(force: bool = false) -> void:
	_shown = _forced.duplicate(true) if not _forced.is_empty() else _capture()
	var report := _verify()
	_stale = bool(report["stale"])
	_report_stale(report)
	_rebuild()
	_apply_copy()
	var signature := _signature()
	if (force or signature != _last_signature) and (force or _bound()):
		_last_signature = signature
		print("INVENTORY_BAR_SHOWN " + JSON.stringify({
			"gold": _shown_gold(),
			"towers": _ids(_shown.get("towers", [])),
			"upgrades": _ids(_shown.get("upgrades", [])),
			"pages": _page_summary(),
			"stale": _stale,
			"selected": _selected_id,
			"visible": visible,
		}))


## Everything a demo, a HUD or the next task (the floating tower window) asks the
## bar for, in one dictionary. Read from the drawn view, not from the session, so
## "what is on screen" has exactly one answer.
func state() -> Dictionary:
	var towers: Array = []
	var upgrades: Array = []
	if not _stale:
		towers = _shown.get("towers", [])
		upgrades = _shown.get("upgrades", [])
	return {
		"bound": _bound(),
		"stale": _stale,
		"gold": _shown_gold(),
		"gold_label": _gold_text(),
		"tower_count": towers.size(),
		"upgrade_count": upgrades.size(),
		"towers": towers.duplicate(true),
		"upgrades": upgrades.duplicate(true),
		"pages": _page_summary(),
		"selected": _selected_id,
		"label": _state_label(),
	}


## The groups as drawn: `{id, label, page, pages, total, items}` each, in drawing
## order. `items` is the current page's items only - the point of paging is that a
## page is what the player can see.
func groups() -> Array:
	var out: Array = []
	for group_id in [GROUP_TOWERS, GROUP_UPGRADES]:
		var items := _page_items(group_id)
		out.append({
			"id": group_id,
			"label": _group_label(group_id),
			"page": _page_of(group_id) + 1,
			"pages": _page_count(_items_of(group_id).size()),
			"total": _items_of(group_id).size() if not _stale else 0,
			"stale": _stale,
			"items": items,
		})
	return out


## The slots drawn, in drawing order: group, index, item, id, type id, tier text,
## and the node. A copy, so a caller cannot edit the list.
func slots() -> Array:
	var out: Array = []
	for entry in _slots:
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		copy.erase("node")
		out.append(copy)
	return out


## The global rect of a drawn slot, or an empty rect. This is how a demo aims a
## real click at what the player sees instead of at a hardcoded pixel.
func slot_rect(group_id: String, index: int) -> Rect2:
	var entry := _slot_entry(group_id, index)
	if entry.is_empty():
		return Rect2()
	return (entry["node"] as Control).get_global_rect()


## The global rect of a group's page control (`-1` previous, `+1` next), or an
## empty rect when the group has one page and the control is not drawn.
func page_control_rect(group_id: String, direction: int) -> Rect2:
	for entry in _page_controls:
		if String(entry["group"]) == group_id and int(entry["dir"]) == direction:
			return (entry["node"] as Control).get_global_rect()
	return Rect2()


func selected_instance() -> int:
	return _selected_id


func is_stale() -> bool:
	return _stale


## True when `point` (viewport coordinates) is inside the bar. The build panel asks
## this before answering a pointer, because the bar draws over the lower part of
## the level and a click there is the bar's, not the board's.
func claim_point(point: Vector2) -> bool:
	if not visible:
		return false
	var rect := get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	return rect.has_point(point)


# --- acting -----------------------------------------------------------------

## The single action path: a click on a slot selects a tower, a click on a page
## control moves that group's page. Nothing here modifies the inventory - this
## task has no modifying action of its own.
func handle_input(event: InputEvent) -> Dictionary:
	var result: Dictionary = _router.intent_for(event)
	var out := result.duplicate()
	out["applied"] = false
	if not visible:
		out["ignored"] = "the bar is not showing"
		return out
	if int(result["intent"]) != MapInputScript.Intent.CONFIRM or not result.has("pointer"):
		out["ignored"] = "the bar only acts on a pointer confirm"
		return out

	var point: Vector2 = result["pointer"]
	var control := _page_at(point)
	if not control.is_empty():
		out["target"] = "page"
		out["group"] = String(control["group"])
		out["applied"] = move_page(String(control["group"]), int(control["dir"]))
		return out

	var slot := _slot_at(point)
	if not slot.is_empty():
		out["target"] = "slot"
		out["id"] = int(slot["id"])
		out["applied"] = _select(int(slot["id"]), "bar")
		return out

	out["target"] = "none"
	return out


## Moves a group one page in `direction` (-1 previous, +1 next), wrapping at the
## ends the way a paged list does. Refused (and silent) for a group with one page:
## a control that is not drawn must not answer.
func move_page(group_id: String, direction: int) -> bool:
	var pages := _page_count(_items_of(group_id).size())
	if pages <= 1 or direction == 0:
		return false
	var before := _page_of(group_id)
	var after := int(posmod(before + direction, pages))
	_pages[group_id] = after
	_rebuild()
	_apply_copy()
	print("INVENTORY_BAR_PAGE " + JSON.stringify({
		"group": group_id,
		"page_before": before + 1,
		"page": after + 1,
		"pages": pages,
		"items": _ids(_page_items(group_id)),
	}))
	page_changed.emit(group_id, after + 1, pages)
	return true


## Marks a tower selected without raising `tower_selected`: the level's panel
## calls this when the player selects a tower on the board, so the bar and the
## panel show one selection rather than two.
func mark_selected(instance_id: int) -> void:
	_selected_id = instance_id
	_rebuild()
	_apply_copy()


# --- the stale binding ------------------------------------------------------

## DEMO ONLY, and named as such: points the bar at an inventory the session no
## longer agrees with, which is the failure the brief asks this bar to catch.
## Play never calls this; `tests/inventory_bar_demo.gd` uses it to prove that a
## disagreement is reported instead of drawn.
func force_view_for_demo(view: Dictionary) -> void:
	_forced = view.duplicate(true)


## Drops a planted view and shows the session's own inventory again.
func use_live_inventory() -> void:
	_forced = {}
	_stale_signature = ""
	refresh()


# --- internals: the view ----------------------------------------------------

func _capture() -> Dictionary:
	var out := {"bound": false, "gold": 0, "towers": [], "upgrades": []}
	if not _bound():
		return out
	var run = _flow.run_state()
	var inventory = _flow.inventory()
	out["bound"] = true
	out["gold"] = int(run.gold()) if run != null else 0
	if inventory != null:
		for instance in inventory.towers():
			out["towers"].append({
				"id": int(instance.id),
				"type_id": String(instance.type_id),
				"tier": int(instance.tier),
				"tier_text": tier_format % int(instance.tier),
				"placed": bool(instance.placed),
			})
		for upgrade in inventory.upgrades():
			out["upgrades"].append({
				"id": int(upgrade.id),
				"type_id": String(upgrade.type_id),
				"tier_text": _upgrade_tier_text(upgrade),
			})
	return out


## The captured view against the live session: `{stale, mismatch, shown, live}`.
## `mismatch` names each disagreeing field with both values, so a caller can report
## the disagreement instead of showing the lagging number.
func _verify() -> Dictionary:
	var live := _capture()
	var out := {"stale": false, "mismatch": {}, "shown": _shown, "live": live}
	if _shown.is_empty() or not bool(live.get("bound", false)):
		return out
	var bad: Dictionary = {}
	if int(_shown.get("gold", 0)) != int(live.get("gold", 0)):
		bad["gold"] = {"shown": int(_shown.get("gold", 0)), "live": int(live.get("gold", 0))}
	for key in ["towers", "upgrades"]:
		var shown_ids := _ids(_shown.get(key, []))
		var live_ids := _ids(live.get(key, []))
		if shown_ids != live_ids:
			bad[key] = {"shown": shown_ids, "live": live_ids}
	out["stale"] = not bad.is_empty()
	out["mismatch"] = bad
	return out


func _report_stale(report: Dictionary) -> void:
	if not bool(report["stale"]):
		_stale_signature = ""
		return
	var signature := JSON.stringify(report["mismatch"])
	if signature == _stale_signature:
		return
	_stale_signature = signature
	var shown: Dictionary = report["shown"]
	var live: Dictionary = report["live"]
	print("INVENTORY_BAR_STALE " + JSON.stringify({
		"mismatch": report["mismatch"],
		"shown": {"gold": int(shown.get("gold", 0)), "towers": _ids(shown.get("towers", [])), "upgrades": _ids(shown.get("upgrades", []))},
		"live": {"gold": int(live.get("gold", 0)), "towers": _ids(live.get("towers", [])), "upgrades": _ids(live.get("upgrades", []))},
		"drawn": false,
	}))


## The tier text of one upgrade: the instance's own tier when it has one, and
## `upgrade_tier_text` when it does not. `in` asks the object, so a future
## `UpgradeInstance.tier` is honoured without an edit here.
func _upgrade_tier_text(upgrade: RefCounted) -> String:
	if "tier" in upgrade:
		return tier_format % int(upgrade.get("tier"))
	return upgrade_tier_text


func _items_of(group_id: String) -> Array:
	if _stale:
		return []
	if group_id == GROUP_TOWERS:
		return _shown.get("towers", [])
	return _shown.get("upgrades", [])


func _page_items(group_id: String) -> Array:
	var items := _items_of(group_id)
	var start := _page_of(group_id) * _page_size()
	var out: Array = []
	for i in range(start, mini(start + _page_size(), items.size())):
		out.append((items[i] as Dictionary).duplicate(true))
	return out


func _page_size() -> int:
	return maxi(page_size, 1)


func _page_count(total: int) -> int:
	return maxi(int(ceil(float(total) / float(_page_size()))), 1)


func _page_of(group_id: String) -> int:
	var page := int(_pages.get(group_id, 0))
	return clampi(page, 0, _page_count(_items_of(group_id).size()) - 1)


func _page_summary() -> Dictionary:
	return {
		GROUP_TOWERS: {"page": _page_of(GROUP_TOWERS) + 1, "pages": _page_count(_items_of(GROUP_TOWERS).size())},
		GROUP_UPGRADES: {"page": _page_of(GROUP_UPGRADES) + 1, "pages": _page_count(_items_of(GROUP_UPGRADES).size())},
	}


# --- internals: building the nodes ------------------------------------------

## Builds the two groups and the gold label once. Drawing re-fills the slot row of
## each group; it never rebuilds the groups themselves, so a page control keeps its
## rect and a click aimed at it lands on it.
func _build() -> void:
	var row := _node(row_path)
	if row == null:
		return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	_group_nodes.clear()
	row.add_child(_make_group(GROUP_TOWERS))
	row.add_child(_make_group(GROUP_UPGRADES))
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var gold := Label.new()
	gold.name = "Gold"
	gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(gold)
	_group_nodes["gold"] = gold


func _make_group(group_id: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Group_%s" % group_id
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_label)

	var count_label := Label.new()
	count_label.name = "Count"
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.add_theme_color_override("font_color", label_colour)
	header.add_child(count_label)

	var filler := Control.new()
	filler.name = "Filler"
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(filler)

	var prev := Label.new()
	prev.name = "Prev"
	prev.text = page_prev_text
	prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prev.add_theme_color_override("font_color", label_colour)
	header.add_child(prev)

	var page_label := Label.new()
	page_label.name = "Page"
	page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_label.add_theme_color_override("font_color", label_colour)
	header.add_child(page_label)

	var next := Label.new()
	next.name = "Next"
	next.text = page_next_text
	next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next.add_theme_color_override("font_color", label_colour)
	header.add_child(next)

	box.add_child(header)

	var slots := HBoxContainer.new()
	slots.name = "Slots"
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots.add_theme_constant_override("separation", slot_separation)
	box.add_child(slots)

	_group_nodes[group_id] = {
		"box": box,
		"name": name_label,
		"count": count_label,
		"prev": prev,
		"page": page_label,
		"next": next,
		"slots": slots,
	}
	return box


## Fills each group's slot row from the current page: one banded slot per item, or
## the empty or stale sentence when there is nothing to draw.
func _rebuild() -> void:
	_slots.clear()
	_page_controls.clear()
	for group_id in [GROUP_TOWERS, GROUP_UPGRADES]:
		var nodes: Dictionary = _group_nodes.get(group_id, {})
		if nodes.is_empty():
			continue
		var slots: Node = nodes["slots"]
		for child in slots.get_children():
			slots.remove_child(child)
			child.queue_free()

		var items := _page_items(group_id)
		for index in items.size():
			var item: Dictionary = items[index]
			var slot := PanelContainer.new()
			slot.name = "Slot%d" % index
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.custom_minimum_size = Vector2(0, slot_min_height)
			slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var text := Label.new()
			text.name = "Text"
			text.mouse_filter = Control.MOUSE_FILTER_IGNORE
			text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			slot.add_child(text)
			slots.add_child(slot)
			var entry := {
				"group": group_id,
				"index": index,
				"item": item,
				"id": int(item.get("id", 0)),
				"type_id": String(item.get("type_id", "")),
				"tier": String(item.get("tier_text", "")),
				"placed": bool(item.get("placed", false)),
				"node": slot,
			}
			_slots.append(entry)
			_dress_slot(entry, text, slot)

		if items.is_empty():
			var empty := Label.new()
			empty.name = "Empty"
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty.text = _empty_text(group_id)
			empty.add_theme_color_override("font_color", label_colour)
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			slots.add_child(empty)

		_add_page_controls(group_id, nodes)


func _add_page_controls(group_id: String, nodes: Dictionary) -> void:
	var pages := _page_count(_items_of(group_id).size())
	var show := pages > 1 and not _stale
	for pair in [["prev", -1], ["next", 1]]:
		var label: Label = nodes[String(pair[0])]
		label.visible = show
		if not show:
			continue
		label.add_theme_color_override("font_color", label_colour)
		_page_controls.append({
			"group": group_id,
			"dir": int(pair[1]),
			"page": _page_of(group_id) + 1,
			"node": label,
		})


## One slot's text and cue: type, tier, where the tower is, and the selection
## marker. Rebuilt from the item on every draw, so a marker cannot be left behind.
func _dress_slot(entry: Dictionary, label: Label, slot: PanelContainer) -> void:
	var text := String(entry["type_id"])
	if String(entry["tier"]) != "":
		text += field_separator + String(entry["tier"])
	if bool(entry["placed"]):
		text += field_separator + placed_marker
	var chosen := int(entry["id"]) == _selected_id and String(entry["group"]) == GROUP_TOWERS
	if chosen:
		text = selected_prefix + text
	label.text = text
	var box := StyleBoxFlat.new()
	box.bg_color = selected_fill if chosen else Color(0.14, 0.17, 0.15, 0.9)
	box.border_color = selected_colour if chosen else Color(0.3, 0.36, 0.31, 1.0)
	box.set_border_width_all(slot_border_width)
	box.set_corner_radius_all(slot_corner_radius)
	box.content_margin_left = slot_padding
	box.content_margin_right = slot_padding
	slot.add_theme_stylebox_override("panel", box)
	label.add_theme_color_override("font_color", selected_colour if chosen else idle_colour)


# --- internals: input lookups -----------------------------------------------

func _slot_entry(group_id: String, index: int) -> Dictionary:
	for entry in _slots:
		if String(entry["group"]) == group_id and int(entry["index"]) == index:
			return entry
	return {}


func _slot_at(point: Vector2) -> Dictionary:
	for entry in _slots:
		var rect: Rect2 = (entry["node"] as Control).get_global_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0 and rect.has_point(point):
			return entry
	return {}


func _page_at(point: Vector2) -> Dictionary:
	for entry in _page_controls:
		var rect: Rect2 = (entry["node"] as Control).get_global_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0 and rect.has_point(point):
			return entry
	return {}


## A click the bar takes is marked handled so the screen under it does not read the
## same event: without this, a click on a slot would also be a node choice on the
## map. Keys and focus are deliberately not taken - the level's panel owns those.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var result: Dictionary = _router.intent_for(event)
	if int(result["intent"]) != MapInputScript.Intent.CONFIRM or not result.has("pointer"):
		return
	if not claim_point(result["pointer"]):
		return
	get_viewport().set_input_as_handled()
	handle_input(event)


# --- internals: selection ---------------------------------------------------

func _select(instance_id: int, source: String) -> bool:
	var item := _tower_item(instance_id)
	if item.is_empty():
		print("INVENTORY_BAR_REJECTED " + JSON.stringify({
			"action": "select",
			"instance": instance_id,
			"reason": "no tower with that id is in the drawn inventory",
		}))
		return false
	_selected_id = instance_id
	_rebuild()
	_apply_copy()
	print("INVENTORY_BAR_SELECT " + JSON.stringify({
		"instance": instance_id,
		"type_id": String(item.get("type_id", "")),
		"tier": int(item.get("tier", 0)),
		"placed": bool(item.get("placed", false)),
		"source": source,
		"stale": _stale,
	}))
	tower_selected.emit(instance_id)
	return true


func _tower_item(instance_id: int) -> Dictionary:
	for raw in _items_of(GROUP_TOWERS):
		var item: Dictionary = raw
		if int(item.get("id", 0)) == instance_id:
			return item
	return {}


# --- internals: presentation ------------------------------------------------

func _apply_copy() -> void:
	for group_id in [GROUP_TOWERS, GROUP_UPGRADES]:
		var nodes: Dictionary = _group_nodes.get(group_id, {})
		if nodes.is_empty():
			continue
		var total := _items_of(group_id).size()
		(nodes["name"] as Label).text = _group_label(group_id)
		(nodes["count"] as Label).text = "" if _stale else str(total)
		var pages := _page_count(total)
		(nodes["page"] as Label).text = page_format % [_page_of(group_id) + 1, pages]
		(nodes["page"] as Label).visible = pages > 1 and not _stale
	var gold = _group_nodes.get("gold", null)
	if gold is Label:
		(gold as Label).text = _gold_text()
		(gold as Label).add_theme_color_override("font_color", idle_colour)


func _group_label(group_id: String) -> String:
	if group_id == GROUP_TOWERS:
		return towers_label
	return upgrades_label


func _empty_text(group_id: String) -> String:
	if _stale:
		return stale_text
	if not _bound():
		return no_session_text
	return no_towers_text if group_id == GROUP_TOWERS else no_upgrades_text


func _gold_text() -> String:
	if not _bound() or _stale:
		return stale_text if _stale else no_session_text
	return gold_format % _shown_gold()


func _state_label() -> String:
	if not _bound():
		return no_session_text
	if _stale:
		return stale_text
	return "%s %d%s%s %d%s%s" % [
		towers_label, _items_of(GROUP_TOWERS).size(), field_separator,
		upgrades_label, _items_of(GROUP_UPGRADES).size(), field_separator,
		_gold_text(),
	]


func _shown_gold() -> int:
	return int(_shown.get("gold", 0))


func _signature() -> String:
	return JSON.stringify({
		"towers": _ids(_shown.get("towers", [])),
		"upgrades": _ids(_shown.get("upgrades", [])),
		"gold": _shown_gold(),
		"pages": _page_summary(),
		"stale": _stale,
		"selected": _selected_id,
	})


func _ids(items: Array) -> Array:
	var out: Array = []
	for raw in items:
		if raw is Dictionary:
			out.append(int((raw as Dictionary).get("id", 0)))
	out.sort()
	return out


# --- internals: session -----------------------------------------------------

func _bound() -> bool:
	return _flow != null and is_instance_valid(_flow) and _flow.has_method("inventory")


func _connect_session() -> void:
	if not _bound():
		return
	var inventory = _flow.inventory()
	if inventory != null and inventory.has_signal("contents_changed") \
			and not inventory.is_connected("contents_changed", _on_inventory_changed):
		inventory.connect("contents_changed", _on_inventory_changed)
	var run = _flow.run_state()
	if run != null and run.has_signal("gold_changed") \
			and not run.is_connected("gold_changed", _on_gold_changed):
		run.connect("gold_changed", _on_gold_changed)


func _disconnect_session() -> void:
	if _flow == null or not is_instance_valid(_flow):
		return
	var inventory = _flow.inventory() if _flow.has_method("inventory") else null
	if inventory != null and inventory.has_signal("contents_changed") \
			and inventory.is_connected("contents_changed", _on_inventory_changed):
		inventory.disconnect("contents_changed", _on_inventory_changed)
	var run = _flow.run_state() if _flow.has_method("run_state") else null
	if run != null and run.has_signal("gold_changed") \
			and run.is_connected("gold_changed", _on_gold_changed):
		run.disconnect("gold_changed", _on_gold_changed)


func _on_inventory_changed() -> void:
	refresh()


func _on_gold_changed(_current: int = 0, _delta: int = 0) -> void:
	refresh()


func _deferred_refresh() -> void:
	refresh()


func _node(path: NodePath) -> Node:
	if path.is_empty():
		return null
	return get_node_or_null(path)


func _reject(action: String, why: String) -> bool:
	print("INVENTORY_BAR_REJECTED " + JSON.stringify({"action": action, "reason": why}))
	return false
