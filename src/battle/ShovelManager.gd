class_name ShovelManager
extends Node3D

# PvZ-style shovel: click a placed plant or live zombie to remove it (no refund).
# Enter with X / the SeedBank shovel tool (GameManager.select_shovel), exit with
# Right-Click / Esc / X. Stays equipped for multi-digs; empty-lawn clicks no-op.
# Plant removal reuses PlantBase.remove_by_shovel (tile freed via plant_died);
# zombie removal reuses HungryGhost.remove_by_shovel (standard death path).
# Clicks fire on RELEASE within a small drag threshold so camera Left-drag pans
# never dig up plants by accident (mirrors ThirdPersonCamera drag_threshold).
#
# LAN co-op: every device owns one cursor for its local player. The guest's dig
# is a command — the host re-picks the target by grid coord / net id, removes it
# and broadcasts, so a guest cannot dig on a device that never saw the plant
# (CONTRACT(lan-coop)).

@export var entity_collision_mask: int = 13 # Layers 1 (Ground) + 3 (Plants) + 4 (Enemies)

## Click-vs-drag gate: releases that travelled further than this are camera
## pans, not shovel digs (camera starts panning at 5px; 6px keeps us outside it).
const CLICK_DRAG_TOLERANCE_PX: float = 6.0
const CURSOR_VALID_COLOR := Color(1.0, 0.75, 0.30, 0.9) # amber: hovered removable
const CURSOR_IDLE_COLOR := Color(0.65, 0.65, 0.65, 0.45) # dim gray: lawn / nothing
const GUEST_CURSOR_VALID_COLOR := Color(0.45, 0.90, 1.0, 0.95)
const GUEST_CURSOR_IDLE_COLOR := Color(0.55, 0.80, 0.90, 0.45)

var is_active: bool = false
var hovered_entity: Node3D = null
var _ray_query: PhysicsRayQueryParameters3D
var _press_down: bool = false
var _press_pos: Vector2 = Vector2.ZERO

var cursor_root: Node3D
var cursor_mat: StandardMaterial3D
var _last_cursor_state: int = -1 # -1 hidden, 0 idle, 1 valid-target
var _punch_tween: Tween = null

func _ready() -> void:
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collision_mask = entity_collision_mask
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true
	_create_cursor()
	if EventBus:
		EventBus.shovel_mode_changed.connect(_on_shovel_mode_changed)
	if GameManager and GameManager.is_shovel_mode:
		_on_shovel_mode_changed(true, GameManager.local_player_id())

func _process(_delta: float) -> void:
	if is_active:
		_update_hover(get_viewport().get_mouse_position())

func _unhandled_input(event: InputEvent) -> void:
	# Selector overlays own all keys/clicks while open.
	if GameManager and GameManager.is_any_selector_open():
		return
	# Debug G-spawner owns Left-Click while armed; shovel yields to avoid spawn+dig races.
	if GameManager and GameManager.is_enemy_spawn_mode:
		return
	var local_id: int = GameManager.local_player_id() if GameManager else 0
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_X:
			if GameManager:
				GameManager.toggle_shovel(local_id)
				get_viewport().set_input_as_handled()
			return
		if not is_active:
			return
		if event.keycode == KEY_ESCAPE:
			GameManager.cancel_shovel(local_id)
			get_viewport().set_input_as_handled()
			return
		return
	if not is_active:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_down = true
				_press_pos = event.position
			else:
				if _press_down:
					# Mouse: a release after a pan is not a dig. Touch: the drag
					# aims (the hover follows the finger), so the lift digs —
					# unless a pinch/orbit was in progress.
					var tap := true
					if GameManager and GameManager.is_touch_ui():
						tap = not GameManager.touch_gesture_multi
					else:
						tap = _press_pos.distance_to(event.position) <= CLICK_DRAG_TOLERANCE_PX
					if tap:
						var target := _pick_at(event.position)
						if is_instance_valid(target):
							_dig(target)
							get_viewport().set_input_as_handled()
				_press_down = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			GameManager.cancel_shovel(local_id)
			get_viewport().set_input_as_handled()

func _on_shovel_mode_changed(active: bool, player_id: int) -> void:
	if GameManager and player_id != GameManager.local_player_id():
		return
	is_active = active
	_press_down = false
	hovered_entity = null
	_last_cursor_state = -1
	_show_cursor(false)
	if active:
		print("[ShovelManager] P", player_id + 1, " shovel ON - remove with Left-Click (no refund).")
	else:
		print("[ShovelManager] P", player_id + 1, " shovel OFF.")

## Fresh entity pick at a screen position (used by hover + release-click alike).
func _pick_at(screen_pos: Vector2) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	_ray_query.from = camera.project_ray_origin(screen_pos)
	_ray_query.to = _ray_query.from + camera.project_ray_normal(screen_pos) * 180.0
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ray_query)
	if result.is_empty() or not result.has("collider"):
		return null
	var collider: Object = result["collider"]
	if collider is Node and (collider.is_in_group("Plants") or collider.is_in_group("Enemies")) and collider.has_method("remove_by_shovel"):
		return collider as Node3D
	return null

func _update_hover(screen_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_ray_query.from = camera.project_ray_origin(screen_pos)
	_ray_query.to = _ray_query.from + camera.project_ray_normal(screen_pos) * 180.0
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ray_query)
	if result.is_empty() or not result.has("position"):
		hovered_entity = null
		_set_cursor(-1, Vector3.ZERO)
		return
	var hit_pos: Vector3 = result["position"]
	var target: Node3D = null
	var collider: Object = result.get("collider")
	if collider is Node and (collider.is_in_group("Plants") or collider.is_in_group("Enemies")) and collider.has_method("remove_by_shovel"):
		target = collider as Node3D
	hovered_entity = target
	if is_instance_valid(target):
		_set_cursor(1, target.global_position)
	else:
		_set_cursor(0, hit_pos)

func _set_cursor(state: int, world_pos: Vector3) -> void:
	if not is_instance_valid(cursor_root):
		return
	if state == -1:
		cursor_root.visible = false
		_last_cursor_state = -1
		return
	cursor_root.visible = true
	cursor_root.global_position = world_pos + Vector3(0.0, 0.06, 0.0)
	if state != _last_cursor_state:
		_last_cursor_state = state
		if is_instance_valid(cursor_mat):
			var guest: bool = GameManager != null and GameManager.local_player_id() == 1
			if guest:
				cursor_mat.albedo_color = GUEST_CURSOR_VALID_COLOR if state == 1 else GUEST_CURSOR_IDLE_COLOR
			else:
				cursor_mat.albedo_color = CURSOR_VALID_COLOR if state == 1 else CURSOR_IDLE_COLOR

func _show_cursor(shown: bool) -> void:
	if is_instance_valid(cursor_root):
		cursor_root.visible = shown

## Remove the target. On the guest this only asks the host; the host's removal
## event drives the actual free on both devices.
func _dig(target: Node3D) -> void:
	var label := target.name
	if target.is_in_group("Plants"):
		label = "plant %s" % target.name
	elif target.is_in_group("Enemies"):
		label = "zombie %s" % target.name
	if GameManager and GameManager.is_client():
		var coord = target.get("grid_coord")
		if coord is Vector2i:
			Net.send_command({"t": "dig_plant", "x": coord.x, "z": coord.y})
		else:
			Net.send_command({"t": "dig_enemy", "id": int(target.get_meta("net_id", -1))})
		_punch_cursor()
		return
	target.remove_by_shovel()
	Audio.play(Audio.SHOVEL_REMOVE)
	hovered_entity = null
	_set_cursor(0, target.global_position if is_instance_valid(target) else Vector3.ZERO)
	_punch_cursor()
	print("[ShovelManager] P", (GameManager.local_player_id() + 1) if GameManager else 1, " shovelled %s (no refund)." % label)

func _punch_cursor() -> void:
	if not is_instance_valid(cursor_root):
		return
	if _punch_tween and _punch_tween.is_valid():
		_punch_tween.kill()
	cursor_root.scale = Vector3(1.25, 1.25, 1.25)
	_punch_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_property(cursor_root, "scale", Vector3.ONE, 0.14)

func _create_cursor() -> void:
	var root := Node3D.new()
	root.name = "ShovelCursor"
	root.visible = false
	add_child(root)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 0.98
	torus.rings = 24
	torus.ring_segments = 12
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var guest: bool = GameManager != null and GameManager.local_player_id() == 1
	mat.albedo_color = GUEST_CURSOR_IDLE_COLOR if guest else CURSOR_IDLE_COLOR
	ring.material_override = mat
	ring.position.y = 0.0
	root.add_child(ring)
	cursor_root = root
	cursor_mat = mat
