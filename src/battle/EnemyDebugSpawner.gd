class_name EnemyDebugSpawner
extends Node3D

# TEMPORARY DEBUG TOOL - TODO REMOVE before wave system lands.
# Click-to-place ghost spawner for the Hungry Ghost:
# Press G to enter spawn mode (translucent ghost preview follows the cursor),
# Left-Click spawns one ghost (free placement, no grid snap, no cost),
# Right-Click / Esc / G exits. Mirrors PlacementManager conventions.

@export var ghost_scene: PackedScene = preload("res://src/entities/enemies/hungry_ghost/HungryGhost.tscn")
@export var ground_collision_mask: int = 1 # Collision Layer 1: Ground
@export var enemies_container_path: NodePath = ^"../Enemies"

# Playable-enemy catalog: BalanceDB.enemies() (every data/units/enemies/<id>.json
# with a "scene"; its "debug" block orders the H-key EnemySelector cards). G+click
# spawns the picked id. Model-only .glb enemies without a scene are not listed.

var selected_enemy_id: String = "hungry_ghost"

# Scene cache: load() hits the resource cache anyway, but this skips even the
# path lookup on rapid multi-spawn clicks.

var is_spawning: bool = false
var current_pos: Vector3 = Vector3.ZERO
var is_current_valid: bool = false
var _ray_query: PhysicsRayQueryParameters3D

var ghost_root: Node3D
var ring_mesh: MeshInstance3D
var ring_mat: StandardMaterial3D
var ghost_model: Node3D

# Island bounds (match PlacementManager)
const ISLAND_EXTENT_X: float = 24.0
const ISLAND_EXTENT_Z: float = 24.0
# Pearl dais footprint (SacredDragonPearl at 0, 0, 0)
const HOUSE_X_MIN: float = -3.7
const HOUSE_X_MAX: float = 3.7
const HOUSE_Z_MIN: float = -3.7
const HOUSE_Z_MAX: float = 3.7

func _ready() -> void:
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collision_mask = ground_collision_mask
	if GameManager:
		selected_enemy_id = GameManager.debug_enemy_id
	if EventBus:
		EventBus.debug_enemy_changed.connect(_on_debug_enemy_changed)
	_create_ghost_preview()
	# Scripted combat checks live in EnemyAiTest.gd (-- --ghost-test / -- --spider-test).
	for flag in ["--ghost-test", "--spider-test"]:
		if flag in OS.get_cmdline_user_args():
			load("res://src/battle/EnemyAiTest.gd").new().run(self, flag)
			break

func _process(_delta: float) -> void:
	if not is_spawning:
		return
	_update_raycast_hover()

func _unhandled_input(event: InputEvent) -> void:
	# While any picker panel is open, keys/clicks belong to it.
	if GameManager and GameManager.is_any_selector_open():
		return
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_G:
			if is_spawning:
				cancel()
			else:
				start()
			get_viewport().set_input_as_handled()
			return
	if not is_spawning:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if is_current_valid:
				_spawn_enemy()
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()

func start() -> void:
	is_spawning = true
	is_current_valid = false
	if is_instance_valid(ghost_root):
		ghost_root.visible = false
	if GameManager:
		GameManager.is_enemy_spawn_mode = true
	print("[EnemyDebugSpawner] Spawn mode ON - Left-Click to spawn %s, Right-Click/Esc/G to exit." % _enemy_display_name(selected_enemy_id))

func cancel() -> void:
	is_spawning = false
	is_current_valid = false
	if is_instance_valid(ghost_root):
		ghost_root.visible = false
	if GameManager and GameManager.is_enemy_spawn_mode:
		GameManager.is_enemy_spawn_mode = false
	print("[EnemyDebugSpawner] Spawn mode OFF.")

func _update_raycast_hover() -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	_ray_query.from = ray_origin
	_ray_query.to = ray_origin + ray_dir * 180.0
	var result = get_world_3d().direct_space_state.intersect_ray(_ray_query)
	if result and result.has("position"):
		var hit_pos: Vector3 = result.position
		current_pos = Vector3(hit_pos.x, hit_pos.y + 0.02, hit_pos.z)
		is_current_valid = _check_validity(current_pos)
		if is_instance_valid(ghost_root):
			ghost_root.visible = true
			ghost_root.global_position = current_pos
			_update_ghost_visuals(is_current_valid)
	else:
		is_current_valid = false
		if is_instance_valid(ghost_root):
			ghost_root.visible = false

func _check_validity(pos: Vector3) -> bool:
	if abs(pos.x) > ISLAND_EXTENT_X or abs(pos.z) > ISLAND_EXTENT_Z:
		return false
	if pos.x > HOUSE_X_MIN and pos.x < HOUSE_X_MAX and pos.z > HOUSE_Z_MIN and pos.z < HOUSE_Z_MAX:
		return false
	return true

func _spawn_enemy() -> void:
	var scene := _enemy_scene(selected_enemy_id)
	if not scene:
		return
	var enemy = scene.instantiate() as Node3D
	_add_enemy_to_container(enemy)
	enemy.global_position = current_pos
	print("✓ Debug enemy spawned: ", selected_enemy_id, " at ", current_pos)
	# Stay in spawn mode for rapid multi-spawn (Right-Click/Esc/G to exit).

## Catalog helpers (linear scan over 1-N entries, spawn path only — never per-frame).
func _enemy_by_id(enemy_id: String) -> Dictionary:
	return BalanceDB.enemy_entry(enemy_id)

func _enemy_display_name(enemy_id: String) -> String:
	return str(_enemy_by_id(enemy_id).get("name", enemy_id))

func _enemy_scene(enemy_id: String) -> PackedScene:
	var scene := BalanceDB.unit_scene(enemy_id)
	return scene if scene else ghost_scene # fallback keeps the legacy --ghost-test path working

func _on_debug_enemy_changed(enemy_id: String) -> void:
	if _enemy_by_id(enemy_id).is_empty():
		print("[EnemyDebugSpawner] Ignoring unknown enemy id: ", enemy_id)
		return
	selected_enemy_id = enemy_id
	_update_preview_model(enemy_id)
	print("[EnemyDebugSpawner] Armed: ", _enemy_display_name(enemy_id))

func _add_enemy_to_container(enemy: Node) -> void:
	var container = get_node_or_null(enemies_container_path)
	if container:
		container.add_child(enemy)
	else:
		get_parent().add_child(enemy)

func _create_ghost_preview() -> void:
	ghost_root = Node3D.new()
	ghost_root.name = "EnemyGhostPreview"
	ghost_root.visible = false
	add_child(ghost_root)

	ring_mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 0.98
	torus.rings = 24
	torus.ring_segments = 12
	ring_mesh.mesh = torus

	ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(0.75, 0.35, 1.0, 0.8)
	ring_mesh.material_override = ring_mat
	ring_mesh.position.y = 0.05
	ghost_root.add_child(ring_mesh)

	_update_preview_model(selected_enemy_id)

## Swaps the translucent cursor model to the picked enemy (selector path).
## Old model is freed; materials are per-preview so instances never share tints.
func _update_preview_model(enemy_id: String) -> void:
	if is_instance_valid(ghost_model):
		ghost_model.queue_free()
		ghost_model = null
	if not is_instance_valid(ghost_root):
		return
	var entry := _enemy_by_id(enemy_id)
	var glb_path := str(entry.get("preview_model", ""))
	var model_scale := float(entry.get("preview_scale", 1.5))
	if glb_path.is_empty() or not ResourceLoader.exists(glb_path):
		return
	var glb_scene := load(glb_path) as PackedScene
	if glb_scene:
		ghost_model = glb_scene.instantiate()
		ghost_model.name = "GhostModel"
		ghost_model.scale = Vector3(model_scale, model_scale, model_scale)
		_make_translucent(ghost_model, 0.65)
		ghost_root.add_child(ghost_model)

func _make_translucent(node: Node, alpha: float) -> void:
	if node is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.8, 0.65, 1.0, alpha)
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
		node.material_override = mat
	for child in node.get_children():
		_make_translucent(child, alpha)

func _update_ghost_visuals(is_valid: bool) -> void:
	if is_instance_valid(ring_mat):
		ring_mat.albedo_color = Color(0.75, 0.35, 1.0, 0.8) if is_valid else Color(0.95, 0.25, 0.25, 0.8)
	if is_instance_valid(ghost_model):
		var col = Color(0.8, 0.65, 1.0, 0.65) if is_valid else Color(1.0, 0.45, 0.45, 0.65)
		_apply_ghost_color(ghost_model, col)

func _apply_ghost_color(node: Node, col: Color) -> void:
	if node is MeshInstance3D and node.material_override is StandardMaterial3D:
		(node.material_override as StandardMaterial3D).albedo_color = col
	for child in node.get_children():
		_apply_ghost_color(child, col)
