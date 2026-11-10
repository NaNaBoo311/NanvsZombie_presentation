class_name AtlasProvinces
extends RefCounted

# AtlasProvinces — the atlas menu's runtime province outlines, loaded once from
# data/atlas_provinces.json (written by vietnam_world_atlas.mjs; world XZ metres,
# north = -Z). Province index = the UV2.x id baked into the atlas meshes.
# pick() answers "which province is under this ray": it intersects the ray with
# each province's own plate top (taller pieces win), rejects by precomputed
# AABB, then point-in-polygon over the outline parts (islets included; holes
# honoured). Pure data + math: no nodes, no per-frame work.

const DATA_PATH := "res://data/atlas_provinces.json"

var locked_top: float = 0.28
var unlocked_top: float = 0.40
var tray := Rect2()
var ids := PackedStringArray()
var names := PackedStringArray()
var labels := PackedVector2Array()
var _parts: Array = [] # per province: Array of parts; part = Array[PackedVector2Array] (outer, holes...)
var _aabbs: Array[Rect2] = []
var _index_by_id: Dictionary = {}


static func load_default() -> AtlasProvinces:
	var atlas := AtlasProvinces.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	if not (parsed is Dictionary):
		push_error("[AtlasProvinces] Missing or unparseable %s (run npm run generate -- environment/vietnam_world_atlas)." % DATA_PATH)
		return atlas
	var data := parsed as Dictionary
	atlas.locked_top = float(data.get("locked_top", 0.28))
	atlas.unlocked_top = float(data.get("unlocked_top", 0.40))
	var t: Dictionary = data.get("tray", {})
	atlas.tray = Rect2(float(t.get("min_x", 0)), float(t.get("min_z", 0)),
		float(t.get("max_x", 0)) - float(t.get("min_x", 0)), float(t.get("max_z", 0)) - float(t.get("min_z", 0)))
	var provinces: Array = data.get("provinces", [])
	provinces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]))
	for p in provinces:
		var parts: Array = []
		var box := Rect2()
		var first := true
		for part in p.get("parts", []):
			var rings: Array[PackedVector2Array] = []
			for ring in part:
				var pts := PackedVector2Array()
				for xz in ring:
					pts.append(Vector2(float(xz[0]), float(xz[1])))
				rings.append(pts)
			if rings.is_empty():
				continue
			parts.append(rings)
			for v in rings[0]:
				if first:
					box = Rect2(v, Vector2.ZERO)
					first = false
				else:
					box = box.expand(v)
		atlas._index_by_id[str(p["id"])] = atlas.ids.size()
		atlas.ids.append(str(p["id"]))
		atlas.names.append(str(p.get("name", p["id"])))
		var lab: Array = p.get("label", [0, 0])
		atlas.labels.append(Vector2(float(lab[0]), float(lab[1])))
		atlas._parts.append(parts)
		atlas._aabbs.append(box)
	return atlas


func count() -> int:
	return ids.size()


func index_of(province_id: String) -> int:
	return int(_index_by_id.get(province_id, -1))


## Outline bounds of a province (world XZ), e.g. for camera framing.
func bounds(index: int) -> Rect2:
	return _aabbs[index]


## Bounds of the province's largest piece only (parts are stored largest first,
## islets last), so framing ignores far islands like Côn Đảo.
func main_bounds(index: int) -> Rect2:
	var box := Rect2()
	var first := true
	if _parts[index].is_empty():
		return box
	for v in _parts[index][0][0]:
		if first:
			box = Rect2(v, Vector2.ZERO)
			first = false
		else:
			box = box.expand(v)
	return box


func contains(index: int, p: Vector2) -> bool:
	var box: Rect2 = _aabbs[index]
	if p.x < box.position.x or p.y < box.position.y or p.x > box.end.x or p.y > box.end.y:
		return false
	for part in _parts[index]:
		if not Geometry2D.is_point_in_polygon(p, part[0]):
			continue
		var in_hole := false
		for h in range(1, part.size()):
			if Geometry2D.is_point_in_polygon(p, part[h]):
				in_hole = true
				break
		if not in_hole:
			return true
	return false


## Province index under the ray, or -1. tops[i] = plate top height of province i;
## a taller piece wins where pieces overlap in screen space.
func pick(origin: Vector3, dir: Vector3, tops: PackedFloat32Array) -> int:
	if absf(dir.y) < 1e-5:
		return -1
	var best := -1
	var best_top := -INF
	for i in count():
		var t := (tops[i] - origin.y) / dir.y
		if t < 0.0 or tops[i] <= best_top:
			continue
		var hit := origin + dir * t
		if contains(i, Vector2(hit.x, hit.z)):
			best = i
			best_top = tops[i]
	return best
