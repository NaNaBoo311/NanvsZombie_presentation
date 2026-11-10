class_name TheatricalMaskSpider
extends HungryGhost

# Theatrical Mask Spider (Fast Skirmisher) - a HungryGhost with 45 HP and a
# 2.0 m/s tetrapod scuttle. All clips play at the native 1.0x authored speed
# (same as the model viewer default): the 1.2s eat loop lands 1 bite per jaw
# snap (0.6s beat) and sieges the house for 6 per 1.2s loop. Walk runs at 1.0x
# like the viewer (leg cadence no longer matched to ground speed, so some
# foot-sliding is expected at 2.0 m/s). All march/seek/eat/siege AI, health
# bar, and materials inherited.

# Registry id (data/units/enemies/theatrical_mask_spider.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "theatrical_mask_spider"

func _ready() -> void:
	# Balance owns the numbers (data/units/enemies/theatrical_mask_spider.json); unit_id is set in _init.
	super._ready()
