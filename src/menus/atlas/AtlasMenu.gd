extends Node3D

# Atlas menu — the start screen: the Vietnam atlas model (vietnam_world_atlas.glb)
# seen by a tilted camera that travels a north -> south rail along the S-curve
# (drag, W/S / arrow keys or two-finger scroll) and zooms in / out along its
# view line (mouse wheel, Q/E, +/- or pinch; ZOOM_MIN..ZOOM_MAX). Every province mesh
# shares one AtlasProvince.gdshader material: hovered_id lifts the piece under the
# mouse, province_state[] dims provinces that have content but are still locked
# and tints finished ones. Hovering shows a tooltip (name + world name + level
# count, or what unlocks it, or "Coming soon"). Provinces with a world get a name
# label. Worlds come from LevelDB (world "province" = atlas id), state from
# Progress (recomputed on EventBus.progress_changed only).
# Clicking an unlocked province with content opens its province screen in this
# same scene: the camera flies to frame the piece, every other province dims
# (shader focus_id / focus_dim), and a ProvinceBoard draws the level path and
# pops the level nodes. Hovering a node names it and starts a threaded preload
# of the battle shell + the level's map; clicking an unlocked node enters the
# level straight away (EventBus.level_play_requested). Back / Esc / right-click flies back to the
# rail. A locked or content-less province only shakes its tooltip. While a
# province is open the name labels and landmark meshes (Landmark 81, pearl, Turtle
# Tower, lighthouse) hide: they stand on the level path.
# GameFlow: on load the menu asks GameFlow.take_menu_request() and, coming back
# from a battle, opens that province at once and pops the just-unlocked nodes;
# the rail starts on Progress.last_world's province (else HCMC). On
# EventBus.flow_transition_started("battle") the camera dives at the picked node
# under GameFlow's fade.
# Zero idle cost: picking runs on mouse events, _process runs only while the
# rail camera glides, and the zoom / reveal are one-shot tweens.
# Run standalone: $GODOT --path . res://src/menus/atlas/AtlasMenu.tscn
# (-- --atlas-test: AtlasTest.gd; -- --path-edit: print clicked XZ for a
# world's "path"; -- --screenshot --atlas-overview|--atlas-hcmc|--atlas-province, or
# --atlas-at <province id> for the rail view hovering that province).

const PROVINCE_SLOTS := 34 # province_state[34] in AtlasProvince.gdshader
const SHADER_PATH := "res://assets/shaders/AtlasProvince.gdshader"
const START_PROVINCE := "hcmc"

# Rail camera: looks north-down at a target that slides along the rail.
const CAM_HEIGHT := 8.0
const CAM_BACK := 5.5
const RAIL_KNOTS := 10
const RAIL_SMOOTH := 1.4        # metres: label points within this z-distance steer a knot
const KEY_STEP := 1.6          # metres of rail per W/S press
const PAN_GESTURE_METRES := 0.35 # metres of rail per unit of trackpad scroll
# Zoom = camera distance multiplier on the rail pose (1 = default framing).
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.6
const ZOOM_STEP := 1.15         # per wheel notch / key press
const DRAG_METRES_PER_PX := 0.02
const DRAG_THRESHOLD_PX := 5.0
const GLIDE_RATE := 8.0         # exponential approach per second
const LABEL_LIFT := 0.35
# Province screen.
const FLY_TIME := 0.8
const REVEAL_DELAY := 0.4       # board starts drawing this far into the fly-in
const FOCUS_DIM := 0.55
const FRAME_MARGIN := 1.5
# Steeper than the rail (~68° down) so tall landmarks don't hide the path.
const PROVINCE_VIEW_DIR := Vector3(0.0, 0.93, 0.37)
const CARD_SHIFT := 0.0
## Touch targets are sized in points, not pixels: 48 px at the 1.3 canvas scale
## is ~34 pt on a phone, under the 44 pt recommended minimum.
const TOUCH_BUTTON_MIN := 48.0
const BATTLE_SCENE := "res://src/battle/DioramaWorld.tscn"

enum State { NO_CONTENT = 0, LOCKED = 1, UNLOCKED = 2, COMPLETED = 3 }
enum Mode { ATLAS, PROVINCE, TRANSITION }

signal transition_finished

@onready var _camera: Camera3D = $Camera3D
@onready var _atlas_root: Node3D = $Atlas
@onready var _tooltip: PanelContainer = $UI/Tooltip
@onready var _tooltip_label: Label = $UI/Tooltip/Label
@onready var _title: Label = $UI/Title
@onready var _hint: Label = $UI/Hint
@onready var _back: Button = $UI/Back

var provinces: AtlasProvinces
var _material: ShaderMaterial
var _states := PackedFloat32Array()
var _tops := PackedFloat32Array()
var _world_by_province: Dictionary = {} # province id -> world Dictionary
var _rail := Curve3D.new()
var _rail_pos: float = 0.0
var _rail_goal: float = 0.0
var _zoom: float = 1.0
var _zoom_goal: float = 1.0
var _hovered: int = -1
var _mouse_pos := Vector2.ZERO
var _dragging := false
var _press_pos := Vector2.ZERO
var _press_goal: float = 0.0
var _left_down := false
var mode: int = Mode.ATLAS
var board: ProvinceBoard = null
var _open_index: int = -1
var _playing_level_id: String = ""
var _requested_loads: Dictionary = {}
var _path_edit := false
var _edit_points: Array[Vector2] = []
var _labels: Array[Label3D] = []
var _landmarks: Array[MeshInstance3D] = [] # hidden on the province screen: they stand on the path
var _lan_button: Button = null
var _lan_panel: LanPanel = null
var _shrine_button: Button = null
var _shrine: SeedShrine = null


func _ready() -> void:
	provinces = AtlasProvinces.load_default()
	if provinces.count() > PROVINCE_SLOTS:
		push_error("[AtlasMenu] %d provinces but the shader holds %d." % [provinces.count(), PROVINCE_SLOTS])
	for w in LevelDB.get_worlds():
		_world_by_province[str(w.get("province", ""))] = w
	_setup_materials()
	_add_content_labels()
	_refresh_states()
	EventBus.progress_changed.connect(_refresh_states)
	_build_rail()
	var request := GameFlow.take_menu_request()
	var start := str(request["province"])
	if start.is_empty() and not Progress.last_world.is_empty():
		start = str(LevelDB.get_world(Progress.last_world).get("province", ""))
	_snap_rail(_rail_offset_of(start if provinces.index_of(start) >= 0 else START_PROVINCE))
	_tooltip.visible = false
	_back.visible = false
	_back.pressed.connect(close_province)
	EventBus.flow_transition_started.connect(_on_flow_transition)
	_setup_chrome()
	_setup_lan()
	_setup_shrine()
	_setup_touch()
	_warm_board_shaders()
	if not str(request["province"]).is_empty():
		open_province(str(request["province"]), true, request["pops"])
	set_process(false)
	var args := OS.get_cmdline_user_args()
	_path_edit = "--path-edit" in args
	if "--atlas-test" in args:
		load("res://src/menus/atlas/AtlasTest.gd").new().run(self)
	elif "--screenshot" in args:
		_run_screenshot(args)


# ---------------------------------------------------------------- materials ---

func _setup_materials() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	for mi in _atlas_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := mi as MeshInstance3D
		if mesh_node.name.begins_with("Provinces_Locked") or mesh_node.name.begins_with("Province_"):
			mesh_node.material_override = _material
			continue
		if mesh_node.name.begins_with("Landmarks") or mesh_node.name.begins_with("Emissive_"):
			_landmarks.append(mesh_node)
		# Other baked-colour meshes: Godot's glTF import stores COLOR_0 sRGB-encoded.
		for s in mesh_node.mesh.get_surface_count():
			var colors: Variant = mesh_node.mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
			var mat := mesh_node.mesh.surface_get_material(s) as StandardMaterial3D
			if mat and colors is PackedColorArray and not (colors as PackedColorArray).is_empty():
				mat.vertex_color_use_as_albedo = true
				mat.vertex_color_is_srgb = true


func _add_content_labels() -> void:
	for province_id in _world_by_province:
		var i := provinces.index_of(province_id)
		if i < 0:
			continue
		var label := Label3D.new()
		label.text = tr(provinces.names[i])
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font = UiPalette.hud_font()
		label.font_size = 52
		label.outline_size = 22
		label.pixel_size = 0.004
		label.modulate = UiPalette.HUD_INK
		label.outline_modulate = UiPalette.HUD_EDGE
		label.no_depth_test = true
		label.position = Vector3(provinces.labels[i].x, provinces.unlocked_top + LABEL_LIFT, provinces.labels[i].y + 1.05)
		add_child(label)
		_labels.append(label)


# ------------------------------------------------------------------ states ---

func province_state(index: int) -> int:
	var world: Dictionary = _world_by_province.get(provinces.ids[index], {})
	if world.is_empty():
		return State.NO_CONTENT
	var world_id := str(world["id"])
	if not Progress.is_world_unlocked(world_id):
		return State.LOCKED
	var total := LevelDB.get_level_ids(world_id).size()
	if total > 0 and Progress.completed_count(world_id) >= total:
		return State.COMPLETED
	return State.UNLOCKED


func _refresh_states() -> void:
	_states.resize(PROVINCE_SLOTS)
	_states.fill(0.0)
	_tops.resize(provinces.count())
	for i in provinces.count():
		var st := province_state(i)
		_states[i] = float(st)
		_tops[i] = provinces.locked_top if st == State.NO_CONTENT else provinces.unlocked_top
	_material.set_shader_parameter("province_state", _states)
	if _hovered >= 0:
		_tooltip_label.text = describe(_hovered)


func describe(index: int) -> String:
	var pname := tr(provinces.names[index])
	var world: Dictionary = _world_by_province.get(provinces.ids[index], {})
	if world.is_empty():
		return tr("%s\nComing soon") % pname
	var world_id := str(world["id"])
	if not Progress.is_world_unlocked(world_id):
		var needs := PackedStringArray()
		var unlock: Variant = world.get("unlock", null)
		if unlock is Dictionary and (unlock as Dictionary).has("stars"):
			return tr("%s\n🔒 Earn %d ★ to unlock (you have %d)") % [pname, int(unlock["stars"]), Progress.total_stars()]
		if unlock is Dictionary:
			for level_id in (unlock as Dictionary).get("after", []):
				needs.append(tr(str(LevelDB.get_level(str(level_id)).get("name", level_id))))
		return tr("%s\n🔒 Finish %s to unlock") % [pname, ", ".join(needs)] if not needs.is_empty() else tr("%s\n🔒 Locked") % pname
	var total := LevelDB.get_level_ids(world_id).size()
	return tr("%s — %s\n%d / %d levels") % [pname, tr(str(world.get("name", world_id))), Progress.completed_count(world_id), total]


# ----------------------------------------------------------------- picking ---

## Province index under a screen position, or -1.
func pick_at(screen_pos: Vector2) -> int:
	return provinces.pick(_camera.project_ray_origin(screen_pos), _camera.project_ray_normal(screen_pos), _tops)


func _update_hover() -> void:
	var i := pick_at(_mouse_pos)
	if i != _hovered:
		_hovered = i
		_material.set_shader_parameter("hovered_id", i)
		_tooltip.visible = i >= 0
		if i >= 0:
			_tooltip_label.text = describe(i)
	if _tooltip.visible:
		_tooltip.reset_size()
		_tooltip.position = _mouse_pos + Vector2(18, 18)


## Touch: the atlas budget is one finger = drag/tap (Godot's emulated mouse,
## already wired below), two fingers = travel + zoom. No new draw calls: the
## gesture maths rides on TouchInput (src/ui/TouchInput.gd), and the Back button
## is grown to a finger-sized target instead of a second one being added.
func _setup_touch() -> void:
	if GameManager == null or not GameManager.is_touch_ui():
		return
	EventBus.touch_pinch.connect(_on_touch_pinch)
	EventBus.touch_drag.connect(_on_touch_drag)
	_back.custom_minimum_size = Vector2(0.0, TOUCH_BUTTON_MIN)
	_back.add_theme_font_size_override("font_size", 18)
	_hint.offset_top = -72.0
	_hint.offset_bottom = -24.0
	_hint.add_theme_font_size_override("font_size", 17)
	# The hint sits over the bright map at the bottom of the screen: a dark
	# outline keeps it readable there without adding a panel or a draw call.
	_hint.add_theme_color_override("font_outline_color", UiPalette.INK)
	_hint.add_theme_constant_override("outline_size", 5)
	SafeArea.apply(_back)
	SafeArea.apply(_hint)
	SafeArea.apply(_title)
	_hint.text = _atlas_hint()


## The atlas screen's controls line. Same sentence slots either way, so the
## layout does not reflow between desktop and a phone.
func _atlas_hint() -> String:
	if GameManager != null and GameManager.is_touch_ui():
		return tr("Two fingers to travel  •  Pinch to zoom  •  Tap a province")
	return tr("Drag or W/S to travel  •  Scroll or Q/E to zoom  •  Click a province")


## Fingers apart (factor > 1) zoom in: the rail zoom is a distance multiplier,
## so dividing by the spread matches the wheel.
func _on_touch_pinch(factor: float) -> void:
	if mode == Mode.TRANSITION or factor <= 0.0:
		return
	set_zoom_goal(_zoom_goal / factor)


## Two-finger drag travels the rail. Vertical only, like a trackpad pan: the
## rail is the one axis the camera has, and horizontal input would be dead.
func _on_touch_drag(delta: Vector2) -> void:
	if mode == Mode.TRANSITION:
		return
	_set_goal(_rail_goal + delta.y * PAN_GESTURE_METRES)


## Android's Back button. Without this the OS would close the app from the
## province screen, which is the only place a back press is not already
## something else. Rides the same path as Esc / the Back button. At the atlas
## root there is nowhere left to go, so Back leaves the app instead of
## swallowing the press.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if mode == Mode.PROVINCE:
		close_province()
	elif mode != Mode.TRANSITION:
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.TRANSITION:
		return
	if mode == Mode.PROVINCE:
		_province_input(event)
		return
	if event is InputEventMouseMotion:
		_mouse_pos = event.position
		if _left_down and not _dragging and event.position.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
			_dragging = true
		if _dragging:
			_set_goal(_press_goal - (event.position.y - _press_pos.y) * DRAG_METRES_PER_PX)
		else:
			_update_hover()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_zoom_goal(_zoom_goal / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_zoom_goal(_zoom_goal * ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_left_down = mb.pressed
			if mb.pressed:
				_press_pos = mb.position
				_press_goal = _rail_goal
			else:
				if not _dragging:
					click_province(pick_at(mb.position))
				_dragging = false
	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_W, KEY_UP:
				_set_goal(_rail_goal - KEY_STEP)
			KEY_S, KEY_DOWN:
				_set_goal(_rail_goal + KEY_STEP)
			KEY_Q, KEY_EQUAL, KEY_KP_ADD:
				set_zoom_goal(_zoom_goal / ZOOM_STEP)
			KEY_E, KEY_MINUS, KEY_KP_SUBTRACT:
				set_zoom_goal(_zoom_goal * ZOOM_STEP)
	elif event is InputEventMagnifyGesture:
		set_zoom_goal(_zoom_goal / (event as InputEventMagnifyGesture).factor)
	elif event is InputEventPanGesture:
		_set_goal(_rail_goal + (event as InputEventPanGesture).delta.y * PAN_GESTURE_METRES)


func _province_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = event.position
		var i := board.node_at_screen(_camera, event.position)
		board.set_hovered(i)
		_tooltip.visible = i >= 0
		if i >= 0:
			var level_id := board.level_ids[i]
			var level := LevelDB.get_level(level_id)
			var level_name := tr(str(level.get("name", level_id)))
			if Progress.is_level_unlocked(level_id):
				if Progress.is_level_completed(level_id):
					_tooltip_label.text = tr("%s (✓ Completed)") % level_name
				else:
					_tooltip_label.text = level_name
				_preload_level(level_id)
			else:
				var ids := LevelDB.get_level_ids(LevelDB.world_of(level_id))
				var prev_idx := ids.find(level_id) - 1
				var prev_name := tr(str(LevelDB.get_level(ids[prev_idx]).get("name", ids[prev_idx]))) if prev_idx >= 0 else ""
				if not prev_name.is_empty():
					_tooltip_label.text = tr("%s (🔒 Finish \"%s\" first)") % [level_name, prev_name]
				else:
					_tooltip_label.text = tr("%s (🔒 Locked)") % level_name
			_tooltip.reset_size()
			_tooltip.position = event.position + Vector2(18, 18)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			close_province()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			var i := board.node_at_screen(_camera, mb.position)
			if i >= 0:
				var clicked_id := board.level_ids[i]
				if Net.is_guest():
					# The host picks the level; show the room status instead.
					if _lan_panel != null:
						_lan_panel.open()
					return
				if Progress.is_level_unlocked(clicked_id):
					_playing_level_id = clicked_id
					Audio.play(Audio.UI_CLICK)
					EventBus.level_play_requested.emit(clicked_id)
				else:
					_shake_tooltip()
			elif _path_edit:
				_path_edit_click(mb.position)
	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				close_province()
			KEY_P:
				if _path_edit:
					print("[PathEdit] \"path\": %s" % JSON.stringify(_edit_points.map(func(p: Vector2) -> Array: return [snappedf(p.x, 0.001), snappedf(p.y, 0.001)])))


# ---------------------------------------------------------------- LAN co-op ---

## Host/join entry point (CONTRACT(lan-coop)). The panel is the only networking
## The Lacquer dressing for the nodes AtlasMenu.tscn places.
func _setup_chrome() -> void:
	_title.add_theme_font_override("font", UiPalette.hud_font())
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", UiPalette.HUD_ACCENT)
	_title.add_theme_color_override("font_outline_color", UiPalette.HUD_EDGE)
	_title.add_theme_constant_override("outline_size", 10)
	_hint.add_theme_font_override("font", UiPalette.hud_font())
	_hint.add_theme_color_override("font_color", UiPalette.HUD_INK_SOFT)
	var plate := UiPalette.lacquer_box(UiPalette.HUD_LACQUER_BOT, UiPalette.HUD_GOLD, 5, 1, 12)
	plate.content_margin_top = 4
	plate.content_margin_bottom = 4
	_hint.add_theme_stylebox_override("normal", plate)
	UiPalette.lacquer_button(_back, false, false, 16)
	var tooltip := $UI/Tooltip as PanelContainer
	tooltip.add_theme_stylebox_override("panel", UiPalette.lacquer_box(UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_GOLD, 5, 1, 10))
	var tip_label := tooltip.get_node("Label") as Label
	tip_label.add_theme_font_override("font", UiPalette.hud_font())
	tip_label.add_theme_color_override("font_color", UiPalette.HUD_INK)


## UI: the atlas stays the level picker, and only the host ever picks one.
func _setup_lan() -> void:
	if Net == null:
		return
	_lan_button = Button.new()
	_lan_button.name = "LanButton"
	_lan_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lan_button.offset_left = -214.0
	_lan_button.offset_top = 18.0
	_lan_button.offset_right = -24.0
	_lan_button.offset_bottom = 58.0
	UiPalette.lacquer_button(_lan_button, false, false, 16)
	_lan_button.pressed.connect(func() -> void: _lan_panel.open())
	$UI.add_child(_lan_button)
	SafeArea.apply(_lan_button)

	_lan_panel = LanPanel.new()
	_lan_panel.name = "LanPanel"
	$UI.add_child(_lan_panel)

	Net.role_changed.connect(_update_lan_button)
	Net.guest_joined.connect(_update_lan_button)
	Net.guest_left.connect(_update_lan_button)
	_update_lan_button()


## Seed Shrine (Leyline Jade shop), under the LAN button. The label carries the wallet.
func _setup_shrine() -> void:
	_shrine_button = Button.new()
	_shrine_button.name = "ShrineButton"
	_shrine_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_shrine_button.offset_left = -214.0
	_shrine_button.offset_top = 66.0
	_shrine_button.offset_right = -24.0
	_shrine_button.offset_bottom = 106.0
	UiPalette.lacquer_button(_shrine_button, false, false, 16)
	$UI.add_child(_shrine_button)
	SafeArea.apply(_shrine_button)
	_shrine = SeedShrine.new()
	_shrine.name = "SeedShrine"
	$UI.add_child(_shrine)
	_shrine_button.pressed.connect(_shrine.open)
	EventBus.progress_changed.connect(_update_shrine_button)
	_update_shrine_button()


func _update_shrine_button() -> void:
	_shrine_button.text = tr("Seed Shrine · %d Jade") % Progress.jade


func _update_lan_button(_role: int = 0) -> void:
	if _lan_button == null or Net == null:
		return
	if Net.is_host():
		_lan_button.text = tr("LAN: Hosting")
	elif Net.is_guest():
		_lan_button.text = tr("LAN: Connected")
	else:
		_lan_button.text = tr("LAN Co-op")


# ---------------------------------------------------------- province screen ---

## Atlas click on province `index`: open it, or shake the tooltip if it has no
## content or is still locked.
func click_province(index: int) -> void:
	if index < 0:
		return
	var st := province_state(index)
	if st == State.UNLOCKED or st == State.COMPLETED:
		Audio.play(Audio.UI_CLICK)
		open_province(provinces.ids[index])
	else:
		_shake_tooltip()


## instant: no flight or reveal (coming back from a battle); pops: level ids
## whose nodes should pop in (just unlocked).
func open_province(province_id: String, instant: bool = false, pops: PackedStringArray = PackedStringArray()) -> void:
	var index := provinces.index_of(province_id)
	var world: Dictionary = _world_by_province.get(province_id, {})
	if mode != Mode.ATLAS or index < 0 or world.is_empty():
		return
	mode = Mode.TRANSITION
	set_process(false)
	_open_index = index
	_hovered = -1
	_material.set_shader_parameter("hovered_id", -1)
	_material.set_shader_parameter("focus_id", index)
	_tooltip.visible = false
	_set_landmarks_visible(false)
	board = ProvinceBoard.new()
	add_child(board)
	board.build(str(world["id"]), _world_path(world, index), provinces.unlocked_top)
	var view := _province_view(index)
	if instant:
		_camera.look_at_from_position(view[0], view[1])
		_material.set_shader_parameter("focus_dim", FOCUS_DIM)
		board.reveal_now()
		board.pop(pops)
		_enter_province_mode(index)
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_method(_fly.bind(_camera.global_position, _rail_target(), view[0], view[1]), 0.0, 1.0, FLY_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("focus_dim", v), 0.0, FOCUS_DIM, FLY_TIME)
	tween.tween_callback(board.reveal).set_delay(REVEAL_DELAY)
	await board.revealed
	if tween.is_running():
		await tween.finished
	_enter_province_mode(index)


func _enter_province_mode(index: int) -> void:
	_title.text = tr(provinces.names[index])
	_hint.text = tr("Tap a level  •  Back to return") if GameManager.is_touch_ui() else tr("Click a level  •  Esc / right-click to go back")
	_back.visible = true
	mode = Mode.PROVINCE
	transition_finished.emit()


func close_province() -> void:
	if mode != Mode.PROVINCE:
		return
	mode = Mode.TRANSITION
	_tooltip.visible = false
	_back.visible = false
	board.queue_free()
	board = null
	_set_landmarks_visible(true)
	var tween := create_tween().set_parallel(true)
	var view := _province_view(_open_index)
	tween.tween_method(_fly.bind(view[0], view[1], _rail_eye(), _rail_target()), 0.0, 1.0, FLY_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("focus_dim", v), FOCUS_DIM, 0.0, FLY_TIME)
	await tween.finished
	_material.set_shader_parameter("focus_id", -1)
	_open_index = -1
	_title.text = tr("VIETNAM")
	_hint.text = _atlas_hint()
	mode = Mode.ATLAS
	_update_hover()
	transition_finished.emit()


func _set_landmarks_visible(on: bool) -> void:
	for label in _labels:
		label.visible = on
	for mesh in _landmarks:
		mesh.visible = on


## The board's path / pulse / node materials compile their GPU pipelines on first
## draw (a multi-second freeze on a cold shader cache). Draw a real board once,
## hidden under the tray, while the menu loads, so the first zoom-in is smooth.
func _warm_board_shaders() -> void:
	var world: Dictionary = _world_by_province.get(START_PROVINCE, {})
	var index := provinces.index_of(START_PROVINCE)
	if world.is_empty() or index < 0:
		return
	var warm := ProvinceBoard.new()
	add_child(warm)
	warm.build(str(world["id"]), _world_path(world, index), -1.0)
	warm._set_reveal(1.0)
	warm.visible = true
	for i in 2:
		await get_tree().process_frame
	warm.queue_free()


## GameFlow is taking us into a battle: dive at the picked node under its fade.
func _on_flow_transition(kind: String) -> void:
	if kind != "battle" or mode != Mode.PROVINCE or board == null:
		return
	var i := board.level_ids.find(_playing_level_id)
	if i < 0:
		i = board.next_index if board.next_index >= 0 else 0
	mode = Mode.TRANSITION
	_tooltip.visible = false
	var node_pos := board.node_positions[i]
	var eye := _camera.global_position
	var target := eye + (-_camera.global_basis.z) * eye.distance_to(node_pos)
	create_tween().tween_method(_fly.bind(eye, target, node_pos + (eye - node_pos) * 0.35, node_pos), 0.0, 1.0, GameFlow.FADE_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


func _fly(t: float, eye_a: Vector3, target_a: Vector3, eye_b: Vector3, target_b: Vector3) -> void:
	_camera.look_at_from_position(eye_a.lerp(eye_b, t), target_a.lerp(target_b, t))


## [eye, target] framing the province's main piece from PROVINCE_VIEW_DIR.
func _province_view(index: int) -> Array:
	var box := provinces.main_bounds(index)
	var center := Vector3(box.get_center().x, provinces.unlocked_top, box.get_center().y)
	var dir := PROVINCE_VIEW_DIR.normalized()
	var tan_v := tan(deg_to_rad(_camera.fov * 0.5))
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var pitch_sin := dir.y
	var dist := maxf(box.size.x * 0.5 / (tan_v * aspect), box.size.y * 0.5 * pitch_sin / tan_v) * FRAME_MARGIN
	var target := center
	return [target + dir * dist, target]


## The world's "path" control points, or a line through the label along the
## province's long axis (LevelDB already warned about the missing path).
func _world_path(world: Dictionary, index: int) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for p in world.get("path", []):
		pts.append(Vector2(float(p[0]), float(p[1])))
	if pts.size() >= 2:
		return pts
	var box := provinces.bounds(index)
	var lab := provinces.labels[index]
	var half := Vector2(box.size.x * 0.35, 0.0) if box.size.x >= box.size.y else Vector2(0.0, box.size.y * 0.35)
	var line: Array[Vector2] = [lab - half, lab + half]
	return line


func _preload_level(level_id: String) -> void:
	for path in [BATTLE_SCENE, LevelDB.get_map_scene(LevelDB.resolve_map(level_id))]:
		if path.is_empty() or _requested_loads.has(path):
			continue
		_requested_loads[path] = true
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path)


func _shake_tooltip() -> void:
	if not _tooltip.visible:
		return
	var base := _tooltip.position
	var tween := create_tween()
	for dx in [10.0, -8.0, 6.0, -3.0, 0.0]:
		tween.tween_property(_tooltip, "position", base + Vector2(dx, 0.0), 0.04)


func _path_edit_click(screen: Vector2) -> void:
	var origin := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	if absf(dir.y) < 1e-5:
		return
	var hit := origin + dir * ((provinces.unlocked_top - origin.y) / dir.y)
	_edit_points.append(Vector2(hit.x, hit.z))
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.025
	sphere.height = 0.05
	dot.mesh = sphere
	dot.position = Vector3(hit.x, provinces.unlocked_top + 0.03, hit.z)
	board.add_child(dot)
	print("[PathEdit] point %d: [%.3f, %.3f]  (P prints the list)" % [_edit_points.size() - 1, hit.x, hit.z])


# -------------------------------------------------------------- rail camera ---

## Smoothed north -> south centre line of the country: each knot's x is the
## label-weighted mean at that z, so the rail follows the S-curve, not the
## east-west zigzag of neighbouring provinces.
func _build_rail() -> void:
	var z_min := INF
	var z_max := -INF
	for p in provinces.labels:
		z_min = minf(z_min, p.y)
		z_max = maxf(z_max, p.y)
	var knots: Array[Vector3] = []
	for k in RAIL_KNOTS:
		var z := lerpf(z_min, z_max, float(k) / float(RAIL_KNOTS - 1))
		var wsum := 0.0
		var xsum := 0.0
		for p in provinces.labels:
			var w := exp(-pow((p.y - z) / RAIL_SMOOTH, 2.0))
			wsum += w
			xsum += p.x * w
		knots.append(Vector3(xsum / maxf(wsum, 1e-6), 0.0, z))
	_rail.clear_points()
	for k in knots.size():
		var prev := knots[maxi(k - 1, 0)]
		var next := knots[mini(k + 1, knots.size() - 1)]
		var tangent := (next - prev) / 6.0
		_rail.add_point(knots[k], -tangent, tangent)


func _rail_offset_of(province_id: String) -> float:
	var i := provinces.index_of(province_id)
	if i < 0:
		return 0.0
	return _rail.get_closest_offset(Vector3(provinces.labels[i].x, 0.0, provinces.labels[i].y))


func rail_length() -> float:
	return _rail.get_baked_length()


## Move the camera to a rail offset at once (tests, screenshots, first frame).
func _snap_rail(offset: float) -> void:
	_rail_goal = clampf(offset, 0.0, rail_length())
	_rail_pos = _rail_goal
	_place_camera()
	set_process(false)


func _set_goal(offset: float) -> void:
	_rail_goal = clampf(offset, 0.0, rail_length())
	if not is_equal_approx(_rail_goal, _rail_pos):
		set_process(true)


func set_zoom_goal(value: float) -> void:
	_zoom_goal = clampf(value, ZOOM_MIN, ZOOM_MAX)
	if not is_equal_approx(_zoom_goal, _zoom):
		set_process(true)


func zoom() -> float:
	return _zoom


func _process(delta: float) -> void:
	if mode != Mode.ATLAS:
		set_process(false)
		return
	var k := 1.0 - exp(-GLIDE_RATE * delta)
	_rail_pos = lerpf(_rail_pos, _rail_goal, k)
	_zoom = lerpf(_zoom, _zoom_goal, k)
	if absf(_rail_pos - _rail_goal) < 0.002:
		_rail_pos = _rail_goal
	if absf(_zoom - _zoom_goal) < 0.001:
		_zoom = _zoom_goal
	if _rail_pos == _rail_goal and _zoom == _zoom_goal:
		set_process(false)
	_place_camera()
	if not _dragging:
		_update_hover()


func _rail_target() -> Vector3:
	return _rail.sample_baked(_rail_pos)


func _rail_eye() -> Vector3:
	return _rail_target() + Vector3(0.0, CAM_HEIGHT, CAM_BACK) * _zoom


func _place_camera() -> void:
	_camera.look_at_from_position(_rail_eye(), _rail_target())


# -------------------------------------------------------------- screenshots ---

func _run_screenshot(args: PackedStringArray) -> void:
	var shot := "screenshot_atlas_hcmc.png"
	if "--atlas-province" in args:
		shot = "screenshot_atlas_province.png"
		open_province(START_PROVINCE)
		await transition_finished
	elif "--atlas-overview" in args:
		shot = "screenshot_atlas_overview.png"
		var c := provinces.tray.get_center()
		_camera.look_at_from_position(Vector3(c.x, 26.0, c.y + 15.0), Vector3(c.x, 0.0, c.y - 1.0))
	else:
		var at := START_PROVINCE
		var flag := args.find("--atlas-at")
		if flag >= 0 and flag + 1 < args.size() and provinces.index_of(args[flag + 1]) >= 0:
			at = args[flag + 1]
			shot = "screenshot_atlas_%s.png" % at
			_snap_rail(_rail_offset_of(at))
		var i := provinces.index_of(at)
		_mouse_pos = _camera.unproject_position(Vector3(provinces.labels[i].x, provinces.unlocked_top, provinces.labels[i].y))
		_update_hover()
	for i in 30:
		await get_tree().process_frame
	if GameManager != null and GameManager.is_touch_ui():
		shot = shot.replace(".png", "_touch.png")
	print("[Telemetry] FPS: %d | Draw Calls: %d | Primitives: %d | Video Mem: %.2f MB" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/.screenshots"))
	get_viewport().get_texture().get_image().save_png("res://tools/.screenshots/" + shot)
	print("✓ Captured atlas screenshot: res://tools/.screenshots/" + shot)
	get_tree().quit()
