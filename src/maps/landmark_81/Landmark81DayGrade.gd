extends RefCounted

# Landmark 81 day/night grade, owned by Landmark81Map (created in its _ready; the
# map forwards EventBus.day_blend_changed to apply()). Grades only this map's own
# nodes: the island ground albedo lift, the lawn + mowing-ring targets, lantern
# lights, forest and grass (their set_day_blend), the water (via Landmark81Water)
# and the skyline window emission. The shared sky, lights and pearl glow stay in
# DayNightCycle.
# CONTRACT(mesh-names): the authored colors below are matched at runtime;
# Landmark81Map.contract_problems() fails --round-test when one breaks.

const Water := preload("res://src/maps/landmark_81/Landmark81Water.gd")

# --- Island ground daylight lift ---
# The island's dark flat-color materials are authored for night: the outer earth base is
# near-black, so no amount of sunlight can rescue it - its ALBEDO itself has to come up.
# The materials are unnamed in the .glb, so rather than matching them by name (brittle)
# each one is lifted by its OWN darkness: base loam, soil and cliffs lift hard while
# already-bright paving, curbs and railings are left exactly as authored.
#
# NOTE: these thresholds are in Godot's sRGB `albedo_color` space, NOT the .glb's linear
# baseColorFactor. The island's dark luminances are loam ~0.12, soil ~0.15, cliff ~0.24 -
# mixing the two spaces up silently no-ops the whole lift.
const GROUND_DARK_CUTOFF := 0.40 # sRGB luminance at/above which a material is "bright" and untouched
const GROUND_MAX_LIFT := 2.2     # Albedo multiplier applied to the darkest materials (keeps soil rich, not bleached)
const GROUND_WARM := Color(1.04, 0.98, 0.88) # Gentle warm sun bounce

# The ONE island material that is not a darkness-lift case. Authored 0x2e7d32 (lawnTropical
# in floating_diorama_island.mjs), it sits right at GROUND_DARK_CUTOFF, so _sunlit_albedo()
# returns it untouched - which by day sits too close to the Lotus Shooter's stem green
# (0x48a82a) and makes placed plants hard to read against their own lawn. It therefore gets
# an explicit sunlit target instead of the automatic lift.
#
# Matching it: the island's materials are UNNAMED in the .glb, so name matching is
# impossible, and an index table would silently mis-target the moment a mesh is added to
# createFloatingDioramaIsland(). The lawn albedo differs from every other island albedo by
# well over epsilon on at least one channel, so an exact color match is unambiguous.
const LAWN_NIGHT_ALBEDO := Color(0.180392, 0.490196, 0.196078) # 0x2e7d32, exactly as imported (CONTRACT(mesh-names))
const LAWN_NIGHT_TARGET := Color(0.20, 0.26, 0.21)              # Desaturated blue-leaning moss: value buys readability, not saturation
const LAWN_DAY_ALBEDO := Color(0.35, 0.68, 0.30)   # Fresh vibrant storybook meadow (Point 5 & 8)
const LAWN_MATCH_EPSILON := 0.02

# The concentric mowing rings around the pearl (lawnStripe 0x43a047 in
# floating_diorama_island.mjs, mesh LawnMowingStripes). Separate island material
# going through the darkness-lift path; at night it stays daylight-green while
# everything turns blue, so it needs its own explicit night target like the lawn.
# Matched the same way (exact authored color + epsilon + push_warning). Do not
# move GROUND_DARK_CUTOFF to catch it - that shifts every other island material.
const RINGS_NIGHT_ALBEDO := Color(0.262745, 0.627451, 0.278431) # 0x43a047, exactly as imported (CONTRACT(mesh-names))
const RINGS_NIGHT_TARGET := Color(0.16, 0.21, 0.20)             # One step darker and bluer than the lawn: lawn is the lit stage, rings are decoration
const RINGS_MATCH_EPSILON := 0.02

# Lantern flames are pure night dressing: fully on at night, switched off by day.
const NIGHT_LANTERN_FACTOR := 1.0
const DAY_LANTERN_FACTOR := 0.0

# Tower window / LED emission, baked into the tower .glbs at 2.5-3.8 (plus beacons).
# Scaled per phase so the skyline stays a backdrop: barely lit by day, and at night
# dimmer than Landmark 81, which keeps its full glow as the one skyline anchor.
const NIGHT_WINDOW_FACTOR := 0.45
const DAY_WINDOW_FACTOR := 0.12
const NIGHT_LANDMARK_FACTOR := 1.0
const DAY_LANDMARK_FACTOR := 0.25

var _forest: Node
var _grass: Node
var _water: Water

var lantern_lights: Array[OmniLight3D] = []
var lantern_energies: PackedFloat32Array = PackedFloat32Array()
# One duplicated material per DISTINCT island source material, each with its
# night albedo and the precomputed sunlit albedo. The imported materials are shared
# resources, so they are duplicated rather than mutated.
var _ground_materials: Array[StandardMaterial3D] = []
var _ground_night_colors: PackedColorArray = PackedColorArray()
var _ground_day_colors: PackedColorArray = PackedColorArray()
var lawn_found: bool = false
var rings_found: bool = false
var window_materials: Array[StandardMaterial3D] = []
var landmark_materials: Array[StandardMaterial3D] = []


func _init(forest: Node, grass: Node, water: Water) -> void:
	_forest = forest
	_grass = grass
	_water = water


# `t` is the eased 0 (night) .. 1 (day) blend from DayNightCycle.
func apply(t: float) -> void:
	# One color lerp per distinct island material: lifts the near-black earth base to a sunlit floor by day.
	for i in range(_ground_materials.size()):
		_ground_materials[i].albedo_color = _ground_night_colors[i].lerp(_ground_day_colors[i], t)
	# By day the lantern omnis are switched off outright, which removes them from
	# the forward+ light loop on weak hardware.
	var lantern_factor := lerpf(NIGHT_LANTERN_FACTOR, DAY_LANTERN_FACTOR, t)
	var lanterns_lit := lantern_factor > 0.001
	for i in range(lantern_lights.size()):
		var light := lantern_lights[i]
		if not is_instance_valid(light):
			continue
		if light.visible != lanterns_lit:
			light.visible = lanterns_lit
		if lanterns_lit:
			light.light_energy = lantern_energies[i] * lantern_factor
	# Re-grades the duplicated tree materials (StandardMaterial3D lerp, no shader).
	if _forest and _forest.has_method(&"set_day_blend"):
		_forest.set_day_blend(t)
	# Warms the play-lawn grass tufts only; the forest belt tufts are excluded GPU-side.
	if _grass and _grass.has_method(&"set_day_blend"):
		_grass.set_day_blend(t)
	_water.set_day_blend(t)
	_scale_emission(window_materials, lerpf(NIGHT_WINDOW_FACTOR, DAY_WINDOW_FACTOR, t))
	_scale_emission(landmark_materials, lerpf(NIGHT_LANDMARK_FACTOR, DAY_LANDMARK_FACTOR, t))


# Collects the Landmark 81 tower's emissive materials, then the rest of the skyline's
# (skipping the tower's own). Either node may be null.
func collect_emissive_materials(landmark: Node, skyline: Node) -> void:
	if landmark:
		_collect_emissive(landmark, landmark_materials, {})
	if skyline:
		var skip := {}
		for m in landmark_materials:
			skip[m.get_instance_id()] = true
		_collect_emissive(skyline, window_materials, skip)


# The tower materials are the imported .glb resources (the skyline MultiMeshes share
# the imported meshes), so they are scaled in place. The authored energy is kept in
# metadata: resources outlive a map reload, and re-reading the live value would compound.
func _collect_emissive(node: Node, out: Array[StandardMaterial3D], seen: Dictionary) -> void:
	var mesh: Mesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh:
		mesh = (node as MultiMeshInstance3D).multimesh.mesh
	if mesh:
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat and mat.emission_enabled and not seen.has(mat.get_instance_id()):
				seen[mat.get_instance_id()] = true
				if not mat.has_meta(&"authored_emission"):
					mat.set_meta(&"authored_emission", mat.emission_energy_multiplier)
				out.append(mat)
	for child in node.get_children():
		_collect_emissive(child, out, seen)


func _scale_emission(mats: Array[StandardMaterial3D], factor: float) -> void:
	for mat in mats:
		mat.emission_energy_multiplier = float(mat.get_meta(&"authored_emission")) * factor


func collect_lantern_lights(node: Node) -> void:
	for child in node.get_children():
		if child is OmniLight3D:
			lantern_lights.append(child)
			lantern_energies.append(child.light_energy)
		collect_lantern_lights(child)


# Walks the island once and warns when a load-bearing color match failed: a color
# match fails SILENTLY, and the daylight lawn recolor would just quietly stop happening.
func collect_ground_materials(island: Node) -> void:
	_collect_ground(island, {})
	if not lawn_found:
		push_warning("Landmark81Map: lawn accent material (0x2e7d32) not found on the island - the daylight lawn recolor is a no-op. Did lawnTropical change in floating_diorama_island.mjs?")
	if not rings_found:
		push_warning("Landmark81Map: lawn ring material (0x43a047) not found on the island - the night ring grade is a no-op. Did lawnStripe change in floating_diorama_island.mjs?")


# Swaps in a per-source-material duplicate so the day grade can be tweened without
# touching the shared imported resource. `seen` maps a source material's instance id
# to its duplicate, so the island meshes resolve to one entry per underlying material
# (and therefore one color to tween each, not one per mesh).
# The lawn accent mesh is additionally dropped from the shadow-CASTER pass (it keeps
# receiving): it floats 25mm above the base top, and the two coplanar depths oscillate
# in the 512px shadow map, striping exactly the 48x48 plantable square in daylight.
# Nothing above the lawn needs its cast (dais/plants/trees cast themselves), so this
# loses no visible shadow and shrinks the shadow pass by one caster.
func _collect_ground(node: Node, seen: Dictionary) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node and mesh_node.mesh and Water.is_water_mesh(mesh_node.name):
		# River, pond and spray run their own shaders via material_override: leave
		# the imported StandardMaterial3D untouched and grade them via day_blend.
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif mesh_node and mesh_node.mesh:
		for i in range(mesh_node.mesh.get_surface_count()):
			var src: Material = mesh_node.get_active_material(i)
			if not (src is StandardMaterial3D):
				continue
			var key: int = src.get_instance_id()
			var mat: StandardMaterial3D
			if seen.has(key):
				mat = seen[key]
			else:
				mat = src.duplicate()
				seen[key] = mat
				var night_col := mat.albedo_color
				_ground_materials.append(mat)
				if _is_lawn_albedo(night_col):
					lawn_found = true
					_ground_night_colors.append(LAWN_NIGHT_TARGET)
					_ground_day_colors.append(LAWN_DAY_ALBEDO)
				elif _is_rings_albedo(night_col):
					rings_found = true
					_ground_night_colors.append(RINGS_NIGHT_TARGET)
					_ground_day_colors.append(night_col)
				else:
					_ground_night_colors.append(night_col)
					_ground_day_colors.append(_sunlit_albedo(night_col))
			mesh_node.set_surface_override_material(i, mat)
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_collect_ground(child, seen)


func _is_lawn_albedo(c: Color) -> bool:
	return absf(c.r - LAWN_NIGHT_ALBEDO.r) < LAWN_MATCH_EPSILON \
		and absf(c.g - LAWN_NIGHT_ALBEDO.g) < LAWN_MATCH_EPSILON \
		and absf(c.b - LAWN_NIGHT_ALBEDO.b) < LAWN_MATCH_EPSILON


func _is_rings_albedo(c: Color) -> bool:
	return absf(c.r - RINGS_NIGHT_ALBEDO.r) < RINGS_MATCH_EPSILON \
		and absf(c.g - RINGS_NIGHT_ALBEDO.g) < RINGS_MATCH_EPSILON \
		and absf(c.b - RINGS_NIGHT_ALBEDO.b) < RINGS_MATCH_EPSILON


# Maps a night-authored albedo to its daylight counterpart for the DARKNESS-LIFT cases
# (loam, soil, cliffs). Dark surfaces are lifted hard and warmed; anything already at or
# above GROUND_DARK_CUTOFF luminance is returned untouched. The lawn accent and the
# mowing rings are the explicit-target cases, handled before this is called.
func _sunlit_albedo(night: Color) -> Color:
	var darkness := 1.0 - smoothstep(0.0, GROUND_DARK_CUTOFF, night.get_luminance())
	if darkness <= 0.0:
		return night
	var lift := lerpf(1.0, GROUND_MAX_LIFT, darkness)
	var warm := Color(1.0, 1.0, 1.0).lerp(GROUND_WARM, darkness)
	return Color(
		minf(night.r * lift * warm.r, 1.0),
		minf(night.g * lift * warm.g, 1.0),
		minf(night.b * lift * warm.b, 1.0),
		night.a
	)
