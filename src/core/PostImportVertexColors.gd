@tool
extends EditorScenePostImport

# Automatically enables vertex_color_use_as_albedo on StandardMaterial3D surfaces
# that actually carry baked vertex colors (such as the Lotus Shooter petals, the
# island's ParkDetailsColored bucket and the merged skyline towers), so
# procedural models render their full baked color gradients inside Godot.
# Surfaces without colors are left alone. Assign per model in its .glb.import:
# import_script/path="res://src/core/PostImportVertexColors.gd". Godot never
# enables the flag on its own, so a newly vertex-colored model renders white
# until its .import names this script (TRAPS.md#postimport-vertex-colors).

func _post_import(scene: Node) -> Object:
	_enable_vertex_colors(scene)
	return scene

func _enable_vertex_colors(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			var mat = node.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and (node.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0:
				mat.vertex_color_use_as_albedo = true
	for child in node.get_children():
		_enable_vertex_colors(child)
