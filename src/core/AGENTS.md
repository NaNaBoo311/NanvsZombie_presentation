# Core Subsystem

Maintains global lifecycle state, autoload singletons, audio management, and database registries.

## Scope & Key Files

- `src/core/GameManager.gd` — primary autoload; owns sun economy, alive enemy tracking, and victory/defeat outcomes. The guest's per-player selection/tool are the `p2_*` mirrors.
- `src/core/SeedCooldowns.gd` — seed recharge, owned by `GameManager`.
- `src/core/GameSettings.gd` — volume and fullscreen; saved apart from `Progress`.
- `src/core/GameFlow.gd` — state machine directing transitions across the title, atlas menu, briefing, battle scene, and result dialogs; the host picks the level and the guest follows `Net.start_level_received`.
- `src/core/EventBus.gd` — decoupled publish-subscribe signal bus for all cross-system events; selection/tool signals carry `player_id` (CONTRACT(player-signals)).
- `src/core/Audio.gd` — sound effects and music player routing through `default_bus_layout.tres`.
- `src/core/LevelDB.gd` — world, map, and level catalog reader and validator (`data/worlds/`, `data/maps/`, `data/levels/`).
- `src/core/BalanceDB.gd` — plant, enemy, and projectile definition reader (`data/units/`, `data/projectiles/`).
- `src/core/Progress.gd` — persistence for completed levels, unlock flags, and star ratings.

## Invariants & Traps

- **Autoload Authority**:
  State singletons (`GameManager`, `EventBus`, `Audio`, `LevelDB`, `BalanceDB`, `Progress`, `Net`) are globally accessible autoloads. Subsystems must query these singletons rather than maintaining duplicate local caches. `Net` is listed first so its node path resolves on every peer for RPCs (CONTRACT(lan-coop)).
- **Host-only progress**:
  `Progress` records only on the host; every completion path is guarded by `GameManager.is_client()`. The guest is a thin client and never unlocks anything.
- **Decoupled Event Flow**:
  Leaf entities and UI components must dispatch signals through `EventBus.gd`. Never use hardcoded node paths or `get_node("../../X")`.
- **Sound Registration (CONTRACT(add-sound))**:
  When adding SFX or music, register audio keys in `src/core/Audio.gd` and verify stream paths against `assets/audio/`.
- **Level and Unit Data Schema**:
  All content definitions in `data/` are validated at boot. Missing scene files or mismatched IDs trigger boot-time assertions. Run `--round-test` to validate all entries.

## Test Flags

```bash
GODOT=/home/nanaboo/Documents/Godot_v4.7.2/Godot_v4.7.2-stable_linux.x86_64
DISPLAY=:0 $GODOT --path . -- --flow-test       # test menu, briefing, and battle state transitions
DISPLAY=:0 $GODOT --path . -- --title-test      # boot title, menu wiring, LAN panel, atlas handoff
DISPLAY=:0 $GODOT --path . -- --progress-test   # test level unlock and save persistence
DISPLAY=:0 $GODOT --path . -- --round-test      # test database schema and asset existence
DISPLAY=:0 $GODOT --path . -- --lan-flow-test host  # LAN end-to-end; second process: client
```
