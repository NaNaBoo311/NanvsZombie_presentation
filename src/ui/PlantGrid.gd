class_name PlantGrid
extends Control

# Dense plant picker grid for the pre-battle briefing's pool: square icon tiles,
# each with its cost (rice gem icon + price) and, once packed, its bank slot number. Built for big pools
# (100+ plants on screen at once), so it is ONE CanvasItem drawn in passes instead
# of a node per card: every tile background, then every icon (all from one atlas
# texture), then the overlays, then all text at one font size. Godot batches
# consecutive draws that share a texture, so the grid costs a handful of draw calls
# at any plant count, where node cards cost ~3 per tile (background / icon / text
# alternate and break the batch). Shapes are plain rects only: a rounded StyleBox or
# draw_circle is a polygon, and polygons never batch (one draw call per tile).
# Icons are baked by IconBaker in small chunks and copied into the atlas as they
# arrive (tiles show the plant's initial until then). Baked cells are kept in a
# static cache, so a retry reopens the briefing without re-rendering models.
# Input: hover and click are hit-tested here (tile_hovered / tile_pressed); the
# mouse wheel passes through to the parent ScrollContainer. Redraws only on
# hover, packing, icon arrival or a deny flash: zero idle cost.

signal tile_pressed(seed_id: String)
signal tile_hovered(seed_id: String) # "" when the pointer leaves every tile

const GAP: float = 4.0
const CELL: int = 96 # atlas cell size in pixels
const BAKE_CHUNK: int = 6 # models per IconBaker pass, so icons appear progressively
const FONT_SIZE: int = 12
const COST_BAND: float = 18.0
const AMBIENT := UiPalette.ICON_AMBIENT
const GEM_MODEL := "res://assets/models/projectiles/rice_gem.glb" # the currency icon
const GEM_SIZE: float = 16.0

static var _cell_cache: Dictionary = {} # model_path -> Image (CELL x CELL, RGBA8)

var tile: float = 96.0
var columns: int = 1

var _ids: PackedStringArray = PackedStringArray()
var _names: PackedStringArray = PackedStringArray()
var _costs: PackedInt32Array = PackedInt32Array()
var _models: PackedStringArray = PackedStringArray()
var _scales: PackedFloat32Array = PackedFloat32Array()
var _cost_widths: PackedFloat32Array = PackedFloat32Array() # price text widths, for centring gem + price
var _soon: Dictionary = {} # seed_id -> true while the plant is not playable yet (BalanceDB.is_playable)
var _slot_of: Dictionary = {} # seed_id -> 1-based bank slot while packed
var _hover: int = -1

var _cells: Dictionary = {} # model_path -> Vector2i atlas cell
var _ready_cells: Dictionary = {} # model_path -> true once its icon is in the atlas
var _atlas_img: Image = null
var _atlas_tex: ImageTexture = null

var _deny_index: int = -1
var deny_alpha: float = 0.0:
	set(value):
		deny_alpha = value
		queue_redraw()

# Lacquer (UiPalette): unpacked tiles sit back in the dark, packed ones are pale with a
# bright gold edge, so what is in the bank reads at a glance.
const BG := UiPalette.HUD_LACQUER_LIT
const BG_HOVER := UiPalette.HUD_TILE_HOVER
const BG_PACKED := UiPalette.HUD_ICON_DISC
const BG_SOON := UiPalette.HUD_LOCKED_TOP
const EDGE := Color(UiPalette.HUD_GOLD, 0.45)
const EDGE_HOVER := UiPalette.HUD_ACCENT
const EDGE_PACKED := UiPalette.HUD_ACCENT
const BADGE := 18.0 # slot-number square, top right


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Icons are drawn far below their 96 px cell size (down to ~14 px for the gem);
	# without mipmaps the minified icons alias into a few dark pixels.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## Fill the grid. `entries` are BalanceDB.seeds() rows in display order.
func setup(entries: Array, tile_size: float, cols: int) -> void:
	tile = tile_size
	columns = maxi(1, cols)
	_ids = PackedStringArray()
	_names = PackedStringArray()
	_costs = PackedInt32Array()
	_models = PackedStringArray()
	_scales = PackedFloat32Array()
	_cost_widths = PackedFloat32Array()
	_soon.clear()
	var font := UiPalette.hud_font()
	for entry: Dictionary in entries:
		_ids.append(str(entry["id"]))
		if not bool(entry.get("playable", true)):
			_soon[str(entry["id"])] = true
		_names.append(str(entry.get("name", entry["id"])))
		_costs.append(int(entry.get("cost", 0)))
		_models.append(str(entry.get("model", "")))
		_scales.append(float(entry.get("preview_scale", 1.0)))
		_cost_widths.append(font.get_string_size(str(_costs[_costs.size() - 1]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	_hover = -1
	var rows := ceili(float(_ids.size()) / float(columns))
	custom_minimum_size = Vector2(columns * (tile + GAP) - GAP, maxf(rows * (tile + GAP) - GAP, 0.0))
	_build_atlas()
	queue_redraw()


## Mark which plants are packed (bank order -> slot numbers).
func set_packed(ids: Array) -> void:
	_slot_of.clear()
	for i in ids.size():
		_slot_of[str(ids[i])] = i + 1
	queue_redraw()


## Red flash on a tile whose pack was refused (bank full, forced plant).
func flash_deny(seed_id: String) -> void:
	_deny_index = _ids.find(seed_id)
	deny_alpha = 1.0
	create_tween().tween_property(self, "deny_alpha", 0.0, 0.35)


## Global rect of a plant's icon area ({} size when unknown), for the fly-to-bank.
func tile_icon_global_rect(seed_id: String) -> Rect2:
	var i := _ids.find(seed_id)
	if i < 0:
		return Rect2()
	var r := _icon_rect(i)
	return Rect2(global_position + r.position, r.size)


## The plant's baked icon as an AtlasTexture, or null while it is still baking.
func icon_texture(seed_id: String) -> Texture2D:
	var i := _ids.find(seed_id)
	if i < 0 or not _ready_cells.has(_models[i]):
		return null
	var tex := AtlasTexture.new()
	tex.atlas = _atlas_tex
	tex.region = Rect2(Vector2(_cells[_models[i]]) * CELL, Vector2(CELL, CELL))
	return tex


func _tile_rect(i: int) -> Rect2:
	@warning_ignore("integer_division")
	var row := i / columns
	var col := i % columns
	return Rect2(col * (tile + GAP), row * (tile + GAP), tile, tile)


func _icon_rect(i: int) -> Rect2:
	var r := _tile_rect(i)
	var pad := 3.0
	return Rect2(r.position + Vector2(pad, pad), Vector2(tile - pad * 2.0, tile - COST_BAND - pad))


func _index_at(pos: Vector2) -> int:
	var step := tile + GAP
	var col := floori(pos.x / step)
	var row := floori(pos.y / step)
	if col < 0 or col >= columns or row < 0:
		return -1
	if pos.x - col * step > tile or pos.y - row * step > tile:
		return -1 # in the gap
	var i := row * columns + col
	return i if i < _ids.size() else -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hover(_index_at(event.position))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _index_at(event.position)
		if i >= 0:
			accept_event()
			if not _soon.has(_ids[i]): # "coming soon" tiles are inert
				tile_pressed.emit(_ids[i])


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hover(-1)


func _set_hover(i: int) -> void:
	if i == _hover:
		return
	_hover = i
	queue_redraw()
	tile_hovered.emit(_ids[i] if i >= 0 else "")


func _draw() -> void:
	var n := _ids.size()
	if n == 0:
		return
	# Pass 1: tile backgrounds and edges (untextured rects, one batch).
	for i in n:
		var r := _tile_rect(i)
		var packed := _slot_of.has(_ids[i])
		var soon := _soon.has(_ids[i])
		draw_rect(r, BG_SOON if soon else (BG_PACKED if packed else (BG_HOVER if i == _hover else BG)))
		_frame(r, EDGE if soon else (EDGE_PACKED if packed else (EDGE_HOVER if i == _hover else EDGE)), 2.0 if packed or i == _hover else 1.0)
		# The cost band belongs under the gem, or it hides it.
		draw_rect(Rect2(r.position.x + 1.0, r.end.y - COST_BAND, tile - 2.0, COST_BAND - 1.0), UiPalette.HUD_LACQUER_BOT)
	# Pass 2: plant icons and cost gems, all from the one atlas texture.
	if _atlas_tex != null:
		var gem_ready := _ready_cells.has(GEM_MODEL)
		var gem_src := Rect2(Vector2(_cells.get(GEM_MODEL, Vector2i.ZERO)) * CELL, Vector2(CELL, CELL))
		for i in n:
			if _ready_cells.has(_models[i]):
				var src := Rect2(Vector2(_cells[_models[i]]) * CELL, Vector2(CELL, CELL))
				draw_texture_rect_region(_atlas_tex, _fit_square(_icon_rect(i)), src)
			if gem_ready:
				draw_texture_rect_region(_atlas_tex, _gem_rect(i), gem_src)
	# Pass 3: untextured rect overlays: cost band, slot badges, hover ring, deny flash.
	for i in n:
		var r := _tile_rect(i)
		if _soon.has(_ids[i]): # dim the plant and lay a spirit-blue ribbon across it
			draw_rect(r, Color(UiPalette.HUD_LOCKED_BOT, 0.6))
			draw_rect(Rect2(r.position.x, r.position.y + (tile - COST_BAND) * 0.5 - 7.0, tile, 14.0), UiPalette.HUD_SPIRIT)
		if _slot_of.has(_ids[i]):
			draw_rect(_badge_rect(r), EDGE_PACKED)
	if _hover >= 0 and _slot_of.has(_ids[_hover]):
		_frame(_tile_rect(_hover).grow(1.0), UiPalette.HUD_INK, 2.0)
	if _deny_index >= 0 and _deny_index < n and deny_alpha > 0.0:
		draw_rect(_tile_rect(_deny_index), Color(UiPalette.HUD_DANGER, 0.55 * deny_alpha))
		_frame(_tile_rect(_deny_index), Color(UiPalette.HUD_DANGER_TEXT, deny_alpha), 2.0)
	# Pass 4: all text at one size (one font cache texture): costs, slot numbers,
	# and the initial on tiles whose icon has not baked yet.
	var font := UiPalette.hud_font()
	for i in n:
		var r := _tile_rect(i)
		var gem := _gem_rect(i)
		draw_string(font, Vector2(gem.end.x + 2.0, r.end.y - 3.0), str(_costs[i]), HORIZONTAL_ALIGNMENT_LEFT,
			-1, FONT_SIZE, UiPalette.HUD_INK)
		if _soon.has(_ids[i]):
			draw_string(font, Vector2(r.position.x, r.position.y + (tile - COST_BAND) * 0.5 + 4.0), "SOON",
				HORIZONTAL_ALIGNMENT_CENTER, tile, FONT_SIZE, UiPalette.HUD_SPIRIT_INK)
		if _slot_of.has(_ids[i]):
			var b := _badge_rect(r)
			draw_string(font, Vector2(b.position.x, b.end.y - 3.0), str(_slot_of[_ids[i]]),
				HORIZONTAL_ALIGNMENT_CENTER, b.size.x, FONT_SIZE, UiPalette.HUD_SEAL_INK)
		if not _ready_cells.has(_models[i]):
			var ir := _icon_rect(i)
			draw_string(font, Vector2(ir.position.x, ir.get_center().y + 4.0), _names[i].substr(0, 1),
				HORIZONTAL_ALIGNMENT_CENTER, ir.size.x, FONT_SIZE, UiPalette.HUD_INK_SOFT)


## The gem before tile `i`'s price; gem + gap + price are centred in the cost band.
func _gem_rect(i: int) -> Rect2:
	var r := _tile_rect(i)
	var total := GEM_SIZE + 2.0 + _cost_widths[i]
	var y := r.end.y - COST_BAND * 0.5 - GEM_SIZE * 0.5 - 0.5
	return Rect2(r.position.x + (tile - total) * 0.5, y, GEM_SIZE, GEM_SIZE)


func _badge_rect(r: Rect2) -> Rect2:
	return Rect2(r.end.x - BADGE - 2.0, r.position.y + 2.0, BADGE, BADGE)


## Border as four filled rects (draw_rect's outline mode is a polyline, which does
## not batch).
func _frame(r: Rect2, color: Color, width: float) -> void:
	draw_rect(Rect2(r.position, Vector2(r.size.x, width)), color)
	draw_rect(Rect2(r.position.x, r.end.y - width, r.size.x, width), color)
	draw_rect(Rect2(r.position.x, r.position.y + width, width, r.size.y - width * 2.0), color)
	draw_rect(Rect2(r.end.x - width, r.position.y + width, width, r.size.y - width * 2.0), color)


func _fit_square(r: Rect2) -> Rect2:
	var side := minf(r.size.x, r.size.y)
	return Rect2(r.position + (r.size - Vector2(side, side)) * 0.5, Vector2(side, side))


## One atlas cell per distinct model; cached cells are copied in at once, the rest
## are baked in chunks.
func _build_atlas() -> void:
	_cells.clear()
	_ready_cells.clear()
	var unique := PackedStringArray()
	for mp in _models:
		if not mp.is_empty() and not unique.has(mp):
			unique.append(mp)
	if not unique.is_empty() and ResourceLoader.exists(GEM_MODEL):
		unique.append(GEM_MODEL)
	if unique.is_empty():
		_atlas_img = null
		_atlas_tex = null
		return
	var side := ceili(sqrt(float(unique.size())))
	_atlas_img = Image.create_empty(side * CELL, side * CELL, false, Image.FORMAT_RGBA8)
	for k in unique.size():
		@warning_ignore("integer_division")
		_cells[unique[k]] = Vector2i(k % side, k / side)
		if _cell_cache.has(unique[k]):
			_blit(unique[k], _cell_cache[unique[k]])
	_atlas_tex = ImageTexture.create_from_image(_mipmapped(_atlas_img))
	_bake_missing(unique)


func _bake_missing(unique: PackedStringArray) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var chunk: Array = []
	for mp in unique:
		if _ready_cells.has(mp):
			continue
		if mp == GEM_MODEL: # a tiny prop: fit its bounds to the cell
			chunk.append({"rect": null, "model": mp, "scale": 1.0, "fit": true})
		else:
			chunk.append({"rect": null, "model": mp, "scale": _scales[_models.find(mp)], "fit": true})
		if chunk.size() >= BAKE_CHUNK:
			if not await _bake_chunk(chunk):
				return
			chunk = []
	if not chunk.is_empty():
		await _bake_chunk(chunk)


## Bake one chunk and copy it into the atlas; false when the grid left the tree or
## was rebuilt meanwhile (stop baking).
func _bake_chunk(items: Array) -> bool:
	var atlas := _atlas_img
	var done: Dictionary = await IconBaker.bake(self, items, AMBIENT)
	if not is_inside_tree() or atlas != _atlas_img:
		return false
	for mp in done:
		var img: Image = (done[mp] as Texture2D).get_image()
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		if mp == GEM_MODEL:
			img = _trim_square(img) # drawn at GEM_SIZE: no padding to spare
		img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		_cell_cache[mp] = img
		_blit(mp, img)
	_atlas_tex.update(_mipmapped(_atlas_img))
	queue_redraw()
	return true


## Upload copy with mipmaps (the working atlas stays mip-free so cells can be blitted).
## fix_alpha_edges first: transparent pixels are black, and averaging them into the
## smaller mips darkens every icon's edge (the gem turned olive).
func _mipmapped(img: Image) -> Image:
	var copy := img.duplicate() as Image
	copy.fix_alpha_edges()
	copy.generate_mipmaps()
	return copy


## Crop to the visible pixels, centred in the smallest square that holds them.
func _trim_square(img: Image) -> Image:
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return img
	var side := maxi(used.size.x, used.size.y)
	var out := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	@warning_ignore("integer_division")
	out.blit_rect(img, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
	return out


func _blit(model_path: String, img: Image) -> void:
	var cell: Vector2i = _cells[model_path]
	_atlas_img.blit_rect(img, Rect2i(0, 0, CELL, CELL), cell * CELL)
	_ready_cells[model_path] = true
