class_name KapokCatapult
extends PlantBase

# Kapok Catapult (Cây Gòn Catapult) - Vietnamese Cultural Artillery Plant
# Lobs heavy fluffy cotton bolls in high parabolic arcs over obstacles to strike backline enemies.
# Features juicy procedural wind-up tension and snap recoil animation.

@export var shoot_interval: float = 2.9
@export var fire_align_deg: float = 8.0
@export var scan_interval: float = 0.1

@onready var shoot_point: Marker3D = $ShootPoint

var shoot_timer: float = 0.0
var _projectile_scene: PackedScene
var _is_attacking: bool = false
var _current_target: Node3D = null
var _scan_cooldown: float = 0.0
var _anim_player: AnimationPlayer = null
var _fire_align_rad: float = 0.139626
var _dead: bool = false
var _attack_gen: int = 0
var _attack_apex: float = 0.55
var _attack_duration: float = 1.0
const DIE_DURATION: float = 0.3

func _init() -> void:
	unit_id = "kapok_catapult"

func _ready() -> void:
	super._ready()
	_projectile_scene = BalanceDB.projectile_scene(str(BalanceDB.get_unit(unit_id).get("projectile", "")))
	shoot_interval = float(BalanceDB.num(unit_id, "shoot_interval", shoot_interval))
	fire_align_deg = float(BalanceDB.num(unit_id, "fire_align_deg", fire_align_deg))
	scan_interval = float(BalanceDB.num(unit_id, "scan_interval", scan_interval))
	_attack_apex = float(BalanceDB.num(unit_id, "attack_apex_sec", _attack_apex))
	_attack_duration = float(BalanceDB.num(unit_id, "attack_duration_sec", _attack_duration))
	_fire_align_rad = deg_to_rad(fire_align_deg)
	shoot_timer = shoot_interval # First shot ready immediately upon target acquisition
	idle_enabled = true

	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player:
		if _anim_player.has_animation("idle"):
			_anim_player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		if _anim_player.has_animation("attack"):
			_anim_player.get_animation("attack").loop_mode = Animation.LOOP_NONE
		if _anim_player.has_animation("die"):
			_anim_player.get_animation("die").loop_mode = Animation.LOOP_NONE
		_play_clip("idle")

func _play_clip(clip_name: String) -> void:
	if _anim_player and _anim_player.has_animation(clip_name):
		_anim_player.play(clip_name)

## is_dead is a method on enemies, so Object.get() would hand back a Callable.
func _is_dead(enemy: Node) -> bool:
	return enemy.has_method("is_dead") and enemy.is_dead()


func acquire_target() -> Node3D:
	# Prioritize the farthest enemy in range within the vision cone
	var enemies := get_tree().get_nodes_in_group("Enemies")
	var best: Node3D = null
	var best_dist_sq: float = -1.0
	var forward := base_forward
	var cos_sq := vision_cone_cos * vision_cone_cos
	var half_angle_cos := vision_cone_cos

	for c in enemies:
		if not is_instance_valid(c) or not (c is Node3D):
			continue
		if c.get("is_rising") == true or c.get("is_airborne") == true or _is_dead(c):
			continue
		var diff: Vector3 = c.global_position - global_position
		diff.y = 0.0
		var dist_sq := diff.length_squared()
		if dist_sq > vision_range_sq or dist_sq < 0.0001:
			continue
		var d := diff.dot(forward)
		if half_angle_cos < 0.0:
			if d < half_angle_cos * sqrt(dist_sq):
				continue
		elif d < 0.0 or d * d < dist_sq * cos_sq:
			continue
		if dist_sq > best_dist_sq:
			best_dist_sq = dist_sq
			best = c
	return best

func _physics_process(delta: float) -> void:
	if is_remote:
		return
	# CONTRACT(plant-stun): stunned turrets freeze in place (no scan, turn or fire).
	if is_stunned():
		return
	# Zero idle cost when no enemies exist
	if GameManager != null and GameManager.alive_enemies == 0:
		_current_target = null
		_scan_cooldown = scan_interval
		shoot_timer = shoot_interval
		rotation.y = rotate_toward(rotation.y, base_rotation_y, turn_speed_rad * delta)
		return

	_scan_cooldown -= delta
	if _scan_cooldown <= 0.0:
		_scan_cooldown = scan_interval
		if is_instance_valid(_current_target):
			var diff: Vector3 = _current_target.global_position - global_position
			diff.y = 0.0
			var dist_sq: float = diff.length_squared()
			if dist_sq > vision_range_sq or _is_dead(_current_target):
				_current_target = acquire_target()
		else:
			_current_target = acquire_target()
	elif not is_instance_valid(_current_target):
		_current_target = null

	if not is_instance_valid(_current_target):
		_current_target = null
		shoot_timer = shoot_interval
		rotation.y = rotate_toward(rotation.y, base_rotation_y, turn_speed_rad * delta)
		return

	if _current_target.get("is_rising") == true or _current_target.get("is_airborne") == true:
		_current_target = null
		shoot_timer = shoot_interval
		rotation.y = rotate_toward(rotation.y, base_rotation_y, turn_speed_rad * delta)
		return

	var remaining: float = face_target(_current_target, delta)
	shoot_timer += delta
	if shoot_timer >= shoot_interval and remaining <= _fire_align_rad:
		_shoot()
		shoot_timer = 0.0

func _shoot() -> void:
	if not _projectile_scene or not shoot_point or _is_attacking:
		return

	_is_attacking = true
	idle_enabled = false
	_attack_gen += 1
	var gen: int = _attack_gen
	_play_clip("attack")

	# Dramatic catapult windup & release tween matching baked clip timings
	var tween = create_tween()
	# Phase 1: Windup (0.0 -> 0.42s) - Lean back and squash gathering tension
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(visuals, "rotation_degrees:x", -22.0, 0.42)
	tween.parallel().tween_property(visuals, "scale", Vector3(1.10, 0.84, 1.10), 0.42)

	# Phase 2: Snap forward (0.42 -> 0.55s) - Violent forward launch to release apex
	tween.chain().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(visuals, "rotation_degrees:x", 18.0, 0.13)
	tween.parallel().tween_property(visuals, "scale", Vector3(0.90, 1.20, 0.90), 0.13)

	# Phase 3: Recoil & Settle (0.55 -> 1.0s) - Elastic decay back to rest
	tween.chain().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(visuals, "rotation_degrees:x", 0.0, 0.45)
	tween.parallel().tween_property(visuals, "scale", Vector3.ONE, 0.45)
	tween.chain().tween_callback(func():
		if gen == _attack_gen and not _dead:
			_is_attacking = false
			idle_enabled = true
			_play_clip("idle")
	)

	_spawn_at_apex(gen)

func _spawn_at_apex(gen: int) -> void:
	await get_tree().create_timer(_attack_apex).timeout
	# A stun landing mid-swing cancels the shot (CONTRACT(plant-stun)).
	if gen != _attack_gen or _dead or is_stunned():
		return
	_spawn_projectile()

func _spawn_projectile() -> void:
	if not _projectile_scene or not shoot_point:
		return

	var facing: Vector3 = global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = Vector3.MODEL_FRONT
	facing = facing.normalized()

	var proj = _projectile_scene.instantiate()
	if not proj:
		return

	if "damage" in proj:
		proj.damage = int(BalanceDB.num(unit_id, "damage", proj.damage))

	var parent_node = get_parent()
	if parent_node:
		parent_node.add_child(proj)
	else:
		get_tree().current_scene.add_child(proj)

	if proj is LobbedProjectile:
		proj.launch(shoot_point.global_position, _current_target)
	else:
		proj.global_position = shoot_point.global_position
		proj.direction = facing

	EventBus.projectile_fired.emit(proj)
	Audio.play(Audio.LOTUS_SHOOT)

func die() -> void:
	if _dead:
		return
	_dead = true
	_attack_gen += 1
	EventBus.plant_died.emit(grid_coord)
	_play_clip("die")

	# Death squash and shrink
	if is_instance_valid(visuals):
		var tween = create_tween().set_parallel(true)
		tween.tween_property(visuals, "scale", Vector3.ZERO, DIE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(visuals, "position:y", -0.4, DIE_DURATION)

	await get_tree().create_timer(DIE_DURATION).timeout
	queue_free()
