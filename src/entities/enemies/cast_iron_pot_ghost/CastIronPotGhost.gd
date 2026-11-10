class_name CastIronPotGhost
extends HungryGhost

# Cast-Iron Pot Ghost (Armored Tank) - a HungryGhost with 200 HP and a heavy
# 0.9 m/s march. Crossing 50% HP pops the pot helmet off: the pot tumbles to
# the lawn on a code-driven arc, lingers a few seconds, then shrinks away,
# while the ghost keeps its current action
# (marching, seeking, chomping, or sieging) completely uninterrupted - no
# timers paused, no clips overridden, no state changed. All march/seek/attack/
# siege AI, health bar, and materials are inherited untouched.

var _armor_broken: bool = false

# Registry id (data/units/enemies/cast_iron_pot_ghost.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "cast_iron_pot_ghost"

func _ready() -> void:
	# Balance owns the numbers (data/units/enemies/cast_iron_pot_ghost.json); unit_id is set in _init.
	super._ready()

func take_damage(amount: int) -> void:
	super.take_damage(amount)
	if _dead or _armor_broken:
		return
	if _health * 2 <= max_health and _anim_player and _anim_player.has_animation("low_hp"):
		_armor_broken = true
		_pop_pot_helmet()

## The walk/attack/die clips all author the pot sitting ON the head, so
## resuming any of them after the pop would snap it back on. Strip the
## pot_helmet_pivot tracks from this instance's copies, then fling the real
## pivot onto the lawn with a tween. Duplicated library first: imported
## animations are shared across every pot ghost, and unbroken ones must
## keep their pots. The 'low_hp' clip is never played in-game (it stays in
## the .glb for the model viewer); the tween below replays its signature
## beats (pop up, apex, falling flip, lawn impact, bounce, settle) while the
## AnimationPlayer carries on with whatever it was doing.
## Detached pot rest height: raw local +Y extent of the pot meshes above the
## pivot origin (rim at y=0). Tallest point is the dome pole at ~0.38
## (center 0.20 + radius 0.24 * y-scale 0.75; foot ring 0.2975 and soot
## 0.31 are lower). After the end-flip of PI around X this extent hangs
## BELOW the pivot, so rest pivot Y = lawn surface + extent * world scale.
const POT_TOP_RAW := 0.38
## Small lift so the dome kisses the turf instead of z-fighting the grass.
const POT_GROUND_EPS := 0.02
## Fallback lawn surface when no map is loaded (island base 0.22804451 +
## lawnAccent 0.05, same source as GrassMultiMesh).
const FALLBACK_LAWN_Y := 0.27804451
## How long the fallen pot lingers on the lawn before vanishing.
const POT_LINGER_TIME := 3.0
## Shrink-out duration (scale tween, then freed: zero idle/draw cost after).
const POT_SHRINK_TIME := 0.45

func _lawn_surface_y() -> float:
	var map := get_tree().get_first_node_in_group(MapDefinition.GROUP) as MapDefinition if is_inside_tree() else null
	if is_instance_valid(map):
		return map.ground_y + 0.05
	return FALLBACK_LAWN_Y

func _pop_pot_helmet() -> void:
	var pivot := find_child("pot_helmet_pivot", true, false) as Node3D
	if not is_instance_valid(pivot):
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
				if str(anim.track_get_path(i)).contains("pot_helmet_pivot"):
					anim.remove_track(i)
			own_lib.remove_animation(clip)
			own_lib.add_animation(clip, anim)
	# World-space fall: pin the pivot so the bobbing head no longer drags it.
	# Save the head-space world transform FIRST: toggling top_level re-parents
	# to the scene root, and reading global_position afterwards would capture
	# the snapped (wrong) origin. Restoring keeps size/pose seamless and keeps
	# the 1.5x model scale so the pot neither shrinks nor jumps on detach.
	var start_xform: Transform3D = pivot.global_transform
	var world_scale_y: float = start_xform.basis.get_scale().y
	pivot.top_level = true
	pivot.global_transform = start_xform
	var start_pos: Vector3 = pivot.global_position
	var start_rot: Vector3 = pivot.rotation
	# Forward (+Z facing) and right vectors on the flat lawn plane.
	var fwd: Vector3 = global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3(0.0, 0.0, 1.0)
	var side: Vector3 = Vector3.UP.cross(fwd).normalized()
	var up := Vector3.UP
	var apex_pos: Vector3 = start_pos + up * 0.60 + fwd * 0.10
	var fall_pos: Vector3 = start_pos + up * 0.10 + fwd * 0.55
	# Rest ON the lawn, not in it: the flipped dome hangs POT_TOP_RAW below
	# the pivot, so lift the pivot by extent * world scale. Old code used a
	# hardcoded 0.08 while the lawn surface sits at ~0.233 -> buried pot.
	var rest_y: float = _lawn_surface_y() + POT_TOP_RAW * world_scale_y + POT_GROUND_EPS
	var rest_pos := Vector3(
		start_pos.x + fwd.x * 0.90 + side.x * 0.20,
		rest_y,
		start_pos.z + fwd.z * 0.90 + side.z * 0.20)
	var bounce_pos: Vector3 = rest_pos + up * 0.17
	var settle_pos: Vector3 = rest_pos + fwd * 0.05
	var flat_rot := Vector3(PI, 0.05, 0.0)
	# Position arc: pop, apex, accelerating fall, impact, bounce, settle.
	var pos_tween := pivot.create_tween()
	pos_tween.tween_property(pivot, "global_position", start_pos + up * 0.35 - fwd * 0.10, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pos_tween.tween_property(pivot, "global_position", apex_pos, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pos_tween.tween_property(pivot, "global_position", fall_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	pos_tween.tween_property(pivot, "global_position", rest_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	pos_tween.tween_property(pivot, "global_position", bounce_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pos_tween.tween_property(pivot, "global_position", rest_pos, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	pos_tween.tween_property(pivot, "global_position", settle_pos, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Linger on the lawn, then shrink away and free the pivot. Scale-only so
	# shared pot materials are untouched (a material fade would leak to every
	# ghost); freeing drops the extra draw cost back to zero. Bound to the
	# pivot, so ghost death mid-arc kills the tween safely with it.
	pos_tween.tween_interval(POT_LINGER_TIME)
	pos_tween.tween_property(pivot, "scale", Vector3.ONE * 0.01, POT_SHRINK_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	pos_tween.tween_callback(func() -> void:
		if is_instance_valid(pivot):
			pivot.queue_free()
	)
	# Tumble alongside the fall, then rest flat like the authored end pose.
	var rot_tween := pivot.create_tween()
	rot_tween.tween_property(pivot, "rotation", start_rot + Vector3(-0.35, 0.20, 0.18), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rot_tween.tween_property(pivot, "rotation", flat_rot, 0.50).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
