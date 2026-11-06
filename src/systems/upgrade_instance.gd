class_name UpgradeInstance
extends RefCounted

## One upgrade the player owns (T-0041).
##
## CONTRACT
## --------
## * An upgrade instance is **identity plus a type id**, and nothing else. What an
##   upgrade *does* (damage multiplier, range bonus, price) is content and lives
##   with the caller's store data, not here: this object never learns what a
##   "sharpen" is, only that one exists and who holds it (`type_id`).
## * Two upgrades of the same type are two distinct instances with distinct `id`s.
##   Duplicate instances are legal; whether a tower may carry two of the same type
##   is `Inventory`'s rule, not this object's.
## * Where an instance is (in hand, or attached to a tower) is recorded in exactly
##   one place: the owning `TowerInstance.upgrades` list, or the inventory's pool.
##   This object carries no `attached_to` field on purpose - a second copy of that
##   fact is a second owner, and the two would drift.
## * `id` is assigned by `Inventory` and is unique for the life of a run. It is an
##   int, so a snapshot or a log line is stable and greppable.

var id: int = 0
var type_id: String = ""


static func create(p_id: int, p_type_id: String) -> UpgradeInstance:
	var upgrade := UpgradeInstance.new()
	upgrade.id = p_id
	upgrade.type_id = p_type_id
	return upgrade


func snapshot() -> Dictionary:
	return {"id": id, "type_id": type_id}
