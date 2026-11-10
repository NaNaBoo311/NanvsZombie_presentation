class_name TouchInput
extends Node

# Touch gestures for the screens that a mouse cannot drive alone. Phones have
# no mouse, so this node turns raw screen touches into the two actions the
# emulated mouse cannot express:
#   - two fingers spread/pinch -> EventBus.touch_pinch (zoom)
#   - two-finger drag          -> EventBus.touch_drag (camera orbit / rail travel)
# One-finger pan and taps stay on Godot's emulated-mouse path, which is what
# makes every existing Control/button work untouched; this node must therefore
# NOT pan or click, or it would double-handle the same finger.
#
# It runs in _input (before GUI), for one specific reason: it sets
# GameManager.touch_gesture_multi as soon as a SECOND finger lands, and clears it
# only when every finger is up. Placement/dig commit on release, and the
# emulated mouse release can be delivered before the raw touch release — the
# latch is already set by then, so a pinch never plants. (The reverse order is
# also safe because the latch clears last.)
#
# One node per screen that needs it (battle shell, atlas): both scenes are never
# alive together, and each connects to the signals it cares about
# (CONTRACT(touch-input)).
#
# Zero idle cost: on a non-touch run _input is disabled in _ready(), and the
# node draws nothing.

var _touches: Dictionary = {} # finger index -> viewport position
var _last_dist: float = 0.0
var _last_mid: Vector2 = Vector2.ZERO

func _ready() -> void:
	if GameManager == null or not GameManager.is_touch_ui():
		set_process_input(false)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)

func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
	if _touches.size() >= 2:
		GameManager.touch_gesture_multi = true
		_anchor_gesture()
	elif _touches.is_empty():
		# Every finger is up: a later single tap may place/dig again.
		GameManager.touch_gesture_multi = false
		_last_dist = 0.0
	else:
		# One finger left after a pinch: stop emitting until a new pair forms.
		_last_dist = 0.0

func _on_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _touches.size() < 2:
		return
	var pair := _first_two()
	var a: Vector2 = pair[0]
	var b: Vector2 = pair[1]
	var dist := a.distance_to(b)
	var mid := (a + b) * 0.5
	if _last_dist > 0.0:
		var factor := dist / _last_dist
		if absf(factor - 1.0) > 0.002:
			EventBus.touch_pinch.emit(factor)
		var delta := mid - _last_mid
		if delta.length_squared() > 0.25:
			EventBus.touch_drag.emit(delta)
	_last_dist = dist
	_last_mid = mid

## Index order is not guaranteed: sort so the pair is stable while fingers move.
func _first_two() -> Array:
	var ids: Array = _touches.keys()
	ids.sort()
	return [_touches[ids[0]], _touches[ids[1]]]

func _anchor_gesture() -> void:
	var pair := _first_two()
	var a: Vector2 = pair[0]
	var b: Vector2 = pair[1]
	_last_dist = a.distance_to(b)
	_last_mid = (a + b) * 0.5

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touches.clear()
		_last_dist = 0.0
		if GameManager != null:
			GameManager.touch_gesture_multi = false
