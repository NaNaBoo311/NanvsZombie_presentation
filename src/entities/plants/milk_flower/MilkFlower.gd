class_name MilkFlower
extends AuraPlant

# Milk Flower (Hoa Sữa) - counter to the Aerobics Auntie's speed aura. Every pulse its
# heavy autumn scent slows every grounded enemy within aura_radius to slow_mult for
# slow_duration (HungryGhost.apply_slow, which multiplies with speed buffs: x1.3 becomes
# x0.65) and deals `damage`. Numbers come from data/units/plants/milk_flower.json.

@export var slow_mult: float = 0.5
@export var slow_duration: float = 1.2
@export var damage: int = 4

# Registry id (data/units/plants/milk_flower.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "milk_flower"

func _ready() -> void:
	super._ready()
	slow_mult = float(BalanceDB.num(unit_id, "slow_mult", slow_mult))
	slow_duration = float(BalanceDB.num(unit_id, "slow_duration", slow_duration))
	damage = int(BalanceDB.num(unit_id, "damage", damage))

func _pulse() -> int:
	var hit: int = 0
	for enemy in enemies_in_aura():
		if enemy.get("is_airborne") == true:
			continue
		if enemy.has_method("apply_slow"):
			enemy.apply_slow(slow_mult, slow_duration)
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage)
		hit += 1
	return hit
