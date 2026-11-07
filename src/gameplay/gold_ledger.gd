class_name GoldLedger
extends Node

## A **view** of the run's gold for one level's scene (T-0036; redefined by
## T-0045).
##
## It holds no balance. `RunState` owns the only gold, because a run outlives a
## level and gold is spent between levels; this node is the adapter between that
## object and the scene that has to show the number:
##
##   * `bind_run()` points it at the run the arena was given (or created). Until
##     then it is a view of nothing: `gold()` is 0 and every mutation is refused
##     with a printed line, rather than inventing a balance of its own.
##   * `earn()` / `try_spend()` forward to `RunState.add_gold()` /
##     `RunState.spend_gold()` and still print one `GOLD_LEDGER` line per attempt,
##     so the arithmetic stays readable in a headless log exactly as it was before
##     the run existed.
##   * `gold()` reads the run, and `changed` re-emits the run's `gold_changed`,
##     so the scene cannot show a balance different from the one that will be
##     carried into the next level.
##
## Why a view rather than a deletion: every caller and every log reader uses the
## `GOLD_LEDGER` lines, and `scenes/main.tscn` wires this node as `Wallet`. A view
## keeps both while removing the duplicate balance, which was the actual defect.
## `total_earned()` / `total_spent()` are this view's own counters of the calls
## that passed through it - they are not gold. The authoritative history is
## `RunState.ledger()`.

signal changed(gold: int)

var _run: RunState = null
var _total_earned: int = 0
var _total_spent: int = 0


## Points this view at `run`. Binding a second run moves the view; the balance
## moves with it, because the balance was never stored here.
func bind_run(run: RunState) -> void:
	if _run != null and _run.gold_changed.is_connected(_on_run_gold_changed):
		_run.gold_changed.disconnect(_on_run_gold_changed)
	_run = run
	if _run != null and not _run.gold_changed.is_connected(_on_run_gold_changed):
		_run.gold_changed.connect(_on_run_gold_changed)


func run() -> RunState:
	return _run


func is_bound() -> bool:
	return _run != null


func gold() -> int:
	return _run.gold() if _run != null else 0


func total_earned() -> int:
	return _total_earned


func total_spent() -> int:
	return _total_spent


func can_afford(amount: int) -> bool:
	return _run != null and amount >= 0 and _run.can_afford(amount)


## Adds `amount` to the run and returns the balance afterwards. A non-positive
## amount changes nothing and returns the current balance, so a zero-reward kill
## cannot pad the accounting.
func earn(amount: int, reason: String) -> int:
	var before := gold()
	if _run == null:
		_print_refused(reason, amount, "no run is bound")
		return before
	if amount <= 0:
		_print_change(reason, 0, before, true)
		return before
	var added := _run.add_gold(amount, reason)
	if added == 0:
		# The run refused it - a run that is over pays nothing. The run's own
		# sentence is the reason, because it knows why.
		_print_refused(reason, amount, _run.last_refusal())
		return gold()
	_total_earned += added
	_print_change(reason, added, before, true)
	return gold()


## Takes `amount` from the run and returns true when it was affordable. On
## refusal the balance is untouched and the line says why, so "not enough gold"
## is visible in the same place as every other economy event.
func try_spend(amount: int, reason: String) -> bool:
	var before := gold()
	if _run == null:
		_print_refused(reason, -amount, "no run is bound")
		return false
	if amount <= 0:
		# A free action is allowed; it still prints, because a cost of zero is a
		# tuning mistake worth seeing.
		_print_change(reason, 0, before, true)
		return true
	if not _run.spend_gold(amount, reason):
		_print_refused(reason, -amount, _run.last_refusal())
		return false
	_total_spent += amount
	_print_change(reason, -amount, before, true)
	return true


func _print_change(reason: String, delta: int, before: int, ok: bool) -> void:
	print("GOLD_LEDGER " + JSON.stringify({
		"reason": reason,
		"amount": delta,
		"gold_before": before,
		"gold_after": gold(),
		"total_earned": _total_earned,
		"total_spent": _total_spent,
		"ok": ok,
	}))


func _print_refused(reason: String, amount: int, why: String) -> void:
	print("GOLD_LEDGER " + JSON.stringify({
		"reason": reason,
		"amount": amount,
		"gold_before": gold(),
		"gold_after": gold(),
		"ok": false,
		"why": why,
	}))


func _on_run_gold_changed(current: int, _delta: int) -> void:
	changed.emit(current)
