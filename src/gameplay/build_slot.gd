class_name BuildSlot
extends Node2D

## A buildable tile (T-0036): one 32 px square of ground a tower may stand on.
##
## The slot is a marker, not a controller. It knows where it is and whether a
## tower stands on it; `Arena` owns the rules (phase lock, gold, lane exclusion)
## and the tower itself. Keeping the slot dumb means the rule that refuses a
## placement has exactly one implementation, in the arena, where the refusal is
## printed with its reason.
##
## Slots are placed by hand in `scenes/main.tscn`; the arena discovers them by
## type, so adding a tile is a scene edit and never a code change.

## How close a pointer must be, in pixels, for a click on bare ground to snap to
## this tile rather than count as a miss. PLACEHOLDER: half a tile plus a little
## slack, so it feels like "the tile" rather than "the exact pixel".
@export var snap_radius_px: float = 24.0
## Tower standing on this tile, or null. Owned by the arena; the slot only holds
## the reference so a click can find the tower without scanning the tree.
var tower: Tower = null


func is_free() -> bool:
	return tower == null or not is_instance_valid(tower)


func world_position() -> Vector2:
	return global_position


func attach(new_tower: Tower) -> void:
	tower = new_tower


func detach() -> Tower:
	var previous := tower
	tower = null
	return previous


## Distance from a world point to this tile's centre, used by the arena to snap a
## click to the nearest free tile.
func distance_to_point(point: Vector2) -> float:
	return world_position().distance_to(point)
