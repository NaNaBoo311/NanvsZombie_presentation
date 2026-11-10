class_name IconBaker
extends RefCounted

## Static 3D-model icon baking for UI cards (SeedBank, Seed/Enemy selectors).
##
## Never put icon previews in SubViewportContainers: a visible container leaves
## its viewport in UPDATE_ALWAYS despite UPDATE_ONCE (TRAPS.md#subviewport-container-flip),
## so each "render once" avatar re-renders every frame (measured 13-53 draws per
## icon). Bake once into an ImageTexture via a hidden staging viewport — hidden
## means no container can flip the mode — and display it in a TextureRect.
## Invariant 6 holds: no viewport sits in ALWAYS at idle.
##
## Staging framing (camera, light) matches the old live previews, so baked pixels
## are identical to what the containers showed. Only `ambient` varies per caller.
##
## Usage: build cards with TextureRect placeholders, then
##   IconBaker.bake(self, [{"rect": r, "model": path, "scale": s}], ambient)
## Optional "fit": true ignores the framing a scale was tuned for and fits the model's
## bounds into the frame (tall enemies, tiny props); "scale" then only seeds the pose.
## Each unique model renders once; every waiting rect gets the texture. No-op
## under the headless dummy renderer (nothing to capture; icons stay empty).

const STAGE_SIZE := Vector2i(256, 256)
const CAM_FOV := 30.0
const CAM_POS := Vector3(0, 0.85, 2.30)
const CAM_TARGET := Vector3(0, 0.52, 0)
const LIGHT_ROT := Vector3(-55, -35, 0)
const LIGHT_ENERGY := 1.3
const AMBIENT_ENERGY := 1.1
## "fit" items: model bounds scaled to this height / width (m) and stood at FIT_BOTTOM,
## which keeps them inside the CAM_* frame (about -0.1 .. 1.14 m tall at the target).
const FIT_HEIGHT := 0.95
const FIT_WIDTH := 1.0
const FIT_BOTTOM := 0.08

static func bake(host: Node, items: Array, ambient: Color) -> Dictionary:
	var done: Dictionary = {}
	if not is_instance_valid(host):
		return done
	if items.is_empty():
		return done
	if DisplayServer.get_name() == "headless":
		return done
	var tree := host.get_tree()
	if tree == null:
		return done
	var holder := Control.new()
	holder.name = "IconBakeStage"
	holder.visible = false
	host.add_child(holder)
	var vp := SubViewport.new()
	vp.size = STAGE_SIZE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.gui_disable_input = true
	holder.add_child(vp)
	var icon_env := Environment.new()
	icon_env.background_mode = Environment.BG_CLEAR_COLOR
	icon_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	icon_env.ambient_light_color = ambient
	icon_env.ambient_light_energy = AMBIENT_ENERGY
	var world_env := WorldEnvironment.new()
	world_env.environment = icon_env
	vp.add_child(world_env)
	var icon_light := DirectionalLight3D.new()
	icon_light.rotation_degrees = LIGHT_ROT
	icon_light.light_energy = LIGHT_ENERGY
	vp.add_child(icon_light)
	var icon_camera := Camera3D.new()
	icon_camera.fov = CAM_FOV
	icon_camera.look_at_from_position(CAM_POS, CAM_TARGET, Vector3.UP)
	vp.add_child(icon_camera)
	icon_camera.current = true
	for it in items:
		if not is_instance_valid(host):
			return done
		var mp := str(it.get("model", ""))
		if mp.is_empty() or done.has(mp):
			continue
		if not ResourceLoader.exists(mp):
			continue
		_clear_previews(vp)
		var model_scene: PackedScene = load(mp)
		if model_scene == null:
			continue
		var preview := model_scene.instantiate() as Node3D
		if preview == null:
			continue
		preview.set_meta("icon_bake_preview", true)
		var sc := float(it.get("scale", 1.0))
		preview.scale = Vector3(sc, sc, sc)
		vp.add_child(preview)
		_enable_vertex_colors(preview)
		if bool(it.get("fit", false)):
			_fit_to_frame(preview)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var img: Image = null
		for attempt in range(4):
			await tree.process_frame
			await tree.process_frame
			if not is_instance_valid(vp):
				return done
			img = vp.get_texture().get_image()
			if img != null and not img.is_invisible():
				break
		if img == null or img.is_invisible():
			push_warning("IconBaker: blank bake for " + mp)
			continue
		var tex := ImageTexture.create_from_image(img)
		done[mp] = tex
		for other in items:
			if str(other.get("model", "")) == mp:
				var ro: Variant = other.get("rect")
				if ro == null or not is_instance_valid(ro):
					continue
				var r := ro as TextureRect
				if r != null:
					r.texture = tex
	if is_instance_valid(holder):
		holder.queue_free()
	return done

## glTF import leaves vertex_color_use_as_albedo off, and some models (Bougainvillea
## Net bracts) bake all colour into vertex colours over a white base: without this
## their icon bakes white. Plant scripts do the same in `_setup_materials`.
static func _enable_vertex_colors(preview: Node) -> void:
	for node in preview.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat != null:
				mat.vertex_color_use_as_albedo = true


static func _clear_previews(vp: SubViewport) -> void:
	for child in vp.get_children():
		if child is Node3D and bool(child.get_meta("icon_bake_preview", false)):
			vp.remove_child(child)
			child.free()


## Scale and move `preview` (already in the staging viewport, at the origin) so its
## visual bounds fill the icon frame. Called once per baked model, never per frame.
static func _fit_to_frame(preview: Node3D) -> void:
	var bounds := AABB()
	var first := true
	for node in preview.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		var box := vi.global_transform * vi.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first or bounds.size.y <= 0.0001:
		return
	var wide := maxf(bounds.size.x, bounds.size.z)
	var factor := FIT_HEIGHT / bounds.size.y
	if wide > 0.0001:
		factor = minf(factor, FIT_WIDTH / wide)
	preview.scale *= factor
	var centre := bounds.get_center() * factor
	preview.position = Vector3(-centre.x, FIT_BOTTOM - bounds.position.y * factor, -centre.z)
