class_name PlacementManager
extends Node3D

# Manages 3D diorama plant placement around the Sacred Dragon Pearl.
# Raycasts a screen position from the camera against Ground (Collision Layer 1),
# snaps coordinates to a 2m x 2m grid, displays a glowing holographic preview
# ghost, displays a batched dynamic glowing lawn grid (1 draw call MultiMesh),
# and spawns the plant when its owner commits a valid, affordable tile.
#
# LAN co-op: every device has exactly one local session (`p1`, whose player_id
# is GameManager.local_player_id()). Occupancy, sun and the lawn overlay are
# shared state replicated by the host. The guest's commit is a command: it
# spends nothing locally and spawns nothing; the host validates, spends, spawns
# and its plant_placed event drives spawn_plant() on the guest (CONTRACT(lan-coop)).
#
# Each device also shows its partner's uncommitted ghost: the local session emits
# EventBus.placement_preview_changed whenever its ghost changes tile, facing,
# validity or seed (never per frame), NetBridge relays it, and the other device
# draws it with show_partner_preview() in the partner's colours. That ghost is
# visual only: it never touches occupancy, sun or input.

## One player's placement session. Everything here is per player; grid
## occupancy and the lawn overlay are not.
class Session extends RefCounted:
	var player_id: int = 0
	var is_placing: bool = false
	var plant_type: String = ""
	var grid_coord: Vector2i = Vector2i(-999, -999)
	var snapped_pos: Vector3 = Vector3.ZERO
	var valid: bool = false
	var last_visual_valid: int = -1 # -1 uninitialized, 0 invalid, 1 valid
	var rot_step: int = 0 # 0 to 7 (45 deg increments)
	var rotation_y: float = 0.0
	var last_auto_coord: Vector2i = Vector2i(-999, -999)
	var last_hovered_instance_id: int = -1
	var rotate_tween: Tween = null
	var ghost_root: Node3D
	var ring_mesh: MeshInstance3D
	var ring_mat: StandardMaterial3D
	var arrow_mesh: MeshInstance3D
	var ghost_model: Node3D
	var range_root: Node3D
	var range_mats: Array[StandardMaterial3D] = []
	var range_base_alphas: Array[float] = []

	func _init(id: int = 0) -> void:
		player_id = id

@export var tile_size: float = 2.0
@export var ground_collision_mask: int = 1 # Collision Layer 1: Ground

@export var plants_container_path: NodePath = ^"../Plants"

## This device's placement session. Its player_id is the local slot (0 host,
## 1 guest) so every signal it emits is attributed correctly.
var p1 := Session.new(0)
## The other device's ghost (LAN co-op), built on its first preview; null solo.
var _partner: Session = null
## What p1's ghost last told the partner: [plant_type, coord, rot_step, valid].
var _published_preview: Array = ["", Vector2i(-999, -999), 0, false]
var _ray_query: PhysicsRayQueryParameters3D

# P1 compatibility surface: the rest of the project (screenshot presets, tests)
## reads these names. They are views onto p1.
var is_placing: bool:
	get:
		return p1.is_placing
	set(value):
		p1.is_placing = value
var selected_plant_type: String:
	get:
		return p1.plant_type
	set(value):
		p1.plant_type = value
var current_grid_coord: Vector2i:
	get:
		return p1.grid_coord
	set(value):
		p1.grid_coord = value
var current_snapped_pos: Vector3:
	get:
		return p1.snapped_pos
	set(value):
		p1.snapped_pos = value
var is_current_valid: bool:
	get:
		return p1.valid
	set(value):
		p1.valid = value
var ghost_root: Node3D:
	get:
		return p1.ghost_root
	set(value):
		p1.ghost_root = value

var occupied_tiles: Dictionary = {}
## grid_coord -> placed plant node, on both peers. Lets NetBridge resolve a
## replicated HP change or death without scanning the tree.
var plants_by_coord: Dictionary = {}
# Dynamic Glowing Lawn Grid Overlay (Batched MultiMeshInstance3D - 1 Draw Call)
var grid_multimesh_instance: MultiMeshInstance3D
var grid_multimesh: MultiMesh
var grid_mat: ShaderMaterial
var coord_to_instance_id: Dictionary = {}
var valid_grid_coords: Array[Vector2i] = []
var _grid_fade_tween: Tween = null

## The session that owns `player_id`. Every device drives its own local slot.
func session_for(player_id: int) -> Session:
	p1.player_id = player_id
	return p1

# Pearl dais footprint bounds (SacredDragonPearl centered at 0, 0, 0)
# Placement ghost look: keep the plant's own colors, solid + self-lit so it reads at night.
const GHOST_ALPHA: float = 0.8
const GHOST_GLOW: float = 0.3
# Valid = soft magenta glow: contrasts the green grid and the yellow hover tile (NOT green/
# yellow/red, which the tile overlay uses). Blocked = red.
const GHOST_VALID_TINT := Color(0.95, 0.6, 1.0)
const ARROW_COLOR := Color(0.35, 0.9, 1.0, 1.0)
const GHOST_INVALID_TINT := Color(1.0, 0.35, 0.35)

# Pearl dais footprint half extent around the pearl position (dais model size).
const PEARL_FOOTPRINT_HALF: float = 3.7

# Attack-range preview: the plant's unit JSON "range_indicator" names which of its
# own "numbers" to draw, so the preview can never drift from the combat values.
#   {"shape": "cone", "radius": <key>, "half_angle_deg": <key>}  - turret vision cone
#   {"shape": "rings", "outer": <key>, "inner": <key>}           - two concentric discs
# No "range_indicator" (no attack): no preview.
const RANGE_CONE_ALPHA: float = 0.18
const RANGE_FUSE_ALPHA: float = 0.24
const RANGE_BLAST_ALPHA: float = 0.12
const RANGE_CONE_SEGMENTS: int = 24
const RANGE_DISC_SEGMENTS: int = 40

# Placeable lawn (world XZ rect) + pearl + ground height come from the loaded
# map (EventBus.map_loaded); a level may pick another lawn zone of that map.
# Plants can be placed on ANY tile of the lawn outside the pearl dais footprint.
var _lawn := Rect2(-24.0, -24.0, 48.0, 48.0)
var _pearl_xz := Vector2.ZERO
var _ground_y: float = 0.0
var _map: MapDefinition = null

func _ready() -> void:
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collision_mask = ground_collision_mask
	p1.player_id = GameManager.local_player_id()
	_create_ghost_preview(p1)
	_init_grid_overlay()
	
	if EventBus:
		EventBus.plant_selected_for_placement.connect(_on_plant_selected)
		EventBus.placement_cancelled.connect(_on_placement_cancelled)
		EventBus.plant_placed.connect(_on_plant_placed)
		EventBus.plant_died.connect(_on_plant_died)
		EventBus.map_loaded.connect(_on_map_loaded)
		EventBus.level_selected.connect(_on_level_selected)
		EventBus.placement_rotate_pressed.connect(_on_rotate_pressed)

## New map: the shell cleared Plants, so every tile is free again. The lawn is
## the current level's zone when that level plays on this map, else the default.
func _on_map_loaded(map: MapDefinition) -> void:
	_map = map
	_pearl_xz = Vector2(map.pearl_position.x, map.pearl_position.z)
	_ground_y = map.ground_y
	occupied_tiles.clear()
	plants_by_coord.clear()
	var zone := ""
	if GameManager.level_active and LevelDB.resolve_map(GameManager.current_level_id) == map.map_id:
		zone = str(LevelDB.get_level(GameManager.current_level_id).get("lawn", ""))
	_lawn = map.lawn_rect(zone)
	_populate_grid()

## A level may place its lawn in another zone of its map ("lawn" field). A level
## on a different map waits for that map's map_loaded instead.
func _on_level_selected(_world_id: String, level_id: String) -> void:
	if _map == null or LevelDB.resolve_map(level_id) != _map.map_id:
		return
	var rect := _map.lawn_rect(str(LevelDB.get_level(level_id).get("lawn", "")))
	if rect != _lawn:
		_lawn = rect
		_populate_grid()

func _process(_delta: float) -> void:
	if p1.is_placing:
		_update_raycast_hover(p1, get_viewport().get_mouse_position())

func _unhandled_input(event: InputEvent) -> void:
	if not p1.is_placing:
		return
	
	if event is InputEventMouseButton:
		# Touch: the press aims (the hover follows the finger), the release
		# plants. Re-hover at the release point first — _process may not have
		# run since the last drag, which would plant a tile behind the finger.
		# A pinch/orbit sets touch_gesture_multi, so it never plants.
		if event.button_index == MOUSE_BUTTON_LEFT and GameManager and GameManager.is_touch_ui():
			if not event.pressed and not GameManager.touch_gesture_multi:
				_update_raycast_hover(p1, event.position)
				if p1.valid:
					_execute_placement(p1)
					get_viewport().set_input_as_handled()
		# Mouse: confirm placement immediately on click.
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if p1.valid:
				_execute_placement(p1)
				get_viewport().set_input_as_handled()
		# Right-Click: cancel placement
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_placement(p1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_cancel_placement(p1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_R:
				if event.shift_pressed:
					_rotate_placement(p1, -1) # Counter-clockwise
				else:
					_rotate_placement(p1, 1)  # Clockwise
				get_viewport().set_input_as_handled()

## On-screen rotate buttons (touch HUD). Same path as R; the player_id guard
## keeps another device's signal from moving this device's ghost.
func _on_rotate_pressed(direction: int, player_id: int) -> void:
	if player_id != p1.player_id:
		return
	if p1.is_placing:
		_rotate_placement(p1, direction)

const ROTATION_ANGLES: PackedFloat32Array = [
	0.0,
	-0.7853982, # -45 deg (South-West)
	-1.5707963, # -90 deg (West)
	-2.3561945, # -135 deg (North-West)
	-3.1415927, # -180 deg (North)
	-3.9269908, # -225 deg (North-East)
	-4.712389,  # -270 deg (East)
	-5.497787   # -315 deg (South-East)
]
## Nearest 45° snap step (into ROTATION_ANGLES) facing radially AWAY from
## the pearl at origin, so freshly placed plants meet incoming ghosts
## head-on instead of defaulting to +Z. Static + allocation-free so it is
## unit-testable; callers invoke it at most once per hovered-tile change.
static func snap_outward_step(tile_pos: Vector3) -> int:
	if Vector2(tile_pos.x, tile_pos.z).length_squared() < 0.0001:
		return 0
	var yaw: float = atan2(tile_pos.x, tile_pos.z) # +Z-facing convention
	return posmod(int(round(-yaw / (PI / 4.0))), 8)

## Point the ghost preview (and pending placement rotation) outward from the
## pearl for the currently hovered tile. Manual R adjustments survive until
## the cursor moves to another tile, which re-autos from the new direction.
func _auto_face_outward(s: Session) -> void:
	if s.grid_coord == s.last_auto_coord:
		return
	s.last_auto_coord = s.grid_coord
	s.rot_step = snap_outward_step(s.snapped_pos)
	s.rotation_y = ROTATION_ANGLES[s.rot_step]
	if is_instance_valid(s.ghost_root):
		s.ghost_root.rotation.y = s.rotation_y

func _rotate_placement(s: Session, dir: int) -> void:
	# dir = 1: Clockwise (+45 deg), dir = -1: Counter-clockwise (-45 deg)
	s.rot_step = (s.rot_step + dir) & 7
	s.rotation_y = ROTATION_ANGLES[s.rot_step]

	if is_instance_valid(s.ghost_root):
		s.ghost_root.rotation.y = s.rotation_y

		# Snappy tactile punch bounce feedback with tween cancellation to prevent leak
		if s.rotate_tween and s.rotate_tween.is_valid():
			s.rotate_tween.kill()
		s.rotate_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		s.ghost_root.scale = Vector3(1.12, 1.12, 1.12)
		s.rotate_tween.tween_property(s.ghost_root, "scale", Vector3.ONE, 0.12)

	print("[PlacementManager] P%d rotated plant to step %d (%.1f deg)" % [s.player_id + 1, s.rot_step, rad_to_deg(s.rotation_y)])
	_publish_preview(s)

func _on_plant_selected(plant_type: String, player_id: int) -> void:
	if player_id != p1.player_id:
		return # another player's pick never drives this device's ghost
	print("[PlacementManager] P", player_id + 1, " selected plant: ", plant_type)
	var s := p1
	s.plant_type = plant_type
	s.is_placing = true
	s.last_visual_valid = -1
	s.last_auto_coord = Vector2i(-999, -999)
	s.rot_step = 0
	s.rotation_y = 0.0
	if is_instance_valid(s.ghost_root):
		s.ghost_root.rotation.y = 0.0
		s.ghost_root.scale = Vector3.ONE
		s.ghost_root.visible = false
	_update_ghost_model(s, plant_type)
	_show_grid_overlay()

func _on_placement_cancelled(player_id: int) -> void:
	if player_id != p1.player_id:
		return
	_cancel_placement(p1)

func _on_plant_placed(_plant_type: String, grid_coord: Vector2i, _player_id: int) -> void:
	occupied_tiles[grid_coord] = true
	var id = coord_to_instance_id.get(grid_coord, -1)
	if id != -1 and grid_multimesh:
		grid_multimesh.set_instance_color(id, Color(0.95, 0.25, 0.20, 0.70))

func _on_plant_died(grid_coord: Vector2i) -> void:
	# Eaten plant frees its tile for re-planting.
	occupied_tiles.erase(grid_coord)
	plants_by_coord.erase(grid_coord)
	var id = coord_to_instance_id.get(grid_coord, -1)
	if id != -1 and grid_multimesh:
		grid_multimesh.set_instance_color(id, Color(0.20, 0.86, 0.45, 0.85))

func _cancel_placement(s: Session) -> void:
	s.is_placing = false
	s.plant_type = ""
	s.valid = false
	s.last_visual_valid = -1
	s.last_auto_coord = Vector2i(-999, -999)
	s.rot_step = 0
	s.rotation_y = 0.0
	if is_instance_valid(s.ghost_root):
		s.ghost_root.rotation.y = 0.0
		s.ghost_root.scale = Vector3.ONE
		s.ghost_root.visible = false
	_clear_range_indicator(s)
	if GameManager:
		if s.player_id == 1:
			GameManager.p2_selected_plant_to_place = ""
		else:
			GameManager.selected_plant_to_place = ""
	_set_tile_hovered(s, Vector2i(-999, -999), false)
	_publish_preview(s)
	if not p1.is_placing:
		_hide_grid_overlay()

func _update_raycast_hover(s: Session, screen_pos: Vector2) -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var ray_end = ray_origin + ray_dir * 180.0
	
	var space_state = get_world_3d().direct_space_state
	_ray_query.from = ray_origin
	_ray_query.to = ray_end
	var result = space_state.intersect_ray(_ray_query)
	
	if result and result.has("position"):
		var hit_pos: Vector3 = result.position
		
		# Snap to 2m grid
		var gx = int(round(hit_pos.x / tile_size))
		var gz = int(round(hit_pos.z / tile_size))
		s.grid_coord = Vector2i(gx, gz)
		# The pearl's collision box shares the ground layer: a ray landing on its top or
		# side edge would snap to the next tile (outside the footprint) at the box's
		# height. Treat such a hit as "on the pearl": ground height, never placeable.
		var on_pearl: bool = result.collider is Node and (result.collider as Node).is_in_group("CentralHouse")
		var snap_y: float = hit_pos.y + 0.02
		if on_pearl:
			var wx: float = gx * tile_size
			var wz: float = gz * tile_size
			snap_y = (_map.ground_y_at(wx, wz) if _map != null else _ground_y) + 0.02
		s.snapped_pos = Vector3(gx * tile_size, snap_y, gz * tile_size)
		_auto_face_outward(s)

		s.valid = not on_pearl and _check_placement_validity(s, s.snapped_pos, s.grid_coord)
		
		# Update hovered grid tile highlight
		_set_tile_hovered(s, s.grid_coord, s.valid)
		
		# Update ghost position and visual indicator
		if is_instance_valid(s.ghost_root):
			s.ghost_root.visible = true
			s.ghost_root.global_position = s.snapped_pos
			var valid_state = 1 if s.valid else 0
			if s.last_visual_valid != valid_state:
				s.last_visual_valid = valid_state
				_update_ghost_visuals(s, s.valid)
		
		EventBus.tile_hovered.emit(s.grid_coord, s.snapped_pos, s.valid, s.player_id)
	else:
		if is_instance_valid(s.ghost_root):
			s.ghost_root.visible = false
		s.valid = false
		_set_tile_hovered(s, Vector2i(-999, -999), false)
	_publish_preview(s)

## Tell the partner device what this device's ghost shows. Compared against the
## last message, so a resting cursor sends nothing and solo play emits only on
## real changes (nobody listens offline).
func _publish_preview(s: Session) -> void:
	var shown := s.is_placing and is_instance_valid(s.ghost_root) and s.ghost_root.visible
	var key: Array = [s.plant_type, s.grid_coord, s.rot_step, s.valid] if shown \
		else ["", Vector2i(-999, -999), 0, false]
	if key == _published_preview:
		return
	_published_preview = key
	EventBus.placement_preview_changed.emit(str(key[0]), key[1], int(key[2]), bool(key[3]), s.player_id)

## Draw (or, with an empty plant_type, hide) the partner device's placement ghost
## at its tile and facing, tinted in its owner's colours. NetBridge calls this for
## the partner's placement_preview_changed; nothing else reads the partner session.
func show_partner_preview(plant_type: String, grid_coord: Vector2i, rot_step: int, valid: bool, player_id: int) -> void:
	if plant_type.is_empty():
		if _partner != null:
			_partner.is_placing = false
			_partner.plant_type = ""
			if is_instance_valid(_partner.ghost_root):
				_partner.ghost_root.visible = false
			_set_tile_hovered(_partner, Vector2i(-999, -999), false)
		return
	if _partner == null:
		_partner = Session.new(player_id)
		_create_ghost_preview(_partner)
		_partner.ghost_root.name = "PartnerGhostPreview"
	var s := _partner
	if s.plant_type != plant_type:
		s.plant_type = plant_type
		s.last_visual_valid = -1
		_update_ghost_model(s, plant_type)
	s.is_placing = true
	s.grid_coord = grid_coord
	s.snapped_pos = position_for_tile(grid_coord)
	s.rot_step = rot_step & 7
	s.rotation_y = ROTATION_ANGLES[s.rot_step]
	s.valid = valid
	s.ghost_root.global_position = s.snapped_pos
	s.ghost_root.rotation.y = s.rotation_y
	s.ghost_root.visible = true
	var valid_state := 1 if valid else 0
	if s.last_visual_valid != valid_state:
		s.last_visual_valid = valid_state
		_update_ghost_visuals(s, valid)
	_set_tile_hovered(s, grid_coord, valid)

## What this device's ghost last told the partner: [plant_type, coord, rot_step,
## valid]; NetBridge re-sends it to a guest that finishes loading late.
func published_preview() -> Array:
	return _published_preview

## The partner's ghost root while it is shown, else null (LanFlowTest reads it).
func partner_preview() -> Node3D:
	if _partner == null or not _partner.is_placing or not is_instance_valid(_partner.ghost_root):
		return null
	return _partner.ghost_root

func _check_placement_validity(s: Session, pos: Vector3, coord: Vector2i) -> bool:
	# 1. Must be inside the placeable square around the pearl
	if not _is_in_placeable_square(pos):
		return false

	# 2. Must not be inside the pearl dais footprint
	if _in_pearl_footprint(pos):
		return false

	# 3. Must not already be occupied
	if occupied_tiles.has(coord):
		return false

	# 4. Player must have enough Sun / Gems
	if GameManager and not GameManager.can_afford(s.plant_type):
		return false

	return true

## Shared predicate: is this world position inside the placeable square?
## Used by both placement validity and grid overlay generation so the
## glowing tiles always match exactly where plants may go.
func _is_in_placeable_square(pos: Vector3) -> bool:
	return pos.x >= _lawn.position.x and pos.x <= _lawn.end.x \
		and pos.z >= _lawn.position.y and pos.z <= _lawn.end.y

func _in_pearl_footprint(pos: Vector3) -> bool:
	return absf(pos.x - _pearl_xz.x) < PEARL_FOOTPRINT_HALF and absf(pos.z - _pearl_xz.y) < PEARL_FOOTPRINT_HALF

## Commit the hovered tile. Re-validates here instead of trusting the cached
## `s.valid`: a replicated placement or a Sun change can land in the same frame,
## which would place two plants on one tile and debit twice.
##
## Guest: sends the command and spends nothing. The host re-validates, spends,
## spawns and broadcasts, so a guest can never mint plants or Sun.
func _execute_placement(s: Session) -> void:
	if occupied_tiles.has(s.grid_coord):
		return
	if not _is_in_placeable_square(s.snapped_pos) or _in_pearl_footprint(s.snapped_pos):
		return
	if GameManager and (not GameManager.can_afford(s.plant_type) or GameManager.is_seed_cooling(s.plant_type)):
		return
	if GameManager and GameManager.is_client():
		Net.send_command({
			"t": "place", "plant": s.plant_type,
			"x": s.grid_coord.x, "z": s.grid_coord.y,
			"px": s.snapped_pos.x, "py": s.snapped_pos.y, "pz": s.snapped_pos.z,
			"rot": s.rotation_y})
		_cancel_placement(s)
		return
	var cost = GameManager.plant_cost(s.plant_type) if GameManager else 100
	if GameManager:
		if not GameManager.spend_sun(cost):
			print("Placement aborted: not enough Sun!")
			return
	spawn_plant(s.plant_type, s.grid_coord, s.snapped_pos, s.rotation_y, s.player_id)
	_cancel_placement(s)

## The one instantiation path, shared by a local commit and a replicated one.
## Occupancy, the lawn grid colour and `plant_placed` update here so both peers
## end up with the same lawn and the same tile map.
func spawn_plant(plant_type: String, grid_coord: Vector2i, pos: Vector3, rotation_y: float, player_id: int) -> Node3D:
	var scene: PackedScene = BalanceDB.unit_scene(plant_type)
	if scene == null:
		return null
	var plant = scene.instantiate() as Node3D
	plant.rotation.y = rotation_y
	if plant is PlantBase:
		plant.grid_coord = grid_coord
		plant.base_rotation_y = rotation_y
	plant.set_meta("owner_id", player_id)
	var container = get_node_or_null(plants_container_path)
	if container:
		container.add_child(plant)
	else:
		get_parent().add_child(plant)
	# After add_child: a rootless Node3D rejects global_position, which used to
	# log "!is_inside_tree()" and leave the plant at the origin.
	plant.global_position = pos
	occupied_tiles[grid_coord] = true
	plants_by_coord[grid_coord] = plant
	var id = coord_to_instance_id.get(grid_coord, -1)
	if id != -1 and grid_multimesh:
		grid_multimesh.set_instance_color(id, Color(0.95, 0.25, 0.20, 0.70))
	EventBus.plant_placed.emit(plant_type, grid_coord, player_id)
	Audio.play(Audio.PLANT_PLACE)
	print("✓ Plant placed: ", plant_type, " at ", pos, " (grid ", grid_coord, ")")
	return plant

## The placed plant owning a grid tile, or null. Replicated HP/death resolve here.
func plant_at(grid_coord: Vector2i) -> Node3D:
	var plant = plants_by_coord.get(grid_coord)
	return plant if is_instance_valid(plant) else null

## Guest full sync: drop every replicated plant and repaint the lawn overlay.
## The host owns occupancy, so this fires no plant_died and no refund.
func clear_replicated_plants() -> void:
	for plant in plants_by_coord.values():
		if is_instance_valid(plant):
			plant.queue_free()
	plants_by_coord.clear()
	occupied_tiles.clear()
	_refresh_grid_colors()

## Host-side gate for a replicated placement (CONTRACT(lan-coop)): the guest
## names a grid tile, never a world position, so it cannot plant off the lawn.
## `valid_grid_coords` is the same lawn/pearl test the hover ghost uses.
func remote_placement_allowed(plant_type: String, grid_coord: Vector2i) -> bool:
	if plant_type.is_empty() or not valid_grid_coords.has(grid_coord):
		return false
	if occupied_tiles.has(grid_coord):
		return false
	if GameManager == null or not GameManager.seed_loadout.has(plant_type):
		return false
	return GameManager.can_afford(plant_type) and not GameManager.is_seed_cooling(plant_type)

## The world position for a grid tile, identical to the hover snap.
func position_for_tile(grid_coord: Vector2i) -> Vector3:
	var wx: float = float(grid_coord.x) * tile_size
	var wz: float = float(grid_coord.y) * tile_size
	var y: float = (_map.ground_y_at(wx, wz) if _map != null else _ground_y) + 0.02
	return Vector3(wx, y, wz)

# ========================================================
# DYNAMIC GLOWING LAWN GRID OVERLAY (MultiMeshInstance3D)
# ========================================================

func _init_grid_overlay() -> void:
	grid_multimesh_instance = MultiMeshInstance3D.new()
	grid_multimesh_instance.name = "LawnGridOverlay"
	grid_multimesh_instance.visible = false
	add_child(grid_multimesh_instance)
	
	grid_mat = ShaderMaterial.new()
	var shader = load("res://assets/shaders/LawnGridOverlay.gdshader")
	grid_mat.shader = shader
	grid_mat.render_priority = 10
	grid_mat.set_shader_parameter("grid_opacity", 1.0)
	grid_multimesh_instance.material_override = grid_mat
	grid_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	grid_multimesh = MultiMesh.new()
	grid_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	grid_multimesh.use_colors = true
	
	var tile_mesh = PlaneMesh.new()
	tile_mesh.size = Vector2(1.88, 1.88)
	grid_multimesh.mesh = tile_mesh
	# Tiles are placed once the map arrives (_on_map_loaded -> _populate_grid).

## Tile instances for the current lawn rect (rebuilt when the map or lawn zone changes).
func _populate_grid() -> void:
	if grid_multimesh == null:
		return
	var min_gx = int(floor(_lawn.position.x / tile_size))
	var max_gx = int(ceil(_lawn.end.x / tile_size))
	var min_gz = int(floor(_lawn.position.y / tile_size))
	var max_gz = int(ceil(_lawn.end.y / tile_size))

	valid_grid_coords.clear()
	coord_to_instance_id.clear()
	p1.last_hovered_instance_id = -1
	if _partner != null:
		_partner.last_hovered_instance_id = -1

	for gx in range(min_gx, max_gx + 1):
		for gz in range(min_gz, max_gz + 1):
			var coord = Vector2i(gx, gz)
			var pos = Vector3(gx * tile_size, 0.0, gz * tile_size)
			# Only tiles inside the placeable square (matches validity check)
			if not _is_in_placeable_square(pos):
				continue
			# Exclude pearl dais footprint
			if _in_pearl_footprint(pos):
				continue
			
			var idx = valid_grid_coords.size()
			valid_grid_coords.append(coord)
			coord_to_instance_id[coord] = idx
			
	grid_multimesh.instance_count = valid_grid_coords.size()
	
	var tile_y: float = _ground_y + 0.06 # sits just above the 0.05 lawn surface
	print("[PlacementManager] Initializing LawnGridOverlay with ", valid_grid_coords.size(), " tiles at y = ", tile_y)
	for i in range(valid_grid_coords.size()):
		var coord = valid_grid_coords[i]
		var t = Transform3D(Basis.IDENTITY, Vector3(coord.x * tile_size, tile_y, coord.y * tile_size))
		grid_multimesh.set_instance_transform(i, t)
		grid_multimesh.set_instance_color(i, Color(0.20, 0.86, 0.45, 0.85))
		
	grid_multimesh_instance.multimesh = grid_multimesh

func _show_grid_overlay() -> void:
	print("[PlacementManager] _show_grid_overlay() - instance count: ", grid_multimesh.instance_count if grid_multimesh else 0)
	if not is_instance_valid(grid_multimesh_instance):
		return
	grid_multimesh_instance.visible = true
	_refresh_grid_colors()
	
	if _grid_fade_tween and _grid_fade_tween.is_valid():
		_grid_fade_tween.kill()
		
	if is_instance_valid(grid_mat):
		grid_mat.set_shader_parameter("grid_opacity", 0.0)
		
	_grid_fade_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_grid_fade_tween.tween_method(func(val: float):
		if is_instance_valid(grid_mat):
			grid_mat.set_shader_parameter("grid_opacity", val)
	, 0.0, 1.0, 0.22)

func _hide_grid_overlay() -> void:
	if not is_instance_valid(grid_multimesh_instance):
		return
	if _grid_fade_tween and _grid_fade_tween.is_valid():
		_grid_fade_tween.kill()
		
	_grid_fade_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_grid_fade_tween.tween_method(func(val: float):
		if is_instance_valid(grid_mat):
			grid_mat.set_shader_parameter("grid_opacity", val)
	, 1.0, 0.0, 0.16)
	_grid_fade_tween.tween_callback(func():
		if not p1.is_placing and is_instance_valid(grid_multimesh_instance):
			grid_multimesh_instance.visible = false
	)

func _refresh_grid_colors() -> void:
	p1.last_hovered_instance_id = -1
	for i in range(valid_grid_coords.size()):
		var coord = valid_grid_coords[i]
		if occupied_tiles.has(coord):
			grid_multimesh.set_instance_color(i, Color(0.95, 0.22, 0.22, 0.80))
		else:
			grid_multimesh.set_instance_color(i, Color(0.20, 0.86, 0.45, 0.85))
	# The repaint wiped the partner's tile; put it back while their ghost is up.
	if _partner != null:
		_partner.last_hovered_instance_id = -1
		if _partner.is_placing:
			_set_tile_hovered(_partner, _partner.grid_coord, _partner.valid)

func _set_tile_hovered(s: Session, coord: Vector2i, is_valid: bool) -> void:
	var new_id = coord_to_instance_id.get(coord, -1)
	
	# Restore previous hovered tile
	if s.last_hovered_instance_id != -1 and s.last_hovered_instance_id != new_id:
		var prev_coord = valid_grid_coords[s.last_hovered_instance_id]
		var prev_col = Color(0.95, 0.22, 0.22, 0.80) if occupied_tiles.has(prev_coord) else Color(0.20, 0.86, 0.45, 0.85)
		grid_multimesh.set_instance_color(s.last_hovered_instance_id, prev_col)
		
	if new_id != -1:
		s.last_hovered_instance_id = new_id
		# The guest's hover is cyan, the host's amber, so screenshots and co-op reads match.
		var hover_col := Color(0.35, 0.86, 0.95, 0.95) if s.player_id == 1 else Color(1.0, 0.88, 0.25, 0.95)
		if not is_valid:
			hover_col = Color(0.98, 0.20, 0.20, 0.90)
		grid_multimesh.set_instance_color(new_id, hover_col)
	else:
		s.last_hovered_instance_id = -1

# ========================================================
# GHOST RETICLE & MODEL
# ========================================================

func _create_ghost_preview(s: Session) -> void:
	s.ghost_root = Node3D.new()
	s.ghost_root.name = "PlacementGhostPreview" if s.player_id == 0 else "PlacementGhostPreview2"
	s.ghost_root.visible = false
	add_child(s.ghost_root)
	
	# Circular Ground Indicator Ring
	s.ring_mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 0.98
	torus.rings = 24
	torus.ring_segments = 12
	s.ring_mesh.mesh = torus
	
	s.ring_mat = StandardMaterial3D.new()
	s.ring_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	s.ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# The guest's ring is cyan, the host's emerald (same slots as before LAN co-op).
	s.ring_mat.albedo_color = Color(0.25, 0.85, 0.98, 0.8) if s.player_id == 1 else Color(0.2, 0.95, 0.3, 0.75)
	s.ring_mesh.material_override = s.ring_mat
	s.ring_mesh.position.y = 0.05
	s.ghost_root.add_child(s.ring_mesh)

	# Directional Pointer Chevron (apex points along +Z, rotates with ghost_root)
	s.arrow_mesh = MeshInstance3D.new()
	var prism = PrismMesh.new()
	prism.size = Vector3(0.8, 0.9, 0.08)
	s.arrow_mesh.mesh = prism
	# Own cyan material: distinct from the green/red/yellow grid tiles so facing stays readable.
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.albedo_color = ARROW_COLOR
	arrow_mat.no_depth_test = true
	arrow_mat.render_priority = 2
	s.arrow_mesh.material_override = arrow_mat
	s.arrow_mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	s.arrow_mesh.position = Vector3(0.0, 0.05, 1.14)
	s.ghost_root.add_child(s.arrow_mesh)

func _update_ghost_model(s: Session, plant_type: String) -> void:
	if is_instance_valid(s.ghost_model):
		s.ghost_model.queue_free()
		s.ghost_model = null

	var seed_entry := BalanceDB.seed_entry(plant_type)
	var glb_path := str(seed_entry.get("model", ""))

	if not glb_path.is_empty() and ResourceLoader.exists(glb_path):
		var glb_scene = load(glb_path) as PackedScene
		if glb_scene:
			s.ghost_model = glb_scene.instantiate()
			s.ghost_model.name = "GhostModel"
			var preview_scale: float = float(seed_entry.get("ghost_scale", 2.0))
			s.ghost_model.scale = Vector3(preview_scale, preview_scale, preview_scale)
			# Apply semi-transparency tint
			_make_translucent(s.ghost_model, GHOST_ALPHA)
			s.ghost_root.add_child(s.ghost_model)

	_update_range_indicator(s, plant_type)

## Clone each surface's original material (shared imported ones stay untouched
## for real plants) and make the clone a solid-looking, self-lit hologram: vertex
## colors kept, depth pre-pass so internal faces never show through.
func _make_translucent(node: Node, alpha: float) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			var src = node.get_active_material(i)
			if not src:
				src = node.mesh.surface_get_material(i)
			if not (src is StandardMaterial3D):
				continue
			var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			mat.vertex_color_use_as_albedo = true
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			mat.albedo_color.a = alpha
			mat.emission_enabled = true
			mat.emission = GHOST_VALID_TINT
			mat.emission_energy_multiplier = GHOST_GLOW
			node.set_surface_override_material(i, mat)
	for child in node.get_children():
		_make_translucent(child, alpha)

func _update_ghost_visuals(s: Session, is_valid: bool) -> void:
	# Host reads emerald (valid) / coral (blocked); the guest reads cyan when valid.
	var tint: Color = (Color(0.25, 0.85, 0.98, 0.9) if s.player_id == 1 else Color(0.2, 0.95, 0.35, 0.9)) if is_valid else Color(0.95, 0.25, 0.25, 0.9)
	if is_instance_valid(s.ring_mat):
		s.ring_mat.albedo_color = tint

	if is_instance_valid(s.ghost_model):
		var valid_tint := GHOST_VALID_TINT if s.player_id == 0 else Color(0.45, 0.9, 1.0)
		_apply_ghost_color(s.ghost_model, valid_tint if is_valid else GHOST_INVALID_TINT)

	_apply_range_tint(s, tint)

## Validity is shown by tinting only the emission, so the plant keeps its own colors.
func _apply_ghost_color(node: Node, tint: Color) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			var mat := node.get_surface_override_material(i) as StandardMaterial3D
			if mat:
				mat.emission = tint
	for child in node.get_children():
		_apply_ghost_color(child, tint)

# ========================================================
# ATTACK-RANGE PREVIEW (child of ghost_root: follows facing)
# ========================================================

## Rebuild the range indicator for the selected plant from its unit JSON
## "range_indicator": a vision cone (apex at the plant, opening along +Z so it
## rotates with the ghost) or two concentric discs; none for non-attackers.
func _update_range_indicator(s: Session, plant_type: String) -> void:
	_clear_range_indicator(s)
	if not is_instance_valid(s.ghost_root):
		return
	var spec: Dictionary = BalanceDB.get_unit(plant_type).get("range_indicator", {})
	match str(spec.get("shape", "")):
		"cone":
			s.range_root = Node3D.new()
			s.range_root.name = "RangePreview"
			s.ghost_root.add_child(s.range_root)
			_add_range_mesh(s,
				_build_cone_mesh(_range_num(plant_type, spec, "radius"), _range_num(plant_type, spec, "half_angle_deg"), RANGE_CONE_SEGMENTS),
				Color(0.2, 0.95, 0.35, RANGE_CONE_ALPHA), 0.04)
		"rings":
			s.range_root = Node3D.new()
			s.range_root.name = "RangePreview"
			s.ghost_root.add_child(s.range_root)
			# Outer first (larger, underneath), inner second (smaller, on top).
			_add_range_mesh(s,
				_build_disc_mesh(_range_num(plant_type, spec, "outer"), RANGE_DISC_SEGMENTS),
				Color(0.2, 0.95, 0.35, RANGE_BLAST_ALPHA), 0.03)
			_add_range_mesh(s,
				_build_disc_mesh(_range_num(plant_type, spec, "inner"), RANGE_DISC_SEGMENTS),
				Color(0.2, 0.95, 0.35, RANGE_FUSE_ALPHA), 0.045)

## The plant's numbers.<key> that range_indicator field `field` names.
func _range_num(plant_type: String, spec: Dictionary, field: String) -> float:
	return float(BalanceDB.num(plant_type, str(spec.get(field, "")), 0.0))

func _clear_range_indicator(s: Session) -> void:
	s.range_mats.clear()
	s.range_base_alphas.clear()
	if is_instance_valid(s.range_root):
		s.range_root.queue_free()
	s.range_root = null

func _add_range_mesh(s: Session, mesh: ArrayMesh, color: Color, local_y: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mi.material_override = mat
	mi.position.y = local_y
	s.range_root.add_child(mi)
	s.range_mats.append(mat)
	s.range_base_alphas.append(color.a)

## Retint range discs to match placement validity, preserving per-disc alpha.
func _apply_range_tint(s: Session, tint: Color) -> void:
	for i in range(s.range_mats.size()):
		var mat := s.range_mats[i]
		if is_instance_valid(mat):
			var a: float = s.range_base_alphas[i] if i < s.range_base_alphas.size() else 0.2
			mat.albedo_color = Color(tint.r, tint.g, tint.b, a)

## Flat fan on the XZ plane: apex at origin, opening symmetrically about +Z.
static func _build_cone_mesh(radius: float, half_angle_deg: float, segments: int) -> ArrayMesh:
	var half_rad: float = deg_to_rad(half_angle_deg)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	for i in range(segments + 1):
		var a: float = lerpf(-half_rad, half_rad, float(i) / float(segments))
		verts.append(Vector3(sin(a) * radius, 0.0, cos(a) * radius))
		normals.append(Vector3.UP)
	var indices := PackedInt32Array()
	for i in range(1, segments + 1):
		indices.append_array([0, i, i + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Flat filled disc on the XZ plane, centered at origin.
static func _build_disc_mesh(radius: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	for i in range(segments + 1):
		var a: float = TAU * float(i) / float(segments)
		verts.append(Vector3(sin(a) * radius, 0.0, cos(a) * radius))
		normals.append(Vector3.UP)
	var indices := PackedInt32Array()
	for i in range(1, segments + 1):
		indices.append_array([0, i, i + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
