@tool
class_name PropMultiMesh
extends Node3D

# Batches a .glb prop into one MultiMeshInstance3D per mesh node of the imported
# .glb, which keeps the importer's LODs; merge per material at export with
# `mergeByMaterial` (tools/asset_generator/common.mjs). N placed instances cost
# (mesh nodes) draw calls instead of (instances x mesh surfaces).
#
# Two modes, chosen by `source_root`:
#   1. `source_root` set  - bake every descendant instance whose `scene_file_path`
#      equals `scene_path`, then free it. This replaces the hand-placed
#      lanterns / towers / villas in Landmark81Map.tscn WITHOUT retyping their
#      transforms, so Phase 0 is pixel-identical by construction. Authored
#      OmniLight3D children (the `Light` nodes under LanternN) are reparented
#      here first so DayNightCycle still finds them.
#   2. `source_root` empty - instance `scene_path` at `positions[i]`, yaw
#      `yaws_degrees[i]` (degrees, optional) and `scales[i]` (optional).
#      Yaw is a plain float here on purpose: hand-written Transform3D text in a
#      .tscn is ambiguous about basis row/column order and silently flips yaw.
#
# **use mode 2 for all new content**; mode 1 exists only for the Phase 0 scene instances.
# `zone_lots` appends world-space lots from the map's `lots()` (src/maps/MapZones.gd) in either mode (villas, the
# Marina Club fleet, the northern skyline and the promenade/trail lamps;
# `data/maps/landmark_81/zones/` is the single source). A lot's scale is a float or a Vector3.
#
# Engine.is_editor_hint() does nothing: the editor shows the authored source
# nodes, which already look correct, and baking would delete them on save.

@export var scene_path: String = ""
@export var source_root: NodePath = ^""
@export var positions: Array[Vector3] = []
@export var yaws_degrees: Array[float] = []
@export var scales: Array[Vector3] = []
@export var zone_lots: String = "" # the map's lots() key (src/maps/MapZones.gd); world-space lots appended in either mode
@export var enabled: bool = true

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if Engine.is_editor_hint():
		return
	for child in get_children():
		# Lights reparented out of a baked source instance stay put across rebuilds.
		if child is Light3D:
			continue
		child.free()
	if not enabled or scene_path.is_empty():
		return

	var template := load(scene_path) as PackedScene
	if template == null:
		push_warning("PropMultiMesh(%s): cannot load '%s'" % [name, scene_path])
		return
	var tmpl := template.instantiate()
	var items := collect_meshes(tmpl)
	tmpl.free()

	var instants := _instance_transforms()
	if instants.is_empty():
		push_warning("PropMultiMesh(%s): no instances for '%s'" % [name, scene_path])
		return
	if items.is_empty():
		push_warning("PropMultiMesh(%s): no meshes in '%s'" % [name, scene_path])
		return

	var base := scene_path.get_file().get_basename()
	for item in items:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%s" % [base, item["name"]]
		# Invariant 4: props batch ground-level decoration (houses, cafes, lamps,
		# people, skyline). Never cast: the owning map also runs set_shadows_off,
		# but _ready order (children first) makes that ordering-fragile alone.
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = item["mesh"]
		mm.instance_count = instants.size()
		for i in instants.size():
			mm.set_instance_transform(i, instants[i] * (item["xf"] as Transform3D))
		mmi.multimesh = mm
		add_child(mmi)

func _instance_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if not source_root.is_empty():
		var root := get_node_or_null(source_root)
		if root == null:
			push_warning("PropMultiMesh(%s): source_root '%s' not found" % [name, str(source_root)])
			return out
		var found: Array[Node] = []
		_find_instances(root, found)
		var inv := global_transform.affine_inverse()
		for n in found:
			out.append(inv * (n as Node3D).global_transform)
		# _ready() runs while the parent is still building its child list, so any
		# tree mutation must be deferred: free() would assert, and a queued free
		# lands in the same message queue after the queued reparents.
		for n in found:
			for c in n.get_children():
				if c is Light3D:
					c.reparent.call_deferred(self, true)
			n.queue_free()

	for i in positions.size():
		var s := Vector3.ONE
		if i < scales.size() and scales[i] != Vector3.ZERO:
			s = scales[i]
		var yaw := 0.0
		if i < yaws_degrees.size():
			yaw = deg_to_rad(yaws_degrees[i])
		out.append(Transform3D(Basis(Vector3.UP, yaw).scaled(s), positions[i]))
	# World-space lots from the map's zone script (MapZones contract), in either mode.
	if not zone_lots.is_empty():
		var lot_inv := global_transform.affine_inverse()
		for lot in MapZones.for_node(self).lots(zone_lots):
			# `scale` is a float, or a Vector3 for y-only stretches (skyline towers).
			var sc: Variant = lot["scale"]
			var sv: Vector3 = sc if sc is Vector3 else Vector3.ONE * float(sc)
			var b := Basis(Vector3.UP, deg_to_rad(float(lot["yaw"]))).scaled(sv)
			out.append(lot_inv * Transform3D(b, lot["pos"]))

	# Apply diorama stepped terrace elevation so props sit on terrace floors
	var terrain := TerrainHeightfield.for_node(self)
	for i in out.size():
		if terrain == null:
			break
		var world_pos: Vector3 = global_transform * out[i].origin
		var th: float = terrain.height(world_pos.x, world_pos.z)
		if th > 0.0:
			out[i].origin.y += th

	return out

# Adds an instance node and stops descending into it, so a nested .glb instance
# is never baked twice.
func _find_instances(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child.scene_file_path == scene_path:
			out.append(child)
		else:
			_find_instances(child, out)

# One entry per MeshInstance3D under `root`, carrying the IMPORTED mesh (so its LOD
# chain survives) and the node's transform relative to `root`.
static func collect_meshes(root: Node, parent_xf: Transform3D = Transform3D()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var xf := parent_xf
	if root is Node3D:
		xf = parent_xf * (root as Node3D).transform
	var mi := root as MeshInstance3D
	if mi != null and mi.mesh:
		out.append({"mesh": mi.mesh, "xf": xf, "name": String(mi.name)})
	for child in root.get_children():
		out.append_array(collect_meshes(child, xf))
	return out
