class_name LobbedProjectile
extends Projectile

# LobbedProjectile — Parabolic arc projectile (Cabbage-pult / Catapult style).
# Launched by catapult plants; arcs high into the sky and drops down onto targets.
# Follows target enemy in flight; if target dies mid-air, lands at last known position.
# On impact or landing, deals damage and bursts into a cloud of cotton puffs.

@export var arc_height: float = 4.0
@export var flight_duration: float = 0.85
## Splash radius (m) from the projectile JSON; 0 keeps the single-target hit. With a
## splash, touchdown (or an early body contact) damages every enemy inside it.
@export var splash_radius: float = 0.0
var _splash_radius_sq: float = 0.0

var target_node: Node3D = null
var target_pos: Vector3 = Vector3.ZERO
var start_pos: Vector3 = Vector3.ZERO
var elapsed_time: float = 0.0
var _has_launched: bool = false

func launch(from_pos: Vector3, target: Node3D, fallback_pos: Vector3 = Vector3.ZERO) -> void:
	global_position = from_pos
	start_pos = from_pos
	target_node = target
	if is_instance_valid(target):
		target_pos = target.global_position
	elif fallback_pos != Vector3.ZERO:
		target_pos = fallback_pos
	else:
		target_pos = from_pos + direction * 14.0
	elapsed_time = 0.0
	_has_launched = true

func _ready() -> void:
	super._ready()
	arc_height = float(BalanceDB.projectile_num(projectile_id, "arc_height", arc_height))
	flight_duration = float(BalanceDB.projectile_num(projectile_id, "flight_duration", flight_duration))
	splash_radius = float(BalanceDB.projectile_num(projectile_id, "splash_radius", splash_radius))
	_splash_radius_sq = splash_radius * splash_radius

func _physics_process(delta: float) -> void:
	if _is_despawning:
		return

	if not _has_launched:
		launch(global_position, null, global_position + direction * 14.0)

	if is_instance_valid(target_node):
		target_pos = target_node.global_position

	elapsed_time += delta
	var t: float = clampf(elapsed_time / maxf(flight_duration, 0.01), 0.0, 1.0)

	var current_xz := start_pos.lerp(target_pos, t)
	var base_y := lerpf(start_pos.y, target_pos.y, t)
	var arc_y := base_y + 4.0 * arc_height * t * (1.0 - t)
	var next_pos := Vector3(current_xz.x, arc_y, current_xz.z)

	var travel_step := next_pos - global_position
	if travel_step.length_squared() > 0.0001:
		look_at(global_position - travel_step, Vector3.UP)

	global_position = next_pos

	# Tumble spin
	if is_instance_valid(visuals):
		visuals.rotate_z(spin_speed * delta)
		visuals.rotate_x(spin_speed * delta * 0.4)

	# Boundary check: diorama island map bounds
	if abs(global_position.x) > map_bound_x or abs(global_position.z) > map_bound_z or global_position.y < -5.0:
		_despawn_out_of_bounds()
		return

	# Touchdown / impact
	if t >= 1.0:
		_on_touchdown()

func _on_body_entered(body: Node3D) -> void:
	if _is_despawning or elapsed_time < flight_duration * 0.8:
		return
	if _splash_radius_sq > 0.0 and body.is_in_group("Enemies"):
		_on_touchdown()
		return
	super._on_body_entered(body)

func _on_area_entered(area: Area3D) -> void:
	if _is_despawning or elapsed_time < flight_duration * 0.8:
		return
	if _splash_radius_sq > 0.0 and area.is_in_group("Enemies"):
		_on_touchdown()
		return
	super._on_area_entered(area)

func _on_touchdown() -> void:
	if _is_despawning:
		return
	if is_remote:
		_impact_and_despawn()
		return
	if _splash_radius_sq > 0.0:
		_splash()
		_impact_and_despawn()
		return

	# Deal damage to primary target or nearest enemy at landing site
	var hit := false
	if is_instance_valid(target_node) and target_node.has_method("take_damage"):
		target_node.take_damage(damage)
		hit = true
	else:
		var enemies := get_tree().get_nodes_in_group("Enemies")
		for e in enemies:
			if is_instance_valid(e) and e is Node3D:
				var diff: Vector3 = e.global_position - global_position
				diff.y = 0.0
				if diff.length_squared() <= 1.5:
					if e.has_method("take_damage"):
						e.take_damage(damage)
						hit = true
					break

	_impact_and_despawn()

## Damages every enemy within splash_radius of the landing point (flat XZ, squared).
func _splash() -> void:
	var origin: Vector3 = global_position
	for e in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var diff: Vector3 = (e as Node3D).global_position - origin
		if diff.x * diff.x + diff.z * diff.z <= _splash_radius_sq:
			_hit(e)

func _impact_and_despawn() -> void:
	_is_despawning = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	if has_node("ImpactParticles"):
		var p := get_node("ImpactParticles") as CPUParticles3D
		if is_instance_valid(p):
			p.emitting = true

	if is_instance_valid(visuals):
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(visuals, "scale", Vector3(1.6, 0.4, 1.6), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(visuals, "scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()
