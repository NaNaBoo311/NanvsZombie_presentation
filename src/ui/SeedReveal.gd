class_name SeedReveal
extends Control

# The new-plant moment on a win: a sealed lacquer card rises from the Pearl, hangs in a
# burst of light, turns over to show the plant, and names it, then waits for the player.
# Several awakened seeds play one after another. Baked icon (IconBaker), painted card and
# rays (ResultFx); it only exists while it plays.

signal finished

const CARD_SIZE := Vector2(210.0, 286.0)
const RISE_SEC := 0.55
const FLIP_SEC := 0.2
const RAY_SPIN := 0.25

var _queue: Array[String] = []
var _card: Control
var _icon: TextureRect
var _heading: Label
var _name: Label
var _subtitle: Label
var _continue: Button
var _rays: ResultFx
var _shown_face := false
var _glow := 0.0
var _spin := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = UiPalette.HUD_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_rays = ResultFx.new()
	_rays.paint = _paint_rays
	add_child(_rays)
	_rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_heading = _text(30, UiPalette.HUD_ACCENT)
	_heading.text = tr("A new seed awakens!")
	_heading.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_heading.offset_left = -300.0
	_heading.offset_right = 300.0
	_heading.offset_top = 52.0
	_heading.offset_bottom = 96.0
	add_child(_heading)
	_card = Control.new()
	_card.size = CARD_SIZE
	_card.pivot_offset = CARD_SIZE * 0.5
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	_icon = TextureRect.new()
	_icon.position = Vector2(20.0, 22.0)
	_icon.size = Vector2(170.0, 170.0)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_icon)
	_name = _text(22, UiPalette.HUD_INK)
	_name.position = Vector2(8.0, 204.0)
	_name.size = Vector2(CARD_SIZE.x - 16.0, 30.0)
	_card.add_child(_name)
	_subtitle = _text(15, UiPalette.HUD_INK_SOFT)
	_subtitle.position = Vector2(14.0, 234.0)
	_subtitle.size = Vector2(CARD_SIZE.x - 28.0, 40.0)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(_subtitle)
	_continue = Button.new()
	_continue.text = tr("Wonderful!")
	UiPalette.lacquer_button(_continue, true)
	_continue.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_continue.offset_left = -110.0
	_continue.offset_right = 110.0
	_continue.offset_top = -74.0
	_continue.offset_bottom = -26.0
	_continue.pressed.connect(_next)
	add_child(_continue)
	var face := ResultFx.new()
	face.paint = _paint_card
	add_child(face)
	move_child(face, _card.get_index())
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.running = true
	_rays.running = true


func play(seed_ids: Array, from: Vector2) -> void:
	_queue.assign(seed_ids)
	_start = from
	_next()


var _start := Vector2.ZERO


func _text(font_size: int, color: Color) -> Label:
	var label := UiPalette.hud_label(font_size, color)
	label.z_index = 1
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _next() -> void:
	if _queue.is_empty():
		finished.emit()
		queue_free()
		return
	_show_seed(_queue.pop_front())


func _show_seed(id: String) -> void:
	var unit := BalanceDB.get_unit(id)
	_name.text = tr(str(unit.get("name", id)))
	_subtitle.text = tr(str(unit.get("subtitle", "")))
	_shown_face = false
	_set_face(false)
	_icon.texture = null
	_continue.modulate.a = 0.0
	_continue.disabled = true
	_heading.modulate.a = 0.0
	_glow = 0.0
	var model := str(unit.get("model", ""))
	if not model.is_empty():
		var path := model if model.begins_with("res://") else "res://assets/models/" + model
		if ResourceLoader.exists(path):
			_bake(path)
	var centre := get_viewport_rect().size * 0.5 - CARD_SIZE * 0.5 - Vector2(0.0, 12.0)
	_card.position = _start - CARD_SIZE * 0.5
	_card.scale = Vector2.ONE * 0.2
	var tween := create_tween()
	tween.tween_property(_card, "position", centre, RISE_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_card, "scale", Vector2.ONE, RISE_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "_glow", 0.55, RISE_SEC)
	tween.tween_interval(0.25)
	tween.tween_property(_card, "scale:x", 0.0, FLIP_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_set_face.bind(true))
	tween.tween_callback(Audio.play.bind(Audio.RICE_GEM_COLLECT))
	tween.tween_property(_card, "scale:x", 1.12, FLIP_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_card, "scale:y", 1.12, FLIP_SEC)
	tween.parallel().tween_property(self, "_glow", 1.0, FLIP_SEC)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_heading, "modulate:a", 1.0, 0.25)
	tween.tween_property(_continue, "modulate:a", 1.0, 0.2)
	tween.tween_callback(func() -> void:
		_continue.disabled = false
		_continue.grab_focus())


func _bake(path: String) -> void:
	var baked: Dictionary = await IconBaker.bake(self, [{"rect": _icon, "model": path, "scale": 1.0, "fit": true}], UiPalette.ICON_AMBIENT)
	if baked.has(path):
		_icon.texture = baked[path]


func _set_face(front: bool) -> void:
	_shown_face = front
	_icon.visible = front
	_name.visible = front
	_subtitle.visible = front


func _paint_rays(p: HudPainter) -> void:
	_spin = Time.get_ticks_msec() / 1000.0 * RAY_SPIN
	var c := _card.get_global_rect().get_center() if false else _card.global_position + CARD_SIZE * 0.5
	p.rays(c, 900.0, 14, _spin, 0.11, Color(UiPalette.HUD_DAWN, 0.5 * _glow))
	p.rays(c, 560.0, 9, -_spin * 1.6, 0.07, Color(UiPalette.HUD_FLASH, 0.35 * _glow))


func _paint_card(p: HudPainter) -> void:
	p.xf = _card.get_global_transform()
	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
	var shape := HudPainter.chamfered(rect, 14.0)
	p.glow(HudPainter.offset(shape, 3.0), Color(UiPalette.HUD_DAWN, 0.6 * _glow), 18.0)
	p.lacquer(shape, UiPalette.HUD_LACQUER_LIT, UiPalette.HUD_LACQUER_BOT, UiPalette.HUD_ACCENT, 5.0)
	p.stroke(HudPainter.chamfered(rect.grow(-6.0), 10.0), 1.2, UiPalette.HUD_GOLD)
	if _shown_face:
		p.fill(HudPainter.circle(Vector2(CARD_SIZE.x * 0.5, 106.0), 84.0), UiPalette.HUD_ICON_DISC)
		p.stroke(HudPainter.circle(Vector2(CARD_SIZE.x * 0.5, 106.0), 84.0), 2.0, UiPalette.HUD_GOLD)
		return
	# The sealed back: the logo's Pearl.
	var c := CARD_SIZE * 0.5
	p.stroke(HudPainter.circle(c, 54.0), 3.0, UiPalette.HUD_GOLD)
	p.rays(c, 96.0, 16, 0.0, 0.05, Color(UiPalette.HUD_GOLD, 0.8))
	p.fill(HudPainter.circle(c, 28.0), UiPalette.HUD_PEARL_TOP, UiPalette.HUD_PEARL_BOT)
	p.stroke(HudPainter.circle(c, 28.0), 1.6, UiPalette.HUD_EDGE)
