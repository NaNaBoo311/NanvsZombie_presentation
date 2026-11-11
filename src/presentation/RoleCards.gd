class_name RoleCards
extends Control

# Section 02, beat 2: the three seeds the section teaches, revealed the way a win
# reveals a new plant. Each card is a lacquer plate painted by HudPainter, with the
# plant's own model baked once by IconBaker; the row rises, flips face-up one card
# at a time, and then waits. No textures, no viewports left running: the bake stage
# is hidden and the rays only tick while the row is on screen.
#
# The copy comes from PresentationDeck.CORE_ROLES; the names, subtitles and models
# come from BalanceDB, so a card can never drift from the unit it describes.

signal finished

const CARD_SIZE := Vector2(240.0, 330.0)
const GAP := 24.0
const RISE_SEC := 0.55
const FLIP_SEC := 0.18
const ICON_RECT := Rect2(20.0, 18.0, 200.0, 190.0)

var _cards: Array[Control] = []
var _home: Array[Vector2] = []
var _heading: Label
var _subheading: Label
var _continue: Button
var _rays: ResultFx
var _dim: ColorRect
var _glow := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_dim()
	_build_rays()
	_build_heading()
	_build_cards()
	_build_continue()
	_layout()
	visible = false


func play() -> void:
	visible = true
	modulate.a = 1.0
	_dim.modulate.a = 0.0
	_heading.modulate.a = 0.0
	_subheading.modulate.a = 0.0
	_continue.modulate.a = 0.0
	_continue.disabled = true
	_rays.running = true
	_glow = 0.0
	for card in _cards:
		card.modulate.a = 0.0
		card.set_meta("shown", false)
		_set_face(card, false)
	for i in _cards.size():
		_cards[i].position = _home[i] + Vector2(0.0, 74.0)
		_cards[i].scale = Vector2.ONE * 0.35

	var lead := create_tween()
	lead.tween_property(_dim, "modulate:a", 1.0, 0.3)
	lead.parallel().tween_property(_heading, "modulate:a", 1.0, 0.45)
	lead.parallel().tween_property(_subheading, "modulate:a", 1.0, 0.45)
	lead.parallel().tween_property(self, "_glow", 1.0, 0.6)

	for i in _cards.size():
		var card := _cards[i]
		var tween := create_tween()
		tween.tween_interval(0.16 * i)
		tween.tween_property(card, "modulate:a", 1.0, 0.28)
		tween.parallel().tween_property(card, "position", _home[i], RISE_SEC) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(card, "scale", Vector2.ONE, RISE_SEC) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(0.12)
		tween.tween_property(card, "scale:x", 0.0, FLIP_SEC) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(_set_face.bind(card, true))
		tween.tween_callback(Audio.play.bind(Audio.RICE_GEM_COLLECT))
		tween.tween_property(card, "scale:x", 1.12, FLIP_SEC) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(card, "scale:y", 1.12, FLIP_SEC)
		tween.tween_property(card, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		if i == _cards.size() - 1:
			tween.tween_property(_continue, "modulate:a", 1.0, 0.2)
			tween.tween_callback(func() -> void:
				_continue.disabled = false
				_continue.grab_focus())


# ------------------------------------------------------------------- build ---

func _build_dim() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(UiPalette.HUD_DIM, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)


func _build_rays() -> void:
	_rays = ResultFx.new()
	_rays.name = "Rays"
	_rays.paint = _paint_rays
	add_child(_rays)
	_rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_heading() -> void:
	_heading = _label(PresentationDeck.CORE_ROLES_TITLE, 34, UiPalette.HUD_INK)
	_heading.name = "Heading"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.anchor_right = 1.0
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_heading)

	_subheading = _label(PresentationDeck.CORE_ROLES_BODY, 16, UiPalette.HUD_INK_SOFT)
	_subheading.name = "Subheading"
	_subheading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subheading.anchor_right = 1.0
	_subheading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subheading)


func _build_cards() -> void:
	var bake_items: Array = []
	for spec: Dictionary in PresentationDeck.CORE_ROLES:
		var unit := BalanceDB.get_unit(str(spec["id"]))
		var card := Control.new()
		card.name = "Card_%s" % str(spec["id"])
		card.size = CARD_SIZE
		card.pivot_offset = CARD_SIZE * 0.5
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.set_meta("shown", false)
		add_child(card)

		var face := ResultFx.new()
		face.name = "Face"
		face.paint = _paint_card.bind(face)
		face.running = true
		card.add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.position = ICON_RECT.position
		icon.size = ICON_RECT.size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(icon)

		var name_label := _label(str(unit.get("name", spec["id"])), 20, UiPalette.HUD_INK)
		name_label.name = "Name"
		name_label.position = Vector2(8.0, 214.0)
		name_label.size = Vector2(CARD_SIZE.x - 16.0, 28.0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(name_label)

		var role := _label(str(spec["role"]), 10, UiPalette.HUD_GOLD, 2.4)
		role.name = "Role"
		role.position = Vector2(8.0, 244.0)
		role.size = Vector2(CARD_SIZE.x - 16.0, 18.0)
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(role)

		var line := _label(str(spec["line"]), 14, UiPalette.HUD_INK_SOFT)
		line.name = "Line"
		line.position = Vector2(18.0, 270.0)
		line.size = Vector2(CARD_SIZE.x - 36.0, 46.0)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(line)

		_cards.append(card)
		_home.append(Vector2.ZERO)

		var model := str(unit.get("model", ""))
		if not model.is_empty():
			var path := model if model.begins_with("res://") else "res://assets/models/" + model
			bake_items.append({"rect": icon, "model": path, "scale": 1.0, "fit": true})
	if not bake_items.is_empty():
		IconBaker.bake(self, bake_items, UiPalette.ICON_AMBIENT)


func _build_continue() -> void:
	_continue = Button.new()
	_continue.name = "ContinueButton"
	_continue.text = tr(PresentationDeck.CORE_ROLES_CONTINUE)
	_continue.size = Vector2(210.0, 46.0)
	_continue.custom_minimum_size = Vector2(210.0, 46.0)
	_continue.mouse_filter = Control.MOUSE_FILTER_STOP
	UiPalette.lacquer_button(_continue, true, false, 20)
	_continue.pressed.connect(_dismiss)
	add_child(_continue)


func _layout() -> void:
	var view := get_viewport_rect().size
	var total := CARD_SIZE.x * _cards.size() + GAP * float(_cards.size() - 1)
	var origin := Vector2((view.x - total) * 0.5, (view.y - CARD_SIZE.y) * 0.5 + 14.0)
	for i in _cards.size():
		_home[i] = origin + Vector2(float(i) * (CARD_SIZE.x + GAP), 0.0)
		_cards[i].position = _home[i]
	_heading.offset_left = 0.0
	_heading.offset_right = 0.0
	_heading.offset_top = origin.y - 96.0
	_heading.offset_bottom = origin.y - 52.0
	_subheading.offset_left = 0.0
	_subheading.offset_right = 0.0
	_subheading.offset_top = origin.y - 54.0
	_subheading.offset_bottom = origin.y - 28.0
	_continue.position = Vector2((view.x - _continue.size.x) * 0.5, origin.y + CARD_SIZE.y + 26.0)
	_rays.queue_redraw()


# ------------------------------------------------------------------ paint ---

func _set_face(card: Control, front: bool) -> void:
	card.set_meta("shown", front)
	for child in card.get_children():
		if child is TextureRect or child is Label:
			(child as Control).visible = front


func _paint_card(p: HudPainter, face: Control) -> void:
	var card := face.get_parent() as Control
	p.xf = Transform2D.IDENTITY
	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
	var shape := HudPainter.chamfered(rect, 14.0)
	p.glow(HudPainter.offset(shape, 3.0), Color(UiPalette.HUD_DAWN, 0.45 * _glow), 16.0)
	p.lacquer(shape, UiPalette.HUD_LACQUER_LIT, UiPalette.HUD_LACQUER_BOT,
		UiPalette.HUD_ACCENT, 5.0)
	p.stroke(HudPainter.chamfered(rect.grow(-6.0), 10.0), 1.2, UiPalette.HUD_GOLD)
	if bool(card.get_meta("shown", false)):
		var disc := Vector2(CARD_SIZE.x * 0.5, 112.0)
		p.fill(HudPainter.circle(disc, 94.0), UiPalette.HUD_ICON_DISC)
		p.stroke(HudPainter.circle(disc, 94.0), 2.0, UiPalette.HUD_GOLD)
		return
	# The sealed back: the logo's Pearl, the same face a new seed shows first.
	var c := CARD_SIZE * 0.5
	p.stroke(HudPainter.circle(c, 54.0), 3.0, UiPalette.HUD_GOLD)
	p.rays(c, 96.0, 16, 0.0, 0.05, Color(UiPalette.HUD_GOLD, 0.8))
	p.fill(HudPainter.circle(c, 28.0), UiPalette.HUD_PEARL_TOP, UiPalette.HUD_PEARL_BOT)
	p.stroke(HudPainter.circle(c, 28.0), 1.6, UiPalette.HUD_EDGE)


func _paint_rays(p: HudPainter) -> void:
	if _cards.is_empty():
		return
	var left := _home[0]
	var right := _home[_home.size() - 1]
	var centre := Vector2((left.x + right.x + CARD_SIZE.x) * 0.5, left.y + CARD_SIZE.y * 0.5)
	var spin := Time.get_ticks_msec() / 1000.0 * 0.18
	p.rays(centre, 880.0, 18, spin, 0.09, Color(UiPalette.HUD_DAWN, 0.14 * _glow))
	p.rays(centre, 620.0, 11, -spin * 1.5, 0.06, Color(UiPalette.HUD_FLASH, 0.10 * _glow))


# ------------------------------------------------------------------ close ---

func _dismiss() -> void:
	Audio.play(Audio.UI_CLICK)
	_continue.disabled = true
	_rays.running = false
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.28)
	tween.tween_callback(func() -> void:
		visible = false
		finished.emit())


# ------------------------------------------------------------------- bits ---

func _label(text: String, font_size: int, color: Color, tracking: int = 0) -> Label:
	var label := Label.new()
	label.text = tr(text)
	var font := UiPalette.hud_font()
	if tracking != 0:
		var varied := FontVariation.new()
		varied.base_font = font
		varied.spacing_glyph = tracking
		font = varied
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
