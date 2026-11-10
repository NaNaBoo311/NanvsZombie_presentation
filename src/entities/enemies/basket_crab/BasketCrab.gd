class_name BasketCrab
extends HungryGhost

# Basket Crab (Minion) - a small mud crab that tumbles out of a broken basket boat.
# Spawned only by BasketBoatZombie._die (flagged "wave_split" / "no_kill_credit");
# a HungryGhost whose numbers live in data/units/enemies/basket_crab.json, so the
# march/seek/eat/siege AI, health bar and materials are inherited. Fast, fragile,
# weak bites.

func _init() -> void:
	unit_id = "basket_crab"
