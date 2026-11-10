class_name SacredRice
extends PlantBase

# Cây Lúa Thần Hạt Ngọc (Sacred Rice)
# Iconic Vietnamese Cultural Currency Producer replacing Sunflower.
# Gently sways with its Nón Lá and heavy golden ear of grain ("Lúa chín cúi đầu").
# Periodically produces "Hạt Ngọc Trời" (Rice Gems) with an energetic, delightful pop-up effect!

@export var production_interval: float = 14.0
@export var first_production_delay: float = 5.0
@export var gem_scene: PackedScene = preload("res://src/entities/plants/sacred_rice/RiceGem.tscn")

@onready var gem_spawn_point: Marker3D = $GemSpawnPoint
@onready var produce_light: OmniLight3D = $ProduceLight
@onready var sparkle_burst: CPUParticles3D = $SparkleBurst
@onready var shockwave_ring: MeshInstance3D = $ShockwaveRing

var production_timer: float = 0.0
var is_producing: bool = false
var is_first_produce: bool = true
var ring_mat: StandardMaterial3D = null
var _anim_player: AnimationPlayer = null
## Baked `attack` sync points (CONTRACT(clip-names)): peak spawns the gem,
## duration ends the pop. Read from the DB; generator authors to match.
var _attack_apex: float = 0.13
var _attack_duration: float = 0.59
var _dead: bool = false
var _attack_gen: int = 0
var _was_anticipating: bool = false
const DIE_DURATION: float = 0.3 # baked `die` is 0.25s; margin, then free

# Registry id (data/units/plants/sacred_rice.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "sacred_rice"

func _ready() -> void:
	super._ready()
	production_interval = float(BalanceDB.num(unit_id, "production_interval", production_interval))
	first_production_delay = float(BalanceDB.num(unit_id, "first_production_delay", first_production_delay))
	_attack_apex = float(BalanceDB.num(unit_id, "attack_apex_sec", _attack_apex))
	_attack_duration = float(BalanceDB.num(unit_id, "attack_duration_sec", _attack_duration))
	production_timer = first_production_delay
	if produce_light:
		produce_light.visible = false
	# Baked clips own all motion (idle sway + produce pop + death shrink);
	# the code keeps anticipation telegraph, VFX and lights. Loop modes set
	# explicitly so sequencing never depends on importer defaults.
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
	
	# Make shockwave material unique per instance
	if shockwave_ring:
		var orig_mat = shockwave_ring.get_active_material(0)
		if orig_mat:
			ring_mat = orig_mat.duplicate() as StandardMaterial3D
			shockwave_ring.set_surface_override_material(0, ring_mat)

func _process(delta: float) -> void:
	if is_remote:
		return
	if is_producing:
		return
	# CONTRACT(plant-stun): a stunned rice pauses its production countdown (and
	# hides the anticipation glow, which resumes with the countdown).
	if is_stunned():
		if produce_light and produce_light.visible:
			produce_light.visible = false
		return
		
	production_timer -= delta
	
	# Anticipation squash, excited quiver & golden glow 1.2s before producing.
	# Drives the outer `visuals` node only; the baked `idle` clip breathes the
	# head underneath. Procedural breathing stays off (idle_enabled false).
	var anticipation_window: float = 1.2
	if production_timer <= anticipation_window and production_timer > 0.0:
		_was_anticipating = true
		var progress: float = 1.0 - (production_timer / anticipation_window) # 0.0 -> 1.0
		
		# Smooth crouch down gathering celestial energy
		var squash: float = sin(progress * PI)
		visuals.scale.y = 1.0 - squash * 0.16
		visuals.scale.x = 1.0 + squash * 0.10
		visuals.scale.z = 1.0 + squash * 0.10
		
		# Excited high-frequency vibration/shiver as energy peaks
		var quiver_freq: float = 24.0 + progress * 16.0
		var quiver_amp: float = progress * 0.015
		visuals.position.x = sin(progress * quiver_freq) * quiver_amp
		visuals.position.z = cos(progress * quiver_freq * 1.3) * (quiver_amp * 0.6)
		
		# Build-up golden light shimmer (light enabled only inside the window,
		# otherwise it sits in the forward light loop at zero energy).
		if produce_light:
			produce_light.visible = true
			produce_light.light_energy = squash * 2.2
	else:
		if produce_light and produce_light.visible:
			produce_light.visible = false
		if _was_anticipating and not is_producing:
			_was_anticipating = false
			visuals.position = Vector3.ZERO
			visuals.scale = Vector3.ONE
	
	if production_timer <= 0.0:
		_produce_gem()

func _produce_gem() -> void:
	is_producing = true
	_attack_gen += 1
	var gen: int = _attack_gen

	# Trigger all VFX bursts (light flash, particles, shockwave)
	_play_pop_vfx()

	# Motion comes from the baked `attack` clip (0.59s, peak 0.13s); the gem
	# spawns on a timer at the peak and the pop resets on a timer at the end.
	# Timer-based (not animation_finished) so sequencing is independent of
	# importer loop defaults; the generation token aborts stale pops.
	_play_clip("attack")
	_spawn_at_peak(gen)
	_finish_produce(gen)

func _spawn_at_peak(gen: int) -> void:
	await get_tree().create_timer(_attack_apex).timeout
	if gen != _attack_gen or _dead:
		return
	_spawn_gem_instance()

func _finish_produce(gen: int) -> void:
	await get_tree().create_timer(_attack_duration).timeout
	if gen != _attack_gen or _dead:
		return
	visuals.position = Vector3.ZERO
	visuals.scale = Vector3.ONE
	_play_clip("idle")
	is_first_produce = false
	production_timer = production_interval
	is_producing = false

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

func _play_pop_vfx() -> void:
	# Light burst (hidden again when the flash decays so rest costs nothing).
	if produce_light:
		produce_light.visible = true
		produce_light.light_energy = 5.0
		var light_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		light_tween.tween_property(produce_light, "light_energy", 0.0, 0.45)
		light_tween.tween_callback(func():
			if is_instance_valid(produce_light):
				produce_light.visible = false
		)
	
	# Sparkle particles burst
	if sparkle_burst:
		sparkle_burst.restart()
		sparkle_burst.emitting = true
		
	# Golden shockwave ring explosion
	if shockwave_ring and ring_mat:
		shockwave_ring.visible = true
		shockwave_ring.scale = Vector3(0.15, 0.15, 0.15)
		ring_mat.albedo_color.a = 0.95
		
		var ring_tween = create_tween().set_parallel(true)
		ring_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ring_tween.tween_property(shockwave_ring, "scale", Vector3(2.6, 2.6, 2.6), 0.38)
		ring_tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.38)
		ring_tween.chain().tween_callback(func():
			shockwave_ring.visible = false
		)

func _spawn_gem_instance() -> void:
	if not gem_scene:
		return
	var gem = gem_scene.instantiate() as RiceGem
	if not gem:
		return
	gem.currency_value = int(BalanceDB.num(unit_id, "gem_value", gem.currency_value))
		
	var start_pos = gem_spawn_point.global_position if gem_spawn_point else global_position + Vector3(0.42, 0.52, 0.30)
	# Drop position in front of plant
	var offset_x = randf_range(-0.75, 0.75)
	var offset_z = randf_range(0.5, 1.2)
	var target_pos = global_position + Vector3(offset_x, 0.0, offset_z)
	
	var root_world = get_tree().current_scene
	if root_world:
		root_world.add_child(gem)
	else:
		get_parent().add_child(gem)
		
	gem.spawn_arc(start_pos, target_pos)
