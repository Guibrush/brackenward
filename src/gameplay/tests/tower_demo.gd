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
## The `ARENA_REFUSED`, `ARENA_PLACED`, `ARENA_KILL`, `ARENA_SOLD` and
## `TOWER_HOLD` lines in this output are printed by the systems under test, not by
## this file. That is the point: the demo shows what the game says, not what the
## demo claims. The `TOWER_DEMO_REFUSED` echo exists only so a reader of the log
## does not have to decode JSON to see the words that refused the input.
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

var _arena = null
var _hq: Hq = null
var _slots: Array[BuildSlot] = []
var _slot: BuildSlot = null
var _tower: Tower = null
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

	# Let the new node run `_ready` before its investment is read: `refund_value()`
	# is computed from `invested()`, which `_ready` seeds. Without this wait the
	# demo would sell a tower that thinks it cost nothing.
	await process_frame
	await physics_frame
	check_eq_int(_tower.invested(), _tower.place_cost, "a placed tower knows what it cost")

	_step_refuse_on_lane()
	_step_refuse_occupied()
	_step_refuse_during_wave()
	_step_kill()
	_step_upgrade()
	_step_hold_fire()
	_step_sell()
	_step_reconcile()


# --- 1: place ---------------------------------------------------------------

func _step_place() -> void:
	_case("place a tower on a build tile")
	_tower = _arena.place_tower(_slot.world_position())
	if not check(_tower != null, "placing on a free tile returns a tower"):
		return
	_expect_gold = _opening_gold - _tower.place_cost
	check_eq_int(_arena.gold(), _expect_gold, "placing a tower spends exactly place_cost")
	check(not _slot.is_free(), "the tile the tower stands on is no longer free")
	check_eq_int(
		_arena.free_slot_count(), _slots.size() - 1, "one build tile fewer is free"
	)
	_step("placed", {"tower": _tower.name, "slot": _slot.name, "cost": _tower.place_cost})


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

	var sold: bool = _arena.sell_tower(_tower)
	print("TOWER_DEMO_REFUSED " + _arena.last_refusal())
	check(not sold, "selling during a wave is refused")
	check(
		_arena.last_refusal().find("locked during a wave") != -1,
		"the sell refusal says towers are locked during a wave"
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
	check_eq_int(
		_tower.invested(), _tower.place_cost + price, "the tower remembers both payments"
	)
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


# --- 8: sell ----------------------------------------------------------------

func _step_sell() -> void:
	_case("sell the tower")
	var refund := _tower.refund_value()
	var invested := _tower.invested()
	var gold_before: int = _arena.gold()
	if not check(refund > 0, "the tower has a refund value to pay"):
		return
	check(
		refund <= invested,
		"the refund never exceeds what was invested (%d of %d)" % [refund, invested]
	)

	var sold: bool = _arena.sell_tower(_tower)
	check(sold, "the sell is accepted in the build phase")
	_expect_gold = gold_before + refund
	check_eq_int(_arena.gold(), _expect_gold, "the sell returned exactly refund_value")
	check_eq_int(_arena.towers().size(), 0, "the tower is gone from the arena")
	check_eq_int(_arena.free_slot_count(), _slots.size(), "every build tile is free again")
	_step("sold", {"refund": refund, "invested": invested, "gold": _arena.gold()})


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
