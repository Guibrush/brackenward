class_name Hq
extends Node2D

## The thing the lane leads to.
##
## `health()`, `health_changed` and `seed_health()` are the whole surface: the
## HUD and the arena watch the first two, and `seed_health()` is the only door
## that moves the number.
##
## T-0045: a level's HQ is the **view** of the run's HQ health. `RunState` owns
## the value for the whole run - it is what survives from one level to the next -
## and this node shows it for the level being played. The arena seeds it from
## `RunState.hq_health()` when a level opens and re-seeds it after every
## `RunState.damage_hq()` / `heal_hq()`, so the node's counter and the run's
## cannot drift apart, and 7 of 10 at the end of one level is 7 of 10 at the start
## of the next.
##
## There is deliberately no `take_damage()` here any more: damage arithmetic lives
## in `RunState.damage_hq()`, which is also what ends a run at zero. A second
## damage path in the node would be a second owner of the same number.
##
## With no run at all (a bare scene - how every gate before T-0045 drove this
## node) it starts at `max_health` and is simply never seeded. `depleted` is
## emitted once, when seeding drops the health to zero.

signal health_changed(current: int, maximum: int)
signal depleted

## Exported so a designer can retune the slice without touching code. Placeholder
## value for T-0025; the real number is a design/systems decision. A run carries
## its own maximum (`RunState.hq_max_health()`), and seeding replaces this value
## with the run's, so the two agree instead of competing.
@export var max_health: int = 10

var _health: int = 0


func _ready() -> void:
	_health = maxi(max_health, 0)
	health_changed.emit(_health, max_health)


func health() -> int:
	return _health


func is_depleted() -> bool:
	return _health <= 0


## Shows `health` of `maximum`; a `maximum` of -1 keeps the current one. Health
## is clamped to `[0, maximum]`, and a drop to zero emits `depleted` exactly once.
##
## The two callers are "a level just opened" and "the run's health changed". Both
## have the run state in hand, which is why this takes a value rather than an
## amount of damage.
func seed_health(health: int, maximum: int = -1) -> void:
	var cap := maxi(max_health if maximum < 0 else maximum, 0)
	var seeded := clampi(health, 0, cap)
	var had_health := _health > 0
	max_health = cap
	_health = seeded
	health_changed.emit(_health, max_health)
	if _health == 0 and had_health:
		depleted.emit()
