class_name ProvinceBoard
extends Node3D

# Province board — the 3D layer of the province screen, built on a province's
# piece by AtlasMenu: the level path as a dashed ribbon (AtlasPath.gdshader,
# one mesh), every level node as one MultiMesh (one draw call; colour = locked /
# open / completed), and a pulsing ring on the next level (AtlasPulse.gdshader,
# GPU-only). Levels sit at even arc-length steps along a Catmull-Rom curve through
# the world's "path" control points (data/worlds/<id>.json, world XZ); without a path,
# a line through the label along the province's long axis. reveal() draws the
# path and pops the nodes in order; pop() replays the pop for just-unlocked
# levels. Those tweens are the only time script runs here.

signal revealed

enum NodeState { LOCKED = 0, OPEN = 1, COMPLETED = 2 }
const STATE_COLORS := [Color(0.42, 0.44, 0.5), Color(1.0, 0.8, 0.28), Color(0.45, 0.85, 0.5)]
const RIBBON_WIDTH := 0.028
const RIBBON_STEP := 0.02
const NODE_HEIGHT := 0.035
const END_INSET := 0.04          # fraction of the path left free at each end
const REVEAL_TIME := 0.7
const HOVER_SCALE := 1.3

var level_ids: Array[String] = []
var node_positions := PackedVector3Array()
var node_states := PackedInt32Array()
var next_index: int = -1
var node_radius: float = 0.06
var path_length: float = 0.0

var _curve := Curve3D.new()
var _ribbon: MeshInstance3D
var _ribbon_mat: ShaderMaterial
var _nodes: MultiMeshInstance3D
var _pulse: MeshInstance3D
var _hovered: int = -1
var _node_scale := PackedFloat32Array()


## control_points: world XZ; top: plate top the board sits on.
func build(world_id: String, control_points: Array[Vector2], top: float) -> void:
	level_ids = LevelDB.get_level_ids(world_id)
	var y := top + 0.012
	_curve = _catmull_rom(control_points, y)
	path_length = _curve.get_baked_length()
	var n := level_ids.size()
	var spacing := path_length * (1.0 - 2.0 * END_INSET) / float(maxi(n - 1, 1))
	node_radius = clampf(spacing * 0.32, 0.035, 0.09)
	node_positions.resize(n)
	for i in n:
		var f := 0.5 if n == 1 else lerpf(END_INSET, 1.0 - END_INSET, float(i) / float(n - 1))
		node_positions[i] = _curve.sample_baked(f * path_length) + Vector3(0.0, NODE_HEIGHT * 0.5, 0.0)
	_build_ribbon()
	_build_nodes()
	refresh_states()


func refresh_states() -> void:
	node_states.resize(level_ids.size())
	next_index = -1
	for i in level_ids.size():
		var id := level_ids[i]
		if Progress.is_level_completed(id):
			node_states[i] = NodeState.COMPLETED
		elif Progress.is_level_unlocked(id):
			node_states[i] = NodeState.OPEN
			if next_index < 0:
				next_index = i
		else:
			node_states[i] = NodeState.LOCKED
		if _nodes:
			_nodes.multimesh.set_instance_color(i, STATE_COLORS[node_states[i]])
	if _pulse:
		_pulse.visible = next_index >= 0
		if next_index >= 0:
			_pulse.position = node_positions[next_index] - Vector3(0.0, NODE_HEIGHT * 0.45, 0.0)
			_pulse.scale = Vector3.ONE * node_radius / 0.06


## Draws the path and pops the nodes in order; emits `revealed` when done.
func reveal() -> void:
	var tween := create_tween()
	tween.tween_method(_set_reveal, 0.0, 1.0, REVEAL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void: revealed.emit())


## Fully drawn at once (returning from a battle straight onto this screen).
func reveal_now() -> void:
	_set_reveal(1.0)


## Pop the given levels' nodes (just unlocked): scale 0 -> overshoot -> 1.
func pop(ids: PackedStringArray) -> void:
	for id in ids:
		var i := level_ids.find(id)
		if i < 0:
			continue
		var tween := create_tween()
		tween.tween_method(func(v: float) -> void:
			_node_scale[i] = v
			_apply_node_transform(i), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.35)


func set_hovered(i: int) -> void:
	if i == _hovered:
		return
	var old := _hovered
	_hovered = i
	for j in [old, i]:
		if j >= 0 and j < level_ids.size():
			_apply_node_transform(j)


## Level node under a screen position (within its projected radius, min 14 px), or -1.
func node_at_screen(camera: Camera3D, screen: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in node_positions.size():
		var p := node_positions[i]
		if camera.is_position_behind(p):
			continue
		var c := camera.unproject_position(p)
		var edge := camera.unproject_position(p + camera.global_basis.x * node_radius)
		var reach := maxf(c.distance_to(edge) * 1.4, 14.0)
		var d := c.distance_to(screen)
		if d <= reach and d < best_d:
			best = i
			best_d = d
	return best


func _set_reveal(t: float) -> void:
	_ribbon_mat.set_shader_parameter("reveal", t)
	for i in level_ids.size():
		var f := 0.5 if level_ids.size() == 1 else lerpf(END_INSET, 1.0 - END_INSET, float(i) / float(level_ids.size() - 1))
		_node_scale[i] = clampf((t - f) * 10.0 + 1.0, 0.0, 1.0) if t < 1.0 else 1.0
		_apply_node_transform(i)
	if _pulse:
		_pulse.visible = t >= 1.0 and next_index >= 0


func _apply_node_transform(i: int) -> void:
	var s := _node_scale[i] * (HOVER_SCALE if i == _hovered else 1.0)
	var basis := Basis.from_scale(Vector3(s, 1.0, s) if s > 0.0 else Vector3(0.001, 0.001, 0.001))
	_nodes.multimesh.set_instance_transform(i, Transform3D(basis, node_positions[i]))


func _catmull_rom(points: Array[Vector2], y: float) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 0.01
	for k in points.size():
		var prev := points[maxi(k - 1, 0)]
		var next := points[mini(k + 1, points.size() - 1)]
		var tangent := Vector3(next.x - prev.x, 0.0, next.y - prev.y) / 6.0
		curve.add_point(Vector3(points[k].x, y, points[k].y), -tangent, tangent)
	return curve


func _build_ribbon() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := maxi(int(path_length / RIBBON_STEP), 2)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for s in steps + 1:
		var d := path_length * float(s) / float(steps)
		var p := _curve.sample_baked(d)
		var ahead := _curve.sample_baked(minf(d + 0.01, path_length))
		var behind := _curve.sample_baked(maxf(d - 0.01, 0.0))
		var side := (ahead - behind).cross(Vector3.UP).normalized() * RIBBON_WIDTH * 0.5
		var l := p - side
		var r := p + side
		if s > 0:
			var u0 := float(s - 1) / float(steps)
			var u1 := float(s) / float(steps)
			for v in [[prev_l, u0], [prev_r, u0], [r, u1], [prev_l, u0], [r, u1], [l, u1]]:
				st.set_uv(Vector2(v[1], 0.0))
				st.add_vertex(v[0])
		prev_l = l
		prev_r = r
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = st.commit()
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbon_mat = ShaderMaterial.new()
	_ribbon_mat.shader = load("res://assets/shaders/AtlasPath.gdshader")
	_ribbon_mat.set_shader_parameter("path_length", path_length)
	_ribbon_mat.set_shader_parameter("reveal", 0.0)
	_ribbon.material_override = _ribbon_mat
	add_child(_ribbon)


func _build_nodes() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = node_radius
	disc.bottom_radius = node_radius
	disc.height = NODE_HEIGHT
	disc.radial_segments = 20
	disc.rings = 1
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.45
	disc.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = disc
	mm.instance_count = level_ids.size()
	_node_scale.resize(level_ids.size())
	_node_scale.fill(0.0)
	_nodes = MultiMeshInstance3D.new()
	_nodes.multimesh = mm
	add_child(_nodes)
	for i in level_ids.size():
		_apply_node_transform(i)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.075
	ring.outer_radius = 0.095
	ring.rings = 24
	ring.ring_segments = 6
	var pulse_mat := ShaderMaterial.new()
	pulse_mat.shader = load("res://assets/shaders/AtlasPulse.gdshader")
	ring.material = pulse_mat
	_pulse = MeshInstance3D.new()
	_pulse.mesh = ring
	_pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pulse.visible = false
	add_child(_pulse)
