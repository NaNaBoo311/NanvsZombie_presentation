extends RefCounted

# --progress-test: checks Progress's unlock rules, star / Jade payouts, Seed Shrine
# purchases and save format against fixture worlds and plants (never the real
# data/) and a throwaway save file
# (never user://save.cfg). Prints "[ProgressTest] PASS" or each failure, then
# quits with exit code 0 / 1. Loaded only by Progress._ready() under the flag.

const TEST_SAVE := "user://save_progress_test.cfg"


## Same lookups Progress uses on LevelDB, over in-memory worlds.
class FixtureDB:
	var worlds := {
		"a": {"unlock": "start", "levels": ["a1", "a2", "a3"]},
		"b": {"unlock": {"after": ["a2"]}, "levels": ["b1", "b2"]},
		"c": {"unlock": {"after": ["a2"]}, "levels": ["c1"]},
		"d": {"unlock": {"after": ["a3", "b2"]}, "levels": ["d1"]},
		"x": {"unlock": "bogus", "levels": ["x1"]},
		"s": {"unlock": {"stars": 4}, "levels": ["s1"]},
	}
	var levels := {"c1": {"difficulty": "hard"}, "a2": {"difficulty": "normal"}}

	func get_level(level_id: String) -> Dictionary:
		return levels.get(level_id, {})

	func get_world(world_id: String) -> Dictionary:
		return worlds.get(world_id, {})

	func get_level_ids(world_id: String) -> Array[String]:
		var ids: Array[String] = []
		ids.assign(get_world(world_id).get("levels", []))
		return ids

	func world_of(level_id: String) -> String:
		for world_id in worlds:
			if (worlds[world_id]["levels"] as Array).has(level_id):
				return world_id
		return ""


## Same lookups Progress uses on BalanceDB, over in-memory seed unlocks.
class FixtureUnits:
	var unlocks := {"p_start": null, "p_after": {"after": "d1"}, "p_jade": {"jade": 100}}

	func seed_unlock(plant_id: String) -> Variant:
		return unlocks.get(plant_id, null)

	func after_unlock_plants() -> Array[String]:
		return ["p_after"]


var _failures: Array[String] = []
var _signals := 0


func run(progress: Node) -> void:
	progress._db = FixtureDB.new()
	progress._units = FixtureUnits.new()
	progress._save_path = TEST_SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	progress._load()
	EventBus.progress_changed.connect(func() -> void: _signals += 1)

	_check(progress.is_world_unlocked("a"), "start world unlocked")
	_check(not progress.is_world_unlocked("b"), "gated world locked at start")
	_check(not progress.is_world_unlocked("x"), "bad unlock rule stays locked")
	_check(not progress.is_world_unlocked("nope"), "unknown world locked")
	_check(progress.is_level_unlocked("a1"), "first level of start world unlocked")
	_check(not progress.is_level_unlocked("a2"), "second level locked at start")
	_check(not progress.is_level_unlocked("b1"), "first level of locked world locked")

	progress.mark_completed("a1")
	progress.mark_completed("a1")
	_check(_signals == 1, "repeat completion signals once (got %d)" % _signals)
	_check(progress.is_level_unlocked("a2") and not progress.is_level_unlocked("a3"), "completing a1 opens a2 only")

	progress.mark_completed("a2")
	_check(progress.is_world_unlocked("b") and progress.is_world_unlocked("c"), "one trigger opens two worlds")
	_check(progress.is_level_unlocked("b1") and progress.is_level_unlocked("c1"), "their first levels open")
	_check(not progress.is_level_unlocked("b2"), "their second levels stay locked")
	_check(not progress.is_world_unlocked("d"), "all-of rule not met yet")

	for level_id in ["a3", "b1", "b2"]:
		progress.mark_completed(level_id)
	_check(progress.is_world_unlocked("d"), "all-of rule met")
	_check(progress.completed_count("a") == 3 and progress.completed_count("b") == 2, "completed counts")

	progress.mark_completed("ghost_level")
	_check(not progress.is_level_completed("ghost_level"), "unknown level not recorded")

	progress._completed.clear()
	progress._load()
	_check(progress.completed_count("a") == 3 and progress.is_world_unlocked("d"), "save round-trips")

	progress.set_last_loadout("a", ["lotus_shooter", "sacred_rice"])
	_check(progress.last_loadout("a") == ["lotus_shooter", "sacred_rice"], "last loadout reads back")
	_check(progress.last_loadout("b") == [], "missing last loadout reads as empty")
	progress._last_loadouts.clear()
	progress._load()
	_check(progress.last_loadout("a") == ["lotus_shooter", "sacred_rice"], "last loadout round-trips")

	# Stars and Jade: jade = base[difficulty] * (first clear ? 1 : REPLAY_FACTOR) + 10 * new stars.
	_check(progress.total_stars() == 0 and not progress.is_world_unlocked("s"), "star gate locked with 0 stars")
	var r: Dictionary = progress.award("c1", 3)
	_check(r.get("jade", -1) == 110 and r.get("first_clear", false) and r.get("new_stars", -1) == 3, "hard first clear pays 80 + 3 stars (got %s)" % str(r))
	r = progress.award("c1", 2)
	_check(r.get("jade", -1) == 40 and progress.stars_of("c1") == 3, "replay pays half base, keeps best stars (got %s)" % str(r))
	r = progress.award("a1", 2)
	_check(r.get("jade", -1) == 35 and progress.total_stars() == 5, "replay with new stars (got %s)" % str(r))
	_check(progress.is_world_unlocked("s"), "star gate opens at 4 stars")
	_check(progress.award("ghost_level", 3).is_empty(), "unknown level awards nothing")

	# Plants: owned from the start, awakened by a level, or bought with Jade.
	_check(progress.is_plant_owned("p_start") and not progress.is_plant_owned("p_after") and not progress.is_plant_owned("p_jade"), "plant ownership at start")
	r = progress.award("d1", 1)
	_check(r.get("awakened", []) == ["p_after"] and progress.is_plant_owned("p_after"), "clearing d1 awakens p_after (got %s)" % str(r))
	_check(progress.jade == 225, "wallet sums payouts (got %d)" % progress.jade)
	_check(progress.buy_plant("p_jade") and progress.is_plant_owned("p_jade") and progress.jade == 125, "buy plant")
	_check(not progress.buy_plant("p_jade") and progress.plant_price("p_jade") == 0, "bought plant is not for sale again")

	# Seed slots: BASE_SLOTS, then SLOT_COST * SLOT_GROWTH^bought each.
	_check(progress.seed_slots() == progress.BASE_SLOTS and progress.next_slot_cost() == 100, "base slots and first slot price")
	_check(progress.buy_slot() and progress.seed_slots() == progress.BASE_SLOTS + 1 and progress.jade == 25, "buy slot")
	_check(progress.next_slot_cost() == 150 and not progress.buy_slot(), "second slot costs 150 and is refused at 25 Jade")

	progress.mark_seen("intro:a1")
	_check(progress.has_seen("intro:a1") and not progress.has_seen("intro:a2"), "story seen keys")

	progress._load()
	_check(progress.jade == 25 and progress.stars_of("c1") == 3 and progress.total_stars() == 6, "stars and Jade round-trip")
	_check(progress.is_plant_owned("p_jade") and progress.seed_slots() == progress.BASE_SLOTS + 1, "purchases round-trip")
	_check(progress.has_seen("intro:a1"), "seen keys round-trip")

	var v2 := ConfigFile.new()
	v2.set_value("meta", "version", 2)
	v2.set_value("progress", "completed", ["a1"])
	v2.save(TEST_SAVE)
	progress._load()
	_check(progress.completed_count("a") == 0 and progress.jade == 0, "v2 save starts fresh")

	var old := ConfigFile.new()
	old.set_value("progress", "unlocked", ["a2"])
	old.save(TEST_SAVE)
	progress._load()
	_check(progress.completed_count("a") == 0, "v1 save starts fresh")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	if _failures.is_empty():
		print("[ProgressTest] PASS")
	else:
		for f in _failures:
			print("[ProgressTest] FAIL: %s" % f)
	progress.get_tree().quit(0 if _failures.is_empty() else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
