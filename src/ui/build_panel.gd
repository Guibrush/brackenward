extends Control

## The in-level build panel (T-0057): the thing that makes a level playable.
##
## CONTRACT
## --------
## * It is a panel **over** the level, not a screen of its own. `bind_arena()` is
##   the only way in; the panel reads the arena, the run and the inventory and
##   copies nothing back. Every rule it applies - the build-phase lock, the price
##   of an upgrade, which tile a tower stands on - belongs to the arena, which is
##   also where the refusal sentence is written.
## * **One list, one kind of row.** A row is either an owned tower, or one of the
##   two actions a placed tower offers (`upgrade`, `take_back`). The list is
##   rebuilt from the inventory on every draw, so the placed marker, the tier and
##   the equipped upgrades are never a second copy of the truth.
## * **Arming is selecting an in-hand tower.** Selecting a tower that is already
##   on a tile selects it for the actions instead; there is no second mode.
## * **A refusal shows the arena's own words.** The panel asks the arena, and when
##   the answer is no it displays `arena.last_refusal()` verbatim rather than
##   inventing a second sentence for the same rule. The one exception is a refusal
##   the arena never hears - placing with nothing armed - because that is this
##   panel's own refusal, and it says so.
## * **Always visible:** gold, HQ current/max, and the phase, in one line that is
##   re-read from the run on every signal rather than cached.
## * **The wave readout is the arena's numbers, formatted here** (T-0059): wave of
##   the level's total, the phase, and how many enemies the running wave still
##   owes the lane. `arena.wave_status()` is the one source; the panel adds no
##   count of its own, so "3 enemies left" and the director's own clear condition
##   can never disagree.
## * **Start Wave is a row, not a second mode** (T-0059): it sits first in the
##   list, is taken like every other row, and asks `arena.start_next_wave()`. The
##   arena decides - build phase only, waves left only - and its sentence is what
##   the player reads when the answer is no. The row stays visible and takeable
##   during a wave on purpose: a locked action that cannot be asked why is
##   indistinguishable from a broken one (`map_input.gd` makes the same choice).
## * **Input comes through one door,** `handle_input()`, which asks `MapInput` for
##   the intent. Nothing here reads a key, an action or a button directly, and a
##   left click is a `CONFIRM` carrying its pointer: a point over a row picks the
##   row, a point over the board places or selects. Mouse, keyboard and pad are
##   therefore the same code path with a different device.
##
## BINDING ORDER
## -------------
## A panel instanced into a level scene has its `_ready` run **before** the arena
## it sits under, so the run and the inventory do not exist yet. `bind_arena()`
## therefore records the arena, and the first draw and the signal connections are
## deferred one frame, when the arena has seeded itself.
##
## SIZING (T-0062)
## ---------------
## A Control resolves its anchors against its **parent's** rect. This panel's
## parent is a `CanvasLayer`, so the anchors resolve against the viewport and the
## panel has a real rect in every run, windowed or headless - which is what makes
## the full-rect anchors in `scenes/build_panel.tscn` mean "cover the screen".
## It was a child of the level's `Node2D` arena until T-0062: a `Node2D` offers no
## anchorable rect, the panel came out 0x0, and the `VBoxContainer` taller than
## that box centred its column at a negative y, so only the last child (the hint)
## was on screen. The panel therefore does no viewport arithmetic of its own; if
## the rect is wrong again, the parent is wrong again.
##
## Prints on stdout, one line per event:
##   BUILD_PANEL_SHOWN {json}     once per draw whose rows changed (a re-draw that
##                                changes nothing prints nothing)
##   BUILD_PANEL_PHASE {json}     on every build <-> wave transition
##   BUILD_PANEL_WAVE_STARTED {json} once per wave this panel started, with the
##                                readout before and after
##   BUILD_PANEL_SELECT {json}    once per tower selected or armed
##   BUILD_PANEL_PLACED {json}    once per successful placement, with the gold
##                                before and after (placement is free)
##   BUILD_PANEL_UPGRADED {json}  once per successful upgrade, with the cost
##   BUILD_PANEL_TAKEN_BACK {json} once per tower returned to the inventory
##   BUILD_PANEL_REFUSED {json}   every refusal this panel reports, with the reason
##
## `ARENA_*` lines in the same output are the arena's, not this file's.

const MapInputScript := preload("res://src/ui/map_input.gd")

## A tower in hand was armed for placement (`instance_id`).
signal tower_armed(instance_id: int)
## A tower was placed on a tile. `tile` is the build tile's own node name.
signal tower_placed(instance_id: int, tile: String, tier: int, gold: int)
## A tower was upgraded: the cost was taken from the run's gold.
signal tower_upgraded(instance_id: int, tier: int, cost: int, gold: int)
## A tower was taken back: the tile is free and the instance is in the inventory.
signal tower_taken_back(instance_id: int, tier: int, gold: int)
## The player started the level's next wave (T-0059): `wave` is the one now
## running, `waves` the level's total. Emitted after the arena printed its own
## `WAVE_START`/`ARENA_PHASE`, so a listener cannot report a wave the log has not.
signal wave_started(wave: int, waves: int)
## An action was refused, with the sentence the player is shown.
signal action_refused(action: String, reason: String)

const KIND_START_WAVE := "start_wave"
const KIND_TOWER := "tower"
const KIND_UPGRADE := "upgrade"
const KIND_TAKE_BACK := "take_back"

@export_group("Layout — node paths")
## Exported rather than hardcoded, so the scene can be rearranged without touching
## behaviour.
@export var title_path: NodePath = ^"Margin/Column/Title"
@export var state_path: NodePath = ^"Margin/Column/State"
## The wave readout line (T-0059). Its own label, so the always-visible state
## line keeps its shape and the readout can be moved without touching it.
@export var wave_path: NodePath = ^"Margin/Column/Wave"
@export var tower_list_path: NodePath = ^"Margin/Column/Towers"
@export var reason_path: NodePath = ^"Margin/Column/Reason"
@export var hint_path: NodePath = ^"Margin/Column/Hint"

@export_group("Binding")
## The arena this panel belongs to, resolved once in `_ready`. Empty means the
## panel waits for `bind_arena()`.
@export var arena_path: NodePath = ^""

@export_group("Copy")
@export var title_text: String = "Build"
## The always-visible line's shape: four values - HQ current, HQ max, gold, phase.
@export var state_format: String = "HP %d/%d    Gold %d    %s phase"
## The wave readout's first part: the wave in play (or the one about to start)
## out of the level's total.
@export var wave_progress_format: String = "Wave %d/%d"
## The wave readout's phase part, so the phase reads the same way in both lines.
@export var wave_phase_format: String = "%s phase"
## The readout while nothing has run yet: the wave the player is about to start.
@export var wave_pending_text: String = "wave %d not started"
## The readout after a wave clears: which one did.
@export var wave_cleared_text: String = "wave %d cleared"
## The readout while a wave runs: enemies still queued or still on the lane.
@export var wave_remaining_format: String = "%d enemies left"
## The readout once every wave of the level has cleared.
@export var wave_finished_text: String = "every wave cleared"
## The readout for a level whose plan is empty - a wiring or data fault, shown
## rather than hidden behind "Wave 0/0".
@export var wave_none_text: String = "the level has no waves"
## The Start Wave row, in each of the three states it can be in. The locked and
## exhausted texts are what the player sees *before* they ask, and the arena's
## own sentence is what they see when they do.
@export var start_wave_text: String = "Start Wave"
@export var start_wave_locked_text: String = "Start Wave - locked during a wave"
@export var start_wave_none_text: String = "Start Wave - no waves left"
## How a tower's tier is written next to its type.
@export var tier_format: String = "T%d"
## How the row of a tower on the board is marked.
@export var placed_marker: String = "placed"
## How the row of a tower still in the inventory is marked.
@export var unplaced_marker: String = "in hand"
## How a row that is the selected tower's arming state is marked.
@export var armed_marker: String = "armed"
## The upgrade action row: next tier, and what it costs.
@export var upgrade_format: String = "Upgrade to T%d - %d gold"
## The upgrade row at the last tier, where the arena's price is -1.
@export var max_tier_text: String = "Upgrade - already at the last tier"
@export var take_back_text: String = "Take back to the inventory"
@export var hint_text: String = (
	"Start Wave begins the next wave, then: D-pad or Up/Down picks, A or Enter confirms, "
	+ "click a tower row to arm it, click a tile to place, click a placed tower for its actions"
)
## Shown in the list when the inventory holds nothing.
@export var no_towers_text: String = "you own no towers"
## Shown instead of any number when no arena is bound.
@export var no_arena_text: String = "no level to build in"
## The panel's own refusal, for a placement it never asked the arena about.
@export var nothing_armed_text: String = "nothing is armed: pick a tower in hand first"
## A click on bare ground with nothing armed and no tower under it.
@export var no_tower_there_text: String = "no tower there: pick a tower in hand to arm placement"
## Prepended to the focused row so a keyboard or pad player can see where they are.
@export var focus_marker: String = "> "
## Between fields of a row's text: "Arrow - T2 - placed - TowerSlot".
@export var field_separator: String = " · "

@export_group("Tuning — PLACEHOLDER (T-0057)")
## Height of one list row, in pixels. Range 24-48; shorter than the font clips,
## much taller and the list stops reading as a list.
@export var row_min_height: int = 32

var _arena: Node = null
var _router = MapInputScript.new()

## One entry per drawn row:
##     index, kind, id, type_id, tier, upgrades, placed, armed, selected, tile,
##     cost, label, node (Button)
var _rows: Array = []
var _focus: int = -1

## The inventory instance armed for placement, or -1.
var _armed_id: int = -1
## The inventory instance the action rows belong to, or -1.
var _selected_id: int = -1

var _reason: String = ""
var _last_signature: String = ""
## True while this panel is waiting on an arena call. The inventory emits
## `contents_changed` from inside `place_tower()` / `take_tower_back()` /
## `raise_tower_tier()`, i.e. before the arena has finished the action; drawing then
## would print a row for a tower that is "placed" on no tile yet. One action, one
## draw.
var _acting: bool = false


func _ready() -> void:
	if not arena_path.is_empty():
		var target := get_node_or_null(arena_path)
		if target != null:
			bind_arena(target)
	_apply_copy()
	# The arena is a parent: its `_ready` has not run yet, so there is no run and
	# no inventory to read. Draw after it has seeded itself.
	call_deferred("_deferred_draw")


# --- binding ----------------------------------------------------------------

## Wires the panel to one arena and draws it. Refused (returns false, with a
## printed reason) for a null arena, or for a second arena: one panel shows one
## level, and a panel showing two would be a panel owning state.
func bind_arena(arena: Node) -> bool:
	if arena == null:
		_reject("bind the build panel", "no arena was handed over")
		return false
	if _arena != null and is_instance_valid(_arena) and _arena != arena:
		_reject("bind the build panel", "this panel is already bound to another arena")
		return false

	_arena = arena
	# The arena is usually this panel's parent, and a parent's `_ready` runs
	# **after** its children's: at this moment the arena has not resolved its
	# ledger or its phase yet, so drawing now would show "Gold 0" for one frame.
	# The deferred draw is the first draw; a caller that binds a ready arena gets
	# one immediately.
	if not arena.is_node_ready():
		return true
	_connect_session()
	refresh()
	return true


func arena() -> Node:
	return _arena


# --- drawing ----------------------------------------------------------------

## Rebuilds the rows and the state line from the arena. Prints `BUILD_PANEL_SHOWN`
## only when what is drawn differs from the previous draw - the inventory signal
## fires on every placement, so a draw that printed unconditionally would put two
## identical lines in the log for one action. `force` prints anyway, for the demo.
func refresh(force: bool = false) -> void:
	_rebuild_rows()
	_apply_copy()
	_apply_focus()
	var signature := _signature()
	if force or signature != _last_signature:
		_last_signature = signature
		print("BUILD_PANEL_SHOWN " + JSON.stringify({
			"rows": _printable_rows(),
			"armed": _armed_id,
			"selected": _selected_id,
			"state": state()["label"],
			"wave": wave()["label"],
			"phase": phase_name(),
			"visible": visible,
		}))


func rows() -> Array:
	return _rows.duplicate(true)


func row_count() -> int:
	return _rows.size()


## One row, or an empty dictionary for an index the panel does not have.
func row(index: int) -> Dictionary:
	if index < 0 or index >= _rows.size():
		return {}
	return (_rows[index] as Dictionary).duplicate(true)


func focus_index() -> int:
	return _focus


func armed_instance() -> int:
	return _armed_id


func selected_instance() -> int:
	return _selected_id


## The last sentence the panel showed the player, or "".
func reason() -> String:
	return _reason


## The always-visible numbers, read live from the arena, the run and the phase:
##     {gold, hq, hq_max, phase, label}
## Nothing is cached: a cached copy is a second owner of a number that already has
## one.
func state() -> Dictionary:
	var out := {
		"gold": 0,
		"hq": 0,
		"hq_max": 0,
		"phase": "",
		"label": no_arena_text,
	}
	if not _bound():
		return out
	out["gold"] = _arena.gold()
	out["phase"] = phase_name()
	var run = _arena.run_state() if _arena.has_method("run_state") else null
	if run != null:
		out["hq"] = run.hq_health()
		out["hq_max"] = run.hq_max_health()
	out["label"] = state_format % [int(out["hq"]), int(out["hq_max"]), int(out["gold"]), out["phase"]]
	return out


## The wave readout, read live from `arena.wave_status()`:
##     {waves, wave, cleared, phase, running, remaining, left, label}
## Same rule as `state()`: nothing cached, because a cached wave count is a
## second owner of a number the director already keeps.
func wave() -> Dictionary:
	var out := {
		"waves": 0,
		"wave": 0,
		"cleared": 0,
		"phase": "",
		"running": false,
		"remaining": 0,
		"left": 0,
		"label": no_arena_text,
	}
	if not _bound() or not _arena.has_method("wave_status"):
		return out
	var status: Dictionary = _arena.wave_status()
	for key in ["waves", "wave", "cleared", "phase", "running", "remaining", "left"]:
		if status.has(key):
			out[key] = status[key]

	var parts: Array[String] = []
	if int(out["waves"]) <= 0:
		parts.append(wave_none_text)
	else:
		parts.append(wave_progress_format % [int(out["wave"]), int(out["waves"])])
		parts.append(wave_phase_format % String(out["phase"]))
		if bool(out["running"]):
			parts.append(wave_remaining_format % int(out["remaining"]))
		elif int(out["cleared"]) >= int(out["waves"]):
			parts.append(wave_finished_text)
		elif int(out["cleared"]) <= 0:
			parts.append(wave_pending_text % int(out["wave"]))
		else:
			parts.append(wave_cleared_text % int(out["cleared"]))
	out["label"] = field_separator.join(parts)
	return out


# --- acting -----------------------------------------------------------------

## The single action path: a row is taken. What the rows are is decided in
## `_rebuild_rows`; what taking one means is decided here and nowhere else.
func activate(index: int) -> bool:
	if not _bound():
		_show_reason(no_arena_text)
		return false
	if index < 0 or index >= _rows.size():
		_show_reason("no row %d" % index)
		return false

	var entry: Dictionary = _rows[index]
	_focus = index
	_apply_focus()
	match String(entry["kind"]):
		KIND_START_WAVE:
			return start_wave()
		KIND_TOWER:
			return _select(int(entry["id"]))
		KIND_UPGRADE:
			return upgrade_selected()
		KIND_TAKE_BACK:
			return take_back_selected()
	_show_reason("row %d is not an action" % index)
	return false


## Starts the level's next wave through the arena (T-0059). The panel decides
## nothing here: the build phase, the waves left and the sentence for a refusal
## are all the arena's, and its sentence is shown verbatim - the same rule every
## other action in this panel follows.
func start_wave() -> bool:
	if not _bound():
		_refuse_action("start wave", no_arena_text)
		return false
	if not _arena.has_method("start_next_wave"):
		_refuse_action("start wave", "the level cannot start a wave from the panel")
		return false

	var before: Dictionary = wave()
	_acting = true
	var started: bool = _arena.start_next_wave()
	_acting = false
	if not started:
		_refuse_action("start wave", _arena.last_refusal())
		refresh()
		return false

	_show_reason("")
	var after: Dictionary = wave()
	print("BUILD_PANEL_WAVE_STARTED " + JSON.stringify({
		"wave_before": int(before["wave"]),
		"wave": int(after["wave"]),
		"waves": int(after["waves"]),
		"remaining": int(after["remaining"]),
		"phase": phase_name(),
		"readout": String(after["label"]),
	}))
	refresh()
	wave_started.emit(int(after["wave"]), int(after["waves"]))
	return true


## Arms an in-hand tower, or selects a placed one. Selecting is the same call
## either way, because arming *is* selecting a tower that is not on a tile.
func _select(instance_id: int) -> bool:
	var instance = _instance(instance_id)
	if instance == null:
		_show_reason("no tower %d in the inventory" % instance_id)
		return false
	_selected_id = instance_id
	_armed_id = -1 if bool(instance.placed) else instance_id
	_show_reason("")
	print("BUILD_PANEL_SELECT " + JSON.stringify({
		"instance": instance_id,
		"type_id": String(instance.type_id),
		"tier": int(instance.tier),
		"upgrades": instance.upgrade_type_ids(),
		"placed": bool(instance.placed),
		"armed": _armed_id,
	}))
	refresh()
	if _armed_id != -1:
		tower_armed.emit(_armed_id)
	return true


## Places the armed tower on the build tile nearest `world_position`. Placement is
## free: gold before and after are printed because "free" is a claim, and the demo
## is the thing that checks it.
func place_at(world_position: Vector2) -> bool:
	if not _bound():
		_refuse_action("place", no_arena_text)
		return false
	if _armed_id == -1:
		# The arena never hears this one: with nothing armed there is nothing to
		# place, and asking it would refuse with "the inventory holds no tower to
		# place", which is the wrong sentence for the player's mistake.
		_refuse_action("place", nothing_armed_text)
		return false

	var instance_id := _armed_id
	var gold_before: int = _arena.gold()
	var free_before: int = _arena.free_slot_count()
	_acting = true
	var tower = _arena.place_tower(world_position, instance_id)
	_acting = false
	if tower == null:
		_refuse_action("place", _arena.last_refusal())
		return false

	_armed_id = -1
	_selected_id = instance_id
	_show_reason("")
	var slot := _slot_of(tower)
	print("BUILD_PANEL_PLACED " + JSON.stringify({
		"instance": instance_id,
		"tower": String(tower.name),
		"tile": String(slot.get("name", "<none>")),
		"tier": tower.tier(),
		"cost": 0,
		"gold_before": gold_before,
		"gold": _arena.gold(),
		"free_before": free_before,
		"free": _arena.free_slot_count(),
		"phase": phase_name(),
	}))
	refresh()
	tower_placed.emit(instance_id, String(slot.get("name", "")), tower.tier(), _arena.gold())
	return true


## Buys the next tier for the selected placed tower. The price is the tower's, the
## charge is the arena's, and the refusal is the arena's own sentence.
func upgrade_selected() -> bool:
	if not _bound():
		_refuse_action("upgrade", no_arena_text)
		return false
	var tower = _selected_tower()
	if tower == null:
		_refuse_action("upgrade", "no placed tower is selected")
		return false

	var gold_before: int = _arena.gold()
	var tier_before: int = tower.tier()
	var cost: int = tower.upgrade_cost()
	_acting = true
	var upgraded: bool = _arena.upgrade_tower(tower)
	_acting = false
	if not upgraded:
		_refuse_action("upgrade", _arena.last_refusal())
		return false

	_show_reason("")
	print("BUILD_PANEL_UPGRADED " + JSON.stringify({
		"instance": _selected_id,
		"tower": String(tower.name),
		"tier_before": tier_before,
		"tier": tower.tier(),
		"cost": cost,
		"gold_before": gold_before,
		"gold": _arena.gold(),
		"phase": phase_name(),
	}))
	refresh()
	tower_upgraded.emit(_selected_id, tower.tier(), cost, _arena.gold())
	return true


## Returns the selected placed tower to the inventory: the tile is freed and the
## instance keeps its tier and upgrades, which is the point of taking a tower back
## rather than selling it.
func take_back_selected() -> bool:
	if not _bound():
		_refuse_action("take back", no_arena_text)
		return false
	var tower = _selected_tower()
	if tower == null:
		_refuse_action("take back", "no placed tower is selected")
		return false

	var instance_id := _selected_id
	var tier: int = tower.tier()
	var gold_before: int = _arena.gold()
	var free_before: int = _arena.free_slot_count()
	_acting = true
	var taken_back: bool = _arena.take_tower_back(tower)
	_acting = false
	if not taken_back:
		_refuse_action("take back", _arena.last_refusal())
		return false

	_selected_id = -1
	_armed_id = -1
	_show_reason("")
	print("BUILD_PANEL_TAKEN_BACK " + JSON.stringify({
		"instance": instance_id,
		"tier": tier,
		"gold_before": gold_before,
		"gold": _arena.gold(),
		"free_before": free_before,
		"free": _arena.free_slot_count(),
		"phase": phase_name(),
	}))
	refresh()
	tower_taken_back.emit(instance_id, tier, _arena.gold())
	return true


## Selects the tower standing nearest `world_position`, for a click on the board
## with nothing armed. Returns false with a reason when there is no tower there.
func select_at(world_position: Vector2) -> bool:
	if not _bound():
		_refuse_action("select", no_arena_text)
		return false
	var slot := _nearest_slot(world_position, false)
	if slot.is_empty():
		_refuse_action("select", no_tower_there_text)
		return false
	return _select(int(slot["instance_id"]))


# --- input ------------------------------------------------------------------

## One door for input. The event is translated by `MapInput`; this method moves
## focus, takes a row, or resolves a pointer to a board action, and returns what it
## did so a caller (or a demo) can assert on the translation as well as the effect.
func handle_input(event: InputEvent) -> Dictionary:
	var result: Dictionary = _router.intent_for(event)
	var out := result.duplicate()
	out["applied"] = false
	if not visible:
		out["ignored"] = "the panel is not showing"
		return out

	match int(result["intent"]):
		MapInputScript.Intent.FOCUS_NEXT:
			out["applied"] = _move_focus(1)
		MapInputScript.Intent.FOCUS_PREV:
			out["applied"] = _move_focus(-1)
		MapInputScript.Intent.CONFIRM:
			if result.has("pointer"):
				out["applied"] = _confirm_pointer(result["pointer"], out)
			else:
				out["index"] = _focus
				out["target"] = "row"
				out["applied"] = activate(_focus)
		MapInputScript.Intent.DISMISS:
			# Dismiss cancels an armed tower and nothing else: it is the way out of
			# a placement a player started and does not want.
			_armed_id = -1
			_show_reason("")
			refresh()
		_:
			pass
	return out


func _unhandled_input(event: InputEvent) -> void:
	# The board is drawn by the arena, not by a Control that could take the click,
	# so a click that no row consumed arrives here.
	handle_input(event)


## A pointer confirm: a point over a row takes that row, a point over the board
## places the armed tower, or selects the tower standing there.
func _confirm_pointer(point: Vector2, out: Dictionary) -> bool:
	var index := _index_at(point)
	if index != -1:
		out["index"] = index
		out["target"] = "row"
		return activate(index)
	var world := _pointer_world(point)
	out["world"] = [world.x, world.y]
	out["target"] = "tile"
	if _armed_id != -1:
		return place_at(world)
	return select_at(world)


# --- internals: rows --------------------------------------------------------

func _rebuild_rows() -> void:
	var previous_key := _focused_key()
	_clear_list()
	_rows.clear()

	if not _bound():
		_focus = -1
		_apply_copy()
		return

	var list := _node(tower_list_path)
	var slots := _slot_index()
	var inventory = _arena.inventory()
	var towers: Array = inventory.towers() if inventory != null else []

	# Start Wave first: it is the one action a level always offers, and the row a
	# player reaching for the phase's next step should not have to scroll to.
	_add_entry(list, {
		"kind": KIND_START_WAVE,
		"id": 0,
		"type_id": "",
		"tier": 0,
		"upgrades": [],
		"placed": false,
		"armed": false,
		"selected": false,
		"tile": "",
		"cost": 0,
		"label": _start_wave_label(),
	})

	for instance in towers:
		var entry := _tower_entry(instance, slots)
		_add_entry(list, entry)

	# The actions a placed tower offers, appended after the list so the tower rows
	# never move when a selection changes the length of the list.
	var tower = _selected_tower()
	if tower != null:
		var cost: int = tower.upgrade_cost()
		var upgrade: Dictionary = {
			"kind": KIND_UPGRADE,
			"id": _selected_id,
			"tier": tower.tier(),
			"cost": cost,
			"placed": true,
			"armed": false,
			"selected": true,
			"tile": String(_slot_of(tower).get("name", "")),
			"type_id": String(tower.instance.type_id) if tower.instance != null else "",
			"upgrades": tower.instance.upgrade_type_ids() if tower.instance != null else [],
			"label": max_tier_text if cost < 0 else upgrade_format % [tower.tier() + 1, cost],
		}
		_add_entry(list, upgrade)
		var take_back: Dictionary = {
			"kind": KIND_TAKE_BACK,
			"id": _selected_id,
			"tier": tower.tier(),
			"cost": 0,
			"placed": true,
			"armed": false,
			"selected": true,
			"tile": String(_slot_of(tower).get("name", "")),
			"type_id": String(tower.instance.type_id) if tower.instance != null else "",
			"upgrades": tower.instance.upgrade_type_ids() if tower.instance != null else [],
			"label": take_back_text,
		}
		_add_entry(list, take_back)

	if _rows.is_empty():
		_focus = -1
	else:
		_focus = _index_of_key(previous_key)
		if _focus < 0:
			_focus = 0


func _tower_entry(instance: RefCounted, slots: Dictionary) -> Dictionary:
	var instance_id := int(instance.id)
	var placed := bool(instance.placed)
	var tile := ""
	if placed and slots.has(instance_id):
		tile = String(slots[instance_id]["name"])
	var entry := {
		"kind": KIND_TOWER,
		"id": instance_id,
		"type_id": String(instance.type_id),
		"tier": int(instance.tier),
		"upgrades": instance.upgrade_type_ids(),
		"placed": placed,
		"armed": instance_id == _armed_id,
		"selected": instance_id == _selected_id,
		"tile": tile,
		"cost": 0,
	}
	entry["label"] = _tower_text(entry)
	return entry


## "Pike · T2 · placed · TowerSlot · piercer, keen": type, tier, where it is, and
## every upgrade it carries. The upgrades are the inventory's own type ids, so a
## tower with an equipped item reads differently from one without.
func _tower_text(entry: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append(String(entry["type_id"]))
	parts.append(tier_format % int(entry["tier"]))
	if bool(entry["placed"]):
		parts.append(placed_marker)
		if String(entry["tile"]) != "":
			parts.append(String(entry["tile"]))
	else:
		parts.append(unplaced_marker)
	var upgrades: Array = entry["upgrades"]
	if not upgrades.is_empty():
		var names: Array[String] = []
		for id in upgrades:
			names.append(String(id))
		parts.append(", ".join(names))
	if bool(entry["armed"]):
		parts.append(armed_marker)
	return field_separator.join(parts)


## The Start Wave row's text, by the state of the level: ready, locked by a
## running wave, or exhausted. The row is drawn in all three states on purpose -
## the two locked ones are the ones a player asks why about, and the answer is the
## arena's refusal sentence.
func _start_wave_label() -> String:
	var status: Dictionary = wave()
	if int(status["waves"]) <= 0:
		return start_wave_none_text
	if bool(status["running"]):
		return start_wave_locked_text
	if int(status["cleared"]) >= int(status["waves"]):
		return start_wave_none_text
	return start_wave_text


## Appends one row: the entry the panel keeps, and the Button the player sees. The
## Button carries no focus of its own - the panel draws `focus_marker` - so a pad,
## a keyboard and a mouse all resolve to `activate()`.
func _add_entry(list: Node, entry: Dictionary) -> void:
	entry["index"] = _rows.size()
	if list != null:
		var button := Button.new()
		button.name = "Row%d" % int(entry["index"])
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, row_min_height)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.text = String(entry["label"])
		button.pressed.connect(_on_row_pressed.bind(int(entry["index"])))
		list.add_child(button)
		entry["node"] = button
	_rows.append(entry)


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
	# A click that landed on a row is the same call as a confirm.
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


## The row whose rect contains `point`, or -1. Deliberately exact: the panel sits
## over the board, so a click that misses every row is a click on the board and
## must reach `place_at()` / `select_at()`. Snapping to the nearest row (which is
## right for a full-screen list) would make the board unclickable.
func _index_at(point: Vector2) -> int:
	for entry in _rows:
		if not entry.has("node"):
			continue
		var rect: Rect2 = (entry["node"] as Control).get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		if rect.has_point(point):
			return int(entry["index"])
	return -1


func _clear_list() -> void:
	var list := _node(tower_list_path)
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _focused_key() -> String:
	if _focus < 0 or _focus >= _rows.size():
		return ""
	var entry: Dictionary = _rows[_focus]
	return "%s:%d" % [String(entry["kind"]), int(entry["id"])]


func _index_of_key(key: String) -> int:
	if key == "":
		return -1
	for entry in _rows:
		if "%s:%d" % [String(entry["kind"]), int(entry["id"])] == key:
			return int(entry["index"])
	return -1


## The rows with every node reference dropped: a Button is not JSON, and printing
## one would either fail or leak a handle into the evidence line.
func _printable_rows() -> Array:
	var out: Array = []
	for entry in _rows:
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		copy.erase("node")
		out.append(copy)
	return out


func _signature() -> String:
	return JSON.stringify({
		"rows": _printable_rows(),
		"armed": _armed_id,
		"selected": _selected_id,
		"bound": _bound(),
	})


# --- internals: the dungeon -------------------------------------------------

func _bound() -> bool:
	return _arena != null and is_instance_valid(_arena) and _arena.has_method("place_tower")


func phase_name() -> String:
	if not _bound() or not _arena.has_method("phase_name"):
		return ""
	return String(_arena.phase_name())


func _instance(instance_id: int) -> RefCounted:
	if not _bound():
		return null
	var inventory = _arena.inventory()
	if inventory == null:
		return null
	return inventory.find_tower(instance_id)


## The tower node the action rows belong to, or null when nothing placed is
## selected. One lookup, so "selected" means one thing.
func _selected_tower():
	if not _bound() or _selected_id == -1:
		return null
	return _arena.tower_for_instance(_selected_id)


func _slot_of(tower) -> Dictionary:
	if not _bound() or tower == null:
		return {}
	for slot in _arena.build_slots():
		if slot.get("tower", null) == tower:
			return slot
	return {}


## Inventory instance id -> its tile, for the rows of placed towers. Built from the
## arena's own tile list, so the panel cannot claim a tower stands somewhere the
## arena does not put it.
func _slot_index() -> Dictionary:
	var out: Dictionary = {}
	if not _bound():
		return out
	for slot in _arena.build_slots():
		var id := int(slot.get("instance_id", 0))
		if id != 0:
			out[id] = slot
	return out


## The nearest build tile whose occupancy matches `want_free`, within that tile's
## own `snap_radius_px`, or an empty dictionary. The radius is the tile's, not a
## constant here: how close a click has to be is level-design tuning, and it
## already has an owner.
func _nearest_slot(world_position: Vector2, want_free: bool) -> Dictionary:
	if not _bound():
		return {}
	var best: Dictionary = {}
	var best_distance := INF
	for slot in _arena.build_slots():
		if bool(slot["free"]) != want_free:
			continue
		var distance: float = (slot["position"] as Vector2).distance_to(world_position)
		if distance > float(slot["snap_radius_px"]) or distance >= best_distance:
			continue
		best = slot
		best_distance = distance
	return best


## A pointer in viewport coordinates in the arena's world coordinates. Read from
## the arena's own transform rather than assumed: a level that is drawn through a
## camera or an offset canvas must still place the tower where the player clicked.
func _pointer_world(point: Vector2) -> Vector2:
	if _bound() and _arena is CanvasItem:
		return (_arena as CanvasItem).get_global_transform_with_canvas().affine_inverse() * point
	return point


# --- internals: presentation ------------------------------------------------

func _apply_copy() -> void:
	var title := _node(title_path)
	if title != null:
		(title as Label).text = title_text
	_sync_state()
	_sync_wave()
	var hint := _node(hint_path)
	if hint != null:
		(hint as Label).text = hint_text
	var reason_label := _node(reason_path)
	if reason_label != null:
		(reason_label as Label).text = _reason
	_sync_empty_label()


## The state line only. Called on every signal that moves a number, because gold
## and the phase change far more often than the row list does.
func _sync_state() -> void:
	var label := _node(state_path)
	if label != null:
		(label as Label).text = String(state()["label"])


## The wave readout only. Separated from `_sync_state` because the two lines move
## on different signals: gold and HQ on the run's, the wave count on the phase and
## on every kill or leak (which the run reports as gold or damage).
func _sync_wave() -> void:
	var label := _node(wave_path)
	if label != null:
		(label as Label).text = String(wave()["label"])


func _sync_empty_label() -> void:
	var list := _node(tower_list_path)
	if list == null:
		return
	var existing := list.get_node_or_null("Empty")
	if _rows.is_empty():
		if existing == null:
			var empty := Label.new()
			empty.name = "Empty"
			empty.text = no_towers_text if _bound() else no_arena_text
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


func _refuse_action(action: String, why: String) -> void:
	_show_reason(why)
	print("BUILD_PANEL_REFUSED " + JSON.stringify({
		"action": action,
		"reason": why,
		"phase": phase_name(),
		"gold": _arena.gold() if _bound() else 0,
		"armed": _armed_id,
		"selected": _selected_id,
		"arena_refusals": _arena.refused_count() if _bound() else 0,
	}))
	action_refused.emit(action, why)


func _reject(action: String, why: String) -> void:
	_show_reason("%s: %s" % [action, why])
	print("BUILD_PANEL_REJECTED " + JSON.stringify({"action": action, "reason": why}))


func _node(path: NodePath) -> Node:
	if path.is_empty():
		return null
	return get_node_or_null(path)


# --- internals: signals -----------------------------------------------------

func _deferred_draw() -> void:
	_connect_session()
	refresh()


## Connects whatever the arena had seeded by now. Guarded on both sides: a panel
## with no run still draws, and an arena without a phase signal still works.
func _connect_session() -> void:
	if not _bound():
		return
	if _arena.has_signal("phase_changed") and not _arena.is_connected("phase_changed", _on_phase_changed):
		_arena.connect("phase_changed", _on_phase_changed)
	var run = _arena.run_state() if _arena.has_method("run_state") else null
	if run != null:
		if run.has_signal("gold_changed") and not run.is_connected("gold_changed", _on_run_numbers):
			run.connect("gold_changed", _on_run_numbers)
		if run.has_signal("hq_changed") and not run.is_connected("hq_changed", _on_run_numbers):
			run.connect("hq_changed", _on_run_numbers)
	var inventory = _arena.inventory() if _arena.has_method("inventory") else null
	if inventory != null:
		if inventory.has_signal("contents_changed") and not inventory.is_connected("contents_changed", _on_inventory_changed):
			inventory.connect("contents_changed", _on_inventory_changed)


func _on_run_numbers(_a: int = 0, _b: int = 0) -> void:
	_sync_state()
	# A kill pays gold and a leak damages the HQ, so both arrive here - which is
	# what keeps "enemies left" moving while a wave runs, without the panel
	# polling anything.
	_sync_wave()


func _on_inventory_changed() -> void:
	if _acting:
		return
	refresh()


func _on_phase_changed(name: String) -> void:
	_sync_state()
	_sync_wave()
	print("BUILD_PANEL_PHASE " + JSON.stringify({
		"phase": name,
		"gold": _arena.gold() if _bound() else 0,
		"state": state()["label"],
		"wave": wave()["label"],
		"armed": _armed_id,
	}))
	# The Start Wave row's text is a function of the phase, so the list is rebuilt
	# as well as the two lines: a row that still says "locked" after the build
	# phase is back is worse than no row.
	refresh()
