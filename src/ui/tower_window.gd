extends Control

## The floating tower window (T-0069): everything about one tower in one place -
## what it is, its tier, what it carries, and the three actions.
##
## CONTRACT
## --------
## * **One window, one tower.** `open_for(instance_id)` shows the inventory's tower
##   instance with that id; there is no second copy of the tower's data here. The
##   tier is read from `TowerInstance.tier`, the equipped list from
##   `TowerInstance.upgrades()`, and the walls (slots) from `TowerInstance.slot_count()`.
##   A window that cached any of those would be a second owner of it.
## * **It opens from the bar or from the board.** The bar raises `tower_selected`
##   for a click on one of its slots; the level's build panel raises
##   `tower_inspected` for a click on a placed tower. The boot wires both to
##   `open_for()`, so both doors reach one window and neither screen builds one.
## * **Possession is enough to equip.** A tower in hand is an inventory instance
##   with no node and no tile, and `Inventory.apply_upgrade_to_tower()` needs
##   neither, so the window equips on it directly. A tier needs a price and a
##   take-back needs a tile, so both need a level: the arena caches the tower
##   scene's tier table and prices an in-hand tower from it (T-0087), and a tower
##   in hand is upgraded through `Arena.upgrade_inventory_tower()`. With no level
##   open (the map screen) there is nothing to price against, and that refusal is
##   a sentence, not a disabled row.
## * **Every action goes through the owner of the rule.** Equipping calls the
##   inventory; tier-up and take-back call the arena, which owns the phase lock and
##   the price. The window never charges, raises or moves anything itself, so a
##   refused action is the owner's refusal and the window reports the owner's words
##   verbatim (`Inventory.last_refusal()`, `Arena.last_refusal()`).
## * **A refusal is told, not drawn** (T-0086). The window ends at its last action
##   row: it has no status line, no refusal sentence and no hint. The owner's words
##   go to `TOWER_WINDOW_REFUSED` and to the `refused` signal, and `reason()` hands
##   the last one to a caller; the tower, the gold and the row stay as they were.
## * **Read-only during a wave.** The window still opens and reads; `equip`,
##   `raise_tier` and `take_back` are each refused, and the sentence is the
##   arena's own. Equipping has no arena door, so the window asks the arena to
##   state its lock sentence (`_arena_wave_reason()`): every arena refusal happens
##   before anything is charged or moved, so asking is not acting. The alternative
##   - a copy of "towers are locked during a wave" written here - would be a second
##   owner of one sentence and could drift from the arena's.
## * **A full tower refuses the third upgrade; nothing is destroyed.** The
##   inventory refuses (`no free upgrade slot (2 of 2 used); replace one instead`)
##   because `apply_upgrade_to_tower()` checks the free slot before it touches the
##   hand. This window therefore offers no replace action and no "warning before
##   destroying" is needed: there is no destroy path here to warn about. The
##   refusal is reported, the upgrade stays in hand, and the tower keeps what it had.
## * **The bar's list needs no filtering here.** `Inventory.upgrades()` is the
##   pool *in hand*; an applied upgrade lives on its tower and has left that pool,
##   so equipping removes the item from the bar by construction. This window adds
##   no flag and no second list.
## * **Closing is allowed** (unlike the choice modal, which grants something and so
##   cannot be thrown away): the window is a view and an action list, and `DISMISS`
##   or a click outside the panel closes it. While it is open it consumes every
##   mapped intent (`_input`), so the bar and the build panel behind it are inert.
## * **It is a popover, not a centred sheet** (T-0083). The scene has no dimming
##   backdrop and no `Center` container: the panel is placed beside the click that
##   opened it - above and to the right, `anchor_gap` away - clamped inside the
##   viewport with `viewport_margin` to spare, and flipped below when the clamped
##   panel would cover that click. Placement happens after one layout frame in which
##   the panel is shown **fully transparent**, so its own measured size is what the
##   arithmetic uses and the player never sees the scene's default rect; the
##   placement tick restores the alpha, so the first visible frame is the final
##   rect. `is_revealed()` is false until then, and a pointer confirm before the
##   placement - including the click that opened the window - is ignored.
##   outside `panel_rect()` closes the window (`why = "clicked outside"`), consumes
##   the event and does nothing else; a pointer confirm that arrives before the
##   panel has been placed - including the click that opened the window - is
##   ignored, because `_input` order can deliver that click here after the bar or
##   the build panel raised the door that opened it.
## * **Pad caveat.** The anchor is the click that opened the window: the point the
##   session just delivered. A pad open delivers no click, so the anchor falls back
##   to the last pointer position this window saw, which is stale for a pad player
##   (and `(0, 0)` in a headless run). Anchoring on the focused slot or tile is the
##   controller task's; this file does not guess a pad position.
## * Input has one door, `handle_input()`, which asks `MapInput` for the intent:
##   keyboard, mouse and gamepad reach the same three actions.
##
## Prints on stdout, one line per event:
##   TOWER_WINDOW_OPEN {json}      once per open, with the tower as it stands
##   TOWER_WINDOW_EQUIP {json}     once per applied upgrade, with both sides before/after
##   TOWER_WINDOW_TIER {json}      once per bought tier, with gold and tier before/after
##   TOWER_WINDOW_TAKE_BACK {json} once per tower returned to the inventory
##   TOWER_WINDOW_REFUSED {json}   every refused action, with the owner's reason
##   TOWER_WINDOW_CLOSED {json}    once per close, with why
##   TOWER_WINDOW_SHOWN {json}     once per draw whose content changed
##   TOWER_WINDOW_PLACED {json}    once per open, with the anchor and the panel's rect

signal closed(why: String)
## An action was applied: `action` is "equip" | "tier" | "take_back", `tier` the
## tower's tier after it, `gold` the run's gold after it.
signal action_applied(action: String, instance_id: int, tier: int, gold: int)
## An action was refused. `why` is the owner's sentence, verbatim.
signal refused(action: String, why: String)

const MapInputScript := preload("res://src/ui/map_input.gd")

const KIND_EQUIP := "equip"
const KIND_TIER := "tier"
const KIND_TAKE_BACK := "take_back"

## Layout ticks the placement waits for before revealing the window (T-0084). One is
## enough: the panel is shown transparent first so its wrapping labels are measured at
## the real width, then the next tick places it and turns it opaque.

@export_group("Layout — node paths")
@export var title_path: NodePath = ^"Panel/Margin/Column/Title"
@export var identity_path: NodePath = ^"Panel/Margin/Column/Identity"
@export var tier_path: NodePath = ^"Panel/Margin/Column/Tier"
@export var equipped_path: NodePath = ^"Panel/Margin/Column/Equipped"
@export var rows_path: NodePath = ^"Panel/Margin/Column/Rows"
## The panel itself, so a click outside it can be told from one inside it.
@export var panel_path: NodePath = ^"Panel"

@export_group("Layout — anchor (T-0083)")
## The panel's narrowest width, in pixels: a popover column, not a sheet. Range
## 280-360.
@export var panel_min_width: int = 320
## The panel's hard ceiling, in pixels. A wider panel stops reading as a popover.
## Range 320-420; the design ceiling is 360.
@export var panel_max_width: int = 360
## Distance kept between the click that opened the window and the panel's edges.
## Range 8-32.
@export var anchor_gap: int = 18
## Distance kept between the panel and the viewport's edges when it is clamped.
## Range 0-24.
@export var viewport_margin: int = 8

@export_group("Copy")
## The window's title: the tower's type id.
@export var title_format: String = "%s"
## The identity line: instance id and where the tower is.
@export var identity_format: String = "instance %d · %s"
@export var placed_text: String = "placed"
@export var in_hand_text: String = "in hand"
@export var tier_format: String = "Tier T%d"
@export var equipped_format: String = "Carrying: %s"
@export var nothing_equipped_text: String = "nothing equipped"
@export var slots_format: String = " %d/%d slots"
@export var gold_format: String = "Gold %d"
## The sentence `_arena_wave_reason()` falls back to when there is no arena to ask.
## It is no longer drawn: a refusal is logged and emitted, never displayed (T-0086).
@export var read_only_text: String = "read only: a wave is running - nothing can be changed"
## One row per upgrade in hand.
@export var equip_row_format: String = "Equip %s"
@export var tier_row_format: String = "Upgrade to T%d — %d gold"
@export var tier_max_row_text: String = "Upgrade — already at the last tier"
## Said on the tier row when there is no arena at all: the map screen has no level
## to price a tier against (T-0087). With a level open, a tower in hand is priced
## from the arena's own table and this sentence is never drawn.
@export var tier_unpriced_text: String = "Upgrade tier — open a level to price it"
@export var take_back_row_text: String = "Take back to the inventory"
@export var no_upgrades_row_text: String = "no upgrades in hand to equip"
@export var no_session_text: String = "no run"
## Said when tier-up is asked for and no level is open: there is no price table,
## which only a level has.
@export var tier_no_level_text: String = "no level is open: a tier is bought in a level"
## Said when take-back is asked for and no level is open.
@export var take_back_no_level_text: String = "no level is open: there is no tile to take it from"
## Said when take-back is asked for on a tower that is already in hand.
@export var take_back_in_hand_text: String = "this tower is already in the inventory"
## Between an option's label and its detail.
@export var field_separator: String = " · "
@export var focus_marker: String = "> "

@export_group("Tuning — PLACEHOLDER (T-0069)")
## Height of one action row, in pixels. Same number as the choice modal's row, so
## one kind of list keeps one rhythm. Range 32-56.
@export var row_min_height: int = 38

var _flow = null
var _arena = null
var _router = MapInputScript.new()

var _open: bool = false
var _open_id: int = -1
## Where the window was opened: the click that opened it (T-0083), and the process
## frame that click landed on. The frame is what lets `handle_input()` ignore the
## pointer confirm that opened the window instead of reading it as a click outside.
var _anchor: Vector2 = Vector2.ZERO
var _open_frame: int = -1
## True once the panel has been placed for the current open. Before that there is
## no rect a click could be outside of.
var _panel_placed: bool = false
## Process ticks left before the panel is placed: 1 is set on open and counts down
## in `_process`, so the placement uses a laid-out panel (see `_place_panel()`).
var _place_countdown: int = -1
## The last pointer this window saw, recorded from `_input()` even while it is
## closed. The click that opens the window is delivered here before the bar or the
## build panel raises the door that opens it, and `Viewport.get_mouse_position()`
## answers from the display server - which is `(0, 0)` in a headless run.
var _last_pointer: Vector2 = Vector2.INF
## One entry per focusable row, in drawing order:
##     index, kind, id, type_id, label, node
var _rows: Array = []
var _focus: int = -1
var _reason: String = ""
var _last_signature: String = ""
var _equips: int = 0
var _tiers: int = 0
var _take_backs: int = 0


func _ready() -> void:
	_apply_copy()
	hide()


# --- binding ----------------------------------------------------------------

## Wires the window to one run session (its inventory and its gold). A second
## session is refused rather than silently replacing the first: one window shows
## one run.
func bind_session(flow) -> bool:
	if flow == null:
		return _reject("bind the tower window", "no run session was handed over")
	if _flow != null and is_instance_valid(_flow) and _flow != flow:
		return _reject("bind the tower window", "this window is already bound to another run")
	_flow = flow
	_connect_session()
	refresh()
	return true


## Wires the window to the level in play, or to nothing when the level closes. The
## arena owns the phase lock and the tier price; a window with no arena still reads
## a tower in hand and still equips on it, and refuses the two map actions.
func bind_arena(arena) -> bool:
	_arena = arena if arena != null and is_instance_valid(arena) else null
	refresh()
	return true


func unbind() -> void:
	_disconnect_session()
	_open = false
	_open_id = -1
	_panel_placed = false
	# A countdown left running would place a panel for a run this window no longer
	# has; `_process` also guards on `_open`, and this is the second lock (T-0084).
	_place_countdown = -1
	_flow = null
	_arena = null
	_rows.clear()
	_focus = -1
	_reason = ""
	_last_signature = ""
	_clear_rows()
	hide()


func flow():
	return _flow


func arena():
	return _arena


# --- opening and closing ----------------------------------------------------

## Opens the window on the inventory tower `instance_id`. Refused, with nothing
## shown, for an id the inventory does not hold - a window on a tower that does not
## exist would be a view of nothing.
func open_for(instance_id: int) -> bool:
	if _flow == null or not is_instance_valid(_flow):
		return _reject("open the tower window", "no run session is bound")
	var tower = _tower_instance(instance_id)
	if tower == null:
		return _reject(
			"open the tower window", "no tower %d is in the inventory" % instance_id
		)
	_open = true
	_open_id = instance_id
	_focus = 0
	_reason = ""
	_anchor = _click_point()
	_open_frame = Engine.get_process_frames()
	_panel_placed = false
	# Shown fully transparent for the layout tick, then placed and made opaque by
	# `_place_panel()` (T-0084). A transparent Control still lays out, so the wrapping
	# labels measure at the real width; the player never sees the scene's default
	# rect, because nothing is drawn until the alpha goes back to 1.
	modulate.a = 0.0
	show()
	refresh(true)
	_place_countdown = 1
	print("TOWER_WINDOW_OPEN " + JSON.stringify({
		"instance": instance_id,
		"type_id": String(tower.type_id),
		"tier": int(tower.tier),
		"placed": bool(tower.placed),
		"upgrades": tower.upgrade_ids(),
		"slots": [tower.upgrade_count(), tower.slot_count()],
		"read_only": read_only(),
		"phase": _phase_name(),
		"gold": _gold(),
		"rows": _rows.size(),
		"anchor": [_anchor.x, _anchor.y],
		"frame": _open_frame,
	}))
	return true


func close(why: String = "") -> bool:
	if not _open:
		return false
	_open = false
	hide()
	_panel_placed = false
	_place_countdown = -1
	modulate.a = 1.0
	var instance_id := _open_id
	_open_id = -1
	_rows.clear()
	_focus = -1
	_reason = ""
	_clear_rows()
	print("TOWER_WINDOW_CLOSED " + JSON.stringify({"instance": instance_id, "why": why}))
	closed.emit(why)
	return true


func is_open() -> bool:
	return _open and visible


## True once the player can actually see the window: open, visible, and no longer in
## the transparent layout tick before placement (T-0084). The bug this distinguishes
## from `is_open()` is a window whose scene rect is drawn for a frame before the
## panel is placed.
func is_revealed() -> bool:
	return is_open() and modulate.a > 0.0


func opened_instance() -> int:
	return _open_id


## The viewport point the window was opened at: the click that opened it (T-0083).
## The anchor is a record of that click, not a live read of the pointer, so it stays
## the same point until the next open.
func anchor_point() -> Vector2:
	return _anchor


## True while the level in play is in its wave phase. The arena owns the phase;
## with no level open (the map screen) there is no wave to be locked by.
func read_only() -> bool:
	if _arena == null or not is_instance_valid(_arena):
		return false
	if not _arena.has_method("is_wave_active"):
		return false
	return bool(_arena.is_wave_active())


# --- the three actions ------------------------------------------------------

## Moves the upgrade `upgrade_id` from hand onto the open tower. Possession is
## enough: a tower in hand has no node and no tile, and the inventory needs
## neither. Every refusal is the inventory's own sentence.
func equip(upgrade_id: int) -> bool:
	if not _can_act("equip"):
		return false
	if read_only():
		return _refuse("equip", _arena_wave_reason())
	var tower = _tower_instance(_open_id)
	if tower == null:
		return _refuse("equip", "no tower %d is in the inventory" % _open_id)
	var inventory = _flow.inventory()
	if inventory == null:
		return _refuse("equip", "the run has no inventory")
	var before: int = inventory.upgrade_count()
	if not inventory.apply_upgrade_to_tower(tower.id, upgrade_id):
		return _refuse("equip", _owner_reason(inventory.last_refusal()))
	_equips += 1
	print("TOWER_WINDOW_EQUIP " + JSON.stringify({
		"instance": tower.id,
		"upgrade": upgrade_id,
		"tier": int(tower.tier),
		"carrying": tower.upgrade_ids(),
		"slots": [tower.upgrade_count(), tower.slot_count()],
		"hand_before": before,
		"hand": inventory.upgrade_count(),
		"placed": bool(tower.placed),
		"gold": _gold(),
	}))
	_after_action("equip", tower)
	return true


## Buys the open tower's next tier out of the run's gold, through the arena. A
## tower on the board is upgraded through its node; a tower in hand has no node, so
## it goes through `Arena.upgrade_inventory_tower()` and the arena prices it from
## the table it cached off the tower scene (T-0087). Both doors charge and grant;
## this window never does either.
func raise_tier() -> bool:
	if not _can_act("tier"):
		return false
	if read_only():
		return _refuse("tier", _arena_wave_reason())
	var tower = _tower_instance(_open_id)
	if tower == null:
		return _refuse("tier", "no tower %d is in the inventory" % _open_id)
	if _arena == null:
		return _refuse("tier", tier_no_level_text)
	var node = _tower_node(tower.id)
	if node == null and not _arena.has_method("upgrade_inventory_tower"):
		return _refuse("tier", "the level cannot upgrade a tower in hand")

	var tier_before := int(tower.tier)
	var gold_before := _gold()
	var cost: int = _tier_cost(tower)
	var bought := false
	if node != null:
		bought = _arena.upgrade_tower(node)
	else:
		bought = bool(_arena.upgrade_inventory_tower(int(tower.id)))
	if not bought:
		return _refuse("tier", _owner_reason(_arena.last_refusal()))
	_tiers += 1
	print("TOWER_WINDOW_TIER " + JSON.stringify({
		"instance": tower.id,
		"tower": String(node.name) if node != null else "<in hand>",
		"placed": node != null,
		"tier_before": tier_before,
		"tier": int(tower.tier),
		"cost": cost,
		"gold_before": gold_before,
		"gold": _gold(),
		"phase": _phase_name(),
	}))
	_after_action("tier", tower)
	return true


## Returns the open tower to the inventory. It keeps its tier and its upgrades,
## which is the difference between taking a tower back and selling one.
func take_back() -> bool:
	if not _can_act("take back"):
		return false
	if read_only():
		return _refuse("take back", _arena_wave_reason())
	var tower = _tower_instance(_open_id)
	if tower == null:
		return _refuse("take back", "no tower %d is in the inventory" % _open_id)
	if _arena == null:
		return _refuse("take back", take_back_no_level_text)
	var node = _arena.tower_for_instance(tower.id) if _arena.has_method("tower_for_instance") else null
	if node == null:
		return _refuse("take back", take_back_in_hand_text)
	if not _arena.take_tower_back(node):
		return _refuse("take back", _owner_reason(_arena.last_refusal()))
	_take_backs += 1
	print("TOWER_WINDOW_TAKE_BACK " + JSON.stringify({
		"instance": tower.id,
		"tower": String(node.name),
		"tier": int(tower.tier),
		"carrying": tower.upgrade_ids(),
		"gold": _gold(),
		"phase": _phase_name(),
	}))
	_after_action("take_back", tower)
	return true


# --- input ------------------------------------------------------------------

## One door for input. `MapInput` translates the event; this method moves focus,
## runs the row under a pointer, or closes the window.
func handle_input(event: InputEvent) -> Dictionary:
	var result: Dictionary = _router.intent_for(event)
	var out := result.duplicate()
	out["applied"] = false
	if not is_open():
		out["ignored"] = "the window is not open"
		return out

	match int(result["intent"]):
		MapInputScript.Intent.FOCUS_NEXT:
			out["applied"] = _move_focus(1)
		MapInputScript.Intent.FOCUS_PREV:
			out["applied"] = _move_focus(-1)
		MapInputScript.Intent.CONFIRM:
			var index := _focus
			if result.has("pointer"):
				var pointer: Vector2 = result["pointer"]
				# The click that opened the window is delivered here too, after the
				# door that opened it: `_input` order is the tree's, not the click's.
				# Reading it as a click outside would shut the window in the frame it
				# appeared, so the opening frame - and the frame before the panel has
				# been placed at all - answers nothing.
				if not _panel_placed or Engine.get_process_frames() <= _open_frame:
					out["target"] = "opening"
					out["ignored"] = "the click that opened the window"
					return out
				if not _panel_contains(pointer):
					out["target"] = "outside"
					out["applied"] = close("clicked outside")
					return out
				index = _index_at(pointer)
			out["index"] = index
			out["target"] = "row"
			out["applied"] = activate(index)
		MapInputScript.Intent.DISMISS:
			out["target"] = "close"
			out["applied"] = close("dismiss")
		_:
			pass
	return out


## Runs row `index`: what a click and a confirm both resolve to. -1 (a click on the
## panel's margin) does nothing and prints nothing - it is not an action.
func activate(index: int) -> bool:
	if not is_open():
		return false
	if index < 0 or index >= _rows.size():
		return false
	_focus = index
	_apply_focus()
	var entry: Dictionary = _rows[index]
	match String(entry["kind"]):
		KIND_EQUIP:
			return equip(int(entry["id"]))
		KIND_TIER:
			return raise_tier()
		KIND_TAKE_BACK:
			return take_back()
	return false


## While the window is open it is the only thing in the session that answers: every
## mapped intent is consumed here, before the bar's or the build panel's `_input`
## can see it. That is what makes the screens behind it inert, and it is why the
## close path has to be this window's own.
##
## The pointer is recorded before the open check on purpose: the click that opens
## the window is delivered here first, while the window is still shut, and that
## event is the anchor (T-0083). Consuming it is the open window's business only.
func _input(event: InputEvent) -> void:
	var pointer := _pointer_of(event)
	if pointer != Vector2.INF:
		_last_pointer = pointer
	if not is_open():
		return
	var result: Dictionary = _router.intent_for(event)
	if int(result["intent"]) == MapInputScript.Intent.NONE:
		return
	get_viewport().set_input_as_handled()
	handle_input(event)


# --- queries ----------------------------------------------------------------

## The window as data: what it shows, read live from the tower, the run and the
## arena. `read_only` is the arena's phase; `cost` is the gold to reach the next
## tier, or -1 when there is none (no level to price against, or the last tier).
func state() -> Dictionary:
	var out := {
		"open": is_open(),
		"bound": _flow != null and is_instance_valid(_flow),
		"instance": _open_id,
		"type_id": "",
		"tier": 0,
		"tier_text": "",
		"placed": false,
		"carrying": [],
		"slots": [0, 0],
		"gold": _gold(),
		"gold_label": gold_format % _gold(),
		"cost": -1,
		"read_only": read_only(),
		"phase": _phase_name(),
		"rows": _rows.size(),
		"reason": _reason,
		"label": no_session_text,
	}
	if not out["bound"]:
		return out
	var tower = _tower_instance(_open_id)
	if tower == null:
		return out
	out["type_id"] = String(tower.type_id)
	out["tier"] = int(tower.tier)
	out["tier_text"] = tier_format % int(tower.tier)
	out["placed"] = bool(tower.placed)
	out["carrying"] = tower.upgrade_ids()
	out["slots"] = [tower.upgrade_count(), tower.slot_count()]
	out["cost"] = _tier_cost(tower)
	out["label"] = "%s %s%s%s" % [
		String(tower.type_id), out["tier_text"], field_separator, _equipped_text(tower),
	]
	return out


## The rows as drawn, without the Control references: safe to JSON, and what a
## caller asserts against.
func rows() -> Array:
	var out: Array = []
	for entry in _rows:
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		copy.erase("node")
		out.append(copy)
	return out


func row_count() -> int:
	return _rows.size()


func row(index: int) -> Dictionary:
	if index < 0 or index >= _rows.size():
		return {}
	var copy: Dictionary = (_rows[index] as Dictionary).duplicate(true)
	copy.erase("node")
	return copy


func row_rect(index: int) -> Rect2:
	if index < 0 or index >= _rows.size():
		return Rect2()
	var node = (_rows[index] as Dictionary).get("node", null)
	if node is Control:
		return (node as Control).get_global_rect()
	return Rect2()


## The rect of the drawn panel, so a demo aims a click at the window rather than
## at a pixel it guessed.
func panel_rect() -> Rect2:
	var panel := _node(panel_path)
	if panel is Control:
		return (panel as Control).get_global_rect()
	return Rect2()


func focus_index() -> int:
	return _focus


func reason() -> String:
	return _reason


func equips() -> int:
	return _equips


func tiers_bought() -> int:
	return _tiers


func take_backs() -> int:
	return _take_backs


# --- drawing ----------------------------------------------------------------

## Redraws the window from the tower as it stands. Prints `TOWER_WINDOW_SHOWN` only
## when what is drawn differs from the previous draw, so one action prints one
## line even though the inventory's signal fires once per change.
func refresh(force: bool = false) -> void:
	_rebuild_rows()
	_apply_copy()
	var signature := JSON.stringify({
		"instance": _open_id,
		"read_only": read_only(),
		"gold": _gold(),
		"rows": _row_summary(),
		"reason": _reason,
		"open": is_open(),
	})
	if (force or signature != _last_signature) and _flow != null:
		_last_signature = signature
		print("TOWER_WINDOW_SHOWN " + JSON.stringify({
			"instance": _open_id,
			"read_only": read_only(),
			"gold": _gold(),
			"rows": _row_summary(),
			"reason": _reason,
			"visible": visible,
		}))


func _rebuild_rows() -> void:
	var previous_key := _focused_key()
	_clear_rows()
	_rows.clear()

	var tower = _tower_instance(_open_id) if is_open() else null
	if tower == null:
		_focus = -1
		return

	var inventory = _flow.inventory() if _flow != null else null
	var hand: Array = inventory.upgrades() if inventory != null else []
	for raw in hand:
		var upgrade = raw
		_add_row({
			"kind": KIND_EQUIP,
			"id": int(upgrade.id),
			"type_id": String(upgrade.type_id),
			"label": equip_row_format % String(upgrade.type_id),
		})

	var cost: int = _tier_cost(tower)
	var tier_label := tier_unpriced_text
	if cost >= 0:
		tier_label = tier_row_format % [int(tower.tier) + 1, cost]
	elif _arena != null and is_instance_valid(_arena):
		# A level is open, so -1 here is the last tier, not a missing price: the
		# arena's table is the one the tower in hand is priced from (T-0087).
		tier_label = tier_max_row_text
	_add_row({
		"kind": KIND_TIER,
		"id": int(tower.id),
		"type_id": String(tower.type_id),
		"label": tier_label,
	})

	if bool(tower.placed) and _arena != null:
		_add_row({
			"kind": KIND_TAKE_BACK,
			"id": int(tower.id),
			"type_id": String(tower.type_id),
			"label": take_back_row_text,
		})

	if _rows.is_empty():
		_focus = -1
		return
	var index := _index_of_key(previous_key)
	_focus = index if index >= 0 else 0
	_apply_focus()


func _add_row(entry: Dictionary) -> void:
	entry["index"] = _rows.size()
	var list := _node(rows_path)
	if list != null:
		var row := PanelContainer.new()
		row.name = "Row%d" % int(entry["index"])
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(0, row_min_height)
		var text := Label.new()
		text.name = "Text"
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)
		list.add_child(row)
		entry["node"] = row
	_rows.append(entry)


func _row_text(entry: Dictionary) -> String:
	var text := String(entry["label"])
	if int(entry["index"]) == _focus:
		text = focus_marker + text
	return text


func _apply_focus() -> void:
	for entry in _rows:
		var node = (entry as Dictionary).get("node", null)
		if node is PanelContainer:
			var row := node as PanelContainer
			var label := row.get_node_or_null("Text")
			if label is Label:
				(label as Label).text = _row_text(entry)


func _move_focus(delta: int) -> bool:
	if _rows.is_empty():
		return false
	_focus = int(posmod(maxi(_focus, 0) + delta, _rows.size()))
	_apply_focus()
	return true


func _index_at(point: Vector2) -> int:
	for entry in _rows:
		var node = (entry as Dictionary).get("node", null)
		if not (node is Control):
			continue
		var rect: Rect2 = (node as Control).get_global_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0 and rect.has_point(point):
			return int((entry as Dictionary)["index"])
	return -1


func _panel_contains(point: Vector2) -> bool:
	var rect := panel_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return true
	return rect.has_point(point)


func _clear_rows() -> void:
	var list := _node(rows_path)
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _apply_copy() -> void:
	var tower = _tower_instance(_open_id) if is_open() and _flow != null else null
	if tower == null:
		_set_label(title_path, no_session_text)
		_set_label(identity_path, "")
		_set_label(tier_path, "")
		_set_label(equipped_path, "")
	else:
		_set_label(title_path, title_format % String(tower.type_id))
		var where := placed_text if bool(tower.placed) else in_hand_text
		_set_label(identity_path, identity_format % [_open_id, where])
		_set_label(tier_path, tier_format % int(tower.tier))
		_set_label(equipped_path, _equipped_text(tower))
	for entry in _rows:
		var node = (entry as Dictionary).get("node", null)
		if node is PanelContainer:
			var label := (node as PanelContainer).get_node_or_null("Text")
			if label is Label:
				(label as Label).text = _row_text(entry)


func _equipped_text(tower) -> String:
	if tower == null:
		return ""
	var carrying := _type_ids(tower)
	var text := nothing_equipped_text if carrying.is_empty() else ", ".join(carrying)
	return (equipped_format % text) + (slots_format % [tower.upgrade_count(), tower.slot_count()])


# --- internals: acting ------------------------------------------------------

func _can_act(action: String) -> bool:
	if not is_open():
		return _refuse(action, "the window is not open")
	if _flow == null or not is_instance_valid(_flow):
		return _refuse(action, no_session_text)
	if _flow.inventory() == null:
		return _refuse(action, "the run has no inventory")
	return true


## Asks the arena to state the sentence it refuses a locked tower action with.
## Every arena refusal happens before anything is charged or moved, so this is a
## question about the lock, not an action. Called only while a wave is running.
func _arena_wave_reason() -> String:
	if _arena == null or not is_instance_valid(_arena):
		return read_only_text
	if _arena.has_method("upgrade_tower"):
		_arena.upgrade_tower(null)
	return _owner_reason(_arena.last_refusal())


## The owner said why; its sentence is shown as it was given. The fallbacks cover
## the one case where an owner refuses without a sentence of its own.
func _owner_reason(reason: String) -> String:
	var text := String(reason)
	if text != "":
		return text
	return "the owner refused without a reason"


func _after_action(action: String, tower) -> void:
	_reason = ""
	refresh(true)
	action_applied.emit(action, int(tower.id), int(tower.tier), _gold())


func _refuse(action: String, why: String) -> bool:
	_reason = why
	print("TOWER_WINDOW_REFUSED " + JSON.stringify({
		"action": action,
		"instance": _open_id,
		"reason": why,
		"tier": _tier_now(),
		"gold": _gold(),
		"read_only": read_only(),
		"phase": _phase_name(),
	}))
	refused.emit(action, why)
	_apply_copy()
	return false


func _reject(action: String, why: String) -> bool:
	print("TOWER_WINDOW_REFUSED " + JSON.stringify({
		"action": action,
		"reason": why,
		"open": is_open(),
	}))
	refused.emit(action, why)
	return false


# --- internals: reading the tower -------------------------------------------

func _tower_instance(instance_id: int):
	if _flow == null or not is_instance_valid(_flow) or instance_id < 0:
		return null
	var inventory = _flow.inventory()
	if inventory == null or not inventory.has_method("find_tower"):
		return null
	return inventory.find_tower(instance_id)


func _tower_node(instance_id: int):
	if _arena == null or not is_instance_valid(_arena) or not _arena.has_method("tower_for_instance"):
		return null
	return _arena.tower_for_instance(instance_id)


## Gold to reach the open tower's next tier, or -1 when there is no price (T-0087).
## A tower on the board is priced by its own node - the tier table lives there. A
## tower in hand has no node, so the arena prices it from the copy of that table it
## cached off the tower scene; with no arena (the map screen) there is nothing to
## price against and the answer is -1. One function, so `state()`, the tier row and
## `raise_tier()` cannot disagree about what the next tier costs.
func _tier_cost(tower) -> int:
	if tower == null:
		return -1
	var node = _tower_node(tower.id)
	if node != null:
		return int(node.upgrade_cost())
	if _arena == null or not is_instance_valid(_arena):
		return -1
	if not _arena.has_method("upgrade_cost_for_tier"):
		return -1
	return int(_arena.upgrade_cost_for_tier(int(tower.tier)))


func _tier_now() -> int:
	var tower = _tower_instance(_open_id)
	return int(tower.tier) if tower != null else 0


func _gold() -> int:
	if _flow == null or not is_instance_valid(_flow):
		return 0
	var run = _flow.run_state()
	return int(run.gold()) if run != null else 0


func _phase_name() -> String:
	if _arena == null or not is_instance_valid(_arena):
		return "no level"
	return _arena.phase_name() if _arena.has_method("phase_name") else "unknown"


func _type_ids(tower) -> Array:
	var out: Array = []
	for raw in tower.upgrades():
		var upgrade = raw
		out.append(String(upgrade.type_id))
	return out


func _row_summary() -> Array:
	var out: Array = []
	for entry in _rows:
		out.append({
			"index": int(entry["index"]),
			"kind": String(entry["kind"]),
			"id": int(entry["id"]),
			"label": String(entry["label"]),
		})
	return out


func _focused_key() -> String:
	if _focus < 0 or _focus >= _rows.size():
		return ""
	var entry: Dictionary = _rows[_focus]
	return "%s:%d" % [String(entry["kind"]), int(entry["id"])]


func _index_of_key(key: String) -> int:
	if key == "":
		return -1
	for entry in _rows:
		if "%s:%d" % [String((entry as Dictionary)["kind"]), int((entry as Dictionary)["id"])] == key:
			return int((entry as Dictionary)["index"])
	return -1


# --- internals: placement (T-0083) ------------------------------------------

## The placement's grace, tick by tick, then the placement itself. A container's
## measured size is only final once it has been laid out **at the width it will
## keep**, and this panel's labels wrap, so their height depends on that width: with
## no layout at all the height measures as if the text were one word per line. The
## first tick therefore gives the hidden panel its width (nothing is visible yet),
## and the next measures that layout, places it and shows it. The countdown is a
## field rather than an `await` so a window freed mid-open cannot leave a coroutine
## resuming on a dead node.
func _process(_delta: float) -> void:
	if not _open or _place_countdown < 0:
		return
	if _place_countdown > 0:
		_place_countdown -= 1
		return
	_place_panel()
	_place_countdown = -1


## The width the panel keeps: its content's own minimum is the floor, the popover's
## ceiling the cap, and `panel_min_width` the column the design asks for.
func _panel_width(panel: Control) -> float:
	var measured: Vector2 = panel.get_combined_minimum_size()
	return clampf(
		maxf(float(measured.x), float(panel_min_width)),
		float(panel_min_width),
		float(panel_max_width)
	)


## Places the panel beside the anchor: above and to the right of the click, inside
## the viewport with `viewport_margin` to spare, and below it when the clamped
## position would cover the click. The root is a full-rect Control parented to the
## HUD layer, so the panel's local position is its viewport position.
func _place_panel() -> void:
	var node := _node(panel_path)
	if not (node is Control):
		return
	var panel := node as Control
	# Width first: the labels wrap, so their height is only right at the width the
	# panel keeps. The panel has been visible (transparent) since `open_for()`, so
	# this measurement is of a real layout.
	var measured: Vector2 = panel.get_combined_minimum_size()
	var width := _panel_width(panel)
	var size := Vector2(width, maxf(float(measured.y), 1.0))
	var view := get_viewport().get_visible_rect().size
	var gap := float(anchor_gap)
	var below := _anchor + Vector2(gap, gap)
	var position := _clamped(_anchor + Vector2(gap, -size.y - gap), size, view)
	var rect := Rect2(position, size)
	var flipped := false
	if rect.has_point(_anchor):
		# Above the click would cover it: sit under it instead, clamped the same
		# way. A viewport too small for either keeps the below position; covering
		# the click is then the least wrong answer rather than an unplaced panel.
		position = _clamped(below, size, view)
		rect = Rect2(position, size)
		flipped = true
	panel.size = size
	panel.position = position
	# Reveal only now (T-0084): the first frame the player can see is the frame the
	# panel is already at its final rect. Before this it was shown at alpha 0.
	modulate.a = 1.0
	_panel_placed = true
	print("TOWER_WINDOW_PLACED " + JSON.stringify({
		"instance": _open_id,
		"anchor": [_anchor.x, _anchor.y],
		"panel": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"viewport": [view.x, view.y],
		"below": flipped,
		"measured": [measured.x, measured.y],
	}))


## `position` clamped so a `size` rect stays `viewport_margin` inside `view`.
func _clamped(position: Vector2, size: Vector2, view: Vector2) -> Vector2:
	var margin := float(viewport_margin)
	var max_x := maxf(margin, view.x - size.x - margin)
	var max_y := maxf(margin, view.y - size.y - margin)
	return Vector2(clampf(position.x, margin, max_x), clampf(position.y, margin, max_y))


## The viewport point that opened the window. The click this window saw is the
## answer: it is the event the door that opened the window was raised by, whereas
## `Viewport.get_mouse_position()` asks the display server, which answers `(0, 0)`
## in a headless run and nothing useful for a pad open (see the pad caveat above).
func _click_point() -> Vector2:
	if _last_pointer != Vector2.INF:
		return _last_pointer
	return get_viewport().get_mouse_position()


## The pointer position an event carries, or `Vector2.INF` for events that carry
## none. The click that opens a window is a press, so both shapes matter.
func _pointer_of(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	if event is InputEventMouseMotion:
		return (event as InputEventMouseMotion).position
	return Vector2.INF


# --- internals: nodes and session -------------------------------------------

func _node(path: NodePath) -> Node:
	if path.is_empty():
		return null
	return get_node_or_null(path)


func _set_label(path: NodePath, text: String) -> void:
	var node := _node(path)
	if node is Label:
		(node as Label).text = text


func _connect_session() -> void:
	if _flow == null or not is_instance_valid(_flow):
		return
	var inventory = _flow.inventory()
	if inventory != null and inventory.has_signal("contents_changed") \
			and not inventory.is_connected("contents_changed", _on_contents_changed):
		inventory.connect("contents_changed", _on_contents_changed)
	var run = _flow.run_state()
	if run != null and run.has_signal("gold_changed") \
			and not run.is_connected("gold_changed", _on_gold_changed):
		run.connect("gold_changed", _on_gold_changed)


func _disconnect_session() -> void:
	if _flow == null or not is_instance_valid(_flow):
		return
	var inventory = _flow.inventory() if _flow.has_method("inventory") else null
	if inventory != null and inventory.has_signal("contents_changed") \
			and inventory.is_connected("contents_changed", _on_contents_changed):
		inventory.disconnect("contents_changed", _on_contents_changed)
	var run = _flow.run_state() if _flow.has_method("run_state") else null
	if run != null and run.has_signal("gold_changed") \
			and run.is_connected("gold_changed", _on_gold_changed):
		run.disconnect("gold_changed", _on_gold_changed)


func _on_contents_changed() -> void:
	if is_open():
		refresh()


func _on_gold_changed(_current: int = 0, _delta: int = 0) -> void:
	if is_open():
		refresh()
