extends Node

# Central Game State Manager
# Manages player currency (Sun), Sacred Dragon Pearl health, and placement state.
# Round flow: a picked level whose intro has not been read opens in "story" (the
# Warden's Chronicle, StoryPanel) until finish_story(); then it waits in "prepare"
# (the pre-battle loadout briefing) until the player confirms a loadout, then runs
# the "setup" countdown. A win awards stars (pearl health) and Jade via Progress.award();
# last_award holds that result for the result panel.
# LAN co-op: the host owns sun, health, waves and progress; the guest runs the
# same code as a thin client and applies replicated values. Selection/tool state
# is per player through the `p2_*` slot, which belongs to the guest on its device.

@export var starting_sun: int = 10000
@export var max_house_health: int = 100

var current_sun: int = 10000
var house_health: int = 100
var selected_plant_to_place: String = ""
var is_shovel_mode: bool = false # PvZ-style shovel: click a plant/zombie to remove it (no refund)
var is_enemy_spawn_mode: bool = false # TEMP debug flag for EnemyDebugSpawner (G key)
var is_seed_selector_open: bool = false # While true, SeedBank hotkeys are suppressed
var is_enemy_selector_open: bool = false # TEMP debug: while true, game hotkeys yield to EnemySelector
var is_briefing_open: bool = false # While true, the loadout briefing owns input (prepare state)
var is_story_open: bool = false # While true, the StoryPanel owns input (story state)
var is_local_menu_open: bool = false # LAN pause overlay: blocks game input, never pauses the tree

# LAN co-op. Every device has exactly one local player; the other slot exists
# only as state the host validates. Sun, loadout, health and grid occupancy stay
# shared, so only the selection/tool is per player. Use the *_for(id) helpers.
var p2_selected_plant_to_place: String = ""
var is_p2_shovel_mode: bool = false
var p2_seed_index: int = -1

# Touch UI: true while two or more fingers are down. Placement and shovel dig
# commit on release, so a pinch / two-finger orbit must not also plant or dig.
# The latch stays set until EVERY finger lifts: the emulated mouse release can
# be delivered before the raw touch release that would clear it.
var touch_gesture_multi: bool = false

var time_of_day: String = "day" # LightingPreset id (assets/lighting/<id>.tres); DayNightCycle.gd renders the blend.
## True while the current preset is more day than night (daylight >= 0.5).
var is_day: bool:
	get:
		return daylight() >= 0.5

# Live enemy count for zero-idle-cost gating: plants skip target scans entirely
# when this is 0 (driven by EventBus.enemy_spawned / enemy_defeated).
var alive_enemies: int = 0

# Single fixed quality preset for every device: 0.85 render scale with FSR/Bilinear
# keeps sharp low-poly edges while staying well under 16ms on integrated GPUs.
const RENDER_SCALE := 0.85

# Touch UI (phones/tablets) keeps the desktop layout but scales the whole 2D
# canvas up so the same cards stay legible and tappable. The 3D view is
# untouched. `-- --touch` forces the path on a desktop for tests and captures.
const TOUCH_UI_SCALE := 1.3

# Frame cap: an uncapped loop pegs the GPU at 100% forever, which is what
# overheats laptops. Physics ticks independently at 60 Hz, so capping rendered
# frames cools the machine without touching gameplay timing.
const TARGET_FPS := 60

# Pre-round seed loadout: ordered seed ids allowed in the SeedBank this round.
# Defaults to the seeds flagged "default_loadout" in their unit JSON (set in _ready).
var seed_loadout: Array[String] = []
var seed_cooldowns: Node = null # SeedCooldowns.gd

# Round flow. States: prepare / setup / wave / won / lost, or "sandbox" (no timers, no
# waves) under a scripted test flag or when peaceful (below).
# peaceful: no enemy waves (EnemySpawner checks it too). The `-- --peaceful` dev
# flag (read once at boot) turns it on for every level; a level's own
# "peaceful": true (LevelDB) turns it on for that level only: a sandbox that never ends.
var peaceful: bool = false
var _peaceful_flag: bool = false

# Owned here (state), rendered by HUD, executed by EnemySpawner — via EventBus only.
const ROUND_SETUP_DURATION := 10.0
const ROUND_TEST_SETUP := 3.0
var round_state: String = "setup"
## Guest: the host's setup countdown, mirrored so a guest that joins during the
## countdown still shows the correct number. Owner: GameManager._begin_setup.
var setup_left: int = 0
var _round_enabled := true
var _round_token := 0

# Level flow (PvZ2-style worlds -> levels -> waves). Set by prepare_level()
# (GameFlow) or start_level(); survives R-restart; clear_level() on leaving.
# level_active gates killed/total progress + sub-wave completion routing.
# Completions and unlocks (the save file) live in Progress.gd.
var level_active: bool = false
var current_world_id: String = ""
var current_level_id: String = ""
var level_total: int = 0
var level_killed: int = 0
var level_flag_fractions: Array[float] = []
var last_award: Dictionary = {} # Progress.award() result of this round's win, else {}

# TEMP debug: which enemy the EnemyDebugSpawner (G key) spawns. Testing only.
var debug_enemy_id: String = "hungry_ghost"

func _ready() -> void:
	seed_cooldowns = preload("res://src/core/SeedCooldowns.gd").new()
	seed_cooldowns.name = "SeedCooldowns"
	add_child(seed_cooldowns)
	_peaceful_flag = "--peaceful" in OS.get_cmdline_user_args()
	peaceful = _peaceful_flag
	seed_loadout = BalanceDB.default_loadout()
	current_sun = starting_sun
	house_health = max_house_health
	EventBus.sun_amount_changed.emit(current_sun)
	EventBus.house_health_changed.emit(house_health, max_house_health)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.level_completed.connect(_on_level_completed)
	# A map switch clears the Enemies container without defeat events.
	EventBus.map_loaded.connect(func(_map: MapDefinition) -> void: alive_enemies = 0)
	_apply_fixed_quality()
	Engine.max_fps = TARGET_FPS
	OS.low_processor_usage_mode = false

# ---- LAN role helpers (CONTRACT(lan-coop)) -------------------------------

## This device's player slot: 0 offline/host, 1 guest.
func local_player_id() -> int:
	return Net.local_player_id if Net != null else 0

## The other slot, for validation and UI that shows the partner's pick.
func other_player_id() -> int:
	return 1 - local_player_id()

## True on the guest: no timers, no wave spawning, no progress writes.
func is_client() -> bool:
	return Net != null and Net.is_guest()

func is_host() -> bool:
	return Net != null and Net.is_host()

func is_online() -> bool:
	return Net != null and Net.is_online()

# ---- Guest-side state application (CONTRACT(lan-coop)) -------------------
# The host owns these values; NetBridge applies its events through these
# setters so no UI or entity writes authoritative state directly.

func apply_remote_sun(value: int) -> void:
	current_sun = maxi(0, value)
	EventBus.sun_amount_changed.emit(current_sun)

func apply_remote_house_health(value: int) -> void:
	house_health = clampi(value, 0, max_house_health)
	EventBus.house_health_changed.emit(house_health, max_house_health)

func apply_remote_round_state(state: String) -> void:
	round_state = state
	if state == "setup" or state == "wave" or state == "won" or state == "lost" or state == "sandbox":
		is_briefing_open = false
		if state != "setup":
			setup_left = 0
	EventBus.round_state_changed.emit(round_state)

func apply_remote_progress(killed: int, total: int) -> void:
	level_killed = clampi(killed, 0, maxi(total, 0))
	level_total = maxi(total, 0)
	var progress := 0.0
	if level_total > 0:
		progress = clampf(float(level_killed) / float(level_total), 0.0, 1.0)
	EventBus.level_progress_changed.emit(level_killed, level_total, progress)

## Round entry, called by DioramaWorld on every scene load. Lives here (not
## _ready) because autoloads persist across reload_current_scene: R-restart
## re-enters through this with a fresh token, and any stale setup loop from
## the previous scene aborts on the token mismatch. Zero per-frame cost —
## one 1 Hz countdown, then silence.
## Level mode: GameFlow and R-restart re-run the picked level (ids persist on
## the autoload); with no level the legacy single wave runs. A picked level
## waits in "prepare" until confirm_loadout(); skip_briefing() auto-confirms.
func start_round() -> void:
	_round_token += 1
	var token := _round_token
	current_sun = starting_sun
	house_health = max_house_health
	alive_enemies = 0
	selected_plant_to_place = ""
	is_shovel_mode = false
	p2_selected_plant_to_place = ""
	is_p2_shovel_mode = false
	p2_seed_index = -1
	if is_instance_valid(seed_cooldowns):
		seed_cooldowns.clear()
	touch_gesture_multi = false
	is_enemy_spawn_mode = false
	setup_left = 0
	last_award = {}
	is_story_open = false
	EventBus.sun_amount_changed.emit(current_sun)
	EventBus.house_health_changed.emit(house_health, max_house_health)
	_round_enabled = ("--round-test" in OS.get_cmdline_user_args()) or (not _has_test_flag() and not peaceful)
	if level_active:
		_reannounce_level()
	if is_client():
		# The host owns the clock, waves and economy: wait for replicated state
		# instead of starting a local countdown that would drift from it.
		round_state = "prepare"
		EventBus.round_state_changed.emit(round_state)
		return
	if not _round_enabled:
		round_state = "sandbox"
		is_briefing_open = false
		EventBus.round_state_changed.emit(round_state)
		return
	if level_active and not skip_briefing():
		if not Progress.has_seen("intro:" + current_level_id) and not LevelDB.story_lines(current_level_id, "intro").is_empty():
			round_state = "story"
			is_story_open = true
			EventBus.round_state_changed.emit(round_state)
			return
		_open_briefing()
		return
	if level_active:
		set_seed_loadout(_prefill_loadout())
	_begin_setup(token)


## The StoryPanel's last line was read (or skipped): remember it, then the briefing.
func finish_story() -> void:
	if round_state != "story" or is_client():
		return
	Progress.mark_seen("intro:" + current_level_id)
	is_story_open = false
	_open_briefing()


func _open_briefing() -> void:
	set_seed_loadout(_prefill_loadout())
	round_state = "prepare"
	is_briefing_open = true
	EventBus.round_state_changed.emit(round_state)


## The existing setup countdown loop, entered from start_round() (auto-confirm)
## or confirm_loadout() (player-confirmed). Token-guarded like before.
func _begin_setup(token: int) -> void:
	round_state = "setup"
	is_briefing_open = false
	EventBus.round_state_changed.emit(round_state)
	var duration := _setup_duration()
	var left := int(duration)
	while left > 0:
		setup_left = left
		EventBus.setup_tick.emit(left)
		await get_tree().create_timer(1.0).timeout
		if token != _round_token or not is_inside_tree():
			return
		left -= 1
	if token != _round_token:
		return
	setup_left = 0
	round_state = "wave"
	EventBus.round_state_changed.emit(round_state)
	EventBus.round_wave_go.emit()


## Player-confirmed loadout from the briefing: lock it in, save it for the
## retry prefill, then run the setup countdown. Only acts in "prepare" and
## reuses the current _round_token, so a retry while in prepare aborts cleanly.
func confirm_loadout(ids: Array) -> void:
	if round_state != "prepare" or is_client():
		return
	var token := _round_token
	set_seed_loadout(ids)
	if not current_world_id.is_empty():
		Progress.set_last_loadout(current_world_id, seed_loadout)
	EventBus.briefing_closed.emit()
	_begin_setup(token)


## Slot limit for the current level (LevelDB.seed_rules), else the full bank.
func seed_slot_count() -> int:
	if level_active and LevelDB != null and LevelDB.has_level(current_level_id):
		return int(LevelDB.seed_rules(current_level_id)["slots"])
	return SeedBank.TOTAL_SLOTS


## Whether this level's briefing is skipped (auto-confirm the prefill).
## --round-test, any GameFlow.SANDBOX_FLAGS, and --quick-start skip it.
## --quick-start only affects levels entered from the atlas (never boots battle).
func skip_briefing() -> bool:
	var args := OS.get_cmdline_user_args()
	if "--round-test" in args or "--quick-start" in args:
		return true
	for flag in GameFlow.SANDBOX_FLAGS:
		if flag in args:
			return true
	return false


## Prefill on briefing open: this world's last confirmed loadout, filtered to
## the pool with forced first and trimmed to the slots. Without one, forced +
## the default_loadout seeds in the pool.
func _prefill_loadout() -> Array[String]:
	if not level_active or LevelDB == null or not LevelDB.has_level(current_level_id):
		return seed_loadout.duplicate()
	var rules: Dictionary = LevelDB.seed_rules(current_level_id)
	var pool: Array[String] = rules["pool"]
	var forced: Array[String] = rules["forced"]
	var slots: int = rules["slots"]
	var out: Array[String] = forced.duplicate()
	var saved: Array[String] = Progress.last_loadout(current_world_id) if Progress != null else []
	var source := saved if not saved.is_empty() else BalanceDB.default_loadout()
	for sid in source:
		var id := str(sid)
		if out.size() >= slots:
			break
		if pool.has(id) and not out.has(id):
			out.append(id)
	return out.slice(0, slots)


## Whether a seed is forced by the current level's rules (locked, cannot unpack).
func is_seed_forced(seed_id: String) -> bool:
	if not level_active or LevelDB == null or not LevelDB.has_level(current_level_id):
		return false
	return (LevelDB.seed_rules(current_level_id)["forced"] as Array).has(seed_id)


## Pack one seed into the draft during prepare. Refused when not in prepare,
## outside the pool, already packed, or the bank is full.
func try_pack_seed(seed_id: String) -> bool:
	if round_state != "prepare":
		return false
	if not level_active or LevelDB == null:
		return false
	var rules: Dictionary = LevelDB.seed_rules(current_level_id)
	var pool: Array[String] = rules["pool"]
	var slots: int = rules["slots"]
	if not pool.has(seed_id) or seed_loadout.has(seed_id) or not BalanceDB.is_playable(seed_id):
		return false
	if seed_loadout.size() >= slots:
		return false
	var next: Array[String] = seed_loadout.duplicate()
	next.append(seed_id)
	set_seed_loadout(next)
	return true


## Unpack one seed from the draft during prepare. Forced ids are refused, and
## later slots shift left via set_seed_loadout.
func try_unpack_seed(seed_id: String) -> bool:
	if round_state != "prepare":
		return false
	if is_seed_forced(seed_id) or not seed_loadout.has(seed_id):
		return false
	var next: Array[String] = seed_loadout.duplicate()
	next.erase(seed_id)
	set_seed_loadout(next)
	return true


## Level entry inside a running battle (tests, tools): prepare_level() then the
## shared setup countdown through start_round(). CONTRACT(add-level): ids must
## exist in LevelDB or this no-ops with a warning.
func start_level(world_id: String, level_id: String) -> void:
	if not prepare_level(world_id, level_id):
		return
	EventBus.level_selected.emit(world_id, level_id)
	EventBus.level_flags_defined.emit(level_flag_fractions.duplicate())
	EventBus.level_progress_changed.emit(0, level_total, 0.0)
	start_round()


## Level state without starting the round: GameFlow calls this before it
## changes to the battle scene, whose _ready() then runs start_round() exactly
## like an R-restart (and re-announces the level to the fresh HUD). The briefing's
## prefill decides the bank, so no loadout is set here.
func prepare_level(world_id: String, level_id: String) -> bool:
	if LevelDB == null or not LevelDB.has_level(level_id):
		push_warning("[GameManager] Unknown level: %s" % level_id)
		return false
	var level: Dictionary = LevelDB.get_level(level_id)
	current_world_id = world_id
	current_level_id = level_id
	level_active = true
	peaceful = _peaceful_flag or bool(level.get("peaceful", false))
	level_total = LevelDB.level_total(level)
	level_killed = 0
	level_flag_fractions = LevelDB.flag_fractions(level)
	return true


## Leaving the battle for the menus: no level is picked any more.
func clear_level() -> void:
	_round_token += 1
	level_active = false
	peaceful = _peaceful_flag
	is_briefing_open = false
	is_story_open = false
	current_world_id = ""
	current_level_id = ""
	level_total = 0
	level_killed = 0
	level_flag_fractions = []


func _setup_duration() -> float:
	if "--round-test" in OS.get_cmdline_user_args():
		return ROUND_TEST_SETUP
	if level_active and LevelDB != null:
		var level: Dictionary = LevelDB.get_level(current_level_id)
		if not level.is_empty():
			return float(level.get("setup_sec", ROUND_SETUP_DURATION))
	return ROUND_SETUP_DURATION


## Re-emit level identity after an R-restart scene reload so a rebuilt HUD
## (progress bar, selectors) re-syncs without re-picking. Signal-only.
func _reannounce_level() -> void:
	if current_level_id.is_empty():
		return
	EventBus.level_selected.emit(current_world_id, current_level_id)
	EventBus.level_flags_defined.emit(level_flag_fractions.duplicate())
	var progress := 0.0
	if level_total > 0:
		progress = clampf(float(level_killed) / float(level_total), 0.0, 1.0)
	EventBus.level_progress_changed.emit(level_killed, level_total, progress)


## Any overlay owns input while open (placement/shovel/debug all yield).
func is_any_selector_open() -> bool:
	return is_seed_selector_open or is_enemy_selector_open or is_briefing_open or is_story_open or is_local_menu_open

## Test flags run their own scripted flows (ghost/spider/demo), so the round
## machine stands down and the scene behaves like the old sandbox. --round-test
## is the exception: it drives the REAL round flow, just compressed.
func _has_test_flag() -> bool:
	var args := OS.get_cmdline_user_args()
	for flag in GameFlow.SANDBOX_FLAGS:
		if flag in args:
			return true
	return false

func _on_wave_completed(_wave_index: int) -> void:
	# Level mode: sub-wave completions only sequence the spawner; the final
	# win arrives via level_completed. Legacy single-wave path wins here.
	if level_active or is_client():
		return
	if _round_enabled and round_state == "wave":
		round_state = "won"
		EventBus.round_state_changed.emit(round_state)


## Final wave of the picked level cleared: record the completion (Progress
## saves it and derives the unlocks), then run the standard won path.
## Killed/total already at 100%.
func _on_level_completed(world_id: String, level_id: String) -> void:
	if not level_active or level_id != current_level_id:
		return
	# Progress is host-only (CONTRACT(lan-coop)): the guest earns nothing.
	if not is_client():
		last_award = Progress.award(level_id, earned_stars())
	if _round_enabled and round_state == "wave":
		round_state = "won"
		EventBus.round_state_changed.emit(round_state)
	print("[GameManager] Level clear: %s (%s)." % [level_id, world_id])


## Stars for a win right now: 1, +1 at >= half pearl health, +1 for an untouched pearl.
func earned_stars() -> int:
	return 1 + int(house_health * 2 >= max_house_health) + int(house_health >= max_house_health)


func _notification(what: int) -> void:
	# An unfocused/minimized game does no useful work: drop to 5 fps so fans
	# stay silent, restore the fixed cap on return. Not under --perf-test: its
	# waits count frames, so a slower frame rate would sample the drifting sky
	# props (balloons, clouds) at a later moment and change the draw calls.
	if "--perf-test" in OS.get_cmdline_user_args():
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Engine.max_fps = 5
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Engine.max_fps = TARGET_FPS

func _on_enemy_spawned(_enemy: Node3D) -> void:
	alive_enemies += 1

func _on_enemy_defeated(enemy: Node3D) -> void:
	alive_enemies = maxi(0, alive_enemies - 1)
	# PvZ2 progress = killed / total. Signal-only: the bar renders on demand.
	# Mid-wave offspring (BasketBoatZombie's crabs) are not in level_total, so they earn no kill.
	if enemy.has_meta("no_kill_credit"):
		return
	if level_active and level_total > 0 and (round_state == "wave" or round_state == "won"):
		level_killed = mini(level_total, level_killed + 1)
		var progress := clampf(float(level_killed) / float(level_total), 0.0, 1.0)
		EventBus.level_progress_changed.emit(level_killed, level_total, progress)

# Fixed quality preset, applied unconditionally on every device. Autoloads run
# before the main scene, so this lands before the first rendered frame.
# Touch screens keep the same 3D scale but scale the 2D canvas for finger-sized
# UI. The smaller mobile shadow atlas is a project setting
# (rendering/lights_and_shadows/*.mobile), so it is already in effect here
# (CONTRACT(mobile-export)).
func _apply_fixed_quality() -> void:
	var touch := is_touch_ui()
	print("[Quality] %s preset (render scale %.2f, max %d fps)" % ["touch" if touch else "native", RENDER_SCALE, TARGET_FPS])
	var tree := get_tree()
	if tree and tree.root:
		if touch:
			tree.root.content_scale_factor = TOUCH_UI_SCALE
		tree.root.scaling_3d_scale = RENDER_SCALE
		tree.root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

## Touch UI runs on phones/tablets, and under --touch / --touch-test so the
## desktop test runs exercise the exact touch code path.
func is_touch_ui() -> bool:
	if DisplayServer.is_touchscreen_available():
		return true
	var args := OS.get_cmdline_user_args()
	return "--touch" in args or "--touch-test" in args

## The guest never mints or spends Sun: the host's events are the only source
## (CONTRACT(lan-coop)). Solo and host behave exactly as before.
func add_sun(amount: int) -> void:
	if is_client():
		return
	current_sun += amount
	EventBus.sun_amount_changed.emit(current_sun)

func is_seed_cooling(plant_type: String) -> bool:
	return is_instance_valid(seed_cooldowns) and seed_cooldowns.is_cooling(plant_type)


func can_afford(plant_type: String) -> bool:
	var cost: int = plant_cost(plant_type)
	return current_sun >= cost

## Sun cost from the plant's unit JSON (data/units/plants/<id>.json); 999 if it has none.
func plant_cost(plant_type: String) -> int:
	return BalanceDB.cost(plant_type, 999)

func spend_sun(amount: int) -> bool:
	if is_client():
		return false
	if current_sun >= amount:
		current_sun -= amount
		EventBus.sun_amount_changed.emit(current_sun)
		return true
	return false

## Per-player placement selection: `player_id` 0 is the host/solo slot, 1 is the
## guest. Sun, loadout, health and grid tiles stay shared; only the choice of
## seed / tool is local.
func select_plant(plant_type: String, player_id: int = 0) -> void:
	cancel_shovel(player_id)
	if player_id == 1:
		p2_selected_plant_to_place = plant_type
	else:
		selected_plant_to_place = plant_type
	EventBus.plant_selected_for_placement.emit(plant_type, player_id)

func clear_selection(player_id: int = 0) -> void:
	if player_id == 1:
		p2_selected_plant_to_place = ""
	else:
		selected_plant_to_place = ""
	EventBus.placement_cancelled.emit(player_id)

## PvZ-style shovel: entities removed with no Sun refund. Entering shovel
## mode cancels an in-flight placement; selecting a plant cancels the shovel.
func select_shovel(player_id: int = 0) -> void:
	if is_shovel_for(player_id):
		return
	if not selected_plant_for(player_id).is_empty():
		if player_id == 1:
			p2_selected_plant_to_place = ""
		else:
			selected_plant_to_place = ""
		EventBus.placement_cancelled.emit(player_id)
	_set_shovel_for(player_id, true)
	EventBus.shovel_mode_changed.emit(true, player_id)

func cancel_shovel(player_id: int = 0) -> void:
	if not is_shovel_for(player_id):
		return
	_set_shovel_for(player_id, false)
	EventBus.shovel_mode_changed.emit(false, player_id)

func toggle_shovel(player_id: int = 0) -> void:
	if is_shovel_for(player_id):
		cancel_shovel(player_id)
	else:
		select_shovel(player_id)

func selected_plant_for(player_id: int) -> String:
	return p2_selected_plant_to_place if player_id == 1 else selected_plant_to_place

func is_shovel_for(player_id: int) -> bool:
	return is_p2_shovel_mode if player_id == 1 else is_shovel_mode

func is_placing_for(player_id: int) -> bool:
	return not selected_plant_for(player_id).is_empty()

func _set_shovel_for(player_id: int, value: bool) -> void:
	if player_id == 1:
		is_p2_shovel_mode = value
	else:
		is_shovel_mode = value

## Join / leave a LAN room: dropping the guest clears that slot's tool and
## selection. The host's own selection, the sun pool and the shared health are
## never touched (the host keeps playing solo).
func set_guest_connected(value: bool) -> void:
	if value:
		EventBus.lan_guest_changed.emit(true)
		return
	cancel_shovel(1)
	if not p2_selected_plant_to_place.is_empty():
		clear_selection(1)
	p2_seed_index = -1
	EventBus.lan_guest_changed.emit(false)

func set_seed_loadout(ids: Array) -> void:
	var cleaned: Array[String] = []
	for id in ids:
		var sid := str(id)
		if not cleaned.has(sid) and BalanceDB.is_playable(sid) and not BalanceDB.seed_entry(sid).is_empty():
			cleaned.append(sid)
	seed_loadout = cleaned
	if not seed_loadout.has(selected_plant_to_place):
		selected_plant_to_place = ""
		EventBus.placement_cancelled.emit(0)
	if not seed_loadout.has(p2_selected_plant_to_place):
		p2_selected_plant_to_place = ""
		p2_seed_index = -1
		EventBus.placement_cancelled.emit(1)
	EventBus.seed_loadout_changed.emit(seed_loadout.duplicate())

# TEMP debug: arm the G-spawner with a different enemy. Empty/same ids are
# no-ops; unknown ids ride along but EnemyDebugSpawner refuses to switch to
# them (cards only ever offer catalog ids, so this is just misuse-proofing).
func set_debug_enemy(enemy_id: String) -> void:
	var eid := enemy_id.strip_edges()
	if eid.is_empty() or eid == debug_enemy_id:
		return
	debug_enemy_id = eid
	EventBus.debug_enemy_changed.emit(debug_enemy_id)

# Time of day. Idempotent: re-requesting the current preset is a no-op, so
# DayNightCycle never restarts a transition that is already settled. Unknown ids
# are rejected (LightingPreset.load_id logs the error).
func set_time_of_day(id: String) -> void:
	if id == time_of_day or LightingPreset.load_id(id) == null:
		return
	time_of_day = id
	EventBus.time_of_day_changed.emit(time_of_day)

## Next preset in LightingPreset.ids() order (the T key).
func cycle_time_of_day() -> void:
	var ids := LightingPreset.ids()
	if ids.is_empty():
		return
	set_time_of_day(ids[(ids.find(time_of_day) + 1) % ids.size()])

## The current preset's settled daylight (0 night .. 1 day) - what the map grades follow.
func daylight() -> float:
	var preset := LightingPreset.load_id(time_of_day)
	return preset.daylight if preset else 1.0

func damage_house(amount: int) -> void:
	if is_client():
		return
	house_health = max(0, house_health - amount)
	EventBus.house_health_changed.emit(house_health, max_house_health)
	if house_health <= 0:
		print("Pearl shattered! Game Over!")
		if _round_enabled and (round_state == "setup" or round_state == "wave"):
			round_state = "lost"
			EventBus.round_state_changed.emit(round_state)

func repair_house(amount: int) -> void:
	house_health = min(max_house_health, house_health + amount)
	EventBus.house_health_changed.emit(house_health, max_house_health)
