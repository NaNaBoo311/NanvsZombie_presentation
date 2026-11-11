class_name ConceptAtlas
extends Node3D

# The 3D half of The World: the Vietnam atlas as a full-screen stage far from the
# talk's title diorama. The glb's provinces live in one locked mesh plus one raised
# piece per playable world; all province pieces share AtlasProvince.gdshader, whose
# focus_id / focus_dim dims the rest and hover tint warms the picked one. The stage
# is static: switching worlds only writes a few shader uniforms, so there is no
# idle script cost.

const SCENE_PATH := "res://assets/models/environment/vietnam_world_atlas.glb"
const SHADER_PATH := "res://assets/shaders/AtlasProvince.gdshader"
const ORIGIN := Vector3(300.0, 0.0, 0.0)
const ATLAS_YAW := 0.34
const FOCUS_DIM := 0.55
const HOVER_MIX := 0.40

var current := 0
var focus_id := -1

var _provinces := AtlasProvinces.load_default()
var _material: ShaderMaterial
var _pivot: Node3D
var _model: Node3D


func _ready() -> void:
	position = ORIGIN
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.rotation.y = ATLAS_YAW
	add_child(_pivot)

	_model = (load(SCENE_PATH) as PackedScene).instantiate()
	_model.name = "Atlas"
	# data/atlas_provinces.json holds world XZ metres; the tray is not centred on
	# the glb origin, so move it under the pivot before the yaw.
	var centre := _provinces.tray.get_center()
	_model.position = Vector3(-centre.x, 0.0, -centre.y)
	_pivot.add_child(_model)

	_setup_materials()
	set_world(0)


func set_world(index: int) -> void:
	current = clampi(index, 0, PresentationDeck.WORLDS.size() - 1)
	focus_id = province_index(current)
	if _material != null:
		_material.set_shader_parameter("focus_id", focus_id)
		_material.set_shader_parameter("focus_dim", FOCUS_DIM)
		# The picked province also takes the shader's hover tint, so it warms up
		# against the dimmed board. The lift stays off: this stage is a backdrop,
		# so no piece rises out of it.
		_material.set_shader_parameter("hovered_id", focus_id)
		_material.set_shader_parameter("hover_lift", 0.0)
		_material.set_shader_parameter("hover_mix", HOVER_MIX)


## Atlas province index for a deck world, or -1 if the id is not on the atlas.
func province_index(world_index: int) -> int:
	if world_index < 0 or world_index >= PresentationDeck.WORLDS.size():
		return -1
	return _provinces.index_of(str(PresentationDeck.WORLDS[world_index]["id"]))


func _setup_materials() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := mi as MeshInstance3D
		if mesh_node.name.begins_with("Provinces_Locked") or mesh_node.name.begins_with("Province_"):
			mesh_node.material_override = _material
			continue
		# Other baked-colour meshes: Godot's glTF import stores COLOR_0 sRGB-encoded.
		for s in mesh_node.mesh.get_surface_count():
			var colors: Variant = mesh_node.mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
			var mat := mesh_node.mesh.surface_get_material(s) as StandardMaterial3D
			if mat and colors is PackedColorArray and not (colors as PackedColorArray).is_empty():
				mat.vertex_color_use_as_albedo = true
