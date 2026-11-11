class_name UiPalette
extends RefCounted

## "Bamboo & paper" look shared by the seed bank and the seed selector: ochre bamboo
## rails, cream paper cards, dark-brown ink, lantern-amber highlights. Colours come
## from docs/STYLE_GUIDE.md tokens (Timber Trunk Brown, Cottage Wall Cream, Amber
## Lantern Glow, Vermilion Bridge Red). Plain StyleBoxFlat only: no textures, and no
## per-frame work, so the bank's draw-call budget (SeedBank.gd header) is unaffected.

const BAMBOO := Color(0.72, 0.53, 0.26, 0.97)
const BAMBOO_EDGE := Color(0.35, 0.24, 0.15, 1.0) # Timber Trunk Brown #5A3D28, deepened
const PAPER := Color(0.91, 0.85, 0.72, 1.0) # Cottage Wall Cream #E8D8B8
const PAPER_WARM := Color(0.98, 0.91, 0.72, 1.0)
const PAPER_EDGE := Color(0.60, 0.45, 0.25, 1.0)
const INK := Color(0.29, 0.19, 0.11, 1.0)
const INK_SOFT := Color(0.45, 0.32, 0.20, 1.0)
const COST_INK := Color(0.62, 0.32, 0.04, 1.0)
const AMBER := Color(1.0, 0.69, 0.28, 1.0) # Amber Lantern Glow #FFB048
## Guest accent (LAN co-op; Sky Horizon Cyan #98D8EB): reads against both the
## host's amber highlight and the green lawn grid without touching the warm palette.
const P2_CYAN := Color(0.60, 0.85, 0.92, 1.0)
const VERMILION := Color(0.64, 0.15, 0.10, 1.0) # Vermilion Bridge Red #A4261A
const SOIL := Color(0.48, 0.29, 0.16, 1.0) # Soil Brown #7A4B29
## Warm ambient for baked plant icons (IconBaker): paper-friendly, not grey.
const ICON_AMBIENT := Color(0.66, 0.60, 0.50)

# Battle HUD "Lacquer Tray": dark lacquer, gold-leaf inlay, cream ink. Painted by
# HudCanvas. Every text pair here clears 4.5:1 on its own backing.
const HUD_LACQUER_TOP := Color("3A241A")
const HUD_LACQUER_BOT := Color("21130D")
const HUD_LACQUER_LIT := Color("4A2E20")
const HUD_TILE_HOVER := Color("5E3D2B")
const HUD_LOCKED_TOP := Color("2E2622")
const HUD_LOCKED_BOT := Color("211B18")
const HUD_INK := Color("FBEFD6") # main text on lacquer
const HUD_INK_SOFT := Color("E5CFA4") # hotkeys and secondary text
const HUD_EDGE := Color("120A06") # the thin ink outline
const HUD_GOLD := Color("E9BE6A") # inlay line, cost seal
const HUD_SEAL_INK := Color("23130A") # text on the gold seal
const HUD_SEAL_EMPTY := Color("2A1810")
const HUD_ICON_DISC := Color("F7E7C2") # plants need a pale ground to read on lacquer
const HUD_ACCENT := Color("FFD27A") # the host's selection ring
const HUD_GUEST := Color("7FDDF2") # the guest's selection ring
const HUD_DANGER := Color("B3261A") # red: threats only
const HUD_DANGER_INK := Color("FFF1DC")
const HUD_DANGER_TEXT := Color("FF9478") # red text on lacquer, where HUD_DANGER is too dark
const HUD_DIM := Color("120A06", 0.62) # behind Lacquer dialogs
const HUD_SPIRIT := Color("3D4274") # cool: spirits and notices
const HUD_SPIRIT_INK := Color("F3EFFF")
const HUD_NIGHT := Color("39457E") # start of the Leyline
const HUD_DUSK := Color("C9713A") # middle of the Leyline
const HUD_DAWN := Color("FFC765") # end of the Leyline, lit lanterns, earned stars
const HUD_HEALTH := Color("6FAE4A") # Pearl ring
const HUD_RING_TRACK := Color("120A06")
const HUD_SHADOW := Color("120A06", 0.35)
const HUD_FLASH := Color("FFF4D6")
const HUD_PEARL_TOP := Color("FFFDF2")
const HUD_PEARL_BOT := Color("F3D9A6")
const HUD_FACET_LIGHT := Color("FFF2A8")
const HUD_FACET_SOFT := Color("FFE680")
const HUD_FACET_MID := Color("FFD84D")
const HUD_FACET_WARM := Color("F4B430")
const HUD_FACET_DEEP := Color("D9901E")
const HUD_FACET_EDGE := Color("3A2410")
const HUD_FONT_PATH := "res://assets/fonts/Fredoka-SemiBold.ttf"
## Text layer shared by the whole HUD: one font file on one z value is one batch
## at every size (MSDF). See HudCanvas.gd for the layer rules.
const HUD_Z_ICON := 1
const HUD_Z_OVER := 2 # over icons, under text: HudCanvas.paint_hud_overlay
const HUD_Z_TEXT := 3

static var _bold: FontVariation = null
static var _hud_font: Font = null


## Rounded box: `fill`, optional `edge` border of `border` px, optional soft `glow`.
static func box(fill: Color, edge: Color, radius: int, border: int = 2, margin: int = 0, glow: Color = Color(0, 0, 0, 0), glow_size: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	if glow_size > 0:
		sb.shadow_color = glow
		sb.shadow_size = glow_size
	return sb


## Cream paper card; `selected` swaps in the lantern-amber ring and glow.
static func card(selected: bool, radius: int, border: int, margin: int, glow_size: int) -> StyleBoxFlat:
	if selected:
		return box(PAPER_WARM, AMBER, radius, border + 1, margin, Color(AMBER, 0.55), glow_size)
	return box(PAPER, PAPER_EDGE, radius, border, margin)


## The HUD's only face. Never add a second weight, or an outline or shadow on a label:
## each costs one draw call per label.
static func hud_font() -> Font:
	if _hud_font == null:
		_hud_font = load(HUD_FONT_PATH)
		# Fredoka has no stars or arrows: fall back to a shipped face, never the OS's.
		_hud_font.fallbacks = [ThemeDB.fallback_font]
	return _hud_font


## A chamfered Lacquer box as a StyleBox, for dialogs and their controls. Dialogs open
## over a paused or dimmed scene, so these may cost a draw each; the live HUD may not
## (HudCanvas.gd). `corner_detail` 1 is what makes the corner a straight cut.
static func lacquer_box(fill: Color, edge: Color, cut: int = 7, border: int = 2, margin: int = 12, glow: Color = Color(0, 0, 0, 0), glow_size: int = 0) -> StyleBoxFlat:
	var sb := box(fill, edge, cut, border, margin, glow, glow_size)
	sb.corner_detail = 1
	return sb


## A bordered board on a stage: one fill and one edge weight, so the reference
## ledger and the pillar cards read as the same material.
static func board_box(margin: int = 0) -> StyleBoxFlat:
	return lacquer_box(Color(HUD_LACQUER_TOP, 0.92), Color(HUD_GOLD, 0.40), 8, 1, margin)


## The dialog sheet: lacquer, gold edge, soft shadow.
static func lacquer_panel(margin: int = 26) -> StyleBoxFlat:
	return lacquer_box(HUD_LACQUER_TOP, HUD_GOLD, 12, 3, margin, HUD_SHADOW, 12)


## Styles any Button as Lacquer. `danger` is the "click again to confirm" state.
static func lacquer_button(b: Button, primary: bool = false, danger: bool = false, font_size: int = 18) -> void:
	var fill := HUD_GOLD if primary else HUD_LACQUER_BOT
	var lit := HUD_ACCENT if primary else HUD_LACQUER_LIT
	var ink := HUD_SEAL_INK if primary else HUD_INK
	if danger:
		fill = HUD_DANGER
		lit = HUD_DANGER.lightened(0.14)
		ink = HUD_DANGER_INK
	var ring := HUD_DANGER_INK if danger else HUD_ACCENT
	var edge := HUD_EDGE if primary or danger else HUD_GOLD
	b.add_theme_font_override("font", hud_font())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", lacquer_box(fill, edge))
	b.add_theme_stylebox_override("hover", lacquer_box(lit, ring, 7, 2, 12, Color(ring, 0.45), 6))
	b.add_theme_stylebox_override("pressed", lacquer_box(HUD_GOLD, HUD_EDGE))
	b.add_theme_stylebox_override("disabled", lacquer_box(HUD_LOCKED_BOT, Color(HUD_GOLD, 0.3)))
	b.add_theme_stylebox_override("focus", lacquer_box(Color(ring, 0.0), ring, 7, 3, 12))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, ink)
	b.add_theme_color_override("font_pressed_color", HUD_SEAL_INK)
	b.add_theme_color_override("font_disabled_color", HUD_INK_SOFT)


## A label on the HUD's shared text layer.
static func hud_label(font_size: int, color: Color = HUD_INK) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", hud_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = HUD_Z_TEXT
	return label


## Bold display face for titles: the default font, emboldened (no font file shipped).
static func bold_font() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.7
	return _bold
