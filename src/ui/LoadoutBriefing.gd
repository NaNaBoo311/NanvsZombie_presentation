class_name LoadoutBriefing
extends Control

# Scouting briefing: the pre-battle step where the player packs the seed bank.
# The loadout row is the real in-battle SeedBank in its normal top-left spot; this
# panel adds the plant pool drawer on the right: a dense PlantGrid of icon tiles that
# fits the whole pool on screen at once (tiles shrink as the pool grows, down to
# MIN_TILE, then the grid scrolls), a details box saying what the hovered plant does
# in words (no numbers: those stay in the unit JSON), and the Back-to-map /
# Strike-the-gong actions under it. A packed tile's icon flies into its bank slot.
# The header's Hide button slides the drawer off-screen so the player can study the
# map; a "Show plant pool" tab at the right edge brings it back.
# The 3D island stays live behind it under a scouting camera, with the level's active
# spawn regions drawn once as translucent amber areas with arrows (NavGrid.briefing_draw).
# During prepare GameManager.seed_loadout IS the draft: every pack/unpack calls
# set_seed_loadout() and the bank rebuilds on seed_loadout_changed. Confirm locks the
# loadout until Retry (which reopens this screen prefilled with the loadout just used).
# Signal-driven, no _process; all motion uses Tweens. Icons are baked ImageTextures
# via IconBaker, never live SubViewports (TRAPS.md#subviewport-container-flip).

const CameraPresets := preload("res://src/battle/CameraPresets.gd")
const SWEEP_YAW_DEG: float = 12.0
const MOVE_SEC: float = 1.2
const SWEEP_SEC: float = 4.8
const EXIT_SEC: float = 0.3
const GONG_SEC: float = 0.4
const HOME_SEC: float = 1.2
const FLY_SEC: float = 0.32
const DETAILS_MIN_HEIGHT: float = 84.0
# Pool drawer sizing: the biggest tile that still fits every plant in the drawer's
# maximum grid area wins; below MIN_TILE the grid scrolls instead.
const MAX_TILE: float = 84.0
## Columns a small pool prefers (bigger pools get ~1.6 x sqrt(n)), so compact tiles form a
## block instead of one wide row that covers the map.
const PREFERRED_COLUMNS: int = 5
const MIN_TILE: float = 56.0
const DRAWER_TOP: float = 100.0 # at least; _fit_below_bank() drops it under a lower bank
const BANK_GAP: float = 8.0
const DRAWER_BOTTOM_GAP: float = 16.0
const DRAWER_MAX_GRID_WIDTH: float = 860.0 # 14 columns at MIN_TILE; Hide shows the whole map
const DRAWER_MIN_WIDTH: float = 380.0 # room for the two action buttons
const TRIM_MARGIN: int = 14 # padding inside the drawer
const DRAWER_PAD: float = 32.0 # panel margins (2 x TRIM_MARGIN) + scroll bar
const DRAWER_CHROME_HEIGHT: float = 236.0 # header, details, warning, buttons, trim margins

var _drawer: PanelContainer = null
var _pool_scroll: ScrollContainer = null
var _grid: PlantGrid = null
var _pool_count: Label = null
var _bank_hint: Label = null
var _warning_label: Label = null
var _back_button: Button = null
var _start_button: Button = null
var _gong_flash: Panel = null
var _show_tab: Button = null # visible while the drawer is hidden
var _drawer_tween: Tween = null
var _details_name: Label = null
var _details_subtitle: Label = null
var _details_text: Label = null

var _card_style: StyleBoxFlat
var _plate_style: StyleBoxFlat

var _drawer_top: float = DRAWER_TOP
var _confirming: bool = false
var _cam_tween: Tween = null
var _hold_yaw: float = 0.0
var _sweep_done: bool = false
var _home_pose: Dictionary = {}
var _route_mesh: MeshInstance3D = null
var _map: MapDefinition = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_styles()
	_build_chrome()
	visible = false
	if EventBus:
		EventBus.round_state_changed.connect(_on_round_state_changed)
		EventBus.seed_loadout_changed.connect(_on_loadout_changed)
		EventBus.briefing_closed.connect(_on_briefing_closed)
		EventBus.map_loaded.connect(_on_map_loaded)


func _on_map_loaded(map: MapDefinition) -> void:
	_map = map


func _on_round_state_changed(state: String) -> void:
	if state == "prepare":
		_open()
	elif state == "setup" or state == "wave" or state == "won" or state == "lost" or state == "sandbox":
		if visible and not _confirming:
			# Closed by the round itself, not by this device's Start: the LAN guest,
			# whose briefing is read-only, closes when the host's setup begins. The
			# host flew home before confirming; fly this camera home too, or it stays
			# parked at the scouting pose instead of on the base.
			if state == "setup" or state == "wave":
				_fly_home()
			_hide_now()


func _on_loadout_changed(_ids: Array) -> void:
	if visible:
		_grid.set_packed(GameManager.seed_loadout)
		_refresh_footer()


func _on_briefing_closed() -> void:
	_hide_now()


func _hide_now() -> void:
	if is_instance_valid(_route_mesh):
		_route_mesh.queue_free()
	_route_mesh = null
	_confirming = false
	_show_tab.visible = false
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible or GameManager == null or GameManager.round_state != "prepare":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_skip_sweep()
		if _confirming:
			return
		var slot_idx := -1
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			slot_idx = event.keycode - KEY_1
		elif event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
			slot_idx = event.keycode - KEY_KP_1
		if slot_idx >= 0:
			var ids: Array = GameManager.seed_loadout
			if slot_idx < ids.size():
				GameManager.try_unpack_seed(str(ids[slot_idx]))
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_skip_sweep()


func _open() -> void:
	_confirming = false
	_sweep_done = false
	_show_tab.visible = false
	_fit_below_bank()
	_build_pool()
	show_details("")
	_grid.set_packed(GameManager.seed_loadout)
	_refresh_footer()
	_draw_routes()
	visible = true
	_play_enter()
	_fly_to_briefing()


## The bank's height and its safe-area inset vary, so the hint and drawer follow it.
func _fit_below_bank() -> void:
	var bank := _find_bank() as Control
	if bank == null:
		return
	var rect := bank.get_global_rect()
	_place(_bank_hint, 0.0, 0.0, 0.0, 0.0, rect.position.x, rect.end.y + 6.0)
	_drawer_top = maxf(DRAWER_TOP, rect.end.y + BANK_GAP)
	_place(_show_tab, 1.0, 0.0, 1.0, 0.0, -8.0, _drawer_top)


## Anchor a floating panel with explicit offsets (never .position: its setter
## back-converts through the current parent size, which parked the drawer and
## the intel strip off-screen). Zero-size offsets let the minimum size win; the
## control's grow direction decides which way it extends from the anchor.
func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = ol
	c.offset_bottom = ot


func _exit_tree() -> void:
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	if is_instance_valid(_route_mesh):
		_route_mesh.queue_free()
		_route_mesh = null


func _maps_for_camera() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		var cam: Node = scene.find_child("ThirdPersonCamera", true, false)
		if cam != null:
			return cam
	return null


func _briefing_pose() -> Dictionary:
	if _map != null and not (_map.briefing_camera as Dictionary).is_empty():
		return _map.briefing_camera
	return CameraPresets.by_flag("--wide-overview")


func _fly_to_briefing() -> void:
	var cam: Node = _maps_for_camera()
	if cam == null:
		return
	_home_pose = {
		"pos": cam.global_position,
		"arm": float(cam.get("arm_length")),
		"pitch": float(cam.get("pitch_degrees")),
		"yaw": float(cam.get("yaw_degrees")),
	}
	var pose := _briefing_pose()
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
	cam.set("target", null)
	_cam_tween = create_tween().set_parallel(true)
	_cam_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(cam, "global_position", pose["pos"], MOVE_SEC)
	_cam_tween.tween_property(cam, "_target_arm_length", float(pose["arm"]), MOVE_SEC)
	_cam_tween.tween_property(cam, "_target_pitch", float(pose["pitch"]), MOVE_SEC)
	_cam_tween.tween_property(cam, "_target_yaw", float(pose["yaw"]), MOVE_SEC)
	if (pose as Dictionary).has("fov") and cam.get("camera") != null:
		(cam.get("camera") as Camera3D).fov = float(pose["fov"])
	_hold_yaw = float(pose["yaw"]) + SWEEP_YAW_DEG
	_cam_tween.chain().tween_property(cam, "_target_yaw", _hold_yaw, SWEEP_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.chain().tween_callback(func() -> void: _sweep_done = true)


func _skip_sweep() -> void:
	if _sweep_done:
		return
	var cam: Node = _maps_for_camera()
	if cam == null or not is_instance_valid(cam) or _cam_tween == null or not _cam_tween.is_valid():
		_sweep_done = true
		return
	_cam_tween.kill()
	cam.set("_target_yaw", _hold_yaw)
	cam.set("yaw_degrees", _hold_yaw)
	cam.set("rotation_degrees", Vector3(float(cam.get("pitch_degrees")), _hold_yaw, 0.0))
	_sweep_done = true


## Fly back to the pose saved before the briefing (the base). Returns the
## tween so Start can wait for it, or null when there is nowhere to fly.
func _fly_home() -> Tween:
	var cam: Node = _maps_for_camera()
	if cam == null or _home_pose.is_empty():
		return null
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel(true)
	_cam_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(cam, "global_position", _home_pose["pos"], HOME_SEC)
	_cam_tween.tween_property(cam, "_target_arm_length", float(_home_pose["arm"]), HOME_SEC)
	_cam_tween.tween_property(cam, "_target_pitch", float(_home_pose["pitch"]), HOME_SEC)
	_cam_tween.tween_property(cam, "_target_yaw", float(_home_pose["yaw"]), HOME_SEC)
	return _cam_tween


## The camera pose the briefing returns to (empty before it first opens).
func home_pose() -> Dictionary:
	return _home_pose


func _draw_routes() -> void:
	if is_instance_valid(_route_mesh):
		_route_mesh.queue_free()
		_route_mesh = null
	if _map == null or GameManager == null or not GameManager.level_active:
		return
	var level: Dictionary = LevelDB.get_level(GameManager.current_level_id)
	var nav: NavGrid = _map.nav()
	if nav == null or nav.is_empty():
		return
	var active := nav.active_regions(level)
	if active.is_empty():
		return
	_route_mesh = nav.briefing_draw(_map, active)


func _on_start_pressed() -> void:
	if _confirming or GameManager == null or GameManager.round_state != "prepare":
		return
	# The host owns the loadout and the round clock (CONTRACT(lan-coop)): the
	# guest's briefing is read-only and closes when the host's setup starts.
	if GameManager.is_client():
		return
	if GameManager.seed_loadout.is_empty():
		return
	_confirming = true
	_start_button.disabled = true
	_back_button.disabled = true
	var out := _slide_drawer(true)
	_play_gong_flash()
	await out.finished
	if not is_instance_valid(self):
		return
	await get_tree().create_timer(GONG_SEC).timeout
	if not is_instance_valid(self):
		return
	var home := _fly_home()
	if home != null:
		await home.finished
	if not is_instance_valid(self):
		return
	GameManager.confirm_loadout(GameManager.seed_loadout.duplicate())


func _on_back_pressed() -> void:
	if _confirming:
		return
	GameFlow.back_to_province()


## Slide the drawer off the right edge (`out`) or back to its spot. Its offsets are
## equal (min-size placement, growing left), so both move together.
func _slide_drawer(out: bool) -> Tween:
	if _drawer_tween != null and _drawer_tween.is_valid():
		_drawer_tween.kill()
	var x := -8.0 + (_drawer.get_combined_minimum_size().x + 24.0 if out else 0.0)
	_drawer_tween = create_tween().set_parallel(true)
	_drawer_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN if out else Tween.EASE_OUT)
	_drawer_tween.tween_property(_drawer, "offset_left", x, EXIT_SEC)
	_drawer_tween.tween_property(_drawer, "offset_right", x, EXIT_SEC)
	return _drawer_tween


func _play_enter() -> void:
	var x := -8.0 + _drawer.get_combined_minimum_size().x + 24.0
	_drawer.offset_left = x
	_drawer.offset_right = x
	_slide_drawer(false)


## Hide the pool to look at the map, or bring it back.
func set_pool_hidden(hidden: bool) -> void:
	if _confirming:
		return
	_show_tab.visible = hidden
	_slide_drawer(hidden)


func _play_gong_flash() -> void:
	if not is_instance_valid(_gong_flash) or not is_instance_valid(_start_button):
		return
	_gong_flash.visible = true
	_gong_flash.global_position = _start_button.global_position + _start_button.size * 0.5 - _gong_flash.size * 0.5
	_gong_flash.scale = Vector2(0.5, 0.5)
	_gong_flash.modulate.a = 0.9
	_gong_flash.pivot_offset = _gong_flash.size * 0.5
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_gong_flash, "scale", Vector2(2.0, 2.0), GONG_SEC)
	tween.tween_property(_gong_flash, "modulate:a", 0.0, GONG_SEC)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(_gong_flash):
			_gong_flash.visible = false)


## Click on a pool tile: pack it (its icon flies into the bank) or, if it is already
## packed, unpack it. Refusals (bank full, forced plant) flash the tile red.
func _on_tile_pressed(seed_id: String) -> void:
	if _confirming or GameManager == null or GameManager.round_state != "prepare":
		return
	if GameManager.seed_loadout.has(seed_id):
		if not GameManager.try_unpack_seed(seed_id):
			_grid.flash_deny(seed_id) # forced: stays packed
		else:
			Audio.play(Audio.UI_CLICK)
		return
	if not GameManager.try_pack_seed(seed_id):
		_grid.flash_deny(seed_id)
		var bank: Node = _find_bank()
		if bank != null and bank.has_method("flash_bank_deny"):
			bank.flash_bank_deny()
		return
	Audio.play(Audio.UI_CLICK)
	_fly_to_bank(seed_id)


## Fly a copy of the tile's icon into the bank slot the plant just took. The bank
## rebuilt its slots this frame, so wait one frame for its layout before reading the
## slot rect; the slot hides its own icon until the copy lands, then pops.
func _fly_to_bank(seed_id: String) -> void:
	var bank: Node = _find_bank()
	var texture := _grid.icon_texture(seed_id)
	if bank == null or texture == null or not bank.has_method("slot_icon_global_rect"):
		return
	var from := _grid.tile_icon_global_rect(seed_id)
	await get_tree().process_frame
	if not is_instance_valid(bank) or not visible:
		return
	var idx := GameManager.seed_loadout.find(seed_id)
	var to: Rect2 = bank.slot_icon_global_rect(idx)
	if idx < 0 or to.size == Vector2.ZERO:
		return
	bank.hide_slot_icon(idx)
	var flyer := TextureRect.new()
	flyer.texture = texture
	flyer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flyer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flyer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flyer.top_level = true
	add_child(flyer)
	flyer.global_position = from.position
	flyer.size = from.size
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(flyer, "global_position", to.position, FLY_SEC)
	tween.tween_property(flyer, "size", to.size, FLY_SEC)
	await tween.finished
	if is_instance_valid(flyer):
		flyer.queue_free()
	if is_instance_valid(bank) and GameManager.seed_loadout.find(seed_id) == idx:
		bank.land_slot(idx)


## Fill the details box with what `seed_id` does; "" shows the prompt.
func show_details(seed_id: String) -> void:
	if _details_name == null:
		return
	var unit := BalanceDB.get_unit(seed_id) if not seed_id.is_empty() else {}
	if unit.is_empty():
		_details_name.text = tr("Hover a plant to see what it does.")
		_details_name.add_theme_color_override("font_color", UiPalette.HUD_INK)
		_details_subtitle.visible = false
		_details_text.visible = false
		return
	_details_name.text = tr(str(unit.get("name", seed_id)))
	_details_name.add_theme_color_override("font_color", UiPalette.HUD_INK)
	_details_subtitle.text = tr(str(unit.get("subtitle", "")))
	_details_subtitle.visible = not _details_subtitle.text.is_empty()
	var what := " ".join(_plant_behaviour(unit))
	_details_text.text = what
	_details_text.visible = not what.is_empty()


## What a plant does, in words only (no numbers), keyed off which "numbers" its
## unit JSON defines. A plant with none of these keys shows its name and subtitle.
func _plant_behaviour(unit: Dictionary) -> PackedStringArray:
	var n: Dictionary = unit.get("numbers", {})
	var lines := PackedStringArray()
	if n.has("damage") and n.has("vision_range"):
		lines.append(tr("Shoots enemies in front of it."))
	if n.has("gem_value"):
		lines.append(tr("Makes sun over time."))
	if n.has("blast_radius"):
		lines.append(tr("Explodes when an enemy comes close, wiping out everything nearby."))
	if n.has("bury_duration"):
		lines.append(tr("Needs a moment underground before it is armed."))
	return lines


func _find_bank() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("SeedBank", true, false)


## Start is off while the bank is empty, and the line above the buttons says why.
func _refresh_footer() -> void:
	var empty: bool = GameManager == null or GameManager.seed_loadout.is_empty()
	var guest: bool = GameManager != null and GameManager.is_client()
	_start_button.disabled = empty or _confirming or guest
	_start_button.text = tr("Waiting for host") if guest else tr("Strike the gong")
	_warning_label.text = tr("The host picks the loadout.") if guest else tr("Pack at least one plant to start.")
	_warning_label.visible = empty or guest


## Fill the grid with the level's pool in seed-bank order and size the drawer: the
## largest tile (MAX_TILE down to MIN_TILE) at which every plant fits the drawer's
## maximum grid area; past that the grid scrolls. The drawer is only as wide as the
## columns it needs, so a small pool leaves the island in view.
func _build_pool() -> void:
	var entries: Array[Dictionary] = []
	if GameManager != null and GameManager.level_active:
		var pool: Array[String] = LevelDB.seed_rules(GameManager.current_level_id)["pool"]
		for entry in BalanceDB.seeds():
			if pool.has(str(entry["id"])):
				entries.append(entry)
	var n := maxi(entries.size(), 1)
	var view := get_viewport_rect().size
	var max_w := DRAWER_MAX_GRID_WIDTH
	var max_h := maxf(view.y - _drawer_top - DRAWER_BOTTOM_GAP - DRAWER_CHROME_HEIGHT, MIN_TILE)
	var gap := PlantGrid.GAP
	var t := MAX_TILE
	var cols := 1
	while true:
		cols = maxi(1, floori((max_w + gap) / (t + gap)))
		cols = mini(cols, maxi(PREFERRED_COLUMNS, ceili(sqrt(float(n)) * 1.6)))
		var rows := ceili(float(n) / float(cols))
		if rows * (t + gap) - gap <= max_h or t <= MIN_TILE:
			break
		t = maxf(t - 2.0, MIN_TILE)
	cols = mini(cols, n)
	_grid.setup(entries, t, cols)
	var rows_needed := ceili(float(n) / float(cols))
	var grid_w := cols * (t + gap) - gap
	# Show whole rows only: a half-cut row above the scroll looks broken.
	var rows_fit := maxi(1, floori((max_h + gap) / (t + gap)))
	_pool_scroll.custom_minimum_size = Vector2(maxf(grid_w + 12.0, DRAWER_MIN_WIDTH - DRAWER_PAD),
		mini(rows_needed, rows_fit) * (t + gap) - gap)
	_pool_count.text = tr("%d plants") % entries.size()
	_place(_drawer, 1.0, 0.0, 1.0, 0.0, -8.0, _drawer_top)


func _setup_styles() -> void:
	# Lacquer dialogs (UiPalette), the same look as the seed bank above it.
	_card_style = UiPalette.lacquer_panel(0)
	_plate_style = UiPalette.lacquer_box(UiPalette.HUD_LACQUER_BOT, Color(UiPalette.HUD_GOLD, 0.45), 6, 1, 10)
	_plate_style.content_margin_top = 6
	_plate_style.content_margin_bottom = 8


func _flat(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := UiPalette.hud_label(font_size, color)
	label.z_index = 0
	parent.add_child(label)
	return label


## Smaller padding for a small header button.
func _tight(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb: StyleBoxFlat = button.get_theme_stylebox(state).duplicate()
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		button.add_theme_stylebox_override(state, sb)


func _build_chrome() -> void:
	# How to edit the bank, right under it (nothing else says slots are clickable).
	_bank_hint = UiPalette.hud_label(14, UiPalette.HUD_INK_SOFT)
	_bank_hint.z_index = 0
	_bank_hint.name = "BankHint"
	_bank_hint.text = tr("Click a packed slot or press 1-9 to unpack it.")
	var hint_plate := UiPalette.lacquer_box(UiPalette.HUD_LACQUER_BOT, Color(UiPalette.HUD_GOLD, 0.45), 4, 1, 10)
	hint_plate.content_margin_top = 3
	hint_plate.content_margin_bottom = 3
	_bank_hint.add_theme_stylebox_override("normal", hint_plate)
	_place(_bank_hint, 0.0, 0.0, 0.0, 0.0, 128.0, 90.0)
	add_child(_bank_hint)

	# Plant pool drawer: top right, grows left and down to fit its grid; the details
	# box and the two actions sit under the grid.
	_drawer = PanelContainer.new()
	_drawer.name = "PoolDrawer"
	_drawer.add_theme_stylebox_override("panel", _card_style)
	_drawer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_place(_drawer, 1.0, 0.0, 1.0, 0.0, -8.0, DRAWER_TOP)
	add_child(_drawer)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", TRIM_MARGIN)
	margin.add_theme_constant_override("margin_top", TRIM_MARGIN)
	margin.add_theme_constant_override("margin_right", TRIM_MARGIN)
	margin.add_theme_constant_override("margin_bottom", TRIM_MARGIN)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(outer)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(header)
	var pool_title := _label(header, 22, UiPalette.HUD_ACCENT)
	pool_title.text = tr("Plant pool")
	pool_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pool_count = _label(header, 14, UiPalette.HUD_INK_SOFT)
	_pool_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var hide_button := Button.new()
	hide_button.text = tr("Hide")
	hide_button.tooltip_text = tr("Hide the plant pool to look at the map.")
	hide_button.focus_mode = Control.FOCUS_NONE
	UiPalette.lacquer_button(hide_button, false, false, 14)
	_tight(hide_button)
	header.add_theme_constant_override("separation", 10)
	header.add_child(hide_button)
	hide_button.pressed.connect(set_pool_hidden.bind(true))
	_pool_scroll = ScrollContainer.new()
	_pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pool_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(_pool_scroll)
	_grid = PlantGrid.new()
	_grid.name = "PlantGrid"
	_pool_scroll.add_child(_grid)
	_grid.tile_pressed.connect(_on_tile_pressed)
	_grid.tile_hovered.connect(func(seed_id: String) -> void:
		if not seed_id.is_empty():
			show_details(seed_id))

	var details := PanelContainer.new()
	details.name = "PlantDetails"
	details.add_theme_stylebox_override("panel", _plate_style)
	details.custom_minimum_size = Vector2(0, DETAILS_MIN_HEIGHT)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(details)
	var details_box := VBoxContainer.new()
	details_box.add_theme_constant_override("separation", 1)
	details_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(details_box)
	_details_name = _label(details_box, 19, UiPalette.HUD_INK)
	_details_subtitle = _label(details_box, 14, UiPalette.HUD_INK_SOFT)
	_details_text = _label(details_box, 15, UiPalette.HUD_INK)
	_details_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_warning_label = _label(outer, 14, UiPalette.HUD_DANGER_TEXT)
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_warning_label.visible = false
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(buttons)
	_back_button = Button.new()
	_back_button.text = tr("Back to map")
	_back_button.custom_minimum_size = Vector2(130, 44)
	_back_button.focus_mode = Control.FOCUS_NONE
	UiPalette.lacquer_button(_back_button, false, false, 16)
	buttons.add_child(_back_button)
	_back_button.pressed.connect(_on_back_pressed)
	_start_button = Button.new()
	_start_button.text = tr("Strike the gong!")
	_start_button.custom_minimum_size = Vector2(210, 48)
	_start_button.focus_mode = Control.FOCUS_NONE
	UiPalette.lacquer_button(_start_button, true, false, 19)
	buttons.add_child(_start_button)
	_start_button.pressed.connect(_on_start_pressed)

	# Shown while the drawer is hidden: brings the plant pool back.
	_show_tab = Button.new()
	_show_tab.name = "ShowPoolTab"
	_show_tab.text = tr("Show plant pool")
	_show_tab.focus_mode = Control.FOCUS_NONE
	UiPalette.lacquer_button(_show_tab, true, false, 16)
	_show_tab.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_place(_show_tab, 1.0, 0.0, 1.0, 0.0, -8.0, DRAWER_TOP)
	_show_tab.visible = false
	add_child(_show_tab)
	_show_tab.pressed.connect(set_pool_hidden.bind(false))

	_gong_flash = Panel.new()
	_gong_flash.custom_minimum_size = Vector2(90, 90)
	_gong_flash.size = Vector2(90, 90)
	var flash_sb := _flat(Color(1.0, 0.75, 0.30, 0.35), Color(1.0, 0.85, 0.45, 0.9), 3, 45)
	_gong_flash.add_theme_stylebox_override("panel", flash_sb)
	_gong_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gong_flash.visible = false
	add_child(_gong_flash)
