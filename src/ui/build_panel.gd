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
## * **This panel does not list the inventory (T-0068).** The bar owns the
##   inventory view; here a row is Start Wave or one of the two actions a placed
##   tower offers (`upgrade`, `take_back`), and nothing else. A second list of one
##   inventory is a second place to go stale - the rule this file applies to every
##   number it draws. The rows are rebuilt from the arena on every draw, so a tier
##   and an equipped upgrade are never a copy of the truth.
## * **Arming is selecting an in-hand tower.** Selecting a tower that is already
##   on a tile selects it for the actions instead; there is no second mode.
## * **One selection, two views.** A pick in the bar arrives here through
##   `select_instance()` - the same call a row makes, without the re-broadcast - and
##   a selection made here is raised as `tower_selected`, which the bar applies
##   through `mark_selected()`. Neither path raises the other's signal, so the two
##   views cannot echo each other into a loop.
## * **A refusal shows the arena's own words.** The panel asks the arena, and when
##   the answer is no it displays `arena.last_refusal()` verbatim rather than
##   inventing a second sentence for the same rule. The one exception is a refusal
##   the arena never hears - placing with nothing armed - because that is this
##   panel's own refusal, and it says so.
## * **Always visible:** HQ current/max and the phase, in one line that is re-read
##   from the run on every signal rather than cached. Gold left this line in
##   T-0068 with the inventory: it is the bar's number now.
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
## THE ARMED AND SELECTED STATE IS VISIBLE (T-0064)
## ------------------------------------------------
## T-0063 proved with pushed events that a click on a row arms it; the human still
## said "clicking did nothing", because the only feedback was a text suffix. A
## state the player cannot see is indistinguishable from a state that never
## changed, so the panel draws three signals at once:
##   * the row's **band** - a filled `StyleBoxFlat` with a border, which no other
##     row has;
##   * the row's **text colour** - warm for armed, cool for selected;
##   * a **leading marker** on the row, and a **status line** (`status_path`) that
##     says what happens next: "arrow armed - click a build tile to place it".
## The colour alone would fail a colourblind eye and a greyscale screenshot, which
## is why the marker and the status line are not optional extras.
## A row is dressed because `armed` or `selected` is true on the entry, so the cue
## is a function of the same truth the actions use - never a second copy of it.
##
## INPUT OWNERSHIP (T-0063)
## ------------------------
## * **This panel is the level's only input reader.** `_input()` is the single
##   entry point, it translates through `MapInput`, and a translated event is
##   marked handled so no other node in the level acts on it as well. The arena
##   reads no input at all - `arena.gd` has no `_input`, `_unhandled_input`,
##   `set_input_as_handled` or `MapInput` reference - so "the arena swallowed the
##   click" cannot be the reason a click went nowhere.
## * **The rows are drawn, not clickable.** A row is a `Label` with
##   `MOUSE_FILTER_IGNORE`, so the GUI hit-tester cannot consume a click over it:
##   the panel resolves the pointer itself (`_index_at`) and takes the row. Before
##   T-0063 a row was a `Button` with `MOUSE_FILTER_STOP`, so a click on a row was
##   handled by the Button's own `pressed` signal (fired on **release**) while a
##   click on the board was handled by `handle_input()` (on **press**): one event,
##   two owners, and which one acted depended on what the GUI hit-tester did. A
##   Button that is destroyed by a re-draw between press and release loses the
##   click silently - no refusal, no log line - which is the shape of "clicking
##   does nothing".
## * **`_unhandled_input` is deliberately not used.** "Unhandled" means "whatever
##   the GUI declined", so any Control that accepts a click hides the board from
##   this panel without a word. The panel reads at `_input` instead: it sees every
##   event first and decides, which is what one owner means in practice.
##
## THE BAR OWNS ITS OWN POINTS (T-0068)
## ------------------------------------
## The inventory bar is drawn over the lower part of the level, so a click there
## must not also be a board click. The bar marks its own clicks handled, and today
## the engine reaches it first (it is the later sibling in `scenes/boot.tscn`), but
## "which `_input` runs first" is a property of the scene tree, not of this
## contract. So the panel carries its own answer: `add_pointer_guard()` takes a
## predicate the bar supplies (`claim_point()`), and a pointer a guard owns is not
## answered and not marked handled - the overlay that owns it still receives it.
## The guard is consulted twice on purpose: in `_input()` before the event is
## claimed, and again in `_confirm_pointer()` at the action door, so a caller that
## drives `handle_input()` directly (a demo, or a future screen) cannot reach the
## board through a bar-owned point either.
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
## The panel's selection changed (T-0068): a tower was selected or armed here, or
## the selection was cleared (`-1`). The bar applies it through `mark_selected()`,
## so one selection is shown in two places. A selection that arrived *from* the bar
## does not raise this, which is what keeps the two views from echoing.
signal tower_selected(instance_id: int)
## The player started the level's next wave (T-0059): `wave` is the one now
## running, `waves` the level's total. Emitted after the arena printed its own
## `WAVE_START`/`ARENA_PHASE`, so a listener cannot report a wave the log has not.
signal wave_started(wave: int, waves: int)
## An action was refused, with the sentence the player is shown.
signal action_refused(action: String, reason: String)

const KIND_START_WAVE := "start_wave"
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
## The one-line prompt that answers "did my click register?" (T-0064): what is
## armed or selected, and what to do next.
@export var status_path: NodePath = ^"Margin/Column/Status"
## The list the action rows are built into (Start Wave, and a placed tower's own
## actions). It no longer holds towers (T-0068); the bar does.
@export var action_list_path: NodePath = ^"Margin/Column/Actions"
@export var reason_path: NodePath = ^"Margin/Column/Reason"
@export var hint_path: NodePath = ^"Margin/Column/Hint"

@export_group("Binding")
## The arena this panel belongs to, resolved once in `_ready`. Empty means the
## panel waits for `bind_arena()`.
@export var arena_path: NodePath = ^""

@export_group("Layout — clearing the inventory bar")
## The container whose bottom margin keeps this panel's last line clear of the
## inventory bar drawn over the level (T-0068). Exported for the same reason every
## other path here is: the scene can be rearranged without touching behaviour.
@export var margin_path: NodePath = ^"Margin"
## Space kept free at the bottom of the panel's column, in pixels. The bar's own
## height owns this number, so the boot measures the bar and calls
## `reserve_bottom()`; the value here is the fallback for a panel shown without a
## bar (the `main` scene on its own). Suggested range: the bar's height plus 4-24.
@export var content_bottom_reserve: int = 148
## The gap between the panel's last line and the reserved strip, in pixels. Range
## 4-24: closer and the lines read as one block, further and the panel looks broken.
@export var bar_gap: int = 12

@export_group("Copy")
@export var title_text: String = "Build"
## The always-visible line's shape: HQ current, HQ max, phase. Gold is not here
## (T-0068): the bar shows it, and one number with two owners is what this file
## exists to avoid.
@export var state_format: String = "HP %d/%d    %s phase"
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
## Prepended to an armed row's text (T-0064). A marker that is not colour, so the
## state survives a colourblind eye and a greyscale screenshot.
@export var armed_prefix: String = "\u25B6 "
## Prepended to a selected tower's action rows.
@export var selected_prefix: String = "\u25C6 "
## The status line while a tower is armed for placement: the tower, then the one
## action the player has left to take.
@export var status_armed_format: String = "%s armed \u2014 click a build tile to place it"
## The status line while a placed tower is selected: whose actions are on screen.
@export var status_selected_format: String = "%s T%d selected \u2014 its actions are listed below"
## The status line when nothing is armed and nothing is selected. Empty on
## purpose: a prompt that is always there stops being a signal.
@export var status_idle_text: String = ""
## The upgrade action row: next tier, and what it costs.
@export var upgrade_format: String = "Upgrade to T%d - %d gold"
## The upgrade row at the last tier, where the arena's price is -1.
@export var max_tier_text: String = "Upgrade - already at the last tier"
@export var take_back_text: String = "Take back to the inventory"
@export var hint_text: String = (
	"Start Wave begins the next wave, then: D-pad or Up/Down picks, A or Enter confirms, "
	+ "click a tower in the bar to arm it, click a tile to place, click a placed tower for its actions"
)
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

@export_group("Tuning — the armed and selected cue (T-0064)")
## Text colour of an armed row and the border of its band. Warm, because it is the
## row the player is about to act on. Suggested range: amber to orange, luminance
## above 0.7 so it reads against the dark sidebar.
@export var armed_colour: Color = Color(1.0, 0.8, 0.3, 1.0)
## Fill behind an armed row. Suggested range: the same hue as `armed_colour`,
## value 0.25-0.45. Darker than the text, or the text stops reading.
@export var armed_fill: Color = Color(0.42, 0.3, 0.06, 0.92)
## Text colour of the selected tower's row and of its action rows, and the border
## of their bands. Cool, so selection never reads as "armed" at a glance.
@export var selected_colour: Color = Color(0.55, 0.86, 1.0, 1.0)
## Fill behind the selected tower's rows. Same rule as `armed_fill`.
@export var selected_fill: Color = Color(0.05, 0.2, 0.3, 0.92)
## Text colour of a row in neither state.
@export var idle_row_colour: Color = Color(0.86, 0.88, 0.84, 1.0)
## Border thickness of a dressed row's band, in pixels. Range 1-4; 0 removes the
## border, leaving only the fill, the colour and the marker.
@export var cue_border_width: int = 2
## Corner radius of a dressed row's band, in pixels. Range 0-6.
@export var cue_corner_radius: int = 3
## Horizontal padding inside a dressed row's band, in pixels. Range 0-12.
@export var cue_padding: int = 6

var _arena: Node = null
var _router = MapInputScript.new()

## Predicates that say "this viewport point is mine, not the board's" (T-0068). The
## inventory bar registers one, so a click on the bar is not answered here as well.
var _pointer_guards: Array[Callable] = []

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
	_apply_metrics()
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


# --- pointer ownership ------------------------------------------------------

## Registers a predicate that claims viewport points this panel must not answer.
## The inventory bar hands over `claim_point` (T-0068), so a click on the bar is the
## bar's and never the board's, whichever of the two the engine reaches first. More
## than one guard is allowed; the first to claim a point wins. An invalid callable
## (a view that is being freed) is refused rather than stored.
func add_pointer_guard(guard: Callable) -> bool:
	if not guard.is_valid() or _pointer_guards.has(guard):
		return false
	_pointer_guards.append(guard)
	return true


## Removes a guard, so a view that is going away stops being asked.
func remove_pointer_guard(guard: Callable) -> void:
	_pointer_guards.erase(guard)


## Whether an overlay owns `point`. A guard whose object has been freed is skipped
## rather than called: a panel must not throw because the bar it was wired to is
## gone.
func is_point_claimed(point: Vector2) -> bool:
	for guard in _pointer_guards:
		if not guard.is_valid():
			continue
		if bool(guard.call(point)):
			return true
	return false


# --- clearing the bar -------------------------------------------------------

## Keeps the panel's column clear of an overlay `height_px` tall: the bottom margin
## becomes that height plus `bar_gap` (T-0068). The boot calls this with the bar's
## own rect, so the bar's height has one owner and no constant here goes stale when
## the bar grows a row.
func reserve_bottom(height_px: int) -> void:
	content_bottom_reserve = maxi(height_px, 0) + maxi(bar_gap, 0)
	_apply_metrics()


## The strip kept free at the bottom, in pixels - what a frame or a demo reads back.
func content_reserve() -> int:
	return content_bottom_reserve


# --- drawing ----------------------------------------------------------------

## Rebuilds the rows and the state line from the arena. Prints `BUILD_PANEL_SHOWN`
## only when what is drawn differs from the previous draw - the inventory signal
## fires on every placement, so a draw that printed unconditionally would put two
## identical lines in the log for one action. `force` prints anyway, for the demo.
func refresh(force: bool = false) -> void:
	_rebuild_rows()
	_apply_copy()
	_apply_visuals()
	var signature := _signature()
	if force or signature != _last_signature:
		_last_signature = signature
		print("BUILD_PANEL_SHOWN " + JSON.stringify({
			"rows": _printable_rows(),
			"armed": _armed_id,
			"selected": _selected_id,
			"state": state()["label"],
			"wave": wave()["label"],
			"status": status()["label"],
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
##     {hq, hq_max, phase, label}
## Nothing is cached: a cached copy is a second owner of a number that already has
## one. Gold used to be here and left with the inventory list (T-0068) - the bar
## owns it now, and a number this panel does not draw is not a number it reports.
func state() -> Dictionary:
	var out := {
		"hq": 0,
		"hq_max": 0,
		"phase": "",
		"label": no_arena_text,
	}
	if not _bound():
		return out
	out["phase"] = phase_name()
	var run = _arena.run_state() if _arena.has_method("run_state") else null
	if run != null:
		out["hq"] = run.hq_health()
		out["hq_max"] = run.hq_max_health()
	out["label"] = state_format % [int(out["hq"]), int(out["hq_max"]), out["phase"]]
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


## The prompt that answers "did my click register?", read live from what is armed
## and selected:
##     {armed, selected, tower, label}
## Idle is an empty label on purpose: a line that always says something is not a
## signal. The tower is the inventory's own type id, so this line cannot name a
## tower the rows do not.
func status() -> Dictionary:
	var out := {
		"armed": _armed_id,
		"selected": _selected_id,
		"tower": "",
		"label": status_idle_text,
	}
	if not _bound():
		return out
	if _armed_id != -1:
		var instance = _instance(_armed_id)
		if instance != null:
			out["tower"] = String(instance.type_id)
			out["label"] = status_armed_format % [String(instance.type_id)]
		return out
	var tower = _selected_tower()
	if tower != null:
		var type_id := "tower"
		if tower.instance != null:
			type_id = String(tower.instance.type_id)
		out["tower"] = type_id
		out["label"] = status_selected_format % [type_id, tower.tier()]
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
	_apply_visuals()
	match String(entry["kind"]):
		KIND_START_WAVE:
			return start_wave()
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
##
## `announce` is false for a selection another view already knows about
## (T-0068): the bar raises `tower_selected` and this call applies it, so
## re-raising it here would send the bar its own pick back.
func _select(instance_id: int, announce: bool = true) -> bool:
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
		"from_bar": not announce,
	}))
	refresh()
	if _armed_id != -1:
		tower_armed.emit(_armed_id)
	if announce:
		tower_selected.emit(_selected_id)
	return true


## Selects or arms a tower on behalf of another view - the inventory bar (T-0068).
## The same call a click makes, minus the re-broadcast: the bar already knows, and
## echoing `tower_selected` back at it is how two views would loop. A negative id
## clears the selection, which is what the bar sends when its own is dropped.
func select_instance(instance_id: int) -> bool:
	if instance_id < 0:
		var had_selection := _armed_id != -1 or _selected_id != -1
		_armed_id = -1
		_selected_id = -1
		refresh()
		return had_selection
	return _select(instance_id, false)


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
	# The new tower is the selection now, and the bar draws one selection (T-0068).
	tower_selected.emit(_selected_id)
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
			out["applied"] = _dismiss()
		_:
			pass
	return out


## The level's single input entry point (T-0063). The engine calls this before the
## GUI hit-tester, so nothing in the level can take an event from this panel, and an
## event this panel acts on is marked handled so nothing acts on it twice.
##
## The one exception is a point an overlay owns (T-0068): the inventory bar claims
## its own, and this panel then answers nothing **and marks nothing handled**, so
## the bar still receives the click. Order between the two `_input` calls is a
## property of the scene tree; this branch is what makes one click one owner
## whatever that order is.
##
## A demo must not call this, `handle_input()` or `activate()`: the whole point of
## the evidence rule is that a click delivered by `get_viewport().push_input()`
## reaches the player-visible action. See `tests/input_route_demo.gd`.
func _input(event: InputEvent) -> void:
	var result: Dictionary = _router.intent_for(event)
	if int(result["intent"]) == MapInputScript.Intent.NONE:
		return
	if not visible:
		return
	if result.has("pointer") and is_point_claimed(result["pointer"]):
		return
	get_viewport().set_input_as_handled()
	handle_input(event)


## Backs out one step, the way a pad player expects B/Escape to: an armed tower is
## disarmed first - that is the placement a player started and does not want - and
## with nothing armed the selected tower's action rows close.
func _dismiss() -> bool:
	var had_selection := _armed_id != -1 or _selected_id != -1
	_armed_id = -1
	_selected_id = -1
	_show_reason("")
	refresh()
	if had_selection:
		# One selection, two views: the bar drops its marker with this panel's
		# (T-0068). -1 is "nothing is selected".
		tower_selected.emit(-1)
	return had_selection


## A pointer confirm: a point an overlay owns is not answered, a point over a row
## takes that row, a point over the board places the armed tower, or selects the
## tower standing there.
func _confirm_pointer(point: Vector2, out: Dictionary) -> bool:
	# Before the row lookup on purpose: the bar is drawn *over* the panel, so a
	# point it claims belongs to it even when a row happens to be underneath. And
	# this is the action door, so a caller that drives `handle_input()` directly
	# cannot reach the board through a bar-owned point either (T-0068).
	if is_point_claimed(point):
		out["target"] = "guard"
		out["claimed"] = true
		return false
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

	var list := _node(action_list_path)

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

	# The actions a placed tower offers, appended after the list so the Start Wave
	# row never moves when a selection changes the length of the list.
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


## Appends one row: the entry the panel keeps, and the Control the player sees.
## Since T-0064 a row is a `PanelContainer` wrapping one `Label`, so the row can
## carry a filled band and a border; a bare `Label` has no stylebox to draw one
## with. The row and its label both take no input (`MOUSE_FILTER_IGNORE`), so a
## click over either is resolved by this panel's own hit-test (`_index_at`) rather
## than by the GUI - one reader, press and release in one place.
func _add_entry(list: Node, entry: Dictionary) -> void:
	entry["index"] = _rows.size()
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


## The text node inside a row, or null for a row that has not been drawn. One
## lookup, so "the row's text" means one thing on every path that touches it.
func _row_label(row: Control) -> Label:
	if row == null:
		return null
	return row.get_node_or_null("Text") as Label


## Draws every row from its entry: the focus marker, the armed or selected marker,
## and the colour and band that make the state impossible to miss (T-0064). The
## row's text is rebuilt from `label` on every call, so a marker can never be left
## behind on a row that is no longer armed.
func _apply_visuals() -> void:
	for entry in _rows:
		if not entry.has("node"):
			continue
		var row: Control = entry["node"]
		var label := _row_label(row)
		if label == null:
			continue
		var text := String(entry["label"])
		if bool(entry["armed"]):
			text = armed_prefix + text
		elif bool(entry["selected"]):
			text = selected_prefix + text
		# The focus marker is outermost, so "where my cursor is" and "what this row
		# is" are two glyphs in a fixed order at the start of the line.
		if int(entry["index"]) == _focus:
			text = focus_marker + text
		label.text = text
		_dress(row, label, entry)


## The cue itself: a filled band with a border, and a text colour, on every row
## that is armed or belongs to the selected tower. A row in neither state is drawn
## plain, so "dressed" is a value a demo can read and a player can see.
func _dress(row: Control, label: Label, entry: Dictionary) -> void:
	var armed := bool(entry["armed"])
	var chosen := armed or bool(entry["selected"])
	if not chosen:
		label.add_theme_color_override("font_color", idle_row_colour)
		row.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		return
	var tint := armed_colour if armed else selected_colour
	var fill := armed_fill if armed else selected_fill
	label.add_theme_color_override("font_color", tint)
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = tint
	box.set_border_width_all(cue_border_width)
	box.set_corner_radius_all(cue_corner_radius)
	box.content_margin_left = cue_padding
	box.content_margin_right = cue_padding
	row.add_theme_stylebox_override("panel", box)


func _move_focus(delta: int) -> bool:
	if _rows.is_empty():
		return false
	if _focus < 0:
		_focus = 0
	else:
		_focus = int(posmod(_focus + delta, _rows.size()))
	_apply_visuals()
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
	var list := _node(action_list_path)
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
	_sync_status()
	var hint := _node(hint_path)
	if hint != null:
		(hint as Label).text = hint_text
	var reason_label := _node(reason_path)
	if reason_label != null:
		(reason_label as Label).text = _reason
	_sync_empty_label()


## Applies the reserve to the layout container (T-0068). A `MarginContainer` theme
## constant, not viewport arithmetic: this panel does none of its own sizing
## (T-0062) - it only asks its container for less room.
func _apply_metrics() -> void:
	var margin := _node(margin_path) as MarginContainer
	if margin == null:
		return
	margin.add_theme_constant_override("margin_bottom", maxi(content_bottom_reserve, 0))


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


## The status line only (T-0064). Drawn in the same colour as the cue it belongs## to, so the line and the row cannot disagree about what is armed.
func _sync_status() -> void:
	var label := _node(status_path)
	if label == null:
		return
	var report: Dictionary = status()
	(label as Label).text = String(report["label"])
	if _armed_id != -1:
		(label as Label).add_theme_color_override("font_color", armed_colour)
	elif _selected_id != -1:
		(label as Label).add_theme_color_override("font_color", selected_colour)
	else:
		(label as Label).add_theme_color_override("font_color", idle_row_colour)


func _sync_empty_label() -> void:
	var list := _node(action_list_path)
	if list == null:
		return
	var existing := list.get_node_or_null("Empty")
	if _rows.is_empty():
		if existing == null:
			var empty := Label.new()
			empty.name = "Empty"
			# The only way the list is empty now is that no arena is bound: Start
			# Wave is a row of every bound level (T-0068).
			empty.text = no_arena_text
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
