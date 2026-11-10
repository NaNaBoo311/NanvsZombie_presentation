class_name PeachBlossomFan
extends LotusShooter

# Peach Blossom Fan (Đào Nhật Tân) - counter to the Bia Hoi Zombie's off-lane stagger.
# Turret behaviour is LotusShooter's; each shot is a fan of `petal_count` petals spread
# `spread_deg` apart around the aim line, so a target swaying off the line still meets
# one. Numbers come from data/units/plants/peach_blossom_fan.json.

@export var petal_count: int = 3
@export var spread_deg: float = 8.0
var _spread_rad: float = 0.1396263

# Registry id (data/units/plants/peach_blossom_fan.json), set at instantiation so the
# --round-test registry check and the base _ready both see it.
func _init() -> void:
	unit_id = "peach_blossom_fan"

func _ready() -> void:
	super._ready()
	petal_count = maxi(1, int(BalanceDB.num(unit_id, "petal_count", petal_count)))
	spread_deg = float(BalanceDB.num(unit_id, "spread_deg", spread_deg))
	_spread_rad = deg_to_rad(spread_deg)

## One petal per fan slot, symmetric around the current facing (flat XZ).
func _spawn_projectile() -> void:
	if not _projectile_scene or not shoot_point:
		return
	var facing: Vector3 = global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = Vector3.MODEL_FRONT
	facing = facing.normalized()
	var dmg: int = int(BalanceDB.num(unit_id, "damage", 12))
	var parent_node: Node = get_parent() if get_parent() else get_tree().current_scene
	for i in petal_count:
		var dir: Vector3 = facing.rotated(Vector3.UP, (float(i) - (petal_count - 1) * 0.5) * _spread_rad)
		var proj := _projectile_scene.instantiate() as Projectile
		proj.damage = dmg
		parent_node.add_child(proj) # in the tree before touching global transforms
		proj.global_position = shoot_point.global_position
		proj.direction = dir
		proj.look_at(proj.global_position - dir, Vector3.UP) # model nose is +Z
		EventBus.projectile_fired.emit(proj)
	Audio.play(Audio.LOTUS_SHOOT)
	_spawn_muzzle_flash()
