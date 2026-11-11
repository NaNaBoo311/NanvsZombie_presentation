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
		"scene": "res://src/presentation/CoreGameplayAtlas.tscn",
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
const CONCEPT_TITLE := "The eclipse comes."
const CONCEPT_PITCH := "Leyline Warden is a 3D tower defence set in a miniature Vietnam. Every thousand years, a solar eclipse frees hungry spirits from rivers and old streets. They march on the Dragon Pearl. You are the Warden; sacred flora is your only army."

## The at-a-glance grid under the pitch copy: label above, value below.
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
## `id` is also the atlas province id: the World exhibit focuses that province.
const WORLDS := [
	{
		"id": "hcmc",
		"name": "SAIGON",
		"place": "Landmark 81 · City of the Dragon Vein",
		"hook": "Landmark 81 rises over the Dragon Vein; the city's spirits ride its evening traffic.",
	},
	{
		"id": "ha_noi",
		"name": "HANOI",
		"place": "Hoan Kiem · Lake of the Returned Sword",
		"hook": "Turtle Tower holds the lake where the returned sword rests; Ngọc Sơn's bridge crosses to the islet.",
	},
	{
		"id": "da_nang",
		"name": "DA NANG",
		"place": "Da Nang · Town of a Thousand Lanterns",
		"hook": "The lantern town remembers its festival; the Mother Lantern Shrine keeps the river lit.",
	},
]

const REFERENCES_TITLE := "Reference Games"
const REFERENCES_BODY := "What we take — and what we deliberately avoid."
const REFERENCES := [
	{"game": "Plants vs. Zombies", "year": "2009", "take": "Plant towers, sun economy, loadout.", "avoid": "Fixed lanes and its presentation."},
	{"game": "Plants vs. Zombies 2", "year": "2013", "take": "Themed worlds, plants and bosses.", "avoid": "Time travel and paid plants."},
	{"game": "Kingdom Rush", "year": "2011", "take": "Visible routes and gradual waves.", "avoid": "Fixed tower slots."},
]

const PILLARS_TITLE := "Design Pillars"
const PILLARS_BODY := "These pillars guide every design decision."
const PILLARS := [
	{"number": "01", "title": "ROOTED IN\nVIETNAM", "line": "Flora, folklore and provinces shape every world."},
	{"number": "02", "title": "COZY TOY\nDIORAMA", "line": "A warm toy diorama, not a war."},
	{"number": "03", "title": "RUNS\nANYWHERE", "line": "60 FPS on integrated GPUs and phones."},
]

# --------------------------------------------------------------- section 02 ---

const CORE_KICKER := "SECTION 02 · CORE GAMEPLAY"
const CORE_TITLE := "One loop, three scales."
const CORE_BODY := "The Warden has no body on the field. You read the island, choose a seed, and plant."

## The loop at each scale: one row of state chips per time horizon.
const CORE_SCALES := [
	{"label": "SECONDS", "steps": ["CHOOSE", "PLACE", "DEFEND", "GATHER"]},
	{"label": "MINUTES", "steps": ["PREPARE", "WAVES", "RESULT"]},
	{"label": "HOURS", "steps": ["ATLAS", "BATTLE", "UNLOCK"]},
]
const CORE_TENSION := "Grow, or hold? Gems buy more economy, or the defence that survives the next wave."
const CORE_ATLAS_HINT := "Click Saigon to open its board."
const CORE_ATLAS_FIELD_HINT := "Click Night 1 to enter the field."
const CORE_FIELD_ENTER := "Enter the field"

const CORE_ROLES_TITLE := "Every plant shares one body."
const CORE_ROLES_BODY := "The role decides what it does with it."
## `id` is the unit id: the card reads its name, subtitle and model from BalanceDB.
const CORE_ROLES := [
	{"id": "sacred_rice", "role": "PRODUCER", "line": "Grows Rice Gems. Never attacks."},
	{"id": "lotus_shooter", "role": "ATTACKER", "line": "Fires down the cone it faces."},
	{"id": "armored_coconut", "role": "DEFENDER", "line": "A high-HP wall on one tile."},
]
const CORE_ROLES_CONTINUE := "Show me"

const CORE_PLACEMENT_TITLE := "Five checks, one tile."
const CORE_CHECKS := [
	"Inside the lawn",
	"Clear of the Pearl's dais",
	"Tile is free",
	"Can pay the cost",
	"Seed has recharged",
]
const CORE_FACING_HINT := "R / Shift+R · 45°"
const CORE_PLACEMENT_CONTINUE := "Now the spirits"

const CORE_ENEMY_TITLE := "Every spirit walks the same road."
const CORE_STATES := ["SPAWN", "ROUTE", "MARCH", "SEEK", "EAT"]
const CORE_SIEGE := "SIEGE"
## Keyed by HungryGhost.ai_state(); the panel shows the line for the live state.
const CORE_STATE_LINES := {
	"spawn": "The mound cracks. The spirit is untouchable until it rises.",
	"route": "It follows the baked nav path around water to the lawn's edge.",
	"march": "No food in sight. It walks straight for the Pearl.",
	"seek": "A plant entered its notice cone. It sidesteps without breaking stride.",
	"eat": "Inside 1.8 m and 30°, it stops and bites: 12 damage every 0.5 s.",
	"siege": "At the dais wall it holds and hits the Pearl: 7 damage per second.",
	"dead": "Any active state dies at zero health.",
}
const CORE_SUMMON := "Summon a ghost"
const CORE_SUMMON_AGAIN := "Summon again"
const CORE_BACK := "Back to contents"
