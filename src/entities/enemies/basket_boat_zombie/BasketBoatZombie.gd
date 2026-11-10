class_name BasketBoatZombie
extends HungryGhost

# Basket Boat Zombie (Splitter) - a Cam Thanh fisherman carrying his woven basket boat
# on his back like a shell. A HungryGhost whose numbers live in
# data/units/enemies/basket_boat_zombie.json; march/seek/eat/siege AI, health bar and
# materials are inherited.
#
# Split: when he dies (bullets or shovel, both reach _die) the basket breaks and
# crab_count Basket Crabs appear at his feet, spread sideways, and march on with the
# normal HungryGhost AI. On a nav route they inherit the REMAINDER of his route.
#
# Bookkeeping (CONTRACT(add-wave), see docs/CONTRACTS.md): the crabs are added to the
# boat's own parent BEFORE the boat emits enemy_defeated, so
#  - each crab emits enemy_spawned from its own _ready (it is NOT rising), which keeps
#    GameManager.alive_enemies balanced against its later enemy_defeated;
#  - EnemySpawner adopts crabs flagged "wave_split" into its alive list in that same
#    emit, so the wave cannot complete in the instant between the boat's death and the
#    crabs' birth.

## How many crabs the basket releases.
@export var crab_count: int = 2
## Sideways distance between neighbouring crabs (m).
@export var crab_spread: float = 0.6

const CRAB_ID := "basket_crab"

func _init() -> void:
	unit_id = "basket_boat_zombie"

func _apply_balance() -> void:
	super._apply_balance()
	crab_count = int(BalanceDB.num(unit_id, "crab_count", crab_count))
	crab_spread = float(BalanceDB.num(unit_id, "crab_spread", crab_spread))

func _die() -> void:
	if _dead:
		return
	_release_crabs() # before super: enemy_defeated must come after the crabs exist
	super._die()

func _release_crabs() -> void:
	var parent := get_parent()
	var scene := BalanceDB.unit_scene(CRAB_ID)
	if scene == null or parent == null or not is_inside_tree() or crab_count <= 0:
		return
	var right := Vector3(cos(rotation.y), 0.0, -sin(rotation.y))
	for i in crab_count:
		var crab := scene.instantiate() as HungryGhost
		if crab == null:
			continue
		var offset := right * ((float(i) - float(crab_count - 1) * 0.5) * crab_spread)
		# Flags read by EnemySpawner (adopt into the wave) and GameManager (no kill credit).
		crab.set_meta("wave_split", true)
		crab.set_meta("no_kill_credit", true)
		parent.add_child(crab) # not rising: _ready emits enemy_spawned itself
		crab.global_position = global_position + offset
		crab.rotation.y = rotation.y
		var route := _remaining_route(offset)
		if not route.is_empty():
			crab.follow_route(route)

## What is left of this ghost's nav route, starting at its current spot (plus `offset`),
## or {} when it is off-route. Same arrays as NavGrid.find_route, sliced from the segment
## being walked; the first segment is re-aimed at the next route point.
func _remaining_route(offset: Vector3) -> Dictionary:
	if _route.is_empty():
		return {}
	var pts: PackedVector3Array = _route["points"]
	var dirs: PackedVector3Array = _route["dirs"]
	var lengths: PackedFloat32Array = _route["lengths"]
	var yaws: PackedFloat32Array = _route["yaws"]
	var seg := _route_seg
	if seg >= lengths.size() or seg + 1 >= pts.size():
		return {}
	var start := global_position + offset
	var first := pts[seg + 1] - start
	var first_len := first.length()
	var out := _route.duplicate()
	var n_pts := PackedVector3Array([start])
	var n_dirs := PackedVector3Array([first / first_len if first_len > 0.001 else dirs[seg]])
	var n_len := PackedFloat32Array([first_len])
	var n_yaw := PackedFloat32Array([yaws[seg]])
	for k in range(seg + 1, pts.size()):
		n_pts.append(pts[k])
	for k in range(seg + 1, lengths.size()):
		n_dirs.append(dirs[k])
		n_len.append(lengths[k])
		n_yaw.append(yaws[k])
	out["points"] = n_pts
	out["dirs"] = n_dirs
	out["lengths"] = n_len
	out["yaws"] = n_yaw
	if _route.has("airborne"):
		out["airborne"] = (_route["airborne"] as PackedByteArray).slice(seg)
	return out
