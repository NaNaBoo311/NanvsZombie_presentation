extends MultiMeshInstance3D

# Street traffic round a map's street ring, built once in _ready() and then moved only
# by assets/shaders/StreetTraffic.gdshader (zero CPU per frame, AGENTS.md invariant 7).
# The instances keep identity transforms; each one's INSTANCE_CUSTOM holds its start
# offset on the loop, its lane (+ a little sideways jitter), its vehicle variant (UV.x
# in the mesh) and its speed. The loop is the centreline of the street band of the
# map's zone file streets.json ({outer: [x0, z0, x1, z1], width}), read through the
# owning map's zone script (src/maps/MapZones.gd). Vehicles in a lane share one speed
# and are evenly spaced (with jitter smaller than the gap), so they never drive
# through each other. One draw call; no shadows (ground-level decoration, invariant 4).

@export var scene_path: String = "res://assets/models/architecture/hanoi_traffic.glb"
@export var per_lane: int = 28
## Share of each variant in the traffic, by UV.x variant id (0 motorbike, 1 two-up
## motorbike, 2 cyclo for hanoi_traffic.glb).
@export var variant_weights: PackedFloat32Array = PackedFloat32Array([0.55, 0.35, 0.1])
@export var lane_speeds: Vector2 = Vector2(7.0, 6.5)
@export var corner_radius: float = 5.0
@export var lane_offset: float = 1.6

const SHADER := preload("res://assets/shaders/StreetTraffic.gdshader")


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var streets: Dictionary = MapZones.for_node(self).data().get("streets", {})
	var scene := load(scene_path) as PackedScene
	if streets.is_empty() or scene == null:
		push_warning("StreetTraffic: no streets zone or no '%s'; no traffic." % scene_path)
		return
	var tmpl := scene.instantiate()
	var mesh_node := tmpl.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (mesh_node[0] as MeshInstance3D).mesh if not mesh_node.is_empty() else null
	tmpl.free()
	if mesh == null:
		push_warning("StreetTraffic: no mesh in '%s'." % scene_path)
		return

	var o: Array = streets["outer"]
	var half_w := float(streets["width"]) * 0.5
	var centre := Vector2((float(o[0]) + float(o[2])) * 0.5, (float(o[1]) + float(o[3])) * 0.5)
	var half := Vector2((float(o[2]) - float(o[0])) * 0.5 - half_w, (float(o[3]) - float(o[1])) * 0.5 - half_w)

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("loop_centre", centre)
	mat.set_shader_parameter("loop_half", half)
	mat.set_shader_parameter("corner_r", corner_radius)
	mat.set_shader_parameter("lane_offset", lane_offset)
	material_override = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = per_lane * 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 1010
	var total := 0.0
	for w in variant_weights:
		total += w
	for lane in 2:
		for i in per_lane:
			var idx := lane * per_lane + i
			mm.set_instance_transform(idx, Transform3D.IDENTITY)
			var pick := rng.randf() * total
			var variant := 0
			while variant < variant_weights.size() - 1 and pick > variant_weights[variant]:
				pick -= variant_weights[variant]
				variant += 1
			var offset := (float(i) + rng.randf_range(-0.3, 0.3)) / float(per_lane)
			var jitter := rng.randf_range(-0.35, 0.35)
			var speed := lane_speeds.x if lane == 0 else lane_speeds.y
			mm.set_instance_custom_data(idx, Color(offset, float(lane) + jitter, float(variant), speed))
	multimesh = mm
	# The instances sit at the origin until the shader moves them: cull by the whole ring.
	custom_aabb = AABB(Vector3(centre.x - half.x - 4.0, -1.0, centre.y - half.y - 4.0), Vector3(half.x * 2.0 + 8.0, 5.0, half.y * 2.0 + 8.0))
