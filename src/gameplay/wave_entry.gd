class_name WaveEntry
extends Resource

## One line of a wave: "this many of this enemy, this far apart" (T-0039).
##
## A wave is data, not a spawn loop. This resource is the unit that data is
## written in, so a designer changes a wave by changing numbers on a resource and
## never by editing a script.
##
## Every number here is a PLACEHOLDER: the curves live in
## `docs/design/systems/waves.md` and the stats in `enemies.md`, and both files
## say `GUESS` until a human plays a full run (G2.2).
##
## Per-enemy `move_speed` is here because `enemies.md` §Legacy conflict says the
## arena's single 200 px/s is superseded by a per-enemy band. The Grunt is
## deliberately *not* the design's 60 px/s: `scripts/tests/cases/leak_damage.gd`
## waits 600 physics frames for the first arrival, and 800 px at 60 px/s is 800
## frames. 100 px/s is the slowest Grunt that still arrives inside that window
## (480 frames), which is also slow enough for one tier-1 tower to kill it. The
## design value needs the case's window raised in the same change, and that file
## belongs to `eng/tools`.

@export var kind: StringName = &"grunt"
## How many units this line spawns. Zero is illegal: a line that spawns nothing
## is a wave that never ends (`WaveDefinition.validate()`).
@export var count: int = 1
## Seconds between two units of this line.
@export var spacing_seconds: float = 2.0
## Hit points of one unit of this kind.
@export var max_health: int = 40
## Gold paid to the run when one unit dies.
@export var gold_reward: int = 4
## Pixels per second along the lane. Zero would be an enemy that never arrives,
## so the floor is one pixel per second.
@export var move_speed: float = 100.0

## Below this, an enemy never reaches the lane end and its wave never clears.
const MIN_MOVE_SPEED := 1.0


## Builds a line in one call, so a plan table reads as data instead of as six
## assignments per row.
static func make(
	p_kind: StringName,
	p_count: int,
	p_spacing: float,
	p_health: int,
	p_gold: int,
	p_speed: float
) -> WaveEntry:
	var entry := WaveEntry.new()
	entry.kind = p_kind
	entry.count = p_count
	entry.spacing_seconds = p_spacing
	entry.max_health = p_health
	entry.gold_reward = p_gold
	entry.move_speed = p_speed
	return entry


## A copy of this line with its count multiplied by `scale` and floored at one
## unit. The original is untouched: a wave plan is rebuilt from its template on
## every level, never scaled in place twice.
func duplicate_scaled(scale: float) -> WaveEntry:
	var entry := WaveEntry.new()
	entry.kind = kind
	entry.count = maxi(int(round(float(count) * maxf(scale, 0.0))), 1)
	entry.spacing_seconds = spacing_seconds
	entry.max_health = max_health
	entry.gold_reward = gold_reward
	entry.move_speed = move_speed
	return entry


## Why this line cannot be spawned, or "" when it can. The caller prints the
## reason; a refusal that says nothing is indistinguishable from a bug.
func validate() -> String:
	if count < 1:
		return "line '%s' asks for %d units" % [kind, count]
	if max_health < 1:
		return "line '%s' has %d hit points, so the enemy would be born dead" % [kind, max_health]
	if spacing_seconds <= 0.0:
		return "line '%s' has %.2f s between units" % [kind, spacing_seconds]
	if move_speed < MIN_MOVE_SPEED:
		return "line '%s' moves at %.2f px/s, so it would never reach the lane end" % [kind, move_speed]
	return ""


## The stats this line hands the enemy scene, keyed by the property names
## `LaneWalker` exposes. The arena applies them before the walker is set up, so
## one scene can stand for every enemy kind until per-kind art exists.
func stats() -> Dictionary:
	return {
		"max_health": max_health,
		"gold_reward": gold_reward,
		"move_speed": move_speed,
	}


func describe() -> String:
	return "%s x%d @%.2fs" % [kind, count, spacing_seconds]
