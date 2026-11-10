class_name TouristZombie
extends HungryGhost

# Tourist Zombie (Disabler) - a Hoi An Ancient Town tourist in a rented pastel ao dai
# and non la, a big camera with a flash on a neck strap. A HungryGhost whose numbers
# live in data/units/enemies/tourist_zombie.json; march/seek/eat/siege AI, health bar
# and materials are inherited.
#
# Camera flash: a plain float countdown (never a per-frame scan). When it runs out she
# checks her frontal cone (flash_range, flash_half_angle_deg; squared-dot test against
# precomputed cos^2 and range^2, no sqrt/trig/division). With no plant inside she
# re-checks every flash_retry_interval; with one she holds still and plays the 'flash'
# clip, and at its flash_apex_sec every plant still in the cone gets
# PlantBase.stun(stun_duration) (CONTRACT(plant-stun)). Then the countdown restarts
# at flash_interval. Uneatable ground traps are stunned too (they stop ticking).

## Seconds between flashes.
@export var flash_interval: float = 6.0
## Countdown at spawn / surfacing, so the first flash comes sooner.
@export var flash_first_delay: float = 3.0
## Re-check cadence (s) while the flash is ready but no plant is in the cone.
@export var flash_retry_interval: float = 0.5
## Cone reach (m) and half-angle (deg) of the flash.
@export var flash_range: float = 5.0
@export var flash_half_angle_deg: float = 35.0
## Plant stun length (s) per flash.
@export var stun_duration: float = 2.0
## Time into the 'flash' clip when the bulb fires (matches the generator).
@export var flash_apex_sec: float = 0.5

## Fallback hold (s) if the model has no 'flash' clip; otherwise the clip length.
const FLASH_HOLD_FALLBACK: float = 1.1

var _flash_timer: float = 3.0
var _flash_hold: float = FLASH_HOLD_FALLBACK
## Remaining hold of the current flash (0 = not flashing).
var _flash_left: float = 0.0
var _flash_fired: bool = false
var _flash_range_sq: float = 25.0
var _flash_cos: float = 0.819152
var _flash_cos_sq: float = 0.671010

# Registry id (data/units/enemies/tourist_zombie.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "tourist_zombie"

func _ready() -> void:
	super._ready()
	_flash_timer = flash_first_delay
	if _anim_player and _anim_player.has_animation("flash"):
		_anim_player.get_animation("flash").loop_mode = Animation.LOOP_NONE
		_flash_hold = _anim_player.get_animation("flash").length

func _apply_balance() -> void:
	super._apply_balance()
	flash_interval = float(BalanceDB.num(unit_id, "flash_interval", flash_interval))
	flash_first_delay = float(BalanceDB.num(unit_id, "flash_first_delay", flash_first_delay))
	flash_retry_interval = float(BalanceDB.num(unit_id, "flash_retry_interval", flash_retry_interval))
	flash_range = float(BalanceDB.num(unit_id, "flash_range", flash_range))
	flash_half_angle_deg = float(BalanceDB.num(unit_id, "flash_half_angle_deg", flash_half_angle_deg))
	stun_duration = float(BalanceDB.num(unit_id, "stun_duration", stun_duration))
	flash_apex_sec = float(BalanceDB.num(unit_id, "flash_apex_sec", flash_apex_sec))
	_flash_range_sq = flash_range * flash_range
	_flash_cos = cos(deg_to_rad(flash_half_angle_deg))
	_flash_cos_sq = _flash_cos * _flash_cos

func _physics_process(delta: float) -> void:
	if _dead or is_rising:
		return
	if _flash_left > 0.0:
		# Holding still for the flash clip (no AI, no movement); the stun lands at the apex.
		_flash_left -= delta
		velocity = Vector3.ZERO
		if not _flash_fired and _flash_hold - _flash_left >= flash_apex_sec:
			_flash_fired = true
			_stun_plants_in_cone()
		if _flash_left <= 0.0:
			_flash_timer = flash_interval
		return
	super._physics_process(delta)
	if _dead:
		return
	_flash_timer -= delta
	if _flash_timer > 0.0:
		return
	if _any_plant_in_cone():
		_start_flash()
	else:
		_flash_timer = flash_retry_interval

func _start_flash() -> void:
	velocity = Vector3.ZERO
	_bite_timer = 0.0
	_arrived = false
	_flash_fired = false
	_flash_left = _flash_hold
	_play_clip("flash")

## Flat frontal-cone test (squared-dot, no sqrt/div): is `p` inside the flash cone?
func _in_flash_cone(p: Vector3, origin: Vector3, forward: Vector3) -> bool:
	var diff: Vector3 = p - origin
	diff.y = 0.0
	var dist_sq: float = diff.length_squared()
	if dist_sq < 0.0001 or dist_sq > _flash_range_sq:
		return false
	var d: float = diff.dot(forward)
	return d > 0.0 and d * d >= dist_sq * _flash_cos_sq

func _any_plant_in_cone() -> bool:
	var origin: Vector3 = global_position
	var forward: Vector3 = global_transform.basis.z
	for node in get_tree().get_nodes_in_group("Plants"):
		var plant := node as PlantBase
		if plant != null and _in_flash_cone(plant.global_position, origin, forward):
			return true
	return false

func _stun_plants_in_cone() -> void:
	var origin: Vector3 = global_position
	var forward: Vector3 = global_transform.basis.z
	for node in get_tree().get_nodes_in_group("Plants"):
		var plant := node as PlantBase
		if plant != null and _in_flash_cone(plant.global_position, origin, forward):
			plant.stun(stun_duration)
