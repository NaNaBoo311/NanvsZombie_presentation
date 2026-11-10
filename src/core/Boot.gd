extends Node

# Boot — the main scene: an empty node that hands control to GameFlow.boot()
# (atlas start screen, or straight into the battle for test/capture flags).
# Keeps the first loaded scene tiny, so tests never load the atlas and players
# never load the battle before picking a level.

func _ready() -> void:
	GameFlow.boot()
