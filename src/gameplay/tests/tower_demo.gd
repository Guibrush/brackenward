extends SceneTree

## T-0036 DoD 2-4 — one headless demo of the tower loop, both planted failures
## included.
##
##     godot --headless --path . --script res://src/gameplay/tests/tower_demo.gd
##
## The demo drives the real `res://scenes/main.tscn` and nothing else: no mock
## arena, no rebuild of the scene by hand. A test that reassembles the scene
## proves the test's idea of the scene, not the scene.
##
## Prints, in this order:
##   TOWER_DEMO_CASE {name}       which step is being taken
##   TOWER_DEMO_REFUSED {text}    a refused call's reason, echoed verbatim
##   TOWER_DEMO_STEP {json}       the state worth recording after a step
##   TOWER_DEMO_HOLD {json}       the held shot of planted failure B, with counters
##   TOWER_DEMO_LEDGER {json}     opening / earned / spent / closing, reconciled
##   TOWER_DEMO_SUMMARY {json}    once; the ledger and a pass/fail
##   TOWER_DEMO_SELF_TEST {json}  once, last; carries checks and failures
##
## The `ARENA_REFUSED`, `ARENA_PLACED`, `ARENA_KILL`, `ARENA_TAKEN_BACK` and
## `TOWER_HOLD` lines in this output are printed by the systems under test, not by
## this file. That is the point: the demo shows what the game says, not what the
## demo claims. The `TOWER_DEMO_REFUSED` echo exists only so a reader of the log
## does not have to decode JSON to see the words that refused the input.
##
## T-0045 changed the model this demo drives: a tower comes **out of the
## inventory** and placement is **free**, and the way off the map is
## `take_tower_back()` (which pays nothing and keeps the tier and upgrades), not a
## sale for a refund. The demo therefore buys nothing at build time; the one 60
## gold upgrade is paid for out of gold earned from kills in the same level, which
## is the "gold in, then gold out" path and keeps every number honest.
## The two planted failures are unchanged: the wave-phase lock (A) and the
## dead-target hold-fire (B).
##
## Why most steps run with no frames between them: `Tower.tick(delta)` is public
## so a harness can drive real cooldowns in game time instead of waiting in real
## time, and planted failure B needs a walker that is dead but not yet freed —
## a state that exists only inside one frame. Everything after the placement
## therefore runs in a single uninterrupted block.
##
## The exit code is not evidence (L-035): `TOWER_DEMO_SELF_TEST` carries
## `checks`, `failed` and the failure strings, and a failing check also emits an
## `ERROR:` line. Exit 0 = every check passed.

const ARENA_SCENE := "res://scenes/main.tscn"

## Long enough that the arena's own spawn timer never fires while the demo runs.
## The demo owns its enemies (`spawn_walker`), so a spawner tick cannot change the
## field underneath a check. One hour of game time; no step reaches it.
const SPAWN_INTERVAL_SECONDS := 3600.0

## Game time per tower step. Longer than every placeholder cooldown (0.8 s at
## tier 1), so one step is exactly one firing opportunity even if the tier tables
## are retuned inside the placeholder range.
const TICK_SECONDS := 1.0

## Guard on the kill loop. A tower that never lands its shots fails the demo with
## a message instead of hanging it.
const MAX_KILL_TICKS := 16

## A demo needs at least one tile to build on and one left over to prove that a
## *free* tile is still refused during a wave — otherwise the phase refusals
## could be explained by the lane check instead.
const MIN_SLOTS_REQUIRED := 2

## What the inventory is asked for. The types are strings until `design/systems`
## publishes the tower and upgrade tables (T-0035).
const TOWER_TYPE := "arrow"
const UPGRADE_TYPE := "sharpen"

## Damage that kills any placeholder walker outright, so a demo kill is one call
## instead of a loop over an unknown health pool.
const LETHAL_DAMAGE := 1000000

## Guard on the earn loop. Five 12-gold placeholder walkers pay for the 60-gold
## tier from a 10-gold start; a table that makes kills worth nothing fails the
## demo with a message instead of hanging it.
const MAX_EARN_KILLS := 12

var _arena = null
var _hq: Hq = null
var _slots: Array[BuildSlot] = []
var _slot: BuildSlot = null
var _tower: Tower = null
## The inventory instance the tower node stands for: the thing that keeps its
## tier and upgrades when the node is taken back off the map (T-0045).
var _instance = null
var _victim: LaneWalker = null

var _opening_gold: int = 0
var _expect_gold: int = 0

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_boot()


## The tree has not iterated during `_initialize()`, so nothing is safe until it
## has: a node added to `root` here enters the tree but does not run `_ready`.
func _boot() -> void:
	await process_frame

	var packed := load(ARENA_SCENE) as PackedScene
	if packed == null:
		fail("could not load " + ARENA_SCENE)
		_finish()
		return
	_arena = packed.instantiate()
	if _arena == null:
		fail(ARENA_SCENE + " did not instantiate")
		_finish()
		return
	# Set before `add_child`, so the value is in force when the arena builds its
	# spawn timer: the demo owns its enemies instead of racing the spawner.
	_arena.set("spawn_interval_seconds", SPAWN_INTERVAL_SECONDS)
	root.add_child(_arena)

	await process_frame
	await physics_frame

	_hq = _resolve_hq()
	if _hq == null:
		fail("no HQ at the arena's hq_path; the scene is not wired")
		_finish()
		return
	if not check(
		_hq.max_health > 0 and _hq.health() == _hq.max_health,
		"the scene booted with a full HQ (%d of %d)" % [_hq.health(), _hq.max_health]
	):
		_finish()
		return

	_slots = _collect_slots()
	if not check(
		_slots.size() >= MIN_SLOTS_REQUIRED,
		"the scene has at least %d build tiles (found %d)" % [MIN_SLOTS_REQUIRED, _slots.size()]
	):
		_finish()
		return
	_slot = _slots[0]
	_opening_gold = _arena.gold()
	_expect_gold = _opening_gold

	await _run_demo()
	_finish()


func _run_demo() -> void:
	_step_place()
	if _tower == null:
		fail("no tower was placed; the rest of the demo cannot run")
		return

	# Let the new node run `_ready` before its investment is read. Placement is
	# free (T-0045), so at this point the tower has cost nothing at all - the
	# money arrives only with the tier bought further down.
	await process_frame
	await physics_frame
	check_eq_int(_tower.invested(), 0, "a placed tower has invested no gold (placement is free)")

	_step_refuse_on_lane()
	_step_refuse_occupied()
	_step_refuse_during_wave()
	_step_kill()
	_step_earn_for_upgrade()
	_step_upgrade()
	_step_hold_fire()
	_step_take_back()
	_step_reconcile()


# --- 1: place ---------------------------------------------------------------

## The tower is a *thing the player owns* now: it is added to the inventory as an
## instance, the instance is given an upgrade, and the arena is asked to put that
## instance on a tile. The instance is what carries tier and loadout, so the node
## is only its view while it stands.
func _step_place() -> void:
	_case("place a tower from the inventory on a build tile")
	var inventory = _arena.inventory()
	if not check(inventory != null, "the arena has an inventory to draw a tower from"):
		return

	_instance = inventory.add_tower(TOWER_TYPE)
	if not check(_instance != null, "a tower can be added to the inventory"):
		return
	var upgrade = inventory.add_upgrade(UPGRADE_TYPE)
	if not check(upgrade != null, "an upgrade can be added to the inventory"):
		return
	check(
		inventory.apply_upgrade_to_tower(_instance.id, upgrade.id),
		"the upgrade in hand goes onto the tower in the inventory"
	)

	_tower = _arena.place_tower(_slot.world_position(), _instance.id)
	if not check(_tower != null, "placing on a free tile returns a tower"):
		return
	_expect_gold = _opening_gold
	check_eq_int(_arena.gold(), _expect_gold, "placing a tower from the inventory costs nothing")
	check(_instance.placed, "the instance is marked as standing on the map")
	check_eq_int(_tower.tier(), _instance.tier, "the node mirrors the instance's tier")
	check_eq_int(_instance.upgrade_count(), 1, "the placement carried the instance's upgrade")
	check(not _slot.is_free(), "the tile the tower stands on is no longer free")
	check_eq_int(
		_arena.free_slot_count(), _slots.size() - 1, "one build tile fewer is free"
	)
	_step("placed", {
		"tower": _tower.name,
		"slot": _slot.name,
		"cost": 0,
		"instance": _instance.id,
		"tier": _tower.tier(),
		"upgrades": _instance.upgrade_type_ids(),
	})


# --- 2: a refusal for being on the lane -------------------------------------

func _step_refuse_on_lane() -> void:
	_case("refuse a tower on the lane")
	var on_lane := _lane_point_near(_tower.global_position)
	var before: int = _arena.gold()
	var refused = _arena.place_tower(on_lane)
	print("TOWER_DEMO_REFUSED " + _arena.last_refusal())
	check(refused == null, "placing on the lane returns no tower")
	check(_arena.last_refusal().find("on the lane") != -1, "the refusal names the lane")
	check_eq_int(_arena.gold(), before, "a refused placement spends nothing")
	_step("refused_on_lane", {"at": [on_lane.x, on_lane.y], "reason": _arena.last_refusal()})


# --- 3: a refusal for an occupied tile --------------------------------------

func _step_refuse_occupied() -> void:
	_case("refuse a tower on an occupied tile")
	var before: int = _arena.gold()
	var refused = _arena.place_tower(_slot.world_position())
	print("TOWER_DEMO_REFUSED " + _arena.last_refusal())
	check(refused == null, "placing on an occupied tile returns no tower")
	check(
		_arena.last_refusal().find("already occupied") != -1,
		"the refusal names the occupied tile"
	)
	check_eq_int(_arena.gold(), before, "a refused placement spends nothing")
	_step("refused_occupied", {"slot": _slot.name, "reason": _arena.last_refusal()})


# --- 4: planted failure A ---------------------------------------------------

## T-0036 DoD 3. Between waves the player plans freely; during a wave towers and
## perks are locked (CHARTER). The lock is only observable if the reason reaches
## the log, so each refusal's words are asserted, not just its return value.
## The placement is aimed at a *free* tile, so the phase is the only thing that
## can refuse it.
func _step_refuse_during_wave() -> void:
	_case("planted failure A: place, upgrade and sell are refused during a wave")
	_arena.begin_wave()
	check(_arena.is_wave_active(), "the arena is in the wave phase")

	var gold_before: int = _arena.gold()
	var tier_before := _tower.tier()
	var towers_before: int = _arena.towers().size()
	var free_before: int = _arena.free_slot_count()
	var refused_count_before: int = _arena.refused_count()
	var free_tile := _slots[1]

	var placed = _arena.place_tower(free_tile.world_position())
	print("TOWER_DEMO_REFUSED " + _arena.last_refusal())
	check(placed == null, "placing during a wave is refused")
	check(
		_arena.last_refusal().find("locked during a wave") != -1,
		"the placement refusal says towers are locked during a wave"
	)

	var upgraded: bool = _arena.upgrade_tower(_tower)
	print("TOWER_DEMO_REFUSED " + _arena.last_refusal())
	check(not upgraded, "upgrading during a wave is refused")
	check(
		_arena.last_refusal().find("locked during a wave") != -1,
		"the upgrade refusal says towers are locked during a wave"
	)

	var sold: bool = _arena.take_tower_back(_tower)
	print("TOWER_DEMO_REFUSED " + _arena.last_refusal())
	check(not sold, "taking a tower back during a wave is refused")
	check(
		_arena.last_refusal().find("locked during a wave") != -1,
		"the take-back refusal says towers are locked during a wave"
	)

	check_eq_int(
		_arena.refused_count(), refused_count_before + 3, "all three build actions were refused"
	)
	check_eq_int(_arena.gold(), gold_before, "no refused build action moved the purse")
	check_eq_int(_tower.tier(), tier_before, "the tower did not change tier")
	check_eq_int(_arena.towers().size(), towers_before, "the tower is still standing")
	check_eq_int(_arena.free_slot_count(), free_before, "no tile was filled")
	check(is_instance_valid(_tower), "the tower the wave refused to sell is still valid")
	_step("refused_during_wave", {
		"phase": _arena.phase_name(),
		"refusals": _arena.refused_count(),
		"gold": _arena.gold(),
	})


# --- 5: end the wave, kill a walker -----------------------------------------

func _step_kill() -> void:
	_case("end the wave, then kill a walker with the tower")
	_arena.end_wave()
	check(not _arena.is_wave_active(), "the arena is back in the build phase")

	# One enemy the demo owns. The arena also spawns one at boot; that walker is
	# at the lane start, outside the tower's range, so the only in-range
	# candidate here is the demo's own.
	_victim = _arena.spawn_walker()
	if not check(_victim != null, "an enemy can be spawned for the demo"):
		return
	var at := _lane_point_near(_tower.global_position)
	_victim.global_position = at
	check(
		_tower.global_position.distance_to(_victim.global_position) <= _tower.range_px(),
		"the demo's enemy stands inside the tower's range"
	)

	var shots_before := _tower.shots_fired()
	var gold_before: int = _arena.gold()
	var ticks := 0
	while _victim.is_alive() and ticks < MAX_KILL_TICKS:
		_tower.tick(TICK_SECONDS)
		ticks += 1
	if not check(not _victim.is_alive(), "the tower killed the walker within %d ticks" % MAX_KILL_TICKS):
		return
	check(_tower.shots_fired() > shots_before, "the tower fired at it")
	check_eq_int(_arena.killed_count(), 1, "the arena counted exactly one kill")

	_expect_gold = gold_before + maxi(_victim.gold_reward, 0)
	check_eq_int(_arena.gold(), _expect_gold, "the kill paid the walker's reward")
	_step("killed", {
		"walker": _victim.name,
		"ticks": ticks,
		"reward": _victim.gold_reward,
		"gold": _arena.gold(),
	})


# --- 5b: earn the gold the upgrade costs ------------------------------------

## Placement is free, so the purse at this point is the run's 10-gold start plus
## the reward of the one walker the tower just killed. The next tier costs 60, so
## the demo earns the difference the same way the game does: it kills more
## walkers. Nothing here writes a balance directly - every coin comes through
## `ARENA_KILL` and the ledger view.
func _step_earn_for_upgrade() -> void:
	_case("earn the gold for the next tier from kills")
	var price: int = _tower.upgrade_cost()
	if not check(price > 0, "the tower quotes a price for its next tier"):
		return
	var killed := 0
	var earned := 0
	while _arena.gold() < price and killed < MAX_EARN_KILLS:
		var walker = _arena.spawn_walker()
		if not check(walker != null, "an enemy can be spawned to pay for the tier"):
			return
		earned += maxi(walker.gold_reward, 0)
		# Killed outright: the demo is buying gold, not testing the tower twice.
		walker.take_damage(LETHAL_DAMAGE)
		killed += 1
	if not check(
		_arena.gold() >= price,
		"the run can afford the %d gold tier (gold is %d after %d kill(s))"
		% [price, _arena.gold(), killed]
	):
		return
	_expect_gold = _arena.gold()
	_step("earned", {"price": price, "kills": killed, "earned": earned, "gold": _arena.gold()})


# --- 6: upgrade -------------------------------------------------------------

func _step_upgrade() -> void:
	_case("upgrade the tower")
	var price := _tower.upgrade_cost()
	var tier_before := _tower.tier()
	if not check(price > 0, "the tower quotes a price for its next tier"):
		return
	var upgraded: bool = _arena.upgrade_tower(_tower)
	check(upgraded, "the upgrade is accepted in the build phase")
	_expect_gold -= maxi(price, 0)
	check_eq_int(_arena.gold(), _expect_gold, "the upgrade spent exactly upgrade_cost")
	check_eq_int(_tower.tier(), tier_before + 1, "the tower went up one tier")
	check_eq_int(_instance.tier, _tower.tier(), "the inventory instance carries the new tier")
	# Placement is free, so the only gold this tower ever cost is the upgrade it
	# bought - the number the take-back below must leave untouched.
	check_eq_int(_tower.invested(), price, "the tower remembers the upgrade it was paid for")
	_step("upgraded", {"tier": _tower.tier(), "paid": price, "gold": _arena.gold()})


# --- 7: planted failure B ---------------------------------------------------

## T-0036 DoD 4. The targeting rule is forced to return a dead enemy as the
## tower's only candidate. The tower must record a hold, fire nothing, pay
## nothing and stay alive - the corpse only exists as a valid node because no
## frame has passed since it died, which is exactly the window a tower holding a
## target across frames sees.
func _step_hold_fire() -> void:
	_case("planted failure B: a dead enemy is a hold, not a shot")
	var corpse := _victim
	if not check(corpse != null and is_instance_valid(corpse), "the corpse is still a valid node"):
		return
	check(not corpse.is_alive(), "the corpse is not alive")

	_tower.candidate_source = func() -> Array: return [corpse]

	var shots_before := _tower.shots_fired()
	var held_before := _tower.held_shots()
	_tower.tick(TICK_SECONDS)

	print("TOWER_DEMO_HOLD " + JSON.stringify({
		"tower": _tower.name,
		"why": _tower.last_hold_reason(),
		"shots_before": shots_before,
		"shots_after": _tower.shots_fired(),
		"held_before": held_before,
		"held_after": _tower.held_shots(),
		"gold": _arena.gold(),
	}))
	check_eq_int(_tower.held_shots(), held_before + 1, "the tower recorded exactly one held shot")
	check_eq_int(_tower.shots_fired(), shots_before, "no shot was fired at the corpse")
	check(_tower.last_hold_reason() != "", "the hold carries a reason")
	check(
		_tower.last_hold_reason().find("not alive") != -1,
		"the reason says the enemy is not alive"
	)
	check_eq_int(_arena.gold(), _expect_gold, "a held shot pays no gold")
	check(is_instance_valid(_tower), "the tower survived the corpse")


# --- 8: take back -----------------------------------------------------------

## T-0045's round trip, on the map and not only in the inventory: taking a tower
## back is **not** a sale. It pays nothing in either direction, the tile frees,
## and the instance keeps its tier and its upgrades - so putting it down again
## puts down the tower the player built, not a tier-1 copy of it. Selling for a
## refund no longer exists, which is why this step asserts "no gold moved"
## instead of reconciling a refund against `invested()`.
func _step_take_back() -> void:
	_case("take the tower back into the inventory")
	var tier_before := _tower.tier()
	var upgrades_before: Array = _instance.upgrade_type_ids()
	var invested_before: int = _tower.invested()
	if not check(
		tier_before > 1,
		"the tower being taken back had been upgraded (tier %d)" % tier_before
	):
		return
	var gold_before: int = _arena.gold()

	var taken: bool = _arena.take_tower_back(_tower)
	check(taken, "the take-back is accepted in the build phase")
	check_eq_int(_arena.gold(), gold_before, "taking a tower back pays nothing")
	check_eq_int(_arena.towers().size(), 0, "the tower is gone from the arena")
	check_eq_int(_arena.free_slot_count(), _slots.size(), "every build tile is free again")
	check(not _instance.placed, "the instance is back in the inventory, not on the map")
	check_eq_int(_instance.tier, tier_before, "the taken-back tower kept its tier")
	check_eq_int(
		_instance.upgrade_count(),
		upgrades_before.size(),
		"the taken-back tower kept its upgrade"
	)
	check(
		_instance.upgrade_type_ids() == upgrades_before,
		"the upgrade it kept is the one it had (%s)" % [_instance.upgrade_type_ids()]
	)
	_step("taken_back", {
		"tier": _instance.tier,
		"upgrades": _instance.upgrade_type_ids(),
		"invested": invested_before,
		"gold": _arena.gold(),
	})

	# And back down again, at the tier it left. A take-back that lost the tier
	# would only show up here, on the map the player actually sees.
	var replanted: Tower = _arena.place_tower(_slot.world_position(), _instance.id)
	if not check(replanted != null, "the taken-back tower can be placed again"):
		return
	check_eq_int(replanted.tier(), tier_before, "it stands again at the tier it was taken back at")
	check_eq_int(_instance.upgrade_count(), upgrades_before.size(), "it still carries its upgrade")
	check_eq_int(_arena.gold(), gold_before, "placing it again costs nothing")
	_step("replaced", {
		"tower": replanted.name,
		"tier": replanted.tier(),
		"upgrades": _instance.upgrade_type_ids(),
		"gold": _arena.gold(),
	})


# --- 9: the ledger reconciles -----------------------------------------------

func _step_reconcile() -> void:
	_case("the gold ledger reconciles")
	var ledger := _resolve_ledger()
	if not check(ledger != null, "the arena's ledger is reachable"):
		return

	var earned := ledger.total_earned()
	var spent := ledger.total_spent()
	var closing := ledger.gold()
	var reconciled := _opening_gold + earned - spent == closing

	print("TOWER_DEMO_LEDGER " + JSON.stringify({
		"opening": _opening_gold,
		"earned": earned,
		"spent": spent,
		"closing": closing,
		"expected_closing": _opening_gold + earned - spent,
		"reconciled": reconciled,
	}))
	check(
		reconciled,
		"opening %d + earned %d - spent %d == closing %d (got %d)"
		% [_opening_gold, earned, spent, _opening_gold + earned - spent, closing]
	)
	check_eq_int(closing, _expect_gold, "the ledger matches the balance the demo expected")
	check_eq_int(_hq.health(), _hq.max_health, "no walker leaked while the tower stood")

	var passed := _failures.is_empty()
	print("TOWER_DEMO_SUMMARY " + JSON.stringify({
		"opening": _opening_gold,
		"earned": earned,
		"spent": spent,
		"closing": closing,
		"kills": _arena.killed_count(),
		"refusals": _arena.refused_count(),
		"towers_left": _arena.towers().size(),
		"status": "pass" if passed else "fail",
	}))


# --- scene wiring -----------------------------------------------------------

func _resolve_hq() -> Hq:
	var declared = _arena.get("hq_path")
	if declared is NodePath and not (declared as NodePath).is_empty():
		return _arena.get_node_or_null(declared) as Hq
	return null


func _resolve_ledger() -> GoldLedger:
	var declared = _arena.get("ledger_path")
	if declared is NodePath and not (declared as NodePath).is_empty():
		return _arena.get_node_or_null(declared) as GoldLedger
	return null


## Build tiles are discovered by type, never by node path: adding a tile is a
## scene edit and must not change this harness.
func _collect_slots() -> Array[BuildSlot]:
	var found: Array[BuildSlot] = []
	for child in _arena.get_children():
		var slot := child as BuildSlot
		if slot != null:
			found.append(slot)
	return found


## The point on the lane centreline closest to `from`. The lane is the arena's
## geometry, so both "a point on the lane" and "a spot inside tower range" are
## derived from it rather than written down here.
func _lane_point_near(from: Vector2) -> Vector2:
	var points := PackedVector2Array(_arena.get("lane_points"))
	if points.is_empty():
		return from
	var best := points[0]
	var best_distance := from.distance_to(points[0])
	for i in maxi(points.size() - 1, 0):
		var closest := Geometry2D.get_closest_point_to_segment(from, points[i], points[i + 1])
		var distance := from.distance_to(closest)
		if distance < best_distance:
			best = closest
			best_distance = distance
	return best


# --- reporting --------------------------------------------------------------

func _case(step_name: String) -> void:
	print("TOWER_DEMO_CASE " + step_name)


func _step(step_name: String, extra: Dictionary = {}) -> void:
	var payload: Dictionary = {"step": step_name, "gold": _arena.gold()}
	payload.merge(extra, false)
	print("TOWER_DEMO_STEP " + JSON.stringify(payload))


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
	print("TOWER_DEMO_SELF_TEST " + JSON.stringify({
		"name": "tower_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("TOWER_DEMO_FAILURE " + f)
	quit(1)
