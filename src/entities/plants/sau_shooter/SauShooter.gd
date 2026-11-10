class_name SauShooter
extends LotusShooter

# Sau Shooter (Cây Sấu Hà Nội) - counter to the Street Vendor's basket shield.
# A Hanoi street tree whose fruit-head spits sour sấu fruit. All turret behaviour (cone
# targeting, aiming, the baked attack sync, stun gating) is LotusShooter's; the unit JSON
# names the sau_fruit shot, whose SauFruit script multiplies damage against shields.

# Registry id (data/units/plants/sau_shooter.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "sau_shooter"
