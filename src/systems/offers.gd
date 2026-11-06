class_name OfferSite
extends RefCounted

## A site that offers items and can reroll them — T-0042.
##
## CONTRACT
## --------
## * A site **draws its whole set once** (`draw()`) and may **replace the whole
##   set** (`reroll()`) a bounded number of times. The between-level offer set is
##   this class used directly; `Store` (store.gd) is this machinery with a tier
##   stage, prices and the second-half guarantee added.
## * A site owns exactly four pieces of mutable state: the current set, the
##   reroll counter for this visit, the pool of (item, tier) pairs already shown
##   here (the no-repeat rule), and the total this site has charged. It owns **no
##   gold**. Every charge goes through the `Callable` the caller supplies, so this
##   system has no dependency on the economy's implementation and never reaches
##   into a wallet.
## * The charge seam is `func(amount: int) -> bool`. It must return `false`
##   *without debiting* when the caller cannot pay, and `true` *after* debiting.
##   `src/gameplay/gold_ledger.gd`'s `try_spend(amount, reason)` fits it by
##   binding the reason:
##       var seam := Callable(ledger, "try_spend").bind("store reroll")
##   A seam that debits and then returns `false` breaks the contract, not this
##   file: a refusal must never cost the player gold.
## * Refusals are **values**, not prints and not exceptions:
##       {"ok": false, "reason": <one of the REASON_* constants>, "text": <sentence>}
##   A refusal leaves the set, the reroll counter and the amount charged exactly
##   as they were. Callers compare `reason` against the constants; `text` is only
##   for the screen and for evidence, so no caller depends on prose.
## * A draw larger than the site's capacity is **refused, never truncated**: the
##   existing set is untouched and the refusal carries both numbers
##   (`requested`, `capacity`). A silent `min(count, capacity)` is the failure this
##   rule exists to prevent.
## * Determinism: a set is a pure function of
##   `(run_seed, site_id, layer, visit_index, draw_index)` plus the pool shown
##   earlier in this visit. `draw_index` 0 is the opening set and `k` is the k-th
##   reroll, so a reroll is reproducible without replaying frames or an RNG
##   stream. Same seed and same visit = same shelf, in any process, on any machine.
## * Empty slots are legal only after a purchase (store.gd). Every counter here
##   skips them, and `is_empty_slot()` is the one test for them.
##
## PLACEHOLDER numbers
## -------------------
## Every count, weight and price below is a pre-play guess. `docs/design/systems/`
## (T-0038) owns the real ones: `reroll-and-offers.md` for the offer set,
## `store.md` for the store. Each carries the marker so replacing it is a search,
## not a hunt. `DATADRIVEN` means it is meant to be tuned by data, never by code.

## Site ids. Part of the draw key, so two sites at the same layer and visit index
## never produce the same set — switching one off cannot shift the other's stock.
const SITE_OFFER := &"offer"
const SITE_STORE := &"store"

## The three catalogue kinds this system can draw. A kind is data: the catalogue
## decides what exists, and nothing here knows a tower's name.
const KIND_TOWER := "tower"
const KIND_RUNE := "rune"
const KIND_RELIC := "relic"

## Refusal reasons. Callers match these; `describe_reason()` is the only place
## that turns one into a sentence.
const REASON_OK := ""
const REASON_REROLL_DISABLED := "reroll_disabled_at_this_site"
const REASON_REROLL_CAP := "reroll_cap_reached"
const REASON_INSUFFICIENT_GOLD := "insufficient_gold"
const REASON_STOCK_SIZE := "stock_size_exceeded"
const REASON_ALREADY_DRAWN := "set_already_drawn"
const REASON_NOT_DRAWN := "set_not_drawn"
const REASON_NO_CHARGE_SEAM := "no_charge_seam_supplied"
const REASON_POOL_EXHAUSTED := "draw_pool_exhausted"
const REASON_NO_SUCH_SLOT := "no_such_slot"
const REASON_SLOT_EMPTY := "slot_already_bought"

## PLACEHOLDER (T-0038 reroll-and-offers.md §The offer set, GUESS): cards per set.
## Three is the smallest number that makes "the best of two bad options" possible.
const OFFER_COUNT := 3
## PLACEHOLDER: the band a caller may ask for. Below 1 there is nothing to choose
## between; above 5 the set is a list, not a choice (pillar 3, readable at a glance).
const MIN_SET_SIZE := 1
const MAX_SET_SIZE := 5
## PLACEHOLDER (reroll-and-offers.md §The offer set): no duplicate (item, tier)
## inside one set — two identical cards is one card and a wasted slot.
const MAX_PER_ITEM_TIER_IN_SET := 1
## PLACEHOLDER (reroll-and-offers.md §Reroll, GUESS): 3 rerolls per set, ladder
## 30 / 45 / 60. The cap is what keeps the gold decision real.
const REROLLS_PER_SET := 3
const REROLL_COSTS := [30, 45, 60]
## PLACEHOLDER (reroll-and-offers.md §Weights, GUESS all three): relative category
## weights, renormalised over the categories that still have something to offer.
const WEIGHTS_OFFER := {KIND_TOWER: 30, KIND_RUNE: 25, KIND_RELIC: 15}

## The keys a catalogue entry must carry. A missing key is a programmer error and
## asserts in a development build; in release the entry is skipped with an error,
## so a mistyped table cannot crash a player's run.
const REQUIRED_ENTRY_KEYS := ["id", "kind", "tier", "path_cost"]

## Fields. Public because the caller may read a site's identity, never write it
## mid-visit: `run_seed`, `layer` and `visit_index` are part of the draw key, and
## changing them after `draw()` would make the shelf a lie.
var run_seed: int = 0
var site_id: StringName = SITE_OFFER
var layer: int = 1
var visit_index: int = 0

## The item catalogue, copied on construction. Never mutated: content belongs to
## the caller (`src/gameplay`, ultimately data), not to this system.
var catalogue: Array[Dictionary] = []
## Relative category weights for this site. `Store` swaps in `store.md`'s mix.
var category_weights: Dictionary = {}

## Bounds. `capacity` is how many slots this site has; `min_size`/`max_size` are
## the band a caller may ask for in `draw()`/`set_capacity()`.
var capacity: int = OFFER_COUNT
var min_size: int = MIN_SET_SIZE
var max_size: int = MAX_SET_SIZE
## How many copies of one (item, tier) the set may hold. The offer set forbids
## duplicates; the store allows two (duplicates are how a player builds a wall of
## one tower). The store overrides it.
var max_per_item_tier: int = MAX_PER_ITEM_TIER_IN_SET

## Reroll ladder for this site, cheapest step first.
var reroll_costs: Array = REROLL_COSTS.duplicate()
var rerolls_per_visit: int = REROLLS_PER_SET
## Per-site switch. Default on; each site owns its own copy, which is what makes
## the switch independent rather than global.
var reroll_enabled: bool = true

## The amount this site has successfully charged. Reported, never authoritative —
## the seam owns the balance.
var spent: int = 0

var _items: Array[Dictionary] = []
var _staging: Array[Dictionary] = []
var _discarded: Dictionary = {}
var _reroll_count: int = 0
var _draw_index: int = 0
var _drawn: bool = false


func _init(
	run_seed_value: int = 0,
	layer_value: int = 1,
	visit_value: int = 0,
	catalogue_entries: Array = [],
) -> void:
	run_seed = run_seed_value
	layer = layer_value
	visit_index = visit_value
	catalogue = _validated_catalogue(catalogue_entries)
	category_weights = WEIGHTS_OFFER.duplicate()


# ---------------------------------------------------------------------------
# Reading a site's state. Every accessor copies, so a caller cannot mutate the
# shelf it was handed and leave the site's counters disagreeing with its stock.
# ---------------------------------------------------------------------------

## The current set, in slot order. Empty slots (after a purchase) stay in place,
## so an index never shifts under the UI.
func stock() -> Array[Dictionary]:
	return _items.duplicate(true)


func slot(index: int) -> Dictionary:
	if index < 0 or index >= _items.size():
		return {}
	return _items[index].duplicate(true)


func is_drawn() -> bool:
	return _drawn


func reroll_count() -> int:
	return _reroll_count


func rerolls_left() -> int:
	return max(0, rerolls_per_visit - _reroll_count)


## The price of the next reroll, or -1 when the ladder is spent.
func next_reroll_cost() -> int:
	if _reroll_count < 0 or _reroll_count >= reroll_costs.size():
		return -1
	return int(reroll_costs[_reroll_count])


func is_reroll_enabled() -> bool:
	return reroll_enabled


func set_reroll_enabled(enabled: bool) -> void:
	reroll_enabled = enabled


## A JSON-safe view of everything a failure report needs.
func snapshot() -> Dictionary:
	return {
		"site": str(site_id),
		"seed": run_seed,
		"layer": layer,
		"visit": visit_index,
		"drawn": _drawn,
		"draw_index": _draw_index,
		"reroll_count": _reroll_count,
		"reroll_enabled": reroll_enabled,
		"spent": spent,
		"stock": stock(),
	}


static func is_empty_slot(entry: Dictionary) -> bool:
	return entry.is_empty() or bool(entry.get("empty", false))


static func empty_slot() -> Dictionary:
	return {
		"empty": true,
		"kind": "",
		"id": "",
		"display_name": "",
		"tier": 0,
		"path_cost": 0,
		"price": 0,
		"weight": 0.0,
	}


# ---------------------------------------------------------------------------
# Determinism. The draw key is mixed by hand rather than through `hash()`, so the
# same seed gives the same shelf across engine versions and platforms.
# ---------------------------------------------------------------------------

const _FNV_OFFSET := 0x811C9DC5
const _FNV_PRIME := 0x01000193


static func _fnv(h: int, value: int) -> int:
	var x: int = value
	var acc: int = h
	for _i in 4:
		acc = ((acc ^ (x & 0xFF)) & 0xFFFFFFFF) * _FNV_PRIME
		acc &= 0xFFFFFFFF
		x = x >> 8
	return acc


static func _fnv_text(h: int, text: String) -> int:
	var acc: int = h
	for byte in text.to_utf8_buffer():
		acc = ((acc ^ int(byte)) & 0xFFFFFFFF) * _FNV_PRIME
		acc &= 0xFFFFFFFF
	return acc


## The one function that decides which RNG stream a draw uses. Every random
## choice a site makes is seeded from this, never from a shared stream, so two
## sites in the same visit cannot influence each other.
static func derive_seed(
	run_seed_value: int,
	site_id_value: StringName,
	layer_value: int,
	visit_value: int,
	draw_index: int,
) -> int:
	var h := _FNV_OFFSET
	h = _fnv(h, run_seed_value)
	h = _fnv_text(h, str(site_id_value))
	h = _fnv(h, layer_value)
	h = _fnv(h, visit_value)
	h = _fnv(h, draw_index)
	return h & 0xFFFFFFFF


## Weighted index over a list of relative weights. Returns -1 when every weight is
## zero or negative, which the caller must treat as "nothing legal to draw"
## rather than as "pick the first".
static func pick_weighted(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += max(0.0, float(w))
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += max(0.0, float(weights[i]))
		if roll < acc:
			return i
	return weights.size() - 1


static func describe_reason(reason: String) -> String:
	match reason:
		REASON_OK:
			return "accepted"
		REASON_REROLL_DISABLED:
			return "reroll is off at this site; its stock is fixed for this visit"
		REASON_REROLL_CAP:
			return "this site's reroll ladder is spent; nothing more can be bought here"
		REASON_INSUFFICIENT_GOLD:
			return "not enough gold for this reroll; the stock and the gold are unchanged"
		REASON_STOCK_SIZE:
			return "the requested stock size is outside this site's band; refused, the existing stock is unchanged"
		REASON_ALREADY_DRAWN:
			return "this site's set has already been drawn; use reroll() to replace it"
		REASON_NOT_DRAWN:
			return "this site has no set yet; nothing can be rerolled or bought before it is drawn"
		REASON_NO_CHARGE_SEAM:
			return "no charge seam was supplied; a site never reaches into a wallet itself"
		REASON_POOL_EXHAUSTED:
			return "the catalogue cannot fill this set under the no-repeat rule"
		REASON_NO_SUCH_SLOT:
			return "there is no slot at that index on this shelf"
		REASON_SLOT_EMPTY:
			return "that slot has already been bought"
	return "unrecognised refusal reason: " + reason


# ---------------------------------------------------------------------------
# The two operations that change the set.
# ---------------------------------------------------------------------------

## Draw the opening set. `count` defaults to this site's capacity. A count outside
## `[min_size, max_size]` or above `capacity` is refused, never clamped.
func draw(count: int = -1) -> Dictionary:
	if _drawn:
		return _refuse(REASON_ALREADY_DRAWN, {"count": _items.size()})
	var requested := capacity if count < 0 else count
	if requested < min_size or requested > capacity or requested > max_size:
		return _refuse(REASON_STOCK_SIZE, {
			"requested": requested,
			"capacity": capacity,
			"band": [min_size, max_size],
		})
	_draw_index = 0
	var reason := _roll(requested)
	if reason != REASON_OK:
		_staging = []
		return _refuse(reason, {"requested": requested})
	_commit()
	return {
		"ok": true,
		"reason": REASON_OK,
		"text": describe_reason(REASON_OK),
		"count": _items.size(),
		"stock": stock(),
	}


## Replace the whole set, charging through the seam the caller supplies.
##
## Order is the contract: every guard that can refuse runs **before** the seam is
## called, and the seam is called **before** any state changes. So a refusal
## cannot spend gold, and a successful charge cannot be lost to a failed draw.
func reroll(charge: Callable = Callable()) -> Dictionary:
	if not _drawn:
		return _refuse(REASON_NOT_DRAWN, {})
	if not reroll_enabled:
		return _refuse(REASON_REROLL_DISABLED, {"reroll_count": _reroll_count})
	if _reroll_count >= rerolls_per_visit:
		return _refuse(REASON_REROLL_CAP, {
			"reroll_count": _reroll_count,
			"cap": rerolls_per_visit,
		})
	if not charge.is_valid():
		return _refuse(REASON_NO_CHARGE_SEAM, {})
	var cost := next_reroll_cost()
	if cost < 0:
		return _refuse(REASON_REROLL_CAP, {"reroll_count": _reroll_count})
	if not bool(charge.call(cost)):
		return _refuse(REASON_INSUFFICIENT_GOLD, {"cost": cost})

	_reroll_count += 1
	_draw_index = _reroll_count
	var reason := _roll(capacity)
	if reason != REASON_OK:
		# Only reachable with a catalogue too small to fill one shelf twice. The
		# gold is already spent at this point, so this is loud on purpose.
		push_error(
			"OfferSite.reroll: charged %d but the pool could not refill: %s" % [cost, reason]
		)
		_reroll_count -= 1
		_draw_index = _reroll_count
		_staging = []
		return _refuse(reason, {"cost": cost, "charged": cost})
	_commit()
	spent += cost
	return {
		"ok": true,
		"reason": REASON_OK,
		"text": describe_reason(REASON_OK),
		"cost": cost,
		"paid": true,
		"reroll_index": _reroll_count,
		"rerolls_left": rerolls_left(),
		"stock": stock(),
	}


## Change how many slots this site has. Used by a node that wants a wider or
## narrower shelf; out-of-band values are refused, not clamped.
func set_capacity(value: int) -> Dictionary:
	if _drawn:
		return _refuse(REASON_ALREADY_DRAWN, {"capacity": capacity})
	if value < min_size or value > max_size:
		return _refuse(REASON_STOCK_SIZE, {
			"requested": value,
			"capacity": capacity,
			"band": [min_size, max_size],
		})
	capacity = value
	return {"ok": true, "reason": REASON_OK, "text": describe_reason(REASON_OK), "capacity": capacity}


# ---------------------------------------------------------------------------
# The draw itself. One staging buffer, committed only on success, so a failed
# draw cannot leave half a shelf behind.
# ---------------------------------------------------------------------------

func _roll(count: int) -> String:
	_staging = []
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(run_seed, site_id, layer, visit_index, _draw_index)
	for _i in count:
		var drawn := _draw_slot(rng)
		if drawn.is_empty():
			return REASON_POOL_EXHAUSTED
		var entry := _prepare(drawn)
		if entry.is_empty():
			return REASON_POOL_EXHAUSTED
		_staging.append(entry)
	_post_pass()
	if _staging.size() != count:
		return REASON_POOL_EXHAUSTED
	return REASON_OK


func _commit() -> void:
	_items = _staging.duplicate(true)
	for entry in _items:
		if is_empty_slot(entry):
			continue
		# Everything the player has been shown is off the table for the rest of
		# the visit: a reroll may not re-offer it (store.md §Reroll, no-repeat).
		_discarded[_key(entry)] = true
	_drawn = true
	_staging = []


## One slot. The base site draws a category by weight, then an item inside it —
## the offer set's rule. `Store` overrides this to put a tier stage in front.
func _draw_slot(rng: RandomNumberGenerator) -> Dictionary:
	var kinds := _legal_kinds(0)
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
	var pool := _legal_entries(String(keys[kind_index]), 0)
	if pool.is_empty():
		return {}
	var pool_weights: Array = []
	for entry in pool:
		pool_weights.append(max(0.0, float(entry.get("weight", 1.0))))
	var entry_index := pick_weighted(rng, pool_weights)
	if entry_index < 0:
		return {}
	return pool[entry_index]


## Hook: turn a drawn entry into the slot that will be committed. The store adds
## a price here; the base site's sets are free to take, so it only copies.
func _prepare(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {}
	return entry.duplicate(true)


## Hook: repair the finished set before it is shown. Base: no rule. The store's
## second-half guarantee lives here.
func _post_pass() -> void:
	pass


func _legal_kinds(tier: int) -> Dictionary:
	var kinds: Dictionary = {}
	var keys: Array = category_weights.keys()
	keys.sort()
	for key in keys:
		if float(category_weights[key]) <= 0.0:
			continue
		if _legal_entries(String(key), tier).is_empty():
			continue
		kinds[key] = float(category_weights[key])
	return kinds


func _legal_entries(kind: String, tier: int) -> Array[Dictionary]:
	var legal: Array[Dictionary] = []
	for entry in catalogue:
		if String(entry["kind"]) != kind:
			continue
		if tier > 0 and int(entry["tier"]) != tier:
			continue
		var key := _key(entry)
		if _discarded.has(key):
			continue
		if _count_staged(key) >= max_per_item_tier:
			continue
		legal.append(entry)
	return legal


func _count_staged(key: String) -> int:
	var count := 0
	for entry in _staging:
		if is_empty_slot(entry):
			continue
		if _key(entry) == key:
			count += 1
	return count


static func _key(entry: Dictionary) -> String:
	return "%s|%s|%d" % [String(entry.get("kind", "")), String(entry.get("id", "")), int(entry.get("tier", 0))]


func _refuse(reason: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false,
		"reason": reason,
		"text": describe_reason(reason),
	}
	for key in extra.keys():
		result[key] = extra[key]
	return result


func _validated_catalogue(entries: Array) -> Array[Dictionary]:
	var validated: Array[Dictionary] = []
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("OfferSite: catalogue entry is not a Dictionary: %s" % str(entry))
			continue
		var missing: Array = []
		for field in REQUIRED_ENTRY_KEYS:
			if not entry.has(field):
				missing.append(field)
		if not missing.is_empty():
			var label := String(entry.get("id", "<no id>"))
			assert(missing.is_empty(), "OfferSite: catalogue entry '%s' is missing %s" % [label, str(missing)])
			push_error("OfferSite: skipping catalogue entry '%s' (missing %s)" % [label, str(missing)])
			continue
		var copy: Dictionary = entry.duplicate(true)
		copy["kind"] = String(copy["kind"])
		copy["id"] = String(copy["id"])
		copy["tier"] = int(copy["tier"])
		copy["path_cost"] = int(copy["path_cost"])
		copy["weight"] = max(0.0, float(copy.get("weight", 1.0)))
		if not copy.has("display_name"):
			copy["display_name"] = copy["id"]
		copy["display_name"] = String(copy["display_name"])
		validated.append(copy)
	if validated.is_empty():
		push_error("OfferSite: the catalogue is empty; every draw will refuse")
	return validated
