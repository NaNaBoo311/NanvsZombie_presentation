class_name PaperEffigy
extends HungryGhost

# Hang Ma Paper Effigy (Glider) - a paper votive figure riding a paper horse,
# the kind burned on Hang Ma street for the Hungry Ghost festival. A HungryGhost
# whose numbers live in data/units/enemies/paper_effigy.json; all march/seek/eat/
# siege AI, health bar and materials are inherited.
#
# Glide: from spawn it rides is_airborne (plants skip it, take_damage ignores hits,
# exactly like a nav-route airborne segment) and notices no food, while its Visuals
# float glide_height above the body. Once it is inside the touchdown_half_extent
# square around the pearl (just past the lawn's outer plant row) it touches down:
# is_airborne clears, the Visuals settle to the ground in one tween, and the normal
# seek/eat state machine takes over, so the first plants it bites are behind the
# outer row. On a nav route the glide simply continues over the route (the route's
# own airborne flags are overridden), and the touchdown check starts at the route end.
# Touchdown test is two abs() compares per tick (no sqrt/trig); no work after it.

## Extra height (m) the Visuals ride while gliding; settles to 0 at touchdown.
@export var glide_height: float = 1.0
## Touchdown once |dx| and |dz| to the pearl are both below this (m).
@export var touchdown_half_extent: float = 12.0
## Seconds the Visuals take to settle onto the ground at touchdown (visual only).
const TOUCHDOWN_DURATION: float = 0.45

var _gliding: bool = true

# Registry id (data/units/enemies/paper_effigy.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "paper_effigy"

func _ready() -> void:
	# Balance owns the numbers (data/units/enemies/paper_effigy.json); unit_id is set in _init.
	super._ready()
	is_airborne = true
	if is_instance_valid(visuals):
		visuals.position.y = glide_height

func _apply_balance() -> void:
	super._apply_balance()
	glide_height = float(BalanceDB.num(unit_id, "glide_height", glide_height))
	touchdown_half_extent = float(BalanceDB.num(unit_id, "touchdown_half_extent", touchdown_half_extent))

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _gliding or _dead or is_rising:
		return
	# A nav route resets is_airborne from its own segments every tick: the glide wins.
	is_airborne = true
	if is_on_route():
		return
	var house_pos: Vector3 = _house.global_position if is_instance_valid(_house) else target_position
	if absf(global_position.x - house_pos.x) < touchdown_half_extent and absf(global_position.z - house_pos.z) < touchdown_half_extent:
		_touch_down()

## No food is noticed mid-air, so the glider never seeks or bites before touchdown.
func _find_plant_in_range() -> Node3D:
	if _gliding:
		return null
	return super._find_plant_in_range()

## Forced landing from a plant (SilkCottonFlare sets the paper alight): touches down
## where it is, wherever that is. Returns true only on the call that grounded it.
func knock_down() -> bool:
	if not _gliding or _dead or is_rising:
		return false
	_touch_down()
	return true

func _touch_down() -> void:
	_gliding = false
	is_airborne = false
	_scan_cooldown = 0.0 # look for food on the very next tick
	if is_instance_valid(visuals):
		var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(visuals, "position:y", 0.0, TOUCHDOWN_DURATION)
