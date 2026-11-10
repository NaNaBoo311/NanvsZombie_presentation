extends Node

# Player preferences: music, effects and interface volume, and fullscreen. Loaded and
# applied at boot, saved to user://settings.cfg whenever one changes; a missing file
# means full volume in a window. F11 toggles fullscreen anywhere. Separate from
# Progress on purpose: wiping a save must not reset someone's volume. The window also
# gets a minimum size here, below which the HUD's top row no longer fits.

const PATH := "user://settings.cfg"
const SECTION := "settings"
const BUSES: Array[StringName] = [&"Music", &"SFX", &"UI"]
const MIN_WINDOW := Vector2i(1024, 600)

var _volume := {&"Music": 1.0, &"SFX": 1.0, &"UI": 1.0}
var _fullscreen := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for bus in BUSES:
			_volume[bus] = clampf(float(cfg.get_value(SECTION, str(bus), 1.0)), 0.0, 1.0)
		_fullscreen = bool(cfg.get_value(SECTION, "fullscreen", false))
	for bus in BUSES:
		_apply_volume(bus)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_min_size(MIN_WINDOW)
		_apply_fullscreen()


func volume(bus: StringName) -> float:
	return float(_volume.get(bus, 1.0))


func set_volume(bus: StringName, value: float) -> void:
	_volume[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)
	_save()


func is_fullscreen() -> bool:
	return _fullscreen


func set_fullscreen(on: bool) -> void:
	_fullscreen = on
	_apply_fullscreen()
	_save()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		set_fullscreen(not _fullscreen)
		get_viewport().set_input_as_handled()


func _apply_volume(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume(bus), 0.0001)))
		AudioServer.set_bus_mute(index, volume(bus) <= 0.0)


func _apply_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func _save() -> void:
	var cfg := ConfigFile.new()
	for bus in BUSES:
		cfg.set_value(SECTION, str(bus), volume(bus))
	cfg.set_value(SECTION, "fullscreen", _fullscreen)
	cfg.save(PATH)
