extends Node

# BalanceDB — the unit registry: one data/units/plants|enemies/<id>.json per unit
# holds its stats, traits and abilities (the model viewer edits these) AND how the
# game finds it: "scene", "model", the seed-bank card ("seed": icon, order,
# preview/ghost scale, default loadout, "unlock"), the placement range preview
# ("range_indicator") and the debug-spawner card ("debug"). Every plant and enemy
# list in the game (SeedBank, SeedSelector, PlacementManager, EnemySpawner,
# EnemyDebugSpawner, EnemySelector, LevelDB checks) is read from here.
# CONTRACT(add-plant): a new plant needs one data/units/plants/<id>.json.
# CONTRACT(add-enemy): a new enemy needs one data/units/enemies/<id>.json.
# CONTRACT(clip-names): "clips" lists every animation clip the unit's model provides
# by agreement; its code plays only those. --round-test checks each model against its
# list, and _play_clip() helpers call report_missing_clip() instead of freezing silently.
# CONTRACT(add-projectile): data/projectiles/<id>.json ({id, scene, numbers}) holds each
# shot's flight numbers; a plant names one via its unit JSON "projectile".
# Loads lazily on first use (other autoloads query it from their _ready).
# Edits apply on next game restart (no live reload).

const DEFAULT_COOLDOWN := 7.5
const UNITS_DIR := "res://data/units"
## Explicit subdir list (mirrors assets/models/<category>/). Never a recursive
## walk: data/.backups/ and future non-unit dirs must not be ingested as units.
const UNIT_SUBDIRS: Array[String] = ["plants", "enemies"]

const PROJECTILES_DIR := "res://data/projectiles"
const MODELS_DIR := "res://assets/models/"

var _db: Dictionary = {}
var _loaded := false
var _projectiles: Dictionary = {}
var _scene_cache: Dictionary = {}
var _reported_clips: Dictionary = {} # "unit_id/clip" -> true, so each miss logs once


func _ensure_loaded() -> void:
	if not _loaded:
		_loaded = true
		_load_all()


func _load_all() -> void:
	_db.clear()
	for sub in UNIT_SUBDIRS:
		var subdir := UNITS_DIR.path_join(sub)
		var dir := DirAccess.open(subdir)
		if dir == null:
			push_warning("[BalanceDB] Missing %s; using script defaults." % subdir)
			continue
		for file in dir.get_files():
			if not file.ends_with(".json"):
				continue
			var path := subdir.path_join(file)
			var text := FileAccess.get_file_as_string(path)
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary and (parsed as Dictionary).has("id"):
				_db[str((parsed as Dictionary)["id"])] = parsed
			else:
				push_warning("[BalanceDB] Skipping unparseable %s." % path)


	_load_projectiles()


func _load_projectiles() -> void:
	_projectiles.clear()
	var dir := DirAccess.open(PROJECTILES_DIR)
	if dir == null:
		push_warning("[BalanceDB] Missing %s; projectiles use script defaults." % PROJECTILES_DIR)
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROJECTILES_DIR.path_join(file)))
		if parsed is Dictionary and (parsed as Dictionary).has("id"):
			_projectiles[str((parsed as Dictionary)["id"])] = parsed
		else:
			push_warning("[BalanceDB] Skipping unparseable %s." % file)


func has(unit_id: String) -> bool:
	_ensure_loaded()
	return _db.has(unit_id)


func get_unit(unit_id: String) -> Dictionary:
	_ensure_loaded()
	return _db.get(unit_id, {}) as Dictionary


## Numeric stat with fallback to the script's @export default.
## Returns float for float fallbacks, int otherwise.
func num(unit_id: String, key: String, fallback: Variant) -> Variant:
	var unit := get_unit(unit_id)
	if unit.is_empty():
		return fallback
	var numbers: Variant = unit.get("numbers", {})
	if not (numbers is Dictionary) or not (numbers as Dictionary).has(key):
		return fallback
	var raw: Variant = (numbers as Dictionary)[key]
	if fallback is float:
		return float(raw)
	if fallback is int:
		return int(raw)
	return float(raw)


## Numeric flight stat of projectile `id` (data/projectiles), else `fallback`.
func projectile_num(id: String, key: String, fallback: float) -> float:
	_ensure_loaded()
	var numbers: Variant = (_projectiles.get(id, {}) as Dictionary).get("numbers", {})
	if numbers is Dictionary and (numbers as Dictionary).has(key):
		return float((numbers as Dictionary)[key])
	return fallback


## The projectile's scene (JSON "scene"), loaded once; null if unknown or missing.
func projectile_scene(id: String) -> PackedScene:
	_ensure_loaded()
	var key := "projectile/" + id
	if not _scene_cache.has(key):
		var path := str((_projectiles.get(id, {}) as Dictionary).get("scene", ""))
		_scene_cache[key] = load(path) as PackedScene if not path.is_empty() and ResourceLoader.exists(path) else null
	return _scene_cache[key]


## Sun cost for plants (the JSON "cost"), else `fallback`.
func cost(unit_id: String, fallback: int) -> int:
	var unit := get_unit(unit_id)
	if unit.is_empty() or not unit.has("cost"):
		return fallback
	return int(unit["cost"])


var _playable_cache: Dictionary = {} # unit id -> bool


## True when the plant can really be planted: its scene exists and its projectile (if it
## names one) has a scene. Seeds that fail this show as "coming soon" and cannot be packed.
func is_playable(unit_id: String) -> bool:
	_ensure_loaded()
	if _playable_cache.has(unit_id):
		return _playable_cache[unit_id]
	var ok := false
	var unit := get_unit(unit_id)
	if not unit.is_empty():
		var scene := str(unit.get("scene", ""))
		ok = not scene.is_empty() and ResourceLoader.exists(scene)
		var proj := str(unit.get("projectile", ""))
		if ok and not proj.is_empty():
			var shot: Dictionary = _projectiles.get(proj, {})
			ok = not shot.is_empty() and ResourceLoader.exists(str(shot.get("scene", "")))
	_playable_cache[unit_id] = ok
	return ok


## Plantable seeds (plants with a "seed" block), in seed-bank order:
## [{id, name, cost, icon, model, preview_scale, ghost_scale, group, playable}] (model = res:// path).
func seeds() -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for unit: Dictionary in _db.values():
		var s: Variant = unit.get("seed", null)
		if unit.get("category", "") != "plant" or not (s is Dictionary):
			continue
		out.append({
			"id": str(unit["id"]), "name": str(unit.get("name", unit["id"])),
			"cost": int(unit.get("cost", 999)), "icon": str(s.get("icon", "")),
			"model": model_path(str(unit["id"])), "order": int(s.get("order", 999)),
			"preview_scale": float(s.get("preview_scale", 1.0)), "ghost_scale": float(s.get("ghost_scale", 2.0)),
			"group": str(s.get("group", "")), "playable": is_playable(str(unit["id"])),
			"cooldown": cooldown(str(unit["id"])),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	return out


## Seconds a seed recharges after planting ("seed.cooldown"; 0 = none).
func cooldown(plant_id: String) -> float:
	var s: Variant = get_unit(plant_id).get("seed", null)
	return float((s as Dictionary).get("cooldown", DEFAULT_COOLDOWN)) if s is Dictionary else 0.0


## The seeds() entry for `plant_id`, or {} if it is not a plantable seed.
func seed_entry(plant_id: String) -> Dictionary:
	for entry in seeds():
		if entry["id"] == plant_id:
			return entry
	return {}


## The seed block's "unlock" rule (Progress decides ownership from it): null when the
## plant is owned from the start, else {"after": level id} or {"jade": price}.
## CONTRACT(add-plant): LevelDB._validate() checks the shape and the level id.
func seed_unlock(plant_id: String) -> Variant:
	var s: Variant = get_unit(plant_id).get("seed", null)
	return (s as Dictionary).get("unlock", null) if s is Dictionary else null


## Seed ids whose unlock is {"after": level id}, in seed-bank order.
func after_unlock_plants() -> Array[String]:
	var out: Array[String] = []
	for entry in seeds():
		var unlock: Variant = seed_unlock(entry["id"])
		if unlock is Dictionary and (unlock as Dictionary).has("after"):
			out.append(entry["id"])
	return out


## Seed ids flagged "default_loadout", in seed-bank order.
func default_loadout() -> Array[String]:
	var out: Array[String] = []
	for entry in seeds():
		if entry["playable"] and bool(get_unit(entry["id"])["seed"].get("default_loadout", false)):
			out.append(entry["id"])
	return out


## Playable enemies (enemies with a "scene"), in debug-picker order:
## [{id, name, scene, preview_model, preview_scale}].
func enemies() -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for unit: Dictionary in _db.values():
		if unit.get("category", "") != "enemy" or not unit.has("scene"):
			continue
		var dbg: Dictionary = unit.get("debug", {})
		out.append({
			"id": str(unit["id"]), "name": str(unit.get("name", unit["id"])), "scene": str(unit["scene"]),
			"preview_model": model_path(str(unit["id"])), "preview_scale": float(dbg.get("preview_scale", 1.0)),
			"order": int(dbg.get("order", 999)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	return out


## The enemies() entry for `enemy_id`, or {} if it is not playable.
func enemy_entry(enemy_id: String) -> Dictionary:
	for entry in enemies():
		if entry["id"] == enemy_id:
			return entry
	return {}


## res:// path of the unit's .glb (JSON "model", relative to assets/models/), or "".
func model_path(unit_id: String) -> String:
	var m := str(get_unit(unit_id).get("model", ""))
	return MODELS_DIR + m if not m.is_empty() else ""


## The unit's gameplay scene (JSON "scene"), loaded once; null if missing.
func unit_scene(unit_id: String) -> PackedScene:
	if _scene_cache.has(unit_id):
		return _scene_cache[unit_id]
	var path := str(get_unit(unit_id).get("scene", ""))
	var scene: PackedScene = load(path) as PackedScene if not path.is_empty() and ResourceLoader.exists(path) else null
	_scene_cache[unit_id] = scene
	return scene


## The unit's declared animation clips (JSON "clips"); empty when undeclared.
func clips(unit_id: String) -> PackedStringArray:
	return PackedStringArray(get_unit(unit_id).get("clips", []))


## Called by a unit's _play_clip() when its model has no clip of that name. Logs one
## error per unit and clip, naming which side is wrong: the model (the clip is
## declared) or the code (it asked for an undeclared name).
func report_missing_clip(unit_id: String, clip: String) -> void:
	var key := "%s/%s" % [unit_id, clip]
	if _reported_clips.has(key):
		return
	_reported_clips[key] = true
	var declared := clips(unit_id)
	if declared.has(clip):
		push_error("[BalanceDB] %s: model %s has no clip \"%s\" although \"clips\" declares it; regenerate the model." % [unit_id, model_path(unit_id), clip])
	else:
		push_error("[BalanceDB] %s: code played clip \"%s\", which is not in its \"clips\" %s." % [unit_id, clip, declared])


## Every "unit_id/clip" report_missing_clip() logged this run (--round-test fails on any).
func reported_missing_clips() -> PackedStringArray:
	return PackedStringArray(_reported_clips.keys())


## --round-test hook: every registered unit's scene loads and its root's unit_id
## matches its JSON id (a mismatch makes the unit silently run on script defaults),
## and every unit with a model declares "clips" that its .glb all contains.
func contract_problems() -> PackedStringArray:
	_ensure_loaded()
	var problems := PackedStringArray()
	for unit: Dictionary in _db.values():
		var uid := str(unit["id"])
		# A plantable seed with no scene yet is "coming soon" by design
		# (CONTRACT(add-plant)); every other unit must load.
		if _is_coming_soon(unit):
			continue
		if not unit.has("scene"):
			continue
		var scene := unit_scene(uid)
		if scene == null:
			problems.append("%s: scene %s does not load" % [uid, unit["scene"]])
			continue
		var node := scene.instantiate()
		var got := str(node.get("unit_id"))
		node.free()
		if got != uid:
			problems.append("%s: scene %s has unit_id \"%s\"" % [uid, unit["scene"], got])
		if not ResourceLoader.exists(model_path(uid)):
			problems.append("%s: model %s missing" % [uid, model_path(uid)])
	for unit: Dictionary in _db.values():
		if _is_coming_soon(unit):
			continue
		var pid := str(unit.get("projectile", ""))
		if not pid.is_empty() and projectile_scene(pid) == null:
			problems.append("%s: projectile \"%s\" has no loadable data/projectiles scene" % [unit["id"], pid])
	for unit: Dictionary in _db.values():
		if _is_coming_soon(unit):
			continue
		problems.append_array(_clip_problems(str(unit["id"])))
	return problems


## A seed the selector already shows as "coming soon": plantable data exists,
## but its scene or projectile scene has not landed yet.
func _is_coming_soon(unit: Dictionary) -> bool:
	return unit.get("category", "") == "plant" \
		and unit.get("seed", null) is Dictionary \
		and not is_playable(str(unit["id"]))


func _clip_problems(uid: String) -> PackedStringArray:
	var problems := PackedStringArray()
	var path := model_path(uid)
	if path.is_empty() or not ResourceLoader.exists(path):
		return problems
	if not get_unit(uid).get("clips", null) is Array:
		problems.append("%s: no \"clips\" list in its data/units file" % uid)
		return problems
	var model := (load(path) as PackedScene).instantiate()
	var players := model.find_children("*", "AnimationPlayer", true, false)
	var player := players[0] as AnimationPlayer if not players.is_empty() else null
	for clip in clips(uid):
		if player == null or not player.has_animation(clip):
			problems.append("%s: model %s has no clip \"%s\" declared in \"clips\"" % [uid, path, clip])
	model.free()
	return problems
