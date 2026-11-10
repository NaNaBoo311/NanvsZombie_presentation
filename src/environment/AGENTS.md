# Environment Subsystem

Manages batched foliage, instanced props, day/night cycles, lighting presets, and ambient effects.

## Scope & Key Files

- `src/environment/ForestMultiMesh.gd` — instanced batching for trees and heavy vegetation.
- `src/environment/GrassMultiMesh.gd` — ground-level grass blade and foliage batching.
- `src/environment/PropMultiMesh.gd` — batched props, lanterns, and architectural decorations.
- `src/environment/DayNightCycle.gd` — sun angle, ambient sky blending, and lighting transitions.
- `src/environment/LightingPreset.gd` — resource definitions for environmental lighting presets in `assets/lighting/`.
- `src/environment/StreetTraffic.gd` / `src/environment/StreetCars.gd` — ambient vehicular flow on perimeter roads.
- `src/environment/LanternDrift.gd` — floating water lanterns on river and canal surfaces.

## Invariants & Traps

- **MultiMesh Batching (<50 Draw Calls)**:
  All foliage, grass, and repeated scenery elements must be batched through `MultiMeshInstance3D`. Never spawn individual `MeshInstance3D` nodes for repeated environment geometry.
- **Zero Raster Textures**:
  All models and materials rely exclusively on baked vertex colors and procedural Godot shaders. Never use raster image maps.
- **Shadow Cost**:
  Instanced ground-level foliage and grass must keep `cast_shadow = OFF`. Decorative local lights must never cast shadows.
- **Post-Processing Restrictions**:
  Volumetric fog, SSAO, and SSIL must remain disabled for integrated GPU targets. Use FXAA, never MSAA.
- **Global Shader Uniforms**:
  Sunlight direction and day-night color grading updates must be set via `RenderingServer.global_shader_parameter_set()` to ensure shader parity.

## Test Flags

```bash
GODOT=/home/nanaboo/Documents/Godot_v4.7.2/Godot_v4.7.2-stable_linux.x86_64
DISPLAY=:0 $GODOT --path . -- --perf-test        # audit draw calls and rendering budget
DISPLAY=:0 $GODOT --path . -- --lighting-grade   # inspect lighting transitions and presets
```
