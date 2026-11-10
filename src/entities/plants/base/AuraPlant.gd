class_name AuraPlant
extends PlantBase

# Base for plants that act in a circle around themselves on a fixed beat (scent, embers,
# healing sap). Every `pulse_interval` seconds the subclass's _pulse() runs; when it
# touched anything the baked `attack` clip plays once, then `idle` resumes. Numbers come
# from the unit JSON: pulse_interval, aura_radius, attack_duration_sec.
# CONTRACT(plant-stun): the beat pauses while stunned. Zero idle cost: with no live
# enemies the timer and the group walk are skipped (override _needs_enemies to keep going).

@export var pulse_interval: float = 1.0
@export var aura_radius: float = 4.0

var _aura_radius_sq: float = 16.0
var _pulse_timer: float = 0.0
var _attack_timer: float = 0.0
var _attack_duration: float = 0.6
var _anim_player: AnimationPlayer = null
var _dead: bool = false
const DIE_DURATION: float = 0.55 # baked `die` is 0.5 s; margin, then free

func _ready() -> void:
	super._ready()
	pulse_interval = float(BalanceDB.num(unit_id, "pulse_interval", pulse_interval))
	aura_radius = float(BalanceDB.num(unit_id, "aura_radius", aura_radius))
	_attack_duration = float(BalanceDB.num(unit_id, "attack_duration_sec", _attack_duration))
	_aura_radius_sq = aura_radius * aura_radius
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

func _physics_process(delta: float) -> void:
	if is_remote:
		return
	if _dead:
		return
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_play_clip("idle")
	if is_stunned():
		return
	if _needs_enemies() and GameManager != null and GameManager.alive_enemies == 0:
		_pulse_timer = 0.0
		return
	_pulse_timer += delta
	if _pulse_timer < pulse_interval:
		return
	_pulse_timer -= pulse_interval
	if _pulse() > 0:
		_attack_timer = _attack_duration
		_play_clip("attack")

## One beat of the aura. Returns how many units it affected (0 skips the attack clip).
func _pulse() -> int:
	return 0

## False for auras that matter without enemies on the field (e.g. healing).
func _needs_enemies() -> bool:
	return true

## Live enemies inside aura_radius (flat XZ, squared distance). Rising spawns are skipped;
## airborne gliders are included, so each aura decides what a glider gets.
func enemies_in_aura() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var origin: Vector3 = global_position
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if not (enemy is Node3D) or not is_instance_valid(enemy) or enemy.get("is_rising") == true:
			continue
		var diff: Vector3 = (enemy as Node3D).global_position - origin
		if diff.x * diff.x + diff.z * diff.z <= _aura_radius_sq:
			out.append(enemy)
	return out

## Live plants inside aura_radius (flat XZ, squared distance), this plant included.
func plants_in_aura() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var origin: Vector3 = global_position
	for plant in get_tree().get_nodes_in_group("Plants"):
		if not (plant is Node3D) or not is_instance_valid(plant):
			continue
		var diff: Vector3 = (plant as Node3D).global_position - origin
		if diff.x * diff.x + diff.z * diff.z <= _aura_radius_sq:
			out.append(plant)
	return out

func _play_clip(clip_name: String) -> void:
	if _anim_player and _anim_player.has_animation(clip_name):
		if _anim_player.current_animation != clip_name or not _anim_player.is_playing():
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
