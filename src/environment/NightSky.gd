@tool
extends Node3D

# Procedural Sky Populator for the 160m x 160m Cozy Diorama World
# Scatters glowing 4-point stars and a low-poly cloud band around the horizon,
# and places a single crescent moon, using MultiMeshInstance3D batching
# (matches ForestMultiMesh.gd conventions) to keep draw calls minimal.
#
# Also builds the DAYLIGHT cloud deck (a denser two-tier ring of chunky white
# cumulus banks, 1 extra draw call, unshaded so it never touches the lighting
# pass). DayNightCycle.gd cross-fades the two sets via set_day_blend(): whichever
# set is fully faded out is hidden outright, so the off-duty sky costs nothing.
# The hot-air balloons ride with the daylight set under one parent that follows the
# loaded map's MapDefinition.sky_balloons (EventBus.map_loaded).

@export var sky_seed: int = 4242:
	set(val):
		sky_seed = val
		if Engine.is_editor_hint() or is_inside_tree():
			_generate_sky()

const STAR_SCENE_PATH := "res://assets/models/sky/star_glow.glb"
const MOON_SCENE_PATH := "res://assets/models/sky/moon_crescent.glb"
const DAY_CLOUD_SCENE_PATH := "res://assets/models/sky/cloud_cluster_day.glb"
const BALLOON_SCENE_PATH := "res://assets/models/sky/hot_air_balloon.glb"

const STAR_COUNT := 130
const STAR_RADIUS := 190.0
const STAR_MIN_ELEVATION_DEG := 16.0
const STAR_MAX_ELEVATION_DEG := 82.0

const MOON_RADIUS := 100.0
const MOON_AZIMUTH_DEG := -45.0 # Matches the default camera's yaw so the moon reads in-frame
const MOON_ELEVATION_DEG := 26.0
const MOON_SCALE := 12.0

# Daylight cloud deck: a dense bank riding just above the skyline plus a sparse high
# tier, so the sky reads as a layered sea of low-poly cumulus rather than a flat ring.
# Heights are tuned against the diorama camera (pitch -85..-8 deg, arm 8..90m, so the
# eye sits roughly 5..50m up): anything lower than ~28m disappears behind the treeline.
const DAY_CLOUD_LOW_COUNT := 32
const DAY_CLOUD_LOW_RADIUS := 150.0
const DAY_CLOUD_LOW_MIN_HEIGHT := 38.0
const DAY_CLOUD_LOW_MAX_HEIGHT := 68.0
const DAY_CLOUD_LOW_MIN_SCALE := 5.0
const DAY_CLOUD_LOW_MAX_SCALE := 9.0

const DAY_CLOUD_HIGH_COUNT := 16
const DAY_CLOUD_HIGH_RADIUS := 192.0
const DAY_CLOUD_HIGH_MIN_HEIGHT := 72.0
const DAY_CLOUD_HIGH_MAX_HEIGHT := 118.0
const DAY_CLOUD_HIGH_MIN_SCALE := 8.0
const DAY_CLOUD_HIGH_MAX_SCALE := 13.0

# Day & night cloud albedos: daytime white, nighttime dreamy periwinkle slate.
# Unshaded, 1 draw call, zero lighting pass costs.
const DAY_CLOUD_ALBEDO := Color(1.0, 1.0, 1.0, 1.0)
const NIGHT_CLOUD_ALBEDO := Color(0.24, 0.32, 0.52, 1.0)

# Below this alpha a layer is hidden outright instead of drawn fully transparent.
const FADE_EPSILON := 0.004

# Cross-fade bookkeeping. Materials are the per-layer duplicates created below, so
# writing one alpha repaints every batched instance of that layer at zero per-instance cost.
var _night_nodes: Array[GeometryInstance3D] = []
var _night_materials: Array[StandardMaterial3D] = []
var _day_nodes: Array[GeometryInstance3D] = []
var _day_materials: Array[StandardMaterial3D] = []
var _day_blend: float = 0.0
var _balloons: Node3D = null
var _balloons_shown: bool = true

func _ready() -> void:
	add_to_group(&"NightSky")
	_generate_sky()
	if not Engine.is_editor_hint():
		EventBus.map_loaded.connect(_on_map_loaded)


func _on_map_loaded(map: MapDefinition) -> void:
	_balloons_shown = map.sky_balloons
	if _balloons:
		_balloons.visible = _balloons_shown


# World-space moon position for the Saigon River reflection (Landmark81Map reads
# this via get_tree().get_first_node_in_group(&"NightSky")).
func moon_global_position() -> Vector3:
	return global_transform * moon_offset()

func _generate_sky() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_night_nodes.clear()
	_night_materials.clear()
	_day_nodes.clear()
	_day_materials.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = sky_seed

	_build_stars(rng)
	_build_moon()
	_build_day_clouds(rng)
	_build_balloons()

	# Re-apply the live phase so a seed change mid-game never snaps back to night.
	set_day_blend(_day_blend)

# 0.0 = pure night sky, 1.0 = pure daylight sky. Called by DayNightCycle.gd only
# while a transition is running (and once on boot), never per idle frame.
func set_day_blend(blend: float) -> void:
	_day_blend = clampf(blend, 0.0, 1.0)
	_fade_layer(_night_nodes, _night_materials, 1.0 - _day_blend)
	
	# The cloud deck is identical in geometry day and night, but transitions its color
	var cloud_col: Color = NIGHT_CLOUD_ALBEDO.lerp(DAY_CLOUD_ALBEDO, _day_blend)
	for node in _day_nodes:
		if is_instance_valid(node) and not node.visible:
			node.visible = true
	for mat in _day_materials:
		if is_instance_valid(mat):
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color = cloud_col

func _fade_layer(nodes: Array[GeometryInstance3D], materials: Array[StandardMaterial3D], alpha: float) -> void:
	var showing := alpha > FADE_EPSILON
	for node in nodes:
		if is_instance_valid(node) and node.visible != showing:
			node.visible = showing
	if not showing:
		return # Hidden: no point repainting materials nothing will draw.

	# Only pay for the transparent pass DURING the blend; at either end point the layer
	# goes back to fully opaque so the settled sky renders exactly as it always has.
	var opaque := alpha >= 1.0 - FADE_EPSILON
	var mode := BaseMaterial3D.TRANSPARENCY_DISABLED if opaque else BaseMaterial3D.TRANSPARENCY_ALPHA
	for mat in materials:
		if not is_instance_valid(mat):
			continue
		if mat.transparency != mode:
			mat.transparency = mode
		if not opaque:
			var col := mat.albedo_color
			col.a = alpha
			mat.albedo_color = col

func _build_stars(rng: RandomNumberGenerator) -> void:
	var scene: PackedScene = load(STAR_SCENE_PATH)
	if not scene:
		return
	var template := scene.instantiate()
	var mesh_items := _collect_meshes(template)
	template.queue_free()
	if mesh_items.is_empty():
		return

	var transforms: Array[Transform3D] = []
	for i in range(STAR_COUNT):
		var azimuth := rng.randf_range(0.0, TAU)
		var elevation := deg_to_rad(rng.randf_range(STAR_MIN_ELEVATION_DEG, STAR_MAX_ELEVATION_DEG))
		var dist := STAR_RADIUS * rng.randf_range(0.88, 1.12)

		var pos := Vector3(
			cos(azimuth) * cos(elevation) * dist,
			sin(elevation) * dist,
			sin(azimuth) * cos(elevation) * dist
		)

		var s := rng.randf_range(0.8, 3.0)
		var t := Transform3D()
		t = t.scaled(Vector3(s, s, s))
		t.origin = pos
		transforms.append(t)

	_spawn_billboard_multimesh("Stars", mesh_items, transforms, false)

# Shared with moon_global_position() so the visible moon and the river's
# moon-road reflection can't drift apart.
static func moon_offset() -> Vector3:
	var azimuth := deg_to_rad(MOON_AZIMUTH_DEG)
	var elevation := deg_to_rad(MOON_ELEVATION_DEG)
	return Vector3(
		cos(azimuth) * cos(elevation) * MOON_RADIUS,
		sin(elevation) * MOON_RADIUS,
		sin(azimuth) * cos(elevation) * MOON_RADIUS
	)


func _build_moon() -> void:
	var scene: PackedScene = load(MOON_SCENE_PATH)
	if not scene:
		return

	var pos := moon_offset()

	var moon := scene.instantiate() as Node3D
	moon.name = "Moon"
	moon.position = pos
	moon.scale = Vector3.ONE * MOON_SCALE
	add_child(moon)
	_apply_billboard(moon)

func _build_day_clouds(rng: RandomNumberGenerator) -> void:
	var scene: PackedScene = load(DAY_CLOUD_SCENE_PATH)
	if not scene:
		return
	var template := scene.instantiate()
	var mesh_items := _collect_meshes(template)
	template.queue_free()
	if mesh_items.is_empty():
		return

	# Both tiers share ONE MultiMesh (the .glb bakes every blob into a single merged
	# mesh), so the whole daylight cloud deck stays a single draw call.
	var transforms: Array[Transform3D] = []
	_append_cloud_ring(rng, transforms, DAY_CLOUD_LOW_COUNT, DAY_CLOUD_LOW_RADIUS,
		DAY_CLOUD_LOW_MIN_HEIGHT, DAY_CLOUD_LOW_MAX_HEIGHT,
		DAY_CLOUD_LOW_MIN_SCALE, DAY_CLOUD_LOW_MAX_SCALE)
	_append_cloud_ring(rng, transforms, DAY_CLOUD_HIGH_COUNT, DAY_CLOUD_HIGH_RADIUS,
		DAY_CLOUD_HIGH_MIN_HEIGHT, DAY_CLOUD_HIGH_MAX_HEIGHT,
		DAY_CLOUD_HIGH_MIN_SCALE, DAY_CLOUD_HIGH_MAX_SCALE)

	_spawn_static_multimesh("DayClouds", mesh_items, transforms, true)

func _build_balloons() -> void:
	var scene: PackedScene = load(BALLOON_SCENE_PATH)
	if not scene:
		return
	var template := scene.instantiate()
	var mesh_items := _collect_meshes(template)
	template.queue_free()
	if mesh_items.is_empty():
		return

	const BALLOON_POSITIONS: Array[Vector3] = [
		Vector3(-38.0, 32.0, -10.0),
		Vector3(46.0, 36.0, 16.0),
		Vector3(8.0, 40.0, -40.0),
	]
	const BALLOON_SCALES: Array[float] = [4.2, 4.5, 4.8]

	var transforms: Array[Transform3D] = []
	for i in range(BALLOON_POSITIONS.size()):
		var t := Transform3D()
		var s: float = BALLOON_SCALES[i]
		t = t.scaled(Vector3(s, s, s))
		t.origin = BALLOON_POSITIONS[i]
		transforms.append(t)

	# One parent so a map can hide them all; set_day_blend() re-shows the MultiMeshes
	# themselves, and a hidden parent keeps them hidden.
	_balloons = Node3D.new()
	_balloons.name = "HotAirBalloons"
	_balloons.visible = _balloons_shown
	add_child(_balloons)
	_spawn_static_multimesh("HotAirBalloons", mesh_items, transforms, true, _balloons)

func _append_cloud_ring(rng: RandomNumberGenerator, transforms: Array[Transform3D], count: int,
		radius: float, min_height: float, max_height: float, min_scale: float, max_scale: float) -> void:
	for i in range(count):
		var azimuth := (float(i) / float(count)) * TAU + rng.randf_range(-0.14, 0.14)
		var dist := radius * rng.randf_range(0.88, 1.18)
		var y := rng.randf_range(min_height, max_height)
		var pos := Vector3(cos(azimuth) * dist, y, sin(azimuth) * dist)

		var s := rng.randf_range(min_scale, max_scale)
		var t := Transform3D()
		t = t.scaled(Vector3(s, s, s))
		t = t.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		t.origin = pos
		transforms.append(t)

func _spawn_billboard_multimesh(prefix: String, mesh_items: Array[Dictionary], transforms: Array[Transform3D], is_day_layer: bool) -> void:
	for item in mesh_items:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = prefix + "_" + item.name
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = item.mesh
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i] * item.transform)
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var src_mat: Material = item.mesh.surface_get_material(0)
		if src_mat:
			var mat: StandardMaterial3D = src_mat.duplicate()
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.billboard_keep_scale = true # Otherwise Godot billboards at a fixed on-screen size, ignoring our per-instance scale
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # Pure emissive glow never needs the lighting/SSAO/SSIL pass
			mmi.material_override = mat
			_register_fade_material(mat, is_day_layer)

		add_child(mmi)
		_register_fade_node(mmi, is_day_layer)

func _spawn_static_multimesh(prefix: String, mesh_items: Array[Dictionary], transforms: Array[Transform3D], is_day_layer: bool, parent: Node = self) -> void:
	for item in mesh_items:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = prefix + "_" + item.name
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = item.mesh
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i] * item.transform)
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# Godot's glTF importer leaves vertex_color_use_as_albedo off and albedo white,
		# so the baked vertex-color gradient is silently ignored unless we enable it here.
		var src_mat: Material = item.mesh.surface_get_material(0)
		if src_mat is StandardMaterial3D:
			var mat: StandardMaterial3D = src_mat.duplicate()
			mat.vertex_color_use_as_albedo = true
			if is_day_layer:
				# Daylight cumulus are pure baked white/sky-blue vertex colors: skipping the
				# lighting pass keeps them crisp under any sun angle and costs one less shader
				# permutation on integrated GPUs.
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mmi.material_override = mat
			_register_fade_material(mat, is_day_layer)

		parent.add_child(mmi)
		_register_fade_node(mmi, is_day_layer)

func _apply_billboard(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Distant background decoration never needs a shadow pass
		var src_mat: Material = node.get_surface_override_material(0)
		if not src_mat:
			src_mat = node.mesh.surface_get_material(0)
		if src_mat:
			var mat: StandardMaterial3D = src_mat.duplicate()
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.billboard_keep_scale = true # Otherwise Godot billboards at a fixed on-screen size, ignoring our per-instance scale
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # Pure emissive glow never needs the lighting/SSAO/SSIL pass
			node.set_surface_override_material(0, mat)
			_register_fade_material(mat, false)
		_register_fade_node(node, false)
	for child in node.get_children():
		_apply_billboard(child)

func _register_fade_node(node: GeometryInstance3D, is_day_layer: bool) -> void:
	if is_day_layer:
		_day_nodes.append(node)
	else:
		_night_nodes.append(node)

func _register_fade_material(mat: StandardMaterial3D, is_day_layer: bool) -> void:
	if is_day_layer:
		_day_materials.append(mat)
	else:
		_night_materials.append(mat)

func _collect_meshes(node: Node, parent_trans: Transform3D = Transform3D()) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cur_trans = parent_trans
	if node is Node3D:
		cur_trans = parent_trans * node.transform

	if node is MeshInstance3D and node.mesh:
		result.append({
			"name": node.name,
			"mesh": node.mesh,
			"transform": cur_trans
		})

	for child in node.get_children():
		result.append_array(_collect_meshes(child, cur_trans))

	return result
