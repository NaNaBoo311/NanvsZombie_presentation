extends MapDefinition

# Landmark 81 map — the Landmark 81 riverside park on the floating diorama island
# (maps/landmark_81/island_diorama_base.glb from maps/landmark_81/floating_diorama_island.mjs + Landmark81Zones props).
# Owns everything specific to this island, in _ready() order: trimesh collision for
# walkable meshes and decorative prop shadows here; the water (river / pond / spray
# materials, the river's night reflectors, yacht bobbing) in Landmark81Water.gd; the
# day/night grade of its own nodes (ground lift, lawn + rings, lanterns, forest,
# grass, water day_blend, skyline emission) in Landmark81DayGrade.gd, driven by
# EventBus.day_blend_changed. The shared sky, lights and pearl glow stay in DayNightCycle.
# CONTRACT(mesh-names): the node names and mesh-name substrings below, and those in
# the two helpers, are looked up at runtime; contract_problems() fails --round-test
# when one breaks.

const Water := preload("res://src/maps/landmark_81/Landmark81Water.gd")
const DayGrade := preload("res://src/maps/landmark_81/Landmark81DayGrade.gd")
const SilhouetteBand := preload("res://src/environment/SilhouetteBand.gd")

# Distant city silhouette band (outskirts_band.glb from outskirts_band.mjs), shaded and
# sky-synced by src/environment/SilhouetteBand.gd.
# CONTRACT(mesh-names): OutskirtsBand node in Landmark81Map.tscn and mesh in outskirts_band.glb.
const OUTSKIRTS_ROOT := "OutskirtsBand"
const OUTSKIRTS_MESH_NAME := "OutskirtsBand"

# Tower window / LED emission roots (graded in Landmark81DayGrade; the tower tip is
# also a river reflector).
# CONTRACT(mesh-names): node names in Landmark81Map.tscn; --round-test asserts both sets.
const SKYLINE_ROOT := "SkylineTowers"
const LANDMARK_TOWER := "SkylineTowers/Landmark81Tower"

# Roots whose OmniLight3D lanterns are graded by day and reflected in the river.
const LANTERN_ROOTS := ["Lanterns", "DandelionPavilions"]

# Decorative props that never cast shadows (invariant 4).
const DECORATIVE_ROOTS := [
	"Lanterns", "SkylineTowers", "VinhomesVillas", "JapaneseGarden", "MarinaClubFleet",
	"LuxuryYachts", "MarinaYachtPier", "MossyStone1", "MossyStone2", "MossyStone3",
	"DandelionPavilions",
	"StreetLife", "OutskirtsBand",
]

# Only walkable ground/lawn/promenade surfaces get trimesh collision. Substrings match
# island mesh names (CONTRACT(mesh-names)): decorative details (railings [1776 tris],
# fountain sprays, ripples, mowing stripes, water, cliff underbelly, soil) are skipped.
const COLLISION_SKIP := ["railing", "spray", "ripple", "water", "stripe", "underbelly", "soil"]

@onready var _island: Node3D = $FloatingIslandBase
@onready var _forest: Node = $ForestMultiMesh
@onready var _grass: Node = $GrassMultiMesh

var _water: Water
var _grade: DayGrade
var _outskirts: SilhouetteBand


func _ready() -> void:
	_water = Water.new(self, _island)
	_grade = DayGrade.new(_forest, _grass, _water)
	_grade.collect_ground_materials(_island)
	add_walkable_collisions(_island, PackedStringArray(COLLISION_SKIP))
	_water.setup_river_material()
	_water.setup_pond_material()
	_outskirts = SilhouetteBand.new(self, OUTSKIRTS_ROOT, OUTSKIRTS_MESH_NAME)
	for root_name in LANTERN_ROOTS:
		var root := get_node_or_null(root_name)
		if root:
			_grade.collect_lantern_lights(root)
	# After the lantern lights are collected (and the bank polyline is filled
	# above): builds the river's night-reflection point list once.
	_water.setup_river_reflections(_grade.lantern_lights, _grade.lantern_energies,
		get_node_or_null(LANDMARK_TOWER) as Node3D, LANDMARK_TOWER)
	_water.collect_yachts()
	for root_name in DECORATIVE_ROOTS:
		var node := get_node_or_null(root_name)
		if node:
			set_shadows_off(node)
	_grade.collect_emissive_materials(get_node_or_null(LANDMARK_TOWER), get_node_or_null(SKYLINE_ROOT))
	EventBus.day_blend_changed.connect(_apply_day_blend)
	# Settled phase at load; DayNightCycle only signals while a transition runs.
	_apply_day_blend(GameManager.daylight())


func _process(delta: float) -> void:
	_water.process(delta)


# `t` is the eased 0 (night) .. 1 (day) blend from DayNightCycle.
func _apply_day_blend(t: float) -> void:
	_grade.apply(t)
	_outskirts.apply(t)


# --round-test guard for CONTRACT(mesh-names): each of these lookups fails silently
# at runtime, so the test fails loudly instead when a generator rename breaks one.
func contract_problems() -> PackedStringArray:
	# super() is the base's nav-grid checks (CONTRACT(add-wave)); a stale grid
	# fails here instead of silently clipping.
	var problems := super.contract_problems()
	problems.append_array(_water.contract_problems())
	var lawn := _island.find_child("GreatOvalLawn", true, false)
	if lawn == null or lawn.find_children("*", "StaticBody3D", false, false).is_empty():
		problems.append("lawn mesh 'GreatOvalLawn' missing or has no collision (placement raycasts will miss)")
	if not _grade.lawn_found:
		problems.append("day/night grade did not match the lawn color 0x2e7d32")
	if not _grade.rings_found:
		problems.append("day/night grade did not match the lawn ring color 0x43a047")
	if _grade.landmark_materials.is_empty() or _grade.window_materials.is_empty():
		problems.append("skyline emission grade found no emissive materials under '%s' / '%s'" % [SKYLINE_ROOT, LANDMARK_TOWER])
	# Outskirts city silhouette band (CONTRACT(mesh-names) row 11)
	problems.append_array(_outskirts.contract_problems(OUTSKIRTS_ROOT, OUTSKIRTS_MESH_NAME))
	# North-city lots file (Phase 2 zone J): the ground and the tower props must
	# come from the same generate, so a stale file fails loudly instead of
	# overlapping towers and streets with no error.
	if not Landmark81Zones.city_lots_ok():
		problems.append("city lots file stale or missing (north_city changed since generate)")
	return problems
