extends Node

# Audio — the only owner of sound playback. One autoload holds three players
# (Music / SFX / UI buses); gameplay sounds are direct Audio.play() calls on the
# exact line where the audible thing happens, music and the opening cue follow
# flow state via EventBus, buttons wire automatically via node_added. No _process,
# no timers: cooldowns compare Time.get_ticks_msec(), fades are tweens.
# CONTRACT(add-sound): a sound is its file + .import flags, a SOUNDS row and a play() call.

const UI_CLICK := &"ui_click"
const SEEDBANK_PICK := &"seedbank_pick"
const PLANT_PLACE := &"plant_place"
const SHOVEL_REMOVE := &"shovel_remove"
const RICE_GEM_COLLECT := &"rice_gem_collect"
const LOTUS_SHOOT := &"lotus_shoot"
const BOUGAINVILLEA_ATTACK := &"bougainvillea_attack"
const ENEMY_EAT := &"enemy_eat"
const BATTLE_START := &"battle_start"

const MUSIC_DIR := "res://assets/audio/music/"
const ATLAS_TRACK := &"atlas_theme"
## Battle track of a world whose JSON has no "music" ("" = silence).
const DEFAULT_BATTLE_TRACK := &""
const MUSIC_DB := -3.0
const SILENT_DB := -40.0
const MUSIC_FADE_IN := 0.4
const SFX_POLYPHONY := 16
const UI_POLYPHONY := 6
## Button meta: the sound id its press plays ("" = none). Absent = UI_CLICK.
const CLICK_META := &"click_sfx"

const SOUNDS := {
	UI_CLICK: {"streams": [preload("res://assets/audio/sfx/ui/ui_click_01.wav")],
		"ui": true, "volume_db": -12.0, "pitch_jitter": 0.0, "max_voices": 2, "cooldown_ms": 50, "offset": 0.0},
	SEEDBANK_PICK: {"streams": [preload("res://assets/audio/sfx/ui/seedbank_pick_01.wav")],
		"ui": true, "volume_db": -10.0, "pitch_jitter": 0.0, "max_voices": 2, "cooldown_ms": 50, "offset": 0.0},
	PLANT_PLACE: {"streams": [preload("res://assets/audio/sfx/plants/plant_place_01.wav")],
		"ui": false, "volume_db": -9.0, "pitch_jitter": 0.04, "max_voices": 2, "cooldown_ms": 60, "offset": 0.0},
	SHOVEL_REMOVE: {"streams": [preload("res://assets/audio/sfx/ui/shovel_remove_01.wav")],
		"ui": false, "volume_db": -8.0, "pitch_jitter": 0.04, "max_voices": 2, "cooldown_ms": 100, "offset": 0.0},
	RICE_GEM_COLLECT: {"streams": [preload("res://assets/audio/sfx/ui/rice_gem_collect_01.wav"), preload("res://assets/audio/sfx/ui/rice_gem_collect_02.wav")],
		"ui": false, "volume_db": -10.0, "pitch_jitter": 0.05, "max_voices": 3, "cooldown_ms": 60, "offset": 0.0},
	LOTUS_SHOOT: {"streams": [preload("res://assets/audio/sfx/plants/lotus_shooter_shoot_01.wav")],
		"ui": false, "volume_db": -14.0, "pitch_jitter": 0.06, "max_voices": 4, "cooldown_ms": 50, "offset": 0.0},
	BOUGAINVILLEA_ATTACK: {"streams": [preload("res://assets/audio/sfx/plants/bougainvillea_net_attack_01.wav")],
		"ui": false, "volume_db": -10.0, "pitch_jitter": 0.06, "max_voices": 2, "cooldown_ms": 120, "offset": 0.0},
	ENEMY_EAT: {"streams": [preload("res://assets/audio/sfx/enemies/enemy_eat_01.wav")],
		"ui": false, "volume_db": -14.0, "pitch_jitter": 0.08, "max_voices": 2, "cooldown_ms": 450, "offset": 0.12},
	BATTLE_START: {"streams": [preload("res://assets/audio/sfx/ui/battle_start.wav")],
		"ui": false, "volume_db": -6.0, "pitch_jitter": 0.0, "max_voices": 1, "cooldown_ms": 1000, "offset": 0.0},
}

var music_starts: int = 0 # times a track actually (re)started; tests read it
var _music: AudioStreamPlayer
var _music_tween: Tween
var _track: StringName = &"" # requested ("" = silence)
var _loaded: StringName = &"" # the track _music holds now ("" = stopped)
var _sfx: AudioStreamPlaybackPolyphonic
var _ui: AudioStreamPlaybackPolyphonic
var _voices := {} # id -> Array of live voice ids
var _last_ms := {} # id -> ticks of the last play
var _play_counts := {} # id -> plays that passed the cooldown (and, un-muted, got a voice); tests
var _silent := false # automated run: bookkeeping only, no player is ever started


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = _is_automated_run()
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	_music.volume_db = SILENT_DB
	add_child(_music)
	if not _silent:
		_sfx = _make_voices(&"SFX", SFX_POLYPHONY, Node.PROCESS_MODE_PAUSABLE)
		_ui = _make_voices(&"UI", UI_POLYPHONY, Node.PROCESS_MODE_ALWAYS)
	get_tree().node_added.connect(_on_node_added)
	EventBus.flow_transition_started.connect(_on_flow_transition)
	EventBus.level_selected.connect(_on_level_selected)
	EventBus.wave_started.connect(_on_wave_started)
	for w in LevelDB.get_worlds():
		var track := str(w.get("music", ""))
		if track.is_empty():
			continue
		if not ResourceLoader.exists(MUSIC_DIR + track + ".ogg"):
			push_warning("[Audio] World %s names missing music \"%s\" in %s." % [str(w.get("id", "")), track, MUSIC_DIR])


func _is_automated_run() -> bool:
	for arg in OS.get_cmdline_user_args():
		if (arg == "--mute" or arg == "--title-shot" or arg.ends_with("-test")
				or arg in GameFlow.BATTLE_FLAGS):
			return true
	return false


func _make_voices(bus: StringName, polyphony: int, mode: Node.ProcessMode) -> AudioStreamPlaybackPolyphonic:
	var player := AudioStreamPlayer.new()
	var stream := AudioStreamPolyphonic.new()
	stream.polyphony = polyphony
	player.stream = stream
	player.bus = bus
	player.process_mode = mode # explicit: a child would inherit ALWAYS
	add_child(player) # in the tree first,
	player.play() # then playing,
	return player.get_stream_playback() as AudioStreamPlaybackPolyphonic # then the playback


func play(id: StringName) -> void:
	var s: Dictionary = SOUNDS.get(id, {})
	if s.is_empty():
		push_error("[Audio] Unknown sound id \"%s\" (CONTRACT(add-sound))." % id)
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(id, -1000000)) < int(s["cooldown_ms"]):
		return
	if not _silent:
		var voices := _ui if s["ui"] else _sfx
		var live: Array = _voices.get_or_add(id, [])
		for i in range(live.size() - 1, -1, -1):
			if not voices.is_stream_playing(live[i]):
				live.remove_at(i)
		if live.size() >= int(s["max_voices"]):
			return
		var streams: Array = s["streams"]
		var jitter: float = s["pitch_jitter"]
		var voice := voices.play_stream(streams[randi() % streams.size()], s["offset"], s["volume_db"],
			1.0 + randf_range(-jitter, jitter), AudioServer.PLAYBACK_TYPE_DEFAULT, &"UI" if s["ui"] else &"SFX")
		if voice == AudioStreamPlaybackPolyphonic.INVALID_ID:
			return
		live.append(voice)
	_last_ms[id] = now
	_play_counts[id] = play_count(id) + 1


func play_count(id: StringName) -> int:
	return int(_play_counts.get(id, 0))


func play_music(track: StringName) -> void:
	if track == _track:
		return # retry / next level / R-restart of the same world: keep playing, no restart
	_track = track
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	if _loaded != &"" and track == _loaded: # its fade-out was still in flight: come back up
		_music_tween.tween_property(_music, "volume_db", MUSIC_DB, MUSIC_FADE_IN)
		return
	if _loaded != &"":
		_music_tween.tween_property(_music, "volume_db", SILENT_DB, GameFlow.FADE_OUT)
	_music_tween.tween_callback(_swap_music)


func _swap_music() -> void: # reads _track now, so the latest request wins
	_music.stop()
	_loaded = &""
	if _track == &"":
		return
	var stream := load(MUSIC_DIR + _track + ".ogg") as AudioStream
	if stream == null:
		push_warning("[Audio] No music file for track \"%s\" in %s." % [_track, MUSIC_DIR])
		return
	_music.stream = stream
	_music.volume_db = SILENT_DB
	if not _silent:
		_music.play()
	_loaded = _track
	music_starts += 1
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", MUSIC_DB, MUSIC_FADE_IN)


func current_track() -> StringName:
	return _track


func world_track(world_id: String) -> StringName:
	var id := str(LevelDB.get_world(world_id).get("music", ""))
	return StringName(id) if not id.is_empty() else DEFAULT_BATTLE_TRACK


func _on_flow_transition(kind: String) -> void:
	_stop_gameplay_voices()
	play_music(ATLAS_TRACK if kind == "menu" else &"")


func _on_level_selected(world_id: String, _level_id: String) -> void:
	_stop_gameplay_voices()
	play_music(world_track(world_id))


## The battle is being left or restarted: its sounds must not carry over. Never the UI voices —
## the click that caused the transition is one of them.
func _stop_gameplay_voices() -> void:
	if _silent:
		return
	for id: StringName in _voices:
		if not SOUNDS[id]["ui"]:
			for voice: int in _voices[id]:
				_sfx.stop_stream(voice)
			_voices[id].clear()


func _on_wave_started(wave_index: int) -> void:
	if wave_index == 0:
		play(BATTLE_START)


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta(&"audio_wired"):
		node.set_meta(&"audio_wired", true) # a button can leave and re-enter the tree
		(node as BaseButton).pressed.connect(_on_button_pressed.bind(node))


func _on_button_pressed(button: BaseButton) -> void:
	var id: StringName = button.get_meta(CLICK_META, UI_CLICK) # read at press time
	if id != &"":
		play(id)


func contract_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	for bus in [&"Music", &"SFX", &"UI"]:
		if AudioServer.get_bus_index(bus) == -1:
			problems.append("bus \"%s\" is missing; it would silently play on Master" % bus)
	var tracks := {ATLAS_TRACK: "atlas"}
	for w in LevelDB.get_worlds():
		var m := str(w.get("music", ""))
		if not m.is_empty():
			tracks[StringName(m)] = "world %s" % str(w.get("id", ""))
	for track in tracks:
		var path := MUSIC_DIR + str(track) + ".ogg"
		if not ResourceLoader.exists(path):
			problems.append("%s has no file %s" % [tracks[track], path])
			continue
		var stream := load(path) as AudioStreamOggVorbis
		if stream != null and not stream.loop:
			problems.append("%s %s would stop after one pass (loop == false)" % [tracks[track], path])
	for id in SOUNDS:
		var s: Dictionary = SOUNDS[id]
		var streams: Array = s.get("streams", [])
		if streams.is_empty():
			problems.append("sound %s has no streams" % id)
			continue
		for stream in streams:
			if stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED:
				problems.append("sound %s loops (a looping one-shot holds its voice forever)" % id)
				break
	var sfx_sum := 0
	var ui_sum := 0
	for id in SOUNDS:
		if bool(SOUNDS[id]["ui"]):
			ui_sum += int(SOUNDS[id]["max_voices"])
		else:
			sfx_sum += int(SOUNDS[id]["max_voices"])
	if sfx_sum > SFX_POLYPHONY:
		problems.append("SFX max_voices sum %d exceeds polyphony %d" % [sfx_sum, SFX_POLYPHONY])
	if ui_sum > UI_POLYPHONY:
		problems.append("UI max_voices sum %d exceeds polyphony %d" % [ui_sum, UI_POLYPHONY])
	return problems
