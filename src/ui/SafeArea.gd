class_name SafeArea
extends RefCounted

# Touch HUD padding for notches, the Dynamic Island, the home indicator and
# Android cutouts. The safe area is reported by the OS in screen pixels; this
# converts it to viewport units and shifts an edge-anchored Control's offsets,
# so the existing anchors/layout stay untouched.
#
# The shift depends on which edge the Control is pinned to:
#   - stretched across an axis: pad both sides (offset_left += left, ...)
#   - pinned to the far edge (anchor 1): move the whole control inward
#   - pinned to the near edge (anchor 0): move the whole control inward
#   - centred (anchor 0.5): leave it alone
# This preserves the control's authored size; padding only one side of a
# right-aligned button would otherwise shrink it.
#
# Usage: call SafeArea.apply(control) once in _ready(), after the scene set its
# offsets. Desktop and non-touch runs are a no-op, so the editor layout and the
# desktop draw-call baseline are unchanged. The original offsets are cached in
# metadata, so re-applying (e.g. after a rotation) re-derives from the authored
# layout instead of stacking insets.

const META_BASE := &"safe_area_base_offsets"
const EPSILON := 0.001

static func apply(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	if GameManager == null or not GameManager.is_touch_ui():
		return
	var viewport := control.get_viewport()
	if viewport == null:
		return
	var safe := DisplayServer.get_display_safe_area()
	var window := DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0:
		return
	var logical := viewport.get_visible_rect().size
	# maxf: some desktop servers report a safe rect larger than the window.
	var left := maxf(0.0, float(safe.position.x) / float(window.x) * logical.x)
	var top := maxf(0.0, float(safe.position.y) / float(window.y) * logical.y)
	var right := maxf(0.0, float(window.x - safe.end.x) / float(window.x) * logical.x)
	var bottom := maxf(0.0, float(window.y - safe.end.y) / float(window.y) * logical.y)
	var base: Array = control.get_meta(META_BASE, [
		control.offset_left, control.offset_top,
		control.offset_right, control.offset_bottom,
	])
	control.set_meta(META_BASE, base)
	var l := float(base[0])
	var t := float(base[1])
	var r := float(base[2])
	var b := float(base[3])
	# Horizontal.
	if absf(control.anchor_left - control.anchor_right) <= EPSILON:
		if control.anchor_left >= 1.0 - EPSILON:
			l -= right
			r -= right
		elif control.anchor_left <= EPSILON:
			l += left
			r += left
	else:
		l += left
		r -= right
	# Vertical.
	if absf(control.anchor_top - control.anchor_bottom) <= EPSILON:
		if control.anchor_top >= 1.0 - EPSILON:
			t -= bottom
			b -= bottom
		elif control.anchor_top <= EPSILON:
			t += top
			b += top
	else:
		t += top
		b -= bottom
	control.offset_left = l
	control.offset_top = t
	control.offset_right = r
	control.offset_bottom = b
