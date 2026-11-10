@tool
class_name MapZones
extends RefCounted

# Zone queries the shared batching scripts (ForestMultiMesh, GrassMultiMesh,
# PropMultiMesh) ask of the map they are placed in, so those scripts hold no map
# content. A map names its zone script in MapDefinition.zones_path (Landmark 81:
# src/maps/landmark_81/Landmark81Zones.gd); that script provides these static
# functions with the same signatures. This script is also the flat default: no
# zones data, no water, nothing blocked, no lots. Static and @tool so the batching
# scripts' editor preview can call it (a map's own script does not run in the editor).
#
#   data() -> Dictionary                      the map's zones JSON
#   is_in_water(x, z) -> bool
#   blocks_trees(x, z) -> bool
#   blocks_tufts(x, z, legacy_pass: bool) -> bool   grass exclusions (see GrassMultiMesh)
#   blocks_new_zone_tufts(x, z) -> bool
#   on_walkway(x, z, margin) -> bool          true on ground the trees and grass must keep clear (paved walkway or spawn clearing)
#   lots(key) -> Array[Dictionary]            [{pos: Vector3, yaw: float, scale: float|Vector3}]

## The zone script of the map `node` belongs to (nearest ancestor with a non-empty
## `zones_path`), or this flat default. Reads the exported property, so it also
## works in the editor.
static func for_node(node: Node) -> Script:
	var n := node
	while n:
		var p: Variant = n.get("zones_path")
		if p is String and not (p as String).is_empty():
			var script := load(p) as Script
			if script == null:
				push_error("MapZones: cannot load zones script %s" % p)
				break
			return script
		n = n.get_parent()
	return load("res://src/maps/MapZones.gd")


static func data() -> Dictionary:
	return {}


static func is_in_water(_x: float, _z: float) -> bool:
	return false


static func blocks_trees(_x: float, _z: float) -> bool:
	return false


static func blocks_tufts(_x: float, _z: float, _legacy_pass: bool) -> bool:
	return false


static func blocks_new_zone_tufts(_x: float, _z: float) -> bool:
	return false


static func on_walkway(_x: float, _z: float, _margin: float = 0.0) -> bool:
	return false


static func lots(_key: String) -> Array[Dictionary]:
	return []
