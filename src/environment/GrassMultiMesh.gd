@tool
extends MultiMeshInstance3D

# High-performance MultiMesh grass distributor for the 112m x 112m diorama island.
# Uses zoned density distribution:
# - Zone A (Central Yard & Flanks): concentrated lush tufts (~2500) hugging the pearl dais
#   foundation and meadow flanks, with manicured scale inside the 9x5 combat lawn.
# - Zone B (Outer Island & Forest): wild lush flowering grass tufts (~5500).
# Batched in 1 single draw call with zero texture memory (baked vertex colors).
#
# Day/night: the ~2500 lawn tufts warm into a sunlit yellow-green by day while the ~2200
# wild forest tufts keep their authored night tone. Both live in the SAME MultiMesh, and
# instance colors multiply the albedo, so one shared material cannot re-tone the lawn
# alone - the two sets are therefore split into two MultiMeshes (2 draw calls).

@export_group("Zoned Grass Distribution")
@export var yard_grass_count: int = 420:
	set(val):
		yard_grass_count = val
		if Engine.is_editor_hint() or is_inside_tree():
			_generate_diorama_carpet()

@export var wild_grass_count: int = 380:
	set(val):
		wild_grass_count = val
		if Engine.is_editor_hint() or is_inside_tree():
			_generate_diorama_carpet()

# Phase-1 outer parkland: its own budget appended AFTER passes 1-2, so the
# seeded RNG order of every existing tuft is unchanged.
@export var outer_grass_count: int = 1500:
	set(val):
		outer_grass_count = val
		if Engine.is_editor_hint() or is_inside_tree():
			_generate_diorama_carpet()

# Sampling areas of the three passes (world XZ). Defaults are Landmark 81's island;
# a map with a different island overrides them on its GrassMultiMesh node.
@export var yard_half_extent: float = 24.0
@export var wild_half_extent: float = 53.5
@export var outer_x_range: Vector2 = Vector2(-118.0, 118.0)
@export var outer_z_range: Vector2 = Vector2(-108.0, 22.0)

# Half-extent of the square play lawn. This is the SAME predicate used below when
# assigning instance colors and in is_valid_grass_pos(), and it is handed to the shader
# so the GPU-side zoning can never drift from the CPU-side zoning.
const LAWN_HALF_EXTENT := 14.0

# Authored tuft albedo (0x4ea426) and its daylight counterpart (0x347544): a DEEPER,
# cooler jade. Counter-intuitively the lawn must go darker, not lighter, to fix the
# collision: under full daylight the plants render bright (Lotus core ~(254,202,229),
# Sacred Rice ~(255,255,239)), so brightening the lawn moves it TOWARD them. Measured
# worst-case plant/lawn contrast: 71 unchanged, 60 if brightened, 134 with this jade.
const NIGHT_TUFT_ALBEDO := Color(0.14, 0.25, 0.16)
const DAY_TUFT_ALBEDO := Color(0.38, 0.70, 0.32) # Vibrant storybook meadow tuft (Point 5 & 8)

const WILD_NODE_NAME := "WildGrassMultiMesh"

var _lawn_material: StandardMaterial3D = null
var _day_blend: float = 0.0
var _zones = null # the owning map's zone script (MapZones contract); untyped: its statics are duck-typed
var _terrain: TerrainHeightfield = null
# Lawn and carpet semi-axes squared (zones json "arena"), read once per generate.
var _lawn_rx2: float = 1.0
var _lawn_rz2: float = 1.0
var _carpet_rx2: float = 1.0
var _carpet_rz2: float = 1.0

var grass_count: int:
	get:
		return yard_grass_count + wild_grass_count + outer_grass_count
	set(val):
		# Distribute proportionately if set from legacy callers
		yard_grass_count = int(round(val * 0.3125))
		wild_grass_count = val - yard_grass_count

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_generate_diorama_carpet()

# 0.0 = authored night tone, 1.0 = sunlit lawn. Called by DayNightCycle.gd only while a
# transition is in flight, never per idle frame. ONE uniform write re-tones all 2500 lawn
# tufts; the forest belt tufts are excluded GPU-side, and the single draw call is intact.
func set_day_blend(blend: float) -> void:
	_day_blend = clampf(blend, 0.0, 1.0)
	if _lawn_material:
		_lawn_material.albedo_color = NIGHT_TUFT_ALBEDO.lerp(DAY_TUFT_ALBEDO, _day_blend)

func is_valid_grass_pos(x: float, z: float, apply_new_zones: bool = true) -> float:
	# The map's own exclusions (MapZones contract). Passes 1-2 run with
	# apply_new_zones = false to keep their shared rng stream bit-identical.
	if _zones.blocks_tufts(x, z, not apply_new_zones):
		return -999.0

	# 5. Exclude the park carpet ring, lawn edge -> carpet edge (zones json arena.lawn / .carpet;
	# a map with no arena.carpet has no ring: the default [1, 1] ellipse never matches)
	var ellipse_inner: float = (x * x) / _lawn_rx2 + (z * z) / _lawn_rz2
	var ellipse_outer: float = (x * x) / _carpet_rx2 + (z * z) / _carpet_rz2
	if ellipse_inner > 0.96 and ellipse_outer < 1.04:
		return -999.0

	# 6. Main continuous lawn and meadow ground height
	var island_y: float = 0.0
	var map := get_parent() as MapDefinition if is_inside_tree() else null
	if map:
		island_y = map.ground_y
	if ellipse_inner <= 1.0:
		return island_y + 0.05
	return island_y + 0.05 + (_terrain.height(x, z) if _terrain else 0.0)

# Removes wild tufts standing inside the map's newer zones (MapZones
# blocks_new_zone_tufts). Runs once after pass 2, before the outer pass
# appends its own (already new-zone-valid) tufts.
func _filter_new_zone_wild(transforms: Array[Transform3D], colors: PackedColorArray) -> void:
	for i in range(transforms.size() - 1, -1, -1):
		var p: Vector3 = transforms[i].origin
		if _zones.blocks_new_zone_tufts(p.x, p.z):
			transforms.remove_at(i)
			colors.remove_at(i)


# Removes tufts standing on a gate walkway (MapZones on_walkway, half-width + 0.4 m
# like the trail). Runs after ALL passes (stream-neutral: every draw already
# happened), so passes 1-2 keep their exact positions.
func _filter_walkway(transforms: Array[Transform3D], colors: PackedColorArray) -> void:
	if not _zones.has_method("on_walkway"):
		return
	for i in range(transforms.size() - 1, -1, -1):
		var p: Vector3 = transforms[i].origin
		if _zones.on_walkway(p.x, p.z, 0.4):
			transforms.remove_at(i)
			colors.remove_at(i)

# The lawn MultiMesh + material are rebuilt from scratch in _ready(), so they must
# never be stored in Landmark81Map.tscn (a serialized instance buffer costs ~800 KB
# of parse/load for a resource that is discarded on boot). Stripping STORAGE keeps
# the @tool editor preview working without re-bloating the scene file on save.
# The wild set needs no guard: it lives on an ownerless child that is never saved.
func _validate_property(property: Dictionary) -> void:
	if property.name == &"multimesh" or property.name == &"material_override":
		property.usage &= ~PROPERTY_USAGE_STORAGE

func _generate_diorama_carpet() -> void:
	_zones = MapZones.for_node(self)
	_terrain = TerrainHeightfield.for_node(self)
	var arena: Dictionary = _zones.data().get("arena", {})
	var lawn: Array = arena.get("lawn", [1.0, 1.0])
	var carpet: Array = arena.get("carpet", [1.0, 1.0])
	_lawn_rx2 = float(lawn[0]) * float(lawn[0])
	_lawn_rz2 = float(lawn[1]) * float(lawn[1])
	_carpet_rx2 = float(carpet[0]) * float(carpet[0])
	_carpet_rz2 = float(carpet[1]) * float(carpet[1])
	var grass_scene = load("res://assets/models/vegetation/grass_tuft_diorama.glb")
	if not grass_scene:
		return

	var inst = grass_scene.instantiate()
	var mesh_node = _find_mesh(inst)
	if not mesh_node or not mesh_node.mesh:
		return

	_lawn_material = null
	var tuft_mesh: Mesh = mesh_node.mesh
	inst.queue_free()

	var rng = RandomNumberGenerator.new()
	rng.seed = 42

	# The lawn and wild sets are split into TWO MultiMeshes so the play lawn can be
	# re-toned for daylight while the forest belt keeps its authored night tone. They
	# cannot share one MultiMesh: instance colors MULTIPLY the material albedo, so a
	# single albedo tween would drag the forest tufts along with the lawn.
	# Cost is one extra draw call (2 total, still far under the <50 budget); the
	# alternative - a hand-written PBR shader doing the split GPU-side - was measured
	# ~8% darker than StandardMaterial3D at night and could not hit pixel parity.
	# The RNG call order below is UNCHANGED from the single-pass version, so every
	# tuft keeps its exact original position, scale and rotation.
	var lawn_transforms: Array[Transform3D] = []
	var lawn_colors: PackedColorArray = PackedColorArray()
	var wild_transforms: Array[Transform3D] = []
	var wild_colors: PackedColorArray = PackedColorArray()

	# Pass 1: Concentrated Central Yard (|x| <= LAWN_HALF_EXTENT)
	for i in range(yard_grass_count):
		var x = rng.randf_range(-yard_half_extent, yard_half_extent)
		var z = rng.randf_range(-yard_half_extent, yard_half_extent)

		# Legacy zones: keeps the pass-1/2 draw stream (and the 320 lawn) bit-identical.
		var y = is_valid_grass_pos(x, z, false)
		if y <= -900.0:
			continue # Culled outright now, instead of parking a degenerate instance at y -999

		# Soft, charming meadow clover/grass clumps (natural, tactile scale)
		var s: float = rng.randf_range(0.85, 1.35)
		var rot_y: float = rng.randf_range(0.0, TAU)
		var t = Transform3D()
		t = t.scaled(Vector3(s, s * rng.randf_range(0.8, 1.15), s))
		t = t.rotated(Vector3.UP, rot_y)
		t.origin = Vector3(x, y, z)
		lawn_transforms.append(t)

		var col_roll = rng.randf()
		if col_roll < 0.12:
			lawn_colors.append(Color(1.30, 1.22, 0.60, 1.0)) # delicate sunny buttercup highlight
		elif col_roll < 0.28:
			lawn_colors.append(Color(1.10, 1.20, 0.90, 1.0)) # soft warm clover highlight
		elif col_roll < 0.42:
			lawn_colors.append(Color(0.88, 1.05, 0.85, 1.0)) # gentle minty meadow tone
		else:
			lawn_colors.append(Color(1.0, 1.0, 1.0, 1.0))

	# Pass 2: Outer Forest and Meadow Belt across the 112m island
	for i in range(wild_grass_count):
		var x = rng.randf_range(-wild_half_extent, wild_half_extent)
		var z = rng.randf_range(-wild_half_extent, wild_half_extent)

		# Legacy zones here too (same stream reason); new-zone wild tufts are filtered below.
		var y = is_valid_grass_pos(x, z, false)
		if y <= -900.0:
			continue

		var is_lawn = (absf(x) <= LAWN_HALF_EXTENT and absf(z) <= LAWN_HALF_EXTENT)
		var s: float = rng.randf_range(0.85, 1.35) if is_lawn else rng.randf_range(1.2, 1.8)

		var rot_y: float = rng.randf_range(0.0, TAU)
		var t = Transform3D()
		t = t.scaled(Vector3(s, s * rng.randf_range(0.8, 1.15), s))
		t = t.rotated(Vector3.UP, rot_y)
		t.origin = Vector3(x, y, z)

		if is_lawn:
			lawn_transforms.append(t)
			lawn_colors.append(Color(1.0, 1.0, 1.0, 1.0))
		else:
			# Deep dark shadowed forest grass blending into the dark forest floor
			var dist = maxf(absf(x), absf(z))
			var forest_depth = clampf((dist - 24.0) / 28.0, 0.0, 1.0)
			var grass_darkness = lerpf(0.52, 0.20, forest_depth)
			wild_transforms.append(t)
			wild_colors.append(Color(grass_darkness * 0.85, grass_darkness * 1.05, grass_darkness * 0.82, 1.0))

	# Enforce the new zones on the pass-1/2 wild set by removal (stream-neutral:
	# the draws already happened). The lawn set is untouched: no new zone reaches
	# inside |x|, |z| <= 24, so every lawn tuft stands exactly where Phase 1 put it.
	_filter_new_zone_wild(wild_transforms, wild_colors)
	# Walkways are filtered after pass 3 instead (both sets, stream-neutral).

	# Pass 3: Phase-1 outer parkland (x +/-118, z -108..22). Never lands inside
	# the play square (that would move lawn tufts into the wild set), and always
	# joins the wild set so the lawn count is unchanged by construction.
	for i in range(outer_grass_count):
		var x = rng.randf_range(outer_x_range.x, outer_x_range.y)
		var z = rng.randf_range(outer_z_range.x, outer_z_range.y)
		if absf(x) <= LAWN_HALF_EXTENT and absf(z) <= LAWN_HALF_EXTENT:
			continue

		var y = is_valid_grass_pos(x, z)
		if y <= -900.0:
			continue

		var s: float = rng.randf_range(1.2, 1.8)
		var rot_y: float = rng.randf_range(0.0, TAU)
		var t = Transform3D()
		t = t.scaled(Vector3(s, s * rng.randf_range(0.8, 1.15), s))
		t = t.rotated(Vector3.UP, rot_y)
		t.origin = Vector3(x, y, z)

		# Deep dark shadowed forest grass blending into the dark forest floor
		var dist = maxf(absf(x), absf(z))
		var forest_depth = clampf((dist - 24.0) / 28.0, 0.0, 1.0)
		var grass_darkness = lerpf(0.52, 0.20, forest_depth)
		wild_transforms.append(t)
		wild_colors.append(Color(grass_darkness * 0.85, grass_darkness * 1.05, grass_darkness * 0.82, 1.0))

	_filter_walkway(lawn_transforms, lawn_colors)
	_filter_walkway(wild_transforms, wild_colors)

	# --- Lawn set: this node. Its material is the one DayNightCycle re-tones. ---
	_lawn_material = _duplicate_tuft_material(tuft_mesh)
	material_override = _lawn_material
	multimesh = _build_multimesh(tuft_mesh, lawn_transforms, lawn_colors)
	set_day_blend(_day_blend) # Re-seed the live phase after a rebuild

	# --- Wild set: a child node with its own, never-re-toned material. ---
	var wild := get_node_or_null(WILD_NODE_NAME) as MultiMeshInstance3D
	if not wild:
		wild = MultiMeshInstance3D.new()
		wild.name = WILD_NODE_NAME
		add_child(wild)
	wild.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wild.material_override = _duplicate_tuft_material(tuft_mesh)
	wild.multimesh = _build_multimesh(tuft_mesh, wild_transforms, wild_colors)

	if not Engine.is_editor_hint():
		print("✓ GrassMultiMesh: Populated expanded diorama island with %d zoned grass tufts (lawn: %d, wild: %d) in 2 draw calls!" % [
			lawn_transforms.size() + wild_transforms.size(), lawn_transforms.size(), wild_transforms.size()])

func _build_multimesh(mesh: Mesh, transforms: Array[Transform3D], colors: PackedColorArray) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	return mm

# A duplicate of the imported .glb material per set. Duplicating (rather than the old
# _setup_materials(), which mutated `mesh.surface_get_material(i)` in place) keeps the
# shared imported resource untouched, and lets the lawn set carry a tweened albedo while
# the wild set keeps the authored one. Note this node IS the MultiMeshInstance3D, which
# has no set_surface_override_material (that is a MeshInstance3D API), so the hook is
# material_override.
func _duplicate_tuft_material(mesh: Mesh) -> StandardMaterial3D:
	var src := mesh.surface_get_material(0) as StandardMaterial3D
	if not src:
		return null
	var mat := src.duplicate() as StandardMaterial3D
	# The glTF importer leaves this false, so MultiMesh instance colors are ignored without it.
	mat.vertex_color_use_as_albedo = true
	return mat

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var res = _find_mesh(child)
		if res:
			return res
	return null
