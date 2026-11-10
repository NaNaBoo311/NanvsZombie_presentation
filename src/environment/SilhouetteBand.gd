extends RefCounted

# A map's distant city silhouette ring (the generated OutskirtsBand mesh, built with
# tools/asset_generator/generators/maps/silhouette_kit.mjs). Gives the mesh its own
# copy of assets/shaders/SilhouetteBand.gdshader, turns its shadows off (invariant 4)
# and, on apply(), pushes day_blend plus the world's ProceduralSkyMaterial gradient
# into the shader so the silhouettes fade into the sky behind them. The owning map
# calls apply() from its EventBus.day_blend_changed handler; nothing runs per frame.
# CONTRACT(mesh-names): the root node in the map's .tscn and the mesh name inside the
# .glb are passed in by the map; `material` stays null when either is missing.

const SHADER := preload("res://assets/shaders/SilhouetteBand.gdshader")

var material: ShaderMaterial = null
var sky_material_found: bool = false

var _map: Node3D
var _sky: ProceduralSkyMaterial = null


## `tones` optionally overrides the shader's silhouette colours, e.g.
## {"tone_day": Color(...), "tone_night": Color(...)} (sRGB, like the uniforms).
func _init(map: Node3D, root_name: String, mesh_name: String, tones: Dictionary = {}) -> void:
	_map = map
	var root := map.get_node_or_null(root_name)
	var mesh: MeshInstance3D = root as MeshInstance3D
	if mesh == null and root != null:
		mesh = root.find_child(mesh_name, true, false) as MeshInstance3D
	if mesh == null:
		return
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = ShaderMaterial.new()
	material.shader = SHADER
	for key: String in tones:
		material.set_shader_parameter(key, tones[key])
	mesh.material_override = material
	_resolve_sky()


# `t` is the eased 0 (night) .. 1 (day) blend from DayNightCycle.
func apply(t: float) -> void:
	if material == null:
		return
	material.set_shader_parameter("day_blend", t)
	var sky := _resolve_sky()
	if sky == null:
		return
	material.set_shader_parameter("sky_top_color", sky.sky_top_color)
	material.set_shader_parameter("sky_horizon_color", sky.sky_horizon_color)
	material.set_shader_parameter("ground_horizon_color", sky.ground_horizon_color)
	material.set_shader_parameter("ground_bottom_color", sky.ground_bottom_color)
	material.set_shader_parameter("sky_curve", sky.sky_curve)
	material.set_shader_parameter("ground_curve", sky.ground_curve)
	material.set_shader_parameter("sky_energy_multiplier", sky.sky_energy_multiplier)
	material.set_shader_parameter("ground_energy_multiplier", sky.ground_energy_multiplier)


func _resolve_sky() -> ProceduralSkyMaterial:
	if _sky:
		return _sky
	if _map and _map.get_world_3d():
		var env := _map.get_world_3d().environment
		if env and env.sky and env.sky.sky_material is ProceduralSkyMaterial:
			_sky = env.sky.sky_material as ProceduralSkyMaterial
			sky_material_found = true
	return _sky


## --round-test problems for CONTRACT(mesh-names); empty when the band is wired.
func contract_problems(root_name: String, mesh_name: String) -> PackedStringArray:
	var problems := PackedStringArray()
	if material == null:
		problems.append("outskirts mesh '%s' missing under '%s'" % [mesh_name, root_name])
	elif not sky_material_found:
		problems.append("outskirts band could not resolve ProceduralSkyMaterial from the world environment")
	return problems
