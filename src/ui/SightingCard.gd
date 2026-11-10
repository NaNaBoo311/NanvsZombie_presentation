class_name SightingCard
extends Control

# "Spirit sighted" card: the first time a save meets an enemy kind in a level, a
# lacquer card with a cool spirit band slides in at the right edge with the enemy's
# portrait, name and the Warden's note on it (unit JSON "lore"), stays HOLD_SEC, and
# slides out. It never pauses or takes input, so it is safe in LAN co-op. Several first
# sightings queue. Seen kinds are Progress "enemy:<id>" keys. Built in code by HUD;
# painted by HudCanvas, which only redraws during the slides. The portrait is baked
# once (IconBaker), so it costs one icon draw only while the card is up.

const HOLD_SEC := 5.0
const SLIDE_SEC := 0.3
const WIDTH := 340.0
const EDGE_GAP := 16.0
const TOP := 112.0
const BAND_HEIGHT := 26.0
const PORTRAIT := Rect2(12.0, 36.0, 64.0, 64.0)
const TEXT_X := 86.0
## Tall enemies bake as a thin full-body figure: show the head and shoulders.
const PORTRAIT_CROP := Rect2(0.2, 0.0, 0.6, 0.6)

var _queue: Array[String] = []
var _showing := false
var _card: Control
var _heading: Label
var _name: Label
var _lore: Label
var _portrait: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SafeArea.apply(self)
	_build()
	HudCanvas.register(self, 70)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)


func _on_enemy_spawned(enemy: Node3D) -> void:
	if not GameManager.level_active or not is_instance_valid(enemy):
		return
	var id := str(enemy.get("unit_id"))
	if id.is_empty() or id == "<null>" or Progress.has_seen("enemy:" + id) or _queue.has(id):
		return
	Progress.mark_seen("enemy:" + id)
	_queue.append(id)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		_card.visible = false
		HudCanvas.dirty()
		return
	_showing = true
	var unit := BalanceDB.get_unit(_queue.pop_front())
	_fill(unit)
	_card.visible = true
	_card.offset_left = 0.0
	_card.offset_right = WIDTH
	var tween := create_tween()
	tween.tween_property(_card, "offset_left", -WIDTH - EDGE_GAP, SLIDE_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_card, "offset_right", -EDGE_GAP, SLIDE_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(HOLD_SEC)
	tween.tween_callback(HudCanvas.animate.bind(SLIDE_SEC + 0.05))
	tween.tween_property(_card, "offset_left", 0.0, SLIDE_SEC)
	tween.parallel().tween_property(_card, "offset_right", WIDTH, SLIDE_SEC)
	tween.tween_callback(_show_next)
	HudCanvas.animate(SLIDE_SEC + 0.05)


## Dev capture only (HudDemo): shows a card without touching the save's seen list.
func preview(unit_id: String) -> void:
	_queue.append(unit_id)
	if not _showing:
		_show_next()


func _fill(unit: Dictionary) -> void:
	_name.text = tr(str(unit.get("name", "")))
	var lore := str(unit.get("lore", ""))
	_lore.text = tr(lore) if not lore.is_empty() else tr("A new spirit walks the leyline. Watch how it moves.")
	_lore.reset_size()
	_lore.size.x = WIDTH - TEXT_X - 14.0
	_card.offset_top = TOP
	_card.offset_bottom = TOP + maxf(PORTRAIT.end.y + 12.0, _lore.position.y + _lore.get_minimum_size().y + 12.0)
	_portrait.texture = null
	var model := str(unit.get("model", ""))
	if not model.is_empty():
		var path := model if model.begins_with("res://") else "res://assets/models/" + model
		if ResourceLoader.exists(path):
			_bake_portrait(path)


func _bake_portrait(path: String) -> void:
	var baked: Dictionary = await IconBaker.bake(self, [{"rect": _portrait, "model": path, "scale": 1.0, "fit": true}], UiPalette.ICON_AMBIENT)
	if not baked.has(path):
		return
	var full: Texture2D = baked[path]
	var crop := AtlasTexture.new()
	crop.atlas = full
	crop.region = Rect2(PORTRAIT_CROP.position * full.get_size(), PORTRAIT_CROP.size * full.get_size())
	_portrait.texture = crop


func _build() -> void:
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.offset_top = TOP
	_card.visible = false
	add_child(_card)

	_heading = UiPalette.hud_label(14, UiPalette.HUD_SPIRIT_INK)
	_heading.text = tr("Spirit sighted")
	_heading.position = Vector2(14.0, 4.0)
	_card.add_child(_heading)

	_portrait = TextureRect.new()
	_portrait.position = PORTRAIT.position
	_portrait.size = PORTRAIT.size
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.z_index = UiPalette.HUD_Z_ICON
	_card.add_child(_portrait)

	_name = UiPalette.hud_label(20)
	_name.position = Vector2(TEXT_X, BAND_HEIGHT + 6.0)
	_card.add_child(_name)

	_lore = UiPalette.hud_label(15, UiPalette.HUD_INK_SOFT)
	_lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lore.position = Vector2(TEXT_X, BAND_HEIGHT + 32.0)
	_lore.custom_minimum_size = Vector2(WIDTH - TEXT_X - 14.0, 0.0)
	_card.add_child(_lore)


func paint_hud(p: HudPainter) -> void:
	if not _card.visible:
		return
	p.xf = _card.get_global_transform()
	var rect := Rect2(Vector2.ZERO, _card.size)
	p.lacquer(HudPainter.chamfered(rect, 7.0), UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT)
	var band := PackedVector2Array([Vector2(7.0, 0.0), Vector2(rect.size.x - 7.0, 0.0), Vector2(rect.size.x, 7.0), Vector2(rect.size.x, BAND_HEIGHT), Vector2(0.0, BAND_HEIGHT), Vector2(0.0, 7.0)])
	p.fill(band, UiPalette.HUD_SPIRIT)
	var disc := PORTRAIT.get_center()
	p.fill(HudPainter.circle(disc, 32.0), UiPalette.HUD_ICON_DISC)
	p.stroke(HudPainter.circle(disc, 32.0), 1.3, UiPalette.HUD_GOLD)
