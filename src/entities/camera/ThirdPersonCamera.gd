extends Node3D

# Third-person diorama camera with smooth follow, spring arm, and cozy tilt angle.
# Left-click + drag pans the camera view across the diorama ground (when not placing plants).
# Right-click + drag orbits the view angle; mouse wheel zooms the spring arm.
# Middle-click + drag also pans the camera view at all times.
# Pan bounds and the home position (over the pearl) come from the loaded map
# (EventBus.map_loaded); pan_bounds is the fallback until one loads.

@export var target_path: NodePath
@export var follow_speed: float = 7.0
@export var arm_length: float = 18.0
@export var pitch_degrees: float = -20.0
@export var yaw_degrees: float = -12.0
@export var target_offset: Vector3 = Vector3(0, 1.4, 0)

@export_group("Pan & Drag")
@export var pan_sensitivity: float = 0.85
@export var pan_bounds: Rect2 = Rect2(-34.0, -34.0, 68.0, 68.0) # world XZ
@export var drag_threshold_pixels: float = 5.0

@export_group("Mouse Orbit & Zoom")
@export var orbit_sensitivity: float = 0.38
@export var min_pitch_degrees: float = -85.0
@export var max_pitch_degrees: float = -8.0
@export var zoom_step: float = 3.0
@export var min_arm_length: float = 8.0
@export var max_arm_length: float = 140.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var target: Node3D = null
var _orbiting: bool = false
var _panning: bool = false
var _left_mouse_down: bool = false
var _left_mouse_down_pos: Vector2 = Vector2.ZERO
var _middle_mouse_down: bool = false

var _target_yaw: float = -12.0
var _target_pitch: float = -20.0
var _target_arm_length: float = 18.0

func _ready() -> void:
	if not target_path.is_empty():
		target = get_node_or_null(target_path)

	_target_yaw = yaw_degrees
	_target_pitch = pitch_degrees
	_target_arm_length = arm_length

	spring_arm.spring_length = arm_length
	rotation_degrees.x = pitch_degrees
	rotation_degrees.y = yaw_degrees

	if is_instance_valid(target):
		global_position = target.global_position + target_offset

	# When player selects a plant, immediately reset any left drag state
	if EventBus:
		EventBus.plant_selected_for_placement.connect(func(_type, _player_id):
			_reset_left_drag()
		)
		EventBus.plant_placed.connect(func(_type, _coord, _player_id):
			_reset_left_drag()
		)
		EventBus.placement_cancelled.connect(func(_player_id):
			_reset_left_drag()
		)
		EventBus.shovel_mode_changed.connect(func(_active, _player_id):
			_reset_left_drag()
		)
		EventBus.map_loaded.connect(_on_map_loaded)
		EventBus.touch_pinch.connect(_on_touch_pinch)
		EventBus.touch_drag.connect(_on_touch_drag)

func _on_map_loaded(map: MapDefinition) -> void:
	pan_bounds = map.camera_bounds
	if not is_instance_valid(target):
		global_position.x = map.pearl_position.x
		global_position.z = map.pearl_position.z

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _orbiting:
			_orbiting = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_reset_left_drag()

func _reset_left_drag() -> void:
	_left_mouse_down = false
	_panning = false

func set_target(new_target: Node3D) -> void:
	target = new_target
	if is_instance_valid(target):
		global_position = target.global_position + target_offset

func _process(delta: float) -> void:
	# Smooth follow target position aligned with render frame
	if is_instance_valid(target) and not _panning:
		var target_pos = target.global_position + target_offset
		if global_position.distance_squared_to(target_pos) >= 0.0001:
			global_position = global_position.lerp(target_pos, follow_speed * delta)

	# Exponential smoothing for camera orbit: eliminates mouse packet jitter and sleep stutter
	if absf(rotation_degrees.y - _target_yaw) > 0.001 or absf(rotation_degrees.x - _target_pitch) > 0.001:
		var rot_weight: float = clampf(1.0 - exp(-38.0 * delta), 0.0, 1.0)
		yaw_degrees = lerp(yaw_degrees, _target_yaw, rot_weight)
		pitch_degrees = lerp(pitch_degrees, _target_pitch, rot_weight)
		rotation_degrees.x = pitch_degrees
		rotation_degrees.y = yaw_degrees

	# Smooth spring arm zoom
	if absf(spring_arm.spring_length - _target_arm_length) > 0.01:
		var zoom_weight: float = clampf(1.0 - exp(-22.0 * delta), 0.0, 1.0)
		spring_arm.spring_length = lerp(spring_arm.spring_length, _target_arm_length, zoom_weight)

func _unhandled_input(event: InputEvent) -> void:
	# While a plant is selected for placement, Left-Click strictly belongs to PlacementManager for planting.
	# While the temporary enemy debug spawner is active, Left-Click belongs to it instead.
	# While the shovel is equipped, Left-Click belongs to ShovelManager (release-click, so pans still work).
	var local_id: int = GameManager.local_player_id() if GameManager else 0
	var is_placing_plant: bool = GameManager and (not GameManager.selected_plant_for(local_id).is_empty() or GameManager.is_enemy_spawn_mode or GameManager.is_shovel_for(local_id))

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_placing_plant:
				_reset_left_drag()
				return
			
			if event.pressed:
				_left_mouse_down = true
				_left_mouse_down_pos = event.position
				_panning = false
			else:
				_reset_left_drag()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_mouse_down = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _orbiting else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(zoom_step)
	elif event is InputEventMouseMotion:
		if _orbiting:
			_target_yaw -= event.relative.x * orbit_sensitivity
			_target_pitch = clampf(_target_pitch - event.relative.y * orbit_sensitivity, min_pitch_degrees, max_pitch_degrees)
		elif _left_mouse_down:
			if is_placing_plant:
				_reset_left_drag()
				return
			
			if not _panning and event.position.distance_to(_left_mouse_down_pos) >= drag_threshold_pixels:
				_panning = true
			
			if _panning:
				_pan(event.relative)
		elif _middle_mouse_down:
			_pan(event.relative)

## Touch: fingers spread (factor > 1) zoom in, pinch together zoom out.
## Multiplicative so the step feels the same at every arm length.
func _on_touch_pinch(factor: float) -> void:
	if factor <= 0.0:
		return
	_target_arm_length = clampf(_target_arm_length / factor, min_arm_length, max_arm_length)
	arm_length = _target_arm_length

## Touch: two-finger drag orbits the view, mirroring right-drag on desktop.
func _on_touch_drag(delta: Vector2) -> void:
	_target_yaw -= delta.x * orbit_sensitivity
	_target_pitch = clampf(_target_pitch - delta.y * orbit_sensitivity, min_pitch_degrees, max_pitch_degrees)

func _pan(relative: Vector2) -> void:
	if not is_instance_valid(camera):
		return
	
	# Compute ground plane orientation vectors from camera basis
	var cam_transform = camera.global_transform
	var cam_right = cam_transform.basis.x
	cam_right.y = 0.0
	if cam_right.length_squared() > 0.001:
		cam_right = cam_right.normalized()
	else:
		cam_right = Vector3.RIGHT
	
	var cam_forward = -cam_transform.basis.z
	cam_forward.y = 0.0
	if cam_forward.length_squared() > 0.001:
		cam_forward = cam_forward.normalized()
	else:
		cam_forward = Vector3.FORWARD
	
	# Scale pan speed with zoom level (arm length) so movement feels 1:1 with ground
	var scale_factor: float = (arm_length / 450.0) * pan_sensitivity
	
	# Grab-to-drag direction: dragging right pulls ground right (camera moves left)
	# Dragging down pulls ground towards camera (camera moves forward)
	var move_offset = (-cam_right * relative.x + cam_forward * relative.y) * scale_factor
	
	global_position += move_offset
	global_position.x = clampf(global_position.x, pan_bounds.position.x, pan_bounds.end.x)
	global_position.z = clampf(global_position.z, pan_bounds.position.y, pan_bounds.end.y)

func _zoom(delta_length: float) -> void:
	_target_arm_length = clampf(_target_arm_length + delta_length, min_arm_length, max_arm_length)
	arm_length = _target_arm_length

