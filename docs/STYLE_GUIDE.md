# Visual Style Guide & GDScript Conventions - PVZ_3D

This guide establishes the visual rules, art tokens, shader guidelines, and GDScript standards for **PVZ_3D**.

---

## 1. Visual Style: Cozy + Stylized Low-Poly Diorama

The visual goal is a warm, inviting, Ghibli/Synty-inspired 3D diorama with clean geometric silhouettes, rich vertex color gradients, and gentle procedural movement.

### Color Palette Tokens
| Token Name | Hex Code | Usage |
| :--- | :--- | :--- |
| **Lawn Grass Green** | `#4EA843` | Garden lawn tiles, lush meadow ground |
| **Soil Brown** | `#7A4B29` | Garden beds, planting soil |
| **Earth Dark Brown** | `#4D311A` | Diorama underground cutaway edge |
| **Spruce Needle Emerald**| `#245838` | Spruce foliage base / deep shadow |
| **Pine Highlight Green** | `#3A784E` | Spruce sunlit canopy tops |
| **Oak Leaf Deep Green** | `#326A28` | Deciduous oak leaf base shadow |
| **Oak Leaf Vibrant** | `#529838` | Deciduous oak sunlit outer foliage |
| **Autumn Amber Gold** | `#E59828` | Autumn tree canopy shadow |
| **Autumn Golden Yellow**| `#F4BC38` | Autumn tree sunlit crown tips |
| **Birch White Bark** | `#EAE6DC` | Birch paper bark trunk |
| **Birch Charcoal Band** | `#3D3B38` | Birch horizontal lenticel markings |
| **Timber Trunk Brown** | `#5A3D28` | Standard tree trunk and wooden structures |
| **Sunflower Yellow** | `#F9D030` | Sunflower petals, sun currency orbs |
| **Peashooter Green** | `#76C835` | Peashooter plant body |
| **Cottage Roof Terracotta**| `#C25636` | Central house roof tiles |
| **Cottage Wall Cream**| `#E8D8B8` | Stucco / wood cottage walls |
| **Cobblestone Gray** | `#828892` | Pathways and stone borders |
| **Sakura Blossom Rose** | `#F292AA` | Sakura tree canopy base |
| **Sakura Blossom Petal**| `#FFBECE` | Sakura sunlit highlight |
| **Vermilion Bridge Red**| `#A4261A` | Japanese arched bridge timber |
| **Amber Lantern Glow**  | `#FFB048` | Warm lantern omni illumination |
| **Warm Twilight Daylight**| `#FFE8CC` | Directional light tint |
| **Sky Horizon Cyan** | `#98D8EB` | Sky gradient lower |
| **Sky Zenith Blue**  | `#4A8EB8` | Sky gradient upper |
| **Plant Marker Green** | `#40FF8C` | Additive ground disc under plants (`FactionMarker`) |
| **Enemy Marker Red** | `#FF334D` | Additive spiked ground ring under enemies (`FactionMarker`) |

---

## 2. Foliage & Vegetation Standards

1. **Multi-Tone Baked Vertex Colors**:
   - Every procedurally generated tree in `tools/asset_generator/generators/vegetation/` has ambient occlusion baked into lower/inner vertices, and sun-dappled highlights baked into upper/outer crown vertices.
   - **Zero texture maps** are used for trees, preserving GPU texture memory bandwidth for mobile devices.
2. **Tree night grade (`ForestMultiMesh.set_day_blend()`)**:
   - Trees keep their imported `StandardMaterial3D` (see `TRAPS.md#pbr-parity` — a
     hand-written foliage shader measured ~8% darker and was removed).
   - Each distinct imported tree material is duplicated once; night albedo is the
     authored day albedo cooled/darkened toward slate-indigo (`NIGHT_TINT`), lerped
     during day/night transitions only. Zero idle cost.
3. **MultiMesh Batching**:
   - Forest trees must always be batched into `MultiMeshInstance3D` nodes to keep the entire forest under 5 draw calls.
   - House clearing bounds (`|X| <= 23.0m`, `|Z| <= 26.0m`) must be respected when placing trees.

---

## 3. Environment & Lighting Standards

- **Sun / Moonlight DirectionalLight3D**:
  - Color: `#FFF0D9` (Warm golden daylight) or `#B3C7F0` (Moonlight)
  - Energy: `0.48` - `1.55`
  - Rotation: Pitch around `-42°`, Yaw around `-38°` for rich diagonal diorama shadows.
  - Shadows: Enabled on primary directional light (`DirectionalLight3D`), max distance `95.0m`.
- **Shadow Discipline (Non-GPU Baseline)**:
  - Ground-level instanced foliage (`GrassMultiMesh`) MUST have `cast_shadow = OFF`.
  - Decorative point lights (e.g. garden pagoda lanterns) MUST keep `shadow_enabled = false` to eliminate point shadow cubemap passes.
- **WorldEnvironment & Post-Processing**:
  - Background Mode: Procedural Sky / Sky shader with smooth gradient.
  - Ambient Light: Sky contribution `0.5`, Color `#B0D0E0` to prevent harsh black shadows.
  - Tonemap: `Filmic` or `ACES` with exposure `1.05`–`1.15` for rich color vibrancy.
  - Glow: Subtle soft bloom (Bloom threshold `0.75`–`0.9`, intensity `0.3`–`0.7`).
  - **Screen-Space Discipline**: SSIL and Volumetric Froxel Fog are disabled by default for 60 FPS iGPU performance. Anti-aliasing defaults to FXAA (`screen_space_aa=1`) to avoid bandwidth starvation from MSAA.

---

## 4. Camera Standards

- **Projection**: Perspective with low Field of View (`FOV: 38° - 42°`).
- **Angle**: Pitch tilted down `~38°` to `45°` looking forward/down onto the garden.
- **SpringArm**: Length `10.0` - `12.0` meters, smoothing enabled (`lerp` with weight `6.0 * delta`).

---

## 5. GDScript Code Conventions

- **Static Typing**: Use static typing everywhere:
  ```gdscript
  var speed: float = 5.0
  var current_target: Node3D = null
  func calculate_damage(amount: int) -> int:
  ```
- **Node References**:
  - Use `@onready var node: MeshInstance3D = $MeshInstance3D` or `@export var custom_scene: PackedScene`.
- **Signals & Decoupling**:
  - Use past-tense signal names (`placed`, `died`, `amount_changed`).
  - Emit to `EventBus` for cross-system events.
- **Naming Conventions**:
  - Functions & Variables: `snake_case` (`attack_nearest_target()`, `movement_speed`)
  - Constants & Enums: `SCREAMING_SNAKE_CASE` (`MAX_HEALTH = 100`)
  - Classes & Types: `PascalCase` (`class_name PlantBase extends CharacterBody3D`)
