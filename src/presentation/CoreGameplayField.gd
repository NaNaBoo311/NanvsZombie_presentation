class_name CoreGameplayField
extends "res://src/battle/DioramaWorld.gd"

# Section 02's field: the real battle shell running Ho Chi Minh City as a peaceful
# sandbox. It prepares hcmc_01 and sets `peaceful` BEFORE the shell's _ready(), so
# start_round() lands in "sandbox" — the real map, night, HUD, seed bank and Pearl,
# with no story, briefing, waves or level progress. Nothing here reimplements a
# battle rule: placement, cost, cooldown, nav routes and the ghost's AI are the
# game's own.
#
# Presentation flow:
#   1. RoleCards    — three seeds revealed (Sacred Rice, Lotus Shooter, Armored Coconut).
#   2. SeedSelector — dev seed picker opens so presenter can pick loadout for the round.
#   3. Normal Play  — live placement with PlacementGuide checks, rotation, seed bank,
#                     and G key for manual enemy summoning.
#
# The section starts at 500 Rice Gems instead of the game's 10,000 so the cost check
# and Sacred Rice's payout are real; starting_sun is restored on the way out. Role
# cards play once per app run (--core-roles forces them again for a rehearsal).
#
# GameFlow.CORE_FIELD_SCENE points here.

const WORLD_ID := "hcmc"
const LEVEL_ID := "hcmc_01"
const DEMO_SUN := 500
const LOADOUT := ["sacred_rice", "lotus_shooter", "armored_coconut"]
const SHOT_DIR := "res://tools/.screenshots"
const CAMERA_PRESET := "--storybook-axonometric"

const ROLES_ARM := 86.0
const PLACEMENT_ARM := 66.0

## Role cards are a first-entry moment, not a loop: one per app run.
static var _roles_seen := false

var _layer: CanvasLayer
var _roles: RoleCards
var _guide: PlacementGuide
var _previous_sun := 10000


func _ready() -> void:
	GameManager.prepare_level(WORLD_ID, LEVEL_ID)
	GameManager.peaceful = true
	_previous_sun = GameManager.starting_sun
	GameManager.starting_sun = DEMO_SUN
	GameManager.set_seed_loadout(LOADOUT)
	super._ready()
	_build_presentation_layer()
	_remove_hint_slip()
	_set_camera(ROLES_ARM)
	var args := OS.get_cmdline_user_args()
	if "--core-shot" in args:
		_capture_shot(args)
		return
	if _should_play_roles():
		_play_roles()
	else:
		_start_normal_gameplay()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_seed_selector()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ layer ---

func _build_presentation_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "PresentationLayer"
	_layer.layer = 5
	add_child(_layer)

	_roles = RoleCards.new()
	_roles.name = "RoleCards"
	_roles.finished.connect(_on_roles_finished)
	_layer.add_child(_roles)

	_guide = PlacementGuide.new()
	_guide.name = "PlacementGuide"
	_guide.placement = get_node_or_null("PlacementManager") as PlacementManager
	_guide.continue_pressed.connect(_finish)
	_layer.add_child(_guide)


## The section's guide replaces the game's control slip; leaving both would say the
## same thing twice. Hide, never free: HudCanvas keeps its registration, and painting
## a freed widget spams errors every redraw.
func _remove_hint_slip() -> void:
	var hud := get_node_or_null("HUDLayer/HUD")
	if hud == null:
		return
	for child in hud.get_children():
		if child is HintSlip:
			(child as Control).visible = false


# ------------------------------------------------------------------ beats ---

func _should_play_roles() -> bool:
	return not _roles_seen or "--core-roles" in OS.get_cmdline_user_args()


func _play_roles() -> void:
	_roles_seen = true
	_roles.play()


func _on_roles_finished() -> void:
	_open_seed_selector()


func _open_seed_selector() -> void:
	var selector := _get_seed_selector()
	if selector == null:
		_start_normal_gameplay()
		return
	if not EventBus.seed_selector_toggled.is_connected(_on_seed_selector_toggled):
		EventBus.seed_selector_toggled.connect(_on_seed_selector_toggled)
	selector.open()


func _on_seed_selector_toggled(is_open: bool) -> void:
	if not is_open:
		if EventBus.seed_selector_toggled.is_connected(_on_seed_selector_toggled):
			EventBus.seed_selector_toggled.disconnect(_on_seed_selector_toggled)
		_start_normal_gameplay()


func _toggle_seed_selector() -> void:
	var selector := _get_seed_selector()
	if selector != null:
		selector.toggle()


func _get_seed_selector() -> SeedSelector:
	var hud := get_node_or_null("HUDLayer/HUD")
	if hud == null:
		return null
	return hud.get_node_or_null("SeedSelector") as SeedSelector


func _start_normal_gameplay() -> void:
	_set_camera(PLACEMENT_ARM)
	_guide.play_intro()


func _finish() -> void:
	var enemies := get_node_or_null("Enemies")
	if enemies != null:
		for child in enemies.get_children():
			child.queue_free()
	GameManager.house_health = GameManager.max_house_health
	GameManager.starting_sun = _previous_sun
	GameManager.clear_level()
	GameFlow.open_contents()


# ----------------------------------------------------------------- camera ---

## The game's own storybook axonometric, the framing its presentation captures use.
func _set_camera(arm: float) -> void:
	var preset: Dictionary = CameraPresets.by_flag(CAMERA_PRESET).duplicate()
	if preset.is_empty():
		return
	preset["arm"] = arm
	CameraPresets.apply(camera_rig, preset)


# ---------------------------------------------------------------- capture ---

## Dev capture only: `--core-shot --core-beat roles|selector|placement`.
func _capture_shot(args: PackedStringArray) -> void:
	var beat := "roles"
	var i := args.find("--core-beat")
	if i >= 0 and i + 1 < args.size():
		beat = args[i + 1]
	await get_tree().create_timer(0.8).timeout
	match beat:
		"selector":
			_roles_seen = true
			_roles.visible = false
			_open_seed_selector()
			await get_tree().create_timer(0.8).timeout
		"placement":
			_roles_seen = true
			_roles.visible = false
			_start_normal_gameplay()
			await get_tree().create_timer(0.6).timeout
			_pose_ghost()
			await get_tree().create_timer(1.0).timeout
		_:
			_roles_seen = true
			_roles.play()
			await get_tree().create_timer(3.4).timeout
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("[CoreGameplayField] Field capture came back empty.")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var shot := "screenshot_core_%s_%dx%d.png" % [beat, img.get_width(), img.get_height()]
	img.save_png("%s/%s" % [SHOT_DIR, shot])
	print("✓ Captured %s/%s" % [SHOT_DIR, shot])
	get_tree().quit()


## Put a Lotus Shooter ghost on a north tile so the guide's checks and cone show.
func _pose_ghost() -> void:
	var placement := get_node_or_null("PlacementManager") as PlacementManager
	if placement == null:
		return
	EventBus.plant_selected_for_placement.emit("lotus_shooter", GameManager.local_player_id())
	var cam := camera_rig.get("camera") as Camera3D
	if cam == null:
		return
	Input.warp_mouse(cam.unproject_position(placement.position_for_tile(Vector2i(2, -4))))
