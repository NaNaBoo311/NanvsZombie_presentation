extends RefCounted

# TitleBake — folds a posed, static subtree into one MeshInstance3D for the title.
#
# The title's landmarks and vignette units come from gameplay .glb files split
# into many meshes (a tower's glass, trim and podium; a zombie's limb pivots),
# one draw call each. The title never animates them, so after posing, bake()
# concatenates every surface under a group into one ArrayMesh with at most three
# shared surfaces, whatever the source materials were:
#   - opaque: lit, vertex colour x linear albedo, so the bake is also the title's
#     vertex-colour pass (glTF import leaves that flag off);
#   - glow: every emissive surface, unshaded, vertex colour = linear emission,
#     lifted over the glow threshold by the material;
#   - glass: every alpha-blended surface, alpha carried in the vertex colour.
# Textured or shader surfaces (none on the title today) keep their own material.
# Positions go into the group's space, normals through the inverse-transpose.
# The source meshes are freed, AnimationPlayers included, so nothing ticks per
# frame; with `parts`, the named nodes survive as empty markers (TitleTest finds
# landmarks and units by name).

enum Kind { OPAQUE, GLOW, GLASS, KEPT }

## Unshaded glow gain; sits above the environment's glow threshold.
const GLOW_GAIN := 1.35

static var _shared := {}


## Bakes meshes into one MeshInstance3D added to `group` as `mesh_name`. With no
## `parts`, every child of `group` is baked and freed. With `parts` (children of
## `group`), only those are baked, and each keeps its node tree as an empty marker:
## meshes and AnimationPlayers go, names stay. Returns the mesh, or null when a
## source holds a skinned mesh (then only vertex colours are set).
static func bake(group: Node3D, cast_shadow: bool, parts: Array = [],
		mesh_name: String = "Baked") -> MeshInstance3D:
	var sources: Array = parts if not parts.is_empty() else group.get_children()
	var meshes: Array[Node] = []
	for src: Node in sources:
		if not src.find_children("*", "Skeleton3D", true, false).is_empty():
			enable_vertex_colors(group)
			return null
		if src is MeshInstance3D:
			meshes.append(src)
		meshes.append_array(src.find_children("*", "MeshInstance3D", true, false))
	var to_group := group.global_transform.affine_inverse()
	var buckets := {}
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := to_group * mi.global_transform
		for s in range(mi.mesh.get_surface_count()):
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat := mi.get_active_material(s)
			var kind := _kind(mat)
			var key: Variant = mat if kind == Kind.KEPT else kind
			if not buckets.has(key):
				buckets[key] = _new_bucket(mat, kind)
			_append(buckets[key], mi.mesh.surface_get_arrays(s), xf, mat, kind)

	var mesh := ArrayMesh.new()
	for key in buckets:
		var b: Dictionary = buckets[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b["v"]
		arrays[Mesh.ARRAY_NORMAL] = b["n"]
		arrays[Mesh.ARRAY_COLOR] = b["c"]
		if b["kind"] == Kind.KEPT:
			arrays[Mesh.ARRAY_TEX_UV] = b["uv"]
			arrays[Mesh.ARRAY_TEX_UV2] = b["uv2"]
		arrays[Mesh.ARRAY_INDEX] = b["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, b["mat"])

	var doomed: Array[Node] = meshes.duplicate()
	if parts.is_empty():
		doomed = group.get_children()
	else:
		for src: Node in sources:
			doomed.append_array(src.find_children("*", "AnimationPlayer", true, false))
	for node in doomed:
		node.get_parent().remove_child(node)
		node.queue_free()
	var baked := MeshInstance3D.new()
	baked.name = mesh_name
	baked.mesh = mesh
	baked.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(baked)
	return baked


## Turns vertex_color_use_as_albedo on for every coloured StandardMaterial3D surface
## (what PostImportVertexColors.gd does at import).
static func enable_vertex_colors(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat != null and (mi.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0:
				mat.vertex_color_use_as_albedo = true


static func _kind(mat: Material) -> Kind:
	var sm := mat as StandardMaterial3D
	if sm == null:
		return Kind.OPAQUE if mat == null else Kind.KEPT
	if sm.albedo_texture != null or sm.emission_texture != null:
		return Kind.KEPT
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return Kind.GLASS
	if sm.emission_enabled or sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return Kind.GLOW
	return Kind.OPAQUE


static func _new_bucket(mat: Material, kind: Kind) -> Dictionary:
	# A kept material is copied: the imported one is shared with the battle maps.
	var out_mat: Material = mat.duplicate() if kind == Kind.KEPT else _material(kind)
	if out_mat is StandardMaterial3D:
		(out_mat as StandardMaterial3D).vertex_color_use_as_albedo = true
	return {
		"kind": kind, "mat": out_mat,
		"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
		"uv": PackedVector2Array(), "uv2": PackedVector2Array(), "i": PackedInt32Array(),
	}


static func _material(kind: Kind) -> StandardMaterial3D:
	if _shared.has(kind):
		return _shared[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	match kind:
		Kind.OPAQUE:
			m.roughness = 0.85
		Kind.GLOW:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(GLOW_GAIN, GLOW_GAIN, GLOW_GAIN)
		Kind.GLASS:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.12
			m.metallic_specular = 0.8
	_shared[kind] = m
	return m


## The colour a source surface contributes, per kind, as linear RGBA.
static func _tint(mat: Material, kind: Kind) -> Color:
	var sm := mat as StandardMaterial3D
	if sm == null or kind == Kind.KEPT:
		return Color.WHITE
	if kind == Kind.GLOW and sm.emission_enabled:
		var e := sm.emission.srgb_to_linear()
		return Color(e.r, e.g, e.b, 1.0)
	return sm.albedo_color.srgb_to_linear()


static func _append(b: Dictionary, src: Array, xf: Transform3D, mat: Material, kind: Kind) -> void:
	var verts := src[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if verts.is_empty():
		return
	var normals = src[Mesh.ARRAY_NORMAL]
	var colors = src[Mesh.ARRAY_COLOR]
	var indices = src[Mesh.ARRAY_INDEX]
	var tint := _tint(mat, kind)
	# Emission is a flat colour; the source's vertex colours tint albedo, not glow.
	var use_vc := colors != null and not (kind == Kind.GLOW and (mat as StandardMaterial3D) != null \
		and (mat as StandardMaterial3D).emission_enabled)
	var nb := xf.basis.inverse().transposed()
	var base := (b["v"] as PackedVector3Array).size()
	var v: PackedVector3Array = b["v"]
	var n: PackedVector3Array = b["n"]
	var c: PackedColorArray = b["c"]
	for k in range(verts.size()):
		v.append(xf * verts[k])
		n.append((nb * (normals[k] as Vector3)).normalized() if normals != null else Vector3.UP)
		var vc: Color = colors[k] if use_vc else Color.WHITE
		c.append(Color(vc.r * tint.r, vc.g * tint.g, vc.b * tint.b, vc.a * tint.a))
	b["v"] = v
	b["n"] = n
	b["c"] = c
	if kind == Kind.KEPT:
		b["uv"] = _append_uv(b["uv"], src[Mesh.ARRAY_TEX_UV], verts.size())
		b["uv2"] = _append_uv(b["uv2"], src[Mesh.ARRAY_TEX_UV2], verts.size())
	var idx: PackedInt32Array = b["i"]
	if indices != null:
		for k in (indices as PackedInt32Array):
			idx.append(base + k)
	else:
		for k in range(verts.size()):
			idx.append(base + k)
	b["i"] = idx


static func _append_uv(dst: PackedVector2Array, src, count: int) -> PackedVector2Array:
	if src != null:
		dst.append_array(src as PackedVector2Array)
	else:
		for _k in range(count):
			dst.append(Vector2.ZERO)
	return dst
