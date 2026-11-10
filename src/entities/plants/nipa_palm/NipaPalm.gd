class_name NipaPalm
extends AuraPlant

# Nipa Palm (Dừa Nước) - counter to the Cao Lau Cook's coal spill. Every pulse it shares
# its sap: every damaged plant within aura_radius (itself included) gets heal_amount HP
# back (PlantBase.heal, never above full), so a row scorched by the spill recovers. It
# keeps healing after the last enemy dies (a group walk every pulse_interval, nothing
# per frame). Numbers come from data/units/plants/nipa_palm.json.

@export var heal_amount: int = 30

# Registry id (data/units/plants/nipa_palm.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "nipa_palm"

func _ready() -> void:
	super._ready()
	heal_amount = int(BalanceDB.num(unit_id, "heal_amount", heal_amount))

## Healing matters between waves too.
func _needs_enemies() -> bool:
	return false

func _pulse() -> int:
	var healed: int = 0
	for plant in plants_in_aura():
		if plant.has_method("heal") and int(plant.heal(heal_amount)) > 0:
			healed += 1
	return healed
