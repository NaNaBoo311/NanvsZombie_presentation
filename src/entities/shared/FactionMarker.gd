class_name FactionMarker
extends RefCounted

# Clean, grounded faction ground marker & contact shadow:
# - Contact shadow: unshaded alpha-blended radial occlusion disc that grounds the unit into the turf.
# - Faction marker: clean additive rim band (green ring for plants, red spiked ring for enemies).
# Cached in static singletons: zero texture memory, zero extra materials, zero per-frame work.

enum Faction { PLANT, ENEMY }

const MARKER_Y: float = 0.04
const SEGMENTS: int = 24
const PLANT_COLOR := Color(0.20, 0.95, 0.50)
const ENEMY_COLOR := Color(1.0, 0.22, 0.32)

static var _meshes: Array[ArrayMesh] = [null, null]
static var _materials: Array[StandardMaterial3D] = [null, null]
static var _contact_mesh: ArrayMesh = null
static var _contact_mat: StandardMaterial3D = null


## Adds one shared-resource marker under `parent`; returns it so callers can hide it.
static func attach(parent: Node3D, faction: Faction, radius: float) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = "FactionMarker"
	marker.mesh = _get_mesh(faction)
	marker.material_override = _get_material(faction)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.position.y = MARKER_Y
	marker.scale = Vector3(radius, 1.0, radius)

	# Ground contact ambient occlusion shadow directly under the entity
	var shadow := MeshInstance3D.new()
	shadow.name = "ContactShadow"
	shadow.mesh = _get_contact_mesh()
	shadow.material_override = _get_contact_material()
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position.y = -0.025 # Sits at y = 0.015 above island, right on the turf
	shadow.scale = Vector3(1.15, 1.0, 1.15)
	marker.add_child(shadow)

	parent.add_child(marker)
	return marker


static func _get_material(faction: Faction) -> StandardMaterial3D:
	if _materials[faction] == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = PLANT_COLOR if faction == Faction.PLANT else ENEMY_COLOR
		_materials[faction] = mat
	return _materials[faction]


static func _get_contact_material() -> StandardMaterial3D:
	if _contact_mat == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(0.04, 0.07, 0.03, 0.72)
		_contact_mat = mat
	return _contact_mat


static func _get_mesh(faction: Faction) -> ArrayMesh:
	if _meshes[faction] == null:
		_meshes[faction] = _build_mesh(faction == Faction.ENEMY)
	return _meshes[faction]


static func _get_contact_mesh() -> ArrayMesh:
	if _contact_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var c_center := Color(1, 1, 1, 0.85)
		var c_mid := Color(1, 1, 1, 0.45)
		var c_edge := Color(1, 1, 1, 0.0)
		var mid_r := 0.55
		for i in SEGMENTS:
			var a0: float = TAU * float(i) / SEGMENTS
			var a1: float = TAU * float(i + 1) / SEGMENTS
			var m0 := Vector3(cos(a0) * mid_r, 0, sin(a0) * mid_r)
			var m1 := Vector3(cos(a1) * mid_r, 0, sin(a1) * mid_r)
			var e0 := Vector3(cos(a0), 0, sin(a0))
			var e1 := Vector3(cos(a1), 0, sin(a1))
			# Inner core
			_tri(st, Vector3.ZERO, c_center, m0, c_mid, m1, c_mid)
			# Outer falloff
			_tri(st, m0, c_mid, e0, c_edge, e1, c_edge)
			_tri(st, m0, c_mid, e1, c_edge, m1, c_mid)
		_contact_mesh = st.commit()
	return _contact_mesh


# Unit-radius mesh on the XZ plane: clean rim band + spikes (enemy), center left open for contact shadow
static func _build_mesh(spiked: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := Color(1, 1, 1, 0.72)
	var rim_fade := Color(1, 1, 1, 0.0)
	var inner_r: float = 0.86
	for i in SEGMENTS:
		var a0: float = TAU * float(i) / SEGMENTS
		var a1: float = TAU * float(i + 1) / SEGMENTS
		var i0 := Vector3(cos(a0) * inner_r, 0, sin(a0) * inner_r)
		var i1 := Vector3(cos(a1) * inner_r, 0, sin(a1) * inner_r)
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		_tri(st, i0, rim_fade, o0, rim, o1, rim)
		_tri(st, i0, rim_fade, o1, rim, i1, rim_fade)
	if spiked:
		for k in 4:
			var a: float = PI * 0.25 + PI * 0.5 * k
			var d := Vector3(cos(a), 0, sin(a))
			var t := Vector3(-d.z, 0, d.x)
			_tri(st, d * 0.90 + t * 0.18, rim, d * 0.90 - t * 0.18, rim, d * 1.35, rim_fade)
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
