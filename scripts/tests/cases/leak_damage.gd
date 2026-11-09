extends "res://scripts/tests/lib/suite.gd"

## One leak costs exactly `damage_per_leak` health - no more, no less.
##
## Measured in the arena run: 10 -> 9 for one arrival. The assertion is written
## against the scene's own `damage_per_leak` rather than the literal 1, so it
## states the contract ("a leak costs what the scene says it costs") and not a
## recorded observation. A scene that double-charges fails here.
##
## The lane is 800 px and a wave Grunt walks it at 100 px/s (`wave_plan.gd`,
## `_default_roster`), so the first arrival is about 8 s of game time = 480
## physics ticks at 60 Hz. LEAK_WAIT_FRAMES is 600 (10 s), which bounds the wait
## without being the thing under test; game time is simulated, so the margin does
## not depend on how fast the machine is.

const LEAK_WAIT_FRAMES := 600


func case_name() -> String:
	return "a leak applies exactly damage_per_leak health"


func run_case() -> void:
	var per_leak := int(arena().get("damage_per_leak"))
	if not check(per_leak >= 1, "damage_per_leak is positive (got %d)" % per_leak):
		return

	# Waves are the only source of enemies on the lane (T-0072): the scene boots
	# with none, so the case starts wave 1 itself. `call` rather than
	# `arena().start_wave(0)` because the harness hands the arena back as a bare
	# `Node`, and a static call on a method `Node` does not have is a parse error.
	# A refused start is reported here as a failure of this case, and the run
	# below never begins: what this case measures is the leak, not the setup.
	if not check(
		bool(arena().call("start_wave", 0)),
		"wave 1 starts (start_wave(0) returned false)"
	):
		return

	var before := hq().health()
	check_eq_int(before, hq().max_health, "the HQ starts the run at full health")

	var leaked := await wait_until(
		func() -> bool: return hq().health() != before,
		LEAK_WAIT_FRAMES,
		"the first walker to reach the lane end"
	)
	if not leaked:
		return

	var after := hq().health()
	check_eq_int(before - after, per_leak, "one leak costs exactly damage_per_leak")
	check(after > 0, "one leak does not empty a full HQ")
