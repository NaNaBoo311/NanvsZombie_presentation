@tool
class_name Landmark81Zones
extends RefCounted

# Runtime reader of data/maps/landmark_81/zones/ (one <zone>.json per zone, the
# single source of truth for Landmark 81 footprints and layouts). The generator bakes geometry from it; the
# river foam in Landmark81Map queries it, and it is this map's zone script
# (MapDefinition.zones_path) for the shared batching scripts: it provides the
# static queries listed in src/maps/MapZones.gd, including the Landmark-specific
# grass exclusions (blocks_tufts) so no footprint is ever typed twice.

const HcmcParkZones = Landmark81Zones
const ParkZones = Landmark81Zones

const ZONES_DIR := "res://data/maps/landmark_81/zones"
const CITY_LOTS_PATH := "res://data/maps/landmark_81/city_lots.json"

static var _cache: Dictionary = {}
static var _loaded: bool = false

static func data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	# One file per zone: <zone>.json holds that zone's value; data() rebuilds the
	# {zone: value} dictionary every query reads.
	var files := DirAccess.get_files_at(ZONES_DIR)
	if files.is_empty():
		push_error("Landmark81Zones: no zone files in %s." % ZONES_DIR)
		return {}
	files.sort()
	for file in files:
		if not file.ends_with(".json"):
			continue
		var path := ZONES_DIR.path_join(file)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null:
			push_error("Landmark81Zones: failed to parse %s." % path)
			continue
		_cache[file.get_basename()] = parsed
	return _cache

# How far the south bank is pushed into the river at `x` (zones/south_bank.json): the
# configured shift inside its x span, 0 outside (east marina club, west bend).
static func south_bank_shift(x: float) -> float:
	var sb: Dictionary = data().get("south_bank", {})
	var span: Array = sb.get("x", [])
	if span.size() == 2 and x >= float(span[0]) and x <= float(span[1]):
		return float(sb.get("shift", 0.0))
	return 0.0

# Returns true if (x, z) falls inside any diorama water body.
static func is_in_water(x: float, z: float) -> bool:
	# 1-3. North crescent lagoon (zones/lagoon.json, the generator's source): two lobes and
	# the bridge neck, each with 0.5 m of shore margin.
	var lg: Dictionary = data().get("lagoon", {})
	if not lg.is_empty():
		var lz: float = float(lg["center_z"])
		var rx: float = float(lg["lobe_rx"]) + 0.5
		var rz: float = float(lg["lobe_rz"]) + 0.5
		var lx: float = float(lg["lobe_x"])
		var dz: float = (z - lz) / rz
		for sx: float in [-lx, lx]:
			var dx: float = (x - sx) / rx
			if dx * dx + dz * dz < 1.0:
				return true
		if absf(x) <= float(lg["neck_half_w"]) + 0.5 and absf(z - lz) <= rz:
			return true

	# 4. Lake 3 (Lotus pond): center (-54, -26), rx = 10.5, rz = 6.5
	var dl3 := ((x - (-54.0)) / 10.5) * ((x - (-54.0)) / 10.5) + ((z - (-26.0)) / 6.5) * ((z - (-26.0)) / 6.5)
	if dl3 < 1.0:
		return true

	# 5. Japanese Garden Koi Pond: center (-72, -2), rx = 7.8, rz = 4.6
	var djp := ((x - (-72.0)) / 7.8) * ((x - (-72.0)) / 7.8) + ((z - (-2.0)) / 4.6) * ((z - (-2.0)) / 4.6)
	if djp < 1.0:
		return true

	# 7. Saigon River & Marina yacht basin; the central bank is pushed `shift` m into the river
	# (zones/south_bank.json).
	if z > 33.0 + south_bank_shift(x):
		return true
	if z > 30.5 and x > 64.0:
		return true

	# 8. West Bend Beach Cove
	if x < -95.0 and z > -5.0:
		var d_beach := Vector2(x - (-95.0), z - 5.0).length()
		if d_beach > 15.5:
			return true

	return false

static func blocks_grass(x: float, z: float) -> bool:
	if is_in_water(x, z):
		return true
	var d := data()
	if d.is_empty():
		return false
	# Garden gravel ellipse.
	var garden: Dictionary = d.get("garden", {})
	var gc: Array = garden.get("gravel_center", [0, 0])
	var grx: float = garden.get("gravel_rx", 0.0)
	var grz: float = garden.get("gravel_rz", 0.0)
	if grx > 0.0 and grz > 0.0:
		var eg := Vector2((x - gc[0]) / grx, (z - gc[1]) / grz)
		if eg.length() < 1.0:
			return true
	# Shrine, gazebo and observation-tower clearances.
	var shrine: Dictionary = d.get("shrine", {})
	if _inside_clear(x, z, shrine.get("pos", [0, 0]), shrine.get("clear_r", 0.0)):
		return true
	var gazebos: Dictionary = d.get("gazebos", {})
	for gp in gazebos.get("pos", []):
		if _inside_clear(x, z, gp, gazebos.get("clear_r", 0.0)):
			return true
	var tower: Dictionary = d.get("obs_tower_1", {})
	if _inside_clear(x, z, tower.get("pos", [0, 0]), tower.get("clear_r", 0.0)):
		return true
	# Lake 3 ellipse grown by its margin.
	var lake: Dictionary = d.get("lake3", {})
	var lc: Array = lake.get("center", [0, 0])
	var lrx: float = float(lake.get("rx", 0.0)) + float(lake.get("margin", 0.0))
	var lrz: float = float(lake.get("rz", 0.0)) + float(lake.get("margin", 0.0))
	if lrx > 0.0 and lrz > 0.0:
		var el := Vector2((x - lc[0]) / lrx, (z - lc[1]) / lrz)
		if el.length() < 1.0:
			return true
	# Phase 3 east side: villa district and Marina Club shore (moved here from GrassMultiMesh).
	if _inside_rect(x, z, (d.get("villa_district", {}) as Dictionary).get("rect", [])):
		return true
	if _inside_rect(x, z, (d.get("marina_shore", {}) as Dictionary).get("rect", [])):
		return true
	return false

static func blocks_trees(x: float, z: float) -> bool:
	if is_in_water(x, z):
		return true
	if blocks_grass(x, z):
		return true
	var d := data()
	if d.is_empty():
		return false
	# Bend beach, ring and water.
	var beach: Dictionary = d.get("beach", {})
	var bc: Array = beach.get("center", [0, 0])
	if x < -95.0 and z > -5.0 \
			and Vector2(x - bc[0], z - bc[1]).length() > float(beach.get("r_inner", 0.0)) - 0.5:
		return true
	# Promenade strip: no trees south of the lawn (they would block the view of it). The one
	# exception is the parkland the pushed-out central bank adds (z 30 to the promenade at
	# 29.5 m + shift), where the south spawn region's canopy grows.
	var shift := south_bank_shift(x)
	if z > 17.0 and not (shift > 0.0 and z >= 30.0 and z < 29.0 + shift):
		return true
	return false

static func _inside_clear(x: float, z: float, pos: Array, clear_r: float) -> bool:
	if pos.size() < 2 or clear_r <= 0.0:
		return false
	return Vector2(x - pos[0], z - pos[1]).length() < clear_r

static func _inside_rect(x: float, z: float, rect: Array) -> bool:
	if rect.size() < 4:
		return false
	return x >= rect[0] and x <= rect[2] and z >= rect[1] and z <= rect[3]

# luxury_motor_yacht.glb footprint (tools/inspect_model.gd): 3.70 m wide, 11.31 m long
# along local z, centred on its origin.
const YACHT_W := 3.70
const YACHT_L := 11.31

# World-space instance lots for PropMultiMesh.zone_lots: [{pos: Vector3, yaw: float (deg), scale: float}].
static func lots(key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := data()
	match key:
		"villas":
			var g: Dictionary = d.get("villa_grid", {})
			for row in g.get("rows", []):
				for x in g.get("xs", []):
					out.append({"pos": Vector3(float(x), 0.06, float(row["z"])), "yaw": float(row["yaw"]), "scale": 1.0})
		"marina_yachts":
			var m: Dictionary = d.get("marina_club", {})
			if m.is_empty():
				return out
			var s := float(m.get("yacht_scale", 1.0))
			var off := float(m["finger_w"]) * 0.5 + 0.1 + YACHT_W * s * 0.5
			var z := float(m["walk_z"]) + float(m["walk_w"]) * 0.5 + 0.5 + YACHT_L * s * 0.5
			for fx in m.get("fingers_x", []):
				for side in [-1.0, 1.0]:
					out.append({"pos": Vector3(float(fx) + side * off, 0.02, z), "yaw": float(m.get("yacht_yaw", 0.0)), "scale": s})
		"skyline_res", "skyline_finance", "skyline_block":
			var want := ["skyline_res", "skyline_finance", "skyline_block"].find(key)
			for t in skyline_towers():
				if int(t["model"]) == want:
					out.append(t)
		"lamps":
			out.append_array(_lamp_lots())
		"city_street_trees":
			for t in _load_city_lots().get("trees", []):
				out.append({"pos": Vector3(float(t["x"]), 0.20, float(t["z"])), "yaw": 0.0, "scale": 1.0})
		"city_cars":
			for c in _load_city_lots().get("cars", []):
				out.append({"pos": Vector3(float(c["x"]), 0.08, float(c["z"])), "yaw": float(c["yaw"]), "scale": 1.0})
		"city_motorbikes":
			for b in _load_city_lots().get("motorbikes", []):
				out.append({"pos": Vector3(float(b["x"]), 0.20, float(b["z"])), "yaw": float(b["yaw"]), "scale": 1.0})
		"city_cafes":
			for c in _load_city_lots().get("cafes", []):
				out.append({"pos": Vector3(float(c["x"]), 0.20, float(c["z"])), "yaw": float(c["yaw"]), "scale": 1.0})
		"villa_garden_frangipani", "villa_garden_bougainvillea":
			for p in villa_garden_positions(key.trim_prefix("villa_garden_")):
				out.append({"pos": p, "yaw": 0.0, "scale": 1.0})
		_:
			push_error("Landmark81Zones.lots: unknown key '%s'" % key)
	return out

# Lake 3 centre fountain (x, z) for the pond shader's ring array. Single source of
# truth is data/maps/landmark_81/zones/lake3.json `center`; the island generator bakes the
# pedestal from it (lake_three.mjs) and Landmark81Map reads it here so the
# footprint is never typed twice (CONTRACT(mesh-names)).
static func lake3_center() -> Vector2:
	var lake: Dictionary = data().get("lake3", {})
	var lc: Array = lake.get("center", [0, 0])
	return Vector2(float(lc[0]), float(lc[1]))

# The crescent lagoon's fountains as PondWater ring centres (x, z, pedestal r, 0), from
# zones/lagoon.json so the baked pedestals and the shader rings can never drift apart.
static func crescent_fountains() -> Array[Vector4]:
	var out: Array[Vector4] = []
	for f in data().get("lagoon", {}).get("fountains", []):
		out.append(Vector4(float(f[0]), float(f[1]), float(f[2]), 0.0))
	return out

# Lake 3 fountain pedestal radius, mirroring lake_three.mjs (r 1.2).
const LAKE3_FOUNTAIN_R := 1.2

# River foam boxes (x, z, half_x, half_z) for the Marina Club: walkway, gangway, and one
# box per finger that also covers the two yachts moored against it (inside a box is solid foam).
static func marina_foam_boxes() -> Array[Vector4]:
	var out: Array[Vector4] = []
	var m: Dictionary = data().get("marina_club", {})
	if m.is_empty():
		return out
	var s := float(m.get("yacht_scale", 1.0))
	var wx: Array = m["walk_x"]
	var walk_z := float(m["walk_z"])
	var half_w := float(m["walk_w"]) * 0.5
	var fc: Array = m["fan_center"]
	var fan_r := float(m["fan_r"])
	out.append(Vector4((float(wx[0]) + float(wx[1])) * 0.5, walk_z, (float(wx[1]) - float(wx[0])) * 0.5, half_w))
	var g0 := float(fc[1]) + fan_r - 0.5
	var g1 := walk_z - half_w + 0.2
	out.append(Vector4(float(fc[0]), (g0 + g1) * 0.5, 1.0, (g1 - g0) * 0.5))
	var flen := float(m["finger_len"])
	var fhx := float(m["finger_w"]) * 0.5 + 0.1 + YACHT_W * s + 0.2
	for fx in m.get("fingers_x", []):
		out.append(Vector4(float(fx), walk_z + half_w + flen * 0.5, fhx, flen * 0.5))
	return out

# (cx, cz, radius) of the Marina Club fan for SaigonRiverWater's marina_club_fan uniform.
static func marina_club_fan() -> Vector3:
	var m: Dictionary = data().get("marina_club", {})
	if m.is_empty():
		return Vector3(0.0, 0.0, -1000.0)
	var fc: Array = m["fan_center"]
	return Vector3(float(fc[0]), float(fc[1]), float(m["fan_r"]) + 0.3)

# Villa-district garden plants: bougainvillea in the gaps between front yards, frangipani
# in the back gardens. Gap x = midpoint between neighbouring villa columns.
static func villa_garden_positions(kind: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var g: Dictionary = data().get("villa_grid", {})
	var xs: Array = g.get("xs", [])
	if xs.size() < 2:
		return out
	var step := float(xs[1]) - float(xs[0])
	for i in g.get("garden_gap_indices", []):
		var gx := float(xs[int(i)]) + step * 0.5
		if kind == "bougainvillea":
			var f := float(g.get("bougainvillea_front", 2.5))
			for row in g.get("rows", []):
				var z := float(row["z"]) + (f if float(row["yaw"]) == 0.0 else -f)
				out.append(Vector3(gx, 0.06, z))
		elif kind == "frangipani":
			for z in g.get("frangipani_z", []):
				out.append(Vector3(gx, 0.06, float(z)))
	return out

# North-city skyline (Phase 2 zone J): every tower lot with its model index (0
# res, 1 finance, 2 block, cycling), a y-only scale and a +-tower_yaw_deg yaw.
# Computed ONCE by tools/.../maps/landmark_81/north_city.mjs and read here from
# data/maps/landmark_81/city_lots.json, so the ground (roads/sidewalks) and the props
# line up exactly. The runtime never recomputes a lot position.
static var _towers_cache: Array[Dictionary] = []
static var _city_lots: Dictionary = {}
static var _city_warned: bool = false

static func _load_city_lots() -> Dictionary:
	if not _city_lots.is_empty():
		return _city_lots
	if not FileAccess.file_exists(CITY_LOTS_PATH):
		push_error("Landmark81Zones: %s not found (run npm run generate -- maps/landmark_81/island_diorama_base)." % CITY_LOTS_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CITY_LOTS_PATH))
	if parsed is Dictionary:
		_city_lots = parsed
	else:
		push_error("Landmark81Zones: failed to parse data/maps/landmark_81/city_lots.json.")
		return {}
	if not _city_warned and _city_lots.get("source", {}) != data().get("north_city", {}):
		_city_warned = true
		push_error("Landmark81Zones: city lots file is stale (north_city changed since generate).")
	return _city_lots

# True when the lots file matches the current north_city block.
static func city_lots_ok() -> bool:
	var lots := _load_city_lots()
	if lots.is_empty():
		return false
	return lots.get("source", {}) == data().get("north_city", {})


# Landmark 81 has no paved walkways any more (enemies pathfind: NavGrid). The shared
# MapZones query is true inside a zones/clearings.json rect (grown by `margin`): the
# trunk-free spawn areas the groves must leave open for NavGrid.
static func on_walkway(x: float, z: float, margin: float = 0.0) -> bool:
	for r in data().get("clearings", {}).get("rects", []):
		if x > float(r[0]) - margin and x < float(r[2]) + margin and z > float(r[1]) - margin and z < float(r[3]) + margin:
			return true
	return false

static func skyline_towers() -> Array[Dictionary]:
	if not _towers_cache.is_empty():
		return _towers_cache
	var out: Array[Dictionary] = []
	for t in _load_city_lots().get("towers", []):
		out.append({
			"pos": Vector3(float(t["x"]), 0.15, float(t["z"])),
			"yaw": float(t["yaw"]),
			"scale": Vector3(1.0, float(t["sy"]), 1.0),
			"model": int(t["model"]),
		})
	_towers_cache = out
	return out

# Promenade lamp head bases (x, z) for the Saigon River night reflections
# (Landmark81Water.setup_river_reflections). Single source of truth is
# data/maps/landmark_81/zones/promenade_lamps.json (z is the original bank; lamps on the
# central bank add south_bank_shift).
static func promenade_lamp_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var pl: Dictionary = data().get("promenade_lamps", {})
	for x in pl.get("xs", []):
		out.append(Vector2(float(x), float(pl.get("z", 20.0)) + south_bank_shift(float(x))))
	return out


# Promenade lamps plus the north-city street lamps.
static func _lamp_lots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pl: Dictionary = data().get("promenade_lamps", {})
	for x in pl.get("xs", []):
		out.append({"pos": Vector3(float(x), 0.06, float(pl.get("z", 20.0)) + south_bank_shift(float(x))), "yaw": 0.0, "scale": 1.0})
	# North-city street lamps (Phase 3 zone J): same StreetLamps PropMultiMesh,
	# 0 new nodes. The forest obstacle registration (obstacles.lots key lamps)
	# picks them up for free.
	for lot in _load_city_lots().get("lamps", []):
		out.append({"pos": Vector3(float(lot["x"]), 0.20, float(lot["z"])), "yaw": float(lot["yaw"]), "scale": 1.0})
	return out

# True inside the lagoon-front street road's footprint (zones/north_city.json
# lagoon_street road). The verge south of the road is open lawn (no paving since
# 2026-10-07), so the old south_sidewalk edge is deliberately NOT included.
static func _on_street(x: float, z: float) -> bool:
	var ls: Dictionary = (data().get("north_city", {}) as Dictionary).get("lagoon_street", {})
	if ls.is_empty():
		return false
	var xr: Array = ls["x"]
	return x > float(xr[0]) - 0.5 and x < float(xr[1]) + 0.5 \
		and z > float(ls["road"][0]) - 0.5 and z < float(ls["road"][1]) + 0.5

# Phase 4 grass exclusions: the lagoon-front street road, the plateau rects and
# the skyline tower bases. The lagoon verge and the old lagoon_plaza are
# open lawn (paving removed 2026-10-07), so they are deliberately NOT excluded.
# Deliberately NOT part of
# blocks_grass(): blocks_trees() -> blocks_grass() drives the west-grove scatter,
# and new exclusions there would move Phase 2 trees.
static func blocks_grass_phase4(x: float, z: float) -> bool:
	var d := data()
	var nc: Dictionary = d.get("north_city", {})
	if not nc.is_empty():
		if _on_street(x, z):
			return true
		if _inside_rect(x, z, (nc.get("plateau", {}) as Dictionary).get("rect", [])):
			return true
		if _inside_rect(x, z, (nc.get("northwest_pad", {}) as Dictionary).get("rect", [])):
			return true
	for t in skyline_towers():
		var tp: Vector3 = t["pos"]
		if Vector2(x - tp.x, z - tp.z).length() < 5.0:
			return true
	return false


# Grass-tuft exclusions for GrassMultiMesh.is_valid_grass_pos (MapZones contract).
# `legacy_pass` = passes 1-2, which skip the JSON zones: all grass passes share one rng, so a changed keep/cull there would
# reshuffle every later tuft (the pass-2 tufts inside the new zones are removed
# afterwards by blocks_new_zone_tufts instead, which is stream-neutral).
static func blocks_tufts(x: float, z: float, legacy_pass: bool) -> bool:
	# Outside the island (land x +-120, z -110..23)
	if absf(x) > 118.0 or absf(z) > 118.0:
		return true
	# Sacred Dragon Pearl plinth (centred on the origin); the lawn grows right up to it
	if x > -3.9 and x < 3.9 and z > -3.9 and z < 3.9:
		return true
	# Lagoon and skyscraper plaza (north). The lagoon moved 8 m north in 2026-10-07
	# (center_z -45); the old basin is grove and verge now, so only water-side stays clear.
	if z < -37.0 and absf(x) < 30.0:
		return true
	# South promenade, river revetment and marina
	if z > 31.0 + south_bank_shift(x):
		return true
	# East villa district
	if x > 38.0 and z > -24.0 and z < 16.0:
		return true
	# West-bend river water and its land-side revetment: west of the bank curve from
	# (-95, 20) to (-120, -5) along the r = 25 arc centred on (-95, -5).
	# (15.8 = beach inner edge (16) minus 0.2 m: excludes water, revetment and beach.)
	if z >= -7.0 and z <= 19.5 and x < -93.0:
		var x_bank := -95.0
		if z < 20.0:
			if z < -5.0:
				x_bank = -120.0
			else:
				x_bank = -95.0 - sqrt(maxf(0.0, 249.64 - (z + 5.0) * (z + 5.0)))
		if x < x_bank:
			return true
	if legacy_pass:
		return false
	# The JSON park zones and the Phase 4 tower footprints.
	return blocks_new_zone_tufts(x, z)


# The zone footprints passes 1-2 could not apply in-stream (see blocks_tufts).
static func blocks_new_zone_tufts(x: float, z: float) -> bool:
	return blocks_grass(x, z) or blocks_grass_phase4(x, z)
