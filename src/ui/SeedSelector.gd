class_name SeedSelector
extends Control

# Dev-only seed picker (TAB overlay): shows EVERY seed in BalanceDB.seeds(),
# click toggles membership in the round loadout, Confirm pushes it to the
# SeedBank via GameManager.set_seed_loadout(). The real game flow is the
# pre-battle loadout briefing (LoadoutBriefing); TAB only opens when no level is
# active (sandbox, --screenshot, scene run directly) or --dev-seeds is passed.
# Cards are grouped into role sections (seed "group", GROUPS below) and hovering one
# fills the detail panel from its unit JSON. Look: UiPalette (bamboo & paper).
# Self-contained: builds cards once in _ready (icons baked once via IconBaker,
# zero per-frame cost), owns its open/close state, blocks game clicks via Dim.

@onready var sections: VBoxContainer = $Center/Popup/Margin/VBox/Sections
@onready var detail_panel: PanelContainer = $Center/Popup/Margin/VBox/Detail
@onready var title_label: Label = $Center/Popup/Margin/VBox/Title
@onready var counter_label: Label = $Center/Popup/Margin/VBox/CounterLabel
@onready var confirm_button: Button = $Center/Popup/Margin/VBox/Footer/ConfirmButton
@onready var clear_button: Button = $Center/Popup/Margin/VBox/Footer/ClearButton

var selected_ids: Array[String] = []
var is_open: bool = false

var _cards: Dictionary = {} # seed_id -> PanelContainer card
var _check_labels: Dictionary = {} # seed_id -> Label check overlay
var _soon: Dictionary = {} # seed_id -> true while the seed is not playable yet
var _bounce_tweens: Dictionary = {} # card -> Tween
var _detail_name: Label
var _detail_sub: Label
var _detail_traits: Label
var _detail_text: Label

## Role sections in display order: [seed "group" (data/units/plants/<id>.json), header,
## row]. Sections sharing a row sit side by side. Seeds with no or an unknown group
## land in the last section.
const GROUPS: Array = [
	["shooter", "SHOOTERS", 0],
	["defender", "DEFENDERS & TRAPS", 1],
	["support", "SUPPORT", 1],
]
const GRID_COLUMNS := 5
## Every card is exactly this size: names wrap to two lines instead of widening the card.
const CARD_SIZE := Vector2i(112, 158)

var normal_style: StyleBoxFlat
var selected_style: StyleBoxFlat
var soon_style: StyleBoxFlat # "coming soon" seeds: not plantable yet (BalanceDB.is_playable)


func _ready() -> void:
	_setup_styles()
	_build_detail_panel()
	_build_cards()
	sync_from_game()
	visible = false
	is_open = false
	title_label.add_theme_font_override("font", UiPalette.bold_font())
	$Center/Popup.add_child(BambooTrim.new()) # woven-bamboo border, last so it draws on top
	_style_button(clear_button, false)
	_style_button(confirm_button, true)
	confirm_button.pressed.connect(_on_confirm_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	if EventBus:
		EventBus.enemy_selector_toggled.connect(_on_enemy_selector_toggled)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			if _tab_allowed():
				toggle()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_open:
			close()
			get_viewport().set_input_as_handled()


## TAB stays a development tool: while a level is active without --dev-seeds it does nothing.
func _tab_allowed() -> bool:
	if GameManager and bool(GameManager.get("level_active")):
		return "--dev-seeds" in OS.get_cmdline_user_args()
	return true


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	sync_from_game()
	# Cancel any active placement ghost so Left-clicks belong to the panel.
	if GameManager and not GameManager.selected_plant_to_place.is_empty():
		GameManager.clear_selection()
	if GameManager and GameManager.is_shovel_mode:
		GameManager.cancel_shovel()
	is_open = true
	visible = true
	if GameManager:
		GameManager.is_seed_selector_open = true
	EventBus.seed_selector_toggled.emit(true)


func close() -> void:
	is_open = false
	visible = false
	if GameManager:
		GameManager.is_seed_selector_open = false
	EventBus.seed_selector_toggled.emit(false)


func sync_from_game() -> void:
	selected_ids.clear()
	if GameManager:
		for sid in GameManager.seed_loadout:
			selected_ids.append(str(sid))
	_refresh_all_visuals()


func _on_enemy_selector_toggled(enemy_open: bool) -> void:
	if enemy_open and is_open:
		close()




func _max_slots() -> int:
	return SeedBank.TOTAL_SLOTS


func _setup_styles() -> void:
	# Unselected cards sit back (dimmer paper); selected ones are bright with an amber
	# ring, so the loadout reads at a glance even when most seeds are picked.
	normal_style = UiPalette.box(Color(0.80, 0.72, 0.56), UiPalette.PAPER_EDGE, 10, 2, 6)
	selected_style = UiPalette.box(Color(1.0, 0.92, 0.66), UiPalette.AMBER, 10, 4, 6, Color(UiPalette.AMBER, 0.55), 6)
	soon_style = UiPalette.box(Color(0.62, 0.55, 0.44), Color(0.45, 0.36, 0.26, 0.8), 10, 2, 6)


## Paper button; `primary` is the lantern-amber call to action.
func _style_button(btn: Button, primary: bool) -> void:
	var fill := UiPalette.AMBER if primary else UiPalette.PAPER
	var edge := UiPalette.BAMBOO_EDGE
	btn.add_theme_stylebox_override("normal", UiPalette.box(fill, edge, 10, 2, 8))
	btn.add_theme_stylebox_override("hover", UiPalette.box(fill.lightened(0.12), edge, 10, 2, 8))
	btn.add_theme_stylebox_override("pressed", UiPalette.box(fill.darkened(0.12), edge, 10, 2, 8))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, UiPalette.INK)
	btn.add_theme_font_override("font", UiPalette.bold_font())
	btn.add_theme_font_size_override("font_size", 16)


## Hover card under the grid: name, subtitle, trait line and the unit's mechanism text.
func _build_detail_panel() -> void:
	detail_panel.add_theme_stylebox_override("panel", UiPalette.box(UiPalette.PAPER, UiPalette.PAPER_EDGE, 10, 2, 10))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	_detail_name = _ink_label(17, UiPalette.INK, true)
	_detail_sub = _ink_label(13, UiPalette.INK_SOFT, false)
	head.add_child(_detail_name)
	head.add_child(_detail_sub)
	_detail_traits = _ink_label(12, UiPalette.COST_INK, true)
	box.add_child(_detail_traits)
	_detail_text = _ink_label(12, UiPalette.INK, false)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size = Vector2(500, 0)
	box.add_child(_detail_text)
	_show_detail("")


func _ink_label(font_size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", UiPalette.bold_font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _show_detail(seed_id: String) -> void:
	var unit: Dictionary = BalanceDB.get_unit(seed_id) if not seed_id.is_empty() else {}
	if unit.is_empty():
		_detail_name.text = tr("Hover a seed")
		_detail_sub.text = ""
		_detail_traits.text = ""
		_detail_text.text = tr("Its role, traits and behaviour show up here.")
		return
	_detail_name.text = tr(str(unit.get("name", seed_id)))
	_detail_sub.text = tr(str(unit.get("subtitle", "")))
	var traits := PackedStringArray(unit.get("traits", []))
	if not BalanceDB.is_playable(seed_id):
		traits.insert(0, tr("Coming soon"))
	_detail_traits.text = "  ·  ".join(traits)
	_detail_text.text = tr(str(unit.get("mechanism", "")))


func _build_cards() -> void:
	for child in sections.get_children():
		child.queue_free()
	_cards.clear()
	_check_labels.clear()
	_soon.clear()
	var grids: Dictionary = {} # group id -> GridContainer
	var rows: Dictionary = {} # row index -> HBoxContainer
	for g in GROUPS:
		var row_idx := int(g[2])
		if not rows.has(row_idx):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 26)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sections.add_child(row)
			rows[row_idx] = row
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.visible = false
		rows[row_idx].add_child(column)
		var header := _ink_label(12, UiPalette.BAMBOO_EDGE, true)
		header.text = tr(str(g[1]))
		column.add_child(header)
		var grid := GridContainer.new()
		grid.columns = GRID_COLUMNS
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(grid)
		grids[str(g[0])] = grid
	for data in BalanceDB.seeds():
		var gid := str(data.get("group", ""))
		var grid: GridContainer = grids.get(gid, grids[str(GROUPS[GROUPS.size() - 1][0])])
		(grid.get_parent() as Control).visible = true
		var card := _create_card(data)
		grid.add_child(card)
		_cards[data.id] = card
	_bake_icons()
	_update_counter()


func _create_card(data: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Card_%s" % data.id
	card.custom_minimum_size = Vector2(CARD_SIZE)
	card.size = Vector2(CARD_SIZE)
	card.pivot_offset = Vector2(CARD_SIZE) * 0.5
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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

	if data.has("model") and data.model:
		vbox.add_child(_create_model_icon(data.model))
	else:
		var icon_label := Label.new()
		icon_label.text = str(data.get("icon", "?"))
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_label.add_theme_font_size_override("font_size", 40)
		icon_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(icon_label)

	var name_label := Label.new()
	name_label.text = tr(str(data.name))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(CARD_SIZE.x - 14, 30)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", UiPalette.INK)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	# Cost: amber sun coin + number.
	var cost_row := HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 4)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := Panel.new()
	coin.custom_minimum_size = Vector2(12, 12)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.add_theme_stylebox_override("panel", UiPalette.box(UiPalette.AMBER, UiPalette.COST_INK, 6, 2))
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(coin)
	var cost_label := _ink_label(13, UiPalette.COST_INK, true)
	cost_label.text = "%d" % int(data.cost)
	cost_row.add_child(cost_label)
	vbox.add_child(cost_row)

	# Corner stamp (amber seal) shown when this seed is in the loadout; sits in the
	# top-right corner so it never covers the plant.
	var check := Label.new()
	check.name = "CheckBadge"
	check.text = "✓"
	check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check.add_theme_font_size_override("font_size", 14)
	check.add_theme_color_override("font_color", UiPalette.INK)
	check.add_theme_stylebox_override("normal", UiPalette.box(UiPalette.AMBER, UiPalette.COST_INK, 11, 2))
	check.anchor_left = 1.0
	check.anchor_right = 1.0
	check.offset_left = -26.0
	check.offset_right = -4.0
	check.offset_top = 4.0
	check.offset_bottom = 26.0
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check.visible = false
	# A PanelContainer stretches its direct children to fill it: pin the stamp inside
	# a plain full-rect overlay so its own anchors and size hold.
	var overlay := Control.new()
	overlay.name = "StampOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(overlay)
	overlay.add_child(check)

	# Not built yet: a vermilion ribbon over the icon, and the card is inert.
	if not bool(data.get("playable", true)):
		_soon[str(data.id)] = true
		var ribbon := Label.new()
		ribbon.text = tr("COMING SOON")
		ribbon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ribbon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ribbon.add_theme_font_size_override("font_size", 10)
		ribbon.add_theme_color_override("font_color", UiPalette.PAPER_WARM)
		ribbon.add_theme_font_override("font", UiPalette.bold_font())
		ribbon.add_theme_stylebox_override("normal", UiPalette.box(UiPalette.VERMILION, UiPalette.BAMBOO_EDGE, 3, 1, 2))
		ribbon.anchor_left = 0.0
		ribbon.anchor_right = 1.0
		ribbon.offset_left = -3.0
		ribbon.offset_right = 3.0
		ribbon.offset_top = 52.0
		ribbon.offset_bottom = 70.0
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(ribbon)
		vbox.modulate = Color(1, 1, 1, 0.5)
	_check_labels[data.id] = check

	var seed_id := str(data.id)
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
	btn.pressed.connect(_on_card_pressed.bind(seed_id))
	btn.mouse_entered.connect(_show_detail.bind(seed_id))
	btn.mouse_exited.connect(_show_detail.bind(""))
	card.add_child(btn)

	return card


func _create_model_icon(model_path: String) -> Control:
	# Baked preview via IconBaker (never a live SubViewportContainer:
	# TRAPS.md#subviewport-container-flip). Same 96px footprint as before.
	var rect := TextureRect.new()
	rect.name = "IconTexture"
	rect.custom_minimum_size = Vector2(96, 96)
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_meta("model_path", model_path)
	var preview_scale: float = 1.0
	for entry in BalanceDB.seeds():
		if entry["model"] == model_path:
			preview_scale = float(entry["preview_scale"])
	rect.set_meta("model_scale", preview_scale)
	return rect

# Cards are built once in _ready; bake their icons once right after.
func _bake_icons() -> void:
	var items: Array = []
	for card in _cards.values():
		var rect := (card as Control).find_child("IconTexture", true, false) as TextureRect
		if rect != null and is_instance_valid(rect):
			items.append({"rect": rect, "model": str(rect.get_meta("model_path")),
				"scale": float(rect.get_meta("model_scale")), "fit": true})
	IconBaker.bake(self, items, UiPalette.ICON_AMBIENT)


func _on_card_pressed(seed_id: String) -> void:
	if _soon.has(seed_id):
		_play_deny_bounce(_cards[seed_id])
		return
	if selected_ids.has(seed_id):
		selected_ids.erase(seed_id)
	else:
		if selected_ids.size() >= _max_slots():
			_play_deny_bounce(_cards[seed_id])
			return
		selected_ids.append(seed_id)
	_refresh_card(seed_id)
	_play_bounce(_cards[seed_id])
	_update_counter()


func _on_confirm_pressed() -> void:
	if GameManager:
		GameManager.set_seed_loadout(selected_ids.duplicate())
	close()


func _on_clear_pressed() -> void:
	selected_ids.clear()
	_refresh_all_visuals()


func _refresh_all_visuals() -> void:
	for seed_id in _cards:
		_refresh_card(seed_id)
	_update_counter()


func _refresh_card(seed_id: String) -> void:
	var card: Control = _cards.get(seed_id)
	if not is_instance_valid(card):
		return
	var check: Label = _check_labels.get(seed_id)
	var is_selected := selected_ids.has(seed_id)
	if _soon.has(seed_id):
		card.add_theme_stylebox_override("panel", soon_style)
		if is_instance_valid(check):
			check.visible = false
		return
	card.add_theme_stylebox_override("panel", selected_style if is_selected else normal_style)
	if is_instance_valid(check):
		check.visible = is_selected


func _update_counter() -> void:
	if is_instance_valid(counter_label):
		counter_label.text = tr("Selected %d / %d") % [selected_ids.size(), _max_slots()]


func _play_bounce(card: Control) -> void:
	if not is_instance_valid(card):
		return
	if _bounce_tweens.has(card):
		var old_tween: Tween = _bounce_tweens[card]
		if is_instance_valid(old_tween):
			old_tween.kill()
	var tween := create_tween()
	_bounce_tweens[card] = tween
	tween.tween_property(card, "scale", Vector2(1.12, 1.12), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_deny_bounce(card: Control) -> void:
	# Full bank: shake "no" instead of selecting.
	if not is_instance_valid(card):
		return
	if _bounce_tweens.has(card):
		var old_tween: Tween = _bounce_tweens[card]
		if is_instance_valid(old_tween):
			old_tween.kill()
	var tween := create_tween()
	_bounce_tweens[card] = tween
	tween.tween_property(card, "scale", Vector2(0.92, 0.92), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
