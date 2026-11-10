class_name TailorZombie
extends HungryGhost

# Tailor Zombie (Healer) - a Hoi An made-to-measure tailor. A HungryGhost whose numbers
# live in data/units/enemies/tailor_zombie.json; march/seek/eat/siege AI, health bar and
# materials are inherited.
#
# Stitch: every heal_interval seconds (a plain float countdown, not every frame) she
# finds the single most-damaged other living enemy within heal_radius (squared
# distance, no sqrt) and calls heal(heal_amount) on it, never above its max. She skips
# herself, dead and rising enemies; nothing happens if no ally is damaged. The scan is
# skipped when she is the only enemy alive (GameManager.alive_enemies). The "heal" clip
# in the model is not played by this script (cosmetic, available for the viewer/preview).

## Heal radius (m).
@export var heal_radius: float = 5.0
## Flat HP restored per stitch.
@export var heal_amount: int = 25
## Seconds between stitches.
@export var heal_interval: float = 3.0

var _heal_radius_sq: float = 25.0
var _heal_timer: float = 0.0

# Registry id (data/units/enemies/tailor_zombie.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "tailor_zombie"

func _apply_balance() -> void:
	super._apply_balance()
	heal_radius = float(BalanceDB.num(unit_id, "heal_radius", heal_radius))
	heal_amount = int(BalanceDB.num(unit_id, "heal_amount", heal_amount))
	heal_interval = float(BalanceDB.num(unit_id, "heal_interval", heal_interval))
	_heal_radius_sq = heal_radius * heal_radius
	_heal_timer = heal_interval

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _dead or is_rising:
		return
	_heal_timer -= delta
	if _heal_timer > 0.0:
		return
	_heal_timer = heal_interval
	_stitch()

func _stitch() -> void:
	# Nothing to mend when she is the only enemy alive: skip the group walk entirely.
	if GameManager.alive_enemies <= 1:
		return
	var origin: Vector3 = global_position
	var best: HungryGhost = null
	var best_missing: int = 0
	for node in get_tree().get_nodes_in_group("Enemies"):
		var ally := node as HungryGhost
		if ally == null or ally == self or ally._dead or ally.is_rising:
			continue
		var missing: int = ally.max_health - ally._health
		if missing <= best_missing:
			continue
		if origin.distance_squared_to(ally.global_position) <= _heal_radius_sq:
			best = ally
			best_missing = missing
	if best != null:
		best.heal(heal_amount)
