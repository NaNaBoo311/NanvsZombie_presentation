# Leyline Warden — Interactive Presentation

The presentation build of *Leyline Warden: Spirits of the Soil*, a 3D tower-defence
game made for **Game Programming (CO3045) · CC02**.

This repository is derived from the playable game at `../NanVsZombie`. It keeps the
game's runtime and assets and adds presentation-only scenes, UI, copy and interactions
under `src/presentation/`. The playable game is never modified from here.

## Run

```bash
DISPLAY=:0 godot --path .
```

The presentation opens on the cover. **Play the game** enters the normal atlas.

## Scope

The talk covers four sections: Concept & Vision, Core Gameplay, World & Narrative,
and Art, Audio & UI. Presentation material for later sections is out of scope.

## Commands

```bash
DISPLAY=:0 godot --headless --editor --quit --path .   # reimport assets
DISPLAY=:0 godot --path . -- --title-test              # cover and stage test
DISPLAY=:0 godot --path . -- --title-shot              # capture the cover
DISPLAY=:0 godot --path . -- --flow-test               # menu/flow regression
```

Saves and settings use the isolated `LeylineWardenPresentation` user directory, so
this build cannot read or overwrite the playable game's progress.

## Commits

Conventional Commits: `<type>(<scope>): <short imperative description>`.
