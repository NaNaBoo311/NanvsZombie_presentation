class_name CoreGameplayAtlas
extends "res://src/menus/atlas/AtlasMenu.gd"

# Section 02 — Core Gameplay, beat 1: the loop at three scales, staged on the real
# world atlas. It inherits the whole menu — rail camera, province picking, tooltips,
# the province board — and replaces only the chrome: the game's LAN / Shrine / home
# buttons go away, the section header takes the top-left, and the screen's legend
# sits over the map.
#
# Level-node clicks never start a battle here: an unlocked node opens the section's
# field (the HCMC sandbox), a locked one shakes the tooltip. The board itself is the
# real one, so the "minutes" scale is the actual level path.
#
# GameFlow.CORE_ATLAS_SCENE points here; the deck row 02 scene is this scene.

const SHOT_DIR := "res://tools/.screenshots"

var _screen: CoreGameplayScreen


func _ready() -> void:
	super._ready()
	_hide_game_chrome()
	_screen = CoreGameplayScreen.new()
	_screen.name = "CoreGameplayScreen"
	$UI.add_child(_screen)
	_screen.continue_pressed.connect(_on_continue)
	_screen.contents_pressed.connect(_on_contents)
	transition_finished.connect(_sync_screen)
	_sync_screen()
	_screen.play_intro()
	var args := OS.get_cmdline_user_args()
	if "--core-shot" in args:
		_capture_shot(args)


# ------------------------------------------------------------------ chrome ---

## The presentation is not the game's front end: no LAN room, no Jade shop, no
## title button, and the atlas's own title/back make room for the section header.
func _hide_game_chrome() -> void:
	_title.visible = false
	_back.visible = false
	if _lan_button != null:
		_lan_button.visible = false
	if _shrine_button != null:
		_shrine_button.visible = false
	if _title_button != null:
		_title_button.visible = false
	_hint.text = _atlas_hint()


func _atlas_hint() -> String:
	return tr("Drag or W/S to travel  •  Scroll or Q/E to zoom  •  Click Saigon")


## A flight or a province open/close just settled: keep the presentation chrome
## on top of whatever the atlas changed.
func _sync_screen() -> void:
	if _screen == null:
		return
	_back.visible = false
	var open := mode == Mode.PROVINCE
	_screen.set_province_mode(open)
	_hint.text = tr("Click Night 1 to enter the field  •  Esc / right-click to go back") \
		if open else _atlas_hint()


# ------------------------------------------------------------------- input ---

## Level nodes are the presentation's door into the field, never a real battle.
func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.PROVINCE and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and board != null:
			var index := board.node_at_screen(_camera, mb.position)
			if index >= 0:
				var level_id: String = board.level_ids[index]
				if Progress.is_level_unlocked(level_id):
					_playing_level_id = level_id
					Audio.play(Audio.UI_CLICK)
					GameFlow.open_core_field()
				else:
					_shake_tooltip()
				get_viewport().set_input_as_handled()
				return
	super._unhandled_input(event)


func _on_continue() -> void:
	GameFlow.open_core_field()


func _on_contents() -> void:
	GameFlow.open_contents()


# --------------------------------------------------------------- capture ---

## Dev capture only: `--core-shot --core-beat atlas [--core-province]`.
## The other beats are captured by CoreGameplayField.
func _capture_shot(args: PackedStringArray) -> void:
	var beat := "atlas"
	var i := args.find("--core-beat")
	if i >= 0 and i + 1 < args.size():
		beat = args[i + 1]
	if beat != "atlas":
		while GameFlow.busy:
			await get_tree().process_frame
		GameFlow.open_core_field()
		return
	if "--core-province" in args:
		open_province(START_PROVINCE)
		await transition_finished
	await get_tree().create_timer(1.2).timeout
	_screen.play_intro()
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("[CoreGameplayAtlas] Atlas capture came back empty.")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var shot := "screenshot_core_atlas%s_%dx%d.png" % [
		"_province" if "--core-province" in args else "",
		img.get_width(), img.get_height()]
	img.save_png("%s/%s" % [SHOT_DIR, shot])
	print("✓ Captured %s/%s" % [SHOT_DIR, shot])
	get_tree().quit()
