class_name WaveDirector
extends RefCounted

## Runs one level's `WaveDefinition`s: paces the spawns, and declares a wave
## complete when its queue is empty *and* every enemy it spawned is gone
## (T-0039).
##
## It is a `RefCounted`, not a `Node`, on purpose. Pacing is game time, not
## engine time: whoever owns the level calls `tick(delta)` — the arena from
## `_physics_process`, a demo in big steps — so one level of waves can be driven
## in a millisecond by a harness and still be the same code the game runs. No
## `_process` here, and no `Timer` to leak.
##
## Two rules it can fail, and both fail *loudly*:
##
##   * **An invalid wave is refused, never run.** `start_wave()` validates the
##     definition first; a wave with no enemies, a null line or a zero-speed
##     enemy prints `WAVE_REFUSED` with the reason and returns false. The wave
##     phase is *not* entered, so the caller cannot be left waiting for a wave
##     that will never finish.
##   * **A failed spawn never stalls the queue.** If the spawn function returns
##     nothing, the unit is dropped with a printed reason and the next one is
##     paced normally; a wave that refuses to advance is a hang with extra steps.
##
## The director owns no walkers and no gold: it asks the arena for one enemy via
## `spawn_callable`, and the arena applies the line's stats. That way there is
## still exactly one place in the codebase that puts an enemy on the lane
## (`Arena.adopt_walker`).

const MIN_SPACING_SECONDS := 0.01

signal wave_started(wave: WaveDefinition)
signal wave_completed(wave: WaveDefinition)
signal level_completed()
signal wave_refused(wave_index: int, reason: String)

## Called once with a `WaveEntry`; returns the spawned `LaneWalker` or null.
var spawn_callable: Callable = Callable()

var _waves: Array[WaveDefinition] = []
var _cleared: Array[bool] = []
## The wave being run, or the last one run. -1 until the first `start_wave`.
var _index: int = -1
var _active: bool = false
## One entry per unit still to spawn, in spawn order. Entries are shared
## references to the plan's lines and are never mutated here.
var _queue: Array[WaveEntry] = []
var _alive: Array[LaneWalker] = []
var _countdown: float = 0.0
var _spawned_units: int = 0
var _cleared_units: int = 0
var _last_refusal: String = ""


## The one place an enemy can come from. A director with no spawn function
## refuses every wave instead of spawning nothing quietly.
func setup(spawn: Callable) -> void:
	spawn_callable = spawn


## Replaces the plan. Rows are `WaveDefinition`s in level order. A plan set while
## a wave is running abandons that wave rather than merging two levels' queues.
func set_plan(waves: Array[WaveDefinition]) -> void:
	if _active:
		print("WAVE_PLAN_RESET " + JSON.stringify({
			"abandoned_wave": _index + 1,
			"units_left": _queue.size(),
		}))
	_waves = waves.duplicate()
	_cleared.clear()
	for i in _waves.size():
		_cleared.append(false)
	_index = -1
	_active = false
	_queue.clear()
	_alive.clear()
	_countdown = 0.0
	_spawned_units = 0
	_cleared_units = 0


func wave_count() -> int:
	return _waves.size()


func current_index() -> int:
	return _index


func current_wave() -> WaveDefinition:
	if _index < 0 or _index >= _waves.size():
		return null
	return _waves[_index]


func is_active() -> bool:
	return _active


## True once every wave of the plan has been cleared. A director with no plan is
## never complete: nothing has been run.
func is_level_complete() -> bool:
	return _waves.size() > 0 and not _cleared.has(false)


func units_left() -> int:
	return _queue.size()


func spawned_units() -> int:
	return _spawned_units


func cleared_units() -> int:
	return _cleared_units


## The walkers this wave spawned that are still in play. A dead-but-not-yet-freed
## node is already out of play: it does not keep a wave open (the arena's own
## watchdog owns "the node is really gone").
func walkers() -> Array[LaneWalker]:
	_prune()
	return _alive.duplicate()


## The reason the last refusal gave, verbatim, so a harness can assert on the
## words and not only on the boolean.
func last_refusal() -> String:
	return _last_refusal


# --- starting a wave --------------------------------------------------------

## Runs wave `index` (0-based). Returns false, without changing state, when the
## wave is one this director must not run — and prints why.
func start_wave(index: int) -> bool:
	if spawn_callable.is_null():
		return _refuse(index, "no spawn function is wired, so no enemy could reach the lane")
	if _waves.is_empty():
		return _refuse(index, "the director has no plan: 0 waves")
	if index < 0 or index >= _waves.size():
		return _refuse(
			index, "wave index %d is outside the plan, which has %d wave(s)" % [index, _waves.size()]
		)
	if _active:
		return _refuse(index, "wave %d is still running" % (_index + 1))

	var wave: WaveDefinition = _waves[index]
	if wave == null:
		return _refuse(index, "wave %d is null" % (index + 1))
	var why: String = wave.validate()
	if why != "":
		return _refuse(index, why)

	_queue.clear()
	for entry in wave.all_entries():
		for i in maxi(entry.count, 0):
			_queue.append(entry)
	_alive.clear()
	_index = index
	_active = true
	# Zero, not the wave's interval: the first unit of a wave arrives at once. A
	# build phase is the caller's decision, and a wave that opens with silence
	# reads as a wave that did not start.
	_countdown = 0.0
	_spawned_units = 0
	_cleared_units = 0

	print("WAVE_START " + JSON.stringify({
		"wave": wave.number,
		"index": index,
		"units": wave.unit_count(),
		"health": wave.total_health(),
		"lines": wave.all_entries().size(),
		"sub_boss": wave.sub_boss.kind if wave.sub_boss != null else "",
		"waves": _waves.size(),
	}))
	wave_started.emit(wave)
	return true


func _refuse(index: int, why: String) -> bool:
	_last_refusal = why
	print("WAVE_REFUSED " + JSON.stringify({
		"wave_index": index,
		"wave": index + 1,
		"reason": why,
		"active": _active,
		"waves": _waves.size(),
	}))
	# Expected player-facing refusals are printed, not errors (`arena.gd` sets the
	# precedent). This one is not player-facing: a wave that cannot run is a data
	# bug, and the log says so where a gate will find it.
	push_error("WAVE_ERROR wave %d refused: %s" % [index + 1, why])
	wave_refused.emit(index, why)
	return false


# --- pacing -----------------------------------------------------------------

## Advances the wave by `delta` seconds of game time: spawns at most one unit per
## call, and completes the wave as soon as it is empty of queued and live units.
func tick(delta: float) -> void:
	if not _active:
		return
	_prune()
	if _queue.is_empty() and _alive.is_empty():
		_complete()
		return
	if _queue.is_empty():
		return
	_countdown -= maxf(delta, 0.0)
	if _countdown > 0.0:
		return
	_spawn_next()


func _spawn_next() -> void:
	var entry: WaveEntry = _queue.pop_front()
	var walker := spawn_callable.call(entry) as LaneWalker
	_countdown = maxf(entry.spacing_seconds, MIN_SPACING_SECONDS)
	if walker == null:
		print("WAVE_SPAWN_FAILED " + JSON.stringify({
			"wave": _index + 1,
			"kind": entry.kind,
			"units_left": _queue.size(),
			"reason": "the spawn function returned no walker; the unit is dropped so the wave can still end",
		}))
		push_error("WAVE_ERROR the arena could not spawn a '%s'" % entry.kind)
		return
	_alive.append(walker)
	_spawned_units += 1


## Drops walkers that are dead, leaked or freed. `is_alive()` is the contract for
## "in play" (`lane_walker.gd`), so a wave ends on the tick its last enemy dies
## rather than a frame later - and a leaked enemy ends it too.
func _prune() -> void:
	var live: Array[LaneWalker] = []
	for walker in _alive:
		if is_instance_valid(walker) and not walker.is_queued_for_deletion() and walker.is_alive():
			live.append(walker)
		else:
			_cleared_units += 1
	_alive = live


func _complete() -> void:
	var wave: WaveDefinition = current_wave()
	_active = false
	if _index >= 0 and _index < _cleared.size():
		_cleared[_index] = true
	print("WAVE_CLEAR " + JSON.stringify({
		"wave": wave.number if wave != null else _index + 1,
		"index": _index,
		"spawned": _spawned_units,
		"cleared": _cleared_units,
		"waves": _waves.size(),
		"level_complete": is_level_complete(),
	}))
	if wave != null:
		wave_completed.emit(wave)
	if is_level_complete():
		print("WAVE_LEVEL_CLEAR " + JSON.stringify({"waves": _waves.size()}))
		level_completed.emit()
