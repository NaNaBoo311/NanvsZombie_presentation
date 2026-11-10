extends MultiMeshInstance3D

# Pedestrians strolling a map's streets, built once in _ready() and then walked only by
# assets/shaders/StreetWalkers.gdshader (zero CPU per frame, AGENTS.md invariant 7).
# The walk segments come from the map's zone file walkers.json (read through the owning
# map's zone script, src/maps/MapZones.gd): each segment {from: [x, z], to: [x, z], y,
# lanes: [sideways offsets], per_lane, speed: [min, max]} is a street's centre line;
# every walker gets a lane (plus a little sideways jitter), a start phase, a speed, a
# variant (by `variants` weight), a palette colour and a size. Each one walks to the end
# of its segment, turns and comes back. One draw call; no shadows (invariant 4).
# The shader clock (TIME) wraps every rendering/limits/time/time_rollover_secs, so each
# speed is nudged to a whole number of round trips per wrap: nobody jumps at the wrap.

const SHADER := preload("res://assets/shaders/StreetWalkers.gdshader")
const PALETTE_SIZE := 10 # StreetWalkers.gdshader palette[10]

@export var scene_path: String = ""


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cfg: Dictionary = MapZones.for_node(self).data().get("walkers", {})
	var scene := load(scene_path) as PackedScene
	if cfg.is_empty() or scene == null:
		push_warning("StreetWalkers: no walkers zone or no '%s'; the streets stay empty." % scene_path)
		return
	var tmpl := scene.instantiate()
	var nodes := tmpl.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (nodes[0] as MeshInstance3D).mesh if not nodes.is_empty() else null
	tmpl.free()
	if mesh == null:
		push_warning("StreetWalkers: no mesh in '%s'." % scene_path)
		return

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var palette := PackedVector3Array()
	for hex in cfg["palette"]:
		var c := Color.html(str(hex)).srgb_to_linear() # COLOR in the mesh is linear too
		palette.append(Vector3(c.r, c.g, c.b))
	palette.resize(PALETTE_SIZE)
	mat.set_shader_parameter("palette", palette)
	material_override = mat

	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg["seed"])
	var rollover := float(ProjectSettings.get_setting("rendering/limits/time/time_rollover_secs", 3600.0))
	var weights: Dictionary = cfg["variants"]
	var colours := (cfg["palette"] as Array).size()
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for seg: Dictionary in cfg["segments"]:
		var a := Vector2(float(seg["from"][0]), float(seg["from"][1]))
		var b := Vector2(float(seg["to"][0]), float(seg["to"][1]))
		var len := a.distance_to(b)
		var dir := (b - a) / len
		var side := Vector2(dir.y, -dir.x)
		var yaw := atan2(dir.x, dir.y) # turns the walker's +Z onto the street
		var y := float(seg["y"])
		var n := int(seg["per_lane"])
		for lane in seg["lanes"]:
			for i in n:
				var size := rng.randf_range(0.92, 1.06)
				var p := a + side * (float(lane) + rng.randf_range(-0.25, 0.25))
				var origin := Vector3(p.x, y, p.y)
				xforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), origin))
				var speed := rng.randf_range(float(seg["speed"][0]), float(seg["speed"][1]))
				speed = maxf(1.0, roundf(speed * rollover / (2.0 * len))) * 2.0 * len / rollover
				var phase := (float(i) + rng.randf_range(0.0, 0.7)) / float(n)
				var variant := _weighted(weights, rng)
				var look := float(variant) * 10.0 + float(rng.randi_range(0, colours - 1)) + rng.randf() * 0.99
				customs.append(Color(phase, len, speed, look))
				for q in [origin, Vector3(b.x, y, b.y) + Vector3(side.x, 0.0, side.y) * float(lane)]:
					lo = lo.min(q)
					hi = hi.max(q)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = customs.size()
	for i in customs.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i])
	multimesh = mm
	# The instances are moved by the shader along their segments: cull by the whole set.
	# custom_aabb is in this node's space, which sits at the map origin.
	custom_aabb = AABB(lo - Vector3(2.0, 0.5, 2.0), hi - lo + Vector3(4.0, 3.0, 4.0))


static func _weighted(weights: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var pick := rng.randf() * total
	for k in weights:
		pick -= float(weights[k])
		if pick <= 0.0:
			return int(k)
	return int(weights.keys().back())
