class_name RiceGem
extends Area3D

# Hạt Ngọc Trời (Gem of Heaven / Rice Gem)
# Tactical collectible currency item produced by Sacred Rice (Cây Lúa Thần)
# Modeled with golden jewel facets, celestial star halo, and husk wings.
# - Pops out in an energetic parabolic arc from the plant to the ground
# - Dynamic squash & stretch during launch and lawn impact bounce
# - Emits expanding golden landing shockwave ring on touchdown
# - Bobs and spins gently with soft celestial luminescence
# - Click to collect, granting +50 currency (Sun / Gems of Heaven)
# - Features delightful collection pop, spin, and float-up animation

@export var currency_value: int = 50
@export var despawn_time: float = 20.0
@export var auto_collect_time: float = 14.0 # Casual-friendly: auto-collects if left unattended

@onready var visuals: Node3D = $Visuals
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var glow_light: OmniLight3D = $GlowLight
@onready var landing_ring: MeshInstance3D = $LandingRing

var is_collected: bool = false
var is_landing: bool = true
## LAN guest copy (CONTRACT(lan-coop)): the host owns the pickup and the Sun.
## A remote gem still reacts to a tap, by asking the host.
var is_remote: bool = false
var net_id: int = 0
var _collect_requested: bool = false
var idle_time: float = 0.0
var base_y: float = 0.0
var life_timer: float = 0.0
var ring_mat: StandardMaterial3D = null

func _ready() -> void:
	collision_layer = 32 # Layer 6: Interactables
	collision_mask = 0
	input_ray_pickable = true
	
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)

	# Resting glow comes from the emissive gem core: keep the omni out of the
	# forward light loop except for the landing / collect flashes.
	if glow_light:
		glow_light.visible = false
	
	# Make landing ring material unique
	if landing_ring:
		var orig_mat = landing_ring.get_active_material(0)
		if orig_mat:
			ring_mat = orig_mat.duplicate() as StandardMaterial3D
			landing_ring.set_surface_override_material(0, ring_mat)

func spawn_arc(start_pos: Vector3, target_pos: Vector3) -> void:
	global_position = start_pos
	base_y = target_pos.y + 0.35 # Hover slightly above ground
	is_landing = true
	
	# Launch pop: start small and elongated along launch direction
	visuals.scale = Vector3(0.5, 1.6, 0.5)
	var scale_tween = create_tween()
	scale_tween.tween_property(visuals, "scale", Vector3(1.15, 1.15, 1.15), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(visuals, "scale", Vector3.ONE, 0.32)
	
	# Celebratory tumble spin during flight
	var spin_tween = create_tween()
	spin_tween.tween_property(visuals, "rotation:y", visuals.rotation.y + PI * 2.0, 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Parabolic trajectory
	var arc_tween = create_tween()
	var apex_y = max(start_pos.y, target_pos.y) + 1.25
	var flight_time = 0.60
	
	# Horizontal movement
	arc_tween.parallel().tween_property(self, "global_position:x", target_pos.x, flight_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc_tween.parallel().tween_property(self, "global_position:z", target_pos.z, flight_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Vertical arc (rise to apex, then drop)
	arc_tween.tween_property(self, "global_position:y", apex_y, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc_tween.tween_property(self, "global_position:y", base_y, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Touchdown impact sequence
	arc_tween.tween_callback(_on_landing_touchdown)
	# Host replication hook: the landing position is only known now, so announce
	# the gem here rather than in _ready (CONTRACT(lan-coop)).
	EventBus.gem_spawned.emit(self)

## Guest: place a replicated gem where the host's gem landed, already resting.
func place_remote(pos: Vector3, value: int) -> void:
	currency_value = value
	is_remote = true
	global_position = pos
	base_y = pos.y
	is_landing = false
	life_timer = 0.0

func _on_landing_touchdown() -> void:
	# Ground impact shockwave ring
	if landing_ring and ring_mat:
		landing_ring.visible = true
		landing_ring.scale = Vector3(0.15, 0.15, 0.15)
		ring_mat.albedo_color.a = 0.85
		
		var ring_tween = create_tween().set_parallel(true)
		ring_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ring_tween.tween_property(landing_ring, "scale", Vector3(2.4, 2.4, 2.4), 0.35)
		ring_tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.35)
		ring_tween.chain().tween_callback(func():
			landing_ring.visible = false
		)
		
	# Ground light flash (light stays out of the forward light loop at rest:
	# the gem core material is already emissive, so only flashes enable it).
	if glow_light:
		glow_light.visible = true
		glow_light.light_energy = 3.2
		var light_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		light_tween.tween_property(glow_light, "light_energy", 1.2, 0.40)
		light_tween.tween_callback(func():
			if not is_collected and is_instance_valid(glow_light):
				glow_light.visible = false
		)
	
	# Juicy squash & bounce on the grass
	var bounce_tween = create_tween()
	bounce_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Squash impact
	bounce_tween.tween_property(visuals, "scale", Vector3(1.42, 0.58, 1.42), 0.08)
	# Upward rebound
	bounce_tween.tween_property(visuals, "scale", Vector3(0.90, 1.14, 0.90), 0.12)
	bounce_tween.parallel().tween_property(visuals, "position:y", 0.10, 0.12)
	# Settle to neutral
	bounce_tween.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	bounce_tween.tween_property(visuals, "scale", Vector3.ONE, 0.16)
	bounce_tween.parallel().tween_property(visuals, "position:y", 0.0, 0.16)
	
	bounce_tween.tween_callback(func():
		is_landing = false
		base_y = global_position.y
	)

func _process(delta: float) -> void:
	if is_collected:
		return
		
	# Idle spin & bob
	idle_time += delta * 2.5
	visuals.rotation.y += delta * 1.8
	
	if not is_landing:
		visuals.position.y = sin(idle_time) * 0.08
		
		# Auto-collect timer (host only: the guest's copy waits for the host's
		# gem_gone event, so both devices agree on when it vanished).
		if is_remote:
			return
		life_timer += delta
		if life_timer >= auto_collect_time:
			collect()

func _on_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if is_collected or _collect_requested:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		collect()
		get_viewport().set_input_as_handled()

func _on_mouse_entered() -> void:
	if is_collected or is_landing:
		return
	# Gentle hover swell
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(visuals, "scale", Vector3(1.2, 1.2, 1.2), 0.1)

func collect() -> void:
	if is_collected or _collect_requested:
		return
	# Guest / remote copy: the host grants the Sun. Ask and wait for gem_gone.
	if is_remote or (GameManager != null and GameManager.is_client()):
		_collect_requested = true
		Net.send_command({"t": "collect", "id": net_id})
		return
	is_collected = true
	Audio.play(Audio.RICE_GEM_COLLECT)

	# Grant currency to GameManager
	if GameManager:
		GameManager.add_sun(currency_value)
	EventBus.gem_collected.emit(self)
	_finish_collect()

## Guest: the host collected this gem. Same juice, no Sun.
func remote_collect() -> void:
	if is_collected:
		return
	is_collected = true
	Audio.play(Audio.RICE_GEM_COLLECT)
	_finish_collect()

func _finish_collect() -> void:
	# Flash light on collection (re-enable: rest state keeps it out of the loop).
	if glow_light:
		glow_light.visible = true
		glow_light.light_energy = 3.6
		var light_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		light_tween.tween_property(glow_light, "light_energy", 0.0, 0.35)
		light_tween.tween_callback(func():
			if is_instance_valid(glow_light):
				glow_light.visible = false
		)
	
	# Satisfying juice: punch scale up, spin fast, rise and pop
	var tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(visuals, "scale", Vector3(1.55, 1.55, 1.55), 0.15)
	tween.tween_property(self, "global_position:y", global_position.y + 1.2, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(visuals, "rotation:y", visuals.rotation.y + PI * 2.5, 0.35)
	
	# Shrink to zero & clean up
	var shrink_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	shrink_tween.tween_interval(0.15)
	shrink_tween.tween_property(visuals, "scale", Vector3.ZERO, 0.20)
	shrink_tween.tween_callback(queue_free)
