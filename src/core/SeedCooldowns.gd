extends Node

# Seed recharge. Planting a seed puts it on cooldown for its unit JSON's "seed.cooldown"
# seconds (BalanceDB.cooldown). One rack per battle: LAN partners share the loadout and the
# sun, so they share this too, each device timing it from the replicated plant_placed.
# The guest hears a placement after the host, so it can never ask early; the host still
# re-checks (PlacementManager.remote_placement_allowed). Only levels recharge: the sandbox
# stays free for testing. Owned by GameManager. Runs only while a seed is cooling, and
# pausing the tree freezes it.

var _left: Dictionary = {} # plant id -> seconds left
var _total: Dictionary = {} # plant id -> seconds at the start


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	EventBus.plant_placed.connect(_on_plant_placed)


func clear() -> void:
	_left.clear()
	_total.clear()
	set_process(false)


func left(plant_id: String) -> float:
	return float(_left.get(plant_id, 0.0))


func total(plant_id: String) -> float:
	return float(_total.get(plant_id, 0.0))


func is_cooling(plant_id: String) -> bool:
	return _left.has(plant_id)


func _on_plant_placed(plant_id: String, _coord: Vector2i, _player_id: int) -> void:
	if not GameManager.level_active:
		return
	var seconds := BalanceDB.cooldown(plant_id)
	if seconds <= 0.0:
		return
	_left[plant_id] = seconds
	_total[plant_id] = seconds
	set_process(true)
	EventBus.seed_cooldown_started.emit(plant_id)


func _process(delta: float) -> void:
	for plant_id: String in _left.keys():
		_left[plant_id] -= delta
		if _left[plant_id] <= 0.0:
			_left.erase(plant_id)
			_total.erase(plant_id)
			EventBus.seed_cooldown_finished.emit(plant_id)
	if _left.is_empty():
		set_process(false)
