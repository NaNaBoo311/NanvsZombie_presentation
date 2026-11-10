class_name StreetVendorZombie
extends HungryGhost

# Street Vendor Zombie (Shield / Tank) - a Hanoi Old Quarter hang rong vendor
# whose two woven baskets (thung) on a bamboo shoulder pole (don ganh) soak up
# damage. A HungryGhost whose numbers live in data/units/enemies/street_vendor_zombie.json;
# all march/seek/eat/siege AI, health bar and materials are inherited.
#
# Shield: the first shield_health points of damage drain the baskets, not the
# body; whatever a hit has left over after the shield breaks spills into the
# body. While it holds the vendor trudges at `speed`. On the break (one-way latch)
# the baskets fly off on a code-driven arc (a tween on the real basket pivots, like
# the pot helmet of CastIronPotGhost), linger a few seconds, shrink away and are
# freed, and the vendor switches to broken_speed. Nothing else is interrupted.
# The health bar tracks the body only.

## Hit points of the basket shield (data: numbers.shield_health).
@export var shield_health: int = 120
## March speed (m/s) once the baskets are gone (data: numbers.broken_speed).
@export var broken_speed: float = 0.9

## The walk clip is authored for ~0.9 m/s, so playback scale is speed * this.
const WALK_ANIM_PER_SPEED: float = 1.1111111
const BASKET_NODES: Array[String] = ["basket_front_pivot", "basket_back_pivot"]
## Raw local radius of a basket belly: it lands tipped on its side.
const BASKET_RADIUS_RAW: float = 0.23
const BASKET_GROUND_EPS: float = 0.02
## Fallback lawn surface when no map is loaded (same value as CastIronPotGhost).
const FALLBACK_LAWN_Y: float = 0.27804451
const BASKET_LINGER_TIME: float = 3.0
const BASKET_SHRINK_TIME: float = 0.45

var _shield: int = 0

# Registry id (data/units/enemies/street_vendor_zombie.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "street_vendor_zombie"

func _ready() -> void:
	super._ready()
	_shield = shield_health

func _apply_balance() -> void:
	super._apply_balance()
	shield_health = int(BalanceDB.num(unit_id, "shield_health", shield_health))
	broken_speed = float(BalanceDB.num(unit_id, "broken_speed", broken_speed))

## Walk playback follows the march speed (slow while shielded, brisk after).
func _walk_anim_scale() -> float:
	return speed * WALK_ANIM_PER_SPEED

## Basket shield points left (0 once broken); shield-breaking shots read this.
func shield_points() -> int:
	return _shield

func take_damage(amount: int) -> void:
	if _dead or is_rising or is_airborne:
		return
	if _shield <= 0:
		super.take_damage(amount)
		return
	_shield -= amount
	if _shield > 0:
		super.take_damage(0) # flinch + health-bar reveal; the body is untouched
		return
	var overflow: int = -_shield
	_shield = 0
	speed = broken_speed
	_drop_baskets()
	super.take_damage(overflow)

func _lawn_surface_y() -> float:
	var map := get_tree().get_first_node_in_group(MapDefinition.GROUP) as MapDefinition if is_inside_tree() else null
	if is_instance_valid(map):
		return map.ground_y + 0.05
	return FALLBACK_LAWN_Y

## The walk/attack/die clips author the baskets hanging from the pole, so playing
## any of them after the drop would snap them back. Strip the basket tracks from
## this instance's copies (the imported library is shared by every vendor), then
## fling the real pivots onto the lawn with tweens.
func _drop_baskets() -> void:
	var pivots: Array[Node3D] = []
	for node_name in BASKET_NODES:
		var p := find_child(node_name, true, false) as Node3D
		if is_instance_valid(p):
			pivots.append(p)
	if pivots.is_empty():
		return
	if _anim_player and _anim_player.has_animation_library(""):
		var own_lib := (_anim_player.get_animation_library("") as AnimationLibrary).duplicate()
		_anim_player.remove_animation_library("")
		_anim_player.add_animation_library("", own_lib)
		for clip in ["walk", "attack", "die"]:
			if not own_lib.has_animation(clip):
				continue
			var anim := (own_lib.get_animation(clip) as Animation).duplicate()
			for i in range(anim.get_track_count() - 1, -1, -1):
				var path := str(anim.track_get_path(i))
				if path.contains("basket_front_pivot") or path.contains("basket_back_pivot"):
					anim.remove_track(i)
			own_lib.remove_animation(clip)
			own_lib.add_animation(clip, anim)
	var fwd: Vector3 = global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3(0.0, 0.0, 1.0)
	var side: Vector3 = Vector3.UP.cross(fwd).normalized()
	# Front basket tumbles ahead, back basket behind, splaying to opposite sides.
	_fling_basket(pivots[0], fwd, side, 1.0)
	if pivots.size() > 1:
		_fling_basket(pivots[1], -fwd, side, -1.0)

func _fling_basket(pivot: Node3D, dir: Vector3, side: Vector3, sign_side: float) -> void:
	# Save the world transform BEFORE toggling top_level (it re-parents to the root).
	var start_xform: Transform3D = pivot.global_transform
	var world_scale_y: float = start_xform.basis.get_scale().y
	pivot.top_level = true
	pivot.global_transform = start_xform
	var start_pos: Vector3 = pivot.global_position
	var start_rot: Vector3 = pivot.rotation
	var up := Vector3.UP
	var apex_pos: Vector3 = start_pos + up * 0.55 + dir * 0.35
	var fall_pos: Vector3 = start_pos + up * 0.15 + dir * 0.85 + side * (0.15 * sign_side)
	var rest_y: float = _lawn_surface_y() + BASKET_RADIUS_RAW * world_scale_y + BASKET_GROUND_EPS
	var rest_pos := Vector3(
		start_pos.x + dir.x * 1.2 + side.x * 0.3 * sign_side,
		rest_y,
		start_pos.z + dir.z * 1.2 + side.z * 0.3 * sign_side)
	var bounce_pos: Vector3 = rest_pos + up * 0.15
	var settle_pos: Vector3 = rest_pos + dir * 0.08
	var pos_tween := pivot.create_tween()
	pos_tween.tween_property(pivot, "global_position", apex_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pos_tween.tween_property(pivot, "global_position", fall_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	pos_tween.tween_property(pivot, "global_position", rest_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	pos_tween.tween_property(pivot, "global_position", bounce_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pos_tween.tween_property(pivot, "global_position", rest_pos, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	pos_tween.tween_property(pivot, "global_position", settle_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Scale-only shrink (shared materials untouched), then freed: zero idle cost after.
	pos_tween.tween_interval(BASKET_LINGER_TIME)
	pos_tween.tween_property(pivot, "scale", Vector3.ONE * 0.01, BASKET_SHRINK_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	pos_tween.tween_callback(func() -> void:
		if is_instance_valid(pivot):
			pivot.queue_free()
	)
	# Tumble onto its side, like the viewer's drop_baskets clip.
	var rot_tween := pivot.create_tween()
	rot_tween.tween_property(pivot, "rotation", start_rot + Vector3(-0.4 * sign_side, 0.3, 0.5 * sign_side), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rot_tween.tween_property(pivot, "rotation", Vector3(0.1 * sign_side, 0.2, 1.45 * sign_side), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
