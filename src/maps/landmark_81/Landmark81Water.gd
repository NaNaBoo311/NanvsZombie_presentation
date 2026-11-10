extends RefCounted

# Landmark 81 water, owned by Landmark81Map (created in its _ready, never per frame):
# the SaigonRiverWater / PondWater / FountainSpray materials assigned as
# material_override on the named island meshes, the river's foam boxes and bank
# polyline, its one-time night-reflector list (bank-filtered lanterns, promenade
# lamp heads, tower tip, moon), the pond fountain rings, yacht bobbing, and the
# water half of the day grade (one day_blend uniform per material).
# CONTRACT(mesh-names): the mesh names and mirrored generator positions below are
# looked up at runtime; contract_problems() fails --round-test when one breaks.

# Shared water materials, assigned as material_override on the named island meshes.
const RIVER_MATERIAL_PATH := "res://assets/shaders/SaigonRiverWater.tres"
const RIVER_MESH_NAME := "SaigonRiverWater"
const POND_MATERIAL_PATH := "res://assets/shaders/PondWater.tres"
const POND_MESH_NAME := "LagoonReflectingWater"
const SPRAY_MATERIAL_PATH := "res://assets/shaders/FountainSpray.tres"
const SPRAY_MESH_NAME := "FountainSprays"
# The crescent fountains come from Landmark81Zones.crescent_fountains() (zones/lagoon.json,
# the island generator's source too); the 5th ring centre (Lake 3) from lake3_center().
# Must equal foam_boxes[16] in SaigonRiverWater.gdshader (raised in Phase 1
# for the pier clusters; 13 are filled since the Phase 3 Marina Club).
const MAX_FOAM_BOXES := 16
# Must equal reflector_pos[16] / reflector_col[16] in SaigonRiverWater.gdshader.
const MAX_REFLECTORS := 16
# Saigon street-lamp head height: tools/inspect_model.gd reports
# assets/models/architecture/saigon_street_lamp.glb as 3.16 m tall, so the head
# sits ~3.16 m above the lot base (y = 0.06 in Landmark81Zones.lots("lamps")).
const LAMP_HEAD_HEIGHT := 3.16
const LAMP_BASE_Y := 0.06

var _map: Node3D
var _island: Node3D
var _yachts: Array[Node3D] = []
var _water_time: float = 0.0
var _river_bank_pts := PackedVector2Array()
var _river_material: ShaderMaterial = null
var _pond_material: ShaderMaterial = null
var _spray_material: ShaderMaterial = null
var _moon_found: bool = false


func _init(map: Node3D, island: Node3D) -> void:
	_map = map
	_island = island


## True for the island meshes that run a water shader via material_override.
static func is_water_mesh(mesh_name: StringName) -> bool:
	return mesh_name == RIVER_MESH_NAME or mesh_name == POND_MESH_NAME or mesh_name == SPRAY_MESH_NAME


func collect_yachts() -> void:
	var yacht_root := _map.get_node_or_null("LuxuryYachts")
	if yacht_root:
		for child in yacht_root.get_children():
			if child is Node3D:
				_yachts.append(child)


func process(delta: float) -> void:
	# Subtle water heave and roll on moored luxury yachts
	if _yachts.is_empty():
		return
	_water_time += delta
	for i in _yachts.size():
		var boat: Node3D = _yachts[i]
		if is_instance_valid(boat):
			var phase: float = _water_time * 1.6 + float(i) * 2.1
			boat.position.y = 0.02 + sin(phase) * 0.035
			boat.rotation.z = sin(phase * 0.8) * 0.018
			boat.rotation.x = cos(phase * 0.7) * 0.012


# Water day_blend: foam / ring / plume night-dim + fresnel sky boost (one uniform each).
func set_day_blend(t: float) -> void:
	if _river_material:
		_river_material.set_shader_parameter("day_blend", t)
	if _pond_material:
		_pond_material.set_shader_parameter("day_blend", t)
	if _spray_material:
		_spray_material.set_shader_parameter("day_blend", t)


# Assigns the shared SaigonRiverWater shader and fills its foam obstacle boxes once.
# Yachts bob ±3.5 cm but never translate in XZ, so static boxes stay correct with
# zero per-frame cost. Finger-pier boxes are sized to the walk width; all 6 mooring
# pilings sit inside the 3 pier boxes.
func setup_river_material() -> void:
	var river_mesh := _island.find_child(RIVER_MESH_NAME, true, false) as MeshInstance3D
	if river_mesh == null:
		push_warning("Landmark81Map: SaigonRiverWater mesh not found - river keeps fallback material.")
		return
	var river_mat := load(RIVER_MATERIAL_PATH) as ShaderMaterial
	if river_mat == null:
		push_warning("Landmark81Map: SaigonRiverWater.tres failed to load.")
		return
	river_mesh.material_override = river_mat
	_river_material = river_mat

	# The finger piers stand on the central bank, pushed `shift` m into the river (south_bank.json).
	var pier_dz := Landmark81Zones.south_bank_shift(24.0)
	var boxes: Array = [
		Vector4(24.0, 38.5 + pier_dz, 1.2, 4.5),   # finger pier main walk (pilings at x 23/25 fit in ±1.2)
		Vector4(27.5, 36.5 + pier_dz, 3.25, 0.6),  # north finger (z 36.5)
		Vector4(27.5, 40.5 + pier_dz, 3.25, 0.6),  # south finger (z 40.5)
	]
	# Yacht hulls: model AABB 3.70 x 11.31 m; long axis taken from the basis so a
	# re-rotated yacht doesn't silently get a transposed box. Shrunk to waterline.
	var yacht_root := _map.get_node_or_null("LuxuryYachts")
	if yacht_root:
		for child in yacht_root.get_children():
			if child is Node3D and boxes.size() < MAX_FOAM_BOXES - 1:
				var nc := child as Node3D
				var along_x := absf(nc.global_basis.z.x) > absf(nc.global_basis.z.z)
				var he := Vector2(4.8, 1.5) if along_x else Vector2(1.5, 4.8)
				boxes.append(Vector4(nc.global_position.x, nc.global_position.z, he.x, he.y))
	# Marina pier pontoon: model AABB 6.34 x 5.65 m, shrunk slightly.
	var pier := _map.get_node_or_null("MarinaYachtPier") as Node3D
	if pier and boxes.size() < MAX_FOAM_BOXES:
		boxes.append(Vector4(pier.global_position.x, pier.global_position.z, 3.0, 2.6))
	# Marina Club (Phase 3 zone F): walkway, gangway and one box per finger + its 2 yachts.
	for b in Landmark81Zones.marina_foam_boxes():
		if boxes.size() < MAX_FOAM_BOXES:
			boxes.append(b)
		else:
			push_warning("Landmark81Map: foam box limit reached - Marina Club box dropped")
	river_mat.set_shader_parameter("marina_club_fan", Landmark81Zones.marina_club_fan())
	var used := boxes.size()
	var shelf: float = float(river_mat.get_shader_parameter("band_shelf"))
	var fw: float = float(river_mat.get_shader_parameter("foam_width"))
	var margin: float = shelf + fw + 0.12
	var min_x := 1e9
	var min_z := 1e9
	var max_x := -1e9
	var max_z := -1e9
	for i in used:
		var b: Vector4 = boxes[i]
		min_x = minf(min_x, b.x - b.z - margin)
		min_z = minf(min_z, b.y - b.w - margin)
		max_x = maxf(max_x, b.x + b.z + margin)
		max_z = maxf(max_z, b.y + b.w + margin)
	var foam_bounds := Vector4(min_x, min_z, max_x, max_z) if used > 0 else Vector4.ZERO
	river_mat.set_shader_parameter("foam_bounds", foam_bounds)
	while boxes.size() < MAX_FOAM_BOXES:
		boxes.append(Vector4.ZERO)
	river_mat.set_shader_parameter("foam_boxes", boxes)
	river_mat.set_shader_parameter("foam_box_count", used)
	# Bank polyline (east -> west): the straight south bank at z = 34.38, stepping out to the
	# pushed central bank (zones/south_bank.json) between x = bank_x[1] and bank_x[0], then the
	# r = 25 arc centred on (-95, 5) of the west bend. The arc is duplicated from
	# maps/landmark_81/west_bend.mjs (CONTRACT(mesh-names)); change both together.
	# z = 34.38 is where the sloped sea-wall top meets the water (not the wall's z = 33 footprint).
	var sb: Dictionary = Landmark81Zones.data().get("south_bank", {})
	var bank_x: Array = sb.get("x", [-95.0, -95.0])
	var bank_dz: float = float(sb.get("shift", 0.0))
	var bank_pts := PackedVector2Array([
		Vector2(120.0, 34.38),
		Vector2(float(bank_x[1]), 34.38),
		Vector2(float(bank_x[1]), 34.38 + bank_dz),
		Vector2(float(bank_x[0]), 34.38 + bank_dz),
	])
	for deg in [90.0, 112.5, 135.0, 157.5, 180.0]:
		var a := deg_to_rad(deg)
		bank_pts.append(Vector2(-95.0 + 25.0 * cos(a), 5.0 + 25.0 * sin(a)))
	_river_bank_pts = bank_pts
	river_mat.set_shader_parameter("bank_pts", bank_pts)
	river_mat.set_shader_parameter("bank_count", bank_pts.size())
	print("✓ Applied SaigonRiverWater with %d foam obstacles!" % used)


# Builds the Saigon River's night-reflection point list once (zero per-frame cost).
# Each reflector is a point: reflector_pos = (world x, y, z, intensity),
# reflector_col = (r, g, b, vertical stretch). The shader mirrors the view ray off
# flat water and scores each reflector by azimuth error, so the streak lands at the
# correct mirrored screen position, broken into dashes by the waves.
# Runs after setup_river_material() (it needs the bank polyline) and after the day
# grade collected the lantern lights. `tower` is the Landmark 81 node (null = missing,
# named by `tower_path` in the warning).
# CONTRACT(mesh-names): lantern lights, promenade lots, the tower node and the
# NightSky group all fail silently on rename; contract_problems() fails
# --round-test when the list comes up short or the moon is missing.
func setup_river_reflections(lantern_lights: Array[OmniLight3D], lantern_energies: PackedFloat32Array, tower: Node3D, tower_path: String) -> void:
	if _river_material == null:
		return
	var pos: Array = []
	var col: Array = []
	# 1. Riverside lantern lights (their own colour), land side plus the pavilion
	# globes just over the water edge. The plan's -12..0 band would drop the two
	# Dandelion globes (d ≈ +2 m river-side), but the acceptance needs their
	# streaks, so the band runs to +4 m.
	for i in lantern_lights.size():
		var light := lantern_lights[i]
		if not is_instance_valid(light):
			continue
		var d := _bank_sdf(Vector2(light.global_position.x, light.global_position.z), _river_bank_pts)
		if d < -12.0 or d > 4.0:
			continue
		var energy := 1.0
		if i < lantern_energies.size():
			energy = lantern_energies[i]
		pos.append(Vector4(light.global_position.x, light.global_position.y, light.global_position.z, energy * 0.5))
		col.append(Vector4(light.light_color.r, light.light_color.g, light.light_color.b, 0.3))
	# 2. Promenade lamp heads (warm, medium stretch).
	for p in Landmark81Zones.promenade_lamp_positions():
		pos.append(Vector4(p.x, LAMP_BASE_Y + LAMP_HEAD_HEIGHT, p.y, 1.5))
		col.append(Vector4(1.0, 0.72, 0.38, 0.3))
	# 3. Landmark 81 tower tip (cool white, long stretch).
	if tower:
		var tip := _global_aabb_top_center(tower)
		pos.append(Vector4(tip.x, tip.y, tip.z, 2.0))
		col.append(Vector4(0.7, 0.85, 1.0, 0.45))
	else:
		push_warning("Landmark81Map: tower node '%s' not found - no tower reflection." % tower_path)
	# 4. The moon (moon-white, very long stretch: the "moon road").
	var sky := _map.get_tree().get_first_node_in_group(&"NightSky")
	if sky and sky.has_method(&"moon_global_position"):
		var mp: Vector3 = sky.moon_global_position()
		pos.append(Vector4(mp.x, mp.y, mp.z, 1.5))
		col.append(Vector4(0.75, 0.85, 1.0, 0.6))
		_moon_found = true
	else:
		push_warning("Landmark81Map: NightSky.moon_global_position() not found - no moon road.")
	var used: int = mini(pos.size(), MAX_REFLECTORS)
	if pos.size() > MAX_REFLECTORS:
		push_warning("Landmark81Map: %d reflectors, keeping %d - some lamps dropped" % [pos.size(), MAX_REFLECTORS])
	while pos.size() < MAX_REFLECTORS:
		pos.append(Vector4.ZERO)
		col.append(Vector4.ZERO)
	_river_material.set_shader_parameter("reflector_pos", pos)
	_river_material.set_shader_parameter("reflector_col", col)
	_river_material.set_shader_parameter("reflector_count", used)
	print("✓ SaigonRiverWater reflections: %d reflectors (moon %s)!" % [used, "found" if _moon_found else "MISSING"])


# Top-centre of a node's global AABB (walks the mesh descendants). Falls back to
# 10 m above the origin when the node holds no mesh.
func _global_aabb_top_center(node: Node3D) -> Vector3:
	var acc: Array = [] # [AABB]; Array boxing because AABB is a value type
	_accumulate_aabb(node, acc)
	if acc.is_empty():
		return node.global_position + Vector3(0.0, 10.0, 0.0)
	var box: AABB = acc[0]
	return box.position + Vector3(box.size.x * 0.5, box.size.y, box.size.z * 0.5)


func _accumulate_aabb(node: Node, acc: Array) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		var global_box := mi.global_transform * mi.get_aabb()
		if acc.is_empty():
			acc.append(global_box)
		else:
			acc[0] = (acc[0] as AABB).merge(global_box)
	for child in node.get_children():
		_accumulate_aabb(child, acc)


# Assigns the shared PondWater shader and fills its fountain ring centres once.
# The 4 crescent fountains and the 5th (Lake 3) are read from Landmark81Zones so the
# json stays the single source of truth (shader array holds 5: fountains[5]). Zero per-frame cost: the rings animate via TIME in the shader.
func setup_pond_material() -> void:
	var pond_mesh := _island.find_child(POND_MESH_NAME, true, false) as MeshInstance3D
	if pond_mesh == null:
		push_warning("Landmark81Map: LagoonReflectingWater mesh not found - ponds keep fallback material.")
	else:
		var pond_mat := load(POND_MATERIAL_PATH) as ShaderMaterial
		if pond_mat == null:
			push_warning("Landmark81Map: PondWater.tres failed to load.")
		else:
			pond_mesh.material_override = pond_mat
			_pond_material = pond_mat
			var fountains: Array = []
			for f in Landmark81Zones.crescent_fountains():
				fountains.append(f)
			var lake3 := Landmark81Zones.lake3_center()
			fountains.append(Vector4(lake3.x, lake3.y, Landmark81Zones.LAKE3_FOUNTAIN_R, 0.0))
			pond_mat.set_shader_parameter("fountains", fountains)
			pond_mat.set_shader_parameter("fountain_count", fountains.size())
			print("✓ Applied PondWater with %d fountain rings!" % fountains.size())
	var spray_mesh := _island.find_child(SPRAY_MESH_NAME, true, false) as MeshInstance3D
	if spray_mesh == null:
		push_warning("Landmark81Map: FountainSprays mesh not found - sprays keep fallback material.")
		return
	var spray_mat := load(SPRAY_MATERIAL_PATH) as ShaderMaterial
	if spray_mat == null:
		push_warning("Landmark81Map: FountainSpray.tres failed to load.")
		return
	spray_mesh.material_override = spray_mat
	_spray_material = spray_mat
	print("✓ Applied FountainSpray!")


# GDScript mirror of SaigonRiverWater.gdshader bank_sdf(): positive on the river side.
static func _bank_sdf(p: Vector2, pts: PackedVector2Array) -> float:
	if pts.size() < 2:
		return 1e9
	var best := 1e9
	var sgn := 1.0
	for i in pts.size() - 1:
		var a := pts[i]
		var ba := pts[i + 1] - a
		var h := clampf((p - a).dot(ba) / maxf(ba.dot(ba), 1e-6), 0.0, 1.0)
		var rel := (p - a) - ba * h
		var dist := rel.length()
		if dist < best:
			var bh := ba / maxf(ba.length(), 1e-6)
			best = dist
			sgn = 1.0 if rel.x * bh.y - rel.y * bh.x >= 0.0 else -1.0
	return best * sgn


# The water half of Landmark81Map.contract_problems() (--round-test).
func contract_problems() -> PackedStringArray:
	var problems: PackedStringArray = []
	var river := _island.find_child(RIVER_MESH_NAME, true, false) as MeshInstance3D
	if river == null or river.material_override == null \
			or river.material_override.resource_path != RIVER_MATERIAL_PATH:
		problems.append("river mesh '%s' missing or not using %s" % [RIVER_MESH_NAME, RIVER_MATERIAL_PATH])
	elif int(river.material_override.get_shader_parameter("foam_box_count")) <= 0:
		problems.append("river foam boxes were not filled")
	# Night reflections (CONTRACT(mesh-names) rows 10-11): tower + moon + lamps.
	if river and river.material_override:
		if int(river.material_override.get_shader_parameter("reflector_count")) < 3:
			problems.append("river reflectors missing (tower + moon + at least one lamp expected)")
		if not _moon_found:
			problems.append("river moon reflection missing (NightSky group / moon_global_position)")
	if river and river.find_children("*", "StaticBody3D", false, false).size() > 0:
		problems.append("river mesh got trimesh collision (collision skip list out of sync)")
	var pond := _island.find_child(POND_MESH_NAME, true, false) as MeshInstance3D
	if pond == null or pond.material_override == null \
			or pond.material_override.resource_path != POND_MATERIAL_PATH:
		problems.append("pond mesh '%s' missing or not using %s" % [POND_MESH_NAME, POND_MATERIAL_PATH])
	elif int(pond.material_override.get_shader_parameter("fountain_count")) <= 0:
		problems.append("pond fountain rings were not filled")
	if pond and pond.find_children("*", "StaticBody3D", false, false).size() > 0:
		problems.append("pond mesh got trimesh collision (collision skip list out of sync)")
	var spray := _island.find_child(SPRAY_MESH_NAME, true, false) as MeshInstance3D
	if spray == null or spray.material_override == null \
			or spray.material_override.resource_path != SPRAY_MATERIAL_PATH:
		problems.append("spray mesh '%s' missing or not using %s" % [SPRAY_MESH_NAME, SPRAY_MATERIAL_PATH])
	# Bank polyline sanity (CONTRACT(mesh-names) rows 4-5): river > 0, land < 0.
	for probe in [[Vector2(0, 50), true], [Vector2(60, 50), true], [Vector2(60, 40), false], [Vector2(0, 20), false], [Vector2(-110, 20), false]]:
		var d := _bank_sdf(probe[0], _river_bank_pts)
		if (d > 0.0) != probe[1]:
			problems.append("bank_sdf%s = %.2f (expected %s)" % [probe[0], d, "river > 0" if probe[1] else "land < 0"])
	return problems
