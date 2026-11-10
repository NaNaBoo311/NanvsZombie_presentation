class_name TitleLogo
extends Control

# The game's logo lockup, drawn rather than imported, so it is sharp at any window size:
# an eclipse emblem with the Pearl rising from a lotus inside it, then the gold
# wordmark, a rule and the subtitle. Painted by HudCanvas; the wordmark's gold is
# TitleGold.gdshader. TitleMenu scales this node as a unit on wide windows.

const EMBLEM := Vector2(58.0, 62.0)
const EMBLEM_R := 40.0
const TEXT_X := 116.0
const RAYS := 16
const LOGO_SIZE := Vector2(760.0, 140.0)

var _rule_right := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = LOGO_SIZE
	var word := UiPalette.hud_label(66, UiPalette.HUD_ACCENT)
	word.name = "Wordmark"
	word.text = tr("Leyline Warden")
	word.position = Vector2(TEXT_X, 0.0)
	word.add_theme_color_override("font_outline_color", UiPalette.HUD_EDGE)
	word.add_theme_constant_override("outline_size", 12)
	var gold := ShaderMaterial.new()
	gold.shader = load("res://assets/shaders/TitleGold.gdshader")
	word.material = gold
	add_child(word)
	var sub := UiPalette.hud_label(26, UiPalette.HUD_INK)
	sub.name = "Subtitle"
	sub.text = tr("Spirits of the Soil")
	sub.position = Vector2(TEXT_X + 4.0, 92.0)
	sub.add_theme_color_override("font_outline_color", UiPalette.HUD_EDGE)
	sub.add_theme_constant_override("outline_size", 8)
	add_child(sub)
	_rule_right = TEXT_X + 4.0 + word.get_minimum_size().x - 12.0
	HudCanvas.register(self, 10)


func paint_hud(p: HudPainter) -> void:
	p.xf = get_global_transform()
	for i in RAYS:
		var a := TAU * i / RAYS
		var d := Vector2(cos(a), sin(a))
		var far := EMBLEM_R + (11.0 if i % 2 == 0 else 6.0)
		p.line(PackedVector2Array([EMBLEM + d * (EMBLEM_R + 3.0), EMBLEM + d * far]), 3.2, UiPalette.HUD_EDGE)
		p.line(PackedVector2Array([EMBLEM + d * (EMBLEM_R + 3.0), EMBLEM + d * (far - 0.6)]), 1.8, UiPalette.HUD_ACCENT)
	var disc := HudPainter.circle(EMBLEM, EMBLEM_R)
	p.fill(HudPainter.offset(disc, 3.2), UiPalette.HUD_EDGE)
	p.fill(HudPainter.offset(disc, 1.8), UiPalette.HUD_GOLD)
	p.fill(disc, UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_EDGE)
	# The Pearl rising from a lotus, inside the eclipse.
	for i in 5:
		var a := PI * 0.5 + (i - 2) * 0.62
		var d := Vector2(cos(a), sin(a))
		var base := EMBLEM + Vector2(0.0, 24.0)
		var side := Vector2(-d.y, d.x)
		var tip := base - d * 27.0 * (1.0 - absf(i - 2) * 0.12)
		var petal := PackedVector2Array([base - side * 3.0, tip - d * 0.0 - side * 7.0 + d * 12.0, tip, tip + side * 7.0 + d * 12.0, base + side * 3.0])
		p.fill(petal, UiPalette.HUD_ACCENT, UiPalette.HUD_DUSK)
		p.stroke(petal, 1.1, UiPalette.HUD_EDGE)
	var pearl := HudPainter.circle(EMBLEM + Vector2(0.0, -8.0), 13.0)
	p.fill(HudPainter.offset(pearl, 5.0), Color(UiPalette.HUD_DAWN, 0.3))
	p.fill(pearl, UiPalette.HUD_PEARL_TOP, UiPalette.HUD_PEARL_BOT)
	p.stroke(pearl, 1.4, UiPalette.HUD_EDGE)
	var y := 90.0
	p.line(PackedVector2Array([Vector2(TEXT_X + 4.0, y), Vector2(_rule_right, y)]), 3.2, UiPalette.HUD_EDGE)
	p.line(PackedVector2Array([Vector2(TEXT_X + 4.0, y), Vector2(_rule_right, y)]), 1.6, UiPalette.HUD_GOLD)
