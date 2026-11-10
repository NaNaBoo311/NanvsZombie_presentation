class_name HungryGhost
extends CharacterBody3D

# Hungry Ghost (Basic Enemy) - marches toward the Sacred Dragon Pearl with a
# two-stage appetite: NOTICE nearby plants in a wide cone, SEEK (sidestep
# toward) them, and EAT only what ends up in the narrow frontal cone.
# Plays 'walk' while moving, 'attack' while chomping, one-shot 'die' on defeat.
# Clip names are the unit's declared "clips" in its data/units JSON
# (CONTRACT(clip-names)): a rename must land there, in the generator, the .glb,
# every _play_clip caller, the viewer maps and the spider-test assertion together.
# Emits through EventBus (no direct node references).
#
# Nav routes: a ghost handed a route (NavGrid, via EnemySpawner) walks that A* path in
# from its spawn region, KINEMATICALLY - position and yaw are set directly, never
# move_and_slide, because the bridges carry no collision and physics would drop it in
# the water. Plants stay targetable (collision layer 4 is on) but it does not seek them
# while on a route, so it cannot walk off a bridge deck; at the route end (the lawn's
# edge) the route clears and the normal march /
# seek / eat state machine resumes untouched. Every enemy type inherits this and uses
# its own speed, so a cat covers a route twice as fast as a pot ghost.

@export var speed: float = 1.2
@export var target_position: Vector3 = Vector3(0, 0, -8.5)
@export var max_health: int = 60
## BalanceDB id matching data/units/enemies/<id>.json (CONTRACT(add-enemy)).
## Subclasses set this BEFORE super._ready(); all tunables below are then
## pulled from the DB with these @exports as fallback.
@export var unit_id: String = "hungry_ghost"
## House siege: attack reach from the wall, and a slower beat than plant chomps
## (the house cannot fight back). Arrival is measured from exterior wall perimeter.
## MUST clear the attack-clip lunge: measured peak forward extent is 1.06m at 1.5x scale
## (base pose is only 0.60m = capsule radius, zero margin), so 1.3 keeps ~0.24m of
## visual clearance mid-chomp.
@export var house_reach: float = 1.3
@export var house_damage: int = 7
@export var house_interval: float = 1.0
## Visual playback speed of the 'attack' clip (1.0 = authored loop, same
## as the model viewer default). Bite timers are synced to the native beat
## (1 plant bite / 0.5s, 1 house hit / 1.0s = 1 hit per attack loop).
@export var eat_anim_speed: float = 1.0

## Fallback pearl dais footprint bounds on local XZ plane (mirrors CentralHouse.gd)
const HOUSE_BOUNDS_MIN = Vector2(-3.5, -3.5)
const HOUSE_BOUNDS_MAX = Vector2(3.5, 3.5)
## Noticing: wide cone that spots nearby food worth sidestepping toward.
@export var detect_half_angle_deg: float = 65.0
@export var detect_range: float = 2.8
## Chomping: narrow frontal cone that gates actual bites (1 bite / 0.5s, synced
## to the native 1.0x 'attack' playback so damage lands on the jaw snap).
@export var eat_half_angle_deg: float = 30.0
@export var eat_range: float = 1.8
@export var bite_damage: int = 12
@export var bite_interval: float = 0.5
@export var scan_interval: float = 0.15

var _house: Node3D = null
var _arrived: bool = false
var _anim_player: AnimationPlayer = null
var _health: int = 60
var _dead: bool = false
var _target_plant: Node3D = null
var _bite_timer: float = 0.0
var _scan_cooldown: float = 0.0
var _fill_style: StyleBoxFlat = null
## Countdown until the damage health bar auto-hides (0 = hidden).
var _bar_hide_timer: float = 0.0
## Burrow-rise spawn state (CONTRACT(add-wave)): true from instantiate (set BEFORE
## add_child) until the rise tween lands. While rising the ghost is invulnerable,
## untargetable, collision-free and runs no AI — plants skip it, bites can't hit it.
## Airborne gliders use is_airborne the same way (plants skip both flags).
var is_rising: bool = false
## True while gliding on an airborne route segment (SpawnGates airborne flag).
## Movement is unchanged (routes are kinematic); the walk clip plays at 1.0 and
## plants ignore the ghost until touchdown, exactly like is_rising.
var is_airborne: bool = false
## LAN guest copy (CONTRACT(lan-coop)): no AI, no bites, no local damage. The
## host's snapshots set position/yaw/clip/HP and its enemy_gone event ends it.
var is_remote: bool = false
var _remote_target: Vector3 = Vector3.ZERO
var _remote_yaw: float = 0.0
## How deep below the surface the ghost starts (tween distance, never a clip).
const BURY_DEPTH: float = 2.5
## Rise duration in seconds (telegraph mound shows ~1.0s before this starts).
const RISE_DURATION: float = 0.8

## Zero-allocation precomputed math constants for high-performance physics ticks
var _detect_cone_cos: float = 0.422618
var _eat_cone_cos: float = 0.866025
var _eat_range_sq: float = 3.24
const TURN_SPEED_RAD: float = TAU

## Precomputed step cycle lookup table for step-synchronized locomotion (Invariant 7: no per-frame trig)
const WALK_SPEED_PROFILE := [
	0.427, 0.488, 0.635, 0.696, 0.867, 1.098, 1.318, 1.635, 1.635, 1.013,
	1.928, 2.050, 2.160, 2.099, 2.172, 2.185, 2.441, 2.136, 1.818, 1.794,
	1.721, 1.635, 1.526, 1.416, 1.269, 1.050, 0.818, 0.659, 0.744, 0.976,
	0.732, 0.574, 0.439, 0.488, 0.391, 0.281, 0.207, 0.159, 0.098, 0.073,
	0.073, 0.061, 0.073, 0.061, 0.195, 0.293, 0.391,
]
const STEP_TABLE_SIZE: int = 47
## Average world speed of the walk clip at 1.0x playback:
## 0.385 (model units per cycle) * 2.4 (model scale in HungryGhost.tscn) / 1.9583 s.
## Recompute it if the model scale changes.
const WALK_BASE_SPEED: float = 0.472
var _walk_step_multipliers := PackedFloat32Array()
var _walk_inv_duration: float = 1.0 / 1.9583

func _walk_anim_scale() -> float:
	if unit_id != "hungry_ghost" and unit_id != "hungry_ghost_v2":
		return 1.0
	return speed / WALK_BASE_SPEED

## Nav approach route (NavGrid.find_route), or {} when there is none. The
## arrays are the route's precomputed ones, so _walk_route is a multiply-add per
## tick: no sqrt, no division, no trig.
var _route: Dictionary = {}
var _route_seg: int = 0
var _route_travelled: float = 0.0
var _route_scale: float = 1.0

## How long the health bar stays visible after taking damage.
@export var bar_visible_time: float = 3.0
@export var marker_radius: float = 1.1
var _faction_marker: MeshInstance3D

@onready var visuals: Node3D = $Visuals
@onready var health_sprite: Sprite3D = $HealthBarSprite
@onready var health_viewport: SubViewport = $HealthBarViewport
@onready var health_bar: ProgressBar = $HealthBarViewport/HealthBar

func _ready() -> void:
	add_to_group("Enemies")
	_apply_balance()
	_faction_marker = FactionMarker.attach(self, FactionMarker.Faction.ENEMY, marker_radius)
	_health = max_health
	_update_cached_math()
	_setup_materials(self)
	_house = get_tree().get_first_node_in_group("CentralHouse") as Node3D
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player:
		for clip in ["walk", "attack"]:
			if _anim_player.has_animation(clip):
				_anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_init_step_table()
	_play_clip("walk", _walk_anim_scale())
	_init_health_bar()
	_optimize_shadows(self)
	if is_remote:
		_remote_target = global_position
		_remote_yaw = rotation.y
		set_physics_process(false)
		set_collision_layer_value(4, false)
		set_collision_mask_value(1, false)
		set_process(true)
	else:
		set_process(false) # no _process work offline / on the host

func _optimize_shadows(node: Node) -> void:
	var mesh_count: int = 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var cur = stack.pop_back()
		if cur is MeshInstance3D:
			mesh_count += 1
			if mesh_count > 4:
				cur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for child in cur.get_children():
			stack.append(child)
	if is_remote:
		return # no pop-in and no enemy_spawned: the host announces the spawn
	if is_rising:
		# Buried path (EnemySpawner): no pop-in, no enemy_spawned yet — both
		# happen in _finish_surface(). Marker stays hidden until surfaced.
		if is_instance_valid(_faction_marker):
			_faction_marker.visible = false
		return
	# Spawn pop-in (mirrors PlantBase feel at enemy scale)
	if is_instance_valid(visuals):
		visuals.scale = Vector3.ONE * 0.01
		var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(visuals, "scale", Vector3.ONE, 0.35)
	EventBus.enemy_spawned.emit(self)

## Burrow-rise entry (EnemySpawner only): drop the ghost below `surface_pos` and
## tween it up. Collision off, AI off, invulnerable until _finish_surface().
## Call AFTER add_child (so _ready has run and seen is_rising=true).
func spawn_buried(surface_pos: Vector3, bury_depth: float = BURY_DEPTH) -> void:
	is_rising = true
	set_physics_process(false)
	set_collision_layer_value(4, false) # untouchable while underground (Layer 4)
	set_collision_mask_value(1, false)
	_target_plant = null
	_bite_timer = 0.0
	_scan_cooldown = scan_interval
	if is_instance_valid(_faction_marker):
		_faction_marker.visible = false
	_hide_health_bar()
	global_position = Vector3(surface_pos.x, surface_pos.y - bury_depth, surface_pos.z)
	_play_clip("walk", _walk_anim_scale())
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", surface_pos, RISE_DURATION)
	tween.tween_callback(_finish_surface)

## Rise landing: restore collision/AI, reveal marker, join the live-enemy count.
## Plants were skipping this ghost while is_rising, so the first scan after this
## picks it up with no stale-target edge cases.
func _finish_surface() -> void:
	if _dead or not is_instance_valid(self):
		return
	is_rising = false
	set_collision_layer_value(4, true)
	set_collision_mask_value(1, true)
	set_physics_process(true)
	if is_instance_valid(_faction_marker):
		_faction_marker.visible = true
	_play_clip("walk", _walk_anim_scale())
	EventBus.enemy_spawned.emit(self)


## Walk a nav route (NavGrid.find_route:
## {points, dirs, lengths, yaws, scale}). Call AFTER add_child and BEFORE
## spawn_buried, so the very first physics tick after the rise is already on the
## route. An empty or malformed route is ignored and the ghost marches as usual.
## CONTRACT(add-wave): the route comes from the queue entry, so it must be handed
## over before the mound telegraph starts or the ghost would step off the spawn spot.
func follow_route(route: Dictionary) -> void:
	if route.is_empty() or not (route.get("points", PackedVector3Array()) as PackedVector3Array).size() >= 2:
		return
	_route = route
	_route_seg = 0
	_route_travelled = 0.0
	_route_scale = float(route.get("scale", 1.0))
	_target_plant = null
	_bite_timer = 0.0
	velocity = Vector3.ZERO # the route sets position directly; no stale push


## True while the ghost is still walking a nav route.
func is_on_route() -> bool:
	return not _route.is_empty()


## Kinematic step along the route. The ghost's own speed scales the route's
## multiplier, so each enemy type keeps its own pace over the same path; the walk
## clip plays at the same rate, so the feet keep up. No move_and_slide: nothing on
## a bridge deck or a stair tread has collision. Airborne segments (both ends
## airborne) play walk at 1.0 — no feet on the ground to slide — and set is_airborne
## so plants skip the glider until touchdown.
func _walk_route(delta: float) -> void:
	var points: PackedVector3Array = _route["points"]
	var dirs: PackedVector3Array = _route["dirs"]
	var lengths: PackedFloat32Array = _route["lengths"]
	var yaws: PackedFloat32Array = _route["yaws"]
	var air: PackedByteArray = _route.get("airborne", PackedByteArray())
	var seg_air := air.size() > _route_seg + 1 and air[_route_seg] == 1 and air[_route_seg + 1] == 1
	is_airborne = seg_air
	var step_mult: float = 1.0 if seg_air else _get_walk_speed_multiplier()
	_route_travelled += speed * _route_scale * step_mult * delta
	# Long ticks (a stall, a debug pause) can cross several segments at once.
	while _route_seg < lengths.size() and _route_travelled > lengths[_route_seg]:
		_route_travelled -= lengths[_route_seg]
		_route_seg += 1
	if _route_seg >= lengths.size():
		_clear_route()
		return
	global_position = points[_route_seg] + dirs[_route_seg] * _route_travelled
	rotation.y = yaws[_route_seg]
	_play_clip("walk", 1.0 if seg_air else _route_scale * _walk_anim_scale())


## Lane end reached: hand the ghost back to the normal march / seek / eat logic.
func _clear_route() -> void:
	_route = {}
	_route_seg = 0
	_route_travelled = 0.0
	_route_scale = 1.0
	is_airborne = false
	_scan_cooldown = scan_interval
	velocity = Vector3.ZERO
	_play_clip("walk", _walk_anim_scale())

## Guest: interpolate toward the host's latest snapshot. Only remote copies run
## this callback (set_process(false) everywhere else), so solo and host pay nothing.
func _process(delta: float) -> void:
	if not is_remote:
		return
	var w: float = minf(1.0, 18.0 * delta)
	if global_position.distance_squared_to(_remote_target) > 0.0001:
		global_position = global_position.lerp(_remote_target, w)
	if absf(angle_difference(rotation.y, _remote_yaw)) > 0.001:
		rotation.y = lerp_angle(rotation.y, _remote_yaw, w)
	if _bar_hide_timer > 0.0:
		_bar_hide_timer -= delta
		if _bar_hide_timer <= 0.0:
			_hide_health_bar()

## Guest: one host snapshot row [id, x, y, z, yaw, hp, clip] (CONTRACT(lan-coop)).
func apply_snapshot(x: float, y: float, z: float, yaw: float, hp: int, clip: int, max_hp: int = -1) -> void:
	_remote_target = Vector3(x, y, z)
	_remote_yaw = yaw
	if max_hp > 0:
		max_health = max_hp
	if hp != _health:
		_health = clampi(hp, 0, max_health)
		_update_health_bar()
		_show_health_bar()
	match clip:
		1:
			_play_clip("walk", _walk_anim_scale())
		2:
			_play_clip("attack", eat_anim_speed)

## Guest: the host's death event. Plays the same clip without `enemy_defeated`
## (the guest keeps no authority over waves or progress).
func remote_die() -> void:
	if _dead:
		return
	_dead = true
	set_process(false)
	set_physics_process(false)
	if is_instance_valid(_faction_marker):
		_faction_marker.visible = false
	velocity = Vector3.ZERO
	set_collision_layer_value(4, false)
	set_collision_mask_value(1, false)
	_hide_health_bar()
	_play_clip("die")
	if _anim_player and _anim_player.has_animation("die"):
		await _anim_player.animation_finished
	else:
		await get_tree().create_timer(0.5).timeout
	if is_instance_valid(self):
		queue_free()

## The host snapshot's clip index.
func remote_clip() -> int:
	if _anim_player == null:
		return 0
	match _anim_player.current_animation:
		"walk":
			return 1
		"attack":
			return 2
		"die":
			return 3
	return 0

func remote_health() -> int:
	return _health

func is_dead() -> bool:
	return _dead

func _physics_process(delta: float) -> void:
	if _dead or is_rising:
		return
	# Auto-hide the damage health bar (plain float countdown: no nodes, no allocs).
	if _bar_hide_timer > 0.0:
		_bar_hide_timer -= delta
		if _bar_hide_timer <= 0.0:
			_hide_health_bar()

	# On a nav route the ghost is kinematic and ignores the state machine below:
	# no plant seeking (leaving a bridge deck for one would drop it in the water)
	# and no house check (it is still 20 m from the dais).
	if not _route.is_empty():
		_walk_route(delta)
		return

	# Throttled plant scan; per-tick validity is cheap.
	_scan_cooldown -= delta
	if _scan_cooldown <= 0.0:
		_scan_cooldown = scan_interval
		_target_plant = _find_plant_in_range()
	elif not is_instance_valid(_target_plant):
		_target_plant = null
	if not is_instance_valid(_target_plant):
		_target_plant = null

	if is_instance_valid(_target_plant):
		if _is_bitable(_target_plant):
			_eat_plant(_target_plant, delta)
			return
		_seek_plant(_target_plant, delta)
		return

	var house_pos: Vector3 = _house.global_position if is_instance_valid(_house) else target_position
	if _gap_to_house(house_pos) <= house_reach:
		_attack_house(house_pos, delta)
		return

	_arrived = false # marching (or seeking) clears arrival; attack re-arms its timer on return
	var march_dir: Vector3 = _get_march_direction(house_pos)
	if march_dir.length_squared() < 0.0001:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	_walk_toward(march_dir.normalized(), delta)
	_play_clip("walk", _walk_anim_scale())

## Flat distance from ghost center to the nearest exterior wall of the house (0 = touching wall).
func _gap_to_house(house_pos: Vector3) -> float:
	if is_instance_valid(_house) and _house.has_method("get_distance_to_wall"):
		return _house.get_distance_to_wall(global_position)
	var local_x: float = global_position.x - house_pos.x
	var local_z: float = global_position.z - house_pos.z
	var p2: Vector2 = Vector2(local_x, local_z)
	return _dist_to_box_2d(p2, HOUSE_BOUNDS_MIN, HOUSE_BOUNDS_MAX)

## Computes travel direction toward the pearl. Marches directly toward
## the closest point on the dais perimeter from any spawn direction (omnidirectional
## diorama). When aligned with a dais face, this naturally produces straight lane marching.
func _get_march_direction(house_pos: Vector3) -> Vector3:
	var closest: Vector3 = _get_closest_wall_point(house_pos)
	var to_closest: Vector3 = closest - global_position
	to_closest.y = 0.0
	if to_closest.length_squared() > 0.0001:
		return to_closest.normalized()
	return Vector3(0.0, 0.0, -1.0)

## Finds the closest point on the exterior house perimeter in world coordinates.
func _get_closest_wall_point(house_pos: Vector3) -> Vector3:
	if is_instance_valid(_house) and _house.has_method("get_closest_wall_point"):
		return _house.get_closest_wall_point(global_position)
	var local_x: float = global_position.x - house_pos.x
	var local_z: float = global_position.z - house_pos.z
	var p2: Vector2 = Vector2(local_x, local_z)
	var chosen: Vector2 = _closest_point_on_box_2d(p2, HOUSE_BOUNDS_MIN, HOUSE_BOUNDS_MAX)
	return house_pos + Vector3(chosen.x, 0.0, chosen.y)

func _dist_to_box_2d(p: Vector2, b_min: Vector2, b_max: Vector2) -> float:
	var dx: float = maxf(0.0, maxf(b_min.x - p.x, p.x - b_max.x))
	var dz: float = maxf(0.0, maxf(b_min.y - p.y, p.y - b_max.y))
	return Vector2(dx, dz).length()

func _closest_point_on_box_2d(p: Vector2, b_min: Vector2, b_max: Vector2) -> Vector2:
	return Vector2(clampf(p.x, b_min.x, b_max.x), clampf(p.y, b_min.y, b_max.y))

## Siege the house: hold position outside the wall, face it, chomp on a slow beat.
func _attack_house(house_pos: Vector3, delta: float) -> void:
	if not _arrived:
		_arrived = true
		_bite_timer = 0.0
	velocity = Vector3.ZERO
	move_and_slide()
	var wall_pt: Vector3 = _get_closest_wall_point(house_pos)
	var to_wall: Vector3 = wall_pt - global_position
	to_wall.y = 0.0
	if to_wall.length_squared() > 0.0001:
		rotation.y = rotate_toward(rotation.y, atan2(to_wall.x, to_wall.z), TURN_SPEED_RAD * delta)
	_play_clip("attack", eat_anim_speed)
	_bite_timer += delta
	if _bite_timer >= house_interval:
		_bite_timer = 0.0
		if is_instance_valid(_house) and _house.has_method("take_damage"):
			_house.take_damage(house_damage)

## Pulls tuning from BalanceDB (data/units/enemies/<unit_id>.json); every key falls
## back to the @export default so a missing entry changes nothing. Runs
## before health init and math caching so subclasses only set unit_id.
func _apply_balance() -> void:
	if unit_id.is_empty():
		return
	max_health = int(BalanceDB.num(unit_id, "max_health", max_health))
	speed = float(BalanceDB.num(unit_id, "speed", speed))
	house_reach = float(BalanceDB.num(unit_id, "house_reach", house_reach))
	house_damage = int(BalanceDB.num(unit_id, "house_damage", house_damage))
	house_interval = float(BalanceDB.num(unit_id, "house_interval", house_interval))
	eat_anim_speed = float(BalanceDB.num(unit_id, "eat_anim_speed", eat_anim_speed))
	detect_half_angle_deg = float(BalanceDB.num(unit_id, "detect_half_angle_deg", detect_half_angle_deg))
	detect_range = float(BalanceDB.num(unit_id, "detect_range", detect_range))
	eat_half_angle_deg = float(BalanceDB.num(unit_id, "eat_half_angle_deg", eat_half_angle_deg))
	eat_range = float(BalanceDB.num(unit_id, "eat_range", eat_range))
	bite_damage = int(BalanceDB.num(unit_id, "bite_damage", bite_damage))
	bite_interval = float(BalanceDB.num(unit_id, "bite_interval", bite_interval))
	scan_interval = float(BalanceDB.num(unit_id, "scan_interval", scan_interval))
	bar_visible_time = float(BalanceDB.num(unit_id, "bar_visible_time", bar_visible_time))
	marker_radius = float(BalanceDB.num(unit_id, "marker_radius", marker_radius))

## Pre-computes trigonometry and squared ranges once so physics frames execute without runtime math overhead.
func _update_cached_math() -> void:
	_detect_cone_cos = cos(deg_to_rad(detect_half_angle_deg))
	_eat_cone_cos = cos(deg_to_rad(eat_half_angle_deg))
	_eat_range_sq = eat_range * eat_range

## Nearest plant inside the wide notice cone (reuses PlantBase cone query with cached cosine).
func _find_plant_in_range() -> Node3D:
	return PlantBase.find_nearest_in_cone(global_position, global_transform.basis.z, get_tree().get_nodes_in_group("Plants"), detect_range, _detect_cone_cos)

## Cheap per-tick gate (no group scan): is the already-noticed plant
## close and frontal enough to actually bite? Squared-dot test, no sqrt/div.
func _is_bitable(plant: Node3D) -> bool:
	var to_plant: Vector3 = plant.global_position - global_position
	to_plant.y = 0.0
	var dist_sq: float = to_plant.length_squared()
	if dist_sq < 0.0001 or dist_sq > _eat_range_sq:
		return false
	var d := to_plant.dot(global_transform.basis.z)
	if d < 0.0:
		return false
	return d * d >= dist_sq * _eat_cone_cos * _eat_cone_cos

## Sidestep toward noticed food (same locomotion as the house march).
func _seek_plant(plant: Node3D, delta: float) -> void:
	_arrived = false
	var to_plant: Vector3 = plant.global_position - global_position
	to_plant.y = 0.0
	if to_plant.length_squared() < 0.0001:
		return
	_walk_toward(to_plant.normalized(), delta)
	_play_clip("walk", _walk_anim_scale())

func _eat_plant(plant: Node3D, delta: float) -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	# Face the meal, then chomp on a fixed beat (1 bite / 0.5s matches the native clip).
	var to_plant: Vector3 = plant.global_position - global_position
	to_plant.y = 0.0
	if to_plant.length_squared() > 0.0001:
		rotation.y = rotate_toward(rotation.y, atan2(to_plant.x, to_plant.z), TURN_SPEED_RAD * delta)
	_play_clip("attack", eat_anim_speed)
	_bite_timer += delta
	if _bite_timer >= bite_interval:
		_bite_timer = 0.0
		if plant.has_method("take_damage"):
			plant.take_damage(bite_damage)
			Audio.play(Audio.ENEMY_EAT)

func _walk_toward(dir: Vector3, _delta: float) -> void:
	# Model faces +Z (matches LotusShooter lane convention); yaw to face travel dir.
	rotation.y = atan2(dir.x, dir.z)
	var step_mult: float = _get_walk_speed_multiplier()
	velocity = dir * (speed * step_mult)
	# Light gravity so the ghost stays grounded on the flat island.
	velocity.y = -2.0
	move_and_slide()

## Applies the frame-accurate speed profile for Hungry Ghost V2 to keep planted feet pinned.
func _init_step_table() -> void:
	if unit_id != "hungry_ghost" and unit_id != "hungry_ghost_v2":
		return
	_walk_step_multipliers = PackedFloat32Array(WALK_SPEED_PROFILE)
	var duration: float = 47.0 / 24.0
	if is_instance_valid(_anim_player) and _anim_player.has_animation("walk"):
		duration = _anim_player.get_animation("walk").length
	_walk_inv_duration = 1.0 / maxf(duration, 0.001)

## Temporary walk-speed buff from a support enemy aura (AerobicsAuntie). Costs one float
## compare per step when never buffed. Re-applying keeps the larger multiplier and the later expiry.
var speed_buff_mult: float = 1.0
var _speed_buff_until_msec: int = 0

func apply_speed_buff(mult: float, duration: float) -> void:
	var now: int = Time.get_ticks_msec()
	if now >= _speed_buff_until_msec:
		speed_buff_mult = mult
	else:
		speed_buff_mult = maxf(speed_buff_mult, mult)
	_speed_buff_until_msec = maxi(_speed_buff_until_msec, now + int(duration * 1000.0))

## Temporary walk-speed slow from a plant (MilkFlower scent, BanyanSnare roots; 0 = rooted).
## Kept apart from the buff so a slow and an aura multiply instead of the larger one
## winning. Re-applying keeps the smaller multiplier and the later expiry.
var slow_mult: float = 1.0
var _slow_until_msec: int = 0

func apply_slow(mult: float, duration: float) -> void:
	if _dead or is_rising:
		return
	var now: int = Time.get_ticks_msec()
	if now >= _slow_until_msec:
		slow_mult = mult
	else:
		slow_mult = minf(slow_mult, mult)
	_slow_until_msec = maxi(_slow_until_msec, now + int(duration * 1000.0))

func _get_walk_speed_multiplier() -> float:
	var buff: float = 1.0
	if speed_buff_mult != 1.0:
		if Time.get_ticks_msec() < _speed_buff_until_msec:
			buff = speed_buff_mult
		else:
			speed_buff_mult = 1.0
	if slow_mult != 1.0:
		if Time.get_ticks_msec() < _slow_until_msec:
			buff *= slow_mult
		else:
			slow_mult = 1.0
	if _walk_step_multipliers.is_empty():
		return buff
	if not is_instance_valid(_anim_player) or not _anim_player.is_playing() or _anim_player.current_animation != "walk":
		return buff
	var idx: int = int(_anim_player.current_animation_position * _walk_inv_duration * STEP_TABLE_SIZE)
	idx = clampi(idx, 0, STEP_TABLE_SIZE - 1)
	return _walk_step_multipliers[idx] * buff

func take_damage(amount: int) -> void:
	if _dead or is_rising or is_airborne or is_remote:
		return
	_health -= amount
	_update_health_bar()
	_show_health_bar()
	# Hit flash / flinch (visuals snap back via tween, no state change).
	if is_instance_valid(visuals):
		var tween = create_tween()
		tween.tween_property(visuals, "scale", Vector3(1.12, 0.88, 1.12), 0.07)
		tween.tween_property(visuals, "scale", Vector3.ONE, 0.1)
	# Health bar punch bounce
	if is_instance_valid(health_sprite):
		var bar_tween = create_tween()
		bar_tween.tween_property(health_sprite, "scale", Vector3(1.22, 1.22, 1.22), 0.08)
		bar_tween.tween_property(health_sprite, "scale", Vector3.ONE, 0.14)
	if _health <= 0:
		_die()

## Heal block (HoiAnChili burn): heal() does nothing until it expires. Re-applying keeps
## the later expiry.
var _heal_blocked_until_msec: int = 0

func block_heal(duration: float) -> void:
	_heal_blocked_until_msec = maxi(_heal_blocked_until_msec, Time.get_ticks_msec() + int(duration * 1000.0))

func is_heal_blocked() -> bool:
	return _heal_blocked_until_msec != 0 and Time.get_ticks_msec() < _heal_blocked_until_msec

## Restore body HP (clamped to max_health); no-op when dead, still rising or heal-blocked.
## Extra pools (e.g. StreetVendorZombie's shield) are not touched.
func heal(amount: int) -> void:
	if _dead or is_rising or amount <= 0 or _health >= max_health or is_heal_blocked():
		return
	_health = mini(_health + amount, max_health)
	_update_health_bar()
	_show_health_bar()

func _init_health_bar() -> void:
	if health_bar:
		var orig = health_bar.get_theme_stylebox("fill")
		if orig is StyleBoxFlat:
			_fill_style = orig.duplicate() as StyleBoxFlat
			health_bar.add_theme_stylebox_override("fill", _fill_style)
		health_bar.max_value = max_health
		health_bar.value = _health
	_update_health_bar(false)
	# Hidden until first damage: zero draw cost while undamaged (see _show_health_bar).
	_hide_health_bar()

func _update_health_bar(animate: bool = true) -> void:
	if not health_bar:
		return
	if animate:
		if is_instance_valid(health_viewport):
			health_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var tween = create_tween()
		tween.tween_property(health_bar, "value", float(maxi(_health, 0)), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.finished.connect(func():
			if is_instance_valid(health_viewport):
				health_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		)
	else:
		health_bar.value = maxi(_health, 0)
		if is_instance_valid(health_viewport):
			health_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _fill_style:
		_fill_style.bg_color = Color(0.92, 0.28, 0.24, 1.0)

## Reveal the bar and refresh its auto-hide timer (each hit extends visibility).
func _show_health_bar() -> void:
	_bar_hide_timer = bar_visible_time
	if is_instance_valid(health_sprite):
		health_sprite.visible = true

## Hide the bar AND pause its viewport: hiding the Sprite3D alone still leaves
## the SubViewport redrawing every frame (UPDATE_ALWAYS), so pausing updates is
## what actually drops the idle cost to zero.
func _hide_health_bar() -> void:
	_bar_hide_timer = 0.0
	if is_instance_valid(health_sprite):
		health_sprite.visible = false
	if is_instance_valid(health_viewport):
		health_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _die() -> void:
	if _dead:
		return
	_dead = true
	if is_instance_valid(_faction_marker):
		_faction_marker.visible = false
	velocity = Vector3.ZERO
	set_physics_process(false)
	set_collision_layer_value(4, false) # stop eating/blocking while dying (Layer 4)
	set_collision_mask_value(1, false)
	_hide_health_bar()
	EventBus.enemy_defeated.emit(self)
	_play_clip("die")
	if _anim_player:
		await _anim_player.animation_finished
	# Fallback: if the clip is missing/looping, never linger.
	if is_instance_valid(self):
		queue_free()

## PvZ shovel removal: instant kill playing the standard death path
## (marker hidden, collision off, `enemy_defeated`, death clip). Shared by
## all subclasses (Pot Ghost, Mask Spider) with no overrides.
func remove_by_shovel() -> void:
	if _dead or is_rising:
		return
	_die()

func _play_clip(clip_name: String, speed_scale: float = 1.0) -> void:
	if _anim_player and _anim_player.has_animation(clip_name):
		if _anim_player.current_animation != clip_name or not _anim_player.is_playing():
			_anim_player.play(clip_name, -1, speed_scale)
		elif not is_equal_approx(_anim_player.speed_scale, speed_scale):
			_anim_player.speed_scale = speed_scale
	elif _anim_player:
		BalanceDB.report_missing_clip(unit_id, clip_name) # logs once (CONTRACT(clip-names))

func _setup_materials(node: Node) -> void:
	# Godot glTF import leaves vertex_color_use_as_albedo=false: re-enable
	# so baked procedural vertex colors are not silently ignored.
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			var mat = node.get_active_material(i)
			if not mat:
				mat = node.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var arrays = node.mesh.surface_get_arrays(i)
				if arrays.size() > Mesh.ARRAY_COLOR and arrays[Mesh.ARRAY_COLOR] != null:
					mat.vertex_color_use_as_albedo = true
	for child in node.get_children():
		_setup_materials(child)
