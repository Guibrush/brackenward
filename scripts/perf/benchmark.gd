extends Node2D

## G2.3 performance benchmark.
##
## Fixed, frame-indexed workload. No RNG and no wall-clock input: every entity
## is placed by a pure function of its index and every per-frame update is a
## pure function of the frame counter, so two runs of the same build perform the
## same work in the same order. Only the stopwatch varies.
##
## Prints on stdout, in this order:
##   PERF_INFO {json}          load, the render conditions actually in force, the
##                             screen refresh rate (0.0 when unreported), the full
##                             screen table, and the GPU/engine flags the process
##                             actually received
##   PERF_PHASE measuring      once, after warmup, before the first window
##   PERF_JSON {json}          one line per WINDOW_FRAMES measured frames
##   PERF_JSON {json}          once with "aggregate": true, then exits 0
##
## With the user argument `--probe-screens` it prints one line and quits without
## building the workload:
##   PERF_SCREENS {json}       every screen the engine sees, the window's screen,
##                             the GPU, and the --screen/--gpu-index flags as the
##                             process received them
## The gate uses that probe to choose a screen before it launches the measurement:
## a screen has to be chosen before the process starts, so the table has to be
## read out of the engine in a separate, trivial run.
##
## Exit codes:
##   0  measured and reported (or, for --probe-screens, enumerated and reported)
##   2  refused: headless, no screen, or the window is on a screen whose refresh
##      rate is unreported while another screen reports one - nothing was measured
##
## Refusing is deliberate. A headless frame time is not a rendered frame, so a
## number produced that way would be evidence for the wrong claim. The same goes
## for a frame rendered on a virtual or streaming display (refresh unreported)
## while a real display is available: the number would describe the wrong screen.
## When *no* screen reports a refresh rate the run continues - there is nothing
## better to measure on - but it prints PERF_WARN so the condition cannot pass
## unnoticed.

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
var _probe_only: bool = false

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

	# Enumerated after the display has been configured, so the window's screen and
	# the sizes below describe the state the measurement would run in.
	var screens := _enumerate_screens()

	if _probe_only:
		print("PERF_SCREENS " + JSON.stringify(_screen_report(screens)))
		get_tree().quit(0)
		return

	var screen_id := DisplayServer.window_get_current_screen()
	var refusal := _screen_refusal(screens, screen_id)
	if refusal != "":
		print("PERF_ERROR " + refusal)
		get_tree().quit(2)
		return

	_build_entities()

	var root := get_tree().root
	var final_scale: Vector2 = root.get_final_transform().get_scale()
	var vsync_mode: int = DisplayServer.window_get_vsync_mode()

	# Display conditions this measurement is subject to. A screen below 120 Hz
	# paces frame delivery to one refresh period even with vsync off, so fps is
	# capped by the machine rather than by the frame; without the number a capped
	# machine is indistinguishable from a regression (L-040). 0.0 means the
	# platform did not report it - recorded as unknown, never guessed.
	var refresh_hz := 0.0
	var refresh_reported := false
	if screen_id >= 0 and screen_id < screens.size():
		refresh_hz = float(screens[screen_id]["refresh_hz"])
		refresh_reported = bool(screens[screen_id]["refresh_reported"])

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
		"screen": screen_id,
		"refresh_hz": refresh_hz,
		"refresh_reported": refresh_reported,
		"screens": screens,
		"renderer": RenderingServer.get_video_adapter_name(),
		"renderer_vendor": RenderingServer.get_video_adapter_vendor(),
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
		elif a == "--probe-screens":
			_probe_only = true


## Every screen the engine can see, as JSON-safe dictionaries. Refresh is the
## value the platform reported, kept raw alongside a normalised field so that
## "0 Hz" and "not reported at all" are never confused: a Windows virtual adapter
## commonly reports no rate, and the raw value (-1 on this API) says which case
## happened.
func _enumerate_screens() -> Array:
	var out := []
	var count := DisplayServer.get_screen_count()
	var primary: int = DisplayServer.get_primary_screen()
	for i in count:
		var size: Vector2i = DisplayServer.screen_get_size(i)
		var raw := float(DisplayServer.screen_get_refresh_rate(i))
		var pos: Vector2i = DisplayServer.screen_get_position(i)
		out.append({
			"index": i,
			"size": [size.x, size.y],
			"area": size.x * size.y,
			"refresh_hz_raw": raw,
			"refresh_hz": raw if raw > 0.0 else 0.0,
			"refresh_reported": raw > 0.0,
			"primary": i == primary,
			"position": [pos.x, pos.y],
			"scale": DisplayServer.screen_get_scale(i),
		})
	return out


func _screen_report(screens: Array) -> Dictionary:
	return {
		"count": screens.size(),
		"primary": DisplayServer.get_primary_screen(),
		"window_screen": DisplayServer.window_get_current_screen(),
		"screens": screens,
		"renderer": RenderingServer.get_video_adapter_name(),
		"renderer_vendor": RenderingServer.get_video_adapter_vendor(),
		"engine": Engine.get_version_info()["string"],
	}


## Empty string when the screen the window is on can carry a measurement, else
## the reason it cannot. Never silently measures on a screen that reports no
## refresh rate while a screen that does report one exists.
func _screen_refusal(screens: Array, screen_id: int) -> String:
	if screens.is_empty():
		return "the platform enumerated no screens, so there is no display to measure on"
	if screen_id < 0 or screen_id >= screens.size():
		return "the window is on screen %d but only %d screen(s) exist - the number would not be attributable to a display" % [screen_id, screens.size()]
	if bool(screens[screen_id]["refresh_reported"]):
		return ""
	for s in screens:
		if bool(s["refresh_reported"]):
			return "the window is on screen %d, which reports no refresh rate, while screen %d reports %s Hz - that looks like a virtual or streaming display, so this run was refused instead of measured; pass --screen <%d> to measure on the real display" % [screen_id, int(s["index"]), str(s["refresh_hz"]), int(s["index"])]
	print("PERF_WARN only_unreported_screens no enumerated screen reports a refresh rate; this measurement cannot be attributed to a physical display")
	return ""


## Note on flag provenance: OS.get_cmdline_args() does not expose Godot's own
## options, so this script cannot echo back the --screen or --gpu-index it was
## started with (verified: both read as "" while the flags were in force). The
## effects are recorded instead - the window's actual screen is in PERF_INFO, and
## the gate reads the engine's own "Using Device #N" line for the render device.

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
