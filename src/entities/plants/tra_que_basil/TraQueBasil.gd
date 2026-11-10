class_name TraQueBasil
extends AuraPlant

# Tra Que Basil (Húng Trà Quế) - counter to the Tourist Zombie's camera flash. Every
# pulse its calming scent makes every plant within aura_radius (itself included)
# stun-immune for immune_duration (PlantBase.grant_stun_immunity), clearing a stun that
# already landed; the pulse outlasts the beat, so neighbours stay covered between pulses.
# The attack clip plays only when a pulse actually cleared a stun. Numbers come from
# data/units/plants/tra_que_basil.json.

@export var immune_duration: float = 0.8

# Registry id (data/units/plants/tra_que_basil.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "tra_que_basil"

func _ready() -> void:
	super._ready()
	immune_duration = float(BalanceDB.num(unit_id, "immune_duration", immune_duration))

func _pulse() -> int:
	var cleared: int = 0
	for plant in plants_in_aura():
		if plant.has_method("grant_stun_immunity") and plant.grant_stun_immunity(immune_duration):
			cleared += 1
	return cleared
