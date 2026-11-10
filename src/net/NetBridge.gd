extends Node

# LAN battle bridge (CONTRACT(lan-coop)). DioramaWorld creates it only while
# Net.is_online(), so solo play holds no extra node and no per-frame work.
#
# The host is the simulation authority. It mirrors the authoritative events to
# the guest and answers the guest's commands; the guest renders replicated
# state, never simulates combat, and sends intents only. Net ids are allocated
# by the host when an entity is announced; plants are keyed by grid coord
# instead, because the tile is the identity on both peers.
#
# Host -> guest, reliable: full, sun, house, state, tick, loadout, progress,
#   plant_add / plant_hp / plant_gone, enemy_add / enemy_gone,
#   gem_add / gem_gone, wave / wave_done / huge, shot, preview.
# Host -> guest, unreliable_ordered at 10 Hz: enemy rows
#   [net_id, x, y, z, yaw, hp, clip, max_hp]; a lost snapshot is replaced by the
#   next one, so lag never accumulates.
# Guest -> host, reliable: map_ready, place, dig_plant, dig_enemy, collect, preview.
#
# `preview` runs both ways: each device's uncommitted placement ghost (seed, tile,
# facing step, validity; empty seed = hidden), sent only when it changes
# (EventBus.placement_preview_changed) and drawn by the partner's PlacementManager.
#
# Guest entity scenes: remote plants/enemies/gems/projectiles carry is_remote,
# which turns off AI, combat, collision and damage in their own scripts. The
# guest's full-sync clear is idempotent, so the host can re-send full while the
# guest is still loading its battle scene; the guest repeats map_ready until the
# first full arrives, because either bridge may finish loading first.

const GEM_SCENE := preload("res://src/entities/plants/sacred_rice/RiceGem.tscn")
const SNAPSHOT_INTERVAL := 0.1
const FULL_RETRY_SEC := 0.5
const FULL_RETRIES := 4

## Filled by DioramaWorld before add_child (the shell owns the containers).
var plants_container: Node3D = null
var enemies_container: Node3D = null
var placement: PlacementManager = null

var _next_id: int = 0
var _enemies: Dictionary = {} # net id -> HungryGhost
var _gems: Dictionary = {} # net id -> RiceGem
var _snapshot_clock: float = 0.0
var _full_retries: int = 0
var _full_clock: float = 0.0
var _synced: bool = false
var _ready_retries: int = 40 # guest: 0.5 s each while the host bridge may be loading
var _ready_clock: float = 0.0


func _ready() -> void:
	if Net == null:
		return
	if Net.is_host():
		EventBus.plant_placed.connect(_on_plant_placed)
		EventBus.plant_died.connect(_on_plant_died)
		EventBus.plant_health_changed.connect(_on_plant_health_changed)
		EventBus.enemy_spawned.connect(_on_enemy_spawned)
		EventBus.enemy_defeated.connect(_on_enemy_defeated)
		EventBus.gem_spawned.connect(_on_gem_spawned)
		EventBus.gem_collected.connect(_on_gem_collected)
		EventBus.sun_amount_changed.connect(_on_sun_changed)
		EventBus.house_health_changed.connect(_on_house_changed)
		EventBus.round_state_changed.connect(_on_round_state_changed)
		EventBus.setup_tick.connect(_on_setup_tick)
		EventBus.seed_loadout_changed.connect(_on_loadout_changed)
		EventBus.level_progress_changed.connect(_on_progress_changed)
		EventBus.wave_started.connect(_on_wave_started)
		EventBus.wave_completed.connect(_on_wave_completed)
		EventBus.huge_wave_incoming.connect(_on_huge_wave)
		EventBus.projectile_fired.connect(_on_projectile_fired)
		EventBus.placement_preview_changed.connect(_on_local_preview)
		Net.command_received.connect(_on_command)
		Net.guest_joined.connect(_on_guest_joined)
		Net.guest_left.connect(_on_guest_left)
		_full_retries = FULL_RETRIES
		set_process(Net.guest_connected())
		_send_full()
	else:
		Net.event_received.connect(_on_event)
		Net.snapshot_received.connect(_on_snapshot)
		EventBus.placement_preview_changed.connect(_on_local_preview)
		# The host's bridge may not exist yet (it can still be loading), so
		# repeat map_ready until the first full arrives instead of sending it
		# once into the void.
		set_process(true)
		_announce_ready.call_deferred()


func _process(delta: float) -> void:
	if Net == null:
		return
	if not Net.is_host():
		if _synced:
			set_process(false)
			return
		_ready_clock += delta
		if _ready_clock >= FULL_RETRY_SEC:
			_ready_clock = 0.0
			_ready_retries -= 1
			if _ready_retries <= 0:
				set_process(false)
				return
			Net.send_command({"t": "map_ready"})
		return
	if not Net.guest_connected():
		set_process(false)
		return
	# Until the guest answers map_ready it may still be loading its battle
	# scene; repeat the snapshot so neither side can miss the other's ready.
	if _full_retries > 0:
		_full_clock += delta
		if _full_clock >= FULL_RETRY_SEC:
			_full_clock = 0.0
			_full_retries -= 1
			_send_full()
	_snapshot_clock += delta
	if _snapshot_clock >= SNAPSHOT_INTERVAL:
		_snapshot_clock = 0.0
		_send_snapshot()


func _on_guest_left() -> void:
	set_process(false)
	if placement != null:
		placement.show_partner_preview("", Vector2i.ZERO, 0, false, 1)


func _on_guest_joined() -> void:
	# Late host (--net-test hosts after the battle loaded): the guest may answer
	# map_ready before or after this, so repeat full until it does.
	_full_retries = FULL_RETRIES
	_full_clock = 0.0
	set_process(true)
	_send_full()


# ========================================================
# HOST -> GUEST
# ========================================================

func _send_full() -> void:
	if Net == null or not Net.is_host() or not Net.guest_connected():
		return
	var plants: Array = []
	if placement != null:
		for coord in placement.plants_by_coord.keys():
			var plant = placement.plants_by_coord[coord]
			if not is_instance_valid(plant):
				continue
			var base := plant as PlantBase
			var hp: int = base.current_health if base != null else 0
			var max_hp: int = base.max_health if base != null else 0
			plants.append([
				str(plant.get("unit_id")), int(coord.x), int(coord.y),
				float(plant.rotation.y), int(plant.get_meta("owner_id", 0)),
				hp, max_hp,
				plant.global_position.x, plant.global_position.y, plant.global_position.z,
			])
	var enemies: Array = []
	for id in _enemies.keys():
		var enemy = _enemies[id]
		if not is_instance_valid(enemy) or enemy.is_dead():
			continue
		var pos: Vector3 = enemy.global_position
		enemies.append([
			int(id), str(enemy.unit_id), pos.x, pos.y, pos.z,
			float(enemy.rotation.y), int(enemy.remote_health()), int(enemy.max_health),
		])
	var gems: Array = []
	for id in _gems.keys():
		var gem = _gems[id]
		if not is_instance_valid(gem):
			continue
		var gpos: Vector3 = gem.global_position
		gems.append([int(id), gpos.x, gpos.y, gpos.z, int(gem.currency_value)])
	Net.send_event({
		"t": "full",
		"state": GameManager.round_state,
		"sun": GameManager.current_sun,
		"house": GameManager.house_health,
		"max_house": GameManager.max_house_health,
		"setup": GameManager.setup_left,
		"loadout": GameManager.seed_loadout.duplicate(),
		"level": GameManager.current_level_id,
		"world": GameManager.current_world_id,
		"killed": GameManager.level_killed,
		"total": GameManager.level_total,
		"plants": plants,
		"enemies": enemies,
		"gems": gems,
	})


func _on_plant_placed(plant_type: String, grid_coord: Vector2i, player_id: int) -> void:
	if not Net.guest_connected():
		return
	var plant = placement.plant_at(grid_coord) if placement != null else null
	if plant == null:
		return
	var base := plant as PlantBase
	var pos: Vector3 = plant.global_position
	Net.send_event({
		"t": "plant_add", "type": plant_type,
		"x": grid_coord.x, "z": grid_coord.y,
		"rot": float(plant.rotation.y), "owner": player_id,
		"px": pos.x, "py": pos.y, "pz": pos.z,
		"hp": base.current_health if base != null else 1,
		"max": base.max_health if base != null else 1,
	})


func _on_plant_died(grid_coord: Vector2i) -> void:
	if Net.guest_connected():
		Net.send_event({"t": "plant_gone", "x": grid_coord.x, "z": grid_coord.y})


func _on_plant_health_changed(grid_coord: Vector2i, health: int, max_health: int) -> void:
	if Net.guest_connected():
		Net.send_event({"t": "plant_hp", "x": grid_coord.x, "z": grid_coord.y, "hp": health, "max": max_health})


func _on_enemy_spawned(enemy: Node3D) -> void:
	if not Net.guest_connected() or enemy == null or not is_instance_valid(enemy):
		return
	var id := _alloc_id(enemy)
	_enemies[id] = enemy
	var pos: Vector3 = enemy.global_position
	Net.send_event({
		"t": "enemy_add", "id": id,
		"type": str(enemy.get("unit_id")),
		"x": pos.x, "y": pos.y, "z": pos.z, "yaw": float(enemy.rotation.y),
		"hp": int(enemy.remote_health()), "max": int(enemy.max_health),
	})


func _on_enemy_defeated(enemy: Node3D) -> void:
	var id := int(enemy.get_meta("net_id", 0)) if enemy != null else 0
	if id == 0:
		return
	_enemies.erase(id)
	if Net.guest_connected():
		Net.send_event({"t": "enemy_gone", "id": id})


func _on_gem_spawned(gem: Node3D) -> void:
	if not Net.guest_connected() or not (gem is RiceGem):
		return
	var rice := gem as RiceGem
	var id := _alloc_id(rice)
	rice.net_id = id
	_gems[id] = rice
	var pos: Vector3 = rice.global_position
	Net.send_event({"t": "gem_add", "id": id, "x": pos.x, "y": pos.y, "z": pos.z, "v": rice.currency_value})


func _on_gem_collected(gem: Node3D) -> void:
	var id := int(gem.get_meta("net_id", 0)) if gem != null else 0
	if id == 0:
		return
	_gems.erase(id)
	if Net.guest_connected():
		Net.send_event({"t": "gem_gone", "id": id})


func _on_sun_changed(value: int) -> void:
	if Net.guest_connected():
		Net.send_event({"t": "sun", "v": value})


func _on_house_changed(current: int, maximum: int) -> void:
	if Net.guest_connected():
		Net.send_event({"t": "house", "v": current, "max": maximum})


func _on_round_state_changed(state: String) -> void:
	if Net.guest_connected():
		Net.send_event({"t": "state", "v": state})


func _on_setup_tick(seconds_left: int) -> void:
	if Net.guest_connected():
		Net.send_event({"t": "tick", "left": seconds_left})


func _on_loadout_changed(ids: Array) -> void:
	if Net.guest_connected():
		Net.send_event({"t": "loadout", "ids": ids})


func _on_progress_changed(killed: int, total: int, _progress: float) -> void:
	if Net.guest_connected():
		Net.send_event({"t": "progress", "killed": killed, "total": total})


func _on_wave_started(index: int) -> void:
	if Net.guest_connected():
		Net.send_event({"t": "wave", "i": index})


func _on_wave_completed(index: int) -> void:
	if Net.guest_connected():
		Net.send_event({"t": "wave_done", "i": index})


func _on_huge_wave(index: int) -> void:
	if Net.guest_connected():
		Net.send_event({"t": "huge", "i": index})


func _on_projectile_fired(projectile: Node3D) -> void:
	if not Net.guest_connected() or not (projectile is Projectile):
		return
	var proj := projectile as Projectile
	var pos: Vector3 = proj.global_position
	var dir: Vector3 = proj.direction
	var ev := {
		"t": "shot", "proj": proj.projectile_id,
		"x": pos.x, "y": pos.y, "z": pos.z,
		"dx": dir.x, "dy": dir.y, "dz": dir.z,
	}
	if proj is LobbedProjectile:
		var lob := proj as LobbedProjectile
		ev["lob"] = true
		ev["tx"] = lob.target_pos.x
		ev["ty"] = lob.target_pos.y
		ev["tz"] = lob.target_pos.z
	Net.send_event(ev)


func _send_snapshot() -> void:
	var rows: Array = []
	for id in _enemies.keys():
		var enemy = _enemies[id]
		if not is_instance_valid(enemy) or enemy.is_dead():
			continue
		var pos: Vector3 = enemy.global_position
		rows.append([
			int(id), pos.x, pos.y, pos.z, float(enemy.rotation.y),
			int(enemy.remote_health()), int(enemy.remote_clip()), int(enemy.max_health),
		])
	Net.send_snapshot({"rows": rows})


# ========================================================
# GUEST -> HOST (commands)
# ========================================================

func _on_command(cmd: Dictionary) -> void:
	if Net == null or not Net.is_host() or int(cmd.get("from", 0)) != 1:
		return
	match str(cmd.get("t", "")):
		"map_ready":
			_full_retries = 0
			_send_full()
			# The guest just arrived: show it a ghost the host may already be holding.
			if placement != null:
				var p: Array = placement.published_preview()
				_on_local_preview(str(p[0]), p[1], int(p[2]), bool(p[3]), GameManager.local_player_id())
		"place":
			_host_place(cmd)
		"dig_plant":
			_host_dig_plant(cmd)
		"dig_enemy":
			_host_dig_enemy(cmd)
		"collect":
			_host_collect(cmd)
		"preview":
			_apply_partner_preview(cmd, 1)


func _host_place(cmd: Dictionary) -> void:
	if placement == null:
		return
	var plant_type := str(cmd.get("plant", ""))
	var coord := Vector2i(int(cmd.get("x", 0)), int(cmd.get("z", 0)))
	if not placement.remote_placement_allowed(plant_type, coord):
		return
	if not GameManager.spend_sun(GameManager.plant_cost(plant_type)):
		return
	placement.spawn_plant(plant_type, coord, placement.position_for_tile(coord), float(cmd.get("rot", 0.0)), 1)


func _host_dig_plant(cmd: Dictionary) -> void:
	if placement == null:
		return
	var plant = placement.plant_at(Vector2i(int(cmd.get("x", 0)), int(cmd.get("z", 0))))
	if plant != null and plant.has_method("remove_by_shovel"):
		plant.remove_by_shovel()


func _host_dig_enemy(cmd: Dictionary) -> void:
	var enemy = _enemies.get(int(cmd.get("id", 0)))
	if enemy != null and is_instance_valid(enemy) and enemy.has_method("remove_by_shovel"):
		enemy.remove_by_shovel()


func _host_collect(cmd: Dictionary) -> void:
	var gem = _gems.get(int(cmd.get("id", 0)))
	if gem != null and is_instance_valid(gem):
		gem.collect()


# ========================================================
# GUEST SIDE
# ========================================================

func _announce_ready() -> void:
	if Net != null and Net.is_guest():
		Net.send_command({"t": "map_ready"})


func _on_event(ev: Dictionary) -> void:
	if Net == null or not Net.is_guest():
		return
	match str(ev.get("t", "")):
		"full":
			_synced = true
			_apply_full(ev)
		"sun":
			GameManager.apply_remote_sun(int(ev.get("v", 0)))
		"house":
			GameManager.apply_remote_house_health(int(ev.get("v", 0)))
		"state":
			GameManager.apply_remote_round_state(str(ev.get("v", "wave")))
		"tick":
			GameManager.setup_left = int(ev.get("left", 0))
			EventBus.setup_tick.emit(GameManager.setup_left)
		"loadout":
			GameManager.set_seed_loadout(ev.get("ids", []))
		"progress":
			GameManager.apply_remote_progress(int(ev.get("killed", 0)), int(ev.get("total", 0)))
		"plant_add":
			_apply_plant_add(ev)
		"plant_hp":
			_apply_plant_hp(ev)
		"plant_gone":
			_apply_plant_gone(ev)
		"enemy_add":
			_apply_enemy_add(ev)
		"enemy_gone":
			_apply_enemy_gone(ev)
		"gem_add":
			_apply_gem_add(ev)
		"gem_gone":
			_apply_gem_gone(ev)
		"wave":
			EventBus.wave_started.emit(int(ev.get("i", 0)))
		"wave_done":
			EventBus.wave_completed.emit(int(ev.get("i", 0)))
		"huge":
			EventBus.huge_wave_incoming.emit(int(ev.get("i", 0)))
		"shot":
			_apply_shot(ev)
		"preview":
			_apply_partner_preview(ev, 0)


func _apply_full(ev: Dictionary) -> void:
	_clear_replicated()
	GameManager.set_seed_loadout(ev.get("loadout", []))
	GameManager.apply_remote_sun(int(ev.get("sun", 0)))
	GameManager.apply_remote_house_health(int(ev.get("house", GameManager.max_house_health)))
	GameManager.apply_remote_progress(int(ev.get("killed", 0)), int(ev.get("total", 0)))
	for row in ev.get("plants", []):
		_apply_plant_row(row)
	for row in ev.get("enemies", []):
		_apply_enemy_row(row)
	for row in ev.get("gems", []):
		_apply_gem_row(row)
	GameManager.setup_left = int(ev.get("setup", 0))
	# State last: it closes the briefing and shows the result panel only after
	# the world it describes exists.
	GameManager.apply_remote_round_state(str(ev.get("state", "wave")))


func _clear_replicated() -> void:
	for enemy in _enemies.values():
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	for gem in _gems.values():
		if is_instance_valid(gem):
			gem.queue_free()
	_gems.clear()
	if placement != null:
		placement.clear_replicated_plants()


func _apply_plant_row(row: Array) -> void:
	if row.size() < 10 or placement == null:
		return
	var coord := Vector2i(int(row[1]), int(row[2]))
	placement.spawn_plant(str(row[0]), coord, Vector3(float(row[7]), float(row[8]), float(row[9])), float(row[3]), int(row[4]))
	var plant = placement.plant_at(coord)
	if plant is PlantBase:
		(plant as PlantBase).set_remote()
		(plant as PlantBase).apply_remote_health(int(row[5]), int(row[6]))


func _apply_plant_add(ev: Dictionary) -> void:
	if placement == null:
		return
	var coord := Vector2i(int(ev.get("x", 0)), int(ev.get("z", 0)))
	if placement.plant_at(coord) != null:
		return
	var plant = placement.spawn_plant(
		str(ev.get("type", "")), coord,
		Vector3(float(ev.get("px", 0)), float(ev.get("py", 0)), float(ev.get("pz", 0))),
		float(ev.get("rot", 0.0)), int(ev.get("owner", 0)))
	if plant is PlantBase:
		(plant as PlantBase).set_remote()
		(plant as PlantBase).apply_remote_health(int(ev.get("hp", 1)), int(ev.get("max", 1)))


func _apply_plant_hp(ev: Dictionary) -> void:
	if placement == null:
		return
	var plant = placement.plant_at(Vector2i(int(ev.get("x", 0)), int(ev.get("z", 0))))
	if plant is PlantBase:
		(plant as PlantBase).apply_remote_health(int(ev.get("hp", 1)), int(ev.get("max", 1)))


func _apply_plant_gone(ev: Dictionary) -> void:
	if placement == null:
		return
	var plant = placement.plant_at(Vector2i(int(ev.get("x", 0)), int(ev.get("z", 0))))
	if plant != null and plant.has_method("die"):
		plant.die()


func _apply_enemy_row(row: Array) -> void:
	if row.size() < 8:
		return
	_apply_enemy_add({
		"id": row[0], "type": row[1], "x": row[2], "y": row[3], "z": row[4],
		"yaw": row[5], "hp": row[6], "max": row[7],
	})


func _apply_enemy_add(ev: Dictionary) -> void:
	if enemies_container == null:
		return
	var id := int(ev.get("id", 0))
	if id == 0 or _enemies.has(id):
		return
	var scene: PackedScene = BalanceDB.unit_scene(str(ev.get("type", "")))
	if scene == null:
		return
	var enemy := scene.instantiate() as HungryGhost
	if enemy == null:
		return
	enemy.is_remote = true
	# position before add_child: the container has no transform, so this is the
	# world position, and _ready() then starts the interpolation at the right spot.
	enemy.position = Vector3(float(ev.get("x", 0)), float(ev.get("y", 0)), float(ev.get("z", 0)))
	enemy.rotation.y = float(ev.get("yaw", 0))
	enemies_container.add_child(enemy)
	enemy.set_meta("net_id", id)
	_enemies[id] = enemy
	enemy.apply_snapshot(
		float(ev.get("x", 0)), float(ev.get("y", 0)), float(ev.get("z", 0)),
		float(ev.get("yaw", 0)), int(ev.get("hp", 1)), 1, int(ev.get("max", 1)))


func _apply_enemy_gone(ev: Dictionary) -> void:
	var id := int(ev.get("id", 0))
	var enemy = _enemies.get(id)
	_enemies.erase(id)
	if enemy != null and is_instance_valid(enemy):
		enemy.remote_die()


func _apply_gem_row(row: Array) -> void:
	if row.size() < 5:
		return
	_apply_gem_add({"id": row[0], "x": row[1], "y": row[2], "z": row[3], "v": row[4]})


func _apply_gem_add(ev: Dictionary) -> void:
	var id := int(ev.get("id", 0))
	if id == 0 or _gems.has(id):
		return
	var gem := GEM_SCENE.instantiate() as RiceGem
	if gem == null:
		return
	var pos := Vector3(float(ev.get("x", 0)), float(ev.get("y", 0)), float(ev.get("z", 0)))
	var parent_node: Node = plants_container if plants_container != null else self
	parent_node.add_child(gem)
	gem.net_id = id
	gem.place_remote(pos, int(ev.get("v", 50)))
	_gems[id] = gem


func _apply_gem_gone(ev: Dictionary) -> void:
	var id := int(ev.get("id", 0))
	var gem = _gems.get(id)
	_gems.erase(id)
	if gem != null and is_instance_valid(gem):
		gem.remote_collect()


func _apply_shot(ev: Dictionary) -> void:
	var scene: PackedScene = BalanceDB.projectile_scene(str(ev.get("proj", "")))
	if scene == null:
		return
	var proj := scene.instantiate() as Projectile
	if proj == null:
		return
	proj.is_remote = true
	var parent_node: Node = plants_container if plants_container != null else self
	if ev.get("lob", false):
		parent_node.add_child(proj)
		var lob := proj as LobbedProjectile
		if lob != null:
			lob.launch(
				Vector3(float(ev.get("x", 0)), float(ev.get("y", 0)), float(ev.get("z", 0))),
				null,
				Vector3(float(ev.get("tx", 0)), float(ev.get("ty", 0)), float(ev.get("tz", 0))))
	else:
		proj.direction = Vector3(float(ev.get("dx", 0)), float(ev.get("dy", 0)), float(ev.get("dz", 1)))
		parent_node.add_child(proj)
		proj.global_position = Vector3(float(ev.get("x", 0)), float(ev.get("y", 0)), float(ev.get("z", 0)))
	Audio.play(Audio.LOTUS_SHOOT)


func _on_snapshot(snap: Dictionary) -> void:
	if Net == null or not Net.is_guest():
		return
	for row in snap.get("rows", []):
		if not (row is Array) or row.size() < 8:
			continue
		var enemy = _enemies.get(int(row[0]))
		if enemy != null and is_instance_valid(enemy):
			enemy.apply_snapshot(
				float(row[1]), float(row[2]), float(row[3]), float(row[4]),
				int(row[5]), int(row[6]), int(row[7]))


# ========================================================
# PLACEMENT PREVIEW (both directions)
# ========================================================

## This device's ghost changed: tell the other device. Host -> guest is an event,
## guest -> host a command; both are reliable and fire only on a change.
func _on_local_preview(plant_type: String, grid_coord: Vector2i, rot_step: int, valid: bool, player_id: int) -> void:
	if Net == null or player_id != GameManager.local_player_id():
		return
	var msg := {"t": "preview", "plant": plant_type, "x": grid_coord.x, "z": grid_coord.y, "r": rot_step, "ok": valid}
	if Net.is_host():
		if Net.guest_connected():
			Net.send_event(msg)
	else:
		Net.send_command(msg)


## The partner's ghost, drawn by PlacementManager. Visual only, so the host checks
## no more than that the seed is in the shared loadout.
func _apply_partner_preview(msg: Dictionary, player_id: int) -> void:
	if placement == null:
		return
	var plant_type := str(msg.get("plant", ""))
	if not plant_type.is_empty() and not GameManager.seed_loadout.has(plant_type):
		plant_type = ""
	placement.show_partner_preview(plant_type, Vector2i(int(msg.get("x", 0)), int(msg.get("z", 0))),
		int(msg.get("r", 0)), bool(msg.get("ok", false)), player_id)


func _alloc_id(node: Node) -> int:
	_next_id += 1
	node.set_meta("net_id", _next_id)
	return _next_id
