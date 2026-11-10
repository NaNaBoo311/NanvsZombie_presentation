class_name KimBongCarpenter
extends HungryGhost

# Kim Bong Carpenter (Cleave) - a woodworker from the Kim Bong carpentry village
# across the Thu Bon river from Hoi An: head wrap, plank on one shoulder, adze in
# the other hand. A HungryGhost whose numbers live in
# data/units/enemies/kim_bong_carpenter.json; march/seek/siege AI, health bar and
# materials are inherited.
#
# Cleave: on each normal bite tick (bite_interval) the adze sweep damages EVERY plant
# inside the same frontal cone the base class bites with (eat_range /
# eat_half_angle_deg, via the cached _eat_range_sq / _eat_cone_cos), not only the
# targeted one. Facing, attack clip, bite timer and sound match the base bite; one
# ENEMY_EAT sound per sweep. Plants that are rising, airborne or `uneatable` ground
# traps are skipped exactly like PlantBase.find_nearest_in_cone does. The "Plants"
# group is walked only on the bite tick; the squared cone cosine is cached in
# _update_cached_math, so there is no sqrt, trig or division per tick.

var _eat_cone_cos_sq: float = 0.75

# Registry id (data/units/enemies/kim_bong_carpenter.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "kim_bong_carpenter"

func _update_cached_math() -> void:
	super._update_cached_math()
	_eat_cone_cos_sq = _eat_cone_cos * _eat_cone_cos

func _eat_plant(plant: Node3D, delta: float) -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	# Face the meal (identical to the base bite).
	var to_plant: Vector3 = plant.global_position - global_position
	to_plant.y = 0.0
	if to_plant.length_squared() > 0.0001:
		rotation.y = rotate_toward(rotation.y, atan2(to_plant.x, to_plant.z), TURN_SPEED_RAD * delta)
	_play_clip("attack", eat_anim_speed)
	_bite_timer += delta
	if _bite_timer < bite_interval:
		return
	_bite_timer = 0.0
	var hit_any: bool = false
	var forward: Vector3 = global_transform.basis.z
	for candidate in get_tree().get_nodes_in_group("Plants"):
		if not (candidate is Node3D) or not is_instance_valid(candidate):
			continue
		if candidate.get("is_rising") == true or candidate.get("is_airborne") == true:
			continue
		if candidate.get("uneatable") == true:
			continue
		if not candidate.has_method("take_damage"):
			continue
		if not _in_cleave_cone(candidate as Node3D, forward):
			continue
		candidate.take_damage(bite_damage)
		hit_any = true
	if hit_any:
		Audio.play(Audio.ENEMY_EAT)

## Same squared-distance + squared-cosine test as HungryGhost._is_bitable.
func _in_cleave_cone(p: Node3D, forward: Vector3) -> bool:
	var to_p: Vector3 = p.global_position - global_position
	to_p.y = 0.0
	var dist_sq: float = to_p.length_squared()
	if dist_sq < 0.0001 or dist_sq > _eat_range_sq:
		return false
	var d: float = to_p.dot(forward)
	if d < 0.0:
		return false
	return d * d >= dist_sq * _eat_cone_cos_sq
