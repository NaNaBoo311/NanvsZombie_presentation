extends Control

# Battle panel — the round's result and pause screen (instanced in HUD.tscn). The win and
# defeat are staged by ResultSequence, which this panel feeds and hands over to.
# won: "Level Clear", the stars and Leyline Jade this win paid (GameManager.last_award),
# any seed it awakened, and the level's "story.outro" Chronicle lines, + Next Level
# (when the next level in the world is unlocked) / Retry / Map. lost: Retry / Map. Esc during prepare / setup / wave /
# sandbox pauses the tree (Resume / Retry / Map) unless something else owns Esc right
# now (placement, shovel, debug spawner, an open overlay). In LAN co-op the tree
# is never paused (that would freeze the host's world for the guest): pause is a
# local menu overlay and the simulation keeps running (CONTRACT(lan-coop)). Buttons call
# GameFlow (retry / next_level / back_to_province); this node processes while
# paused. Styled in code with the shared Lacquer dialog look (UiPalette.lacquer_*, no
# textures): the first visible of Next / Resume / Retry (lost) / Map is the gold
# primary button. While paused, Retry and Map ask for a second press
# ("Sure? Click again") because they throw the run away; result screens act at once.
# One-shot fade-in tween on show. Signal-driven, no per-frame work.

enum Mode { HIDDEN, WON, LOST, PAUSED }

@onready var _title: Label = $Center/Panel/VBox/Title
@onready var _subtitle: Label = $Center/Panel/VBox/Subtitle
@onready var _next: Button = $Center/Panel/VBox/Buttons/Next
@onready var _resume: Button = $Center/Panel/VBox/Buttons/Resume
@onready var _retry: Button = $Center/Panel/VBox/Buttons/Retry
@onready var _map: Button = $Center/Panel/VBox/Buttons/Map

enum Kind { PRIMARY, SECONDARY, ARMED }

const FADE_IN := 0.15
## How dark the scene sits behind each panel, by Mode: the win keeps the dawn visible.
const RESULT_DIM := {Mode.WON: 0.12, Mode.LOST: 0.28, Mode.PAUSED: 0.62}

@onready var _panel: PanelContainer = $Center/Panel
@onready var _hint: Label = $Center/Panel/VBox/Hint

var mode: int = Mode.HIDDEN
var _reward: Label
var _chronicle: Label
var _sequence: ResultSequence
var _star_row: Control
var _report: VBoxContainer
var _reached: Label
var _tip: Label
var _settings_button: Button
var _settings_panel: SettingsPanel
var _primary_button: Button = null
var _armed: Button = null
var _armed_text := ""
var _fade_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	EventBus.round_state_changed.connect(_on_round_state_changed)
	EventBus.pause_requested.connect(_on_pause_requested)
	($Dim as ColorRect).color = UiPalette.HUD_DIM
	_panel.add_theme_stylebox_override("panel", UiPalette.lacquer_panel())
	_title.add_theme_font_override("font", UiPalette.hud_font())
	_title.add_theme_font_size_override("font_size", 34)
	for label: Label in [_subtitle, _hint]:
		label.add_theme_font_override("font", UiPalette.hud_font())
		label.add_theme_color_override("font_color", UiPalette.HUD_INK_SOFT)
	_reward = Label.new()
	_reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward.add_theme_font_override("font", UiPalette.hud_font())
	_reward.add_theme_font_size_override("font_size", 22)
	_reward.add_theme_color_override("font_color", UiPalette.HUD_ACCENT)
	_chronicle = Label.new()
	_chronicle.add_theme_font_override("font", UiPalette.hud_font())
	_chronicle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chronicle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chronicle.custom_minimum_size = Vector2(minf(420.0, get_viewport_rect().size.x - 96.0), 0.0)
	_chronicle.add_theme_color_override("font_color", UiPalette.HUD_INK_SOFT)
	var vbox := _subtitle.get_parent()
	vbox.add_child(_reward)
	vbox.move_child(_reward, _subtitle.get_index() + 1)
	vbox.add_child(_chronicle)
	vbox.move_child(_chronicle, _reward.get_index() + 1)
	_settings_button = Button.new()
	_settings_button.name = "Settings"
	_settings_button.text = tr("Settings")
	_settings_button.custom_minimum_size = _resume.custom_minimum_size
	_resume.get_parent().add_child(_settings_button)
	_resume.get_parent().move_child(_settings_button, _resume.get_index() + 1)
	_settings_panel = SettingsPanel.new()
	add_child(_settings_panel)
	_settings_button.pressed.connect(_settings_panel.open)
	_build_results(vbox)
	_next.pressed.connect(func() -> void: GameFlow.next_level())
	_resume.pressed.connect(close_pause)
	_retry.pressed.connect(func() -> void:
		if _confirmed(_retry):
			GameFlow.retry())
	_map.pressed.connect(func() -> void:
		if _confirmed(_map):
			GameFlow.back_to_province())


func _on_round_state_changed(state: String) -> void:
	if state == "won":
		_show(Mode.WON)
	elif state == "lost":
		_show(Mode.LOST)
	elif mode != Mode.PAUSED:
		_show(Mode.HIDDEN)


## Pause entry from the on-screen touch button and the Esc key.
## While paused it resumes; while playing it pauses if Esc would also be free.
func _on_pause_requested() -> void:
	if mode == Mode.PAUSED:
		close_pause()
	elif mode == Mode.HIDDEN and _esc_is_free():
		open_pause()


func open_pause() -> void:
	if mode != Mode.HIDDEN:
		return
	GameManager.is_local_menu_open = true
	# Online, the guest's world must keep moving: a local overlay is the pause.
	if not GameManager.is_online():
		get_tree().paused = true
	_show(Mode.PAUSED)


func close_pause() -> void:
	if mode != Mode.PAUSED:
		return
	GameManager.is_local_menu_open = false
	get_tree().paused = false
	_show(Mode.HIDDEN)


## Android's Back button: it must not close the app mid-wave. Back opens the
## pause panel (leaving the level is a button there), and backs out of it again.
## The OS only forwards this because quit_on_go_back is off in project.godot.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	_on_pause_requested()


func _input(event: InputEvent) -> void:
	if _sequence != null and _sequence.is_playing() and event is InputEventKey and event.pressed and not event.echo:
		_sequence.skip()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if _settings_panel.visible:
		return # Esc belongs to the open dialog
	if mode == Mode.PAUSED:
		close_pause()
	elif mode == Mode.HIDDEN and _esc_is_free():
		open_pause()
	else:
		return
	get_viewport().set_input_as_handled()


## Esc cancels placement / shovel / the debug spawner / overlays first. The briefing
## stays open under the pause panel (Resume returns to it), so its flag does not block Esc here.
func _esc_is_free() -> bool:
	var local_id: int = GameManager.local_player_id()
	return not GameManager.is_seed_selector_open and not GameManager.is_enemy_selector_open \
		and GameManager.selected_plant_for(local_id).is_empty() \
		and not GameManager.is_shovel_for(local_id) \
		and not GameManager.is_enemy_spawn_mode \
		and GameManager.round_state in ["prepare", "setup", "wave", "sandbox"]


## True when the press should act. While paused the first press only arms the button.
func _confirmed(button: Button) -> bool:
	if mode != Mode.PAUSED or _armed == button:
		_disarm()
		return true
	_disarm()
	_armed = button
	_armed_text = button.text
	button.text = tr("Sure? Click again")
	_style_button(button, Kind.ARMED)
	return false


func _disarm() -> void:
	if _armed == null:
		return
	_armed.text = _armed_text
	_style_button(_armed, Kind.SECONDARY)
	_armed = null


## The defeat report, the star row the sequence paints on, and the sequence itself.
func _build_results(vbox: Node) -> void:
	_star_row = Control.new()
	_star_row.name = "StarRow"
	_star_row.custom_minimum_size = Vector2(260.0, 74.0)
	_star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_star_row.visible = false
	vbox.add_child(_star_row)
	vbox.move_child(_star_row, _subtitle.get_index() + 1)
	_report = VBoxContainer.new()
	_report.name = "Report"
	_report.add_theme_constant_override("separation", 8)
	_report.visible = false
	vbox.add_child(_report)
	vbox.move_child(_report, _chronicle.get_index() + 1)
	_reached = _dialog_label(19, UiPalette.HUD_INK)
	_report.add_child(_reached)
	_tip = _dialog_label(16, UiPalette.HUD_INK_SOFT)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(minf(420.0, get_viewport_rect().size.x - 96.0), 0.0)
	_report.add_child(_tip)
	_sequence = ResultSequence.new()
	_sequence.name = "ResultSequence"
	_sequence.panel = _panel
	_sequence.title = _title
	_sequence.star_row = _star_row
	_sequence.reward = _reward
	_sequence.chronicle = _chronicle
	_sequence.buttons = _retry.get_parent()
	_sequence.report = _report
	add_child(_sequence)
	_sequence.setup($Center.get_index())
	_sequence.finished.connect(_focus_primary)


func _dialog_label(font_size: int, color: Color) -> Label:
	var label := UiPalette.hud_label(font_size, color)
	label.z_index = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## How far the run got, and one thing to try. Only the defeat panel shows this.
func _fill_report() -> void:
	var total := int(GameManager.level_total)
	_reached.visible = total > 0
	_reached.text = tr("You calmed %d of %d spirits") % [int(GameManager.level_killed), total]
	var tips := [tr("Plant Sacred Rice early: every seed you can afford starts with gems."),
		tr("Walls buy time. Put Armored Coconuts in front of your shooters."),
		tr("Watch where spirits rise in the briefing, and plant to meet them.")]
	_tip.text = tips[int(GameManager.level_killed) % tips.size()]


## The stars, Jade and awakened seeds (host only: the guest earns nothing) and the outro.
func _fill_reward(won: bool) -> void:
	var award: Dictionary = GameManager.last_award if won else {}
	_reward.visible = not award.is_empty()
	if _reward.visible:
		_reward.text = tr("+%d Jade") % int(award["jade"])
	var lines: Array[String] = []
	if won and GameManager.level_active:
		lines = LevelDB.story_lines(GameManager.current_level_id, "outro")
	_chronicle.visible = not lines.is_empty()
	_chronicle.text = "\n".join(PackedStringArray(lines.map(func(l: String) -> String: return "“%s”" % tr(l))))


## PRIMARY is gold-filled, ARMED red (the "click again to confirm" state).
func _style_button(b: Button, kind: int) -> void:
	UiPalette.lacquer_button(b, kind == Kind.PRIMARY, kind == Kind.ARMED)


func _show(m: int) -> void:
	mode = m
	visible = m != Mode.HIDDEN
	_disarm()
	if _fade_tween != null:
		_fade_tween.kill()
	modulate.a = 1.0
	_sequence.reset()
	if not visible:
		return
	($Dim as ColorRect).color = Color(UiPalette.HUD_DIM, RESULT_DIM[m])
	if m == Mode.PAUSED:
		modulate.a = 0.0
		_fade_tween = create_tween()
		_fade_tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	var level_name := str(LevelDB.get_level(GameManager.current_level_id).get("name", "")) if GameManager.level_active else ""
	var next := GameFlow.next_level_id()
	var guest := Net != null and Net.is_guest()
	match m:
		Mode.WON:
			_title.text = tr("Dawn Breaks — Level Clear!")
		Mode.LOST:
			_title.text = tr("Pearl Shattered!")
		Mode.PAUSED:
			_title.text = tr("Paused")
	_title.add_theme_color_override("font_color", UiPalette.HUD_DANGER_TEXT if m == Mode.LOST else UiPalette.HUD_ACCENT)
	_subtitle.text = tr(level_name)
	_subtitle.visible = not level_name.is_empty()
	_fill_reward(m == Mode.WON)
	# LAN guest: progress and the run belong to the host, so Next/Retry are the
	# host's buttons. The guest's one action is leaving for the atlas.
	_next.visible = not guest and m == Mode.WON and not next.is_empty() and Progress.is_level_unlocked(next)
	_resume.visible = m == Mode.PAUSED
	_settings_button.visible = m == Mode.PAUSED
	_retry.visible = GameManager.level_active and not guest
	_map.text = tr("World Map") if GameManager.level_active else tr("Atlas")
	_hint.visible = m == Mode.PAUSED
	if m == Mode.PAUSED:
		if GameManager.is_touch_ui():
			_hint.text = tr("Tap Resume to continue")
		else:
			_hint.text = tr("Esc or Start to resume")
	var primary: Button = _next if _next.visible else (_resume if _resume.visible else (_retry if m == Mode.LOST and _retry.visible else _map))
	for b: Button in [_next, _resume, _settings_button, _retry, _map]:
		_style_button(b, Kind.PRIMARY if b == primary else Kind.SECONDARY)
	_primary_button = primary
	match m:
		Mode.WON:
			_sequence.play_win(GameManager.last_award)
		Mode.LOST:
			_fill_report()
			_sequence.play_lose()
		_:
			primary.grab_focus()


func _focus_primary() -> void:
	if is_instance_valid(_primary_button):
		_primary_button.grab_focus()
