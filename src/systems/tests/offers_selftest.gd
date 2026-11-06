extends SceneTree

## Headless proof for `src/systems/offers.gd` and `src/systems/store.gd` — T-0042.
##
##     godot --headless --path . --script res://src/systems/tests/offers_selftest.gd
##
## Pure logic: no scene, no frames, every case inside `_initialize`.
##
## Prints, in this order:
##   OFFERS_CASE {name}       which case is running
##   STORE_HALVES {json}      the 200 + 200 store observation (DoD 3)
##   STORE_TOGGLE {json}      reroll switches, both directions (DoD 4)
##   STORE_SIZEREFUSAL {json} an oversized draw refused, not truncated (DoD 5)
##   STORE_SEAM {json}        both ladders through a caller-supplied seam (DoD 6)
##   STORE_RULES {json}       duplicates, no-repeat, prices, purchases
##   OFFER_SET {json}         the offer set used directly, with its own ladder
##   STORE_DETERMINISM {json} same seed = same shelf, before and after rerolls
##   STORE_HALF_RULE {json}   second_half is arithmetic, across run lengths
##   STORE_REFUSAL ...        refusal sentences, verbatim
##   OFFERS_SELFTEST {json}   exactly one, last; carries checks and failures
##
## The exit code alone is not evidence (L-035): `OFFERS_SELFTEST` carries
## `checks`, `failed` and the failure strings, and each failure also prints an
## error line. Exit 0 = every check passed.
##
## This file lives under `src/systems/tests/` because `scripts/**` belongs to
## eng/tools. The assertions are already in the suite's shape, so moving them into
## `scripts/tests/cases/` is a delete-and-wire, not a rewrite.
##
## The catalogue below is **fixture data**, not game data: `store.md`'s price
## table, six towers and twenty upgrades, so the counts mean something. The system
## under test knows no item's name.

## Preloaded rather than relied on as globals, so a load-order surprise fails
## here instead of inside a case.
const StoreScript := preload("res://src/systems/store.gd")

## Fixed seeds, never a random one: a failure has to be reproducible by its seed.
const HALVES_BASE_SEED := 4200001
const FIRST_HALF_VISITS := 200
const SECOND_HALF_VISITS := 200
const TOTAL_LAYERS := 9
const DETERMINISM_TRIALS := 50
const RULE_TRIALS := 100
const MIN_CHECK_COUNT := 1

## Fixture: `docs/design/systems/store.md` §Price, path cost per tier.
const TOWER_COSTS := {
	"Arrow": [70, 165, 300],
	"Bramble": [60, 140, 255],
	"Rime": [85, 190, 330],
	"Beacon": [90, 200, 350],
	"Mortar": [100, 225, 400],
	"Ballista": [110, 245, 430],
}
const RUNE_COSTS := [60, 130, 230]
const RELIC_COSTS := [90, 200, 350]
const RUNE_COUNT := 12
const RELIC_COUNT := 8

## A wallet behind a charge seam. It debits only when it can pay, which is the
## seam contract the systems rely on; a seam that debits on failure would be a
## bug in the caller, not in the site.
class Wallet:
	var balance: int = 0
	var charges: Array = []

	func _init(starting_balance: int = 0) -> void:
		balance = starting_balance

	func charge(amount: int) -> bool:
		charges.append(amount)
		if amount < 0:
			push_error("Wallet.charge: negative amount %d" % amount)
			return false
		if balance < amount:
			return false
		balance -= amount
		return true

	func seam() -> Callable:
		return Callable(self, "charge")

	func charge_count() -> int:
		return charges.size()

	func total_charged() -> int:
		var total := 0
		for amount in charges:
			if int(amount) > 0:
				total += int(amount)
		return total

var _catalogue_entries: Array = []
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_catalogue_entries = _build_catalogue()
	_case_two_hundred_stores_by_half()
	_case_toggle_independence()
	_case_oversized_draw_refused()
	_case_charge_seam()
	_case_store_rules()
	_case_offer_set()
	_case_determinism()
	_case_half_arithmetic()
	_finish()


# ---------------------------------------------------------------------------
# DoD 3 — the second-half guarantee, observed over 200 + 200 seeded stores.
# ---------------------------------------------------------------------------

func _case_two_hundred_stores_by_half() -> void:
	_case("two hundred stores by half")
	var first := _count_half(1, 4, FIRST_HALF_VISITS, 0)
	var second := _count_half(5, 9, SECOND_HALF_VISITS, 100000)

	check_eq_int(second["without_tier2_plus"], 0, "every second-half store holds a tier-2+ item")
	check_eq_int(second["shelves_with_wrong_size"], 0, "every second-half shelf is exactly five items")
	check_eq_int(first["shelves_with_wrong_size"], 0, "every first-half shelf is exactly five items")
	check_eq_int(first["guarantee_checked"], 0, "no shelf in the first half runs the guarantee")
	check_eq_int(first["repaired"], 0, "nothing is repaired in the first half")
	check(
		first["without_tier2_plus"] > 0,
		"the first half does produce shelves with no tier-2+ item, so the guarantee is not vacuous",
	)
	check(
		second["repaired"] > 0,
		"the guarantee actually fires on some second-half shelves, so the pass is doing work",
	)
	check(
		second["with_tier2_plus"] == SECOND_HALF_VISITS,
		"every one of the %d second-half stores contains a tier-2+ item" % SECOND_HALF_VISITS,
	)

	print("STORE_HALVES " + JSON.stringify({"first": first, "second": second}))
	print(
		"STORE_HALVES_SUMMARY first %d visits: %d without tier-2+, %d repaired | second %d visits: %d without tier-2+, %d repaired"
		% [
			first["visits"], first["without_tier2_plus"], first["repaired"],
			second["visits"], second["without_tier2_plus"], second["repaired"],
		]
	)


func _count_half(first_layer: int, last_layer: int, visits: int, seed_offset: int) -> Dictionary:
	var span := last_layer - first_layer + 1
	var with_tier2 := 0
	var without_tier2 := 0
	var repaired := 0
	var guarantee_checked := 0
	var guarantee_failed := 0
	var wrong_size := 0
	var tier_totals := [0, 0, 0]
	var sample := ""
	for i in visits:
		var layer := first_layer + (i % span)
		var store: Store = StoreScript.new(
			HALVES_BASE_SEED + seed_offset + i, layer, i, _catalogue_entries, TOTAL_LAYERS
		)
		var opened: Dictionary = store.draw()
		if not bool(opened.get("ok", false)):
			_fail("store draw failed at layer %d visit %d: %s" % [layer, i, str(opened.get("reason", "?"))])
			continue
		if store.live_count() != StoreScript.STOCK_SIZE:
			wrong_size += 1
		if store.guarantee_checked:
			guarantee_checked += 1
		if store.guarantee_repaired:
			repaired += 1
		if store.guarantee_failed:
			guarantee_failed += 1
		var high := store.tier_two_plus_count()
		if high >= 1:
			with_tier2 += 1
		else:
			without_tier2 += 1
			if sample == "":
				sample = _shelf_signature(store.stock())
		for entry in store.stock():
			var tier := int(entry.get("tier", 0))
			if tier >= 1 and tier <= 3:
				tier_totals[tier - 1] += 1
	return {
		"visits": visits,
		"with_tier2_plus": with_tier2,
		"without_tier2_plus": without_tier2,
		"repaired": repaired,
		"guarantee_checked": guarantee_checked,
		"guarantee_failed": guarantee_failed,
		"shelves_with_wrong_size": wrong_size,
		"items_per_tier": tier_totals,
		"first_shelf_without_tier2_plus": sample,
	}


# ---------------------------------------------------------------------------
# DoD 4 — the two reroll switches are independent, shown in both directions.
# ---------------------------------------------------------------------------

func _case_toggle_independence() -> void:
	_case("reroll switches are independent per site")
	# Direction 1: the store's switch is off, the offer set's is on.
	var off_store: Store = _fresh_store(7001, 6, 3)
	var on_offer: OfferSite = _fresh_offer(7001, 6, 3)
	var store_shelf_before := _shelf_signature(off_store.stock())
	var offer_set_before := _shelf_signature(on_offer.stock())
	off_store.set_reroll_enabled(false)
	var store_wallet := Wallet.new(500)
	var offer_wallet := Wallet.new(500)

	var refused_store: Dictionary = off_store.reroll(store_wallet.seam())
	check(not bool(refused_store.get("ok", true)), "store reroll is refused while its switch is off")
	check(
		String(refused_store.get("reason", "")) == OfferSite.REASON_REROLL_DISABLED,
		"the refusal is the toggle's, not the ladder's or the wallet's: got %s" % str(refused_store.get("reason", "")),
	)
	check(
		_shelf_signature(off_store.stock()) == store_shelf_before,
		"a refused reroll leaves the store's stock byte-identical",
	)
	check_eq_int(off_store.reroll_count(), 0, "a refused reroll does not advance the store's ladder")
	check_eq_int(store_wallet.charge_count(), 0, "a refused store reroll never reaches the seam")
	check_eq_int(off_store.next_reroll_cost(), 25, "the store's next reroll is still the first rung")

	var accepted_offer: Dictionary = on_offer.reroll(offer_wallet.seam())
	check(bool(accepted_offer.get("ok", false)), "the offer set still rerolls with the store's switch off")
	check_eq_int(offer_wallet.charge_count(), 1, "the offer reroll charged its own seam once")
	check_eq_int(offer_wallet.total_charged(), 30, "the offer set charged the offer ladder's first rung")
	check(
		_shelf_signature(on_offer.stock()) != offer_set_before,
		"the offer set actually changed while the store was fixed",
	)

	# Direction 2: the offer set's switch is off, the store's is on.
	var on_store: Store = _fresh_store(7002, 6, 4)
	var off_offer: OfferSite = _fresh_offer(7002, 6, 4)
	var store_before_2 := _shelf_signature(on_store.stock())
	var offer_before_2 := _shelf_signature(off_offer.stock())
	off_offer.set_reroll_enabled(false)
	var store_wallet_2 := Wallet.new(500)
	var offer_wallet_2 := Wallet.new(500)

	var accepted_store: Dictionary = on_store.reroll(store_wallet_2.seam())
	check(bool(accepted_store.get("ok", false)), "the store still rerolls with the offer set's switch off")
	check_eq_int(store_wallet_2.total_charged(), 25, "the store charged the store ladder's first rung")
	check(
		_shelf_signature(on_store.stock()) != store_before_2,
		"the store's shelf actually changed while the offer set was fixed",
	)

	var refused_offer: Dictionary = off_offer.reroll(offer_wallet_2.seam())
	check(not bool(refused_offer.get("ok", true)), "offer reroll is refused while its switch is off")
	check(
		String(refused_offer.get("reason", "")) == OfferSite.REASON_REROLL_DISABLED,
		"the offer refusal names the toggle: got %s" % str(refused_offer.get("reason", "")),
	)
	check(
		_shelf_signature(off_offer.stock()) == offer_before_2,
		"a refused offer reroll leaves the offer set byte-identical",
	)
	check_eq_int(offer_wallet_2.charge_count(), 0, "a refused offer reroll never reaches the seam")

	print("STORE_TOGGLE " + JSON.stringify({
		"store_off": {
			"store_reason": String(refused_store.get("reason", "")),
			"store_text": String(refused_store.get("text", "")),
			"store_charged": store_wallet.charge_count(),
			"offer_rerolled": bool(accepted_offer.get("ok", false)),
			"offer_charged": offer_wallet.total_charged(),
		},
		"offer_off": {
			"offer_reason": String(refused_offer.get("reason", "")),
			"offer_text": String(refused_offer.get("text", "")),
			"offer_charged": offer_wallet_2.charge_count(),
			"store_rerolled": bool(accepted_store.get("ok", false)),
			"store_charged": store_wallet_2.total_charged(),
		},
	}))
	print("STORE_REFUSAL store reroll, switch off: " + String(refused_store.get("text", "")))
	print("STORE_REFUSAL offer reroll, switch off: " + String(refused_offer.get("text", "")))


# ---------------------------------------------------------------------------
# DoD 5 — an oversized draw is refused, not truncated.
# ---------------------------------------------------------------------------

func _case_oversized_draw_refused() -> void:
	_case("an oversized draw is refused, never truncated")
	var store: Store = StoreScript.new(7101, 3, 0, _catalogue_entries, TOTAL_LAYERS)
	var too_big: Dictionary = store.draw(StoreScript.STOCK_SIZE + 1)
	check(not bool(too_big.get("ok", true)), "a six-item draw on a five-slot store is refused")
	check(
		String(too_big.get("reason", "")) == OfferSite.REASON_STOCK_SIZE,
		"the refusal names the size: got %s" % str(too_big.get("reason", "")),
	)
	check_eq_int(too_big.get("requested", -1), 6, "the refusal carries what was asked for")
	check_eq_int(too_big.get("capacity", -1), 5, "the refusal carries what the shelf holds")
	check_eq_int(store.stock().size(), 0, "nothing was drawn, so nothing was truncated to five")
	check(not store.is_drawn(), "a refused draw does not count as the shelf existing")
	var stock_after_refusal := store.stock().size()

	var above_band: Dictionary = store.draw(StoreScript.STOCK_SIZE_MAX + 1)
	check(String(above_band.get("reason", "")) == OfferSite.REASON_STOCK_SIZE, "eight items is above the band")
	var below_band: Dictionary = store.draw(StoreScript.STOCK_SIZE_MIN - 1)
	check(String(below_band.get("reason", "")) == OfferSite.REASON_STOCK_SIZE, "two items is below the band")

	var narrower: Dictionary = store.draw(4)
	check(bool(narrower.get("ok", false)), "a legal narrower shelf is accepted")
	check_eq_int(store.stock().size(), 4, "a shelf of four holds exactly four, not five")

	var again: Dictionary = store.draw(4)
	check(String(again.get("reason", "")) == OfferSite.REASON_ALREADY_DRAWN, "a second opening draw is refused")

	var resizer: Store = StoreScript.new(7102, 3, 0, _catalogue_entries, TOTAL_LAYERS)
	var refused_capacity: Dictionary = resizer.set_capacity(StoreScript.STOCK_SIZE_MAX + 2)
	check(String(refused_capacity.get("reason", "")) == OfferSite.REASON_STOCK_SIZE, "a capacity above the band is refused")
	check_eq_int(resizer.capacity, StoreScript.STOCK_SIZE, "a refused capacity change leaves the shelf size alone")
	check(bool(resizer.set_capacity(StoreScript.STOCK_SIZE_MAX).get("ok", false)), "the top of the band is allowed")
	check_eq_int(resizer.draw().get("count", -1), StoreScript.STOCK_SIZE_MAX, "a seven-slot shelf holds seven")

	var offer: OfferSite = OfferSite.new(7103, 3, 0, _catalogue_entries)
	var wide_set: Dictionary = offer.draw(OfferSite.OFFER_COUNT + 1)
	check(String(wide_set.get("reason", "")) == OfferSite.REASON_STOCK_SIZE, "the offer set refuses a fourth card")

	print("STORE_SIZEREFUSAL " + JSON.stringify({
		"store_requested": too_big.get("requested", -1),
		"store_capacity": too_big.get("capacity", -1),
		"store_stock_after": stock_after_refusal,
		"refused_capacity": refused_capacity.get("requested", -1),
		"capacity_after": resizer.capacity,
		"offer_requested": wide_set.get("requested", -1),
		"offer_capacity": wide_set.get("capacity", -1),
	}))
	print("STORE_REFUSAL oversized store draw: " + String(too_big.get("text", "")))


# ---------------------------------------------------------------------------
# DoD 6 — every charge goes through the seam the caller supplies.
# ---------------------------------------------------------------------------

func _case_charge_seam() -> void:
	_case("rerolls and purchases charge through the caller's seam")
	var offer: OfferSite = _fresh_offer(7201, 3, 0)
	var offer_wallet := Wallet.new(1000)
	var offer_costs: Array = []
	for _i in OfferSite.REROLLS_PER_SET:
		offer_costs.append(int(offer.reroll(offer_wallet.seam()).get("cost", -1)))
	check(
		str(offer_costs) == str(OfferSite.REROLL_COSTS),
		"the offer ladder is %s, got %s" % [str(OfferSite.REROLL_COSTS), str(offer_costs)],
	)
	check_eq_int(offer.spent, 135, "three offer rerolls cost 135 in total")
	check_eq_int(offer_wallet.balance, 865, "the seam's wallet is 865 lighter, not the site's own")
	var sixth: Dictionary = offer.reroll(offer_wallet.seam())
	check(String(sixth.get("reason", "")) == OfferSite.REASON_REROLL_CAP, "a fourth offer reroll is refused by the cap")
	check_eq_int(offer_wallet.charge_count(), 3, "the cap is refused before the seam is called again")

	var store: Store = StoreScript.new(7202, 3, 0, _catalogue_entries, TOTAL_LAYERS)
	store.draw()
	var store_wallet := Wallet.new(1000)
	var store_costs: Array = []
	for _i in StoreScript.REROLLS_PER_VISIT:
		store_costs.append(int(store.reroll(store_wallet.seam()).get("cost", -1)))
	check(
		str(store_costs) == str(StoreScript.REROLL_COSTS_STORE),
		"the store ladder is %s, got %s" % [str(StoreScript.REROLL_COSTS_STORE), str(store_costs)],
	)
	check_eq_int(store.spent, 120, "three store rerolls cost 120 in total")
	check_eq_int(store_wallet.balance, 880, "the store seam's wallet paid, and only it")

	# Insufficient gold: refused before anything moves.
	var poor: Store = StoreScript.new(7203, 4, 0, _catalogue_entries, TOTAL_LAYERS)
	poor.draw()
	var poor_before := _shelf_signature(poor.stock())
	var thin_wallet := Wallet.new(10)
	var refused: Dictionary = poor.reroll(thin_wallet.seam())
	check(
		String(refused.get("reason", "")) == OfferSite.REASON_INSUFFICIENT_GOLD,
		"a reroll with 10 gold against a 25 gold rung is refused: got %s" % str(refused.get("reason", "")),
	)
	check_eq_int(thin_wallet.balance, 10, "a refused reroll costs nothing")
	check_eq_int(thin_wallet.charge_count(), 1, "the seam was asked once and declined, without debiting")
	check(_shelf_signature(poor.stock()) == poor_before, "the stock is unchanged after the refusal")
	check_eq_int(poor.reroll_count(), 0, "the ladder did not advance on a refusal")
	check_eq_int(poor.spent, 0, "the site charged nothing")
	check_eq_int(poor.next_reroll_cost(), 25, "the rung is still the first one")

	var no_seam: Dictionary = poor.reroll()
	check(
		String(no_seam.get("reason", "")) == OfferSite.REASON_NO_CHARGE_SEAM,
		"a reroll without a seam is refused rather than reaching for a wallet",
	)

	# A purchase uses the same seam, and empties its slot in place.
	var shop: Store = StoreScript.new(7204, 2, 0, _catalogue_entries, TOTAL_LAYERS)
	shop.draw()
	var bought_index := -1
	var price := 0
	for i in shop.stock().size():
		var entry: Dictionary = shop.slot(i)
		if OfferSite.is_empty_slot(entry):
			continue
		bought_index = i
		price = int(entry.get("price", 0))
		break
	check(bought_index >= 0, "the shelf has something to buy")
	var shop_wallet := Wallet.new(price)
	var purchase: Dictionary = shop.purchase(bought_index, shop_wallet.seam())
	check(bool(purchase.get("ok", false)), "a purchase with exact gold is accepted")
	check_eq_int(shop_wallet.balance, 0, "buying at exact gold takes the balance to zero")
	check(OfferSite.is_empty_slot(shop.slot(bought_index)), "the bought slot is empty afterwards")
	check_eq_int(shop.live_count(), 4, "four items are left on the shelf")
	check_eq_int(shop.stock().size(), 5, "the slot itself stays, so no index shifts")
	var broke: Dictionary = shop.purchase((bought_index + 1) % shop.stock().size(), shop_wallet.seam())
	check(
		String(broke.get("reason", "")) == OfferSite.REASON_INSUFFICIENT_GOLD,
		"a purchase with no gold is refused with the shelf untouched",
	)

	print("STORE_SEAM " + JSON.stringify({
		"offer_costs": offer_costs,
		"store_costs": store_costs,
		"offer_balance": offer_wallet.balance,
		"store_balance": store_wallet.balance,
		"insufficient_reason": String(refused.get("reason", "")),
		"insufficient_balance_after": thin_wallet.balance,
		"stock_unchanged": _shelf_signature(poor.stock()) == poor_before,
		"purchase_price": price,
		"purchase_balance_after": shop_wallet.balance,
	}))
	print("STORE_REFUSAL insufficient gold: " + String(refused.get("text", "")))
	print("STORE_REFUSAL no seam: " + String(no_seam.get("text", "")))


# ---------------------------------------------------------------------------
# The rest of store.md, measured rather than asserted in prose.
# ---------------------------------------------------------------------------

func _case_store_rules() -> void:
	_case("duplicates, no-repeat, prices, and the guarantee after a reroll")
	var max_duplicate := 0
	var shelves_with_a_duplicate := 0
	var bad_price := 0
	var non_multiple := 0
	var overlap_after_reroll := 0
	var guarantee_missed_after_reroll := 0
	var rerolls_checked := 0

	for i in RULE_TRIALS:
		var layer := 1 + (i % TOTAL_LAYERS)
		var store: Store = StoreScript.new(7301 + i, layer, i, _catalogue_entries, TOTAL_LAYERS)
		store.draw()
		var counts: Dictionary = {}
		for entry in store.stock():
			var key := _entry_key(entry)
			counts[key] = int(counts.get(key, 0)) + 1
			if int(counts[key]) > max_duplicate:
				max_duplicate = int(counts[key])
			var price := int(entry.get("price", -1))
			if price % StoreScript.PRICE_ROUNDING != 0:
				non_multiple += 1
			if price != _expected_price(entry):
				bad_price += 1
		for key in counts.keys():
			if int(counts[key]) > 1:
				shelves_with_a_duplicate += 1
				break
		var seen: Dictionary = {}
		for entry in store.stock():
			seen[_entry_key(entry)] = true
		var wallet := Wallet.new(1000)
		for _r in 2:
			var result: Dictionary = store.reroll(wallet.seam())
			if not bool(result.get("ok", false)):
				_fail("a rule-trial reroll was refused: %s" % str(result.get("reason", "")))
				break
			rerolls_checked += 1
			# Duplicates inside one shelf are legal (store.md), so overlap is
			# measured shelf-against-earlier-shelves, never within a shelf.
			var this_shelf: Dictionary = {}
			for entry in store.stock():
				this_shelf[_entry_key(entry)] = true
			for key in this_shelf.keys():
				if seen.has(key):
					overlap_after_reroll += 1
				seen[key] = true
			if store.guarantee_checked and store.tier_two_plus_count() < 1:
				guarantee_missed_after_reroll += 1

	check_eq_int(max_duplicate, StoreScript.MAX_PER_ITEM_TIER, "a shelf never holds more than two of one (item, tier)")
	check(
		shelves_with_a_duplicate > 0,
		"duplicates do occur, so the cap is a cap and not a filter that removes them",
	)
	check_eq_int(bad_price, 0, "every shelf price is path cost times its tier's premium")
	check_eq_int(non_multiple, 0, "every price is a multiple of %d" % StoreScript.PRICE_ROUNDING)
	check_eq_int(overlap_after_reroll, 0, "a reroll never re-offers a (item, tier) shown earlier in the visit")
	check_eq_int(guarantee_missed_after_reroll, 0, "the second-half guarantee re-applies after every reroll")
	check_eq_int(rerolls_checked, RULE_TRIALS * 2, "every rule-trial reroll succeeded")

	# The guarantee repairs the highest-priced tier-1 slot, so a second-half
	# shelf's top price never goes down when the repair runs.
	var repaired_sample := ""
	for i in 400:
		var store: Store = StoreScript.new(7401 + i, 6, i, _catalogue_entries, TOTAL_LAYERS)
		store.draw()
		if not store.guarantee_repaired:
			continue
		repaired_sample = _shelf_signature(store.stock())
		check(store.tier_two_plus_count() >= 1, "a repaired shelf always holds a tier-2+ item")
		break
	check(repaired_sample != "", "at least one second-half shelf needed the repair, over 400 visits")

	print("STORE_RULES " + JSON.stringify({
		"max_duplicate_of_item_tier": max_duplicate,
		"shelves_with_a_duplicate": shelves_with_a_duplicate,
		"price_errors": bad_price,
		"non_multiple_prices": non_multiple,
		"reroll_overlap": overlap_after_reroll,
		"guarantee_missed_after_reroll": guarantee_missed_after_reroll,
		"rerolls_checked": rerolls_checked,
		"a_repaired_shelf": repaired_sample,
	}))


func _case_offer_set() -> void:
	_case("the between-level offer set, used directly")
	var kinds_seen: Dictionary = {}
	var duplicate_cards := 0
	var wrong_count := 0
	for i in RULE_TRIALS:
		var offer: OfferSite = OfferSite.new(7501 + i, 1 + (i % TOTAL_LAYERS), i, _catalogue_entries)
		var drawn: Dictionary = offer.draw()
		if int(drawn.get("count", -1)) != OfferSite.OFFER_COUNT:
			wrong_count += 1
		var seen: Dictionary = {}
		for entry in offer.stock():
			kinds_seen[String(entry.get("kind", ""))] = true
			var key := _entry_key(entry)
			if seen.has(key):
				duplicate_cards += 1
			seen[key] = true
	check_eq_int(wrong_count, 0, "every offer set holds exactly three cards")
	check_eq_int(duplicate_cards, 0, "an offer set never holds the same (item, tier) twice")
	check(kinds_seen.has(OfferSite.KIND_TOWER), "towers appear in offer sets")
	check(kinds_seen.has(OfferSite.KIND_RUNE), "rune upgrades appear in offer sets")
	check(kinds_seen.has(OfferSite.KIND_RELIC), "relic upgrades appear in offer sets")
	check_eq_int(OfferSite.MAX_PER_ITEM_TIER_IN_SET, 1, "the offer set's duplicate rule is stricter than the store's")

	print("OFFER_SET " + JSON.stringify({
		"sets": RULE_TRIALS,
		"cards_per_set": OfferSite.OFFER_COUNT,
		"kinds_seen": kinds_seen.keys(),
		"duplicate_cards": duplicate_cards,
		"ladder": OfferSite.REROLL_COSTS,
		"store_ladder": StoreScript.REROLL_COSTS_STORE,
	}))


func _case_determinism() -> void:
	_case("the same seed reproduces the same shelf, including after rerolls")
	var mismatches := 0
	var collisions := 0
	var reroll_mismatches := 0
	for i in DETERMINISM_TRIALS:
		var seed_value := 7601 + i
		var layer := 1 + (i % TOTAL_LAYERS)
		var a: Store = StoreScript.new(seed_value, layer, i, _catalogue_entries, TOTAL_LAYERS)
		var b: Store = StoreScript.new(seed_value, layer, i, _catalogue_entries, TOTAL_LAYERS)
		a.draw()
		b.draw()
		if _shelf_signature(a.stock()) != _shelf_signature(b.stock()):
			mismatches += 1
		var wallet_a := Wallet.new(1000)
		var wallet_b := Wallet.new(1000)
		for _r in 2:
			a.reroll(wallet_a.seam())
			b.reroll(wallet_b.seam())
		if _shelf_signature(a.stock()) != _shelf_signature(b.stock()):
			reroll_mismatches += 1
		var other: Store = StoreScript.new(seed_value, layer, i + 1, _catalogue_entries, TOTAL_LAYERS)
		other.draw()
		if _shelf_signature(other.stock()) == _shelf_signature(a.stock()):
			collisions += 1
	check_eq_int(mismatches, 0, "the same (seed, layer, visit) gives the same opening shelf")
	check_eq_int(reroll_mismatches, 0, "the same (seed, layer, visit) gives the same shelf after two rerolls each")
	check_eq_int(collisions, 0, "a different visit index gives a different shelf")
	check(
		OfferSite.derive_seed(5, OfferSite.SITE_STORE, 6, 7, 0)
			!= OfferSite.derive_seed(5, OfferSite.SITE_OFFER, 6, 7, 0),
		"the site id is part of the draw key, so one site's draws cannot shift another's",
	)
	check_eq_int(
		OfferSite.derive_seed(5, OfferSite.SITE_STORE, 6, 7, 1),
		OfferSite.derive_seed(5, OfferSite.SITE_STORE, 6, 7, 1),
		"the draw key is a pure function of its five inputs",
	)

	print("STORE_DETERMINISM " + JSON.stringify({
		"trials": DETERMINISM_TRIALS,
		"opening_mismatches": mismatches,
		"reroll_mismatches": reroll_mismatches,
		"visit_index_collisions": collisions,
		"store_draw_key": OfferSite.derive_seed(5, OfferSite.SITE_STORE, 6, 7, 1),
	}))


func _case_half_arithmetic() -> void:
	_case("half of the run is arithmetic, not a flag")
	# layer > floor(total_layers / 2)
	var cases := [
		{"layers": 9, "first": 4, "second": 5},
		{"layers": 8, "first": 4, "second": 5},
		{"layers": 10, "first": 5, "second": 6},
	]
	var measured: Array = []
	for item in cases:
		var total := int(item["layers"])
		var first: Store = StoreScript.new(1, int(item["first"]), 0, _catalogue_entries, total)
		var second: Store = StoreScript.new(1, int(item["second"]), 0, _catalogue_entries, total)
		check(not first.is_second_half(), "layer %d of %d is the first half" % [int(item["first"]), total])
		check(second.is_second_half(), "layer %d of %d is the second half" % [int(item["second"]), total])
		measured.append({
			"layers": total,
			"last_first_half_layer": int(item["first"]),
			"first_second_half_layer": int(item["second"]),
			"weights_used_at_second": second.tier_weights(),
		})
	# The weights themselves shift between the halves.
	var early: Store = StoreScript.new(2, 1, 0, _catalogue_entries, TOTAL_LAYERS)
	var late: Store = StoreScript.new(2, TOTAL_LAYERS, 0, _catalogue_entries, TOTAL_LAYERS)
	check(
		str(early.tier_weights()) != str(late.tier_weights()),
		"the tier weights differ between the halves",
	)
	check_eq_int(int(early.tier_weights()[0]), 70, "the first half leans on tier 1")
	check_eq_int(int(late.tier_weights()[0]), 45, "the second half leans on tier 1 less")

	print("STORE_HALF_RULE " + JSON.stringify({"cases": measured}))


# ---------------------------------------------------------------------------
# Fixtures and helpers.
# ---------------------------------------------------------------------------

func _build_catalogue() -> Array:
	var entries: Array = []
	for name in TOWER_COSTS.keys():
		var costs: Array = TOWER_COSTS[name]
		for tier in 3:
			entries.append({
				"id": String(name).to_lower(),
				"display_name": String(name),
				"kind": OfferSite.KIND_TOWER,
				"tier": tier + 1,
				"path_cost": int(costs[tier]),
				"weight": 1.0,
			})
	for i in RUNE_COUNT:
		for tier in 3:
			entries.append({
				"id": "rune-%02d" % (i + 1),
				"display_name": "Rune %02d" % (i + 1),
				"kind": OfferSite.KIND_RUNE,
				"tier": tier + 1,
				"path_cost": int(RUNE_COSTS[tier]),
				"weight": 1.0,
			})
	for i in RELIC_COUNT:
		for tier in 3:
			entries.append({
				"id": "relic-%02d" % (i + 1),
				"display_name": "Relic %02d" % (i + 1),
				"kind": OfferSite.KIND_RELIC,
				"tier": tier + 1,
				"path_cost": int(RELIC_COSTS[tier]),
				"weight": 1.0,
			})
	return entries


func _fresh_store(seed_value: int, layer: int, visit: int) -> Store:
	var store: Store = StoreScript.new(seed_value, layer, visit, _catalogue_entries, TOTAL_LAYERS)
	var opened: Dictionary = store.draw()
	if not bool(opened.get("ok", false)):
		_fail("fixture store failed to open: %s" % str(opened.get("reason", "")))
	return store


func _fresh_offer(seed_value: int, layer: int, visit: int) -> OfferSite:
	var offer: OfferSite = OfferSite.new(seed_value, layer, visit, _catalogue_entries)
	var drawn: Dictionary = offer.draw()
	if not bool(drawn.get("ok", false)):
		_fail("fixture offer set failed to draw: %s" % str(drawn.get("reason", "")))
	return offer


## Path cost times the premium the store promises, rounded half up to 5.
func _expected_price(entry: Dictionary) -> int:
	var base := int(entry.get("path_cost", 0))
	var premium := 1.25 if int(entry.get("tier", 1)) >= 2 else 1.0
	var raw := float(base) * premium
	return int(roundf(raw / 5.0)) * 5


func _entry_key(entry: Dictionary) -> String:
	return "%s|%s|%d" % [
		String(entry.get("kind", "")), String(entry.get("id", "")), int(entry.get("tier", 0))
	]


func _shelf_signature(stock: Array) -> String:
	return JSON.stringify(stock)


func _case(name: String) -> void:
	print("OFFERS_CASE " + name)


func _fail(message: String) -> void:
	_checks += 1
	_failures.append(message)


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
	print("OFFERS_SELFTEST " + JSON.stringify({
		"name": "offers_and_store",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))

	if passed:
		quit(0)
		return
	for failure in _failures:
		push_error("OFFERS_FAILURE " + failure)
	quit(1)
