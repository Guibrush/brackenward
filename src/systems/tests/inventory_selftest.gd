extends SceneTree

## Headless proof for `src/systems/inventory.gd` - T-0041 DoD items 2-6.
##
##     godot --headless --path . --script res://src/systems/tests/inventory_selftest.gd
##
## Pure logic, so no scene and no frames: every case runs inside `_initialize`.
##
## Prints, in this order:
##   INV_CASE {name}            which case is running
##   INV_STEP {json}            the inventory state after each step worth recording
##   INV_REFUSED {text}         the reason a refused call gave, verbatim
##   INV_DEMO {json}            a planted-failure / switch demonstration, with both sides
##   INV_TOWER {json}           one tower's snapshot before and after the round trip
##   INV_SELF_TEST {json}       exactly one, last; carries checks and failures
##
## The exit code alone is not evidence (L-035): `INV_SELF_TEST` carries `checks`,
## `failed` and the failure strings, and a failing check also prints an `ERROR:`
## line so a gate that greps for one sees it. Exit 0 = every check passed.
##
## Variables holding the system are left untyped on purpose: GDScript resolves
## member access on an untyped base at runtime, so a renamed field fails loudly
## here instead of being silently accepted as a warning at parse time.

const InventoryScript := preload("res://src/systems/inventory.gd")

const MIN_CHECK_COUNT := 1
const PLACEHOLDER := "(placeholder numbers; design/systems owns the real tables)"

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_case_ownership_and_slots()
	_case_planted_failure_a_cap_on()
	_case_planted_failure_b_duplicate_toggle()
	_case_removal_switch()
	_case_tier_round_trip()
	_case_slots_are_data()
	_finish()


# --- case 1: what the inventory owns, and duplicates (DoD 2) ----------------

func _case_ownership_and_slots() -> void:
	print("INV_CASE ownership_duplicates_and_the_two_slot_rule")
	var inv = InventoryScript.new()
	_step(inv, "empty")

	# Duplicate towers: no toggle, no refusal. Two of the same type are two towers.
	var first = inv.add_tower("arrow")
	var second = inv.add_tower("arrow")
	check(first != null, "a tower can be acquired")
	check(second != null, "a second tower of the same type is acquired too")
	check(first.id != second.id, "duplicate towers are distinct instances")
	check_eq_int(inv.count_towers_of_type("arrow"), 2, "two towers of one type")
	check_eq_int(inv.tower_count(), 2, "both towers are in the inventory")
	check_eq_int(first.slot_count(), 2, "a default tower has two upgrade slots")
	check_eq_int(first.tier, 1, "a new tower starts at tier 1")

	# The third slot does not exist: two is the count, proven by asking for a third.
	var sharpen_a = inv.add_upgrade("sharpen")
	var sharpen_b = inv.add_upgrade("sharpen")
	check_eq_int(inv.upgrade_count(), 2, "two upgrades of one type are in hand")
	check(sharpen_a.id != sharpen_b.id, "duplicate upgrades are distinct instances")
	check(inv.apply_upgrade_to_tower(first.id, sharpen_a.id), "first upgrade applies")
	check(
		inv.apply_upgrade_to_tower(first.id, sharpen_b.id),
		"a duplicate upgrade applies while duplicates are allowed (default)"
	)
	check_eq_int(first.upgrade_count(), 2, "the tower holds both")
	check_eq_int(first.free_slots(), 0, "the tower has no free slot left")
	check(first.is_full(), "is_full() agrees with the slot count")

	var third_upgrade = inv.add_upgrade("range")
	var third_applied: bool = inv.apply_upgrade_to_tower(first.id, third_upgrade.id)
	print("INV_REFUSED " + inv.last_refusal())
	print("INV_DEMO " + JSON.stringify({
		"demo": "third_upgrade_into_two_slots",
		"applied": third_applied,
		"reason": inv.last_refusal(),
		"tower_upgrades": first.upgrade_count(),
		"still_in_hand": inv.upgrade_count(),
	}))
	check(not third_applied, "a third upgrade into two slots is refused")
	check_eq_int(first.upgrade_count(), 2, "the refusal changed nothing on the tower")
	check_eq_int(inv.upgrade_count(), 1, "the refused upgrade is still in hand")
	check(
		inv.last_refusal().find("no free upgrade slot") != -1, "the reason names the full slots"
	)

	# Replacing is the legal way to change a loaded tower, and it destroys the
	# displaced upgrade rather than returning it.
	check(
		inv.replace_upgrade_in_tower(first.id, 0, third_upgrade.id),
		"replacing a slot is allowed when the tower is full"
	)
	check_eq_int(first.upgrade_count(), 2, "the tower still holds two upgrades")
	check_eq_int(inv.upgrade_count(), 0, "the incoming upgrade left the hand")
	var destroyed: Array = inv.destroyed_upgrades()
	check_eq_int(destroyed.size(), 1, "the displaced upgrade was destroyed")
	if destroyed.size() == 1:
		check(
			destroyed[0]["type_id"] == "sharpen",
			"the destroyed upgrade is the one that was replaced"
		)
	check(
		inv.count_upgrades_in_hand_of_type("sharpen") == 0,
		"the destroyed upgrade did not go back to hand"
	)

	# Tiers move, and the cost is the caller's.
	check_eq_int(inv.raise_tower_tier(first.id), 2, "tier rises to 2")
	check_eq_int(inv.raise_tower_tier(first.id), 3, "tier rises to 3")
	check_eq_int(first.tier, 3, "the instance carries the tier")
	check_eq_int(inv.raise_tower_tier(9999), 0, "an unknown tower cannot be tiered up")
	check_eq_int(inv.tower_cap, 0, "the inventory is uncapped by default")
	check(not inv.is_capped(), "is_capped() agrees with the default")
	_step(inv, "after_ownership_case")
	print("INV_SUMMARY " + JSON.stringify({
		"note": PLACEHOLDER,
		"towers": inv.tower_count(),
		"towers_of_type_arrow": inv.count_towers_of_type("arrow"),
		"upgrades_in_hand": inv.upgrade_count(),
		"destroyed": inv.destroyed_upgrades().size(),
		"default_slots": inv.default_upgrade_slots,
	}))


# --- case 2: planted failure A, the cap (DoD 3) ----------------------------

func _case_planted_failure_a_cap_on() -> void:
	print("INV_CASE planted_failure_a_cap_on_at_three_refuses_the_fourth_tower")
	var inv = InventoryScript.new()
	var cap := 3
	check(inv.set_tower_cap(cap), "the cap can be switched on")
	check(inv.is_capped(), "the inventory reports itself capped")
	check_eq_int(inv.tower_cap, cap, "the cap is the count that was set")

	var added: Array = []
	for type_id in ["arrow", "frost", "mortar"]:
		var tower = inv.add_tower(type_id)
		added.append(tower != null)
	check_eq_int(inv.tower_count(), cap, "the inventory filled to exactly the cap")
	check(inv.is_at_cap(), "is_at_cap() is true at the cap")
	check(not added.has(false), "the first three towers were all accepted")

	var before := inv.snapshot()
	var fourth = inv.add_tower("arrow")
	print("INV_REFUSED " + inv.last_refusal())
	print("INV_DEMO " + JSON.stringify({
		"demo": "cap_on_refusal",
		"cap": cap,
		"before_count": before["tower_count"],
		"fourth_added": fourth != null,
		"reason": inv.last_refusal(),
		"after_count": inv.tower_count(),
		"unchanged": before["towers"] == inv.snapshot()["towers"],
	}))
	check(fourth == null, "the N+1th tower is refused")
	check_eq_int(inv.tower_count(), cap, "nothing was added by the refusal")
	check(
		before["towers"] == inv.snapshot()["towers"], "the refused add left the tower list untouched"
	)
	check(inv.last_refusal() != "", "the refusal carries a reason")
	check(
		inv.last_refusal().find("cap on") != -1, "the reason names the cap"
	)
	check(
		inv.last_refusal().find("3 of 3") != -1, "the reason names the count and the cap"
	)

	# The cap is a setting, not a hardcode: switching it off admits the tower.
	check(inv.set_tower_cap(0), "the cap can be switched off again")
	check(inv.add_tower("arrow") != null, "with the cap off the next tower is accepted")
	check_eq_int(inv.tower_count(), cap + 1, "the inventory grew past the old cap")


# --- case 3: planted failure B, duplicate upgrades (DoD 4) -----------------

func _case_planted_failure_b_duplicate_toggle() -> void:
	print("INV_CASE planted_failure_b_duplicate_upgrade_toggle_both_ways")
	var inv = InventoryScript.new()
	var tower = inv.add_tower("arrow")
	var first_upgrade = inv.add_upgrade("sharpen")
	var second_upgrade = inv.add_upgrade("sharpen")

	# --- switch off: the second copy of the same type is refused
	inv.set_duplicate_upgrades_allowed(false)
	check(not inv.allow_duplicate_upgrades, "duplicate upgrades are switched off")
	check(
		inv.apply_upgrade_to_tower(tower.id, first_upgrade.id),
		"the first sharpen still applies with duplicates off"
	)
	var refused_second: bool = inv.apply_upgrade_to_tower(tower.id, second_upgrade.id)
	print("INV_REFUSED " + inv.last_refusal())
	var refusal_with_switch_off := inv.last_refusal()
	print("INV_DEMO " + JSON.stringify({
		"demo": "duplicate_upgrade_refused",
		"allow_duplicate_upgrades": inv.allow_duplicate_upgrades,
		"second_applied": refused_second,
		"reason": refusal_with_switch_off,
		"tower_upgrades": tower.upgrade_type_ids(),
		"still_in_hand": inv.upgrade_count(),
	}))
	check(not refused_second, "with the toggle off the second copy is refused")
	check_eq_int(tower.upgrade_count(), 1, "the refusal left one upgrade on the tower")
	check_eq_int(inv.upgrade_count(), 1, "the refused copy is still in hand")
	check(
		tower.count_upgrade_type("sharpen") == 1, "the tower carries sharpen once, not twice"
	)
	check(
		refusal_with_switch_off.find("duplicate upgrades are switched off") != -1,
		"the reason names the toggle"
	)

	# --- switch on: the same sequence succeeds, on the same tower, same instances
	inv.set_duplicate_upgrades_allowed(true)
	var applied_second: bool = inv.apply_upgrade_to_tower(tower.id, second_upgrade.id)
	print("INV_DEMO " + JSON.stringify({
		"demo": "duplicate_upgrade_allowed",
		"allow_duplicate_upgrades": inv.allow_duplicate_upgrades,
		"second_applied": applied_second,
		"reason_when_refused": "(none; the call succeeded)",
		"tower_upgrades": tower.upgrade_type_ids(),
		"still_in_hand": inv.upgrade_count(),
	}))
	check(applied_second, "with the toggle on the same sequence succeeds")
	check_eq_int(tower.upgrade_count(), 2, "the tower carries two upgrades")
	check_eq_int(tower.count_upgrade_type("sharpen"), 2, "both are sharpen")
	check_eq_int(inv.upgrade_count(), 0, "nothing of the pair is left in hand")
	check(inv.last_refusal() == refusal_with_switch_off, "a success does not rewrite the last reason")


# --- case 4: the removal switch (DoD 5) ------------------------------------

func _case_removal_switch() -> void:
	print("INV_CASE removal_switch_off_refuses_on_returns_the_upgrade")
	var inv = InventoryScript.new()
	var tower = inv.add_tower("frost")
	var upgrade = inv.add_upgrade("chill")
	check(inv.apply_upgrade_to_tower(tower.id, upgrade.id), "the upgrade applies")
	check(not inv.allow_upgrade_removal, "removal is switched off by default (permanent)")
	check_eq_int(inv.find_upgrade_holder(upgrade.id), tower.id, "the tower holds the upgrade")

	# --- switch off: permanence is enforced
	var refused_removal: bool = inv.remove_upgrade_from_tower(tower.id, upgrade.id)
	print("INV_REFUSED " + inv.last_refusal())
	var refusal_with_switch_off := inv.last_refusal()
	print("INV_DEMO " + JSON.stringify({
		"demo": "removal_switch_off",
		"allow_upgrade_removal": inv.allow_upgrade_removal,
		"removed": refused_removal,
		"reason": refusal_with_switch_off,
		"tower_upgrades": tower.upgrade_count(),
		"upgrades_in_hand": inv.upgrade_count(),
		"holder": inv.find_upgrade_holder(upgrade.id),
	}))
	check(not refused_removal, "with the switch off removal is refused")
	check(
		refusal_with_switch_off.find("permanent") != -1, "the reason names the permanence rule"
	)
	check_eq_int(tower.upgrade_count(), 1, "the refused removal left the upgrade in place")
	check_eq_int(inv.upgrade_count(), 0, "the refused removal put nothing in hand")

	# --- switch on: the same call returns the upgrade to hand
	inv.set_upgrade_removal_allowed(true)
	var removed: bool = inv.remove_upgrade_from_tower(tower.id, upgrade.id)
	print("INV_DEMO " + JSON.stringify({
		"demo": "removal_switch_on",
		"allow_upgrade_removal": inv.allow_upgrade_removal,
		"removed": removed,
		"reason_when_refused": "(none; the call succeeded)",
		"tower_upgrades": tower.upgrade_count(),
		"upgrades_in_hand": inv.upgrade_count(),
		"holder": inv.find_upgrade_holder(upgrade.id),
	}))
	check(removed, "with the switch on removal succeeds")
	check_eq_int(tower.upgrade_count(), 0, "the tower is empty")
	check_eq_int(inv.upgrade_count(), 1, "the upgrade is back in hand")
	check_eq_int(inv.find_upgrade_holder(upgrade.id), 0, "find_upgrade_holder() reports in hand")
	check(
		inv.find_upgrade_in_hand(upgrade.id) != null, "the returned instance is the same one"
	)
	check(
		inv.apply_upgrade_to_tower(tower.id, upgrade.id), "the returned upgrade can be applied again"
	)
	check_eq_int(tower.upgrade_count(), 1, "and the tower carries it again")


# --- case 5: the tier round trip (DoD 6) -----------------------------------

func _case_tier_round_trip() -> void:
	print("INV_CASE tier_3_and_its_upgrades_survive_place_take_back_place")
	var inv = InventoryScript.new()
	var tower = inv.add_tower("ballista")
	inv.raise_tower_tier(tower.id)
	inv.raise_tower_tier(tower.id)
	check_eq_int(tower.tier, 3, "the tower is at tier 3")
	var first_upgrade = inv.add_upgrade("sharpen")
	var second_upgrade = inv.add_upgrade("range")
	check(inv.apply_upgrade_to_tower(tower.id, first_upgrade.id), "first upgrade applies")
	check(inv.apply_upgrade_to_tower(tower.id, second_upgrade.id), "second upgrade applies")
	check_eq_int(inv.upgrade_count(), 0, "both upgrades left the hand")

	var before: Dictionary = tower.snapshot()
	print("INV_TOWER " + JSON.stringify({"step": "before_round_trip", "tower": before}))

	check(inv.place_tower(tower.id, "level_2_slot_3"), "the tower is placed")
	check(tower.placed, "the instance records the placement")
	check(inv.take_tower_back(tower.id), "the tower is taken back into the inventory")
	check(not tower.placed, "the instance records that it is back in the inventory")
	check_eq_int(tower.tier, 3, "the tier survived being taken back")
	check_eq_int(tower.upgrade_count(), 2, "both upgrades survived being taken back")
	check(inv.place_tower(tower.id, "level_3_slot_1"), "the tower is placed again")

	var after: Dictionary = tower.snapshot()
	print("INV_TOWER " + JSON.stringify({"step": "after_round_trip", "tower": after}))
	print("INV_DEMO " + JSON.stringify({
		"demo": "tier_round_trip",
		"tier_before": before["tier"],
		"tier_after": after["tier"],
		"upgrades_before": before["upgrades"],
		"upgrades_after": after["upgrades"],
		"slots_before": before["upgrade_slots"],
		"slots_after": after["upgrade_slots"],
		"location": after["location"],
	}))
	check_eq_int(after["tier"], 3, "the tower is still tier 3 after the round trip")
	check_eq_int(after["upgrade_slots"], 2, "the slot count survived the round trip")
	check(after["upgrades"] == before["upgrades"], "the same upgrades, by id and type, are attached")
	check_eq_int(after["upgrades"].size(), 2, "both upgrades are still attached")
	check(after["placed"], "the tower is standing on the map again")
	check_eq_int(after["free_slots"], 0, "the slots are still used by the same upgrades")


# --- case 6: the slot count is data, not a hardcoded two -------------------

func _case_slots_are_data() -> void:
	print("INV_CASE slot_count_is_data_three_slots_and_zero_slots")
	var inv = InventoryScript.new()
	var wide = inv.add_tower("trebuchet", 1, 3)
	check_eq_int(wide.slot_count(), 3, "a tower can be built with three slots")
	var accepted := 0
	for i in 3:
		var upgrade = inv.add_upgrade("whetstone_%d" % i)
		if inv.apply_upgrade_to_tower(wide.id, upgrade.id):
			accepted += 1
	check_eq_int(accepted, 3, "all three upgrades fit a three-slot tower")
	check_eq_int(wide.free_slots(), 0, "the three-slot tower is full at three")

	var narrow = inv.add_tower("totem", 1, 0)
	check_eq_int(narrow.slot_count(), 0, "a tower can be built with no slots")
	var spare = inv.add_upgrade("charm")
	var into_narrow: bool = inv.apply_upgrade_to_tower(narrow.id, spare.id)
	print("INV_REFUSED " + inv.last_refusal())
	check(not into_narrow, "a zero-slot tower accepts no upgrade")
	check_eq_int(inv.upgrade_count(), 1, "the refused upgrade stayed in hand")

	check(inv.set_default_upgrade_slots(4), "the default slot count is a setting")
	var defaulted = inv.add_tower("catapult")
	check_eq_int(defaulted.slot_count(), 4, "a new tower takes the configured default")
	check_eq_int(wide.slot_count(), 3, "changing the default did not rewrite existing towers")
	check(not inv.set_default_upgrade_slots(-1), "a negative slot count is refused")
	check_eq_int(inv.default_upgrade_slots, 4, "the refused setting changed nothing")


# --- helpers ---------------------------------------------------------------

func _step(inv, step: String) -> void:
	print("INV_STEP " + JSON.stringify({"step": step, "state": inv.snapshot()}))


func check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
	return condition


func check_eq_int(actual, expected: int, message: String) -> bool:
	_checks += 1
	if int(actual) != expected:
		_failures.append("%s: expected %d, got %d" % [message, expected, int(actual)])
		return false
	return true


func _finish() -> void:
	if _checks == 0 and _failures.is_empty():
		_failures.append("the self-test recorded no checks")
	check(_checks >= MIN_CHECK_COUNT, "at least one check ran")

	var passed := _failures.is_empty()
	print("INV_SELF_TEST " + JSON.stringify({
		"name": "inventory",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))

	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("INV_FAILURE " + f)
	quit(1)
