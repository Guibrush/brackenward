extends SceneTree

## T-0039 DoD 2, 4 and 5 — the waves of level 1 and level 5 as **numbers**, and
## both planted failures, in one headless run.
##
##     godot --headless --path . --script res://src/gameplay/tests/wave_demo.gd
##
## The demo drives the real `res://scenes/main.tscn` for the integration step:
## the wave that spawns here is spawned by the scene's own arena, through the
## scene's own enemy scene and `adopt_walker`. No mock director, no hand-built
## plan for the part that matters.
##
## Prints, in this order:
##   WAVE_DEMO_CASE {name}       which step is being taken
##   WAVE_DEMO_LEVEL {json}      waves, units and enemy health for one level
##   WAVE_DEMO_ELITE {json}      which sub-boss an elite carries, and on which wave
##   WAVE_DEMO_REFUSED {text}    a refusal's reason, echoed verbatim
##   WAVE_DEMO_STEP {json}       the state worth recording after a step
##   WAVE_DEMO_SELF_TEST {json}  once, last; carries checks and failures
##
## The `WAVE_PLAN_*`, `WAVE_START`, `WAVE_CLEAR`, `WAVE_REFUSED`, `ARENA_WAVE`,
## `ARENA_PHASE` and `ARENA_PLACED`-style lines below are printed by the systems
## under test, not by this file. That is the point: the demo shows what the game
## says.
##
## **One `ERROR:` line is expected and deliberate.** Planted failure A is a wave
## with no enemies, and `WaveDirector` treats that as a data bug: it prints the
## reason and `push_error`s it (DoD 4 asks for loud). The demo's verdict is
## `WAVE_DEMO_SELF_TEST`, never the exit code (L-035).
##
## Wave pacing runs in game time: `WaveDirector.tick(delta)` is public, so the
## demo drives a whole wave in microseconds instead of waiting 13 real seconds for
## six spawn intervals. That is the same call the arena makes from
## `_physics_process`.

const ARENA_SCENE := "res://scenes/main.tscn"

## Game time per director tick. 1 s against a 2.2 s interval means every unit of a
## wave is observed on the tick after it spawns, so the kill loop cannot run ahead
## of the spawner.
const TICK_SECONDS := 1.0

## Guard on the wave loop. A director that never completes fails this demo with a
## message instead of hanging it.
const MAX_WAVE_TICKS := 400

## `waves.md` §Level 1 and §The scale. The calibration fixture is asserted, not
## described: `economy.md` §Worked example is priced on exactly these numbers.
const LEVEL1_WAVES := 6
const LEVEL1_UNITS := 81
const LEVEL1_HEALTH := 2856
const LEVEL1_WAVE1_UNITS := 6
const LEVEL1_WAVE1_HEALTH := 240
const LEVEL1_THREAT := 82.0
const LEVEL5_WAVES := 7
const LEVEL5_THREAT := 170.0

## Enough damage to kill any placeholder enemy in one hit.
const LETHAL_DAMAGE := 1000000

var _arena = null
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# The tree has not iterated during `_initialize()`: nothing is safe until it
	# has, and a node added to `root` here has not run `_ready` yet.
	await process_frame

	var packed := load(ARENA_SCENE) as PackedScene
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

	await process_frame
	await physics_frame

	if not check(_arena.wave_plan() != null, "the arena booted with a wave plan"):
		_finish()
		return

	await _run_demo()
	_finish()


func _run_demo() -> void:
	_step_numbers()
	_step_elite()
	_step_planted_a()
	_step_planted_b()
	_step_integration()


# --- 1: the numbers ---------------------------------------------------------

## DoD 2. Level 1 against level 5, wave count, unit count and enemy health, plus
## the two spot values the brief names (wave 1 = 6 Grunts / 240 HP).
func _step_numbers() -> void:
	_case("level 1 against level 5")
	var plan := WavePlan.new()

	var one := plan.build(1, false)
	var five := plan.build(5, false)
	var one_numbers := plan.describe_level(one)
	var five_numbers := plan.describe_level(five)

	print("WAVE_DEMO_LEVEL " + JSON.stringify({
		"level_index": 1,
		"elite": false,
		"threat": plan.total_threat_for(1),
		"waves": one_numbers["waves"],
		"units": one_numbers["units"],
		"health": one_numbers["health"],
		"wave_1": {
			"units": one[0].unit_count(),
			"health": one[0].total_health(),
			"composition": one[0].describe()["lines"],
		},
		"final_wave": {
			"units": one[one.size() - 1].unit_count(),
			"health": one[one.size() - 1].total_health(),
		},
	}))
	print("WAVE_DEMO_LEVEL " + JSON.stringify({
		"level_index": 5,
		"elite": false,
		"threat": plan.total_threat_for(5),
		"waves": five_numbers["waves"],
		"units": five_numbers["units"],
		"health": five_numbers["health"],
		"wave_1": {
			"units": five[0].unit_count(),
			"health": five[0].total_health(),
			"composition": five[0].describe()["lines"],
		},
		"final_wave": {
			"units": five[five.size() - 1].unit_count(),
			"health": five[five.size() - 1].total_health(),
		},
	}))

	check_eq_int(int(one_numbers["waves"]), LEVEL1_WAVES, "level 1 has %d waves" % LEVEL1_WAVES)
	check_eq_int(int(one_numbers["units"]), LEVEL1_UNITS, "level 1 spawns %d units" % LEVEL1_UNITS)
	check_eq_int(
		int(one_numbers["health"]), LEVEL1_HEALTH, "level 1 carries %d enemy HP" % LEVEL1_HEALTH
	)
	check_eq_int(
		one[0].unit_count(), LEVEL1_WAVE1_UNITS, "level 1 wave 1 is %d units" % LEVEL1_WAVE1_UNITS
	)
	check_eq_int(
		one[0].total_health(),
		LEVEL1_WAVE1_HEALTH,
		"level 1 wave 1 is %d HP of Grunts" % LEVEL1_WAVE1_HEALTH
	)
	check(
		one[0].units_of_kind([&"grunt"]) == LEVEL1_WAVE1_UNITS,
		"level 1 wave 1 is all Grunts, as the calibration table says"
	)

	check_eq_int(int(five_numbers["waves"]), LEVEL5_WAVES, "level 5 has %d waves" % LEVEL5_WAVES)
	check(
		int(five_numbers["units"]) > int(one_numbers["units"]),
		"level 5 spawns more units than level 1 (%d against %d)"
		% [int(five_numbers["units"]), int(one_numbers["units"])]
	)
	check(
		int(five_numbers["health"]) > int(one_numbers["health"]),
		"level 5 carries more enemy HP than level 1 (%d against %d)"
		% [int(five_numbers["health"]), int(one_numbers["health"])]
	)

	# The escalation itself: `level_index` is the only input, so threat must rise
	# with it and nothing else may move it.
	var previous := 0.0
	var monotone := true
	for level in range(1, 6):
		var threat := plan.total_threat_for(level)
		if threat <= previous:
			monotone = false
		previous = threat
	check(monotone, "threat rises with level_index across levels 1-5")
	check(
		is_equal_approx(plan.total_threat_for(1), LEVEL1_THREAT),
		"level 1's budget is %.1f threat" % LEVEL1_THREAT
	)
	check(
		is_equal_approx(plan.total_threat_for(5), LEVEL5_THREAT),
		"level 5's budget is %.1f threat" % LEVEL5_THREAT
	)
	check(plan.validate_level(1, false, one) == "", "the level 1 plan validates")
	check(plan.validate_level(5, false, five) == "", "the level 5 plan validates")

	# A level index of zero is illegal (`waves.md` §Edge cases): refused with a
	# printed reason and no waves, never a plan that makes level 0 the easiest.
	var none := plan.build(0, false)
	print("WAVE_DEMO_STEP " + JSON.stringify({
		"step": "illegal_level_index",
		"waves": none.size(),
	}))
	check(none.is_empty(), "level index 0 builds no waves at all")

	_step("numbers", {
		"level_1": {
			"waves": int(one_numbers["waves"]),
			"units": int(one_numbers["units"]),
			"health": int(one_numbers["health"]),
		},
		"level_5": {
			"waves": int(five_numbers["waves"]),
			"units": int(five_numbers["units"]),
			"health": int(five_numbers["health"]),
		},
	})


# --- 2: the elite finale ----------------------------------------------------

## DoD 5's positive half: an elite carries exactly one sub-boss, on its final
## wave, chosen at generation time so the choice is fixed before the player
## commits to the node (`waves.md` §The elite finale).
func _step_elite() -> void:
	_case("an elite level carries exactly one sub-boss, on its final wave")
	var plan := WavePlan.new()
	var elite := plan.build(5, true)
	var numbers := plan.describe_level(elite)
	var last_index := elite.size() - 1
	var final_wave := elite[last_index]
	var sub_boss_kind: StringName = final_wave.sub_boss.kind if final_wave.sub_boss != null else &""

	print("WAVE_DEMO_ELITE " + JSON.stringify({
		"level_index": 5,
		"waves": numbers["waves"],
		"sub_bosses": numbers["sub_bosses"],
		"final_wave": final_wave.number,
		"kind": sub_boss_kind,
		"sub_boss_health": final_wave.sub_boss.max_health if final_wave.sub_boss != null else 0,
		"trash_units": final_wave.unit_count() - (1 if final_wave.sub_boss != null else 0),
		"trash_health": _trash_health(final_wave),
		"trash_fraction": plan.elite_final_trash_fraction,
	}))

	check_eq_int(int(numbers["sub_bosses"]), 1, "the elite level carries exactly one sub-boss unit")
	check(final_wave.sub_boss != null, "the sub-boss is on the final wave")
	var earlier := 0
	for i in last_index:
		if elite[i].sub_boss != null:
			earlier += 1
	check_eq_int(earlier, 0, "no wave before the final one carries a sub-boss")
	check(
		plan.sub_boss_pool.has(sub_boss_kind),
		"the sub-boss came from the pool %s (drew '%s')" % [plan.sub_boss_pool, sub_boss_kind]
	)
	check(
		numbers.has("sub_bosses") and int(numbers["sub_bosses"]) == 1,
		"the level's sub-boss count is one, not one per wave"
	)

	# The elite's trash is reduced, so the sub-boss is added on top rather than
	# crowding out the wave it leads.
	var normal := plan.build(5, false)
	var normal_trash := _trash_health(normal[normal.size() - 1])
	check(
		_trash_health(final_wave) < normal_trash,
		"the elite's final-wave trash is smaller than the normal one (%d HP against %d)"
		% [_trash_health(final_wave), normal_trash]
	)

	# Generation-time choice: the same level builds the same sub-boss twice, so a
	# player cannot re-roll the wall by reopening the node.
	var again := plan.build(5, true)
	var again_wave := again[again.size() - 1]
	var again_kind: StringName = again_wave.sub_boss.kind if again_wave.sub_boss != null else &""
	check(again_kind == sub_boss_kind, "the sub-boss choice is fixed at generation time ('%s')" % again_kind)

	_step("elite", {
		"final_wave": final_wave.number,
		"kind": sub_boss_kind,
		"sub_bosses": int(numbers["sub_bosses"]),
	})


# --- 3: planted failure A ---------------------------------------------------

## DoD 4. A wave definition with zero enemies must fail loudly with a printed
## reason, not hang and not skip. The refusal is checked in three places: the
## definition itself, the director, and the arena - because "the director says no"
## is worth nothing if the phase still locks.
func _step_planted_a() -> void:
	_case("planted failure A: a wave with no enemies is refused, not run")
	var empty_wave := WaveDefinition.new()
	empty_wave.number = 1

	var why := empty_wave.validate()
	print("WAVE_DEMO_REFUSED " + why)
	check(why.find("no enemies") != -1, "the wave definition names the fault: no enemies")

	var plan := WavePlan.new()
	var empty_plan: Array[WaveDefinition] = [empty_wave]
	check(
		plan.validate_level(1, false, empty_plan) != "",
		"the level validator refuses a plan made of one empty wave"
	)

	var director: WaveDirector = _arena.wave_director()
	director.set_plan(empty_plan)
	var started: bool = director.start_wave(0)
	print("WAVE_DEMO_REFUSED " + director.last_refusal())
	check(not started, "the director refuses to start a wave with no enemies")
	check(director.last_refusal().find("no enemies") != -1, "the director's reason names the fault")
	check(not director.is_active(), "a refused wave is not active")

	# The anti-hang assertion: ticking a refused wave produces nothing, forever.
	director.tick(600.0)
	check(director.walkers().is_empty(), "a refused wave spawned no walker")
	check_eq_int(director.units_left(), 0, "a refused wave has no queue to drain")

	# And through the arena, which is where the phase lives.
	var arena_started: bool = _arena.start_wave(0)
	print("WAVE_DEMO_REFUSED " + director.last_refusal())
	check(not arena_started, "the arena refuses the same wave")
	check(
		not _arena.is_wave_active(),
		"a refused wave leaves the build phase unlocked instead of locking the player out"
	)

	_step("planted_a", {
		"reason": why,
		"director_active": director.is_active(),
		"phase": _arena.phase_name(),
	})


# --- 4: planted failure B ---------------------------------------------------

## DoD 5, broken on purpose. `elite_sub_boss_picks` is an int for exactly this
## reason: a bug that spawns two sub-bosses is a data change, and the rule that
## forbids it has to catch data. Both halves are checked - two is refused, one is
## accepted - so the catcher is not just "always fail".
func _step_planted_b() -> void:
	_case("planted failure B: an elite with two sub-bosses is caught")
	var plan := WavePlan.new()
	plan.elite_sub_boss_picks = 2
	var broken := plan.build(5, true)
	var broken_numbers := plan.describe_level(broken)
	var why := plan.validate_level(5, true, broken)

	print("WAVE_DEMO_STEP " + JSON.stringify({
		"step": "two_sub_bosses",
		"sub_bosses": int(broken_numbers["sub_bosses"]),
		"final_wave": broken[broken.size() - 1].number,
		"reason": why,
	}))
	check_eq_int(int(broken_numbers["sub_bosses"]), 2, "the broken selection put two sub-bosses in the level")
	check(why != "", "the elite rule refuses an elite with two sub-bosses")
	check(why.find("sub-boss") != -1, "the reason names the sub-boss rule")
	check(why.find("exactly one") != -1, "the reason states the rule: exactly one")

	plan.elite_sub_boss_picks = 1
	var fixed := plan.build(5, true)
	var fixed_why := plan.validate_level(5, true, fixed)
	check_eq_int(int(plan.describe_level(fixed)["sub_bosses"]), 1, "one pick puts back exactly one sub-boss")
	check(fixed_why == "", "the same validator accepts exactly one (it is not a blanket refusal)")

	_step("planted_b", {
		"broken_sub_bosses": int(broken_numbers["sub_bosses"]),
		"fixed_sub_bosses": int(plan.describe_level(fixed)["sub_bosses"]),
	})


# --- 5: a real wave through the real arena ----------------------------------

## `arena.gd` integration, driven end to end: the arena builds the plan for its
## `level_index`, starts wave 1, spawns it through `adopt_walker` with the line's
## stats, and returns to the build phase when the last walker is gone.
func _step_integration() -> void:
	_case("the arena runs level 1 wave 1 and returns to the build phase")
	_arena.build_level_plan()
	check_eq_int(_arena.level_wave_count(), LEVEL1_WAVES, "the arena built a %d-wave level" % LEVEL1_WAVES)
	check(_arena.start_wave(0), "the arena starts the level")
	check(_arena.is_wave_active(), "a running wave locks the build phase")

	var director: WaveDirector = _arena.wave_director()
	var wave: WaveDefinition = director.current_wave()
	if not check(wave != null, "the director knows which wave is running"):
		return
	check_eq_int(wave.number, 1, "the first wave of the level is wave 1")
	check_eq_int(wave.unit_count(), LEVEL1_WAVE1_UNITS, "wave 1 is %d units" % LEVEL1_WAVE1_UNITS)

	var killed := 0
	var saw_wave_stats := false
	var ticks := 0
	while director.is_active() and ticks < MAX_WAVE_TICKS:
		director.tick(TICK_SECONDS)
		ticks += 1
		for walker in director.walkers():
			if not walker.is_alive():
				continue
			if walker.max_health == 40 and is_equal_approx(walker.move_speed, 100.0):
				saw_wave_stats = true
			if walker.take_damage(LETHAL_DAMAGE) > 0:
				killed += 1

	check(not director.is_active(), "wave 1 finished within %d ticks" % MAX_WAVE_TICKS)
	check_eq_int(director.spawned_units(), LEVEL1_WAVE1_UNITS, "the director spawned the whole wave")
	check_eq_int(killed, LEVEL1_WAVE1_UNITS, "every unit of the wave was accounted for")
	check(saw_wave_stats, "the wave line's stats reached the walker (40 HP at 100 px/s)")
	check_eq_int(director.units_left(), 0, "the wave's queue is empty")
	check(director.is_level_complete() == false, "one wave of six does not complete the level")
	check_eq_int(_arena.waves_cleared(), 1, "the arena counted one cleared wave")
	check(
		not _arena.is_wave_active(),
		"the phase returned to build when the last walker was gone"
	)

	_step("integration", {
		"waves": _arena.level_wave_count(),
		"cleared": _arena.waves_cleared(),
		"spawned": director.spawned_units(),
		"killed": killed,
		"ticks": ticks,
		"phase": _arena.phase_name(),
	})


# --- helpers ----------------------------------------------------------------

## A wave's health without its sub-boss: the elite comparison is about the trash
## budget, and the sub-boss is added on top of it.
func _trash_health(wave: WaveDefinition) -> int:
	var total := 0
	for entry in wave.entries:
		total += maxi(entry.count, 0) * maxi(entry.max_health, 0)
	return total


# --- reporting --------------------------------------------------------------

func _case(step_name: String) -> void:
	print("WAVE_DEMO_CASE " + step_name)


func _step(step_name: String, extra: Dictionary = {}) -> void:
	var payload: Dictionary = {"step": step_name}
	payload.merge(extra, false)
	print("WAVE_DEMO_STEP " + JSON.stringify(payload))


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


## Exactly one self-test line, last. A demo that recorded no checks fails: it
## proved nothing, and "no assertions" must never look like a pass.
func _finish() -> void:
	if _checks == 0 and _failures.is_empty():
		_failures.append("the demo recorded no checks")

	var passed := _failures.is_empty()
	print("WAVE_DEMO_SELF_TEST " + JSON.stringify({
		"name": "wave_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("WAVE_DEMO_FAILURE " + f)
	quit(1)
