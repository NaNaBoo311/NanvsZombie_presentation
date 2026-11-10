class_name ConceptVision
extends "res://src/menus/title/TitleMenu.gd"

# Section 01 — Concept & Vision, staged over the game's title diorama. It inherits
# the whole title stage (eclipse, leyline, island chain, Pearl, effects and the
# camera settle) and replaces only the UI with ConceptScreen. The world carousel
# is a separate display stage far from the title diorama; when the world exhibit
# is live the camera travels there, and returns to the title pose for every other
# exhibit. Both stays are one tween, so the screen is idle once it settles.
#
# The screen owns the copy and the four exhibits; this script owns the stage:
# the camera poses, the carousel, and the hand-offs to the contents page and the
# playable atlas. GameFlow.CONCEPT_SCENE points here.

const CARRY_EYE := Vector3(0.0, 20.0, 58.0)
const CARRY_TARGET := Vector3(-8.0, 7.0, 0.0)
const CARRY_ECLIPSE := Vector2(0.62, 0.66)
const CARRY_SEC := 0.8

var _screen: ConceptScreen
var _carousel: ConceptCarousel
var _camera_tween: Tween
var _carousel_active := false
var _home_transform := Transform3D.IDENTITY


func _ready() -> void:
	super()
	_carousel = ConceptCarousel.new()
	_carousel.name = "WorldCarousel"
	add_child(_carousel)
	var args := OS.get_cmdline_user_args()
	if "--concept-shot" in args:
		_capture_concept_shot(args)


func _build_ui() -> void:
	_screen = ConceptScreen.new()
	_screen.name = "ConceptScreen"
	_ui.add_child(_screen)
	_screen.stage_focus_requested.connect(_on_stage_focus)
	_screen.world_selected.connect(_on_world_selected)
	_screen.enter_game_pressed.connect(_on_enter_game)
	_screen.contents_pressed.connect(_on_contents)


func _fade_in_ui() -> void:
	if _screen != null:
		_screen.play_intro()


## Keep the title's settle, but remember where it lands: the carousel goes back
## to exactly this pose. The base class only tweens the position, so the basis is
## already final from _apply_viewport_fov().
func _play_intro() -> void:
	var home := Transform3D(_camera.global_basis, CAMERA_POS)
	_home_transform = home
	_camera.global_transform = Transform3D(home.basis, CAMERA_POS + home.basis.z * INTRO_PULLBACK)
	_camera_tween = create_tween()
	_camera_tween.tween_property(_camera, "global_position", CAMERA_POS, INTRO_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The title's aspect handling, except while the carousel is on screen: there the
## camera belongs to the display stage and holds the shard's width instead.
func _apply_viewport_fov() -> void:
	if _carousel_active:
		_apply_carousel_view()
		return
	super._apply_viewport_fov()
	_home_transform = Transform3D(_camera.global_basis, CAMERA_POS)


func _on_stage_focus(active: bool) -> void:
	if active == _carousel_active:
		return
	_carousel_active = active
	_move_camera(_carousel_transform() if active else _home_transform, CARRY_SEC)


func _on_world_selected(index: int) -> void:
	if _carousel != null:
		_carousel.set_world(index)


func _on_enter_game() -> void:
	GameFlow.open_atlas()


func _on_contents() -> void:
	GameFlow.open_contents()


func _move_camera(target: Transform3D, seconds: float) -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.tween_property(_camera, "global_position", target.origin, seconds) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(_camera, "quaternion",
		target.basis.get_rotation_quaternion(), seconds) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.finished.connect(_apply_viewport_fov, CONNECT_ONE_SHOT)


func _carousel_transform() -> Transform3D:
	var eye := ConceptCarousel.ORIGIN + CARRY_EYE
	var target := ConceptCarousel.ORIGIN + CARRY_TARGET
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)


func _apply_carousel_view() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var aspect := size.x / size.y
	var half := deg_to_rad(CAMERA_FOV * 0.5)
	var hold_width := aspect <= TARGET_ASPECT
	_camera.fov = rad_to_deg(2.0 * atan(tan(half) * TARGET_ASPECT / aspect)) if hold_width else CAMERA_FOV
	_camera.global_transform = _carousel_transform()
	_camera.v_offset = 0.0
	var tan_v := tan(deg_to_rad(_camera.fov * 0.5))
	var b := _camera.global_basis
	_sky.set_shader_parameter("cam_forward", -b.z)
	_sky.set_shader_parameter("cam_right", b.x)
	_sky.set_shader_parameter("cam_up", b.y)
	_sky.set_shader_parameter("tan_v", tan_v)
	_sky.set_shader_parameter("tan_h", tan_v * aspect)
	var side_scale := 1.0 if hold_width else TARGET_ASPECT / aspect
	_sky.set_shader_parameter("eclipse_xy", Vector2(CARRY_ECLIPSE.x * side_scale, CARRY_ECLIPSE.y))


## Dev capture only: `--concept-shot [--concept-exhibit n]` saves the screen and
## quits, like --title-shot does for the cover.
func _capture_concept_shot(args: PackedStringArray) -> void:
	await get_tree().create_timer(1.2).timeout
	var exhibit := args.find("--concept-exhibit")
	if exhibit >= 0 and exhibit + 1 < args.size():
		_screen.show_exhibit(int(args[exhibit + 1]))
		await get_tree().create_timer(CARRY_SEC + 0.5).timeout
	else:
		await get_tree().create_timer(maxf(INTRO_SEC, 1.2)).timeout
	var world := args.find("--concept-world")
	if world >= 0 and world + 1 < args.size():
		_screen.call("_select_world", int(args[world + 1]))
		await get_tree().create_timer(CARRY_SEC + 0.4).timeout
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("[ConceptVision] Concept capture came back empty.")
		get_tree().quit(1)
		return
	var shot := "screenshot_concept_%dx%d%s.png" % [img.get_width(), img.get_height(),
		"_touch" if GameManager.is_touch_ui() else ""]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	img.save_png("%s/%s" % [SHOT_DIR, shot])
	print("✓ Captured concept screenshot: %s/%s" % [SHOT_DIR, shot])
	get_tree().quit()
