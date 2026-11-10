class_name MapDefinition
extends Node3D

# MapDefinition — root script of every battlefield map scene (src/maps/<id>/).
# The battle shell (DioramaWorld) instances the scene named by
# data/maps/<map_id>/map.json for the level, stands the pearl on pearl_position and emits
# EventBus.map_loaded(map). PlacementManager, EnemySpawner and
# ThirdPersonCamera configure themselves from these fields instead of
# constants; mid-play queries (ground height) go through the "BattleMap" group.
# A map owns its own look: collision, water materials, prop shadows and its
# reaction to EventBus.day_blend_changed. Nothing here knows about provinces.
# CONTRACT(add-map): a map is data/maps/<map_id>/map.json {id, scene} + a scene
# whose root extends this script; LevelDB rejects unknown map ids at boot. The shared
# batching scripts read terrain_path (TerrainHeightfield) and zones_path
# (MapZones) from here; unset, they silently fall back to flat ground and no zones.
# nav_path (NavGrid) is the same pattern and is optional: a map with no nav file
# spawns enemies in spawn_zones / the forest belt exactly as before. With one, enemies
# spawn in the nav regions and walk A* routes around water and obstacles.
#
# XZ rects are Rect2(x, z, width, depth) in world metres.

const GROUP := "BattleMap"

## Height of the map's walkable ground (its island top), the zero the terrain
## heightfield measures from. 0.228 is Landmark 81's baked island.
const ISLAND_TOP_Y: float = 0.228
## Added on top of ISLAND_TOP_Y so a unit's origin clears the lawn accent (0.05).
const ORIGIN_CLEARANCE: float = 0.09

## Id from data/maps/<map_id>/map.json, set by the shell before the map enters the tree.
var map_id: String = ""

## Lawn zones a level can pick with its "lawn" field; default_lawn otherwise.
@export var lawn_zones: Dictionary = {"main": Rect2(-24.0, -24.0, 48.0, 48.0)}
@export var default_lawn: String = "main"
## World height of the map's ground origin (consumers add their own lifts).
@export var ground_y: float = 0.0
## Where the Sacred Dragon Pearl (the defend target) stands.
@export var pearl_position: Vector3 = Vector3.ZERO
## The building this map defends in place of the pearl (it stands on pearl_position
## and must fit the pearl's 7 x 7 m footprint, CentralHouse.PEARL_BOUNDS); null = the pearl.
## CONTRACT(add-map): a bigger building is silently mis-sized for placement and enemies.
@export var defend_model: PackedScene = null
## Enemy spawn band: square ring around spawn_center, outside spawn_inner and
## inside spawn_outer (half extents), plus fixed fallback points (world XZ).
@export var spawn_center: Vector2 = Vector2.ZERO
@export var spawn_inner: float = 25.0
@export var spawn_outer: float = 40.0
@export var spawn_fallback_points: Array[Vector2] = []
## Named spawn areas: zone_id -> Rect2(x, z, width, depth)
@export var spawn_zones: Dictionary = {}
## Camera pan bounds (world XZ).
@export var camera_bounds: Rect2 = Rect2(-34.0, -34.0, 68.0, 68.0)
## LightingPreset id (assets/lighting/<id>.tres) applied when a level sets no
## time_of_day; "" keeps the current one.
@export var default_time_of_day: String = ""
## Whether the shared daytime sky (NightSky) shows its hot-air balloons over this map.
@export var sky_balloons: bool = true
## Generated terrain heightfield (TerrainHeightfield); "" = flat at ground_y.
@export var terrain_path: String = ""
## Zone script the shared batching scripts query (src/maps/MapZones.gd contract);
## "" = the flat default (no water, nothing blocked, no lots).
@export_file("*.gd") var zones_path: String = ""
## Enemy regions, bridge decks and grid bounds (NavGrid, data/maps/<map_id>/nav.json);
## "" = no pathfinding, the old zone / belt spawns.
## CONTRACT(add-map): unset, a nav.json is never read and every wave spawns on the belt.
@export var nav_path: String = ""
## Scouting pose for the pre-battle loadout briefing ({pos, arm, pitch, yaw, fov?},
## same keys as a CameraPresets row). Empty = the --wide-overview fallback.
@export var briefing_camera: Dictionary = {}

var _nav: NavGrid = null


func _enter_tree() -> void:
	add_to_group(GROUP)


func lawn_rect(zone: String) -> Rect2:
	if zone.is_empty():
		zone = default_lawn
	if lawn_zones.has(zone):
		return lawn_zones[zone]
	push_warning("[MapDefinition] %s has no lawn zone \"%s\"; using \"%s\"." % [name, zone, default_lawn])
	return lawn_zones.get(default_lawn, Rect2())


## Terrain height above ground_y at world (x, z); 0 on a flat map.
func terrain_height(x: float, z: float) -> float:
	var field := TerrainHeightfield.load_path(terrain_path) if not terrain_path.is_empty() else null
	return field.height(x, z) if field else 0.0


## World height of the ground a unit stands on at (x, z): the island top plus
## ORIGIN_CLEARANCE, plus the terrain above it. Consumers add their own lift
## (EnemySpawner adds SURFACE_LIFT). This is the one place the spawn origin
## height is defined, so spawns and nav routes can never disagree.
func ground_y_at(x: float, z: float) -> float:
	return maxf(ground_y, ISLAND_TOP_Y) + ORIGIN_CLEARANCE + terrain_height(x, z)


func get_spawn_zone(zone_id: String) -> Rect2:
	return spawn_zones.get(zone_id, Rect2())


## The map's nav grid, parsed once on first use. Never cached in a static: it must die
## with the map, because --map-switch-test counts resources across round trips and a
## static would keep the first map's grid alive.
func nav() -> NavGrid:
	if _nav == null:
		_nav = NavGrid.from_path(self, nav_path)
	return _nav


## Gives every MeshInstance3D under `node` a trimesh StaticBody3D on layer 1 (the
## ground placement raycasts and RouteClearance hit), except meshes whose lowercase
## name contains one of `skip` (water, railings, cliff underbelly...: decorative).
## The body is named Col_<mesh> so a physics query reports which surface it hit.
func add_walkable_collisions(node: Node, skip: PackedStringArray) -> void:
	if node is MeshInstance3D and node.mesh:
		var n_name := node.name.to_lower()
		var is_decorative := false
		for part in skip:
			if part in n_name:
				is_decorative = true
				break
		if not is_decorative:
			var shape: Shape3D = node.mesh.create_trimesh_shape()
			if shape:
				var col_shape := CollisionShape3D.new()
				col_shape.shape = shape
				var sb := StaticBody3D.new()
				sb.name = "Col_%s" % str(node.name)
				sb.collision_layer = 1
				sb.collision_mask = 6
				sb.add_child(col_shape)
				node.add_child(sb)
	for child in node.get_children():
		add_walkable_collisions(child, skip)


## Turns shadow casting off for every GeometryInstance3D under `node`
## (decorative props, AGENTS.md invariant 4).
func set_shadows_off(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		set_shadows_off(child)


## --round-test hook: this map's silent lookups that broke (empty = all OK).
func contract_problems() -> PackedStringArray:
	return nav().problems()
