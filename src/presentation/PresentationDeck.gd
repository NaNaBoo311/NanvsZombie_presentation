class_name PresentationDeck
extends RefCounted

# PresentationDeck — the presentation's copy, in one place. The cover, the contents
# page and every section read their headings, credits and exhibit copy from here.
# Scene scripts never repeat it.
#
# Copy follows the title, team, contents and concept slides in
# reports/GameProgramming_slide_latex plus the GDD's Chapter 1. Adding a section is
# a registration point (CONTRACT(add-presentation-section)): add its row below, its
# screen scene under src/presentation/, and its scripts to project.godot's
# locale/translations_pot_files. GameFlow reads the row's scene path, and the
# contents page derives the row's live/disabled state from it.
#
# The presenter order below is the credit order in the Account dialog.

const UNIVERSITY_EYEBROW := "HO CHI MINH CITY"
const UNIVERSITY := "University of Technology"
const FACULTY := "Faculty of Computer Science and Engineering"
const COURSE := "Game Programming (CO3045) · CC02"

const TITLE_FIRST := "Leyline"
const TITLE_SECOND := "Warden"
const SUBTITLE := "Spirits of the Soil"

const PRESENTERS := [
	{"name": "Phạm Nam An", "id": "2352016"},
	{"name": "Hồ Minh Nhật", "id": "2352858"},
	{"name": "Lê Phạm Tiến Long", "id": "2352688"},
]
const LECTURER := "Phan Trần Minh Khuê"
const DATE := "11 November 2026"

const CONTENTS_TITLE := "Contents"

## The six sections this presentation covers. `scene` is empty until a section ships;
## the contents page disables a row when it is empty. Keep the list in slide order.
const SECTIONS := [
	{
		"number": "01",
		"title": "Concept & Vision",
		"scene": "res://src/presentation/ConceptVision.tscn",
	},
	{
		"number": "02",
		"title": "Core Gameplay",
		"scene": "",
	},
	{
		"number": "03",
		"title": "World & Narrative",
		"scene": "",
	},
	{
		"number": "04",
		"title": "Art, Audio & UI",
		"scene": "",
	},
	{
		"number": "05",
		"title": "Systems & Balance",
		"scene": "",
	},
	{
		"number": "06",
		"title": "Technology & Production",
		"scene": "",
	},
]

# --------------------------------------------------------------- section 01 ---

const CONCEPT_KICKER := "SECTION 01 · CONCEPT & VISION"
const CONCEPT_TITLE := "A miniature Vietnam."
const CONCEPT_PITCH := "Leyline Warden is a 3D tower defence set in a miniature Vietnam. Every thousand years, a solar eclipse frees hungry spirits from rivers and old streets. They march on the Dragon Pearl. You are the Warden; sacred flora is your only army."

## The at-a-glance ribbon under the pitch: label above, value below.
const CONCEPT_GLANCE := [
	{"label": "GENRE", "value": "3D tower defence"},
	{"label": "PLATFORMS", "value": "PC · Android · iOS"},
	{"label": "PLAYERS", "value": "Solo · LAN co-op"},
	{"label": "AUDIENCE", "value": "All ages · 10–35"},
]

const CIRCLE_TITLE := "Not lanes. A circle."
const CIRCLE_BODY := "The Pearl sits at the centre of the island. Spirits rise from spawn gates on every side. Plants reach only what they face — so position and facing are the decision."
const CIRCLE_STATS := [
	{"value": "3+", "label": "SPAWN\nREGIONS"},
	{"value": "8", "label": "HOME\nFACINGS"},
	{"value": "100+", "label": "PLANTABLE\nTILES"},
]

const WORLDS_TITLE := "Vietnam in miniature."
const WORLDS_BODY := "Real Vietnamese places rebuilt as floating dioramas — landmarks, plants and spirits."
const WORLDS_PROMISE := "PC and phones, no account, LAN co-op."
## `model` is the title-screen shard; `landmark` and its local pad position come from
## the generator's published anchors. `unit` is a posed vignette character.
const WORLDS := [
	{
		"id": "hcmc",
		"name": "SAIGON",
		"place": "Landmark 81 · City of the Dragon Vein",
		"hook": "Landmark 81 rises over the Dragon Vein; the city's spirits ride its evening traffic.",
		"model": "res://assets/models/maps/title/title_island_saigon.glb",
		"landmark": "res://assets/models/maps/landmark_81/landmark_81_tower.glb",
		"landmark_pos": Vector3(8.0, 0.0, -9.0),
		"unit": "res://assets/models/plants/lotus_shooter.glb",
		"unit_pos": Vector3(-6.0, 0.0, 6.0),
		"unit_yaw": 1.0,
		"unit_clip": "attack",
		"yaw": -0.28,
	},
	{
		"id": "ha_noi",
		"name": "HANOI",
		"place": "Hoan Kiem · Lake of the Returned Sword",
		"hook": "Turtle Tower holds the lake where the returned sword rests; Ngọc Sơn's bridge crosses to the islet.",
		"model": "res://assets/models/maps/title/title_island_hanoi.glb",
		"landmark": "res://assets/models/maps/hoan_kiem/ngoc_son_temple.glb",
		"landmark_pos": Vector3(-11.0, 0.0, -9.5),
		"unit": "res://assets/models/plants/sacred_rice.glb",
		"unit_pos": Vector3(7.0, 0.0, 10.0),
		"unit_yaw": -1.1,
		"unit_clip": "idle",
		"yaw": 0.3,
	},
	{
		"id": "da_nang",
		"name": "HOI AN",
		"place": "Hoi An · Town of a Thousand Lanterns",
		"hook": "The old town remembers its lantern festival; the Mother Lantern Shrine keeps the river lit.",
		"model": "res://assets/models/maps/title/title_island_hoi_an.glb",
		"landmark": "res://assets/models/maps/hoi_an/mother_lantern_shrine.glb",
		"landmark_pos": Vector3(0.0, 0.0, -1.0),
		"unit": "res://assets/models/enemies/tailor_zombie.glb",
		"unit_pos": Vector3(-8.0, 0.0, 5.0),
		"unit_yaw": 0.7,
		"unit_clip": "walk",
		"yaw": 0.0,
	},
]

const REFERENCES_TITLE := "Reference Games"
const REFERENCES_BODY := "What we take — and what we deliberately avoid."
const REFERENCES := [
	{"game": "Plants vs. Zombies", "year": "2009", "take": "Plant towers, sun economy, loadout.", "avoid": "Fixed lanes and its presentation."},
	{"game": "Plants vs. Zombies 2", "year": "2013", "take": "Themed worlds, plants and bosses.", "avoid": "Time travel and paid plants."},
	{"game": "Kingdom Rush", "year": "2011", "take": "Visible routes and gradual waves.", "avoid": "Fixed tower slots."},
	{"game": "Bloons TD 6", "year": "2018", "take": "Co-op and distinct targeting.", "avoid": "Monetisation, long upgrades."},
	{"game": "Dungeon Defenders", "year": "2010", "take": "3D camera and core co-op.", "avoid": "Hero combat, action-RPG loot."},
]

const PILLARS_TITLE := "Design Pillars"
const PILLARS_BODY := "These pillars guide every design decision."
const PILLARS := [
	{"number": "01", "title": "ROOTED IN\nVIETNAM", "line": "Flora, folklore and provinces shape every world."},
	{"number": "02", "title": "COZY TOY\nDIORAMA", "line": "A warm toy diorama, not a war."},
	{"number": "03", "title": "RUNS\nANYWHERE", "line": "60 FPS on integrated GPUs and phones."},
]
