class_name AerobicsAuntie
extends HungryGhost

# Aerobics Auntie (Support) - a morning-exercise auntie from Hoan Kiem Lake towing her
# loa ke keo party speaker. A HungryGhost whose numbers live in
# data/units/enemies/aerobics_auntie.json; march/seek/eat/siege AI, health bar and
# materials are inherited.
#
# Aura: every aura_interval seconds (a plain float countdown, not every frame) she
# calls apply_speed_buff(aura_speed_mult, aura_buff_duration) on every other living
# enemy within aura_radius (squared distance, no sqrt). The duration is slightly longer
# than the interval, so the buff lapses shortly after an enemy leaves the aura or she
# dies. She never buffs herself. Enemies come from the "Enemies" group, which is empty
# of work when she is alone (the scan is skipped via GameManager.alive_enemies).

## Aura radius (m).
@export var aura_radius: float = 4.0
## Walk-speed multiplier granted to allies in the aura.
@export var aura_speed_mult: float = 1.3
## Seconds between aura pulses.
@export var aura_interval: float = 0.5
## Buff lifetime per pulse (s); a little longer than aura_interval.
@export var aura_buff_duration: float = 0.7

var _aura_radius_sq: float = 16.0
var _aura_timer: float = 0.0

# Registry id (data/units/enemies/aerobics_auntie.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "aerobics_auntie"

func _apply_balance() -> void:
	super._apply_balance()
	aura_radius = float(BalanceDB.num(unit_id, "aura_radius", aura_radius))
	aura_speed_mult = float(BalanceDB.num(unit_id, "aura_speed_mult", aura_speed_mult))
	aura_interval = float(BalanceDB.num(unit_id, "aura_interval", aura_interval))
	aura_buff_duration = float(BalanceDB.num(unit_id, "aura_buff_duration", aura_buff_duration))
	_aura_radius_sq = aura_radius * aura_radius

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _dead or is_rising:
		return
	_aura_timer -= delta
	if _aura_timer > 0.0:
		return
	_aura_timer = aura_interval
	_pulse_aura()

func _pulse_aura() -> void:
	# Nothing to buff when she is the only enemy alive: skip the group walk entirely.
	if GameManager.alive_enemies <= 1:
		return
	var origin: Vector3 = global_position
	for node in get_tree().get_nodes_in_group("Enemies"):
		var ally := node as HungryGhost
		if ally == null or ally == self or ally._dead or ally.is_rising:
			continue
		if origin.distance_squared_to(ally.global_position) <= _aura_radius_sq:
			ally.apply_speed_buff(aura_speed_mult, aura_buff_duration)
