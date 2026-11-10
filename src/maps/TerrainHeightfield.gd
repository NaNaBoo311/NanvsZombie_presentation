@tool
class_name TerrainHeightfield
extends RefCounted

# Runtime terrain height for a map: samples the vertex grid the terrain generator
# exported next to the mesh (MapDefinition.terrain_path, e.g. data/maps/landmark_81/terrain.json
# from park_topography.mjs). Each grid cell is split along the same diagonal as the
# generated mesh, so height() is exactly the rendered ground, and the terrain shape
# has one source: the generator. Outside the grid it returns 0. @tool because the
# batching scripts (ForestMultiMesh is @tool) also place instances in the editor.

static var _cache: Dictionary = {} # path -> TerrainHeightfield

var _x0: float
var _z0: float
var _inv_dx: float
var _inv_dz: float
var _nx: int
var _cells_x: int
var _cells_z: int
var _h: PackedFloat32Array


## The heightfield at `path`, loaded once per path; null (with an error) if unreadable.
static func load_path(path: String) -> TerrainHeightfield:
	if _cache.has(path):
		return _cache[path]
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		push_error("TerrainHeightfield: cannot read %s - regenerate the map's island model (npm run generate -- maps/<map_id>/...)" % path)
		_cache[path] = null
		return null
	var field := TerrainHeightfield.new()
	field._x0 = float(data["x0"])
	field._z0 = float(data["z0"])
	field._inv_dx = 1.0 / float(data["dx"])
	field._inv_dz = 1.0 / float(data["dz"])
	field._nx = int(data["nx"])
	field._cells_x = field._nx - 1
	field._cells_z = int(data["nz"]) - 1
	field._h = PackedFloat32Array(data["heights"])
	_cache[path] = field
	return field


## The terrain of the map `node` belongs to (the nearest ancestor with a non-empty
## `terrain_path`), or null for a flat map. Reads the exported property rather than
## calling MapDefinition, so it also works in the editor.
static func for_node(node: Node) -> TerrainHeightfield:
	var n := node
	while n:
		var p: Variant = n.get("terrain_path")
		if p is String and not (p as String).is_empty():
			return load_path(p)
		n = n.get_parent()
	return null


func height(x: float, z: float) -> float:
	var u := (x - _x0) * _inv_dx
	var v := (z - _z0) * _inv_dz
	if u < 0.0 or v < 0.0 or u > _cells_x or v > _cells_z:
		return 0.0
	var i := mini(int(u), _cells_x - 1)
	var j := mini(int(v), _cells_z - 1)
	var fu := u - i
	var fv := v - j
	var a := _h[j * _nx + i]
	var b := _h[j * _nx + i + 1]
	var c := _h[(j + 1) * _nx + i]
	if fu + fv <= 1.0:
		return a + (b - a) * fu + (c - a) * fv
	var d := _h[(j + 1) * _nx + i + 1]
	return d + (c - d) * (1.0 - fu) + (b - d) * (1.0 - fv)
