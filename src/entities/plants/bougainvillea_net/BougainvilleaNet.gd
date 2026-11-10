class_name BougainvilleaNet
extends PlantBase

# Bougainvillea Net - ground trap. A bed of thorny vines that hurts every enemy
# standing on its 2x2 m tile once per `tick_interval`. Enemies never notice or
# bite it (`uneatable`), they simply walk over it. Shovel still removes it.

@export var damage: int = 10
@export var tick_interval: float = 1.0

## Half of one grid tile (1 tile = 2x2 m): an enemy is "on the tile" inside it.
const TILE_HALF: float = 1.0
const ATTACK_CLIP_SEC: float = 0.6

var _tick_timer: float = 0.0
var _attack_timer: float = 0.0
var _anim_player: AnimationPlayer = null

# Registry id (data/units/plants/bougainvillea_net.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "bougainvillea_net"
	uneatable = true

func _ready() -> void:
	super._ready()
	damage = int(BalanceDB.num(unit_id, "damage", damage))
	tick_interval = float(BalanceDB.num(unit_id, "tick_interval", tick_interval))
	idle_enabled = false
	_setup_materials(self)
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_play_clip("idle")

func _physics_process(delta: float) -> void:
	if is_remote:
		return
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_play_clip("idle")
	# CONTRACT(plant-stun): a stunned net pauses its damage tick.
	if is_stunned():
		return
	# Zero idle cost: no live enemies means no timer and no group scan.
	if GameManager != null and GameManager.alive_enemies == 0:
		_tick_timer = 0.0
		return
	_tick_timer += delta
	if _tick_timer < tick_interval:
		return
	_tick_timer -= tick_interval
	if _hurt_enemies_on_tile() > 0:
		_attack_timer = ATTACK_CLIP_SEC
		_play_clip("attack")
		Audio.play(Audio.BOUGAINVILLEA_ATTACK)

## Damages every live enemy on this tile; returns how many were hit.
func _hurt_enemies_on_tile() -> int:
	var hit: int = 0
	var origin: Vector3 = global_position
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if not (enemy is Node3D) or not is_instance_valid(enemy):
			continue
		var e := enemy as Node3D
		# Burrow-rise spawns are invulnerable until surfaced; airborne gliders
		# until touchdown (CONTRACT(add-wave)).
		if e.get("is_rising") == true or e.get("is_airborne") == true:
			continue
		var p: Vector3 = e.global_position
		if absf(p.x - origin.x) <= TILE_HALF and absf(p.z - origin.z) <= TILE_HALF and e.has_method("take_damage"):
			e.take_damage(damage)
			hit += 1
	return hit

func _play_clip(clip_name: String) -> void:
	if _anim_player and _anim_player.has_animation(clip_name):
		if _anim_player.current_animation != clip_name or not _anim_player.is_playing():
			_anim_player.play(clip_name)
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
				mat.vertex_color_use_as_albedo = true
	for child in node.get_children():
		_setup_materials(child)
