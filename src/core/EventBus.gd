extends Node

# Global EventBus for zero-coupling inter-system communication.
# Any system can emit or listen to these signals without direct node references.

# Economy & Stats Signals
signal sun_amount_changed(new_amount: int)
signal house_health_changed(current_health: int, max_health: int)

# Grid & Building Signals
# CONTRACT(player-signals): `player_id` is 0 for the host (or solo player) and
# 1 for the guest; online, both devices run the same code and each routes its
# local input through GameManager.local_player_id(). GDScript signals cannot
# declare defaults, so every emit and every connect passes it explicitly.
signal tile_hovered(grid_coord: Vector2i, world_position: Vector3, is_plantable: bool, player_id: int)
signal plant_selected_for_placement(plant_type: String, player_id: int)
signal plant_placed(plant_type: String, grid_coord: Vector2i, player_id: int)
signal plant_died(grid_coord: Vector2i)
signal plant_removed(grid_coord: Vector2i)
signal placement_cancelled(player_id: int)
signal placement_rotate_pressed(direction: int, player_id: int) # -1 counter-clockwise, +1 clockwise
## A player's placement ghost changed tile, facing step (0-7), validity or seed;
## an empty plant_type means it is hidden. Fires only on change, never per frame.
## NetBridge relays the local player's to the partner device.
signal placement_preview_changed(plant_type: String, grid_coord: Vector2i, rot_step: int, is_plantable: bool, player_id: int)

# Shovel (removal tool) Signals
signal seed_cooldown_started(plant_type: String)
signal seed_cooldown_finished(plant_type: String)
signal shovel_mode_changed(is_active: bool, player_id: int)

# LAN Co-op Signals (NetBridge -> HUD, lobby feedback)
signal lan_guest_changed(joined: bool) # a guest entered or left the host's room
signal lan_link_lost(reason: String) # the guest lost the host

# Touch Input Signals (TouchInput -> camera / HUD / battle panel)
signal touch_pinch(factor: float) # >1 fingers spread (zoom in), <1 pinch (zoom out)
signal touch_drag(delta: Vector2) # two-finger drag, viewport pixels
signal pause_requested() # on-screen pause button and the Esc key path

# Time-of-Day Signals (GameManager -> DayNightCycle)
signal time_of_day_changed(id: String) # a LightingPreset id (assets/lighting/<id>.tres)
signal day_blend_changed(blend: float) # DayNightCycle, only while a transition runs: eased 0 night .. 1 day

# Wave & Combat Signals
signal wave_started(wave_index: int)
signal wave_completed(wave_index: int)
signal enemy_spawned(enemy: Node3D)
signal enemy_defeated(enemy: Node3D)

# LAN replication hooks: NetBridge listens on the host and mirrors these to the
# guest. Solo play emits them too, and nothing pays attention.
signal plant_health_changed(grid_coord: Vector2i, health: int, max_health: int)
signal gem_spawned(gem: Node3D)
signal gem_collected(gem: Node3D)
signal projectile_fired(projectile: Node3D) # after the shot is configured and in the tree

# Round Flow Signals (GameManager -> EnemySpawner / HUD)
signal round_state_changed(state: String) # menu / prepare / setup / wave / won / lost / sandbox
signal setup_tick(seconds_left: int) # 1 Hz countdown during setup
signal round_wave_go() # setup done: spawner must request the round wave
signal briefing_closed() # confirm transition finished, before setup starts

# Level Flow Signals (GameManager <-> EnemySpawner / HUD / selectors)
signal level_selected(world_id: String, level_id: String)
signal level_flags_defined(fractions: Array)
signal level_progress_changed(killed: int, total: int, progress: float)
signal huge_wave_incoming(wave_idx: int)
signal level_completed(world_id: String, level_id: String)
signal progress_changed() # Progress: a level was newly completed; unlocks re-derive

# Battlefield map (DioramaWorld shell -> PlacementManager / EnemySpawner / camera)
signal map_loaded(map: MapDefinition) # map instanced + pearl placed; configure from its fields

# Seed Selection Signals (pre-round loadout: SeedSelector -> SeedBank)
signal seed_loadout_changed(selected_ids: Array)
signal seed_selector_toggled(is_open: bool)

# Debug Enemy Selection Signals (EnemySelector -> EnemyDebugSpawner, testing only)
signal debug_enemy_changed(enemy_id: String)
signal enemy_selector_toggled(is_open: bool)


# Atlas menu -> GameFlow: the level card's Play button
signal level_play_requested(level_id: String)
# GameFlow -> the scene being left: a transition started ("battle" | "menu")
signal flow_transition_started(kind: String)
