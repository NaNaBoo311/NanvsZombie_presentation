class_name CycloZombie
extends HungryGhost

# Cyclo Zombie (Charger) - a Hanoi xich lo (pedal tricycle, passenger bench and
# canvas hood in front, zombie driver in a pith helmet pedaling behind). A
# HungryGhost whose numbers live in data/units/enemies/cyclo_zombie.json; all
# march/seek/siege AI, health bar and materials are inherited.
#
# Charge: it races in at `speed`. The FIRST plant it would bite is crushed instead:
# one crash_damage hit (enough to kill a normal plant), applied once, then the
# 'crash' clip plays while it holds still. After that it drops to speed_after_crash
# and bites like any ghost. The latch is one-way (_charging) and never resets.
# Ground traps (PlantBase.uneatable) are never noticed by the inherited
# _find_plant_in_range, so the charge rolls over them and is not spent.
# The walk clip plays at speed / initial speed, so pedals and wheels match the
# ground speed (fast at first, a slow plod after the crash).
# No trig, division or sqrt per tick: the walk-scale reciprocal is cached in _ready.

## Damage of the one-time crush on the first plant reached.
@export var crash_damage: int = 200
## March speed (m/s) after the crash.
@export var speed_after_crash: float = 0.7

## Fallback hold time (s) if the model has no 'crash' clip; otherwise the clip length.
const CRASH_HOLD_FALLBACK: float = 0.8

var _charging: bool = true
var _crash_left: float = 0.0
var _crash_hold: float = CRASH_HOLD_FALLBACK
var _walk_ref_inv: float = 1.0

# Registry id (data/units/enemies/cyclo_zombie.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "cyclo_zombie"

func _ready() -> void:
	# Balance owns the numbers (data/units/enemies/cyclo_zombie.json); unit_id is set in _init.
	super._ready()
	_walk_ref_inv = 1.0 / maxf(speed, 0.01)
	if _anim_player and _anim_player.has_animation("crash"):
		_anim_player.get_animation("crash").loop_mode = Animation.LOOP_NONE
		_crash_hold = _anim_player.get_animation("crash").length

func _apply_balance() -> void:
	super._apply_balance()
	crash_damage = int(BalanceDB.num(unit_id, "crash_damage", crash_damage))
	speed_after_crash = float(BalanceDB.num(unit_id, "speed_after_crash", speed_after_crash))

## Pedals and wheels track ground speed: 1.0x at the charge, slower after the crash.
func _walk_anim_scale() -> float:
	return speed * _walk_ref_inv

func _physics_process(delta: float) -> void:
	if _crash_left > 0.0 and not _dead and not is_rising:
		# Holding still for the crash clip (no AI, no movement).
		_crash_left -= delta
		velocity = Vector3.ZERO
		return
	super._physics_process(delta)

func _eat_plant(plant: Node3D, delta: float) -> void:
	if not _charging:
		super._eat_plant(plant, delta)
		return
	_charging = false
	speed = speed_after_crash
	if plant.has_method("take_damage"):
		plant.take_damage(crash_damage)
		Audio.play(Audio.ENEMY_EAT)
	velocity = Vector3.ZERO
	_bite_timer = 0.0
	_arrived = false
	_crash_left = _crash_hold
	_play_clip("crash")
