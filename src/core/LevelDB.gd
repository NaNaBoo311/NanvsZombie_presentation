extends Node

# LevelDB — data source of truth for worlds (= atlas provinces) and levels.
# Reads data/worlds/<world_id>.json + data/levels/<world_id>/*.json at boot;
# GameManager, Progress, the atlas menu and GameFlow pull from here. Edits apply on next
# game restart (no live reload).
#
# CONTRACT(add-level): a world is one data/worlds/<world_id>.json file; its
# "levels" list is the ONLY membership + play order (level files carry no world_id — it is
# filled in here at load). A new level is data/levels/<world_id>/<id>.json
# with "id" matching the filename, plus its id in that list. Unlisted files are
# dropped with a warning; listed ids without a file are errors.
# "story" (optional): {intro?, outro?, huge_wave?}, each an array of strings.
# Loadout fields (all optional): "seed_pool" ([plant id], if skipped every seed),
# "seed_forced" ([plant id] in the pool, if skipped none), "seed_slots" (int
# 1..SeedBank.TOTAL_SLOTS, if skipped the full bank). "seed_loadout" is retired:
# it errors naming these fields. "peaceful": true makes the level a sandbox with
# no waves that never ends (its "waves" must be empty; listed waves warn).
# A new world also needs `npm run generate -- environment/vietnam_world_atlas`
# + reimport so the atlas bakes its province as playable (and
# data/atlas_provinces.json stays in sync).
#
# Maps: data/maps/<map_id>/map.json {id, name, scene, dev?} — every world/level
# "map" must be one of these ids (CONTRACT(add-map)); get_map_scene() gives the scene path.
# "dev": true marks test-only maps (--map-switch-test); no world or level may use one.
#
# World schema:
#   {id, province, name, map, unlock, levels[], path?, order, icon, model, music?}
#   music = battle-track stem in assets/audio/music/ (optional; missing = silence).
#   province = id in the atlas data (vietnam_provinces.json); map = battlefield
#   map id; unlock = "start", {"after": [level ids]} (all completed) or
#   {"stars": N} (Progress.total_stars() >= N);
#   path = [[x, z], ...] control points of the province screen's level path,
#   world XZ metres like data/atlas_provinces.json (>= 2; author with the atlas
#   menu's --path-edit). Missing -> a fallback line with a warning.
# Level schema:
#   {id, name, difficulty, setup_sec, story?, seed_pool?, seed_forced?, seed_slots?,
#    map?, lawn?, time_of_day?, peaceful?, waves[]}
#   difficulty = easy / normal / hard (Progress.JADE_BASE picks the win's Jade).
#   seed_pool = [plant id] (if skipped: every seed); each id needs a "seed" block.
#   seed_forced = [plant id] in the pool (if skipped: none); no duplicates;
#   size() <= seed_slots. seed_slots = int 1..SeedBank.TOTAL_SLOTS (if skipped:
#   the full bank). "seed_loadout" is retired and errors.
#   map overrides the world's map (resolve_map is the only place that decides);
#   lawn = lawn zone id on that map; time_of_day = a LightingPreset id (assets/lighting/<id>.tres).
#   peaceful = true: no enemy waves and the level never ends (a sandbox for a map whose
#   enemies do not exist yet); its "waves" must be empty, and it can never be completed.
# Wave schema:
#   {is_huge: bool, spawns: [{enemy_id, count, interval_sec, delay_sec}]}
# Progress convention: total = sum of all spawn counts; a huge-wave flag sits
# at cumulative_killed_through_that_wave / total (killed/total metric).

const WORLDS_DIR := "res://data/worlds"
const MAPS_DIR := "res://data/maps"
const LEVELS_DIR := "res://data/levels"

var _worlds: Array[Dictionary] = []
var _levels: Dictionary = {} # level_id -> Dictionary (with "world_id" filled in)
var _world_levels: Dictionary = {} # world_id -> Array[String] in play order
var _maps: Dictionary = {} # map_id -> {id, name, scene}


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_worlds.clear()
	_levels.clear()
	_world_levels.clear()
	_maps.clear()
	_load_maps()
	_load_worlds()
	var files := _load_level_files()
	_sort_worlds()
	_assign_levels(files)
	_validate()


func _load_worlds() -> void:
	var root := DirAccess.open(WORLDS_DIR)
	if root == null:
		push_warning("[LevelDB] Missing %s; no worlds available." % WORLDS_DIR)
		return
	var files: Array[String] = []
	for file in root.get_files():
		if file.ends_with(".json"):
			files.append(file)
	files.sort()
	for file in files:
		var path := WORLDS_DIR.path_join(file)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary and (parsed as Dictionary).has("id")):
			push_warning("[LevelDB] Skipping unparseable %s." % path)
			continue
		var world := parsed as Dictionary
		var world_id := str(world["id"])
		if world_id != file.get_basename():
			push_warning("[LevelDB] %s: id \"%s\" does not match its filename." % [path, world_id])
		if _worlds.any(func(w: Dictionary) -> bool: return str(w.get("id", "")) == world_id):
			push_error("[LevelDB] Duplicate world id %s (%s)." % [world_id, path])
			continue
		_worlds.append(world)


func _load_maps() -> void:
	var root := DirAccess.open(MAPS_DIR)
	if root == null:
		push_error("[LevelDB] Missing %s; no maps available." % MAPS_DIR)
		return
	var folders := root.get_directories()
	folders.sort()
	for folder in folders:
		var path := MAPS_DIR.path_join(folder).path_join("map.json")
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary and (parsed as Dictionary).has("id") and (parsed as Dictionary).has("scene")):
			push_error("[LevelDB] %s: map entries need \"id\" and \"scene\"." % path)
			continue
		var map := parsed as Dictionary
		var map_id := str(map["id"])
		if map_id != folder:
			push_warning("[LevelDB] %s: id \"%s\" does not match its folder name." % [path, map_id])
		if _maps.has(map_id):
			push_error("[LevelDB] Duplicate map id %s (%s)." % [map_id, path])
			continue
		if not ResourceLoader.exists(str(map["scene"])):
			push_error("[LevelDB] Map %s: scene %s does not exist." % [map_id, map["scene"]])
		_maps[map_id] = map
	if _maps.is_empty():
		push_error("[LevelDB] No valid %s/<map_id>/map.json; no maps available." % MAPS_DIR)


## Every data/levels/<folder>/*.json, keyed by level id (folder kept for validation).
func _load_level_files() -> Dictionary:
	var files := {}
	var root := DirAccess.open(LEVELS_DIR)
	if root == null:
		push_warning("[LevelDB] Missing %s; no levels available." % LEVELS_DIR)
		return files
	for loose in root.get_files():
		if loose.ends_with(".json"):
			push_warning("[LevelDB] %s is outside a world folder (data/levels/<world_id>/); ignored." % loose)
	for folder in root.get_directories():
		var dir_path := LEVELS_DIR.path_join(folder)
		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".json"):
				continue
			var path := dir_path.path_join(file)
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not (parsed is Dictionary and (parsed as Dictionary).has("id")):
				push_warning("[LevelDB] Skipping unparseable %s." % path)
				continue
			var level := parsed as Dictionary
			var level_id := str(level["id"])
			if level_id != file.get_basename():
				push_warning("[LevelDB] %s: id \"%s\" does not match its filename." % [path, level_id])
			if files.has(level_id):
				push_error("[LevelDB] Duplicate level id %s (%s)." % [level_id, path])
				continue
			level["_folder"] = folder
			files[level_id] = level
	return files


func _sort_worlds() -> void:
	_worlds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 0)) < int(b.get("order", 0)))


## Membership + order come only from each world's "levels" list.
func _assign_levels(files: Dictionary) -> void:
	for w in _worlds:
		var world_id := str(w.get("id", ""))
		var ids: Array[String] = []
		var listed: Variant = w.get("levels", [])
		if not (listed is Array):
			push_error("[LevelDB] World %s: \"levels\" must be an array of level ids." % world_id)
			listed = []
		for raw_id in (listed as Array):
			var level_id := str(raw_id)
			if _levels.has(level_id):
				push_error("[LevelDB] Level %s is listed twice (world %s)." % [level_id, world_id])
				continue
			if not files.has(level_id):
				push_error("[LevelDB] World %s lists %s but data/levels/%s/%s.json does not exist." % [world_id, level_id, world_id, level_id])
				continue
			var level: Dictionary = files[level_id]
			if str(level.get("_folder", "")) != world_id:
				push_warning("[LevelDB] Level %s lives in data/levels/%s/ but belongs to world %s." % [level_id, level["_folder"], world_id])
			level.erase("_folder")
			level["world_id"] = world_id
			_levels[level_id] = level
			ids.append(level_id)
		_world_levels[world_id] = ids
	for level_id in files:
		if not _levels.has(level_id):
			push_warning("[LevelDB] Level %s is not listed by any world in data/worlds/<world_id>.json; dropped." % level_id)


func _validate() -> void:
	for w in _worlds:
		var world_id := str(w.get("id", ""))
		for key in ["province", "map"]:
			if str(w.get(key, "")).is_empty():
				push_error("[LevelDB] World %s has no \"%s\"." % [world_id, key])
		_validate_map_ref("World " + world_id, str(w.get("map", "")))
		var path: Variant = w.get("path", null)
		if path == null:
			push_warning("[LevelDB] World %s has no \"path\"; the province screen lays levels on a fallback line." % world_id)
		elif not (path is Array and (path as Array).size() >= 2 and (path as Array).all(func(pt: Variant) -> bool: return pt is Array and (pt as Array).size() == 2)):
			push_error("[LevelDB] World %s: \"path\" must be >= 2 [x, z] points." % world_id)
		var unlock: Variant = w.get("unlock", null)
		if unlock is String and unlock == "start":
			pass
		elif unlock is Dictionary and (unlock as Dictionary).get("after", null) is Array:
			for after_id in (unlock as Dictionary)["after"]:
				if not _levels.has(str(after_id)):
					push_error("[LevelDB] World %s unlocks after unknown level %s (it stays locked)." % [world_id, str(after_id)])
		elif unlock is Dictionary and (unlock as Dictionary).has("stars"):
			if int((unlock as Dictionary)["stars"]) < 1:
				push_error("[LevelDB] World %s: {\"stars\": N} needs N >= 1." % world_id)
		else:
			push_error("[LevelDB] World %s: \"unlock\" must be \"start\", {\"after\": [level ids]} or {\"stars\": N} (it stays locked)." % world_id)
	for level_id in _levels:
		var level: Dictionary = _levels[level_id]
		var tod: Variant = level.get("time_of_day", null)
		if tod != null and not LightingPreset.ids().has(str(tod)):
			push_warning("[LevelDB] Level %s: time_of_day \"%s\" is not a preset in %s." % [level_id, str(tod), LightingPreset.DIR])
		for key in ["map", "lawn"]:
			if level.has(key) and str(level[key]).is_empty():
				push_warning("[LevelDB] Level %s: empty \"%s\"." % [level_id, key])
		if level.has("map"):
			_validate_map_ref("Level " + str(level_id), str(level["map"]))
		if bool(level.get("peaceful", false)) and not (level.get("waves", []) as Array).is_empty():
			push_warning("[LevelDB] Level %s is peaceful but lists waves; they never spawn." % level_id)
		# Unit ids come from the unit registry (data/units/, BalanceDB).
		# "seed_loadout" is retired: the briefing's seed_pool / seed_forced / seed_slots replace it.
		if level.has("seed_loadout"):
			push_error("[LevelDB] Level %s uses retired \"seed_loadout\"; use \"seed_pool\" / \"seed_forced\" / \"seed_slots\" instead." % level_id)
		_validate_seed_rules(level_id, level)
		_validate_story(level_id, level)
		for wave in level.get("waves", []):
			for spawn in (wave as Dictionary).get("spawns", []):
				var eid := str((spawn as Dictionary).get("enemy_id", ""))
				if BalanceDB.enemy_entry(eid).is_empty():
					push_error("[LevelDB] Level %s: enemy_id \"%s\" is not an enemy with a \"scene\" in data/units/enemies/ (its spawns are skipped)." % [level_id, eid])

	for entry in BalanceDB.seeds():
		var plant_id := str(entry["id"])
		var unlock: Variant = BalanceDB.seed_unlock(plant_id)
		if unlock == null:
			continue
		if unlock is Dictionary and (unlock as Dictionary).has("after"):
			if not _levels.has(str(unlock["after"])):
				push_error("[LevelDB] Plant %s unlocks after unknown level %s (it is never owned)." % [plant_id, str(unlock["after"])])
		elif not (unlock is Dictionary and (unlock as Dictionary).has("jade") and int(unlock["jade"]) > 0):
			push_error("[LevelDB] Plant %s: seed \"unlock\" must be {\"after\": level id} or {\"jade\": N > 0}." % plant_id)


## "story" = {intro?, outro?, huge_wave?}: each an array of plain strings (StoryPanel / BattlePanel / HUD).
func _validate_story(level_id: String, level: Dictionary) -> void:
	if not level.has("story"):
		return
	if not (level["story"] is Dictionary):
		push_error("[LevelDB] Level %s: \"story\" must be an object." % level_id)
		return
	for key in level["story"]:
		var lines: Variant = level["story"][key]
		if not (str(key) in ["intro", "outro", "huge_wave"]):
			push_warning("[LevelDB] Level %s: unknown story key \"%s\" (ignored)." % [level_id, str(key)])
		elif not (lines is Array and (lines as Array).all(func(l: Variant) -> bool: return l is String)):
			push_error("[LevelDB] Level %s: story.%s must be an array of strings." % [level_id, str(key)])


## The level's story lines for `key` ("intro" / "outro" / "huge_wave"), or [].
func story_lines(level_id: String, key: String) -> Array[String]:
	var out: Array[String] = []
	var story: Variant = get_level(level_id).get("story", null)
	if story is Dictionary and (story as Dictionary).get(key, null) is Array:
		for line in story[key]:
			out.append(str(line))
	return out


func _validate_map_ref(owner: String, map_id: String) -> void:
	if map_id.is_empty():
		return
	if not _maps.has(map_id):
		push_error("[LevelDB] %s uses unknown map %s (not in data/maps/<map_id>/map.json)." % [owner, map_id])
	elif bool(_maps[map_id].get("dev", false)):
		push_error("[LevelDB] %s uses dev-only map %s." % [owner, map_id])


## Seed rule errors for one level (boot, error): pool ids need a "seed" block;
## forced ids must be in the pool with no duplicates and fit in the slots;
## slots must be 1..SeedBank.TOTAL_SLOTS.
func _validate_seed_rules(level_id: String, level: Dictionary) -> void:
	var rules := seed_rules(level_id, false)
	var pool: Array[String] = rules["pool"]
	for sid in level.get("seed_pool", []):
		if BalanceDB.seed_entry(str(sid)).is_empty():
			push_error("[LevelDB] Level %s: seed_pool id \"%s\" is not a plant with a \"seed\" block in data/units/plants/ (dropped from the pool)." % [level_id, str(sid)])
	var seen := {}
	for sid in level.get("seed_forced", []):
		var id := str(sid)
		if seen.has(id):
			push_error("[LevelDB] Level %s: seed_forced id \"%s\" is duplicated." % [level_id, id])
		seen[id] = true
		if not pool.has(id):
			push_error("[LevelDB] Level %s: seed_forced id \"%s\" is not in the pool." % [level_id, id])
	var forced: Array[String] = rules["forced"]
	var slots: int = rules["slots"]
	if forced.size() > slots:
		push_error("[LevelDB] Level %s: seed_forced has %d ids but seed_slots is %d." % [level_id, forced.size(), slots])
	if level.has("seed_slots"):
		var raw := int(level.get("seed_slots", slots))
		if raw < 1 or raw > SeedBank.TOTAL_SLOTS:
			push_error("[LevelDB] Level %s: seed_slots %d is outside 1..%d." % [level_id, raw, SeedBank.TOTAL_SLOTS])


## One resolved answer for a level's loadout rules: {pool, forced, slots}.
## GameManager, the briefing and SeedBank read this instead of re-deriving defaults.
## pool defaults to every seed; forced defaults to []; slots defaults to the full bank.
## owned_only (the player's view): the pool keeps only Progress-owned plants plus the
## forced ones, and slots are capped by Progress.seed_slots() (never below forced).
## Validation passes false so the raw data is checked. --dev-seeds ignores ownership.
func seed_rules(level_id: String, owned_only: bool = true) -> Dictionary:
	var level := get_level(level_id)
	var pool: Array[String] = []
	if level.has("seed_pool") and level["seed_pool"] is Array:
		for sid in level["seed_pool"]:
			var id := str(sid)
			if not pool.has(id) and not BalanceDB.seed_entry(id).is_empty():
				pool.append(id)
	else:
		for entry in BalanceDB.seeds():
			pool.append(str(entry["id"]))
	var forced: Array[String] = []
	if level.has("seed_forced") and level["seed_forced"] is Array:
		for sid in level["seed_forced"]:
			var id := str(sid)
			if not forced.has(id) and pool.has(id):
				forced.append(id)
	var slots := SeedBank.TOTAL_SLOTS
	if level.has("seed_slots"):
		slots = clampi(int(level.get("seed_slots", slots)), 1, SeedBank.TOTAL_SLOTS)
	if owned_only and not ("--dev-seeds" in OS.get_cmdline_user_args()):
		pool.assign(pool.filter(func(id: String) -> bool: return forced.has(id) or Progress.is_plant_owned(id)))
		slots = maxi(mini(slots, Progress.seed_slots()), forced.size())
	return {"pool": pool, "forced": forced, "slots": slots}


func get_worlds() -> Array[Dictionary]:
	return _worlds.duplicate()


func get_world(world_id: String) -> Dictionary:
	for w in _worlds:
		if str(w.get("id", "")) == world_id:
			return w
	return {}


## Level ids of a world in play order (the world's "levels" list).
func get_level_ids(world_id: String) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_world_levels.get(world_id, []))
	return ids


func get_levels(world_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for level_id in get_level_ids(world_id):
		out.append(_levels[level_id])
	return out


func get_level(level_id: String) -> Dictionary:
	return _levels.get(level_id, {}) as Dictionary


func has_level(level_id: String) -> bool:
	return _levels.has(level_id)


func world_of(level_id: String) -> String:
	return str(get_level(level_id).get("world_id", ""))


## --round-test hook: seed rule mistakes that would otherwise fail silently.
func contract_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	for level_id in _levels:
		var level: Dictionary = _levels[level_id]
		if level.has("seed_loadout"):
			problems.append("level %s uses retired \"seed_loadout\"; use \"seed_pool\" / \"seed_forced\" / \"seed_slots\" instead" % level_id)
		var rules := seed_rules(level_id, false)
		var pool: Array[String] = rules["pool"]
		var seen := {}
		for sid in level.get("seed_pool", []):
			if BalanceDB.seed_entry(str(sid)).is_empty():
				problems.append("level %s: seed_pool id \"%s\" is not a plant with a \"seed\" block" % [level_id, str(sid)])
		for sid in level.get("seed_forced", []):
			var id := str(sid)
			if seen.has(id):
				problems.append("level %s: seed_forced id \"%s\" is duplicated" % [level_id, id])
			seen[id] = true
			if not pool.has(id):
				problems.append("level %s: seed_forced id \"%s\" is not in the pool" % [level_id, id])
		var forced: Array[String] = rules["forced"]
		var slots: int = rules["slots"]
		if forced.size() > slots:
			problems.append("level %s: seed_forced has %d ids but seed_slots is %d" % [level_id, forced.size(), slots])
		if level.has("seed_slots"):
			var raw := int(level.get("seed_slots", slots))
			if raw < 1 or raw > SeedBank.TOTAL_SLOTS:
				problems.append("level %s: seed_slots %d is outside 1..%d" % [level_id, raw, SeedBank.TOTAL_SLOTS])
	return problems


## Scene path of a map id from data/maps/<map_id>/map.json ("" when unknown).
func get_map_scene(map_id: String) -> String:
	return str(_maps.get(map_id, {}).get("scene", ""))


## The map shown before any level is picked: the first world's map.
func default_map() -> String:
	return str(_worlds[0].get("map", "")) if not _worlds.is_empty() else ""


## The battlefield map a level plays on: its own "map", else its world's.
## The only place that decides (regions can later override per level group).
func resolve_map(level_id: String) -> String:
	var level := get_level(level_id)
	if level.is_empty():
		return ""
	var own := str(level.get("map", ""))
	if not own.is_empty():
		return own
	return str(get_world(str(level.get("world_id", ""))).get("map", ""))


## Total enemies in a level (killed/total progress denominator).
static func level_total(level: Dictionary) -> int:
	var total := 0
	for wave in level.get("waves", []):
		if not (wave is Dictionary):
			continue
		for spawn in (wave as Dictionary).get("spawns", []):
			if spawn is Dictionary:
				total += int((spawn as Dictionary).get("count", 0))
	return total


## Flag fractions (0..1) at the END of each huge wave, in wave order.
## Pure math so the progress bar and tests share one implementation.
static func flag_fractions(level: Dictionary) -> Array[float]:
	var flags: Array[float] = []
	var total := level_total(level)
	if total <= 0:
		return flags
	var cumulative := 0
	for wave in level.get("waves", []):
		if not (wave is Dictionary):
			continue
		for spawn in (wave as Dictionary).get("spawns", []):
			if spawn is Dictionary:
				cumulative += int((spawn as Dictionary).get("count", 0))
		if bool((wave as Dictionary).get("is_huge", false)):
			flags.append(clampf(float(cumulative) / float(total), 0.0, 1.0))
	return flags


static func huge_wave_count(level: Dictionary) -> int:
	var count := 0
	for wave in level.get("waves", []):
		if wave is Dictionary and bool((wave as Dictionary).get("is_huge", false)):
			count += 1
	return count
