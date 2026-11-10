extends RefCounted

# Fixed camera views for --screenshot captures and --perf-test. One row per view:
# the command-line flags that select it, the screenshot file it saves to, and the
# rig pose (orbit centre `pos`, `arm` length, `pitch`, `yaw`, optional `fov`).
# First matching row wins. Adding a view = adding a row; nothing else changes.

const DEFAULT_SHOT := "screenshot_diorama.png"

const PRESETS: Array[Dictionary] = [
	{"flags": ["--wide-overview"], "shot": "screenshot_wide_overview.png", "pos": Vector3(0.0, 30.0, 60.0), "arm": 110.0, "pitch": -28.0, "yaw": 0.0},
	{"flags": ["--west-zoom-back"], "shot": "screenshot_west_zoom_back.png", "pos": Vector3(-80.0, 2.0, -24.0), "arm": 70.0, "pitch": -35.0, "yaw": 180.0},
	{"flags": ["--west-zoom"], "shot": "screenshot_west_zoom.png", "pos": Vector3(-80.0, 2.0, -24.0), "arm": 70.0, "pitch": -35.0, "yaw": 0.0},
	{"flags": ["--north-zoom-back"], "shot": "screenshot_north_zoom_back.png", "pos": Vector3(0.0, 2.0, -80.0), "arm": 95.0, "pitch": -32.0, "yaw": 180.0},
	{"flags": ["--north-zoom"], "shot": "screenshot_north_zoom.png", "pos": Vector3(0.0, 2.0, -80.0), "arm": 95.0, "pitch": -32.0, "yaw": 0.0},
	{"flags": ["--east-zoom-back"], "shot": "screenshot_east_zoom_back.png", "pos": Vector3(86.0, 2.0, 5.0), "arm": 80.0, "pitch": -35.0, "yaw": 180.0},
	{"flags": ["--east-zoom"], "shot": "screenshot_east_zoom.png", "pos": Vector3(86.0, 2.0, 5.0), "arm": 80.0, "pitch": -35.0, "yaw": 0.0},
	{"flags": ["--park-overview"], "shot": "screenshot_park_overview.png", "pos": Vector3(4.0, 14.0, 34.0), "arm": 42.0, "pitch": -24.0, "yaw": -6.0},
	{"flags": ["--skyline-panorama"], "shot": "screenshot_skyline_panorama.png", "pos": Vector3(0.0, 9.5, 24.0), "arm": 42.0, "pitch": -14.0, "yaw": 0.0},
	{"flags": ["--skyline-zoom"], "shot": "screenshot_skyline.png", "pos": Vector3(0.0, 6.0, 14.0), "arm": 32.0, "pitch": -12.0, "yaw": 0.0},
	{"flags": ["--marina-zoom"], "shot": "screenshot_marina.png", "pos": Vector3(-3.0, 4.0, 14.0), "arm": 16.0, "pitch": -14.0, "yaw": 175.0},
	{"flags": ["--landmark-zoom"], "shot": "screenshot_landmark.png", "pos": Vector3(0.0, 4.0, -8.0), "arm": 26.0, "pitch": -9.0, "yaw": 0.0},
	{"flags": ["--house-zoom"], "shot": "screenshot_house_zoom.png", "pos": Vector3(-10.0, 1.8, -26.5), "arm": 8.8, "pitch": -16.0, "yaw": -15.0},
	{"flags": ["--outskirts-west"], "shot": "screenshot_outskirts_west.png", "pos": Vector3(-75.0, 16.0, 48.0), "arm": 40.0, "pitch": -16.0, "yaw": 85.0},
	{"flags": ["--outskirts-east"], "shot": "screenshot_outskirts_east.png", "pos": Vector3(75.0, 16.0, 48.0), "arm": 40.0, "pitch": -16.0, "yaw": -85.0},
	{"flags": ["--temple-zoom"], "shot": "screenshot_temple_zoom.png", "pos": Vector3(36.0, 2.0, -97.0), "arm": 34.0, "pitch": -22.0, "yaw": 35.0},
	{"flags": ["--east-bank-zoom"], "shot": "screenshot_east_bank_zoom.png", "pos": Vector3(72.0, 3.0, 10.0), "arm": 50.0, "pitch": -22.0, "yaw": -70.0},
	{"flags": ["--chua-cau-zoom"], "shot": "screenshot_chua_cau_zoom.png", "pos": Vector3(-79.0, 1.5, -57.0), "arm": 24.0, "pitch": -20.0, "yaw": 25.0},
	{"flags": ["--night-market-zoom"], "shot": "screenshot_night_market_zoom.png", "pos": Vector3(-20.0, 1.5, 54.0), "arm": 26.0, "pitch": -18.0, "yaw": 180.0},
	{"flags": ["--riverfront-zoom"], "shot": "screenshot_riverfront_zoom.png", "pos": Vector3(0.0, 2.0, 22.0), "arm": 44.0, "pitch": -16.0, "yaw": 0.0},
	{"flags": ["--storybook-axonometric", "--axonometric"], "shot": "screenshot_storybook_axonometric.png", "pos": Vector3(0.0, 3.0, 0.0), "arm": 86.0, "pitch": -34.0, "yaw": -36.0, "fov": 26.0},
]


## The first preset any of `args` selects, or {} for the gameplay camera.
static func find(args: PackedStringArray) -> Dictionary:
	for preset in PRESETS:
		for flag in preset["flags"]:
			if flag in args:
				return preset
	return {}


## The preset whose flags include `flag` ({} if none).
static func by_flag(flag: String) -> Dictionary:
	for preset in PRESETS:
		if flag in preset["flags"]:
			return preset
	return {}


## Snaps the camera rig to `preset` with no easing (current = target).
static func apply(cam: Node, preset: Dictionary) -> void:
	var arm: float = preset["arm"]
	var pitch: float = preset["pitch"]
	var yaw: float = preset["yaw"]
	cam.set_target(null)
	cam.global_position = preset["pos"]
	cam.arm_length = arm
	cam.pitch_degrees = pitch
	cam.yaw_degrees = yaw
	cam._target_arm_length = arm
	cam._target_pitch = pitch
	cam._target_yaw = yaw
	cam.rotation_degrees.x = pitch
	cam.rotation_degrees.y = yaw
	var spring := cam.get_node_or_null("SpringArm3D") as SpringArm3D
	if spring:
		spring.spring_length = arm
	if preset.has("fov") and cam.camera:
		cam.camera.fov = preset["fov"]
