extends MultiMeshInstance3D

# Cars driving a map's streets, built once in _ready() and then driven only by
# assets/shaders/StreetCars.gdshader (zero CPU per frame, AGENTS.md invariant 7). The lots
# (x, lane z, yaw) come from the map's lots() key `zone_lots` (src/maps/MapZones.gd), the
# span they loop over and the palette from the map's zone data: north_city.traffic.x /
# north_city.traffic.palette. Every lane drives at its own speed, so cars never overtake;
# the shader clock (TIME) wraps every rendering/limits/time/time_rollover_secs, so each
# speed is nudged to a whole number of laps per wrap: nobody jumps at the wrap.
# Past the island rim (outskirts island_bounds.x) the shader crossfades each car to the
# outskirts silhouette tone; the rim and the day/night blend are the only uniforms ever
# touched again, via EventBus.day_blend_changed (signal-only, zero idle cost).
# One draw call; no shadows (invariant 4).

const SHADER := preload("res://assets/shaders/StreetCars.gdshader")
const PALETTE_SIZE := 6 # StreetCars.gdshader palette[6]
const SPEED_RANGE := Vector2(6.0, 11.0) # m/s, picked per lane

@export var scene_path: String = ""
@export var zone_lots: String = "city_cars"

var _mat: ShaderMaterial = null


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var zones := MapZones.for_node(self)
	var cfg: Dictionary = (zones.data().get("north_city", {}) as Dictionary).get("traffic", {})
	var scene := load(scene_path) as PackedScene
	var lots: Array = zones.lots(zone_lots) if not cfg.is_empty() else []
	if lots.is_empty() or scene == null:
		push_warning("StreetCars: no traffic zone, lots or '%s'; the streets stay empty." % scene_path)
		return
	var tmpl := scene.instantiate()
	var items := PropMultiMesh.collect_meshes(tmpl)
	tmpl.free()
	if items.is_empty():
		push_warning("StreetCars: no mesh in '%s'." % scene_path)
		return
	var mesh: Mesh = items[0]["mesh"]
	var mesh_xf: Transform3D = items[0]["xf"]

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var palette := PackedVector3Array()
	for hex in cfg["palette"]:
		var c := Color.html(str(hex)).srgb_to_linear() # COLOR in the mesh is linear too
		palette.append(Vector3(c.r, c.g, c.b))
	palette.resize(PALETTE_SIZE)
	mat.set_shader_parameter("palette", palette)
	# Outskirts crossfade rim: single source of truth is outskirts island_bounds.x
	# (the streets run on across it); maps without one keep the huge default: never.
	var ob: Dictionary = zones.data().get("outskirts", {})
	var ib: Array = (ob.get("island_bounds", {}) as Dictionary).get("x", [])
	if ib.size() == 2:
		mat.set_shader_parameter("rim_x", maxf(absf(float(ib[0])), absf(float(ib[1]))))
	_mat = mat
	material_override = mat
	EventBus.day_blend_changed.connect(_on_day_blend)
	# Settled phase at load; DayNightCycle only signals while a transition runs.
	_on_day_blend(GameManager.daylight())

	var start := float(cfg["x"][0])
	var length := float(cfg["x"][1]) - start
	var rollover := float(ProjectSettings.get_setting("rendering/limits/time/time_rollover_secs", 3600.0))
	var colours := (cfg["palette"] as Array).size()
	var lane_speed := {}
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = lots.size()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var inv := global_transform.affine_inverse()
	for i in lots.size():
		var lot: Dictionary = lots[i]
		var pos: Vector3 = lot["pos"]
		var yaw := deg_to_rad(float(lot["yaw"]))
		# One speed per lane (lane = its z), a whole number of laps per shader-clock wrap.
		var lane := int(roundf(pos.z * 2.0))
		if not lane_speed.has(lane):
			var h := fposmod(sin(float(lane) * 12.9898) * 43758.5453, 1.0)
			var speed := lerpf(SPEED_RANGE.x, SPEED_RANGE.y, h)
			lane_speed[lane] = maxf(1.0, roundf(speed * rollover / length)) * length / rollover
		mm.set_instance_transform(i, inv * Transform3D(Basis(Vector3.UP, yaw), pos) * mesh_xf)
		var colour := float(int(fposmod(sin(float(i) * 78.233) * 43758.5453, 1.0) * colours) % colours)
		mm.set_instance_custom_data(i, Color(lane_speed[lane], start, length, colour))
		lo = lo.min(Vector3(start, pos.y, pos.z))
		hi = hi.max(Vector3(start + length, pos.y, pos.z))
	multimesh = mm
	# The cars are moved by the shader along their lanes: cull by the whole span.
	# custom_aabb is in this node's space, which sits at the map origin.
	custom_aabb = AABB(lo - Vector3(2.0, 0.5, 2.0), hi - lo + Vector3(4.0, 3.0, 4.0))


# `t` is the eased 0 (night) .. 1 (day) blend from DayNightCycle.
func _on_day_blend(t: float) -> void:
	if _mat:
		_mat.set_shader_parameter("day_blend", t)
