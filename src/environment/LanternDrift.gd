extends MultiMeshInstance3D

# Boats and lanterns that move, built once in _ready() and then moved only by
# assets/shaders/LanternDrift.gdshader (zero CPU per frame, AGENTS.md invariant 7).
# `kind` picks what this batch holds, from the map's zone file drift.json (read through
# the owning map's zone script, src/maps/MapZones.gd):
#   "boats"           drift_boat.glb; one instance per boat in each lane, evenly spaced
#                     with a lane's one speed and direction, so boats never overlap.
#   "river_lanterns"  drift_river_lanterns.glb; floating lanterns of several shapes and
#                     colours, some let go below the bridge, the rest drifting the river.
#   "sky_lanterns"    drift_sky_lanterns.glb; sky lanterns of several shapes, colours and
#                     sizes, released all over the map's release_areas.
# A mesh holds several shapes and the shader collapses the ones an instance is not.
# River instances keep identity transforms; a sky lantern's transform is its release
# point. INSTANCE_CUSTOM carries the motion (see the shader's header). The owning map
# calls set_day_blend() from its EventBus.day_blend_changed handler. One draw call per
# batch; no shadows (invariant 4).
# The shader clock (TIME) wraps every rendering/limits/time/time_rollover_secs, so
# every speed is nudged to a whole number of trips per wrap (_seamless) and the sky
# period must divide it: nothing jumps when the clock wraps.

const SHADER := preload("res://assets/shaders/LanternDrift.gdshader")
const MOTION_BOAT := 0
const MOTION_RELEASED := 1
const MOTION_SKY := 2
const MOTION_DRIFTING := 3
const SHAPE_BOAT := 0
const PALETTE_SIZE := 12 # LanternDrift.gdshader palette[12]

@export var scene_path: String = ""
@export_enum("boats", "river_lanterns", "sky_lanterns") var kind: String = "boats"

var _mat: ShaderMaterial = null
var _river_len: float = 1.0
var _release_len: float = 1.0


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var zones: Dictionary = MapZones.for_node(self).data()
	var cfg: Dictionary = zones.get("drift", {})
	var scene := load(scene_path) as PackedScene
	if cfg.is_empty() or scene == null:
		push_warning("LanternDrift: no drift zone or no '%s'; nothing moves." % scene_path)
		return
	var tmpl := scene.instantiate()
	var nodes := tmpl.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (nodes[0] as MeshInstance3D).mesh if not nodes.is_empty() else null
	tmpl.free()
	if mesh == null:
		push_warning("LanternDrift: no mesh in '%s'." % scene_path)
		return

	var river: Array = cfg["river_span"]
	var water_y := float((zones.get("river", {}) as Dictionary).get("water_y", 0.0))
	var lanterns: Dictionary = cfg["river_lanterns"]
	var sky: Dictionary = cfg["sky_lanterns"]
	var bridge_x := float(((zones.get("landmarks", {}) as Dictionary).get("an_hoi_bridge", {}) as Dictionary).get("from", [0.0])[0])
	_river_len = float(river[1]) - float(river[0])
	_release_len = float(lanterns["release_span"])
	var rollover := float(ProjectSettings.get_setting("rendering/limits/time/time_rollover_secs", 3600.0))
	if not is_zero_approx(fmod(rollover, float(sky["period"]))):
		push_warning("LanternDrift: sky period %s does not divide the %ss shader clock wrap; sky lanterns jump once per wrap." % [sky["period"], rollover])

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("river_span", Vector2(float(river[0]), float(river[1])))
	# Let go just downstream of An Hoi bridge, clear of its piers.
	_mat.set_shader_parameter("release_span", Vector2(bridge_x + 3.0, bridge_x + 3.0 + _release_len))
	_mat.set_shader_parameter("fade", float(cfg["fade"]))
	_mat.set_shader_parameter("water_y", water_y)
	_mat.set_shader_parameter("sky_rise", float(sky["rise"]))
	_mat.set_shader_parameter("sky_period", float(sky["period"]))
	_mat.set_shader_parameter("sky_wind", Vector2(float(sky["wind"][0]), float(sky["wind"][1])))
	var palette := PackedVector3Array()
	for hex in cfg["palette"]:
		var c := Color.html(str(hex)).srgb_to_linear() # COLOR in the mesh is linear too
		palette.append(Vector3(c.r, c.g, c.b))
	palette.resize(PALETTE_SIZE)
	_mat.set_shader_parameter("palette", palette)
	material_override = _mat

	var origins: Array[Vector3] = []
	var customs: Array[Color] = []
	match kind:
		"boats":
			_boat_instances(cfg["boats"], origins, customs)
		"river_lanterns":
			_river_lantern_instances(lanterns, origins, customs)
		"sky_lanterns":
			_sky_lantern_instances(sky, origins, customs)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = customs.size()
	for i in customs.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, origins[i]))
		mm.set_instance_custom_data(i, customs[i])
	multimesh = mm
	# The instances are moved by the shader: cull by where they go.
	var x0 := float(river[0]) - 4.0
	var x1 := float(river[1]) + 4.0
	if kind == "sky_lanterns":
		var reach := Vector2(float(sky["wind"][0]), float(sky["wind"][1])) * float(sky["period"])
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for o in origins:
			lo = lo.min(o)
			hi = hi.max(o)
		custom_aabb = AABB(lo - Vector3(4.0, 1.0, 4.0), hi - lo + Vector3(reach.x + 8.0, float(sky["rise"]) + 6.0, reach.y + 8.0))
	else:
		custom_aabb = AABB(Vector3(x0, water_y - 1.0, 24.0), Vector3(x1 - x0, 4.0, 30.0))


## 0 = night .. 1 = day, from the owning map's day/night handler.
func set_day_blend(t: float) -> void:
	if _mat:
		_mat.set_shader_parameter("day_blend", t)


# The nearest speed that makes a whole number of trips of `length` metres per wrap.
func _seamless(speed: float, length: float) -> float:
	var rollover := float(ProjectSettings.get_setting("rendering/limits/time/time_rollover_secs", 3600.0))
	return maxf(1.0, roundf(speed * rollover / length)) * length / rollover


# A key of a {key: weight} dictionary, drawn by weight.
static func _weighted(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var pick := rng.randf() * total
	for k in weights:
		pick -= float(weights[k])
		if pick <= 0.0:
			return str(k)
	return str(weights.keys().back())


# INSTANCE_CUSTOM.w: shape id * 10 + palette index + bob phase (a fraction).
static func _look(shape: int, colour: int, rng: RandomNumberGenerator) -> float:
	return float(shape) * 10.0 + float(colour) + rng.randf() * 0.99


func _boat_instances(boats: Dictionary, origins: Array[Vector3], out: Array[Color]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(boats["seed"])
	for lane: Dictionary in boats["lanes"]:
		var n := int(lane["count"])
		var speed := _seamless(float(lane["speed"]), _river_len) * signf(float(lane["dir"]))
		for i in n:
			var phase := (float(i) + rng.randf_range(-0.2, 0.2)) / float(n)
			origins.append(Vector3.ZERO)
			out.append(Color(fposmod(phase, 1.0), float(lane["z"]), MOTION_BOAT * 10.0 + 5.0 + speed, _look(SHAPE_BOAT, 0, rng)))


func _river_lantern_instances(cfg: Dictionary, origins: Array[Vector3], out: Array[Color]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg["seed"])
	var colours: Array = cfg["colours"]
	for i in int(cfg["count"]):
		var released := rng.randf() < float(cfg["release"])
		var motion := MOTION_RELEASED if released else MOTION_DRIFTING
		var speed := _seamless(rng.randf_range(float(cfg["speed"][0]), float(cfg["speed"][1])), _release_len if released else _river_len)
		var z := rng.randf_range(float(cfg["z"][0]), float(cfg["z"][1]))
		var shape := int(_weighted(cfg["shapes"], rng))
		var colour := int(colours[rng.randi_range(0, colours.size() - 1)])
		origins.append(Vector3.ZERO)
		out.append(Color(rng.randf(), z, motion * 10.0 + 5.0 + speed, _look(shape, colour, rng)))


func _sky_lantern_instances(cfg: Dictionary, origins: Array[Vector3], out: Array[Color]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg["seed"])
	var areas: Array = cfg["release_areas"]
	var weights := {}
	for i in areas.size():
		var r: Array = areas[i]["rect"]
		weights[i] = float(areas[i]["weight"]) * (float(r[2]) - float(r[0])) * (float(r[3]) - float(r[1]))
	var colours: Array = cfg["colours"]
	var n := int(cfg["count"])
	for i in n:
		var area: Dictionary = areas[int(_weighted(weights, rng))]
		var r: Array = area["rect"]
		origins.append(Vector3(rng.randf_range(float(r[0]), float(r[2])), float(area["y"]), rng.randf_range(float(r[1]), float(r[3]))))
		# Evenly spread through the cycle, so lanterns are always rising at every height.
		var phase := (float(i) + rng.randf_range(0.0, 0.8)) / float(n)
		var size := rng.randf_range(float(cfg["size"][0]), float(cfg["size"][1]))
		var shape := int(_weighted(cfg["shapes"], rng))
		var colour := int(colours[rng.randi_range(0, colours.size() - 1)])
		out.append(Color(phase, size, MOTION_SKY * 10.0 + 5.0, _look(shape, colour, rng)))
