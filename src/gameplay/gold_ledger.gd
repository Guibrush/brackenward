class_name GoldLedger
extends Node

## The run's gold, as far as gameplay can see it (T-0036).
##
## This is deliberately the *smallest* thing that lets towers be placed and sold
## without inventing an economy: one integer, earns, and spends that can refuse.
## Run-scoped currency - gold lost at the end of a run, gold earned on level
## completion, spending between levels - is `eng/systems` work (T-0037), and that
## run state replaces this ledger through `Arena`'s `ledger_path` rather than
## editing it. Until then this node is the placeholder and it prints every change
## so a headless run can show the arithmetic instead of asserting it.
##
## Every mutation prints one `GOLD_LEDGER` line, refusals included: a spend that
## failed is a fact about the run, and a ledger that only records successes
## cannot explain why a placement did not happen.

signal changed(gold: int)

## Gold the run starts with. PLACEHOLDER; `docs/design/systems/economy.md`
## (T-0035) replaces it.
@export var starting_gold: int = 120

var _gold: int = 0
var _total_earned: int = 0
var _total_spent: int = 0


func _ready() -> void:
	_gold = maxi(starting_gold, 0)


func gold() -> int:
	return _gold


func total_earned() -> int:
	return _total_earned


func total_spent() -> int:
	return _total_spent


func can_afford(amount: int) -> bool:
	return amount <= _gold


## Adds `amount` and returns the new balance. A non-positive amount changes
## nothing and returns the current balance, so a zero-reward kill cannot pad the
## accounting.
func earn(amount: int, reason: String) -> int:
	if amount <= 0:
		print("GOLD_LEDGER " + JSON.stringify({
			"reason": reason,
			"amount": amount,
			"gold_before": _gold,
			"gold_after": _gold,
			"ok": false,
			"why": "nothing to earn",
		}))
		return _gold
	var before := _gold
	_gold += amount
	_total_earned += amount
	_print_change(reason, amount, before, true)
	changed.emit(_gold)
	return _gold


## Deducts `amount` and returns true when it was affordable. On refusal the
## balance is untouched and the line says why, so "not enough gold" is visible in
## the same place as every other economy event.
func try_spend(amount: int, reason: String) -> bool:
	if amount <= 0:
		# A free action is allowed; it still prints, because a cost of zero is a
		# tuning mistake worth seeing.
		_print_change(reason, 0, _gold, true)
		return true
	if amount > _gold:
		print("GOLD_LEDGER " + JSON.stringify({
			"reason": reason,
			"amount": -amount,
			"gold_before": _gold,
			"gold_after": _gold,
			"ok": false,
			"why": "not enough gold",
		}))
		return false
	var before := _gold
	_gold -= amount
	_total_spent += amount
	_print_change(reason, -amount, before, true)
	changed.emit(_gold)
	return true


func _print_change(reason: String, delta: int, before: int, ok: bool) -> void:
	print("GOLD_LEDGER " + JSON.stringify({
		"reason": reason,
		"amount": delta,
		"gold_before": before,
		"gold_after": _gold,
		"total_earned": _total_earned,
		"total_spent": _total_spent,
		"ok": ok,
	}))
