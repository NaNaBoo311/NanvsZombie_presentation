# Presentation Repo — Agent Entry

This repository is the **interactive presentation build** of Leyline Warden. The
playable game lives at `../NanVsZombie`; never edit it from here. Presentation-only
scenes, UI, copy and interactions belong under `src/presentation/`. Everything else
is the imported game runtime and changes only when the presentation needs it.

## Routing

| Task | Open first |
| :--- | :--- |
| Presentation cover | `src/presentation/PresentationTitle.gd` |
| Cover copy, credits, section data | `src/presentation/PresentationDeck.gd` |
| Cover layout and interaction | `src/presentation/PresentationCover.gd` |
| 3D title stage | `src/menus/title/TitleMenu.gd` |
| Scene changes, atlas hand-off | `src/core/GameFlow.gd` |
| Colours, fonts, buttons | `src/ui/UiPalette.gd`, `src/ui/HudMenuButton.gd` |
| Contracts, traps, style | `docs/CONTRACTS.md`, `docs/TRAPS.md`, `docs/STYLE_GUIDE.md` |
| Story and world copy | `docs/LORE.md` |

## Commands

```bash
GODOT=/home/nanaboo/Documents/Godot_v4.7.2/Godot_v4.7.2-stable_linux.x86_64
DISPLAY=:0 $GODOT --path .                              # run the presentation
DISPLAY=:0 $GODOT --headless --editor --quit --path .   # reimport after asset changes
DISPLAY=:0 $GODOT --path . -- --title-test              # cover and 3D stage
DISPLAY=:0 $GODOT --path . -- --title-shot              # cover capture and budget line
DISPLAY=:0 $GODOT --path . -- --flow-test               # flow regression
```

## Invariants

- **Original game untouched** — all work happens in this repository.
- **One owner for scene changes** — `GameFlow`.
- **Tokens only** — colours come from `UiPalette`, never raw hex.
- **`tr()` for player-facing text** and register UI scripts in
  `project.godot`'s `locale/translations_pot_files`.
- **60 FPS baseline** — batch shapes through `HudCanvas`; no per-frame script when
  nothing animates; never `UPDATE_ALWAYS` a `SubViewport`.
- **No dead actions** — a control either does what it says or is not shipped.

## Commits

Never run `git commit`; write the message to `commit.txt` for the user.
