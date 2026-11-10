class_name Projectile
extends Area3D

# Projectile — the one script every plant shot uses: flies straight along `direction`
# with a rifling spin, damages the first enemy it touches, and dissolves on impact or
# outside the island. A scene only supplies the look (Visuals, TrailParticles) and
# sets `projectile_id`; speed, spin and range come from data/projectiles/<id>.json
# (BalanceDB.projectile_num), the shooter sets `damage` from its own unit JSON.
# CONTRACT(add-projectile): a new shot needs a data/projectiles/<id>.json, a scene under
# src/entities/projectiles/<id>/ whose root sets projectile_id, and a plant whose unit
# JSON names it ("projectile").

@export var projectile_id: String = ""
@export var speed: float = 16.0
@export var damage: int = 20
@export var spin_speed: float = 15.0
@export var max_distance: float = 110.0
@export var map_bound_x: float = 54.0
@export var map_bound_z: float = 54.0
## Guest copy (CONTRACT(lan-coop)): flights are cosmetic, no hit detection and
## no damage — the host's snapshots carry the result.
var is_remote: bool = false

@onready var visuals: Node3D = $Visuals
@onready var trail_particles: CPUParticles3D = $TrailParticles

var direction: Vector3 = Vector3.MODEL_FRONT # +Z direction down the lane
var _distance_traveled: float = 0.0
var _is_despawning: bool = false

func _ready() -> void:
	speed = float(BalanceDB.projectile_num(projectile_id, "speed", speed))
	spin_speed = float(BalanceDB.projectile_num(projectile_id, "spin_speed", spin_speed))
	max_distance = float(BalanceDB.projectile_num(projectile_id, "max_distance", max_distance))
	if is_remote:
		collision_layer = 0
		collision_mask = 0
		monitoring = false
		monitorable = false
	else:
		body_entered.connect(_on_body_entered)
		area_entered.connect(_on_area_entered)
	
	# Look towards flight direction
	if direction.length_squared() > 0.001:
		look_at(global_position - direction, Vector3.UP) # model nose is +Z; look_at aims -Z

func _physics_process(delta: float) -> void:
	if _is_despawning:
		return

	var move_step = speed * delta
	global_position += direction * move_step
	_distance_traveled += move_step

	# Aerodynamic rifling spin
	if is_instance_valid(visuals):
		visuals.rotate_z(spin_speed * delta)

	# Boundary check: disappear when flying outside the diorama island map bounds
	if abs(global_position.x) > map_bound_x or abs(global_position.z) > map_bound_z or global_position.y < -5.0:
		_despawn_out_of_bounds()
	elif _distance_traveled >= max_distance:
		_despawn_out_of_bounds()

func _on_body_entered(body: Node3D) -> void:
	if _is_despawning:
		return
	
	if body.is_in_group("Enemies"):
		_hit(body)
		_impact_and_despawn()

func _on_area_entered(area: Area3D) -> void:
	if _is_despawning:
		return
	
	if area.is_in_group("Enemies"):
		_hit(area)
		_impact_and_despawn()

## What a hit does to the enemy it touched. Shots with a side effect (shield break,
## heal block) override this and keep the rest of the flight and impact.
func _hit(enemy: Node3D) -> void:
	if is_remote:
		return
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage)

func _impact_and_despawn() -> void:
	_is_despawning = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# Mini floral burst on hit (Visuals is a Node3D: scale-only, it has no modulate).
	if is_instance_valid(visuals):
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(visuals, "scale", Vector3(1.6, 1.6, 0.4), 0.08)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()

func _despawn_out_of_bounds() -> void:
	if _is_despawning:
		return
	_is_despawning = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# Gentle floral fade-out as it flies into the boundary mist
	if is_instance_valid(visuals):
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(visuals, "scale", Vector3.ZERO, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()
