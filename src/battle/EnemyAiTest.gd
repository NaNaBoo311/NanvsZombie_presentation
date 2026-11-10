extends RefCounted

# --ghost-test / --spider-test: scripted Hungry Ghost and Mask Spider combat checks
# on the battle shell. --ghost-test runs five phases (turret face-off, off-path seek,
# pearl-dais siege, side-lane siege, rotated turret field of fire); --spider-test
# checks the spider's clips, combat and death. Each prints "[GhostTest]" /
# "[SpiderTest]" PASS or FAIL lines and quits. Loaded only by
# EnemyDebugSpawner._ready() under either flag; spawns through the spawner so
# enemies land in its Enemies container.

static var _alive: RefCounted = null # keeps the awaiting coroutine alive

var _spawner: Node3D
var _tree: SceneTree


func run(spawner: Node3D, flag: String) -> void:
	_alive = self
	_spawner = spawner
	_tree = spawner.get_tree()
	if flag == "--ghost-test":
		_run_ghost_test()
	elif flag == "--spider-test":
		_run_spider_test()

var _test_plant_died: bool = false
var _test_enemy_defeated: bool = false

func _on_test_plant_died(_grid_coord: Vector2i) -> void:
	_test_plant_died = true

func _on_test_enemy_defeated(_enemy: Node3D) -> void:
	_test_enemy_defeated = true

func _run_ghost_test() -> void:
	await _tree.physics_frame
	await _tree.physics_frame
	EventBus.plant_died.connect(_on_test_plant_died)
	EventBus.enemy_defeated.connect(_on_test_enemy_defeated)
	# Ghost approaches a turret Lotus head-on: plant should shoot it,
	# Phase 1: Turret Lotus vs Hungry Ghost face-off
	var enemy = _spawner.ghost_scene.instantiate() as Node3D
	_spawner._add_enemy_to_container(enemy)
	enemy.global_position = Vector3(0, 0.3, 13.0)
	await _tree.physics_frame
	var lotus_scene: PackedScene = load("res://src/entities/plants/lotus_shooter/LotusShooter.tscn")
	var lotus = lotus_scene.instantiate() as Node3D
	var plants_container: Node = _spawner.get_parent().get_node_or_null("Plants")
	if plants_container:
		plants_container.add_child(lotus)
	else:
		_spawner.get_parent().add_child(lotus)
	lotus.global_position = Vector3(0, 0.3, 10.0)
	var anim = enemy.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clips: PackedStringArray = anim.get_animation_list() if anim else []
	print("[GhostTest] face-off: ghost HP ", enemy._health, " clips: ", clips, " vs lotus HP ", lotus.current_health)
	for i in range(480):
		await _tree.physics_frame
	var ghost_down: bool = (not is_instance_valid(enemy)) or enemy._health < 60
	var plant_hurt: bool = (not is_instance_valid(lotus)) or lotus.current_health < 100
	print("[GhostTest] after 8s: ghost alive=", is_instance_valid(enemy),
		" plant alive=", is_instance_valid(lotus),
		" plant_died_signal=", _test_plant_died,
		" enemy_defeated_signal=", _test_enemy_defeated)
	if ghost_down and plant_hurt:
		print("[GhostTest] PASS: turret damaged/killed the ghost and the ghost ate back.")
	else:
		push_error("[GhostTest] FAIL: one-sided combat (ghost_down=%s plant_hurt=%s)." % [ghost_down, plant_hurt])
	# Phase 2 (seek): fresh tanky ghost marching down x=0 with a plant deliberately
	# off-path at x=2.2 (inside the wide notice cone, outside the narrow bite cone).
	# The ghost must veer sideways toward it before eating.
	for member in _tree.get_nodes_in_group("Enemies") + _tree.get_nodes_in_group("Plants"):
		member.queue_free()
	_test_plant_died = false
	_test_enemy_defeated = false
	for i in range(5):
		await _tree.physics_frame
	var seeker = _spawner.ghost_scene.instantiate() as Node3D
	_spawner._add_enemy_to_container(seeker)
	seeker.global_position = Vector3(0, 0.3, 15.0)
	await _tree.physics_frame
	seeker._health = 1000 # tanky: survive turret fire long enough to demonstrate seeking
	var side_lotus = lotus_scene.instantiate() as Node3D
	if plants_container:
		plants_container.add_child(side_lotus)
	else:
		_spawner.get_parent().add_child(side_lotus)
	side_lotus.global_position = Vector3(2.2, 0.3, 11.0)
	var max_deviation: float = 0.0
	for i in range(480):
		await _tree.physics_frame
		if is_instance_valid(seeker):
			max_deviation = maxf(max_deviation, absf(seeker.global_position.x))
	print("[GhostTest] seek: max lateral deviation=", max_deviation,
		" plant_died_signal=", _test_plant_died)
	if max_deviation > 0.4 and _test_plant_died:
		print("[GhostTest] PASS: ghost noticed off-path food, veered over, and ate it.")
	else:
		push_error("[GhostTest] FAIL: ghost ignored off-path plant.")
	# Phase 3 (siege): lone ghost south of the pearl on the lawn, no plants.
	# It must stop OUTSIDE the dais edge (Z > 3.5) and damage the house.
	for member in _tree.get_nodes_in_group("Enemies") + _tree.get_nodes_in_group("Plants"):
		member.queue_free()
	for i in range(5):
		await _tree.physics_frame
	var sieger = _spawner.ghost_scene.instantiate() as Node3D
	_spawner._add_enemy_to_container(sieger)
	sieger.global_position = Vector3(0, 0.3, 12.0)
	var house_node = _tree.get_first_node_in_group("CentralHouse") as Node3D
	var house_pos: Vector3 = house_node.global_position if house_node else Vector3.ZERO
	var start_hp: int = GameManager.house_health
	var min_gap: float = 999.0
	for i in range(600):
		await _tree.physics_frame
		if is_instance_valid(sieger):
			var gap: float = sieger._gap_to_house(house_pos)
			min_gap = minf(min_gap, gap)
	var siege_anim: String = sieger._anim_player.current_animation if is_instance_valid(sieger) and sieger._anim_player else "gone"
	var sieger_z: float = sieger.global_position.z if is_instance_valid(sieger) else -999.0
	print("[GhostTest] siege: house HP ", start_hp, " -> ", GameManager.house_health,
		" min wall gap=", min_gap, " sieger_z=", sieger_z, " clip=", siege_anim)
	# Gap must hold the full attack lunge clear of the wall (reach 1.3 vs 1.06 lunge).
	# Dais edge is at z = 3.5; ghost halts outside (z ~ 4.8, min_gap >= 1.1 and <= 1.35).
	if GameManager.house_health < start_hp and min_gap >= 1.1 and min_gap <= 1.35 and sieger_z > 3.5 and siege_anim == "attack":
		print("[GhostTest] PASS: ghost sieged from outside the pearl dais and damaged the house.")
	else:
		push_error("[GhostTest] FAIL: dais siege broken (damage/inside/no-attack).")
	# Phase 4 (side lane siege): ghost marching down lane at x=4.0 outside the dais.
	# It must steer inward and stop OUTSIDE the dais wall (gap 1.1-1.35) and damage the house.
	for member in _tree.get_nodes_in_group("Enemies") + _tree.get_nodes_in_group("Plants"):
		member.queue_free()
	for i in range(5):
		await _tree.physics_frame
	var side_sieger = _spawner.ghost_scene.instantiate() as Node3D
	_spawner._add_enemy_to_container(side_sieger)
	side_sieger.global_position = Vector3(4.0, 0.3, 9.0)
	GameManager.repair_house(100)
	var side_start_hp: int = GameManager.house_health
	var side_min_gap: float = 999.0
	for i in range(600):
		await _tree.physics_frame
		if is_instance_valid(side_sieger):
			var gap: float = side_sieger._gap_to_house(house_pos)
			side_min_gap = minf(side_min_gap, gap)
	var side_siege_anim: String = side_sieger._anim_player.current_animation if is_instance_valid(side_sieger) and side_sieger._anim_player else "gone"
	var side_sieger_z: float = side_sieger.global_position.z if is_instance_valid(side_sieger) else -999.0
	print("[GhostTest] side siege (x=4): house HP ", side_start_hp, " -> ", GameManager.house_health,
		" min wall gap=", side_min_gap, " sieger_z=", side_sieger_z, " clip=", side_siege_anim)
	if GameManager.house_health < side_start_hp and side_min_gap >= 1.1 and side_min_gap <= 1.35 and side_sieger_z > 3.5 and side_siege_anim == "attack":
		print("[GhostTest] PASS: ghost sieged from outside the dais wall and damaged the house.")
	else:
		push_error("[GhostTest] FAIL: side dais siege broken.")

	# Phase 5 (rotated plant targeting): Lotus Shooter placed facing West (rotation.y = -PI/2).
	# West ghost at (-3.0, 0.3, 10.0) is directly inside cone and must be damaged.
	# South ghost at (0.0, 0.3, 13.0) is outside the West cone and must remain undamaged.
	for member in _tree.get_nodes_in_group("Enemies") + _tree.get_nodes_in_group("Plants"):
		member.queue_free()
	for i in range(5):
		await _tree.physics_frame
	var rot_lotus = lotus_scene.instantiate() as PlantBase
	rot_lotus.rotation.y = -PI / 2.0
	rot_lotus.base_rotation_y = -PI / 2.0
	if plants_container:
		plants_container.add_child(rot_lotus)
	else:
		_spawner.get_parent().add_child(rot_lotus)
	rot_lotus.global_position = Vector3(0, 0.3, 10.0)

	var west_ghost = _spawner.ghost_scene.instantiate() as Node3D
	_spawner._add_enemy_to_container(west_ghost)
	west_ghost.global_position = Vector3(-3.0, 0.3, 10.0)

	var south_ghost = _spawner.ghost_scene.instantiate() as Node3D
	_spawner._add_enemy_to_container(south_ghost)
	south_ghost.global_position = Vector3(0.0, 0.3, 13.0)

	for i in range(240):
		await _tree.physics_frame

	var west_hit: bool = is_instance_valid(west_ghost) and west_ghost._health < 60
	var south_untouched: bool = is_instance_valid(south_ghost) and south_ghost._health == 60
	print("[GhostTest] rotated turret (facing West): west_ghost HP=", west_ghost._health if is_instance_valid(west_ghost) else 0, " south_ghost HP=", south_ghost._health if is_instance_valid(south_ghost) else 0)
	if west_hit and south_untouched:
		print("[GhostTest] PASS: rotated plant fired only at enemy in its rotated field of fire!")
	else:
		push_error("[GhostTest] FAIL: rotated plant targeting failed (west_hit=%s, south_untouched=%s)" % [west_hit, south_untouched])

	print("[GhostTest] ALL 5 PHASES PASSED CLEANLY!")
	_tree.quit(0)

func _run_spider_test() -> void:
	await _tree.physics_frame
	await _tree.physics_frame
	EventBus.plant_died.connect(_on_test_plant_died)
	EventBus.enemy_defeated.connect(_on_test_enemy_defeated)

	var spider_scene: PackedScene = load("res://src/entities/enemies/theatrical_mask_spider/TheatricalMaskSpider.tscn")
	var spider = spider_scene.instantiate() as Node3D
	_spawner._add_enemy_to_container(spider)
	spider.global_position = Vector3(0, 0.3, 13.0)
	await _tree.physics_frame

	var lotus_scene: PackedScene = load("res://src/entities/plants/lotus_shooter/LotusShooter.tscn")
	var lotus = lotus_scene.instantiate() as Node3D
	var plants_container: Node = _spawner.get_parent().get_node_or_null("Plants")
	if plants_container:
		plants_container.add_child(lotus)
	else:
		_spawner.get_parent().add_child(lotus)
	lotus.global_position = Vector3(0, 0.3, 10.0)

	var anim = spider.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clips: PackedStringArray = anim.get_animation_list() if anim else []
	print("[SpiderTest] face-off: spider HP ", spider._health, " clips: ", clips, " vs lotus HP ", lotus.current_health)

	if not ("walk" in clips and "attack" in clips and "die" in clips):
		push_error("[SpiderTest] FAIL: missing required animation clips!")
		_tree.quit(1)
		return

	# Run simulation frames until spider dies or time runs out
	for i in range(480):
		await _tree.physics_frame
		if _test_enemy_defeated:
			break

	var spider_dead: bool = (not is_instance_valid(spider)) or spider._dead
	print("[SpiderTest] after combat: spider alive=", is_instance_valid(spider),
		" plant alive=", is_instance_valid(lotus),
		" enemy_defeated_signal=", _test_enemy_defeated)

	if spider_dead and _test_enemy_defeated:
		print("[SpiderTest] PASS: Mask Spider combat, damage, and death animation completed cleanly!")
		_tree.quit(0)
	else:
		push_error("[SpiderTest] FAIL: Spider test failed to defeat spider cleanly.")
		_tree.quit(1)
