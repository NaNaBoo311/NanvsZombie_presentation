extends "res://src/menus/title/TitleMenu.gd"

# PresentationTitle — the presentation build's front door. It inherits the game's
# whole 3D title stage (TitleMenu.tscn: eclipse, leyline, island chain, Pearl,
# vignette, effects and camera settle) and replaces only the UI built on top.
#
# The stage's scene owns the camera, lights, bake and effects. This script owns the
# cover: it swaps TitleMenu's logo/menu stack for PresentationCover and leaves the
# inherited test, capture and viewport code in place. GameFlow.TITLE_SCENE points
# here; the original title scene is untouched.

var _cover: PresentationCover


func _build_ui() -> void:
	_cover = PresentationCover.new()
	_cover.name = "Cover"
	_ui.add_child(_cover)
	_title_block = _cover.title_block
	_cover.play_pressed.connect(_on_primary)
	_cover.quit_pressed.connect(_on_quit)
	if not GameManager.is_touch_ui():
		_cover.focus_play()


func _fade_in_ui() -> void:
	if _cover != null:
		_cover.play_intro()


## The cover's one action opens the contents page. The playable build lives one
## step further in, on the contents page, so the cover never skips the talk.
func _on_primary() -> void:
	GameFlow.open_contents()
