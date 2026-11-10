# Net Subsystem

Two devices on one network: one host, one guest, no relay. The host simulates; the guest renders
and sends intents. CONTRACT(lan-coop) lists the files that must change together.

## Scope & Key Files

- `src/net/Net.gd` — autoload, registered first in `project.godot`. Owns the ENet peer, the UDP
  discovery beacon/listener, the version handshake, the room/lobby state and **every `@rpc`**.
  `Role { OFFLINE, HOST, GUEST }`; `GameManager.local_player_id()` is `0` on the host and `1`
  on the guest.
- `src/net/NetBridge.gd` — battle-side replication. Created by `DioramaWorld.ensure_net_bridge()`
  only while online, so solo play has no extra node and no per-frame work. Host mirror `EventBus`
  → events + 10 Hz `unreliable_ordered` enemy snapshots; guest events + commands → host.
- `src/net/LanPanel.gd` — atlas host/join panel: discovered rooms, manual IP fallback, room state.
- `src/net/NetTest.gd` — `--net-test host|client`, transport only, one process each.
- `src/net/LanFlowTest.gd` — `--lan-flow-test host|client`, the real atlas → battle → atlas flow
  including a guest placement and replicated wave.

## Invariants & Traps

- **RPCs only on `Net`**:
  A `@rpc` executes only when the node path matches on both peers. `Net` is an autoload, so its
  path survives every scene change. Never put an `@rpc` on a scene node (CONTRACT(lan-coop)).
- **Host authority**:
  Sun, house health, waves, spawns, damage and progress exist on the host. The guest's placement
  and dig are commands the host re-validates (`PlacementManager.remote_placement_allowed()`), and
  `Progress.mark_completed()` is guarded by `GameManager.is_client()`.
- **Remote copies**:
  Every replicated entity gets `is_remote` (or an equivalent spawn path) that turns off AI,
  collision, damage and rewards. Set it **before** `add_child()` for enemies and projectiles;
  plants are marked by `NetBridge` right after `spawn_plant()`.
- **Pause is local**:
  `GameManager.is_local_menu_open` overlays the pause panel; `get_tree().paused` stays false so
  the host's wave clock and the transport keep running.
- **No mid-game join**:
  `Net.begin_session()` closes the room and starts the level on both peers. A dropped guest goes
  back to the atlas (`Net.link_lost`); the host keeps playing solo.

## Test Flags

```bash
GODOT=/home/nanaboo/Documents/Godot_v4.7.2/Godot_v4.7.2-stable_linux.x86_64
DISPLAY=:0 $GODOT --path . -- --lan-flow-test host    # then, in another shell:
DISPLAY=:0 $GODOT --path . -- --lan-flow-test client  # join, level sync, placement, wave, return
DISPLAY=:0 $GODOT --path . -- --net-test host         # transport only
DISPLAY=:0 $GODOT --path . -- --net-test client
```
