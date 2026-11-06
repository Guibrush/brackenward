extends SceneTree

## Headless proof for `src/systems/run_state.gd` — T-0037 DoD items 2-5.
##
##     godot --headless --path . --script res://src/systems/tests/run_state_selftest.gd
##
## Pure logic, so no scene and no frames: every case runs inside `_initialize`.
##
## Prints, in this order:
##   RUN_CASE {name}            which case is running
##   RUN_STEP {json}            the state after each step worth recording
##   RUN_LEDGER {json}          each run's gold ledger, reconciled
##   RUN_REFUSED {text}         the reason a refused call gave, verbatim
##   RUN_RESET {json}           before/after of the second-run reset
##   RUN_SAVE_SCAN {json}       user:// file list before and after a full run
##   RUN_SELF_TEST {json}       exactly one, last; carries checks and failures
##
## The exit code alone is not evidence (L-035): `RUN_SELF_TEST` carries `checks`,
## `failed` and the failure strings, and a failing check also prints an `ERROR:`
## line so a gate that greps for one sees it. Exit 0 = every check passed.
##
## This file exists under `src/systems/` because `scripts/**` belongs to
## eng/tools. Moving it to `scripts/tests/cases/` (and deleting this copy) is
## theirs to do; the assertions are written in the suite's shape already.

const RunStateScript := preload("res://src/systems/run_state.gd")

const SAVE_CANDIDATES := [
	"user://run.save",
	"user://run_state.save",
	"user://save.json",
	"user://savegame.save",
	"user://brackenward.save",
]

const MIN_CHECK_COUNT := 1
const PLACEHOLDER := "(placeholder numbers; T-0035 replaces them)"

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_case_three_level_run()
	_case_planted_failure_a()
	_case_planted_failure_b()
	_case_no_save_file()
	_finish()


# --- case 1: the happy path (DoD 2) -----------------------------------------

func _case_three_level_run() -> void:
	print("RUN_CASE three_level_run_gold_in_gold_spent_hq_carried")
	var run: RefCounted = RunStateScript.new()

	check(run.start(3, 10, RunStateScript.STARTING_GOLD), "a three-level run starts")
	_step(run, "run_start")
	check_eq_int(run.gold(), 10, "starting gold")
	check_eq_int(run.hq_health(), 10, "starting HQ")
	check_eq_int(run.level_number(), 1, "starting level number")
	check(not run.is_final_level(), "level 1 of 3 is not the final level")

	# --- level 1
	_earn_kills(run, 3)
	check(run.spend_gold(6, "tower"), "a tower can be bought for 6")
	check(run.spend_gold(2, "reroll"), "a reroll can be bought for 2")
	_step(run, "level_1_spent")

	var refused_overspend: bool = run.spend_gold(999, "tower")
	print("RUN_REFUSED " + run.last_refusal())
	check(not refused_overspend, "a purchase beyond the balance is refused")
	check_eq_int(run.gold(), 5, "a refused purchase leaves the balance untouched")
	check(run.last_refusal().find("only 5 in hand") != -1, "the refusal names the shortfall")

	_leak(run, 2)
	check_eq_int(run.hq_health(), 8, "HQ after two leaks")
	check(run.complete_level(), "level 1 clears")
	_step(run, "level_1_cleared")
	check_eq_int(run.gold(), 10, "level-clear gold paid on top of the balance")
	check_eq_int(run.hq_health(), 8, "HQ carried into level 2")
	check_eq_int(run.level_number(), 2, "advanced to level 2")

	# --- level 2
	_earn_kills(run, 4)
	check(run.spend_gold(5, "upgrade"), "an upgrade can be bought for 5")
	_leak(run, 1)
	check_eq_int(run.hq_health(), 7, "HQ after three leaks across two levels")
	check(run.complete_level(), "level 2 clears")
	_step(run, "level_2_cleared")
	check_eq_int(run.hq_health(), 7, "HQ carried into the final level")
	check_eq_int(run.level_number(), 3, "advanced to level 3")
	check(run.is_final_level(), "level 3 of 3 is the final level")

	# --- level 3, the final one: clearing it wins the run
	_earn_kills(run, 2)
	check(run.spend_gold(8, "tower"), "a tower can be bought for 8")
	_step(run, "level_3_spent")
	check(run.complete_level(), "the final level clears")
	_step(run, "run_completed")

	check(run.is_victory(), "the run is won on the final level")
	check(run.is_over(), "a won run is over")
	check(not run.is_defeated(), "a won run is not a defeat")
	check(run.end_reason() != "", "a won run records why it ended")
	check_eq_int(run.gold(), 13, "gold left at victory")
	check_eq_int(run.hq_health(), 7, "HQ left at victory")
	check_eq_int(run.hq_max_health(), 10, "the HQ maximum never changed")

	# The run is over: further play is refused and pays nothing. The refusal's
	# reason is printed by the system itself (`RUN_REFUSED ...`, debug builds).
	var gold_at_end: int = run.gold()
	var replayed: bool = run.complete_level()
	check(not replayed, "clearing a won run's level again is refused")
	check(run.last_refusal().find("completed") != -1, "the refusal names the completion")
	check_eq_int(run.gold(), gold_at_end, "a refused advance pays no gold")

	_print_ledger(run, "three_level_run")
	_check_ledger_reconciles(run, "three_level_run")
	print("RUN_SUMMARY " + JSON.stringify({
		"note": PLACEHOLDER,
		"gold_in": 10 + 3 + 5 + 4 + 5 + 2 + 5,
		"gold_spent": 6 + 2 + 5 + 8,
		"gold_left": run.gold(),
		"hq_start": 10,
		"hq_carried": [8, 7, 7],
		"levels": 3,
		"status": run.status_name(),
	}))


# --- case 2: planted failure A (DoD 3) --------------------------------------

func _case_planted_failure_a() -> void:
	print("RUN_CASE planted_failure_a_hq_zero_ends_the_run_and_refuses_advancement")
	var run: RefCounted = RunStateScript.new()
	run.start(3, 10, 10)
	_earn_kills(run, 2)

	check(run.complete_level(), "level 1 clears normally")
	check_eq_int(run.level_number(), 2, "the run is on level 2")
	_step(run, "a_level_2_start")

	print("RUN_DAMAGE " + JSON.stringify({
		"step": "mid_run_damage",
		"applied": run.damage_hq(4, "leak"),
		"state": run.snapshot(),
	}))
	check(run.is_in_progress(), "the run survives partial HQ damage")
	check_eq_int(run.hq_health(), 6, "HQ after the first hit")

	# Driven to zero, mid-run: this is the planted failure.
	print("RUN_DAMAGE " + JSON.stringify({
		"step": "fatal_damage",
		"applied": run.damage_hq(6, "leak"),
		"state": run.snapshot(),
	}))
	check_eq_int(run.hq_health(), 0, "HQ reaches zero")
	check(run.is_defeated(), "HQ zero ends the run as a defeat")
	check(run.is_over(), "a defeated run is over")
	check(not run.is_in_progress(), "a defeated run is not in progress")
	check(run.end_reason() != "", "the defeat records why")
	print("RUN_ENDED " + JSON.stringify({
		"victory": run.is_victory(),
		"reason": run.end_reason(),
		"level": run.level_number(),
	}))

	# Subsequent advancement must be refused, with a reason, and pay nothing.
	var gold_at_defeat: int = run.gold()
	var level_at_defeat: int = run.level_number()
	var advanced: bool = run.complete_level()
	print("RUN_REFUSED " + run.last_refusal())
	check(not advanced, "advancing after the defeat is refused")
	check(run.last_refusal() != "", "the refusal carries a reason")
	check(
		run.last_refusal().find("cannot complete the current level") != -1,
		"the refusal names the refused action"
	)
	check(run.last_refusal().find("defeated") != -1, "the reason names the defeat")
	check(run.last_refusal().find("HQ reached zero") != -1, "the reason names the cause")
	check_eq_int(run.level_number(), level_at_defeat, "the level index did not advance")
	check_eq_int(run.gold(), gold_at_defeat, "a refused advance pays no level-clear gold")
	check(not run.can_complete_level(), "can_complete_level() agrees with the refusal")

	# Nothing resurrects a lost run.
	check_eq_int(run.heal_hq(5), 0, "a defeated run cannot be healed back to life")
	check_eq_int(run.damage_hq(1), 0, "a defeated run takes no further damage")
	check(not run.is_in_progress(), "still defeated after both attempts")
	_print_ledger(run, "planted_failure_a")


# --- case 3: planted failure B (DoD 4) --------------------------------------

func _case_planted_failure_b() -> void:
	print("RUN_CASE planted_failure_b_second_run_resets_gold_and_hq")
	var run: RefCounted = RunStateScript.new()
	run.start(3, 10, 10)

	# A first run that accumulates real value and then loses.
	_earn_kills(run, 7)
	check(run.spend_gold(6, "tower"), "run 1 buys a tower")
	check(run.spend_gold(2, "reroll"), "run 1 buys a reroll")
	check(run.complete_level(), "run 1 clears level 1")
	check_eq_int(run.level_number(), 2, "run 1 reached level 2")
	_step(run, "b_run_1_level_2")
	_leak(run, 3)
	_step(run, "b_run_1_wounded")
	_leak(run, 7)
	_step(run, "b_run_1_defeated")
	check(run.is_defeated(), "run 1 is defeated")

	var before: Dictionary = run.snapshot()
	var ledger_before: int = run.ledger().size()
	print("RUN_BEFORE " + JSON.stringify(before))
	check_eq_int(before["gold"], 14, "run 1 ends holding 14 gold")
	check_eq_int(before["hq"], 0, "run 1 ends with an empty HQ")
	check_eq_int(before["level"], 2, "run 1 ended on level 2")

	# Second run: every run-scoped value must reset, not inherit.
	var started: bool = run.start(3, 10, 10)
	var after: Dictionary = run.snapshot()
	print("RUN_AFTER " + JSON.stringify(after))
	print("RUN_RESET " + JSON.stringify({
		"gold_before": before["gold"],
		"gold_after": after["gold"],
		"hq_before": before["hq"],
		"hq_after": after["hq"],
		"level_before": before["level"],
		"level_after": after["level"],
		"status_before": before["status"],
		"status_after": after["status"],
		"ledger_entries_before": ledger_before,
		"ledger_entries_after": run.ledger().size(),
	}))

	check(started, "a second run starts after a defeat")
	check_eq_int(after["gold"], 10, "gold reset to the starting value, not inherited")
	check_eq_int(after["hq"], 10, "HQ reset to full, not inherited")
	check_eq_int(after["hq_max"], 10, "the HQ maximum is unchanged")
	check_eq_int(after["level"], 1, "the level index reset")
	check(after["status"] == "in_progress", "the second run is in progress")
	check(after["end_reason"] == "", "the previous run's end reason is cleared")
	check_eq_int(run.ledger().size(), 1, "the ledger restarted with the new run")

	# Restarting a live run is refused, so a restart cannot refill the purse.
	check(run.spend_gold(4, "tower"), "the second run can spend its own gold")
	check_eq_int(run.gold(), 6, "second-run balance after a purchase")
	var refused_restart: bool = run.start(3, 10, 10)
	print("RUN_REFUSED " + run.last_refusal())
	check(not refused_restart, "starting a run while one is in progress is refused")
	check(
		run.last_refusal().find("already in progress") != -1,
		"the refusal says a run is already in progress"
	)
	check_eq_int(run.gold(), 6, "a refused restart did not refill the purse")
	check(run.is_in_progress(), "the live run survived the refused restart")
	_print_ledger(run, "planted_failure_b_second_run")


# --- case 4: nothing persists (DoD 5) --------------------------------------

func _case_no_save_file() -> void:
	print("RUN_CASE no_save_file_is_written_by_a_run")
	var user_dir := ProjectSettings.globalize_path("user://")
	var before := _user_files()
	print("RUN_SAVE_ROOT " + JSON.stringify({"user_dir": user_dir, "files": before}))

	# Drive one run to victory and one to defeat, so anything that persisted on
	# either ending would have had its chance to write.
	var won: RefCounted = RunStateScript.new()
	won.start(2, 10)
	won.damage_hq(4)
	won.complete_level()
	won.complete_level()
	check(won.is_victory(), "the first probe run reached victory")

	var lost: RefCounted = RunStateScript.new()
	lost.start(2, 10)
	lost.damage_hq(10)
	check(lost.is_defeated(), "the second probe run reached defeat")

	var after := _user_files()
	print("RUN_SAVE_SCAN " + JSON.stringify({
		"user_dir": user_dir,
		"before": before,
		"after": after,
		"unchanged": before == after,
	}))

	# Persistence is deliberately deferred to G3; a file here would be a scope
	# breach, so absence is asserted rather than assumed.
	check(before == after, "a whole run wrote no file to user://")
	for candidate in SAVE_CANDIDATES:
		check(
			not FileAccess.file_exists(candidate),
			"no save file at %s" % candidate
		)


# --- helpers ---------------------------------------------------------------

func _earn_kills(run: RefCounted, count: int) -> void:
	for i in maxi(count, 0):
		run.add_gold(RunStateScript.GOLD_PER_KILL, "kill")


func _leak(run: RefCounted, count: int) -> void:
	for i in maxi(count, 0):
		run.damage_hq(1, "leak")


func _step(run: RefCounted, step: String) -> void:
	print("RUN_STEP " + JSON.stringify({"step": step, "state": run.snapshot()}))


func _print_ledger(run: RefCounted, label: String) -> void:
	print("RUN_LEDGER " + JSON.stringify({"run": label, "entries": run.ledger()}))


## The ledger must be an audit trail, not decoration: its balances have to match
## the gold the object reports, and its deltas have to sum to that same number.
func _check_ledger_reconciles(run: RefCounted, label: String) -> void:
	var entries: Array = run.ledger()
	var running := 0
	var consistent := true
	for entry in entries:
		running += int(entry["delta"])
		if int(entry["balance"]) != running:
			consistent = false
	check(consistent, "%s: every ledger balance equals the running total" % label)
	check(
		running == run.gold(),
		"%s: ledger deltas sum to the gold in hand (%d vs %d)" % [label, running, run.gold()]
	)


func _user_files() -> Array:
	var files: Array = Array(DirAccess.get_files_at("user://"))
	files.sort()
	return files


func check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
	return condition


func check_eq_int(actual, expected: int, message: String) -> bool:
	_checks += 1
	if int(actual) != expected:
		_failures.append("%s: expected %d, got %d" % [message, expected, int(actual)])
		return false
	return true


func _finish() -> void:
	if _checks == 0 and _failures.is_empty():
		_failures.append("the self-test recorded no checks")
	check(_checks >= MIN_CHECK_COUNT, "at least one check ran")

	var passed := _failures.is_empty()
	print("RUN_SELF_TEST " + JSON.stringify({
		"name": "run_state",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))

	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("RUN_FAILURE " + f)
	quit(1)
