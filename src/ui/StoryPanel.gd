class_name StoryPanel
extends Control

# The Warden's Chronicle: the level intro, shown once per save before the loadout
# briefing. GameManager enters round_state "story" when the level's "story.intro"
# (LevelDB.story_lines) has not been read; this panel shows those lines one page
# at a time on a paper journal page over the live, dimmed island. Click / tap /
# Space / Enter finishes the line being written, then turns the page; Skip or Esc
# jumps to the end. The last page calls GameManager.finish_story(), which marks it
# seen and opens the briefing. The LAN guest reads along but its finish does
# nothing: the panel closes when the host's briefing opens.
# Built in code by HUD; the text reveal is one Tween per line (no _process).

const CHARS_PER_SEC := 55.0
const FADE_SEC := 0.25

var _lines: Array[String] = []
var _index := 0
var _title: Label
var _body: Label
var _next: Button
var _skip: Button
var _type_tween: Tween = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	EventBus.round_state_changed.connect(_on_round_state_changed)
	if GameManager.round_state == "story":
		_on_round_state_changed("story")


func _on_round_state_changed(state: String) -> void:
	if state == "story":
		_open()
	elif visible:
		visible = false


func _open() -> void:
	_lines = LevelDB.story_lines(GameManager.current_level_id, "intro")
	if _lines.is_empty():
		GameManager.finish_story()
		return
	_index = 0
	_title.text = tr(str(LevelDB.get_level(GameManager.current_level_id).get("name", "")))
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_SEC)
	_show_line()
	_next.grab_focus()


func _show_line() -> void:
	_body.text = tr(_lines[_index])
	_body.visible_ratio = 0.0
	_next.text = tr("Begin") if _index == _lines.size() - 1 else tr("Next")
	if _type_tween != null:
		_type_tween.kill()
	_type_tween = create_tween()
	_type_tween.tween_property(_body, "visible_ratio", 1.0, _body.text.length() / CHARS_PER_SEC)


## First press finishes the line being written; the next one turns the page.
func _advance() -> void:
	if _type_tween != null and _type_tween.is_running():
		_type_tween.kill()
		_body.visible_ratio = 1.0
		return
	if _index < _lines.size() - 1:
		_index += 1
		_show_line()
	else:
		_finish()


func _finish() -> void:
	if _type_tween != null:
		_type_tween.kill()
	if GameManager.is_client():
		visible = false
		return
	GameManager.finish_story()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		_finish()
	elif event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_advance()
	else:
		return
	get_viewport().set_input_as_handled()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var page := PanelContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	page.anchor_left = 0.5
	page.anchor_right = 0.5
	page.anchor_top = 1.0
	page.anchor_bottom = 1.0
	var width := minf(680.0, get_viewport_rect().size.x - 32.0)
	page.offset_left = -width * 0.5
	page.offset_right = width * 0.5
	page.offset_bottom = -36.0
	page.grow_vertical = Control.GROW_DIRECTION_BEGIN
	page.add_theme_stylebox_override("panel", UiPalette.box(UiPalette.PAPER_WARM, UiPalette.BAMBOO_EDGE, 12, 3, 22, Color(0, 0, 0, 0.35), 10))
	add_child(page)
	SafeArea.apply(page)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	page.add_child(box)

	var heading := Label.new()
	heading.text = tr("The Warden's Chronicle")
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", UiPalette.COST_INK)
	box.add_child(heading)

	_title = Label.new()
	_title.add_theme_font_override("font", UiPalette.bold_font())
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", UiPalette.INK)
	box.add_child(_title)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(0.0, 72.0)
	_body.add_theme_font_size_override("font_size", 19)
	_body.add_theme_color_override("font_color", UiPalette.INK)
	box.add_child(_body)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_skip = _button(tr("Skip"), false)
	_skip.pressed.connect(_finish)
	row.add_child(_skip)
	_next = _button(tr("Next"), true)
	_next.pressed.connect(_advance)
	row.add_child(_next)


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110.0, 44.0)
	var fill := UiPalette.AMBER if primary else UiPalette.PAPER
	b.add_theme_stylebox_override("normal", UiPalette.box(fill, UiPalette.BAMBOO_EDGE if primary else UiPalette.PAPER_EDGE, 8, 2, 10))
	b.add_theme_stylebox_override("hover", UiPalette.box(fill.lightened(0.15), UiPalette.AMBER, 8, 2, 10, Color(UiPalette.AMBER, 0.55), 6))
	b.add_theme_stylebox_override("pressed", UiPalette.box(fill.darkened(0.1), UiPalette.PAPER_EDGE, 8, 2, 10))
	b.add_theme_stylebox_override("focus", UiPalette.box(Color(0, 0, 0, 0), UiPalette.INK, 8, 3, 10))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, UiPalette.INK)
	return b
