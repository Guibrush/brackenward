class_name Inventory
extends RefCounted

## What the player owns, for exactly one run (T-0041).
##
## CONTRACT
## --------
## * A caller creates one `Inventory` per run, next to `RunState`, and keeps the
##   reference for the life of that run. Plain object: not an autoload, not a node,
##   no global. The code that starts the run owns the instance and there is exactly
##   one. Nothing is written to disk and nothing survives the run (CHARTER,
##   non-goals): there is no save path and deliberately no dictionary round-trip.
##   The "round trip" this object does support is placement: a tower taken back off
##   the map and put down again keeps its tier and its upgrades, because the tower
##   instance - not the map node - is where both live.
## * This object owns three pieces of mutable state and nothing else owns them:
##   the tower instances the player holds, the upgrades that are in hand (not
##   attached to a tower), and the id counters. A tower owns its own `tier` and its
##   own attached upgrades; the map owns where a placed tower stands on screen.
##   `placed`/`location` on the instance are written only here, by `place_tower()`
##   and `take_tower_back()`.
## * Acquiring is free of any placement rule: `add_tower()` and `add_upgrade()`
##   only say the player owns the thing. `place_tower()` is free - it consumes no
##   gold, no slot and no turn - and the same instance can be placed, taken back
##   and placed again. Whether it is legal *when* is the caller's problem.
## * Duplicates are allowed: two towers of the same `type_id` are two instances,
##   and `add_tower()` has no duplicate check at all. Two upgrades of the same type
##   on one tower are allowed while `allow_duplicate_upgrades()` is true (the
##   default) and refused per-tower, with a reason, while it is false.
## * Upgrades become permanent once applied: `remove_upgrade_from_tower()` refuses
##   while `allow_upgrade_removal()` is false, and `replace_upgrade_in_tower()`
##   destroys the upgrade it displaces instead of returning it to hand. Both are
##   flags and an explicit destroy list, not a hardcode, so the permanence rule can
##   be reversed later without touching the call sites: flip the flag and removal
##   starts returning the upgrade to hand.
## * The inventory is uncapped while `tower_cap()` is 0 (the default) and capped on
##   towers alone when it is N > 0: the N+1th `add_tower()` is refused and adds
##   nothing. Upgrades in hand are not capped; nothing in T-0041 asks for that, and
##   a second count would need its own rule.
##
## CALLERS MUST
## ------------
## * Check the bool returned by every mutation and show `last_refusal()` to the
##   player or the log. A refusal is never silent: it is stored and also emitted on
##   `refused`. Cap hit, duplicate blocked and removal blocked are normal play, so
##   they are not WARNING lines; a bad id, a negative count or a full slot asked to
##   take a third upgrade is a programmer error and prints in a development build.
## * Read tiers and loadouts from the tower instances this object hands out, and
##   mutate them only through `raise_tower_tier()`, `apply_upgrade_to_tower()`,
##   `replace_upgrade_in_tower()` and `remove_upgrade_from_tower()`. Assigning
##   `tower.tier` or pushing into `tower.upgrades()` directly skips the slot count
##   and the duplicate rule.
## * Apply upgrades and raise tiers only on a map, between waves. This object does
##   not know what a wave is and cannot enforce the timing; it exposes the
##   operations and the caller orders them.
## * Treat an instance as owned by this object: do not hold a tower after the
##   inventory that created it has gone out of scope, and do not build a second
##   inventory for the same run.
##
## No number in this file is real. Each carries the PLACEHOLDER marker so replacing
## it is a search, not a hunt (design/systems owns the tuning tables).

signal refused(reason: String)
signal contents_changed()

## PLACEHOLDER (design/systems, upgrade tables): how many upgrades one tower holds
## when the caller does not pass a count. T-0041 says two; the count is a parameter
## of `add_tower()` and is never branched on, so this is a default, not a rule.
const DEFAULT_UPGRADE_SLOTS := 2
## PLACEHOLDER (design/systems, economy): towers the inventory holds once the cap
## is switched on at N. Unused while the cap is off, which is the default.
const DEFAULT_TOWER_CAP := 12

## Ids start at 1 so that 0 can mean "no tower" / "in hand" in returned values.
const FIRST_ID := 1

# Preloaded rather than referenced by class name so `--check-only` does not depend
# on the global class cache having been built by a prior `--import`.
const TowerInstanceScript := preload("res://src/systems/tower_instance.gd")
const UpgradeInstanceScript := preload("res://src/systems/upgrade_instance.gd")


var _towers: Array = []
var _upgrades: Array = []
var _destroyed: Array = []
var _next_tower_id: int = FIRST_ID
var _next_upgrade_id: int = FIRST_ID
var _last_refusal: String = ""

# --- settings: counts and toggles -------------------------------------------
# Plain vars with a validating setter, so a caller can flip a rule at runtime
# (that is how the permanence rule gets reversed later) and cannot store an
# impossible value by assignment alone.

## PLACEHOLDER (design/systems, upgrade tables): default slots for a new tower.
var default_upgrade_slots: int = DEFAULT_UPGRADE_SLOTS
## PLACEHOLDER (design/systems, economy): towers held before `add_tower()` refuses.
## 0 means uncapped, which is the rule for now.
var tower_cap: int = 0
## PLACEHOLDER (design/systems, upgrade tables): may one tower carry two copies of
## the same upgrade? T-0041 allows it today.
var allow_duplicate_upgrades: bool = true
## PLACEHOLDER (design/systems, upgrade tables): the permanence rule. False keeps
## an applied upgrade on the tower for the run; true lets it go back to hand.
var allow_upgrade_removal: bool = false


# --- settings ---------------------------------------------------------------

func set_default_upgrade_slots(count: int) -> bool:
	if count < 0:
		return _refuse(
			"set the default upgrade slot count", "a slot count cannot be negative, got %d" % count, true
		)
	default_upgrade_slots = count
	contents_changed.emit()
	return true


## Turns the cap on at `cap` towers. `0` switches it off again.
func set_tower_cap(cap: int) -> bool:
	if cap < 0:
		return _refuse(
			"set the tower cap", "the cap cannot be negative, got %d (use 0 for no cap)" % cap, true
		)
	tower_cap = cap
	contents_changed.emit()
	return true


func is_capped() -> bool:
	return tower_cap > 0


func set_duplicate_upgrades_allowed(value: bool) -> void:
	allow_duplicate_upgrades = value
	contents_changed.emit()


func set_upgrade_removal_allowed(value: bool) -> void:
	allow_upgrade_removal = value
	contents_changed.emit()


# --- acquiring --------------------------------------------------------------

## Adds a tower instance to the inventory and returns it, or null when the cap
## refuses the call. Duplicates are not checked: the same `type_id` twice is two
## towers, which is the rule.
##
## `upgrade_slots` of -1 means "use `default_upgrade_slots`". The count is stored
## on the instance, so a tower built with three slots keeps three.
func add_tower(type_id: String, tier: int = 1, upgrade_slots: int = -1) -> RefCounted:
	if type_id == "":
		_refuse("add a tower", "every tower needs a type id; got an empty one", true)
		return null
	if tier < 1:
		_refuse("add tower %s" % type_id, "tier starts at 1, got %d" % tier, true)
		return null

	var slots := default_upgrade_slots if upgrade_slots == -1 else upgrade_slots
	if slots < 0:
		_refuse(
			"add tower %s" % type_id, "upgrade slots cannot be negative, got %d" % slots, true
		)
		return null
	if is_capped() and _towers.size() >= tower_cap:
		# Player-facing: the cap is a rule the player can hit in normal play.
		_refuse(
			"add tower %s" % type_id,
			"the inventory holds %d of %d towers (cap on)" % [_towers.size(), tower_cap],
			false
		)
		return null

	var tower := TowerInstanceScript.create(_next_tower_id, type_id, tier, slots)
	_next_tower_id += 1
	_towers.append(tower)
	contents_changed.emit()
	return tower


## Adds an upgrade to the pool in hand. Duplicates are allowed and uncapped: a
## second copy is a second instance with its own id.
func add_upgrade(type_id: String) -> RefCounted:
	if type_id == "":
		_refuse("add an upgrade", "every upgrade needs a type id; got an empty one", true)
		return null

	var upgrade := UpgradeInstanceScript.create(_next_upgrade_id, type_id)
	_next_upgrade_id += 1
	_upgrades.append(upgrade)
	contents_changed.emit()
	return upgrade


# --- placement (free) -------------------------------------------------------

## Marks a tower as standing at `location`. Free: no gold, no slot, no state lost.
## Idempotence is refused rather than ignored, because a double-placement call is
## a caller bug that would otherwise hide a lost tower.
func place_tower(tower_id: int, location: String = "") -> bool:
	var tower: RefCounted = find_tower(tower_id)
	if tower == null:
		return _refuse("place tower %d" % tower_id, "no such tower in the inventory", true)
	if tower.placed:
		return _refuse(
			"place tower %d" % tower_id,
			"it is already placed at %s" % (_location_or(tower, "no location")),
			true
		)
	tower.placed = true
	tower.location = location
	contents_changed.emit()
	return true


## Picks a placed tower back up into the inventory. Keeps `tier` and every
## attached upgrade untouched - this is the half of the round trip in DoD 6.
func take_tower_back(tower_id: int) -> bool:
	var tower: RefCounted = find_tower(tower_id)
	if tower == null:
		return _refuse("take tower %d back" % tower_id, "no such tower in the inventory", true)
	if not tower.placed:
		return _refuse(
			"take tower %d back" % tower_id, "it is not on the map; it is already in the inventory", true
		)
	tower.placed = false
	tower.location = ""
	contents_changed.emit()
	return true


# --- tiers and upgrades (on a map, between waves) ---------------------------

## Raises a tower's tier by `amount` and returns the new tier, 0 when refused.
## Cost and timing are the caller's `RunState.spend_gold()` and its own schedule.
func raise_tower_tier(tower_id: int, amount: int = 1) -> int:
	var tower: RefCounted = find_tower(tower_id)
	if tower == null:
		_refuse("raise the tier of tower %d" % tower_id, "no such tower in the inventory", true)
		return 0
	if amount < 1:
		_refuse("raise the tier of tower %d" % tower_id, "amount must be positive, got %d" % amount, true)
		return 0
	tower.tier += amount
	contents_changed.emit()
	return tower.tier


## Moves an upgrade from hand onto a tower. Refused, with a reason and no change,
## when the tower has no free slot, or when duplicates are switched off and the
## tower already carries this type.
func apply_upgrade_to_tower(tower_id: int, upgrade_id: int) -> bool:
	var tower: RefCounted = find_tower(tower_id)
	if tower == null:
		return _refuse(
			"apply upgrade %d to tower %d" % [upgrade_id, tower_id],
			"no such tower in the inventory",
			true
		)
	var upgrade: RefCounted = _find_in_hand(upgrade_id)
	if upgrade == null:
		return _refuse(
			"apply upgrade %d to tower %d" % [upgrade_id, tower_id],
			"it is not in hand (never acquired, or already on a tower)",
			true
		)
	if not tower.has_free_slot():
		return _refuse(
			"apply upgrade %s to tower %d" % [upgrade.type_id, tower_id],
			"no free upgrade slot (%d of %d used); replace one instead"
			% [tower.upgrade_count(), tower.slot_count()],
			false
		)
	if not allow_duplicate_upgrades and tower.count_upgrade_type(upgrade.type_id) > 0:
		return _refuse(
			"apply upgrade %s to tower %d" % [upgrade.type_id, tower_id],
			"the tower already carries %s and duplicate upgrades are switched off"
			% upgrade.type_id,
			false
		)

	_take_from_hand(upgrade_id)
	if not tower.attach_upgrade(upgrade):
		# Unreachable: the slot and duplicate checks above are the only refusals
		# `attach_upgrade()` can apply. Put it back rather than lose an instance.
		_upgrades.append(upgrade)
		return _refuse(
			"apply upgrade %s to tower %d" % [upgrade.type_id, tower_id],
			"the tower refused the upgrade after the checks passed; nothing changed",
			true
		)
	contents_changed.emit()
	return true


## Puts `new_upgrade_id` into `slot_index`, destroying whatever was there. This is
## the "replaced is destroyed" path: the displaced upgrade does not go back to
## hand, it is recorded in `destroyed_upgrades()` and gone.
func replace_upgrade_in_tower(
	tower_id: int, slot_index: int, new_upgrade_id: int
) -> bool:
	var tower: RefCounted = find_tower(tower_id)
	if tower == null:
		return _refuse(
			"replace an upgrade on tower %d" % tower_id, "no such tower in the inventory", true
		)
	if slot_index < 0 or slot_index >= tower.upgrade_count():
		return _refuse(
			"replace upgrade slot %d on tower %d" % [slot_index, tower_id],
			"the tower has %d occupied slot(s)" % tower.upgrade_count(),
			true
		)
	var incoming: RefCounted = _find_in_hand(new_upgrade_id)
	if incoming == null:
		return _refuse(
			"replace upgrade slot %d on tower %d" % [slot_index, tower_id],
			"upgrade %d is not in hand" % new_upgrade_id,
			true
		)
	if not allow_duplicate_upgrades:
		for i in tower.upgrade_count():
			if i == slot_index:
				continue
			if tower.upgrade_at(i).type_id == incoming.type_id:
				return _refuse(
					"replace upgrade %s on tower %d" % [incoming.type_id, tower_id],
					"the tower would then carry two %s and duplicate upgrades are switched off"
					% incoming.type_id,
					false
				)

	var displaced: RefCounted = tower.detach_upgrade(tower.upgrade_at(slot_index).id)
	if displaced != null:
		_destroyed.append({
			"tower": tower_id,
			"upgrade_id": displaced.id,
			"type_id": displaced.type_id,
			"reason": "replaced",
		})
	_take_from_hand(new_upgrade_id)
	tower.attach_upgrade(incoming)
	contents_changed.emit()
	return true


## Takes an applied upgrade back into hand. Refused while the permanence rule is
## on, which is the default: this refusal is the rule, and flipping
## `allow_upgrade_removal` is the whole of reversing it.
func remove_upgrade_from_tower(tower_id: int, upgrade_id: int) -> bool:
	var tower: RefCounted = find_tower(tower_id)
	if tower == null:
		return _refuse(
			"remove upgrade %d from tower %d" % [upgrade_id, tower_id],
			"no such tower in the inventory",
			true
		)
	if tower.index_of_upgrade(upgrade_id) == -1:
		return _refuse(
			"remove upgrade %d from tower %d" % [upgrade_id, tower_id],
			"it is not attached to that tower",
			true
		)
	if not allow_upgrade_removal:
		return _refuse(
			"remove upgrade from tower %d" % tower_id,
			"applied upgrades are permanent for the run; removal is switched off",
			false
		)

	var detached: RefCounted = tower.detach_upgrade(upgrade_id)
	if detached == null:
		return _refuse(
			"remove upgrade %d from tower %d" % [upgrade_id, tower_id],
			"the tower refused to detach it; nothing changed",
			true
		)
	_upgrades.append(detached)
	contents_changed.emit()
	return true


# --- queries ----------------------------------------------------------------

func tower_count() -> int:
	return _towers.size()


## Every tower instance held, placed or not, in acquisition order. Shallow copy:
## the instances are the inventory's, and a caller must not treat the array as a
## place to add or remove towers.
func towers() -> Array:
	return _towers.duplicate()


func find_tower(tower_id: int) -> RefCounted:
	for tower in _towers:
		if tower.id == tower_id:
			return tower
	return null


func count_towers_of_type(type_id: String) -> int:
	var total := 0
	for tower in _towers:
		if tower.type_id == type_id:
			total += 1
	return total


func is_at_cap() -> bool:
	return is_capped() and _towers.size() >= tower_cap


func upgrade_count() -> int:
	return _upgrades.size()


## Upgrades in hand - acquired, not attached to a tower - oldest first.
func upgrades() -> Array:
	return _upgrades.duplicate()


func find_upgrade_in_hand(upgrade_id: int) -> RefCounted:
	return _find_in_hand(upgrade_id)


func count_upgrades_in_hand_of_type(type_id: String) -> int:
	var total := 0
	for upgrade in _upgrades:
		if upgrade.type_id == type_id:
			total += 1
	return total


## Tower id that holds `upgrade_id`, or 0 when the upgrade is in hand. Derived by
## search: the tower's own list is the only record of attachment.
func find_upgrade_holder(upgrade_id: int) -> int:
	for tower in _towers:
		if tower.index_of_upgrade(upgrade_id) != -1:
			return tower.id
	return 0


## Every upgrade destroyed by `replace_upgrade_in_tower()` this run, oldest first:
## `{"tower": int, "upgrade_id": int, "type_id": String, "reason": String}`. A copy,
## so a caller cannot rewrite history.
func destroyed_upgrades() -> Array:
	return _destroyed.duplicate(true)


# --- diagnostics ------------------------------------------------------------

func last_refusal() -> String:
	return _last_refusal


## Everything a store screen, a HUD or a test wants, in one dictionary.
func snapshot() -> Dictionary:
	var towers_out: Array = []
	for tower in _towers:
		towers_out.append(tower.snapshot())
	var hand_out: Array = []
	for upgrade in _upgrades:
		hand_out.append(upgrade.snapshot())
	return {
		"tower_count": _towers.size(),
		"placed_count": _placed_count(),
		"upgrade_count": _upgrades.size(),
		"towers": towers_out,
		"upgrades_in_hand": hand_out,
		"tower_cap": tower_cap,
		"capped": is_capped(),
		"default_upgrade_slots": default_upgrade_slots,
		"allow_duplicate_upgrades": allow_duplicate_upgrades,
		"allow_upgrade_removal": allow_upgrade_removal,
		"destroyed_upgrades": _destroyed.size(),
		"last_refusal": _last_refusal,
	}


# --- internals --------------------------------------------------------------

func _find_in_hand(upgrade_id: int) -> RefCounted:
	for upgrade in _upgrades:
		if upgrade.id == upgrade_id:
			return upgrade
	return null


func _take_from_hand(upgrade_id: int) -> RefCounted:
	for i in _upgrades.size():
		if _upgrades[i].id == upgrade_id:
			var upgrade: RefCounted = _upgrades[i]
			_upgrades.remove_at(i)
			return upgrade
	return null


func _placed_count() -> int:
	var total := 0
	for tower in _towers:
		if tower.placed:
			total += 1
	return total


func _location_or(tower: RefCounted, fallback: String) -> String:
	return fallback if tower.location == "" else tower.location


## One place where refusals are worded, stored and emitted. Returns false so
## callers can `return _refuse(...)`.
##
## `loud` is for calls the contract forbids: an unknown id, a negative count, a
## third upgrade into two slots. Those print in a development build and stay
## silent in a release build. A cap hit, a blocked duplicate and a blocked removal
## are normal play, never loud; the caller puts that reason in the shop UI.
func _refuse(action: String, why: String, loud: bool) -> bool:
	_last_refusal = "cannot %s: %s" % [action, why]
	refused.emit(_last_refusal)
	if loud and OS.is_debug_build():
		print("INV_REFUSED " + _last_refusal)
	return false
