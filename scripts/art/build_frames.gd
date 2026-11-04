# Godot 4 headless tool: sheet + manifest -> SpriteFrames resource.
#
#   godot --headless --path . --script res://scripts/art/build_frames.gd
#
# Reads art/manifest.json, and for every asset that declares a `sheet` block,
# writes `<sheet-name>_frames.tres` beside it. Deterministic: same inputs produce
# the same resource, so the output can be committed and diffed.
#
# Sheet schema (see docs/ASSETS.md):
#   "sheet": {
#     "file": "assets/art/characters/hero/sheet.png",
#     "frame_width": 32, "frame_height": 32,
#     "columns": 4, "rows": 2,
#     "animations": {
#       "idle": { "row": 0, "frames": 4, "fps": 8,  "loop": true },
#       "walk": { "row": 1, "frames": 4, "fps": 10, "loop": true }
#     }
#   }
#
# Images are loaded from disk rather than through the import pipeline, so this
# works immediately after generation without an editor round-trip.

extends SceneTree

const MANIFEST := "res://art/manifest.json"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var manifest_path := MANIFEST
	if args.size() > 0:
		manifest_path = args[0]

	print("build_frames: ", manifest_path)

	if not FileAccess.file_exists(manifest_path):
		printerr("manifest not found: ", manifest_path)
		quit(1)
		return

	var raw := FileAccess.get_file_as_string(manifest_path)
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("manifest is not a JSON object")
		quit(1)
		return

	var assets = parsed.get("assets", [])
	if typeof(assets) != TYPE_ARRAY:
		printerr("manifest.assets is not an array")
		quit(1)
		return

	var built := 0
	var failed := 0

	for asset in assets:
		if typeof(asset) != TYPE_DICTIONARY:
			continue
		if not asset.has("sheet"):
			continue
		var sheet = asset["sheet"]
		if typeof(sheet) != TYPE_DICTIONARY:
			continue

		var rel: String = String(sheet.get("file", ""))
		if rel == "":
			printerr("asset ", asset.get("id", "?"), " declares a sheet without a file")
			failed += 1
			continue

		var abs_path := ProjectSettings.globalize_path("res://" + rel)
		if not FileAccess.file_exists(abs_path):
			printerr("missing sheet: ", rel)
			failed += 1
			continue

		var image := Image.load_from_file(abs_path)
		if image == null:
			printerr("cannot read image: ", rel)
			failed += 1
			continue

		var fw: int = int(sheet.get("frame_width", 0))
		var fh: int = int(sheet.get("frame_height", 0))
		if fw <= 0 or fh <= 0:
			printerr("invalid frame size for ", rel)
			failed += 1
			continue

		var tex := ImageTexture.create_from_image(image)
		var frames := SpriteFrames.new()
		# SpriteFrames starts with a "default" animation; drop it so the resource
		# contains exactly what the manifest declares.
		if frames.has_animation("default"):
			frames.remove_animation("default")

		var animations = sheet.get("animations", {})
		for anim_name in animations.keys():
			var spec = animations[anim_name]
			var row := int(spec.get("row", 0))
			var count := int(spec.get("frames", 1))
			var fps := float(spec.get("fps", 8))
			var loop := bool(spec.get("loop", true))

			frames.add_animation(String(anim_name))
			frames.set_animation_speed(String(anim_name), fps)
			frames.set_animation_loop(String(anim_name), loop)

			for i in count:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * fw, row * fh, fw, fh)
				frames.add_frame(String(anim_name), at)

		var out_rel := rel.get_basename() + "_frames.tres"
		var out_abs := ProjectSettings.globalize_path("res://" + out_rel)
		var out_dir := out_abs.get_base_dir()
		DirAccess.make_dir_recursive_absolute(out_dir)

		var err := ResourceSaver.save(frames, out_abs)
		if err != OK:
			printerr("save failed (", err, "): ", out_rel)
			failed += 1
			continue

		print("  built ", out_rel, " (", animations.size(), " animations)")
		built += 1

	print("build_frames: ", built, " built, ", failed, " failed")
	if failed > 0:
		quit(1)
	else:
		quit(0)
