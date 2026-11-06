class_name WaveDefinition
extends Resource

## One wave of a level: an ordered list of `WaveEntry` lines, plus the optional
## sub-boss that makes an elite level's final wave (T-0039).
##
## A wave is *finished* when every unit it spawned is dead or leaked, which is
## `WaveDirector`'s job to observe; this resource only says what the wave is.
##
## The one rule it enforces on its own is that a wave must spawn something.
## `docs/design/systems/waves.md` §Edge cases allows a zero-budget "breathing"
## wave, but a designer typing zero *units* by mistake produces a level that can
## never advance, and that has to fail loudly instead (T-0039 DoD 4).

## 1-based position in the level's wave list. Printed, never used for ordering:
## the array order is the order.
@export var number: int = 1

## The wave's trash lines, spawned in this order (bursts first is the plan's
## job, not this resource's).
@export var entries: Array[WaveEntry] = []

## The elite final wave's sub-boss. Null on every other wave. Kept separate from
## `entries` so "exactly one sub-boss" is countable instead of inferred.
@export var sub_boss: WaveEntry = null


## Every line this wave spawns, sub-boss first. The sub-boss leads because
## `enemies.md` §Composition rule 5 is explicit: the biggest thing is never
## hidden behind ten grunts, or the player cannot answer it in time.
func all_entries() -> Array[WaveEntry]:
	var lines: Array[WaveEntry] = []
	if sub_boss != null:
		lines.append(sub_boss)
	for entry in entries:
		lines.append(entry)
	return lines


func unit_count() -> int:
	var total := 0
	for entry in all_entries():
		total += maxi(entry.count, 0)
	return total


func total_health() -> int:
	var total := 0
	for entry in all_entries():
		total += maxi(entry.count, 0) * maxi(entry.max_health, 0)
	return total


## Units of the given kinds, summed. `WavePlan` uses it to count sub-bosses
## wherever a plan may have put them, so a sub-boss smuggled into the trash lines
## is still caught.
func units_of_kind(kinds: Array) -> int:
	var total := 0
	for entry in all_entries():
		if kinds.has(entry.kind):
			total += maxi(entry.count, 0)
	return total


## Why this wave cannot be run, or "" when it can. Printed by the planner at
## build time and by the director at start time: the same words in both places,
## so a hand-authored plan and a generated one fail identically.
func validate() -> String:
	for entry in all_entries():
		if entry == null:
			return "wave %d carries a null line" % number
		var why := entry.validate()
		if why != "":
			return "wave %d: %s" % [number, why]
	if unit_count() <= 0:
		return (
			"wave %d has no enemies: %d line(s) and no sub-boss, so it would spawn nothing "
			+ "and the level could never advance"
		) % [number, entries.size()]
	return ""


func describe() -> Dictionary:
	var lines: Array[String] = []
	for entry in all_entries():
		lines.append(entry.describe())
	return {
		"wave": number,
		"units": unit_count(),
		"health": total_health(),
		"lines": lines,
	}
