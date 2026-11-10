extends CharacterBody3D

# Third-person cozy gardener character controller.
# Handles responsive movement, cute procedural walk bounce, and grid interaction.

@export var move_speed: float = 6.5
@export var acceleration: float = 18.0
@export var friction: float = 22.0
@export var rotation_speed: float = 12.0

@onready var visuals: Node3D = $Visuals
@onready var interaction_ray: RayCast3D = $InteractionRay

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var walk_time: float = 0.0
var facing_direction: Vector3 = Vector3.FORWARD
var _last_grid_coord: Vector2i = Vector2i(2147483647, 2147483647)

func _ready() -> void:
	# Add to player group for easy querying if needed
	add_to_group("Player")

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Read directional inputs
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("move_forward"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("move_backward"):
		input_dir.y += 1.0

	# Skip sqrt/div when no keys are held (normalized() of zero is zero anyway).
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()

	# Movement direction in 3D (X = right/left, Z = down/up)
	var move_dir := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		move_dir = Vector3(input_dir.x, 0, input_dir.y).normalized()

	if move_dir.length() > 0.1:
		# Accelerate towards target velocity
		var target_vel = move_dir * move_speed
		velocity.x = move_toward(velocity.x, target_vel.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, acceleration * delta)

		# Face the movement direction
		facing_direction = move_dir
		var target_angle = atan2(move_dir.x, move_dir.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)

		# Procedural cute walking bobbing & tilt
		walk_time += delta * 12.0
		visuals.position.y = sin(walk_time) * 0.06
		visuals.rotation.z = cos(walk_time) * 0.05
	else:
		# Decelerate / Friction
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

		# Return visuals to neutral rest pose
		visuals.position.y = lerp(visuals.position.y, 0.0, 10.0 * delta)
		visuals.rotation.z = lerp(visuals.rotation.z, 0.0, 10.0 * delta)
		walk_time = 0.0

	move_and_slide()
	_update_grid_target()
	_handle_actions()

func _update_grid_target() -> void:
	# Calculate target tile in front of the player
	var target_world_pos = global_position + facing_direction * 1.5
	# Grid tiles are 2x2 units
	var grid_x = int(floor((target_world_pos.x + 1.0) / 2.0))
	var grid_z = int(floor((target_world_pos.z + 1.0) / 2.0))
	var grid_coord = Vector2i(grid_x, grid_z)
	# Standing still spams 60 Hz duplicates; the visualizer only needs changes.
	if grid_coord == _last_grid_coord:
		return
	_last_grid_coord = grid_coord

	var snapped_world_pos = Vector3(grid_x * 2.0, 0.0, grid_z * 2.0)

	# Broadcast hovered tile to EventBus for grid visualizer
	EventBus.tile_hovered.emit(grid_coord, snapped_world_pos, true, 0)

func _handle_actions() -> void:
	if Input.is_action_just_pressed("interact_action"):
		var target_world_pos = global_position + facing_direction * 1.5
		var grid_x = int(floor((target_world_pos.x + 1.0) / 2.0))
		var grid_z = int(floor((target_world_pos.z + 1.0) / 2.0))
		var grid_coord = Vector2i(grid_x, grid_z)
		
		# Request planting at this coordinate
		var plant_to_place = GameManager.selected_plant_to_place
		if plant_to_place != "":
			if GameManager.can_afford(plant_to_place):
				EventBus.plant_placed.emit(plant_to_place, grid_coord, 0)
			else:
				print("Not enough sun for ", plant_to_place)
