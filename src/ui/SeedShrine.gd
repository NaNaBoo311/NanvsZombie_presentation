class_name SeedShrine
extends Control

# Seed Shrine: where Leyline Jade (the meta currency Progress pays per level win)
# is spent, opened from the atlas. It lists every seed in seed-bank order with its
# state: owned, awakened by clearing a level (seed "unlock": {"after": id}), or
# for sale ({"jade": N}, a Buy button). One more row buys the next seed-bank slot
# (Progress.next_slot_cost). Prices and rules live in Progress / the unit JSON;
# this panel only reads them and calls Progress.buy_plant / buy_slot, then
# rebuilds on EventBus.progress_changed. Icons are the seed's emoji (no baked
# textures). Esc / Android Back / Close shut it.

signal closed

var _jade: Label
var _slots: Label
var _slot_button: Button
var _list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()
	EventBus.progress_changed.connect(_refresh)


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close()


func _refresh() -> void:
	if not visible:
		return
	_jade.text = tr("Leyline Jade: %d") % Progress.jade
	var cost := Progress.next_slot_cost()
	_slots.text = tr("Seed slots: %d / %d") % [Progress.seed_slots(), SeedBank.TOTAL_SLOTS]
	_slot_button.visible = cost > 0
	_slot_button.text = tr("Add a slot — %d Jade") % cost
	_slot_button.disabled = Progress.jade < cost
	for child in _list.get_children():
		child.queue_free()
	for entry in BalanceDB.seeds():
		_list.add_child(_row(entry))


func _row(entry: Dictionary) -> Control:
	var id := str(entry["id"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := Label.new()
	icon.text = str(entry["icon"])
	icon.custom_minimum_size = Vector2(32.0, 0.0)
	icon.add_theme_font_size_override("font_size", 22)
	row.add_child(icon)
	var label := Label.new()
	label.text = tr(str(entry["name"]))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", UiPalette.INK)
	row.add_child(label)
	var price := Progress.plant_price(id)
	if Progress.is_plant_owned(id):
		row.add_child(_note(tr("Owned"), UiPalette.INK_SOFT))
	elif price > 0:
		var buy := _button(tr("Buy — %d Jade") % price)
		buy.disabled = Progress.jade < price
		buy.pressed.connect(func() -> void: Progress.buy_plant(id))
		row.add_child(buy)
	else:
		var unlock: Variant = BalanceDB.seed_unlock(id)
		var level_name := str(LevelDB.get_level(str(unlock["after"])).get("name", unlock["after"]))
		row.add_child(_note(tr("Clear %s") % tr(level_name), UiPalette.COST_INK))
	return row


func _note(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	return l


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.04, 0.06, 0.74)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var view := get_viewport_rect().size
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(520.0, view.x - 32.0), 0.0)
	panel.add_theme_stylebox_override("panel", UiPalette.box(UiPalette.PAPER, UiPalette.BAMBOO_EDGE, 14, 3, 22, Color(0, 0, 0, 0.35), 10))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = tr("Seed Shrine")
	title.add_theme_font_override("font", UiPalette.bold_font())
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiPalette.INK)
	box.add_child(title)

	_jade = _note("", UiPalette.COST_INK)
	_jade.add_theme_font_size_override("font_size", 20)
	box.add_child(_jade)

	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 10)
	box.add_child(slot_row)
	_slots = _note("", UiPalette.INK)
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_row.add_child(_slots)
	_slot_button = _button("")
	_slot_button.pressed.connect(func() -> void: Progress.buy_slot())
	slot_row.add_child(_slot_button)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, minf(380.0, view.y - 260.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	var close_button := _button(tr("Close"))
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(close)
	box.add_child(close_button)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 40.0)
	b.add_theme_stylebox_override("normal", UiPalette.box(UiPalette.PAPER_WARM, UiPalette.PAPER_EDGE, 8, 2, 10))
	b.add_theme_stylebox_override("hover", UiPalette.box(Color(1.0, 0.95, 0.80), UiPalette.AMBER, 8, 2, 10))
	b.add_theme_stylebox_override("pressed", UiPalette.box(UiPalette.PAPER, UiPalette.PAPER_EDGE, 8, 2, 10))
	b.add_theme_stylebox_override("disabled", UiPalette.box(UiPalette.PAPER, UiPalette.PAPER_EDGE, 8, 2, 10))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, UiPalette.INK)
	b.add_theme_color_override("font_disabled_color", UiPalette.INK_SOFT)
	return b
