extends "res://scripts/tests/lib/suite.gd"

## One leak costs exactly `damage_per_leak` health - no more, no less.
##
## Measured in the arena run: 10 -> 9 for one arrival. The assertion is written
## against the scene's own `damage_per_leak` rather than the literal 1, so it
## states the contract ("a leak costs what the scene says it costs") and not a
## recorded observation. A scene that double-charges fails here.
##
## The lane is 800 px and the walker moves at 200 px/s, so the first arrival is
## about 4 s of game time; MAX_WAIT_FRAMES is five times that.

const LEAK_WAIT_FRAMES := 600


func case_name() -> String:
	return "a leak applies exactly damage_per_leak health"


func run_case() -> void:
	var per_leak := int(arena().get("damage_per_leak"))
	if not check(per_leak >= 1, "damage_per_leak is positive (got %d)" % per_leak):
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
