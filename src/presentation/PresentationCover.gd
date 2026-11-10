class_name PresentationCover
extends Control

# PresentationCover — the presentation build's cover, laid over the game's live 3D
# title stage. It replaces only the UI layer: the eclipse, leyline, island chain,
# Pearl, plants and spirits all come from the inherited TitleMenu scene.
#
# Composition follows the title slide: university lockup top left, the two-line
# wordmark, course line, subtitle, and the actions the presenter can take. The
# team stays behind the Account button, and the lecturer and date sit in a
# compact footer, so the cover holds one clear invitation: start the presentation.
# Shapes are plain StyleBoxFlat/CanvasItem draws and the only texture is the 54 px
# university mark, so the cover adds no per-frame script cost once its intro ends.

signal play_pressed
signal quit_pressed

const NOTO_REGULAR_PATH := "res://assets/fonts/NotoSans-Regular.ttf"
const NOTO_BOLD_PATH := "res://assets/fonts/NotoSans-Bold.ttf"
const GOLD_SHADER_PATH := "res://assets/shaders/TitleGold.gdshader"

const MARGIN := 72.0
const TOP_MARGIN := 44.0
const FRAME_INSET := 22.0

static var _noto_regular: Font = null
static var _noto_bold: Font = null

var title_block: Control
var _play: Button
var _canvas: HudCanvas
var _accounts: PresentationAccounts
var _fade_groups: Array[Control] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_wash()
	_build_frame()
	_build_canvas()
	_build_lockup()
	_build_title()
	_build_actions()
	_build_footer()


## Draws the 3D stage back, then the cover copy in: university, wordmark, actions,
## footer. Each band has its own delay, so the eye lands on the wordmark first.
func play_intro() -> void:
	for group in _fade_groups:
		group.modulate.a = 0.0
	_canvas.modulate.a = 0.0
	_fade(_fade_groups[0], 0.28)
	_fade(_fade_groups[1], 0.42)
	_fade(_fade_groups[2], 0.66)
	_fade(_canvas, 0.66)
	_fade(_fade_groups[3], 0.84)


func focus_play() -> void:
	if _play != null:
		_play.grab_focus.call_deferred()


func _fade(group: Control, delay: float) -> void:
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(group, "modulate:a", 1.0, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## A faint ink wash over the whole art, then a left gradient that clears by the
## island. Matches the deck's two fills: every scene gets a little shade, the copy
## side gets enough to hold cream and gold at 4.5:1.
func _build_wash() -> void:
	var wash := ColorRect.new()
	wash.name = "Wash"
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(UiPalette.HUD_EDGE, 0.12)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	var scrim := TextureRect.new()
	scrim.name = "Scrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.texture = _scrim_texture()
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)


func _scrim_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UiPalette.HUD_EDGE, 0.86))
	gradient.set_color(1, Color(UiPalette.HUD_EDGE, 0.0))
	gradient.add_point(0.30, Color(UiPalette.HUD_EDGE, 0.80))
	gradient.add_point(0.46, Color(UiPalette.HUD_EDGE, 0.38))
	gradient.add_point(0.66, Color(UiPalette.HUD_EDGE, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 4
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 0.0)
	return texture


## The thin gold inlay the deck draws just inside the slide edge.
func _build_frame() -> void:
	var frame := Panel.new()
	frame.name = "InlayFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = FRAME_INSET
	frame.offset_top = FRAME_INSET
	frame.offset_right = -FRAME_INSET
	frame.offset_bottom = -FRAME_INSET
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel",
		UiPalette.box(Color(UiPalette.HUD_GOLD, 0.0), Color(UiPalette.HUD_GOLD, 0.20), 0, 1, 0))
	add_child(frame)
	SafeArea.apply(frame)


## HudMenuButton paints its lacquer shapes through the shared canvas.
func _build_canvas() -> void:
	_canvas = HudCanvas.new()
	_canvas.name = "HudCanvas"
	add_child(_canvas)


func _build_lockup() -> void:
	var lockup := Control.new()
	lockup.name = "Lockup"
	lockup.position = Vector2(MARGIN, TOP_MARGIN)
	lockup.size = Vector2(500.0, 68.0)
	lockup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lockup)
	_fade_groups.append(lockup)

	var logo := Panel.new()
	logo.name = "Logo"
	logo.position = Vector2.ZERO
	logo.size = Vector2(60.0, 60.0)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.add_theme_stylebox_override("panel",
		UiPalette.box(UiPalette.PAPER_WARM, UiPalette.PAPER_EDGE, 3, 1, 4))
	lockup.add_child(logo)

	var mark := TextureRect.new()
	mark.name = "Mark"
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.offset_left = 5.0
	mark.offset_top = 5.0
	mark.offset_right = -5.0
	mark.offset_bottom = -5.0
	mark.texture = load("res://assets/presentation/bk_logo.png")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.add_child(mark)

	var eyebrow := _label(PresentationDeck.UNIVERSITY_EYEBROW, UiPalette.hud_font(), 12,
		UiPalette.HUD_GOLD, Vector2(74.0, -1.0), 2.4)
	eyebrow.name = "Eyebrow"
	lockup.add_child(eyebrow)

	var name_label := _label(PresentationDeck.UNIVERSITY, UiPalette.hud_font(), 22,
		UiPalette.HUD_INK, Vector2(74.0, 15.0))
	name_label.name = "University"
	lockup.add_child(name_label)

	var faculty := _label(PresentationDeck.FACULTY, UiPalette.hud_font(), 13,
		UiPalette.HUD_INK_SOFT, Vector2(74.0, 46.0))
	faculty.name = "Faculty"
	lockup.add_child(faculty)

	SafeArea.apply(lockup)


func _build_title() -> void:
	title_block = Control.new()
	title_block.name = "TitleBlock"
	title_block.anchor_top = 0.165
	title_block.anchor_bottom = 0.165
	title_block.offset_left = MARGIN
	title_block.offset_right = MARGIN + 650.0
	title_block.offset_top = 0.0
	title_block.offset_bottom = 300.0
	title_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_block)
	_fade_groups.append(title_block)

	var course := _label(PresentationDeck.COURSE, UiPalette.hud_font(), 15,
		UiPalette.HUD_GOLD, Vector2.ZERO, 1.6)
	course.name = "Course"
	title_block.add_child(course)

	var first := _label(PresentationDeck.TITLE_FIRST, UiPalette.hud_font(), 92,
		UiPalette.HUD_INK, Vector2(-4.0, 18.0))
	first.name = "TitleFirst"
	title_block.add_child(first)

	var second := _label(PresentationDeck.TITLE_SECOND, UiPalette.hud_font(), 92,
		UiPalette.HUD_ACCENT, Vector2(-4.0, 112.0))
	second.name = "TitleSecond"
	var gold := ShaderMaterial.new()
	gold.shader = load(GOLD_SHADER_PATH)
	gold.set_shader_parameter("light", UiPalette.HUD_FLASH)
	gold.set_shader_parameter("deep", UiPalette.HUD_GOLD)
	gold.set_shader_parameter("top_y", 10.0)
	gold.set_shader_parameter("foot_y", 78.0)
	second.material = gold
	title_block.add_child(second)

	var rule := Panel.new()
	rule.name = "Rule"
	rule.position = Vector2(2.0, 236.0)
	rule.size = Vector2(320.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override("panel",
		UiPalette.box(Color(UiPalette.HUD_GOLD, 0.55), Color(UiPalette.HUD_GOLD, 0.55), 0, 0, 0))
	title_block.add_child(rule)

	var subtitle := _label(PresentationDeck.SUBTITLE, UiPalette.hud_font(), 30,
		UiPalette.HUD_INK, Vector2(0.0, 246.0))
	subtitle.name = "Subtitle"
	title_block.add_child(subtitle)


func _build_actions() -> void:
	var actions := Control.new()
	actions.name = "Actions"
	actions.anchor_top = 0.74
	actions.anchor_bottom = 0.74
	actions.offset_left = MARGIN
	actions.offset_right = MARGIN + 430.0
	actions.offset_top = 0.0
	actions.offset_bottom = 104.0
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(actions)
	_fade_groups.append(actions)

	_play = HudMenuButton.new()
	_play.name = "PlayButton"
	_play.text = tr("Start")
	_play.primary = true
	_play.position = Vector2.ZERO
	_play.size = Vector2(220.0, 56.0)
	_play.custom_minimum_size = Vector2(220.0, 56.0)
	_play.pressed.connect(func() -> void: play_pressed.emit())
	actions.add_child(_play)

	var links := HBoxContainer.new()
	links.name = "Links"
	links.position = Vector2(2.0, 70.0)
	links.size = Vector2(420.0, 38.0)
	links.add_theme_constant_override("separation", 24)
	actions.add_child(links)

	var account := _quiet_button("Account")
	account.name = "AccountButton"
	account.pressed.connect(_on_accounts)
	links.add_child(account)

	if not GameManager.is_touch_ui():
		var quit := _quiet_button("Quit")
		quit.name = "QuitButton"
		quit.pressed.connect(func() -> void: quit_pressed.emit())
		links.add_child(quit)

	SafeArea.apply(actions)


func _build_footer() -> void:
	var footer := Control.new()
	footer.name = "Footer"
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = MARGIN
	footer.offset_right = MARGIN + 760.0
	footer.offset_top = -86.0
	footer.offset_bottom = -38.0
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)
	_fade_groups.append(footer)

	var rule := Panel.new()
	rule.name = "Rule"
	rule.position = Vector2.ZERO
	rule.size = Vector2(190.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override("panel",
		UiPalette.box(Color(UiPalette.HUD_GOLD, 0.30), Color(UiPalette.HUD_GOLD, 0.30), 0, 0, 0))
	footer.add_child(rule)

	var label := _label("LECTURER", UiPalette.hud_font(), 11,
		UiPalette.HUD_GOLD, Vector2(0.0, 15.0), 2.2)
	label.name = "LecturerLabel"
	footer.add_child(label)

	var name_label := _label(PresentationDeck.LECTURER, _noto(false), 19,
		UiPalette.HUD_INK, Vector2(88.0, 8.0))
	name_label.name = "Lecturer"
	footer.add_child(name_label)

	var dot := _label("·", UiPalette.hud_font(), 18,
		UiPalette.HUD_GOLD, Vector2(318.0, 8.0))
	dot.name = "Dot"
	footer.add_child(dot)

	var date := _label(PresentationDeck.DATE, _noto(false), 17,
		UiPalette.HUD_INK_SOFT, Vector2(344.0, 11.0))
	date.name = "Date"
	footer.add_child(date)

	SafeArea.apply(footer)


func _on_accounts() -> void:
	if _accounts == null:
		_accounts = PresentationAccounts.new()
		_accounts.name = "AccountsPanel"
		add_child(_accounts)
	_accounts.open()


func _quiet_button(text: String) -> Button:
	var button := Button.new()
	button.text = tr(text)
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", UiPalette.hud_font())
	button.add_theme_font_size_override("font_size", 19)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, UiPalette.HUD_INK_SOFT)
	button.add_theme_color_override("font_pressed_color", UiPalette.HUD_ACCENT)
	button.add_theme_stylebox_override("hover",
		UiPalette.box(Color(UiPalette.HUD_ACCENT, 0.0), Color(UiPalette.HUD_ACCENT, 0.0), 0, 0, 6))
	button.add_theme_stylebox_override("pressed",
		UiPalette.box(Color(UiPalette.HUD_ACCENT, 0.0), Color(UiPalette.HUD_ACCENT, 0.0), 0, 0, 6))
	button.add_theme_stylebox_override("focus",
		UiPalette.box(Color(UiPalette.HUD_ACCENT, 0.0), Color(UiPalette.HUD_ACCENT, 0.60), 4, 1, 6))
	button.custom_minimum_size = Vector2(0.0, 36.0)
	return button


func _label(text: String, font: Font, font_size: int, color: Color, at: Vector2,
		tracking: int = 0) -> Label:
	var label := Label.new()
	label.text = tr(text)
	label.position = at
	label.add_theme_font_override("font", _tracked(font, tracking) if tracking != 0 else font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _tracked(font: Font, tracking: int) -> FontVariation:
	var varied := FontVariation.new()
	varied.base_font = font
	varied.spacing_glyph = tracking
	return varied


static func _noto(bold: bool) -> Font:
	if bold:
		if _noto_bold == null:
			_noto_bold = load(NOTO_BOLD_PATH)
		return _noto_bold
	if _noto_regular == null:
		_noto_regular = load(NOTO_REGULAR_PATH)
	return _noto_regular
