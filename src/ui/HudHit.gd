class_name HudHit
extends Button

# An invisible button over a painted HUD shape: it draws nothing itself (HudCanvas paints
# the shape) and reports hover and press so the painter can show them. Touch and mouse
# both arrive here as ordinary Control input. Setting tip_title gives it a Lacquer
# tooltip instead of the engine's default box.

var tip_title := ""
var tip_detail := ""
var tip_cost := -1
var hovered := false


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var nothing := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(state, nothing)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	button_down.connect(HudCanvas.dirty)
	button_up.connect(HudCanvas.dirty)


func _set_hover(on: bool) -> void:
	hovered = on
	HudCanvas.dirty()


## The engine only opens a tooltip for non-empty tooltip_text.
func set_tip(title: String, detail: String = "", cost: int = -1) -> void:
	tip_title = title
	tip_detail = detail
	tip_cost = cost
	tooltip_text = title


func _make_custom_tooltip(_for_text: String) -> Object:
	var tip := HudTooltip.new()
	tip.setup(tip_title, tip_detail, tip_cost)
	return tip
