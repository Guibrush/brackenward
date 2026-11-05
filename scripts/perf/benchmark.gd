extends Node2D

## G2.3 performance benchmark.
##
## Fixed, frame-indexed workload. No RNG and no wall-clock input: every entity
## is placed by a pure function of its index and every per-frame update is a
## pure function of the frame counter, so two runs of the same build perform the
## same work in the same order. Only the stopwatch varies.
##
## Prints on stdout, in this order:
##   PERF_INFO {json}          load and the render conditions actually in force
##   PERF_PHASE measuring      once, after warmup, before the first window
##   PERF_JSON {json}          one line per WINDOW_FRAMES measured frames
##   PERF_JSON {json}          once with "aggregate": true, then exits 0
##
## Exit codes:
##   0  measured and reported
##   2  refused: headless, or the load is not usable - nothing was measured
##
## Refusing is deliberate. A headless frame time is not a rendered frame, so a
## number produced that way would be evidence for the wrong claim.

## Canonical load. scripts/gate/perf.ps1 asserts this value, so changing the
## load here without changing the gate fails the gate instead of moving the
## goalposts silently.
const DECLARED_ENTITY_COUNT := 1000

## Discarded frames. Run-to-run spread at low entity counts is wide enough that
## measuring from the first frame reports the shader/pipeline warmup, not the
## scene.
const WARMUP_FRAMES := 120

const WINDOW_FRAMES := 60
const DEFAULT_WINDOWS := 12

## Canvas area of the 1920x1080 window at content scale 2, i.e. the world the
## sprites live in. 960x540 is what a 32px tile grid at 2x shows on screen.
const WORLD_SIZE := Vector2(960.0, 540.0)

const TEX_VARIANTS := 4
const TEX_SIZE := 32

var _entity_count: int = DECLARED_ENTITY_COUNT
var _windows_requested: int = DEFAULT_WINDOWS
var _warmup_frames: int = WARMUP_FRAMES

var _sprites: Array[Sprite2D] = []
var _textures: Array[ImageTexture] = []

var _frame: int = 0
var _measuring: bool = false
var _window_index: int = 0
var _window_ms: Array[float] = []
var _all_ms: Array[float] = []
var _last_usec: int = 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("PERF_ERROR headless frame times do not measure rendered frames; run windowed")
		get_tree().quit(2)
		return

	_parse_args()
	_configure_display()
	_build_entities()

	var root := get_tree().root
	var final_scale: Vector2 = root.get_final_transform().get_scale()
	var vsync_mode: int = DisplayServer.window_get_vsync_mode()
	var info := {
		"entity_count": _sprites.size(),
		"declared_entity_count": DECLARED_ENTITY_COUNT,
		"warmup_frames": _warmup_frames,
		"window_frames": WINDOW_FRAMES,
		"windows_requested": _windows_requested,
		"viewport": [root.size.x, root.size.y],
		"content_scale": [final_scale.x, final_scale.y],
		"vsync_disabled": vsync_mode == DisplayServer.VSYNC_DISABLED,
		"vsync_mode": vsync_mode,
		"max_fps": Engine.max_fps,
		"renderer": RenderingServer.get_video_adapter_name(),
		"engine": Engine.get_version_info()["string"],
	}
	print("PERF_INFO " + JSON.stringify(info))

	_last_usec = Time.get_ticks_usec()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--entities="):
			_entity_count = max(1, int(a.substr(11)))
		elif a.begins_with("--windows="):
			_windows_requested = max(3, int(a.substr(10)))
		elif a.begins_with("--warmup="):
			_warmup_frames = max(0, int(a.substr(9)))


func _configure_display() -> void:
	# Declared conditions, not assumptions: the same values are printed in
	# PERF_INFO and re-checked by the gate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))

	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(int(WORLD_SIZE.x), int(WORLD_SIZE.y))


func _build_entities() -> void:
	_textures.clear()
	for v in TEX_VARIANTS:
		_textures.append(_make_texture(v))

	var holder := Node2D.new()
	holder.name = "Entities"
	add_child(holder)

	for i in _entity_count:
		var s := Sprite2D.new()
		s.texture = _textures[i % TEX_VARIANTS]
		var f := float(i)
		s.position = Vector2(
			fmod(f * 37.0, WORLD_SIZE.x),
			fmod(f * 91.0, WORLD_SIZE.y)
		)
		var tone := float(i % 8) / 8.0
		s.modulate = Color(0.35 + 0.55 * tone, 0.7 - 0.3 * tone, 0.95 - 0.45 * tone, 1.0)
		s.scale = Vector2(2.0, 2.0)
		holder.add_child(s)
		_sprites.append(s)


func _make_texture(variant: int) -> ImageTexture:
	# Generated rather than loaded, so the measurement depends on no art asset
	# that another owner may replace mid-gate. Pattern is a fixed integer hash.
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var h: int = (x * 37 + y * 61 + variant * 137) % 251
			var a: int = 255 if (x + y) % 7 != 0 else 176
			img.set_pixel(x, y, Color8(h, (h * 3) % 251, (h * 7) % 251, a))
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec == 0:
		_last_usec = now
		return
	var frame_ms := float(now - _last_usec) / 1000.0
	_last_usec = now

	# The workload: one transform write per entity per frame, driven by the
	# frame counter so the work per frame is identical on every run.
	var phase := float(_frame % 240) * 0.01309
	for i in _sprites.size():
		var s := _sprites[i]
		s.rotation = phase + float(i % 16) * 0.03125
	_frame += 1

	if _frame <= _warmup_frames:
		return

	if not _measuring:
		_measuring = true
		print("PERF_PHASE measuring")

	_window_ms.append(frame_ms)
	_all_ms.append(frame_ms)

	if _window_ms.size() >= WINDOW_FRAMES:
		_emit_window()
		if _window_index >= _windows_requested:
			_emit_aggregate()
			get_tree().quit(0)


func _emit_window() -> void:
	var fps := 1000.0 / _mean(_window_ms)
	print("PERF_JSON " + JSON.stringify({
		"window": _window_index,
		"frames": _window_ms.size(),
		"fps_avg": fps,
		"frame_ms_p50": _percentile(_window_ms, 0.50),
		"frame_ms_p99": _percentile(_window_ms, 0.99),
	}))
	_window_index += 1
	_window_ms.clear()


func _emit_aggregate() -> void:
	var p99 := _percentile(_all_ms, 0.99)
	print("PERF_JSON " + JSON.stringify({
		"aggregate": true,
		"entity_count": _sprites.size(),
		"windows": _window_index,
		"measured_frames": _all_ms.size(),
		"fps_avg": 1000.0 / _mean(_all_ms),
		"frame_ms_p50": _percentile(_all_ms, 0.50),
		"frame_ms_p99": p99,
		"fps_1pct_low": 1000.0 / p99,
	}))


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


## Nearest-rank percentile: sorted[ceil(p * n) - 1]. Deterministic, no RNG, no
## interpolation that could flatter a bad tail.
func _percentile(values: Array[float], p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var idx := int(ceil(p * float(sorted.size()))) - 1
	if idx < 0:
		idx = 0
	if idx > sorted.size() - 1:
		idx = sorted.size() - 1
	return sorted[idx]
