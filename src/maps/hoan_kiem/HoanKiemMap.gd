extends MapDefinition

# Hoan Kiem Lake map (Ha Noi) on a floating diorama island
# (maps/hoan_kiem/island_base.glb from tools/asset_generator/generators/maps/hoan_kiem/).
# The lake runs long north-south like the real one. The defend target is Turtle Tower
# (defend_model in HoanKiemMap.tscn), standing on the turtle-shaped island in the
# middle of the lake; Ngoc Son temple on Jade Island and The Huc bridge stand where
# data/maps/hoan_kiem/zones/landmarks.json says (placed here at load, through
# HoanKiemZones), and LakesideLandmarks bakes Pen Tower on Doc Ton hill, the gates, the
# Ly Thai To statue and the Post Office at the same spots. StreetProps holds the Old Quarter
# tube houses, cafes, lamps, the locals on the promenade and the GPU-driven traffic
# (src/environment/StreetTraffic.gd). OutskirtsBand is the rest of central Ha Noi as a
# faded silhouette ring past the island edge (outskirts_band.glb, laid out from
# zones/outskirts.json), shaded and sky-synced by src/environment/SilhouetteBand.gd.
# The map has no spawn gates yet: its levels are peaceful until water and flying
# enemies exist. Owns, in _ready() order:
# trimesh collision for walkable meshes, the murky jade pond-water material (no
# caustics, shaded by the banks of zones/lake.json, arena.json and islets.json), landmark
# placement, the outskirts band material, decorative shadows off, and its day/night
# reaction (forest, grass, water and outskirts day_blend) to EventBus.day_blend_changed. The map defaults to a hazy Hanoi
# morning (default_time_of_day in HoanKiemMap.tscn) with no hot-air balloons
# (sky_balloons); the shared sky, lights and pearl glow stay in DayNightCycle.
# CONTRACT(mesh-names): the mesh names and substrings below match addMerged() in
# hoan_kiem_island.mjs and the landmark node names in HoanKiemMap.tscn;
# contract_problems() fails --round-test when one breaks.

const SilhouetteBand := preload("res://src/environment/SilhouetteBand.gd")

const POND_MATERIAL_PATH := "res://assets/shaders/PondWater.tres"
const LAWN_MESH_NAME := "CentralLawn"
const WATER_MESH_NAME := "LakeWater"
# CONTRACT(mesh-names): OutskirtsBand node in HoanKiemMap.tscn and the mesh in
# outskirts_band.glb (tools/asset_generator/generators/maps/hoan_kiem/outskirts_band.mjs).
const OUTSKIRTS_ROOT := "OutskirtsBand"
const OUTSKIRTS_MESH_NAME := "OutskirtsBand"
# Warm grey-taupe daytime silhouettes for the hazy Hanoi morning (the shader's default
# is Landmark 81's cool blue). sRGB, like the shader's source_color uniforms.
const OUTSKIRTS_TONES := {"tone_day": Color(0.55, 0.52, 0.49)}
# Only walkable ground gets trimesh collision: water, the rock underbelly, the cliff
# soil and the reeds/benches details mesh are skipped.
const COLLISION_SKIP := ["water", "underbelly", "soil", "reeds"]
# zones/landmarks.json key -> node in HoanKiemMap.tscn.
const LANDMARK_NODES := {
	"ngoc_son_temple": "NgocSonTemple", "huc_bridge": "HucBridge",
}
# Decorative props that never cast shadows (invariant 4). LakesideLandmarks spans
# 171 m in one bake: a giant shadow caster outside the 65 m shadow range.
const DECORATIVE_ROOTS := ["StreetProps", "LakesideLandmarks"]
# Hoan Kiem's murky olive-jade water, pushed onto this map's own copy of the pond
# material (the shared .tres also carries Landmark 81's fountain rings). sRGB, like
# the shader's source_color uniforms.
const WATER_DEEP := Color(0.1, 0.22, 0.14)
const WATER_SHALLOW := Color(0.3, 0.44, 0.25)
# Opaque lake: weaker sky sheen than the clear pools, and no caustic glints.
const WATER_REFLECT_BOOST := 0.12
# Array sizes of PondWater.gdshader's shore_lake / shore_islands uniforms.
const SHORE_LAKE_SLOTS := 4
const SHORE_ISLAND_SLOTS := 8

@onready var _island: Node3D = $IslandBase
@onready var _forest: Node = $ForestMultiMesh
@onready var _grass: Node = $GrassMultiMesh

var _water_mat: ShaderMaterial = null
var _outskirts: SilhouetteBand
var _placed: PackedStringArray = PackedStringArray()


func _ready() -> void:
	add_walkable_collisions(_island, PackedStringArray(COLLISION_SKIP))
	# The island is floor: it receives shadows, never casts them.
	set_shadows_off(_island)
	_setup_water()
	_place_landmarks()
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
	if _water_mat:
		_water_mat.set_shader_parameter("day_blend", t)
	_outskirts.apply(t)


func _setup_water() -> void:
	var mesh := _island.find_child(WATER_MESH_NAME, true, false) as MeshInstance3D
	var shared := load(POND_MATERIAL_PATH) as ShaderMaterial
	if mesh == null or shared == null:
		push_warning("HoanKiemMap: water mesh '%s' or %s missing; the pools keep the flat fallback colour." % [WATER_MESH_NAME, POND_MATERIAL_PATH])
		return
	_water_mat = shared.duplicate() as ShaderMaterial
	_water_mat.set_shader_parameter("deep_color", WATER_DEEP)
	_water_mat.set_shader_parameter("shallow_color", WATER_SHALLOW)
	_water_mat.set_shader_parameter("fountain_count", 0)
	_water_mat.set_shader_parameter("reflect_boost", WATER_REFLECT_BOOST)
	_water_mat.set_shader_parameter("caustic_strength", 0.0)
	_set_shore(_water_mat)
	mesh.material_override = _water_mat


# Shore fields for the shader's bank shading: the lake's lobes and the islands' lobes
# (the turtle island's, then each islet as one ellipse), all from the zone files.
func _set_shore(mat: ShaderMaterial) -> void:
	var zones := HoanKiemZones.data()
	var lake: Dictionary = zones.get("lake", {})
	var lake_lobes := HoanKiemZones.lobes_of(lake.get("lobes", []))
	if lake_lobes.is_empty():
		return
	var turtle: Dictionary = (zones.get("arena", {}) as Dictionary).get("island", {})
	var islands := HoanKiemZones.lobes_of(turtle.get("lobes", []))
	for islet in (zones.get("islets", {}) as Dictionary).values():
		if islet is Dictionary and (islet as Dictionary).has("center"):
			islands.append(Vector4(float(islet["center"][0]), float(islet["center"][1]), float(islet["r"][0]), float(islet["r"][1])))
	# The shader arrays hold 4 lake lobes and 8 island lobes; the unused tails stay zero.
	var lake_count := mini(lake_lobes.size(), SHORE_LAKE_SLOTS)
	var island_count := mini(islands.size(), SHORE_ISLAND_SLOTS)
	lake_lobes.resize(SHORE_LAKE_SLOTS)
	islands.resize(SHORE_ISLAND_SLOTS)
	mat.set_shader_parameter("shore_lake", lake_lobes)
	mat.set_shader_parameter("shore_lake_count", lake_count)
	mat.set_shader_parameter("shore_lake_blend", float(lake.get("blend", 0.0)))
	mat.set_shader_parameter("shore_islands", islands)
	mat.set_shader_parameter("shore_island_count", island_count)
	mat.set_shader_parameter("shore_island_blend", float(turtle.get("blend", 0.0)))


func _place_landmarks() -> void:
	for key: String in LANDMARK_NODES:
		var node := get_node_or_null(str(LANDMARK_NODES[key])) as Node3D
		var xf := HoanKiemZones.landmark_transform(key)
		if node == null or xf.is_empty():
			continue
		node.position = xf["pos"]
		node.rotation = Vector3(0.0, deg_to_rad(float(xf["yaw"])), 0.0)
		_placed.append(key)


# --round-test guard for CONTRACT(mesh-names): each of these lookups fails silently
# at runtime, so the test fails loudly instead.
func contract_problems() -> PackedStringArray:
	# super() is the base's spawn-gate checks (CONTRACT(add-wave)).
	var problems := super.contract_problems()
	var lawn := _island.find_child(LAWN_MESH_NAME, true, false)
	if lawn == null or lawn.find_children("*", "StaticBody3D", false, false).is_empty():
		problems.append("lawn mesh '%s' missing or has no collision (placement raycasts will miss)" % LAWN_MESH_NAME)
	if defend_model == null:
		problems.append("defend_model (Turtle Tower) is not set in HoanKiemMap.tscn; the pearl stands in its place")
	if _water_mat == null:
		problems.append("water mesh '%s' missing; the pools keep the flat fallback colour" % WATER_MESH_NAME)
	problems.append_array(_outskirts.contract_problems(OUTSKIRTS_ROOT, OUTSKIRTS_MESH_NAME))
	for key: String in LANDMARK_NODES:
		if not _placed.has(key):
			problems.append("landmark '%s' not placed (node '%s' or zones/landmarks.json entry missing)" % [key, LANDMARK_NODES[key]])
	# The lawn grid must lie on the turtle island, or placement raycasts miss its corners.
	for zone_name in lawn_zones:
		var r: Rect2 = lawn_zones[zone_name]
		for corner in [r.position, r.position + Vector2(r.size.x, 0.0), r.end, r.position + Vector2(0.0, r.size.y)]:
			if HoanKiemZones.turtle_sd(corner.x, corner.y) > -0.5:
				problems.append("lawn zone '%s' corner %s is off the turtle island (zones/arena.json island)" % [zone_name, corner])
	for zone in ["arena", "lake", "islets", "landmarks", "streets", "lamps", "shophouses", "outskirts"]:
		if not HoanKiemZones.data().has(zone):
			problems.append("zones file data/maps/hoan_kiem/zones/%s.json missing" % zone)
	return problems
