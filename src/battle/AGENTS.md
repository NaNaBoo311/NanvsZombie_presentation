# Battle Subsystem

Guides combat loop execution, wave spawning, grid plant placement, and shovel mechanics.

## Scope & Key Files

- `src/battle/EnemySpawner.gd` — wave sequence director, burrow-rise instancing, and zone spawn dispatch.
- `src/battle/PlacementManager.gd` — grid raycasting, hover ghost preview, cost debit, and plant placement.
- `src/battle/ShovelManager.gd` — shovel tool toggle, targeted plant highlighting, and removal.
- `src/battle/DioramaWorld.gd` — battle scene container connecting map, camera, HUD, and battle managers; creates the online `NetBridge`.
- `src/battle/NavTest.gd` — route walk speed and clearance verification.
- `src/battle/TouchTest.gd` — headless touch contract test (`--touch-test`): real
  `InputEventScreenTouch`/`ScreenDrag` through the emulated-mouse chain.

## State Ownership

- **Sun Balance & Round State**: strictly owned by `src/core/GameManager.gd`. Never store sun balance locally.
- **Grid Occupancy**: owned by `src/battle/PlacementManager.gd`. Cell size is 2×2 m (1 tile).
- **Per-player selection**: `GameManager` mirrors the guest as `p2_*` state; sun, health, loadout and tiles stay shared. Signals carry `player_id` (CONTRACT(player-signals)).
- **Active Enemy Count**: tracked by `GameManager` via signals `enemy_spawned` and `enemy_killed` in `src/core/EventBus.gd`.
- **Signals**: communicate strictly through `EventBus`. Never use direct `get_parent()` traversals.

## Invariants & Traps

- **Burrow-rise Spawn Order (CONTRACT(add-wave))**:
  Always set `enemy.is_rising = true` **before** calling `add_child()`, then call `enemy.spawn_buried(pos)` **after** `add_child()`. Setting `is_rising` after `add_child()` triggers a duplicate `enemy_spawned` signal and causes alive-enemy count drift.
- **Airborne & Rising Targeting**:
  Plants must ignore enemies where `is_rising == true` or `is_airborne == true`. Every targeting filter must check both flags or mid-air gliders will be targeted prematurely.
- **Collision Layers**:
  Plants occupy layer 3; enemies occupy layer 4; projectiles occupy layer 5 (mask 4).
- **Nav Route Clearance**:
  Kinematic enemies on baked routes clip through obstacles if clearance is broken. Run `--round-test` after changing map props or foliage.
- **Online bridge cost**:
  `DioramaWorld` builds `NetBridge` only while `Net.is_online()`. Never create it in `_ready()`
  unconditionally, or solo play pays for a node and its per-frame work (invariant 7).
- **Replicated placement**:
  The guest's commit is a command, not a local spawn: the host validates, spends, spawns and
  broadcasts (CONTRACT(lan-coop)). Never let the guest write `occupied_tiles` or `current_sun`.

## Test Flags

```bash
GODOT=/home/nanaboo/Documents/Godot_v4.7.2/Godot_v4.7.2-stable_linux.x86_64
DISPLAY=:0 $GODOT --path . -- --spawner-demo  # verify rise animations and wave completion
DISPLAY=:0 $GODOT --path . -- --touch-test    # press/lift placement, pinch, orbit, rotate
DISPLAY=:0 $GODOT --path . -- --nav-test      # verify route distances and walk times
DISPLAY=:0 $GODOT --path . -- --round-test    # full battle integration & scene load test
DISPLAY=:0 $GODOT --path . -- --lan-flow-test host  # then a second process: --lan-flow-test client
```
