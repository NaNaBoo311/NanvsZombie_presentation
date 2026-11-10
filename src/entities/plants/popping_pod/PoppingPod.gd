class_name PoppingPod
extends PlantBase

# Popping Pod (Trái Nổ / Potato Mine role) - Slot 3 explosive defender.
# Lifecycle: buried UNDERGROUND for `bury_duration` (plays 'underground' clip,
# pod tip peeking like a periscope), then grows up ('grow' clip) and arms.
# Once armed, a proximity fuse detonates when any enemy enters `fuse_radius`;
# the blast deals lethal damage to ALL enemies within `blast_radius`.
# Vulnerable while buried: ghosts can still notice and eat it (no hiding from
# targeting, collision stays active). One-shot: detonation frees the tile.

@export var bury_duration: float = 5.0
## MUST exceed HungryGhost.eat_range (1.8m): the ghost halts in place to chomp
## once the plant is bitable, so a smaller fuse would never be reached and the
## pod would just get eaten. 2.0m also covers the ~0.18m a ghost can travel
## between 0.15s fuse scans. Blast (3.5m) still outranges the fuse.
@export var fuse_radius: float = 2.0
@export var blast_radius: float = 3.5
@export var blast_damage: int = 9999
@export var scan_interval: float = 0.15

var _armed: bool = false
var _exploded: bool = false
var _arm_timer: float = 5.0
var _scan_cooldown: float = 0.0
var _fuse_radius_sq: float = 4.0
var _blast_radius_sq: float = 12.25
var _anim_player: AnimationPlayer = null

# Registry id (data/units/plants/popping_pod.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "popping_pod"

func _ready() -> void:
	super._ready()
	bury_duration = float(BalanceDB.num(unit_id, "bury_duration", bury_duration))
	fuse_radius = float(BalanceDB.num(unit_id, "fuse_radius", fuse_radius))
	blast_radius = float(BalanceDB.num(unit_id, "blast_radius", blast_radius))
	blast_damage = int(BalanceDB.num(unit_id, "blast_damage", blast_damage))
	scan_interval = float(BalanceDB.num(unit_id, "scan_interval", scan_interval))
	idle_enabled = false
	_arm_timer = bury_duration
	_fuse_radius_sq = fuse_radius * fuse_radius
	_blast_radius_sq = blast_radius * blast_radius
	_setup_materials(self)
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_play_clip("underground")

func _physics_process(delta: float) -> void:
	if is_remote:
		return
	# CONTRACT(plant-stun): a stunned pod pauses arming and its fuse scan.
	if _exploded or is_stunned():
		return
	if not _armed:
		_arm_timer -= delta
		if _arm_timer <= 0.0:
			_arm_up()
		return
	# Armed: throttled proximity fuse scan (enemies move on physics frames).
	# Zero idle cost: no live enemies means no group scan/alloc at all.
	if GameManager != null and GameManager.alive_enemies == 0:
		_scan_cooldown = scan_interval
		return
	_scan_cooldown -= delta
	if _scan_cooldown > 0.0:
		return
	_scan_cooldown = scan_interval
	if _enemy_within(fuse_radius, _fuse_radius_sq):
		_detonate()

## Flat XZ check: is any live enemy within `radius` of this pod?
func _enemy_within(_radius: float, radius_sq: float) -> bool:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("Enemies")
	for enemy in enemies:
		if not (enemy is Node3D):
			continue
		var e := enemy as Node3D
		if not is_instance_valid(e):
			continue
		# Burrow-rise spawns are invulnerable until surfaced; airborne gliders
		# until touchdown (CONTRACT(add-wave)).
		if e.get("is_rising") == true or e.get("is_airborne") == true:
			continue
		var diff: Vector3 = e.global_position - global_position
		diff.y = 0.0
		if diff.length_squared() <= radius_sq:
			return true
	return false

func _arm_up() -> void:
	_armed = true
	_play_clip("grow")

func _detonate() -> void:
	if _exploded:
		return
	_exploded = true
	set_physics_process(false)
	# Free the grid tile immediately so it can be replanted during the blast.
	EventBus.plant_died.emit(grid_coord)
	_play_clip("attack")
	# Damage lands on the pod snap (~0.24s into the 1.6s clip), synced with
	# the valves bursting open and the flash star appearing.
	await get_tree().create_timer(0.24).timeout
	if not is_instance_valid(self):
		return
	_apply_blast_damage()
	# Fixed-timer cleanup (never waits on animation_finished: imported clips
	# may loop, which would linger the plant forever).
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		queue_free()

func _apply_blast_damage() -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("Enemies")
	for enemy in enemies:
		if not (enemy is Node3D):
			continue
		var e := enemy as Node3D
		if not is_instance_valid(e):
			continue
		# Burrow-rise spawns are invulnerable until surfaced; airborne gliders
		# until touchdown (CONTRACT(add-wave)).
		if e.get("is_rising") == true or e.get("is_airborne") == true:
			continue
		var diff: Vector3 = e.global_position - global_position
		diff.y = 0.0
		if diff.length_squared() <= _blast_radius_sq and e.has_method("take_damage"):
			e.take_damage(blast_damage)

func take_damage(amount: int) -> void:
	if is_remote:
		return
	# Ignore bites during the blast so the explosion always completes.
	if _exploded:
		return
	# Any bite landing on an ARMED pod sets it off instead of wounding it:
	# guarantees contact detonation even if the ghost spawns directly on top
	# between fuse scans. Buried pods stay vulnerable and take damage normally.
	# A stunned pod cannot detonate: bites wound it like any plant (CONTRACT(plant-stun)).
	if _armed and not is_stunned():
		_detonate()
		return
	super.take_damage(amount)

func die() -> void:
	# Normal death (eaten before detonating): standard PlantBase pop-out.
	# Explosion cleanup is handled by _detonate(), never double-free the tile.
	if _exploded:
		return
	super.die()

## Shovel defuses instead of detonating: never call _detonate() here, even
## when armed (bites detonate, the shovel does not). Marks exploded first so
## in-flight fuse scans / bite callbacks become no-ops, then reuses the
## PlantBase pop-out removal.
func remove_by_shovel() -> void:
	if _exploded:
		return
	_exploded = true
	set_physics_process(false)
	set_collision_layer_value(3, false) # unpickable during the pop-out (no double-dig)
	EventBus.plant_died.emit(grid_coord)
	EventBus.plant_removed.emit(grid_coord)
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(visuals, "scale", Vector3.ZERO, 0.25)
	tween.tween_callback(queue_free)

func _play_clip(clip_name: String) -> void:
	if _anim_player and _anim_player.has_animation(clip_name):
		if _anim_player.current_animation != clip_name or not _anim_player.is_playing():
			_anim_player.play(clip_name)
	elif _anim_player:
		BalanceDB.report_missing_clip(unit_id, clip_name) # logs once (CONTRACT(clip-names))

func _setup_materials(node: Node) -> void:
	# Godot glTF import leaves vertex_color_use_as_albedo=false: re-enable
	# only when vertex colors actually exist so textured PBR materials are preserved.
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
