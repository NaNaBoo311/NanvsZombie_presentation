class_name ConceptAtlas
extends Node3D

# The 3D half of The World: the Vietnam atlas as a full-screen stage far from the
# talk's title diorama. The glb's provinces live in one locked mesh plus one raised
# piece per playable world; all province pieces share AtlasProvince.gdshader, whose
# focus_id / focus_dim dims the rest and hover tint warms the picked one. A gold
# light pillar rises from the picked province. Switching worlds only writes a few
# uniforms and one short beam tween, so the stage has no idle script cost.

const SCENE_PATH := "res://assets/models/environment/vietnam_world_atlas.glb"
const SHADER_PATH := "res://assets/shaders/AtlasProvince.gdshader"
const BEAM_SHADER_PATH := "res://assets/shaders/AtlasFocusBeam.gdshader"
const ORIGIN := Vector3(300.0, 0.0, 0.0)
const ATLAS_YAW := 0.34
const FOCUS_DIM := 0.62
const HOVER_MIX := 0.50
const BEAM_HEIGHT := 6.0

var current := 0
var focus_id := -1

var _provinces := AtlasProvinces.load_default()
var _material: ShaderMaterial
var _pivot: Node3D
var _model: Node3D
var _beam: Node3D
var _beam_material: ShaderMaterial
var _beam_tween: Tween
var _centre := Vector2.ZERO


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
	_centre = _provinces.tray.get_center()
	_model.position = Vector3(-_centre.x, 0.0, -_centre.y)
	_pivot.add_child(_model)
	_build_beam()

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
	_place_beam(focus_id)


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

	_beam_material = ShaderMaterial.new()
	_beam_material.shader = load(BEAM_SHADER_PATH)
	_beam_material.set_shader_parameter("beam_color", UiPalette.HUD_GOLD)
	(_beam.get_node("Beam") as MeshInstance3D).material_override = _beam_material


## A tapered open cylinder at the picked province's label point. The node sits on
## the board, so scaling its Y grows the shaft out of the ground.
func _build_beam() -> void:
	_beam = Node3D.new()
	_beam.name = "FocusBeam"
	_beam.visible = false
	_pivot.add_child(_beam)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.40
	cone.height = BEAM_HEIGHT
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var mesh := MeshInstance3D.new()
	mesh.name = "Beam"
	mesh.mesh = cone
	mesh.position.y = BEAM_HEIGHT * 0.5
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.add_child(mesh)


func _place_beam(index: int) -> void:
	if _beam == null:
		return
	if index < 0 or index >= _provinces.labels.size():
		_beam.visible = false
		return
	var spot := _provinces.labels[index] - _centre
	_beam.position = Vector3(spot.x, 0.0, spot.y)
	_beam.visible = true
	if _beam_tween != null:
		_beam_tween.kill()
	_beam.scale = Vector3(1.0, 0.45, 1.0)
	_beam_tween = create_tween()
	_beam_tween.tween_property(_beam, "scale:y", 1.0, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
