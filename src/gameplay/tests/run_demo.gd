extends SceneTree

## T-0045 DoD 2, 3 and 4 - the arena as **one level of a run**, in one headless run.
##
##     godot --headless --path . --script res://src/gameplay/tests/run_demo.gd
##
## The demo drives the real `res://scenes/main.tscn` twice, with one `RunState`
## and one `Inventory` handed to both levels through `arena.bind_run()`. No mock
## arena, no reimplementation of the scene.
##
## Prints, in this order:
##   RUNDEMO_STEP {json}         the state worth recording after a step
##   RUNDEMO_LEVEL {json}        one level's opening/ending numbers
##   RUNDEMO_REFUSED {text}      a refusal's reason, echoed verbatim
##   RUNDEMO_PLANTED_A {json}    defeat ends the run through RunState; no next level
##   RUNDEMO_PLANTED_B {json}    complete_level() called, win_run() not
##   RUNDEMO_SELF_TEST {json}    once, last; carries checks and failures
##
## The `ARENA_*`, `WAVE_*`, `GOLD_LEDGER`, `RUN_REFUSED` and `TOWER_UPGRADE` lines
## in this output are printed by the systems under test, not by this file: the demo
## shows what the game says, not what the demo claims. The exit code is not
## evidence (L-035); `RUNDEMO_SELF_TEST` is.
##
## Why the run's starting gold (10) is enough for the demo: placement is free, and
## the upgrade it buys is paid for out of gold earned by kills in the same level -
## which is exactly the "gold in, then gold out" path T-0045 asks to see.

const ARENA_SCENE := "res://scenes/main.tscn"
const RunStateScript := preload("res://src/systems/run_state.gd")
const InventoryScript := preload("res://src/systems/inventory.gd")

## Long enough that the arena's own spawn timer never fires during the demo. The
## demo owns the field; a spawner tick cannot change it underneath a check.
const SPAWN_INTERVAL_SECONDS := 3600.0

## Health and gold the run starts with; both are `RunState` placeholders, passed
## explicitly so the demo states the numbers it asserts instead of inheriting them.
const RUN_HQ_MAX := 10
const RUN_STARTING_GOLD := 10

## Kills needed to afford one 60-gold upgrade from the 10-gold start: five
## 12-gold placeholder walkers leave 10 gold to spare.
const KILLS_FOR_GOLD := 5

## A leak walker covers the 800 px lane in a handful of frames at this speed, so
## the demo observes the real walk -> arrive -> HQ damage -> despawn path without
## waiting four real seconds per leak.
const FAST_LEAK_SPEED := 8000.0
const LEAK_FRAMES := 20

## Leaks driven in level 1 and in level 2: the first leaves 7 of 10, the second
## empties the run.
const LEAKS_LEVEL_1 := 3
const LEAKS_LEVEL_2 := 7

## Game time per director tick while the level's waves are driven by hand, and a
## guard so a wave that never finishes fails the demo instead of hanging it.
const TICK_SECONDS := 1.0
const MAX_WAVE_TICKS := 400

const LETHAL_DAMAGE := 1000000
const TOWER_TYPE := "arrow"
const UPGRADE_TYPE := "sharpen"

var _run = null
var _inventory = null
var _arena = null

var _level1_hq := 0
var _level1_gold := 0
var _run_ended_emissions := 0
var _run_ended_victory := false
var _run_ended_reason := ""

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# The tree has not iterated during `_initialize()`: nothing is safe until it
	# has, and a node added to `root` here has not run `_ready` yet.
	await process_frame

	_run = RunStateScript.new()
	_inventory = InventoryScript.new()
	_run.run_ended.connect(_on_run_ended)
	if not check(
		_run.start(RUN_HQ_MAX, RUN_STARTING_GOLD),
		"the run starts at HQ %d with %d gold" % [RUN_HQ_MAX, RUN_STARTING_GOLD]
	):
		_finish()
		return

	await _step_level_one()
	if _level1_hq == 0:
		# Level 1 did not get far enough to hand anything to level 2. Reporting the
		# failures already recorded is more useful than a cascade of them.
		_finish()
		return
	await _step_level_two()

	_finish()


# --- level 1 ----------------------------------------------------------------

func _step_level_one() -> void:
	_case("level 1: seed, earn, spend, leak, clear")
	_arena = await _open_level()
	if _arena == null:
		fail("the arena for level 1 did not boot")
		return

	# 1. The level is seeded from the run, and is the run's level 1.
	# Untyped on purpose: `_hq()` returns whatever the node is, and `:=` cannot
	# infer a type from an untyped helper (parse error, not a runtime one).
	var hq = _hq()
	if not check(hq != null, "the level has an HQ at the arena's hq_path"):
		return
	check(_arena.run_state() == _run, "the arena is bound to the run the demo owns")
	check(_arena.inventory() == _inventory, "the arena is bound to the demo's inventory")
	check_eq_int(hq.health(), RUN_HQ_MAX, "level 1 opens at the run's HQ (10 of 10)")
	check_eq_int(hq.max_health, RUN_HQ_MAX, "the HQ view carries the run's maximum")
	check_eq_int(_arena.gold(), _run.gold(), "the arena shows the run's gold")
	check_eq_int(_arena.effective_level_index(), 1, "level 1 plays as the run's level 1")

	# 2. Gold in: kills pay the run. `_run` is untyped, so `gold()` is Variant and
	# the target type has to be spelled out rather than inferred.
	var kill_gold: int = _run.gold()
	var rewards := 0
	for i in KILLS_FOR_GOLD:
		var walker = _arena.spawn_walker()
		if not check(walker != null, "an enemy can be spawned for the kill"):
			return
		rewards += maxi(walker.gold_reward, 0)
		walker.take_damage(LETHAL_DAMAGE)
	check_eq_int(
		_run.gold(), kill_gold + rewards, "kills paid %d gold into the run" % rewards
	)
	_step("gold_in", {"kills": KILLS_FOR_GOLD, "gold": _run.gold()})

	# 3. Placement is free, and draws the tower out of the inventory.
	var instance = _inventory.add_tower(TOWER_TYPE)
	if not check(instance != null, "a tower can be added to the inventory"):
		return
	var upgrade = _inventory.add_upgrade(UPGRADE_TYPE)
	if not check(upgrade != null, "an upgrade can be added to the inventory"):
		return
	check(
		_inventory.apply_upgrade_to_tower(instance.id, upgrade.id),
		"the upgrade in hand goes onto the tower in the inventory"
	)
	var slot = _slots()[0]
	if not check(slot != null, "the scene has a build tile"):
		return

	var gold_before_build: int = _run.gold()
	var tower = _arena.place_tower(slot.world_position(), instance.id)
	if not check(tower != null, "the inventory's tower can be placed"):
		return
	check_eq_int(_run.gold(), gold_before_build, "placing a tower from the inventory costs nothing")
	check(instance.placed, "the instance is marked as standing on the map")
	check_eq_int(tower.tier(), instance.tier, "the node mirrors the instance's tier (1)")

	# 4. Gold out: the next tier is bought out of the run.
	var price: int = tower.upgrade_cost()
	if not check(price > 0, "the tower quotes a price for its next tier"):
		return
	if not check(_run.can_afford(price), "the run can afford the %d gold tier" % price):
		return
	check(_arena.upgrade_tower(tower), "the upgrade is accepted in the build phase")
	check_eq_int(_run.gold(), gold_before_build - price, "the tier was paid out of the run's gold")
	check_eq_int(instance.tier, 2, "the inventory instance carries the new tier")
	check_eq_int(tower.tier(), 2, "the node mirrors the instance after the upgrade")
	_step("gold_out", {"tier": instance.tier, "paid": price, "gold": _run.gold()})

	# 5. Take-back keeps tier and upgrades, and pays nothing.
	var gold_before_takeback: int = _run.gold()
	check(_arena.take_tower_back(tower), "the tower is taken back into the inventory")
	check(not instance.placed, "the instance is no longer on the map")
	check_eq_int(instance.tier, 2, "the taken-back tower kept its tier")
	check_eq_int(instance.upgrade_count(), 1, "the taken-back tower kept its upgrade")
	check(
		instance.upgrade_type_ids() == [UPGRADE_TYPE],
		"the upgrade it kept is the one that was applied (%s)" % [instance.upgrade_type_ids()]
	)
	check_eq_int(_run.gold(), gold_before_takeback, "taking a tower back pays no gold")
	_step("taken_back", {
		"tier": instance.tier,
		"upgrades": instance.upgrade_type_ids(),
		"gold": _run.gold(),
	})

	# 6. Leaks: the HQ is the run's, one point per arrival.
	var per_leak := int(_arena.get("damage_per_leak"))
	for i in LEAKS_LEVEL_1:
		var applied: int = await _leak_once()
		check_eq_int(applied, per_leak, "leak %d cost the run %d point(s)" % [i + 1, per_leak])
	check_eq_int(
		hq.health(),
		RUN_HQ_MAX - LEAKS_LEVEL_1 * per_leak,
		"level 1 is down to %d of %d" % [RUN_HQ_MAX - LEAKS_LEVEL_1 * per_leak, RUN_HQ_MAX]
	)
	check_eq_int(
		_run.hq_health(), hq.health(), "the HQ node and the run agree after the leaks"
	)

	# 7. Clear the level: the waves, killed as they arrive.
	await _clear_level_one()

	# 8. Planted failure B: the level is completed and the run is NOT won.
	print("RUNDEMO_PLANTED_B " + JSON.stringify({
		"complete_level_called": _run.level_index() == 1,
		"levels_completed": _run.level_index(),
		"win_run_called": _run_ended_emissions > 0,
		"run_ended_emissions": _run_ended_emissions,
		"status": _run.status_name(),
		"is_over": _run.is_over(),
		"is_victory": _run.is_victory(),
		"end_reason": _run.end_reason(),
	}))
	check_eq_int(_run.level_index(), 1, "the run counted exactly one completed level")
	check_eq_int(
		_run_ended_emissions, 0, "the arena did not end the run (win_run() is the map's call)"
	)
	check(_run.is_in_progress(), "the run is still in progress after a level clear")
	check(not _run.is_victory(), "clearing a level is not a victory")

	_level1_hq = _run.hq_health()
	_level1_gold = _run.gold()
	print("RUNDEMO_LEVEL " + JSON.stringify({
		"level": 1,
		"hq": _level1_hq,
		"hq_max": _run.hq_max_health(),
		"gold": _level1_gold,
		"levels_completed": _run.level_index(),
		"status": _run.status_name(),
	}))
	check_eq_int(_level1_hq, 7, "level 1 ends with the HQ at 7 of 10")

	# 9. Close the level. The run and the inventory outlive the scene.
	_arena.queue_free()
	_arena = null
	await process_frame


## Runs every wave of the level, killing each unit as it arrives, and asserts the
## level-clear gold is the only thing the clear itself paid.
func _clear_level_one() -> void:
	var director = _arena.wave_director()
	if not check(director != null, "the level has a wave director"):
		return
	var gold_before: int = _run.gold()
	var paid := 0
	var ticks := 0
	if not check(_arena.start_level(), "the level's first wave starts"):
		return
	while ticks < MAX_WAVE_TICKS and not director.is_level_complete():
		director.tick(TICK_SECONDS)
		ticks += 1
		for walker in director.walkers():
			if not walker.is_alive():
				continue
			paid += maxi(walker.gold_reward, 0)
			walker.take_damage(LETHAL_DAMAGE)
		if not director.is_active() and not director.is_level_complete():
			# Waves do not auto-advance; the level's owner starts the next one.
			if not _arena.start_wave(director.current_index() + 1):
				break
	check(director.is_level_complete(), "the level's waves finished in %d ticks" % MAX_WAVE_TICKS)
	check_eq_int(
		_run.gold(),
		gold_before + paid + RunStateScript.GOLD_PER_LEVEL_CLEAR,
		"the cleared level paid %d gold from kills and %d for the clear"
		% [paid, RunStateScript.GOLD_PER_LEVEL_CLEAR]
	)


# --- level 2 ----------------------------------------------------------------

func _step_level_two() -> void:
	_case("level 2: HQ carried, gold carried, tower carried, defeat")
	_arena = await _open_level()
	if _arena == null:
		fail("the arena for level 2 did not boot")
		return
	var hq = _hq()
	if not check(hq != null, "level 2 has an HQ at the arena's hq_path"):
		return

	# 1. HQ and gold carried across the level boundary.
	check_eq_int(hq.health(), _level1_hq, "level 2 opens with the HQ level 1 ended with (7 of 10)")
	check_eq_int(hq.max_health, RUN_HQ_MAX, "level 2 still has a 10 point HQ")
	check_eq_int(_arena.gold(), _level1_gold, "the gold earned in level 1 is available in level 2")
	check_eq_int(_run.gold(), _level1_gold, "the run carried the gold, not the scene")
	check_eq_int(_run.level_number(), 2, "the run is on level 2")
	check_eq_int(_arena.effective_level_index(), 2, "level 2 plays as the run's level 2")
	print("RUNDEMO_LEVEL " + JSON.stringify({
		"level": 2,
		"hq": hq.health(),
		"hq_max": hq.max_health,
		"gold": _run.gold(),
		"levels_completed": _run.level_index(),
		"status": _run.status_name(),
	}))

	# 2. The tower taken back in level 1 is placed again at its tier, upgrades and
	#    all, still free.
	var instance = _inventory.find_tower(1)
	if not check(instance != null, "the inventory still holds the taken-back tower"):
		return
	var slot = _slots()[0]
	if not check(slot != null, "level 2 has a build tile"):
		return
	var gold_before: int = _run.gold()
	var tower = _arena.place_tower(slot.world_position(), instance.id)
	if not check(tower != null, "the taken-back tower can be placed again in level 2"):
		return
	check_eq_int(tower.tier(), 2, "the tower stands again at its previous tier (2)")
	check_eq_int(instance.upgrade_count(), 1, "it still carries its upgrade")
	check(
		instance.upgrade_type_ids() == [UPGRADE_TYPE],
		"the upgrade it carries is still %s" % UPGRADE_TYPE
	)
	check_eq_int(_run.gold(), gold_before, "placing it again cost nothing")
	print("RUNDEMO_STEP " + JSON.stringify({
		"step": "replaced_in_level_2",
		"instance": instance.id,
		"tier": tower.tier(),
		"upgrades": instance.upgrade_type_ids(),
		"placed": instance.placed,
		"gold": _run.gold(),
	}))

	# 3. Planted failure A: leaks drive the run to zero, and the run ends through
	#    RunState, not through the arena.
	var per_leak := int(_arena.get("damage_per_leak"))
	var gold_before_defeat: int = _run.gold()
	for i in LEAKS_LEVEL_2:
		var applied: int = await _leak_once()
		check_eq_int(applied, per_leak, "leak %d cost the run %d point(s)" % [i + 1, per_leak])
	check_eq_int(_run.hq_health(), 0, "the leaks emptied the run's HQ")
	check_eq_int(hq.health(), 0, "the HQ node shows the run's zero")
	check(_run.is_defeated(), "the run ended as a defeat")
	check(_run.status_name() == "defeated", "the run's own status says defeated")
	check(_run.end_reason().find("HQ reached zero") != -1, "the run's reason names the HQ")
	check_eq_int(
		_run_ended_emissions, 1, "RunState announced the end exactly once"
	)
	check(not _run_ended_victory, "the ending it announced was not a victory")
	check(_run_ended_reason.find("HQ reached zero") != -1, "the announced reason is the HQ")

	# A kill after the end pays nothing: the refusal is RunState's, not the arena's.
	var walker = _arena.spawn_walker()
	if check(walker != null, "an enemy can still be spawned"):
		walker.take_damage(LETHAL_DAMAGE)
	check_eq_int(_run.gold(), gold_before_defeat, "a kill after the run ended paid nothing")

	# And the arena refuses to start another level on a run that is over.
	var started: bool = _arena.start_level()
	print("RUNDEMO_REFUSED " + _arena.last_refusal())
	check(not started, "the arena refuses to start another level")
	check(
		_arena.last_refusal().find("defeated") != -1, "the refusal names the defeated run"
	)
	check_eq_int(_run.level_index(), 1, "no level was completed after the defeat")

	print("RUNDEMO_PLANTED_A " + JSON.stringify({
		"hq": _run.hq_health(),
		"status": _run.status_name(),
		"is_over": _run.is_over(),
		"is_defeated": _run.is_defeated(),
		"end_reason": _run.end_reason(),
		"level_started": started,
		"refusal": _arena.last_refusal(),
		"levels_completed": _run.level_index(),
		"gold": _run.gold(),
	}))


# --- lookups ----------------------------------------------------------------

## Instantiates the real scene with the run and inventory bound **before** it
## enters the tree, so `_ready` seeds the level from them.
func _open_level() -> Node:
	var packed := load(ARENA_SCENE) as PackedScene
	if not check(packed != null, "the arena scene loads"):
		return null
	var arena = packed.instantiate()
	if not check(arena != null, "the arena scene instantiates"):
		return null
	arena.set("spawn_interval_seconds", SPAWN_INTERVAL_SECONDS)
	if not check(arena.bind_run(_run, _inventory), "the arena accepts the run and inventory"):
		return null
	root.add_child(arena)
	await process_frame
	await physics_frame
	return arena


func _hq():
	if _arena == null:
		return null
	var declared = _arena.get("hq_path")
	if declared is NodePath and not (declared as NodePath).is_empty():
		return _arena.get_node_or_null(declared)
	return null


## Build tiles are discovered by type, never by node path: adding a tile is a scene
## edit and must not change this harness.
func _slots() -> Array:
	var found: Array = []
	if _arena == null:
		return found
	for child in _arena.get_children():
		if child is BuildSlot:
			found.append(child)
	return found


## Spawns one enemy, sends it down the lane at `FAST_LEAK_SPEED`, and returns the
## health the arrival cost. 0 means it never arrived within `LEAK_FRAMES`; -1
## means the scene could not produce a walker.
func _leak_once() -> int:
	var hq = _hq()
	if hq == null:
		return -1
	var before: int = hq.health()
	var walker = _arena.spawn_walker()
	if walker == null:
		return -1
	walker.move_speed = FAST_LEAK_SPEED
	for i in LEAK_FRAMES:
		await physics_frame
		if hq.health() != before:
			return before - hq.health()
	return 0


func _on_run_ended(victory: bool, reason: String) -> void:
	_run_ended_emissions += 1
	_run_ended_victory = victory
	_run_ended_reason = reason


# --- reporting --------------------------------------------------------------

func _case(step_name: String) -> void:
	print("RUNDEMO_CASE " + step_name)


func _step(step_name: String, extra: Dictionary = {}) -> void:
	var payload: Dictionary = {"step": step_name}
	payload.merge(extra, false)
	print("RUNDEMO_STEP " + JSON.stringify(payload))


func check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
	return condition


func check_eq_int(actual: int, expected: int, message: String) -> bool:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %d, got %d" % [message, expected, actual])
		return false
	return true


func fail(message: String) -> void:
	_checks += 1
	_failures.append(message)


## Exactly one self-test line, last. A demo that recorded no checks fails: it
## proved nothing, and "no assertions" must never look like a pass.
func _finish() -> void:
	if _checks == 0 and _failures.is_empty():
		_failures.append("the demo recorded no checks")

	var passed := _failures.is_empty()
	print("RUNDEMO_SELF_TEST " + JSON.stringify({
		"name": "run_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("RUNDEMO_FAILURE " + f)
	quit(1)
