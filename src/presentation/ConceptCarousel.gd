class_name ConceptCarousel
extends Node3D

# The 3D half of "Vietnam in miniature": one title-screen shard per world on a
# display stage far from the talk's title diorama. Each shard carries its landmark
# and one posed unit, all folded into a single mesh by TitleBake, so a world costs
# one draw call. Only the chosen world is visible; switching is a one-shot tween,
# so the carousel has no idle script cost.

const TitleBake := preload("res://src/menus/title/TitleBake.gd")

const BASE_SCALE := 0.62
const ORIGIN := Vector3(300.0, 8.0, 0.0)
const WATER_OFF := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

var worlds: Array[Node3D] = []
var current := -1

var _tween: Tween


func _ready() -> void:
	position = ORIGIN
	build()


func build() -> void:
	for spec: Dictionary in PresentationDeck.WORLDS:
		var root := Node3D.new()
		root.name = "World_%s" % str(spec["id"])
		root.rotation.y = float(spec["yaw"])
		root.scale = Vector3.ONE * BASE_SCALE
		add_child(root)

		var shard := _instance(str(spec["model"]))
		shard.name = "Shard"
		root.add_child(shard)

		var landmarks := Node3D.new()
		landmarks.name = "Landmarks"
		var landmark := _instance(str(spec["landmark"]))
		landmark.position = spec["landmark_pos"]
		landmarks.add_child(landmark)
		root.add_child(landmarks)

		var units := Node3D.new()
		units.name = "Units"
		var unit := _instance(str(spec["unit"]))
		unit.position = spec["unit_pos"]
		unit.rotation.y = float(spec["unit_yaw"])
		unit.scale = Vector3.ONE * 3.4
		units.add_child(unit)
		_pose(unit, str(spec["unit_clip"]), 0.3)
		root.add_child(units)

		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			mi.cast_shadow = WATER_OFF
		TitleBake.enable_vertex_colors(root)
		TitleBake.bake(root, false, [shard, landmarks, units], "Baked")
		_add_base_ring(root)
		worlds.append(root)
	if not worlds.is_empty():
		set_world(0, false)


func set_world(index: int, animated: bool = true) -> void:
	if worlds.is_empty():
		return
	index = clampi(index, 0, worlds.size() - 1)
	for i in worlds.size():
		worlds[i].visible = i == index
	current = index
	var root := worlds[index]
	if _tween != null and _tween.is_running():
		_tween.kill()
	if not animated:
		root.position = Vector3.ZERO
		root.rotation.y = float(PresentationDeck.WORLDS[index]["yaw"])
		root.scale = Vector3.ONE * BASE_SCALE
		return
	var base_yaw := float(PresentationDeck.WORLDS[index]["yaw"])
	root.position = Vector3(16.0, -2.0, -4.0)
	root.rotation.y = base_yaw + 0.28
	root.scale = Vector3.ONE * BASE_SCALE * 0.78
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(root, "position", Vector3.ZERO, 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(root, "rotation:y", base_yaw, 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(root, "scale", Vector3.ONE * BASE_SCALE, 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _add_base_ring(root: Node3D) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 12.0
	torus.outer_radius = 12.25
	torus.rings = 48
	torus.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(UiPalette.HUD_GOLD, 0.34)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	var ring := MeshInstance3D.new()
	ring.name = "LeylineRing"
	ring.mesh = torus
	ring.material_override = mat
	ring.position = Vector3(0.0, -15.2, 0.0)
	ring.cast_shadow = WATER_OFF
	root.add_child(ring)


func _instance(path: String) -> Node3D:
	return (load(path) as PackedScene).instantiate() as Node3D


## Seek one clip to a held frame so the bake freezes a readable pose.
func _pose(root: Node, clip: String, at: float) -> void:
	for node in root.find_children("*", "AnimationPlayer", true, false):
		var ap := node as AnimationPlayer
		if not ap.has_animation(clip):
			continue
		ap.play(clip)
		ap.seek(at, true)
		ap.pause()
		return
