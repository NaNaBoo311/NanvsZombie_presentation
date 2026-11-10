class_name ArmoredCoconut
extends PlantBase

# Armored Coconut (Trái Dừa Chiến / Dừa Hộ Vệ) - Slot 4 defensive barrier (Wall-nut role).
# Heavy frontline blocker with high HP.
# Pure blocker: no attack, never acquires targets. Takes damage via PlantBase.
# Tile freed via PlantBase.die().

var _anim_player: AnimationPlayer = null

# Registry id (data/units/plants/armored_coconut.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "armored_coconut"

func _ready() -> void:
	super._ready()
	# Enable PlantBase procedural idle breathing bounce.
	idle_enabled = true
	_setup_materials(self)
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player and _anim_player.has_animation("idle"):
		idle_enabled = false
		_play_clip("idle")

func _play_clip(clip_name: String) -> void:
	if _anim_player and _anim_player.has_animation(clip_name):
		if _anim_player.current_animation != clip_name or not _anim_player.is_playing():
			_anim_player.play(clip_name)
	elif _anim_player:
		BalanceDB.report_missing_clip(unit_id, clip_name) # logs once (CONTRACT(clip-names))

func _setup_materials(node: Node) -> void:
	# Only enable vertex_color_use_as_albedo when vertex colors actually exist
	# so textured models without COLOR attributes are not darkened or corrupted.
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			var mat = node.get_active_material(i)
			if not mat:
				mat = node.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var arrays = node.mesh.surface_get_arrays(i)
				if arrays.size() > Mesh.ARRAY_COLOR and arrays[Mesh.ARRAY_COLOR] != null:
					mat.vertex_color_use_as_albedo = true
	for child in node.get_children():
		_setup_materials(child)
