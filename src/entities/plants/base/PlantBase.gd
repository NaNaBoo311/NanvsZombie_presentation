class_name PlantBase
extends StaticBody3D

# Base class for all plants.
# Provides cute idle breathing bounce, health management, grid coordinate tracking,
# and the stun state (stun() / is_stunned()) that acting plants gate on.

@export var current_health: int = 100
## Full health, captured in _ready from the DB (heal() clamps to it).
var max_health: int = 100
## BalanceDB id matching data/units/plants/<id>.json (CONTRACT(add-plant)).
## When set and the DB has an entry, max_health and shared turret tuning
## below are pulled from the DB with these @exports as fallback.
@export var unit_id: String = ""

# Turret targeting personality (overridden per plant species).
# Convention: actors face +Z (Vector3.MODEL_FRONT).
@export var vision_range: float = 14.0
@export var vision_half_angle_deg: float = 22.5
@export var turn_speed_deg: float = 180.0

var base_rotation_y: float = 0.0:
	set(val):
		base_rotation_y = val
		base_forward = Vector3(sin(val), 0.0, cos(val))

var base_forward: Vector3 = Vector3(0.0, 0.0, 1.0)
var vision_cone_cos: float = 0.9238795
var turn_speed_rad: float = 3.1415927
var vision_range_sq: float = 196.0

## True for ground traps: enemies never notice or bite this plant.
var uneatable: bool = false
## LAN guest copy (CONTRACT(lan-coop)): the host owns HP and death; a remote copy
## renders them and never acts. Acting loops in subclasses early-return on this.
var is_remote: bool = false
var grid_coord: Vector2i = Vector2i.ZERO
var idle_timer: float = 0.0
var idle_enabled: bool = true
@onready var visuals: Node3D = $Visuals

## Stun expiry (Time.get_ticks_msec()), 0 when not stunned. See stun().
var _stunned_until_msec: int = 0
## Stun immunity expiry (TraQueBasil's aura), 0 when not immune. See grant_stun_immunity().
var _stun_immune_until_msec: int = 0
var _daze_tween: Tween = null
## Dazed wobble: visuals roll +-DAZE_ROLL rad, one swing per DAZE_SWING s.
const DAZE_ROLL: float = 0.14
const DAZE_SWING: float = 0.25

func _ready() -> void:
	if not unit_id.is_empty():
		current_health = int(BalanceDB.num(unit_id, "max_health", current_health))
		vision_range = float(BalanceDB.num(unit_id, "vision_range", vision_range))
		vision_half_angle_deg = float(BalanceDB.num(unit_id, "vision_half_angle_deg", vision_half_angle_deg))
		turn_speed_deg = float(BalanceDB.num(unit_id, "turn_speed_deg", turn_speed_deg))
	max_health = current_health
	add_to_group("Plants")
	FactionMarker.attach(self, FactionMarker.Faction.PLANT, 0.9)
	if is_zero_approx(base_rotation_y) and not is_zero_approx(rotation.y):
		base_rotation_y = rotation.y
	else:
		base_forward = Vector3(sin(base_rotation_y), 0.0, cos(base_rotation_y))
	
	vision_cone_cos = cos(deg_to_rad(vision_half_angle_deg))
	turn_speed_rad = deg_to_rad(turn_speed_deg)
	vision_range_sq = vision_range * vision_range
	
	# Spawn scale pop-in animation
	visuals.scale = Vector3.ZERO
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(visuals, "scale", Vector3.ONE, 0.4)
	_optimize_shadows(self)

func _optimize_shadows(node: Node) -> void:
	# Invariant 4: only the primary silhouette meshes cast shadows; secondary details skip shadow passes.
	var mesh_count: int = 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var cur = stack.pop_back()
		if cur is MeshInstance3D:
			mesh_count += 1
			if mesh_count > 3:
				cur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for child in cur.get_children():
			stack.append(child)

## Godot's glTF import leaves vertex_color_use_as_albedo off, so a vertex-coloured model
## (tools/asset_generator/generators/plants/plant_kit.mjs) renders white until this runs.
## Call once from _ready on the plant root.
func use_vertex_colors(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in node.mesh.get_surface_count():
			var mat: Material = node.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				mat.vertex_color_use_as_albedo = true
	for child in node.get_children():
		use_vertex_colors(child)

func _process(delta: float) -> void:
	if not idle_enabled:
		return
	# Subtle cute idle breathing (one sin per plant per frame, reused for all axes).
	idle_timer += delta * 3.0
	var s := sin(idle_timer)
	visuals.scale.y = 1.0 + s * 0.04
	visuals.scale.x = 1.0 - s * 0.02
	visuals.scale.z = 1.0 - s * 0.02

# ========================================================
# STUN (enemy disablers, e.g. TouristZombie's camera flash)
# ========================================================

## Stuns this plant for `duration` seconds: it does not acquire targets, fire,
## explode or produce until the stun ends. Re-stunning keeps the later expiry.
## Plays a brief dazed wobble on `visuals` (rotation.z only, one tween per stun).
## CONTRACT(plant-stun): stun() only sets a timestamp. Every plant with its own
## acting loop (_physics_process / _process / _shoot / timed spawns) must gate
## that loop on is_stunned(), or it silently ignores stuns. Passive plants
## (pure walls) need nothing.
func stun(duration: float) -> void:
	if duration <= 0.0 or current_health <= 0 or not is_inside_tree():
		return
	if Time.get_ticks_msec() < _stun_immune_until_msec:
		return
	var until: int = Time.get_ticks_msec() + int(duration * 1000.0)
	if until <= _stunned_until_msec:
		return
	_stunned_until_msec = until
	_play_daze(duration)

## True while stunned. Unstunned plants pay one int compare; an expired stun
## clears itself on the first check after it ends.
func is_stunned() -> bool:
	if _stunned_until_msec == 0:
		return false
	if Time.get_ticks_msec() < _stunned_until_msec:
		return true
	_stunned_until_msec = 0
	return false

## Clears any stun and ignores new ones for `duration` seconds (re-granting keeps the later
## expiry). Returns true when it actually cleared a stun, so an aura can tell it mattered.
func grant_stun_immunity(duration: float) -> bool:
	_stun_immune_until_msec = maxi(_stun_immune_until_msec, Time.get_ticks_msec() + int(duration * 1000.0))
	if not is_stunned():
		return false
	_stunned_until_msec = 0
	if _daze_tween and _daze_tween.is_valid():
		_daze_tween.kill()
	if is_instance_valid(visuals):
		visuals.rotation.z = 0.0
	return true

## Restores up to `amount` HP, never above max_health. Returns the HP actually restored.
func heal(amount: int) -> int:
	if is_remote or amount <= 0 or current_health <= 0 or current_health >= max_health:
		return 0
	var before: int = current_health
	current_health = mini(current_health + amount, max_health)
	if current_health != before:
		EventBus.plant_health_changed.emit(grid_coord, current_health, max_health)
	return current_health - before

func _play_daze(duration: float) -> void:
	if not is_instance_valid(visuals):
		return
	if _daze_tween and _daze_tween.is_valid():
		_daze_tween.kill()
	_daze_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var swings: int = maxi(1, int(duration / DAZE_SWING))
	var side: float = 1.0
	for _i in swings:
		_daze_tween.tween_property(visuals, "rotation:z", DAZE_ROLL * side, DAZE_SWING)
		side = -side
	_daze_tween.tween_property(visuals, "rotation:z", 0.0, DAZE_SWING * 0.5)

func take_damage(amount: int) -> void:
	if is_remote:
		return # host authority: only replicated HP changes apply
	current_health -= amount
	EventBus.plant_health_changed.emit(grid_coord, current_health, max_health)
	# Visual hit flash / squash
	var tween = create_tween()
	tween.tween_property(visuals, "scale", Vector3(1.1, 0.85, 1.1), 0.08)
	tween.tween_property(visuals, "scale", Vector3.ONE, 0.1)
	
	if current_health <= 0:
		die()

## Guest: apply the host's authoritative HP (no local damage path, no signal).
func apply_remote_health(hp: int, max_hp: int) -> void:
	max_health = maxi(1, max_hp)
	current_health = clampi(hp, 0, max_health)

func set_remote() -> void:
	is_remote = true

func die() -> void:
	EventBus.plant_died.emit(grid_coord)
	# Pop out death animation
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(visuals, "scale", Vector3.ZERO, 0.25)
	tween.tween_callback(queue_free)

## PvZ shovel removal: dig up with no Sun refund. Same tile-freeing signal
## as death (PlacementManager frees the grid tile), plus a `plant_removed`
## analytics signal. Bypasses `take_damage` so armed Popping Pods defuse
## instead of detonating (see PoppingPod override).
func remove_by_shovel() -> void:
	EventBus.plant_died.emit(grid_coord)
	EventBus.plant_removed.emit(grid_coord)
	set_physics_process(false)
	set_collision_layer_value(3, false) # unpickable during the pop-out (no double-dig)
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(visuals, "scale", Vector3.ZERO, 0.25)
	tween.tween_callback(queue_free)

# ========================================================
# SHARED TARGETING (reused by plants and enemies)
# ========================================================

## Nearest candidate inside a flat forward cone. Single implementation shared by
## plant targeting (vs Enemies) and ghost eating (vs Plants) — no duplicated math.
## Squared-dot cone test: no sqrt/div per candidate (invariant 7).
static func find_nearest_in_cone(origin: Vector3, forward: Vector3, candidates: Array[Node], cone_range: float, half_angle_cos: float) -> Node3D:
	var best: Node3D = null
	var best_dist_sq: float = INF
	var cos_sq: float = half_angle_cos * half_angle_cos
	for candidate in candidates:
		if not (candidate is Node3D):
			continue
		# Burrow-rise spawns are invulnerable until surfaced; airborne gliders
		# until touchdown (CONTRACT(add-wave)).
		if candidate.get("is_rising") == true or candidate.get("is_airborne") == true:
			continue
		# CONTRACT(add-plant): ground traps set `uneatable` so ghosts walk over
		# them instead of stopping to bite (they stay in "Plants" for the shovel).
		if candidate.get("uneatable") == true:
			continue
		var c := candidate as Node3D
		var diff: Vector3 = c.global_position - origin
		diff.y = 0.0
		var dist_sq: float = diff.length_squared()
		if dist_sq < 0.0001 or dist_sq > cone_range * cone_range:
			continue
		var d := diff.dot(forward)
		if half_angle_cos < 0.0:
			if d < half_angle_cos * sqrt(dist_sq):
				continue
		elif d < 0.0 or d * d < dist_sq * cos_sq:
			continue
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = c
	return best

## Nearest enemy inside this plant's vision cone. Override for exotic targeting.
func acquire_target() -> Node3D:
	return find_nearest_in_cone(global_position, base_forward, get_tree().get_nodes_in_group("Enemies"), vision_range, vision_cone_cos)

## Smooth turret yaw toward target. Returns remaining angle in radians (for align-to-fire gates).
func face_target(target: Node3D, delta: float) -> float:
	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return 0.0
	var desired: float = atan2(to_target.x, to_target.z)
	rotation.y = rotate_toward(rotation.y, desired, turn_speed_rad * delta)
	return absf(angle_difference(rotation.y, desired))
