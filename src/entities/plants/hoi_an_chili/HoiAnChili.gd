class_name HoiAnChili
extends LotusShooter

# Hoi An Chili (Ớt Hội An) - counter to the Tailor Zombie's healing. Turret behaviour is
# LotusShooter's; the unit JSON names the chili_pepper shot, whose ChiliPepper script
# burns the target so it cannot be healed for heal_block_sec.

# Registry id (data/units/plants/hoi_an_chili.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "hoi_an_chili"
