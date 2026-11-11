class_name CoreGameplayField
extends "res://src/battle/DioramaWorld.gd"

# Section 02's field: running Ho Chi Minh City (hcmc_01) with the 3 role cards
# presented at the start. Once the cards are dismissed ("Show me"), the game
# resumes normal gameplay exactly like the original NanVsZombie (briefing,
# setup countdown, waves, HUD progress, and victory).
#
# GameFlow.CORE_FIELD_SCENE points here.

const WORLD_ID := "hcmc"
const LEVEL_ID := "hcmc_01"
const SHOT_DIR := "res://tools/.screenshots"
const CAMERA_PRESET := "--storybook-axonometric"
const ROLES_ARM := 86.0

## Role cards are a first-entry moment: one per app run.
static var _roles_seen := false

var _layer: CanvasLayer
var _roles: RoleCards
var _home_camera_pose: Dictionary = {}


func _ready() -> void:
	GameManager.prepare_level(WORLD_ID, LEVEL_ID)
	Progress.mark_seen("intro:" + LEVEL_ID)
	_save_camera_home()

	var args := OS.get_cmdline_user_args()
	if "--core-shot" in args:
		super._ready()
		_capture_shot(args)
		return

	if _should_play_roles():
		GameManager.peaceful = true
		super._ready()
		_build_roles()
		_set_camera(ROLES_ARM)
		_roles.play()
	else:
		GameManager.peaceful = false
		super._ready()


func _should_play_roles() -> bool:
	return not _roles_seen or "--core-roles" in OS.get_cmdline_user_args()


func _build_roles() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "PresentationLayer"
	_layer.layer = 5
	add_child(_layer)

	_roles = RoleCards.new()
	_roles.name = "RoleCards"
	_roles.finished.connect(_on_roles_finished)
	_layer.add_child(_roles)


func _on_roles_finished() -> void:
	_roles_seen = true
	if is_instance_valid(_layer):
		_layer.queue_free()
	_restore_camera_home()
	GameManager.peaceful = false
	GameManager.start_round()


func _save_camera_home() -> void:
	if camera_rig == null:
		return
	_home_camera_pose = {
		"pos": camera_rig.global_position,
		"arm": float(camera_rig.get("arm_length")),
		"pitch": float(camera_rig.get("pitch_degrees")),
		"yaw": float(camera_rig.get("yaw_degrees")),
	}


func _restore_camera_home() -> void:
	if camera_rig == null or _home_camera_pose.is_empty():
		return
	camera_rig.global_position = _home_camera_pose["pos"]
	camera_rig.set("arm_length", _home_camera_pose["arm"])
	camera_rig.set("pitch_degrees", _home_camera_pose["pitch"])
	camera_rig.set("yaw_degrees", _home_camera_pose["yaw"])
	camera_rig.set("_target_arm_length", _home_camera_pose["arm"])
	camera_rig.set("_target_pitch", _home_camera_pose["pitch"])
	camera_rig.set("_target_yaw", _home_camera_pose["yaw"])


func _set_camera(arm: float) -> void:
	var preset: Dictionary = CameraPresets.by_flag(CAMERA_PRESET).duplicate()
	if preset.is_empty():
		return
	preset["arm"] = arm
	CameraPresets.apply(camera_rig, preset)


# ---------------------------------------------------------------- capture ---

func _capture_shot(args: PackedStringArray) -> void:
	var beat := "roles"
	var i := args.find("--core-beat")
	if i >= 0 and i + 1 < args.size():
		beat = args[i + 1]
	await get_tree().create_timer(0.8).timeout
	match beat:
		"gameplay":
			_roles_seen = true
			GameManager.peaceful = false
			GameManager.start_round()
			await get_tree().create_timer(1.5).timeout
		_:
			_roles_seen = true
			_build_roles()
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
