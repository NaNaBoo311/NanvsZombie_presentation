extends Node3D

# TitleMenu — the game's front door, staged entirely in 3D: Eclipse over the
# Dragon Vein (docs/LORE.md). It belongs to the whole game, not to any one place.
#
# The Millennial Eclipse hangs in the sky (assets/shaders/TitleSky.gdshader). The
# Long Mạch leyline falls from it in an S through a cloud sea and ends in the Sacred
# Dragon Pearl, on a Warden's garden island that is the same however far the game
# grows (title_island_home.glb). Plants hold the line around the Pearl while seed
# shots fly at the horde, and spirits rise out of the clouds toward its light.
#
# Along the leyline, a chain of floating islands recedes to the eclipse. It is built
# from LevelDB.get_worlds(): one island per world, whose lantern is lit once the world
# is open and brightest once it is cleared, plus dark islands past the last world
# (MIN_ISLES). A new world therefore needs no title work, and the chain shows each
# player's journey. The whole chain is two draw calls at any world count.
#
# The eclipse dims the world, so light comes from it and from life: a strong gold
# rim from the corona, deep cool shade, and warm emissives (pearl, lanterns, shots) set
# against cool spirits. Motion lives in shaders (TitleEffects.gd); the home island's
# landmark and the posed vignette are baked to one mesh each (TitleBake.gd); after a
# short camera settle nothing runs per frame in script.
#
# --title-shot prints draw calls, primitives, boot-to-first-frame time and FPS,
# saves tools/.screenshots/screenshot_title_<w>x<h>[_touch].png and quits.

const TitleBake := preload("res://src/menus/title/TitleBake.gd")
const TitleEffects := preload("res://src/menus/title/TitleEffects.gd")
const LEYLINE_SHADER := preload("res://assets/shaders/TitleLeyline.gdshader")
const SPIRITS_SHADER := preload("res://assets/shaders/TitleSpirits.gdshader")
const SHOTS_SHADER := preload("res://assets/shaders/TitleShots.gdshader")

const SHOT_DIR := "res://tools/.screenshots"

## The home island's place on the leyline.
const HOME_POS := Vector3(21.0, 0.0, -6.0)
const HOME_YAW := -0.3
## At least this many islands in the chain, so a young game still reads as a long road.
const MIN_ISLES := 8
const MAX_ISLES := 40
const CHAIN_FROM_M := 96.0
const CHAIN_END_GAP_M := 330.0
const CHAIN_SIDE_M := 25.0
## Lantern colours. The chain's nearest island is the first world.
const BEACON_OPEN := Color(1.0, 0.46, 0.08)
const BEACON_CLEARED := Color(1.0, 0.82, 0.3)
const BEACON_LOCKED := Color(0.32, 0.26, 0.42)
## The Long Mạch centreline (world metres), after the points _leyline() adds at the
## eclipse: an S through the clouds that climbs the home island's back and ends in the
## Pearl's lotus, with the plants and the battle in front of it.
const LEYLINE := [
	Vector3(24.0, -9.0, -300.0),
	Vector3(-14.0, -7.0, -174.0), Vector3(-34.0, -9.0, -118.0),
	Vector3(-37.0, -6.0, -62.0), Vector3(-20.0, -6.0, -42.0), Vector3(1.0, 1.0, -22.0),
	Vector3(12.0, 1.2, -13.0), Vector3(21.0, 3.2, -6.0),
]
## How far along the view ray to the eclipse the ribbon starts.
const LEYLINE_FAR := 760.0
## Where it leaves the sky, in frame coordinates: just outside the eclipse's lower rim.
const LEYLINE_ORIGIN_XY := Vector2(0.20, 0.53)
## Spirit streams rising out of the cloud sea; most crest Saigon's east rim.
const SPIRITS := [
	{"centre": Vector3(38.0, -30.0, 4.0), "radius": 9.0, "count": 26, "rise": 32.0, "size": 3.8},
	{"centre": Vector3(26.0, -30.0, 30.0), "radius": 8.0, "count": 16, "rise": 30.0, "size": 3.4},
	{"centre": Vector3(-8.0, -30.0, 34.0), "radius": 10.0, "count": 10, "rise": 26.0, "size": 3.2},
	{"centre": Vector3(-10.0, -32.0, -82.0), "radius": 14.0, "count": 14, "rise": 34.0, "size": 5.0},
	{"centre": Vector3(14.0, -36.0, -200.0), "radius": 18.0, "count": 12, "rise": 40.0, "size": 7.0},
]
const SPIRIT_SEED := 1975
## The camera settles in from slightly farther back over INTRO_SEC, once.
const CAMERA_POS := Vector3(8.0, 34.0, 96.0)
const CAMERA_TARGET := Vector3(-2.0, -4.0, -60.0)
const CAMERA_FOV := 30.0
const INTRO_PULLBACK := 14.0
const INTRO_SEC := 2.6
## Composition was authored at 16:9. Narrower windows and phones hold the horizontal
## field: narrow ones see more sky and cloud, wide phones crop a little of both.
## Ultrawide desktops hold the vertical field and see more at the sides.
const TARGET_ASPECT := 16.0 / 9.0
## Haze and ink-line fade band, metres from the camera (InkOutlinePostProcess).
const HAZE_RANGE := Vector2(130.0, 420.0)
## Haze and ink tints for the eclipse twilight (the battle presets' are daylight).
const HAZE_COLOR := Color(0.55, 0.42, 0.58)
const INK_COLOR := Color(0.1, 0.06, 0.16, 0.9)
## Where the eclipse sits, in frame coordinates (-1..1, x right, y up).
const ECLIPSE_XY := Vector2(0.24, 0.70)
## Wider-than-16:9 screens (phones) turn the camera left by this many radians per
## unit of extra aspect, sliding the stage right of the title block, and shrink
## the title block by TITLE_SHRINK per unit (capped at 25%).
const WIDE_YAW := 0.17
const TITLE_SHRINK := 0.6
## ...and lower the camera view (metres per unit of extra aspect). Near objects
## shift more than far ones, so the battle lifts off the bottom edge while the
## far islands stay clear of the title block.
const WIDE_LIFT := 6.5

## The battle on the home island's front lawn, in island-local metres: plants west of
## the Pearl face east (+X), turned a little toward the camera, across a clear gap at
## the horde. The gap is the point: seeds fly through it. Units are hero-scaled and hold
## one pose: plants mid-shot, horde mid-stride.
const UNIT_SCALE := 3.0
const VIGNETTE := [
	{"name": "LotusShooter", "group": "Plants", "model": "res://assets/models/plants/lotus_shooter.glb",
		"pos": Vector3(-10.0, 0.0, 13.2), "yaw": 1.05, "clip": "attack", "at": 0.22, "lift": 0.0},
	{"name": "SauShooter", "group": "Plants", "model": "res://assets/models/plants/sau_shooter.glb",
		"pos": Vector3(-13.6, 0.0, 9.0), "yaw": 1.2, "clip": "attack", "at": 0.24, "lift": 0.0},
	{"name": "ArmoredCoconut", "group": "Plants", "model": "res://assets/models/plants/armored_coconut.glb",
		"pos": Vector3(-5.6, 0.0, 15.4), "yaw": 1.0, "clip": "idle", "at": 0.3, "lift": 0.0},
	{"name": "CycloZombie", "group": "Enemies", "model": "res://assets/models/enemies/cyclo_zombie.glb",
		"pos": Vector3(7.2, 0.0, 15.0), "yaw": -1.15, "clip": "walk", "at": 0.35, "lift": 0.0},
	{"name": "CastIronPotGhost", "group": "Enemies", "model": "res://assets/models/enemies/cast_iron_pot_ghost.glb",
		"pos": Vector3(14.0, 0.0, 8.0), "yaw": -1.2, "clip": "walk", "at": 0.6, "lift": 2.0},
	{"name": "BiaHoiZombie", "group": "Enemies", "model": "res://assets/models/enemies/bia_hoi_zombie.glb",
		"pos": Vector3(14.6, 0.0, 13.2), "yaw": -1.0, "clip": "walk", "at": 0.5, "lift": 0.0},
]
## Seed-shot lanes, island-local: from each shooter's mouth across the gap.
const SHOT_LANES := [
	[Vector3(-8.0, 3.4, 13.4), Vector3(5.8, 3.0, 14.8)],
	[Vector3(-11.6, 3.6, 9.4), Vector3(12.4, 3.2, 8.4)],
]
const SHOTS_PER_LANE := 4

const MENU_BUTTON_HEIGHT := 50.0
const MENU_SEPARATION := 12.0
const LOGO_POS := Vector2(40.0, 34.0)
const UI_FADE_DELAY := 0.5
const UI_FADE_SEC := 0.7

var _camera: Camera3D
var _sky: ShaderMaterial
var _ui: CanvasLayer
var _menu: VBoxContainer
var _primary: Button
var _title_block: Control
var _base_basis: Basis
var _lan_panel: Control = null
var _settings: SettingsPanel = null
var _ui_fade: Array[Control] = []
var _first_frame_ms := -1


func _ready() -> void:
	RenderingServer.frame_post_draw.connect(_on_first_frame, CONNECT_ONE_SHOT)
	_camera = $Camera3D
	_ui = $UI
	var env := ($WorldEnvironment as WorldEnvironment).environment
	_sky = env.sky.sky_material as ShaderMaterial
	_place_stage()
	_build_vignette()
	_bake_stage()
	_build_effects()
	_build_ui()
	_fade_in_ui()
	_apply_viewport_fov()
	get_viewport().size_changed.connect(_apply_viewport_fov)
	var ink := $InkOutline as InkOutlinePostProcess
	ink.set_colors(HAZE_COLOR, INK_COLOR)
	ink.set_haze_range(HAZE_RANGE.x, HAZE_RANGE.y)
	_play_intro()
	if "--title-shot" in OS.get_cmdline_user_args():
		_capture_shot()


func _on_first_frame() -> void:
	_first_frame_ms = Time.get_ticks_msec()


## Shards along the leyline and a fixed camera. The key is the corona itself: a strong,
## low gold rim from behind the stage on the eclipse's side, which leaves the camera
## faces in deep cool shade. The dim fill keeps those faces readable.
func _place_stage() -> void:
	var home := $Worlds/Home as Node3D
	home.position = HOME_POS
	home.rotation.y = HOME_YAW
	_camera.global_position = CAMERA_POS
	_camera.look_at(CAMERA_TARGET, Vector3.UP)
	_base_basis = _camera.global_basis
	var b := _base_basis
	_aim_light($MoonKey, b.x * 0.55 + Vector3.UP * 0.5 - b.z * 1.0)
	_aim_light($MoonFill, -b.x * 0.6 + Vector3.UP * 0.5 + b.z * 0.7)


## Points a directional light so it shines *from* `from_dir` toward the stage.
func _aim_light(light: DirectionalLight3D, from_dir: Vector3) -> void:
	var dir := -from_dir.normalized()
	light.global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)


func _build_vignette() -> void:
	var vignette := $Worlds/Home/Vignette as Node3D
	for spec: Dictionary in VIGNETTE:
		if not ResourceLoader.exists(spec["model"]):
			continue
		var model := (load(spec["model"]) as PackedScene).instantiate() as Node3D
		model.position.y = float(spec["lift"]) / UNIT_SCALE
		var unit := Node3D.new()
		unit.name = spec["name"]
		unit.position = spec["pos"]
		unit.rotation.y = spec["yaw"]
		unit.scale = Vector3.ONE * UNIT_SCALE
		unit.add_child(model)
		vignette.get_node(str(spec["group"])).add_child(unit)
		_pose(model, spec["clip"], spec["at"])


## Seek one clip to a held frame; bake() then freezes the pose into the mesh.
func _pose(root: Node, clip: String, at: float) -> void:
	for node in root.find_children("*", "AnimationPlayer", true, false):
		var ap := node as AnimationPlayer
		if not ap.has_animation(clip):
			continue
		ap.play(clip)
		ap.seek(at, true)
		ap.pause()
		return


## The title's one vertex-colour pass: the island keeps its two surfaces (terrain
## casts, water does not); the Pearl and the vignette fold to one mesh each.
func _bake_stage() -> void:
	var home := get_node("Worlds/Home") as Node3D
	var shard := home.get_node("Shard")
	TitleBake.enable_vertex_colors(shard)
	for node in shard.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
			if "Water" in str(mi.name) else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	TitleBake.bake(home, true, [home.get_node("Pearl")], "Landmarks")
	var vignette := home.get_node("Vignette") as Node3D
	TitleBake.bake(vignette, true, vignette.get_children())
	# The ink quad is a screen-space pass; it has nothing to cast.
	($InkOutline/QuadMeshInstance as GeometryInstance3D).cast_shadow = \
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_effects() -> void:
	var path := _leyline()
	add_child(TitleEffects.leyline(path, _shader_material(LEYLINE_SHADER)))
	add_child(TitleEffects.spirits(SPIRITS, _shader_material(SPIRITS_SHADER), SPIRIT_SEED))
	$Worlds/Home/Vignette.add_child(TitleEffects.shots(SHOT_LANES, SHOTS_PER_LANE, _shader_material(SHOTS_SHADER)))
	_build_chain(path)


## One island per world in the data, nearest first, then dark ones to MIN_ISLES.
func _build_chain(path: PackedVector3Array) -> void:
	var worlds: Array[Dictionary] = LevelDB.get_worlds()
	var preview := _preview_world_count()
	var count := clampi(preview if preview > 0 else worlds.size(), MIN_ISLES, MAX_ISLES)
	# The curve runs eclipse to Pearl; the chain counts outward from the Pearl.
	var outward := TitleEffects.curve(path)
	outward.reverse()
	var spots := TitleEffects.isle_spots(outward, count, CHAIN_FROM_M, CHAIN_END_GAP_M, CHAIN_SIDE_M)
	var glows: Array[Color] = []
	if preview > 0:
		for i in mini(preview, count):
			glows.append([BEACON_CLEARED, BEACON_OPEN, BEACON_LOCKED][i % 3])
	else:
		for i in mini(worlds.size(), count):
			glows.append(_beacon_color(str(worlds[i]["id"])))
	add_child(TitleEffects.isles(spots))
	add_child(TitleEffects.beacons(spots, glows))


## Dev capture only: `--title-chain <n>` stages n worlds cycling cleared, open and locked.
func _preview_world_count() -> int:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--title-chain")
	return int(args[i + 1]) if i >= 0 and i + 1 < args.size() else 0


func _beacon_color(world_id: String) -> Color:
	if not Progress.is_world_unlocked(world_id):
		return BEACON_LOCKED
	var total := LevelDB.get_level_ids(world_id).size()
	return BEACON_CLEARED if total > 0 and Progress.completed_count(world_id) >= total else BEACON_OPEN


## The centreline with its first points on the view ray to the eclipse's rim, so the
## ribbon visibly comes out of the eclipse. Held for 16:9: the corona hides the
## small offset on wider screens.
func _leyline() -> PackedVector3Array:
	var tan_v := tan(deg_to_rad(CAMERA_FOV * 0.5))
	var b := _base_basis
	var ray := -b.z + b.x * LEYLINE_ORIGIN_XY.x * tan_v * TARGET_ASPECT + b.y * LEYLINE_ORIGIN_XY.y * tan_v
	var points := PackedVector3Array([CAMERA_POS + ray * LEYLINE_FAR])
	points.append_array(PackedVector3Array(LEYLINE))
	return points


func _shader_material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


## One settle from slightly farther back. The camera moves only along its own
## view axis, so the sky's frame mapping (set from the basis) stays valid.
func _play_intro() -> void:
	var back := _camera.global_basis.z * INTRO_PULLBACK
	_camera.global_position = CAMERA_POS + back
	create_tween().tween_property(_camera, "global_position", CAMERA_POS, INTRO_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Holds the 16:9 horizontal field at any aspect and hands the sky the camera's
## frame (basis and half-FOV tangents), so the twilight band and the eclipse keep
## their place in the frame at any aspect ratio.
func _apply_viewport_fov() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var aspect := size.x / size.y
	var half := deg_to_rad(CAMERA_FOV * 0.5)
	var touch := GameManager.is_touch_ui()
	# Ultrawide monitors see more sky and cloud at the sides; only phones crop, because
	# they need the stage slid clear of the title block.
	var hold_width := aspect <= TARGET_ASPECT or touch
	_camera.fov = rad_to_deg(2.0 * atan(tan(half) * TARGET_ASPECT / aspect)) if hold_width else CAMERA_FOV
	var wide := maxf(aspect - TARGET_ASPECT, 0.0) if touch else 0.0
	_camera.global_basis = _base_basis.rotated(Vector3.UP, WIDE_YAW * wide)
	_camera.v_offset = -WIDE_LIFT * wide
	if _title_block != null:
		_title_block.scale = Vector2.ONE * (1.0 - minf(wide * TITLE_SHRINK, 0.25))
	var tan_v := tan(deg_to_rad(_camera.fov * 0.5))
	var b := _camera.global_basis
	_sky.set_shader_parameter("cam_forward", -b.z)
	_sky.set_shader_parameter("cam_right", b.x)
	_sky.set_shader_parameter("cam_up", b.y)
	_sky.set_shader_parameter("tan_v", tan_v)
	_sky.set_shader_parameter("tan_h", tan_v * aspect)
	# Frame coordinates stretch with the width, so pin the eclipse to the stage.
	var side_scale := 1.0 if hold_width else TARGET_ASPECT / aspect
	_sky.set_shader_parameter("eclipse_xy", Vector2(ECLIPSE_XY.x * side_scale, ECLIPSE_XY.y))


# ------------------------------------------------------------------- UI ---

func _build_ui() -> void:
	var scrim := TextureRect.new()
	scrim.name = "Scrim"
	scrim.texture = _scrim_texture()
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Bottom-left only: it shades the menu, never the morning sky behind the wordmark.
	scrim.anchor_left = 0.0
	scrim.anchor_top = 0.35
	scrim.anchor_right = 0.55
	scrim.anchor_bottom = 1.0
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(scrim)

	var canvas := HudCanvas.new()
	canvas.name = "HudCanvas"
	_ui.add_child(canvas)
	_ui_fade.append(canvas)

	# Emblem, wordmark and subtitle scale together on wide phones.
	var logo := TitleLogo.new()
	logo.name = "TitleBlock"
	logo.position = LOGO_POS
	_title_block = logo
	_ui.add_child(logo)
	_ui_fade.append(logo)

	_menu = VBoxContainer.new()
	_menu.name = "Menu"
	_menu.anchor_left = 0.0
	_menu.anchor_top = 1.0
	_menu.anchor_right = 0.0
	_menu.anchor_bottom = 1.0
	_menu.offset_left = 64.0
	_menu.offset_right = 344.0
	_menu.offset_bottom = -64.0
	_menu.add_theme_constant_override("separation", int(MENU_SEPARATION))
	_ui.add_child(_menu)
	_ui_fade.append(_menu)

	var primary_text := tr("Continue") if Progress.has_progress() else tr("New Game")
	_primary = _menu_button(primary_text, _on_primary, true)
	_primary.name = "PrimaryButton"
	_menu.add_child(_primary)
	var lan_button := _menu_button(tr("LAN Co-op"), _on_lan)
	lan_button.name = "LanButton"
	_menu.add_child(lan_button)
	var settings_button := _menu_button(tr("Settings"), _on_settings)
	settings_button.name = "SettingsButton"
	_menu.add_child(settings_button)
	if not GameManager.is_touch_ui():
		var quit_button := _menu_button(tr("Quit"), _on_quit)
		quit_button.name = "QuitButton"
		_menu.add_child(quit_button)
	# Anchor the stack to the bottom edge; hiding Quit on touch must not leave
	# a pocket of dead space above the home indicator.
	_menu.offset_top = _menu.offset_bottom \
		- float(_menu.get_child_count()) * MENU_BUTTON_HEIGHT \
		- float(_menu.get_child_count() - 1) * MENU_SEPARATION

	# Keyboard and gamepad players land on the primary action.
	if not GameManager.is_touch_ui():
		_primary.grab_focus.call_deferred()

	SafeArea.apply(_title_block)
	SafeArea.apply(_menu)


## A radial shade from the bottom-left corner, clear by the top and right edges.
func _scrim_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.0, 0.58))
	g.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.0, 1.0)
	tex.fill_to = Vector2(1.0, 1.0)
	return tex


func _menu_button(text: String, on_press: Callable, primary: bool = false) -> Button:
	var b := HudMenuButton.new()
	b.text = text
	b.primary = primary
	b.custom_minimum_size = Vector2(0.0, MENU_BUTTON_HEIGHT)
	b.pressed.connect(on_press)
	return b


func _on_settings() -> void:
	if _settings == null:
		_settings = SettingsPanel.new()
		_settings.name = "SettingsPanel"
		_ui.add_child(_settings)
	_settings.open()


## The stage settles first, then the logo and menu fade in over it.
func _fade_in_ui() -> void:
	for control in _ui_fade:
		control.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(UI_FADE_DELAY)
		tween.tween_property(control, "modulate:a", 1.0, UI_FADE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_primary() -> void:
	GameFlow.open_atlas()


func _on_lan() -> void:
	if _lan_panel == null:
		_lan_panel = LanPanel.new()
		_lan_panel.name = "LanPanel"
		_ui.add_child(_lan_panel)
	_lan_panel.open()


func _on_quit() -> void:
	get_tree().quit()


# --------------------------------------------------------------- capture ---

func _capture_shot() -> void:
	await get_tree().create_timer(maxf(INTRO_SEC, UI_FADE_DELAY + UI_FADE_SEC) + 0.4).timeout
	# Average over a 2 s window: Engine's FPS counter lags right after a load.
	var frames := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 2000000:
		await RenderingServer.frame_post_draw
		frames += 1
	var fps := frames / ((Time.get_ticks_usec() - t0) / 1000000.0)
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var texture_mb := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / (1024.0 * 1024.0)
	print("[TitleShot] draw_calls=%d primitives=%d boot_to_first_frame_ms=%d fps=%d texture_mem_mb=%.2f" % [
		draw_calls, primitives, _first_frame_ms, roundi(fps), texture_mb])
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("[TitleMenu] Title capture came back empty.")
		get_tree().quit(1)
		return
	var shot := "screenshot_title_%dx%d%s.png" % [img.get_width(), img.get_height(),
		"_touch" if GameManager.is_touch_ui() else ""]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	img.save_png("%s/%s" % [SHOT_DIR, shot])
	print("✓ Captured title screenshot: %s/%s" % [SHOT_DIR, shot])
	get_tree().quit()
