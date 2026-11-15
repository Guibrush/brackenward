class_name LaneWalker
extends Node2D

## One enemy walking a lane towards the HQ.
##
## It owns its own despawn: on reaching the end of the lane it emits `arrived`
## (the arena turns that into HQ damage) and then frees itself in `_despawn`.
## The same is true of death: `take_damage` emits `died` (the arena turns that
## into gold) and the node frees itself, so no corpse ever walks or shoots.
##
## `has_arrived()` and `arrived_at_usec()` are read by the arena watchdog, not by
## gameplay. They exist so the arena can prove the despawn happened instead of
## trusting the `arrived` signal, which fires whether or not the enemy ever goes
## away (L-021: an unobserved failure is not evidence).
##
## `is_alive()` is the contract towers check before every shot. A walker reaches
## zero health in the same physics frame in which its `died` handler runs, and is
## only freed at the end of that frame, so a tower that keeps a target across
## frames can hold a node that is valid but no longer alive. Towers must ask
## `is_alive()`, not `is_instance_valid()` alone (T-0036 DoD 4).
##
## Movement runs in `_physics_process` at a fixed 60 Hz tick, so lane timing does
## not depend on render framerate. Headless runs are uncapped, and a
## `_process`-driven walk would cover the lane in whatever time the idle loop
## happens to take.
##
## Drawing is the shipped static sprite for this kind and facing, at 1x, with the
## placeholder polygons in `scenes/enemy_walker.tscn` kept as the fallback for a
## kind with no file (T-0105). Art never touches health, speed, gold, arrival or
## targeting: it is read from `kind` and the movement direction and nothing else.

signal arrived(walker: LaneWalker)
signal died(walker: LaneWalker)

## Pixels per second along the lane. Placeholder value for T-0025: how long a
## wave takes to cross a level is a design decision (design/level, design/systems).
@export var move_speed: float = 200.0

@export_group("Health — PLACEHOLDER (T-0035 enemies.md)")
## Hit points. PLACEHOLDER for T-0036: 40 is chosen so that a tier-1 tower at
## 15 damage needs three hits, which is enough to observe firing and a cooldown
## without waiting. The real curve is design/systems work.
@export var max_health: int = 40
## Gold paid to the run when this walker dies. PLACEHOLDER; the economy table is
## `docs/design/systems/economy.md` (T-0035).
@export var gold_reward: int = 12

@export_group("Presentation — T-0105")
## Which enemy kind this walker is drawn as (`grunt`, `runner`, ...). The arena
## copies it from the wave line before `setup()`; a kind with no shipped art keeps
## the placeholder polygons.
@export var kind: StringName = &"grunt"
## The placeholder polygons in `scenes/enemy_walker.tscn`, resolved by path so no
## script hardcodes a node path. They are shown only when no sprite exists.
@export var outline_path: NodePath = ^"Outline"
@export var body_path: NodePath = ^"Body"
## The sprite node the art goes into. Same rule as the polygons: a path resolved
## at run time, so the scene can move the node without touching code.
@export var sprite_path: NodePath = ^"Sprite"
## Where a kind's shipped art lives. `%s` is the kind, then the facing
## (`south`, `west`, `east`, `north`); a kind with no file at this path falls back
## to the polygons.
@export var sprite_format: String = "res://assets/art/enemies/%s/idle/%s.png"

## The four facings a shipped sprite set carries. Movement picks one by dominant
## axis; a tie keeps the last facing, so a diagonal lane does not flicker.
const FACING_SOUTH := &"south"
const FACING_WEST := &"west"
const FACING_EAST := &"east"
const FACING_NORTH := &"north"

var _points := PackedVector2Array()
var _segment_lengths: Array[float] = []
var _total_length: float = 0.0
var _distance: float = 0.0
var _arrived: bool = false
var _arrived_usec: int = 0
var _alive: bool = false
var _health: int = 0
## The facing the current texture was chosen for. `south` until the lane has a
## direction to read, so a walker has art before its first physics tick.
var _facing: StringName = FACING_SOUTH
var _outline: CanvasItem = null
var _body: CanvasItem = null
var _sprite: Sprite2D = null
## True when the sprite carries this walker's look and the polygons are hidden.
var _art_shown: bool = false


func _ready() -> void:
	_bind_art_nodes()
	_apply_art()


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
	_alive = true
	_health = maxi(max_health, 1)
	position = _points[0] if _points.size() > 0 else Vector2.ZERO
	_update_facing(_direction_at(_distance))
	_apply_art()


func _physics_process(delta: float) -> void:
	if _arrived or not _alive or _points.is_empty():
		return
	_distance = minf(_distance + move_speed * delta, _total_length)
	position = _point_at(_distance)
	_update_facing(_direction_at(_distance))
	if _distance >= _total_length:
		_arrive()


func has_arrived() -> bool:
	return _arrived


func arrived_at_usec() -> int:
	return _arrived_usec


func health() -> int:
	return _health


## The contract every tower checks before it fires. False once the walker has
## died or reached the lane end, whichever came first.
func is_alive() -> bool:
	return _alive and not _arrived


## How far along the lane this walker is, 0.0 at the spawn point and 1.0 at the
## HQ. This is what "first" and "last" in the targeting rules mean (T-0036).
func lane_progress() -> float:
	if _total_length <= 0.0:
		return 0.0
	return clampf(_distance / _total_length, 0.0, 1.0)


## Applies up to `amount` damage and returns the points actually lost, mirroring
## `Hq.take_damage`. Returns 0 - the wrong number to hand gold from - when the
## walker is already dead or has already arrived, so a tower shooting a corpse
## cannot mint a second `died` signal.
func take_damage(amount: int) -> int:
	if amount <= 0 or not is_alive():
		return 0
	var before := _health
	_health = maxi(_health - amount, 0)
	var applied := before - _health
	if _health == 0:
		_die()
	return applied


## Stamps the arrival time the watchdog measures against, hands the arrival to
## the arena, then despawns.
func _arrive() -> void:
	_arrived = true
	_arrived_usec = Time.get_ticks_usec()
	_alive = false
	arrived.emit(self)
	_despawn()


## Reaching zero health. The signal fires before the free so a listener can read
## the walker; the node itself is gone at the end of the frame, which is why
## towers check `is_alive()` rather than `is_instance_valid()` (T-0036 DoD 4).
func _die() -> void:
	_alive = false
	died.emit(self)
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


## The unit direction of the segment `distance` falls in, zero when the lane has no
## direction to read. Walks the same segments as `_point_at`, because the facing is
## the facing of the ground under the feet and never an interpolated blend.
func _direction_at(distance: float) -> Vector2:
	if _points.size() < 2 or _segment_lengths.is_empty():
		return Vector2.ZERO
	var remaining := distance
	for i in _segment_lengths.size():
		var segment := _segment_lengths[i]
		if remaining <= segment or i == _segment_lengths.size() - 1:
			var step := _points[i + 1] - _points[i]
			return Vector2.ZERO if step.is_zero_approx() else step.normalized()
		remaining -= segment
	return Vector2.ZERO


# --- art (T-0105) ----------------------------------------------------------

## Resolves the drawing nodes by exported path. Called from `_ready`, and again by
## `_apply_art()` when a walker is drawn before it entered the tree.
func _bind_art_nodes() -> void:
	_outline = get_node_or_null(outline_path) as CanvasItem
	_body = get_node_or_null(body_path) as CanvasItem
	_sprite = get_node_or_null(sprite_path) as Sprite2D


## Picks the drawing for this walker's kind and facing: the shipped idle sprite
## when one exists, the placeholder polygons when it does not. Art is drawn at 1x,
## never scaled, so a 16px grunt and a 96px boss are the same node.
func _apply_art() -> void:
	if _sprite == null:
		_bind_art_nodes()
	var texture: Texture2D = null
	var art_path: String = sprite_format % [String(kind), String(_facing)]
	if ResourceLoader.exists(art_path):
		texture = load(art_path) as Texture2D
	_art_shown = texture != null
	if _sprite != null:
		_sprite.texture = texture
		_sprite.visible = _art_shown
	if _outline != null:
		_outline.visible = not _art_shown
	if _body != null:
		_body.visible = not _art_shown


## Re-reads the facing from the movement direction and redraws only when it
## changed, so a walk down a straight lane loads one texture and not sixty a
## second.
func _update_facing(direction: Vector2) -> void:
	var facing := _facing_for(direction, _facing)
	if facing == _facing:
		return
	_facing = facing
	_apply_art()


## The dominant axis of `direction` as a facing. A tie - including a zero
## direction - keeps `current`, which is why the last facing survives a corner
## whose two axes are equal.
func _facing_for(direction: Vector2, current: StringName) -> StringName:
	if absf(direction.x) > absf(direction.y):
		return FACING_EAST if direction.x > 0.0 else FACING_WEST
	if absf(direction.y) > absf(direction.x):
		return FACING_SOUTH if direction.y > 0.0 else FACING_NORTH
	return current


## The facing this walker is drawn with. Read by the frame evidence, not by
## gameplay.
func facing() -> StringName:
	return _facing


## True when the sprite is carrying this walker's look and the polygons are
## hidden.
func art_shown() -> bool:
	return _art_shown

