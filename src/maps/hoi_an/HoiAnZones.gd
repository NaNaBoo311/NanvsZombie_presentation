@tool
class_name HoiAnZones
extends RefCounted

# Runtime reader of data/maps/hoi_an/zones/ (one <zone>.json per zone, the single source
# of truth for the Hoi An Ancient Town footprints; the generators in
# tools/asset_generator/generators/maps/hoi_an/ bake their geometry from the same files).
# This is the map's zone script (MapDefinition.zones_path): it provides the static
# queries listed in src/maps/MapZones.gd, every answer computed from those files, never
# from typed-in numbers. The Thu Bon river is the band between river.json's banks across
# the whole island, plus the creek under the Japanese Covered Bridge. Grass grows only on
# the lawn turf and the gardens: never on streets, paving, house lots or the landmarks.
# The map has no gate walkways, so on_walkway is always false.

const ZONES_DIR := "res://data/maps/hoi_an/zones"

static var _cache: Dictionary = {}
static var _loaded: bool = false
# Shophouse block footprints as Rect2 (x, z, w, d), and their lots, built once.
static var _house_rects: Array[Rect2] = []
static var _house_lots: Array[Dictionary] = []


static func data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	var files := DirAccess.get_files_at(ZONES_DIR)
	if files.is_empty():
		push_error("HoiAnZones: no zone files in %s." % ZONES_DIR)
		return {}
	files.sort()
	for file in files:
		if not file.ends_with(".json"):
			continue
		var path := ZONES_DIR.path_join(file)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null:
			push_error("HoiAnZones: failed to parse %s." % path)
			continue
		_cache[file.get_basename()] = parsed
	_build_houses()
	return _cache


static func _rect(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]) - float(a[0]), float(a[3]) - float(a[1]))


static func _in(r: Array, x: float, z: float, pad: float = 0.0) -> bool:
	return r.size() == 4 and x > float(r[0]) - pad and x < float(r[2]) + pad and z > float(r[1]) - pad and z < float(r[3]) + pad


# Expands zones/shophouses.json rows into lots (block origin on the facade line) and
# footprints (the block runs `depth` metres back from its facade, away from the street).
static func _build_houses() -> void:
	_house_rects.clear()
	_house_lots.clear()
	var sh: Dictionary = _cache.get("shophouses", {})
	var depth := float(sh.get("depth", 12.0))
	var width := float(sh.get("width", 20.0))
	for row: Dictionary in sh.get("rows", []):
		var a := Vector2(float(row["from"][0]), float(row["from"][1]))
		var b := Vector2(float(row["to"][0]), float(row["to"][1]))
		var step := float(row["step"])
		var count := int(floor(a.distance_to(b) / step + 0.001)) + 1
		var yaw := float(row["yaw"])
		var dir := (b - a).normalized() if a.distance_to(b) > 0.001 else Vector2.ZERO
		for i in count:
			var p := a + dir * step * i
			_house_lots.append({"pos": Vector3(p.x, 0.0, p.y), "yaw": yaw, "scale": 1.0})
			# yaw 0 faces +Z, so the body runs to -Z; yaw 180 the other way.
			var z0 := p.y - depth if absf(yaw) < 90.0 else p.y
			_house_rects.append(Rect2(p.x - width * 0.5, z0, width, depth))


## In the Thu Bon river (between its embankments) or the creek.
static func is_in_water(x: float, z: float) -> bool:
	var rv: Dictionary = data().get("river", {})
	if rv.is_empty():
		return false
	if z > float(rv["north_bank_z"]) and z < float(rv["south_bank_z"]):
		return true
	var creek: Dictionary = rv.get("creek", {})
	return not creek.is_empty() and x > float(creek["x"][0]) and x < float(creek["x"][1]) \
		and z > float(creek["z"][0]) and z < float(rv["north_bank_z"])


## On a street, the riverfront, the An Hoi promenade or lane, or the square.
static func _on_paving(x: float, z: float, pad: float = 0.0) -> bool:
	var st: Dictionary = data().get("streets", {})
	for r in st.get("riverfront", []):
		if _in(r, x, z, pad):
			return true
	for s: Dictionary in st.get("streets", []):
		if _in(s["rect"], x, z, pad):
			return true
	if _in(st.get("an_hoi_promenade", []), x, z, pad) or _in(st.get("an_hoi_lane", []), x, z, pad):
		return true
	return _in((data().get("arena", {}) as Dictionary).get("plaza_rect", []), x, z, pad)


## On a shophouse lot or a landmark's footprint (temples, market).
static func _on_building(x: float, z: float, pad: float = 0.0) -> bool:
	data()
	for r in _house_rects:
		if r.grow(pad).has_point(Vector2(x, z)):
			return true
	var lm: Dictionary = data().get("landmarks", {})
	if _in((lm.get("central_market", {}) as Dictionary).get("rect", []), x, z, pad):
		return true
	for key in ["fujian_hall", "quan_cong_temple"]:
		var h: Dictionary = lm.get(key, {})
		if h.is_empty():
			continue
		var w := float(h["size"][0])
		var d := float(h["size"][1])
		var p: Array = h["pos"]
		if _in([float(p[0]) - w * 0.5, float(p[2]) - d, float(p[0]) + w * 0.5, float(p[2])], x, z, pad):
			return true
	return false


static func _on_turf(x: float, z: float, pad: float = 0.0) -> bool:
	return _in((data().get("arena", {}) as Dictionary).get("turf_rect", []), x, z, pad)


## Trees stand only on open ground: off the water, the paving and the buildings.
static func blocks_trees(x: float, z: float) -> bool:
	return is_in_water(x, z) or _on_paving(x, z) or _on_building(x, z, 0.5)


## Grass tufts grow on the lawn turf and in the gardens only.
static func blocks_tufts(x: float, z: float, _legacy_pass: bool) -> bool:
	if _on_turf(x, z, -0.3):
		return false
	var island: Array = (data().get("island", {}) as Dictionary).get("rect", [])
	if island.size() == 4 and not _in(island, x, z, -0.5):
		return true
	if is_in_water(x, z) or _on_paving(x, z, 0.3) or _on_building(x, z, 0.4):
		return true
	var rv: Dictionary = data().get("river", {})
	# The embankment kerbs.
	return absf(z - float(rv.get("north_bank_z", 0.0))) < 0.8 or absf(z - float(rv.get("south_bank_z", 0.0))) < 0.8


static func blocks_new_zone_tufts(_x: float, _z: float) -> bool:
	return false


static func on_walkway(_x: float, _z: float, _margin: float = 0.0) -> bool:
	return false


# World-space instance lots for PropMultiMesh.zone_lots: [{pos: Vector3, yaw: float (deg), scale: float}].
static func lots(key: String) -> Array[Dictionary]:
	data()
	var out: Array[Dictionary] = []
	match key:
		"shophouses":
			out.assign(_house_lots)
		"shophouses_a", "shophouses_b":
			# The two block variants alternate along every row.
			for i in range(0 if key == "shophouses_a" else 1, _house_lots.size(), 2):
				out.append(_house_lots[i])
		"food_stall", "shop_spill", "crowd":
			for lot in _clutter_lots():
				if lot["kind"] == key:
					out.append({"pos": lot["pos"], "yaw": lot["yaw"], "scale": 1.0})
		_:
			push_error("HoiAnZones.lots: unknown key '%s'" % key)
	return out


## The pavement life (zones/streets.json clutter) as [{kind, pos: Vector3, yaw}]: along
## both edges of each listed street, facing its centre, the kinds taking turns; none at
## a junction (within cross_margin of another street) or by the temple gates, the market
## or the Japanese Bridge; food stalls on the Bach Dang riverfront; crowds on the square.
static func _clutter_lots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var st: Dictionary = data().get("streets", {})
	var cfg: Dictionary = st.get("clutter", {})
	if cfg.is_empty():
		return out
	var kinds: Array = cfg["kinds"]
	var step := float(cfg["step"])
	var inset := float(cfg["inset"])
	var streets: Array = st.get("streets", [])
	var k := 0
	for street: Dictionary in streets:
		if not (cfg["streets"] as Array).has(street["name"]):
			continue
		var r: Array = street["rect"]
		var along_x: bool = street["axis"] == "x"
		var a := float(r[0]) if along_x else float(r[1])
		var b := float(r[2]) if along_x else float(r[3])
		for side in [0, 1]:
			# Side 0 is the low edge (north / west), facing +Z / +X; side 1 the high edge.
			var edge: float = (float(r[1]) + inset if side == 0 else float(r[3]) - inset) if along_x \
				else (float(r[0]) + inset if side == 0 else float(r[2]) - inset)
			var yaw: float = (0.0 if side == 0 else 180.0) if along_x else (90.0 if side == 0 else -90.0)
			var t: float = a + step * (0.5 + 0.5 * float(side))
			while t < b - 2.0:
				var pos := Vector3(t, 0.03, edge) if along_x else Vector3(edge, 0.03, t)
				if not _at_junction(pos, street, streets, float(cfg["cross_margin"])) \
						and not _near_landmark(pos.x, pos.z, float(cfg["landmark_margin"])):
					out.append({"kind": kinds[k % kinds.size()], "pos": pos, "yaw": yaw})
					k += 1
				t += step
	var rf: Dictionary = cfg["riverfront"]
	for span in rf["x"]:
		var x := float(span[0])
		while x <= float(span[1]):
			if not _near_landmark(x, float(rf["z"]), float(cfg["landmark_margin"])) and not is_in_water(x, float(rf["z"]) + 1.0):
				out.append({"kind": "food_stall", "pos": Vector3(x, 0.055, float(rf["z"])), "yaw": 0.0})
			x += float(rf["step"])
	for p in cfg["plaza"]:
		out.append({"kind": "crowd", "pos": Vector3(float(p[0]), 0.05, float(p[1])), "yaw": float(p[2])})
	return out


static func _at_junction(pos: Vector3, own: Dictionary, streets: Array, margin: float) -> bool:
	for street: Dictionary in streets:
		if street == own:
			continue
		if _in(street["rect"], pos.x, pos.z, margin):
			return true
	return false


## By a temple gate, the market, the Japanese Bridge or the An Hoi bridge foot.
static func _near_landmark(x: float, z: float, pad: float) -> bool:
	var lm: Dictionary = data().get("landmarks", {})
	for key in ["fujian_hall", "quan_cong_temple"]:
		var h: Dictionary = lm.get(key, {})
		if h.is_empty():
			continue
		var w := float(h["size"][0])
		var p: Array = h["pos"]
		if _in([float(p[0]) - w * 0.5, float(p[2]) - float(h["size"][1]), float(p[0]) + w * 0.5, float(p[2])], x, z, pad):
			return true
	var jb: Dictionary = lm.get("japanese_bridge", {})
	if not jb.is_empty() and absf(x - float(jb["pos"][0])) < float(jb["length"]) * 0.5 + pad and absf(z - float(jb["pos"][2])) < 4.0 + pad:
		return true
	var bridge: Dictionary = lm.get("an_hoi_bridge", {})
	if not bridge.is_empty() and absf(x - float(bridge["from"][0])) < float(bridge["width"]) * 0.5 + pad:
		return true
	return false


## Riverfront lantern posts (zones/river.json lantern_posts), lantern head positions,
## for the river's night reflections. Mirrors the post loop in old_town_landmarks.mjs.
static func lantern_post_heads() -> PackedVector3Array:
	var out := PackedVector3Array()
	var rv: Dictionary = data().get("river", {})
	var lm: Dictionary = data().get("landmarks", {})
	if rv.is_empty() or lm.is_empty():
		return out
	var lp: Dictionary = rv["lantern_posts"]
	var creek: Array = rv["creek"]["x"]
	var bridge: Dictionary = lm["an_hoi_bridge"]
	var bridge_x := float(bridge["from"][0])
	var x := float(lp["x"][0])
	while x <= float(lp["x"][1]) + 0.001:
		var on_creek := x > float(creek[0]) - 1.5 and x < float(creek[1]) + 1.5
		var on_bridge := absf(x - bridge_x) < float(bridge["width"]) * 0.5 + 1.5
		if not on_creek and not on_bridge:
			out.append(Vector3(x + 0.42, 0.055 + 3.2 - 0.55, float(lp["z"])))
		x += float(lp["step"])
	return out


## An Hoi night-market stall centres (zones/landmarks.json night_market), front lantern
## height, for the river's night reflections. Mirrors old_town_landmarks.mjs.
static func night_market_stalls() -> PackedVector3Array:
	var out := PackedVector3Array()
	var nm: Dictionary = (data().get("landmarks", {}) as Dictionary).get("night_market", {})
	if nm.is_empty():
		return out
	var x := float(nm["from"][0])
	while x <= float(nm["to"][0]) + 0.01:
		if not (x > float(nm["skip_x"][0]) and x < float(nm["skip_x"][1])):
			out.append(Vector3(x, 2.5, float(nm["from"][1]) - 1.25))
		x += float(nm["step"])
	return out


## The streets group with a street's approach / back override applied (range, energy).
static func _street_group(sg: Dictionary, street_name: String) -> Dictionary:
	for key in ["approach", "back"]:
		var o: Dictionary = sg.get(key, {})
		if (o.get("names", []) as Array).has(street_name):
			return {"range": o["range"], "energy": o["energy"], "color": sg["color"]}
	return sg


## The lantern light pools (zones/streets.json lantern_lights) as
## [{pos: Vector3, range: float, energy: float, color: Color}], from the street, post,
## stall and square layout, so the light always sits under the lanterns that cast it.
static func lantern_lights() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var st: Dictionary = data().get("streets", {})
	var cfg: Dictionary = st.get("lantern_lights", {})
	if cfg.is_empty():
		return out
	var add := func(group: Dictionary, pos: Vector3) -> void:
		out.append({"pos": pos, "range": float(group["range"]), "energy": float(group["energy"]),
			"color": Color.html(str(group["color"]))})
	# Streets: pools along each centre line, none on the Japanese Covered Bridge.
	var sg: Dictionary = cfg["streets"]
	var jb: Dictionary = (data().get("landmarks", {}) as Dictionary).get("japanese_bridge", {})
	for street: Dictionary in st.get("streets", []):
		var r: Array = street["rect"]
		var along_x: bool = street["axis"] == "x"
		var a := float(r[0]) if along_x else float(r[1])
		var b := float(r[2]) if along_x else float(r[3])
		var mid := (float(r[1]) + float(r[3])) * 0.5 if along_x else (float(r[0]) + float(r[2])) * 0.5
		var t := a + float(sg["step"]) * 0.5
		while t < b:
			var pos := Vector3(t, float(sg["height"]), mid) if along_x else Vector3(mid, float(sg["height"]), t)
			var on_bridge := not jb.is_empty() and absf(pos.x - float(jb["pos"][0])) < float(jb["length"]) * 0.5 + 1.0 \
				and absf(pos.z - float(jb["pos"][2])) < 4.0
			if not on_bridge:
				add.call(_street_group(sg, str(street["name"])), pos)
			t += float(sg["step"])
	# Bach Dang: every other post, but every post in front of the square, brighter.
	var rf: Dictionary = cfg["riverfront"]
	var near := {"range": rf["near_range"], "energy": rf["near_energy"], "color": rf["color"]}
	var posts := lantern_post_heads()
	for i in posts.size():
		if absf(posts[i].x) < float(rf["near_x"]):
			add.call(near, posts[i])
		elif i % int(rf["every"]) == 0:
			add.call(rf, posts[i])
	var sl: Dictionary = cfg["stalls"]
	var stalls := night_market_stalls()
	for i in range(0, stalls.size(), int(sl["every"])):
		add.call(sl, stalls[i])
	var pz: Dictionary = cfg["plaza"]
	var plaza: Array = (data().get("arena", {}) as Dictionary).get("plaza_rect", [])
	if plaza.size() == 4:
		# The square's lantern poles (old_town_landmarks.mjs: 1 m in from the sides, z +-13.5).
		for x in [float(plaza[0]) + 1.0, float(plaza[2]) - 1.0]:
			for z in [-13.5, 13.5]:
				add.call(pz, Vector3(x, float(pz["height"]), z))
	var ml: Dictionary = cfg["mother_lantern"]
	add.call(ml, Vector3(float(ml["pos"][0]), float(ml["pos"][1]), float(ml["pos"][2])))
	var ex: Dictionary = cfg["extra"]
	for p in ex["pos"]:
		add.call(ex, Vector3(float(p[0]), float(p[1]), float(p[2])))
	return out
