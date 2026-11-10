class_name SilkCottonFlare
extends AuraPlant

# Silk Cotton Flare (Hoa Gạo) - counter to the Paper Effigy glider. Every pulse it
# showers embers over aura_radius: a gliding effigy catches fire and is forced to land
# (PaperEffigy.knock_down) taking ignite_damage, so the shooters can hit it before it
# passes the outer row; every grounded enemy in range takes burn_damage. Numbers come
# from data/units/plants/silk_cotton_flare.json.

@export var ignite_damage: int = 20
@export var burn_damage: int = 3

# Registry id (data/units/plants/silk_cotton_flare.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "silk_cotton_flare"

func _ready() -> void:
	super._ready()
	ignite_damage = int(BalanceDB.num(unit_id, "ignite_damage", ignite_damage))
	burn_damage = int(BalanceDB.num(unit_id, "burn_damage", burn_damage))

func _pulse() -> int:
	var hit: int = 0
	for enemy in enemies_in_aura():
		if enemy.get("is_airborne") == true:
			# Only gliders that can land (PaperEffigy) are grounded; other airborne
			# segments (nav-route hops) stay untouchable.
			if enemy.has_method("knock_down") and enemy.knock_down():
				enemy.take_damage(ignite_damage)
				hit += 1
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(burn_damage)
			hit += 1
	return hit
