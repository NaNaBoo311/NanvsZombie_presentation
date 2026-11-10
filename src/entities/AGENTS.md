# Entities Subsystem

Defines plants, enemies, projectiles, camera, defend targets, and shared markers.

## Scope & Key Files

- `src/entities/plants/base/PlantBase.gd` — base class for plants; owns targeting cones, facing rotation, attack cadence, and `uneatable` trap handling.
- `src/entities/plants/base/AuraPlant.gd` — base for plants that act in a radius on a fixed beat (override `_pulse()`); owns the stun gate and idle-cost skip.
- `src/entities/enemies/hungry_ghost/HungryGhost.gd` — base class for enemies; owns nav route following, biting, burrow-rise, and dais targeting.
- `src/entities/projectiles/Projectile.gd` — projectile movement, impact detection, and trail particle triggers.
- `src/entities/house/CentralHouse.gd` — defended target (pearl on the central dais). Node group is `CentralHouse`.
- `src/entities/shared/FactionMarker.gd` — ground ring visual indicator for unit alignment.
- `src/entities/camera/ThirdPersonCamera.gd` — combat camera positioning, orbital angles, preset framing, and mouse/touch pan.

## Registration Contracts

- Adding a plant: follow `docs/CONTRACTS.md#add-plant` (3 places: generator, entity scene/script, and unit JSON).
- Adding an enemy: follow `docs/CONTRACTS.md#add-enemy` (3 places: generator, entity scene/script, and unit JSON).
- Adding a projectile: follow `docs/CONTRACTS.md#add-projectile` (3 places: projectile JSON, projectile scene, and plant JSON).

## Invariants & Traps

- **Unit Initialization**:
  Every entity subclass must assign `unit_id = "<id>"` in its `_init()` method to bind with `src/core/BalanceDB.gd`.
- **Data-Driven Stats**:
  Combat numbers (HP, damage, attack speed, cost) must live in `data/units/` or `data/projectiles/`. Never hardcode stats in `.gd` or `.tscn` files.
- **Collision Matrix**:
  - Layer 3: Plants
  - Layer 4: Enemies
  - Layer 5: Projectiles (Mask 4: Enemies)
- **Ground Traps**:
  Ground trap plants set `uneatable = true` in `_init()`. Ghosts ignore uneatable plants and path over them without biting.
- **Physics Performance**:
  Never compute trigonometric functions, square roots, or vector divisions inside `_physics_process()`. Precompute cosines and squared radii in `_ready()`.
- **Remote copies (CONTRACT(lan-coop))**:
  A replicated entity carries `is_remote` and must skip AI, collision, damage and rewards in its
  own script. Set the flag before `add_child()` when the class acts from `_ready()`; a guard only
  in `_process()` lets the first frame run on the guest.

## Test Flags

```bash
GODOT=/home/nanaboo/Documents/Godot_v4.7.2/Godot_v4.7.2-stable_linux.x86_64
DISPLAY=:0 $GODOT --path . -- --preview-test  # test card, scale, and placement ghost
DISPLAY=:0 $GODOT --path . -- --ghost-test    # test basic enemy AI and march behaviour
DISPLAY=:0 $GODOT --path . -- --round-test    # verify all unit scenes and models load
```
