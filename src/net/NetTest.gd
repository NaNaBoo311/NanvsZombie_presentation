extends RefCounted

# --net-test: two-process LAN smoke test (CONTRACT(lan-coop)).
#
#   host:   $GODOT --path . -- --net-test host
#   client: $GODOT --path . -- --net-test client [ip]   (default 127.0.0.1)
#
# Both boot straight into the battle shell. The test covers the parts a single
# process cannot: the ENet handshake, the host->guest event channel (ping) and
# the guest->host command channel (pong). Replication itself is exercised by
# playing a level from the atlas with both processes; this flag exists so CI can
# fail loudly when the transport regresses. Exit code 0 = PASS, 1 = FAIL.
# Loaded only by DioramaWorld._ready() under the flag (RefCounted coroutine,
# kept alive by _alive exactly like PerfTest).

const TIMEOUT_SEC := 20.0

static var _alive: RefCounted = null # keeps the awaiting coroutine alive

var _tree: SceneTree
var _done := false


func run(world: Node) -> void:
	_alive = self
	_tree = world.get_tree()
	var args := OS.get_cmdline_user_args()
	var index := args.find("--net-test")
	var mode := "host"
	if index >= 0 and index + 1 < args.size():
		mode = args[index + 1]
	var ip := "127.0.0.1"
	if index >= 0 and index + 2 < args.size() and args[index + 2].count(".") == 3:
		ip = args[index + 2]
	_start_watchdog(TIMEOUT_SEC)
	if mode == "client":
		await _run_client(ip)
	else:
		await _run_host(world)


func _run_host(world: Node) -> void:
	var got_guest := [false]
	var got_pong := [false]
	Net.guest_joined.connect(func() -> void: got_guest[0] = true)
	Net.command_received.connect(func(cmd: Dictionary) -> void:
		if str(cmd.get("t", "")) == "pong":
			got_pong[0] = true)
	var err := Net.host_game("NetTest Host")
	if not err.is_empty():
		_fail("host_game: " + err)
		return
	if world != null and world.has_method("ensure_net_bridge"):
		world.ensure_net_bridge()
	print("[NetTest] Hosting on UDP %d. Waiting for a guest…" % Net.GAME_PORT)
	if not await _wait_flag(got_guest, TIMEOUT_SEC):
		_fail("no guest joined")
		return
	Net.send_event({"t": "ping"})
	if not await _wait_flag(got_pong, TIMEOUT_SEC):
		_fail("guest never answered pong")
		return
	_pass("host: guest joined, event + command channels work")


func _run_client(ip: String) -> void:
	var got_join := [false]
	var got_ping := [false]
	Net.join_succeeded.connect(func(_host_name: String) -> void: got_join[0] = true)
	Net.event_received.connect(func(ev: Dictionary) -> void:
		if str(ev.get("t", "")) == "ping":
			got_ping[0] = true)
	var err := Net.join_game(ip)
	if not err.is_empty():
		_fail("join_game: " + err)
		return
	print("[NetTest] Joining %s:%d…" % [ip, Net.GAME_PORT])
	if not await _wait_flag(got_join, TIMEOUT_SEC):
		_fail("no welcome from the host")
		return
	print("[NetTest] Guest handshake OK, waiting for the host event…")
	if not await _wait_flag(got_ping, TIMEOUT_SEC):
		_fail("no host event")
		return
	Net.send_command({"t": "pong"})
	# Let ENet flush the command before quitting: quit() drops the peer at once.
	await _tree.create_timer(0.6).timeout
	_pass("client: welcome, event and command channels work")


func _wait_flag(flag: Array, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not flag[0] and Time.get_ticks_msec() < deadline and not _done:
		await _tree.create_timer(0.05).timeout
	return flag[0]


func _start_watchdog(seconds: float) -> void:
	await _tree.create_timer(seconds, true).timeout
	if not _done:
		push_error("[NetTest] FAIL: timed out after %.0fs" % seconds)
		_tree.quit(1)


func _pass(message: String) -> void:
	_done = true
	print("[NetTest] PASS: " + message)
	_tree.quit(0)


func _fail(message: String) -> void:
	_done = true
	push_error("[NetTest] FAIL: " + message)
	_tree.quit(1)
