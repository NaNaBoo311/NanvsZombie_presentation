# Model Card: Fluffy Cloud-Canopy Tree

- **GLB Path**: `res://assets/models/vegetation/tree_fluffy_cloud.glb`
- **Category**: Vegetation

---

## 1. Visual Intent & Design
- **Description**: Soft billowy cloud-canopy diorama tree — tapered cedar trunk with root flare and playful bend, 3 branch stubs feeding 5 overlapping hand-jittered foliage puffs (crown + left/right/back + sun-cap) forming a tiered fluffy silhouette.
- **Aesthetic**: Miniature clay/toy diorama with spherical normals, inspired by *Animal Crossing: New Horizons* and *Link's Awakening*.
- **Color Palette** (vertex colors, `Col`, sRGB hex → linear baked):
  - Foliage crest `#78A832`, mid `#468228`, underside `#285420` (undersides ×0.72, sun faces ×1.06).
  - Trunk base `#5E3A20`, sun side `#784E2E`, root `#3A2210` with wood-grain striations.
  - No `vertex_color_dirt` op used — deterministic normal-based AO per `docs/TRAPS.md#vertex-dirt-zeroes-col`.

---

## 2. Technical Specifications
- **Triangles**: 484 total (Trunk 84 + Foliage 400) — budget 400–700 PASS
  - Trunk: 7-sided tapered cylinder + 3× 6-sided branch stubs (Z 2.30–2.79m).
  - Foliage: 5× icosphere subdiv-2 (80 tris each), joined to one mesh.
- **Materials**: 1 unified material (`M_CloudTree`, Roughness 0.82, Specular IOR Level 0.08) reading `Col`, shared by both meshes = 2 draw calls.
- **Textures**: 0 MB (zero raster maps; baked vertex colors + deterministic AO).
- **Bounding Box (W × D × H)**: 3.72m (X) × 3.23m (Z) × 5.11m (Y height)
  - Canopy spread 3.72 × 3.23m (spec 3.2–3.8m); total height 5.11m (spec 4.5–5.2m); trunk clear height 1.98m (spec 1.8–2.2m); base dia ~0.40m (spec 0.35–0.42m).
- **Origin / Pivot**: Ground level center `(0, 0, 0)` (trunk base).
- **Facing**: Forward (-Z in Godot).
- **Spherical normals**: BAKED — `NormalEdit` Radial, target `CanopyCenter` Empty at `(0,0,3.4)`, Mix COPY 0.9, `export_apply=True` so the `.glb` carries soft cloud normals.

---

## 3. Node Hierarchy & Mesh Parts
```text
tree_fluffy_cloud (Node3D)
├── Trunk (MeshInstance3D)
└── Foliage (MeshInstance3D)
```

---

## 4. Animations (If Applicable)
- None (static vegetation). Wind sway via `StylizedTreeFoliage.gdshader` (`wind_height_min 1.5` keeps trunk grounded).

---

## 5. Attachment Sockets & Offsets
- **Health Bar Offset**: `Vector3(0, 5.4, 0)` (above sun-cap)
- **Canopy Center / Interaction Point**: `Vector3(0, 3.4, 0)`
- **Footprint / Ground Contact**: `Vector2(3.7, 3.2)`

---

## 6. Godot Integration Recipe
Suggested node type, collision shape, and initialization code:
```gdscript
# Suggested Node: MultiMeshInstance3D (batched with ForestMultiMesh pattern)
# 1 shared foliage material + 1 shared bark material keeps the whole forest <5 draw calls.
var mmi = MultiMeshInstance3D.new()
mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
# Per-instance: Transform3D(Basis(), Vector3(x, 0, z)) outside |x|,|z| <= 25m clearing
# (see ForestMultiMesh.is_valid_tree_pos). Zero idle cost: sway is shader TIME only.

# Collision Shape (only if a hero instance needs blocking):
var shape = CylinderShape3D.new()
shape.radius = 0.25
shape.height = 2.0
var col = CollisionShape3D.new()
col.shape = shape
col.position = Vector3(0, 1.0, 0)
```
