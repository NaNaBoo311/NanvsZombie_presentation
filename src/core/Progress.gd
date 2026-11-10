extends Node

# Progress — campaign progress + the local save (no backend; one save per device).
# Stores completed level ids, best stars per level, the Leyline Jade wallet, the
# Jade purchases (plants, extra seed slots) and which story beats were seen.
# Every unlock is derived on demand from the LevelDB / BalanceDB data by the
# rules below, so a new rule never changes the save format:
#   world unlocked = its "unlock" is "start", or every level in {"after": [...]}
#                    is completed, or total_stars() >= N for {"stars": N}
#   level unlocked = completed, or its world is unlocked and it is first in the
#                    world's "levels" list or the previous level is completed
#   plant owned    = its seed "unlock" is missing, or {"after": level id} is
#                    completed, or {"jade": N} was bought in the Seed Shrine
# Meta economy (Leyline Jade; never converts into battle sun):
#   jade  = JADE_BASE[difficulty] * (first clear ? 1 : REPLAY_FACTOR) + JADE_PER_STAR * new stars
#   slots = BASE_SLOTS + bought; the next slot costs SLOT_COST * SLOT_GROWTH^bought
# Save v3 (user://save.cfg): [meta] version=3, [progress] completed=[level ids],
# stars={level id: 1..3}, jade, plants=[bought plant ids], bonus_slots,
# seen=[story keys], optional [ui] last_world (the atlas camera starts on that
# province; UI state, never used to derive unlocks) and last_loadout_<world_id> =
# [seed ids] (this world's last confirmed briefing loadout for the prefill; UI
# state, never used to derive unlocks).
# A missing file starts empty; any other version starts fresh (pre-release, no
# migration) and the next save overwrites it. GameManager calls award() on a
# verified level win; it saves and emits EventBus.progress_changed.
# --progress-test runs ProgressTest.gd on fixture data and a throwaway save.

const SAVE_PATH := "user://save.cfg"
const SAVE_VERSION := 3
const JADE_BASE := {"easy": 30, "normal": 50, "hard": 80}
const REPLAY_FACTOR := 0.5
const JADE_PER_STAR := 10
const MAX_STARS := 3
const BASE_SLOTS := 5
const SLOT_COST := 100
const SLOT_GROWTH := 1.5

var _save_path := SAVE_PATH
var _completed: Dictionary = {} # level_id -> true
var _stars: Dictionary = {} # level_id -> best stars 1..MAX_STARS
var jade: int = 0
var _bought_plants: Dictionary = {} # plant_id -> true
var bonus_slots: int = 0
var _seen: Dictionary = {} # story key ("intro:<level>", "enemy:<id>") -> true
var last_world: String = ""
var _last_loadouts: Dictionary = {} # world_id -> Array[String]
# LevelDB, or a fixture with the same get_world / get_level / get_level_ids / world_of (tests).
var _db: Object = null
# BalanceDB, or a fixture with the same seed_unlock (tests).
var _units: Object = null


func _ready() -> void:
	_db = LevelDB
	_units = BalanceDB
	if "--progress-test" in OS.get_cmdline_user_args():
		load("res://src/core/ProgressTest.gd").new().run(self)
		return
	_load()


func is_world_unlocked(world_id: String) -> bool:
	var world: Dictionary = _db.get_world(world_id)
	if world.is_empty():
		return false
	var unlock: Variant = world.get("unlock", null)
	if unlock is String:
		return unlock == "start"
	if unlock is Dictionary and (unlock as Dictionary).get("after", null) is Array:
		for level_id in (unlock as Dictionary)["after"]:
			if not _completed.has(str(level_id)):
				return false
		return true
	if unlock is Dictionary and (unlock as Dictionary).has("stars"):
		return total_stars() >= int((unlock as Dictionary)["stars"])
	return false


func is_level_unlocked(level_id: String) -> bool:
	if _completed.has(level_id):
		return true
	var world_id: String = _db.world_of(level_id)
	if world_id.is_empty() or not is_world_unlocked(world_id):
		return false
	var ids: Array[String] = _db.get_level_ids(world_id)
	var idx := ids.find(level_id)
	if idx == 0:
		return true
	return idx > 0 and _completed.has(ids[idx - 1])


func is_level_completed(level_id: String) -> bool:
	return _completed.has(level_id)


func completed_count(world_id: String) -> int:
	var count := 0
	for level_id in _db.get_level_ids(world_id):
		if _completed.has(level_id):
			count += 1
	return count


## True when the local save has at least one completed level (title's Continue).
func has_progress() -> bool:
	return not _completed.is_empty()


## Record a won level. Idempotent: a replayed win saves and signals nothing.
func mark_completed(level_id: String) -> void:
	if _completed.has(level_id):
		return
	if str(_db.world_of(level_id)).is_empty():
		push_warning("[Progress] Ignoring completion of unknown level %s." % level_id)
		return
	_completed[level_id] = true
	_save()
	EventBus.progress_changed.emit()


## Record a won level with its stars (1..MAX_STARS) and pay out Jade.
## Returns {jade, stars, new_stars, first_clear, awakened: [plant ids now owned]};
## an unknown level returns {} and records nothing.
func award(level_id: String, stars: int) -> Dictionary:
	if str(_db.world_of(level_id)).is_empty():
		push_warning("[Progress] Ignoring completion of unknown level %s." % level_id)
		return {}
	stars = clampi(stars, 1, MAX_STARS)
	var first_clear := not _completed.has(level_id)
	var owned_before := _owned_after_plants()
	var new_stars := maxi(0, stars - stars_of(level_id))
	var base := int(JADE_BASE.get(str(_db.get_level(level_id).get("difficulty", "easy")), JADE_BASE["easy"]))
	var earned := (base if first_clear else int(base * REPLAY_FACTOR)) + JADE_PER_STAR * new_stars
	_completed[level_id] = true
	_stars[level_id] = maxi(stars, stars_of(level_id))
	jade += earned
	var awakened: Array[String] = []
	for plant_id in _owned_after_plants():
		if not owned_before.has(plant_id):
			awakened.append(plant_id)
	_save()
	EventBus.progress_changed.emit()
	return {"jade": earned, "stars": stars, "new_stars": new_stars, "first_clear": first_clear, "awakened": awakened}


## Best stars earned on a level (0 when never won).
func stars_of(level_id: String) -> int:
	return int(_stars.get(level_id, 0))


func total_stars() -> int:
	var total := 0
	for level_id in _stars:
		total += int(_stars[level_id])
	return total


## Whether the player may pack this plant (see the header rules).
func is_plant_owned(plant_id: String) -> bool:
	var unlock: Variant = _units.seed_unlock(plant_id)
	if not (unlock is Dictionary):
		return true
	if (unlock as Dictionary).has("after"):
		return _completed.has(str(unlock["after"]))
	if (unlock as Dictionary).has("jade"):
		return _bought_plants.has(plant_id)
	return true


## Jade price of a plant still for sale in the Seed Shrine, else 0.
func plant_price(plant_id: String) -> int:
	var unlock: Variant = _units.seed_unlock(plant_id)
	if unlock is Dictionary and (unlock as Dictionary).has("jade") and not _bought_plants.has(plant_id):
		return int(unlock["jade"])
	return 0


func buy_plant(plant_id: String) -> bool:
	var price := plant_price(plant_id)
	if price <= 0 or jade < price:
		return false
	jade -= price
	_bought_plants[plant_id] = true
	_save()
	EventBus.progress_changed.emit()
	return true


## Seed-bank slots the player owns (a level's own seed_slots can only lower it).
func seed_slots() -> int:
	return BASE_SLOTS + bonus_slots


## Jade price of the next seed slot, or 0 when the bank is already full.
func next_slot_cost() -> int:
	if seed_slots() >= SeedBank.TOTAL_SLOTS:
		return 0
	return int(round(SLOT_COST * pow(SLOT_GROWTH, bonus_slots)))


func buy_slot() -> bool:
	var price := next_slot_cost()
	if price <= 0 or jade < price:
		return false
	jade -= price
	bonus_slots += 1
	_save()
	EventBus.progress_changed.emit()
	return true


## Story beats shown once per save ("intro:<level id>", "enemy:<enemy id>").
func has_seen(key: String) -> bool:
	return _seen.has(key)


func mark_seen(key: String) -> void:
	if _seen.has(key):
		return
	_seen[key] = true
	_save()


## Plants with an {"after": level} unlock that the completed levels already grant.
func _owned_after_plants() -> Array[String]:
	var out: Array[String] = []
	for plant_id in _units.after_unlock_plants():
		if is_plant_owned(plant_id):
			out.append(plant_id)
	return out


func _load() -> void:
	_completed.clear()
	_stars.clear()
	jade = 0
	_bought_plants.clear()
	bonus_slots = 0
	_seen.clear()
	last_world = ""
	_last_loadouts.clear()
	var cfg := ConfigFile.new()
	if cfg.load(_save_path) != OK:
		return
	var version := int(cfg.get_value("meta", "version", 1))
	if version != SAVE_VERSION:
		print("[Progress] Save %s is v%d, not v%d: starting fresh." % [_save_path, version, SAVE_VERSION])
		return
	for level_id in cfg.get_value("progress", "completed", []):
		_completed[str(level_id)] = true
	var stars: Variant = cfg.get_value("progress", "stars", {})
	if stars is Dictionary:
		for level_id in stars:
			_stars[str(level_id)] = clampi(int(stars[level_id]), 0, MAX_STARS)
	jade = maxi(0, int(cfg.get_value("progress", "jade", 0)))
	for plant_id in cfg.get_value("progress", "plants", []):
		_bought_plants[str(plant_id)] = true
	bonus_slots = maxi(0, int(cfg.get_value("progress", "bonus_slots", 0)))
	for key in cfg.get_value("progress", "seen", []):
		_seen[str(key)] = true
	last_world = str(cfg.get_value("ui", "last_world", ""))
	if cfg.has_section("ui"):
		for key in cfg.get_section_keys("ui"):
			if str(key).begins_with("last_loadout_"):
				var world_id := str(key).trim_prefix("last_loadout_")
				var ids: Array[String] = []
				for sid in cfg.get_value("ui", key, []):
					ids.append(str(sid))
				_last_loadouts[world_id] = ids


func set_last_world(world_id: String) -> void:
	if world_id == last_world:
		return
	last_world = world_id
	_save()


## This world's last confirmed briefing loadout, or [] when none was saved.
func last_loadout(world_id: String) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_last_loadouts.get(world_id, []))
	return ids


func set_last_loadout(world_id: String, ids: Array) -> void:
	var cleaned: Array[String] = []
	for sid in ids:
		cleaned.append(str(sid))
	_last_loadouts[world_id] = cleaned
	_save()


func _save() -> void:
	var ids: Array = _completed.keys()
	ids.sort()
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("progress", "completed", ids)
	cfg.set_value("progress", "stars", _stars.duplicate())
	cfg.set_value("progress", "jade", jade)
	var plants: Array = _bought_plants.keys()
	plants.sort()
	cfg.set_value("progress", "plants", plants)
	cfg.set_value("progress", "bonus_slots", bonus_slots)
	var seen: Array = _seen.keys()
	seen.sort()
	cfg.set_value("progress", "seen", seen)
	if not last_world.is_empty():
		cfg.set_value("ui", "last_world", last_world)
	for world_id in _last_loadouts:
		cfg.set_value("ui", "last_loadout_" + str(world_id), (_last_loadouts[world_id] as Array).duplicate())
	var err := cfg.save(_save_path)
	if err != OK:
		push_warning("[Progress] Could not write %s (error %d)." % [_save_path, err])
