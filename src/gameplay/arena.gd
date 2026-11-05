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
## Prints on stdout, in this order:
##   ARENA_START {json}       values actually in force
##   ARENA_LEAK {json}        one line per arrival, with HQ health before and after
##   ARENA_STUCK {json}       only when an enemy outlives its arrival (a bug)
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

const LANE_WIDTH_PX := 18.0
const LANE_COLOR := Color(0.81569, 0.54118, 0.29020, 1.0)  # palette amber #d08a4a
const MIN_TIMER_SECONDS := 0.01
const USEC_PER_SECOND := 1000000.0

var _hq: Hq
var _spawn_timer: Timer
var _watchdog_timer: Timer
var _run_timer: Timer
var _lane_line: Line2D

var _active: Array[LaneWalker] = []
var _reported_stuck: Dictionary = {}

var _spawned: int = 0
var _despawned: int = 0
var _leaked: int = 0
var _stuck: int = 0

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
		"engine": Engine.get_version_info()["string"],
		"display": DisplayServer.get_name(),
	}))

	# One enemy immediately: a short run then observes a full walk plus at least
	# one clean despawn, instead of starting idle for one spawn interval.
	_spawn_one()


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


func _spawn_one() -> void:
	var walker := enemy_scene.instantiate() as LaneWalker
	if walker == null:
		push_error("ARENA_ERROR enemy_scene root is not a LaneWalker")
		return
	walker.name = "LaneWalker%d" % (_spawned + 1)
	add_child(walker)
	walker.setup(lane_points)
	walker.arrived.connect(_on_walker_arrived)
	_active.append(walker)
	_spawned += 1


func _on_spawn_timer_timeout() -> void:
	_spawn_one()


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
	}))
