extends Node2D

## G2 arena: the smallest scene `smoke.ps1` and `tests.ps1` can exercise.
##
## One lane, one HQ, one enemy type, no art. Every visual is a flat polygon, so
## this scene cannot block on the art probe. Scope is deliberately thin (T-0025):
## towers do nothing, the run/level lifecycle does not exist, and the only
## mechanic under test is "an enemy walks the lane, reaches the HQ, costs it
## exactly one point, and goes away".
##
## Because `run/main_scene` belongs to eng/tools, the scene is passed explicitly:
##     godot --headless --path . res://scenes/main.tscn -- --seconds=12
##     godot --headless --path . --quit-after 18000 res://scenes/main.tscn
##
## T-0036 adds towers on top of that, without changing any of it: build tiles
## (`BuildSlot`) are discovered by type in `_ready`, placement, upgrade and sell
## go through the arena, and the arena turns a walker's `died` signal into gold
## in the `GoldLedger`.
##
## The phase lock lives here and only here (CHARTER: between waves the player
## plans freely; during a wave towers and perks are locked). A refused place,
## upgrade or sell prints its reason - a locked input that says nothing is
## indistinguishable from a broken one. The same reason is kept in
## `last_refusal()` so a harness can assert on the words instead of on the
## refusal count alone (`run_state.gd` sets the same precedent).
##
## T-0039 adds waves. A level's waves are data (`WavePlan` builds them from
## `docs/design/systems/waves.md` for `level_index` and nothing else), and
## `WaveDirector` paces them. The arena owns the one transition that matters: a
## wave start locks the build phase, a wave clear unlocks it again.
##
## T-0059 puts the start of a wave in the player's hands. `start_next_wave()` is
## the build panel's door to it, and it refuses **before** the director is asked:
## a wave already running, or a plan with nothing left, is a sentence the player
## reads, not a `WAVE_ERROR` line the gate fails on. `wave_status()` is the
## readout - it reports what the director and the phase already say and computes
## no number of its own.
##
## T-0072: waves are the **only** source of enemies. A leftover spawner from the
## first prototype put one walker on the lane from `_ready` and another every few
## seconds on a timer, so every level had enemies walking to the HQ before anyone
## pressed Start Wave. That spawner, its timer, its handler and its
## `spawn_interval_seconds` export are gone: `spawn_walker()` remains only as a
## harness entry point, and `spawn_from_entry()` (the wave director's callback) is
## the one path that produces enemies during play.
##
## T-0045 makes the arena **one level of a run**. The `RunState` and `Inventory`
## it is handed (or creates, and says so) are the only owners of HQ health, gold
## and the towers the player holds; this scene is the view of them for one level:
##
##   * HQ health is seeded from the run when the level opens and every leak is
##     reported through `RunState.damage_hq()`, so 7 of 10 at the end of a level
##     is 7 of 10 at the start of the next one.
##   * Placement draws a tower instance from the inventory and costs nothing;
##     taking a tower back returns the same instance, tier and upgrades intact.
##   * Gold in and out goes through the run (`GoldLedger` is a view of it).
##   * Clearing the last wave emits `level_cleared` and stops there (T-0048). The
##     run session that opened this level calls `complete_level()` exactly once,
##     so a level cannot count itself twice; the arena **never** calls `win_run()`
##     (ADR-0006), because it cannot know which node it is playing. Defeat is
##     `RunState`'s call too - the arena stops spawning and refuses to start
##     another level, and invents no ending of its own.
##
## `bind_run(run, inventory)` hands the arena the run the caller owns; call it
## before the node enters the tree so the level boots already seeded. With
## nothing bound the arena creates a run and inventory of its own and says so on
## `ARENA_RUN`.
##
## Prints on stdout, in this order:
##   ARENA_RUN {json}         once, when the arena had to create (or start) a run
##   ARENA_START {json}       values actually in force, including the wave plan
##   ARENA_WALLET {json}      only when the arena had to create the ledger
##   ARENA_PHASE {json}       on every build <-> wave transition
##   ARENA_WAVE {json}        once per wave cleared, with the phase it returned to
##   ARENA_LEVEL_CLEAR {json} once, when the level's last wave is cleared, with
##                            who the completion was handed to
##   ARENA_RUN_END {json}     once, when the run ends (defeat from the leaks, or
##                            victory when the run session calls `win_run()`)
##   ARENA_LEAK {json}        one line per arrival, with HQ health before and after
##   ARENA_STUCK {json}       only when an enemy outlives its arrival (a bug)
##   ARENA_PLACED {json}      one line per tower placed, with the instance it came from
##   ARENA_TAKEN_BACK {json}  one line per tower returned to the inventory
##   ARENA_UPGRADE_IN_HAND {json} one line per tier bought for a tower in hand (T-0087)
##   ARENA_KILL {json}        one line per walker killed, with the gold it paid
##   ARENA_REFUSED {json}     every refused build or level action, with its reason
##   ARENA_SUMMARY {json}     once, on exit
##
## Self-checks, both of which report through `push_error` so the engine prints an
## ERROR line that `smoke.ps1` already greps for:
##   1. accounting: one arrival costs exactly `damage_per_leak`, no more, no less
##   2. despawn:    a walker alive `stall_grace_seconds` after arriving means the
##                  despawn handler did not run

@export_group("Layout")
## Lane centreline in world pixels. The arena is the single owner of lane
## geometry: the walker walks these points and the lane line is drawn from the
## same array, so the enemy cannot walk somewhere the player cannot see.
@export var lane_points: PackedVector2Array = PackedVector2Array([
	Vector2(80.0, 270.0),
	Vector2(880.0, 270.0),
])
## Where the HQ marker lives. Exported as a path and resolved once in `_ready`,
## so the scene wires the dependency and no script hardcodes a node path.
@export var hq_path: NodePath = ^"HQ"
@export var enemy_scene: PackedScene

@export_group("Wave")
## HP removed from the HQ per enemy that reaches it.
@export var damage_per_leak: int = 1

@export_group("Diagnostics")
## How long a walker may stay alive after arriving before the despawn check
## reports it. One frame proves the handler did not run; a full second keeps a
## slow machine from crying wolf.
@export var stall_grace_seconds: float = 1.0
## How often the despawn check looks.
@export var watchdog_interval_seconds: float = 0.25
## Wall-clock seconds before the scene quits itself, printing its summary. 0 means
## run until the engine quits, which is what `smoke.ps1` does with `--quit-after`.
@export var run_seconds: float = 0.0

@export_group("Towers — PLACEHOLDER (T-0035 towers.md)")
## Scene instantiated for a placed tower. The arena reads the tier tables off the
## node; placement is free (T-0045), so no price is read from the instance and a
## tower's cost is whatever its upgrades were bought for.
@export var tower_scene: PackedScene
## How close to the lane centreline a click may land and still build. A tower on
## the lane would be a wall in the enemy's path. PLACEHOLDER; the real clearance
## is level design work.
@export var lane_clearance_px: float = 40.0
## Where the run's gold is shown. The scene wires a `GoldLedger` here and the
## arena binds it to the run (T-0045) - the node is a view, not a balance. A scene
## with no ledger still boots, with a placeholder the arena creates and says it made.
@export var ledger_path: NodePath = ^"Wallet"
## Whether the arena starts in the wave phase. False for the slice: wave
## scheduling arrives with T-0038, which calls `begin_wave` / `end_wave`.
@export var start_in_wave: bool = false

@export_group("Run — T-0045")
## Whether this level's plan is built from the run's level number
## (`RunState.level_number()`, what the map advanced) rather than from the
## exported `level_index`. True for a level of a run, which is what the scene is
## now; false only to play a specific level's waves outside a run.
@export var level_from_run: bool = true

@export_group("Waves — PLACEHOLDER (T-0039 waves.md)")
## Which level of the run this arena is, 1-based. Difficulty is a function of this
## and of nothing else (`docs/CHARTER.md`), so it is the only knob the wave plan
## reads.
@export var level_index: int = 1
## Whether this level is an elite: its final wave carries exactly one sub-boss.
@export var elite_level: bool = false
## Whether the arena starts its first wave on its own, as `start_wave(0)`. False
## for the tested scene: what starts a wave is the caller's decision, so the
## gates keep running a scene with nobody playing it. `start_level()` does not
## start one (T-0070) - a level that started its own first wave is why every
## level opened in the wave phase whatever the caller asked for.
@export var autostart_waves: bool = false

## The run's two planning modes. During WAVE, placement, upgrade and sell are
## refused; nothing else changes.
enum Phase { BUILD, WAVE }

const PHASE_NAMES: Array[String] = ["build", "wave"]

const LANE_WIDTH_PX := 18.0
const LANE_COLOR := Color(0.81569, 0.54118, 0.29020, 1.0)  # palette amber #d08a4a
const MIN_TIMER_SECONDS := 0.01
const USEC_PER_SECOND := 1000000.0

# Preloaded rather than referenced by class name, for the reason `inventory.gd`
# gives: `--check-only` must not depend on the global class cache having been
# built by a prior `--import`.
const RunStateScript := preload("res://src/systems/run_state.gd")
const InventoryScript := preload("res://src/systems/inventory.gd")

## The level's last wave is clear and control is handed back to whoever owns the
## run (T-0048). The run session calls `RunState.complete_level()` once and, for
## the boss node, `win_run()`; this scene calls neither, so a level can neither
## count itself twice nor end the run. Emitted **after** `ARENA_LEVEL_CLEAR` and
## after every other line this frame, so a listener that frees the level on the
## spot cannot pull the node out from under the code that reported it.
signal level_cleared(level_index: int, elite: bool)

## The phase changed (T-0057). Emitted after `ARENA_PHASE`, so a listener that
## refreshes on this signal can never report a phase the log has not printed yet.
## The build panel is the first listener: "build or wave" has to be visible the
## moment it changes, and polling it every frame is how a panel starts to own
## game state it does not own.
signal phase_changed(phase_name: String)

var _hq: Hq
var _watchdog_timer: Timer
var _run_timer: Timer
var _lane_line: Line2D
var _ledger: GoldLedger

## The run this level is part of, and the towers the player holds. Owned by the
## caller when it binds them; created here when it does not, and the arena says so
## on `ARENA_RUN` (T-0045).
var _run: RunState = null
var _inventory: Inventory = null
var _owns_run: bool = false

var _active: Array[LaneWalker] = []
var _reported_stuck: Dictionary = {}

var _slots: Array[BuildSlot] = []
var _towers: Array[Tower] = []
## The tower scene's `tier_upgrade_cost` table, copied once in `_ready` (T-0087).
## The price of a tier lives on the placed `Tower` node's export, and a tower in
## the inventory has no node, so the arena keeps one copy of the table and prices
## a tier without building anything: entry 0 buys tier 2, entry 1 buys tier 3.
var _tier_upgrade_costs: Array[int] = []
## Towers ever placed this level, so a name is unique even when a taken-back
## tower's node has not been freed yet: `_towers.size() + 1` collided in exactly
## that window and Godot silently renamed the node to `@Node2D@4`, which made the
## `ARENA_PLACED` line name something no other line mentions.
var _towers_built: int = 0
var _phase: Phase = Phase.BUILD

## The level's waves, as data, and the thing that paces them.
var _plan: WavePlan = null
var _director: WaveDirector = null
var _plan_summary: Dictionary = {}
var _waves_cleared: int = 0

var _spawned: int = 0
var _despawned: int = 0
var _leaked: int = 0
var _stuck: int = 0
var _killed: int = 0
var _gold_from_kills: int = 0
var _refusals: int = 0
var _last_refusal: String = ""

## Shadow copy of the balance, kept because the summary is printed during tree
## teardown, when the ledger child may already be gone.
var _gold_shadow: int = 0

## Shadow copies of HQ state. The summary is printed during tree teardown, when
## children are already gone, so it must not read through `hq`.
var _hq_max: int = 0
var _hq_health: int = 0
## HQ health at the moment this level opened - what the run carried in. The leak
## self-check is written against this rather than against `_hq_max`, because a
## level that starts at 7 of 10 must still charge exactly one point per leak.
var _hq_level_start: int = 0

var _started_usec: int = 0
var _summary_emitted: bool = false


func _ready() -> void:
	_parse_args()
	_hq = get_node_or_null(hq_path) as Hq
	if _hq == null or enemy_scene == null:
		push_error(
			"ARENA_ERROR the arena needs an Hq at '%s' and an enemy_scene; got %s and %s"
			% [hq_path, _hq, enemy_scene]
		)
		get_tree().quit(2)
		return

	_started_usec = Time.get_ticks_usec()
	_hq.health_changed.connect(_on_hq_health_changed)

	_ledger = _resolve_ledger()
	_ledger.changed.connect(_on_gold_changed)
	_ensure_run()
	# Seed the level from the run: the HQ node is a view of the run's health, and
	# the shadow copies are what the summary reads during teardown. Seeding from
	# the balance in force, not from zero, is why a run that never spends or earns
	# still reports the gold it started with.
	_seed_level_from_run()
	_gold_shadow = gold()
	_collect_slots()
	_cache_tier_costs()
	_phase = Phase.WAVE if start_in_wave else Phase.BUILD

	_build_lane_visual()
	# The HQ sits wherever the lane ends; the lane is the only source of truth, so
	# a designer editing `lane_points` cannot leave the HQ off the path.
	if lane_points.size() > 0:
		_hq.position = lane_points[lane_points.size() - 1]

	build_level_plan()
	_start_timers()
	print("ARENA_START " + JSON.stringify({
		"lane_points": lane_points.size(),
		"damage_per_leak": damage_per_leak,
		"stall_grace_seconds": stall_grace_seconds,
		"run_seconds": run_seconds,
		"hq": _hq_health,
		"hq_max": _hq_max,
		"phase": phase_name(),
		"build_slots": _slots.size(),
		"lane_clearance_px": lane_clearance_px,
		"tower_scene": tower_scene != null,
		"tier_costs": _tier_upgrade_costs,
		"gold": gold(),
		"level_index": effective_level_index(),
		"elite": elite_level,
		"plan": _plan_summary,
		"autostart_waves": autostart_waves,
		"run": _run.snapshot() if _run != null else {},
		"inventory": _inventory.snapshot() if _inventory != null else {},
		"engine": Engine.get_version_info()["string"],
		"display": DisplayServer.get_name(),
	}))

	# A level opens empty and stays empty until a wave is started (T-0072). The
	# build phase is where the player plans; nothing walks the lane in it. An
	# `autostart_waves` scene names its first wave explicitly, because
	# `start_level()` prepares the level and starts nothing (T-0070).
	if autostart_waves:
		start_wave(0)


func _exit_tree() -> void:
	# Covers the `--quit-after` invocation above, where the engine ends the loop
	# without the arena being asked to.
	_emit_summary()


## Wave pacing only. No policy lives here: what a wave *is* belongs to the plan,
## what it *does* belongs to the director, and the phase belongs to this node.
## Once the run is over there is no level to pace, so the director stops being
## ticked rather than spawning enemies into a decided run.
func _physics_process(delta: float) -> void:
	if _run_is_over():
		return
	if _director != null and _director.is_active():
		_director.tick(delta)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			run_seconds = maxf(0.0, float(a.trim_prefix("--seconds=")))


func _build_lane_visual() -> void:
	_lane_line = Line2D.new()
	_lane_line.name = "Lane"
	_lane_line.width = LANE_WIDTH_PX
	_lane_line.default_color = LANE_COLOR
	_lane_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_lane_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_lane_line.points = lane_points
	add_child(_lane_line)
	# Below the HQ and tower markers, above the board (which is z_index -1 in the
	# scene). Drawing order is why the lane is moved to the front of the child list.
	move_child(_lane_line, 0)


func _start_timers() -> void:
	_watchdog_timer = _make_timer(watchdog_interval_seconds, false, _on_watchdog_timeout)
	if run_seconds > 0.0:
		_run_timer = _make_timer(run_seconds, true, _on_run_timer_timeout)


func _make_timer(seconds: float, one_shot: bool, handler: Callable) -> Timer:
	var timer := Timer.new()
	timer.wait_time = maxf(seconds, MIN_TIMER_SECONDS)
	timer.one_shot = one_shot
	timer.timeout.connect(handler)
	add_child(timer)
	timer.start()
	return timer


## Instantiates the scene's enemy and puts it on the lane. A harness entry point
## only (T-0072): the arena never calls this itself, because waves are the only
## source of enemies during play. `adopt_walker` stays the one place a walker
## joins the field.
func spawn_walker() -> LaneWalker:
	if enemy_scene == null:
		push_error("ARENA_ERROR no enemy_scene is wired; nothing can spawn")
		return null
	var walker := enemy_scene.instantiate() as LaneWalker
	if walker == null:
		push_error("ARENA_ERROR enemy_scene root is not a LaneWalker")
		return null
	adopt_walker(walker)
	return walker


## Puts `walker` on the lane: names it, adds it, hands it the lane geometry and
## connects both of its contracts. The single entry point means an injected
## walker (T-0036 DoD 4: a corpse the arena still holds) is wired exactly like a
## spawned one, so what the tower sees is the real field and not a mock.
func adopt_walker(walker: LaneWalker) -> void:
	walker.name = "LaneWalker%d" % (_spawned + 1)
	add_child(walker)
	walker.setup(lane_points)
	walker.arrived.connect(_on_walker_arrived)
	walker.died.connect(_on_walker_died)
	_active.append(walker)
	_spawned += 1


## Enemies a tower may be given, in spawn order. Deliberately unfiltered by
## health: selecting is `Targeting`'s job and validating is the tower's
## (`tower.gd`, "Firing validates the target, every shot"). A tower that is
## handed a corpse must hold fire, and that only happens if the arena can hand
## one over.
func walkers() -> Array[LaneWalker]:
	var live: Array[LaneWalker] = []
	for walker in _active:
		if is_instance_valid(walker) and not walker.is_queued_for_deletion():
			live.append(walker)
	return live


## Instantiates the scene's enemy with one wave line's stats applied. `stats()`
## is keyed by `LaneWalker`'s export names, so one scene stands for every enemy
## kind until per-kind art exists - and this is the director's only way onto the
## lane (T-0072), so a wave enemy is wired exactly like a harness-spawned one.
func spawn_from_entry(entry: WaveEntry) -> LaneWalker:
	if entry == null:
		push_error("ARENA_ERROR a wave line is null; nothing can spawn")
		return null
	if enemy_scene == null:
		push_error("ARENA_ERROR no enemy_scene is wired; nothing can spawn")
		return null
	var walker := enemy_scene.instantiate() as LaneWalker
	if walker == null:
		push_error("ARENA_ERROR enemy_scene root is not a LaneWalker")
		return null
	# Before `adopt_walker`, because `LaneWalker.setup()` seeds health from
	# `max_health` and the speed is used from the first physics tick.
	var stats := entry.stats()
	for key in stats:
		walker.set(key, stats[key])
	adopt_walker(walker)
	return walker


## A kill pays the run. The walker reports its own reward; the arena owns the
## wallet, so the tower never touches gold. A kill scored after the run ended is
## counted but pays nothing: `RunState` accepts no gold once it is over.
func _on_walker_died(walker: LaneWalker) -> void:
	var reward := maxi(walker.gold_reward, 0)
	_killed += 1
	if _run_is_over():
		print("ARENA_KILL " + JSON.stringify({
			"killed": _killed,
			"walker": walker.name,
			"gold_reward": reward,
			"paid": 0,
			"why": "the run is over",
			"gold": gold(),
			"spawned": _spawned,
		}))
		return
	if reward > 0:
		_gold_from_kills += reward
	_ledger.earn(reward, "kill %s" % walker.name)
	print("ARENA_KILL " + JSON.stringify({
		"killed": _killed,
		"walker": walker.name,
		"gold_reward": reward,
		"paid": reward,
		"gold": gold(),
		"run_gold": _run.gold() if _run != null else 0,
		"spawned": _spawned,
	}))


## One arrival, one leak, reported to the run. `run_state.gd` makes the level's
## `Hq` node a per-level view of the run's health, so the damage is applied there
## and the node is re-seeded from the result - never the other way round, or the
## two counters would be two owners of one number.
func _on_walker_arrived(walker: LaneWalker) -> void:
	_leaked += 1
	if _run_is_over():
		# The level was already decided while this enemy was on the lane. There is
		# nothing to charge, and `RunState` refuses damage on an ended run - a
		# refused call is not a leak, so it is reported as zero damage.
		print("ARENA_LEAK " + JSON.stringify({
			"spawned": _spawned,
			"leaked": _leaked,
			"damage_applied": 0,
			"why": "the run is over",
			"hq_before": _hq_health,
			"hq_after": _hq_health,
			"hq_max": _hq_max,
			"walker": walker.name,
		}))
		return

	var before := _run.hq_health()
	var applied := _run.damage_hq(damage_per_leak, "leak %s" % walker.name)
	var after := _run.hq_health()
	_hq.seed_health(after, _run.hq_max_health())
	print("ARENA_LEAK " + JSON.stringify({
		"spawned": _spawned,
		"leaked": _leaked,
		"damage_applied": applied,
		"hq_before": before,
		"hq_after": after,
		"hq_max": _run.hq_max_health(),
		"walker": walker.name,
	}))

	# Self-check 1: accounting. Every arrival costs exactly `damage_per_leak`
	# until the HQ is empty, so the expected health is a closed-form function of
	# the leak count. Measured from the health this level opened with, which is the
	# run's, so a level that starts at 7 of 10 is still charged one point per leak.
	var expected := maxi(_hq_level_start - _leaked * damage_per_leak, 0)
	if after != expected or (after > 0 and applied != damage_per_leak):
		push_error(
			"ARENA_ERROR HQ accounting broke at leak %d: applied %d, health %d, expected %d"
			% [_leaked, applied, after, expected]
		)


func _on_hq_health_changed(current: int, maximum: int) -> void:
	_hq_health = current
	_hq_max = maximum


## Self-check 2: despawn. Counts an enemy as despawned only when the node is
## actually gone, never on the strength of the `arrived` signal.
func _on_watchdog_timeout() -> void:
	var now_usec := Time.get_ticks_usec()
	_prune_walkers()

	for walker in _active:
		if not walker.has_arrived():
			continue
		var stalled := float(now_usec - walker.arrived_at_usec()) / USEC_PER_SECOND
		if stalled < stall_grace_seconds:
			continue
		var id := walker.get_instance_id()
		if _reported_stuck.has(id):
			continue
		_reported_stuck[id] = true
		_stuck += 1
		print("ARENA_STUCK " + JSON.stringify({
			"spawned": _spawned,
			"despawned": _despawned,
			"live": _live_walker_count(),
			"stalled_seconds": stalled,
			"walker": walker.name,
		}))
		push_error(
			"ARENA_ERROR %s is still alive %.2f s after reaching the lane end: the despawn handler did not run"
			% [walker.name, stalled]
		)


func _prune_walkers() -> void:
	var live: Array[LaneWalker] = []
	for walker in _active:
		if is_instance_valid(walker) and not walker.is_queued_for_deletion():
			live.append(walker)
		else:
			_despawned += 1
	_active = live


func _live_walker_count() -> int:
	var count := 0
	for walker in _active:
		if is_instance_valid(walker) and not walker.is_queued_for_deletion():
			count += 1
	return count


# --- the run and the inventory (T-0045) -------------------------------------

## Hands the arena the run this level is one of, and the towers the player holds.
## Call it before the node enters the tree: `_ready` seeds the level from whatever
## is in force, and a run bound afterwards does not re-seed the level already open.
##
## Both objects are plain `RefCounted`s owned by the caller for the life of the
## run. The arena reads gold and HQ from them and never keeps a second copy.
func bind_run(run: RunState, inventory: Inventory) -> bool:
	if run == null or inventory == null:
		push_error("ARENA_ERROR bind_run needs both a RunState and an Inventory")
		return false
	_run = run
	_inventory = inventory
	return true


func run_state() -> RunState:
	return _run


func inventory() -> Inventory:
	return _inventory


func is_run_over() -> bool:
	return _run_is_over()


## The level in play: the run's `level_number()` - what the map advanced to - or
## the exported `level_index` when the scene is played outside a run, or the
## caller switched `level_from_run` off. One function, so the plan, the log lines
## and the summary cannot disagree about which level this is.
func effective_level_index() -> int:
	if level_from_run and _run != null:
		return _run.level_number()
	return level_index


## Creates (and starts) a run of its own when the caller bound none, starts a
## bound-but-unstarted run, and binds the ledger view and the run's ending either
## way. A level cannot seed itself from a run that has no values yet, which is why
## an unstarted run is started here rather than left to produce a zero HQ.
func _ensure_run() -> void:
	if _run == null:
		_run = RunStateScript.new()
		_inventory = InventoryScript.new()
		_owns_run = true
		# The scene's HQ is the only maximum in hand, so it becomes the run's; the
		# seeding below copies it back, which keeps the two equal by construction.
		_run.start(maxi(_hq.max_health, RunStateScript.MIN_HQ_MAX), RunStateScript.STARTING_GOLD)
		print("ARENA_RUN " + JSON.stringify({
			"source": "created",
			"why": "no run was bound; the arena made one",
			"run": _run.snapshot(),
		}))
	elif _run.status() == RunState.Status.NOT_STARTED:
		_run.start(maxi(_hq.max_health, RunStateScript.MIN_HQ_MAX), RunStateScript.STARTING_GOLD)
		print("ARENA_RUN " + JSON.stringify({
			"source": "started",
			"why": "the bound run had not started; the arena started it from the scene's HQ",
			"run": _run.snapshot(),
		}))
	if _inventory == null:
		_inventory = InventoryScript.new()
		print("ARENA_RUN " + JSON.stringify({
			"source": "inventory_created",
			"why": "no inventory was bound; the arena made an empty one",
		}))
	_ledger.bind_run(_run)
	if not _run.run_ended.is_connected(_on_run_ended):
		_run.run_ended.connect(_on_run_ended)


## Seeds the level's HQ view - and the shadow copies the summary reads during
## teardown - from the run. Called once per level, from `_ready`.
func _seed_level_from_run() -> void:
	_hq_max = _run.hq_max_health()
	_hq_health = _run.hq_health()
	_hq_level_start = _hq_health
	_hq.seed_health(_hq_health, _hq_max)


func _run_is_over() -> bool:
	return _run != null and _run.is_over()


## The instance `place_tower` should draw: `tower_id` when it names one that is not
## on the map, otherwise the oldest instance that is not on the map, or null.
func _unplaced_tower(tower_id: int) -> RefCounted:
	if _inventory == null:
		return null
	for tower in _inventory.towers():
		if tower_id != 0 and tower.id != tower_id:
			continue
		if not tower.placed:
			return tower
	return null


# --- phase -----------------------------------------------------------------

func phase() -> Phase:
	return _phase


func phase_name() -> String:
	if _phase < 0 or _phase >= PHASE_NAMES.size():
		return "unknown(%d)" % _phase
	return PHASE_NAMES[_phase]


func is_wave_active() -> bool:
	return _phase == Phase.WAVE


## Enters the wave phase. Idempotent: a second call in the same wave is not an
## error and prints nothing, so a scheduler cannot spam the log.
func begin_wave() -> void:
	_set_phase(Phase.WAVE)


func end_wave() -> void:
	_set_phase(Phase.BUILD)


func _set_phase(next_phase: Phase) -> void:
	if _phase == next_phase:
		return
	_phase = next_phase
	print("ARENA_PHASE " + JSON.stringify({
		"phase": phase_name(),
		"walkers": _live_walker_count(),
		"gold": _ledger.gold() if _ledger != null else _gold_shadow,
	}))
	phase_changed.emit(phase_name())


# --- waves -----------------------------------------------------------------

## Builds this level's waves from the level in play and `elite_level`, and hands
## them to a fresh director. The level in play is `RunState.level_number()` when a
## run is bound (`level_from_run`), because that is the level the map advanced to
## (ADR-0006); `level_index` is the fallback for a scene played outside a run.
## Public because both a demo and the map change the level and then ask for a new
## plan; the arena never rebuilds a plan behind the caller's back.
func build_level_plan() -> void:
	_plan = WavePlan.new()
	var waves := _plan.build(effective_level_index(), elite_level)
	_plan_summary = _plan.describe_level(waves)
	_director = WaveDirector.new()
	_director.setup(spawn_from_entry)
	_director.set_plan(waves)
	_director.wave_completed.connect(_on_wave_completed)
	_director.level_completed.connect(_on_level_completed)
	_waves_cleared = 0


## The arena's entry point for "this level has begun". It prepares the level and
## leaves it in the **build phase**: the plan is already built (`_ready` calls
## `build_level_plan()`), the towers are placeable, and the level waits for
## whoever owns it to start wave 1.
##
## It does **not** start a wave (T-0070). Starting one is `start_wave(0)`, and it
## is the caller's decision: this method used to end in `start_wave(0)`, so every
## level opened in the wave phase no matter what the caller asked for - which is
## why a flag on the boot could not make a player's level wait.
##
## Refused when the run is over: a defeated (or already won) run has no level to
## play, and the arena must not invent a way to keep going (T-0045 DoD 3).
func start_level() -> bool:
	if _run_is_over():
		_refuse(
			"start the level",
			"the run is %s (%s); no level can start"
			% [_run.status_name(), _run.end_reason()]
		)
		return false
	return true


## Starts one wave of the plan (0-based) and locks the build phase for its
## duration. False when the director refused it - the reason is already printed,
## and the phase is untouched, so a refused wave cannot leave the player unable
## to build. A wave cannot start on an ended run either, for the reason above.
func start_wave(index: int) -> bool:
	if _run_is_over():
		_refuse("start a wave", "the run is %s; no wave can start" % _run.status_name())
		return false
	if _director == null:
		_refuse("wave", "the level has no wave plan")
		return false
	if not _director.start_wave(index):
		return false
	begin_wave()
	return true


## The player's door onto the next wave (T-0059). Everything it can refuse is
## refused **here**, before the director is asked, because a refused wave is a
## normal thing a player does and the director answers a bad index with
## `push_error` - an ERROR line that `smoke.ps1` would fail on. The three
## sentences a player can read:
##
##   * the run is over - there is no level left to play;
##   * a wave is still running - finish it first, and nothing changes;
##   * the plan has no wave after the last one cleared - the level is done.
##
## `start_wave()` still exists and still decides; this only picks the index and
## refuses the two states the director would have reported as an error.
func start_next_wave() -> bool:
	if _director == null:
		_refuse("start a wave", "the level has no wave plan")
		return false
	if _run_is_over():
		_refuse("start a wave", "the run is %s; no wave can start" % _run.status_name())
		return false
	if _director.is_active():
		_refuse(
			"start a wave",
			"wave %d is still running; the next one can start when it is cleared"
			% (_director.current_index() + 1)
		)
		return false
	var next_index: int = _director.current_index() + 1
	if next_index >= level_wave_count():
		_refuse(
			"start a wave",
			"the level has no waves left: %d of %d cleared" % [_waves_cleared, level_wave_count()]
		)
		return false
	return start_wave(next_index)


## The wave readout (T-0059), for the build panel to print. Every value is read
## from the director and the phase; `remaining` is what the wave still owes the
## lane - units it has not spawned yet **and** units it has spawned that are
## still in play - so "3 enemies left" goes to zero on the tick the last one
## dies, which is the same moment the wave is declared clear.
##
##     {waves, wave, cleared, phase, running, remaining, left}
##
## `wave` is the wave in play, or the one the player is about to start, so a
## level that has not begun reads "wave 1 of 6" rather than "wave 0". `left` is
## how many waves the level still has to run, and `remaining` is 0 while building.
func wave_status() -> Dictionary:
	var waves := level_wave_count()
	var running := _director != null and _director.is_active()
	var number := 0
	var remaining := 0
	if running:
		number = _director.current_index() + 1
		remaining = _director.units_left() + _director.walkers().size()
	else:
		number = mini(_waves_cleared + 1, waves)
	return {
		"waves": waves,
		"wave": number,
		"cleared": _waves_cleared,
		"phase": phase_name(),
		"running": running,
		"remaining": remaining,
		"left": maxi(waves - _waves_cleared, 0),
	}


func wave_plan() -> WavePlan:
	return _plan


func wave_director() -> WaveDirector:
	return _director


func level_wave_count() -> int:
	return _director.wave_count() if _director != null else 0


func waves_cleared() -> int:
	return _waves_cleared


func plan_summary() -> Dictionary:
	return _plan_summary.duplicate()


func _on_wave_completed(wave: WaveDefinition) -> void:
	# The wave is over when its queue is empty and its walkers are gone, so the
	# build phase returns here and nowhere else. That is the whole point of the
	# phase lock: between waves the player plans freely.
	end_wave()
	_waves_cleared += 1
	print("ARENA_WAVE " + JSON.stringify({
		"wave": wave.number,
		"cleared": _waves_cleared,
		"waves": level_wave_count(),
		"units": wave.unit_count(),
		"health": wave.total_health(),
		"phase": phase_name(),
		"hq": _hq_health,
	}))


## The level's last wave is clear. This is the one place a level reports itself
## finished, and it reports **to the run session** (T-0048): `complete_level()` is
## called by whoever opened the level, exactly once, because two callers cannot
## both be the one that counts a level and this scene cannot know whether it is
## playing a standard, an elite or the boss node. The arena deliberately does
## **not** call `win_run()` either (ADR-0006).
##
## A level played straight from the scene with no session listening keeps its
## numbers and moves nobody's level index: `handed_to` below says so, which is the
## visible sign the scene is being played outside a run.
func _on_level_completed() -> void:
	var why := ""
	if _run == null:
		why = "no run is bound, so there is nothing to complete"
	elif _run.is_over():
		why = "the run is %s" % _run.status_name()

	print("ARENA_LEVEL_CLEAR " + JSON.stringify({
		"level_index": effective_level_index(),
		"elite": elite_level,
		"waves": level_wave_count(),
		"phase": phase_name(),
		"hq": _hq_health,
		"gold": gold(),
		"levels_completed": _run.level_index() if _run != null else 0,
		"run_status": _run.status_name() if _run != null else "no_run",
		"handed_to": "run_session" if why == "" else "nobody",
		"why": why,
	}))

	# Last, so a listener may queue the level for deletion without racing the
	# lines above. `level_cleared` is the arena's whole completion contract: what
	# the level index becomes is the session's decision, not this scene's.
	level_cleared.emit(effective_level_index(), elite_level)


## The run ended, wherever the decision was made: `RunState.damage_hq()` reaching
## zero (defeat) today, `win_run()` from the run session when the boss node is
## completed. The arena reacts and invents nothing: it stops spawning - the
## director is no longer ticked (`_physics_process`) and `start_wave` refuses - so
## no further enemy is charged to a decided run, and refuses to start another level
## (`start_level`).
func _on_run_ended(victory: bool, reason: String) -> void:
	print("ARENA_RUN_END " + JSON.stringify({
		"victory": victory,
		"reason": reason,
		"status": _run.status_name() if _run != null else "no_run",
		"level_index": effective_level_index(),
		"levels_completed": _run.level_index() if _run != null else 0,
		"hq": _run.hq_health() if _run != null else _hq_health,
		"gold": gold(),
	}))


# --- towers ----------------------------------------------------------------

## Places the inventory tower `tower_id` (0 = the oldest one not on the map) on
## the free build tile nearest `world_position`, and returns the node or null when
## the build was refused. Every refusal prints `ARENA_REFUSED` with its reason: the
## lock is only observable if the reason reaches the log (T-0036 DoD 3).
##
## Placement is free (T-0045): the tower comes out of the inventory, no gold moves,
## and the node mirrors the instance's tier and upgrades - which is what makes
## "take it back and put it down again" keep both.
func place_tower(world_position: Vector2, tower_id: int = 0) -> Tower:
	if _phase != Phase.BUILD:
		_refuse("place", "towers are locked during a wave")
		return null
	if tower_scene == null:
		_refuse("place", "no tower_scene is wired into the arena")
		return null
	if _inventory == null:
		_refuse("place", "the arena has no inventory to draw a tower from")
		return null
	if _slots.is_empty():
		_refuse("place", "the scene has no build tiles")
		return null
	if _lane_distance(world_position) < lane_clearance_px:
		_refuse("place", "that point is on the lane")
		return null
	var slot := _nearest_slot(world_position, true)
	if slot == null:
		# Distinguish "you clicked bare ground" from "that tile is taken": the two
		# need different words, or a player cannot tell a miss from a refusal.
		var taken := _nearest_slot(world_position, false)
		if taken != null:
			_refuse("place", "%s is already occupied by %s" % [taken.name, taken.tower.name])
		else:
			_refuse("place", "no free build tile within clicking distance of that point")
		return null
	if _lane_distance(slot.world_position()) < lane_clearance_px:
		_refuse("place", "%s sits on the lane" % slot.name)
		return null

	var instance: RefCounted = _unplaced_tower(tower_id)
	if instance == null:
		if tower_id != 0 and _inventory.find_tower(tower_id) != null:
			_refuse("place", "tower %d is already on the map" % tower_id)
		else:
			_refuse("place", "the inventory holds no tower to place")
		return null

	_towers_built += 1
	var tower := tower_scene.instantiate() as Tower
	if tower == null:
		push_error("ARENA_ERROR tower_scene root is not a Tower")
		return null
	tower.name = "Tower%d" % _towers_built
	# Before `add_child`, so `_ready` sees the instance's tier immediately instead
	# of showing tier 1 for a frame.
	tower.bind_instance(instance)
	tower.candidate_source = walkers
	if not _inventory.place_tower(instance.id, str(slot.name)):
		# Not in the tree yet, so there is nothing to defer. Freeing it now keeps
		# a refused build from leaving an orphan node behind.
		tower.free()
		_refuse("place", _inventory.last_refusal())
		return null
	add_child(tower)
	# global_position, not position: the arena may itself be transformed, and the
	# tower must stand on the tile the player clicked.
	tower.global_position = slot.world_position()
	slot.attach(tower)
	_towers.append(tower)
	print("ARENA_PLACED " + JSON.stringify({
		"tower": tower.name,
		"slot": slot.name,
		"at": [tower.global_position.x, tower.global_position.y],
		"cost": 0,
		"instance": instance.id,
		"tier": instance.tier,
		"upgrades": instance.upgrade_type_ids(),
		"gold": gold(),
		"phase": phase_name(),
	}))
	return tower


## Buys the next tier for `tower` out of the run's gold and grants it through the
## inventory, so the instance - not the node - carries it. Refused during a wave,
## at max tier, without the gold, or for a node that is not bound to an instance;
## the reason is printed in each case.
func upgrade_tower(tower: Tower) -> bool:
	if _phase != Phase.BUILD:
		_refuse("upgrade", "towers are locked during a wave")
		return false
	if tower == null or not is_instance_valid(tower):
		_refuse("upgrade", "no tower to upgrade")
		return false
	if tower.instance == null:
		_refuse("upgrade", "%s is not bound to an inventory tower" % tower.name)
		return false
	if tower.is_max_tier():
		_refuse("upgrade", "%s is already at tier %d" % [tower.name, tower.tier()])
		return false
	var cost := maxi(tower.upgrade_cost(), 0)
	if not _ledger.try_spend(cost, "upgrade %s" % tower.name):
		_refuse("upgrade", "not enough gold for a %d gold upgrade" % cost)
		return false
	var new_tier: int = _inventory.raise_tower_tier(tower.instance.id)
	if new_tier == 0 or not tower.adopt_tier(new_tier, cost):
		# Paid for and then refused: hand the gold back rather than eat it.
		_ledger.earn(cost, "refund: %s refused the upgrade" % tower.name)
		_refuse("upgrade", "%s refused the upgrade it was paid for" % tower.name)
		return false
	return true


## Gold to reach `tier + 1`, read from the table cached off the tower scene in
## `_ready` (T-0087). -1 at the last tier, above it, and when no table was cached:
## -1 rather than 0 so "cannot buy" cannot be mistaken for "free" (the same
## convention `Tower.upgrade_cost()` uses). `tier` is 1-based, the table's index
## is `tier - 1`.
func upgrade_cost_for_tier(tier: int) -> int:
	if tier < 1 or tier >= Tower.MAX_TIER:
		return -1
	var index := tier - 1
	if index >= _tier_upgrade_costs.size():
		return -1
	# A negative entry means "no price for this tier" in the table itself, so it
	# is reported the same way as a missing entry.
	return maxi(int(_tier_upgrade_costs[index]), -1)


## Buys the next tier for the inventory tower `instance_id`, which is **not** on
## the map (T-0087): possession is enough to own an upgrade, and the price comes
## from the same table a placed tower uses. The instance is what carries the tier,
## so the grant goes through `Inventory.raise_tower_tier()` exactly as it does for
## a placed tower; the node mirrors it when the tower is placed later.
##
## Refused, with its reason printed, during a wave, for an unknown instance, for
## an instance that **is** on the map (that one is upgraded through its node), at
## the last tier, when the table has no price, and without the gold. Paid for and
## then refused is refunded rather than eaten.
func upgrade_inventory_tower(instance_id: int) -> bool:
	if _phase != Phase.BUILD:
		_refuse("upgrade", "towers are locked during a wave")
		return false
	if _inventory == null:
		_refuse("upgrade", "the arena has no inventory to read the tower from")
		return false
	var instance: RefCounted = _inventory.find_tower(instance_id)
	if instance == null:
		_refuse("upgrade", "no tower %d is in the inventory" % instance_id)
		return false
	if bool(instance.placed):
		_refuse(
			"upgrade",
			"tower %d is on the map; a placed tower is upgraded through its node" % instance_id
		)
		return false
	var tier_before := int(instance.tier)
	if tier_before >= Tower.MAX_TIER:
		_refuse("upgrade", "tower %d is already at tier %d" % [instance_id, tier_before])
		return false
	var cost := upgrade_cost_for_tier(tier_before)
	if cost < 0:
		_refuse(
			"upgrade",
			"no price for tower %d's tier %d; the level has no tower price table" % [instance_id, tier_before + 1]
		)
		return false
	var gold_before := gold()
	if not _ledger.try_spend(cost, "upgrade tower %d in hand" % instance_id):
		_refuse("upgrade", "not enough gold for a %d gold upgrade" % cost)
		return false
	var new_tier: int = _inventory.raise_tower_tier(instance_id)
	if new_tier <= tier_before:
		# Paid for and then refused: hand the gold back rather than eat it.
		_ledger.earn(cost, "refund: tower %d refused the upgrade" % instance_id)
		_refuse("upgrade", "tower %d refused the upgrade it was paid for" % instance_id)
		return false
	print("ARENA_UPGRADE_IN_HAND " + JSON.stringify({
		"instance": instance_id,
		"type_id": String(instance.type_id),
		"tier_before": tier_before,
		"tier": int(instance.tier),
		"cost": cost,
		"gold_before": gold_before,
		"gold": gold(),
		"placed": false,
		"phase": phase_name(),
	}))
	return true


## Picks `tower` back into the inventory and frees its tile. No gold moves in
## either direction (T-0045): the instance keeps its tier and its upgrades, which
## is the whole point of taking a tower back rather than selling one. Refused
## during a wave, like every other build action.
func take_tower_back(tower: Tower) -> bool:
	if _phase != Phase.BUILD:
		_refuse("take back", "towers are locked during a wave")
		return false
	if tower == null or not is_instance_valid(tower):
		_refuse("take back", "no tower to take back")
		return false
	if tower.instance == null:
		_refuse("take back", "%s is not bound to an inventory tower" % tower.name)
		return false
	if not _inventory.take_tower_back(tower.instance.id):
		_refuse("take back", _inventory.last_refusal())
		return false
	var slot := slot_for(tower)
	if slot != null:
		slot.detach()
	_towers.erase(tower)
	print("ARENA_TAKEN_BACK " + JSON.stringify({
		"tower": tower.name,
		"slot": slot.name if slot != null else "<none>",
		"instance": tower.instance.id,
		"tier": tower.instance.tier,
		"upgrades": tower.instance.upgrade_type_ids(),
		"invested": tower.invested(),
		"gold": gold(),
		"phase": phase_name(),
	}))
	tower.queue_free()
	return true


func slot_for(tower: Tower) -> BuildSlot:
	for slot in _slots:
		if slot.tower == tower:
			return slot
	return null


func towers() -> Array[Tower]:
	return _towers.duplicate()


## The build tiles as the panel needs them (T-0057): one dictionary per tile, in
## scene order, so the panel can draw the board and resolve a click to a tile
## without knowing how tiles are discovered or where they are.
##
##     {name: String, position: Vector2, free: bool, snap_radius_px: float,
##      tower: Tower or null, instance_id: int}
##
## `tower` is a live node reference on purpose: the panel hands it straight back to
## `upgrade_tower()` / `take_tower_back()`, which is what keeps every rule in this
## file. A caller that prints a row must drop the reference first - a node is not
## JSON.
func build_slots() -> Array:
	var out: Array = []
	for slot in _slots:
		var standing: Tower = null if slot.is_free() else slot.tower
		out.append({
			"name": String(slot.name),
			"position": slot.world_position(),
			"free": slot.is_free(),
			"snap_radius_px": slot.snap_radius_px,
			"tower": standing,
			"instance_id": (int(standing.instance.id) if standing != null and standing.instance != null else 0),
		})
	return out


## The tower node standing for the inventory instance `instance_id`, or null. The
## panel selects by instance id (what the inventory and the run speak in) and needs
## the node to act on the arena with.
func tower_for_instance(instance_id: int) -> Tower:
	for tower in _towers:
		if tower.instance != null and int(tower.instance.id) == instance_id:
			return tower
	return null


func free_slot_count() -> int:
	var count := 0
	for slot in _slots:
		if slot.is_free():
			count += 1
	return count


func killed_count() -> int:
	return _killed


func refused_count() -> int:
	return _refusals


## The reason the last refused build action gave, verbatim, or "" when nothing has
## been refused yet. Printed as `ARENA_REFUSED` at the time; kept readable so a
## harness asserts on the words ("locked during a wave") and not just on a counter.
func last_refusal() -> String:
	return _last_refusal


func gold() -> int:
	return _ledger.gold() if _ledger != null else _gold_shadow


## The one refusal shape: action, reason, and the state that refused it. Printed,
## never `push_error` - a locked input is expected behaviour, and an ERROR line
## would make `smoke.ps1` red for a working game.
func _refuse(action: String, why: String) -> void:
	_refusals += 1
	_last_refusal = why
	print("ARENA_REFUSED " + JSON.stringify({
		"action": action,
		"reason": why,
		"phase": phase_name(),
		"gold": _ledger.gold() if _ledger != null else _gold_shadow,
		"towers": _towers.size(),
		"free_slots": free_slot_count(),
	}))


func _nearest_slot(world_position: Vector2, free_only: bool) -> BuildSlot:
	var best: BuildSlot = null
	var best_distance := INF
	for slot in _slots:
		if free_only and not slot.is_free():
			continue
		var distance := slot.distance_to_point(world_position)
		if distance > slot.snap_radius_px or distance >= best_distance:
			continue
		best = slot
		best_distance = distance
	return best


func _collect_slots() -> void:
	_slots.clear()
	for child in get_children():
		if child is BuildSlot:
			_slots.append(child)


## Copies the tower scene's tier price table once, in `_ready` (T-0087). One probe
## node is instantiated, read and freed: the price is an export on the `Tower`
## node, an in-hand instance has no node, and instantiating a tower every time a
## player asks what the next tier costs would be a node per question. A scene with
## no `tower_scene` caches nothing and prices every tier as -1, which the window
## reports as "open a level to price it".
func _cache_tier_costs() -> void:
	_tier_upgrade_costs.clear()
	if tower_scene == null:
		return
	var probe := tower_scene.instantiate()
	if probe == null:
		return
	var table = probe.get("tier_upgrade_cost")
	if table is Array:
		for value in table:
			_tier_upgrade_costs.append(int(value))
	# Never entered the tree (no `_ready` ran), so freeing it now leaves nothing.
	probe.free()


func _resolve_ledger() -> GoldLedger:
	var wired := get_node_or_null(ledger_path) as GoldLedger
	if wired != null:
		return wired
	var created := GoldLedger.new()
	created.name = "Wallet"
	add_child(created)
	print("ARENA_WALLET " + JSON.stringify({
		"source": "created",
		"why": "no GoldLedger at '%s'; the arena made a placeholder" % ledger_path,
	}))
	return created


func _on_gold_changed(current: int) -> void:
	_gold_shadow = current


## Distance from `point` to the lane centreline, in pixels. The lane is the only
## source of geometry, so "on the lane" is measured against the same points the
## walkers use.
func _lane_distance(point: Vector2) -> float:
	if lane_points.is_empty():
		return INF
	if lane_points.size() == 1:
		return point.distance_to(lane_points[0])
	var best := INF
	for i in lane_points.size() - 1:
		var closest := _closest_on_segment(point, lane_points[i], lane_points[i + 1])
		best = minf(best, point.distance_to(closest))
	return best


func _closest_on_segment(point: Vector2, from: Vector2, to: Vector2) -> Vector2:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.0:
		return from
	var t := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return from + segment * t


func _on_run_timer_timeout() -> void:
	_emit_summary()
	get_tree().quit(0)


func _emit_summary() -> void:
	if _summary_emitted:
		return
	_summary_emitted = true
	print("ARENA_SUMMARY " + JSON.stringify({
		"seconds": float(Time.get_ticks_usec() - _started_usec) / USEC_PER_SECOND,
		"spawned": _spawned,
		"despawned": _despawned,
		"live": _live_walker_count(),
		"leaked": _leaked,
		"stuck": _stuck,
		"hq_before": _hq_level_start,
		"hq_after": _hq_health,
		"hq_max": _hq_max,
		"phase": phase_name(),
		"killed": _killed,
		"gold_from_kills": _gold_from_kills,
		"gold": _gold_shadow,
		"towers": _towers.size(),
		"refusals": _refusals,
		"level_index": effective_level_index(),
		"elite": elite_level,
		"waves": level_wave_count(),
		"waves_cleared": _waves_cleared,
		"wave": (_director.current_index() + 1) if _director != null else 0,
		"run_status": _run.status_name() if _run != null else "no_run",
		"levels_completed": _run.level_index() if _run != null else 0,
		"end_reason": _run.end_reason() if _run != null else "",
		"inventory_towers": _inventory.tower_count() if _inventory != null else 0,
	}))
