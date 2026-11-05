extends SceneTree

## Shared harness for every case in `scripts/tests/cases/`.
##
## A case does not decide anything about its own exit status. It records checks
## through `check()` / `check_eq_int()`, then the harness prints exactly one
## machine-readable line and exits. That split is what lets `run.ps1` tell the
## difference between:
##
##   * the case ran and an assertion failed  -> a TEST_RESULT line, status fail
##   * the case never ran at all             -> no TEST_RESULT line (parse error,
##                                              crash, or a script the engine
##                                              refused to load)
##
## Both are failures, but they need different words in the report, and a case
## that silently does nothing must never look green (L-021, L-031, L-035).
##
## Every case drives the real `res://scenes/main.tscn` rather than a
## reimplementation of it. A test that rebuilds the scene by hand proves the
## test's idea of the scene, not the scene.
##
## How to write a case:
##
##     extends "res://scripts/tests/lib/suite.gd"
##
##     func case_name() -> String:
##         return "what this proves"
##
##     func run_case() -> void:
##         check(true, "...")          # records a check, never exits
##
## `run_case` may await (`await step(n)`, `await wait_until(...)`). The harness
## awaits it, and `await` on a non-coroutine is a no-op in Godot 4, so a case
## with no waiting still works.

const ARENA_SCENE := "res://scenes/main.tscn"

## Only used if the arena does not declare its own `hq_path`.
const HQ_FALLBACK_PATH := ^"HQ"

## Ceiling on any single wait, in physics frames. At the engine's 60 Hz default
## this is 20 s, which is five times what a walker needs to cross the 800 px
## lane at 200 px/s, and small enough that a broken assumption fails the case
## instead of stalling the gate.
const MAX_WAIT_FRAMES := 1200

const LINE_PREFIX := "TEST_RESULT "

var _name := "unnamed"
var _checks := 0
var _failures: Array[String] = []
var _arena: Node = null
var _hq: Hq = null


func _initialize() -> void:
	_name = case_name()
	_boot()


## Name reported by the runner. Override in every case.
func case_name() -> String:
	return "unnamed"


## The body of the case. Override in every case.
func run_case() -> void:
	pass


func arena() -> Node:
	return _arena


func hq() -> Hq:
	return _hq


# --- assertions -------------------------------------------------------------
#
# Each returns bool so a case can stop early with `if not check(...): return`.
# Nothing here exits: a case that fails check 2 should still run check 3, so the
# report says everything that is wrong instead of only the first thing.

func check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
	return condition


func check_eq_int(actual: int, expected: int, message: String) -> bool:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %d, got %d" % [message, expected, actual])
		return false
	return true


func fail(message: String) -> void:
	_checks += 1
	_failures.append(message)


# --- frame driving ----------------------------------------------------------

## Advances exactly `frames` physics ticks. Physics is used rather than idle
## frames because the walker moves in `_physics_process`: one tick is one step
## of game time regardless of how fast the headless loop happens to run.
func step(frames: int) -> void:
	for i in maxi(frames, 0):
		await physics_frame


## Advances one physics tick at a time until `predicate` returns true.
## Returns false and records a failure if `max_frames` is exhausted, so a wait
## that never satisfies its condition is a named failure, not a hang.
func wait_until(predicate: Callable, max_frames: int, what: String) -> bool:
	for i in max_frames:
		if predicate.call():
			return true
		await physics_frame
	if predicate.call():
		return true
	_checks += 1
	_failures.append("timed out after %d physics frames waiting for %s" % [max_frames, what])
	return false


func physics_ticks_per_second() -> int:
	return maxi(int(Engine.physics_ticks_per_second), 1)


## Frames worth of `seconds` of game time, rounded up, plus a small margin so a
## one-tick ordering difference cannot make a grace window end a tick early.
func frames_for_seconds(seconds: float, margin_frames: int = 5) -> int:
	return int(ceil(maxf(seconds, 0.0) * float(physics_ticks_per_second()))) + margin_frames


# --- lifecycle --------------------------------------------------------------

func _boot() -> void:
	# The tree has not iterated yet during _initialize(); nothing below is safe
	# until it has.
	await process_frame

	var packed := load(ARENA_SCENE)
	if packed == null:
		fail("could not load " + ARENA_SCENE)
		_finish()
		return

	_arena = packed.instantiate()
	if _arena == null:
		fail(ARENA_SCENE + " did not instantiate")
		_finish()
		return
	root.add_child(_arena)

	# `_ready()` has NOT run at the moment the node enters the tree: health still
	# reads 0 here. This wait is not politeness. Without it, a test for "the HQ
	# reports depleted at zero health" would pass on a scene that never booted,
	# which is the worst kind of green.
	await process_frame
	await physics_frame

	_hq = _resolve_hq(_arena)
	if _hq == null:
		fail("no HQ reachable from the arena's hq_path; the scene is not wired")
		_finish()
		return

	# Precondition for every case: the scene booted and the HQ is full. If this
	# fails, the scene is at fault, not the case, and the message says so.
	if not check(
		_hq.max_health > 0 and _hq.health() == _hq.max_health,
		"the scene booted with a full HQ (health %d of %d)" % [_hq.health(), _hq.max_health]
	):
		_finish()
		return

	await run_case()
	_finish()


func _resolve_hq(from: Node) -> Hq:
	var path := HQ_FALLBACK_PATH
	var declared = from.get("hq_path")
	if declared is NodePath and not (declared as NodePath).is_empty():
		path = declared
	return from.get_node_or_null(path) as Hq


## Prints the single result line the runner parses, then sets the process exit
## code. A case that ran zero checks fails: it proved nothing, and "no
## assertions" must not be able to look like a pass.
func _finish() -> void:
	if _checks == 0 and _failures.is_empty():
		_failures.append("the case recorded no checks")

	var passed := _failures.is_empty()
	var payload := {
		"name": _name,
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
		"message": "" if passed else _failures[0],
	}
	print(LINE_PREFIX + JSON.stringify(payload, "", true))

	if passed:
		quit(0)
		return
	for f in _failures:
		printerr("TEST_FAILURE " + f)
	quit(1)
