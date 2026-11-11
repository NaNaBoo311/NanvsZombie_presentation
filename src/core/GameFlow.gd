extends Node

# GameFlow — the only owner of scene changes. Boot (src/core/Boot.tscn, the main
# scene) calls boot(): a battle test/capture flag goes straight into the battle
# shell as before; atlas tests and captures open the atlas; presentation test
# flags boot into their screen; everything else opens the title screen
# (open_title), whose Start action opens the contents page
# (open_contents), whose live section opens the concept screen (open_concept).
# The atlas is reachable from the section's final action; its home button returns
# to the title.
# Play on a level card
# (EventBus.level_play_requested) fades out while the battle shell and the
# level's map finish their threaded load, prepares the level on GameManager and
# changes to the shell, whose _ready() starts the round exactly like an
# R-restart; the fade lifts once the map is in. retry() / next_level() /
# back_to_province() are what the battle's result and pause panel call; going
# back reopens the atlas already zoomed into that province, popping the level
# nodes this run unlocked (take_menu_request()). The fade overlay lives here
# (above everything, survives scene changes) and this node processes while the
# tree is paused, so "Back to map" works from the pause panel.
# LAN co-op (CONTRACT(lan-coop)): the host is the only one who picks a level.
# _enter_battle calls Net.begin_session so the guest loads the same level in
# parallel; the guest follows Net.start_level_received through remote_play_level
# and returns to the atlas when the host leaves the battle or the link drops.
# Game progress stays host-only: the guest never runs play_level's unlock check.
# --flow-test runs src/core/FlowTest.gd after boot; --title-test runs
# src/menus/title/TitleTest.gd, --contents-test runs
# src/presentation/ContentsTest.gd and --concept-test runs
# src/presentation/ConceptTest.gd.

const TITLE_SCENE := "res://src/presentation/PresentationTitle.tscn"
const CONTENTS_SCENE := "res://src/presentation/PresentationContents.tscn"
const CONCEPT_SCENE := "res://src/presentation/ConceptVision.tscn"
const CORE_ATLAS_SCENE := "res://src/presentation/CoreGameplayAtlas.tscn"
const CORE_FIELD_SCENE := "res://src/presentation/CoreGameplayField.tscn"
const ATLAS_SCENE := "res://src/menus/atlas/AtlasMenu.tscn"
const BATTLE_SCENE := "res://src/battle/DioramaWorld.tscn"
# Test flags that run their own scripted flow in the battle shell, so the round
# machine stands down (GameManager._has_test_flag). A new battle test flag goes here.
const SANDBOX_FLAGS := ["--ghost-test", "--spider-test", "--spawner-demo",
	"--map-switch-test", "--perf-test", "--screenshot", "--nav-test", "--nav-bake",
	"--touch-test", "--net-test", "--hud-demo"]
# Flags that boot straight into the battle shell (tests and screenshot captures):
# the sandbox flags plus the ones that drive the real round or only pin the lighting.
const BATTLE_FLAGS := SANDBOX_FLAGS + ["--round-test", "--day-test", "--night-test"]
# Tests and captures that live on the atlas: they skip the title so they keep
# booting straight into the screen they measure.
const ATLAS_FLAGS := ["--flow-test", "--lan-flow-test", "--atlas-test",
	"--atlas-overview", "--atlas-province", "--atlas-at", "--progress-test"]
const FADE_OUT := 0.45
const FADE_IN := 0.4

var busy := false
var _fade: ColorRect
var _fade_tween: Tween
var _menu_province: String = ""
var _menu_pops := PackedStringArray()
var _unlocked_before := PackedStringArray()
var _pending_remote_level: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.025, 0.04)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	layer.add_child(_fade)
	EventBus.level_play_requested.connect(play_level)
	Net.start_level_received.connect(_on_remote_start)
	Net.session_end_received.connect(_on_session_end)
	Net.link_lost.connect(_on_link_lost)
	Net.guest_joined.connect(_on_guest_joined)
	Net.guest_left.connect(_on_guest_left)
	Net.link_lost.connect(func(reason: String) -> void: EventBus.lan_link_lost.emit(reason))


## Called once by Boot.tscn. Scenes run directly from the command line never
## pass through here, so they keep their own behaviour.
func boot() -> void:
	var args := OS.get_cmdline_user_args()
	for flag in BATTLE_FLAGS:
		if flag in args:
			get_tree().change_scene_to_file.call_deferred(BATTLE_SCENE)
			return
	_fade.modulate.a = 1.0
	var atlas_only := false
	for flag in ATLAS_FLAGS:
		if flag in args:
			atlas_only = true
			break
	if atlas_only:
		open_atlas()
	elif "--contents-test" in args or "--contents-shot" in args:
		open_contents()
		if "--contents-test" in args:
			load("res://src/presentation/ContentsTest.gd").new().run()
	elif "--concept-test" in args or "--concept-shot" in args:
		open_concept()
		if "--concept-test" in args:
			load("res://src/presentation/ConceptTest.gd").new().run()
	elif "--core-test" in args or "--core-shot" in args:
		var shot_beat := "atlas"
		var bi := args.find("--core-beat")
		if bi >= 0 and bi + 1 < args.size():
			shot_beat = args[bi + 1]
		if "--core-shot" in args and shot_beat != "atlas":
			open_core_field()
		else:
			open_core_gameplay()
		if "--core-test" in args:
			load("res://src/presentation/CoreGameplayTest.gd").new().run()
	else:
		open_title()
	if "--flow-test" in args:
		load("res://src/core/FlowTest.gd").new().run()
	elif "--lan-flow-test" in args:
		load("res://src/net/LanFlowTest.gd").new().run()
	elif "--title-test" in args:
		load("res://src/menus/title/TitleTest.gd").new().run()


## The front door: the presentation cover. It owns no level state; every menu
## hand-off goes through _open_menu so the fade covers the load the same way.
func open_title() -> void:
	_open_menu(TITLE_SCENE)


## The contents page. Section 01 is live; the rest are listed but disabled.
func open_contents() -> void:
	_open_menu(CONTENTS_SCENE)


## Section 01 — Concept & Vision.
func open_concept() -> void:
	_open_menu(CONCEPT_SCENE)


## Section 02 — Core Gameplay, on the atlas stage (deck row 02).
func open_core_gameplay() -> void:
	open_section(1)


## Section 02's field: the HCMC sandbox the atlas hands over to. The field
## prepares the level itself before the shell's _ready(), so clearing the last
## level here is exactly what we want.
func open_core_field() -> void:
	_open_menu(CORE_FIELD_SCENE)


## Opens a section by its row in PresentationDeck.SECTIONS. A row without a scene
## is not live and does nothing, which is the same rule the contents page draws.
func open_section(index: int) -> void:
	if index < 0 or index >= PresentationDeck.SECTIONS.size():
		return
	var path := str(PresentationDeck.SECTIONS[index]["scene"])
	if path.is_empty():
		return
	_open_menu(path)


func _open_menu(path: String) -> void:
	if busy:
		return
	busy = true
	EventBus.flow_transition_started.emit("menu")
	await _fade_to(1.0, FADE_OUT)
	get_tree().paused = false
	if Net.is_host() and GameManager.level_active:
		Net.end_session()
	GameManager.clear_level()
	get_tree().change_scene_to_file(path)
	await _scene_ready(path)
	await _fade_to(0.0, FADE_IN)
	busy = false


## What the atlas should show on load: {province, pops}. Cleared once read.
func take_menu_request() -> Dictionary:
	var req := {"province": _menu_province, "pops": _menu_pops}
	_menu_province = ""
	_menu_pops = PackedStringArray()
	return req


func open_atlas(province_id: String = "", pops: PackedStringArray = PackedStringArray()) -> void:
	if busy:
		return
	busy = true
	EventBus.flow_transition_started.emit("menu")
	await _fade_to(1.0, FADE_OUT)
	get_tree().paused = false
	# Host leaving a battle: the guest leaves it too and the room reopens.
	if Net.is_host() and GameManager.level_active:
		Net.end_session()
	GameManager.clear_level()
	_menu_province = province_id
	_menu_pops = pops
	get_tree().change_scene_to_file(ATLAS_SCENE)
	await _scene_ready(ATLAS_SCENE)
	await _fade_to(0.0, FADE_IN)
	busy = false


## Play on a level card. The host picks; a connected guest waits for the host's
## start event instead of running its own round (CONTRACT(lan-coop)).
func play_level(level_id: String) -> void:
	if Net.is_guest():
		return
	if busy or not LevelDB.has_level(level_id) or not Progress.is_level_unlocked(level_id):
		return
	busy = true
	var world_id := LevelDB.world_of(level_id)
	_unlocked_before = _unlocked_levels(world_id)
	Progress.set_last_world(world_id)
	EventBus.flow_transition_started.emit("battle")
	await _enter_battle(level_id)
	busy = false
	_drain_pending_remote()


## Guest: the host picked a level. No unlock check here — progress is host-only;
## the level only has to exist in this build (same build, checked by the handshake).
func remote_play_level(level_id: String) -> void:
	if not Net.is_guest() or level_id.is_empty():
		return
	if not LevelDB.has_level(level_id):
		Net.stop(tr("The host picked a level this build does not have."))
		return
	if busy:
		_pending_remote_level = level_id
		return
	busy = true
	Progress.set_last_world(LevelDB.world_of(level_id))
	EventBus.flow_transition_started.emit("battle")
	await _enter_battle(level_id)
	busy = false
	_drain_pending_remote()


func _drain_pending_remote() -> void:
	if _pending_remote_level.is_empty():
		return
	var next := _pending_remote_level
	_pending_remote_level = ""
	remote_play_level(next)


func _on_remote_start(level_id: String) -> void:
	remote_play_level(level_id)


func _on_guest_joined() -> void:
	GameManager.set_guest_connected(true)


func _on_guest_left() -> void:
	GameManager.set_guest_connected(false)


## The host returned to the atlas while still connected: follow it out of the
## battle (a host that gave up still owns the session).
func _on_session_end(_reason: String) -> void:
	await _leave_battle_for_lobby()


## The host vanished: the guest cannot simulate a battle alone, so it returns to
## the atlas. The host's own game is unaffected (it keeps playing solo).
func _on_link_lost(_reason: String) -> void:
	await _leave_battle_for_lobby()


func _leave_battle_for_lobby() -> void:
	for _i in 120:
		if not busy:
			break
		await get_tree().process_frame
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == BATTLE_SCENE:
		open_atlas()


func retry() -> void:
	if Net.is_guest() or busy or not GameManager.level_active:
		return
	busy = true
	await _enter_battle(GameManager.current_level_id)
	busy = false


func next_level() -> void:
	if Net.is_guest():
		return
	var next := next_level_id()
	if busy or next.is_empty() or not Progress.is_level_unlocked(next):
		return
	busy = true
	await _enter_battle(next)
	busy = false


## Next level in the current world's list ("" at the end or with no level).
func next_level_id() -> String:
	if not GameManager.level_active:
		return ""
	var ids := LevelDB.get_level_ids(GameManager.current_world_id)
	var i := ids.find(GameManager.current_level_id)
	return ids[i + 1] if i >= 0 and i + 1 < ids.size() else ""


## Back to the atlas, zoomed into the current level's province, popping the
## level nodes that this visit to the battle unlocked. No level: plain atlas.
func back_to_province() -> void:
	var world_id := GameManager.current_world_id if GameManager.level_active else ""
	if world_id.is_empty():
		open_atlas()
		return
	var pops := PackedStringArray()
	for id in _unlocked_levels(world_id):
		if not _unlocked_before.has(id):
			pops.append(id)
	open_atlas(str(LevelDB.get_world(world_id).get("province", "")), pops)


func _enter_battle(level_id: String) -> void:
	var map_path := LevelDB.get_map_scene(LevelDB.resolve_map(level_id))
	var fade := _start_fade(1.0, FADE_OUT) # loads keep running under the fade
	var shell := await _load(BATTLE_SCENE) as PackedScene
	var map_scene := await _load(map_path) # held until the shell has instanced it
	if fade.is_running():
		await fade.finished
	get_tree().paused = false
	if not GameManager.prepare_level(LevelDB.world_of(level_id), level_id) or shell == null:
		push_error("[GameFlow] Cannot enter level %s." % level_id)
		await _fade_to(0.0, FADE_IN)
		return
	# Host: tell the guest which level to load before changing scenes, so both
	# devices boot the battle in parallel (CONTRACT(lan-coop)).
	if Net.is_host():
		Net.begin_session(level_id)
	get_tree().change_scene_to_packed(shell)
	await _scene_ready(BATTLE_SCENE)
	map_scene = null
	await get_tree().process_frame
	await _fade_to(0.0, FADE_IN)


## Threaded load (reuses a request the atlas started on node hover), blocking
## fallback. Polls once per frame only while the load is in flight.
func _load(path: String) -> Resource:
	if path.is_empty():
		return null
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		if ResourceLoader.load_threaded_request(path) != OK:
			return load(path)
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		return ResourceLoader.load_threaded_get(path)
	return load(path)


func _scene_ready(path: String) -> void:
	while true:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene and scene.scene_file_path == path and scene.is_node_ready():
			return


## Tween the overlay to `alpha`; it blocks input while not fully clear.
func _start_fade(alpha: float, duration: float) -> Tween:
	if _fade_tween and _fade_tween.is_running():
		_fade_tween.kill()
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_tween = _fade.create_tween()
	_fade_tween.tween_property(_fade, "modulate:a", alpha, duration if not is_equal_approx(_fade.modulate.a, alpha) else 0.0)
	if alpha <= 0.0:
		_fade_tween.tween_callback(func() -> void: _fade.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	return _fade_tween


func _fade_to(alpha: float, duration: float) -> void:
	await _start_fade(alpha, duration).finished


func fade_alpha() -> float:
	return _fade.modulate.a


func _unlocked_levels(world_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in LevelDB.get_level_ids(world_id):
		if Progress.is_level_unlocked(id):
			out.append(id)
	return out
