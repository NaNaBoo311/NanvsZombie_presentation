class_name LanternPhysalis
extends KapokCatapult

# Lantern Physalis (Tầm Bóp Lồng Đèn) - counter to the Basket Boat Zombie's crab split.
# Lobber behaviour (farthest target in the cone, wind-up tween, apex launch, stun gate)
# is KapokCatapult's; the unit JSON names the lantern_berry shot, whose splash_radius
# (data/projectiles/lantern_berry.json) hits the crabs spilling out around the boat.

# Registry id (data/units/plants/lantern_physalis.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "lantern_physalis"

func _ready() -> void:
	super._ready()
	use_vertex_colors(self)
