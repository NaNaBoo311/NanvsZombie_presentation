# Audio

Sound effects and music for the game, played through the `src/core/Audio.gd` autoload
(buses `Music` / `SFX` / `UI` in `default_bus_layout.tres`). Add your files here and see
`docs/CONTRACTS.md#add-sound` for the three steps to wire them in.

## Where files go

| Kind | Folder | Name |
|:--|:--|:--|
| Enemy sounds | `sfx/enemies/` | `<unit_id>_<event>.wav`, e.g. `hungry_ghost_attack.wav` |
| Plant sounds | `sfx/plants/` | `<unit_id>_<event>.wav`, e.g. `lotus_shooter_attack.wav` |
| Menus, HUD, clicks | `sfx/ui/` | `<screen>_<action>.wav`, e.g. `seedbank_pick.wav` |
| Background loops (river, city, wind) | `sfx/ambience/` | `<place>_<what>.ogg`, e.g. `landmark_81_river.ogg` |
| Music | `music/` | `<world_or_screen>_<mood>.ogg`, e.g. `atlas_theme.ogg` |

- `<unit_id>` is the file name in `data/units/plants/` or `data/units/enemies/`.
- `<event>` is the animation clip the sound plays with (`walk`, `attack`, `die`, `idle`), or
  `spawn` / `hit` / `shoot`.
- Variants of one sound: add `_01`, `_02`, … (`hungry_ghost_die_01.wav`).
- Names are lowercase with underscores only. Never rename a file after it has been merged: the game
  refers to it by path.

## Format
- **Short sound effects:** WAV, 16-bit, 44.1 kHz. Use mono for anything that happens at a place
  on the island (units, projectiles) and stereo only for UI.
- **Music and ambience loops:** Ogg Vorbis, 44.1 kHz, stereo. Loops must be seamless.
- Peaks at −1 dBFS, with the silence trimmed from both ends.
- Work out what the sound is meant to do first: its length, and whether it loops. Keep unit
  sounds under about 2 s.

## Committing
Godot writes a `.import` file next to each sound the first time it opens the project. Commit each
sound **with** its `.import`, and nothing outside `assets/audio/`, `docs/lore/` and your own
source files.
