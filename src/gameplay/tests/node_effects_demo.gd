extends SceneTree

## T-0049 DoD 2-5: every non-level node does something, in one headless run.
##
##     godot --headless --path . --script res://src/gameplay/tests/node_effects_demo.gd
##
## Two real `RunFlow` sessions (`src/gameplay/run_flow.gd`), one after the other:
##
##   the poor run   starting gold 0, a store on layer 1. Every purchase must be
##                  refused for lack of gold, the shelf untouched and the inventory
##                  empty - planted failure B, the gold half.
##   the rich run   starting gold 2000 and a route pinned with the map's own
##                  `forced_types` override so it holds one of every non-level
##                  node: store, rest (twice), treasure, event, boss preview and a
##                  high-stakes event. Planted failure A (the blind roll) and the
##                  inventory-cap half of B live here.
##
## The route is pinned rather than searched for so "one of each" is guaranteed by
## construction and not by a lucky seed; the seed is still printed and the map sha
## with it, so a rerun is comparable.
##
## Levels are not played. A level node is entered and completed immediately
## through the session's own `complete_level()`: this demo is evidence about
## non-level effects, and `run_flow_demo.gd` is the evidence about levels (waves,
## leaks, HQ carried). Completing without playing pays no kill gold, which is why
## the rich run's purse is set rather than earned.
##
## Prints, in this order:
##   NODE_EFFECTS_CASE {text}                 one line per phase
##   RUNFLOW_START / RUNFLOW_NODE / RUNFLOW_BUY / RUNFLOW_STORE_REROLL /
##   RUNFLOW_EVENT_PICK / RUNFLOW_TIER_UP / RUNFLOW_REFUSED ...
##                                            printed by the session under test
##   NODE_EFFECTS_POOR_* {json}               planted failure B, the gold half
##   NODE_EFFECTS_STORE {json}                store: shelf, purchase, reroll, cap
##   NODE_EFFECTS_CAP {json}                  a purchase past a switched-on cap
##   NODE_EFFECTS_REST {json} / _REST_FULL    heal, and a no-op at full HQ
##   NODE_EFFECTS_TREASURE {json}             gold paid, data-driven amount
##   NODE_EFFECTS_EVENT {json}                one item taken, a second pick refused
##   NODE_EFFECTS_BOSS_PREVIEW {json}         what the preview revealed
##   NODE_EFFECTS_BLIND_BEFORE {json}         the map before entry: no outcome
##   NODE_EFFECTS_HIGH_STAKES {json}          the roll and what it did
##   NODE_EFFECTS_BLIND_REREAD {json}         re-reads: same roll, nothing changed
##   NODE_EFFECTS_ROUTE {json}                the numbers after the boss
##   NODE_EFFECTS_SELF_TEST {json}            once, last; carries checks and failures
##
## The exit code is not evidence (L-035); NODE_EFFECTS_SELF_TEST is.

const ARENA_SCENE := "res://scenes/main.tscn"
const RunFlowScript := preload("res://src/gameplay/run_flow.gd")
const OfferSiteScript := preload("res://src/systems/offers.gd")

## Printed with the map sha, so a reader compares the sha and not this number.
const SEED := 20261109

## Gold the poor run begins with: below the cheapest item in the catalogue (60),
## so any purchase must be refused and no coin flip decides it.
const POOR_GOLD := 0
## Gold the rich run begins with: enough to buy, reroll and hit a cap without the
## purse being the reason anything fails.
const RICH_GOLD := 2000

## 0-based layer -> the types pinned on it. Every non-level type appears once, and
## `rest` appears twice: once with damage to heal, once at full HQ to prove the
## no-op. Layers 7-9 are left to the map, which guarantees a level node on each.
const FORCED_TYPES := {
	0: ["map", "store"],
	1: ["map", "rest"],
	2: ["map", "treasure"],
	3: ["map", "event"],
	4: ["map", "rest"],
	5: ["map", "boss_preview"],
	6: ["map", "high_stakes_event"],
}

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# Nothing is safe before the tree has iterated once: a node added to `root`
	# here has not run `_ready` yet.
	await process_frame

	_case("planted failure B — a purchase without gold")
	await _poor_run()

	_case("the rich run — one of every non-level node")
	await _rich_run()

	_finish()


# --- the poor run: planted failure B, gold half ------------------------------

## A store with an empty purse. `Store` must not empty a slot it could not charge
## for, and nothing may land in the inventory.
func _poor_run() -> void:
	var flow = _new_flow(POOR_GOLD)
	if not check(
		flow.start_run(SEED, {"forced_types": {0: ["map", RunFlowScript.STORE_TYPE]}}),
		"the poor run starts on a pinned route"
	):
		_free_flow(flow)
		return

	var map = flow.map()
	var node := _selectable_of_type(map, RunFlowScript.STORE_TYPE)
	if not check(node != -1, "layer 1 offers a store"):
		_free_flow(flow)
		return
	if not check(flow.enter_node(node), "the store node is entered with no gold"):
		_free_flow(flow)
		return

	var store = flow.store()
	if not check(store != null, "the session opened a shelf"):
		_free_flow(flow)
		return
	var stock: Array = store.stock()
	var slot := _first_live_slot(stock)
	if not check(slot != -1, "the shelf has a live slot"):
		_free_flow(flow)
		return

	var gold_before: int = flow.run_state().gold()
	var towers_before: int = flow.inventory().tower_count()
	var upgrades_before: int = flow.inventory().upgrade_count()
	var bought: bool = flow.buy(slot)

	print("NODE_EFFECTS_POOR_BUY " + JSON.stringify({
		"node": node,
		"slot": slot,
		"item": String(stock[slot].get("id", "")),
		"price": int(stock[slot].get("price", 0)),
		"gold": flow.run_state().gold(),
		"bought": bought,
		"refused": flow.last_refusal(),
		"slot_still_on_the_shelf": not _is_empty(store.slot(slot)),
		"towers": flow.inventory().tower_count(),
		"upgrades": flow.inventory().upgrade_count(),
	}))

	check(not bought, "a purchase with no gold is refused")
	check(
		flow.last_refusal().find("not enough gold") != -1,
		"the refusal says there is not enough gold"
	)
	check_eq_int(flow.run_state().gold(), gold_before, "the refused purchase moved no gold")
	check_eq_int(flow.inventory().tower_count(), towers_before, "no tower landed")
	check_eq_int(flow.inventory().upgrade_count(), upgrades_before, "no upgrade landed")
	check(not _is_empty(store.slot(slot)), "the slot is still on the shelf")

	_free_flow(flow)


# --- the rich run ------------------------------------------------------------

func _rich_run() -> void:
	var flow = _new_flow(RICH_GOLD)
	if not check(
		flow.start_run(SEED, {"forced_types": FORCED_TYPES}),
		"the rich run starts on the pinned route"
	):
		_free_flow(flow)
		return

	await _visit_store(flow)
	await _visit_rest_healing(flow)
	await _visit_treasure(flow)
	await _visit_event(flow)
	await _visit_rest_at_full(flow)
	await _visit_boss_preview(flow)
	await _visit_high_stakes(flow)
	await _finish_route(flow)

	_free_flow(flow)


## Store: a purchase lands and costs the shelf price, a reroll charges its ladder
## step, a purchase past a switched-on cap is refused with no gold moved, and a
## reroll on a switched-off site is refused too (`store.md` §Reroll).
func _visit_store(flow) -> void:
	var node := _selectable_of_type(flow.map(), RunFlowScript.STORE_TYPE)
	if not check(node != -1, "layer 1 offers a store"):
		return
	if not check(flow.enter_node(node), "the store is entered"):
		return
	var store = flow.store()
	if not check(store != null, "the session holds an open shelf"):
		return

	var slot := _tower_slot(flow)
	if not check(slot != -1, "the shelf holds a tower copy to buy"):
		return
	var entry: Dictionary = store.slot(slot)
	var price := int(entry.get("price", 0))
	var gold_before: int = flow.run_state().gold()
	var towers_before: int = flow.inventory().tower_count()

	if not check(flow.buy(slot), "buying slot %d is accepted" % slot):
		return

	print("NODE_EFFECTS_STORE " + JSON.stringify({
		"node": node,
		"slot": slot,
		"item": String(entry.get("id", "")),
		"tier": int(entry.get("tier", 1)),
		"price": price,
		"gold_before": gold_before,
		"gold": flow.run_state().gold(),
		"towers": flow.inventory().tower_count(),
		"slot_empty_after_buy": _is_empty(store.slot(slot)),
		"second_half": store.is_second_half(),
		"guarantee_checked": store.guarantee_checked,
		"guarantee_repaired": store.guarantee_repaired,
	}))
	check_eq_int(
		flow.run_state().gold(), gold_before - price, "the purchase cost the shelf price, no more"
	)
	check_eq_int(
		flow.inventory().tower_count(), towers_before + 1, "the tower landed in the inventory"
	)
	check(_is_empty(store.slot(slot)), "the bought slot emptied in place")

	var reroll_cost: int = store.next_reroll_cost()
	var gold_before_reroll: int = flow.run_state().gold()
	if check(flow.reroll_store(), "the store reroll is accepted"):
		print("NODE_EFFECTS_STORE_REROLL " + JSON.stringify({
			"cost": reroll_cost,
			"gold": flow.run_state().gold(),
			"rerolls_left": store.rerolls_left(),
			"stock": _shelf_lines(store.stock()),
		}))
		check_eq_int(
			flow.run_state().gold(),
			gold_before_reroll - reroll_cost,
			"the reroll charged its ladder step and nothing else"
		)
		check_eq_int(store.reroll_count(), 1, "the site counted one reroll")

	# Planted failure B, cap half: switch the cap on at what is held, then buy a
	# tower. Refused before the charge, so no gold moves and nothing lands.
	var cap: int = flow.inventory().tower_count()
	check(flow.inventory().set_tower_cap(cap), "the inventory cap is switched on at %d tower(s)" % cap)
	var cap_slot := _tower_slot(flow)
	var gold_before_cap: int = flow.run_state().gold()
	var towers_before_cap: int = flow.inventory().tower_count()
	var cap_bought := false
	if cap_slot != -1:
		cap_bought = flow.buy(cap_slot)

	print("NODE_EFFECTS_CAP " + JSON.stringify({
		"cap": cap,
		"slot": cap_slot,
		"item": String(store.slot(cap_slot).get("id", "")) if cap_slot != -1 else "",
		"price": int(store.slot(cap_slot).get("price", 0)) if cap_slot != -1 else 0,
		"bought": cap_bought,
		"refused": flow.last_refusal(),
		"gold": flow.run_state().gold(),
		"towers": flow.inventory().tower_count(),
	}))
	check(cap_slot != -1, "a tower copy is on the shelf to test the cap with")
	check(not cap_bought, "a purchase past a switched-on inventory cap is refused")
	check(flow.last_refusal().find("cap on") != -1, "the refusal names the inventory cap")
	check_eq_int(flow.run_state().gold(), gold_before_cap, "the refused purchase cost no gold")
	check_eq_int(
		flow.inventory().tower_count(), towers_before_cap, "the refused purchase added no tower"
	)
	flow.inventory().set_tower_cap(0)

	# The per-site switch: turned off on this site only, the reroll is refused.
	store.set_reroll_enabled(false)
	var gold_before_switch: int = flow.run_state().gold()
	var rerolled_while_off: bool = flow.reroll_store()
	print("NODE_EFFECTS_STORE_SWITCH " + JSON.stringify({
		"reroll_enabled": store.is_reroll_enabled(),
		"rerolled": rerolled_while_off,
		"refused": flow.last_refusal(),
		"gold": flow.run_state().gold(),
	}))
	check(not rerolled_while_off, "a reroll on a switched-off site is refused")
	check(
		flow.last_refusal().find("reroll is off at this site") != -1,
		"the refusal names the site's own switch"
	)
	check_eq_int(flow.run_state().gold(), gold_before_switch, "the refused reroll cost no gold")
	store.set_reroll_enabled(true)


## Rest with something to heal: the demo takes 4 HQ first, so the heal is visible
## and the clamp at the maximum is visible in the same call.
func _visit_rest_healing(flow) -> void:
	var damaged: int = flow.run_state().damage_hq(4, "demo: before the rest node")
	check_eq_int(damaged, 4, "the demo took 4 HQ so the rest has something to heal")

	var before: int = flow.run_state().hq_health()
	var node := _selectable_of_type(flow.map(), RunFlowScript.REST_TYPE)
	if not check(node != -1, "layer 2 offers a rest node"):
		return
	if not check(flow.enter_node(node), "the rest node is entered"):
		return
	var effect: Dictionary = _last_effect(flow)

	print("NODE_EFFECTS_REST " + JSON.stringify({
		"node": node,
		"rest_heal": int(flow.rest_heal),
		"hq_before": before,
		"hq": flow.run_state().hq_health(),
		"hq_max": flow.run_state().hq_max_health(),
		"healed": int(effect.get("healed", -1)),
		"no_effect": bool(effect.get("no_effect", true)),
	}))
	check_eq_int(flow.run_state().hq_health(), before + 4, "the rest healed exactly the damage")
	check_eq_int(
		flow.run_state().hq_health(),
		flow.run_state().hq_max_health(),
		"the heal stopped at the maximum"
	)
	check_eq_int(int(effect.get("healed", -1)), 4, "the node reports what it actually applied")


## Treasure: `base + per_layer × layer`, on arrival, no choice.
func _visit_treasure(flow) -> void:
	var map = flow.map()
	var node := _selectable_of_type(map, RunFlowScript.TREASURE_TYPE)
	if not check(node != -1, "layer 3 offers a treasure node"):
		return
	var layer := int(map.node(node).layer) + 1
	var expected: int = int(flow.treasure_base_gold) + int(flow.treasure_gold_per_layer) * layer
	var gold_before: int = flow.run_state().gold()
	if not check(flow.enter_node(node), "the treasure node is entered"):
		return

	print("NODE_EFFECTS_TREASURE " + JSON.stringify({
		"node": node,
		"layer": layer,
		"expected": expected,
		"gold_before": gold_before,
		"gold": flow.run_state().gold(),
		"levels_completed": flow.run_state().level_index(),
	}))
	check_eq_int(flow.run_state().gold(), gold_before + expected, "the treasure paid base + per-layer × layer")
	check_eq_int(
		flow.run_state().level_index(), 0, "a treasure node is not a level and moves no level index"
	)


## Event: N offers drawn, exactly one taken, a second pick refused. An unresolved
## event also blocks moving on (the charter: offers cannot be skipped).
func _visit_event(flow) -> void:
	var map = flow.map()
	var node := _selectable_of_type(map, RunFlowScript.EVENT_TYPE)
	if not check(node != -1, "layer 4 offers an event node"):
		return
	if not check(flow.enter_node(node), "the event node is entered"):
		return
	var offer = flow.event_offer()
	if not check(offer != null, "the session holds an open event set"):
		return
	var stock: Array = offer.stock()
	if not check(stock.size() == int(flow.event_offer_count), "the set holds the configured number of offers"):
		return

	# The unresolved set blocks the next choice, which is the "cannot be skipped"
	# rule; the refusal must not move the route.
	var route_before: Array = map.route()
	var next_choice: Array = map.selectable_nodes()
	var blocked := false
	if not next_choice.is_empty():
		blocked = not flow.enter_node(int(next_choice[0]))
	var block_refusal: String = flow.last_refusal()
	check(blocked, "moving on with an untaken offer is refused")
	check(block_refusal.find("choose one of its") != -1, "the refusal says an offer must be chosen")
	check(map.route() == route_before, "the refused move left the route where it was")

	var towers_before: int = flow.inventory().tower_count()
	var upgrades_before: int = flow.inventory().upgrade_count()
	var slot := _first_live_slot(stock)
	if not check(flow.choose_event(slot), "one offer is taken"):
		return
	var taken: Dictionary = stock[slot]
	var owned_delta: int = (
		flow.inventory().tower_count() - towers_before
		+ flow.inventory().upgrade_count() - upgrades_before
	)
	var second: bool = flow.choose_event(0)
	var second_refusal: String = flow.last_refusal()

	print("NODE_EFFECTS_EVENT " + JSON.stringify({
		"node": node,
		"offers": _shelf_lines(stock),
		"taken_slot": slot,
		"taken": String(taken.get("id", "")),
		"owned_delta": owned_delta,
		"towers": flow.inventory().tower_count(),
		"upgrades": flow.inventory().upgrade_count(),
		"blocked_move": block_refusal,
		"second_pick": second,
		"second_pick_refusal": second_refusal,
	}))
	check_eq_int(owned_delta, 1, "exactly one item landed in the inventory")
	check(not second, "a second pick from the same event is refused")
	check(
		second_refusal.find("no event is open") != -1,
		"the refusal says the pick was already made"
	)


## Rest at full HQ: the heal is lost, not banked, and the node says so.
func _visit_rest_at_full(flow) -> void:
	var before: int = flow.run_state().hq_health()
	if not check_eq_int(
		before, flow.run_state().hq_max_health(), "the run is at full HQ before the second rest"
	):
		return
	var node := _selectable_of_type(flow.map(), RunFlowScript.REST_TYPE)
	if not check(node != -1, "layer 5 offers a second rest node"):
		return
	if not check(flow.enter_node(node), "the second rest node is entered"):
		return
	var effect: Dictionary = _last_effect(flow)

	print("NODE_EFFECTS_REST_FULL " + JSON.stringify({
		"node": node,
		"hq_before": before,
		"hq": flow.run_state().hq_health(),
		"hq_max": flow.run_state().hq_max_health(),
		"healed": int(effect.get("healed", -1)),
		"no_effect": bool(effect.get("no_effect", false)),
		"why": String(effect.get("why", "")),
	}))
	check_eq_int(flow.run_state().hq_health(), before, "rest at full HQ changed nothing")
	check_eq_int(int(effect.get("healed", -1)), 0, "the heal applied 0")
	check(bool(effect.get("no_effect", false)), "the node's own record says no_effect")


## Boss preview: reveals the boss, changes no state at all.
func _visit_boss_preview(flow) -> void:
	var gold_before: int = flow.run_state().gold()
	var hq_before: int = flow.run_state().hq_health()
	var levels_before: int = flow.run_state().level_index()
	var towers_before: int = flow.inventory().tower_count()
	var upgrades_before: int = flow.inventory().upgrade_count()

	var node := _selectable_of_type(flow.map(), RunFlowScript.BOSS_PREVIEW_TYPE)
	if not check(node != -1, "layer 6 offers a boss preview"):
		return
	if not check(flow.enter_node(node), "the boss preview is entered"):
		return
	var revealed: Dictionary = flow.revealed_boss()

	print("NODE_EFFECTS_BOSS_PREVIEW " + JSON.stringify({
		"node": node,
		"revealed": revealed,
		"gold_before": gold_before,
		"gold": flow.run_state().gold(),
		"hq": flow.run_state().hq_health(),
		"levels_completed": flow.run_state().level_index(),
		"towers": flow.inventory().tower_count(),
		"upgrades": flow.inventory().upgrade_count(),
	}))
	check(not revealed.is_empty(), "the preview revealed the boss")
	check(String(revealed.get("level", "")) != "", "the boss map is named")
	check(
		(revealed.get("dominant_enemies", []) as Array).size() > 0,
		"the boss's dominant enemies are revealed"
	)
	check_eq_int(flow.run_state().gold(), gold_before, "a preview pays no gold")
	check_eq_int(flow.run_state().hq_health(), hq_before, "a preview changes no HQ")
	check_eq_int(flow.run_state().level_index(), levels_before, "a preview is not a level")
	check_eq_int(flow.inventory().tower_count(), towers_before, "a preview adds no tower")
	check_eq_int(flow.inventory().upgrade_count(), upgrades_before, "a preview adds no upgrade")


## Planted failure A: the blind high-stakes roll.
##
##   1. before entry neither the map nor the session can name the outcome;
##   2. on entry exactly one roll exists and its effect has been applied;
##   3. reading it again - twice, and through a second entry attempt - returns the
##      same roll and changes nothing.
func _visit_high_stakes(flow) -> void:
	var map = flow.map()
	var node := _selectable_of_type(map, RunFlowScript.HIGH_STAKES_TYPE)
	if not check(node != -1, "layer 7 offers a high-stakes node"):
		return

	var knowledge: Dictionary = map.knowledge(node)
	var pre: Dictionary = flow.high_stakes_outcome(node)
	print("NODE_EFFECTS_BLIND_BEFORE " + JSON.stringify({
		"node": node,
		"knowledge": knowledge,
		"outcome_before_entry": pre,
		"pending_tier_up": flow.pending_tier_up_node(),
	}))
	check(
		String(knowledge.get("detail", "")) == "hidden_until_entry",
		"the map marks the high-stakes node hidden until entry"
	)
	check(not knowledge.has("outcome"), "the map carries no outcome key")
	check(not knowledge.has("good"), "the map carries no good/bad flag")
	check(not knowledge.has("hq_damage"), "the map carries no damage number")
	check(not bool(pre.get("rolled", true)), "reading the outcome before entry rolls nothing")
	check_eq_int(flow.pending_tier_up_node(), -1, "no reward is pending before entry")

	var hq_before: int = flow.run_state().hq_health()
	var gold_before: int = flow.run_state().gold()
	if not check(flow.enter_node(node), "the high-stakes node is entered"):
		return

	var roll: Dictionary = flow.high_stakes_outcome(node)
	print("NODE_EFFECTS_HIGH_STAKES " + JSON.stringify({
		"node": node,
		"roll": roll,
		"hq_before": hq_before,
		"hq": flow.run_state().hq_health(),
		"gold_before": gold_before,
		"gold": flow.run_state().gold(),
		"pending_tier_up": flow.pending_tier_up_node(),
		"towers": flow.inventory().tower_count(),
	}))
	check(bool(roll.get("rolled", false)), "the outcome exists once the node is entered")
	check(
		String(roll.get("kind", "")) == ("tier_up" if bool(roll.get("good", false)) else "hq_damage"),
		"the printed kind matches the roll"
	)

	if bool(roll.get("good", false)):
		if flow.pending_tier_up_node() != -1:
			var target := int(roll.get("reward_target", 0))
			var tower = flow.inventory().find_tower(target)
			if check(tower != null, "the roll names a copy to raise"):
				var tier_before := int(tower.tier)
				check(flow.claim_high_stakes_tier_up(target), "the good roll's tier-up is claimed")
				check_eq_int(
					int(flow.inventory().find_tower(target).tier),
					tier_before + 1,
					"the chosen copy rose exactly one tier"
				)
				check_eq_int(flow.pending_tier_up_node(), -1, "the reward is consumed on claim")
				check(
					not flow.claim_high_stakes_tier_up(target),
					"a second claim from the same roll is refused"
				)
		else:
			check_eq_int(
				flow.run_state().gold(),
				gold_before + int(flow.high_stakes_gold_fallback),
				"a good roll with no copy below tier 3 paid the fallback gold"
			)
	else:
		check_eq_int(
			flow.run_state().hq_health(),
			maxi(hq_before - int(flow.high_stakes_hq_damage), 0),
			"the bad roll took the HQ it printed, floored at zero"
		)

	# Re-reading, twice, then a second entry attempt.
	var hq_after: int = flow.run_state().hq_health()
	var gold_after: int = flow.run_state().gold()
	var towers_after: int = flow.inventory().tower_count()
	var second_read: Dictionary = flow.high_stakes_outcome(node)
	var third_read: Dictionary = flow.high_stakes_outcome(node)
	var reentered: bool = flow.enter_node(node)
	var reenter_refusal: String = flow.last_refusal()

	print("NODE_EFFECTS_BLIND_REREAD " + JSON.stringify({
		"node": node,
		"first_read": roll,
		"second_read": second_read,
		"third_read": third_read,
		"second_equals_first": JSON.stringify(second_read) == JSON.stringify(roll),
		"third_equals_first": JSON.stringify(third_read) == JSON.stringify(roll),
		"hq_after": hq_after,
		"hq": flow.run_state().hq_health(),
		"gold_after": gold_after,
		"gold": flow.run_state().gold(),
		"towers_after": towers_after,
		"towers": flow.inventory().tower_count(),
		"reentered": reentered,
		"reenter_refusal": reenter_refusal,
	}))
	check(
		JSON.stringify(second_read) == JSON.stringify(roll), "re-reading returned the same roll"
	)
	check(
		JSON.stringify(third_read) == JSON.stringify(roll), "a third read returned it again"
	)
	check_eq_int(flow.run_state().hq_health(), hq_after, "re-reading changed no HQ")
	check_eq_int(flow.run_state().gold(), gold_after, "re-reading changed no gold")
	check_eq_int(flow.inventory().tower_count(), towers_after, "re-reading changed no inventory")
	check(not reentered, "entering the high-stakes node again is refused")
	check(
		reenter_refusal.find("not selectable") != -1,
		"the second entry is refused because the route has moved on"
	)


## The remaining layers and the boss. Each level node is entered and completed
## immediately: the session's own handover, no waves played (see the header).
## The tail layers are not pinned, so a non-level node can be the only choice a
## layer offers; it is resolved like any other and the walk continues.
func _finish_route(flow) -> void:
	var map = flow.map()
	var steps := 0
	while not map.is_complete() and steps < 6 and not flow.run_state().is_over():
		steps += 1
		var choices: Array = map.selectable_nodes()
		if not check(not choices.is_empty(), "layer %d offers a choice" % (map.current_layer() + 1)):
			return
		var node := _selectable_level_node(map)
		if node == -1:
			# No level on offer: this layer's only reachable node is a non-level
			# one, which is ordinary play and resolves like the pinned ones above.
			node = int(choices[0])
		var type_id := String(map.type_of(node))
		var levels_before: int = flow.run_state().level_index()
		if not check(flow.enter_node(node), "node %d (%s) is entered" % [node, type_id]):
			return

		if RunFlowScript.LEVEL_TYPES.has(type_id):
			if not check(flow.complete_level(), "level node %d is completed" % node):
				return
			check_eq_int(
				flow.run_state().level_index(),
				levels_before + 1,
				"the completion counted exactly one level"
			)
		else:
			if flow.event_offer() != null:
				check(flow.choose_event(0), "the tail event's first offer is taken")
			check_eq_int(
				flow.run_state().level_index(),
				levels_before,
				"a tail non-level node moved no level index"
			)
		await process_frame
		await process_frame

	check(map.is_complete(), "the route reached the boss")
	check(flow.run_state().is_victory(), "the run ends as a victory")

	var run = flow.run_state()
	print("NODE_EFFECTS_ROUTE " + JSON.stringify({
		"sha": map.sha(),
		"route": map.route(),
		"types": _route_types(map),
		"levels_completed": run.level_index(),
		"hq": run.hq_health(),
		"hq_max": run.hq_max_health(),
		"gold": run.gold(),
		"towers": flow.inventory().tower_count(),
		"upgrades": flow.inventory().upgrade_count(),
		"node_effects": flow.node_effects().size(),
		"status": run.status_name(),
	}))


# --- helpers ----------------------------------------------------------------

func _new_flow(gold: int):
	var flow = RunFlowScript.new()
	flow.name = "RunFlow"
	flow.level_scene = load(ARENA_SCENE)
	flow.starting_gold = gold
	root.add_child(flow)
	return flow


func _free_flow(flow) -> void:
	flow.queue_free()
	await process_frame


func _selectable_of_type(map, type_id: String) -> int:
	for id in map.selectable_nodes():
		if String(map.type_of(int(id))) == type_id:
			return int(id)
	return -1


## A selectable level node, preferring an elite so the elite flag gets exercised
## when a layer offers one. Every layer holds at least one map node.
func _selectable_level_node(map) -> int:
	var fallback := -1
	for id in map.selectable_nodes():
		var type_id := String(map.type_of(int(id)))
		if not RunFlowScript.LEVEL_TYPES.has(type_id):
			continue
		if type_id == RunFlowScript.ELITE_TYPE:
			return int(id)
		if fallback == -1:
			fallback = int(id)
	return fallback


## A live slot holding a tower. Rerolls the shelf while it has none and the
## ladder is unspent, so "the shelf had no tower" cannot be a seed accident.
func _tower_slot(flow) -> int:
	var store = flow.store()
	if store == null:
		return -1
	var slot := _live_slot_of_kind(store.stock(), OfferSiteScript.KIND_TOWER)
	var guard := 0
	while slot == -1 and store.rerolls_left() > 0 and guard < 4:
		guard += 1
		if not flow.reroll_store():
			break
		slot = _live_slot_of_kind(store.stock(), OfferSiteScript.KIND_TOWER)
	return slot


func _live_slot_of_kind(stock: Array, kind: String) -> int:
	for i in stock.size():
		var entry: Dictionary = stock[i]
		if _is_empty(entry):
			continue
		if String(entry.get("kind", "")) == kind:
			return i
	return -1


func _first_live_slot(stock: Array) -> int:
	for i in stock.size():
		var entry: Dictionary = stock[i]
		if not _is_empty(entry):
			return i
	return -1


func _is_empty(entry: Dictionary) -> bool:
	return entry.is_empty() or bool(entry.get("empty", false))


## The last resolved node's record. One place, so a check reads the same dictionary
## the `RUNFLOW_NODE` line printed rather than re-deriving it from snapshot().
func _last_effect(flow) -> Dictionary:
	var effects: Array = flow.node_effects()
	if effects.is_empty():
		return {}
	return effects[effects.size() - 1]


func _shelf_lines(stock: Array) -> Array:
	var out: Array = []
	for i in stock.size():
		var entry: Dictionary = stock[i]
		if _is_empty(entry):
			out.append({"slot": i, "empty": true})
			continue
		out.append({
			"slot": i,
			"id": String(entry.get("id", "")),
			"kind": String(entry.get("kind", "")),
			"tier": int(entry.get("tier", 1)),
			"price": int(entry.get("price", 0)),
		})
	return out


func _route_types(map) -> Array:
	var out: Array = []
	for id in map.route():
		out.append(String(map.type_of(int(id))))
	return out


# --- reporting --------------------------------------------------------------

func _case(label: String) -> void:
	print("NODE_EFFECTS_CASE " + label)


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


## Exactly one self-test line, last. A demo that recorded no checks fails: it
## proved nothing, and "no assertions" must never look like a pass (L-021).
func _finish() -> void:
	if _checks == 0 and _failures.is_empty():
		_failures.append("the demo recorded no checks")

	var passed := _failures.is_empty()
	print("NODE_EFFECTS_SELF_TEST " + JSON.stringify({
		"name": "node_effects_demo",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))
	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("NODE_EFFECTS_FAILURE " + f)
	quit(1)
