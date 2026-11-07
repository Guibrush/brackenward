class_name Tower
extends Node2D

## A placeable tower (T-0036): one build tile, three tiers, one cooldown, one
## targeting rule.
##
## The tower owns only what is about the tower: what it costs, what it does at
## each tier, and how it fires. It does not own gold, phases, tiles, or the enemy
## list - `Arena` owns those and hands the tower its candidates through
## `candidate_source`. A tower with no source fires at nothing, which is what a
## tower dropped into a scene with no arena should do.
##
## **Firing validates the target, every shot.** `Targeting.pick()` chooses a
## target; it does not grant permission to damage it (`targeting.gd` says so at
## the top). Selection is checked, then the shot is checked again immediately
## before `take_damage`, because a walker reaches zero health in the frame its
## `died` handler runs and is freed at the end of that frame - a tower holding a
## target across frames can hold a node that is still valid but no longer alive
## (`lane_walker.gd`: "Towers must ask `is_alive()`, not `is_instance_valid()`
## alone"). A dead target produces a printed hold, never a shot and never a crash
## (T-0036 DoD 4: planted failure B).
##
## Time comes in through `tick(delta)`. `_physics_process` is the only caller in
## the game, so a tower fires on the fixed 60 Hz tick and not on render
## framerate; a headless harness drives the same `tick` with fixed steps instead
## of waiting in real time, so the cooldown is measured in game time in both.
##
## T-0045: a tower node is the **view** a tower instance gets while it stands on
## the map. `Inventory` owns the tower's `tier` - that is what survives being
## picked up and put down again - so `bind_instance()` copies it here and
## `adopt_tier()` accepts a tier the inventory has already granted. Placement is
## free: the price of a tower is a store decision, not a build-time spend, so
## `invested()` counts the upgrades paid for this tower and nothing else. Upgrades
## carried by the instance have no combat effect yet; they are identity and
## loadout until the design tables land.
##
## Every number below is a PLACEHOLDER: the tier tables are `design/systems`
## work (T-0035, `docs/design/systems/towers.md`) and replace these arrays, not
## this code.

## Where candidate enemies come from: a zero-argument callable returning an
## array of walkers. `Arena` binds its own `walkers` at placement. Unbound means
## "no enemies", so a tower without an arena never fires.
var candidate_source: Callable = Callable()

@export_group("Tiers — PLACEHOLDER (T-0035 towers.md)")
## Damage per shot, index 0 = tier 1. Three shots kill a 40 HP walker at tier 1,
## which is enough to observe firing and a cooldown in a short run.
@export var tier_damage: Array[int] = [15, 30, 55]
## Range in pixels, measured from the tower's centre, index 0 = tier 1.
@export var tier_range_px: Array[float] = [160.0, 180.0, 200.0]
## Seconds between shots, index 0 = tier 1.
@export var tier_cooldown_seconds: Array[float] = [0.8, 0.7, 0.55]
## Gold to reach the next tier: entry 0 buys tier 2, entry 1 buys tier 3. The
## arena charges the run (`RunState.spend_gold()`) and then grants the tier
## through the inventory; this table is the price and nothing else.
@export var tier_upgrade_cost: Array[int] = [60, 110]

@export_group("Targeting")
## Which enemy this tower shoots. FIRST is the default: stop the leak before it
## happens. Changing it is a UI/design decision, not a per-tower hack.
@export var rule: Targeting.Rule = Targeting.Rule.FIRST

@export_group("Presentation")
## Placeholder polygons in `scenes/tower.tscn`. Resolved by path in `_ready` so
## no script hardcodes a node path; a tower with no visuals still fires.
@export var body_path: NodePath = ^"Body"
@export var tier_mark_path: NodePath = ^"TierMark"

## How much the placeholder body grows per tier above the first. Visual only.
const BODY_GROWTH_PER_TIER := 0.25
const MAX_TIER := 3

## The inventory instance this node stands for (T-0045), or null when the node was
## dropped into a scene without one. The instance owns `tier`; this node mirrors it.
var instance: RefCounted = null

var _tier: int = 1
## Gold paid for upgrades on this tower. Placement is free, so nothing else adds to
## it (T-0045).
var _invested: int = 0
var _cooldown_left: float = 0.0
var _shots_fired: int = 0
var _held_shots: int = 0
var _last_hold_reason: String = ""
var _reported_hold: Dictionary = {}

var _body: Node2D = null
var _tier_mark: Node2D = null


func _ready() -> void:
	_body = get_node_or_null(body_path) as Node2D
	_tier_mark = get_node_or_null(tier_mark_path) as Node2D
	_invested = 0
	# A freshly built tower is ready to fire: no free shot is lost waiting out a
	# cooldown it never spent.
	_cooldown_left = 0.0
	sync_from_instance()


func _physics_process(delta: float) -> void:
	tick(delta)


# --- tier ------------------------------------------------------------------

## Binds the node to the inventory instance it stands for and copies the tier that
## instance carries. The arena calls this before the node enters the tree; `_ready`
## calls `sync_from_instance()` again, which is why it is safe to call twice.
func bind_instance(tower_instance: RefCounted) -> void:
	instance = tower_instance
	sync_from_instance()


## Copies the instance's tier onto this node. The instance owns the value - it is
## what survives being picked up - so this is the mirror's only writer.
func sync_from_instance() -> void:
	if instance == null:
		return
	_tier = clampi(instance.tier, 1, MAX_TIER)
	_update_visual()


func tier() -> int:
	return _tier


func is_max_tier() -> bool:
	return _tier >= MAX_TIER


func damage() -> int:
	return _tier_value_int(tier_damage, _tier)


func range_px() -> float:
	return _tier_value_float(tier_range_px, _tier)


func cooldown_seconds() -> float:
	return maxf(_tier_value_float(tier_cooldown_seconds, _tier), 0.0)


## Gold to reach the next tier, or -1 when there is no next tier. -1 rather than
## 0 so "cannot upgrade" cannot be mistaken for "free upgrade".
func upgrade_cost() -> int:
	if is_max_tier():
		return -1
	return _tier_value_int(tier_upgrade_cost, _tier)


## Everything spent on this tower: every upgrade paid for. Placement is free
## (T-0045), so a tower that was put down and never upgraded invested nothing.
func invested() -> int:
	return _invested


## Takes a tier the inventory has already granted (`Inventory.raise_tower_tier`).
## `paid` is the gold the arena took from the run; it is recorded only so the log
## and `invested()` can show what the tower cost - the tower never touches gold.
## A tier that is not higher is refused rather than silently absorbed.
func adopt_tier(new_tier: int, paid: int = 0) -> bool:
	if new_tier <= _tier:
		return false
	_tier = clampi(new_tier, 1, MAX_TIER)
	_invested += maxi(paid, 0)
	_update_visual()
	print("TOWER_UPGRADE " + JSON.stringify({
		"tower": name,
		"tier": _tier,
		"paid": paid,
		"damage": damage(),
		"range_px": range_px(),
		"cooldown_seconds": cooldown_seconds(),
		"invested": _invested,
	}))
	return true


# --- firing ----------------------------------------------------------------

## One step of game time. Public because a headless harness must be able to drive
## real cooldowns without waiting in real time; gameplay reaches it through
## `_physics_process`.
func tick(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - maxf(delta, 0.0), 0.0)
	if _cooldown_left > 0.0:
		return
	var target := _select_target()
	if target == null:
		return
	_fire(target)


func shots_fired() -> int:
	return _shots_fired


## Shots the tower refused to take because the target was not shootable. A
## non-zero value with `shots_fired()` unchanged is the hold-fire contract.
func held_shots() -> int:
	return _held_shots


func last_hold_reason() -> String:
	return _last_hold_reason


func candidates_in_range() -> Array[LaneWalker]:
	return Targeting.candidates_in_range(_candidates(), global_position, range_px())


func _candidates() -> Array[LaneWalker]:
	var found: Array[LaneWalker] = []
	if not candidate_source.is_valid():
		return found
	var raw = candidate_source.call()
	if not raw is Array:
		return found
	for item in raw:
		if item is LaneWalker:
			found.append(item)
	return found


## The rule's pick, or null. A pick that is not alive is a hold, not a shot.
func _select_target() -> LaneWalker:
	var candidates := candidates_in_range()
	var picked := Targeting.pick(rule, candidates)
	if picked == null:
		return null
	if not _is_shootable(picked):
		_hold(picked, "the targeting rule returned an enemy that is not alive")
		return null
	return picked


## The only definition of "this enemy may be damaged": both the node and its
## health must still be there.
func _is_shootable(walker: LaneWalker) -> bool:
	if walker == null or not is_instance_valid(walker):
		return false
	return walker.is_alive()


func _fire(target: LaneWalker) -> void:
	# Checked again, not because selection is untrusted in general but because
	# this is the line that damages: the last thing before `take_damage` must be
	# the check that the thing taking it is alive.
	if not _is_shootable(target):
		_hold(target, "the enemy stopped being alive between selection and the shot")
		return
	var applied := target.take_damage(damage())
	_cooldown_left = cooldown_seconds()
	if applied <= 0:
		# The walker refused the damage (already dead / already arrived). The
		# contract says that returns 0 and pays nothing; do not count it as a hit.
		_hold(target, "the enemy took no damage")
		return
	_shots_fired += 1
	print("TOWER_SHOT " + JSON.stringify({
		"tower": name,
		"tier": _tier,
		"rule": Targeting.rule_name(rule),
		"target": target.name,
		"damage": damage(),
		"applied": applied,
		"target_health": target.health(),
		"shots_fired": _shots_fired,
	}))


## Records a refused shot and prints it once per target instance, so a tower
## staring at a corpse does not bury the log. The cooldown is re-armed so the
## hold costs exactly one firing opportunity, not one per physics frame.
func _hold(walker: LaneWalker, why: String) -> void:
	_held_shots += 1
	_last_hold_reason = why
	_cooldown_left = cooldown_seconds()
	print("TOWER_HOLD " + JSON.stringify({
		"tower": name,
		"tier": _tier,
		"rule": Targeting.rule_name(rule),
		"target": walker.name if walker != null and is_instance_valid(walker) else "<freed>",
		"why": why,
		"shots_fired": _shots_fired,
		"held_shots": _held_shots,
	}, "", true))


# --- helpers ---------------------------------------------------------------

func _tier_value_int(table: Array[int], tier_now: int) -> int:
	if table.is_empty():
		return 0
	return table[clampi(tier_now - 1, 0, table.size() - 1)]


func _tier_value_float(table: Array[float], tier_now: int) -> float:
	if table.is_empty():
		return 0.0
	return table[clampi(tier_now - 1, 0, table.size() - 1)]


func _update_visual() -> void:
	if _body != null:
		_body.scale = Vector2.ONE * (1.0 + BODY_GROWTH_PER_TIER * float(_tier - 1))
	if _tier_mark != null:
		_tier_mark.visible = _tier > 1
