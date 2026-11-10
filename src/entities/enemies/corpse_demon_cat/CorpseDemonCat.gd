class_name CorpseDemonCat
extends HungryGhost

# Corpse Demon Cat / Linh Mieu (Fast Skirmisher) - a HungryGhost with 45 HP
# and a 2.0 m/s predatory stalk. All clips play at the native 1.0x authored
# speed (same as the model viewer default): the 1.2s attack loop lands 2 hits
# (1 plant bite per 0.6s pounce beat) and sieges the house for 6 per 1.2s
# loop. The 2.0s 'reanimate' ritual stays viewer-only for now (future hook,
# same pattern as the pot ghost's viewer-only 'low_hp'); gameplay runs on
# walk/attack/die only. All march/seek/eat/siege AI, health bar, and
# materials inherited.

# Registry id (data/units/enemies/corpse_demon_cat.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "corpse_demon_cat"

func _ready() -> void:
	# Balance owns the numbers (data/units/enemies/corpse_demon_cat.json); unit_id is set in _init.
	super._ready()
