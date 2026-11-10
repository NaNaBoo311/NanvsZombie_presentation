# Model Card: Cozy Terracotta Cottage

- **GLB Path**: `res://assets/models/architecture/cozy_cottage.glb`
- **Category**: Architecture / Defense Home Base

---

## 1. Visual Intent & Design
- **Description**: Handcrafted cozy wooden cottage with chunky closed terracotta barrel tiles (3 overlapping tiers with thick lips), dark cedar plank siding with stepped boards, solid pediment gables (fascia trim removed per art review — verified zero roof protrusions), covered front porch with timber awning and steps, and glowing windows.
- **Aesthetic**: Tactile miniature diorama / clay toy aesthetic with soft beveled edges inspired by *Animal Crossing: New Horizons* and *The Legend of Zelda: Link's Awakening*.
- **Palette** (rev2, walls darkened for contrast):
  - Roof tiles: `#D86535` base, `#F08C52` crest highlights, `#A4451C` crevices; ridge caps `#C45428`.
  - Timber cabin walls: `#52301A` dark cedar with alternate-plank variation; `#854E28` oak posts/trims.
  - Porch steps & floor: `#9E6436` amber wood.
  - Window & Door: `#4D2C15` walnut with `#FFE28A` warm interior glow (door glass `#FFE082`).
  - Garden: `#C45C30` clay pots, `#488228` leaves, `#F6B820` / `#EB6824` marigolds.

---

## 2. Technical Specifications
- **Triangles**: 1,684 triangles total (rev2 budget: 1,200 – 1,800)
  - `CottageBody`: 992 triangles (plank walls, solid gables, posts 0.24, base skirt, wall plates, porch with timber awning, door, windows with 4-pane mullions, planters, garden)
  - `CottageRoof`: 692 triangles (42 closed skirt tiles in 3 tiers with per-vertex crest highlight, 9 ridge caps with rounded ends, 2 slabs)
- **Materials**: 1 unified material (`M_Cottage`, Roughness 0.80) reading Vertex Color Attributes (`Col`)
- **Textures**: 0 MB (Zero raster maps; baked vertex colors + normal-based baked AO — see `docs/TRAPS.md#vertex-dirt-zeroes-col`; Bevel is vertex-group-gated to hero masses to hold the tri budget)
- **Bounding Box (W × D × H)**: 5.22m (X) × 5.83m (Z) × 4.68m (Y height)
- **Origin / Pivot**: Ground level center `(0, 0, 0)`
- **Facing**: Forward (-Z in Godot)

---

## 3. Node Hierarchy & Mesh Parts
```text
cozy_cottage (Node3D)
├── CottageBody (MeshInstance3D)
└── CottageRoof (MeshInstance3D)
```

---

## 4. Attachment Sockets & Offsets
- **Health Bar Offset**: `Vector3(0, 5.1, 0)` (above the roof ridge)
- **Front Porch Steps**: `Vector3(0, 0.35, -2.4)`
- **Doorway Socket**: `Vector3(0, 0.6, -1.8)`
- **Base Footprint**: `Vector2(5.2, 5.2)`

---

## 5. Godot Integration Recipe
```gdscript
# Suggested Node: StaticBody3D (Layer 1: Environment / Objective)
# Collision Shape:
var shape = BoxShape3D.new()
shape.size = Vector3(4.8, 3.8, 4.4)

var col = CollisionShape3D.new()
col.shape = shape
col.position = Vector3(0, 1.9, 0.4)
```
