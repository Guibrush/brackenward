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
##   does; this file raises `tower_selected` on the press and `tower_clicked` on the
##   release, and builds no window. During a wave the bar stays drawn and readable
##   for the same reason: with no modifying action of its own, there is nothing
##   here to lock - `set_wave_locked()` only repaints the border and puts down a
##   gesture the phase change interrupted.
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
##   gesture. A **placed** tower begins no drag (its window waits for the release,
##   T-0085), and `set_wave_locked(true)` suppresses one. The point is in viewport
##   coordinates, the space `MapInput.intent_for()` reports: the bar does not
##   convert to world, because it does not own the board's transform.
## * **A press waits to learn whether it is a click (T-0085).** A press on a tower
##   slot - in hand **or placed** - selects it and records it as the *click
##   candidate*; the tower window opens on the **release**, and only when the
##   release was not a drop. Before this the press opened the window and
##   `tower_drag_started` closed it again, so a gesture that was about to become a
##   drag flashed a window for a frame. A release that ends a drag inside the bar, or
##   under `drag_threshold_px`, is a click and opens the window; a release that drops
##   opens nothing. A **placed** slot drags nothing, so its candidate waits for the
##   plain release `_release_click()` answers. A press anywhere else in the bar, a
##   cancelled drag, `unbind()` and the wave lock coming on all clear the candidate,
##   so a release can only open a window for a press that is still the player's.
## * **Pointer only.** The gesture reads the mouse button and motion directly,
##   because `MapInput` has no drag intent - a stick has no "drag", and inventing
##   one there would make a pointer gesture look like a pad action. Gamepad and
##   keyboard keep the click-then-tile path; the press itself still goes through
##   `MapInput` in `handle_input()`, so the selection keeps its one door.
## * **A controller face, driven from outside (T-0090).** Left/right moves a
##   **focus** across the current page's tower slots, confirm selects and arms the
##   focused tower, dismiss clears the focus. The bar still reads **no** key or pad
##   button for it: `focus_tower()`, `activate_focused()` and `clear_focus()` are a
##   door the panel calls (T-0091), so the one input door above is untouched and the
##   keyboard keeps one owner. Focus is drawn as a `ReferenceRect` named
##   `FocusFrame` - one persistent child added after the ghost, framing the focused
##   slot one pixel outside its own rect - and it is **not** the selection: state
##   stays the slot's border and selection stays the fill, text colour and prefix,
##   so three cues on one slot never overwrite each other. `activate_focused()` goes
##   through `_select(..., "pad")`, which raises `tower_selected` (the panel arms the
##   tower) and never `tower_clicked`: a controller selection opens no window.
##
## Prints on stdout, one line per event:
##   INVENTORY_BAR_SHOWN {json}    once per draw whose content changed
##   INVENTORY_BAR_STALE {json}    once per distinct stale mismatch caught
##   INVENTORY_BAR_PAGE {json}     once per page change, with the page before/after
##   INVENTORY_BAR_SELECT {json}   once per tower selected
##   INVENTORY_BAR_CLICK {json}    once per press-and-release that opens a window
##   INVENTORY_BAR_DRAG {json}     once per drag begun or cancelled
##   INVENTORY_BAR_DROP {json}     once per release that ended a drag
##   INVENTORY_BAR_FOCUS {json}    once per focus move or clear
##   INVENTORY_BAR_REJECTED {json} a bind or call this bar refused

const MapInputScript := preload("res://src/ui/map_input.gd")

## The towers group's id, and the upgrades group's: the same strings the session's
## own offer table uses for a kind, so a caller can talk about them by name.
const GROUP_TOWERS := "towers"
const GROUP_UPGRADES := "upgrades"

## How far, in pixels, the focus frame is drawn **outside** the slot it frames
## (T-0090). One pixel: enough that the frame does not sit on the slot's own border -
## so the state border stays readable inside it - and small enough that it still reads
## as one slot. Not exported: it is the relationship the brief fixes, not a feel value.
const FOCUS_FRAME_EXPAND := 1.0

## A tower in the bar was selected: the **press** on its slot (T-0085). `instance_id`
## is the inventory's id. This is the selection door - the level's panel hears it and
## selects the same tower - and deliberately not the window's door: a press that is
## about to become a drag must not open a window, so the window waits for
## `tower_clicked`.
signal tower_selected(instance_id: int)
## A tower slot was **clicked**: pressed and released without the gesture becoming a
## drop (T-0085). `instance_id` is the inventory's id, and this is the door the tower
## window opens on (`boot.gd`), for a tower in hand and for one already placed. The
## press alone raises nothing here, which is the whole point: the release is the
## first moment the bar knows the gesture was a click.
signal tower_clicked(instance_id: int)
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
## click on a tower in hand announces nothing, which is what keeps the window it
## opens on release from being closed again by a signal meant for drags. Never raised
## for a placed slot and never while `set_wave_locked(true)` is in force. It exists so
## that a gesture which turns into a drag can put away a window already open for
## another tower (T-0080), before the release can place under it.
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

@export_group("Tuning — the controller focus (T-0090, PLACEHOLDER)")
## Colour of the focus frame: the cue a controller drives. Near-white, and
## deliberately outside the selection tint (`selected_colour`) and all three state
## borders, so a slot can be focused, selected and placed at once and show three
## separate cues that cannot be mistaken for each other.
@export var focus_colour: Color = Color(0.97, 0.97, 0.92, 1.0)
## Border thickness of the focus frame, in pixels. Range 1-4: below 1 the frame stops
## reading at 1152x648, and above 4 it starts to look like a state border.
@export var focus_border_width: int = 2

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
## The click candidate (T-0085): the tower slot whose press is still waiting for its
## release, or -1. Set by `handle_input()` on a tower slot - in hand or placed - so
## the press can be a drag or a click; spent by `_emit_click()`, and cleared by a
## press anywhere else, a cancelled drag, `unbind()` and the wave lock.
var _click_id: int = -1
## The ghost: one persistent child of the bar, built once outside `_rebuild()` so a
## slot rebuild cannot free it mid-gesture. Added last, so it draws over the row.
var _ghost: Panel = null
var _ghost_label: Label = null
## The controller focus (T-0090): the instance the frame is drawn on, or -1 when
## nothing is focused. Only the id is stored - the index is derived from the page as
## drawn, so a rebuild cannot leave the focus pointing at a slot that is not there.
var _focus_id: int = -1
## The focus frame: one persistent child of the bar, added after the ghost so it draws
## over the slots, and built outside `_rebuild()` for the ghost's reason - a rebuild
## runs on every selection and page change and must not free the cue mid-walk.
var _focus_frame: ReferenceRect = null


func _ready() -> void:
	_build()
	_ensure_ghost()
	_ensure_focus_frame()
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
	_click_id = -1
	_flow = null
	_shown = {}
	_forced = {}
	_stale = false
	_selected_id = -1
	clear_focus()
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
## task has no modifying action of its own. On a tower **in hand** the press also
## begins a drag (T-0078): the selection is today's meaning and stands either way.
## On any tower slot it also records the click candidate (T-0085), which is what the
## release uses to decide whether a window opens.
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
		# A press anywhere that is not a tower slot is not a click on a tower (T-0085):
		# the candidate from an earlier press cannot survive it.
		_click_id = -1
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
		# The press is a click candidate whether or not this slot drags (T-0085): a
		# placed slot drags nothing but still opens its window on release, and a
		# tower in hand is a click until the motion says otherwise.
		_click_id = slot_id if bool(out["applied"]) else -1
		# A drag needs a pointer, so a pad or a key can never start one: those never
		# carry a `pointer` and never reach here (see the header).
		if drags and bool(out["applied"]):
			out["drag"] = _begin_drag(slot_id, point, slot_text)
		return out

	_click_id = -1
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
	# suppresses the drag, so it also ends one that is already live (T-0078). A press
	# still waiting for its release is no longer the player's either (T-0085): the
	# phase changed under it, so it opens nothing.
	if locked:
		_cancel_drag("the wave lock came on")
		_click_id = -1
	_rebuild()
	print("INVENTORY_BAR_LOCK " + JSON.stringify({
		"locked": _wave_locked,
		"slots": _slots.size(),
		"states": _states(),
	}))


# --- the controller focus (T-0090) -------------------------------------------

## Moves the controller focus by `delta` (+1 right, -1 left) across the **current
## page's** tower slots and returns the focused instance id, or -1 when the group is
## empty. With nothing focused the first slot is where it lands, whatever the
## direction; from there the index wraps with `posmod`, so left at the first slot goes
## to the last. Called by the panel (T-0091): the bar itself still reads no keys.
func focus_tower(delta: int) -> int:
	var items := _page_items(GROUP_TOWERS)
	var count := items.size()
	if count == 0:
		clear_focus()
		return -1
	var current := _focus_index_of(items)
	var index := 0 if current < 0 else int(posmod(current + delta, count))
	_set_focus(int((items[index] as Dictionary).get("id", -1)))
	_place_focus_frame()
	return _focus_id


## The instance the focus frame is drawn on, or -1 when nothing is focused - including
## when the focused tower is not on the page drawn, because a focus the player cannot
## see is not a focus.
func focused_instance() -> int:
	if _focus_id == -1 or not _focus_on_page():
		return -1
	return _focus_id


## Selects **and arms** the focused tower: confirm on a pad, through `_select()`, so
## it is the same selection door a click uses. `tower_selected` is raised (the panel
## arms the tower and the two views agree) and `tower_clicked` is not - a controller
## selection is not a request for the tower window, which is a pointer's click
## (T-0085). False when nothing is focused or the tower is no longer drawn.
func activate_focused() -> bool:
	var instance_id := focused_instance()
	if instance_id < 0:
		return false
	# A pad selection is not a click: a release a pointer press may still owe this bar
	# must not open a window over the selection the pad just made.
	_click_id = -1
	var selected := _select(instance_id, "pad")
	_place_focus_frame()
	return selected


## Drops the focus and hides the frame. The selection is untouched: focus and
## selection are two cues, so a player who backs out of the bar keeps what they had
## selected.
func clear_focus() -> void:
	_set_focus(-1)
	_place_focus_frame()


## The focus frame's rect as the player sees it, or an empty rect while it is not
## showing - the same convention as `ghost_rect()`.
func focus_rect() -> Rect2:
	if _focus_frame == null or not is_instance_valid(_focus_frame) or not _focus_frame.visible:
		return Rect2()
	return _focus_frame.get_global_rect()


# --- internals: the focus frame ---------------------------------------------

## Builds the frame once, as the bar's **last** child so it draws over the row, and
## outside `_rebuild()` so no rebuild frees it. `editor_only` is switched off on
## purpose: a `ReferenceRect` draws nothing in a running game while it is on, which
## would make this cue an editor-only one by accident.
func _ensure_focus_frame() -> void:
	if _focus_frame != null and is_instance_valid(_focus_frame):
		return
	var frame := ReferenceRect.new()
	frame.name = "FocusFrame"
	# A view, never a target: the frame must not eat the click on the slot it frames.
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.editor_only = false
	frame.visible = false
	add_child(frame)
	_focus_frame = frame
	_apply_focus_style()
	set_process(false)


## The frame's colour and thickness, from the two exports. Applied on build and again
## on every placement, so a designer tuning `focus_colour` or `focus_border_width` in
## the inspector sees it in the game without an edit here. `ReferenceRect` ignores a
## value it already holds, so calling this per frame costs two comparisons.
func _apply_focus_style() -> void:
	if _focus_frame == null or not is_instance_valid(_focus_frame):
		return
	if _focus_frame.border_color != focus_colour:
		_focus_frame.border_color = focus_colour
	var width := maxi(focus_border_width, 0)
	if _focus_frame.border_width != width:
		_focus_frame.border_width = width


## The frame's upkeep while something is focused: the slot it surrounds is laid out by
## a container, so the frame is placed from that slot's rect every frame instead of
## only when the focus moves (T-0090). A rebuild, a page change, a container reflow and
## a window resize all end in the same place this way, and `_place_focus_frame()` is a
## no-op when the rect has not changed. Processing is off whenever nothing is focused.
func _process(_delta: float) -> void:
	_place_focus_frame()


## Places the frame on the focused slot, or hides it. Also the one place the focus is
## clamped: it lives on the current page's tower slots, so an id that page no longer
## holds is not a focus any more - it clamps to that page's last slot, or clears when
## the page holds no towers at all (the two answers the brief allows, chosen by
## whether there is anywhere to go). Never re-enters itself: it writes through
## `_set_focus()` and does its own placing.
func _place_focus_frame() -> void:
	if _focus_frame == null or not is_instance_valid(_focus_frame):
		return
	_apply_focus_style()
	if _focus_id == -1:
		_focus_frame.visible = false
		return
	if not _focus_on_page():
		_clamp_focus()
		if _focus_id == -1:
			_focus_frame.visible = false
			return
	var rect := _focused_slot_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		# The slot is drawn but the container has not laid it out yet - the rebuild of
		# this very frame. Leaving the frame where it was for one frame is better than
		# placing it at the origin, and `_process` or the next rebuild catches up.
		_focus_frame.visible = _focus_frame.visible and visible
		return
	_focus_frame.visible = visible
	var framed := rect.grow(FOCUS_FRAME_EXPAND)
	if not _focus_frame.size.is_equal_approx(framed.size):
		_focus_frame.size = framed.size
	if not _focus_frame.global_position.is_equal_approx(framed.position):
		_focus_frame.global_position = framed.position


## The focus's one writer: stores the id, turns the frame's upkeep on and off with it,
## and prints one line per change. It does **not** place the frame - the caller does,
## which is what keeps `_place_focus_frame()`'s clamp from recursing into itself.
func _set_focus(instance_id: int) -> void:
	if _focus_id == instance_id:
		return
	_focus_id = instance_id
	set_process(instance_id != -1)
	print("INVENTORY_BAR_FOCUS " + JSON.stringify({
		"instance": instance_id,
		"index": _focus_index_of(_page_items(GROUP_TOWERS)),
		"towers": _page_items(GROUP_TOWERS).size(),
		"page": _page_of(GROUP_TOWERS) + 1,
	}))


## The focused tower is not on the drawn page any more: clamp to that page's last slot,
## or clear the focus when it holds no towers.
func _clamp_focus() -> void:
	var items := _page_items(GROUP_TOWERS)
	if items.is_empty():
		_set_focus(-1)
		return
	_set_focus(int((items[items.size() - 1] as Dictionary).get("id", -1)))


## The global rect of the slot the focus is drawn on, or an empty rect when that slot
## is not drawn (it is on another page, or the row has not been rebuilt yet).
func _focused_slot_rect() -> Rect2:
	for entry in _slots:
		if String(entry["group"]) == GROUP_TOWERS and int(entry["id"]) == _focus_id:
			return (entry["node"] as Control).get_global_rect()
	return Rect2()


## True when the focused instance is one of the tower slots on the drawn page.
func _focus_on_page() -> bool:
	return _focus_index_of(_page_items(GROUP_TOWERS)) >= 0


## The focus's index within a page's tower items, or -1 when it is not one of them.
func _focus_index_of(items: Array) -> int:
	for index in items.size():
		if int((items[index] as Dictionary).get("id", -1)) == _focus_id:
			return index
	return -1


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
		# The carried id is read before `_finish_drag()` clears it, and the release
		# opens a window only when it was **not** a drop (T-0085): a throw is a
		# gesture on the board, a click on the slot is a request for its window.
		var carried := _drag_id
		var dropped := _finish_drag(_drag_to)
		if not dropped:
			_emit_click(carried)
		get_viewport().set_input_as_handled()
		return true
	return false


## Ends the live drag at `point`: a release further than `drag_threshold_px` from
## the press **and** outside the bar raises `tower_dropped` once; anything else was
## a click (T-0085), whose window the caller opens through `_emit_click()`. Returns
## the drop verdict, so the caller never recomputes it.
func _finish_drag(point: Vector2) -> bool:
	var instance := _drag_id
	var travelled := point.distance_to(_drag_from)
	var outside := not _bar_contains(point)
	var dropped := travelled > drag_threshold_px and outside
	if dropped:
		_announce_drag()
	_drag_id = -1
	_drag_text = ""
	_drag_announced = false
	# The gesture is over, so its press is spent whether it was thrown or clicked:
	# a candidate that outlived it would open a window on the next release anywhere.
	_click_id = -1
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
	return dropped


## Raises `tower_clicked` for the press whose release ended the gesture as a click
## (T-0085), and spends the candidate. One door for both halves - a drag that ended
## inside the bar and a placed slot that never dragged - so the window has one
## trigger and the candidate has one place it is cleared by.
func _emit_click(instance_id: int) -> void:
	if instance_id < 0:
		_click_id = -1
		return
	_click_id = -1
	print("INVENTORY_BAR_CLICK " + JSON.stringify({
		"instance": instance_id,
		"locked": _wave_locked,
		"selected": _selected_id,
		"source": "release",
	}))
	tower_clicked.emit(instance_id)


## The release half of a click on a **placed** slot (T-0085). A placed tower begins
## no drag, so nothing else answers its release: the candidate recorded by the press
## is spent here. Returns true when the event was this bar's.
func _release_click(event: InputEvent) -> bool:
	if _click_id == -1:
		return false
	if not (event is InputEventMouseButton):
		return false
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or button.pressed:
		return false
	var instance := _click_id
	get_viewport().set_input_as_handled()
	_emit_click(instance)
	return true


## Puts down a tower held mid-gesture without raising `tower_dropped`: the gesture
## stopped being the player's (a wave started, or the bar was unbound), so nothing
## was thrown anywhere - and nothing opens on the release that may still arrive
## (T-0085), so the candidate goes with it.
func _cancel_drag(why: String) -> void:
	_click_id = -1
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

	# The frame is placed from the row that was just filled (T-0090): a rebuild can
	# move, renumber or replace the focused slot, so the cue follows it here as well
	# as from `_process`.
	_place_focus_frame()


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
## outside the bar's rect, where `claim_point()` is false; a placed slot's release is
## answered second (T-0085), for the same reason in reverse - no drag exists to claim
## it, but it is still the release of a bar press.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _update_drag(event):
		return
	# A placed slot's release, which no drag will claim (T-0085).
	if _release_click(event):
		return
	var result: Dictionary = _router.intent_for(event)
	if int(result["intent"]) != MapInputScript.Intent.CONFIRM or not result.has("pointer"):
		return
	if not claim_point(result["pointer"]):
		# A press that lands off the bar starts a new gesture too, so the earlier
		# press's candidate cannot survive it (T-0085).
		_click_id = -1
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
