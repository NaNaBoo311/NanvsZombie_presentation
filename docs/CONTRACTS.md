# Contracts

Registration steps for adding a *kind of thing*. Read the relevant section **before** you start —
these are the files a change must touch **together**, and several fail silently if skipped.

⚠ = **fails silently**: no error, no crash, no log line. The feature just does not appear or
quietly does the wrong thing.

Each `##` slug matches a `CONTRACT(<slug>)` comment at the corresponding site in the code, so the
two can be grepped as one unit: `grep -rn "CONTRACT(add-plant)" src/`.

---

## add-plant

**Touches 3 places.** Every plant list in the game (seed bank, TAB picker, placement, costs,
range preview, level checks) is read from the plant's unit JSON through `src/core/BalanceDB.gd`.

**Before you start:** `ls data/units/plants/` — the id must be unused.

| # | File | Anchor | Do | If skipped |
|:--|:--|:--|:--|:--|
| 1 | `tools/asset_generator/generators/plants/<id>.mjs` | new file | export `MODELS = [{ file: 'plants/<id>.glb', build }]`; `build()` returns an `Object3D` or `{root, animations}`. `generate_models.mjs` finds it on its own. Then `npm run generate -- plants/<id>` + the headless reimport | no model; ⚠ without the reimport Godot serves stale meshes from `.godot/imported/` |
| 2 | `src/entities/plants/<id>/<Name>.gd` + `.tscn` | new | `extends PlantBase`; layer 3; set `unit_id = "<id>"` in `_init()`; copy `lotus_shooter/`. `PlantBase` owns targeting + facing | no plant |
| 3 | `data/units/plants/<id>.json` | new | `id`, `name`, `category: "plant"`, `cost`, `model`, `clips` (see #clip-names), `scene`, `numbers`; `"seed": {order, group, icon, cooldown, preview_scale, ghost_scale, default_loadout, unlock?}` makes it plantable (`unlock`: omit = owned from the start, `{"after": level id}` = awakened by that win, `{"jade": N}` = bought in the Seed Shrine; rules in `src/core/Progress.gd`) (`group`: `shooter` / `defender` / `support`, its TAB-picker section, `SeedSelector.GROUPS`); optional `"range_indicator"` (`cone` / `rings`, naming `numbers` keys). The viewer edits it | no `seed` block: not in the bank or TAB picker, and levels listing it error at boot |
| 4 | `src/entities/plants/<id>/<Name>.gd` | its acting loop | gate on `is_stunned()` (see #plant-stun) | ⚠ the plant ignores stuns |

A seed whose scene (or projectile scene) is missing is "coming soon": it shows a ribbon and cannot be packed or default-loaded (`BalanceDB.is_playable`), so no extra step is needed when its files land.

Ground traps (see `bougainvillea_net/`) set `uneatable = true` in `_init()`: `PlantBase.find_nearest_in_cone` then skips them, so ghosts walk over instead of biting.

**Verify:** `-- --round-test` (checks every unit's scene loads, its `unit_id` matches the JSON and
its model exists) → launch with `-- --screenshot --preview-test`: TAB lists the seed → its card
fits → the hover ghost is the right model at the right scale → left-click spawns the plant and
debits the cost.

---

## plant-stun

**Touches every plant with its own acting loop.** `PlantBase.stun(duration)` only stores an
expiry timestamp; nothing stops a plant unless its own loop asks `is_stunned()`. (CONTRACT(plant-stun))

| # | File | Anchor | Do | If skipped |
|:--|:--|:--|:--|:--|
| 1 | `src/entities/plants/<id>/<Name>.gd` | `_physics_process` / `_process` (targeting, firing, detonation, production countdown) | `if is_stunned(): return` before acting; also gate deferred shots (`_spawn_at_apex`) and contact triggers (bite detonation) | ⚠ the plant keeps acting under a Tourist Zombie flash |

Passive walls need nothing. Copy the gates in `lotus_shooter/` (turret) or `sacred_rice/` (producer).

**Verify:** spawn `tourist_zombie` facing the plant → after the flash the plant wobbles and does not act for `stun_duration`.

---

## add-projectile

**Touches 3 places** (+ an optional preview model). A shot's flight numbers live in `data/projectiles/`, read through
`src/core/BalanceDB.gd`; the plant's unit JSON only names it.

**Before you start:** `ls data/projectiles/` — the id must be unused.

| # | File | Anchor | Do | If skipped |
|:--|:--|:--|:--|:--|
| 1 | `data/projectiles/<id>.json` | new | `id`, `scene`, `numbers` (`speed`, `spin_speed`, `max_distance`) | scene never loads; flight uses script defaults |
| 2 | `src/entities/projectiles/<id>/<Name>.tscn` | new | root `Area3D` with `Projectile.gd`, `projectile_id = "<id>"`, children `Visuals` + `TrailParticles`; layer 5, mask 4 | no shot, or default speed |
| 3 | `data/units/plants/<plant>.json` | `"projectile"` | the id; damage stays in that JSON's `numbers` | the plant fires nothing |

Optional preview model: `tools/asset_generator/generators/projectiles/<id>.mjs` exporting
`MODELS = [{ file: 'projectiles/<id>.glb', build }]` (see #add-model), named by `"model"` in the JSON.

**Verify:** `-- --round-test` (checks every named projectile's scene loads).

---

## add-enemy

**Touches 3 places.** The spawner, the debug picker (`H`), the cursor ghost and `G`-spawn all read
the enemy's unit JSON through `src/core/BalanceDB.gd`.

| # | File | Anchor | Do | If skipped |
|:--|:--|:--|:--|:--|
| 1 | `tools/asset_generator/generators/enemies/<id>.mjs` | new file | export `MODELS = [{ file: 'enemies/<id>.glb', build }]` (found automatically), then `npm run generate -- enemies/<id>` + the headless reimport | ⚠ stale or missing model |
| 2 | `src/entities/enemies/<id>/<Name>.gd` + `.tscn` | new | `extends HungryGhost` — it owns the whole AI; set `unit_id = "<id>"` in `_init()` | no enemy |
| 3 | `data/units/enemies/<id>.json` | new | `id`, `name`, `category: "enemy"`, `model`, `clips` (see #clip-names), `scene`, `numbers`, optional `"debug": {order, preview_scale}`. The viewer edits it | no `scene`: not spawnable, and levels naming it error at boot |

**Before adding:** `ls assets/models/enemies/` — some models already exist with no scene yet.

**Verify:** `-- --round-test` passes → `H` lists the enemy → click arms it → `G` + left-click
spawns it → it walks toward the pearl and is blocked at the dais.

---

## add-wave

**Burrow-rise spawns must set the flag BEFORE `add_child`, or the ghost counts twice.**
`HungryGhost._ready()` takes the buried path only when `is_rising` is already true;
setting it afterwards plays the pop-in, emits `enemy_spawned` immediately, and emits
again on surfacing — `GameManager.alive_enemies` drifts with no error. (CONTRACT(add-wave))
Nav routes (`NavGrid`) walk at each enemy's own speed (scale 1.0); `--nav-test` expects rise + length / speed.
Plants skip both `is_rising` and `is_airborne` (gliders until touchdown); every
`is_rising` filter must check both flags or gliders take plant fire mid-air.

| # | File | Anchor | Do | If skipped |
|:-|:--|:--|:--|:--|
| 1 | caller (e.g. `src/battle/EnemySpawner.gd`) | before `add_child` | set `enemy.is_rising = true` on the instance | double `enemy_spawned`, plants shoot the rising/gliding ghost |
| 2 | same caller | after `add_child` | call `enemy.spawn_buried(surface_pos)` | ghost never rises; AI runs from the buried position |
| 3 | `src/battle/EnemySpawner.gd` | `WAVE_DEFS` / `_expand_wave` | reference only enemy ids with a `scene` in `data/units/enemies/` | group warns and is skipped at runtime |
| 4 | `data/maps/<map_id>/nav.json` | the group's `"zone"` | on a map with a nav grid the zone must be a key of that file's `regions` (`north` / `east` / `west` / `south` on Landmark 81); leave it off and the regions round-robin, so a wave comes from every side. The retired `"gate"` field is an error. Spawn cells come from the baked grid, so a region rect over water or obstacles still works as long as some cell of it connects to the lawn | `NavGrid.problems()` reports an unknown zone, a leftover `"gate"`, a region with no lawn-connected cell or no route, and `-- --round-test` fails; a group with an `"at"` pair keeps its fixed spot and never reads a region |
| 5 | `src/maps/RouteClearance.gd` | `--round-test` | after any edit that can put something in a route's way (a tree point in `forest.json`, a prop's transform, a new railing) re-run `-- --map <map_id> --nav-bake`, then `-- --round-test`; it sweeps a sample of every region's routes (`NavGrid.sample_routes`) against the loaded scene and names what is in the way | a ghost is kinematic on a route and would clip through the blocker with no error; the stale-grid check (`NavGrid.inputs_hash`) only covers the files listed in `nav.json` `hash_inputs` |
| 6 | an enemy that spawns offspring mid-wave (e.g. `BasketBoatZombie._release_crabs`) | before `add_child`, before the parent emits `enemy_defeated` | `set_meta("wave_split", true)` (and `"no_kill_credit"` when the offspring is not in the level total) | the wave ends while offspring live; extra kills push the progress bar to 100% early |

**Verify:** `-- --spawner-demo` shows a mound → the ghost rises → plants ignore it until
surfaced → it marches and `wave_completed` fires after the last kill.

---

## add-level

**Touches 1–2 data files, 0 code changes. The selectors and Progress read LevelDB only.**

| # | File | Anchor | Do | If skipped |
|:-|:--|:--|:--|:--|
| 1 | `data/levels/<world_id>/<id>.json` | new | `"id"` matches the filename; no `world_id` (LevelDB fills it in); optional `map` / `lawn` / `time_of_day` (a preset file name in `assets/lighting/`; an unknown id warns at boot and keeps the current look) / group `zone` (a key of that map's `nav.json` `regions`; omit it and the regions round-robin); `seed_pool` ([plant id], if skipped every seed) / `seed_forced` ([plant id] in the pool, if skipped none) / `seed_slots` (int 1..`SeedBank.TOTAL_SLOTS`, if skipped the full bank) / `peaceful` (true: no waves spawn and the level never ends, for a map whose enemies do not exist yet; `waves` empty, or they warn and never spawn) / `story` (`{intro?, outro?, huge_wave?}`, arrays of strings: the Warden's Chronicle) / `waves[].spawns[].enemy_id` name units in `data/units/` | LevelDB errors at boot; the seed is dropped / the enemy's groups are skipped and the progress total comes up short |
| 2 | `data/worlds/<world_id>.json` | the world's `levels` | add the id at its play position; a new world is one new file `{id, province, name, map, unlock, levels, path, order, icon, model}` with `id` matching the filename, `unlock` `"start"` / `{"after": [level ids]}` / `{"stars": N}`, `province` an id in `vietnam_provinces.json`, `path` the level-path control points (author them with the atlas menu's `--path-edit`), then `npm run generate -- environment/vietnam_world_atlas` + the headless reimport | level dropped with a warning (unlisted) or error (listed, no file); a bad `province` fails the atlas generator; a bad `unlock` keeps the world locked; an unknown `zone` is reported by `NavGrid.problems()` and the wave round-robins every region; no `path`: levels sit on a fallback line (warning); ⚠ no regenerate: the atlas still bakes the province as a plain pastel piece |

**Verify:** no `[LevelDB]` warnings at boot → the atlas (`src/menus/atlas/AtlasMenu.tscn`) shows the province raised, with its level count on hover → click it: the level's node on the path, its card shows `N waves • M🚩` → Play runs setup (`--flow-test` drives this) → bar fills killed/total with flags at huge-wave ends → final kill emits `level_completed` → the next level in the list unlocks (`--progress-test` covers the rules).

---

## lan-coop

**Touches 5 places.** Two devices on one network: one host, one guest, no relay and no internet.
The host owns the simulation — sun, waves, plants, enemies, gems and progress — and the guest
renders replicated state and sends intents. Everything that crosses the wire is registered here.

| # | File | Anchor | Do | If skipped |
|:--|:--|:--|:--|:--|
| 1 | `src/net/Net.gd` | autoload | **every** `@rpc` lives on this one autoload so the node path is the same on both peers across scene changes; new messages go through `send_event()` / `send_command()` / `send_snapshot()` | ⚠ `rpc_id` is dropped with no error when the path differs |
| 2 | `src/net/NetBridge.gd` | `_ready` (host/guest branches) | new replicated state: an `EventBus` listener on the host, an event kind in `_on_event` on the guest, and a row in `send_snapshot()` if it moves | ⚠ the guest shows stale or missing state |
| 3 | `src/net/NetBridge.gd` | `_on_command` | a guest intent must be re-validated and applied on the host (`place`, `dig_*`, `collect`) | ⚠ a guest can mint sun, plants and kills |
| 4 | the entity script | `is_remote` | remote copies skip AI, collision, damage and rewards | ⚠ the guest simulates too: double damage, ghost plants, host-only progress leaks |
| 5 | `project.godot` + iOS `Info.plist` | version, `NSLocalNetworkUsageDescription` | both devices run the same build; iOS needs the local-network key for UDP discovery | ⚠ iOS blocks discovery silently and no host ever appears |

Rules:
- LAN only, `MAX_PLAYERS = 2` (host + one guest). Internet co-op is out of scope.
- No mid-game join and no reconnect: `Net.begin_session()` closes the room; the guest joins from
  the atlas and the host picks the level.
- Pause is a local overlay (`GameManager.is_local_menu_open`), never `get_tree().paused`.
- Progress is host-only: `Progress.mark_completed()` is guarded by `is_client()`.
- If the guest drops, `Net.link_lost` returns it to the atlas; the host keeps playing solo.

**Verify:** `-- --lan-flow-test host` and `-- --lan-flow-test client` in two processes (join, level
sync, guest placement, enemy replication, atlas return) → `-- --net-test host|client` for the bare
transport → `-- --perf-test` unchanged.

---

## player-signals

**Every selection/tool signal carries a trailing `player_id`.** LAN co-op gives each device one
placement owner: `0` is the host (or the solo player), `1` is the guest. GDScript signals cannot
declare default parameter values, so the id is required at the emit **and** at every `connect()`
handler — a missed argument is a runtime error, and a handler that ignores it silently cancels the
other player's seed or tool.

Sun, house health, seed loadout, grid occupancy and the lawn overlay stay **shared**. Only the
cursor, chosen seed and equipped tool are per player; the guest's are mirrored as `p2_*` state in
`GameManager` on its own device.

| # | File | Anchor | Do | If skipped |
|:--|:--|:--|:--|:--|
| 1 | `src/core/EventBus.gd` | signals with `player_id` | keep it last; update every emit | `Invalid call ... expected N arguments` when the signal fires |
| 2 | `src/core/GameManager.gd` | `select_plant` / `clear_selection` / `select_shovel` / `cancel_shovel` | pass `local_player_id()` through to the emit | ⚠ the guest's pick clears the host's; the wrong shovel toggles |
| 3 | handler | `PlacementManager`, `SeedBank`, `ShovelManager`, `ThirdPersonCamera` | take `player_id` and branch on it | ⚠ the host's highlight/placement is cancelled by the guest's action |
| 4 | `src/battle/PlacementManager.gd` | `_execute_placement` | re-check tile occupancy and affordability at commit, not the cached hover; on the guest, send a command instead of spending | ⚠ two cursors place two plants on one tile and debit twice |
| 5 | `src/battle/PlacementManager.gd` | `plants_by_coord` / `plant_at()` | the tile is the identity on both peers; replicated plants go through `spawn_plant()` | ⚠ remote HP/death cannot find the plant |

**Verify:** `-- --lan-flow-test` (host join, shared sun, guest placement replicated) →
`-- --perf-test` still matches the solo baseline.

---

## touch-input

**Touches 4 places.** Touch is not a second input scheme: it reuses the emulated mouse
(input_devices/pointing/emulate_mouse_from_touch) for every tap, drag and button, and adds
only what a mouse cannot express. A new touch action is therefore one new signal, its emit in
`TouchInput`, and the screen that listens — not a new input layer.

| # | File | Anchor | Do | If skipped |
|:--|:--|:--|:--|:--|
| 1 | `src/core/EventBus.gd` | touch signals | `touch_pinch(factor)` / `touch_drag(delta)`, or a new gesture signal | — |
| 2 | `src/ui/TouchInput.gd` | `_on_drag` | emit it from the two-finger path and nowhere else | ⚠ single-finger taps stop reaching `Control`s |
| 3 | the screen's script | `_setup_touch` / `_setup_touch_ui` | `connect` it only when `GameManager.is_touch_ui()` | ⚠ desktop pays for the node and the callbacks |
| 4 | `PlacementManager` / `ShovelManager` | `_unhandled_input` | commit on **release**, and refuse when `GameManager.touch_gesture_multi` | ⚠ a pinch plants or digs |

A button that replaces a keyboard key goes in `src/ui/TouchControls.gd`, which `HUD` only
instantiates on touch and never under `--perf-test`. Size it from `BUTTON_SIZE`: at the 1.3 canvas
scale that is ~45 pt on a phone, the smallest tap target worth shipping.

**Verify:** `-- --touch-test` (press aims and spends nothing, lift plants once, two fingers never
plant, pinch zooms, drag orbits, rotate turns the ghost) → `-- --perf-test` unchanged →
`-- --touch --screenshot --preview-test` and read the capture.

---

## mobile-export

**Touches 4 places.** A mobile build is the same project with a different renderer and a bigger
canvas scale; nothing in the gameplay code may branch on the platform.

| # | File | Anchor | Do | If skipped |
|:--|:--|:--|:--|:--|
| 1 | `project.godot` | `[rendering]` | `rendering_method.mobile="mobile"`, `*.mobile` shadow atlases, import_etc2_astc=true | ⚠ Vulkan mobile has no compressed textures to sample |
| 2 | `project.godot` | `[display]` | window/handheld/orientation=4 (sensor landscape) | the app rotates to portrait |
| 3 | `src/core/GameManager.gd` | `is_touch_ui` / `_apply_fixed_quality` | one `content_scale_factor` for every touch screen; `--touch` forces the path on desktop | ⚠ untestable without a device |
| 4 | `export_presets.cfg` | both presets | package/unique_name, application/bundle_identifier, version, shader_baker/enabled | the export refuses, or ships as `com.example.*` |

Shaders must compile in **both** renderers (TRAPS.md#mobile-renderer-screen-buffers), and every
edge-anchored HUD control must go through `src/ui/SafeArea.gd` or the notch eats it.

**Verify:** `-- --touch-test`, then `--rendering-method mobile -- --screenshot --preview-test` for
shader parity, then a device run of the checklist in `docs/mobile-qa.md`.

---

## clip-names

**Each unit declares its own clips.** A unit's `data/units/plants|enemies/<id>.json` lists
`"clips"`: every animation clip its model provides by agreement between the modeler and
whoever writes the unit's code, and the only names that code may play. Any lowercase
snake_case name is fine (`run`, `attack_1`, `attack_2`); agree the list before modeling.
Three checks enforce it:
- `npm run generate -- <category>/<id>` refuses to write the `.glb` when a clip name is not
  lowercase snake_case, when a declared clip is missing, or when the unit has no list. An
  extra, undeclared clip only warns.
- `--round-test` fails when a unit's `.glb` lacks a declared clip.
- It also fails when code asked for a clip the model lacks. `_play_clip()` helpers report
  through `BalanceDB.report_missing_clip()`, which also logs in normal play.

**Adding or renaming a clip must land in all 6 places together.** The checks above catch
misses in rows 1–3. Rows 4–6 still fail silently.

| # | File | Anchor | Do |
|:--|:--|:--|:--|
| 1 | `data/units/plants|enemies/<id>.json` | `"clips"` | add or rename the name in the list first |
| 2 | `tools/asset_generator/generators/**/<id>.mjs` | `new THREE.AnimationClip('<name>'` | rename the clip, then `npm run generate -- <category>/<id>` + headless reimport |
| 3 | `src/entities/**/<Name>.gd` | `_play_clip("` | rename every played name; check `has_animation(` lists too (e.g. pot-helmet strip list) |
| 4 | `data/units/plants|enemies/<id>.json` | `abilities[].clip`, `clipAnnotations` keys | rename refs; `numbers.*` keys (e.g. `eat_range`) are stats, not clips — leave them |
| 5 | `tools/model_viewer/public/viewer.js` + `grid.js` | label map, `ONE_SHOT_CLIPS`, one-shot rule | `die`/`low_hp*` play once; `attack`/`walk`/`idle` loop |
| 6 | `src/battle/EnemyAiTest.gd` | spider-test clip assertion, `siege_anim ==` | rename the asserted names or the test fails the run |

**Verify:** `npm run generate -- <category>/<id>` writes the model with no clip error →
`-- --round-test` passes → spider test passes its clip assertion → ghost test sieges with
`clip=attack` in the log → viewer grid animates the renamed model with the new clip names.

---

## mesh-names

**Island base mesh names and material colors are looked up at runtime.** The names are
set in `addMerged(..., '<Name>')` in
`tools/asset_generator/generators/maps/landmark_81/floating_diorama_island.mjs`. Renaming a
mesh or recoloring its material there fails silently ⚠ at every site below. Each site
logs a warning at most, and most don't. Rows 1–11 live in the Landmark 81 map scripts:
`Landmark81Map.gd` and the helpers it owns, `Landmark81Water.gd` and `Landmark81DayGrade.gd`.
Rows 12–14 are Hoan Kiem's, whose names are set in
`tools/asset_generator/generators/maps/hoan_kiem/hoan_kiem_island.mjs`. Row 15 is Hoi An's, whose
names are set in `tools/asset_generator/generators/maps/hoi_an/hoi_an_island.mjs` and
`tools/asset_generator/generators/architecture/lantern_kit.mjs`.
Shared environment kit (stones, the world atlas) still lives in
`tools/asset_generator/generators/environment/`.

| # | File | Anchor | Depends on | If broken |
|:--|:--|:--|:--|:--|
| 1 | `src/maps/landmark_81/Landmark81Map.gd` | `COLLISION_SKIP` | lowercase substrings of mesh names (`water`, `soil`, `stripe`, …) | ⚠ a decorative mesh gains trimesh collision, or a walkable one loses it; placement raycasts hit the wrong surface |
| 2 | `src/maps/landmark_81/Landmark81Water.gd` | `RIVER_MESH_NAME` | the exact river mesh name | river keeps the flat fallback material and the day grade tweens a dead duplicate (a warning is logged) |
| 3 | `src/maps/landmark_81/Landmark81DayGrade.gd` | `LAWN_NIGHT_ALBEDO` / `RINGS_NIGHT_ALBEDO` | `lawnTropical` color `0x2e7d32` / `lawnStripe` color `0x43a047` | the daylight lawn recolor / night ring grade is a no-op (a warning is logged; `--round-test` asserts both) |
| 4 | `src/maps/landmark_81/Landmark81Water.gd` | `setup_river_material()` bank points | the west-bend centre, radius and angles in `tools/asset_generator/generators/maps/landmark_81/west_bend.mjs` | ⚠ bend foam detaches from the bank (hidden or floating in open water) |
| 5 | `src/maps/landmark_81/Landmark81Water.gd` | `setup_river_material()` straight bank z = 34.38 and the step at `data/maps/landmark_81/zones/south_bank.json` | the sea-wall revetment boxes in `floating_diorama_island.mjs` (the central span is `shift` m further south than the east one) | ⚠ sea-wall foam hidden under the wall or floating off it |
| 5b | `data/maps/landmark_81/zones/south_bank.json` | `x`, `shift` | `Landmark81Zones.is_in_water` / `south_bank_shift()`, `floating_diorama_island.mjs`, `park_topography.mjs`, the scene nodes at z ≥ 42 in `Landmark81Map.tscn` (lantern, dandelions, yachts, pier) and the central-bank z values in `forest.json` (authored already shifted) | ⚠ trees, lamps or props float in the river or sink into the new parkland; nav spawn cells land in water |
| 6 | `src/maps/landmark_81/Landmark81Water.gd` | `POND_MESH_NAME` + `SPRAY_MESH_NAME` | the `LagoonReflectingWater` / `FountainSprays` merge names in `floating_diorama_island.mjs` | ponds/sprays keep the flat fallback material (a warning is logged) |
| 7 | `src/maps/landmark_81/Landmark81Zones.gd` | `crescent_fountains()` / `is_in_water()` | `data/maps/landmark_81/zones/lagoon.json` (lobes, neck, curbs, fountains), also read by `floating_diorama_island.mjs` and `park_topography.mjs` | ⚠ editing the json without `npm run generate` + reimport leaves the baked water and pedestals on the old shape while trees, grass and `is_in_water` use the new one |
| 8 | `src/maps/landmark_81/Landmark81Zones.gd` | `lake3_center()` / `LAKE3_FOUNTAIN_R` | `data/maps/landmark_81/zones/lake3.json` `center` and the fountain `r` in `tools/asset_generator/generators/maps/landmark_81/lake_three.mjs` | ⚠ the Lake 3 ring sits off-centre or mis-sized |
| 9 | `src/maps/landmark_81/Landmark81Map.gd` | `SKYLINE_ROOT` / `LANDMARK_TOWER` | those node names in `src/maps/landmark_81/Landmark81Map.tscn` and emissive materials in the tower `.glb`s | skyline windows keep their baked night glow by day (`--round-test` asserts) |
| 10 | `src/maps/landmark_81/Landmark81Water.gd` | `setup_river_reflections()` reflector lookups | the lantern `OmniLight3D`s under `Lanterns` / `DandelionPavilions` (`LANTERN_ROOTS` in `Landmark81Map.gd`), `data/maps/landmark_81/zones/promenade_lamps.json` (via `Landmark81Zones.promenade_lamp_positions()`), the `LANDMARK_TOWER` node, the `NightSky` group + `moon_global_position()` | ⚠ the dropped source's streak silently never appears; `--round-test` fails below tower + moon + one lamp, or when the moon is missing |
| 11 | `src/maps/landmark_81/Landmark81Map.gd` | `OUTSKIRTS_ROOT` / `OUTSKIRTS_MESH_NAME` | the `OutskirtsBand` node in `Landmark81Map.tscn`, its mesh name in `tools/asset_generator/generators/maps/landmark_81/outskirts_band.mjs`, and `ProceduralSkyMaterial` in the active world environment (looked up by `src/environment/SilhouetteBand.gd`) | ⚠ outskirts band keeps unlit default material or fails to sync sky horizon gradient; `--round-test` asserts |
| 12 | `src/maps/hoan_kiem/HoanKiemMap.gd` | `COLLISION_SKIP` / `LAWN_MESH_NAME` / `WATER_MESH_NAME` | lowercase substrings of the island mesh names; the `CentralLawn` / `LakeWater` merge names | ⚠ a skip miss gives a decorative mesh collision; a renamed lawn or water mesh fails `--round-test` (no lawn collision / flat water) |
| 13 | `src/maps/hoan_kiem/HoanKiemMap.gd` | `LANDMARK_NODES` | landmark node names in `HoanKiemMap.tscn` and keys in `data/maps/hoan_kiem/zones/landmarks.json` | the landmark keeps its scene transform; `--round-test` names it |
| 14 | `src/maps/hoan_kiem/HoanKiemMap.gd` | `OUTSKIRTS_ROOT` / `OUTSKIRTS_MESH_NAME` | the `OutskirtsBand` node in `HoanKiemMap.tscn`, its mesh name in `tools/asset_generator/generators/maps/hoan_kiem/outskirts_band.mjs`, and `ProceduralSkyMaterial` in the active world environment (looked up by `src/environment/SilhouetteBand.gd`) | ⚠ the band keeps the unlit default material or stops fading into the sky; `--round-test` asserts |
| 15 | `src/maps/hoi_an/HoiAnMap.gd` | `COLLISION_SKIP` / `LAWN_MESH_NAME` / `WATER_MESH_NAME` / `LANTERN_MESH_TAG` / `OUTSKIRTS_ROOT` | lowercase substrings of the island mesh names; the `CentralLawn` / `RiverWater` merge names; the `LanternGlow` material name in `lantern_kit.mjs` (meshes are named after it); the `OutskirtsBand` node and mesh (`tools/asset_generator/generators/maps/hoi_an/outskirts_band.mjs`) | ⚠ a skip miss gives a decorative mesh collision; a renamed lantern material leaves every lantern a flat white glow; `--round-test` names a missing lawn, river, lantern or band lookup |

**Verify:** after regenerating the island (`npm run generate -- <the map's island model>`, listed by `npm run generate -- --list`) and the headless reimport, run `-- --map <map_id> --round-test`.
`DioramaWorld` runs the map's `contract_problems()` and fails the run if any lookup broke.

---

## lake-shape

**Hoan Kiem's lake and turtle island are one signed distance field, evaluated in three
places that must agree term for term.** The shape is data: `lobes` + `blend` in
`data/maps/hoan_kiem/zones/lake.json` and `arena.json` `island`. The field (`ellipseSd` +
`smin`) is code, written three times.

| # | File | Anchor | Do | If skipped |
|:-|:--|:--|:--|:--|
| 1 | `tools/asset_generator/generators/maps/hoan_kiem/lake_shape.mjs` | `ellipseSd`, `smin` | change the field here first; the island generator cuts water, walls and turf from its level sets | — |
| 2 | `src/maps/hoan_kiem/HoanKiemZones.gd` | `_ellipse_sd`, `_smin` | mirror the change | ⚠ trees, grass and `is_in_water` disagree with the meshes: tufts in the water, trees culled on land |
| 3 | `assets/shaders/PondWater.gdshader` | `ellipse_sd`, `smin` | mirror the change | ⚠ the shore shade band drifts off the stone walls |
| 4 | `tools/asset_generator/generators/maps/hoan_kiem/build_layout.mjs` | run it | after any change to the lake, islands, streets or landmarks, rerun it (it rewrites `data/maps/hoan_kiem/zones/lamps.json` and `data/maps/hoan_kiem/forest.json`), then `npm run generate -- maps/hoan_kiem/island_base` | ⚠ lamps, benches and trees stay where the old shore was: on the water or in the street |

**Verify:** `-- --map hoan_kiem --round-test` passes (it fails if the lawn grid leaves the
turtle island) → `-- --screenshot --skyline-panorama` shows the shore shade hugging the walls.

---

## add-map

**A battlefield map is data + one scene; the battle shell (`src/battle/DioramaWorld.gd`) needs no code change.**

| # | File | Anchor | Do | If skipped |
|:-|:--|:--|:--|:--|
| 1 | `src/maps/<map_id>/<Name>.tscn` | scene root | root script extends `src/maps/MapDefinition.gd`; set `lawn_zones`, `default_lawn`, `ground_y`, `pearl_position`, the `spawn_*` band, optional `spawn_zones` (unused when `nav_path` is set), `camera_bounds`, optional `terrain_path` (a heightfield your terrain generator exports, read by `src/maps/TerrainHeightfield.gd`; empty = flat); walkable meshes need collision on layer 1 | root not a `MapDefinition`: nothing loads (error logged); ⚠ unset fields keep the base defaults (24×24 lawn at the origin, 25–40 m spawn ring), so placement, spawns or camera sit in the wrong place |
| 2 | `data/maps/<map_id>/map.json` | new file | `{id, name, scene}` with `id` matching the folder; `"dev": true` only for test maps (`data/maps/test_flat/map.json`), which no world or level may use | no file: the map does not exist (LevelDB errors on any world or level naming it); id ≠ folder warns |
| 3 | `data/worlds/<world_id>.json` (world `map`) or a level's `map` | id | name the map; `LevelDB.resolve_map()` picks level over world | the world keeps its old map |
| 4 | the map scene (optional) | `zones_path` + batching nodes | to reuse `ForestMultiMesh` / `GrassMultiMesh` / `PropMultiMesh`, write a zone script with the static queries in `src/maps/MapZones.gd` and name it in `zones_path`; give `ForestMultiMesh` a layout JSON in `config_path` (copy `data/maps/landmark_81/forest.json`) and `GrassMultiMesh` its sampling ranges. These scripts never name a map | ⚠ unset `zones_path` falls back to the flat default: no water or blocked ground, so trees and grass stand in lakes and on paths; an empty `config_path` plants no trees |
| 5 | map-owned files | ownership rule | a file lives under `maps/<map_id>/` only if it depicts that map's real place or is fitted to its layout (e.g. `data/maps/landmark_81/zones/`, `assets/models/maps/landmark_81/landmark_81_tower.glb`, `tools/asset_generator/generators/maps/landmark_81/`); everything else is shared kit and stays in its category folder | kit filed under a map (or map-owned files left shared): the next map copies the wrong pattern |
| 6 | the map scene (optional) | `nav_path` | to have enemies spawn in regions and walk A* routes around water and obstacles, point it at `data/maps/<map_id>/nav.json` (`{cell, bounds, regions, bridges, hash_inputs}`, see `src/maps/NavGrid.gd`), then run `-- --map <map_id> --nav-bake` WITH A WINDOW (not `--headless`: TRAPS.md#headless-multimesh) to write `nav_grid.json` and commit both; trees that must leave a way through (a spawn clearing) go in `data/maps/landmark_81/zones/clearings.json` via the map zone script's `on_walkway`; leave it empty and the spawner samples `spawn_zones` / the forest belt exactly as before | ⚠ a nav file with no `nav_path` is never read: every wave spawns on the flat ring, with no warning |
| 7 | `data/maps/<map_id>/perf_baseline.json` | new file | `--perf-test` measures the boot map (the first world's map, or `-- --map <map_id>`) against its own baseline; write it once with `-- --map <map_id> --perf-test --update-baseline` | `--perf-test` fails naming the missing file |
| 8 | `data/maps/<map_id>/nav_grid.json` | generated | written by `-- --map <map_id> --nav-bake` (`NavGrid.bake`): a 1 m walkable bitmap from water, slope and a capsule sweep of the loaded scene, with the hash of `nav.json` and its `hash_inputs` (lagoon, forest, lots, terrain, the scene and the island glb). Bridges are `nav.json` `bridges` decks (`[x, z, y]`, `half_w` ~1.2), forced walkable over water | ⚠ editing a listed input without re-baking: `NavGrid.problems()` reports the stale hash and `-- --round-test` fails; a bridge or obstacle NOT in `hash_inputs` can change with no error until `RouteClearance` hits it |
| 9 | the map scene (optional) | `briefing_camera` | scouting pose for the loadout briefing (`{pos, arm, pitch, yaw, fov?}`, same keys as a `CameraPresets` row); missing falls back to the `--wide-overview` values | ⚠ missing keeps the fallback: the briefing still opens, just from the generic overview |
| 10 | the map scene (optional) | `defend_model` | a `PackedScene` of the building to defend instead of the pearl (Hoan Kiem: Turtle Tower); `DioramaWorld` hands it to `CentralHouse.set_defend_model()` on every map install. It must fit the pearl's 7 × 7 m footprint (`CentralHouse.PEARL_BOUNDS`), which placement and enemies still use | ⚠ a bigger building: plants can be placed inside it and enemies stop at the 7 × 7 box, not its walls; unset: the pearl stands there |

**Verify:** no `[LevelDB]` errors at boot → play a level on the map → lawn grid lights the intended zone → enemies rise in the spawn band → camera pans stop at `camera_bounds` → `-- --map <map_id> --round-test` passes → `-- --round-test` still passes on Landmark 81 → `-- --map-switch-test` passes (switching leaves no leftovers).

---

## add-model

**A generated shared-kit model is one module; `tools/asset_generator/generate_models.mjs` never
changes.** Plant, enemy and map-owned models follow the same rule inside their own contracts.

| # | File | Anchor | Do | If skipped |
|:-|:--|:--|:--|:--|
| 1 | `tools/asset_generator/generators/<category>/<name>.mjs` | new file | export `MODELS = [{ file: '<category>/<name>.glb', build }]`; the folder mirrors `assets/models/<category>/` (e.g. `tools/asset_generator/generators/sky/star_glow.mjs` writes `assets/models/sky/star_glow.glb`); any wrapper (`mergeByMaterial`, `bakeToVertexColors`) goes inside `build`. Shared helpers export no `MODELS` (e.g. `tools/asset_generator/generators/vegetation/foliage_colors.mjs`) | ⚠ no `export const MODELS` in the source text: the module is never imported and no `.glb` is written |
| 2 | — | — | `npm run generate -- <category>/<name>` (one model per run; `npm run generate:all` rebuilds every model) + the headless reimport, then `npm run generate:check` | Godot serves a stale mesh; an unseeded random draw churns the `.glb` on every generate |

**Verify:** `npm run generate -- --list` lists the new model → `git status` shows only the files you meant
to change → `npm run viewer` shows the model.

---

## add-sound

**Touches 3 places.** Every sound is a file, a `SOUNDS` row and a call site in `src/core/Audio.gd`.

| # | File | Anchor | Do | If skipped |
|:--|:--|:--|:--|:--|
| 1 | `assets/audio/` + its `.import` | new file | edit/trim=true and edit/normalize=true (music: `loop=true`), then the headless reimport | input lag, wrong level, or music that stops after one pass |
| 2 | `src/core/Audio.gd` | `SOUNDS` | an id constant and a `SOUNDS` row (music: the world's `"music"` key) | parse error at the call site |
| 3 | caller | event line | `Audio.play(Audio.<ID>)` on the line where the event happens | silence, with no error |

**Verify:** `-- --round-test`.
