@tool
extends Node3D

# Batched tree and shrub placement for a map: one MultiMeshInstance3D per species mesh
# part, so draw calls scale with species, not trees. Holds no map content: the layout
# (species, hand-placed positions, scatter counts, fill rects, obstacles) is the JSON at
# `config_path` (Landmark 81: data/maps/landmark_81/forest.json), while water, blocked
# ground, lots, walkways and the arena come from the map's zone script
# (src/maps/MapZones.gd: on_walkway keeps authored AND scattered trunks off gate
# paths) and heights from its terrain (src/maps/TerrainHeightfield.gd). Every list is
# drawn from fixed-seed streams in file order, so the same data always gives the same
# forest.

## Forest layout JSON for this map.
@export_file("*.json") var config_path: String = ""

@export var enabled: bool = true:
	set(val):
		enabled = val
		if Engine.is_editor_hint() or is_inside_tree():
			_generate_forest()

@export var tree_seed: int = 1337:
	set(val):
		tree_seed = val
		if Engine.is_editor_hint() or is_inside_tree():
			_generate_forest()

var _day_blend: float = 0.0

# Duplicate-and-tween grade (same pattern as DayNightCycle._collect_ground_materials):
# the imported tree materials are shared resources, so each distinct source material
# gets one duplicate whose albedo is lerped night <-> day. No custom shader
# (TRAPS.md#pbr-parity): StandardMaterial3D only, zero idle cost.
var _terrain: TerrainHeightfield = null # the owning map's ground (null = flat)
var _zones = null # the owning map's zone script (MapZones contract); untyped: its statics are duck-typed

func _ground_height(x: float, z: float) -> float:
	return _terrain.height(x, z) if _terrain else 0.0

# Tree-free ellipse over the lawn and carpet (zones json arena.tree_clear), squared once.
var _clear_rx2: float = 1.0
var _clear_rz2: float = 1.0
# Per-gate walkway cull counts for the current generate (Outcome report).
var _walkway_culled: Dictionary = {}

func _walkway_gate(x: float, z: float) -> String:
	if _zones == null:
		return ""
	if _zones.has_method("walkway_match"):
		return _zones.walkway_match(x, z, 1.0)
	if _zones.has_method("on_walkway") and _zones.on_walkway(x, z, 1.0):
		return "?"
	return ""

func _on_carpet(x: float, z: float) -> bool:
	return (x * x) / _clear_rx2 + (z * z) / _clear_rz2 < 1.0

func _load_config() -> Dictionary:
	if config_path.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not (parsed is Dictionary):
		push_error("ForestMultiMesh: cannot read %s" % config_path)
		return {}
	return parsed

# One species entry of the config, with its position groups flattened (file order is
# draw order) and its "east_lots" resolved through the map's lots().
func _species_config(sp: Dictionary) -> Dictionary:
	var cfg := sp.duplicate()
	var positions: Array = []
	for group in sp.get("positions", []):
		for p in group["points"]:
			positions.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	cfg["positions"] = positions
	var east: Array = []
	if sp.has("east_lots"):
		for lot in _zones.lots(str(sp["east_lots"])):
			east.append(lot["pos"])
	cfg["east_positions"] = east
	return cfg

const NIGHT_TINT := Color(0.55, 0.60, 0.78)
var _tree_materials: Array[StandardMaterial3D] = []
var _tree_night_colors: PackedColorArray = PackedColorArray()
var _tree_day_colors: PackedColorArray = PackedColorArray()

func _ready() -> void:
	_generate_forest()

# 0.0 = nocturnal grade, 1.0 = sunlit grade. Called by DayNightCycle.gd only while a transition runs.
func set_day_blend(blend: float) -> void:
	_day_blend = clampf(blend, 0.0, 1.0)
	for i in range(_tree_materials.size()):
		_tree_materials[i].albedo_color = _tree_night_colors[i].lerp(_tree_day_colors[i], _day_blend)

func _generate_forest() -> void:
	# Clean up previous generated MultiMesh instances
	for child in get_children():
		child.queue_free()
	_tree_materials.clear()
	_tree_night_colors = PackedColorArray()
	_tree_day_colors = PackedColorArray()
	var _grade_seen: Dictionary = {}

	if not enabled:
		return
	_terrain = TerrainHeightfield.for_node(self)
	_zones = MapZones.for_node(self)
	var tree_clear: Array = _zones.data().get("arena", {}).get("tree_clear", [0.0, 0.0])
	_clear_rx2 = float(tree_clear[0]) * float(tree_clear[0])
	_clear_rz2 = float(tree_clear[1]) * float(tree_clear[1])

	var rng = RandomNumberGenerator.new()
	rng.seed = tree_seed
	var zone_rng := RandomNumberGenerator.new()
	zone_rng.seed = tree_seed + 7919 # separate stream: zone trees never shift the core trees' draws
	var east_rng := RandomNumberGenerator.new()
	east_rng.seed = tree_seed + 104729 # east-side stream (Phase 3): never shifts core or west draws
	var fill_rng := RandomNumberGenerator.new()
	fill_rng.seed = tree_seed + 15485863 # fill-rect stream: never shifts core, west or east draws

	var config := _load_config()
	if config.is_empty():
		return
	# Zone scatter: species with zone_scatter_count fill this rect from the map's zones data.
	var grove_rect: Array = _zones.data().get(str(config.get("zone_scatter_rect", "")), {}).get("rect", [])
	# Fill rects: open ground the toy-diorama look wants covered in canopy, each with its own
	# {species name: count}. Only list species that already grow next to the rect: a MultiMesh
	# is culled by one AABB, so stretching a species into a far corner pulls its whole batch
	# into more views and shadow cascades (a NE rect cost +10 draw calls in the gameplay view).
	var fill_rects: Array = config.get("fill_rects", [])
	var species_configs: Array[Dictionary] = []
	for sp in config.get("species", []):
		species_configs.append(_species_config(sp))

	# Spatial collision registry: prevents any tree from overlapping with other trees or map obstacles
	var occupied_pos: Array[Vector2] = []
	var occupied_radii: Array[float] = []
	_register_obstacles(config.get("obstacles", {}), occupied_pos, occupied_radii)

	var total_instanced = 0
	_walkway_culled.clear()

	for cfg in species_configs:
		var scene: PackedScene = load(cfg.scene_path)
		if not scene:
			push_warning("Could not load tree scene: " + cfg.scene_path)
			continue

		var template = scene.instantiate()
		var mesh_items = _collect_meshes(template)
		template.queue_free()

		if mesh_items.is_empty():
			push_warning("No meshes found in tree scene: " + cfg.scene_path)
			continue

		var positions: Array = cfg.positions
		var transforms: Array[Transform3D] = []
		var clear_r: float = float(cfg.get("clear_r", 1.5))

		for pos in positions:
			# Safety guard: ensure no tree ever stands on the white park carpet or central lawn
			if _on_carpet(pos.x, pos.z):
				continue
			# Water guard: ensure no tree ever stands on water (lakes, canal, river)
			if _zones.is_in_water(pos.x, pos.z):
				continue
			# Walkway guard: trunks stay off gate paths (half-width + 1.0 m).
			var hit_gate := _walkway_gate(pos.x, pos.z)
			if hit_gate != "":
				_walkway_culled[hit_gate] = int(_walkway_culled.get(hit_gate, 0)) + 1
				continue
			# Spatial collision guard: ensure no tree overlaps with obstacles or earlier trees
			if is_colliding(pos.x, pos.z, clear_r, occupied_pos, occupied_radii):
				continue

			occupied_pos.append(Vector2(pos.x, pos.z))
			occupied_radii.append(clear_r)

			var s: float = rng.randf_range(cfg.scale_min, cfg.scale_max)
			var rot_y: float = rng.randf_range(0.0, TAU)
			var tilt_x: float = rng.randf_range(-0.015, 0.015)
			var tilt_z: float = rng.randf_range(-0.015, 0.015)

			var t := Transform3D()
			t = t.scaled(Vector3(s, s, s))
			t = t.rotated(Vector3.UP, rot_y)
			t = t.rotated(Vector3.RIGHT, tilt_x)
			t = t.rotated(Vector3.FORWARD, tilt_z)
			var ground_y: float = _ground_height(pos.x, pos.z) + pos.y
			t.origin = Vector3(pos.x, ground_y, pos.z)
			transforms.append(t)

		# Zone additions: dynamically scattered into available pockets without overlapping any existing tree or obstacle
		if cfg.has("zone_scatter_count"):
			var zone_pts := dynamic_scatter(int(cfg.zone_scatter_count), grove_rect, zone_rng, clear_r, occupied_pos, occupied_radii)
			_append_scattered(transforms, zone_pts, zone_rng, cfg.scale_min, cfg.scale_max)

		# East-side additions (Phase 3 villa gardens): same MultiMeshes, own stream, collision-guarded.
		if not cfg.east_positions.is_empty():
			_append_scattered_checked(transforms, cfg.east_positions, east_rng, cfg.scale_min, cfg.scale_max, clear_r, occupied_pos, occupied_radii)

		# Fill-rect additions: same MultiMeshes (no new MMI), own stream, collision-guarded.
		for fr in fill_rects:
			var fill_count := int((fr.get("species", {}) as Dictionary).get(cfg.name, 0))
			if fill_count > 0:
				var fill_pts := dynamic_scatter(fill_count, fr.get("rect", []), fill_rng, clear_r, occupied_pos, occupied_radii)
				_append_scattered(transforms, fill_pts, fill_rng, cfg.scale_min, cfg.scale_max)

		# For each mesh part in this tree model, create a batched MultiMeshInstance3D
		for item in mesh_items:
			var mmi := MultiMeshInstance3D.new()
			mmi.name = cfg.name + "_" + item.name
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = item.mesh
			mm.instance_count = transforms.size()

			for i in range(transforms.size()):
				var instance_t: Transform3D = transforms[i] * item.transform
				mm.set_instance_transform(i, instance_t)

			mmi.multimesh = mm

			# Invariant 4: Ground-level instanced foliage is cast_shadow = OFF.
			# Small shrubs, flowers, and secondary detail layers never pay for shadow cascade passes.
			# Strands are the willow's ground-curtain cones (weeping_willow.mjs): textbook ground-level.
			var item_lower: String = str(item.name).to_lower()
			if not cfg.get("cast_shadow", true):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif "flower" in item_lower or "blossom" in item_lower or "fruit" in item_lower or "ring" in item_lower or "shaft" in item_lower or "top" in item_lower or "petiole" in item_lower or "strands" in item_lower:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

			add_child(mmi)
			_grade_tree_mmi(mmi, _grade_seen)

		total_instanced += transforms.size()

	_apply_tree_grade()
	if not Engine.is_editor_hint():
		print("✓ ForestMultiMesh: Batched %d trees & shrubs of %d species from %s" % [total_instanced, species_configs.size(), config_path])
		if not _walkway_culled.is_empty():
			print("  Walkway culls: %s" % str(_walkway_culled))

# One duplicate per DISTINCT imported tree material (same pattern as
# DayNightCycle._collect_ground_materials): the .glb materials are shared, so
# they are duplicated rather than mutated. Day = authored albedo; night = day
# cooled and darkened toward slate-indigo (no per-distance falloff in Phase 1).
# `seen` maps a source material's instance id to its duplicate, so all MMIs
# sharing one source tween one color, not one per instance.
func _grade_tree_mmi(mmi: MultiMeshInstance3D, seen: Dictionary) -> void:
	var mesh: Mesh = mmi.multimesh.mesh
	if mesh == null:
		return
	if mesh.get_surface_count() == 1:
		var src: Material = mesh.surface_get_material(0)
		if src is StandardMaterial3D:
			var key: int = src.get_instance_id()
			var mat: StandardMaterial3D
			if seen.has(key):
				mat = seen[key]
			else:
				mat = (src as StandardMaterial3D).duplicate()
				seen[key] = mat
				_register_tree_material(mat)
			mmi.material_override = mat
		return
	# Multi-surface mesh part: duplicate the mesh so each surface keeps its own
	# graded material instead of collapsing to one override.
	var dup: Mesh = mesh.duplicate()
	for i in range(dup.get_surface_count()):
		var src: Material = dup.surface_get_material(i)
		if not (src is StandardMaterial3D):
			continue
		var key: int = src.get_instance_id()
		var mat: StandardMaterial3D
		if seen.has(key):
			mat = seen[key]
		else:
			mat = (src as StandardMaterial3D).duplicate()
			seen[key] = mat
			_register_tree_material(mat)
		dup.surface_set_material(i, mat)
	mmi.multimesh.mesh = dup

func _register_tree_material(mat: StandardMaterial3D) -> void:
	var day_col: Color = mat.albedo_color
	_tree_materials.append(mat)
	_tree_day_colors.append(day_col)
	_tree_night_colors.append(Color(
		minf(day_col.r * NIGHT_TINT.r, 1.0),
		minf(day_col.g * NIGHT_TINT.g, 1.0),
		minf(day_col.b * NIGHT_TINT.b, 1.0),
		day_col.a))

func _apply_tree_grade() -> void:
	for i in range(_tree_materials.size()):
		_tree_materials[i].albedo_color = _tree_night_colors[i].lerp(_tree_day_colors[i], _day_blend)

# Appends one randomized transform per position, drawing scale/yaw/tilt from `r`
# (the stream that owns these positions) in the same order as the core loop.
func _append_scattered(transforms: Array[Transform3D], positions: Array, r: RandomNumberGenerator, scale_min: float, scale_max: float) -> void:
	for p in positions:
		if _on_carpet(p.x, p.z):
			continue
		if _zones.is_in_water(p.x, p.z):
			continue
		var hit_gate := _walkway_gate(p.x, p.z)
		if hit_gate != "":
			_walkway_culled[hit_gate] = int(_walkway_culled.get(hit_gate, 0)) + 1
			continue

		var s := r.randf_range(scale_min, scale_max)
		var rot_y := r.randf_range(0.0, TAU)
		var tilt_x := r.randf_range(-0.015, 0.015)
		var tilt_z := r.randf_range(-0.015, 0.015)
		var t := Transform3D()
		t = t.scaled(Vector3(s, s, s))
		t = t.rotated(Vector3.UP, rot_y)
		t = t.rotated(Vector3.RIGHT, tilt_x)
		var ground_y: float = _ground_height(p.x, p.z) + p.y
		t.origin = Vector3(p.x, ground_y, p.z)
		transforms.append(t)

# Registers the map's stationary obstacles (forest config "obstacles") into the
# collision registry: fixed points [x, z, radius], every position of a zones-data
# entry ("zone_points"), and every lot of a map lots() key ("lots").
func _register_obstacles(obstacles: Dictionary, out_pos: Array[Vector2], out_radii: Array[float]) -> void:
	for p in obstacles.get("points", []):
		var at: Array = p["at"]
		out_pos.append(Vector2(float(at[0]), float(at[1])))
		out_radii.append(float(at[2]))
	for zp in obstacles.get("zone_points", []):
		for pos in _zones.data().get(str(zp["zone"]), {}).get("pos", []):
			out_pos.append(Vector2(float(pos[0]), float(pos[1])))
			out_radii.append(float(zp["radius"]))
	for lot_spec in obstacles.get("lots", []):
		for lot in _zones.lots(str(lot_spec["key"])):
			var lp: Vector3 = lot.get("pos", Vector3())
			out_pos.append(Vector2(lp.x, lp.z))
			out_radii.append(float(lot_spec["radius"]))

# Fast 2D circle-circle collision test against all registered obstacles and existing trees.
# Precomputed squared distance avoids sqrt / division per Invariant 7.
static func is_colliding(x: float, z: float, r: float, occupied_pos: Array[Vector2], occupied_radii: Array[float]) -> bool:
	var p := Vector2(x, z)
	for i in range(occupied_pos.size()):
		var min_dist: float = r + occupied_radii[i]
		if p.distance_squared_to(occupied_pos[i]) < min_dist * min_dist:
			return true
	return false

# Dynamic deterministic scatter inside grove_rect: rejects points that fall on the central oval,
# in water, in blocked zones, or that collide with any existing tree or map obstacle.
# Registers accepted points into occupied_pos and occupied_radii to ensure subsequent species never collide.
func dynamic_scatter(count: int, rect: Array, rng: RandomNumberGenerator, clear_r: float, occupied_pos: Array[Vector2], occupied_radii: Array[float], y: float = 0.06) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if rect.size() < 4:
		return out
	var tries := 0
	var max_tries := count * 100
	while out.size() < count and tries < max_tries:
		tries += 1
		var x := rng.randf_range(rect[0], rect[2])
		var z := rng.randf_range(rect[1], rect[3])
		if _on_carpet(x, z):
			continue
		if _zones.blocks_trees(x, z) or _zones.is_in_water(x, z):
			continue
		var hit_gate := _walkway_gate(x, z)
		if hit_gate != "":
			_walkway_culled[hit_gate] = int(_walkway_culled.get(hit_gate, 0)) + 1
			continue
		if is_colliding(x, z, clear_r, occupied_pos, occupied_radii):
			continue

		occupied_pos.append(Vector2(x, z))
		occupied_radii.append(clear_r)
		out.append(Vector3(x, y, z))
	return out

# Appends one randomized transform per position, validating collision and registering accepted points.
func _append_scattered_checked(transforms: Array[Transform3D], positions: Array, r: RandomNumberGenerator, scale_min: float, scale_max: float, clear_r: float, occupied_pos: Array[Vector2], occupied_radii: Array[float]) -> void:
	for p in positions:
		if _on_carpet(p.x, p.z):
			continue
		if _zones.is_in_water(p.x, p.z):
			continue
		var hit_gate := _walkway_gate(p.x, p.z)
		if hit_gate != "":
			_walkway_culled[hit_gate] = int(_walkway_culled.get(hit_gate, 0)) + 1
			continue
		if is_colliding(p.x, p.z, clear_r, occupied_pos, occupied_radii):
			continue

		occupied_pos.append(Vector2(p.x, p.z))
		occupied_radii.append(clear_r)

		var s := r.randf_range(scale_min, scale_max)
		var rot_y := r.randf_range(0.0, TAU)
		var tilt_x := r.randf_range(-0.015, 0.015)
		var tilt_z := r.randf_range(-0.015, 0.015)
		var t := Transform3D()
		t = t.scaled(Vector3(s, s, s))
		t = t.rotated(Vector3.UP, rot_y)
		t = t.rotated(Vector3.RIGHT, tilt_x)
		var ground_y: float = _ground_height(p.x, p.z) + p.y
		t.origin = Vector3(p.x, ground_y, p.z)
		transforms.append(t)

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
