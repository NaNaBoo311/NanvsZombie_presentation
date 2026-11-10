# UI Subsystem

Battle HUD, seed selection, loadout briefing, and debug pickers.

## Scope & Key Files

- `src/ui/SeedBank.gd` — active combat seed bar; cost seals, cooldown eclipses and slot selection for the one local player (`GameManager.local_player_id()`).
- `src/ui/SeedSelector.gd` — TAB overlay grid for viewing unlocked plants and picking seeds.
- `src/ui/LoadoutBriefing.gd` — pre-battle seed preparation screen governed by level loadout rules.
- `src/ui/PlantGrid.gd` — reusable plant-card grid with costs and badges.
- `src/ui/HUD.gd` — rail, Rice Gem counter, desktop pause, layout, and what the banners say.
- `src/ui/HudCanvas.gd` — the battle HUD's one painted surface; its header holds the layer rules. Read it before adding a HUD element.
- `src/ui/HudDemo.gd` — `-- --hud-demo <pose>` capture and draw probe (`--perf-test` misses wave and touch widgets).
- `src/ui/StoryPanel.gd`, `src/ui/SightingCard.gd` — story UI built by `HUD`; `src/ui/SeedShrine.gd` — atlas Jade shop.
- `src/ui/TouchInput.gd` — multi-touch latch and pinch/drag signals, worn by both the battle shell
  and the atlas (`CONTRACT(touch-input)`).
- `src/ui/TouchControls.gd` — pause/rotate/cancel overlay; the actions a touchscreen cannot express.
  `HUD` builds it only on touch and never under `--perf-test`.
- `src/ui/SafeArea.gd` — notch, Dynamic Island and Android cutout insets for edge-anchored controls.
- `src/ui/UiPalette.gd` — semantic color tokens; use this instead of hardcoded hex values.
- `src/ui/BambooTrim.gd` — decorative border frame.
- `src/ui/EnemySelector.gd` — debug spawn picker (`H` overlay).

## Invariants & Traps

- **Internationalization (`tr()`) Requirement**:
  Wrap player-facing strings in `tr("...")` and register the script in `project.godot` POT files. `tools/doc_lint.mjs` enforces this.
- **Strict Color Tokens**:
  Use tokens from `src/ui/UiPalette.gd`, never raw hex or `Color()` literals.
- **SubViewport Update Cost**:
  Never `UPDATE_ALWAYS`; use `UPDATE_ONCE` or `UPDATE_DISABLED` after baking icons.
- **Loadout Rules**:
  Seed selection logic must validate against `src/core/LevelDB.gd` constraints (`seed_rules` for min/max selection and fixed slots).
- **Touch Reuses the Mouse**:
  Touch is the emulated mouse (`emulate_mouse_from_touch`), so every `Control` and every tap already
  works. A gesture only earns its own code when a mouse cannot express it, and it lives in
  `TouchInput`. Placement and digging commit on **release** and refuse while
  `GameManager.touch_gesture_multi` is set, so a pinch can never plant.
- **Safe Area**:
  Any edge- or corner-anchored control must pass through `SafeArea.apply()` after its offsets are
  set, or a notch or home indicator eats it. It is a no-op off touch and caches the authored offsets
  in metadata, so re-applying after a rotation does not stack insets.
- **One local player per device**:
  Every device runs the same HUD for exactly one player. Handlers that receive `player_id`
  compare it with `GameManager.local_player_id()` and ignore the other device's events, so a
  replicated `plant_placed` never moves the guest's cursor. Both devices share one loadout and
  one sun pool (CONTRACT(player-signals), CONTRACT(lan-coop)).

## Test Flags

```bash
GODOT=/home/nanaboo/Documents/Godot_v4.7.2/Godot_v4.7.2-stable_linux.x86_64
DISPLAY=:0 $GODOT --path . -- --flow-test                  # test loadout briefing and battle transitions
DISPLAY=:0 $GODOT --path . -- --screenshot --preview-test  # inspect seed card styling and preview meshes
```
