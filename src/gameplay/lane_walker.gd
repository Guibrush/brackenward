class_name LaneWalker
extends Node2D

## One enemy walking a lane towards the HQ.
##
## It owns its own despawn: on reaching the end of the lane it emits `arrived`
## (the arena turns that into HQ damage) and then frees itself in `_despawn`.
##
## `has_arrived()` and `arrived_at_usec()` are read by the arena watchdog, not by
## gameplay. They exist so the arena can prove the despawn happened instead of
## trusting the `arrived` signal, which fires whether or not the enemy ever goes
## away (L-021: an unobserved failure is not evidence).
##
## Movement runs in `_physics_process` at a fixed 60 Hz tick, so lane timing does
## not depend on render framerate. Headless runs are uncapped, and a
## `_process`-driven walk would cover the lane in whatever time the idle loop
## happens to take.

signal arrived(walker: LaneWalker)

## Pixels per second along the lane. Placeholder value for T-0025: how long a
## wave takes to cross a level is a design decision (design/level, design/systems).
@export var move_speed: float = 200.0

var _points := PackedVector2Array()
var _segment_lengths: Array[float] = []
var _total_length: float = 0.0
var _distance: float = 0.0
var _arrived: bool = false
var _arrived_usec: int = 0


## Places the walker at the start of `points`. Called by the arena before (or
## immediately after) the walker enters the tree; the arena is the only owner of
## lane geometry, so the drawn line and the walked line cannot diverge.
func setup(points: PackedVector2Array) -> void:
	_points = points
	_segment_lengths.clear()
	_total_length = 0.0
	for i in maxi(_points.size() - 1, 0):
		var segment := _points[i].distance_to(_points[i + 1])
		_segment_lengths.append(segment)
		_total_length += segment
	_distance = 0.0
	_arrived = false
	_arrived_usec = 0
	position = _points[0] if _points.size() > 0 else Vector2.ZERO


func _physics_process(delta: float) -> void:
	if _arrived or _points.is_empty():
		return
	_distance = minf(_distance + move_speed * delta, _total_length)
	position = _point_at(_distance)
	if _distance >= _total_length:
		_arrive()


func has_arrived() -> bool:
	return _arrived


func arrived_at_usec() -> int:
	return _arrived_usec


## Stamps the arrival time the watchdog measures against, hands the arrival to
## the arena, then despawns.
func _arrive() -> void:
	_arrived = true
	_arrived_usec = Time.get_ticks_usec()
	arrived.emit(self)
	_despawn()


## Deliberately its own function: this is the handler T-0025 breaks on purpose to
## prove the arena watchdog can see a stuck enemy.
func _despawn() -> void:
	queue_free()


func _point_at(distance: float) -> Vector2:
	if _points.is_empty():
		return position
	if _segment_lengths.is_empty():
		return _points[0]
	var remaining := distance
	for i in _segment_lengths.size():
		var segment := _segment_lengths[i]
		if remaining <= segment or i == _segment_lengths.size() - 1:
			var t := 0.0 if segment <= 0.0 else clampf(remaining / segment, 0.0, 1.0)
			return _points[i].lerp(_points[i + 1], t)
		remaining -= segment
	return _points[_points.size() - 1]
