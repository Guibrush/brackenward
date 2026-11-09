extends Control

## The game's entry point (T-0052): it owns one run at a time and every screen
## around it.
##
## CONTRACT
## --------
## * **The screen sequence is this scene's whole job:**
##       menu --(Start Game)--> map + opening choice --(confirmed)--> map
##            --(node entered)--> level --(level completed)--> map --> ... --> menu
##   `Exit` quits the application. Nothing else in the game decides which screen
##   is up.
## * **The opening choice (T-0065).** After Start Game the map is up and the choice
##   modal is on top of it; the run has granted nothing, the map is inert, and the
##   player picks one tower and one upgrade. `confirmed` lands the picks through
##   `RunFlow.confirm_opening()`; the modal is closed only after that call succeeds,
##   so a refused grant leaves the player held by the choice. The modal itself is a
##   reusable component (`src/ui/choice_modal.gd`) and knows nothing about towers:
##   this file builds the groups from `RunFlow.opening_offers()`, which is the
##   opening rule, and is the right place for it.
## * **The inventory bar (T-0067).** One bar per run, mounted by this file in the##   `Hud` CanvasLayer above the screens and bound to the run's session, so the map
##   screen and every level read the same object and the same inventory - there is
##   nothing to copy between screens because there is only one bar (its own
##   contract). It is **hidden while the opening choice is up**: a run that has
##   granted nothing has no inventory to view yet, and the modal is the thing the
##   player is answering. It is shown by the confirm that lands the picks - both
##   paths (`_on_opening_confirmed` for a player, `_autostart_confirm_opening` for
##   `--autostart`) - and freed with the run in `_release_run()`. A boot that
##   cannot mount it refuses the run rather than opening one with no inventory
##   view.
## * **The level's panel and the bar are wired here, once per level (T-0068).**
##   `_wire_level_panel()` hands the panel the bar's `claim_point` as a pointer
##   guard (a click on the bar is not a board click), tells the panel to keep its
##   column clear of the bar's measured height (the bar drew over the panel's hint
##   line), and connects the two directions of the selection: a pick in the bar
##   selects it in the panel, and a tower selected on the board marks the bar. The
##   boot owns it because it is the only object that can see both - the bar is in
##   the HUD layer, the panel is inside the level - and neither has to know where
##   the other lives.
## * **One run, one session object.** A `RunFlow` owns the map, the run state and
##   the inventory for exactly one run, and the map screen binds to exactly one
##   session (both contracts live in those files). So the boot creates both on
##   Start and releases both when `run_ended` arrives; a second run gets a second
##   pair. The level is not owned here - `RunFlow` instantiates it and frees it.
## * **The menu is data.** The entries come from `scenes/main_menu.tscn`; this
##   scene is the owner that gives an `action` a meaning. `_handlers()` is the
##   whole table from an action to its behaviour, so a new option is one row in
##   the menu's data plus one line there - the menu, its focus handling and the
##   screen transitions do not change. An action with no handler is printed as
##   `BOOT_UNHANDLED` and does nothing: a dead option must be visible, never
##   silent (T-0052 DoD 5).
## * **Input is not routed here.** Each screen reads its own input through
##   `MapInput` in its own `_unhandled_input`; the boot would otherwise be a
##   second reader of the same event and act on it twice. Driving a screen from
##   code (a demo) calls that screen's `handle_input()`.
## * **`--autostart` skips the menu** and begins a run immediately, walking the
##   map to the first level it can reach, so a headless gate exercises real
##   gameplay from this same entry point instead of an idle menu. It also forces
##   `start_first_wave`, because a headless session cannot press the build
##   panel's Start Wave row (T-0060); a player's level opens in the build phase
##   and waits for it. Since the opening choice blocks the map, autostart
##   **confirms the first offer of every group** itself (T-0065) - the same
##   config the modal would show, so a designer changing the offer table changes
##   the automatic pick with it. That branch is guarded on `autostart`, so an
##   automatic pick can never land in a player's run: the player's run is held by
##   the modal until they confirm it.
## * **`--seconds=N` is the session length**, the same flag the arena reads:
##   whichever screen is up, the application quits after N seconds. Without it
##   the game runs until the player quits.
## * **Inside a session, a run that ends is replaced by another** (T-0053), for as
##   long as the session time allows: an autostart stability run must keep a
##   *game* on screen, not a menu, and a live arena is the only thing that can
##   still report when the session ends. Only `--autostart` restarts: a player's
##   run ending is the player's run ending, and it returns to the menu as always.
##   Without `--seconds=` there is no session, so nothing restarts.
## * Refusals are loud and printed (`BOOT_REFUSED {json}`), never `push_error`: a
##   refused start is a wiring or run-state problem the player can be told about,
##   and an ERROR line would make a working build red for the gates.
##
## Prints on stdout, in this order:
##   BOOT_LIFETIME {json}   once, when a `--seconds=` lifetime was set
##   BOOT_AUTOSTART {json}  once, before the menu is skipped
##   BOOT_SCREEN {json}     once per screen transition, with why
##   BOOT_START {json}      once per run started: seed, map sha, next choices
##   BOOT_OPENING {json}    once per run: the groups the opening choice shows
##   BOOT_OPENING_CONFIRMED {json}  once per applied opening pick, with the items
##   BOOT_OPENING_AUTO {json}       once per autostart run: the picks it made
##   BOOT_HUD {json}        once per inventory-bar mount, show and hide, with what
##                          the bar is bound to and whether it is on screen
##   BOOT_WIRED {json}      once per level: the build panel wired to the bar - the
##                          pointer guard, the reserve above the bar, and both
##                          directions of the selection (T-0068)
##   BOOT_RESTART {json}    once per run replaced because the session goes on
##   BOOT_LEVEL {json}      once per level opened: the mode in force (`autostart`
##                          or `player`) and whether wave 1 started
##   BOOT_COMPLETE {json}   once per level completed, with the run's numbers
##   BOOT_RUN_END {json}    once when the run ends and the menu comes back
##   BOOT_UNHANDLED {json}  an entry whose action has no handler
##   BOOT_QUIT {json}       every quit request, with the screen it came from
##   BOOT_REFUSED {json}    every refusal, with its reason
##   BOOT_SESSION {json}    once, last, on the quit path: this process's session
##
## `BOOT_SESSION` is the session's own measurement - seconds since the process
## started, how many runs it played and how many of those replaced a finished
## run - because a session outlives the runs inside it (ADR-0007). It is the
## only line here that is a measurement rather than an event, and it is printed
## once per boot even if the quit path is raised twice: two lines under one
## prefix would be ambiguous. The shipped entry point runs one boot per process,
## so once per boot is once per process there. The requested `--seconds=` length
## is an event and is therefore `BOOT_LIFETIME`, at the other end of the session.
##
## `RUNFLOW_*`, `MAPSCREEN_*`, `MENU_*` and `ARENA_*` lines in the same output are
## printed by the objects under this one, not by this file.

## The screen on show changed. `screen_name` is one of `SCREEN_NAMES`.
signal screen_changed(screen_name: String)
## A run began.
signal run_started(seed_value: int)
## The run ended, of its own accord: defeat or the boss.
signal run_finished(victory: bool, reason: String)
## The quit path was raised. Emitted before the application actually quits, so a
## test can observe the request without ending its own process.
signal quit_requested()

## The action values a menu row can carry. They are data in the menu and meaning
## here: this table, and the menu's entry list, are the two places a new option
## touches.
const ACTION_START := "start"
const ACTION_EXIT := "exit"

## 0 means "pick a seed when the run starts". A named constant so the inspector
## value reads as the choice it is rather than a bare zero.
const SEED_RANDOM := 0

## How many nodes autostart may enter before giving up on reaching a level. A
## map's opening choices can all be non-level nodes (a store, a rest, a
## high-stakes roll), so autostart has to settle them to reach a level; a map that
## never offers one is reported, not looped on.
const AUTOSTART_MAX_STEPS := 32

const EXIT_CODE_OK := 0
const MIN_SECONDS := 0.01
const USEC_PER_SECOND := 1000000.0

## The screens this scene can be showing. One at a time; the level is a child of
## the run session, so LEVEL means "the session has a level open".
enum Screen { NONE, MENU, MAP, LEVEL }
const SCREEN_NAMES: Array[String] = ["none", "menu", "map", "level"]

# Preloaded rather than referenced by class name, for the reason `inventory.gd`
# gives: `--check-only` must not depend on the global class cache having been
# built by a prior `--import`.
const RunFlowScript := preload("res://src/gameplay/run_flow.gd")
const ChoiceModalScript := preload("res://src/ui/choice_modal.gd")
const ItemCatalogueScript := preload("res://src/gameplay/item_catalogue.gd")

@export_group("Scenes")
## The menu. Its entries are the menu's data; this scene interprets their actions.
@export var menu_scene: PackedScene
## The between-level map screen, one instance per run.
@export var map_scene: PackedScene
## One level of the run. Handed to `RunFlow`, which instantiates it per level.
@export var level_scene: PackedScene
## The blocking choice modal, one instance per run: the opening pick, and later
## the event node and the store. Required for a run - a run with nothing granted
## and no way to choose would be an empty run.
@export var choice_modal_scene: PackedScene
## The inventory bar, one instance per run, mounted in the HUD layer and bound to
## the run's session (T-0067). Required for a run: it is the game's inventory view
## on both the map screen and in a level.
@export var inventory_bar_scene: PackedScene

@export_group("Layout — node paths")
## Where the level and the run session are mounted. Behind the screens, so a
## full-screen screen covers a live level instead of the reverse.
@export var game_layer_path: NodePath = ^"Game"
## Where the menu and the map screen are mounted.
@export var screens_path: NodePath = ^"Screens"
## Where the inventory bar is mounted: the HUD layer, drawn above the screens so
## the bar is on top of both the map screen and a level without either of them
## knowing it exists.
@export var hud_layer_path: NodePath = ^"Hud"

@export_group("Copy — the opening choice")
## Title of the opening choice the modal shows. Player-facing.
@export var opening_title: String = "Choose your opening"
## Group heading for the tower offers.
@export var opening_tower_label: String = "Tower"
## Group heading for the upgrade offers.
@export var opening_upgrade_label: String = "Upgrade"

@export_group("Run")
## The seed the next run is built from, or `SEED_RANDOM` to pick one.
@export var run_seed: int = SEED_RANDOM
## Skip the menu and begin a run on `_ready`. Also set by `--autostart`.
@export var autostart: bool = false
## Whether a level's first wave starts as soon as the level opens (T-0060).
##
## False for a player: the build panel offers a Start Wave row, so a level opens
## in the build phase and waits for the player's decision. It is true only when
## `--autostart` was passed, because a headless session has nobody to press the
## row and `smoke.ps1` measures waves that never ran otherwise. Setting it in the
## inspector alone cannot auto-start a level - `_on_level_opened()` requires
## `start_first_wave and autostart`, and `autostart` is only ever set by the
## command line (`--autostart` in `_parse_args`).
@export var start_first_wave: bool = false

# --- screens ----------------------------------------------------------------

## Untyped on purpose: the menu and the map screen are different scripts, and a
## statically typed base would have to name every method each one has
## (`run_flow.gd` records the same reason).
var _menu = null
var _map_screen = null
## The run's opening choice, or null once it is confirmed. One per run, freed with
## the run; while it is open the map screen under it is inert (its own contract).
var _opening_modal = null
## The run's inventory bar, mounted in the HUD layer and bound to the run session,
## or null between runs. One per run, freed with it.
var _inventory_bar = null
## The run session for the current run, or null between runs.
var _flow = null
var _screen: int = Screen.NONE

# --- quit -------------------------------------------------------------------

## Requests raised through the quit path. A count, not a bool, so "asked twice"
## is visible.
var _quit_requests: int = 0
## Whether the quit path may end the process. Play never touches it; a demo that
## drives Exit has to, because quitting the tree would end the demo mid-report.
var _quit_enabled: bool = true
var _session_seconds: float = 0.0
var _session_timer: Timer = null
## When the session started, for the length of the session and for how deep into
## it a run began. Stamped at the top of `_ready`, before any screen exists.
var _session_started_usec: int = 0
## Runs started by this boot, restarts included. A count, not a bool, because
## "the session restarted the run" has to be visible in the evidence.
var _runs_started: int = 0
## Runs replaced because the session had time left: one per `BOOT_RESTART`. Kept
## apart from `_runs_started` because a replacement that is refused counts as a
## restart attempt and as no run at all.
var _restarts: int = 0
## Whether `BOOT_SESSION` has been printed. The quit path can be raised twice; the
## session is measured once, so the summary is never ambiguous.
var _session_reported: bool = false
## A replacement run is queued for the next idle frame. Set when a run ends inside
## a session; cleared by `_begin_pending_restart()`.
var _restart_pending: bool = false

# --- diagnostics ------------------------------------------------------------

## Handled menu actions since the boot started. One entry that did nothing must
## not look like one that did.
var _effects: int = 0
var _last_action: String = ""
var _refusals: int = 0


func _ready() -> void:
	# The session clock starts with the process, not with `--seconds=`: the entry
	# point *is* the session (ADR-0007), so a quit from the menu has to report how
	# long the session lasted just as a timed one does.
	_session_started_usec = Time.get_ticks_usec()
	_parse_args()
	if not _interfaces_are_wired():
		return
	# The timer that ends the session starts before any screen does, so an
	# autostart run that ends during its own walk already knows the session is
	# in progress and is replaced rather than left on the menu.
	if _session_seconds > 0.0:
		_start_session_timer()
	if autostart:
		_autostart_run()
	else:
		_show_menu("opening")


# --- the screens ------------------------------------------------------------

## Brings the menu up, releasing whatever run was in progress. Safe to call when
## the menu is already up: it is reused, not rebuilt, because its data belongs to
## the scene.
func _show_menu(why: String) -> void:
	_release_run()
	if _menu == null:
		if menu_scene == null:
			_refuse("show the menu", "no menu_scene is wired")
			return
		_menu = menu_scene.instantiate()
		if _menu == null:
			_refuse("show the menu", "the menu scene did not instantiate")
			return
		_menu.name = "MainMenu"
		_connect(_menu, "option_chosen", _on_option_chosen)
		_screens().add_child(_menu)
	_menu.show()
	# No redraw: the menu drew itself in `_ready`, and its data only changes when
	# a caller sets new entries. A refresh here would print a second MENU_DATA for
	# a list that did not change (L-038: two lines under one prefix is ambiguous).
	_set_screen(Screen.MENU, why)


## Starts a run: a fresh session, a fresh map screen bound to it, and `start_run`.
## Returns whether the run began. Every failure releases what was built and leaves
## the caller on the menu with a printed reason.
func _start_run(entry_id: String) -> bool:
	if _flow != null:
		_refuse(
			"start a run", "a run session is still alive; the previous run has not been released"
		)
		return false
	if map_scene == null or level_scene == null:
		_refuse("start a run", "map_scene or level_scene is not wired")
		return false
	if choice_modal_scene == null:
		# A run starts with nothing granted (T-0065), so a boot with no way to
		# choose would open an empty run behind an inert map: refused, loudly.
		_refuse(
			"start a run",
			"choice_modal_scene is not wired: the run would start with nothing granted and no way to choose"
		)
		return false
	if game_layer_path.is_empty() or get_node_or_null(game_layer_path) == null:
		_refuse("start a run", "the game layer '%s' is missing from the scene" % game_layer_path)
		return false
	if inventory_bar_scene == null:
		# The bar is the game's inventory view (T-0067). A run without it would be
		# a run the player cannot see their inventory in, so it is refused here
		# rather than opened and left thin.
		_refuse("start a run", "inventory_bar_scene is not wired: the run would have no inventory view")
		return false
	if hud_layer_path.is_empty() or get_node_or_null(hud_layer_path) == null:
		_refuse("start a run", "the HUD layer '%s' is missing from the scene" % hud_layer_path)
		return false

	# The session is created and wired before the run begins, so `map_ready` is
	# heard by the screen that is about to draw it (T-0050's documented order).
	var flow = RunFlowScript.new()
	flow.name = "RunFlow"
	flow.level_scene = level_scene
	_flow = flow
	_connect(flow, "map_ready", _on_map_ready)
	_connect(flow, "level_opened", _on_level_opened)
	_connect(flow, "level_completed", _on_level_completed)
	_connect(flow, "run_ended", _on_run_ended)
	_game_layer().add_child(flow)

	var screen = map_scene.instantiate()
	if screen == null:
		_release_run()
		_refuse("show the map screen", "the map screen scene did not instantiate")
		return false
	screen.name = "MapScreen"
	_map_screen = screen
	_screens().add_child(screen)
	if not screen.bind_run(flow):
		_release_run()
		_refuse("show the map screen", "the map screen refused the session")
		return false

	var seed_value := _seed_for_new_run()
	if not flow.start_run(seed_value):
		# The session prints its own reason; this is the boot's copy of the
		# decision, and the menu stays up so the player can try again.
		_refuse("start a run", flow.last_refusal())
		_release_run()
		return false

	if _menu != null:
		_menu.hide()
	# The bar is mounted with the run, before the choice goes up: a mount failure
	# must leave the player on the menu, not on a map with no inventory view.
	if not _mount_inventory_bar():
		_show_menu("the inventory bar could not be mounted")
		return false

	# The choice goes up before the run counts as started: a run with nothing
	# granted is only usable once the modal is on top of the map (T-0065). A
	# modal that cannot be shown leaves the player on the menu with the reason
	# printed rather than on an inert map they cannot leave.
	if not _show_opening_choice():
		_show_menu("the opening choice could not be shown")
		return false
	print("BOOT_START " + JSON.stringify({
		"entry": entry_id,
		"seed": seed_value,
		"sha": flow.map().sha(),
		"selectable": flow.map().selectable_nodes(),
		"screens": screen_name(),
	}))
	_runs_started += 1
	run_started.emit(seed_value)
	return true


## Releases the run session and the map screen that was bound to it. Queued, not
## freed: this is called from inside the session's own `run_ended` handler, and
## the session still has lines to print after emitting it.
##
## The two nodes are renamed first because a restart mounts the next run's pair in
## the same frame (T-0053), and the names are siblings: without the rename Godot
## would warn that the name is already in use. Nothing looks these nodes up by
## name - the scene's own layers are the exported paths.
func _release_run() -> void:
	# The choice first: a modal bound to a session that is going away must never
	# outlive it, or the next run's map would be held by a dead choice.
	_free_opening_modal()
	_free_inventory_bar()
	if _map_screen != null:
		_map_screen.name = "MapScreen@released"
		_map_screen.queue_free()
		_map_screen = null
	if _flow != null:
		_flow.name = "RunFlow@released"
		_flow.queue_free()
		_flow = null


# --- the inventory bar (T-0067) ---------------------------------------------

## Mounts one bar in the HUD layer and binds it to the run session, hidden while
## the opening choice still holds the run: a run with nothing granted has no
## inventory to view, and the choice is what the player is answering. Returns
## whether the bar is mounted and bound; every failure is printed and changes
## nothing, so the caller can release the run and stay on the menu.
func _mount_inventory_bar() -> bool:
	if _flow == null:
		_refuse("mount the inventory bar", "no run has started")
		return false
	var hud := _hud_layer()
	if hud == null:
		_refuse("mount the inventory bar", "the HUD layer '%s' is missing" % hud_layer_path)
		return false
	var bar = inventory_bar_scene.instantiate()
	if bar == null:
		_refuse("mount the inventory bar", "the inventory bar scene did not instantiate")
		return false
	bar.name = "InventoryBar"
	# Set before binding, so the first draw the bar prints already carries the
	# visibility the player will get (its `INVENTORY_BAR_SHOWN` line reports it).
	bar.visible = not _flow.opening_pending()
	hud.add_child(bar)
	if not bar.bind_session(_flow):
		# The bar printed its own reason; this copy names what the boot asked for.
		_refuse("mount the inventory bar", "the bar refused the run session")
		bar.name = "InventoryBar@refused"
		bar.queue_free()
		return false
	_inventory_bar = bar
	_print_hud("mount", "the run began")
	return true


## Shows the bar once the opening picks have been applied - the same call from a
## player's confirm and from the autostart pick, so the two paths cannot diverge.
## A no-op when no bar is mounted (an autostart run that never reached here) and a
## printed no-op when the bar is already showing, so one action prints one line.
func _show_inventory_bar(why: String) -> void:
	if _inventory_bar == null or not is_instance_valid(_inventory_bar):
		return
	if _inventory_bar.visible:
		return
	_inventory_bar.visible = true
	_print_hud("show", why)


## Releases the run's bar. Unbound before it is freed, so the session's signals
## stop feeding a bar that is going away, and renamed first for the reason
## `_release_run()` gives: a restart mounts the next run's bar in the same frame.
func _free_inventory_bar() -> void:
	if _inventory_bar == null:
		return
	var bar = _inventory_bar
	_inventory_bar = null
	if not is_instance_valid(bar):
		return
	bar.unbind()
	bar.name = "InventoryBar@released"
	bar.queue_free()


## What the boot decided about the bar, in the bar's own terms: whether it is on
## screen, what it is bound to, and the run's counts at that moment.
func _print_hud(action: String, why: String) -> void:
	var counts := _inventory_counts()
	print("BOOT_HUD " + JSON.stringify({
		"action": action,
		"why": why,
		"visible": _inventory_bar != null and is_instance_valid(_inventory_bar) and _inventory_bar.visible,
		"bound": _flow != null and _inventory_bar != null and is_instance_valid(_inventory_bar),
		"towers": counts["towers"],
		"upgrades": counts["upgrades"],
		"opening_pending": _flow.opening_pending() if _flow != null else false,
		"screen": screen_name(),
	}))


func _inventory_counts() -> Dictionary:
	if _flow == null:
		return {"towers": 0, "upgrades": 0}
	var inventory = _flow.inventory()
	if inventory == null:
		return {"towers": 0, "upgrades": 0}
	return {"towers": inventory.tower_count(), "upgrades": inventory.upgrade_count()}


# --- panel <-> bar (T-0068) -------------------------------------------------

## Wires the level's build panel to the run's inventory bar: the pointer guard, the
## reserve that keeps the panel clear of the bar, and one selection in two views.
## Called on every `level_opened`, because a run opens more than one level and each
## level instances its own panel.
##
## Every step is guarded on the method existing: a level without a build panel (or
## a bar from an older scene) is refused with a printed reason rather than crashing
## the run, and a boot that wires half of it is visible in the log.
func _wire_level_panel() -> void:
	if _inventory_bar == null or not is_instance_valid(_inventory_bar):
		return
	if _flow == null:
		return
	var arena = _flow.current_level()
	if arena == null:
		return
	var panel = _find_panel(arena)
	if panel == null:
		_refuse("wire the build panel", "the level has no build panel to wire to the inventory bar")
		return
	var bar = _inventory_bar
	var guard_added := false
	if panel.has_method("add_pointer_guard"):
		guard_added = bool(panel.add_pointer_guard(Callable(bar, "claim_point")))
	# The bar's own rect says how tall it is; the panel then leaves room for it, so
	# the bar's height has one owner and this file adds no constant of its own.
	var bar_height := int(bar.get_global_rect().size.y)
	if panel.has_method("reserve_bottom") and bar_height > 0:
		panel.reserve_bottom(bar_height)
	# Both directions. `select_instance` does not re-raise `tower_selected` and
	# `mark_selected` raises nothing, so the two views cannot echo each other.
	if panel.has_method("select_instance"):
		_connect(bar, "tower_selected", Callable(panel, "select_instance"))
	_connect(panel, "tower_selected", Callable(bar, "mark_selected"))
	print("BOOT_WIRED " + JSON.stringify({
		"panel": String(panel.name),
		"bar": String(bar.name),
		"guard": guard_added,
		"reserve": bar_height,
		"panel_reserve": int(panel.content_reserve()) if panel.has_method("content_reserve") else 0,
		"level": _flow.level_node_id(),
		"screen": screen_name(),
	}))


## The build panel under `node`, found by what it can do (`bind_arena`) rather than
## by its node name: the level scene is free to move it, and this file must not be
## the second thing that knows where it lives.
func _find_panel(node: Node) -> Node:
	if node is Control and node.has_method("bind_arena"):
		return node
	for child in node.get_children():
		var found := _find_panel(child)
		if found != null:
			return found
	return null


# --- the menu's actions -----------------------------------------------------

## The whole table from a menu action to its behaviour. Adding an option is one
## entry in the menu's data plus one line here.
func _handlers() -> Dictionary:
	return {
		ACTION_START: Callable(self, "_start_run"),
		ACTION_EXIT: Callable(self, "_request_quit"),
	}


func _on_option_chosen(entry_id: String, action: String) -> void:
	var handlers := _handlers()
	if not handlers.has(action):
		print("BOOT_UNHANDLED " + JSON.stringify({
			"entry": entry_id,
			"action": action,
			"screen": screen_name(),
			"why": "no handler for this action; the option is dead until one exists",
		}))
		return
	_last_action = action
	_effects += 1
	(handlers[action] as Callable).call(entry_id)


## Raised by the Exit entry, and by the session timer. One quit path, so "the
## game closed" always means the same thing and is always printed.
func _request_quit(entry_id: String) -> void:
	_quit_requests += 1
	print("BOOT_QUIT " + JSON.stringify({
		"entry": entry_id,
		"requests": _quit_requests,
		"screen": screen_name(),
		"enabled": _quit_enabled,
	}))
	quit_requested.emit()
	# Last line before the process goes: what the session as a whole did.
	_print_session_summary()
	if _quit_enabled:
		get_tree().quit(EXIT_CODE_OK)


## The session's measurement, printed once and last. `seconds` is the process's
## lifetime, `runs` every run this boot started (restarts included) and
## `restarts` the runs that replaced a finished one - so a session that played
## three runs and restarted twice reads `runs: 3, restarts: 2`, and
## `runs - restarts` is always 1 or 0. A consumer that needs to know the session
## length reads this field, not an arena's age (ADR-0007).
func _print_session_summary() -> void:
	if _session_reported:
		return
	_session_reported = true
	print("BOOT_SESSION " + JSON.stringify({
		"seconds": _session_elapsed(),
		"runs": runs_started(),
		"restarts": _restarts,
	}))


# --- the opening choice ------------------------------------------------------

## Puts the opening choice over the map, built from the session's own offer table.
## Returns whether the modal is open and waiting.
##
## The **groups** are this file's business, not the modal's: "one tower and one
## upgrade" is the opening rule (T-0065), and `RunFlow.opening_offers()` is the
## data it applies to. The modal only ever sees groups, options and a selection
## rule, which is what lets the event node and the store reuse it.
func _show_opening_choice() -> bool:
	if _flow == null:
		_refuse("show the opening choice", "no run has started")
		return false
	if not _flow.opening_pending():
		_refuse("show the opening choice", "the run has no opening choice to make")
		return false
	var modal = choice_modal_scene.instantiate()
	if modal == null:
		_refuse("show the opening choice", "the choice modal scene did not instantiate")
		return false
	modal.name = "ChoiceModal"
	# Connected before `open()`, per the modal's contract: a confirm with nobody
	# listening would grant nothing and close nothing.
	_connect(modal, "confirmed", _on_opening_confirmed)
	# Mounted after the map screen, so it draws over it and takes the pointer
	# first. Nothing else is needed to make the map inert - a full-screen overlay
	# that stops the pointer and consumes mapped keys is the blocking (the
	# modal's own contract).
	_screens().add_child(modal)
	_opening_modal = modal

	var config := _opening_config()
	if not modal.open(config):
		# The modal printed why; the boot's copy names what it could not do.
		_refuse("show the opening choice", "the choice modal refused the opening config")
		_free_opening_modal()
		return false

	print("BOOT_OPENING " + JSON.stringify({
		"title": String(config["title"]),
		"groups": _opening_group_summary(config),
		"rows": modal.row_count(),
		"towers": _flow.inventory().tower_count(),
		"upgrades": _flow.inventory().upgrade_count(),
		"pending": _flow.opening_pending(),
		"screen": screen_name(),
	}))
	return true


## The player's pick, applied through the session's own rule. The modal is closed
## only once the grant succeeded: a refused grant leaves the choice up with the
## session's reason, so the player is held by it instead of released with nothing.
func _on_opening_confirmed(picks: Array) -> void:
	if _flow == null:
		_refuse("apply the opening choice", "no run has started")
		return
	var entries := _entries_from_picks(picks)
	if not _flow.confirm_opening(entries):
		var why: String = _flow.last_refusal()
		if _opening_modal != null and _opening_modal.has_method("show_reason"):
			_opening_modal.show_reason(why)
		_refuse("apply the opening choice", why)
		return
	print("BOOT_OPENING_CONFIRMED " + JSON.stringify({
		"picks": entries,
		"towers": _flow.inventory().tower_count(),
		"upgrades": _flow.inventory().upgrade_count(),
		"pending": _flow.opening_pending(),
	}))
	_refresh_map_after_choice()
	_show_inventory_bar("the opening choice was confirmed")
	if _opening_modal != null:
		_opening_modal.close()
	_free_opening_modal()


## The map screen captured the run's numbers when the run began, before the choice
## was applied, and it refuses a choice while its snapshot disagrees with the
## session (its own contract). Once the picks land the screen is still showing
## "Towers 0" against a run that holds one, so every node is refused as stale: the
## map would be inert *after* the choice as well as before it. The grant is what
## changes the numbers the screen reads, so the grant is what refreshes it - the
## boot owns this ordering, the screen only reports what it was handed.
func _refresh_map_after_choice() -> void:
	if _map_screen != null and is_instance_valid(_map_screen) and _map_screen.has_method("refresh"):
		_map_screen.refresh()


## Releases the opening modal, if one is mounted. Queued rather than freed for
## the reason `_release_run()` gives - a confirm handler can reach here and the
## modal still has a line to print - and renamed first so a restart can mount the
## next run's modal in the same frame without a sibling-name clash.
func _free_opening_modal() -> void:
	if _opening_modal == null:
		return
	_opening_modal.name = "ChoiceModal@released"
	_opening_modal.queue_free()
	_opening_modal = null


## The groups the opening choice shows, in order. The opening rule in one place:
## a tower group and an upgrade group, and the modal knows about neither.
func _opening_groups() -> Array:
	return [
		{"id": "tower", "label": opening_tower_label, "tower": true},
		{"id": "upgrade", "label": opening_upgrade_label, "tower": false},
	]


## The opening choice as data: one group per kind in the run's offer table, each
## option carrying the catalogue entry as its payload (what `_on_opening_confirmed()`
## hands back to the session). Every group is guaranteed non-empty because
## `start_run()` refuses a table without one tower and one upgrade.
func _opening_config() -> Dictionary:
	var offers: Array = _flow.opening_offers() if _flow != null else []
	var groups: Array = []
	for descriptor in _opening_groups():
		var want_tower := bool((descriptor as Dictionary)["tower"])
		var options: Array = []
		for raw in offers:
			var offer: Dictionary = raw
			if _offer_is_tower(offer) != want_tower:
				continue
			options.append({
				"id": String(offer.get("id", "")),
				"label": String(offer.get("display_name", offer.get("id", ""))),
				"detail": "tier %d" % int(offer.get("tier", 1)),
				"payload": offer,
			})
		if options.is_empty():
			continue
		groups.append({
			"id": String((descriptor as Dictionary)["id"]),
			"label": String((descriptor as Dictionary)["label"]),
			"options": options,
		})
	return {
		"title": opening_title,
		"rule": ChoiceModalScript.RULE_ONE_PER_GROUP,
		"groups": groups,
	}


## An offer is a tower when the catalogue says so; every other offer kind is an
## upgrade (a rune or a relic), which is exactly how `RunFlow` counts the picks.
func _offer_is_tower(offer: Dictionary) -> bool:
	return String(offer.get("kind", "")) == ItemCatalogueScript.KIND_TOWER


## `{group, id, options}` per group, for the `BOOT_OPENING` line.
func _opening_group_summary(config: Dictionary) -> Array:
	var out: Array = []
	for raw in (config.get("groups", []) as Array):
		var group: Dictionary = raw
		var ids: Array = []
		for option in (group["options"] as Array):
			ids.append(String((option as Dictionary)["id"]))
		out.append({"id": String(group["id"]), "label": String(group["label"]), "options": ids})
	return out


## The picks `confirmed` carries, as the `{kind, type_id, tier}` triples the
## session's own rule takes. A pick with no payload is dropped rather than
## guessed at, so a malformed pick is refused by the session instead of granted.
func _entries_from_picks(picks: Array) -> Array:
	var entries: Array = []
	for raw in picks:
		if not (raw is Dictionary):
			continue
		var entry := _pick_entry(raw as Dictionary)
		if entry.is_empty():
			continue
		entries.append(entry)
	return entries


func _pick_entry(pick: Dictionary) -> Dictionary:
	var payload = pick.get("payload", null)
	if not (payload is Dictionary):
		return {}
	var entry: Dictionary = payload
	var type_id := String(entry.get("id", ""))
	if type_id == "":
		return {}
	return {
		"kind": String(entry.get("kind", "")),
		"type_id": type_id,
		"tier": int(entry.get("tier", 0)),
	}


# --- the session's signals --------------------------------------------------

func _on_map_ready(seed_value: int, selectable: Array) -> void:
	_set_screen(Screen.MAP, "map_ready")
	print("BOOT_MAP " + JSON.stringify({
		"seed": seed_value,
		"selectable": selectable,
		"screens": screen_name(),
	}))


func _on_level_opened(node_id: int, level_index: int, elite: bool) -> void:
	_set_screen(Screen.LEVEL, "level_opened")
	# `and autostart` is load-bearing (T-0060): only the command line may start a
	# wave unasked, so a level opened by a player always lands in the build phase
	# and waits for the build panel's Start Wave row, whatever `start_first_wave`
	# was left at in the inspector.
	var auto_start := start_first_wave and autostart
	var started := false
	if auto_start:
		started = _start_first_wave()
	# The level instanced its own build panel a frame before this signal; wiring it
	# here is what makes the bar and the panel one inventory view (T-0068).
	_wire_level_panel()
	print("BOOT_LEVEL " + JSON.stringify({
		"node": node_id,
		"level_index": level_index,
		"elite": elite,
		"mode": "autostart" if auto_start else "player",
		"wave_started": started,
		"start_first_wave": start_first_wave,
		"autostart": autostart,
		"level_name": str(_flow.current_level().name) if _flow != null else "",
	}))


func _on_level_completed(node_id: int, levels_completed: int, boss: bool) -> void:
	# A boss completion ends the run, and `run_ended` arrives before this signal -
	# in that case the session has already been released and the menu is up, so
	# there is nothing here to draw.
	if _flow == null:
		return
	_set_screen(Screen.MAP, "level_completed")
	var run = _flow.run_state()
	print("BOOT_COMPLETE " + JSON.stringify({
		"node": node_id,
		"levels_completed": levels_completed,
		"boss": boss,
		"hq": run.hq_health() if run != null else 0,
		"gold": run.gold() if run != null else 0,
		"screens": screen_name(),
	}))


func _on_run_ended(victory: bool, reason: String) -> void:
	var summary := {
		"victory": victory,
		"reason": reason,
		"screens_before": screen_name(),
	}
	if _flow != null and _flow.run_state() != null:
		var run = _flow.run_state()
		summary["status"] = run.status_name()
		summary["levels_completed"] = run.level_index()
		summary["hq"] = run.hq_health()
		summary["gold"] = run.gold()
	run_finished.emit(victory, reason)
	print("BOOT_RUN_END " + JSON.stringify(summary))
	# A session with `--autostart` keeps playing: the run that just ended is
	# replaced before the menu is built, so a stability run leaves a live arena
	# behind a decided run instead of an idle menu (T-0053).
	if _session_keeps_playing():
		_replace_run(victory, reason)
		return
	# Back to the menu: the run is over, and the next Start gets a new session.
	_show_menu("run ended")


# --- autostart --------------------------------------------------------------

## Skips the menu: starts a run and walks the map until a level is open. Every
## node it enters on the way is a real node of a real map - this is the same path
## a player takes, only chosen automatically.
func _autostart_run() -> void:
	print("BOOT_AUTOSTART " + JSON.stringify({
		"seed": run_seed,
		"seconds": _session_seconds,
		"start_first_wave": start_first_wave,
	}))
	_autostart_begin("--autostart", "autostart refused")


## Starts a run and walks it to its first level. Shared by `--autostart` and by the
## replacement run a session starts when one ends, so both begin the same way.
## Returns whether a level is open. A refused start puts the menu up with the
## reason printed; a walk that fails prints why and leaves the screen alone. The
## caller never retries - the next attempt belongs to the session clock.
func _autostart_begin(entry_id: String, refusal_why: String) -> bool:
	if not _start_run(entry_id):
		_show_menu(refusal_why)
		return false
	if not _autostart_confirm_opening(entry_id):
		_show_menu(refusal_why)
		return false

	var steps := 0
	while _flow != null and _flow.run_state() != null and not _flow.is_in_level():
		if _flow.run_state().is_over():
			break
		if steps >= AUTOSTART_MAX_STEPS:
			_refuse(
				"autostart a level", "no level node was reached in %d steps" % AUTOSTART_MAX_STEPS
			)
			break
		steps += 1
		var pick := _next_level_node()
		if pick == -1:
			pick = _first_selectable()
		if pick == -1:
			_refuse("autostart a level", "the map offers no node to enter")
			break
		if not _flow.enter_node(pick):
			if _flow == null:
				# The node ended the run (a high-stakes roll can), so there is no
				# route left to walk: the session's handler has taken over.
				break
			_refuse("autostart a level", _flow.last_refusal())
			break
		if _flow == null:
			break
		# An open event blocks the route until one offer is taken, exactly as it
		# does for a player; autostart takes the first offer.
		var offers = _flow.event_offer()
		if offers != null and not (offers.stock() as Array).is_empty():
			_flow.choose_event(0)

	if _flow == null:
		# A walk interrupted by the run ending is not a refusal: the session has
		# already queued the replacement run that this call was checking for.
		if not _restart_pending:
			_refuse("autostart a level", "the run ended before a level opened")
		return false
	if not _flow.is_in_level():
		_refuse("autostart a level", "the run is on the map with no level open")
		return false
	print("BOOT_AUTOSTART " + JSON.stringify({
		"level_open": true,
		"node": _flow.level_node_id(),
		"screens": screen_name(),
		"steps": steps,
	}))
	return true


## Takes the first option in every group of the choice a player would have been
## shown, because a headless session has nobody to pick one. The guard is
## `autostart` and nothing else: `_autostart_begin()` is only ever reached from
## `--autostart` and from the replacement run a `--seconds=` session starts, so a
## player's run can never be confirmed here - it stays held by the modal.
##
## The modal `_start_run()` mounted is closed and released in the same call: in a
## headless session nobody reads it, and leaving it up would draw the level under
## a choice that has already been made.
func _autostart_confirm_opening(entry_id: String) -> bool:
	if not autostart or _flow == null or not _flow.opening_pending():
		return true
	var picks := _autostart_opening_entries()
	if picks.is_empty():
		_refuse(
			"pick the opening choice", "the offer table resolves to no pickable group"
		)
		return false
	if not _flow.confirm_opening(picks):
		_refuse("pick the opening choice", _flow.last_refusal())
		return false
	print("BOOT_OPENING_AUTO " + JSON.stringify({
		"entry": entry_id,
		"picks": picks,
		"towers": _flow.inventory().tower_count(),
		"upgrades": _flow.inventory().upgrade_count(),
		"pending": _flow.opening_pending(),
	}))
	_refresh_map_after_choice()
	_show_inventory_bar("the opening choice was auto-confirmed")
	if _opening_modal != null:
		_opening_modal.close()
	_free_opening_modal()
	return true


## The first option of every group of the opening choice, as the session's
## `{kind, type_id, tier}` triples. Read from the same config the modal would show,
## so "the first offer" moves with the offer table instead of being a second list
## of items that can drift out of it.
func _autostart_opening_entries() -> Array:
	var entries: Array = []
	for raw in (_opening_config().get("groups", []) as Array):
		var group: Dictionary = raw
		var options: Array = group.get("options", [])
		if options.is_empty():
			continue
		var entry := _pick_entry(options[0] as Dictionary)
		if entry.is_empty():
			continue
		entries.append(entry)
	return entries


## Replaces the run that just ended with another, because the `--seconds=` session
## has time left. The ended run is released now; the next one is begun on the next
## idle frame, never inside this session's own `run_ended` emission nor inside a
## map walk that the end interrupted - that is how a run would nest inside a run.
func _replace_run(victory: bool, reason: String) -> void:
	_release_run()
	_restart_pending = true
	_restarts += 1
	print("BOOT_RESTART " + JSON.stringify({
		"runs_started": _runs_started,
		"victory": victory,
		"reason": reason,
		"elapsed_seconds": _session_elapsed(),
		"session_seconds": _session_seconds,
	}))
	call_deferred("_begin_pending_restart")


## Starts the queued replacement run, walking it to its first level: a session
## parked on the map has nothing to report at the end either.
func _begin_pending_restart() -> void:
	if not _restart_pending:
		return
	_restart_pending = false
	_autostart_begin("--autostart restart", "the session could not start another run")


## The id of a next choice that plays a level, or -1. `RunFlow.LEVEL_TYPES` is
## the session's own list, so autostart cannot disagree with what opens a level.
func _next_level_node() -> int:
	var map = _flow.map()
	for id in map.selectable_nodes():
		if RunFlowScript.LEVEL_TYPES.has(String(map.type_of(int(id)))):
			return int(id)
	return -1


func _first_selectable() -> int:
	var nodes: Array = _flow.map().selectable_nodes()
	if nodes.is_empty():
		return -1
	return int(nodes[0])


# --- session lifetime -------------------------------------------------------

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autostart":
			autostart = true
			# The one place the first wave is forced (T-0060): a headless session
			# cannot press the build panel's Start Wave row, and `smoke.ps1`
			# asserts on waves that actually ran. A player's boot never reaches
			# this branch, so `start_first_wave` stays at its exported false.
			start_first_wave = true
		elif a.begins_with("--seconds="):
			_session_seconds = maxf(0.0, float(a.trim_prefix("--seconds=")))


func _start_session_timer() -> void:
	_session_timer = Timer.new()
	_session_timer.name = "SessionTimer"
	_session_timer.wait_time = maxf(_session_seconds, MIN_SECONDS)
	_session_timer.one_shot = true
	_session_timer.timeout.connect(_on_session_timer_timeout)
	add_child(_session_timer)
	_session_timer.start()
	print("BOOT_LIFETIME " + JSON.stringify({"seconds": _session_seconds}))


## Whether an ended run must be replaced instead of returning to the menu: only an
## `--autostart` run inside a `--seconds=` session that has not raised its quit
## yet. A player's run ending is the player's run ending, and a run without a
## session has no time left to fill.
func _session_keeps_playing() -> bool:
	return autostart and _session_seconds > 0.0 and _session_timer != null and _quit_requests == 0


## Seconds since this boot's `_ready`. Stamped with the process, so it measures
## the session the gates run, not the timer they set.
func _session_elapsed() -> float:
	if _session_started_usec == 0:
		return 0.0
	return float(Time.get_ticks_usec() - _session_started_usec) / USEC_PER_SECOND


func _on_session_timer_timeout() -> void:
	_request_quit("--seconds")


# --- queries ----------------------------------------------------------------

func screen() -> int:
	return _screen


func screen_name() -> String:
	if _screen < 0 or _screen >= SCREEN_NAMES.size():
		return "unknown(%d)" % _screen
	return SCREEN_NAMES[_screen]


## The menu while it exists (it is reused across runs), or null before `_ready`
## and in autostart play, where the menu is skipped.
func menu():
	return _menu


## The map screen bound to the current run, or null between runs.
func map_screen():
	return _map_screen


## The run session of the current run, or null between runs.
func flow():
	return _flow


## The opening choice modal while the run is held by it: null before a run, once
## the pick is applied, and in autostart play, where the boot confirms it itself.
func opening_modal():
	return _opening_modal


## The run's inventory bar while a run is bound to it, or null before a run and
## between runs. One instance for the whole run, on both screens.
func inventory_bar():
	return _inventory_bar


## Handled menu actions since the boot started.
func effects() -> int:
	return _effects


func last_action() -> String:
	return _last_action


func quit_requests() -> int:
	return _quit_requests


## Runs this boot started, the replacement runs of a session included.
func runs_started() -> int:
	return _runs_started


func refused_count() -> int:
	return _refusals


## DEMO ONLY, and named as such: lets a harness drive the Exit entry without
## quitting its own process, which would end the demo before it printed its
## result. Play never calls this; the quit path is otherwise unconditional.
func set_quit_enabled_for_demo(enabled: bool) -> void:
	_quit_enabled = enabled


# --- internals --------------------------------------------------------------

func _interfaces_are_wired() -> bool:
	if game_layer_path.is_empty() or get_node_or_null(game_layer_path) == null:
		_refuse("start", "the game layer '%s' is missing from the scene" % game_layer_path)
		return false
	if screens_path.is_empty() or get_node_or_null(screens_path) == null:
		_refuse("start", "the screens layer '%s' is missing from the scene" % screens_path)
		return false
	return true


func _seed_for_new_run() -> int:
	if run_seed != SEED_RANDOM:
		return run_seed
	return maxi(randi(), 1)


func _start_first_wave() -> bool:
	if _flow == null:
		return false
	var arena = _flow.current_level()
	if arena == null:
		_refuse("start wave 1", "the session reports a level but has none")
		return false
	if not arena.start_wave(0):
		_refuse("start wave 1", "the level refused its first wave")
		return false
	return true


func _game_layer() -> Node:
	return get_node_or_null(game_layer_path)


func _screens() -> Node:
	return get_node_or_null(screens_path)


func _hud_layer() -> Node:
	return get_node_or_null(hud_layer_path)


func _set_screen(next_screen: int, why: String) -> void:
	if _screen == next_screen:
		return
	_screen = next_screen
	print("BOOT_SCREEN " + JSON.stringify({
		"screen": screen_name(),
		"why": why,
		"run": _flow != null,
	}))
	screen_changed.emit(screen_name())


func _connect(target: Node, signal_name: String, handler: Callable) -> void:
	if target.has_signal(signal_name) and not target.is_connected(signal_name, handler):
		target.connect(signal_name, handler)


func _refuse(action: String, why: String) -> void:
	_refusals += 1
	print("BOOT_REFUSED " + JSON.stringify({
		"action": action,
		"reason": why,
		"screen": screen_name(),
	}))
