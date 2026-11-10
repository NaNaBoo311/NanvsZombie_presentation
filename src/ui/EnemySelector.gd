class_name EnemySelector
extends Control

# TEMP DEBUG TOOL - pairs with EnemyDebugSpawner (TODO REMOVE both when waves land).
# Pick which playable enemy G+click spawns: H toggles this overlay, one click
# arms the spawner via GameManager.set_debug_enemy() and closes immediately.
# Self-contained: cards built once in _ready (icons baked once via IconBaker,
# zero per-frame cost), game clicks blocked by Dim while open. Does NOT cancel
# plant placement (testers plant first, then spawn). Closes itself when the
# SeedSelector opens and vice versa (mutual exclusion via toggled signals).

@onready var enemy_grid: GridContainer = $Center/Popup/Margin/VBox/EnemyGrid
@onready var armed_label: Label = $Center/Popup/Margin/VBox/ArmedLabel

var selected_id: String = ""
var is_open: bool = false

var _cards: Dictionary = {} # enemy_id -> PanelContainer card
var _check_labels: Dictionary = {} # enemy_id -> Label check overlay
var _bounce_tweens: Dictionary = {} # card -> Tween

var normal_style: StyleBoxFlat
var selected_style: StyleBoxFlat


func _ready() -> void:
	_setup_styles()
	_build_cards()
	sync_from_game()
	visible = false
	is_open = false
	if EventBus:
		EventBus.seed_selector_toggled.connect(_on_seed_selector_toggled)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_open:
			close()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	sync_from_game()
	is_open = true
	visible = true
	if GameManager:
		GameManager.is_enemy_selector_open = true
	EventBus.enemy_selector_toggled.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if GameManager:
		GameManager.is_enemy_selector_open = false
	EventBus.enemy_selector_toggled.emit(false)


func sync_from_game() -> void:
	selected_id = str(GameManager.debug_enemy_id) if GameManager else ""
	_refresh_all_visuals()


func _on_seed_selector_toggled(seed_open: bool) -> void:
	if seed_open and is_open:
		close()




func _setup_styles() -> void:
	normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.20, 0.15, 0.22, 0.95)
	normal_style.border_color = Color(0.45, 0.35, 0.50, 0.8)
	normal_style.border_width_left = 2
	normal_style.border_width_top = 2
	normal_style.border_width_right = 2
	normal_style.border_width_bottom = 2
	normal_style.corner_radius_top_left = 10
	normal_style.corner_radius_top_right = 10
	normal_style.corner_radius_bottom_right = 10
	normal_style.corner_radius_bottom_left = 10
	normal_style.content_margin_left = 6
	normal_style.content_margin_right = 6
	normal_style.content_margin_top = 6
	normal_style.content_margin_bottom = 6

	selected_style = StyleBoxFlat.new()
	selected_style.bg_color = Color(0.30, 0.20, 0.34, 0.98)
	selected_style.border_color = Color(0.85, 0.45, 1.0, 1.0)
	selected_style.border_width_left = 3
	selected_style.border_width_top = 3
	selected_style.border_width_right = 3
	selected_style.border_width_bottom = 3
	selected_style.corner_radius_top_left = 10
	selected_style.corner_radius_top_right = 10
	selected_style.corner_radius_bottom_right = 10
	selected_style.corner_radius_bottom_left = 10
	selected_style.shadow_color = Color(0.85, 0.45, 1.0, 0.5)
	selected_style.shadow_size = 8
	selected_style.content_margin_left = 6
	selected_style.content_margin_right = 6
	selected_style.content_margin_top = 6
	selected_style.content_margin_bottom = 6


func _build_cards() -> void:
	for child in enemy_grid.get_children():
		child.queue_free()
	_cards.clear()
	_check_labels.clear()
	for data in BalanceDB.enemies():
		var card := _create_card(data)
		enemy_grid.add_child(card)
		_cards[data.id] = card
	_bake_icons()
	_refresh_all_visuals()


func _create_card(data: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Card_%s" % data.id
	card.custom_minimum_size = Vector2(120, 158)
	card.size = Vector2(120, 158)
	card.pivot_offset = Vector2(60, 79)
	card.add_theme_stylebox_override("panel", normal_style)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.clip_contents = false # Contents fit by layout; clipping breaks 2D batching.

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(vbox)

	vbox.add_child(_create_model_icon(str(data.preview_model), float(data.get("preview_scale", 1.5))))

	var name_label := Label.new()
	name_label.text = tr(str(data.name))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.93, 0.88, 0.96, 1.0))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var hint_label := Label.new()
	hint_label.text = tr("G+click spawns")
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.80, 0.9))
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint_label)

	var check := Label.new()
	check.name = "CheckBadge"
	check.text = "✔"
	check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check.add_theme_font_size_override("font_size", 28)
	check.add_theme_color_override("font_color", Color(0.85, 0.45, 1.0, 1.0))
	check.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	check.add_theme_constant_override("shadow_offset_x", 2)
	check.add_theme_constant_override("shadow_offset_y", 2)
	check.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	check.position = Vector2(86, 2)
	check.size = Vector2(32, 32)
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check.visible = false
	card.add_child(check)
	_check_labels[data.id] = check

	var enemy_id := str(data.id)
	var btn := Button.new()
	btn.name = "CardButton"
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty_sb := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("disabled", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.pressed.connect(_on_card_pressed.bind(enemy_id))
	card.add_child(btn)

	return card


func _create_model_icon(model_path: String, model_scale: float) -> Control:
	# Baked preview via IconBaker (never a live SubViewportContainer:
	# TRAPS.md#subviewport-container-flip). Same 104px footprint as before.
	var rect := TextureRect.new()
	rect.name = "IconTexture"
	rect.custom_minimum_size = Vector2(104, 104)
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_meta("model_path", model_path)
	rect.set_meta("model_scale", model_scale)
	return rect

# Cards are built once in _ready; bake their icons once right after.
func _bake_icons() -> void:
	var items: Array = []
	for card in _cards.values():
		var rect := (card as Control).find_child("IconTexture", true, false) as TextureRect
		if rect != null and is_instance_valid(rect):
			items.append({"rect": rect, "model": str(rect.get_meta("model_path")),
				"scale": float(rect.get_meta("model_scale"))})
	IconBaker.bake(self, items, Color(0.60, 0.55, 0.65))


func _on_card_pressed(enemy_id: String) -> void:
	# Single-select: arm the G-spawner and close immediately (fast testing loop).
	if GameManager:
		GameManager.set_debug_enemy(enemy_id)
	selected_id = enemy_id
	_refresh_all_visuals()
	_play_bounce(_cards.get(enemy_id))
	close()


func _refresh_all_visuals() -> void:
	for enemy_id in _cards:
		_refresh_card(enemy_id)
	_update_armed_label()


func _refresh_card(enemy_id: String) -> void:
	var card: Control = _cards.get(enemy_id)
	if not is_instance_valid(card):
		return
	var check: Label = _check_labels.get(enemy_id)
	var is_armed := enemy_id == selected_id
	card.add_theme_stylebox_override("panel", selected_style if is_armed else normal_style)
	if is_instance_valid(check):
		check.visible = is_armed


func _update_armed_label() -> void:
	if not is_instance_valid(armed_label):
		return
	var display := selected_id
	for data in BalanceDB.enemies():
		if str(data.id) == selected_id:
			display = tr(str(data.name))
	armed_label.text = tr("Armed: %s  (G + click spawns)") % display


func _play_bounce(card: Variant) -> void:
	if not (card is Control) or not is_instance_valid(card):
		return
	if _bounce_tweens.has(card):
		var old_tween: Tween = _bounce_tweens[card]
		if is_instance_valid(old_tween):
			old_tween.kill()
	var tween := create_tween()
	_bounce_tweens[card] = tween
	tween.tween_property(card, "scale", Vector2(1.12, 1.12), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
