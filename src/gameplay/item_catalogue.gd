class_name ItemCatalogue
extends RefCounted

## The item catalogue a run's stores and event nodes draw from — T-0049.
##
## CONTRACT
## --------
## * One function, `entries()`, returning the list `OfferSite` and `Store` take in
##   their constructor. It builds a fresh array on every call, so a caller cannot
##   mutate the catalogue another caller already holds.
## * Every entry carries exactly the four keys `OfferSite.REQUIRED_ENTRY_KEYS`
##   names (`id`, `kind`, `tier`, `path_cost`) plus `display_name` and `weight`.
##   `weight` is uniform: the tier stage and the category weights are the two
##   stages that carry rarity (`store.md` §Stock generation), and a per-entry
##   weight would be a third, unstated one.
## * Ids are stable, lowercase and namespaced by kind, so a log line or a save
##   diff can name an item without the display name. Nothing here knows a price:
##   `Store.price_of()` derives it from `path_cost`, which is what keeps the price
##   list in one place.
## * 78 (item, tier) pairs: 6 towers × 3, 12 runes × 3, 8 relics × 3. That is the
##   number `store.md` §Edge cases cites when it says the draw pool cannot empty.
##
## PLACEHOLDER content
## -------------------
## Names and `path_cost` values are copied from the design tables so a store can
## draw something real before content lands:
##   * tower path costs — `docs/design/systems/towers.md` §Tower table
##   * rune costs 60 / 130 / 230 and relic costs 90 / 200 / 350 —
##     `docs/design/systems/store.md` §Price
##   * rune and relic names — `docs/design/systems/items.md` (I-01…I-12 runes,
##     I-13…I-20 relics)
## `design/systems` owns the real table. Replacing this file's tables is a data
## change; no other file reads an item by name.

const KIND_TOWER := "tower"
const KIND_RUNE := "rune"
const KIND_RELIC := "relic"

## PLACEHOLDER (towers.md): `path_cost` per tier, in catalogue order.
const TOWER_PATH_COSTS := {
	"arrow": [70, 130, 240],
	"ballista": [110, 195, 345],
	"bramble": [60, 110, 205],
	"beacon": [90, 160, 280],
	"mortar": [100, 180, 320],
	"rime": [85, 150, 265],
}

const TOWER_DISPLAY_NAMES := {
	"arrow": "Arrow",
	"ballista": "Ballista",
	"bramble": "Bramble",
	"beacon": "Beacon",
	"mortar": "Mortar",
	"rime": "Rime",
}

## PLACEHOLDER (store.md §Price): one ladder for every rune, one for every relic.
## The design table does not vary upgrade cost by item, and a per-item ladder would
## be a second tuning axis nobody asked for.
const RUNE_PATH_COSTS := [60, 130, 230]
const RELIC_PATH_COSTS := [90, 200, 350]

## PLACEHOLDER (items.md): ids are the display names folded to snake case, so
## `items.md`'s I-01…I-20 row and a catalogue entry can be matched by eye.
const RUNE_IDS := [
	"whetstone",
	"greased_winch",
	"long_eye",
	"heavy_bolt",
	"split_case",
	"piercer",
	"rime_coat",
	"ember_load",
	"toll",
	"short_brace",
	"vantage",
	"crowd_sigil",
]
const RUNE_DISPLAY_NAMES := [
	"Whetstone",
	"Greased Winch",
	"Long Eye",
	"Heavy Bolt",
	"Split Case",
	"Piercer",
	"Rime Coat",
	"Ember Load",
	"Toll",
	"Short Brace",
	"Vantage",
	"Crowd Sigil",
]
const RELIC_IDS := [
	"chain_link",
	"snipers_mark",
	"banner",
	"overwatch",
	"last_stand",
	"vigil",
	"twin_shot",
	"ward_stone",
]
const RELIC_DISPLAY_NAMES := [
	"Chain Link",
	"Sniper's Mark",
	"Banner",
	"Overwatch",
	"Last Stand",
	"Vigil",
	"Twin Shot",
	"Ward Stone",
]

## Every tier an entry can be. Towers and upgrades both stop at 3
## (`towers.md`: 0 and 4 are illegal, not "uncapped").
const MIN_TIER := 1
const MAX_TIER := 3


## The whole catalogue, in a fixed order (towers, runes, relics; id-sorted inside
## a kind, tier 1 first). Sorted rather than dictionary order so a draw seeded on
## this list reproduces on any build.
static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_append_towers(out)
	_append_upgrades(out, KIND_RUNE, RUNE_IDS, RUNE_DISPLAY_NAMES, RUNE_PATH_COSTS)
	_append_upgrades(out, KIND_RELIC, RELIC_IDS, RELIC_DISPLAY_NAMES, RELIC_PATH_COSTS)
	return out


## How many (item, tier) pairs the catalogue holds. The store draws against this
## number, and the suite checks it is 78.
static func combination_count() -> int:
	return entries().size()


static func _append_towers(out: Array[Dictionary]) -> void:
	var ids: Array = TOWER_PATH_COSTS.keys()
	ids.sort()
	for id in ids:
		var costs: Array = TOWER_PATH_COSTS[id]
		for tier in range(MIN_TIER, MAX_TIER + 1):
			out.append(_entry(KIND_TOWER, String(id), String(TOWER_DISPLAY_NAMES[id]), tier, int(costs[tier - 1])))


static func _append_upgrades(
	out: Array[Dictionary], kind: String, ids: Array, names: Array, costs: Array
) -> void:
	for i in ids.size():
		for tier in range(MIN_TIER, MAX_TIER + 1):
			out.append(
				_entry(kind, String(ids[i]), String(names[i]), tier, int(costs[tier - 1]))
			)


static func _entry(kind: String, id: String, display_name: String, tier: int, cost: int) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"tier": tier,
		"path_cost": cost,
		"display_name": display_name,
		"weight": 1.0,
	}
