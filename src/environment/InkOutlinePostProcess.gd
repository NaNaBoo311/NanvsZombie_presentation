extends Node3D
class_name InkOutlinePostProcess

# Screen-space ink outline post-process manager for whimsical cel-shaded diorama look.
# Renders a full-screen unshaded quad reading depth and normal buffers.
# Cost: exactly 1 draw call, 0 raster textures.
# Key 'O' toggles the outline in-game for live comparison.
# Command line flag: '--ink-style' can force-enable or configure it.

@export var outline_enabled: bool = true:
	set(val):
		outline_enabled = val
		_update_material()

@export var line_thickness: float = 1.25:
	set(val):
		line_thickness = val
		_update_material()

@export var outline_opacity: float = 1.0:
	set(val):
		outline_opacity = val
		_update_material()

@onready var quad: MeshInstance3D = $QuadMeshInstance

var _material: ShaderMaterial = null

# Haze and line colours come from the current LightingPreset via DayNightCycle, which
# may call set_colors() before this node's _ready (it sits earlier in the scene).
var _haze_color := Color(0.62, 0.78, 0.90)
var _ink_color := Color(0.12, 0.09, 0.08, 0.92)
var _haze_range := Vector2.ZERO

func _ready() -> void:
	if quad and quad.material_override is ShaderMaterial:
		# Use local duplicate so adjustments don't taint the saved .tres resource
		_material = quad.material_override.duplicate() as ShaderMaterial
		# Crucial: render_priority = -10 renders the post-process quad before transparent
		# objects (Sprite3D health bars, plant placement preview ghost, arrow chevrons, grid)
		_material.render_priority = -10
		quad.material_override = _material
	
	# Check cmdline flags: allow testing with or without ink style
	var args := OS.get_cmdline_user_args()
	if "--no-ink" in args:
		outline_enabled = false
	elif "--ink-style" in args:
		outline_enabled = true
		
	set_colors(_haze_color, _ink_color)
	if _haze_range != Vector2.ZERO:
		set_haze_range(_haze_range.x, _haze_range.y)
	_update_material()

## Distance haze and ink line colour (driven by DayNightCycle from the LightingPreset).
func set_colors(haze: Color, ink: Color) -> void:
	_haze_color = haze
	_ink_color = ink
	if _material:
		_material.set_shader_parameter("haze_color", haze)
		_material.set_shader_parameter("ink_color", ink)

## Distance band (metres from the camera) over which haze rises and ink lines thin.
## The shader defaults suit the battle camera; far shots like the title widen it.
func set_haze_range(start: float, end: float) -> void:
	_haze_range = Vector2(start, end)
	if _material:
		_material.set_shader_parameter("haze_start", start)
		_material.set_shader_parameter("haze_end", end)

func _update_material() -> void:
	if not is_instance_valid(quad):
		return
	quad.visible = outline_enabled and outline_opacity > 0.001
	if _material:
		_material.set_shader_parameter("line_thickness", line_thickness)
		_material.set_shader_parameter("outline_opacity", outline_opacity if outline_enabled else 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_O:
		outline_enabled = not outline_enabled
		print("[InkOutline] Toggled ink outlines: %s" % ("ON" if outline_enabled else "OFF"))
		get_viewport().set_input_as_handled()
