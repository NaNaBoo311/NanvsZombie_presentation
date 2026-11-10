extends StaticBody3D

# Sacred Dragon Pearl on Lotus Dais — the defend target.
# Emits events when damaged and acts as an obstacle.
# Features 3D billboarded floating health bar above the pearl.
# Plays the model's own 'idle' clip (pearl bob + ribbon spin + petal breathe).
# A map may defend its own building instead (MapDefinition.defend_model, e.g. Turtle
# Tower on Hoan Kiem): DioramaWorld calls set_defend_model() on every map install,
# which swaps the model under Visuals and lifts the health bar above it. The
# footprint (PEARL_BOUNDS, the collision box) stays the same, so the building
# must fit inside it.

## Pearl dais footprint on local XZ plane (single box):
## octagonal plinth r~3.2m + steps/balustrades out to ~3.7m.
const PEARL_BOUNDS_MIN = Vector2(-3.5, -3.5)
const PEARL_BOUNDS_MAX = Vector2(3.5, 3.5)
const PEARL_MODEL := preload("res://assets/models/architecture/sacred_dragon_pearl.glb")
## Health bar height above the top of the defended model.
const HEALTH_BAR_CLEARANCE := 1.2

@export var max_health: int = 100
var current_health: int = 100

@onready var health_sprite: Sprite3D = $HealthBarSprite
@onready var health_viewport: SubViewport = $HealthBarViewport
@onready var health_bar: ProgressBar = $HealthBarViewport/PanelContainer/Margin/HBox/HealthBar
var fill_style: StyleBoxFlat = null
var _anim_player: AnimationPlayer = null
var _model_scene: PackedScene = PEARL_MODEL
var _health_bar_y: float = 7.0

func _ready() -> void:
	current_health = max_health
	add_to_group("CentralHouse")

	_setup_materials(self)
	_setup_dais_contact_shadow()
	_health_bar_y = health_sprite.position.y if health_sprite else _health_bar_y
	_play_idle()

	if health_bar:
		var orig = health_bar.get_theme_stylebox("fill")
		if orig is StyleBoxFlat:
			fill_style = orig.duplicate() as StyleBoxFlat
			health_bar.add_theme_stylebox_override("fill", fill_style)
		health_bar.max_value = max_health
		health_bar.value = current_health

	if health_viewport:
		health_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		
	if EventBus:
		EventBus.house_health_changed.connect(_on_health_changed)

## Swaps the defended model: `scene` (a map's own building) or, when null, the
## Sacred Dragon Pearl. No-op when that model is already shown.
func set_defend_model(scene: PackedScene) -> void:
	var wanted: PackedScene = scene if scene else PEARL_MODEL
	if wanted == _model_scene:
		return
	_model_scene = wanted
	var visuals := $Visuals as Node3D
	for child in visuals.get_children():
		visuals.remove_child(child)
		child.queue_free()
	var model := wanted.instantiate() as Node3D
	model.name = "DefendModel"
	visuals.add_child(model)
	_setup_materials(model)
	if health_sprite:
		var top := _model_top(model) if scene else _health_bar_y - HEALTH_BAR_CLEARANCE
		health_sprite.position.y = maxf(_health_bar_y, top + HEALTH_BAR_CLEARANCE)
	_play_idle()


func _play_idle() -> void:
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player and _anim_player.has_animation("idle"):
		# glTF imports default to LOOP_NONE while the model viewer loops every
		# clip: without this the whole idle (pearl bob, ribbon spin, orbiting
		# mini pearls, petal breathe) freezes after one 3s pass.
		var idle_anim: Animation = _anim_player.get_animation("idle")
		if idle_anim:
			idle_anim.loop_mode = Animation.LOOP_LINEAR
		_anim_player.play("idle")


## Highest point of every mesh under `node`, in this node's local space.
func _model_top(node: Node) -> float:
	var top := 0.0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		var box: AABB = mi.get_aabb()
		if mi.is_inside_tree():
			box = (global_transform.affine_inverse() * mi.global_transform) * box
		top = box.end.y
	for child in node.get_children():
		top = maxf(top, _model_top(child))
	return top


func take_damage(amount: int) -> void:
	current_health = max(0, current_health - amount)
	GameManager.damage_house(amount)
	
	# Shake pearl visuals on hit (safe: 'idle' animates PearlPivot, never root scale)
	var tween = create_tween()
	tween.tween_property($Visuals, "scale", Vector3(1.05, 0.95, 1.05), 0.08)
	tween.tween_property($Visuals, "scale", Vector3.ONE, 0.12)
	
	# Health bar punch bounce
	if health_sprite:
		var bar_tween = create_tween()
		bar_tween.tween_property(health_sprite, "scale", Vector3(1.22, 1.22, 1.22), 0.08)
		bar_tween.tween_property(health_sprite, "scale", Vector3.ONE, 0.14)

func _on_health_changed(current: int, max_hp: int) -> void:
	current_health = current
	max_health = max_hp

	if health_bar:
		var bar_tween = create_tween()
		bar_tween.tween_property(health_bar, "value", float(current), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if is_instance_valid(health_viewport):
			health_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			bar_tween.finished.connect(func():
				if is_instance_valid(health_viewport):
					health_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			)
	
	# Dynamic color transitions based on health ratio
	if fill_style:
		var ratio: float = float(current) / float(max(1, max_hp))
		var target_color: Color
		if ratio > 0.60:
			target_color = Color(0.35, 0.82, 0.40, 1.0) # Healthy emerald green
		elif ratio > 0.30:
			target_color = Color(0.95, 0.72, 0.20, 1.0) # Caution amber
		else:
			target_color = Color(0.92, 0.28, 0.24, 1.0) # Danger ruby red
		
		var color_tween = create_tween()
		color_tween.tween_property(fill_style, "bg_color", target_color, 0.25)

## Flat distance from world_pos to the nearest exterior wall of the pearl
## dais (0 = touching the plinth).
func get_distance_to_wall(world_pos: Vector3) -> float:
	var local_p: Vector3 = to_local(world_pos)
	var p2: Vector2 = Vector2(local_p.x, local_p.z)
	return _dist_to_box(p2, PEARL_BOUNDS_MIN, PEARL_BOUNDS_MAX)

## Returns the closest point on the exterior dais perimeter in world coordinates.
func get_closest_wall_point(world_pos: Vector3) -> Vector3:
	var local_p: Vector3 = to_local(world_pos)
	var p2: Vector2 = Vector2(local_p.x, local_p.z)
	var chosen: Vector2 = _closest_point_on_box(p2, PEARL_BOUNDS_MIN, PEARL_BOUNDS_MAX)
	return to_global(Vector3(chosen.x, 0.0, chosen.y))

func _dist_to_box(p: Vector2, b_min: Vector2, b_max: Vector2) -> float:
	var dx: float = maxf(0.0, maxf(b_min.x - p.x, p.x - b_max.x))
	var dz: float = maxf(0.0, maxf(b_min.y - p.y, p.y - b_max.y))
	return Vector2(dx, dz).length()

func _closest_point_on_box(p: Vector2, b_min: Vector2, b_max: Vector2) -> Vector2:
	return Vector2(clampf(p.x, b_min.x, b_max.x), clampf(p.y, b_min.y, b_max.y))

func _setup_materials(node: Node) -> void:
	# Godot glTF import leaves vertex_color_use_as_albedo=false: re-enable it,
	# BUT only on surfaces that actually carry a COLOR array. The pearl's colors
	# are material-based (no baked vertex colors), and forcing the flag on those
	# surfaces would tint them.
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(i)
			var has_vc := false
			if arrays.size() > Mesh.ARRAY_COLOR:
				var carr: Variant = arrays[Mesh.ARRAY_COLOR]
				if carr is PackedColorArray:
					has_vc = not (carr as PackedColorArray).is_empty()
			if has_vc:
				var mat = node.get_active_material(i)
				if not mat:
					mat = node.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					mat.vertex_color_use_as_albedo = true
	for child in node.get_children():
		_setup_materials(child)

func _setup_dais_contact_shadow() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c_core := Color(1, 1, 1, 0.78)
	var c_edge := Color(1, 1, 1, 0.0)
	var inner_r := 3.5
	var outer_r := 4.6
	var segs := 32
	for i in segs:
		var a0: float = TAU * float(i) / segs
		var a1: float = TAU * float(i + 1) / segs
		var i0 := Vector3(cos(a0) * inner_r, 0, sin(a0) * inner_r)
		var i1 := Vector3(cos(a1) * inner_r, 0, sin(a1) * inner_r)
		var o0 := Vector3(cos(a0) * outer_r, 0, sin(a0) * outer_r)
		var o1 := Vector3(cos(a1) * outer_r, 0, sin(a1) * outer_r)
		_tri(st, Vector3.ZERO, c_core, i0, c_core, i1, c_core)
		_tri(st, i0, c_core, o0, c_edge, o1, c_edge)
		_tri(st, i0, c_core, o1, c_edge, i1, c_core)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.04, 0.07, 0.03, 0.75)
	var mi := MeshInstance3D.new()
	mi.name = "DaisContactShadow"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.015
	add_child(mi)

static func _tri(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
