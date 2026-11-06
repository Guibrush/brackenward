class_name Store
extends OfferSite

## A store visit — T-0042. A shelf of five, drawn tier-first, with a price
## premium on tiers 2 and 3 and a second-half floor on the whole shelf.
##
## CONTRACT
## --------
## * A store is a node on the run map (`docs/design/systems/store.md`). It sells
##   **copies** of towers and upgrades. It decides what is on the shelf and what a
##   reroll produces; it does **not** place, equip or hold anything. The inventory
##   (T-0041, `src/systems/inventory.gd`) owns what the player has, so a caller
##   must check its own caps *before* calling `purchase()` — a refused purchase
##   must not be able to cost gold, and this file cannot check a cap it does not own.
## * One draw order: **tier** (by the half-of-run weights), then **category** (by
##   the store's mix), then an item inside that (kind, tier) uniformly. The tier
##   stage is where rarity lives; a per-entry `weight` in the catalogue is the
##   offer set's business and is ignored here.
## * **Second-half guarantee.** A shelf drawn when `is_second_half()` is true is
##   repaired after the draw if it holds no tier-2-or-better item: the
##   highest-priced tier-1 slot is replaced by a tier-2 item drawn by the category
##   weights. At most one slot is repaired. The repair is part of the visited
##   shelf, re-applies after every reroll, and reports itself —
##   `guarantee_checked`, `guarantee_repaired`, `guarantee_failed` are readable, so
##   "the guarantee never fires" and "the guarantee fires every time" are both
##   distinguishable from "it is working".
## * **Half of the run is arithmetic**, never a flag a caller sets by feel:
##   `second_half ⇔ layer > floor(total_layers / 2)`. For the nine-layer map that is
##   layers 5–9. `total_layers` is the map's ceiling handed in by the caller
##   (ADR-0006: the map is the authority on progress), defaulting to the design's
##   nine.
## * Prices are derived from the item's path cost, so a cost is changed in exactly
##   one place: `price = path_cost × premium`, tier 1 at cost, tiers 2–3 at +25%,
##   rounded to the nearest 5 (half up). Duplicates on the shelf are legal — two
##   Arrows is a good roll — but never more than `MAX_PER_ITEM_TIER` of one
##   (item, tier), because a shelf of five identical Arrows reads as a bug.
## * Rerolls charge through the caller's seam (`OfferSite.reroll`), on the store's
##   own ladder (25 / 40 / 55), capped at three per visit, and are refused with a
##   reason when the site's own `reroll_enabled` is false. The switch is **per
##   site**: turning the store's off leaves the offer set's on, and vice versa,
##   because each site holds its own flag and its own draw key.
## * A purchase empties its slot in place; the slot index never shifts. Buying is
##   refused, with the shelf untouched, when the seam declines.
##
## PLACEHOLDER numbers
## -------------------
## Every number below is a pre-play guess (`store.md`, marked GUESS there).
## `DATADRIVEN` marks a named field meant to be tuned by data, never by code.

## PLACEHOLDER (T-0038 store.md §What a store is, DATADRIVEN): items on the shelf.
const STOCK_SIZE := 5
## PLACEHOLDER (store.md, DATADRIVEN band 3–7): below 3 a reroll has nothing to
## improve; above 7 the shelf stops being readable in one look (pillar 3).
const STOCK_SIZE_MIN := 3
const STOCK_SIZE_MAX := 7
## PLACEHOLDER (store.md §Edge cases, DATADRIVEN): at most this many of one
## (item, tier) on one shelf.
const MAX_PER_ITEM_TIER := 2
## PLACEHOLDER (store.md §The second-half guarantee, DATADRIVEN): slots repaired
## at most, per shelf.
const GUARANTEE_REPAIRS := 1
## The tier the guarantee repairs with. Not a tunable: "tier-2-or-better" is the
## rule, and repairing upward from 2 would make the floor a gift.
const GUARANTEE_MIN_TIER := 2
## A salt that keeps the repair on its own RNG stream, so adding the guarantee
## cannot shift the slot draws it repairs.
const GUARANTEE_SEED_SALT := 7919
## PLACEHOLDER (store.md §Stock generation): layer count of the reference run, used
## only when the caller does not hand one in. ADR-0006 makes the map the authority,
## so a caller that knows the map's ceiling must pass it.
const TOTAL_RUN_LAYERS := 9
## PLACEHOLDER (store.md §Tier weights, DATADRIVEN): weights for tiers 1/2/3 in the
## first half — a tier 3 is roughly a once-a-run event (0.2 expected per shelf).
const TIER_WEIGHTS_FIRST := [70.0, 26.0, 4.0]
## PLACEHOLDER (store.md §Tier weights, DATADRIVEN): weights for tiers 1/2/3 in the
## second half. The shift is the run getting deeper, not a catch-up mechanism.
const TIER_WEIGHTS_SECOND := [45.0, 47.0, 8.0]
## PLACEHOLDER (store.md §Category mix, DATADRIVEN, GUESS all three): relative
## category weights: towers are the verbs, upgrades are the modifiers.
const WEIGHTS_STORE := {KIND_TOWER: 60, KIND_RUNE: 25, KIND_RELIC: 15}
## PLACEHOLDER (store.md §Price): multiplier on path cost. A tier-2 or tier-3 item
## skips the in-level gold sinks, so the store charges for the skip.
const PREMIUM_TIER1 := 1.0
const PREMIUM_T2_PLUS := 1.25
## PLACEHOLDER (store.md §Price): prices round to this, so a shelf is readable
## without a calculator.
const PRICE_ROUNDING := 5
## PLACEHOLDER (store.md §Reroll, DATADRIVEN, GUESS 25/40/55): the store's own
## ladder — cheaper at the first step than the offer set's, because a shelf of five
## is a smaller gamble than a forced pick from three.
const REROLLS_PER_VISIT := 3
const REROLL_COSTS_STORE := [25, 40, 55]

## The map's layer ceiling. Part of the half-of-run arithmetic, not a tunable.
var total_layers: int = TOTAL_RUN_LAYERS

## What the last draw did about the second-half guarantee. All three are readable
## so the rule can be observed rather than asserted.
var guarantee_checked: bool = false
var guarantee_repaired: bool = false
var guarantee_failed: bool = false


func _init(
	run_seed_value: int = 0,
	layer_value: int = 1,
	visit_value: int = 0,
	catalogue_entries: Array = [],
	total_layers_value: int = TOTAL_RUN_LAYERS,
) -> void:
	super._init(run_seed_value, layer_value, visit_value, catalogue_entries)
	site_id = SITE_STORE
	capacity = STOCK_SIZE
	min_size = STOCK_SIZE_MIN
	max_size = STOCK_SIZE_MAX
	max_per_item_tier = MAX_PER_ITEM_TIER
	category_weights = WEIGHTS_STORE.duplicate()
	rerolls_per_visit = REROLLS_PER_VISIT
	reroll_costs = REROLL_COSTS_STORE.duplicate()
	total_layers = total_layers_value
	assert(total_layers > 0, "Store: total_layers must be positive (got %d)" % total_layers)


## The half-of-run test, arithmetic and public so a caller can label the visit
## without re-deriving it: `layer > floor(total_layers / 2)`.
func is_second_half() -> bool:
	var half := int(floor(float(total_layers) / 2.0))
	return layer > half


func tier_weights() -> Array:
	return (TIER_WEIGHTS_SECOND if is_second_half() else TIER_WEIGHTS_FIRST).duplicate()


## How many slots currently hold an unsold item.
func live_count() -> int:
	var count := 0
	for entry in _items:
		if is_empty_slot(entry):
			continue
		count += 1
	return count


## How many shelf items are tier 2 or better. The second-half guarantee is exactly
## "this is at least 1", so the count is public.
func tier_two_plus_count() -> int:
	var count := 0
	for entry in _items:
		if is_empty_slot(entry):
			continue
		if int(entry["tier"]) >= GUARANTEE_MIN_TIER:
			count += 1
	return count


## Shelf price: path cost times the tier's premium, rounded to the nearest
## `PRICE_ROUNDING` with halves rounded up.
func price_of(entry: Dictionary) -> int:
	var base := int(entry.get("path_cost", 0))
	var tier := int(entry.get("tier", 1))
	var premium := PREMIUM_TIER1 if tier < GUARANTEE_MIN_TIER else PREMIUM_T2_PLUS
	var raw := float(base) * float(premium)
	return int(roundf(raw / float(PRICE_ROUNDING))) * PRICE_ROUNDING


## Buy the item in one slot. The item leaves the shelf and the slot stays in
## place, empty, so no other index shifts under the UI.
##
## The caller must have checked its own caps first (inventory space, ownership
## rules): this system owns no inventory and cannot refuse on its behalf. A
## declined seam leaves the shelf exactly as it was.
func purchase(index: int, charge: Callable = Callable()) -> Dictionary:
	if not _drawn:
		return _refuse(REASON_NOT_DRAWN, {})
	if index < 0 or index >= _items.size():
		return _refuse(REASON_NO_SUCH_SLOT, {"index": index, "count": _items.size()})
	var entry: Dictionary = _items[index]
	if is_empty_slot(entry):
		return _refuse(REASON_SLOT_EMPTY, {"index": index})
	if not charge.is_valid():
		return _refuse(REASON_NO_CHARGE_SEAM, {"index": index})
	var cost := int(entry.get("price", 0))
	if not bool(charge.call(cost)):
		return _refuse(REASON_INSUFFICIENT_GOLD, {"cost": cost, "index": index})
	_items[index] = empty_slot()
	spent += cost
	return {
		"ok": true,
		"reason": REASON_OK,
		"text": describe_reason(REASON_OK),
		"cost": cost,
		"index": index,
		"item": entry.duplicate(true),
	}


func snapshot() -> Dictionary:
	var data := super.snapshot()
	data["stock_size"] = capacity
	data["total_layers"] = total_layers
	data["second_half"] = is_second_half()
	data["tier_weights"] = tier_weights()
	data["tier_two_plus"] = tier_two_plus_count()
	data["guarantee_checked"] = guarantee_checked
	data["guarantee_repaired"] = guarantee_repaired
	data["guarantee_failed"] = guarantee_failed
	return data


# ---------------------------------------------------------------------------
# The store's draw: tier, then category, then item.
# ---------------------------------------------------------------------------

func _draw_slot(rng: RandomNumberGenerator) -> Dictionary:
	var tiers := _legal_tiers()
	if tiers.is_empty():
		return {}
	var tier_weights_for_draw: Array = []
	for tier in tiers:
		tier_weights_for_draw.append(_tier_weight(int(tier)))
	var tier_index := pick_weighted(rng, tier_weights_for_draw)
	if tier_index < 0:
		return {}
	var tier := int(tiers[tier_index])

	var kinds := _legal_kinds(tier)
	if kinds.is_empty():
		return {}
	var keys: Array = kinds.keys()
	keys.sort()
	var kind_weights: Array = []
	for key in keys:
		kind_weights.append(float(kinds[key]))
	var kind_index := pick_weighted(rng, kind_weights)
	if kind_index < 0:
		return {}
	var pool := _legal_entries(String(keys[kind_index]), tier)
	if pool.is_empty():
		return {}
	# Uniform inside (kind, tier): the tier stage already carried the rarity.
	var entry_index := rng.randi_range(0, pool.size() - 1)
	return pool[entry_index]


func _prepare(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {}
	var slot_entry := entry.duplicate(true)
	slot_entry["price"] = price_of(slot_entry)
	return slot_entry


func _tier_weight(tier: int) -> float:
	var weights := tier_weights()
	var index := tier - 1
	if index < 0 or index >= weights.size():
		return 0.0
	return float(weights[index])


func _legal_tiers() -> Array:
	var tiers: Array = []
	for tier in [1, 2, 3]:
		if _tier_weight(int(tier)) <= 0.0:
			continue
		if _legal_kinds(int(tier)).is_empty():
			continue
		tiers.append(int(tier))
	return tiers


# ---------------------------------------------------------------------------
# The second-half guarantee. A post-pass over the finished shelf, not a filter on
# each slot: the repair target is chosen with the whole shelf in view.
# ---------------------------------------------------------------------------

func _post_pass() -> void:
	guarantee_checked = is_second_half()
	guarantee_repaired = false
	guarantee_failed = false
	if not guarantee_checked:
		return
	# At most `GUARANTEE_REPAIRS` slots are repaired, and the pass stops as soon as
	# the shelf passes. At the declared value of 1 this is a single repair; the
	# bound is enforced here rather than only described in a comment, and a data
	# change to 0 makes the rule stop holding, which `guarantee_failed` reports.
	var repaired_any := false
	for _attempt in max(0, GUARANTEE_REPAIRS):
		if _staged_tier_two_plus() >= 1:
			break
		var target := _highest_priced_tier_one_slot()
		if target < 0:
			# store.md calls this impossible: a shelf with no tier-1 slot already
			# has a tier-2 item. Loud, because it means this file and the tier
			# table disagree.
			push_error("Store: second-half guarantee found no tier-1 slot to repair")
			guarantee_failed = true
			break
		var replacement := _draw_guarantee_repair()
		if replacement.is_empty():
			push_error(
				"Store: second-half guarantee could not draw a tier-%d item" % GUARANTEE_MIN_TIER
			)
			guarantee_failed = true
			break
		_staging[target] = replacement
		repaired_any = true
	guarantee_repaired = repaired_any
	if not guarantee_failed and _staged_tier_two_plus() < 1:
		push_error("Store: the guarantee finished with no tier-2 item on a second-half shelf")
		guarantee_failed = true


func _staged_tier_two_plus() -> int:
	var count := 0
	for entry in _staging:
		if is_empty_slot(entry):
			continue
		if int(entry["tier"]) >= GUARANTEE_MIN_TIER:
			count += 1
	return count


## The repair target: the most expensive tier-1 slot. Repairing the cheapest would
## put a tier-2 label on a trinket and make the guarantee a gift rather than a
## change of shape. Ties go to the lowest index, so the choice is deterministic.
func _highest_priced_tier_one_slot() -> int:
	var found := -1
	var best := -1
	for i in _staging.size():
		var entry: Dictionary = _staging[i]
		if is_empty_slot(entry):
			continue
		if int(entry["tier"]) != GUARANTEE_MIN_TIER - 1:
			continue
		var price := int(entry.get("price", 0))
		if price > best:
			best = price
			found = i
	return found


## Draw one tier-2 replacement by the category weights, on a stream salted apart
## from the slot draws. Respects the no-repeat pool and the per-(item, tier) cap.
func _draw_guarantee_repair() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(
		run_seed, site_id, layer, visit_index, _draw_index * 8 + GUARANTEE_SEED_SALT
	)
	var kinds := _legal_kinds(GUARANTEE_MIN_TIER)
	if kinds.is_empty():
		return {}
	var keys: Array = kinds.keys()
	keys.sort()
	var weights: Array = []
	for key in keys:
		weights.append(float(kinds[key]))
	var kind_index := pick_weighted(rng, weights)
	if kind_index < 0:
		return {}
	var pool := _legal_entries(String(keys[kind_index]), GUARANTEE_MIN_TIER)
	if pool.is_empty():
		return {}
	return _prepare(pool[rng.randi_range(0, pool.size() - 1)])
