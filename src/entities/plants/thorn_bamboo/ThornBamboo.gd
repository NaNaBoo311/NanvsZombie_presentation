class_name ThornBamboo
extends PlantBase

# Thorn Bamboo (Tre Gai) - counter to the Kim Bong Carpenter's cleave. A wall: every
# time it is hurt, its thorns deal thorn_damage back to every grounded enemy within
# thorn_radius, so each adze sweep (or bite) costs the attacker. Event-driven: all work
# happens inside take_damage, none per frame. Numbers come from
# data/units/plants/thorn_bamboo.json.

@export var thorn_damage: int = 12
@export var thorn_radius: float = 2.0

var _thorn_radius_sq: float = 4.0
var _attack_duration: float = 0.4
var _anim_player: AnimationPlayer = null
var _dead: bool = false
const DIE_DURATION: float = 0.55 # baked `die` is 0.5 s; margin, then free

# Registry id (data/units/plants/thorn_bamboo.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "thorn_bamboo"

func _ready() -> void:
	super._ready()
	thorn_damage = int(BalanceDB.num(unit_id, "thorn_damage", thorn_damage))
	thorn_radius = float(BalanceDB.num(unit_id, "thorn_radius", thorn_radius))
	_attack_duration = float(BalanceDB.num(unit_id, "attack_duration_sec", _attack_duration))
	_thorn_radius_sq = thorn_radius * thorn_radius
	use_vertex_colors(self)
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player:
		if _anim_player.has_animation("idle"):
			_anim_player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		for clip in ["attack", "die"]:
			if _anim_player.has_animation(clip):
				_anim_player.get_animation(clip).loop_mode = Animation.LOOP_NONE
	idle_enabled = false # the baked idle clip sways instead
	_play_clip("idle")

func take_damage(amount: int) -> void:
	if _dead or is_remote:
		return
	super.take_damage(amount)
	# CONTRACT(plant-stun): stunned thorns do not bite back.
	if amount <= 0 or is_stunned():
		return
	if _prick_attackers() > 0 and not _dead:
		_bristle()

## Deals thorn_damage to every live, grounded enemy within thorn_radius; returns how many.
func _prick_attackers() -> int:
	var hit: int = 0
	var origin: Vector3 = global_position
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if not (enemy is Node3D) or not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		if enemy.get("is_rising") == true or enemy.get("is_airborne") == true:
			continue
		var diff: Vector3 = (enemy as Node3D).global_position - origin
		if diff.x * diff.x + diff.z * diff.z <= _thorn_radius_sq:
			enemy.take_damage(thorn_damage)
			hit += 1
	return hit

func _bristle() -> void:
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
