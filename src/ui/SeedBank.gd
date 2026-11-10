class_name SeedBank
extends PanelContainer

# Seed bank for the battle HUD: lacquer cards with a gold inlay, hung under the rail.
# Number keys 1 to 9 (top row and numpad) or clicks select a seed; a selected card lifts,
# gets a double ring in the local player's accent, and bounces. Affordability shows on
# the cost seal: a seal that cannot be paid empties, and a gold gauge under the number
# fills as gems approach the cost. In co-op a pip marks the card the partner is holding.
# After planting, a seed recharges under a small eclipse: a dark moon covers its portrait
# and slides off with a gold corona as the time runs down, a seal counts the seconds, and
# the card bursts with light when it is ready. A recharging card wiggles "no" if pressed.
# In battle the bank shows only the packed seeds plus the shovel. Prepare mode (the
# pre-battle loadout briefing, GameManager.round_state == "prepare") shows every slot:
# packed ones carry a remove chip and unpack on click (never select_plant), forced ones
# show a lock and ignore clicks, open ones show "+" where the next plant lands, slots
# past the level's seed_slots render locked, and the shovel is hidden. The briefing
# flies packed icons into a slot via slot_icon_global_rect() / hide_slot_icon() /
# land_slot(). The bank rebuilds only when the loadout changes or prepare starts/ends,
# so a seed picked during the setup countdown stays selected when the wave starts.
# LAN co-op: each device has one local player. Selection is routed through
# GameManager.local_player_id(), which is what makes the guest's picks its own and lets
# the host validate them (CONTRACT(player-signals)).

# Seed cards (id, name, cost, icon, model, preview_scale) come from the unit
# registry: BalanceDB.seeds() (data/units/plants/<id>.json "seed" block).
#
# Draw-call budget: the bank adds no draw of its own. Cards are transparent Controls
# that carry the tweens; HudCanvas paints them in paint_hud(), icons share ONE atlas
# (_apply_icon_atlas) and text uses the HUD font, so each layer stays one batch however
# many seeds there are. Layer rules are in HudCanvas.gd. Do not give a card a panel,
# or raise a card's z_index to bring it forward: paint_hud() paints the selected card last.

const TOTAL_SLOTS: int = 9
const CARD_SIZE := Vector2(52.0, 72.0)
const CARD_CUT := 7.0
const ICON_RECT := Rect2(5.0, 13.0, 42.0, 42.0)
const SEAL_RECT := Rect2(9.0, 50.0, 34.0, 17.0)
const SELECTED_LIFT := -7.0
const HOVER_LIFT := -3.0
const DISC_CENTRE := Vector2(26.0, 34.0)
const DISC_RADIUS := 19.0
## The moon leaves toward the top right, where the seal is.
const MOON_DIR := Vector2(0.707, -0.707)
const SEAL_CENTRE := Vector2(41.0, 13.0)
const SEAL_RADIUS := 10.0
const BURST_RAYS := 12
const ECLIPSE_REDRAW_SEC := 0.05
## Icon atlas cell (px): the 256 px bakes are shown at 42 px, so 128 keeps them sharp
## on HiDPI; 2 px of clear padding stops filtering bleeding between neighbours.
const ATLAS_CELL: int = 128
const ATLAS_PAD: int = 2

@onready var slots_container: HBoxContainer = $Margin/HBox

var selected_index: int = -1 # the local player's highlighted slot
var slot_wrappers: Array[Control] = []
var slot_cards: Array[Control] = []
var _bounce_tweens: Dictionary = {}
var _lift_tweens: Dictionary = {}

## Active round loadout: ordered subset of BalanceDB.seeds() chosen in the SeedSelector.
## The bank renders these and nothing else (PvZ-style: only loaded seeds plantable).
var loadout: Array[Dictionary] = []

## Paint state per slot, parallel to slot_cards: kind, ratio (gems / cost), flash, hit.
var _slot_state: Array[Dictionary] = []

## PvZ shovel tool card (appended after the 9 seed slots, NOT part of slot_cards).
var shovel_wrapper: Control = null
var shovel_card: Control = null
var _shovel_state: Dictionary = {}
var _shovel_on: bool = false
var _redraw_wait := 0.0
var _built_prepare: bool = false # prepare-mode layout of the last _build_slots()
var _partner_seed: String = "" # co-op: the plant id the other device is holding

func _ready() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_resolve_loadout()
	_build_slots()
	HudCanvas.register(self, 20)
	set_process(false)
	# Cards are painted from their Control positions, so any re-layout needs a repaint.
	slots_container.sort_children.connect(HudCanvas.dirty)

	if EventBus:
		EventBus.sun_amount_changed.connect(_on_sun_changed)
		EventBus.plant_placed.connect(_on_plant_placed)
		EventBus.placement_cancelled.connect(_on_placement_cancelled)
		EventBus.seed_loadout_changed.connect(_on_loadout_changed)
		EventBus.shovel_mode_changed.connect(_on_shovel_mode_changed)
		EventBus.round_state_changed.connect(_on_round_state_changed)
		EventBus.placement_preview_changed.connect(_on_preview_changed)
		EventBus.seed_cooldown_started.connect(_on_cooldown_started)
		EventBus.seed_cooldown_finished.connect(_on_cooldown_finished)

	if GameManager:
		_on_sun_changed(GameManager.current_sun)

## Maps GameManager.seed_loadout ids onto BalanceDB.seeds() entries.
## Unknown ids are skipped; falls back to the full catalog when GameManager
## is unavailable (e.g. isolated scene preview).
func _resolve_loadout() -> void:
	loadout.clear()
	if GameManager and GameManager.get("seed_loadout") != null:
		for sid in GameManager.seed_loadout:
			var entry := BalanceDB.seed_entry(str(sid))
			if not entry.is_empty():
				entry = entry.duplicate()
				entry["cost"] = GameManager.plant_cost(str(sid))
				loadout.append(entry)
	else:
		loadout = BalanceDB.seeds()

func _on_loadout_changed(_selected_ids: Array) -> void:
	_resolve_loadout()
	_build_slots()
	selected_index = -1
	if GameManager:
		GameManager.p2_seed_index = -1
		_on_sun_changed(GameManager.current_sun)

func _build_slots() -> void:
	if not is_instance_valid(slots_container):
		return

	# remove_child first: a card still in the row for its last frame would push the new
	# cards to the right of it for one layout pass.
	for child in slots_container.get_children():
		slots_container.remove_child(child)
		child.queue_free()
	slot_wrappers.clear()
	slot_cards.clear()
	_slot_state.clear()
	# Drop tweens bound to freed cards (loadout rebuild) to avoid stale keys.
	for tween in _bounce_tweens.values():
		if is_instance_valid(tween):
			tween.kill()
	for tween in _lift_tweens.values():
		if is_instance_valid(tween):
			tween.kill()
	_bounce_tweens.clear()
	_lift_tweens.clear()

	_built_prepare = _is_prepare()
	var shown := TOTAL_SLOTS if _built_prepare else mini(loadout.size(), TOTAL_SLOTS)
	for i in range(shown):
		var wrapper: Control
		if i < loadout.size():
			wrapper = _create_slot(i, loadout[i])
		elif i < _slot_limit():
			wrapper = _create_empty_slot(i)
		else:
			wrapper = _create_locked_slot(i)
		slots_container.add_child(wrapper)
		slot_wrappers.append(wrapper)

	# PvZ shovel tool appended after the seed slots (own card, not a seed slot).
	# Hidden during the briefing: removal has no meaning while packing.
	shovel_wrapper = _create_shovel_tool()
	slots_container.add_child(shovel_wrapper)
	shovel_wrapper.visible = not _is_prepare()
	if GameManager and GameManager.is_shovel_mode:
		_set_shovel_visual(true)
	_bake_missing_icons()


func _is_prepare() -> bool:
	return GameManager and GameManager.round_state == "prepare"


func _slot_limit() -> int:
	return GameManager.seed_slot_count() if GameManager else TOTAL_SLOTS


## Rebuild only when prepare starts or ends (the layout differs); setup -> wave
## must keep the slot the player picked during the countdown.
func _on_round_state_changed(_state: String) -> void:
	if _is_prepare() == _built_prepare:
		return
	_resolve_loadout()
	_build_slots()
	selected_index = -1
	if GameManager:
		GameManager.p2_seed_index = -1
		_on_sun_changed(GameManager.current_sun)


## Deny flash for a full-bank pack attempt (called by the briefing via scene search).
func flash_bank_deny() -> void:
	for card in slot_cards:
		if is_instance_valid(card):
			_play_slot_flash(card)


## Global rect of slot `index`'s plant icon (the card when it has none); empty
## Rect2 when the slot is not built. The briefing flies a packed icon to it.
func slot_icon_global_rect(index: int) -> Rect2:
	if index < 0 or index >= slot_cards.size() or not is_instance_valid(slot_cards[index]):
		return Rect2()
	var card := slot_cards[index]
	var rect := card.find_child("IconTexture", true, false) as Control
	var target: Control = rect if rect != null else card
	return Rect2(target.global_position, target.size)


## Hide slot `index`'s icon while a packed icon flies toward it.
func hide_slot_icon(index: int) -> void:
	var rect := _slot_icon(index)
	if rect != null:
		rect.modulate.a = 0.0


## The flying icon arrived: show the slot's own icon again with a pop.
func land_slot(index: int) -> void:
	var rect := _slot_icon(index)
	if rect != null:
		rect.modulate.a = 1.0
	if index >= 0 and index < slot_cards.size() and is_instance_valid(slot_cards[index]):
		_play_slot_bounce(slot_cards[index], slot_wrappers[index], index)
		_play_slot_flash(slot_cards[index])


func _slot_icon(index: int) -> Control:
	if index < 0 or index >= slot_cards.size() or not is_instance_valid(slot_cards[index]):
		return null
	return slot_cards[index].find_child("IconTexture", true, false) as Control


## Hotkey number (top-left) or remove mark (top-right): plain text on the shared layer.
func _corner_chip(host: Control, text: String, right: bool, fg: Color) -> Label:
	var chip := UiPalette.hud_label(13, fg)
	chip.text = text
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.position = Vector2(CARD_SIZE.x - 18.0 if right else 3.0, 2.0)
	chip.size = Vector2(15.0, 16.0)
	host.add_child(chip)
	return chip


## A card: a transparent Control that carries the tweens; HudCanvas paints its shape.
func _new_card(index_name: String, kind: String) -> Dictionary:
	var wrapper := Control.new()
	wrapper.name = index_name
	wrapper.custom_minimum_size = CARD_SIZE
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	var card := Control.new()
	card.name = "Card"
	card.size = CARD_SIZE
	card.pivot_offset = CARD_SIZE * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(card)
	return {"wrapper": wrapper, "card": card, "kind": kind, "ratio": 1.0, "flash": 0.0, "hit": null}


func _new_hit(card: Control, hit_name: String) -> HudHit:
	var hit := HudHit.new()
	hit.name = hit_name
	card.add_child(hit)
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.mouse_entered.connect(_set_card_hover.bind(card, true))
	hit.mouse_exited.connect(_set_card_hover.bind(card, false))
	return hit


func _create_slot(index: int, data: Dictionary) -> Control:
	var state := _new_card("SlotWrapper_%d" % (index + 1), "seed")
	state["seed_id"] = str(data.id)
	var card: Control = state["card"]
	slot_cards.append(card)
	_slot_state.append(state)

	if data.has("model") and data.model:
		card.add_child(_create_model_icon(data.model))
	else:
		var initial := UiPalette.hud_label(26, UiPalette.HUD_SEAL_INK)
		initial.name = "IconLabel"
		initial.text = tr(str(data.get("name", data.id))).left(1)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.position = ICON_RECT.position
		initial.size = ICON_RECT.size
		card.add_child(initial)

	var cost_label := UiPalette.hud_label(14, UiPalette.HUD_SEAL_INK)
	cost_label.name = "CostLabel"
	cost_label.text = "%d" % data.cost
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.position = SEAL_RECT.position
	cost_label.size = SEAL_RECT.size
	card.add_child(cost_label)

	var count := UiPalette.hud_label(14, UiPalette.HUD_INK)
	count.name = "CooldownLabel"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.position = SEAL_CENTRE - Vector2.ONE * SEAL_RADIUS
	count.size = Vector2.ONE * SEAL_RADIUS * 2.0
	count.visible = false
	card.add_child(count)
	state["count"] = count
	state["burst"] = 0.0

	var hit := _new_hit(card, "SlotButton")
	hit.set_meta(Audio.CLICK_META, &"")
	hit.pressed.connect(trigger_slot.bind(index))
	state["hit"] = hit

	var forced: bool = GameManager != null and GameManager.is_seed_forced(str(data.id))
	state["forced"] = forced and _built_prepare
	_corner_chip(hit, str(index + 1), false, UiPalette.HUD_INK_SOFT)
	if _built_prepare and not forced:
		_corner_chip(hit, "×", true, UiPalette.HUD_INK)
	var plant_name := tr(str(data.get("name", data.id)))
	if _built_prepare:
		hit.set_tip(plant_name, tr("Locked by this level") if forced else tr("Click to unpack"))
	else:
		hit.set_tip(plant_name, tr("Key %d  ·  recharges in %ds") % [index + 1, ceili(float(data.get("cooldown", 0.0)))], int(data.cost))

	return state["wrapper"]

## Batching constraint (draw-call budget): slot icons are STATIC ImageTextures
## baked once via IconBaker, never live SubViewports. A SubViewportContainer
## forces its viewport to UPDATE_ALWAYS while visible (TRAPS.md#subviewport-container-flip;
## measured 13-53 draws per icon per frame). TextureRects batch like any 2D
## item. Keep it that way: do not reintroduce per-slot viewports.
var _icon_textures: Dictionary = {} # model_path -> ImageTexture (baked once)
var _bake_token: int = 0

func _create_model_icon(model_path: String) -> Control:
	# Static baked preview (see batching constraint above): a TextureRect filled
	# in by _bake_missing_icons().
	var rect := TextureRect.new()
	rect.name = "IconTexture"
	rect.position = ICON_RECT.position
	rect.size = ICON_RECT.size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = UiPalette.HUD_Z_ICON
	rect.set_meta("model_path", model_path)
	if _icon_textures.has(model_path):
		rect.texture = _icon_textures[model_path]
	return rect

# Assigns cached icon textures, then bakes the rest via IconBaker. Runs after
# every _build_slots; the token drops stale passes when a rebuild interrupts
# a bake.
func _bake_missing_icons() -> void:
	_bake_token += 1
	var token := _bake_token
	var missing: Array = []
	for card in slot_cards:
		var rect := card.find_child("IconTexture", true, false) as TextureRect
		if rect == null or not is_instance_valid(rect):
			continue
		var mp := str(rect.get_meta("model_path"))
		if _icon_textures.has(mp):
			rect.texture = _icon_textures[mp]
		else:
			missing.append({"rect": rect, "model": mp, "scale": _preview_scale_for(mp), "fit": true})
	if missing.is_empty():
		_apply_icon_atlas()
		return
	var fresh := await IconBaker.bake(self, missing, UiPalette.ICON_AMBIENT)
	if token != _bake_token:
		return
	for mp in fresh:
		_icon_textures[mp] = fresh[mp]
	_apply_icon_atlas()


# Packs every slot's baked icon into one texture and points each icon at its region
# (AtlasTexture), so the icon layer draws as one batch (see the budget note at the
# top). Runs once per bake or rebuild, never per frame.
func _apply_icon_atlas() -> void:
	var rects: Array[TextureRect] = []
	var order: Array[String] = []
	for card in slot_cards:
		if not is_instance_valid(card):
			continue
		var rect := card.find_child("IconTexture", true, false) as TextureRect
		if rect == null:
			continue
		var mp := str(rect.get_meta("model_path"))
		if not _icon_textures.has(mp):
			continue
		rects.append(rect)
		if not order.has(mp):
			order.append(mp)
	if order.is_empty():
		return
	var step := ATLAS_CELL + ATLAS_PAD
	var atlas := Image.create_empty(step * order.size(), ATLAS_CELL, false, Image.FORMAT_RGBA8)
	var regions: Dictionary = {}
	for i in order.size():
		var img: Image = (_icon_textures[order[i]] as Texture2D).get_image()
		if img == null:
			continue
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
		img.resize(ATLAS_CELL, ATLAS_CELL, Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(img, Rect2i(0, 0, ATLAS_CELL, ATLAS_CELL), Vector2i(i * step, 0))
		regions[order[i]] = Rect2(i * step, 0, ATLAS_CELL, ATLAS_CELL)
	var atlas_tex := ImageTexture.create_from_image(atlas)
	for rect in rects:
		var mp := str(rect.get_meta("model_path"))
		if not regions.has(mp):
			continue
		var region := AtlasTexture.new()
		region.atlas = atlas_tex
		region.region = regions[mp]
		rect.texture = region

func _preview_scale_for(model_path: String) -> float:
	for entry in BalanceDB.seeds():
		if entry["model"] == model_path:
			return float(entry["preview_scale"])
	return 1.0

func _create_empty_slot(index: int) -> Control:
	# Open slot (prepare only): a faint "+" says a packed plant lands here.
	var state := _new_card("SlotWrapper_%d" % (index + 1), "empty")
	var card: Control = state["card"]
	state["wrapper"].mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_cards.append(card)
	_slot_state.append(state)
	var plus := UiPalette.hud_label(26, UiPalette.HUD_INK_SOFT)
	plus.name = "OpenGlyph"
	plus.text = "+"
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.size = CARD_SIZE
	plus.modulate.a = 0.55 if index > loadout.size() else 1.0
	card.add_child(plus)
	return state["wrapper"]


func _create_locked_slot(index: int) -> Control:
	# Slot past the level's seed_slots: dimmer than empty, with a painted lock.
	var state := _new_card("SlotWrapper_%d" % (index + 1), "locked")
	state["wrapper"].mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_cards.append(state["card"])
	_slot_state.append(state)
	return state["wrapper"]


## PvZ shovel tool card: click (or X) toggles removal mode for plants+zombies.
func _create_shovel_tool() -> Control:
	var state := _new_card("ShovelWrapper", "shovel")
	var card: Control = state["card"]
	card.name = "ShovelCard"
	shovel_card = card
	_shovel_state = state
	var hit := _new_hit(card, "ShovelButton")
	hit.pressed.connect(trigger_shovel)
	hit.set_tip(tr("Shovel"), tr("Dig up a plant, no refund  ·  key X"))
	state["hit"] = hit
	_corner_chip(hit, "X", false, UiPalette.HUD_INK_SOFT)
	return state["wrapper"]

func trigger_shovel() -> void:
	if GameManager and GameManager.is_any_selector_open():
		return
	# Sentinel -99: never equals selected_index, so the bounce callback always
	# drops the wrapper back to z 0 and _set_shovel_visual owns the lift state.
	_play_slot_bounce(shovel_card, shovel_wrapper, -99)
	_play_slot_flash(shovel_card)
	if GameManager:
		GameManager.toggle_shovel()

func _set_shovel_visual(is_equipped: bool) -> void:
	if not is_instance_valid(shovel_card):
		return
	_shovel_on = is_equipped
	_tween_lift(shovel_card, is_equipped)

## Shovel equip clears the local player's seed highlight (GameManager already
## cancelled that player's placement before emitting).
func _on_shovel_mode_changed(is_equipped: bool, player_id: int) -> void:
	if GameManager and player_id != GameManager.local_player_id():
		return
	_set_shovel_visual(is_equipped)
	if not is_equipped:
		return
	if selected_index >= 0 and selected_index < slot_cards.size():
		_set_slot_selected_visual(slot_cards[selected_index], slot_wrappers[selected_index], false)
		selected_index = -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	# While either selector overlay is open, number keys belong to nothing here.
	if GameManager and GameManager.is_any_selector_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot_idx := -1
		# Match Keys 1 to 9 on top row or keypad
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			slot_idx = event.keycode - KEY_1
		elif event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
			slot_idx = event.keycode - KEY_KP_1

		if slot_idx >= 0 and slot_idx < slot_cards.size():
			trigger_slot(slot_idx)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if GameManager and GameManager.is_shovel_mode:
				GameManager.cancel_shovel()
				get_viewport().set_input_as_handled()
			elif selected_index >= 0:
				deselect_current()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if GameManager and GameManager.is_shovel_mode:
			GameManager.cancel_shovel()
		elif selected_index >= 0:
			deselect_current()

## `player_id` defaults to the local slot: every device has exactly one player,
## so a call without an id can only mean "me" (CONTRACT(player-signals)).
func trigger_slot(index: int, player_id: int = -1) -> void:
	if index < 0 or index >= slot_cards.size():
		return
	if index >= loadout.size():
		return # Empty/locked slot - no seed to select
	var local_id: int = GameManager.local_player_id() if GameManager else 0
	if player_id < 0:
		player_id = local_id
	if player_id != local_id:
		return # the partner's pick never drives this device's ghost

	var card = slot_cards[index]
	var wrapper = slot_wrappers[index]
	var data = loadout[index]

	# Prepare mode: the draft lives in GameManager.seed_loadout. A filled,
	# non-forced slot click unpacks it (never select_plant); forced ignores.
	if _is_prepare():
		if GameManager.is_seed_forced(str(data.id)):
			return
		_play_slot_flash(card)
		if GameManager.try_unpack_seed(str(data.id)):
			Audio.play(Audio.UI_CLICK)
		return

	if GameManager.is_seed_cooling(str(data.id)):
		_play_slot_deny(card)
		return

	# 1. Visual Indicator Effects (Punch Bounce & Luminous Flash)
	_play_slot_bounce(card, wrapper, index, player_id)
	_play_slot_flash(card)

	# 2. Toggle Selection State
	if selected_index == index:
		deselect_current()
	else:
		if selected_index >= 0 and selected_index < slot_cards.size():
			_set_slot_selected_visual(slot_cards[selected_index], slot_wrappers[selected_index], false)

		selected_index = index
		_set_slot_selected_visual(card, wrapper, true)
		Audio.play(Audio.SEEDBANK_PICK)
		GameManager.select_plant(data.id, player_id)

func deselect_current() -> void:
	if selected_index >= 0 and selected_index < slot_cards.size():
		_set_slot_selected_visual(slot_cards[selected_index], slot_wrappers[selected_index], false)
	selected_index = -1
	GameManager.clear_selection(GameManager.local_player_id())

func _set_slot_selected_visual(card: Control, _wrapper: Control, is_selected: bool) -> void:
	_tween_lift(card, is_selected)


## Hover rises a little; a selected card is already up and stays there.
func _set_card_hover(card: Control, on: bool) -> void:
	var held: bool = card == shovel_card and _shovel_on
	if selected_index >= 0 and selected_index < slot_cards.size():
		held = held or slot_cards[selected_index] == card
	if not held:
		_tween_lift(card, on, HOVER_LIFT)


func _tween_lift(card: Control, lifted: bool, height: float = SELECTED_LIFT) -> void:
	if _lift_tweens.has(card):
		var old_tween: Tween = _lift_tweens[card]
		if is_instance_valid(old_tween):
			old_tween.kill()
	var lift_tween := create_tween()
	_lift_tweens[card] = lift_tween
	if lifted:
		lift_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		lift_tween.tween_property(card, "position:y", height, 0.15)
	else:
		lift_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		lift_tween.tween_property(card, "position:y", 0.0, 0.15)
	HudCanvas.animate(0.2)


func _play_slot_bounce(card: Control, _wrapper: Control, _index: int, _player_id: int = 0) -> void:
	if _bounce_tweens.has(card):
		var old_tween: Tween = _bounce_tweens[card]
		if is_instance_valid(old_tween):
			old_tween.kill()
	var tween := create_tween()
	_bounce_tweens[card] = tween
	tween.tween_property(card, "scale", Vector2(1.08, 0.92), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	HudCanvas.animate(0.32)


func _play_slot_flash(card: Control) -> void:
	var state := _state_of(card)
	if state.is_empty():
		return
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: state["flash"] = v, 0.8, 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	HudCanvas.animate(0.3)


## "Not yet": a quick shake of the head.
func _play_slot_deny(card: Control) -> void:
	var tween := create_tween()
	for x in [-4.0, 4.0, -2.0, 0.0]:
		tween.tween_property(card, "position:x", x, 0.05)
	HudCanvas.animate(0.25)


func _state_of_seed(plant_id: String) -> Dictionary:
	for state in _slot_state:
		if state.get("seed_id", "") == plant_id:
			return state
	return {}


func _on_cooldown_started(plant_id: String) -> void:
	var state := _state_of_seed(plant_id)
	if state.is_empty():
		return
	# The partner planted the seed this player was holding.
	if selected_index >= 0 and selected_index < _slot_state.size() and _slot_state[selected_index] == state:
		deselect_current()
	state["count"].visible = true
	_redraw_wait = 0.0
	set_process(true)


func _on_cooldown_finished(plant_id: String) -> void:
	var state := _state_of_seed(plant_id)
	if state.is_empty():
		return
	state["count"].visible = false
	var card: Control = state["card"]
	_play_slot_bounce(card, state["wrapper"], -99)
	_play_slot_flash(card)
	Audio.play(Audio.SEEDBANK_PICK)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: state["burst"] = v, 0.01, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: state["burst"] = 0.0)
	HudCanvas.animate(0.55)


## Only while a seed recharges, and only the overlay repaints.
func _process(delta: float) -> void:
	_redraw_wait -= delta
	if _redraw_wait > 0.0:
		return
	_redraw_wait = ECLIPSE_REDRAW_SEC
	var cooling := false
	for state in _slot_state:
		var id: String = state.get("seed_id", "")
		if not id.is_empty() and GameManager.is_seed_cooling(id):
			cooling = true
			var label: Label = state["count"]
			var seconds := "%d" % ceili(GameManager.seed_cooldowns.left(id))
			if label.text != seconds:
				label.text = seconds
	HudCanvas.dirty_overlay()
	if not cooling:
		set_process(false)


func paint_hud_overlay(p: HudPainter) -> void:
	for state in _slot_state:
		var id: String = state.get("seed_id", "")
		var card: Control = state["card"]
		if id.is_empty() or not is_instance_valid(card):
			continue
		var burst: float = state.get("burst", 0.0)
		if GameManager.is_seed_cooling(id):
			p.xf = card.get_global_transform()
			paint_eclipse(p, GameManager.seed_cooldowns.left(id) / GameManager.seed_cooldowns.total(id))
		elif burst > 0.0:
			p.xf = card.get_global_transform()
			_paint_ready_burst(p, burst)


## The eclipse over a seed's portrait: `covered` 1 is total, 0 has passed.
func paint_eclipse(p: HudPainter, covered: float) -> void:
	var d := DISC_RADIUS * 2.0 * (1.0 - covered)
	var moon := HudPainter.eclipse(DISC_CENTRE, DISC_RADIUS, MOON_DIR, d)
	if not moon.is_empty():
		p.fill(moon, Color(UiPalette.HUD_EDGE, 0.9))
		var edge := HudPainter.eclipse_edge(DISC_CENTRE, DISC_RADIUS, MOON_DIR, d)
		p.line(edge, 4.0, Color(UiPalette.HUD_DAWN, 0.3))
		p.line(edge, 1.6, UiPalette.HUD_DAWN)
	var seal := HudPainter.circle(SEAL_CENTRE, SEAL_RADIUS)
	p.fill(seal, UiPalette.HUD_LACQUER_BOT)
	p.stroke(seal, 1.4, UiPalette.HUD_GOLD)


## Ready: the sun comes back, in a ring of rays from the portrait.
func _paint_ready_burst(p: HudPainter, t: float) -> void:
	var fade := Color(UiPalette.HUD_DAWN, 1.0 - t)
	p.fill(HudPainter.circle(DISC_CENTRE, DISC_RADIUS), Color(UiPalette.HUD_FLASH, (1.0 - t) * 0.7))
	for i in BURST_RAYS:
		var a := TAU * i / BURST_RAYS
		var dir := Vector2(cos(a), sin(a))
		var from := DISC_RADIUS + 2.0 + 16.0 * t
		p.line(PackedVector2Array([DISC_CENTRE + dir * from, DISC_CENTRE + dir * (from + 9.0)]), 2.4, fade)


func _state_of(card: Control) -> Dictionary:
	if card == shovel_card:
		return _shovel_state
	for state in _slot_state:
		if state["card"] == card:
			return state
	return {}


func _on_sun_changed(current_sun: int) -> void:
	for i in range(mini(loadout.size(), slot_cards.size())):
		var state := _slot_state[i]
		var cost := int(loadout[i].cost)
		var ratio := 1.0 if cost <= 0 else clampf(float(current_sun) / float(cost), 0.0, 1.0)
		state["ratio"] = ratio
		var card := slot_cards[i]
		var icon := card.find_child("IconTexture", true, false) as Control
		if icon != null:
			icon.self_modulate.a = 1.0 if ratio >= 1.0 else 0.62
		var cost_label := card.find_child("CostLabel", true, false) as Label
		if cost_label != null:
			cost_label.add_theme_color_override("font_color", UiPalette.HUD_SEAL_INK if ratio >= 1.0 else UiPalette.HUD_INK)
			cost_label.position.y = SEAL_RECT.position.y - (0.0 if ratio >= 1.0 else 2.0) # clears the gauge
	HudCanvas.dirty()


## Co-op: the partner's seed, for the pip on its card. Only the other device's events.
func _on_preview_changed(plant_type: String, _coord: Vector2i, _rot: int, _plantable: bool, player_id: int) -> void:
	if GameManager and player_id != GameManager.local_player_id() and plant_type != _partner_seed:
		_partner_seed = plant_type
		HudCanvas.dirty()


func paint_hud(p: HudPainter) -> void:
	var selected: Dictionary = {}
	for i in _slot_state.size():
		if i == selected_index:
			selected = _slot_state[i]
		else:
			_paint_card(p, _slot_state[i], false)
	if not _shovel_state.is_empty() and is_instance_valid(shovel_wrapper) and shovel_wrapper.visible:
		_paint_card(p, _shovel_state, _shovel_on)
	if not selected.is_empty():
		_paint_card(p, selected, true) # last: a lifted card sits over its neighbours


func _paint_card(p: HudPainter, state: Dictionary, selected: bool) -> void:
	var card: Control = state["card"]
	if not is_instance_valid(card):
		return
	p.xf = card.get_global_transform()
	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
	var shape := HudPainter.chamfered(rect, CARD_CUT)
	var kind: String = state["kind"]
	var open: bool = kind == "empty" or kind == "locked"
	var hit: HudHit = state["hit"]
	var hovered: bool = hit != null and hit.hovered
	var accent := _accent()
	var top := UiPalette.HUD_LOCKED_TOP if open else (UiPalette.HUD_LACQUER_LIT if selected or hovered else UiPalette.HUD_LACQUER_TOP)
	var bottom := UiPalette.HUD_LOCKED_BOT if open else UiPalette.HUD_LACQUER_BOT
	var flash: float = state["flash"]
	if flash > 0.0:
		top = top.lerp(UiPalette.HUD_FLASH, flash * 0.5)
		bottom = bottom.lerp(UiPalette.HUD_FLASH, flash * 0.3)
	if selected:
		p.glow(HudPainter.offset(shape, 3.0), Color(accent, 0.55), 9.0)
	elif hovered:
		p.glow(HudPainter.offset(shape, 3.0), Color(UiPalette.HUD_ACCENT, 0.6), 8.0)
	p.lacquer(shape, top, bottom, accent if selected or hovered else UiPalette.HUD_GOLD)
	if selected:
		p.stroke(HudPainter.offset(shape, 3.6), 2.0, accent)
	var inlay := UiPalette.HUD_GOLD
	inlay.a = 0.28 if open else (1.0 if hovered else 0.75)
	p.stroke(HudPainter.chamfered(rect.grow(-3.0), 4.5), 0.9, inlay)
	var centre := Vector2(CARD_SIZE.x * 0.5, 34.0)
	match kind:
		"seed":
			p.fill(HudPainter.circle(centre, 19.0), UiPalette.HUD_ICON_DISC)
			p.stroke(HudPainter.circle(centre, 19.0), 1.2, UiPalette.HUD_GOLD)
			_paint_seal(p, state["ratio"])
			if state.get("forced", false):
				_paint_lock(p, Vector2(CARD_SIZE.x - 11.0, 12.0), 0.6, UiPalette.HUD_GOLD)
			if not _partner_seed.is_empty() and state.get("seed_id", "") == _partner_seed:
				p.fill(HudPainter.circle(Vector2(CARD_SIZE.x - 9.0, 11.0), 4.5), _partner_accent())
				p.stroke(HudPainter.circle(Vector2(CARD_SIZE.x - 9.0, 11.0), 4.5), 1.2, UiPalette.HUD_EDGE)
		"locked":
			_paint_lock(p, centre, 1.0, UiPalette.HUD_INK_SOFT)
		"shovel":
			_paint_shovel(p, centre + Vector2(0.0, 3.0), accent if selected else UiPalette.HUD_GOLD)


## The cost seal: gold when payable; otherwise empty, with a gauge rising toward the cost.
func _paint_seal(p: HudPainter, ratio: float) -> void:
	var seal := HudPainter.chamfered(SEAL_RECT, 2.5)
	if ratio >= 1.0:
		p.fill(seal, UiPalette.HUD_GOLD)
		p.stroke(seal, 1.0, UiPalette.HUD_EDGE)
		return
	p.fill(seal, UiPalette.HUD_SEAL_EMPTY)
	p.stroke(seal, 1.2, UiPalette.HUD_GOLD)
	var gauge := Rect2(SEAL_RECT.position + Vector2(2.0, SEAL_RECT.size.y - 3.4), Vector2((SEAL_RECT.size.x - 4.0) * ratio, 1.9))
	if gauge.size.x > 0.5:
		p.fill(HudPainter.chamfered(gauge, 0.4), UiPalette.HUD_GOLD)


func _paint_lock(p: HudPainter, c: Vector2, s: float, color: Color) -> void:
	p.line(HudPainter.arc(c + Vector2(0.0, -3.0) * s, 5.0 * s, PI, TAU, 10), 2.0 * s, color)
	p.fill(HudPainter.chamfered(Rect2(c + Vector2(-8.0, -2.0) * s, Vector2(16.0, 12.0) * s), 2.0 * s), color)


func _paint_shovel(p: HudPainter, c: Vector2, color: Color) -> void:
	p.line(PackedVector2Array([c + Vector2(9.0, -17.0), c + Vector2(-1.0, 1.0)]), 3.2, color)
	p.line(PackedVector2Array([c + Vector2(5.0, -19.0), c + Vector2(13.0, -15.0)]), 3.2, color)
	var dir := Vector2(-10.0, 18.0).normalized()
	var side := Vector2(-dir.y, dir.x)
	var base := c + dir * 1.0
	p.fill(PackedVector2Array([base + side * 7.0, base - side * 7.0, base - side * 6.0 + dir * 11.0, base + dir * 17.0, base + side * 6.0 + dir * 11.0]), color)


func _accent() -> Color:
	return UiPalette.HUD_GUEST if GameManager and GameManager.local_player_id() == 1 else UiPalette.HUD_ACCENT


func _partner_accent() -> Color:
	return UiPalette.HUD_ACCENT if GameManager and GameManager.local_player_id() == 1 else UiPalette.HUD_GUEST


func _on_plant_placed(_plant_type: String, _grid_coord: Vector2i, player_id: int) -> void:
	# Only the planting player's own bank re-picks; the partner keeps their seed.
	if GameManager and player_id != GameManager.local_player_id():
		return
	deselect_current()

func _on_placement_cancelled(player_id: int) -> void:
	if GameManager and player_id != GameManager.local_player_id():
		return
	if selected_index >= 0:
		_set_slot_selected_visual(slot_cards[selected_index], slot_wrappers[selected_index], false)
		selected_index = -1
