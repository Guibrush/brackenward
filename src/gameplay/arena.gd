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
## Prints on stdout, in this order:
##   ARENA_START {json}       values actually in force
##   ARENA_WALLET {json}      only when the arena had to create the ledger
##   ARENA_PHASE {json}       on every build <-> wave transition
##   ARENA_LEAK {json}        one line per arrival, with HQ health before and after
##   ARENA_STUCK {json}       only when an enemy outlives its arrival (a bug)
##   ARENA_PLACED {json}      one line per tower built
##   ARENA_SOLD {json}        one line per tower sold
##   ARENA_KILL {json}        one line per walker killed, with the gold it paid
##   ARENA_REFUSED {json}     every refused build action, with its reason
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
## Seconds between spawns. Placeholder pacing for T-0025; real wave pacing is
## design/systems work.
@export var spawn_interval_seconds: float = 3.0
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
## Scene instantiated for a placed tower. The arena reads `place_cost` and the
## tier table off the instance, so a tower's price has exactly one home.
@export var tower_scene: PackedScene
## How close to the lane centreline a click may land and still build. A tower on
## the lane would be a wall in the enemy's path. PLACEHOLDER; the real clearance
## is level design work.
@export var lane_clearance_px: float = 40.0
## Where the run's gold lives. The scene wires a `GoldLedger` here; a scene with
## no ledger still boots, with a placeholder the arena creates and says it made.
@export var ledger_path: NodePath = ^"Wallet"
## Whether the arena starts in the wave phase. False for the slice: wave
## scheduling arrives with T-0038, which calls `begin_wave` / `end_wave`.
@export var start_in_wave: bool = false

## The run's two planning modes. During WAVE, placement, upgrade and sell are
## refused; nothing else changes.
enum Phase { BUILD, WAVE }

const PHASE_NAMES: Array[String] = ["build", "wave"]

const LANE_WIDTH_PX := 18.0
const LANE_COLOR := Color(0.81569, 0.54118, 0.29020, 1.0)  # palette amber #d08a4a
const MIN_TIMER_SECONDS := 0.01
const USEC_PER_SECOND := 1000000.0

var _hq: Hq
var _spawn_timer: Timer
var _watchdog_timer: Timer
var _run_timer: Timer
var _lane_line: Line2D
var _ledger: GoldLedger

var _active: Array[LaneWalker] = []
var _reported_stuck: Dictionary = {}

var _slots: Array[BuildSlot] = []
var _towers: Array[Tower] = []
var _phase: Phase = Phase.BUILD

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
	_hq_max = _hq.max_health
	_hq_health = _hq.health()
	_hq.health_changed.connect(_on_hq_health_changed)

	_ledger = _resolve_ledger()
	_ledger.changed.connect(_on_gold_changed)
	# Seed the shadow copy from the balance in force, not from zero: a run that
	# never spends or earns must still report the gold it started with when the
	# summary is printed during teardown.
	_gold_shadow = _ledger.gold()
	_collect_slots()
	_phase = Phase.WAVE if start_in_wave else Phase.BUILD

	_build_lane_visual()
	# The HQ sits wherever the lane ends; the lane is the only source of truth, so
	# a designer editing `lane_points` cannot leave the HQ off the path.
	if lane_points.size() > 0:
		_hq.position = lane_points[lane_points.size() - 1]

	_start_timers()
	print("ARENA_START " + JSON.stringify({
		"lane_points": lane_points.size(),
		"spawn_interval_seconds": spawn_interval_seconds,
		"damage_per_leak": damage_per_leak,
		"stall_grace_seconds": stall_grace_seconds,
		"run_seconds": run_seconds,
		"hq_max": _hq_max,
		"phase": phase_name(),
		"build_slots": _slots.size(),
		"lane_clearance_px": lane_clearance_px,
		"tower_scene": tower_scene != null,
		"gold": _ledger.gold(),
		"engine": Engine.get_version_info()["string"],
		"display": DisplayServer.get_name(),
	}))

	# One enemy immediately: a short run then observes a full walk plus at least
	# one clean despawn, instead of starting idle for one spawn interval.
	spawn_walker()


func _exit_tree() -> void:
	# Covers the `--quit-after` invocation above, where the engine ends the loop
	# without the arena being asked to.
	_emit_summary()


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
	_spawn_timer = _make_timer(spawn_interval_seconds, false, _on_spawn_timer_timeout)
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


## Instantiates the scene's enemy and puts it on the lane. Public so a harness
## can drive spawns explicitly, and so `adopt_walker` is the one place a walker
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


func _on_spawn_timer_timeout() -> void:
	spawn_walker()


## A kill pays the run. The walker reports its own reward; the arena owns the
## wallet, so the tower never touches gold.
func _on_walker_died(walker: LaneWalker) -> void:
	var reward := maxi(walker.gold_reward, 0)
	_killed += 1
	_gold_from_kills += reward
	_ledger.earn(reward, "kill %s" % walker.name)
	print("ARENA_KILL " + JSON.stringify({
		"killed": _killed,
		"walker": walker.name,
		"gold_reward": reward,
		"gold": _ledger.gold(),
		"spawned": _spawned,
	}))


func _on_walker_arrived(walker: LaneWalker) -> void:
	_leaked += 1
	var before := _hq_health
	var applied := _hq.take_damage(damage_per_leak)
	var after := _hq_health
	print("ARENA_LEAK " + JSON.stringify({
		"spawned": _spawned,
		"leaked": _leaked,
		"damage_applied": applied,
		"hq_before": before,
		"hq_after": after,
		"hq_max": _hq_max,
		"walker": walker.name,
	}))

	# Self-check 1: accounting. Every arrival costs exactly `damage_per_leak`
	# until the HQ is empty, so the expected health is a closed-form function of
	# the leak count.
	var expected := maxi(_hq_max - _leaked * damage_per_leak, 0)
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


# --- towers ----------------------------------------------------------------

## Builds a tower on the free build tile nearest `world_position` and returns it,
## or null when the build was refused. Every refusal prints `ARENA_REFUSED` with
## its reason: the lock is only observable if the reason reaches the log
## (T-0036 DoD 3).
func place_tower(world_position: Vector2) -> Tower:
	if _phase != Phase.BUILD:
		_refuse("place", "towers are locked during a wave")
		return null
	if tower_scene == null:
		_refuse("place", "no tower_scene is wired into the arena")
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

	var tower := tower_scene.instantiate() as Tower
	if tower == null:
		push_error("ARENA_ERROR tower_scene root is not a Tower")
		return null
	var cost := maxi(tower.place_cost, 0)
	if not _ledger.try_spend(cost, "build %s" % slot.name):
		# Not in the tree yet, so there is nothing to defer. Freeing it now keeps
		# a refused build from leaving an orphan node behind.
		tower.free()
		_refuse("place", "not enough gold for a %d gold tower" % cost)
		return null

	tower.name = "Tower%d" % (_towers.size() + 1)
	tower.candidate_source = walkers
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
		"cost": cost,
		"gold": _ledger.gold(),
		"phase": phase_name(),
	}))
	return tower


## Buys the next tier for `tower`. Refused during a wave, at max tier, or without
## the gold; the reason is printed in each case.
func upgrade_tower(tower: Tower) -> bool:
	if _phase != Phase.BUILD:
		_refuse("upgrade", "towers are locked during a wave")
		return false
	if tower == null or not is_instance_valid(tower):
		_refuse("upgrade", "no tower to upgrade")
		return false
	if tower.is_max_tier():
		_refuse("upgrade", "%s is already at tier %d" % [tower.name, tower.tier()])
		return false
	var cost := maxi(tower.upgrade_cost(), 0)
	if not _ledger.try_spend(cost, "upgrade %s" % tower.name):
		_refuse("upgrade", "not enough gold for a %d gold upgrade" % cost)
		return false
	if not tower.apply_upgrade():
		# Paid for and then refused: hand the gold back rather than eat it.
		_ledger.earn(cost, "refund: %s refused the upgrade" % tower.name)
		_refuse("upgrade", "%s refused the upgrade it was paid for" % tower.name)
		return false
	return true


## Sells `tower` for `Tower.refund_value()`, frees its tile and removes it.
## Refused during a wave, like every other build action.
func sell_tower(tower: Tower) -> bool:
	if _phase != Phase.BUILD:
		_refuse("sell", "towers are locked during a wave")
		return false
	if tower == null or not is_instance_valid(tower):
		_refuse("sell", "no tower to sell")
		return false
	var slot := slot_for(tower)
	var refund := maxi(tower.refund_value(), 0)
	_ledger.earn(refund, "sell %s" % tower.name)
	if slot != null:
		slot.detach()
	_towers.erase(tower)
	print("ARENA_SOLD " + JSON.stringify({
		"tower": tower.name,
		"slot": slot.name if slot != null else "<none>",
		"refund": refund,
		"invested": tower.invested(),
		"gold": _ledger.gold(),
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
		"hq_before": _hq_max,
		"hq_after": _hq_health,
		"hq_max": _hq_max,
		"phase": phase_name(),
		"killed": _killed,
		"gold_from_kills": _gold_from_kills,
		"gold": _gold_shadow,
		"towers": _towers.size(),
		"refusals": _refusals,
	}))
