class_name ChiliPepper
extends Projectile

# Burning chili (HoiAnChili's shot): a normal hit that also blocks the target's healing
# for heal_block_sec (HungryGhost.block_heal), so a Tailor Zombie's stitches do nothing.
# heal_block_sec comes from data/projectiles/chili_pepper.json.

@export var heal_block_sec: float = 4.0

func _ready() -> void:
	super._ready()
	heal_block_sec = float(BalanceDB.projectile_num(projectile_id, "heal_block_sec", heal_block_sec))

func _hit(enemy: Node3D) -> void:
	super._hit(enemy)
	if enemy.has_method("block_heal"):
		enemy.block_heal(heal_block_sec)
