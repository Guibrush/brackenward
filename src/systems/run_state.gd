class_name RunState
extends RefCounted

## Lifecycle and currency for exactly one run.
##
## CONTRACT
## --------
## * A caller creates one `RunState` per run, calls `start()` once, and keeps the
##   reference for the life of that run. It is a plain object: not an autoload,
##   not a node, no global. The code that starts the run owns the instance, and
##   there is exactly one per run.
## * This object owns three pieces of mutable state and nothing else owns them:
##   how many levels the run has completed, the gold in hand, and the run's HQ
##   health. The level's `Hq` node is a per-level *view* of the same health, not a
##   second owner (see CALLERS MUST).
## * A run has **no level total** (ADR-0006). `level_index()` counts levels
##   *finished*; there is no constructor count, no "final level" and no progress
##   fraction here, because how many levels a run contains is a property of the
##   route the player takes. The map is the authority on progress.
## * Gold exists only inside a run, can never go below zero, is earned by the
##   caller (kills) and by `complete_level()` (level clear), and is spent through
##   `spend_gold()`. `start()` after a finished run resets gold and HQ instead of
##   inheriting them; `start()` during a live run is refused, so restarting is
##   never a way to top up.
## * A run ends in exactly one of two ways: `win_run()` (victory), or HQ reaching
##   zero at any point (defeat). `complete_level()` never ends a run by itself -
##   this object does not know which level is last, so whoever owns the map calls
##   `complete_level()` for the boss's level and then `win_run()`. Once over, every
##   mutation is refused and `last_refusal()` carries the reason; the level index
##   cannot advance and no level-clear gold is paid.
## * Nothing is written to disk. Meta-progression persistence is deferred to G3
##   (CHARTER, non-goals), so this object has no save path, no format version and
##   no dictionary round-trip. When persistence arrives it belongs to the save
##   system, which must version the format (eng/systems rule 3), not to this file.
##
## CALLERS MUST
## ------------
## * Read gold and HQ from here and nowhere else. To wire a level, seed the
##   level's `Hq` node from `hq_max_health()` and report every leak back through
##   `damage_hq()`; do not let the node's counter and this one drift apart.
## * Check the bool returned by every mutation, and surface `last_refusal()` to
##   the player or the log instead of ignoring it. A refusal is never silent:
##   it is stored and also emitted on `refused`.
## * Call `complete_level()` once per *played* level, and only for a level-type
##   node. A `store`, `rest`, `treasure`, `event` or boss-preview stop is not a
##   level and must not call it: the index would then count stops instead of
##   levels, which is the defect ADR-0006 removes. Those stops are the map's
##   business; they change gold and HQ at most, never the level index.
## * Call `win_run()` when the boss node is finished (after `complete_level()` for
##   that node's level). Nothing here caps how many levels came before it, so a
##   map that forgets the call leaves a live run standing on its boss.
## * Call `is_over()` before asking to advance. Advancement after the run ends is
##   a programmer error; it is refused loudly (a greppable `RUN_REFUSED` line on
##   stdout in a debug build) rather than asserted, because a stray UI event must
##   not crash a run in progress.
##
## No number in this file is real. Each is a PLACEHOLDER for T-0035
## (`docs/design/systems/economy.md`, `waves.md`) to replace; every one carries
## the marker so the replacement is a search, not a hunt.

enum Status { NOT_STARTED, IN_PROGRESS, COMPLETED, DEFEATED }

const STATUS_NAMES := ["not_started", "in_progress", "completed", "defeated"]

## PLACEHOLDER (T-0035 economy.md): gold in hand when a run begins.
const STARTING_GOLD := 10
## PLACEHOLDER (T-0035 economy.md): gold paid per enemy killed. The caller reads
## this constant and passes it to `add_gold()`; this file does not know what an
## enemy is.
const GOLD_PER_KILL := 1
## PLACEHOLDER (T-0035 economy.md): gold paid for clearing a level, awarded by
## `complete_level()` because clearing a level is a run transition.
const GOLD_PER_LEVEL_CLEAR := 5
## PLACEHOLDER (T-0035 economy.md): a run's HQ health when the caller has no
## better number. Matches `Hq.max_health`'s placeholder so the two agree.
const DEFAULT_HQ_MAX := 10
const MIN_HQ_MAX := 1

signal gold_changed(current: int, delta: int)
signal hq_changed(current: int, maximum: int)
## Emitted with the number of levels *completed* so far. There is no total to
## pair it with (ADR-0006): anything wanting progress against the route asks the
## map, which is the only object that knows the remaining layers.
signal level_changed(levels_completed: int)
signal run_ended(victory: bool, reason: String)
signal refused(reason: String)

var _status: int = Status.NOT_STARTED
## Levels finished this run. Not an index into a fixed list: ADR-0006 defines
## `level_index()` as this count, and only a completed level-type node moves it.
var _levels_completed: int = 0
var _gold: int = 0
var _hq: int = 0
var _hq_max: int = 0
var _end_reason: String = ""
var _last_refusal: String = ""
var _ledger: Array[Dictionary] = []


# --- lifecycle --------------------------------------------------------------

## Begins a run and resets every run-scoped value. Legal from NOT_STARTED, or
## from COMPLETED/DEFEATED (that is how a second run starts); refused while a run
## is in progress, because inheriting a live run's gold would make restarting a
## way to refill the purse.
##
## There is deliberately no level count (ADR-0006): a run's number of levels is a
## route outcome, decided after the run has begun, and the map owns it.
func start(hq_max: int = DEFAULT_HQ_MAX, starting_gold: int = STARTING_GOLD) -> bool:
	if _status == Status.IN_PROGRESS:
		return _refuse(
			"start a run", "a run is already in progress; finish or lose it first", true
		)
	if hq_max < MIN_HQ_MAX:
		return _refuse(
			"start a run",
			"HQ health must be at least %d, got %d" % [MIN_HQ_MAX, hq_max],
			true
		)
	if starting_gold < 0:
		return _refuse(
			"start a run", "starting gold cannot be negative, got %d" % starting_gold, true
		)

	_levels_completed = 0
	_hq_max = hq_max
	_hq = hq_max
	_gold = starting_gold
	_status = Status.IN_PROGRESS
	_end_reason = ""
	_last_refusal = ""
	_ledger.clear()
	_record("run_start", starting_gold)
	gold_changed.emit(_gold, starting_gold)
	hq_changed.emit(_hq, _hq_max)
	level_changed.emit(_levels_completed)
	return true


## Finishes one level-type node: pays the level-clear gold, then counts the level
## completed (gold and HQ carry untouched). It never ends the run - victory is the
## map's call through `win_run()` once the boss node has been finished (ADR-0006),
## so a run that stops calling this stays live until `win_run()` or defeat.
func complete_level() -> bool:
	if _status != Status.IN_PROGRESS:
		return _refuse(
			"complete the current level",
			"the run is %s (%s)" % [status_name(), _end_reason_or("no run started")],
			true
		)
	if _hq <= 0:
		# Defence in depth. `damage_hq()` already ends the run at zero, so this can
		# only be reached if state was tampered with, and advancing a run with no
		# HQ would be the exact continuation the charter forbids.
		return _refuse(
			"complete the current level", "the HQ is empty; a run with no HQ cannot advance", true
		)

	add_gold(GOLD_PER_LEVEL_CLEAR, "level_clear")
	_levels_completed += 1
	level_changed.emit(_levels_completed)
	return true


## Ends the run as a victory. The map calls this once the boss node's level has
## been completed; nothing here decides that, and nothing here counts the levels
## that came before. `reason` is free text for the end-of-run line ("the boss node
## was completed"); a blank reason gets the default sentence.
func win_run(reason: String = "") -> bool:
	if _status != Status.IN_PROGRESS:
		return _refuse(
			"win the run",
			"the run is %s (%s)" % [status_name(), _end_reason_or("no run started")],
			true
		)
	if _hq <= 0:
		# Same defence in depth as `complete_level()`: a run whose HQ is gone
		# cannot be won, because `damage_hq()` has already made it a defeat.
		return _refuse(
			"win the run", "the HQ is empty; a run with no HQ cannot be won", true
		)

	var why := reason if reason != "" else "the boss node was completed"
	_end_run(true, "%s after %d level(s) completed; the run is won" % [why, _levels_completed])
	return true


func end_reason() -> String:
	return _end_reason


func status() -> int:
	return _status


func status_name() -> String:
	return str(STATUS_NAMES[_status])


func is_in_progress() -> bool:
	return _status == Status.IN_PROGRESS


func is_over() -> bool:
	return _status == Status.COMPLETED or _status == Status.DEFEATED


func is_victory() -> bool:
	return _status == Status.COMPLETED


func is_defeated() -> bool:
	return _status == Status.DEFEATED


func can_complete_level() -> bool:
	return _status == Status.IN_PROGRESS and _hq > 0


# --- levels -----------------------------------------------------------------

## How many levels this run has **completed** (ADR-0006). Zero at the start; it
## moves only on `complete_level()`, so a store, rest, treasure, event or
## boss-preview stop leaves it exactly where it was.
func level_index() -> int:
	return _levels_completed


## One-based number of the level in play - the level that has not been completed
## yet, which makes it the number to show in a HUD and the number the ledger
## records. It is display arithmetic on a count, never a bound: there is no last
## level here (ADR-0006).
func level_number() -> int:
	return _levels_completed + 1


# --- gold -------------------------------------------------------------------

func gold() -> int:
	return _gold


func can_afford(amount: int) -> bool:
	return amount >= 0 and _gold >= amount


## Adds gold and returns the amount actually added (0 when refused). `source` is
## free text for the ledger: "kill", "level_clear", whatever the caller reports.
## This file does not know what any of them mean.
func add_gold(amount: int, source: String = "unspecified") -> int:
	if amount <= 0:
		_refuse(
			"add gold",
			"amount must be positive, got %d (spending goes through spend_gold)" % amount,
			true
		)
		return 0
	if _status != Status.IN_PROGRESS:
		_refuse("add gold", "the run is %s" % status_name(), true)
		return 0

	_gold += amount
	_record(source, amount)
	gold_changed.emit(_gold, amount)
	return amount


## Takes gold if the run is live and the balance covers it. `purpose` is free text
## for the ledger: "tower", "reroll", whatever the caller bought.
func spend_gold(amount: int, purpose: String = "unspecified") -> bool:
	if amount <= 0:
		return _refuse(
			"spend gold", "amount must be positive, got %d" % amount, true
		)
	if _status != Status.IN_PROGRESS:
		return _refuse("spend gold", "the run is %s" % status_name(), true)
	if _gold < amount:
		# Player-facing: not enough gold is normal play, not a bug. Refused and
		# recorded, but not a WARNING line (the caller should have asked
		# `can_afford()` first).
		return _refuse(
			"spend gold on %s" % purpose,
			"costs %d, only %d in hand" % [amount, _gold],
			false
		)

	_gold -= amount
	_record(purpose, -amount)
	gold_changed.emit(_gold, -amount)
	return true


## Every gold change this run, oldest first:
## `{"level": int, "kind": String, "delta": int, "balance": int}`. A copy, so a
## caller cannot rewrite history.
func ledger() -> Array:
	return _ledger.duplicate(true)


# --- HQ ---------------------------------------------------------------------

func hq_health() -> int:
	return _hq


func hq_max_health() -> int:
	return _hq_max


## Applies up to `amount` damage, floored at zero, and returns what was applied.
## Reaching zero ends the run as a defeat, exactly once.
func damage_hq(amount: int, source: String = "unspecified") -> int:
	if amount <= 0:
		_refuse("damage the HQ", "amount must be positive, got %d" % amount, true)
		return 0
	if _status != Status.IN_PROGRESS:
		_refuse("damage the HQ", "the run is %s" % status_name(), true)
		return 0

	var before := _hq
	_hq = maxi(_hq - amount, 0)
	var applied := before - _hq
	hq_changed.emit(_hq, _hq_max)
	if _hq == 0 and before > 0:
		_end_run(
			false, "HQ reached zero on level %d (%s)" % [level_number(), source]
		)
	return applied


## Restores up to `amount` health, never above the run's maximum. Between-level
## healing competes with upgrades for gold (CHARTER, run structure); the price is
## the caller's `spend_gold()`, not this call.
func heal_hq(amount: int) -> int:
	if amount <= 0:
		_refuse("heal the HQ", "amount must be positive, got %d" % amount, true)
		return 0
	if _status != Status.IN_PROGRESS:
		_refuse("heal the HQ", "the run is %s" % status_name(), true)
		return 0

	var before := _hq
	_hq = mini(_hq + amount, _hq_max)
	var applied := _hq - before
	if applied > 0:
		hq_changed.emit(_hq, _hq_max)
	return applied


# --- diagnostics ------------------------------------------------------------

## Why the most recent mutation was refused, or "" when none was. Never clear a
## refusal without showing it: a refused call is a call the player did not get.
func last_refusal() -> String:
	return _last_refusal


## Everything a HUD, a log line or a test wants to print, in one dictionary.
## `level` is the level in play; `levels_completed` is the run's progress. There
## is no total and no "final level" flag: ask the map (ADR-0006).
func snapshot() -> Dictionary:
	return {
		"status": status_name(),
		"level": level_number(),
		"levels_completed": _levels_completed,
		"gold": _gold,
		"hq": _hq,
		"hq_max": _hq_max,
		"end_reason": _end_reason,
		"last_refusal": _last_refusal,
	}


# --- internals --------------------------------------------------------------

func _end_run(victory: bool, reason: String) -> void:
	_status = Status.COMPLETED if victory else Status.DEFEATED
	_end_reason = reason
	run_ended.emit(victory, reason)


func _record(kind: String, delta: int) -> void:
	_ledger.append({
		"level": level_number(),
		"kind": kind,
		"delta": delta,
		"balance": _gold,
	})


## One place where refusals are worded, stored, emitted and (for programmer error)
## logged. Returns false so callers can `return _refuse(...)`.
##
## `loud` is for calls the contract forbids - advance after the run ended, begin a
## second run, a non-positive amount. Those are programmer errors, so they print in
## a development build and stay silent in a release build: loud where it is
## readable, harmless where a player could see it. Not-enough-gold is normal play,
## never loud; the caller puts that reason in the HUD.
func _refuse(action: String, why: String, loud: bool) -> bool:
	_last_refusal = "cannot %s: %s" % [action, why]
	refused.emit(_last_refusal)
	if loud and OS.is_debug_build():
		# One greppable line rather than push_warning: a warning's backtrace buries
		# the sentence, and this project reads stdout (L-035).
		print("RUN_REFUSED " + _last_refusal)
	return false


func _end_reason_or(fallback: String) -> String:
	return fallback if _end_reason == "" else _end_reason
