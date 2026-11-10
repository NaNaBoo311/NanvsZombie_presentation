class_name LotusShooter
extends PlantBase

# Lotus Shooter (Bát Sen Bắn Hạt) - Original Vietnamese Cultural Defender
# Fires high-velocity golden jade lotus seeds down the lane with bouncy PvZ cartoon recoil.

@export var shoot_interval: float = 1.5
@export var always_shooting: bool = false
## Fire only once aimed within this angle of the target.
@export var fire_align_deg: float = 5.0
## Target re-scan rate (scanning every tick wastes group array allocations).
@export var scan_interval: float = 0.1

@onready var shoot_point: Marker3D = $ShootPoint
@onready var lane_ray: RayCast3D = $LaneRay

var shoot_timer: float = 0.0
## Resolved from the unit JSON "projectile" id (data/projectiles/).
var _projectile_scene: PackedScene
var _is_attacking: bool = false
var _current_target: Node3D = null
var _scan_cooldown: float = 0.0
var _flash_mesh: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _flash_tween: Tween
var _tracking_cone_cos: float = 0.8314696
var _fire_align_rad: float = 0.0872665
var _anim_player: AnimationPlayer = null
## Baked `attack` sync points (CONTRACT(clip-names)): apex spawns the seed,
## duration ends the swing. Read from the DB; generator authors to match.
var _attack_apex: float = 0.24
var _attack_duration: float = 0.5
var _dead: bool = false
var _attack_gen: int = 0
const DIE_DURATION: float = 0.3 # baked `die` is 0.25s; margin, then free

# Registry id (data/units/plants/lotus_shooter.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "lotus_shooter"

func _ready() -> void:
	super._ready()
	_projectile_scene = BalanceDB.projectile_scene(str(BalanceDB.get_unit(unit_id).get("projectile", "")))
	shoot_interval = float(BalanceDB.num(unit_id, "shoot_interval", shoot_interval))
	fire_align_deg = float(BalanceDB.num(unit_id, "fire_align_deg", fire_align_deg))
	scan_interval = float(BalanceDB.num(unit_id, "scan_interval", scan_interval))
	_attack_apex = float(BalanceDB.num(unit_id, "attack_apex_sec", _attack_apex))
	_attack_duration = float(BalanceDB.num(unit_id, "attack_duration_sec", _attack_duration))
	_setup_materials(self)
	_setup_muzzle_flash()
	_tracking_cone_cos = cos(deg_to_rad(vision_half_angle_deg * 1.5))
	_fire_align_rad = deg_to_rad(fire_align_deg)
	# Turret aiming replaced the fixed lane ray; keep the node dormant for future use.
	if lane_ray:
		lane_ray.enabled = false
	shoot_timer = shoot_interval # first shot fires immediately on acquiring a target
	# Baked clips own all motion (idle breathing + attack swing + death shrink);
	# the code keeps only muzzle flash. Loop modes set explicitly so sequencing
	# never depends on importer defaults.
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player:
		if _anim_player.has_animation("idle"):
			_anim_player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		if _anim_player.has_animation("attack"):
			_anim_player.get_animation("attack").loop_mode = Animation.LOOP_NONE
		if _anim_player.has_animation("die"):
			_anim_player.get_animation("die").loop_mode = Animation.LOOP_NONE
	idle_enabled = false
	_play_clip("idle")

func _setup_muzzle_flash() -> void:
	if not shoot_point:
		return
	_flash_mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.08
	torus.outer_radius = 0.18
	torus.rings = 8
	torus.ring_segments = 6
	_flash_mesh.mesh = torus
	
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1.0, 0.85, 0.25, 0.0)
	_flash_mesh.material_override = _flash_mat
	_flash_mesh.visible = false
	shoot_point.add_child(_flash_mesh)

func _setup_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			var mat = node.get_active_material(i)
			if not mat:
				mat = node.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				# Enable vertex color shading for authentic botanical gradient (green -> ivory -> magenta)
				mat.vertex_color_use_as_albedo = true
	for child in node.get_children():
		_setup_materials(child)

func _physics_process(delta: float) -> void:
	if is_remote:
		return
	# CONTRACT(plant-stun): stunned turrets freeze in place (no scan, turn or fire).
	if is_stunned():
		return
	# Zero idle cost: with no live enemies there is nothing to acquire, so skip
	# the group scan/alloc entirely and settle to guard facing.
	if GameManager != null and GameManager.alive_enemies == 0:
		_current_target = null
		_scan_cooldown = scan_interval
		shoot_timer = shoot_interval # stay ready so acquisition fires instantly
		rotation.y = rotate_toward(rotation.y, base_rotation_y, turn_speed_rad * delta)
		if always_shooting: # debug ambient fire straight ahead (no target needed)
			_shoot()
		return
	# Throttled re-scan; per-tick validation is a cheap validity check.
	_scan_cooldown -= delta
	if _scan_cooldown <= 0.0:
		_scan_cooldown = scan_interval
		if is_instance_valid(_current_target):
			# Keep engaging current target as long as it remains alive, in range, and within an expanded tracking cone
			var diff: Vector3 = _current_target.global_position - global_position
			diff.y = 0.0
			var dist_sq: float = diff.length_squared()
			if dist_sq > vision_range_sq or (diff / sqrt(dist_sq)).dot(base_forward) < _tracking_cone_cos:
				_current_target = acquire_target()
		else:
			_current_target = acquire_target()
	elif not is_instance_valid(_current_target):
		_current_target = null

	if not is_instance_valid(_current_target):
		_current_target = null
		shoot_timer = shoot_interval # stay ready so acquisition fires instantly
		# Return smoothly to resting guard facing when idle
		rotation.y = rotate_toward(rotation.y, base_rotation_y, turn_speed_rad * delta)
		if always_shooting: # debug ambient fire straight ahead (no target needed)
			_shoot()
		return
	# Burrow-rise spawns are invulnerable until surfaced; airborne gliders until
	# touchdown (CONTRACT(add-wave)): drop a target that started rising/gliding.
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

	# Motion comes from the baked `attack` clip (0.5s, apex 0.24s); the seed
	# spawns on a timer at the apex and the swing resets on a timer at the end.
	# Timer-based (not animation_finished) so sequencing is independent of
	# importer loop defaults; the generation token aborts stale swings.
	_play_clip("attack")
	_spawn_at_apex(gen)
	_finish_attack(gen)

func _spawn_at_apex(gen: int) -> void:
	await get_tree().create_timer(_attack_apex).timeout
	# A stun landing mid-swing cancels the shot (CONTRACT(plant-stun)).
	if gen != _attack_gen or _dead or is_stunned():
		return
	_spawn_projectile()

func _finish_attack(gen: int) -> void:
	await get_tree().create_timer(_attack_duration).timeout
	if gen != _attack_gen or _dead:
		return
	_play_clip("idle")
	_is_attacking = false
	idle_enabled = true

func _play_clip(clip_name: String) -> void:
	if _anim_player and _anim_player.has_animation(clip_name):
		if _anim_player.current_animation != clip_name or not _anim_player.is_playing():
			_anim_player.play(clip_name)
	elif _anim_player:
		BalanceDB.report_missing_clip(unit_id, clip_name) # logs once (CONTRACT(clip-names))

## Eaten: baked `die` shrink, then free. Mirrors HungryGhost._die; the tile
## is already freed by the signal up front, so shovel timing is unaffected.
func die() -> void:
	if _dead:
		return
	_dead = true
	_attack_gen += 1
	EventBus.plant_died.emit(grid_coord)
	_play_clip("die")
	await get_tree().create_timer(DIE_DURATION).timeout
	queue_free()

func _spawn_projectile() -> void:
	if not _projectile_scene or not shoot_point:
		return

	# Fire along current turret facing (flat XZ).
	var facing: Vector3 = global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = Vector3.MODEL_FRONT
	facing = facing.normalized()

	var proj = _projectile_scene.instantiate() as Projectile
	proj.damage = int(BalanceDB.num(unit_id, "damage", proj.damage))
	# Add to diorama parent (world scene) BEFORE touching transforms:
	# global_position setters error on nodes outside the tree.
	var parent_node = get_parent()
	if parent_node:
		parent_node.add_child(proj)
	else:
		get_tree().current_scene.add_child(proj)
	proj.global_position = shoot_point.global_position
	proj.direction = facing
	if facing.length_squared() > 0.001:
		proj.look_at(proj.global_position - facing, Vector3.UP) # model nose is +Z

	EventBus.projectile_fired.emit(proj)
	Audio.play(Audio.LOTUS_SHOOT)
	_spawn_muzzle_flash()

func _spawn_muzzle_flash() -> void:
	if not is_instance_valid(_flash_mesh):
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	
	_flash_mesh.visible = true
	_flash_mesh.scale = Vector3(0.5, 0.5, 0.5)
	_flash_mat.albedo_color.a = 0.95
	
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_property(_flash_mesh, "scale", Vector3(1.8, 1.8, 1.8), 0.14)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.14)
	_flash_tween.chain().tween_callback(func():
		if is_instance_valid(_flash_mesh):
			_flash_mesh.visible = false
	)
