extends MapDefinition

# Hoi An Ancient Town map (Da Nang) on a floating diorama island
# (maps/hoi_an/island_base.glb from tools/asset_generator/generators/maps/hoi_an/).
# The Thu Bon river crosses the island east-west: the old town on the north bank, An Hoi
# islet on the south. The lawn is the lantern garden on the riverfront square, and the
# defend target is the Mother Lantern shrine at its centre (defend_model in
# HoiAnMap.tscn). OldTownLandmarks bakes the Japanese Covered Bridge, the Fujian
# Assembly Hall and Quan Cong temple gates, the central market, An Hoi bridge, the night
# market and the lantern strings over the streets; StreetProps holds the shophouse rows
# (zones/shophouses.json), the pavement life (food stalls, shops' goods, crowds: zones/streets.json
# clutter) and the pedestrians walking the streets (zones/walkers.json, src/environment/StreetWalkers.gd).
# DriftBoats, DriftRiverLanterns and DriftSkyLanterns are what
# moves: lantern boats travelling the river, floating lanterns of several shapes
# drifting downstream and sky lanterns rising from all over the town (zones/drift.json),
# all moved on the GPU by src/environment/LanternDrift.gd. OutskirtsBand is
# the country round Hoi An as a faded silhouette ring past the island edge
# (outskirts_band.glb, laid out from zones/outskirts.json), shaded and sky-synced by
# src/environment/SilhouetteBand.gd. The map defaults to the lantern night
# (default_time_of_day). Its levels are peaceful until its enemies exist.
# Owns, in _ready() order: trimesh collision for walkable meshes, the river material
# (its own copy of SaigonRiverWater: Thu Bon palette, the banks of zones/river.json, and
# night reflections of the riverfront lanterns, the night-market stalls and the moon),
# the lantern shader on every LanternGlow mesh, the lantern light pools that light the
# dark night (zones/streets.json lantern_lights, night only), the outskirts band material, decorative
# shadows off, and its day/night reaction (forest, grass, river, lanterns and outskirts
# day_blend, and the drifting boats and lanterns) to EventBus.day_blend_changed. The shared sky, lights and the defend light
# (the pearl's warm glow, now inside the Mother Lantern) stay in DayNightCycle.
# CONTRACT(mesh-names): the mesh names and substrings below match addMerged() in
# hoi_an_island.mjs, the LanternGlow material of lantern_kit.mjs and the node names in
# HoiAnMap.tscn; contract_problems() fails --round-test when one breaks.

const SilhouetteBand := preload("res://src/environment/SilhouetteBand.gd")

const RIVER_MATERIAL_PATH := "res://assets/shaders/SaigonRiverWater.tres"
const LANTERN_SHADER := preload("res://assets/shaders/LanternGlow.gdshader")
const LAWN_MESH_NAME := "CentralLawn"
const WATER_MESH_NAME := "RiverWater"
# Every mesh (or batched MultiMesh) whose name holds this gets the lantern shader:
# lantern_kit.mjs names the material, mergeByMaterial names the mesh after it.
const LANTERN_MESH_TAG := "LanternGlow"
# CONTRACT(mesh-names): OutskirtsBand node in HoiAnMap.tscn and the mesh in
# outskirts_band.glb (tools/asset_generator/generators/maps/hoi_an/outskirts_band.mjs).
const OUTSKIRTS_ROOT := "OutskirtsBand"
const OUTSKIRTS_MESH_NAME := "OutskirtsBand"
# Violet night and warm-taupe day silhouettes. sRGB, like the shader's uniforms.
const OUTSKIRTS_TONES := {"tone_night": Color(0.02, 0.018, 0.04), "tone_day": Color(0.55, 0.52, 0.47)}
# Only walkable ground gets trimesh collision: the water, the soil and rock and the
# details mesh (steps, benches, pots, garden beds) are skipped.
const COLLISION_SKIP := ["water", "underbelly", "soil", "details"]
# Decorative props that never cast shadows (invariant 4). OldTownLandmarks spans the
# whole island in one bake: a giant shadow caster outside the shadow range.
const DECORATIVE_ROOTS := ["StreetProps", "OldTownLandmarks"]
# The moving boats and lanterns (LanternDrift batches in HoiAnMap.tscn).
const DRIFT_NODES := ["DriftBoats", "DriftRiverLanterns", "DriftSkyLanterns"]
# Thu Bon water: murky green-brown by day, near-black teal by night, warm lantern glow
# along both banks. sRGB, like the shader's source_color uniforms.
const RIVER_TONES := {
	"deep_day": Color(0.16, 0.24, 0.17), "mid_day": Color(0.24, 0.32, 0.22), "shallow_day": Color(0.34, 0.4, 0.27),
	"deep_night": Color(0.02, 0.04, 0.05), "mid_night": Color(0.035, 0.06, 0.07), "shallow_night": Color(0.07, 0.08, 0.08),
	"sky_tint_night": Color(0.2, 0.15, 0.3), "city_glow_color": Color(1.0, 0.58, 0.28),
}
const RIVER_WAVES := 0.3
# Rougher than the Saigon river: the warm fill and the moon spread into a soft sheen
# instead of sharp stripes on every wave crest.
const RIVER_ROUGHNESS := 0.34
const RIVER_CITY_GLOW := 0.045
const RIVER_CITY_GLOW_FALLOFF := 2.5
# Must equal reflector_pos[16] / foam_boxes[16] in SaigonRiverWater.gdshader.
const MAX_REFLECTORS := 16
const MAX_FOAM_BOXES := 16
# Reflections: riverfront lantern posts nearest the square, then night-market stalls.
const REFLECT_POSTS := 8
const REFLECT_STALLS := 6
# Past both island edges, so the bank legs never end inside the visible river.
const BANK_REACH := 400.0

@onready var _island: Node3D = $IslandBase
@onready var _forest: Node = $ForestMultiMesh
@onready var _grass: Node = $GrassMultiMesh

var _river_mat: ShaderMaterial = null
var _lantern_mat: ShaderMaterial = null
var _lantern_meshes: int = 0
var _glow_lights: Array[OmniLight3D] = []
var _moon_found: bool = false
var _outskirts: SilhouetteBand


func _ready() -> void:
	add_walkable_collisions(_island, PackedStringArray(COLLISION_SKIP))
	# The island is floor: it receives shadows, never casts them.
	set_shadows_off(_island)
	_setup_river()
	_setup_lanterns()
	_setup_glow_lights()
	_outskirts = SilhouetteBand.new(self, OUTSKIRTS_ROOT, OUTSKIRTS_MESH_NAME, OUTSKIRTS_TONES)
	for root_name in DECORATIVE_ROOTS:
		var node := get_node_or_null(root_name)
		if node:
			set_shadows_off(node)
	EventBus.day_blend_changed.connect(_apply_day_blend)
	# Settled phase at load; DayNightCycle only signals while a transition runs.
	_apply_day_blend(GameManager.daylight())


# `t` is the eased 0 (night) .. 1 (day) blend from DayNightCycle.
func _apply_day_blend(t: float) -> void:
	if _forest and _forest.has_method(&"set_day_blend"):
		_forest.set_day_blend(t)
	if _grass and _grass.has_method(&"set_day_blend"):
		_grass.set_day_blend(t)
	if _river_mat:
		_river_mat.set_shader_parameter("day_blend", t)
	if _lantern_mat:
		_lantern_mat.set_shader_parameter("day_blend", t)
	# The lantern light pools only exist at night; hidden, they cost nothing.
	for light in _glow_lights:
		light.visible = t < 0.5
	_outskirts.apply(t)
	for node_name in DRIFT_NODES:
		var drift := get_node_or_null(node_name)
		if drift and drift.has_method(&"set_day_blend"):
			drift.set_day_blend(t)


# The river gets this map's own copy of the Saigon river material (the shared .tres is
# Landmark 81's): Thu Bon tones, no marina foam, the two banks as one bank polyline,
# and the night reflections.
func _setup_river() -> void:
	var mesh := _island.find_child(WATER_MESH_NAME, true, false) as MeshInstance3D
	var shared := load(RIVER_MATERIAL_PATH) as ShaderMaterial
	if mesh == null or shared == null:
		push_warning("HoiAnMap: water mesh '%s' or %s missing; the river keeps the flat fallback colour." % [WATER_MESH_NAME, RIVER_MATERIAL_PATH])
		return
	_river_mat = shared.duplicate() as ShaderMaterial
	for key: String in RIVER_TONES:
		_river_mat.set_shader_parameter(key, RIVER_TONES[key])
	_river_mat.set_shader_parameter("city_glow_intensity", RIVER_CITY_GLOW)
	_river_mat.set_shader_parameter("city_glow_falloff", RIVER_CITY_GLOW_FALLOFF)
	_river_mat.set_shader_parameter("flow_dir", Vector2(1.0, 0.05)) # downstream, to the sea
	_river_mat.set_shader_parameter("flow_speed", 0.25)
	# A slow, sheltered river: gentle waves, so the warm fill light does not band them.
	_river_mat.set_shader_parameter("wave_strength", RIVER_WAVES)
	_river_mat.set_shader_parameter("roughness_near", RIVER_ROUGHNESS)
	_river_mat.set_shader_parameter("roughness_far", RIVER_ROUGHNESS)
	# No marina here: both foam fans far away, no foam boxes.
	_river_mat.set_shader_parameter("marina_fan", Vector3(0.0, 0.0, -1000.0))
	_river_mat.set_shader_parameter("marina_club_fan", Vector3(0.0, 0.0, -1000.0))
	var no_boxes: Array = []
	no_boxes.resize(MAX_FOAM_BOXES)
	no_boxes.fill(Vector4.ZERO)
	_river_mat.set_shader_parameter("foam_boxes", no_boxes)
	_river_mat.set_shader_parameter("foam_box_count", 0)
	_river_mat.set_shader_parameter("foam_bounds", Vector4.ZERO)
	# Bank polyline (8 points, the shader's limit), positive on the water side: the north
	# bank east -> west, round the creek (up its east wall, across its head, down its
	# west wall), on west, down the far west, then the south bank west -> east
	# (bank_sdf takes the nearest leg's sign).
	var rv: Dictionary = HoiAnZones.data().get("river", {})
	var nb := float(rv.get("north_bank_z", 0.0))
	var sb := float(rv.get("south_bank_z", 0.0))
	var creek: Dictionary = rv.get("creek", {})
	var cx0 := float(creek["x"][0])
	var cx1 := float(creek["x"][1])
	var cz0 := float(creek["z"][0])
	var bank := PackedVector2Array([
		Vector2(BANK_REACH, nb), Vector2(cx1, nb), Vector2(cx1, cz0), Vector2(cx0, cz0),
		Vector2(cx0, nb), Vector2(-BANK_REACH, nb), Vector2(-BANK_REACH, sb), Vector2(BANK_REACH, sb),
	])
	_river_mat.set_shader_parameter("bank_pts", bank)
	_river_mat.set_shader_parameter("bank_count", bank.size())
	mesh.material_override = _river_mat
	_setup_river_reflections()


# Night reflection points (zero per-frame cost): reflector_pos = (x, y, z, intensity),
# reflector_col = (r, g, b, vertical stretch); see SaigonRiverWater.gdshader.
func _setup_river_reflections() -> void:
	var pos: Array = []
	var col: Array = []
	var posts := Array(HoiAnZones.lantern_post_heads())
	posts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return absf(a.x) < absf(b.x))
	for p: Vector3 in posts.slice(0, REFLECT_POSTS):
		pos.append(Vector4(p.x, p.y, p.z, 1.4))
		col.append(Vector4(1.0, 0.55, 0.3, 0.35))
	var stalls := Array(HoiAnZones.night_market_stalls())
	stalls.sort_custom(func(a: Vector3, b: Vector3) -> bool: return absf(a.x) < absf(b.x))
	for p: Vector3 in stalls.slice(0, REFLECT_STALLS):
		pos.append(Vector4(p.x, p.y, p.z, 1.6))
		col.append(Vector4(1.0, 0.45, 0.32, 0.4))
	var sky := get_tree().get_first_node_in_group(&"NightSky")
	if sky and sky.has_method(&"moon_global_position"):
		var mp: Vector3 = sky.moon_global_position()
		pos.append(Vector4(mp.x, mp.y, mp.z, 1.2))
		col.append(Vector4(0.8, 0.85, 1.0, 0.6))
		_moon_found = true
	var used: int = mini(pos.size(), MAX_REFLECTORS)
	pos.resize(MAX_REFLECTORS)
	col.resize(MAX_REFLECTORS)
	for i in range(used, MAX_REFLECTORS):
		pos[i] = Vector4.ZERO
		col[i] = Vector4.ZERO
	_river_mat.set_shader_parameter("reflector_pos", pos)
	_river_mat.set_shader_parameter("reflector_col", col)
	_river_mat.set_shader_parameter("reflector_count", used)


# One shared lantern material for every LanternGlow mesh in the map (the landmarks'
# and each shophouse MultiMesh's): one day_blend write re-tones them all.
func _setup_lanterns() -> void:
	_lantern_mat = ShaderMaterial.new()
	_lantern_mat.shader = LANTERN_SHADER
	_lantern_meshes = _apply_lantern_material(self)


func _apply_lantern_material(node: Node) -> int:
	var count := 0
	if node is GeometryInstance3D and LANTERN_MESH_TAG in String(node.name):
		(node as GeometryInstance3D).material_override = _lantern_mat
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		count += 1
	for child in node.get_children():
		count += _apply_lantern_material(child)
	return count


# The lantern light: warm unshadowed omni pools under the street lanterns, the
# riverfront posts, the night-market stalls, the square's poles and the temple gates,
# and the Mother Lantern lighting the lawn (HoiAnZones.lantern_lights() from
# zones/streets.json). The night itself is dark (assets/lighting/lantern_night.tres),
# so these carry the scene; decorative lights never cast shadows (invariant 4), and
# by day they are hidden, which costs nothing.
func _setup_glow_lights() -> void:
	for l in HoiAnZones.lantern_lights():
		var light := OmniLight3D.new()
		light.name = "LanternLight%d" % _glow_lights.size()
		light.position = l["pos"]
		light.light_color = l["color"]
		light.light_energy = l["energy"]
		light.omni_range = l["range"]
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.light_specular = 0.3
		add_child(light)
		_glow_lights.append(light)


# --round-test guard for CONTRACT(mesh-names): each of these lookups fails silently
# at runtime, so the test fails loudly instead.
func contract_problems() -> PackedStringArray:
	# super() is the base's spawn-gate checks (CONTRACT(add-wave)).
	var problems := super.contract_problems()
	var lawn := _island.find_child(LAWN_MESH_NAME, true, false)
	if lawn == null or lawn.find_children("*", "StaticBody3D", false, false).is_empty():
		problems.append("lawn mesh '%s' missing or has no collision (placement raycasts will miss)" % LAWN_MESH_NAME)
	if defend_model == null:
		problems.append("defend_model (Mother Lantern shrine) is not set in HoiAnMap.tscn; the pearl stands in its place")
	if _river_mat == null:
		problems.append("water mesh '%s' missing; the river keeps the flat fallback colour" % WATER_MESH_NAME)
	elif int(_river_mat.get_shader_parameter("reflector_count")) < REFLECT_POSTS:
		problems.append("river reflectors missing (zones/river.json lantern_posts or landmarks.json night_market)")
	if not _moon_found:
		problems.append("river moon reflection missing (NightSky group / moon_global_position)")
	# The landmarks and both shophouse variants each carry one LanternGlow mesh.
	if _lantern_meshes < 3:
		problems.append("only %d '%s' meshes got the lantern shader (expected the landmarks and both shophouse variants)" % [_lantern_meshes, LANTERN_MESH_TAG])
	problems.append_array(_outskirts.contract_problems(OUTSKIRTS_ROOT, OUTSKIRTS_MESH_NAME))
	for node_name in DRIFT_NODES:
		var drift := get_node_or_null(node_name) as MultiMeshInstance3D
		if drift == null or drift.multimesh == null or drift.multimesh.instance_count == 0:
			problems.append("'%s' has nothing to move (node, its .glb or zones/drift.json missing)" % node_name)
	# The lawn grid must lie on the turf, or placement raycasts miss its corners.
	var turf: Array = (HoiAnZones.data().get("arena", {}) as Dictionary).get("turf_rect", [])
	for zone_name in lawn_zones:
		var r: Rect2 = lawn_zones[zone_name]
		if turf.size() != 4 or not HoiAnZones._rect(turf).encloses(r):
			problems.append("lawn zone '%s' %s is not on the turf (zones/arena.json turf_rect)" % [zone_name, r])
	if _glow_lights.size() < 20:
		problems.append("only %d lantern lights (zones/streets.json lantern_lights); the night stays unlit" % _glow_lights.size())
	var walkers := get_node_or_null("StreetProps/Walkers") as MultiMeshInstance3D
	if walkers == null or walkers.multimesh == null or walkers.multimesh.instance_count == 0:
		problems.append("no pedestrians (StreetProps/Walkers, hoi_an_walkers.glb or zones/walkers.json missing)")
	for key in ["food_stall", "shop_spill", "crowd"]:
		if HoiAnZones.lots(key).is_empty():
			problems.append("no '%s' lots (zones/streets.json clutter)" % key)
	for zone in ["arena", "island", "river", "streets", "shophouses", "landmarks", "outskirts", "drift", "walkers"]:
		if not HoiAnZones.data().has(zone):
			problems.append("zones file data/maps/hoi_an/zones/%s.json missing" % zone)
	return problems
