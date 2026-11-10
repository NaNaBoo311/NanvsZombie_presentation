# Feat: enemies enter through gates at the map's landmarks

Status: draft
Owner: nanaboo

## Context
Today every enemy rises out of a dirt mound at a random point inside one of four rectangles just
outside the lawn (`spawn_zones` in `src/maps/landmark_81/Landmark81Map.tscn`), then walks in a
straight line to the pearl (`HungryGhost._get_march_direction`). That has three problems:
- It borrows zombie-game graves and ignores the map. Ghosts dig out of paved promenade three
  metres from the river.
- A random point along a 36 m strip gives the player nothing to read or plan around.
- The map's landmarks (bridges, stairs, the pier) play no part in the fight.

Enemies can't simply spawn at the landmarks, because they have **no pathfinding**. The strips
were pulled in close on purpose (plan `2026-09-27-08`): from farther out, straight lines run
through palms, lamps and the crescent ponds.

**Goal:** enemies enter through named **gates** at real landmarks, follow a **fixed path**
(data, no pathfinding) to one of 2–3 **entry lanes** at the lawn edge, then switch to today's
straight march.

User decisions (2026-09-30):
- Enemies still come from **every direction**: there is a gate on each side.
- **During this development phase, every gate is open for every spawn**, whatever the level
  says. Per-wave gate choice is designed now and switched on later (see *Later phases*).
- The mechanism is **shared**; only the data is per map. A map with no gates keeps today's
  behaviour.

## Measured facts the design depends on
| Fact | Value | Where |
|:--|:--|:--|
| Enemy movement | `CharacterBody3D`, `velocity.y = -2`, `move_and_slide()`, mask = layer 1 only | `HungryGhost._walk_toward` |
| What has collision | island meshes only, minus water, railings, soil, … The arch bridges, pier and props have **none** | `Landmark81Map._add_trimesh_collisions` |
| Spawn height | the spawner **ignores the sampled y** and uses `_surface_y + SURFACE_LIFT` (flat) | `EnemySpawner._run_telegraph` |
| Current clear entry band | `spawn_zones`: north z −29…−24, south z 24…29, east x 27…32, west x −32…−27 | `Landmark81Map.tscn` |
| Speeds | hungry ghost 1.2 m/s · pot ghost 0.9 · cat 2.0 · spider 2.0 | `data/units/enemies/*.json` |
| Lotus reach | 14 m forward cone | `data/units/plants/lotus_shooter.json` |
| North stairs | at x 0 and x 36, 8 m wide; plateau y 4.0 (z −110 → −74); the steps run from the wall (z ≈ −74.3) to z ≈ −66.3 | `data/maps/landmark_81/zones/north_city.json`, `Landmark81Zones._inside_stair` |
| North arch bridge | at (0, 0, −36), 4.2 × 1.16 × 13.06 m, spanning z −42.5 → −29.5 over the pond neck | `Landmark81Map.tscn`, `inspect_model.gd` |
| Canal arch bridge | at (48, 0.05, −10), rotated 90°, spanning x ≈ 41.5 → 54.5 | `Landmark81Map.tscn` |
| Water test | `Landmark81Zones.is_in_water(x, z)` is **true under both bridges** | `src/maps/landmark_81/Landmark81Zones.gd` |

Two consequences shape the design:
- Enemies can't walk the paths with physics. With nothing to collide with on the bridges and
  pier, they would fall into the water, and the stairs are 0.2 m steps.
- The spawner has to start from the gate's real height, for example y 4 on the plateau.

## Design

### Data: `data/maps/<map_id>/gates.json` (per map)
```json
{
  "dev_all_open": true,
  "reference_enemy": "hungry_ghost",
  "approach_sec_range": [12, 25],
  "approach_scale_range": [1.0, 2.5],
  "gates": {
    "north_stairs": {
      "side": "north_plaza",
      "approach_sec": 22,
      "path": [[0, -80, 4.0], [0, -74.4, 4.0], [0, -66.3], [0, -44], [0, -42.5], [0, -36, 1.0], [0, -29.5], [0, -27]],
      "over_water": [[4, 6]],
      "lanes": [[-10, -26.5], [0, -26.5], [10, -26.5]]
    }
  }
}
```
- **`path`**: points as `[x, z]` or `[x, z, y]`.
  - Without `y`, the point stands on the ground: `MapDefinition.terrain_height(x, z)`, the same
    foot offset the spawner uses today.
  - With `y`, that height is used as given (stair top, bridge crown); the path runs in a straight
    line between neighbouring points.
  - The last path point is the **fork**.
- **`lanes`**: 2–3 end points `[x, z]`. Each enemy walks from the fork to one lane, then switches
  to the normal straight march.
- **`over_water`**: path segments (index ranges) that may cross water, meaning the bridge decks.
  Everywhere else the path must stay on land.
- **`side`**: names the map's existing `spawn_zones` rect on that side. **Every lane must end
  inside that rect**, which is today's proven-clear band. It also maps old level `zone` names to
  gates.
- **`dev_all_open`**: while `true`, every spawn uses every gate (round-robin) and ignores the
  level's choice. Later this is flipped to `false` in this one place.
- **Approach speed is set per gate as a time, never as a global multiplier.** Route lengths run
  from ≈ 17 m (`marina_pier`) to ≈ 53 m (`north_stairs`). A hungry ghost (1.2 m/s) needs a
  multiplier of ≥ 1.77 to cover the north route in 25 s, but ≤ 1.18 to spend at least 12 s on the
  pier route, so no single value works.
  - **`approach_sec`** (per gate): how long the **reference enemy** takes from appearing to
    reaching its lane end. It must lie inside **`approach_sec_range`**. Gates may differ on purpose:
    a short gate is the dangerous one, a long walk gives more warning.
  - **`reference_enemy`**: the unit whose speed defines `approach_sec`. Its speed is read from
    `BalanceDB.num(<id>, "speed", …)`, never copied into this file.
  - **The multiplier is derived, per gate × lane**, at map load:
    `scale = route_length / (approach_sec × reference_speed)`. Each lane is measured separately,
    so every lane of a gate takes the same time.
  - **`approach_scale_range`** clamps it. Below 1.0 an enemy would crawl slower than its own walk;
    above 2.5 it visibly skates. A gate whose target needs a multiplier outside the range is a
    **problem** (see *Checks*): fix the **route length** (move the start point), not the speed.
  - **Every enemy type uses its own speed × the route's multiplier**, so type differences survive:
    on the north route the cat (2.0 m/s) arrives in ≈ 13 s and the pot ghost (0.9 m/s) in ≈ 29 s.
    Only the reference enemy is held to the time window.

### Starting gates for Landmark 81 (one per side)
The coordinates are a **first draft**. Steps 4–5 check each route (clearance sweep, then screenshots) and adjust it.

| Gate | Side (`spawn_zones`) | Route | Why it's worth it |
|:--|:--|:--|:--|
| `north_stairs` | `north_plaza` | Boulevard on the plateau (0, −80, y 4) → down the x = 0 stairs → across the apron → over the **arch bridge** (crown y: measure the deck) → fork at z ≈ −27 → lanes at z −26.5, x −10 / 0 / 10 | The longest and most dramatic approach, straight down the axis from Landmark 81 |
| `canal_bridge` | `east_villas` | Villa street (66, −14) → (57, −10) → over the **canal bridge** (54.5 → 41.5 at z −10, crown y measured) → west at z ≈ −8, passing between the x = 35 lanterns (z −16 / 2.2) and clear of the mossy stone at (35.5, −2.2) → fork → lanes at x 29.5, z −8 / 0 / 8 | Ghosts come out of the villa district over a real bridge |
| `marina_pier` | `river` | Out-end of the **marina pier** (≈ (−3, 46); measure the pier) → between the two dandelion pavilions (x −7.5 and 2.2, z 36.5) → the promenade through the marina deck's gangway gap (railings run along z 32.8; find the opening) → through a gap in the palm row (z ≈ 20.8) → fork → lanes at z 26.5, x −10 / 0 / 10 | Ghosts come up out of the river. This path is where the lantern entrance lands later |
| `west_woods` | `west_groves` | East edge of the Japanese garden gravel (≈ (−58, 2)) → south-east, clear of the gazebo at (−52, −8) (clear radius 4) → east at z ≈ −8, between the x = −35 lanterns and clear of the mossy stone at (−35.5, −2.2) → fork → lanes at x −29.5, z −8 / 0 / 8 | Out of the woods and the garden |

Draft `approach_sec` values (hungry ghost, multiplier in brackets):
- `marina_pier`: 14 s (≈ 1.0, a normal walk)
- `north_stairs`: 22 s (≈ 2.0)
- `canal_bridge` and `west_woods`: 18 s each (computed once the routes are final)

Recheck them after step 5 changes the route lengths.

### Shared code (never names a map)
- **`src/maps/SpawnGates.gd`** (new, `RefCounted`). It parses one `gates.json` at map load:
  - Resamples every path to ~1 m points, with y from the terrain except between explicit-y
    points.
  - **Precomputes each segment's unit direction, length and facing yaw**, so the enemy's
    per-frame step needs no `sqrt`, division or trig (invariant 7).
  - Computes each gate × lane's `scale` from its measured length (see *Approach speed*), once.
  - Queries: `gate_ids()`, `route(gate_id, lane_idx) -> {points, dirs, lengths, yaws, scale}`,
    `lane_count(gate_id)`, `side(gate_id)`, `problems() -> PackedStringArray`.
  - An empty or missing file gives zero gates.
- **`src/maps/MapDefinition.gd`**: new `@export var gates_path: String = ""` (the same pattern as
  `terrain_path`), and a `spawn_gates()` accessor that parses once. `contract_problems()` appends
  `SpawnGates.problems()`.
- **`src/battle/EnemySpawner.gd`**:
  - On `map_loaded`, keep the map's `SpawnGates`.
  - `_expand_def` / `_expand_wave`: when the map has gates, each enemy gets a gate and a random
    lane:
    - With `dev_all_open`: gates are used **round-robin**, starting at a random gate per wave, so
      every gate sees traffic.
    - Otherwise: the group's `"gate"`.
    - The queue entry carries the route. `"at"` (round-test) and maps without gates keep today's
      code paths unchanged.
  - **One 3D spawn point, used by every consumer.** Today three places read the flat
    `_surface_y` and ignore the sampled height:
    - `_show_mound` hardcodes `mound.y = _surface_y - 0.02`
    - `_run_telegraph` rebuilds the rise target from `_surface_y + SURFACE_LIFT`
    - the zone/forest samplers do the same

    On a gate that starts on the 4 m plateau, a raised garden terrace or a pontoon, the warning
    would show on the park floor while the ghost rises somewhere else. Fix:
    - The queue entry carries `surface: Vector3`, the **walking surface** at the spawn spot. For a
      gate it is route point 0, with y from its explicit value or the terrain. For the existing
      paths (`"at"`, zones, forest, fallback points) it is today's flat `_surface_y`, so they don't
      change.
    - `_show_mound(mound, surface)` places the mound (and its `FactionMarker` ring, a child) at
      `surface.y - 0.02`. `_run_telegraph` rises the ghost to `surface.y + SURFACE_LIFT`. **Neither
      reads `_surface_y` any more**; only the helper that builds `surface` for the old paths does.
    - `spawn_buried` still sinks the ghost `BURY_DEPTH` below that point. On a pontoon it rises out
      of the river, on the plateau through the paving; both are acceptable for this phase.
    - Hand the route to the enemy **before** it surfaces, so its first physics tick already follows
      the route.
  - The mound telegraph is reused as-is for now; entrances per enemy type come later.
- **`src/entities/enemies/hungry_ghost/HungryGhost.gd`** (owns all AI; subclasses inherit it):
  - `follow_route(route)` stores the precomputed arrays.
  - While a route is active, `_physics_process` moves the ghost **kinematically**:
    - Advance distance along the current segment by `speed × route.scale × delta`, where `speed`
      is this enemy's own speed.
    - Set `global_position = point + dir × travelled`, and `rotation.y` to the segment's
      precomputed yaw.
    - Play `walk` at `route.scale` playback speed (`_play_clip("walk", route.scale)`), so feet
      don't slide; back to 1.0 at the lane end. Don't call `move_and_slide()`.
    - At the lane end, clear the route and continue with the existing march / seek / eat logic
      unchanged.
  - While on a route: **no plant seeking**. Plants only stand on the lawn, and leaving a bridge
    deck to seek a plant would drop the ghost into the pond. Collision layer 4 stays on, so plants
    in range can still shoot it.
  - `enemy_spawned` still fires on surfacing, as today, so `GameManager.alive_enemies` doesn't
    change.
- **Subclasses:** check that `CastIronPotGhost` (pot helmet pop uses `_lawn_surface_y`) looks
  acceptable if the pot pops while on a bridge deck. It is cosmetic; note it in the Outcome if not
  fixed.

### Level data
- A spawn group may name `"gate": "<gate_id>"`. Migrate the two current levels now, although
  `dev_all_open` makes them ignored for the moment:
  - `data/levels/hcmc/hcmc_01.json`: `"zone": "river"` → `"gate": "marina_pier"`
  - `data/levels/hcmc/hcmc_02.json`: `river` → `marina_pier`, `west_groves` → `west_woods`
- `"zone"` keeps working on maps **without** gates (`test_flat`). On a map **with** gates, a
  `"zone"` group or an unknown `"gate"` is reported by the check below.
- Update the level-format comment at the top of `src/core/LevelDB.gd` (it lists the spawn-group
  fields).

### Checks: fail loudly, never silently
A kinematic ghost clips straight through anything in its way, so a bad route fails **silently**
unless a check catches it. There are two layers, for two kinds of mistake.

**Layer 1: data checks.** Always on and cheap. `SpawnGates.problems()`, run through
`contract_problems()` so `--round-test` fails, reports:
- a sampled path point where `MapZones.is_in_water` is true, outside an `over_water` span
- a lane end outside its gate's `side` rect in `spawn_zones`
- an unknown `side`, a path with fewer than 2 points, a gate with no lanes
- a gate with no `approach_sec`, or one outside `approach_sec_range`
- a gate × lane whose derived multiplier falls outside `approach_scale_range` (the message names
  the route length and the length that would fit)
- a `reference_enemy` unknown to `BalanceDB` or without a `speed`
- any level whose resolved map (`LevelDB.resolve_map`) is the loaded map and that names an unknown
  gate or uses `"zone"`

**Layer 2: clearance sweep against the loaded scene.** Obstacles are map data spread over many
sources: `forest.json`, zone lots, prop nodes, meshes baked into the island (railings, gazebos,
pavilions). **Don't** teach `SpawnGates` those sources, and don't list obstacles in `gates.json`.
Either would be a second copy that drifts. The source of truth is what is actually in the scene, so
check the routes against that. New shared file **`src/maps/RouteClearance.gd`** (it never names a
map), run once after the map is ready:
1. **Collect every obstacle the player can see**, walking the map's tree:
   - each `MeshInstance3D`
   - each instance of each `MultiMeshInstance3D` (trees, lamps, towers, villas, cars), with its
     instance transform
   - Skip anything whose world AABB is shorter than `STEP_CLEARANCE` (grass tufts, petals). That
     rule is generic, not a list of names.
2. **Build temporary collision** on a dedicated physics layer that nothing else uses. Use one
   `create_trimesh_shape()` per distinct mesh, shared by all its instances, so memory stays small.
3. **Sweep the enemy capsule along each gate × lane route**, one sample per ~0.5 m:
   - Capsule size: the **largest** `CollisionShape3D` among the enemy scenes in
     `BalanceDB.enemies()` (hungry ghost today: radius 0.6, height 2.7), so a bigger enemy added
     later is covered automatically.
   - Lift the capsule by `STEP_CLEARANCE` (≈ 0.35 m) above the route's y, so floors, stair nosings
     and bridge decks don't count as hits. Railings, trunks, lamps, benches and walls still do.
   - Canopies above the capsule's head don't count, so walking under a tree is fine.
   - Skip the part of each route inside the lawn's clear band (after the lane end), since that
     ground is already proven clear.
4. **Check the feet with a ray straight down** at each sample:
   - Report where the measured walking surface differs from the route's y by more than 0.15 m.
     This catches a straight segment cutting under a curved bridge arch, a missing stair point,
     or a terrace edge.
   - Report the measured y, so the author knows what value to put in.
5. **Report every hit** with gate, lane, sample (x, z) and the **node path of what was hit**, for
   example `ForestMultiMesh/… instance 214` or `FloatingIslandBase/…/Railings`. Free the
   temporary collision afterwards.

**When it runs:** inside `--round-test`, where it has to stay **under 3 s** (measure it). A later
edit that moves a tree or a lamp onto a route then fails the standard check instead of shipping.
If it can't meet 3 s, it runs in `--gate-test` only, and the `docs/CONTRACTS.md#add-map` verify
line must say to run `--gate-test` after any change to the map's scene or layout data. It never
runs in normal play.

**What stays human:** routes that are clear but look awkward (across a flower bed, hugging a
wall). `--gate-debug` screenshots (step 5) cover those.

### Debug and test flags
- **`--gate-debug`**: draws every path and lane as lines, plus a marker at each fork. It is built
  only when the flag is passed, so it costs nothing otherwise. Combine it with `--screenshot
  --wide-overview` and the `--*-zoom` presets to review routes.
- **`--gate-test`** (add to `SANDBOX_FLAGS` in `src/core/GameFlow.gd`): no plants; spawn one hungry
  ghost on every gate × lane.
  - It **passes** when every ghost reaches the pearl, and when each measured time-to-lane-end is
    within ±1 s of the gate's `approach_sec`.
  - It prints, per gate × lane: route length, multiplier, time-to-lane-end and time-to-pearl.
  - It also prints the computed (not measured) time-to-lane-end for every enemy type.
  - **Telegraph and rise must match:** for each gate, the mound's global position equals the
    surfaced ghost's position minus `SURFACE_LIFT + 0.02` in y, within 0.05 m.
  - It **fails** on the timeout, on any `SpawnGates.problems()` or on any clearance-sweep hit.

## Steps
1. **Data file + parser:** `gates.json` with the four draft gates, `SpawnGates.gd`, the
   `MapDefinition` export, and `gates_path` set in `Landmark81Map.tscn`. Unit-check it: the
   parser prints each gate's resampled length.
2. **Enemy route following** in `HungryGhost.gd`: kinematic segment stepping with precomputed
   values only.
3. **Spawner:** gate/lane choice, round-robin under `dev_all_open`, the single `surface` point used
   by the mound and the rise, handing over the route. `--round-test`, `--ghost-test` and
   `--spawner-demo` behave exactly as before (their mound is still on the flat floor).
4. **Clearance sweep** (`RouteClearance.gd`). Prove it catches things first: temporarily move one
   route point onto a lamp, a railing and a tree trunk, and confirm each is reported with the right
   node path. Then time it inside `--round-test` and decide where it runs (see *When it runs*).
5. **Route review:** fix every sweep hit and feet-height report. Measure the bridge crowns and the
   pier end with `inspect_model.gd` and put the real values in `gates.json`. Then take
   `--gate-debug` screenshots from above and from each side for the awkward-but-clear cases.
6. **`--gate-test`**, then tune each gate's `approach_sec`. If a gate's multiplier would leave
   `approach_scale_range`, lengthen or shorten its route instead of widening the range.
7. **Level migration** (`zone` → `gate`) and the level checks.
8. **Playtest `hcmc_01` and `hcmc_02`** with all gates open. Report whether wave pacing still
   feels right (4 ghosts now come from 4 sides).
9. **Landing** (AGENTS.md Rule 0):
   - `npm run doc-lint`, `-- --round-test`, `-- --perf-test` and `-- --gate-test` all pass.
   - `docs/CONTRACTS.md`:
     - #add-wave: a row for gates, its `CONTRACT(add-wave)` comment next to the gate choice.
     - #add-map: an optional row for `gates.json` + `gates_path`.
     - #add-level: the `"gate"` field.
   - One router cell in `AGENTS.md`: the *Waves* row's gotcha gets `gates: data/maps/<map_id>/gates.json`
     (stay under the word budget).
   - Header comments of `EnemySpawner.gd` (it says enemies burrow from the forest belt) and
     `HungryGhost.gd`.
   - This plan: `Status: done` + Outcome.
   - Write `commit.txt`. **Don't commit.**

## Later phases (designed, NOT part of this plan)
Recorded so the design isn't lost. Each becomes its own plan when `dev_all_open` is turned off.
1. **Gate choice per wave.** Set `dev_all_open: false`; levels choose gates per spawn group
   (supported by step 6). The level rule, checked at load:
   - a level uses **at least 2 sides** across its waves
   - its last huge wave uses **at least 3**
   - Exception: level 1's first wave may use one gate to introduce the mechanic.

   The point: a player who knows only one side is attacked would put every plant there, so the
   difficulty has to come from not knowing which side is next.
2. **Reveal between waves.** The next wave's gates glow a few seconds before it starts: enough to
   add a plant or two, not to rebuild the defence. A second gate can also open mid-wave with a
   short warning.
3. **River lanterns.** During Ghost Month people float lotus lanterns on the river for lost souls.
   Hungry ghosts drift in on those lanterns along a river path and step onto `marina_pier`'s
   route. The lantern floating in is the telegraph.
4. **Each enemy type enters its own way.** The corpse demon cat leaps from the east villa
   rooftops; the pot ghost uses the bridges only; the dirt mound stays only for corpse-type
   enemies.
5. **Off-screen warning:** an edge-of-screen marker for enemies approaching from gates outside
   the camera view.

## Risks to check, not assume
- **Pacing.** With every gate open, `hcmc_01` sends its 4 ghosts from 4 sides. That is harder
  than today. It's accepted for this phase, but report it from step 8.
- **Kinematic enemies and projectiles.** Setting `global_position` directly while on a route must
  not break projectile hits or the health bar. `--gate-test` with one lotus placed near a lane end
  should show hits landing.
- **Shovel/debug spawns.** `EnemyDebugSpawner` (G key) and `remove_by_shovel()` must work on a
  ghost that is mid-route.
- **Map switching.** `--map-switch-test` must pass: gates are parsed per map load and dropped on
  switch.

## Not doing
- No pathfinding or navmesh, and no raycasts on the spawn or walk path.
- No new models or gate visuals (arches, glows). The telegraph stays the existing mound + ring.
- No changes to plant targeting, the lawn, camera bounds or the wave/level progression logic.
