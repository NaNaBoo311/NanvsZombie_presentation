extends RefCounted

# Dev capture and draw-call probe for the HUD: `-- --hud-demo [wave|setup|calm|prepare|pause|won|lost|cooldown]`
# plus `--full-bank` (nine seeds) and `--touch`. `--hover` rests the mouse on a seed;
# `prepare --level <id> --unpack` removes a packed seed, for the briefing layout.
# --perf-test runs in sandbox, without the wave widgets or the touch row. This poses the
# busiest HUD on the real battle shell, prints "[HudDemo] hud=<n>" (draw calls with
# the HUD minus without it), saves tools/.screenshots/screenshot_hud_<pose>.png and quits.
# `--no-hud` on its own hides the HUD for clean captures. Loaded only by HUD under the flag.

const SETTLE_SEC := 5.0
const SAMPLE_FRAMES := 30
const FULL_BANK := ["lotus_shooter", "sacred_rice", "popping_pod", "armored_coconut", "kapok_catapult",
	"bougainvillea_net", "dipterocarp_spinner", "tamarind_cannon", "kumquat_sprayer"]

static var _alive: RefCounted = null # keeps the awaiting coroutine alive


func run(hud: Control) -> void:
	_alive = self
	var tree := hud.get_tree()
	var args := OS.get_cmdline_user_args()
	var pose := "wave"
	var i := args.find("--hud-demo")
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		pose = args[i + 1]
	await tree.create_timer(SETTLE_SEC).timeout
	var bank: SeedBank = hud.find_child("SeedBank", true, false)
	if "--full-bank" in args:
		var ids: Array[String] = []
		ids.assign(FULL_BANK)
		GameManager.seed_loadout = ids
		EventBus.seed_loadout_changed.emit(FULL_BANK)
		await tree.create_timer(1.5).timeout
	GameManager.level_active = true
	GameManager.current_sun = 110
	EventBus.sun_amount_changed.emit(110)
	match pose:
		"calm":
			pass
		"prepare":
			GameManager.current_level_id = _level_id(args)
			GameManager.round_state = "prepare"
			EventBus.round_state_changed.emit("prepare")
			if "--unpack" in args:
				await tree.create_timer(0.6).timeout
				# As the pool does: no card animation, so nothing else forces a repaint.
				GameManager.try_unpack_seed(str(GameManager.seed_loadout[1]))
				await tree.create_timer(0.2).timeout
		"pause":
			_pose_battle(hud, bank, "wave")
			bank.deselect_current()
			await tree.process_frame
			EventBus.pause_requested.emit()
			await tree.process_frame
			if "--armed" in args:
				hud.find_child("Retry", true, false).pressed.emit()
		"cooldown":
			await _check_cooldown(tree, hud, bank)
			tree.quit()
			return
		"won", "lost":
			GameManager.current_level_id = _level_id(args)
			GameManager.last_award = {"stars": 2, "jade": 45, "awakened": []}
			GameManager.round_state = pose
			EventBus.round_state_changed.emit(pose)
		_:
			_pose_battle(hud, bank, pose)
	await tree.create_timer(1.0).timeout
	if "--hover" in args:
		var card: Control = bank.slot_cards[0]
		var at := card.get_global_rect().get_center()
		tree.root.warp_mouse(at)
		await tree.process_frame
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		tree.root.push_input(motion)
		await tree.create_timer(1.2).timeout
	var with_hud := await _median_draws(tree)
	var shot := "res://tools/.screenshots/screenshot_hud_%s%s.png" % [pose, _shot_suffix(args)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/.screenshots"))
	tree.root.get_texture().get_image().save_png(shot)
	if tree.paused or pose in ["pause", "won", "lost"]:
		tree.quit()
		return
	hud.visible = false
	var without := await _median_draws(tree)
	print("[HudDemo] pose=%s touch=%s hud=%d (with %d, without %d) saved %s" % [pose, GameManager.is_touch_ui(), with_hud - without, with_hud, without, shot])
	tree.quit()


## Cooldown rules on the real bank, with a capture at each stage of the eclipse.
func _check_cooldown(tree: SceneTree, hud: Control, bank: SeedBank) -> void:
	var cd: Node = GameManager.seed_cooldowns
	var pm: Node = hud.get_tree().current_scene.find_child("PlacementManager", true, false)
	var fails: Array[String] = []
	var ids: Array[String] = []
	for entry in bank.loadout:
		ids.append(str(entry.id))
	GameManager.round_state = "wave"
	EventBus.round_state_changed.emit("wave")
	for id in ids:
		EventBus.plant_placed.emit(id, Vector2i(99, 99), 0)
	var rice := "sacred_rice"
	var index := ids.find(rice)
	bank.trigger_slot(index)
	if bank.selected_index == index or GameManager.selected_plant_for(0) == rice:
		fails.append("a cooling seed was selected")
	if pm.remote_placement_allowed(rice, pm.valid_grid_coords.keys()[0] if pm.valid_grid_coords is Dictionary else pm.valid_grid_coords[0]):
		fails.append("the host accepted a cooling seed")
	await tree.create_timer(0.6).timeout
	var shot_at := func(tag: String) -> void:
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png("res://tools/.screenshots/screenshot_hud_cooldown_%s.png" % tag)
	await shot_at.call("early")
	var before: float = cd.left(rice)
	tree.paused = true
	await tree.create_timer(0.7).timeout # frame_post_draw never fires while paused
	if absf(cd.left(rice) - before) > 0.05:
		fails.append("the timer ran while paused")
	tree.paused = false
	await tree.create_timer(3.0).timeout
	await shot_at.call("mid")
	while cd.is_cooling(rice):
		await tree.process_frame
	await tree.create_timer(0.12).timeout
	await shot_at.call("ready")
	bank.trigger_slot(index)
	if bank.selected_index != index:
		fails.append("a recharged seed could not be selected")
	bank.deselect_current()
	print("[HudDemo] cooldown checks: %s" % ("PASS" if fails.is_empty() else "FAIL " + ", ".join(fails)))


func _level_id(args: PackedStringArray) -> String:
	var i := args.find("--level")
	return args[i + 1] if i >= 0 and i + 1 < args.size() else GameManager.current_level_id


func _shot_suffix(args: PackedStringArray) -> String:
	var suffix := ""
	for flag in ["--full-bank", "--touch", "--hover", "--unpack", "--armed", "--dev-seeds", "--day-test", "--night-test"]:
		if flag in args:
			suffix += "_" + flag.trim_prefix("--").get_slice("-", 0)
	return suffix


func _pose_battle(hud: Control, bank: SeedBank, pose: String) -> void:
	bank.trigger_slot(2)
	GameManager.round_state = pose
	EventBus.level_flags_defined.emit([0.5, 1.0])
	EventBus.round_state_changed.emit(pose)
	EventBus.level_progress_changed.emit(14, 30, 0.46)
	GameManager.house_health = 72
	EventBus.house_health_changed.emit(72, 100)
	if pose == "setup":
		EventBus.setup_tick.emit(20)
		EventBus.setup_tick.emit(12)
		return
	EventBus.placement_preview_changed.emit("kapok_catapult", Vector2i.ZERO, 0, true, 1 - GameManager.local_player_id())
	EventBus.placement_preview_changed.emit("kapok_catapult", Vector2i.ZERO, 0, true, 1 - GameManager.local_player_id())
	EventBus.huge_wave_incoming.emit(1)
	var banner: HudBanner = hud.find_child("HudBanner", true, false)
	banner.show_slip("Hold the line, Warden. The Pearl remembers every root you planted.")
	var card: SightingCard = hud.find_child("SightingCard", true, false)
	card.preview("hungry_ghost")


func _median_draws(tree: SceneTree) -> int:
	var samples: Array[int] = []
	for i in SAMPLE_FRAMES * 2:
		await tree.process_frame
		if i >= SAMPLE_FRAMES:
			samples.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	samples.sort()
	return samples[samples.size() / 2]
