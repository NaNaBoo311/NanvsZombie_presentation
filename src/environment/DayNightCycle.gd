extends Node3D

# Time-of-day renderer for the battle shell (DioramaWorld).
#
# Single authority for the time-of-day LOOK. GameManager owns the STATE
# (`GameManager.time_of_day`, a LightingPreset id) and announces it on
# `EventBus.time_of_day_changed`; this node cross-fades from the current look to
# that preset (assets/lighting/<id>.tres, src/environment/LightingPreset.gd).
#
# What it drives, all from one eased 0..1 blend between two presets:
#   - ProceduralSkyMaterial gradient
#   - WorldEnvironment ambient / tonemap exposure / glow / depth fog / colour grade
#   - The key DirectionalLight3D + the unshadowed DirectionalMoonFill
#   - The pearl glow light energy
#   - The ink outline's distance haze and line colour (InkOutlinePostProcess.set_colors)
#   - NightSky.set_day_blend(daylight) -> stars + moon + night band vs white cumulus deck
#   - EventBus.day_blend_changed(daylight) -> the loaded map grades its own nodes
#     (ground, lanterns, forest, grass, water; see e.g. src/maps/landmark_81/Landmark81Map.gd).
#     `daylight` is the presets' own 0 (night) .. 1 (day) value, blended. Emitted only
#     while a transition runs (or on a scene-entry snap); a freshly loaded map reads
#     GameManager.daylight().
#
# Low-end / no-GPU budget (see AGENTS.md "Invariants"):
#   - Idle cost is ZERO: `_process` is disabled unless a transition is in flight.
#   - A phase set in the scene's first frame (the boot map/level default) snaps, so
#     entering a night level never plays a day->night sweep.
#   - The sky gradient is the only expensive write (it forces a radiance re-bake),
#     so it is throttled to ~15 Hz during the blend instead of per-frame, and the
#     Sky drops to the cheap REALTIME process mode for the duration only.
#   - At either end point every faded-out system is hidden AND switched off
#     (the off-duty sky layer here, lantern lights in the map), so the settled
#     phase is strictly cheaper than today's night scene, never more expensive.
#   - No project-settings `global uniform`: those are registered only at engine
#     startup, so adding one breaks every already-open editor and running game
#     until it is restarted. Shared ShaderMaterials are pushed from here instead.

const TRANSITION_TIME := 2.6           # Seconds for a full preset-to-preset sweep
const SKY_UPDATE_INTERVAL := 1.0 / 15.0 # Radiance re-bake cadence while blending

@export var world_environment_path: NodePath = ^"../WorldEnvironment"
@export var key_light_path: NodePath = ^"../DirectionalMoonlight"
@export var fill_light_path: NodePath = ^"../DirectionalMoonFill"
@export var pearl_light_path: NodePath = ^"../SacredDragonPearl/PearlGlowLight"
@export var night_sky_path: NodePath = ^"../NightSky"
@export var ink_path: NodePath = ^"../InkOutlinePostProcess"

var _environment: Environment = null
var _sky: Sky = null
var _sky_material: ProceduralSkyMaterial = null
var _key_light: DirectionalLight3D = null
var _fill_light: DirectionalLight3D = null
var _pearl_light: OmniLight3D = null
var _night_sky: Node = null
var _ink: Node = null
var _from: LightingPreset = null # look at the start of the current blend
var _to: LightingPreset = null   # target preset
var _blend: float = 1.0          # Raw 0..1 progress from _from to _to
var _sky_accum: float = 0.0
var _ready_frame: int = -1 # Changes arriving in this frame (boot map default) snap instead of fading

func _ready() -> void:
	_resolve_nodes()

	# Dev smoke test (matches the existing `-- --ghost-test` convention): boot straight
	# into daylight with no transition, e.g. for `-- --screenshot --day-test`.
	if "--day-test" in OS.get_cmdline_user_args():
		GameManager.set_time_of_day("day") # Emitted before we connect, so nothing animates
	elif "--night-test" in OS.get_cmdline_user_args():
		GameManager.set_time_of_day("night")

	_ready_frame = Engine.get_process_frames()
	EventBus.time_of_day_changed.connect(_on_time_of_day_changed)

	_to = LightingPreset.load_id(GameManager.time_of_day)
	_from = _to
	_blend = 1.0
	_apply_blend(_blend, true)
	set_process(false) # Zero idle cost until something actually changes

func _resolve_nodes() -> void:
	var world_env := get_node_or_null(world_environment_path) as WorldEnvironment
	if world_env:
		_environment = world_env.environment
		if _environment:
			_sky = _environment.sky
			if _sky:
				_sky_material = _sky.sky_material as ProceduralSkyMaterial
				# A small radiance map is all this stylized scene needs, and it keeps the
				# per-transition re-bakes affordable on integrated GPUs.
				_sky.radiance_size = Sky.RADIANCE_SIZE_128

	_key_light = get_node_or_null(key_light_path) as DirectionalLight3D
	if _key_light:
		# Opacity is per preset (blended); the blur stays a soft watercolor edge.
		_key_light.shadow_blur = 1.6
	_fill_light = get_node_or_null(fill_light_path) as DirectionalLight3D
	_pearl_light = get_node_or_null(pearl_light_path) as OmniLight3D
	_night_sky = get_node_or_null(night_sky_path)
	_ink = get_node_or_null(ink_path)

	# Depth fog is per-fragment inside the existing material pass (not volumetric
	# fog): no extra draw calls, no fullscreen pass. Set once here, never
	# tweened - toggling fog_enabled mid-blend pops.
	if _environment:
		_environment.fog_enabled = true
		_environment.fog_mode = Environment.FOG_MODE_DEPTH
		# Colour grade (per preset): applied inside the existing tonemap pass, so it
		# costs nothing.
		_environment.adjustment_enabled = true

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	if event.keycode != KEY_T:
		return
	# Overlays own the keyboard while they are up (matches SeedBank / EnemyDebugSpawner).
	if GameManager.is_any_selector_open():
		return
	GameManager.cycle_time_of_day()
	get_viewport().set_input_as_handled()


func _on_time_of_day_changed(id: String) -> void:
	var target := LightingPreset.load_id(id)
	if target == null or target == _to:
		return
	if Engine.get_process_frames() == _ready_frame:
		# Scene entry: the map/level phase is the starting look, not a transition.
		_from = target
		_to = target
		_blend = 1.0
		_apply_blend(_blend, true)
		return
	# Start from wherever the look is now, so a change mid-blend never jumps.
	_from = LightingPreset.mix(_from, _to, smoothstep(0.0, 1.0, _blend)) if _blend < 1.0 else _to
	_to = target
	_blend = 0.0
	# Cheap, low-quality sky updates are exactly right for a moving gradient.
	if _sky:
		_sky.process_mode = Sky.PROCESS_MODE_REALTIME
	_sky_accum = SKY_UPDATE_INTERVAL # Force a sky write on the very first blend frame
	set_process(true)

func _process(delta: float) -> void:
	_blend = move_toward(_blend, 1.0, delta / TRANSITION_TIME)
	var finished := is_equal_approx(_blend, 1.0)

	_sky_accum += delta
	var write_sky := finished or _sky_accum >= SKY_UPDATE_INTERVAL
	if write_sky:
		_sky_accum = 0.0

	_apply_blend(_blend, write_sky)

	if finished:
		# Settle: one last full-quality bake, then go completely idle again.
		_from = _to
		if _sky:
			_sky.process_mode = Sky.PROCESS_MODE_QUALITY
		set_process(false)

# `blend` is raw progress; everything reads the eased curve so the sweep starts and
# lands softly. `write_sky` gates the only radiance-re-baking write.
func _apply_blend(blend: float, write_sky: bool) -> void:
	if _from == null or _to == null:
		return
	var t := smoothstep(0.0, 1.0, blend)
	var a := _from
	var b := _to

	if write_sky and _sky_material:
		_sky_material.sky_top_color = a.sky_top.lerp(b.sky_top, t)
		_sky_material.sky_horizon_color = a.sky_horizon.lerp(b.sky_horizon, t)
		_sky_material.sky_curve = lerpf(a.sky_curve, b.sky_curve, t)
		_sky_material.ground_bottom_color = a.ground_bottom.lerp(b.ground_bottom, t)
		_sky_material.ground_horizon_color = a.ground_horizon.lerp(b.ground_horizon, t)
		_sky_material.ground_curve = lerpf(a.ground_curve, b.ground_curve, t)

	if _environment:
		_environment.ambient_light_color = a.ambient.lerp(b.ambient, t)
		_environment.ambient_light_energy = lerpf(a.ambient_energy, b.ambient_energy, t)
		_environment.tonemap_exposure = lerpf(a.exposure, b.exposure, t)
		_environment.glow_intensity = lerpf(a.glow_intensity, b.glow_intensity, t)
		_environment.glow_bloom = lerpf(a.glow_bloom, b.glow_bloom, t)
		_environment.glow_hdr_threshold = lerpf(a.glow_threshold, b.glow_threshold, t)
		_environment.fog_light_color = a.fog_light_color.lerp(b.fog_light_color, t)
		_environment.fog_density = lerpf(a.fog_density, b.fog_density, t)
		_environment.fog_sky_affect = lerpf(a.fog_sky_affect, b.fog_sky_affect, t)
		_environment.adjustment_saturation = lerpf(a.grade_saturation, b.grade_saturation, t)
		_environment.adjustment_contrast = lerpf(a.grade_contrast, b.grade_contrast, t)

	if _key_light:
		_key_light.light_color = a.key_color.lerp(b.key_color, t)
		_key_light.light_energy = lerpf(a.key_energy, b.key_energy, t)
		_key_light.rotation_degrees = a.key_rotation.lerp(b.key_rotation, t)
		_key_light.shadow_opacity = lerpf(a.shadow_opacity, b.shadow_opacity, t)

	if _fill_light:
		_fill_light.light_color = a.fill_color.lerp(b.fill_color, t)
		_fill_light.light_energy = lerpf(a.fill_energy, b.fill_energy, t)

	if _pearl_light:
		_pearl_light.light_energy = lerpf(a.pearl_energy, b.pearl_energy, t)

	if _ink and _ink.has_method(&"set_colors"):
		_ink.set_colors(a.haze_color.lerp(b.haze_color, t), a.ink_color.lerp(b.ink_color, t))

	var daylight := lerpf(a.daylight, b.daylight, t)
	if _night_sky and _night_sky.has_method(&"set_day_blend"):
		_night_sky.set_day_blend(daylight)
	# The loaded map grades its own nodes (ground, lanterns, forest, grass, water).
	EventBus.day_blend_changed.emit(daylight)
