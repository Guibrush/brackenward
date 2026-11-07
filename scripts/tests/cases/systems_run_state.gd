extends "res://scripts/tests/lib/suite.gd"

## Headless proof for `src/systems/run_state.gd` — T-0043 DoD items 2-6, under
## `docs/adr/0006-run-level-count.md`, now run by the suite instead of by hand.
##
##     powershell -NoProfile -File scripts/tests/run.ps1 -Filter systems_run_state
##
## Pure logic: no scene and no frames, so this case replaces the harness's scene
## boot (`_boot`) with a direct `run_case()`. Every assertion below is the one the
## selftest at the old `src/systems/tests/run_state_selftest.gd` made, unchanged.
## The harness owns the accounting: inherited `check()` / `check_eq_int()` count
## and record, and the inherited `_finish()` prints the single `TEST_RESULT` line
## and sets the exit code, failing a case that records no checks.
##
## ADR-0006 shape: a run has no level total. Every case here drives the run by
## *completions* (`complete_level()`), and victory comes from `win_run()` rather
## than from reaching a number. Nothing in this file hands `start()` a count.
##
## The case reports the same 116 checks the selftest reported: the selftest's
## closing "at least one check ran" tally is kept at the end of `run_case()` (see
## the comment there) instead of being replaced by the harness's uncounted
## equivalent.

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


func case_name() -> String:
	return "run state: completions, victory refusal, defeat and reset hold"


## Pure logic, so there is no arena to boot: this replaces the harness's scene
## load with the case itself. The single result line, the exit code and the
## zero-check guard are still the base's `_finish()`.
func _boot() -> void:
	run_case()
	_finish()


func run_case() -> void:
	_case_completion_sequence()
	_case_planted_failure_a()
	_case_planted_failure_b()
	_case_defeat_and_second_run()
	_case_no_save_file()
	# The selftest's own closing tally, kept so the count is unchanged. The
	# harness also fails a case that recorded no checks, so this is a second
	# guard rather than the only one.
	check(_checks >= MIN_CHECK_COUNT, "at least one check ran")


# --- case 1: three levels, driven by completions (DoD 2) --------------------

func _case_completion_sequence() -> void:
	print("RUN_CASE three_level_sequence_driven_by_completions_gold_in_gold_spent_hq_carried")
	var run: RunState = RunStateScript.new()
	var sequence: Array = []

	check(run.start(10, RunStateScript.STARTING_GOLD), "a run starts from HQ 10 and 10 gold")
	_step(run, "run_start")
	check_eq_int(run.level_index(), 0, "no level has been completed at the start")
	check_eq_int(run.level_number(), 1, "the level in play is level 1")
	check_eq_int(run.gold(), 10, "starting gold")
	check_eq_int(run.hq_health(), 10, "starting HQ")

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
	sequence.append(run.level_index())
	_step(run, "level_1_cleared")
	check_eq_int(run.level_index(), 1, "one level completed")
	check_eq_int(run.gold(), 10, "level-clear gold paid on top of the balance")
	check_eq_int(run.hq_health(), 8, "HQ carried into level 2")
	check_eq_int(run.level_number(), 2, "the level in play is level 2")
	check(run.is_in_progress(), "clearing a level never ends a run on its own")

	# --- level 2
	_earn_kills(run, 4)
	check(run.spend_gold(5, "upgrade"), "an upgrade can be bought for 5")
	_leak(run, 1)
	check_eq_int(run.hq_health(), 7, "HQ after three leaks across two levels")
	check(run.complete_level(), "level 2 clears")
	sequence.append(run.level_index())
	_step(run, "level_2_cleared")
	check_eq_int(run.level_index(), 2, "two levels completed")
	check_eq_int(run.gold(), 14, "level 2 paid its clear gold too")
	check_eq_int(run.hq_health(), 7, "HQ carried into level 3")
	check_eq_int(run.level_number(), 3, "the level in play is level 3")

	# --- level 3: the boss's level. Complete it, then the map wins the run.
	_earn_kills(run, 2)
	check(run.spend_gold(8, "tower"), "a tower can be bought for 8")
	_step(run, "level_3_spent")
	check(run.complete_level(), "the boss's level clears")
	sequence.append(run.level_index())
	_step(run, "boss_level_cleared")
	check_eq_int(run.level_index(), 3, "three levels completed")
	check(run.is_in_progress(), "clearing the boss's level does not win the run by itself")

	check(run.win_run("the boss node was completed"), "win_run() wins the run")
	_step(run, "run_completed")

	check(run.is_victory(), "the run is won by win_run(), not by a level number")
	check(run.is_over(), "a won run is over")
	check(not run.is_defeated(), "a won run is not a defeat")
	check(run.end_reason() != "", "a won run records why it ended")
	check(run.end_reason().find("boss") != -1, "the end reason carries the map's reason")
	check_eq_int(run.gold(), 13, "gold left at victory")
	check_eq_int(run.level_index(), 3, "the completion count is unchanged by the win")
	check_eq_int(run.hq_health(), 7, "HQ left at victory")
	check_eq_int(run.hq_max_health(), 10, "the HQ maximum never changed")

	print("RUN_SEQUENCE " + JSON.stringify({
		"case": "three_level_sequence",
		"level_index_after_each_completion": sequence,
		"note": "ADR-0006: the index advances once per completion and has no total",
	}))
	_print_ledger(run, "three_level_sequence")
	_check_ledger_reconciles(run, "three_level_sequence")
	print("RUN_SUMMARY " + JSON.stringify({
		"note": PLACEHOLDER,
		"gold_in": 10 + 3 + 5 + 4 + 5 + 2 + 5,
		"gold_spent": 6 + 2 + 5 + 8,
		"gold_left": run.gold(),
		"hq_start": 10,
		"hq_carried": [8, 7, 7],
		"levels_completed": run.level_index(),
		"status": run.status_name(),
	}))


# --- case 2: planted failure A (DoD 3) --------------------------------------

func _case_planted_failure_a() -> void:
	print("RUN_CASE planted_failure_a_completing_a_level_after_win_run_is_refused")
	var run: RunState = RunStateScript.new()
	run.start(10, 10)
	_earn_kills(run, 1)

	check(run.complete_level(), "level 1 clears normally")
	check(run.win_run("the boss node was completed"), "the run is won")
	check(run.is_victory(), "the run reports victory")

	var index_at_win: int = run.level_index()
	var gold_at_win: int = run.gold()
	var ledger_at_win: int = run.ledger().size()
	print("RUN_WON " + JSON.stringify({
		"level_index": index_at_win,
		"level_number": run.level_number(),
		"gold": gold_at_win,
		"status": run.status_name(),
		"end_reason": run.end_reason(),
	}))

	# The planted failure: ask to complete one more level on a won run. It must be
	# refused, say why, and leave the completion count exactly where it was.
	var replayed: bool = run.complete_level()
	print("RUN_REFUSED " + run.last_refusal())
	check(not replayed, "completing a level after win_run() is refused")
	check(run.last_refusal() != "", "the refusal carries a reason")
	check(
		run.last_refusal().find("cannot complete the current level") != -1,
		"the refusal names the refused action"
	)
	check(run.last_refusal().find("completed") != -1, "the reason names the completed run")
	check(
		run.last_refusal().find("boss node was completed") != -1,
		"the reason carries the win reason the map gave"
	)
	check_eq_int(run.level_index(), index_at_win, "the level index did not move")
	check_eq_int(run.level_number(), index_at_win + 1, "the level in play did not move")
	check_eq_int(run.gold(), gold_at_win, "a refused advance pays no level-clear gold")
	check_eq_int(run.ledger().size(), ledger_at_win, "a refused advance writes no ledger entry")
	check(
		run.snapshot()["status"] == "completed",
		"the run is still completed after the refused advance"
	)
	check(run.is_victory(), "a refused advance does not undo the victory")

	# Nothing else reopens a won run either.
	check_eq_int(run.add_gold(5, "kill"), 0, "a won run cannot earn gold")
	check(not run.win_run("second win"), "a won run cannot be won twice")
	check_eq_int(run.damage_hq(1), 0, "a won run takes no damage")
	check(not run.can_complete_level(), "can_complete_level() agrees with the refusal")
	print("RUN_AFTER_REFUSAL " + JSON.stringify({
		"level_index": run.level_index(),
		"gold": run.gold(),
		"ledger_entries": run.ledger().size(),
		"status": run.status_name(),
	}))
	_print_ledger(run, "planted_failure_a")


# --- case 3: planted failure B (DoD 4) --------------------------------------

func _case_planted_failure_b() -> void:
	print("RUN_CASE planted_failure_b_a_store_stop_between_levels_does_not_advance_the_index")
	var run: RunState = RunStateScript.new()
	var advances: Array = []
	run.level_changed.connect(func(completed: int) -> void: advances.append(completed))

	check(run.start(10, 20), "the run starts")
	check(run.complete_level(), "level 1 clears")
	_leak(run, 3)

	# The map stops at a store node between two levels. The player buys and heals;
	# no level is played, so nothing here calls `complete_level()`.
	var before_store: Dictionary = {
		"level_index": run.level_index(),
		"level_number": run.level_number(),
		"gold": run.gold(),
		"hq": run.hq_health(),
		"level_changed_emissions": advances.size(),
	}
	check(run.spend_gold(4, "store_tower"), "the store sells a tower")
	check_eq_int(run.heal_hq(2), 2, "the store heals the HQ by 2")

	# `store` is a node type, not a level: RunState has no "visit a node" call at
	# all, which is the point - a stop that is not played cannot touch the index.
	var after_store: Dictionary = {
		"level_index": run.level_index(),
		"level_number": run.level_number(),
		"gold": run.gold(),
		"hq": run.hq_health(),
		"level_changed_emissions": advances.size(),
	}
	print("RUN_STORE_STOP " + JSON.stringify({
		"case": "planted_failure_b",
		"stop": "store",
		"level_index_before": before_store["level_index"],
		"level_index_after": after_store["level_index"],
		"before": before_store,
		"after": after_store,
		"index_unchanged": before_store["level_index"] == after_store["level_index"],
		"note": "ADR-0006: store/rest/treasure/event/boss_preview stops are not levels",
	}))

	check_eq_int(run.level_index(), 1, "the store stop left the level index at 1")
	check_eq_int(
		int(after_store["level_index"]) - int(before_store["level_index"]),
		0,
		"the level index is identical before and after the store stop"
	)
	check_eq_int(
		int(after_store["level_changed_emissions"]) - int(before_store["level_changed_emissions"]),
		0,
		"the store stop emitted no level_changed"
	)
	check_eq_int(after_store["level_number"], before_store["level_number"], "the level in play did not move")
	check_eq_int(after_store["gold"], before_store["gold"] - 4, "the store stop moved gold, not levels")
	check_eq_int(after_store["hq"], before_store["hq"] + 2, "the store stop moved HQ, not levels")

	# And the next real level counts exactly one, so the store left no residue.
	check(run.complete_level(), "level 2 clears after the store stop")
	check_eq_int(run.level_index(), 2, "the next completion advances the index by exactly one")
	check_eq_int(advances.size(), 3, "three emissions: the start reset plus two completions")
	check(
		str(advances) == "[0, 1, 2]",
		"emissions count completions only, never stops (%s)" % str(advances)
	)
	print("RUN_SEQUENCE " + JSON.stringify({
		"case": "planted_failure_b",
		"level_changed_emissions": advances,
		"level_index": run.level_index(),
	}))
	_print_ledger(run, "planted_failure_b")


# --- case 4: defeat, refusal, and the second-run reset ----------------------

func _case_defeat_and_second_run() -> void:
	print("RUN_CASE defeat_by_hq_and_second_run_resets_gold_hq_and_completions")
	var run: RunState = RunStateScript.new()
	run.start(10, 10)

	# A first run that accumulates real value and then loses.
	_earn_kills(run, 7)
	check(run.spend_gold(6, "tower"), "run 1 buys a tower")
	check(run.spend_gold(2, "reroll"), "run 1 buys a reroll")
	check(run.complete_level(), "run 1 clears level 1")
	check_eq_int(run.level_index(), 1, "run 1 completed one level")
	_step(run, "b_run_1_level_2")
	_leak(run, 3)
	_step(run, "b_run_1_wounded")
	_leak(run, 7)
	_step(run, "b_run_1_defeated")
	check(run.is_defeated(), "run 1 is defeated")
	check(run.is_over(), "a defeated run is over")
	print("RUN_ENDED " + JSON.stringify({
		"victory": run.is_victory(),
		"reason": run.end_reason(),
		"level": run.level_number(),
	}))

	var before: Dictionary = run.snapshot()
	var ledger_before: int = run.ledger().size()
	print("RUN_BEFORE " + JSON.stringify(before))
	check_eq_int(before["gold"], 14, "run 1 ends holding 14 gold")
	check_eq_int(before["hq"], 0, "run 1 ends with an empty HQ")
	check_eq_int(before["levels_completed"], 1, "run 1 ended with one level completed")
	check_eq_int(before["level"], 2, "run 1 ended with level 2 in play")

	# Advancing after a defeat is refused, with a reason, and pays nothing.
	var gold_at_defeat: int = run.gold()
	var advanced: bool = run.complete_level()
	print("RUN_REFUSED " + run.last_refusal())
	check(not advanced, "advancing after the defeat is refused")
	check(run.last_refusal().find("defeated") != -1, "the reason names the defeat")
	check(run.last_refusal().find("HQ reached zero") != -1, "the reason names the cause")
	check_eq_int(run.level_index(), 1, "a refused advance left the level index alone")
	check_eq_int(run.gold(), gold_at_defeat, "a refused advance pays no level-clear gold")
	check(not run.can_complete_level(), "can_complete_level() agrees with the refusal")

	# A defeat is not a victory path: `win_run()` cannot overturn it.
	check(not run.win_run("late victory"), "win_run() on a defeated run is refused")
	print("RUN_REFUSED " + run.last_refusal())
	check(run.is_defeated(), "the run is still defeated after the refused win")
	check_eq_int(run.heal_hq(5), 0, "a defeated run cannot be healed back to life")
	check_eq_int(run.damage_hq(1), 0, "a defeated run takes no further damage")

	# Second run: every run-scoped value must reset, not inherit.
	var started: bool = run.start(10, 10)
	var after: Dictionary = run.snapshot()
	print("RUN_AFTER " + JSON.stringify(after))
	print("RUN_RESET " + JSON.stringify({
		"gold_before": before["gold"],
		"gold_after": after["gold"],
		"hq_before": before["hq"],
		"hq_after": after["hq"],
		"levels_completed_before": before["levels_completed"],
		"levels_completed_after": after["levels_completed"],
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
	check_eq_int(after["levels_completed"], 0, "the completion count reset")
	check_eq_int(after["level"], 1, "the level in play reset to level 1")
	check(after["status"] == "in_progress", "the second run is in progress")
	check(after["end_reason"] == "", "the previous run's end reason is cleared")
	check_eq_int(run.ledger().size(), 1, "the ledger restarted with the new run")

	# Restarting a live run is refused, so a restart cannot refill the purse.
	check(run.spend_gold(4, "tower"), "the second run can spend its own gold")
	check_eq_int(run.gold(), 6, "second-run balance after a purchase")
	var refused_restart: bool = run.start(10, 10)
	print("RUN_REFUSED " + run.last_refusal())
	check(not refused_restart, "starting a run while one is in progress is refused")
	check(
		run.last_refusal().find("already in progress") != -1,
		"the refusal says a run is already in progress"
	)
	check_eq_int(run.gold(), 6, "a refused restart did not refill the purse")
	check(run.is_in_progress(), "the live run survived the refused restart")
	_print_ledger(run, "defeat_and_second_run")


# --- case 5: nothing persists (DoD 6) --------------------------------------

func _case_no_save_file() -> void:
	print("RUN_CASE no_save_file_is_written_by_a_run")
	var user_dir := ProjectSettings.globalize_path("user://")
	var before := _user_files()
	print("RUN_SAVE_ROOT " + JSON.stringify({"user_dir": user_dir, "files": before}))

	# Drive one run to victory and one to defeat, so anything that persisted on
	# either ending would have had its chance to write.
	var won: RunState = RunStateScript.new()
	won.start(10)
	won.damage_hq(4)
	won.complete_level()
	won.complete_level()
	won.win_run()
	check(won.is_victory(), "the first probe run reached victory")

	var lost: RunState = RunStateScript.new()
	lost.start(10)
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

func _earn_kills(run: RunState, count: int) -> void:
	for i in maxi(count, 0):
		run.add_gold(RunStateScript.GOLD_PER_KILL, "kill")


func _leak(run: RunState, count: int) -> void:
	for i in maxi(count, 0):
		run.damage_hq(1, "leak")


func _step(run: RunState, step: String) -> void:
	print("RUN_STEP " + JSON.stringify({"step": step, "state": run.snapshot()}))


func _print_ledger(run: RunState, label: String) -> void:
	print("RUN_LEDGER " + JSON.stringify({"run": label, "entries": run.ledger()}))


## The ledger must be an audit trail, not decoration: its balances have to match
## the gold the object reports, and its deltas have to sum to that same number.
func _check_ledger_reconciles(run: RunState, label: String) -> void:
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
