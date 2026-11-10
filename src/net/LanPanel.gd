class_name LanPanel
extends Control

# LAN co-op panel (CONTRACT(lan-coop)), opened from the atlas. One device hosts
# from here, the other joins either from the auto-discovered host list or by
# typing an IPv4 address (the fallback for networks that drop broadcasts).
# Closing the panel stops discovery; leaving the atlas for a battle frees it,
# and Net stops browsing on the host's start event.
#
# The room is transport only: the host still picks the level on the atlas, and
# the guest follows it into the battle (GameFlow.remote_play_level).
# Every player-facing string goes through tr(); the script is listed in
# project.godot translations_pot_files (UI i18n contract).

signal closed

var _status: Label
var _host_button: Button
var _leave_button: Button
var _addresses: Label
var _join_box: VBoxContainer
var _host_list: VBoxContainer
var _ip_edit: LineEdit
var _join_button: Button
var _close_button: Button
var _started_browse: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	z_index = 20 # over the logo and HUD text layers, or they show through the backdrop
	_build()
	if Net != null:
		Net.role_changed.connect(_on_role_changed)
		Net.hosts_changed.connect(_on_hosts_changed)
		Net.guest_joined.connect(_refresh)
		Net.guest_left.connect(_refresh)
		Net.join_succeeded.connect(_on_join_succeeded)
		Net.join_failed.connect(_on_join_failed)
		Net.lobby_received.connect(_on_lobby_received)


func _exit_tree() -> void:
	if _started_browse and Net != null:
		Net.stop_browsing()


# ========================================================
# OPEN / CLOSE
# ========================================================

func open() -> void:
	visible = true
	if Net != null and not Net.is_online() and not _started_browse:
		Net.browse()
		_started_browse = true
	_refresh()


func close() -> void:
	visible = false
	if _started_browse and Net != null:
		Net.stop_browsing()
		_started_browse = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close()


# ========================================================
# BUILD
# ========================================================

func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UiPalette.HUD_DIM
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(440.0, get_viewport_rect().size.x - 64.0), 0.0)
	panel.add_theme_stylebox_override("panel", UiPalette.lacquer_panel(24))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := _label(30, UiPalette.HUD_ACCENT)
	title.text = tr("LAN Co-op")
	box.add_child(title)

	_status = _label(17, UiPalette.HUD_INK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	box.add_child(_status)

	_addresses = _label(16, UiPalette.HUD_INK_SOFT)
	_addresses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_addresses.visible = false
	box.add_child(_addresses)

	_host_button = _button(tr("Host a game"), true)
	_host_button.pressed.connect(_on_host_pressed)
	box.add_child(_host_button)

	_leave_button = _button(tr("Close room"))
	_leave_button.pressed.connect(_on_leave_pressed)
	box.add_child(_leave_button)

	_join_box = VBoxContainer.new()
	_join_box.add_theme_constant_override("separation", 8)
	box.add_child(_join_box)

	var nearby := _label(16, UiPalette.HUD_INK_SOFT)
	nearby.text = tr("Hosts nearby")
	_join_box.add_child(nearby)

	_host_list = VBoxContainer.new()
	_host_list.add_theme_constant_override("separation", 4)
	_join_box.add_child(_host_list)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_join_box.add_child(row)

	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = tr("Host IP address")
	_ip_edit.text = Net.last_ip() if Net != null else ""
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.custom_minimum_size = Vector2(0.0, 40.0)
	_ip_edit.add_theme_font_override("font", UiPalette.hud_font())
	_ip_edit.add_theme_font_size_override("font_size", 17)
	_ip_edit.add_theme_stylebox_override("normal", UiPalette.lacquer_box(UiPalette.HUD_SEAL_EMPTY, UiPalette.HUD_GOLD, 6, 2, 10))
	_ip_edit.add_theme_stylebox_override("focus", UiPalette.lacquer_box(UiPalette.HUD_SEAL_EMPTY, UiPalette.HUD_ACCENT, 6, 2, 10, Color(UiPalette.HUD_ACCENT, 0.45), 6))
	_ip_edit.add_theme_color_override("font_color", UiPalette.HUD_INK)
	_ip_edit.add_theme_color_override("font_placeholder_color", UiPalette.HUD_INK_SOFT)
	_ip_edit.add_theme_color_override("caret_color", UiPalette.HUD_ACCENT)
	_ip_edit.add_theme_color_override("selection_color", Color(UiPalette.HUD_ACCENT, 0.4))
	_ip_edit.text_submitted.connect(_on_ip_submitted)
	_ip_edit.text_changed.connect(_on_ip_changed)
	row.add_child(_ip_edit)

	_join_button = _button(tr("Join"))
	_join_button.pressed.connect(_on_join_pressed)
	row.add_child(_join_button)

	_close_button = _button(tr("Back"))
	_close_button.pressed.connect(close)
	box.add_child(_close_button)


func _button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 44.0)
	UiPalette.lacquer_button(b, primary)
	return b


## Dialog text, so the panel is drawn on the default layer rather than the HUD's.
func _label(font_size: int, color: Color) -> Label:
	var label := UiPalette.hud_label(font_size, color)
	label.z_index = 0
	return label


# ========================================================
# STATE
# ========================================================

func _refresh() -> void:
	if Net == null:
		return
	var hosting := Net.is_host()
	var guest := Net.is_guest()
	_host_button.visible = not hosting and not guest
	_leave_button.visible = hosting or guest
	_join_box.visible = not hosting and not guest

	if hosting:
		_leave_button.text = tr("Close room")
		_set_status(tr("Player 2 connected") if Net.guest_connected() else tr("Waiting for player 2"))
		var ips := Net.local_addresses()
		_addresses.visible = not ips.is_empty()
		if not ips.is_empty():
			_addresses.text = tr("Your IP: %s") % ips[0]
	elif guest:
		_leave_button.text = tr("Leave room")
		var host_name := str(Net.lobby_state.get("name", ""))
		_set_status(tr("Connected to %s") % host_name if not host_name.is_empty() else tr("Connecting…"))
		_addresses.visible = false
	else:
		_set_status("")
		_addresses.visible = false
		_keep_ip()
		_join_button.disabled = _ip_edit.text.strip_edges().is_empty()

	if not hosting and not guest:
		_rebuild_hosts(Net.known_hosts() if Net.browse_active() else [])


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()


func _rebuild_hosts(hosts: Array) -> void:
	for child in _host_list.get_children():
		_host_list.remove_child(child)
		child.queue_free()
	if hosts.is_empty():
		var none := _label(16, UiPalette.HUD_INK_SOFT)
		none.text = tr("Searching for hosts…")
		_host_list.add_child(none)
		return
	for h in hosts:
		var b := _button("")
		var playing := str(h.get("state", "lobby")) == "battle"
		# Display only: the address is data, the "(playing)" suffix is translated.
		b.text = "%s — %s%s" % [h.get("name", h.get("ip", "")), h.get("ip", ""), tr(" (playing)") if playing else ""]
		b.disabled = playing
		if not playing:
			b.pressed.connect(_join.bind(str(h.get("ip", ""))))
		_host_list.add_child(b)


func _keep_ip() -> void:
	if _ip_edit.text.strip_edges().is_empty() and Net.last_ip() != "":
		_ip_edit.text = Net.last_ip()


# ========================================================
# ACTIONS
# ========================================================

func _on_host_pressed() -> void:
	if Net == null:
		return
	var err := Net.host_game()
	_refresh()
	if not err.is_empty():
		_set_status(err)


func _on_leave_pressed() -> void:
	if Net == null:
		return
	if Net.is_host():
		Net.close_room()
	else:
		Net.stop()
	_resume_browse()
	_refresh()


func _resume_browse() -> void:
	if Net == null or not visible or Net.is_online() or _started_browse:
		return
	Net.browse()
	_started_browse = true


func _on_join_pressed() -> void:
	_join(_ip_edit.text)


func _on_ip_submitted(text: String) -> void:
	_join(text)


func _on_ip_changed(_text: String) -> void:
	_join_button.disabled = _ip_edit.text.strip_edges().is_empty()


func _join(ip: String) -> void:
	if Net == null:
		return
	var err := Net.join_game(ip)
	if not err.is_empty():
		_set_status(err)
		return
	Net.stop_browsing()
	_started_browse = false
	_set_status(tr("Connecting…"))


func _on_role_changed(_role: int) -> void:
	_refresh()


func _on_hosts_changed(hosts: Array) -> void:
	if visible and Net != null and not Net.is_online():
		_rebuild_hosts(hosts)


func _on_join_succeeded(_host_name: String) -> void:
	_refresh()


func _on_join_failed(reason: String) -> void:
	_resume_browse()
	_refresh()
	_set_status(reason)


func _on_lobby_received(state: Dictionary) -> void:
	if str(state.get("state", "lobby")) == "battle":
		_set_status(tr("The host is starting a level…"))
