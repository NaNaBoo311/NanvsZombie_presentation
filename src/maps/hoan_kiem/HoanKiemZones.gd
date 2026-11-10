@tool
class_name HoanKiemZones
extends RefCounted

# Runtime reader of data/maps/hoan_kiem/zones/ (one <zone>.json per zone, the single
# source of truth for the Hoan Kiem Lake footprints; the island generator
# tools/asset_generator/generators/maps/hoan_kiem/ bakes its geometry from the same
# files). This is the map's zone script (MapDefinition.zones_path): it provides the
# static queries listed in src/maps/MapZones.gd, every answer computed from those
# files, never from typed-in numbers. The lake and the turtle island are signed
# distance fields (metres, negative inside): smooth unions of the ellipse lobes in
# lake.json and arena.json. The map has no gate walkways, so on_walkway is always false.
# CONTRACT(lake-shape): _ellipse_sd and _smin match lake_shape.mjs (the generator) and
# PondWater.gdshader term for term.

const ZONES_DIR := "res://data/maps/hoan_kiem/zones"

static var _cache: Dictionary = {}
static var _loaded: bool = false
static var _lake_lobes: PackedVector4Array = PackedVector4Array()
static var _lake_blend: float = 0.0
static var _turtle_lobes: PackedVector4Array = PackedVector4Array()
static var _turtle_blend: float = 0.0


static func data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	var files := DirAccess.get_files_at(ZONES_DIR)
	if files.is_empty():
		push_error("HoanKiemZones: no zone files in %s." % ZONES_DIR)
		return {}
	files.sort()
	for file in files:
		if not file.ends_with(".json"):
			continue
		var path := ZONES_DIR.path_join(file)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null:
			push_error("HoanKiemZones: failed to parse %s." % path)
			continue
		_cache[file.get_basename()] = parsed
	var lake: Dictionary = _cache.get("lake", {})
	_lake_lobes = lobes_of(lake.get("lobes", []))
	_lake_blend = float(lake.get("blend", 0.0))
	var island: Dictionary = (_cache.get("arena", {}) as Dictionary).get("island", {})
	_turtle_lobes = lobes_of(island.get("lobes", []))
	_turtle_blend = float(island.get("blend", 0.0))
	return _cache


## JSON lobes [[cx, cz, rx, rz], ...] as Vector4s (also what PondWater.gdshader takes).
static func lobes_of(list: Array) -> PackedVector4Array:
	var out := PackedVector4Array()
	for l in list:
		out.append(Vector4(float(l[0]), float(l[1]), float(l[2]), float(l[3])))
	return out


## Approximate signed distance to an axis-aligned ellipse; near-exact near the outline.
static func _ellipse_sd(px: float, pz: float, rx: float, rz: float) -> float:
	var k0 := Vector2(px / rx, pz / rz).length()
	var k1 := Vector2(px / (rx * rx), pz / (rz * rz)).length()
	if k1 < 1e-6:
		return -minf(rx, rz)
	return k0 * (k0 - 1.0) / k1


## Polynomial smooth minimum over `k` metres.
static func _smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return b + (a - b) * h - k * h * (1.0 - h)


static func _lobes_sd(lobes: PackedVector4Array, blend: float, x: float, z: float) -> float:
	if lobes.is_empty():
		return INF
	var d := _ellipse_sd(x - lobes[0].x, z - lobes[0].y, lobes[0].z, lobes[0].w)
	for i in range(1, lobes.size()):
		var l := lobes[i]
		d = _smin(d, _ellipse_sd(x - l.x, z - l.y, l.z, l.w), blend)
	return d


## Signed distance to the lake shore (negative over water, the islands included).
static func lake_sd(x: float, z: float) -> float:
	data()
	return _lobes_sd(_lake_lobes, _lake_blend, x, z)


## Signed distance to the turtle island's bank (negative on the island).
static func turtle_sd(x: float, z: float) -> float:
	data()
	return _lobes_sd(_turtle_lobes, _turtle_blend, x, z)


## True inside an ellipse given as JSON center [x, z] and radii [rx, rz] (plus pad).
static func _in_ellipse(x: float, z: float, center: Array, r: Array, pad: float = 0.0) -> bool:
	var dx := (x - float(center[0])) / (float(r[0]) + pad)
	var dz := (z - float(center[1])) / (float(r[1]) + pad)
	return dx * dx + dz * dz < 1.0


static func _on_islet(x: float, z: float, pad: float = 0.0) -> bool:
	for islet in (data().get("islets", {}) as Dictionary).values():
		if islet is Dictionary and (islet as Dictionary).has("center") and _in_ellipse(x, z, islet["center"], islet["r"], pad):
			return true
	return false


## The turtle island in the middle of the lake, out to its bank (zones/arena.json).
static func _on_lawn_island(x: float, z: float, pad: float = 0.0) -> bool:
	return turtle_sd(x, z) < pad


## Lake water: inside the basin, off the lawn island and the islets.
static func is_in_water(x: float, z: float) -> bool:
	return _in_basin(x, z) and not _on_lawn_island(x, z) and not _on_islet(x, z)


## Inside the lake basin (the water, the lawn island and the islets).
static func _in_basin(x: float, z: float, pad: float = 0.0) -> bool:
	return lake_sd(x, z) < pad


## On the embankment or the promenade ring around the basin.
static func _on_promenade(x: float, z: float) -> bool:
	var lake: Dictionary = data().get("lake", {})
	if lake.is_empty():
		return false
	var outer := float(lake.get("embankment_w", 0.0)) + float(lake.get("promenade_w", 0.0)) + 0.3
	return _in_basin(x, z, outer) and not _in_basin(x, z)


## On the street ring or its sidewalks (zones/streets.json).
static func _on_street(x: float, z: float) -> bool:
	var st: Dictionary = data().get("streets", {})
	if st.is_empty():
		return false
	var o: Array = st["outer"]
	var w := float(st["width"])
	var walk := float(st.get("sidewalk", 0.0))
	var outside_inner := x < float(o[0]) + w + walk * 0.6 or x > float(o[2]) - w - walk * 0.6 \
		or z < float(o[1]) + w + walk * 0.6 or z > float(o[3]) - w - walk * 0.6
	var inside_outer := x > float(o[0]) - walk and x < float(o[2]) + walk \
		and z > float(o[1]) - walk and z < float(o[3]) + walk
	return outside_inner and inside_outer


## On the squares, the temple path or Doc Ton hill (zones/landmarks.json).
static func _on_paving(x: float, z: float) -> bool:
	var lm: Dictionary = data().get("landmarks", {})
	for key in ["ly_thai_to_garden", "post_office", "dong_kinh_square"]:
		var r: Array = (lm.get(key, {}) as Dictionary).get("rect", [])
		if r.size() == 4 and x > float(r[0]) and x < float(r[2]) and z > float(r[1]) and z < float(r[3]):
			return true
	var tp: Dictionary = lm.get("temple_path", {})
	if not tp.is_empty() and x > float(tp["from"][0]) and x < float(tp["to"][0]) \
			and absf(z - float(tp["from"][1])) < float(tp["width"]) * 0.5 + 0.3:
		return true
	var hill: Dictionary = lm.get("doc_ton_hill", {})
	return not hill.is_empty() and Vector2(x - float(hill["pos"][0]), z - float(hill["pos"][2])).length() < float(hill["r"]) + 0.3


## Trees are scattered only on the grass between the promenade and the streets.
static func blocks_trees(x: float, z: float) -> bool:
	return _in_basin(x, z, 0.0) or _on_promenade(x, z) or _on_street(x, z) or _on_paving(x, z)


## Grass tufts stay off the water and islets, paving, streets and the island's edge.
static func blocks_tufts(x: float, z: float, _legacy_pass: bool) -> bool:
	var island: Array = (data().get("island", {}) as Dictionary).get("rect", [])
	if island.size() == 4 and (x < float(island[0]) + 0.5 or x > float(island[2]) - 0.5 \
			or z < float(island[1]) + 0.5 or z > float(island[3]) - 0.5):
		return true
	if _on_promenade(x, z) or _on_street(x, z) or _on_paving(x, z):
		return true
	return _in_basin(x, z, 0.3) and not _on_lawn_island(x, z, -0.3)


static func blocks_new_zone_tufts(_x: float, _z: float) -> bool:
	return false


static func on_walkway(_x: float, _z: float, _margin: float = 0.0) -> bool:
	return false


# World-space instance lots for PropMultiMesh.zone_lots: [{pos: Vector3, yaw: float (deg), scale: float}].
static func lots(key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := data()
	match key:
		"shophouses":
			out = _shophouse_lots()
		"shophouses_a", "shophouses_b":
			# The two tube-house block variants alternate along every row.
			var all := _shophouse_lots()
			for i in range(0 if key == "shophouses_a" else 1, all.size(), 2):
				out.append(all[i])
		"cafes":
			# A sidewalk cafe in front of every tube-house block, cafe_out metres out.
			var out_m := float((d.get("shophouses", {}) as Dictionary).get("cafe_out", 2.4))
			for h in _shophouse_lots():
				var yaw := deg_to_rad(float(h["yaw"]))
				var front := Vector3(sin(yaw), 0.0, cos(yaw))
				out.append({"pos": (h["pos"] as Vector3) + front * out_m + Vector3(0.0, 0.07, 0.0), "yaw": float(h["yaw"]), "scale": 1.0})
		"people":
			# Lakeside life on the promenade: a group of locals in front of every fifth
			# lamp, 2.5 m toward the water (lamps face the lake).
			var lamps: Array = (d.get("lamps", {}) as Dictionary).get("pos", [])
			for i in range(2, lamps.size(), 5):
				var p: Array = lamps[i]
				var yaw := deg_to_rad(float(p[2]))
				out.append({"pos": Vector3(float(p[0]) + sin(yaw) * 2.5, 0.055, float(p[1]) + cos(yaw) * 2.5), "yaw": float(p[2]) + 180.0, "scale": 1.0})
		"lamps":
			for p in (d.get("lamps", {}) as Dictionary).get("pos", []):
				out.append({"pos": Vector3(float(p[0]), 0.055, float(p[1])), "yaw": float(p[2]), "scale": 1.0})
		_:
			push_error("HoanKiemZones.lots: unknown key '%s'" % key)
	return out


static func _shophouse_lots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in (data().get("shophouses", {}) as Dictionary).get("rows", []):
		var a := Vector2(float(row["from"][0]), float(row["from"][1]))
		var b := Vector2(float(row["to"][0]), float(row["to"][1]))
		var step := float(row["step"])
		var count := int(floor(a.distance_to(b) / step)) + 1
		for i in count:
			var p := a + (b - a).normalized() * step * i
			out.append({"pos": Vector3(p.x, 0.0, p.y), "yaw": float(row["yaw"]), "scale": 1.0})
	return out


## Landmark placement (zones/landmarks.json) for HoanKiemMap.gd: {pos: Vector3, yaw: float (deg)}.
## The bridge stands at the midpoint of its from/to feet, its local X along the deck.
static func landmark_transform(key: String) -> Dictionary:
	var lm: Dictionary = (data().get("landmarks", {}) as Dictionary).get(key, {})
	if lm.is_empty():
		return {}
	if lm.has("from"):
		var a := Vector2(float(lm["from"][0]), float(lm["from"][1]))
		var b := Vector2(float(lm["to"][0]), float(lm["to"][1]))
		var mid := (a + b) * 0.5
		return {"pos": Vector3(mid.x, 0.0, mid.y), "yaw": rad_to_deg(atan2(-(b.y - a.y), b.x - a.x))}
	return {"pos": Vector3(float(lm["pos"][0]), float(lm["pos"][1]), float(lm["pos"][2])), "yaw": float(lm.get("yaw", 0.0))}
