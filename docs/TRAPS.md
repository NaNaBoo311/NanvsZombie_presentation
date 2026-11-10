# Traps

Engine, importer and toolchain behavior that is **invisible at the edit site**. Read this when a
change compiles, runs, and silently does nothing.

**Admission criteria — all four must hold.** Cost >30 min to discover · invisible in the file you
would naturally edit · a property of the engine/importer/toolchain (not of this project's current
content — that is state, and state belongs in the file's own header comment) · states a failure
mode, i.e. you can write "if you do X, Y silently happens".

**Hard cap: 20 entries.** At 21, delete the least useful or promote it into a comment at the
`site:` where it bites. This is a fixed-size cache, not an append log.

---

### global-uniform
`site:` `assets/shaders/*.gdshader`, `project.godot`

Godot registers project-settings `global uniform`s **only at engine startup**. Add one and every
already-open editor and running game spams `Shader uses global parameter 'x', but it was removed at
some point. Material will not display correctly.`, while `global_shader_parameter_set()` fails with
`Condition "!global_shader_uniforms.variables.has(p_name)" is true` — until every process is
restarted. Everyone who pulls must restart too.

Use a plain `uniform` on one shared `ShaderMaterial` and push it from GDScript instead. See
`Landmark81Water.setup_river_material()` / `setup_pond_material()` for the pattern
(shared `.tres` loaded once, `set_shader_parameter("day_blend", t)` during transitions).

### srgb-vs-linear
`site:` `src/maps/landmark_81/Landmark81DayGrade.gd` (`_sunlit_albedo`), any `.glb` material work

`StandardMaterial3D.albedo_color` is **sRGB**. The `.glb` `baseColorFactor` is **linear**. A
threshold derived from one and applied to the other silently no-ops: a darkness cutoff computed
from the linear luminance `0.0135` was applied to the sRGB value `0.119` and produced a 1.01x
"lift" — no error, no warning, just no visible change.

Convert explicitly with `Color.srgb_to_linear()` and never mix the two spaces in one comparison.

### pbr-parity
`site:` any replacement of an imported `StandardMaterial3D` with a custom shader

A hand-written spatial shader will **not** match `StandardMaterial3D`, even with identical albedo,
roughness, metallic, specular and cull mode — measured **~8% darker** on the grass tufts. Albedo
values, instance `COLOR`, `diffuse_burley`/`specular_schlick_ggx` and two-sided normal handling
were each ruled out individually; the gap persisted.

If pixel parity with the existing look matters, keep the `StandardMaterial3D` and split the
geometry instead of writing a shader.

### pixel-diff-invalid
`site:` any screenshot-based regression check

Whole-frame pixel diffs **cannot** detect regressions in this project. Tree wind sway is driven by
`TIME`, so two runs of *identical* code differ in ~21% of pixels (max channel delta 232) — larger
than the diff produced by a real change. A frame diff will appear to "fail" no matter what.

Sample **static patches** instead (open lawn, ground away from the pearl and lanterns); those are
bit-exact run to run. Always take a control run of unchanged code first and diff it against itself
before trusting any comparison. Patches near the pearl, wisps or lanterns still jitter.

### drawcall-load-order
`site:` any draw-call comparison (`--screenshot` telemetry) across a scene restructure

Draw-call counts depend on **resource load order**, not only on what is drawn. Moving the park
into a map scene that loads at runtime changed `--wide-overview` from 179 to 181 draw calls,
with identical primitives and an identical dump of every `VisualInstance3D` (visibility,
shadow flag, MultiMesh counts). Instancing the same map statically in the parent scene put the
daytime count back to 179. A ±1–2 shift with unchanged primitives is load-order batching noise,
not added rendering.

Before calling it an invariant-1 regression, compare primitives and a node dump against a
baseline worktree (`git worktree add`, copy `.godot/` to skip the reimport). Only a primitive or
node-set change means something new is drawn.

### dof-blur-stochastic-dither
`site:` `CameraAttributesPractical`, `dof_blur_far_enabled`, `scaling_3d_scale`

Godot 4's Depth of Field shader uses **stochastic dither jitter (noise sampling)** in blur
transition zones. If `scaling_3d_scale < 1.0` (e.g. 0.67 for iGPU performance) and screen-space AA
(FXAA) is active, the upscaled dither dots get blurred along contrast diagonals, turning into a
visible **diagonal cross-hatching / woven canvas / sandpaper artifact** across all meshes in the
transition zone (even on perfectly flat, untextured surfaces).

Disable DoF blur passes entirely (`CameraAttributesPractical` removed or `dof_blur_*_enabled = false`)
whenever low internal resolution scaling is active.

### shadow-acne-planar-stripes
`site:` `DirectionalLight3D`, `shadow_normal_bias`, `shadow_bias`

When a `DirectionalLight3D` with large cascades (e.g. 65–95m) shines at a grazing angle onto
slanted low-poly planar geometry (such as cottage porch awnings or deck steps), low `shadow_normal_bias`
(default `1.0`) produces self-shadow depth oscillation across the shadow-map texel grid. This
manifests as visible, high-contrast **diagonal corduroy stripes / venetian blinds** on untextured
surfaces. Setting `shadow_normal_bias = 4.0` and `shadow_bias = 0.05` eliminates the acne while
keeping contact shadows sharp.



### day-blend-dead-path
`site:` `src/environment/DayNightCycle.gd` (`set_day_blend` callers), any `set_day_blend()` stub

A shader declaring a `day_blend` uniform, a `set_day_blend()` that only stores the
value, and a caller invoking it every transition — with no path between them and no
error anywhere. Nothing fails; the grade simply never happens (the tree canopy
rendered identical at noon and midnight while all three suggested otherwise).

After writing the caller, the stub and the consumer, run one transition and confirm
a material actually changes (e.g. print one albedo before/after, or screenshot the
same preset day vs night). Neighbours the `#global-uniform` entry.

### subviewport-container-flip
`site:` any `SubViewportContainer` + `SubViewport` icon preview in `src/ui/`

Setting `render_target_update_mode = UPDATE_ONCE` on a viewport inside a
**visible** `SubViewportContainer` does not stick: the container leaves it in
UPDATE_ALWAYS, so every "render once" avatar re-renders every frame (measured
13-53 draws per icon) with no error and no warning. Under a hidden ancestor it
reads back DISABLED, which looks like the pattern works — until the overlay
opens and the cost lands mid-game (SeedSelector 183 -> 348 draws on TAB).

Bake static icons once into ImageTextures via a hidden staging viewport (see
`IconBaker`), which has no container to flip the mode, and display them in
TextureRects. Live viewports are only for things that actually animate (the HUD
gem, re-armed to UPDATE_ONCE at 10 Hz by design).

### renderer-override-flag
`site:` `project.godot`, any run command with a rendering-driver flag

The --rendering-driver vulkan flag silently overrides the declared
rendering_method in project.godot, so the documented dev command (Forward+),
the project setting and an exported build can run three different renderers
with no warning — and every measurement belongs to whichever renderer actually
booted, not the one you assumed. Glow, fog and shadow behaviour all differ
between Mobile and Forward+.

After changing either side, re-run the bench on the target iGPU and confirm the
booted renderer in the log before trusting any number.

### three-half-cylinder-side
`site:` `tools/asset_generator/**` — `CylinderGeometry(…, thetaStart, thetaLength)`

three.js places cylinder vertices at `x = r·sin θ, z = r·cos θ`, so a `(0, π)` half-cylinder
lies on **+x**, not +z. If you rotate it `ry = π` expecting the +z half, it lands on **−x**
and nothing errors: the railing drawn with cos/sin angles follows one half while the floor
covers the other. `ry = -π/2` puts it on +z. Check a `computeBoundingBox()` before pushing it
(see `tools/asset_generator/generators/maps/landmark_81/marina_club.mjs`).

### multimesh-aabb-draw-calls
`site:` any `MultiMeshInstance3D` batch (`src/environment/ForestMultiMesh.gd`, `PropMultiMesh.gd`)

Godot culls a MultiMesh by **one AABB covering all of its instances**. If you add even a few
instances far from the rest, the whole batch enters every view and shadow cascade that touches the
new corner: +10 draw calls in the gameplay view, from trees the camera never sees. The count of
instances doesn't matter; the extent of the batch does.

The single-frame `[Telemetry] Draw Calls` line from `--screenshot` also varies between identical
runs (±2, occasionally +28). Measure with `-- --perf-test` instead: 30-frame medians per view, day
and night, against the map's `data/maps/<map_id>/perf_baseline.json`.

### postimport-vertex-colors
`site:` any model exported through `bakeToVertexColors` (`tools/asset_generator/common.mjs`)

Godot never enables `vertex_color_use_as_albedo` on its own: a freshly baked model
imports with its `COLOR_0` intact on the mesh **and** the flag off on the material, so it
renders flat white with no error and no warning — while the export-side checks (attribute
exists, tri budget, mesh count) all look green. The only signal is the washed-out render.

Assign the post-import script in the model's .glb.import file before reimporting
(the import_script/path setting, pointing at `src/core/PostImportVertexColors.gd`).
It flips the flag only on surfaces that carry colors, so emissive meshes are
untouched.

### class-name-static-in-script-mode
`site:` any `tools/*.gd` harness run as `godot --headless -s tools/<file>.gd`

A script started with `-s` runs as a `SceneTree` **before** the project's autoloads and
script class cache are set up for it. A `class_name`'s static functions then resolve to a
bare `GDScript` and the call fails with `Invalid call. Nonexistent function 'run' in base
'GDScript'` — for a function that plainly exists in the file you are reading. Autoloads in
the same harness are `null`, so a `load()` of a data file that reads one is empty.

If you need a harness to call project code, put the call behind the flag the game already
handles (`-- --round-test` and friends reach the same functions through `DioramaWorld`),
or `preload` the script and hope the editor has resaved the class cache — which only works
once the class has been used in-game. Both in-game flag paths are the supported route.

### frame-counted-clock
`site:` any in-engine test that times something (`src/battle/NavTest.gd`)

A test that advances its clock by a fixed step per `physics_frame` measures **frames, not
seconds**: `clock += 0.1` every tick reports 6x the real time at 60 Hz and 1x at 10 Hz, and
every number it prints — time to arrival, time-to-lane, anything compared against a target
— is wrong by the frame rate, silently. The symptom is a value that is plausible but
consistently ~6x too large, so it reads as "the thing under test is slow" and sends you
measuring frame rates, physics ticks and time scales instead of the test.

Derive the clock from the wall clock (`Time.get_ticks_msec()` against a start stamp) and keep
the fixed step only for the polling interval. If a test's number is only ever compared
against another number it produced, the bug is invisible.

### canvas-draw-calls
`site:` `src/ui/SeedBank.gd`, any HUD built from repeated cards

`--perf-test` and the `--screenshot` telemetry read `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, which
**counts 2D canvas draws too**. Measured on Godot 4.7: only rectangles (`draw_rect`, TextureRect,
glyphs) batch. Every `StyleBoxFlat`, `draw_polygon`, `draw_circle` and `draw_mesh` is one draw each,
even with one shared style or inside one canvas item, so 10 panel cards cost 10 draws. A label
outline adds a draw per label, and so does a second font file; with a bitmap font so does a
second size. A map's `--perf-test` blames the map while every 3D scene is untouched.

Before suspecting the map, run once with `-- --no-hud`. Keep repeated UI one batch per layer: merge
shapes into one triangle array (`HudCanvas`), share one icon atlas, and use one MSDF font, which is
one batch at every size. `--perf-test` runs in sandbox, so use `-- --hud-demo` for wave and touch.

### dark-sky-white-blobs
`site:` `assets/shaders/InkOutline.gdshader`, any full-screen or screen-reading shader

GLSL `pow()` of a negative number is NaN, and the HDR screen buffer can hold slightly
negative colour values in very dark pixels (a dark sky horizon and ground gradient, dark
clouds under a dark preset). A post pass that runs `pow(screen_colour, ...)` turns them into
NaN: the pixel shows black with glow off, and the glow pass spreads it into huge white blobs
over the sky and skyline. It looks like a lighting-preset problem, so it gets "fixed" by
brightening the preset and comes back at the next camera angle.

Clamp before any `pow`, `log` or `sqrt` on screen colour (`pow(max(c, vec3(0.0)), ...)`,
as InkOutline does). To check, count pure-white pixels in a capture that looks at the sky
(`--riverfront-zoom`, `--wide-overview`).

### headless-multimesh
`site:` `src/maps/NavGrid.gd` (`bake`), `src/maps/RouteClearance.gd`, any code that reads a `MultiMesh` back

Under `--headless` the dummy renderer keeps no instance buffer: `MultiMesh.get_instance_transform(i)`
returns the origin for every instance. A scene sweep or bake that walks the map's trees, grass and props
then puts them all at (0, 0, 0): no error, the result just never sees a tree, so a nav grid baked or a
route swept headless is clear of every tree, and every tree is then walked through in the real game.

Run those with a window (`DISPLAY=:0`, no `--headless`). `--nav-bake` and `--nav-test` refuse to run headless.
`--round-test` under `--headless` still reaches `RouteClearance`, but only buildings and other real nodes are swept.

### mobile-renderer-screen-buffers
`site:` `assets/shaders/*.gdshader` — any `hint_*` screen buffer

`hint_normal_roughness_texture` exists **only in Forward+**. A shader sampling it compiles and
renders on desktop; on a phone (`rendering_method.mobile="mobile"`) the material fails outright —
`SHADER ERROR: 'hint_normal_roughness_texture' is only available when using the Forward+
renderer` — and the mesh or full-screen quad draws with the fallback material, with nothing else
in the log naming the shader. `hint_screen_texture` and `hint_depth_texture` are the only screen
buffers both renderers share; derive normals from the depth buffer instead.

A normal `--screenshot` run cannot catch this. Check shaders with
`--rendering-method mobile -- --screenshot` before shipping.

### signal-default-params
`site:` any `signal` declaration, e.g. `src/core/EventBus.gd`

Adding a trailing optional parameter to a GDScript signal to keep old emits working is
impossible: `signal x(a: int, player_id: int = 0)` fails at load with `Parse Error: Signal
parameters cannot have a default value`, and an autoload that fails to parse takes the
whole game with it. Every `.emit()` and every `.connect()` handler must pass the new
argument; a handler with the old arity fails only when that signal fires, and a handler
that accepts it but ignores it silently acts for the wrong owner.

Change the declaration and grep every emit/connect site in the same edit.
