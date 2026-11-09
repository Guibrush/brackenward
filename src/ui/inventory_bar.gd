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
## * **Square slots, one border per state (T-0075).** A slot is a square of
##   `slot_side` pixels, drawn as its own rect - nothing inside it is clipped away
##   or drawn outside it, so the rect a click lands on is the rect the player sees.
##   The border says **where the tower is**: `hand_border_colour` for a tower in
##   hand, `placed_border_colour` for one standing in the level, and
##   `locked_border_colour` while `set_wave_locked()` says a wave is running. All
##   three are exported. Selection keeps its own channel - fill, text colour and
##   the `selected_prefix` marker - so it never overwrites what the border means.
## * **A placed tower stays listed.** The bar and the board are two views of one
##   object, so placing a tower changes its border and its header count, not its
##   presence here.
## * **No modifying actions.** Selecting a tower is the only thing a click here
##   does; the floating tower window is the next task, so this file raises
##   `tower_selected` and marks the selection, and builds no window. During a wave
##   the bar stays drawn and readable for the same reason: with no modifying
##   action of its own, there is nothing here to lock - `set_wave_locked()` only
##   repaints the border for the task that will own the lock.
## * **Input comes through one door**, `handle_input()`, which asks `MapInput` for
##   the intent. The bar acts on a pointer `CONFIRM` that lands on one of its own
##   slots or page controls and on nothing else - it never moves focus and never
##   takes a key, so the level's panel keeps owning the keyboard. A click it does
##   take is marked handled in `_input` (through `claim_point()`), which is what
##   stops the map screen underneath from reading the same click as a node choice.
##   The build panel asks `claim_point()` before it answers a pointer, because
##   `_input` reaches it first (see `add_pointer_guard()` there).
## * **The bar's half of drag-and-drop (T-0078).** A left press on a tower **in
##   hand** keeps its meaning - the slot is selected and the panel arms it - and
##   also begins a drag. Motion carries a ghost square under the pointer; a release
##   further than `drag_threshold_px` from the press *and* outside the bar raises
##   `tower_dropped(instance_id, screen_point)` exactly once and hides the ghost. A
##   release inside the bar, or a shorter one, is a click: the selection stands and
##   nothing is emitted. The drag is stored as **scalars**, never as a node,
##   because `_select()` rebuilds the slot row on the very press that starts it;
##   the ghost is one persistent child of the bar, built outside `_rebuild()`, so
##   no rebuild can free it mid-gesture. While a drag is live the release is
##   consumed (`set_input_as_handled`), so nothing under the bar answers the same
##   gesture. A **placed** tower begins no drag (its click opens the window), and
##   `set_wave_locked(true)` suppresses one. The point is in viewport coordinates,
##   the space `MapInput.intent_for()` reports: the bar does not convert to world,
##   because it does not own the board's transform.
## * **Pointer only.** The gesture reads the mouse button and motion directly,
##   because `MapInput` has no drag intent - a stick has no "drag", and inventing
##   one there would make a pointer gesture look like a pad action. Gamepad and
##   keyboard keep the click-then-tile path; the press itself still goes through
##   `MapInput` in `handle_input()`, so the selection keeps its one door.
##
## Prints on stdout, one line per event:
##   INVENTORY_BAR_SHOWN {json}    once per draw whose content changed
##   INVENTORY_BAR_STALE {json}    once per distinct stale mismatch caught
##   INVENTORY_BAR_PAGE {json}     once per page change, with the page before/after
##   INVENTORY_BAR_SELECT {json}   once per tower selected
##   INVENTORY_BAR_DRAG {json}     once per drag begun or cancelled
##   INVENTORY_BAR_DROP {json}     once per release that ended a drag
##   INVENTORY_BAR_REJECTED {json} a bind or call this bar refused

const MapInputScript := preload("res://src/ui/map_input.gd")

## The towers group's id, and the upgrades group's: the same strings the session's
## own offer table uses for a kind, so a caller can talk about them by name.
const GROUP_TOWERS := "towers"
const GROUP_UPGRADES := "upgrades"

## A tower in the bar was selected. `instance_id` is the inventory's id. The
## floating tower window (next task) listens here; this task only raises it.
signal tower_selected(instance_id: int)
## A tower **in hand** was pressed in the bar and released past
## `drag_threshold_px`, outside the bar (T-0078). `screen_point` is the release
## position in viewport coordinates - the space `MapInput.intent_for()` reports - so
## the receiver resolves it with the same `_pointer_world()` a click uses. The bar
## does not convert to world: it does not own the board's transform. A release
## inside the bar, or a shorter one, raises nothing at all.
signal tower_dropped(instance_id: int, screen_point: Vector2)
## A drag began: `instance_id` is the tower the player is carrying (T-0078). Raised
## **once per gesture**, the first time the pointer has travelled past
## `drag_threshold_px` and the gesture is therefore no longer a click - so a plain
## click on a tower in hand announces nothing, which is what keeps the tower window
## it opens from being closed again by a signal meant for drags. Never raised for a
## placed slot and never while `set_wave_locked(true)` is in force. It exists because
## every bar selection opens the tower window (`boot.gd`), so a drag has to say so
## before it is dragged under an open window; T-0080 is the receiver that closes it.
signal tower_drag_started(instance_id: int)
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
## The towers header's count: total, then how many of those are on the board.
## Showing both is the choice T-0075 asked for: "2" alone cannot say whether the
## two towers are in hand, placed, or one of each, and that is the question the
## header exists to answer.
@export var tower_count_format: String = "%d (%d %s)"
@export var placed_word: String = "placed"
## An upgrade's tier, when the instance does not carry one. The inventory does not
## store an upgrade's tier today (`run_flow.gd` records the divergence), so this is
## a statement about the data, not a zero.
@export var upgrade_tier_text: String = "T?"
## Prepended to the selected tower's slot. Not colour, so the state survives a
## colourblind eye and a greyscale screenshot. Selection is the only thing that
## changes a slot's text (T-0076); placement changes the border and nothing else.
@export var selected_prefix: String = "\u25C6 "
## Between fields of a slot's text: "arrow · T2".
@export var field_separator: String = " \u00B7 "
## Shown inside a group with nothing in it.
@export var no_towers_text: String = "no towers"
@export var no_upgrades_text: String = "no upgrades in hand"
## Shown instead of the items when the captured view disagrees with the session.
@export var stale_text: String = "inventory unavailable: the view is stale"
## Shown instead of any number when no session is bound.
@export var no_session_text: String = "no run"

@export_group("Tuning — slot layout (PLACEHOLDER)")
## Side of one square slot, in pixels: width and height are the same number.
## Range 48-72; below 48 two lines of text stop fitting, and much above 72 the bar
## eats the board (the bar's own height is set by `scenes/inventory_bar.tscn`).
@export var slot_side: int = 56
## Gap between slots in a group, in pixels. Range 0-12.
@export var slot_separation: int = 4
## Gap between the two groups and the gold label, in pixels. Range 8-32.
@export var group_separation: int = 18

@export_group("Tuning — slot borders by state (PLACEHOLDER)")
## Border of a slot whose tower is **in hand** (upgrades are always in hand).
@export var hand_border_colour: Color = Color(0.3, 0.36, 0.31, 1.0)
## Border of a slot whose tower is **placed** on the board.
@export var placed_border_colour: Color = Color(0.93, 0.72, 0.29, 1.0)
## Border of every slot while the wave lock is on (`set_wave_locked(true)`).
@export var locked_border_colour: Color = Color(0.55, 0.2, 0.2, 1.0)

@export_group("Tuning — the drag gesture (T-0078, PLACEHOLDER)")
## How far, in pixels, the pointer must travel from the press before a release
## **outside** the bar counts as a drop instead of a click. Range 2-24: below 2 a
## click that trembles becomes a throw, above 24 the gesture starts to feel like a
## deliberate cast rather than a drag. This is a feel decision - change it here, not
## in the code, and say so to `design/systems`.
@export var drag_threshold_px: float = 6.0

@export_group("Tuning — the selected cue (PLACEHOLDER)")
## Text colour of the selected tower's slot. The same cool tint the build panel
## uses for a selection, so one state keeps one look. Selection is drawn with this
## colour, `selected_fill` and `selected_prefix`; the border belongs to the
## slot's state (T-0075), so the two cues never overwrite each other.
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
## True while `set_wave_locked(true)` says a wave is running. This file owns no
## lock rule (T-0075): the arena will own the phase, and its caller flips this so
## every slot shows the locked border.
var _wave_locked: bool = false
var _stale: bool = false
var _last_signature: String = ""

## The live drag as scalars (T-0078): `_drag_id` is the instance carried, or -1 when
## no drag is live. Never a node: `_select()` rebuilds the slot row on the press that
## starts the drag, so any node reference taken there would be freed immediately.
var _drag_id: int = -1
var _drag_from: Vector2 = Vector2.ZERO
var _drag_to: Vector2 = Vector2.ZERO
## The text the ghost shows: the carried tower's type and tier, taken from the slot
## the press landed on.
var _drag_text: String = ""
## True once this gesture has raised `tower_drag_started`: a gesture announces itself
## once, on the first motion past the threshold, and a drop that never saw one
## announces itself before the drop.
var _drag_announced: bool = false
## The ghost: one persistent child of the bar, built once outside `_rebuild()` so a
## slot rebuild cannot free it mid-gesture. Added last, so it draws over the row.
var _ghost: Panel = null
var _ghost_label: Label = null


func _ready() -> void:
	_build()
	_ensure_ghost()
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
	_cancel_drag("the bar was unbound")
	_flow = null
	_shown = {}
	_forced = {}
	_stale = false
	_selected_id = -1
	_wave_locked = false
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
		var nodes: Dictionary = _group_nodes.get(group_id, {})
		out.append({
			"id": group_id,
			"label": _group_label(group_id),
			"page": _page_of(group_id) + 1,
			"pages": _page_count(_items_of(group_id).size()),
			"total": _items_of(group_id).size() if not _stale else 0,
			"placed": _placed_count(group_id) if not _stale else 0,
			# The header's count as drawn, not as computed: "what is on screen"
			# has one answer, and it is the label the player is reading.
			"count_text": (nodes["count"] as Label).text if not nodes.is_empty() else "",
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


## The state a drawn slot is in: `"in_hand"`, `"placed"`, or `"locked"` while the
## wave lock is on. Read from the same facts the border is painted from, so the
## answer and the paint cannot disagree.
func slot_state(group_id: String, index: int) -> String:
	var entry := _slot_entry(group_id, index)
	if entry.is_empty():
		return ""
	return _state_of(entry)


## True while a drag is live: pressed on a tower in hand, not yet released. A
## boolean of the drag's own scalars, not of the ghost's visibility - the ghost is
## a view of the drag, and this is the drag.
func drag_active() -> bool:
	return _drag_id != -1


## The instance the live drag carries, or -1 when no drag is live.
func drag_instance() -> int:
	return _drag_id


## The pointer position (viewport coordinates) the live drag last saw: the press
## point until the first motion arrives, and the release point afterwards.
func drag_point() -> Vector2:
	return _drag_to


## The ghost's rect as the player sees it, or an empty rect while it is not showing.
## Read off the node, not from a flag (L-041): a ghost the demo cannot point at is a
## ghost the player is not looking at either, and an empty rect is how "not there"
## is reported here, the same convention as `slot_rect()`.
func ghost_rect() -> Rect2:
	if _ghost == null or not is_instance_valid(_ghost) or not _ghost.visible:
		return Rect2()
	return _ghost.get_global_rect()


## The text the ghost carries, read off the Label it draws - the string the player
## reads, not a stored copy of it. Empty when the ghost was never built.
func ghost_text() -> String:
	if _ghost_label == null or not is_instance_valid(_ghost_label):
		return ""
	return String(_ghost_label.text)


## The border colour a drawn slot is drawn with, read off its own stylebox - not
## recomputed here, so a demo checks the pixels' source, not a second copy of it.
func slot_border(group_id: String, index: int) -> Color:
	var entry := _slot_entry(group_id, index)
	if entry.is_empty():
		return Color(0, 0, 0, 0)
	var node = entry["node"]
	if not (node is PanelContainer):
		return Color(0, 0, 0, 0)
	var box := (node as PanelContainer).get_theme_stylebox("panel")
	if box is StyleBoxFlat:
		return (box as StyleBoxFlat).border_color
	return Color(0, 0, 0, 0)


## True while the bar is painting every slot with the locked border.
func wave_locked() -> bool:
	return _wave_locked


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
	return _bar_contains(point)


## True when `point` is inside the bar's own rect. The drop test (T-0078) and
## `claim_point()` are the same question, so they are the same function: a release
## the bar calls a click and a release it calls "inside" cannot disagree.
func _bar_contains(point: Vector2) -> bool:
	var rect := get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	return rect.has_point(point)


# --- acting -----------------------------------------------------------------

## The single action path: a click on a slot selects a tower, a click on a page
## control moves that group's page. Nothing here modifies the inventory - this
## task has no modifying action of its own. On a tower **in hand** the click also
## begins a drag (T-0078): the selection is today's meaning and stands either way.
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
		# Read out as scalars first: `_select()` rebuilds the slot row, which frees
		# the node this entry points at, and `_begin_drag()` must survive that.
		var slot_id := int(slot["id"])
		var slot_text := _item_text(String(slot["type_id"]), String(slot["tier"]))
		var drags := String(slot["group"]) == GROUP_TOWERS and not bool(slot["placed"])
		out["target"] = "slot"
		out["id"] = slot_id
		out["applied"] = _select(slot_id, "bar")
		# A drag needs a pointer, so a pad or a key can never start one: those never
		# carry a `pointer` and never reach here (see the header).
		if drags and bool(out["applied"]):
			out["drag"] = _begin_drag(slot_id, point, slot_text)
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


## The seam for the wave lock (T-0075). The bar owns no lock rule: the arena will
## own the phase, and whoever owns it calls this once when the phase changes, so
## every slot repaints with `locked_border_colour`. A no-op (and no repaint) when
## the value does not change, so a per-frame caller is cheap.
func set_wave_locked(locked: bool) -> void:
	if _wave_locked == locked:
		return
	_wave_locked = locked
	# A tower held mid-gesture when a wave starts is put down, not thrown: the lock
	# suppresses the drag, so it also ends one that is already live (T-0078).
	if locked:
		_cancel_drag("the wave lock came on")
	_rebuild()
	print("INVENTORY_BAR_LOCK " + JSON.stringify({
		"locked": _wave_locked,
		"slots": _slots.size(),
		"states": _states(),
	}))


# --- the drag gesture (T-0078) ----------------------------------------------

## Begins a drag for a tower in hand that was just pressed. Refused while the wave
## lock is on and for a second press while one is already live; the caller has
## already checked that the slot holds a tower in hand. The scalars are stored
## before anything is drawn, so a press that rebuilds the row cannot lose them.
func _begin_drag(instance_id: int, point: Vector2, text: String) -> bool:
	if _wave_locked:
		print("INVENTORY_BAR_DRAG " + JSON.stringify({
			"instance": instance_id,
			"started": false,
			"reason": "the wave lock is on",
		}))
		return false
	if _drag_id != -1:
		return false
	_drag_id = instance_id
	_drag_from = point
	_drag_to = point
	_drag_text = text
	_drag_announced = false
	_ensure_ghost()
	_ghost_label.text = _drag_text
	_ghost.visible = true
	_place_ghost(point)
	print("INVENTORY_BAR_DRAG " + JSON.stringify({
		"instance": instance_id,
		"started": true,
		"from": [point.x, point.y],
		"threshold_px": drag_threshold_px,
		"text": _drag_text,
	}))
	return true


## Announces the drag, once per gesture: the pointer has left the click behind, so a
## receiver may now clear the screen the press opened (T-0080). Called from the first
## motion past `drag_threshold_px` and, defensively, from a drop that never saw such
## a motion - a release further from the press than the threshold *is* a drag, and
## the receiver must hear about it before it hears about the drop.
func _announce_drag() -> void:
	if _drag_announced or _drag_id == -1:
		return
	_drag_announced = true
	print("INVENTORY_BAR_DRAG " + JSON.stringify({
		"instance": _drag_id,
		"announced": true,
		"from": [_drag_from.x, _drag_from.y],
		"to": [_drag_to.x, _drag_to.y],
		"threshold_px": drag_threshold_px,
	}))
	tower_drag_started.emit(_drag_id)


## Motion and release while a drag is live. Returns true when the event belonged to
## the drag, so `_input()` stops there: a drag's motion and its release arrive
## outside the bar's rect, where `claim_point()` is false and the click path above
## would never see them.
##
## This reads the mouse directly on purpose: `MapInput` has no drag intent, and
## adding one would let a stick look like a drag. Only a release is consumed; a
## motion is not, because nothing else in the session acts on a move and consuming
## it would blind the GUI during a gesture.
func _update_drag(event: InputEvent) -> bool:
	if _drag_id == -1:
		return false
	if event is InputEventMouseMotion:
		_drag_to = (event as InputEventMouseMotion).position
		_place_ghost(_drag_to)
		# The moment the gesture stops being a click is the moment it is announced.
		if _drag_to.distance_to(_drag_from) > drag_threshold_px:
			_announce_drag()
		return true
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT or button.pressed:
			return false
		_drag_to = button.position
		_finish_drag(_drag_to)
		get_viewport().set_input_as_handled()
		return true
	return false


## Ends the live drag at `point`: a release further than `drag_threshold_px` from
## the press **and** outside the bar raises `tower_dropped` once; anything else was
## a click, whose work (the selection) the press already did.
func _finish_drag(point: Vector2) -> void:
	var instance := _drag_id
	var travelled := point.distance_to(_drag_from)
	var outside := not _bar_contains(point)
	var dropped := travelled > drag_threshold_px and outside
	if dropped:
		_announce_drag()
	_drag_id = -1
	_drag_text = ""
	_drag_announced = false
	_hide_ghost()
	print("INVENTORY_BAR_DROP " + JSON.stringify({
		"instance": instance,
		"dropped": dropped,
		"from": [_drag_from.x, _drag_from.y],
		"to": [point.x, point.y],
		"travel_px": snappedf(travelled, 0.01),
		"threshold_px": drag_threshold_px,
		"outside_bar": outside,
	}))
	if dropped:
		tower_dropped.emit(instance, point)


## Puts down a tower held mid-gesture without raising `tower_dropped`: the gesture
## stopped being the player's (a wave started, or the bar was unbound), so nothing
## was thrown anywhere.
func _cancel_drag(why: String) -> void:
	if _drag_id == -1:
		return
	print("INVENTORY_BAR_DRAG " + JSON.stringify({
		"instance": _drag_id,
		"cancelled": true,
		"reason": why,
	}))
	_drag_id = -1
	_drag_text = ""
	_drag_announced = false
	_hide_ghost()


# --- internals: the ghost ---------------------------------------------------

## Builds the ghost once: one persistent child of the bar, added last so it draws
## over the slot row. It is deliberately not built in `_rebuild()` - a rebuild runs
## on the press that starts the drag and on every page and inventory change, and a
## ghost rebuilt with the slots would be freed under the player's hand.
func _ensure_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		return
	var ghost := Panel.new()
	ghost.name = "DragGhost"
	# A view, never a target: the ghost must not take the click it is following.
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.clip_contents = true
	ghost.visible = false
	var label := Label.new()
	label.name = "Text"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ghost.add_child(label)
	add_child(ghost)
	# The selection's colours, so the tower being carried looks like the slot it was
	# picked out of and no new palette enters the bar (T-0078).
	var box := StyleBoxFlat.new()
	box.bg_color = selected_fill
	box.border_color = selected_colour
	box.set_border_width_all(slot_border_width)
	box.set_corner_radius_all(slot_corner_radius)
	box.content_margin_left = slot_padding
	box.content_margin_right = slot_padding
	ghost.add_theme_stylebox_override("panel", box)
	label.add_theme_color_override("font_color", selected_colour)
	_ghost = ghost
	_ghost_label = label


## Moves and sizes the ghost so it sits centred under `point`: the ghost is the slot
## the player is carrying, and the pointer is where they are holding it. The side is
## `_slot_side()` - the same square the slot they picked it out of is drawn at.
func _place_ghost(point: Vector2) -> void:
	_ensure_ghost()
	var side := float(_slot_side())
	_ghost.size = Vector2(side, side)
	_ghost.global_position = point - Vector2(side, side) * 0.5


func _hide_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.visible = false


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
			# A square: the same number for both sides, and no expand flag, so the
			# container cannot stretch it wider than it is tall. Nothing inside is
			# allowed to draw outside it (`clip_contents`), which keeps the drawn
			# square and the rect a click is tested against the same rectangle.
			var side := float(_slot_side())
			slot.custom_minimum_size = Vector2(side, side)
			slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slot.clip_contents = true
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


## One slot's text and cue: **the type and the tier, and nothing else** (T-0076).
## Where the tower is - in hand, placed, or locked - is the **border colour alone**,
## so placing a tower cannot change the slot's text and therefore cannot change the
## slot. Before T-0076 a `placed` word was appended, which made the slot's contents
## (and, with a wide label, its size) move under the player the moment they placed
## the first tower.
## The selection is still a separate channel: the fill and the text colour, plus the
## `selected_prefix` marker - all of which are drawn from the same entry, so neither
## cue can hide the other and neither touches the placement border.
func _dress_slot(entry: Dictionary, label: Label, slot: PanelContainer) -> void:
	var text := _item_text(String(entry["type_id"]), String(entry["tier"]))
	var chosen := int(entry["id"]) == _selected_id and String(entry["group"]) == GROUP_TOWERS
	if chosen:
		text = selected_prefix + text
	label.text = text
	var box := StyleBoxFlat.new()
	box.bg_color = selected_fill if chosen else Color(0.14, 0.17, 0.15, 0.9)
	box.border_color = _border_colour(_state_of(entry))
	box.set_border_width_all(slot_border_width)
	box.set_corner_radius_all(slot_corner_radius)
	box.content_margin_left = slot_padding
	box.content_margin_right = slot_padding
	slot.add_theme_stylebox_override("panel", box)
	label.add_theme_color_override("font_color", selected_colour if chosen else idle_colour)


## One item's text: its type and its tier, joined by `field_separator` - "arrow ·
## T2". The slot and the drag ghost both read it from here, so the tower the player
## carries and the slot they picked it out of cannot drift apart (T-0078).
func _item_text(type_id: String, tier_text: String) -> String:
	var text := type_id
	if tier_text != "":
		text += field_separator + tier_text
	return text


## Where a drawn slot's item is: "locked" beats "placed" beats "in hand", because
## a locked slot cannot be acted on whatever it holds.
func _state_of(entry: Dictionary) -> String:
	if _wave_locked:
		return "locked"
	if bool(entry["placed"]):
		return "placed"
	return "in_hand"


func _border_colour(state: String) -> Color:
	match state:
		"placed":
			return placed_border_colour
		"locked":
			return locked_border_colour
		_:
			return hand_border_colour


func _slot_side() -> int:
	return maxi(slot_side, 1)


func _placed_count(group_id: String) -> int:
	var total := 0
	for raw in _items_of(group_id):
		if bool((raw as Dictionary).get("placed", false)):
			total += 1
	return total


## The state of every drawn slot, in drawing order: `group:index=state`.
func _states() -> Array:
	var out: Array = []
	for entry in _slots:
		out.append("%s:%d=%s" % [String(entry["group"]), int(entry["index"]), _state_of(entry)])
	return out


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
## A live drag is answered first (T-0078), because its motion and its release land
## outside the bar's rect, where `claim_point()` is false.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _update_drag(event):
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
		(nodes["count"] as Label).text = _count_text(group_id) if not _stale else ""
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


## The header's count. Towers show both numbers (T-0075): how many the run holds,
## and how many of those stand on the board. Upgrades are all in hand by
## construction (an equipped upgrade has left the pool), so a second number there
## would always be zero - noise, not information.
func _count_text(group_id: String) -> String:
	var total := _items_of(group_id).size()
	if group_id == GROUP_TOWERS:
		return tower_count_format % [total, _placed_count(group_id), placed_word]
	return str(total)


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
