class_name TowerInstance
extends RefCounted

## One tower the player owns (T-0041).
##
## CONTRACT
## --------
## * A tower instance carries everything that has to survive being picked up and
##   put down again: its type (`type_id`), its `tier`, how many upgrade slots it
##   has (`upgrade_slots`), and the upgrades attached to it (`upgrades`). It
##   carries no position, no scene node and no stats: where a tower stands is the
##   map's business, what it does is the tower scene's business, and neither is
##   re-derived here.
## * `upgrade_slots` is **data**: two is the current rule (T-0041), but the count
##   is passed in by `Inventory.add_tower()` and never branched on in code, so a
##   three-slot tower or a zero-slot tower needs no edit here. A slot count below
##   zero is rejected by the inventory, not silently repaired.
## * `upgrades` is the **single owner** of "which upgrades sit on which tower".
##   `attach_upgrade()` and `detach_upgrade()` are written by `Inventory` and by
##   nothing else; the array is exposed read-only through `upgrades()` and
##   `upgrade_at()`. A caller that pushes into the list directly has defeated the
##   duplicate rule and the slot count in one line.
## * `placed` and `location` are written only by `Inventory.place_tower()` and
##   `Inventory.take_tower_back()`; the map passes the location string and does
##   not keep a second copy of "which tower is where".
## * Tier is a plain int, raised by `Inventory.raise_tower_tier()`. The cost and
##   the timing (between waves, on a map) belong to the caller; this object only
##   records the result, which is what makes the round trip in T-0041 DoD 6 work.

var id: int = 0
var type_id: String = ""
var tier: int = 1
var upgrade_slots: int = 0
var placed: bool = false
var location: String = ""

var _upgrades: Array = []


static func create(
	p_id: int, p_type_id: String, p_tier: int, p_upgrade_slots: int
) -> TowerInstance:
	var tower := TowerInstance.new()
	tower.id = p_id
	tower.type_id = p_type_id
	tower.tier = p_tier
	tower.upgrade_slots = p_upgrade_slots
	return tower


# --- upgrades on this tower -------------------------------------------------

## Copy of the attached upgrades, oldest first. Shallow: the instances are the
## same objects, which is the point - the caller reads them, the inventory owns
## the list.
func upgrades() -> Array:
	return _upgrades.duplicate()


func upgrade_count() -> int:
	return _upgrades.size()


func upgrade_at(index: int) -> RefCounted:
	if index < 0 or index >= _upgrades.size():
		return null
	return _upgrades[index]


func free_slots() -> int:
	return maxi(upgrade_slots - _upgrades.size(), 0)


func has_free_slot() -> bool:
	return free_slots() > 0


func is_full() -> bool:
	return free_slots() == 0


func slot_count() -> int:
	return upgrade_slots


## How many attached upgrades are of `p_type_id`. This is the number the duplicate
## rule is decided on, and it counts instances, not types.
func count_upgrade_type(p_type_id: String) -> int:
	var total := 0
	for upgrade in _upgrades:
		if upgrade.type_id == p_type_id:
			total += 1
	return total


func index_of_upgrade(upgrade_id: int) -> int:
	for i in _upgrades.size():
		if _upgrades[i].id == upgrade_id:
			return i
	return -1


## Inventory-only. Returns false when the slot count is already used up.
func attach_upgrade(upgrade: RefCounted) -> bool:
	if upgrade == null or not has_free_slot() or index_of_upgrade(upgrade.id) != -1:
		return false
	_upgrades.append(upgrade)
	return true


## Inventory-only. Returns the detached instance, or null when it is not attached.
func detach_upgrade(upgrade_id: int) -> RefCounted:
	var index := index_of_upgrade(upgrade_id)
	if index == -1:
		return null
	var upgrade: RefCounted = _upgrades[index]
	_upgrades.remove_at(index)
	return upgrade


## Every attached upgrade's type id, in slot order. Used by the round-trip check
## and by anything that has to compare two towers' loadouts.
func upgrade_type_ids() -> Array:
	var ids: Array = []
	for upgrade in _upgrades:
		ids.append(upgrade.type_id)
	return ids


func upgrade_ids() -> Array:
	var ids: Array = []
	for upgrade in _upgrades:
		ids.append(upgrade.id)
	return ids


func snapshot() -> Dictionary:
	var attached: Array = []
	for upgrade in _upgrades:
		attached.append(upgrade.snapshot())
	return {
		"id": id,
		"type_id": type_id,
		"tier": tier,
		"upgrade_slots": upgrade_slots,
		"free_slots": free_slots(),
		"upgrades": attached,
		"placed": placed,
		"location": location,
	}
