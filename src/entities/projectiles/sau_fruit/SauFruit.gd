class_name SauFruit
extends Projectile

# Sour sấu fruit (SauShooter's shot): against an enemy still holding a shield
# (StreetVendorZombie.shield_points() > 0) it deals shield_mult x damage, so the acid
# eats through woven baskets; otherwise a normal hit. shield_mult comes from
# data/projectiles/sau_fruit.json.

@export var shield_mult: float = 3.0

func _ready() -> void:
	super._ready()
	shield_mult = float(BalanceDB.projectile_num(projectile_id, "shield_mult", shield_mult))

func _hit(enemy: Node3D) -> void:
	if enemy.has_method("shield_points") and int(enemy.shield_points()) > 0 and enemy.has_method("take_damage"):
		enemy.take_damage(int(round(damage * shield_mult)))
		return
	super._hit(enemy)
