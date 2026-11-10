class_name BiaHoiZombie
extends HungryGhost

# Bia Hoi Zombie (Dodger) - a Ta Hien sidewalk draft-beer drinker lurching toward
# the pearl with a foamy mug and a stack of red plastic stools on his back. A
# HungryGhost whose numbers live in data/units/enemies/bia_hoi_zombie.json; all
# seek/eat/siege AI, health bar and materials are inherited.
#
# Stagger: while marching, _walk_toward adds a lateral velocity perpendicular to the
# march direction. The velocity is the derivative of a sine of amplitude sway_amplitude
# and period sway_period, read from a table built once in _ready (_init_step_table), so
# the net lateral offset stays within +-sway_amplitude of the lane line (zero-mean table).
# Per tick: one float add, one multiply-index and a table read: no sin/cos/sqrt/division.
# Swaying stops while eating, sieging, or within sway_fade_gap of the dais wall (it is
# faded linearly to zero there so the zombie never slides into the dais), and it never
# applies on a nav route (routes are kinematic and stay on their deck).

## Peak sideways displacement from the lane line (m).
@export var sway_amplitude: float = 0.8
## Seconds for one full left-right-left stagger.
@export var sway_period: float = 2.4
## Gap to the dais wall (m) under which the sway is faded out.
@export var sway_fade_gap: float = 2.5

const SWAY_TABLE_SIZE: int = 64

var _sway_lat_velocity := PackedFloat32Array()
var _sway_index_per_sec: float = 1.0
var _sway_inv_fade_gap: float = 0.4
var _sway_time: float = 0.0
var _sway_sign: float = 1.0

# Registry id (data/units/enemies/bia_hoi_zombie.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "bia_hoi_zombie"

func _apply_balance() -> void:
	super._apply_balance()
	sway_amplitude = float(BalanceDB.num(unit_id, "sway_amplitude", sway_amplitude))
	sway_period = float(BalanceDB.num(unit_id, "sway_period", sway_period))
	sway_fade_gap = float(BalanceDB.num(unit_id, "sway_fade_gap", sway_fade_gap))

## Builds the lateral-velocity table: d/dt of amplitude * sin(TAU * t / period), mean removed.
func _init_step_table() -> void:
	super._init_step_table()
	var period: float = maxf(sway_period, 0.1)
	var peak_speed: float = sway_amplitude * TAU / period
	_sway_lat_velocity.resize(SWAY_TABLE_SIZE)
	var sum: float = 0.0
	for i in SWAY_TABLE_SIZE:
		var v: float = peak_speed * cos(TAU * (float(i) + 0.5) / float(SWAY_TABLE_SIZE))
		_sway_lat_velocity[i] = v
		sum += v
	var mean: float = sum / float(SWAY_TABLE_SIZE)
	for i in SWAY_TABLE_SIZE:
		_sway_lat_velocity[i] -= mean
	_sway_index_per_sec = float(SWAY_TABLE_SIZE) / period
	_sway_inv_fade_gap = 1.0 / maxf(sway_fade_gap, 0.1)
	_sway_sign = 1.0 if randi() % 2 == 0 else -1.0

func _walk_toward(dir: Vector3, delta: float) -> void:
	# Model faces +Z; yaw faces the march direction (the stagger is sideways drift only).
	rotation.y = atan2(dir.x, dir.z)
	var lateral: float = 0.0
	if not _sway_lat_velocity.is_empty():
		var fade: float = _sway_fade()
		if fade > 0.0:
			_sway_time += delta
			var idx: int = int(_sway_time * _sway_index_per_sec) % SWAY_TABLE_SIZE
			lateral = _sway_lat_velocity[idx] * fade * _sway_sign
	var fwd: float = speed * _get_walk_speed_multiplier()
	# Perpendicular on the ground plane: dir is unit length, so (z, 0, -x) is too.
	velocity = Vector3(dir.x * fwd + dir.z * lateral, -2.0, dir.z * fwd - dir.x * lateral)
	move_and_slide()

## 1 away from the dais, ramping to 0 at the wall.
func _sway_fade() -> float:
	var house_pos: Vector3 = _house.global_position if is_instance_valid(_house) else target_position
	return clampf(_gap_to_house(house_pos) * _sway_inv_fade_gap, 0.0, 1.0)
