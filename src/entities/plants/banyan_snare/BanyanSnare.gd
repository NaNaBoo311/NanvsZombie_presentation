class_name BanyanSnare
extends PlantBase

# Banyan Snare (Cây Đa) - counter to the Cyclo Zombie's crash. A wall whose 300 HP
# outlasts the 200 crash; whenever it is hurt and its roots are ready, every enemy within
# root_radius is rooted in place (HungryGhost.apply_slow(0, root_duration)) and the roots
# rest root_cooldown seconds. Event-driven: all work happens inside take_damage, none per
# frame. Numbers come from data/units/plants/banyan_snare.json.

@export var root_radius: float = 2.2
@export var root_duration: float = 2.5
@export var root_cooldown: float = 4.0

var _root_radius_sq: float = 4.84
var _roots_ready_msec: int = 0
var _attack_duration: float = 0.6
var _anim_player: AnimationPlayer = null
var _dead: bool = false
const DIE_DURATION: float = 0.55 # baked `die` is 0.5 s; margin, then free

# Registry id (data/units/plants/banyan_snare.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "banyan_snare"

func _ready() -> void:
	super._ready()
	root_radius = float(BalanceDB.num(unit_id, "root_radius", root_radius))
	root_duration = float(BalanceDB.num(unit_id, "root_duration", root_duration))
	root_cooldown = float(BalanceDB.num(unit_id, "root_cooldown", root_cooldown))
	_attack_duration = float(BalanceDB.num(unit_id, "attack_duration_sec", _attack_duration))
	_root_radius_sq = root_radius * root_radius
	use_vertex_colors(self)
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player:
		if _anim_player.has_animation("idle"):
			_anim_player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		for clip in ["attack", "die"]:
			if _anim_player.has_animation(clip):
				_anim_player.get_animation(clip).loop_mode = Animation.LOOP_NONE
	idle_enabled = false # the baked idle clip breathes instead
	_play_clip("idle")

func take_damage(amount: int) -> void:
	if is_remote:
		return
	if _dead:
		return
	super.take_damage(amount)
	# CONTRACT(plant-stun): stunned roots stay still.
	if _dead or current_health <= 0 or is_stunned():
		return
	var now: int = Time.get_ticks_msec()
	if now < _roots_ready_msec:
		return
	if _root_enemies() > 0:
		_roots_ready_msec = now + int(root_cooldown * 1000.0)
		_lash()

## Roots every live, grounded enemy within root_radius; returns how many.
func _root_enemies() -> int:
	var rooted: int = 0
	var origin: Vector3 = global_position
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if not (enemy is Node3D) or not is_instance_valid(enemy) or not enemy.has_method("apply_slow"):
			continue
		if enemy.get("is_rising") == true or enemy.get("is_airborne") == true:
			continue
		var diff: Vector3 = (enemy as Node3D).global_position - origin
		if diff.x * diff.x + diff.z * diff.z <= _root_radius_sq:
			enemy.apply_slow(0.0, root_duration)
			rooted += 1
	return rooted

func _lash() -> void:
	_play_clip("attack")
	await get_tree().create_timer(_attack_duration).timeout
	if not _dead:
		_play_clip("idle")

func _play_clip(clip_name: String) -> void:
	if _anim_player and _anim_player.has_animation(clip_name):
		_anim_player.play(clip_name)
	elif _anim_player:
		BalanceDB.report_missing_clip(unit_id, clip_name) # logs once (CONTRACT(clip-names))

## Eaten: baked `die` shrink, then free (the tile is freed by the signal up front).
func die() -> void:
	if _dead:
		return
	_dead = true
	EventBus.plant_died.emit(grid_coord)
	_play_clip("die")
	await get_tree().create_timer(DIE_DURATION).timeout
	queue_free()
