class_name CaoLauCook
extends HungryGhost

# Cao Lau Cook (Death Blast) - a Hoi An street-food cook carrying a charcoal stove and a
# broth pot on a shoulder pole. A HungryGhost whose numbers live in
# data/units/enemies/cao_lau_cook.json; march/seek/eat/siege AI, health bar and materials
# are inherited.
#
# Death blast: when he is killed (bullets) the stove tips and spills hot coals. Every plant
# in the "Plants" group within blast_radius (XZ distance from his position) takes
# blast_damage once, through the plant's own take_damage. Uneatable ground traps are
# included on purpose: it is a fire spill, not a bite. A shovel removal does NOT blast
# (remove_by_shovel is overridden to mark the death as non-lethal to plants). Nothing runs
# per frame: one group walk inside _die, squared radius precomputed in _apply_balance().

## Flat damage dealt to each plant caught in the spill.
@export var blast_damage: int = 60
## Radius of the spill around the cook (m).
@export var blast_radius: float = 2.5

var _blast_radius_sq: float = 6.25
var _shoveled: bool = false

func _init() -> void:
	unit_id = "cao_lau_cook"

func _apply_balance() -> void:
	super._apply_balance()
	blast_damage = int(BalanceDB.num(unit_id, "blast_damage", blast_damage))
	blast_radius = float(BalanceDB.num(unit_id, "blast_radius", blast_radius))
	_blast_radius_sq = blast_radius * blast_radius

## Shovel removal reaches the same _die as a kill; flag it first so the coals stay put.
func remove_by_shovel() -> void:
	if _dead or is_rising:
		return
	_shoveled = true
	super.remove_by_shovel()

func _die() -> void:
	if _dead:
		return
	if not _shoveled and is_inside_tree():
		_spill_coals()
	super._die()

func _spill_coals() -> void:
	var here := global_position
	for node in get_tree().get_nodes_in_group("Plants"):
		var plant := node as Node3D
		if plant == null or not is_instance_valid(plant) or not plant.has_method("take_damage"):
			continue
		var dx := plant.global_position.x - here.x
		var dz := plant.global_position.z - here.z
		if dx * dx + dz * dz <= _blast_radius_sq:
			plant.take_damage(blast_damage)
