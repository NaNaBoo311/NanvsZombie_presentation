extends Node

# LAN co-op transport. Two players on the same network: one HOST runs the
# simulation, one GUEST renders it and sends commands (CONTRACT(lan-coop)).
#
# Everything network-shaped lives here, on an autoload, so `@rpc` node paths are
# identical on both peers across every scene change. Game code never touches
# ENet: it calls send_command()/send_event() and listens to the signals below,
# which is what keeps a future internet transport a drop-in replacement.
#
# OFFline cost is zero: no sockets, no timers, no per-frame work until
# host_game() or browse() is called (set_process stays false).
#
# Discovery: the host broadcasts a one-line UTF-8 beacon on UDP 47811 once a
# second while its room is open; a browsing guest lists whoever answers. Manual
# IP entry is the fallback for networks that drop broadcasts (AP isolation).
# iOS needs NSLocalNetworkUsageDescription in Info.plist or it blocks this
# silently (TRAPS.md#ios-local-network).

enum Role { OFFLINE, HOST, GUEST }

signal role_changed(role: int)
signal guest_joined
signal guest_left
signal join_succeeded(host_name: String)
signal join_failed(reason: String)
signal hosts_changed(hosts: Array)
signal command_received(cmd: Dictionary) # host: a guest command
signal event_received(ev: Dictionary) # guest: a host event
signal snapshot_received(snap: Dictionary) # guest: unreliable enemy state
signal lobby_received(state: Dictionary) # guest: host lobby snapshot
signal link_lost(reason: String) # guest: host vanished
signal start_level_received(level_id: String) # guest: the host picked a level
signal session_end_received(reason: String) # guest: the host returned to the atlas

const PROTOCOL_VERSION := 1
const GAME_PORT := 47810
const DISCOVERY_PORT := 47811
const BEACON_PREFIX := "PVZ3DLAN1"
const MAX_PLAYERS := 2 # host + one guest
const BEACON_INTERVAL := 1.0
const HOST_TIMEOUT := 6.0 # a listed host disappears this long after its last beacon
const LAST_IP_PATH := "user://lan_last_ip.txt"

var role: int = Role.OFFLINE
## 0 = host/offline, 1 = guest. Input and selection routing read this.
var local_player_id: int = 0
## Host lobby snapshot, mirrored to the guest: {"name","level","state"}.
var lobby_state: Dictionary = {"name": "", "level": "", "state": "lobby"}
## False while a level runs: no mid-game joins and no reconnects (CONTRACT(lan-coop)).
var accepting_guests: bool = false

var _guest_peer_id: int = 0
var _host_name: String = ""

# Discovery
var _browsing := false
var _beacon_clock := 0.0
var _beacon: PacketPeerUDP = null
var _listener: PacketPeerUDP = null
var _hosts: Dictionary = {} # ip -> {"name","level","state","seen"}

func _ready() -> void:
	set_process(false)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ========================================================
# QUERIES
# ========================================================

func is_host() -> bool:
	return role == Role.HOST

func is_guest() -> bool:
	return role == Role.GUEST

func is_online() -> bool:
	return role != Role.OFFLINE

func guest_connected() -> bool:
	return role == Role.HOST and _guest_peer_id != 0

func game_version() -> String:
	return "%s/%s" % [PROTOCOL_VERSION, str(ProjectSettings.get_setting("application/config/version", "0"))]

# ========================================================
# HOSTING
# ========================================================

## Open a room. Returns an error string ("" on success).
func host_game(player_name: String = "") -> String:
	if is_online():
		stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_PLAYERS - 1)
	if err != OK:
		return "Cannot listen on UDP %d (error %d)." % [GAME_PORT, err]
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	local_player_id = 0
	_host_name = player_name.strip_edges() if not player_name.strip_edges().is_empty() else tr("Host")
	lobby_state = {"name": _host_name, "level": "", "state": "lobby"}
	accepting_guests = true
	_start_beacon()
	role_changed.emit(role)
	return ""

## Close the room and tell the guest why.
func close_room(reason: String = "") -> void:
	if role == Role.HOST and _guest_peer_id != 0 and reason.is_empty():
		send_event({"t": "closed"})
	stop(reason)

# ========================================================
# JOINING
# ========================================================

## Connect to a host by IPv4 address. join_succeeded / join_failed follow.
func join_game(ip: String) -> String:
	if is_online():
		stop()
	var address := ip.strip_edges()
	if address.is_empty():
		return tr("Enter the host's IP address.")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, GAME_PORT)
	if err != OK:
		return "Cannot connect to %s:%d (error %d)." % [address, GAME_PORT, err]
	multiplayer.multiplayer_peer = peer
	_save_last_ip(address)
	role = Role.GUEST # provisional until the handshake answers
	role_changed.emit(role)
	return ""

func stop(reason: String = "") -> void:
	var was := role
	var had_guest := was == Role.HOST and _guest_peer_id != 0
	role = Role.OFFLINE
	local_player_id = 0
	_guest_peer_id = 0
	_host_name = ""
	accepting_guests = false
	lobby_state = {"name": "", "level": "", "state": "lobby"}
	multiplayer.multiplayer_peer = null
	_stop_beacon()
	if was != Role.OFFLINE:
		role_changed.emit(role)
	if had_guest:
		guest_left.emit()
	if was == Role.GUEST and not reason.is_empty():
		link_lost.emit(reason)

## Host: a level is being entered. Closes the room to new peers and tells the
## guest which level to load, before the host's own scene starts loading so both
## devices boot the battle in parallel.
func begin_session(level_id: String) -> void:
	if role != Role.HOST:
		return
	accepting_guests = false
	set_lobby({"name": _host_name, "level": level_id, "state": "battle"})
	send_event({"t": "start", "level": level_id})

## Host: back in the atlas. The room accepts a friend again and the guest (if
## any) leaves the battle too, staying connected for the next level.
func end_session() -> void:
	if role != Role.HOST:
		return
	if _guest_peer_id != 0:
		send_event({"t": "end"})
	accepting_guests = true
	set_lobby({"name": _host_name, "level": "", "state": "lobby"})

func last_ip() -> String:
	if not FileAccess.file_exists(LAST_IP_PATH):
		return ""
	var f := FileAccess.open(LAST_IP_PATH, FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""

func _save_last_ip(ip: String) -> void:
	var f := FileAccess.open(LAST_IP_PATH, FileAccess.WRITE)
	if f:
		f.store_string(ip)
		f = null

# ========================================================
# MESSAGES
# ========================================================

## Guest -> host. Reliable and ordered; commands are rare.
func send_command(cmd: Dictionary) -> void:
	if role != Role.GUEST or multiplayer.multiplayer_peer == null:
		return
	_rpc_command.rpc_id(1, cmd)

## Host -> guest. Reliable and ordered; joins the same channel as commands.
func send_event(ev: Dictionary) -> void:
	if role != Role.HOST or _guest_peer_id == 0:
		return
	_rpc_event.rpc_id(_guest_peer_id, ev)

## Host -> guest enemy state, sent on the unreliable-ordered channel: a lost
## snapshot is replaced by the next one, so lag never accumulates.
func send_snapshot(snap: Dictionary) -> void:
	if role != Role.HOST or _guest_peer_id == 0:
		return
	_rpc_snapshot.rpc_id(_guest_peer_id, snap)

## Host tells the guest what the room looks like (level picked, state).
func set_lobby(state: Dictionary) -> void:
	lobby_state = state
	if role == Role.HOST and _guest_peer_id != 0:
		_rpc_lobby.rpc_id(_guest_peer_id, state)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(payload: Dictionary) -> void:
	if role != Role.HOST:
		return
	var from := multiplayer.get_remote_sender_id()
	if int(payload.get("protocol", 0)) != PROTOCOL_VERSION or str(payload.get("version", "")) != game_version():
		rpc_id(from, "_rpc_rejected", tr("Version mismatch — both devices need the same build."))
		return
	if _guest_peer_id != 0 and from != _guest_peer_id:
		rpc_id(from, "_rpc_rejected", tr("That room is already full."))
		return
	if not accepting_guests and from != _guest_peer_id:
		rpc_id(from, "_rpc_rejected", tr("The host is already playing — join from the atlas."))
		return
	var joined := _guest_peer_id == 0
	_guest_peer_id = from
	rpc_id(from, "_rpc_welcome", {"player_id": 1, "name": _host_name, "lobby": lobby_state})
	if joined:
		guest_joined.emit()

@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(payload: Dictionary) -> void:
	role = Role.GUEST
	local_player_id = int(payload.get("player_id", 1))
	lobby_state = payload.get("lobby", lobby_state)
	join_succeeded.emit(str(payload.get("name", "")))
	role_changed.emit(role)

@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason: String) -> void:
	stop()
	join_failed.emit(reason)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_command(cmd: Dictionary) -> void:
	if role != Role.HOST:
		return
	cmd["from"] = local_player_id_of(multiplayer.get_remote_sender_id())
	command_received.emit(cmd)

@rpc("authority", "call_remote", "reliable")
func _rpc_event(ev: Dictionary) -> void:
	if role != Role.GUEST:
		return
	# Session messages are understood even when no battle scene is loaded yet.
	match str(ev.get("t", "")):
		"start":
			start_level_received.emit(str(ev.get("level", "")))
			return
		"end":
			session_end_received.emit(str(ev.get("reason", "")))
			return
		"closed":
			stop(tr("The host closed the room."))
			return
	event_received.emit(ev)

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(snap: Dictionary) -> void:
	if role != Role.GUEST:
		return
	snapshot_received.emit(snap)

@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(state: Dictionary) -> void:
	if role != Role.GUEST:
		return
	lobby_state = state
	lobby_received.emit(state)

## Peer id -> player id. The host is always 0 and the one guest is 1.
func local_player_id_of(_peer_id: int) -> int:
	return 1

# ========================================================
# CONNECTION EVENTS
# ========================================================

func _on_peer_connected(_id: int) -> void:
	# The guest is only "in" once the version handshake answers (see _rpc_hello).
	# Counting a bare TCP/ENet connection here would fill the room with a peer
	# that never finished joining and lock out the real guest.
	pass

func _on_peer_disconnected(id: int) -> void:
	if role != Role.HOST:
		return
	if id == _guest_peer_id:
		_guest_peer_id = 0
		guest_left.emit()

func _on_connected_to_server() -> void:
	if role != Role.GUEST:
		return
	_rpc_hello.rpc_id(1, {"protocol": PROTOCOL_VERSION, "version": game_version()})

func _on_connection_failed() -> void:
	if role != Role.GUEST:
		return
	stop()
	join_failed.emit(tr("No host answered. Check the IP and that you are on the same network."))

func _on_server_disconnected() -> void:
	if role != Role.GUEST:
		return
	stop()
	link_lost.emit(tr("The host left the game."))

# ========================================================
# DISCOVERY (UDP broadcast)
# ========================================================

func _start_beacon() -> void:
	_beacon_clock = 0.0
	if _beacon == null:
		_beacon = PacketPeerUDP.new()
		_beacon.set_broadcast_enabled(true)
		_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	set_process(true)

func _stop_beacon() -> void:
	_beacon = null
	_stop_listening()
	_refresh_processing()

## Start listening for host beacons (atlas co-op panel open).
func browse() -> void:
	if _browsing:
		return
	_browsing = true
	_hosts.clear()
	_open_listener()
	_refresh_processing()

func stop_browsing() -> void:
	if not _browsing:
		return
	_browsing = false
	_stop_listening()
	_refresh_processing()

func browse_active() -> bool:
	return _browsing

func known_hosts() -> Array:
	var out: Array = []
	for ip in _hosts.keys():
		var h: Dictionary = _hosts[ip]
		out.append({"ip": ip, "name": h.get("name", ip), "level": h.get("level", ""), "state": h.get("state", "")})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return out

func _open_listener() -> void:
	if _listener != null:
		return
	_listener = PacketPeerUDP.new()
	_listener.set_broadcast_enabled(true)
	if _listener.bind(DISCOVERY_PORT, "0.0.0.0") != OK:
		# Another instance on this machine already owns the port (two clients on
		# one desktop). Manual IP entry still works; say so once.
		_listener = null
		print("[Net] Discovery port %d busy: auto-discovery off, use the IP field." % DISCOVERY_PORT)

func _stop_listening() -> void:
	_listener = null

func _refresh_processing() -> void:
	set_process(role == Role.HOST or _browsing)

func _process(delta: float) -> void:
	if role == Role.HOST:
		_beacon_clock += delta
		if _beacon_clock >= BEACON_INTERVAL:
			_beacon_clock = 0.0
			_send_beacon()
	if _browsing:
		_poll_hosts()

func _send_beacon() -> void:
	if _beacon == null:
		return
	var payload := "%s|%d|%d|%s|%s|%s" % [
		BEACON_PREFIX, PROTOCOL_VERSION, GAME_PORT,
		lobby_state.get("name", "Host").replace("|", " "),
		str(lobby_state.get("level", "")), str(lobby_state.get("state", "lobby"))]
	_beacon.put_packet(payload.to_utf8_buffer())

func _poll_hosts() -> void:
	if _listener == null:
		return
	var before := _hosts_signature()
	var now := Time.get_ticks_msec()
	while _listener.get_available_packet_count() > 0:
		var buf := _listener.get_packet()
		var ip := _listener.get_packet_ip()
		if ip.is_empty() or ip == "0.0.0.0":
			continue
		var text := buf.get_string_from_utf8()
		if not text.begins_with(BEACON_PREFIX + "|"):
			continue
		var f := text.split("|")
		if f.size() < 6 or int(f[1]) != PROTOCOL_VERSION:
			continue
		var level := str(f[4])
		var host_name := str(f[3])
		if host_name.is_empty():
			host_name = ip
		_hosts[ip] = {"name": host_name, "level": level, "state": str(f[5]), "seen": now}
	for ip in _hosts.keys():
		if now - int(_hosts[ip].get("seen", 0)) > int(HOST_TIMEOUT * 1000.0):
			_hosts.erase(ip)
	# Emit only when the visible list changed: a beacon every second must not
	# rebuild the atlas panel every frame it is open.
	if _hosts_signature() != before:
		hosts_changed.emit(known_hosts())

func _hosts_signature() -> String:
	var parts := PackedStringArray()
	for h in known_hosts():
		parts.append("%s|%s|%s|%s" % [h["ip"], h["name"], h["level"], h["state"]])
	return ";".join(parts)

## IPv4 addresses a guest on the same network can dial, best first. Loopback,
## link-local and virtual interfaces (Docker bridges, VPN tunnels) are dropped:
## a guest that types the wrong address gets a timeout, which is worse than the
## panel showing nothing to type.
func local_addresses() -> PackedStringArray:
	var ranked: Array = []
	for iface in IP.get_local_interfaces():
		if _is_virtual_interface(str(iface.get("name", ""))):
			continue
		for addr in iface.get("addresses", []):
			var ip := str(addr)
			if ip.count(".") != 3 or ip.begins_with("127.") or ip.begins_with("169.254."):
				continue
			ranked.append([_address_rank(ip), ip])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := PackedStringArray()
	for entry in ranked:
		out.append(entry[1])
	return out


func _is_virtual_interface(name: String) -> bool:
	if name == "lo":
		return true
	for prefix in ["docker", "br-", "veth", "virbr", "vmnet", "vboxnet",
			"tun", "tap", "utun", "wg", "zt", "tailscale", "awdl", "llw", "anpi"]:
		if name.begins_with(prefix):
			return true
	return false


## Home routers first, then the other RFC 1918 ranges, then anything routable.
func _address_rank(ip: String) -> int:
	if ip.begins_with("192.168."):
		return 0
	if ip.begins_with("10."):
		return 1
	if ip.begins_with("172."):
		var second := int(ip.split(".")[1])
		if second >= 16 and second <= 31:
			return 2
	return 3
