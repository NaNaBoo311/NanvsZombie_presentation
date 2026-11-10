class_name LightingPreset
extends Resource

# One time of day as data: everything DayNightCycle blends (sky gradient, ambient,
# tonemap exposure, glow, fog, colour grade, key/fill/pearl lights) plus the ink
# outline's distance haze and line colour. Presets live in assets/lighting/<id>.tres
# and the file name is the id that levels (time_of_day), maps (default_time_of_day)
# and GameManager.set_time_of_day() use. Adding a time of day = adding one .tres.
#
# `daylight` (0 night .. 1 day) is what the map-owned grades still follow
# (EventBus.day_blend_changed: ground, forest, grass, water shaders, night sky, window
# glow), so a new preset also picks where those land, e.g. dusk = 0.5.

const DIR := "res://assets/lighting/"

@export_range(0.0, 1.0) var daylight: float = 1.0

@export_group("Sky")
@export var sky_top: Color
@export var sky_horizon: Color
@export var sky_curve: float = 0.12
@export var ground_bottom: Color
@export var ground_horizon: Color
@export var ground_curve: float = 0.14

@export_group("Environment")
@export var ambient: Color
@export var ambient_energy: float = 0.4
@export var exposure: float = 1.0
@export var glow_intensity: float = 0.2
@export var glow_bloom: float = 0.05
@export var glow_threshold: float = 1.2
@export var fog_light_color: Color
@export var fog_density: float = 0.005
@export var fog_sky_affect: float = 1.0
@export var grade_saturation: float = 1.0
@export var grade_contrast: float = 1.0

@export_group("Lights")
@export var key_color: Color
@export var key_energy: float = 1.0
@export var key_rotation: Vector3
@export var shadow_opacity: float = 0.8
@export var fill_color: Color
@export var fill_energy: float = 0.0
@export var pearl_energy: float = 1.0

@export_group("Ink outline")
@export var haze_color: Color
@export var ink_color: Color


## Every preset id (file names under DIR, sorted).
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".tres"):
			out.append(f.get_basename())
	out.sort()
	return out


## The preset `id`, or null (with an error) if there is no such file.
static func load_id(id: String) -> LightingPreset:
	var path := DIR + id + ".tres"
	if not ResourceLoader.exists(path):
		push_error("LightingPreset: no preset \"%s\" (%s)" % [id, path])
		return null
	return load(path) as LightingPreset


## A new preset between `a` and `b` at `t` (every exported float, Color and Vector3
## blended). DayNightCycle snapshots the current look with it when the time of day
## changes mid-transition.
static func mix(a: LightingPreset, b: LightingPreset, t: float) -> LightingPreset:
	var out := LightingPreset.new()
	for prop in out.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: StringName = prop["name"]
		var va: Variant = a.get(n)
		var vb: Variant = b.get(n)
		if va is float:
			out.set(n, lerpf(va, vb, t))
		elif va is Color or va is Vector3:
			out.set(n, va.lerp(vb, t))
	return out
