class_name Hq
extends Node2D

## The thing the lane leads to.
##
## Health changes only through `take_damage`, and that call returns the damage it
## actually applied. That is deliberate: it lets the arena assert "one arrival
## costs exactly one point" instead of assuming it, so a double-damage bug shows
## up as an error line rather than as a suspiciously fast defeat.
##
## Nothing here knows about levels, runs, or healing. HQ health carrying across a
## run (CHARTER, run structure) is a later system; this node is only the counter.

signal health_changed(current: int, maximum: int)
signal depleted

## Exported so a designer can retune the slice without touching code. Placeholder
## value for T-0025; the real number is a design/systems decision.
@export var max_health: int = 10

var _health: int = 0


func _ready() -> void:
	_health = max_health
	health_changed.emit(_health, max_health)


func health() -> int:
	return _health


func is_depleted() -> bool:
	return _health <= 0


## Applies up to `amount` damage, floored at zero. Returns the points actually
## lost, which is 0 once the HQ is already empty.
func take_damage(amount: int) -> int:
	if amount <= 0:
		return 0
	var before := _health
	_health = maxi(_health - amount, 0)
	health_changed.emit(_health, max_health)
	if _health == 0 and before > 0:
		depleted.emit()
	return before - _health
