class_name Targeting
extends RefCounted

## The one targeting rule set every tower uses (T-0036).
##
## Pure selection, no side effects, no engine state: given the candidates the
## caller offers, return the one the rule chooses. Kept out of `Tower` so the
## rules can be reasoned about and demonstrated without a tower, a scene or a
## cooldown - and so a second tower type cannot quietly invent its own rules.
##
## **Selection is not permission to shoot.** `pick()` does not check health or
## validity beyond ordering; the tower validates whatever it gets back before it
## damages it (`Tower._tick`). That split is deliberate and is what T-0036's
## planted failure B exercises: a rule that returns a dead enemy must produce a
## held shot, not a crashed frame or a corpse taking damage.
##
## The three rules, in the order the enum documents them:
##
##   FIRST     - furthest along the lane, i.e. closest to the HQ. The default,
##               because stopping a leak before it happens is the point of a tower.
##   LAST      - least far along the lane, i.e. the newest arrival. Use it to
##               finish a wave from the back.
##   STRONGEST - most health remaining. Use it to put damage where the armour is.
##
## Ties resolve by lane progress (furthest first) and then by candidate order,
## which is spawn order, so two runs of the same wave choose the same walker.

enum Rule { FIRST, LAST, STRONGEST }

const RULE_NAMES: Array[String] = ["first", "last", "strongest"]


static func rule_name(rule: int) -> String:
	if rule < 0 or rule >= RULE_NAMES.size():
		return "unknown(%d)" % rule
	return RULE_NAMES[rule]


## Every rule in enum order, for a UI or a test that must not hardcode the list.
static func all_rules() -> Array[int]:
	return [Rule.FIRST, Rule.LAST, Rule.STRONGEST]


## The candidates a tower at `origin` could shoot: inside `radius_px` of it. Range
## is a circle around the tower's own position, so a tower cannot reach a walker
## it is not standing near.
static func candidates_in_range(
	walkers: Array[LaneWalker], origin: Vector2, radius_px: float
) -> Array[LaneWalker]:
	var in_range: Array[LaneWalker] = []
	for walker in walkers:
		if walker == null or not is_instance_valid(walker):
			continue
		if walker.global_position.distance_to(origin) <= radius_px:
			in_range.append(walker)
	return in_range


## The walker `rule` selects out of `candidates`, or null when there is nothing
## to choose from. `candidates` is expected to be non-empty and already in range.
static func pick(rule: int, candidates: Array[LaneWalker]) -> LaneWalker:
	if candidates.is_empty():
		return null
	var best: LaneWalker = candidates[0]
	for i in range(1, candidates.size()):
		var candidate := candidates[i]
		if candidate == null or not is_instance_valid(candidate):
			continue
		if _beats(rule, candidate, best):
			best = candidate
	return best


## True when `candidate` should replace `incumbent` under `rule`.
static func _beats(rule: int, candidate: LaneWalker, incumbent: LaneWalker) -> bool:
	if incumbent == null or not is_instance_valid(incumbent):
		return true
	match rule:
		Rule.LAST:
			return candidate.lane_progress() < incumbent.lane_progress()
		Rule.STRONGEST:
			if candidate.health() != incumbent.health():
				return candidate.health() > incumbent.health()
			return candidate.lane_progress() > incumbent.lane_progress()
		_:
			# Rule.FIRST, and the fallback for an out-of-range rule: a rule this
			# build does not know must still hold a defence rather than crash.
			return candidate.lane_progress() > incumbent.lane_progress()
