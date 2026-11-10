# Maps Subsystem

Manages diorama island environments, nav-grid generation, zone boundaries, and route clearance.

## Scope & Key Files

- `src/maps/MapDefinition.gd` — base class for diorama maps; manages lighting links, defense target anchor, and zone setups.
- `src/maps/NavGrid.gd` — grid navigation generator, pathfinding routes, connectivity validation, and stale input hash verification.
- `src/maps/RouteClearance.gd` — kinematic obstacle collision sweep for baked routes.
- `src/maps/landmark_81/` — Landmark 81 diorama map scripts and zones.
- `src/maps/hoan_kiem/` — Hoàn Kiếm Lake diorama map scripts and zones.
- `src/maps/hoi_an/` — Hội An Ancient Town diorama map scripts and zones.

## Registration Contracts

- Adding a map: follow `docs/CONTRACTS.md#add-map`. Each map owns its folder under `src/maps/<map_id>/` and configuration under `data/maps/<map_id>/map.json`.

## Invariants & Traps

- **Region Spawns vs. Deprecated Gates (CONTRACT(add-wave))**:
  In `data/maps/<map_id>/nav.json`, spawn locations are specified by `regions` (e.g. `north`, `east`, `south`, `west`). The legacy `"gate"` field is forbidden. If a wave omits a zone, it round-robins across all valid regions.
- **Nav Mesh Baking**:
  Whenever map geometry, tree positions (`forest.json`), or props move, re-bake routes using `--map <map_id> --nav-bake`. Enemies move kinematically along routes and will clip through obstacles if clearance is compromised.
- **Route Clearance Verification**:
  Always verify navigation changes with `src/battle/NavTest.gd` (`--nav-test`) and `--round-test`.
- **Decoupled Architecture**:
  Map scripts must not directly reference UI or game managers. All state changes emit through `src/core/EventBus.gd`.

## Test Flags

```bash
GODOT=/home/nanaboo/Documents/Godot_v4.7.2/Godot_v4.7.2-stable_linux.x86_64
DISPLAY=:0 $GODOT --path . -- --map landmark_81               # load a specific map
DISPLAY=:0 $GODOT --path . -- --map hoan_kiem --nav-bake     # bake nav routes for map
DISPLAY=:0 $GODOT --path . -- --map-switch-test               # test switching between all maps
```
