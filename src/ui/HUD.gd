extends Control

# The battle HUD: a lacquer rail across the top of the screen with everything hung from
# it. Rice Gem counter and SeedBank on the left; the Leyline, Pearl and pause on the
# right; banners, the incense countdown and the hint slip come and go. All of it is
# painted on one HudCanvas (layer rules there), so the HUD costs about three draws
# whatever it shows. This script owns the rail, the counter, the desktop pause
# button and the layout, and decides what the banners say. Everything else builds itself.
# SeedSelector is a TAB-toggled dev overlay (sandbox only); the real pre-battle
# flow is the loadout briefing (LoadoutBriefing), which owns prepare state.
# LAN co-op: a banner names the partner joining/leaving and the connection dropping.
# Story: HUD builds the StoryPanel (level intro, "story" state) and the SightingCard
# (first sightings); both stay hidden outside their moment. A huge wave's banner
# adds the level's next "story.huge_wave" line from the Warden.

const EDGE := 16.0
const RAIL_TOP := 5.0
const RAIL_HEIGHT := 11.0
const COUNTER_SIZE := Vector2(118.0, 54.0)
const COUNTER_GEM := Vector2(27.0, 27.0)
const COUNTER_TEXT_X := 48.0
const GAP := 8.0
const PAUSE_SIZE := 48.0
const TOUCH_PAUSE_SIZE := 64.0 # TouchControls.BUTTON_SIZE
const PEARL_TOP := 12.0
## Below this width the Leyline leaves the top row for the bottom of the screen.
const WIDE_ENOUGH := 1100.0
const LEYLINE_BOTTOM_TOP := -96.0
const COUNT_SEC := 0.25
const DELTA_HOLD_SEC := 0.7

@onready var _top_bar: Control = $TopBar
@onready var _gem_panel: Control = $TopBar/HBoxContainer/GemPanel
@onready var _leyline: LevelProgressBar = $LevelProgressBar

var _gem_label: Label
var _delta_label: Label
var _delta_alpha := 0.0
var _delta_tween: Tween = null
var _count_tween: Tween = null
var _pop_tween: Tween = null
var _shown_sun := -1
var _target_sun := 0
var _pearl: PearlMedallion
var _banner: HudBanner
var _incense: IncenseTimer
var _pause: HudHit = null
var _huge_waves_seen := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_gem_panel.pivot_offset = COUNTER_SIZE * 0.5
	_gem_label = UiPalette.hud_label(26)
	_gem_label.position = Vector2(COUNTER_TEXT_X, 0.0)
	_gem_label.size = Vector2(COUNTER_SIZE.x - COUNTER_TEXT_X, COUNTER_SIZE.y)
	_gem_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gem_panel.add_child(_gem_label)
	_delta_label = UiPalette.hud_label(16)
	_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_delta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_delta_label.position = Vector2(COUNTER_SIZE.x - 38.0, COUNTER_SIZE.y - 8.0)
	_delta_label.size = Vector2(46.0, 22.0)
	_delta_label.visible = false
	_gem_panel.add_child(_delta_label)
	HudCanvas.register(self, 0)
	theme = _tooltip_theme()

	_pearl = PearlMedallion.new()
	_pearl.name = "PearlMedallion"
	add_child(_pearl)
	_incense = IncenseTimer.new()
	_incense.name = "IncenseTimer"
	add_child(_incense)
	_banner = HudBanner.new()
	_banner.name = "HudBanner"
	add_child(_banner)
	add_child(HintSlip.new())
	var sighting := SightingCard.new()
	sighting.name = "SightingCard"
	add_child(sighting)
	var story := StoryPanel.new()
	story.z_index = 10 # above the HUD's icon and text layers
	add_child(story)
	_setup_touch_ui()
	if not GameManager.is_touch_ui():
		_setup_desktop_pause()

	EventBus.sun_amount_changed.connect(_on_currency_changed)
	EventBus.round_state_changed.connect(_on_round_state_changed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.huge_wave_incoming.connect(_on_huge_wave_incoming)
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.briefing_closed.connect(_on_briefing_closed)
	EventBus.lan_guest_changed.connect(_on_lan_guest_changed)
	EventBus.lan_link_lost.connect(_on_lan_link_lost)
	_on_currency_changed(GameManager.current_sun)
	_on_round_state_changed(GameManager.round_state)
	_layout.call_deferred()
	get_viewport().size_changed.connect(_layout)
	if "--no-hud" in args:
		visible = false
	if "--hud-demo" in args:
		load("res://src/ui/HudDemo.gd").new().run(self)


## The engine wraps a custom tooltip in its own panel; HudTooltip brings its own shape.
func _tooltip_theme() -> Theme:
	var tips := Theme.new()
	tips.set_stylebox("panel", "TooltipPanel", StyleBoxEmpty.new())
	return tips


## LAN feedback: one transient banner, no persistent nodes (solo draw calls are
## untouched). The host keeps playing when the guest drops.
func _on_lan_guest_changed(joined: bool) -> void:
	if GameManager and GameManager.is_client():
		return
	if joined:
		_banner.show_banner(tr("Friend joined on the local network"), HudBanner.Kind.NOTICE)
	else:
		_banner.show_banner(tr("Friend left — playing solo"), HudBanner.Kind.NOTICE)


func _on_lan_link_lost(reason: String) -> void:
	_banner.show_banner(reason, HudBanner.Kind.NOTICE)


## On-screen pause/rotate/cancel buttons exist only on a touch device, so a
## desktop scene keeps its exact node tree and draw calls. --perf-test never
## builds them: its draw-call baseline is the desktop layout.
func _setup_touch_ui() -> void:
	if not GameManager.is_touch_ui():
		return
	if "--perf-test" in OS.get_cmdline_user_args():
		return
	var controls := TouchControls.new()
	controls.name = "TouchControls"
	add_child(controls)


## Pause on a mouse: Esc still works, but a pause the player can see is friendlier.
func _setup_desktop_pause() -> void:
	_pause = HudHit.new()
	_pause.name = "Pause"
	_pause.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause.size = Vector2(PAUSE_SIZE, PAUSE_SIZE)
	_pause.custom_minimum_size = _pause.size
	_pause.set_tip(tr("Pause"), tr("Esc"))
	_pause.pressed.connect(func() -> void: EventBus.pause_requested.emit())
	add_child(_pause)


## Right cluster and the notch / home-indicator padding. SafeArea is a no-op on
## desktop; it caches authored offsets, so re-authoring here must clear them first.
func _layout() -> void:
	var width := get_viewport_rect().size.x
	var right := EDGE + (TOUCH_PAUSE_SIZE if GameManager.is_touch_ui() else PAUSE_SIZE) + GAP
	if _pause != null:
		_pin_top_right(_pause, EDGE, RAIL_TOP + 13.0, Vector2(PAUSE_SIZE, PAUSE_SIZE))
	_pin_top_right(_pearl, right, PEARL_TOP, PearlMedallion.PANEL_SIZE)
	if _leyline != null:
		if _leyline.has_meta(SafeArea.META_BASE):
			_leyline.remove_meta(SafeArea.META_BASE)
		if width >= WIDE_ENOUGH:
			_pin_top_right(_leyline, right + PearlMedallion.PANEL_SIZE.x + GAP, RAIL_TOP + 15.0, LevelProgressBar.PANEL_SIZE)
		else:
			_leyline.anchor_left = 0.5
			_leyline.anchor_right = 0.5
			_leyline.anchor_top = 1.0
			_leyline.anchor_bottom = 1.0
			_leyline.offset_left = -LevelProgressBar.PANEL_SIZE.x * 0.5
			_leyline.offset_right = LevelProgressBar.PANEL_SIZE.x * 0.5
			_leyline.offset_top = LEYLINE_BOTTOM_TOP
			_leyline.offset_bottom = LEYLINE_BOTTOM_TOP + LevelProgressBar.PANEL_SIZE.y
			SafeArea.apply(_leyline)
	if _top_bar.has_meta(SafeArea.META_BASE):
		_top_bar.remove_meta(SafeArea.META_BASE)
	SafeArea.apply(_top_bar)
	if _incense.has_meta(SafeArea.META_BASE):
		_incense.remove_meta(SafeArea.META_BASE)
	SafeArea.apply(_incense)
	HudCanvas.dirty()


func _pin_top_right(control: Control, from_right: float, top: float, widget_size: Vector2) -> void:
	if control.has_meta(SafeArea.META_BASE):
		control.remove_meta(SafeArea.META_BASE)
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = -from_right - widget_size.x
	control.offset_right = -from_right
	control.offset_top = top
	control.offset_bottom = top + widget_size.y
	SafeArea.apply(control)


## Round banner flow: incense during setup, a plaque on wave start, huge-wave warning per
## sub-wave, won/lost hand over to BattlePanel (R still retries). All signal-driven.
func _on_round_state_changed(state: String) -> void:
	if state != "wave":
		_banner.hide_slip()
	_incense.visible = state == "setup"
	if _pause != null:
		_pause.visible = state in ["setup", "wave", "sandbox"]
	if state != "wave":
		_banner.hide_banner()
	HudCanvas.dirty()


func _on_wave_started(_wave_index: int) -> void:
	# Level mode: the first sub-wave gets the night banner; huge waves get
	# their own warning via huge_wave_incoming (avoids a banner per trickle).
	if GameManager and bool(GameManager.get("level_active")):
		if int(_wave_index) == 0:
			_banner.show_banner(_first_wave_banner())
		return
	_banner.show_banner(_first_wave_banner())


func _first_wave_banner() -> String:
	return tr("Survive the night!") if not GameManager.is_day else tr("Defend the park!")


## PvZ2 huge-wave telegraph: red plaque 3s before the burst lands.
func _on_huge_wave_incoming(_wave_idx: int) -> void:
	_banner.show_banner(tr("Huge Wave Approaching!"), HudBanner.Kind.DANGER)
	var lines: Array[String] = []
	if GameManager.level_active:
		lines = LevelDB.story_lines(GameManager.current_level_id, "huge_wave")
	if not lines.is_empty():
		_banner.show_slip(tr(lines[_huge_waves_seen % lines.size()]))
	_huge_waves_seen += 1


func _on_level_completed(_world_id: String, _level_id: String) -> void:
	pass # won banner comes from round_state_changed; kept for future stars UI


func _on_briefing_closed() -> void:
	_banner.show_banner(tr("Strike the gong!"))


func _unhandled_input(event: InputEvent) -> void:
	# Post-round restart. Guarded like every other global key: overlays own
	# input while open, and an in-flight placement keeps R as rotate (see
	# PlacementManager._rotate_placement).
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and GameManager and (GameManager.round_state == "won" or GameManager.round_state == "lost"):
			if GameManager.is_any_selector_open():
				return
			if not GameManager.selected_plant_for(GameManager.local_player_id()).is_empty():
				return
			GameFlow.retry() if GameManager.level_active else get_tree().reload_current_scene()
			get_viewport().set_input_as_handled()

func _on_currency_changed(new_amount: int) -> void:
	if _shown_sun < 0:
		_shown_sun = new_amount
		_target_sun = new_amount
		_gem_label.text = "%d" % new_amount
		return
	var delta := new_amount - _target_sun
	_target_sun = new_amount
	if _count_tween != null:
		_count_tween.kill()
	_count_tween = create_tween()
	_count_tween.tween_method(_show_count, _shown_sun, new_amount, COUNT_SEC)
	_show_delta(delta)
	if delta > 0:
		_pop_counter()


func _show_count(value: int) -> void:
	_shown_sun = value
	_gem_label.text = "%d" % value


## Collecting swells the counter a touch: squash and stretch, then settle.
func _pop_counter() -> void:
	if _pop_tween != null:
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.tween_property(_gem_panel, "scale", Vector2(1.06, 1.06), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(_gem_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	HudCanvas.animate(0.3)


## "+25" / "-100" on a chip under the counter, for a moment.
func _show_delta(delta: int) -> void:
	if delta == 0:
		return
	_delta_label.text = "+%d" % delta if delta > 0 else "−%d" % -delta
	_delta_label.visible = true
	_delta_label.modulate.a = 1.0
	_delta_alpha = 1.0
	if _delta_tween != null:
		_delta_tween.kill()
	_delta_tween = create_tween()
	_delta_tween.tween_interval(DELTA_HOLD_SEC)
	_delta_tween.tween_method(_set_delta_alpha, 1.0, 0.0, 0.25)
	_delta_tween.tween_callback(_delta_label.hide)
	HudCanvas.dirty()


func _set_delta_alpha(value: float) -> void:
	_delta_alpha = value
	_delta_label.modulate.a = value
	HudCanvas.dirty()


func paint_hud(p: HudPainter) -> void:
	_paint_rail(p)
	p.xf = _gem_panel.get_global_transform()
	var shape := HudPainter.chamfered(Rect2(Vector2.ZERO, COUNTER_SIZE), 6.0)
	p.lacquer(shape, UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT)
	p.stroke(HudPainter.chamfered(Rect2(Vector2.ZERO, COUNTER_SIZE).grow(-3.0), 4.0), 0.9, Color(UiPalette.HUD_GOLD, 0.75))
	p.gem(COUNTER_GEM, 15.0)
	if _delta_label.visible:
		var chip := HudPainter.chamfered(Rect2(_delta_label.position, _delta_label.size), 4.0)
		p.fill(chip, Color(UiPalette.HUD_LACQUER_TOP, _delta_alpha))
		p.stroke(chip, 1.2, Color(UiPalette.HUD_GOLD, _delta_alpha))
	if _pause != null and _pause.is_visible_in_tree():
		p.xf = _pause.get_global_transform()
		p.button(_pause, _pause.size)
		p.glyph_pause(_pause.size * 0.5, UiPalette.HUD_SEAL_INK if _pause.is_pressed() else UiPalette.HUD_INK)


## The rail everything hangs from: a thin lacquer bar with one gold line.
func _paint_rail(p: HudPainter) -> void:
	p.xf = Transform2D.IDENTITY
	var bar := _top_bar.get_global_rect()
	var rect := Rect2(bar.position.x + EDGE, bar.position.y + RAIL_TOP, bar.size.x - EDGE * 2.0, RAIL_HEIGHT)
	var shape := HudPainter.chamfered(rect, 2.0)
	p.fill(HudPainter.offset(shape, 1.4), UiPalette.HUD_EDGE)
	p.fill(shape, UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT)
	var inlay_y := rect.position.y + 3.5
	p.line(PackedVector2Array([Vector2(rect.position.x + 4.0, inlay_y), Vector2(rect.end.x - 4.0, inlay_y)]), 1.0, UiPalette.HUD_GOLD)
