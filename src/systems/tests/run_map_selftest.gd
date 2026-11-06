extends SceneTree

## Headless proof for `src/systems/run_map.gd` — T-0040 DoD items 2-6.
##
##     godot --headless --path . --script res://src/systems/tests/run_map_selftest.gd
##
## Pure logic, so no scene and no frames: every case runs inside `_initialize`.
##
## Prints, in this order:
##   MAP_CASE {name}          which case is running
##   MAP_RUNS {json}          the 200-run aggregate counts (DoD 2)
##   MAP_SEED {json}          same seed twice / different seed (DoD 3)
##   MAP_LURE {json}          the lure-is-selectable proof (the T-0040 defect)
##   MAP_ROUTE {json}         a full route walked to the boss
##   MAP_LEVEL_COUNT {json}   layers vs levels (ADR-0006: a count is a route outcome)
##   MAP_KNOWLEDGE {json}     what is visible at layer 1, at layer 5, blind rolls
##   MAP_WEIGHTS {json}       the weighting table and its assertion (DoD 5)
##   MAP_REFUSAL_TEXT ...     a refusal's reason, verbatim (DoD 4 and 5)
##   MAP_SELFTEST {json}      exactly one, last; carries checks and failures
##
## The exit code alone is not evidence (L-035): `MAP_SELFTEST` carries `checks`,
## `failed` and the failure strings, and each failure also prints an error line.
## Exit 0 = every check passed.
##
## This file lives under `src/systems/tests/` because `scripts/**` belongs to
## eng/tools. The assertions are written in the suite's shape already, so moving
## them into `scripts/tests/cases/` is a delete-and-wire, not a rewrite.

const RunMapScript := preload("res://src/systems/run_map.gd")
const RunMapNodeTypeScript := preload("res://src/systems/run_map_types.gd")

## Fixed seeds, never a random one: a failure has to be reproducible by its seed.
const RUN_COUNT := 200
const BASE_SEED := 200001
const DISTINCT_SEED_COUNT := 50
const MIN_CHECK_COUNT := 1

## The complete knowledge key set. Anything else is a leak by definition, so the
## test fails on an unexpected key rather than quietly ignoring it.
const KNOWLEDGE_KEYS := [
	"id",
	"layer",
	"type",
	"type_name",
	"plays_level",
	"lure",
	"level",
	"active_tiles",
	"dominant_enemies",
	"boss_telegraph",
	"detail",
]

## Wave composition is the wave system's, generated when a level is played. These
## keys must never appear in anything the map hands a client.
const FORBIDDEN_WAVE_KEYS := [
	"waves",
	"wave",
	"wave_manifest",
	"wave_composition",
	"spawns",
	"spawn_list",
	"enemies_in_wave",
]

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_case_two_hundred_runs()
	_case_seed_determinism()
	_case_lure_reachability()
	_case_route_to_the_boss()
	_case_route_with_a_non_level_stop()
	_case_knowledge_layers_one_and_five()
	_case_hidden_until_entry()
	_case_planted_failure_a()
	_case_planted_failure_b()
	_finish()


# --- case 1: 200 seeded runs (DoD 2) ----------------------------------------

func _case_two_hundred_runs() -> void:
	print("MAP_CASE two_hundred_seeded_runs")
	var choice_layers := 0
	var two_node_layers := 0
	var three_node_layers := 0
	var single_map_layers := 0
	var multi_map_layers := 0
	var min_nodes_in_layer := 99
	var max_nodes_in_layer := 0
	var nodes_total := 0
	var lures_total := 0
	var runs_with_lure := 0
	var shas := {}

	for i in RUN_COUNT:
		var seed_value := BASE_SEED + i
		var map: RefCounted = RunMapScript.new()
		if not check(map.generate(seed_value), "seed %d generates a map" % seed_value):
			continue
		shas[map.sha()] = true
		nodes_total += map.node_count()

		var lures := 0
		for id in map.node_ids():
			if map.is_lure(int(id)):
				lures += 1
		lures_total += lures
		if lures > 0:
			runs_with_lure += 1

		# The system's own validation, then the same rules re-measured from the
		# public API below: a broken validator must not be able to bless itself.
		var errors: Array = map.structure_errors()
		check(
			errors.is_empty(),
			"seed %d: structure_errors is empty (%s)" % [seed_value, _join(errors)]
		)
		check_eq_int(map.total_layers(), 10, "seed %d: choice layers plus the boss" % seed_value)

		for layer in RunMapScript.CHOICE_LAYERS:
			var ids: Array = map.nodes_in_layer(layer)
			choice_layers += 1
			min_nodes_in_layer = mini(min_nodes_in_layer, ids.size())
			max_nodes_in_layer = maxi(max_nodes_in_layer, ids.size())
			check(
				ids.size() >= 2 and ids.size() <= 3,
				(
					"seed %d layer %d has %d nodes, expected 2-3"
					% [seed_value, layer + 1, ids.size()]
				)
			)
			if ids.size() == 2:
				two_node_layers += 1
			elif ids.size() == 3:
				three_node_layers += 1
			var map_nodes := 0
			for id in ids:
				if map.type_of(int(id)) == _map_type_id():
					map_nodes += 1
			check(
				map_nodes >= 1,
				(
					"seed %d layer %d has %d map nodes, expected at least 1"
					% [seed_value, layer + 1, map_nodes]
				)
			)
			if map_nodes == 1:
				single_map_layers += 1
			else:
				multi_map_layers += 1

		var final_ids: Array = map.nodes_in_layer(RunMapScript.CHOICE_LAYERS)
		var bosses := 0
		for id in map.node_ids():
			if map.type_of(int(id)) == _boss_type_id():
				bosses += 1
		check_eq_int(bosses, 1, "seed %d: exactly one boss node on the map" % seed_value)
		check_eq_int(final_ids.size(), 1, "seed %d: the final layer holds one node" % seed_value)
		if final_ids.size() == 1:
			var boss_id := int(final_ids[0])
			check(
				map.type_of(boss_id) == _boss_type_id(),
				"seed %d: the single final node is the boss" % seed_value
			)
			check(
				map.node(boss_id).children.is_empty(),
				"seed %d: the boss has no children" % seed_value
			)

		var reached := _reachable(map)
		check_eq_int(
			reached,
			map.node_count(),
			"seed %d: every node is reachable from the start" % seed_value
		)

	check_eq_int(shas.size(), RUN_COUNT, "each of the 200 fixed seeds made a distinct map")
	check_eq_int(two_node_layers + three_node_layers, choice_layers, "every layer is 2 or 3 nodes")
	check(
		two_node_layers > 0 and three_node_layers > 0,
		"both layer sizes occur across the runs (2: %d, 3: %d)"
		% [two_node_layers, three_node_layers]
	)
	check(
		min_nodes_in_layer >= 2 and max_nodes_in_layer <= 3,
		"layer size stayed inside 2-3 (min %d, max %d)"
		% [min_nodes_in_layer, max_nodes_in_layer]
	)
	check_eq_int(lures_total, RUN_COUNT, "the default lure_count of 1 put exactly one lure per map")
	check_eq_int(runs_with_lure, RUN_COUNT, "every run has at least one lure")

	print("MAP_RUNS " + JSON.stringify({
		"runs": RUN_COUNT,
		"seeds": "%d-%d" % [BASE_SEED, BASE_SEED + RUN_COUNT - 1],
		"distinct_maps": shas.size(),
		"choice_layers_per_run": RunMapScript.CHOICE_LAYERS,
		"choice_layers_checked": choice_layers,
		"layers_with_2_nodes": two_node_layers,
		"layers_with_3_nodes": three_node_layers,
		"layer_nodes_min": min_nodes_in_layer,
		"layer_nodes_max": max_nodes_in_layer,
		"layers_with_one_map_node": single_map_layers,
		"layers_with_two_or_more_map_nodes": multi_map_layers,
		"nodes_total": nodes_total,
		"lures_total": lures_total,
		"runs_with_a_lure": runs_with_lure,
		"placeholder": "(placeholder numbers; T-0038 replaces them)",
	}))


# --- case 2: determinism (DoD 3) -------------------------------------------

func _case_seed_determinism() -> void:
	print("MAP_CASE seed_determinism")
	var seed_a := 700001
	var first: RefCounted = RunMapScript.new()
	var second: RefCounted = RunMapScript.new()
	var other: RefCounted = RunMapScript.new()

	check(first.generate(seed_a), "seed A generates")
	check(second.generate(seed_a), "the same seed generates in a second instance")
	check(other.generate(seed_a + 1), "a different seed generates")

	var form_a := JSON.stringify(first.serialise(), "", true)
	var form_a2 := JSON.stringify(second.serialise(), "", true)
	var form_b := JSON.stringify(other.serialise(), "", true)

	check(form_a == form_a2, "the same seed serialises to an identical map")
	check(first.sha() == second.sha(), "the same seed hashes identically")
	check(first.sha() != other.sha(), "a different seed hashes differently")
	check(form_a != form_b, "a different seed serialises to a different map")
	check(
		first.sha() == form_a.sha256_text(),
		"sha() is the SHA-256 of the canonical form, not an opaque counter"
	)

	# Regenerating on an instance that already holds a map must replace it, not
	# layer a second map on top of the first.
	check(first.generate(seed_a), "regenerating the same seed on the same instance")
	check(
		JSON.stringify(first.serialise(), "", true) == form_a,
		"regeneration reproduced the map exactly"
	)
	check_eq_int(first.node_count(), second.node_count(), "regeneration kept the node count")

	print("MAP_SEED " + JSON.stringify({
		"same_seed_twice": {
			"seed": seed_a,
			"sha_first": first.sha(),
			"sha_second": second.sha(),
			"identical_serialised": form_a == form_a2,
			"nodes": first.node_count(),
			"canonical_form_bytes": form_a.length(),
		},
		"different_seed": {
			"seed": seed_a + 1,
			"sha": other.sha(),
			"differs_from_same_seed": other.sha() != first.sha(),
		},
	}))

	var seen := {}
	for i in DISTINCT_SEED_COUNT:
		var probe: RefCounted = RunMapScript.new()
		probe.generate(seed_a + 1000 + i)
		seen[probe.sha()] = true
	check_eq_int(
		seen.size(), DISTINCT_SEED_COUNT, "%d distinct seeds made %d distinct maps" % [DISTINCT_SEED_COUNT, DISTINCT_SEED_COUNT]
	)
	print("MAP_SEED " + JSON.stringify({
		"distinct_seed_sample": DISTINCT_SEED_COUNT,
		"distinct_maps": seen.size(),
		"seeds": "%d-%d" % [seed_a + 1000, seed_a + 1000 + DISTINCT_SEED_COUNT - 1],
	}))


# --- case 3: a lure is visible early, never an illegal destination ----------

func _case_lure_reachability() -> void:
	print("MAP_CASE a_lure_that_is_a_legal_child_is_selectable")
	# Regression guard for the T-0040 defect: the old `is_selectable()` returned
	# false for every lure, so this map would offer lures the map then refused.
	# With every non-opening node forced to be a lure, the layer-1 choice set is
	# entirely lures, and it must still be enterable.
	var map: RefCounted = RunMapScript.new()
	map.lure_count = 999
	check(map.generate(777001), "a map whose non-opening nodes are all lures generates")

	var candidates := 0
	var lured := 0
	for id in map.node_ids():
		var layer := int(map.node(id).layer)
		if layer >= 1 and layer < RunMapScript.CHOICE_LAYERS:
			candidates += 1
			if map.is_lure(int(id)):
				lured += 1
	check_eq_int(lured, candidates, "every node on layers 2-9 is a lure under lure_count 999")

	# Reachability, not lure status, still decides: a far lure is visible from
	# the start and is not yet a legal destination.
	var far_id := int(map.nodes_in_layer(4)[0])
	check(map.is_lure(far_id), "a node on layer 5 is a lure")
	check(map.is_visible(far_id), "the layer-5 lure is visible from the start")
	check(not map.is_selectable(far_id), "the layer-5 lure is not selectable from the start")
	var refused: bool = map.enter(far_id)
	print("MAP_REFUSAL_TEXT far_lure :: " + map.last_refusal())
	check(not refused, "entering a far lure is refused")
	check(
		map.last_refusal().find("lure") == -1,
		"the refusal is about reachability, not about being a lure"
	)
	check(
		map.last_refusal().find("is on layer 5, the route is on layer 1") != -1,
		"the refusal names the layer mismatch"
	)

	# Enter layer 1, and the next choice set is entirely lures — and legal.
	check(map.enter(int(map.selectable_nodes()[0])), "the route enters a layer-1 node")
	var choices: Array = map.selectable_nodes()
	if not check(choices.size() >= 1, "the layer-2 choice set is not emptied by lure status"):
		# The pre-fix defect: every legal child was a lure, every lure was
		# filtered out, and the map offered nothing to enter. Nothing further in
		# this case can be measured, so say what happened and stop here.
		print("MAP_LURE " + JSON.stringify({
			"defect": "every legal next choice was a lure and was filtered out",
			"selectable": choices,
		}))
		return
	var all_lures_and_selectable := true
	for id in choices:
		if not map.is_lure(int(id)):
			all_lures_and_selectable = false
		if not map.is_selectable(int(id)):
			all_lures_and_selectable = false
	check(
		all_lures_and_selectable,
		"every legal next choice is a lure and every one is selectable (defect fixed)"
	)
	check(map.enter(int(choices[0])), "a lure that is a legal child can be entered")
	check_eq_int(map.route().size(), 2, "the route advanced onto the lure")
	check_eq_int(map.current_node_id(), int(choices[0]), "the route stands on the lure node")
	check(map.is_visible(int(choices[0])), "the entered lure stays visible")

	print("MAP_LURE " + JSON.stringify({
		"lure_nodes_on_layers_2_to_9": lured,
		"candidate_nodes": candidates,
		"far_lure": {
			"id": far_id,
			"layer": 5,
			"visible": true,
			"selectable_at_start": false,
			"refusal": "the refusal names the layer mismatch, never the lure flag",
		},
		"layer_2_choice_set": choices,
		"layer_2_choice_set_all_lures": true,
		"entered_a_lure": true,
		"route": map.route(),
	}))


# --- case 4: a full route, start to boss ------------------------------------

func _case_route_to_the_boss() -> void:
	print("MAP_CASE a_full_route_walks_to_the_boss")
	var map: RefCounted = RunMapScript.new()
	check(map.generate(800001), "the route map generates")

	# An illegal jump is refused and changes nothing.
	var far_id := int(map.nodes_in_layer(4)[0])
	check(not map.enter(far_id), "entering a layer-5 node from the start is refused")
	check_eq_int(map.route().size(), 0, "a refused move leaves the route empty")
	check(
		map.last_refusal().find("is on layer 5, the route is on layer 1") != -1,
		"the refusal names the layer the node sits on and the layer the route is on"
	)

	var guard := 0
	while not map.is_complete() and guard < map.total_layers() * 2:
		guard += 1
		var choices: Array = map.selectable_nodes()
		if not check(
			choices.size() >= 1,
			"layer %d offers at least one legal choice" % (map.current_layer() + 1)
		):
			break
		if not check(map.enter(int(choices[0])), "entering node %d is legal" % int(choices[0])):
			break

	check(map.is_complete(), "the route reached the boss")
	check_eq_int(
		map.route().size(), map.total_layers(), "the route has exactly one stop per layer"
	)

	var stops: Array = []
	var layer_in_order := true
	var expected_layer := 0
	var level_stops := 0
	for id in map.route():
		var node = map.node(int(id))
		stops.append(String(node.describe()))
		if int(node.layer) != expected_layer:
			layer_in_order = false
		expected_layer += 1
		if _plays_level(map, int(id)):
			level_stops += 1
	check(layer_in_order, "the route visits layers 1-10 in order, one node each")
	check_eq_int(
		int(map.current_node_id()),
		int(map.nodes_in_layer(RunMapScript.CHOICE_LAYERS)[0]),
		"the route ends on the boss node"
	)
	check_eq_int(map.current_layer(), map.total_layers(), "no layer awaits a choice after the boss")
	check_eq_int(
		level_stops, map.route().size(), "an all-map route plays a level at every stop"
	)
	check(
		map.max_levels() == map.total_layers(),
		"max_levels() is the layer ceiling (%d), not a level count" % map.max_levels()
	)

	print("MAP_ROUTE " + JSON.stringify({
		"seed": map.seed_value(),
		"sha": map.sha(),
		"stops": stops,
		"route": map.route(),
		"layers": map.total_layers(),
		"level_stops": level_stops,
		"max_levels": map.max_levels(),
		"complete": map.is_complete(),
		"snapshot": map.snapshot(),
	}))


# --- case 5: ADR-0006 — a layer index is not a level index -------------------

func _case_route_with_a_non_level_stop() -> void:
	print("MAP_CASE a_store_stop_plays_no_level_so_the_count_is_a_route_outcome")
	var map: RefCounted = RunMapScript.new()
	check(
		map.generate(810001, {"forced_types": {2: ["map", "store"]}}),
		"a map with a pinned store on layer 3 generates"
	)

	var guard := 0
	while not map.is_complete() and guard < map.total_layers() * 2:
		guard += 1
		var choices: Array = map.selectable_nodes()
		if not check(choices.size() >= 1, "a choice exists on layer %d" % (map.current_layer() + 1)):
			break
		var pick := int(choices[0])
		if map.current_layer() == 2:
			# Layer 3 is the pinned layer: take the store when it is reachable.
			for id in choices:
				if map.type_of(int(id)) == "store":
					pick = int(id)
		if not check(map.enter(pick), "entering node %d is legal" % pick):
			break

	check(map.is_complete(), "the route still reaches the boss with a store on it")
	var level_stops := 0
	var non_level_stops := 0
	for id in map.route():
		if _plays_level(map, int(id)):
			level_stops += 1
		else:
			non_level_stops += 1
	var pinned_store := -1
	for id in map.nodes_in_layer(2):
		if map.type_of(int(id)) == "store":
			pinned_store = int(id)
	check(pinned_store >= 0, "the pinned layer really holds a store")
	check(map.route().has(pinned_store), "the route took the pinned store")
	check(non_level_stops >= 1, "at least one stop on the route plays no level")
	check_eq_int(
		level_stops + non_level_stops,
		map.route().size(),
		"every stop is either a level or not: the counts partition the route"
	)
	check(level_stops < map.max_levels(), "the route's level count is below the ceiling")
	check(
		map.total_layers() == map.route().size(),
		"the layer index still advanced across the store: layers are not levels"
	)

	print("MAP_LEVEL_COUNT " + JSON.stringify({
		"seed": map.seed_value(),
		"route": map.route(),
		"pinned_store": pinned_store,
		"layers_walked": map.route().size(),
		"level_stops": level_stops,
		"non_level_stops": non_level_stops,
		"max_levels": map.max_levels(),
		"note": "ADR-0006: max_levels() is a ceiling; a layer index is not a level index",
	}))


# --- case 6: what the player knows at layer 1 versus layer 5 (DoD 6) --------

func _case_knowledge_layers_one_and_five() -> void:
	print("MAP_CASE reveal_at_layer_1_versus_layer_5")
	var map: RefCounted = RunMapScript.new()
	check(map.generate(820001), "the reveal map generates")

	var at_one := _knowledge_report(map)
	check_eq_int(int(at_one["layer"]), 1, "no choice has been made: the player is on layer 1")
	check(
		at_one["selectable"] == map.nodes_in_layer(0),
		"on layer 1 every opening node is a legal choice"
	)
	check(_no_issues(at_one), "layer 1 reveals nothing it must not: %s" % _join(at_one["issues"]))
	check_eq_int(int(at_one["wave_keys_present"]), 0, "layer 1 shows no wave composition")
	check(int(at_one["level_nodes"]) > 0, "layer 1 reveals at least one level's enemy types")
	check(int(at_one["lures_visible"]) > 0, "a lure is visible from layer 1")

	# Nothing two layers away is visible, except a lure.
	var leaked_two_layers_ahead := 0
	for id in map.nodes_in_layer(2):
		if map.is_visible(int(id)) and not map.is_lure(int(id)):
			leaked_two_layers_ahead += 1
	check_eq_int(leaked_two_layers_ahead, 0, "no layer-3 node is visible from layer 1 unless it is a lure")
	check(map.knowledge(int(map.nodes_in_layer(5)[0])).is_empty(), "an unseen node's knowledge is empty")

	# Walk four stops to stand on the layer-5 choice.
	var walked := 0
	while map.current_layer() < 4 and walked < map.total_layers():
		var choices: Array = map.selectable_nodes()
		if not check(choices.size() >= 1, "a choice exists on layer %d" % (map.current_layer() + 1)):
			break
		var pick := int(choices[choices.size() - 1])
		if not check(map.enter(pick), "entering node %d is legal" % pick):
			break
		walked += 1
	check_eq_int(map.current_layer(), 4, "the route stands on the layer-5 choice")

	var at_five := _knowledge_report(map)
	check_eq_int(int(at_five["layer"]), 5, "the player is on layer 5")
	check(
		at_five["selectable"] == map.node(map.current_node_id()).children,
		"on layer 5 the legal choices are exactly the current node's children"
	)
	check(_no_issues(at_five), "layer 5 reveals nothing it must not: %s" % _join(at_five["issues"]))
	check_eq_int(int(at_five["wave_keys_present"]), 0, "layer 5 shows no wave composition")
	check(int(at_five["level_nodes"]) > 0, "layer 5 reveals its levels' enemy types")
	check(
		int(at_five["visible"]) >= map.route().size(),
		"every stop on the route stays visible"
	)
	check(
		int(at_five["visible"]) < map.node_count(),
		"the far half of the map is still hidden at layer 5"
	)
	var leaked_ahead := 0
	for id in map.nodes_in_layer(7):
		if map.is_visible(int(id)) and not map.is_lure(int(id)):
			leaked_ahead += 1
	check_eq_int(leaked_ahead, 0, "no layer-8 node is visible from layer 5 unless it is a lure")

	print("MAP_KNOWLEDGE " + JSON.stringify({"at": 1, "report": at_one}))
	print("MAP_KNOWLEDGE " + JSON.stringify({"at": 5, "report": at_five}))


# --- case 7: a blind roll reveals its content to nobody --------------------

func _case_hidden_until_entry() -> void:
	print("MAP_CASE hidden_until_entry_hides_content")
	var map: RefCounted = RunMapScript.new()
	check(
		map.generate(830001, {"forced_types": {0: ["map", "high_stakes_event"]}}),
		"a layer with a blind roll generates"
	)
	var hidden_id := -1
	for id in map.nodes_in_layer(0):
		if map.type_of(int(id)) == "high_stakes_event":
			hidden_id = int(id)
	check(hidden_id >= 0, "the pinned blind roll is on layer 1")

	var know: Dictionary = map.knowledge(hidden_id)
	check(String(know.get("detail", "")) == "hidden_until_entry", "the blind roll is flagged")
	check(not know.has("dominant_enemies"), "a blind roll reveals no enemy types")
	check(not know.has("level"), "a blind roll reveals no level")
	check(not know.has("active_tiles"), "a blind roll reveals no tile count")
	check(_wave_keys_in(know).is_empty(), "a blind roll reveals no waves")
	check(
		map.knowledge(int(map.nodes_in_layer(0)[0])).has("dominant_enemies"),
		"the map node beside it does reveal enemy types: the reveal is per node"
	)
	print("MAP_KNOWLEDGE " + JSON.stringify({"at": 1, "hidden_node": know}))

	check(map.enter(hidden_id), "the blind roll is a legal next choice and is entered")
	var after: Dictionary = map.knowledge(hidden_id)
	check(not after.has("detail"), "once entered the blind roll is no longer flagged")
	check(_wave_keys_in(after).is_empty(), "entering it still adds no wave data")


# --- case 8: planted failure A (DoD 4) -------------------------------------

func _case_planted_failure_a() -> void:
	print("MAP_CASE planted_failure_a_a_layer_with_no_map_node_is_refused")
	var map: RefCounted = RunMapScript.new()
	var forced := {"forced_types": {3: ["store", "rest"]}}
	var refused: bool = map.generate(515151, forced)
	print("MAP_REFUSAL_TEXT layer_without_a_map_node :: " + map.last_refusal())

	check(not refused, "a layer pinned with no map node is refused")
	check(not map.is_generated(), "a refused map is not marked generated")
	check_eq_int(map.node_count(), 0, "a refused map leaves no nodes behind")
	check(map.sha() == "", "a refused map has no fingerprint")
	check(
		map.last_refusal().find("layer 4 has no map node") != -1,
		"the refusal names the layer and the rule"
	)
	check(
		map.last_refusal().find("at least 1 is required") != -1,
		"the refusal states the requirement"
	)
	# The refusal is loud, not silent: the system printed its own MAP_REFUSED line
	# before this returns (L-035: a reason nobody sees is not a refusal).
	print("MAP_PLANTED_A " + JSON.stringify({
		"forced": {"4": ["store", "rest"]},
		"returned": refused,
		"node_count": map.node_count(),
		"reason": map.last_refusal(),
	}))


# --- case 9: planted failure B (DoD 5) -------------------------------------

func _case_planted_failure_b() -> void:
	print("MAP_CASE planted_failure_b_previous_map_weight_at_the_base_weight")
	var map: RefCounted = RunMapScript.new()
	map.previous_map_weight = 100.0
	var errors: Array = map.weighting_errors()
	print("MAP_WEIGHTS " + JSON.stringify({
		"base_weight": map.map_base_weight,
		"previous_map_weight": map.previous_map_weight,
		"errors": errors,
	}))

	check(not errors.is_empty(), "a previous-map weight equal to the base trips the assertion")
	check(
		_join(errors).find("lowest non-zero weight") != -1,
		"the error names the rule: the previous map is the least likely"
	)

	var refused: bool = map.generate(616161)
	print("MAP_REFUSAL_TEXT previous_map_weight :: " + map.last_refusal())
	check(not refused, "generation is refused while the previous map is not the least likely")
	check_eq_int(map.node_count(), 0, "a refused generation leaves no map behind")
	check(not map.is_generated(), "a refused generation is not marked generated")

	# The same assertion on the shipped defaults, so the check is not vacuous.
	var ok: RefCounted = RunMapScript.new()
	var default_errors: Array = ok.weighting_errors()
	check(default_errors.is_empty(), "the default weights satisfy the rule")
	var weights: Dictionary = ok.map_weights(["map-03"])
	var previous_is_lowest := true
	for id in weights.keys():
		if String(id) != "map-03" and float(weights[id]) <= float(weights["map-03"]):
			previous_is_lowest = false
	check(
		is_equal_approx(float(weights["map-03"]), ok.previous_map_weight),
		"the previous map is drawn at previous_map_weight"
	)
	check(
		is_equal_approx(float(weights["map-04"]), ok.map_base_weight),
		"every other map is drawn at map_base_weight"
	)
	check(previous_is_lowest, "the previous map has the strictly lowest non-zero weight")
	check(float(weights["map-03"]) > 0.0, "a revisit stays possible: the previous weight is above 0")
	print("MAP_WEIGHTS " + JSON.stringify({
		"previous_ids": ["map-03"],
		"weights": weights,
		"previous_is_lowest": previous_is_lowest,
		"revisit_possible": float(weights["map-03"]) > 0.0,
	}))


# --- helpers ---------------------------------------------------------------

## Everything a client can see right now, key-checked against the contract.
func _knowledge_report(map: RefCounted) -> Dictionary:
	var entries: Array = []
	var issues: Array = []
	var wave_keys := 0
	var level_nodes := 0
	var lures_visible := 0
	for id in map.visible_nodes():
		var node_id := int(id)
		var know: Dictionary = map.knowledge(node_id)
		if know.is_empty():
			issues.append("visible node %d has empty knowledge" % node_id)
			continue
		var found: Array = _wave_keys_in(know)
		if not found.is_empty():
			wave_keys += found.size()
		for key in know.keys():
			if not KNOWLEDGE_KEYS.has(String(key)):
				issues.append("node %d leaks unknown key '%s'" % [node_id, key])
		if String(know.get("type", "")) != map.type_of(node_id):
			issues.append("node %d knowledge type disagrees with the map" % node_id)
		if map.is_lure(node_id):
			lures_visible += 1
		if _plays_level(map, node_id):
			level_nodes += 1
			if not know.has("detail"):
				var enemies: Array = know.get("dominant_enemies", [])
				if enemies.is_empty():
					issues.append("level node %d reveals no dominant enemy types" % node_id)
				if int(know.get("active_tiles", 0)) <= 0:
					issues.append("level node %d reveals no active tile count" % node_id)
		else:
			if know.has("level") or know.has("dominant_enemies"):
				issues.append("non-level node %d reveals level content" % node_id)
		var entry := {
			"id": node_id,
			"layer": int(know.get("layer", 0)),
			"type": String(know.get("type", "")),
			"level": String(know.get("level", "")),
			"active_tiles": int(know.get("active_tiles", 0)),
			"dominant_enemies": know.get("dominant_enemies", []),
			"lure": bool(know.get("lure", false)),
		}
		if know.has("detail"):
			entry["detail"] = String(know["detail"])
		if know.has("boss_telegraph"):
			entry["boss_telegraph"] = String(know["boss_telegraph"])
		entries.append(entry)

	return {
		"layer": map.current_layer() + 1,
		"route": map.route(),
		"visible": entries.size(),
		"selectable": map.selectable_nodes(),
		"lures_visible": lures_visible,
		"level_nodes": level_nodes,
		"wave_keys_present": wave_keys,
		"issues": issues,
		"nodes": entries,
	}


func _wave_keys_in(know: Dictionary) -> Array:
	var found: Array = []
	for key in know.keys():
		if FORBIDDEN_WAVE_KEYS.has(String(key)):
			found.append(String(key))
	return found


func _plays_level(map: RefCounted, node_id: int) -> bool:
	var def = map.node_types.get(map.type_of(node_id))
	return def != null and bool(def.plays_level)


## Reachable node count from the opening layer, via the public children edges.
func _reachable(map: RefCounted) -> int:
	var seen := {}
	var frontier: Array = []
	for id in map.nodes_in_layer(0):
		seen[int(id)] = true
		frontier.append(int(id))
	while not frontier.is_empty():
		var id: int = int(frontier.pop_back())
		for child in map.node(id).children:
			if not seen.has(int(child)):
				seen[int(child)] = true
				frontier.append(int(child))
	return seen.size()


func _join(parts: Array) -> String:
	var texts: Array = []
	for part in parts:
		texts.append(str(part))
	return "; ".join(texts)


func _no_issues(report: Dictionary) -> bool:
	var issues: Array = report.get("issues", [])
	return issues.is_empty()


# The two type ids the map's structure rule names, read from the registry script
# rather than hard-coded here, so a rename is caught by the parser.
static func _map_type_id() -> String:
	return RunMapNodeTypeScript.TYPE_MAP


static func _boss_type_id() -> String:
	return RunMapNodeTypeScript.TYPE_BOSS


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
	print("MAP_SELFTEST " + JSON.stringify({
		"name": "run_map",
		"status": "pass" if passed else "fail",
		"checks": _checks,
		"failed": _failures.size(),
		"failures": _failures,
	}))

	if passed:
		quit(0)
		return
	for f in _failures:
		push_error("MAP_FAILURE " + f)
	quit(1)
