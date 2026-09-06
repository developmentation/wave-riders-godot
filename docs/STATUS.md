# Wave Riders (Godot) — module status

Per-module API, integration steps, screenshots and known issues (see docs/GODOT-PORT.md).

## Submarine + The Deep Run (`boats/SubPhysics.gd`, `boats/Submarine.tscn`, `boats/SubmarineVisual.gd`, `worlds/SubmarineWorld.gd`, `worlds/deep/*`, `shaders/underwater_*`)

Port of the web `src/game/Submarine.js` (SubPhysics + toy sub visual) and `src/game/SubmarineWorld.js`
(analytic canyon seabed, hoop course, kelp, marine snow, underwater look). Same numbers as the web:
6 m / 4000 kg hull, 30 km/h submerged / 20 surfaced, planes +-20 deg, yaw cap 0.75 rad/s, <= 8 deg bank,
1/120 s substeps, terrain probes with look-ahead so a canyon wall at 30 km/h is a bump, never a tunnel.

### API

```gdscript
# boats/SubPhysics.gd  (class_name SubPhysics, extends Node3D)  — writes its own transform once per update()
var hull: Dictionary            # SubPhysics.SUB_HULL {length 6, width 2.2, mass 4000, radius 0.95, max_speed, surface_speed, thrust, max_yaw, max_pitch, is_sub}
var throttle, steer, dive, boost: float      # throttle -0.5..1; +steer = bow to the visual right; +dive = up
var velocity, angular, forward, right, up: Vector3
var heading, pitch, roll, depth, submersion, ballast, speed, speed_kmh, surface_y, scrape: float
var airborne, slap_impulse, wake_strength, beached_time, contacts, is_sub = true   # BoatPhysics-compatible
var ground_fn: Callable          # (x, z) -> seabed y   (SubmarineWorld.height_at)
var ceiling_fn: Callable         # (x, z) -> sea surface y  (Ocean.height_at); invalid = flat 0
@export var auto_update := true  # update(dt) from _physics_process; turn off to drive it from Main
func update(dt) ; set_pose(x, y, z, heading) ; reset() ; rescue() ; get_harness_state()
# frame: local +Z forward, heading = atan2(forward.x, forward.z) (same as the web and the world defs)

# boats/Submarine.tscn:  Submarine (SubPhysics) / Visual (SubmarineVisual)
# boats/SubmarineVisual.gd  (class_name SubmarineVisual, extends Node3D)
@export var color_index := 0     # 0 yellow, 1 orange, 2 mint (helmets red / navy / purple); set before add_child
@export var auto_update := true  # drives update(dt, parent) itself when the parent is a SubPhysics
var triangles: int               # 2384 per sub (budget 2500)
func build(color_index) ; update(dt, body)   # prop spin, planes, rudder, kid lean, headlights (SpotLight3D x2 +
                                             # emissive discs + additive cones fading in with submersion), bubble trail (GPUParticles3D, clamped below surface_y)

# worlds/SubmarineWorld.gd  (class_name SubmarineWorld, extends Node3D)
func build("deep")               # 130 chunked ArrayMesh tiles + details + kelp MultiMesh + snow; ~350 ms, 55.5k tris
var def: Dictionary              # web schema: id, name, underwater = true, weather {key, patch (Ocean.set_weather keys)},
                                 #   fog {color, density, absorb}, start {x,y,z,heading}, gates [{x,y,z,heading,width}] (13 hoops),
                                 #   laps 1, portals [{x 40, z -70, heading PI, dest "hub"}], bounds 900, path
var seabed: DeepSeabed           # the analytic seabed (worlds/deep/DeepSeabed.gd); height_at is exact for the mesh, ~10-30 us
func height_at(x, z) ; terrain_at(x, z)
func update(dt, camera)          # distance-culls tiles (260 m under / 420 m surfaced), keeps the snow box on the camera
func set_submerged(on: bool, depth := 0.0, camera: Camera3D = null)   # call EVERY frame with the camera's depth below ocean.height_at
func dispose()
var underwater_environment: Environment ; var submerged: bool ; @export var sky_irradiance: Color
```

`set_submerged` does not touch the scene's WorldEnvironment: it sets `camera.environment` (a per-camera
override) to an underwater Environment duplicated from the surface one (tonemap/glow kept) with the
`shaders/underwater_sky.gdshader` sky (water colour, brightened ceiling), exponential fog (density 0.022/m,
`fog_sky_affect` 0 so the sky *is* the fog at infinity), flat ambient, and no SSR/SDFGI/volumetrics. The fog,
ambient, sky and snow colours are `fog.color * sky_irradiance * exp(-absorb * camera_depth)`, so the column
goes turquoise -> deep blue with depth. Seabed/kelp/sub materials attenuate their albedo by the same per-metre
absorption of *their* depth (`shaders/underwater_seabed|kelp|prop.gdshader`; the sub uses ~1/3 of it so the toy
stays yellow at hoop depth like the web). Godot Environment colours and `source_color` uniforms are sRGB — the
world converts its linear values with `linear_to_srgb()` on assignment.

### Integration steps (Main.gd / Race / Camera)

1. `var world := SubmarineWorld.new(); add_child(world); world.build("deep")`; apply `world.def.weather.patch`
   to the Ocean; `world.def.start` is at the surface (y = 0, heading 0 = +Z), portal to the hub at (40, -70).
2. Spawn subs with `preload("res://boats/Submarine.tscn").instantiate()`; set `Visual.color_index` before
   `add_child`, then `sub.ground_fn = world.height_at`, `sub.ceiling_fn = ocean.height_at`,
   `sub.set_pose(x, ocean.height_at(x, z) - 0.5, z, heading)`. Controls: `sub.dive = Controls.dive` (+up).
3. Every frame: `world.set_submerged(cam_depth > 0.3, cam_depth, camera)` where
   `cam_depth = ocean.height_at(cam.x, cam.z) - cam.y`, then `world.update(dt, camera)`. Also usable in the
   surface worlds when the camera dips under (pass the same `def.fog` look). Call `world.dispose()` on leave.
4. FollowCamera `sub` mode (the web rule, implemented locally in `tests/SubTest.gd`): 12 m behind (xz), 4 m
   above, look 6 m ahead; if `body.depth > 3` clamp the lens to `surface - 1.5`, else to `surface + 1.5`;
   lerp `1 - exp(-5 dt)`; also keep it above `world.height_at + 2`.
5. SubRace: gates are `def.gates` (hoop centre + heading + diameter `width`); the test scene's emissive
   TorusMesh rings show the placement (`_build_hoops`), and its AI (`_process`) is the simplest working
   hoop follower: `steer = clamp(-heading_err * 1.6)`, `dive = clamp((gate.y - y) * 0.15)`, advance when
   inside `width/2` or past the gate plane.
6. Audio hooks: `sub.scrape` (0..1 terrain contact), `sub.submersion`, `sub.wake_strength`.
7. After adding `class_name` scripts run `godot --headless --path . --import` once so the class cache knows them
   (the CLI harness does not scan scripts); the test scripts `preload` their scenes/scripts to be safe.

### Tests / verification

- `godot --headless --path . --script res://tests/SubSim.gd` — port of `tools/physics-sim.mjs sub`, all 13
  checks pass: floats at y -0.51 (hull top out), 20.8 km/h surfaced, dives to 30 m in 11.3 s at -20.0 deg,
  holds 33.6 m +-0.00 at 28.7 km/h, full-lock yaw 0.75 rad/s with 6.6 deg max roll, 0.47 rad/s on the spot,
  surfaces in 13.7 s and floats again, wall test max x 37.44 (< 40, hull half length 3), slope ride, rescue.
  `update()` costs 33 us per 60 Hz step with a flat seabed.
- `node tools/godot-run.mjs --seconds 16 --tag sub --scene res://tests/SubTest.tscn --script "throttle:4,dive_down:5,throttle:7" --every 3`
  — zero ERROR lines. Player dives to 15 m and holds it at 28.7 km/h; both AI subs take the hoops; a 45 s run
  (`--tag sub-long`, `throttle:4,dive_down:6,throttle:35`) has the player bump the rock-table edge at 18 m,
  slow to 14.6 km/h and ride over it (no tunnelling) while the AI reach hoop 4 at 41.5 m.
- Screenshots: `tools/shots/sub/e003.png` surfaced (hull top above the swell), `t009.png` diving with the
  two AI subs and headlight cones, `e012.png` through hoop 1, `final.png` over the rock table with the
  canyon ahead; `tools/shots/sub-long/e027.png` canyon wall contact, `final.png` the cut through the table
  with kelp on the rim. Compared with the web `tools/shots/deeprun2-t018.png` / `deeptouch-t008.png`:
  mid-blue water column, visible walls at ~60-100 m, green hoops, kelp, yellow toy sub with cones.
- Performance (this machine, 1280x720, Forward+, stub ocean, 3 subs = 6 spot lights, ~210 draw calls):
  median 640 fps / min 537 in the 16 s run; 430 / 239 over 45 s (the dip is the environment swap + snow
  restart at the first submerge). World build 350 ms, 55,474 seabed+kelp triangles, sub 2,384.

### Known issues / notes

- The StubOcean is opaque: between 1 and 3 m of depth the camera stays above the surface and the sub is hidden
  (web rule). The real Ocean's underside/transparency will fix the look; the rule can be revisited in FollowCamera.
- Underwater look is per-camera (`Camera3D.environment`); if Main renders with several cameras, pass each one.
  The surface WorldEnvironment is untouched; the sun (DirectionalLight3D) is not dimmed under water — the
  depth absorption in the seabed/kelp/prop shaders provides the darkening instead.
- Volumetric fog is off (Intel UHD target); enabling `underwater_environment.volumetric_fog_enabled` on
  high/ultra is a one-liner once Quality.gd exists.
- Hoop clearance above the seabed (m, per gate): 6.5 2.7 3.5 4.0 4.3 2.9 3.7 4.3 4.9 6.6 4.7 16.3 18.7 — same
  course as the web; the canyon hoops are 14 m wide, mouth/exit 16 m, the rest 18 m.
- `DeepSeabed.height_at` is GDScript (~10-30 us); 3 subs x 120 Hz x ~10 probes is ~3-4 % of a frame budget.
  If more AI subs are needed, sample it into a cached grid for the AI.

## Worlds, islands, shore foam, portals (`worlds/Worlds.gd`, `worlds/World.gd`, `worlds/IslandField.gd`, `worlds/IslandBuilder.gd`, `worlds/ShoreFoam.gd`, `worlds/Portals.gd`, `shaders/portal_*`, `shaders/shore_foam.gdshader`, `tools/check-worlds.gd`, `tests/WorldTest.tscn`)

Port of the web `src/game/Worlds.js`, `Islands.js`, `ShoreFoam.js`, `Portals.js` and `tools/check-worlds.mjs`.
The six surface worlds (hub, lagoon, swell, storm, giant, tempest) carry the same numbers as the web: weather
preset + patch, water scatter/absorb, islands, piers, start, gates (the web's equal-arc-length loop samples,
pasted from the running web module), laps, portals, bounds, probe_span, gate_spacing, exposure, events. The island
noise/hash arithmetic replicates the web's `Math.imul`/`>>>` bit for bit, so grid sizes, triangle counts, heights
(to 1e-5) and the mulberry32 RNG match the web exactly; the gate layouts validated there stay valid here.

### API

```gdscript
# worlds/Worlds.gd  (class_name Worlds, static)
const WORLDS := { hub, lagoon, swell, storm, giant, tempest }    # web schema, snake_case keys
#   def: id, name, icon, weather {key, patch {wind_speed, swell_hs, swell_period, choppiness, rain, storm, fog, spray,
#        lightning_rate, sun_elevation (rad), sun_azimuth (rad), sun_intensity, turbidity, cloud_coverage, cloud_density,
#        cloud_bottom, cloud_top, cloud_anvil, foam_strength, star_intensity, gustiness, spread}},
#        water {scatter[3], absorb[3]}, exposure, islands [{x, z, radius, height, seed, shape cone|plateau|crescent, palms,
#        hut, lighthouse, warp, detail, shelf, arc {r, a0, a1, thick}, scenery}], piers [{x, z, heading, length, width}],
#        start {x, z, heading}, gates [{x, z, heading, width}], gate_spacing, lap_length, laps,
#        portals [{x, z, heading, dest}], probe_span, bounds, events {rogue, spout, lightning}
const CONDITIONS := { clear, trade, golden, overcast, squall, storm, night }   # base presets (web Sandbox.js)
const EXTERNAL_DESTS := ["deep"]                # portal destinations owned by another module
static func world_weather(def) -> Dictionary    # preset + patch (+ wind_angle 0.6, swell_angle 1.1, water_*, exposure)
static func ocean_weather(def) -> Dictionary    # mapped to Ocean.set_weather keys: wind_speed, wind_dir_deg, swell_dir_deg,
                                                #   swell_hs, swell_period, choppiness, foam, water_color, sun_elev_deg,
                                                #   sun_azimuth_deg, cloud_cover, rain, fog, lightning_rate (+ extras:
                                                #   gustiness, spread, storm, spray, sun_intensity, turbidity, cloud_density,
                                                #   cloud_bottom/top/anvil, star_intensity, exposure, water_scatter, water_absorb)
static func water_color(def) -> Color           # scatter * 1.6 (hue of the water body; the FFT ocean may use the raw coefficients)
static func apply_world_weather(ocean, def, immediate := false)
static func update_world_events(ocean, def, dt, focus := Vector3.INF)   # rogue waves / waterspouts / lightning bursts
#   calls ocean.spawn_rogue({x, z, angle, height, radius, wavelength, speed}), ocean.spawn_waterspout(x, z, strength),
#   ocean.lightning_burst(n, {cloud_base, radius, window}) through has_method checks (the stub has none: timers still run);
#   focus = player position (defaults to the current camera). static var event_rate (dev speed-up), reset_world_events(id)

# worlds/World.gd  (class_name World, extends Node3D)
var ocean: Node                  # set before build() (else group "ocean" / sibling "Ocean")
var def: Dictionary ; var id ; var fields: Array[IslandField] ; var portals: Portals ; var shore_foam: ShoreFoam
var triangles, palms, build_ms ; var material: StandardMaterial3D (one vertex-colour material for terrain, props, palms)
var auto_update := true          # update(dt) from _process; set false to drive it from Main
func build(id) ; update(dt) ; dispose() ; get_harness_state()
func height_at(x, z) -> float    # collision field for BoatPhysics.ground_fn: seabed in the water, +8 m soft wall past the
                                 #   shoreline (IslandField.collision_height). 2.4-3.4 us/call averaged over a course.
func terrain_at(x, z, exact := false) -> float   # the surface the mesh shows; exact = web's full analytic profile beyond
                                                 #   the sampled grids (deep seabed only; validator/tools use it)
# gates / hoops: World builds no gate visuals; Race reads world.def.gates / def.start (heading = atan2(dx, dz), +Z = 0)

# worlds/Portals.gd  (class_name Portals, extends Node3D)   world.portals is built by World.build
const PORTAL_TINTS := { hub, lagoon, swell, storm, giant, tempest, deep: {tint, deep, label} }   # web colours
var ocean ; var transitioning ; var last_dest
func build(defs) ; update(dt)            # 12 m torus ring (emissive), swirling liquid-light disc, tapered light column,
                                         #   glow pool, floating rotating icon (sun/wave/storm/giant wave/tempest/submarine),
                                         #   160 vertex-shader sparkles; bobs on ocean.height_at (damped)
func test(body) -> String                # dest when body crossed the ring plane inside RING_RADIUS this frame (once; 3 s
                                         #   re-entry cooldown); body = Node3D (global_position) or anything with .position
func transition(cb: Callable, dest := "") -> void   # await it: CanvasLayer iris white-out in the dest tint 0.6 s,
                                         #   `await cb.call()` (plain or coroutine), dissolve 0.8 s
func dispose(full := true)

# worlds/ShoreFoam.gd  (class_name ShoreFoam, extends MeshInstance3D)   world.shore_foam
func build(world, ocean) ; update(dt)    # one mesh + one ShaderMaterial for every island (96 waterline rays per island,
                                         #   4 rows, 2-11+ m band); islands within 350 m of the camera re-lay their
                                         #   vertices on max(sand, ocean.height_at) every 0.2 s (staggered), far ones every 2 s
var vertices, triangles, islands

# worlds/IslandField.gd (class_name IslandField)   heightfield + noise; IslandBuilder.gd = meshes (Soup, palms, props)
static island_profile(def, x, z, noise := true) ; collision_height(h) ; fields_height(fields, x, z) ; pier_height(p, x, z)
func sample(x, z, exact := true) ; slope(x, z, e) ; to_world(u, v) ; to_param(x, z) ; var grid, nu, nv, tris
```

### Integration steps (Main.gd)

1. `var world := World.new(); world.ocean = ocean; add_child(world); world.build(id)` (2.5-3.5 s for the lagoon,
   1-2 s for the others, on this machine's CPU: GDScript heightfield sampling; see known issues).
2. `Worlds.apply_world_weather(ocean, world.def, immediate)` on every world load (the Sky module should read the same
   `Worlds.ocean_weather(def)` record: sun_elev_deg/sun_azimuth_deg/cloud_cover/fog/rain/exposure/star_intensity).
   If the ocean has a probe/focus span API, pass `world.def.get("probe_span", 300)`.
3. Every boat: `body.ground_fn = world.height_at`. Player spawn: `def.start` at `ocean.height_at(x, z) + 0.3`.
4. Every frame: `world.update(dt)` (or leave `auto_update`), `Worlds.update_world_events(ocean, world.def, dt, player_pos)`,
   then `var dest := world.portals.test(player)`; if non-empty:
   `await world.portals.transition(func(): await load_world(dest), dest)` where load_world disposes the old World,
   builds the new one, re-applies weather and re-parks the boats. Portals keep firing once per crossing with a 3 s
   cooldown so the boat can coast out of the far side after the teleport.
5. Race: `world.def.gates` (x, z, heading, width), `def.start`, `def.laps`, `def.lap_length`; hub has no gates.
   `def.portals[i].dest == "deep"` hands over to SubmarineWorld.
6. `world.dispose()` (or `queue_free`) on leave; `Worlds.reset_world_events(id)` is called for you.
7. Layout check after editing any def: `godot --headless --path . -s tools/check-worlds.gd [world] [--no-maps] [--strict]`
   (exit 1 on failure; maps in tools/shots/map-<world>.png).

### Tests / verification

`node tools/godot-run.mjs --seconds 10 --tag world-<id> --scene res://tests/WorldTest.tscn --script "throttle:10" --every 2.5 --extra "--world=<id>"`
(`--extra` is a new pass-through in godot-run.mjs; the scene also takes `--at=x,z`, `--radius=`, `--nofoam`). Zero
ERROR lines for all six worlds. The scene applies the world weather to the StubOcean, maps sun/sky/fog roughly (the Sky
module owns the real look), draws emissive gate posts + width bars + index nubs and yellow start posts, orbits the start
(or `--at`) at 25 m sweeping the horizon, drives a fake body through the first portal (hit test + transition are logged)
and prints `[WorldTest] height_at: N us per call`. Screenshots: `tools/shots/world-{hub,lagoon,swell,storm,giant,tempest}/`,
`tools/shots/world-hub-portal/` (portal close-up), `tools/shots/world-lagoon-close/` (island + surf close-up).

| world | islands | terrain+prop+palm tris | palms | foam verts | build ms | fps (1280x720, stub ocean, dev GPU) |
| --- | --- | --- | --- | --- | --- | --- |
| hub | 5 | 57 977 | 104 | 1916 | 2312 | median 557 |
| lagoon | 6 | 67 610 | 112 | 2304 | 2556-3447 | median 448-704 |
| swell | 2 | 24 992 | 52 | 768 | 1006-1071 | median 552-667 |
| storm | 3 | 33 758 | 54 | 1480 | 1580-1687 | median 575 |
| giant | 3 | 32 001 | 55 | 1152 | 1179-1257 | median 423-615 |
| tempest | 3 | 33 980 | 54 | 1480 | 1703-1754 | median 320-463 |

Per island: <= 8000 terrain triangles (6529-7962), props (lighthouse/hut/pier) one extra mesh per world, palms 3
MultiMeshInstance3D per world (3 variants, ~360 tris each). Draw calls: ~35 (lagoon) to ~62 (hub, 6 portals x 6 parts).
`tools/check-worlds.gd`: all worlds pass (14 s headless); one advisory: swell gate 6 sits over the west island's
-2.8 m shelf (the web's own rule is -1.5 m; `--strict` turns the -4 m keel-clearance rule into a failure).

Compared with the web frames (tools/shots fhub-t003, gate2-t007, storm3-t008, fgiant-t014, abp-start): islands read
as the same chunky toy cones/plateaus/crescents with lime grass, darker crowns, rock on steep faces, red-white
lighthouse, hut, pier and leaning palms; giant's spire matches fgiant; portals match abp-start (swirl disc, coloured
rim, icon, sparkles, pool) and are readable at 135 m in the hub.

### Known issues

- Build time is GDScript-bound (~350 ms per island for the 74x74 analytic sampling + mesh). Options if it matters:
  sample the grids on WorkerThreadPool, or bake the six worlds' grids to a .res at export.
- The StubOcean is opaque, so the wet sand shelf (0 to -0.1 m, ~10 m wide on a flat beach) reads as open water and the
  traced surf line looks detached from the dry sand; the web sea is transparent there and shows the sand through it. The
  real ocean should do the same (or the foam WATERLINE constant can be raised toward 0.3 m for an opaque sea).
- Shore foam uses a procedural noise stand-in for the engine's foam texture (thresholded and thinned to keep the swash a
  line); swap in the ocean module's foam texture if it ships one.
- Portal glow brightness is tuned for the test scene's ACES tonemap + glow (`brightness` uniform in
  `shaders/portal_common.gdshaderinc`, 0.32); revisit once the Sky/exposure pipeline lands. `fog_density` on the portal
  materials is 0 until the Sky module drives it.
- `height_at` is 2.4-3.4 us per call on average (GDScript; the brief asked for <= 1 us). Beyond an island's sampled
  grid the runtime path drops the noise terms (seabed at -5..-50 m only); `terrain_at(x, z, true)` is the exact web value.
- Tempest/storm test-scene lighting is a placeholder (night darkening capped so the frames stay legible); lightning,
  rain and the dark-purple look belong to the Sky module. World events fire but the stub ocean has no spawn hooks.
- `Worlds.WORLDS` has the six surface worlds; `deep` is `worlds/SubmarineWorld.gd` (portal dest accepted via EXTERNAL_DESTS).

## HUD + touch controls + synthesized audio (`ui/Hud.tscn`, `ui/Hud.gd`, `ui/Hud*.gd`, `audio/GameAudio.gd`, `tests/HudTest.tscn`, `tests/AudioTest.tscn`)

Port of the web `src/game/Hud.js` + `game.css` (every screen, the race readouts, the touch controls) and
`src/game/Audio.js` (all sounds synthesized, no audio files). Pure Control nodes drawn with CanvasItem
primitives — no textures: gradient pills/cards/badges (`HudPanel`), vector icons (`HudIcon`, the web's SVG
set), candy buttons (`HudButton`), boat cards (`HudCard`), readout badges (`HudBadge`), the km/h dial
(`HudSpeedo`, custom `_draw` with needle). Fonts: Godot's default font emboldened (`FontVariation`) with
the system emoji font as fallback (boat/world emoji render in colour on Windows/macOS/Android), white
text with a dark outline + shadow everywhere (`HudTheme.style_label`). Layout reproduces the CSS
`clamp()` metrics in *CSS pixels* (window px / screen scale) then maps to canvas units, so 1280x720 is
pixel-for-pixel the web layout, 1024x600 tablets get the "short" tweaks, and windows under 520 CSS px
tall get the phone layout (no wheel, pause+home only, small dial, depth chip on top). Works with the
project's `canvas_items` + `expand` stretch from 900x400 up to 4K.

### API

```gdscript
# ui/Hud.gd  (class_name Hud, extends CanvasLayer, layer 10)  — instance res://ui/Hud.tscn
func show_screen(screen: String, data := {})   # "title" | "garage" | "hub" | "race" | "results" | "paused"
       # results data: {place|position, time, best|best_time, stars}; anything missing falls back to the last frame
func update(frame: Dictionary)                 # every frame (cheap: only touches nodes on change)
func set_boats(list)                           # Array of {id,label,icon,description,colors,stats{speed,turning,steady}} or Dictionary by id;
                                               #   colours may be Color, "#rrggbb" or 0xRRGGBB ints; fields merge over Hud.DEFAULT_BOATS
func set_stars(map)                            # {world: 3} or {world: {stars, best}}  -> hub panel stars
func toast(text, final := false)               # big centre pop text ("LAP 2!" is automatic from update())
func set_muted(b) ; set_matte(on) ; set_tilt(on)
var screen, touch, muted, selected_boat, color_index, virtual   # virtual = {steer, throttle, brake, boost, dive, active}
signal start(info: Dictionary)                 # {from: "title"|"garage", boat: String, color: int}
signal select_boat(id: String, color: int)
signal pause ; resume ; camera ; reset ; mute(muted: bool) ; exit ; horn ; race_again ; garage ; matte ; fullscreen ; tilt(enabled: bool)
```

`frame` fields (snake_case of the web frameData): `speed_kmh`, `lap`, `laps`, `position`, `racers`, `time` (s),
`countdown` (s, > 0 shows 3·2·1 then "GO!"), `next_gate_dir` (rad, relative, +right; omit/NAN hides the
arrow; |dir| > 0.75 turns it yellow + pulsing; |dir| > 2.35 at > 4 km/h for 2 s shows WRONG WAY!),
`next_gate_pitch` (rad, +up; in sub mode shows "▲ rise / ▼ dive" under the arrow when |pitch| > 0.3),
`submerged` (bool → sub mode: depth gauge, ▲◀▶▼ d-pad, Q/E key hints), `depth` (m), `state`, `world`,
`stars`, `best_time`. A lap increase after lap 1 toasts "LAP n!" / "FINAL LAP!" automatically.

**`show()` vs `show_screen()`:** CanvasLayer already has a native `show()` and GDScript 4.7 refuses to
overload it (the call binds to the native method even with `@warning_ignore`), so the contract's
`show(screen, data)` is `show_screen(screen, data)`. Everything else matches the contract.

Touch controls appear only when `DisplayServer.is_touchscreen_available()`, the user arg `--touch`, or
env `WR_TOUCH=1`. They are driven from `_input` with `InputEventScreenTouch/Drag` (per-finger dictionary,
a control stays held while any finger is on it, the wheel tracks angle deltas and springs back at
e^-9t, ±100° = full steer) and, on desktop with `--touch`, the mouse as finger -1. Every frame while the
race/hub screen is up they call `Controls.set_virtual({steer, throttle, brake, boost, dive, active})`
(falls back to setting `Controls.virtual` if `set_virtual` is missing; nothing if `/root/Controls` is
absent). Tilt (pause menu, touch only) feeds `Controls.set_tilt(accelerometer.x / 4.5)` and
`clear_tilt()` — untested on a device. Menu buttons are regular `_gui_input` controls (mouse or
Godot's touch→mouse emulation). Keyboard: Enter/Space on title = play, Enter in garage = GO!, ←/→ cycle
boats, Enter on results = race again. Fullscreen toggles `DisplayServer.window_set_mode`.

```gdscript
# audio/GameAudio.gd  (autoload "GameAudio", process_mode ALWAYS)
GameAudio.unlock()                                          # no-op on desktop (starts the generator); web parity
GameAudio.set_engine(type, rpm, load, speed_frac, submersion := 1.0, airborne := false)  # every frame; stops itself 0.5 s after the last call
GameAudio.drive_engine(type, body)                          # derives rpm/load/speed from a BoatPhysics-like body (throttle, speed_kmh, hull.max_speed|maxSpeed, airborne, boost, submersion)
GameAudio.stop_engine()
GameAudio.splash(i) ; gate() ; wrong_gate() ; portal() ; countdown(n) ; finish(place) ; horn(type) ; star() ; click() ; lightning(distance_m)
GameAudio.rain(level) ; wind(level)                         # continuous 0..1, smoothed
GameAudio.music(on) ; mood("hub" | "race" | "storm")        # (set_music_mood alias) pentatonic arp + bass + kick/hat, I-vi-ii-V / i-III-IV-v
GameAudio.mute(b) ; set_volume(v)                           # smoothed master
GameAudio.debug_level() -> {rms, peak, frames}              # Master-bus AudioEffectCapture since the last call (installed lazily)
```

Engine types map boat ids → rigs: jetski/airboat = 2-stroke buzz (saw + square octave, fast LP),
speedboat/towboat = V8 (two detuned saws with the half-rate chug baked into a 2-cycle table, square
subharmonic louder at idle, 17 Hz pulsed-noise exhaust crackle on throttle drops), pontoon/fishing/tug =
outboard putter, sailboat/rowboat = wind in the rigging + random sail flaps, sub = warm sine-stack hum
with 2.5 Hz tremolo. Spray = band-passed noise following speed (thins when airborne/submerged). Horns per
type incl. the sub's sonar ping (1.25 kHz + echo). Thunder is delayed by distance/340 s.

Implementation: one `AudioStreamGenerator` (24 kHz, 0.15 s buffer) filled in `_process` in 256-sample
blocks from precomputed band-limited wavetables (saw/square/tri at 3 partial counts chosen by pitch, the
engine tables, 64 k white noise + a pulsed copy) and RBJ biquads (GDScript, ~20 M voice-samples/s
measured, so a typical mix of ~12 voices costs ≈0.3 ms per frame); one-shots use a 40-voice pool with
attack/hold/exponential-release envelopes, pitch glides and one-pole low-passes; the music scheduler is
sample-accurate (step boundaries inside the block). Master = volume × soft peak limiter (0.85 ceiling,
fast attack / slow release) + soft clip. Pause: the autoload keeps running (`PROCESS_MODE_ALWAYS`);
on `NOTIFICATION_PAUSED` the engine/spray duck to silence and the music drops to 50 %, restored on unpause.
No allocations in the render loop (the one-shot API allocates only when a sound is triggered).

### Integration steps (Main.gd)

1. `var hud: Hud = preload("res://ui/Hud.tscn").instantiate(); add_child(hud)` (any parent — it is a
   CanvasLayer). Optionally `hud.set_boats(catalog)` (ids/labels/icons/colours from `boats/Boats.gd`;
   colours as Color or 0xRRGGBB) and `hud.set_stars(saved_stars)`.
2. State machine: `hud.show_screen("title")` → on `start` (`info.from == "title"`) → `show_screen("garage")` →
   on `start` (`from == "garage"`, `info.boat`, `info.color`) spawn the player and `show_screen("hub")`;
   entering a race world → `show_screen("race")`; `Race.finish` → `show_screen("results", {place, time, best,
   stars})`; `pause` → `get_tree().paused = true; show_screen("paused")`; `resume` → unpause +
   `show_screen(prev)`; `exit` → hub; `race_again` → restart; `garage` → garage; `camera`/`reset`/`horn` →
   forward to FollowCamera/BoatPhysics/GameAudio; `mute(m)` → `GameAudio.mute(m)`; `matte` → water look toggle
   then `hud.set_matte(on)`. Also call `hud.set_muted()` if the game restores a saved mute state.
3. Every frame: `hud.update({speed_kmh = boat.speed_kmh, lap = race.player.lap, laps = race.laps, position =
   race.player.position, racers = race.standings.size(), time = race.time, countdown = race.countdown,
   next_gate_dir = race.next_gate_dir(), next_gate_pitch = sub_race.next_gate_pitch(), submerged = boat.is_sub
   and boat.submersion > 0.5, depth = boat.depth, state = race.state, world = world.def.id})`. In the hub pass
   only `speed_kmh`/`submerged`/`depth` (the race readouts are hidden there).
4. `Controls.gd` already exposes `set_virtual()`; the HUD finds `/root/Controls` by itself.
5. Audio per frame: `GameAudio.drive_engine(boat_id, boat.body)` (or `set_engine(...)`), `GameAudio.rain(w.rain)`,
   `GameAudio.wind(w.wind_speed / 25.0)`; `GameAudio.splash(boat.slap_impulse)` when it jumps; on race signals
   `gate()`, `wrong_gate()`, `countdown(n)`, `finish(place)`; on portals `portal()`; `music(true)` after the
   title, `mood("race")` in races, `mood("storm")` in storm/tempest, `mood("hub")` in the hub; `lightning(d)`
   from the ocean's lightning events; `click()` on HUD button presses (connect the HUD signals).
6. After adding `class_name` scripts run `godot --headless --path . --import` once (the CLI harness does not
   rebuild the class cache); the UI scripts reference each other by class name.

### Tests / verification

- `node tools/godot-run.mjs --seconds 20 --tag hud --scene res://tests/HudTest.tscn --script "throttle:1,throttle:20" --every 3`
  cycles title (1.6 s) → garage → hub → race (6 s: countdown, arrow, WRONG WAY!) → results → paused → race…
  over the stub ocean with fake frame data (`tools/shots/hud/`: t001 title, e003 garage, e006 hub, e009 race
  countdown, e012 WRONG WAY!, e015 results, e018 paused, final race). 0 errors; fps median 420 / min 297
  (stub ocean + HUD; the HUD alone is a handful of draw calls — layout runs only on change).
- Phone/touch: `WR_TOUCH=1 node tools/godot-run.mjs --seconds 20 --tag hud-phone --res 900x400 --scene res://tests/HudTest.tscn --script "throttle:1,throttle:20" --every 3`
  (`tools/shots/hud-phone/`): compact layout with ◀ ▶, GO/STOP pedals, horn/boost, pause+home, small dial.
- Submarine: `WR_TOUCH=1 WR_SUB=1 WR_SCREEN=race node tools/godot-run.mjs --seconds 6 --tag hud-sub --scene res://tests/HudTest.tscn --script "throttle:3,throttle:6"`
  (`tools/shots/hud-sub/t003.png`): wheel + ▲◀▶▼ d-pad, depth chip beside the dial, pitch hint.
  Flags also work as user args (`-- --touch --sub --screen=results`) when running Godot directly.
- `node tools/godot-run.mjs --seconds 26 --tag audio --scene res://tests/AudioTest.tscn --script "throttle:26"`:
  each engine 2 s with an rpm sweep, then gate, wrong gate, portal, countdown 3-2-1-GO, finish 1/2/4, five
  horns, star, click, splash, thunder, with music (hub → race → storm) and rain/wind. Prints
  `AUDIO t=<s> rms=<n> peak=<n> voices=<n>` per second; last run: mean rms 0.074, min 0.040, worst peak 0.58
  (no silence, no clipping), 0 errors, fps ~940 in the empty scene (audio cost is negligible).

### Known issues / notes

- `show()` is `show_screen()` (native-method clash, see above).
- Text is drawn with Godot's default Open Sans (emboldened), not Baloo 2/Nunito — same weight and outline
  treatment, slightly less rounded. Emoji come from the OS font (Segoe UI Emoji on Windows); on a system
  without a colour emoji font the boat/world icons fall back to monochrome glyphs or boxes.
- "RIDERS" is flat yellow with a light top highlight, not the CSS gradient text; the results star / card
  pop-ins, toasts, countdown, confetti, bobbing and pulsing are re-timed by hand from the CSS keyframes.
- The garage card strip scrolls by button/keyboard/mouse-wheel; touch drag-scrolling of the strip is not
  implemented (the cards themselves are tappable).
- Tilt steering and multi-touch are only verified with the harness (mouse as one finger); real-device
  behaviour of `Input.get_accelerometer()` orientation may need a sign flip in `Hud._process`.
- Audio: engine pitch/gain targets are smoothed per 256-sample block (10.7 ms), fine for engines; the
  fastest one-shot attacks (2–4 ms) are exact. Everything is mono (same signal both channels).


## Race / SubRace / Main game flow (`race/Race.gd`, `race/SubRace.gd`, `race/DevCourse.gd`, `race/banner.gdshader`, `race/stubs/*`, `scripts/Main.gd`, `scenes/Main.tscn`, `scripts/SaveData.gd`, `tests/RaceTest.tscn`, `tests/race-check.gd`)

Ported from the web `src/game/Race.js`, `SubRace.js` and `Game.js`: same gate-plane maths, AI personalities and
start grid, rubber band, stuck rescue, standings order, countdown timing, stars rule, boat-vs-boat collision
spheres, soft world bounds and beached rescue.

### API

```gdscript
# race/Race.gd (class_name Race, extends Node3D) — race/SubRace.gd (class_name SubRace, extends Race)
var race := Race.new().configure(game, world_def, {"laps": 3, "ai_count": 3, "rubber_band": true, "ai_assist": true})
add_child(race); race.setup(); race.start()      # setup() spawns the AI through game.spawn_boat / game.spawn_sub
race.update(dt)                                   # gates, laps, standings, AI, visuals — Main calls it after the boats step
race.dispose()                                    # removes the AI boats through game.remove_boat, frees itself
race.state       # "setup" | "countdown" | "racing" | "finished" | "disposed"
race.countdown   # float seconds (HUD shows ceil);  race.time;  race.laps;  race.accepts_input;  race.course_length
race.player      # Dictionary {lap, next_gate, position, finished, finish_time, progress, ...} (empty without a player)
race.standings   # [{boat, name, lap, gate, position, progress, finished, finish_time, gates_total, ai, speed_kmh, stuck_nudges, x, y, z}]
race.next_gate_dir() -> float (rad, +right);  race.next_gate_pos() -> Vector3;  SubRace.next_gate_pitch() -> float (rad, +up)
race.gate_test(gate, body) -> bool;  race.autopilot (the AI drives the player too — harness / screenshots)
signal gate_passed(boat, index);  signal lap(boat, n);  signal finished(boat, place, time);  signal countdown_tick(n)   # 3, 2, 1, 0 = GO
```

The contract's `countdown` callback is the signal `countdown_tick`: GDScript forbids a signal and a property
(`countdown`, which the contract requires as the float) sharing one name.

`game` (Main) is duck-typed: `boats: Array`, `player: Node`, `ocean` (height_at), `world` (height_at),
`spawn_boat(id, x, z, heading, color) -> Node`, `spawn_sub(x, y, z, heading, color) -> Node`, `remove_boat(node)`.
Bodies are duck-typed too: `heading`, `velocity`, `hull` (Dictionary, snake_case or camelCase keys), `angular`,
`throttle / steer / boost / dive`, `set_pose`, optional `ground_fn`, `ceiling_fn`, `pitch`, `surface_y`.

Visuals: striped buoy pillars (CylinderMesh + generated ImageTexture), a generated half-torus arch (SurfaceTool,
UV along the arc, checkered on the start/finish gate), SphereMesh lamp caps, pole + fluttering banner
(`race/banner.gdshader`, displaces along the gate's travel axis), StandardMaterial3D emission per state
(next = green glow, after = white, far = grey, passed = dim). Hoops: TorusMesh + 10 sparkle beads turning on the
next two. Arrow: BoxMesh slab + flattened 4-sided cone, 4/6 m over the player, nose down 20 degrees; the sub
arrow points in 3D.

```gdscript
# scripts/Main.gd (root of scenes/Main.tscn) — the Game.js state machine
state: boot | title | garage | hub | race | results | paused;  world_id;  boats;  player;  race
spawn_boat(id, x, z, heading, color) / spawn_sub(x, y, z, heading, color) / remove_boat(b)
load_world(id, immediate) / enter_world(id) (await, portal white-out) / enter_hub() / show_title() / show_garage() / select_boat(id, color)
pause() / resume(silent)     # get_tree().paused; HUD, Main and the Harness run on PROCESS_MODE_ALWAYS
set_matte(on) -> ocean.set_matte(on) when present;  toggle_mute();  get_harness_state() (group harness_state: world/state/boat/pos/speed/race+standings)
exports: start_world, start_boat, force_stubs, stubs ("ocean,boats,world,hud,camera,controls"), ai_rubber_band, ai_count, autopilot, laps_override
user args: --skip=<world|title> --boat=<id> --rubber=0 --matte=1 --autopilot=1 --laps=N --stubs=<list|all>
# Under the CLI harness with no --skip the game opens in the hub (the web smoke's ?skip=title); without a real HUD it also opens in the hub (as Game.js).
# scripts/SaveData.gd: load_stars() / save_stars() / record_result(stars, world, place, time) -> user://stars.json;
#                      load_prefs() / save_prefs() -> user://prefs.json (boat, matte, muted)
```

### Integration status

| module | how Main uses it | status |
| --- | --- | --- |
| `ocean/Ocean.tscn` | instantiated only if every `[ext_resource]` exists (else `StubOcean`); `set_weather`, `height_at`, `set_focus`, `set_matte` if present; the scene's default WorldEnvironment/Sun are dropped when the ocean brings its own | real ocean runs (fft 256, medium) |
| `worlds/World.gd` + `Worlds.gd` | `world.ocean = ocean; add_child; build(id)`, `auto_update = false` (Main ticks it), `Worlds.apply_world_weather` / `ocean_weather` (wind for sailboats), `Worlds.update_world_events`, rings via `world.portals.test(player)` | hub builds in ~2.3 s, portals fire |
| `worlds/SubmarineWorld.gd` | `build("deep")`, `update(dt, camera)`, `set_submerged(on, depth, camera)` every frame the camera is under water | Deep Run races with SubRace (13 hoops, 3 AI subs) |
| `worlds/Portals.gd` | one persistent instance for `transition(cb, dest)` (a world's own portals are freed by the switch they animate); an own instance only for dev-course defs | white-out works |
| `boats/BoatPhysics.gd` | `configure(id, color, ocean, ground)`, `simulate = false`, Main writes `wind` then calls `advance(dt)` (web order: boats, collisions, race, camera); visual via `auto_visual` | real hulls race |
| `boats/SubPhysics.gd` + `Submarine.tscn` | `auto_update = false`, Main calls `update(dt)`, `ceiling_fn = ocean.height_at` | ok |
| `boats/Wake.gd` | one `Wake` child per body exposing `sea_hs()` (stubs get none) | ok |
| `scripts/FollowCamera.gd` | `follow(b)`, `orbit {angle, dist, height, speed, fov}`, `mode`, `next_view`, `impulse`; self-updates | ok |
| `ui/Hud.tscn` | `show_screen`, `update(frame)`, `toast`, `set_boats(Boats.CATALOG.values())`, `set_stars`, `set_muted`, `set_matte`; signals start(info) / select_boat / pause / resume / camera / reset / mute(m) / horn / exit / race_again / garage / matte / fullscreen | ok; title and garage also advance on throttle or Enter |
| `Controls` autoload | `throttle / steer / boost / dive`, `has("pause" | "camera" | "reset" | "horn" | "mute" | "confirm")`; fallback reads the input map with rising-edge actions | ok |
| `GameAudio` autoload | duck-typed: countdown(n) gate() star() finish(place) horn(type) music(on) mood(m) mute(b) splash(i) portal() set_engine(type, rpm, load, speed, submersion) suspend() resume() click() | called when present |

Fallbacks in `race/stubs/`: `StubBoat` / `StubSub` (BoatPhysics / SubPhysics surface on the Gerstner stub ocean),
`StubWorld` (bare sea; `race/DevCourse.gd` lays the web dev loop and hoop spiral for `--skip=devcourse|devspiral`,
and for any race id while `worlds/` is absent), `StubFollowCamera`, `StubHud` (text overlay). `tests/RaceTest.tscn`
runs Main with `stubs = "ocean,world,hud,controls"`, `autopilot = true`, `ai_rubber_band = false`: real BoatPhysics
and FollowCamera on the stub ocean and the flat 8-gate loop.

### Verification (1280x720, vsync off, this machine)

- `node tools/godot-run.mjs --seconds 30 --tag race --scene res://tests/RaceTest.tscn --script "throttle:30"` — 0 error lines,
  median ~165 fps (4 real hulls + wakes on the stub ocean). Screenshots in `tools/shots/race/`: the autopilot player through a
  striped-pillar arch, yellow arrow above the boat, next gate glowing green — same composition as the web `final2-t020.png`.
- 92 s acceptance (`--seconds 92`): `RACECHECK RESULT PASS ai=3` — Jet Ski 11 gates, Pontoon 7, Sailboat 6, 0 stuck rescues.
  The sailboat sits right at the >= 6 threshold (the web's point-of-sail thrust; upwind legs run ~30 km/h).
  Headless: `godot --headless --path . res://tests/RaceTest.tscn -- --seconds=92` (grep `RACECHECK RESULT`).
- `--laps=1` run: `racing` -> `finished` -> `results`, `user://stars.json` = `{"devcourse": {"best": 54.9, "stars": 3}}`;
  a harness `pause` action freezes race time (state `paused`, time held) and a second one resumes.
- `node tools/godot-run.mjs --seconds 20 --tag main --script "throttle:8,steer_right:2,throttle:10"` — boots with every module present
  (ocean, world, boats, wake, camera, HUD, portals, controls, audio), 0 error lines, ~275 fps steady in the hub (`tools/shots/main/`).
- `godot --path . -- --skip=deep --autopilot=1 --seconds=25 --perf --shots=...` — SubRace on the real Deep Run, 0 error lines,
  ~270 fps (`tools/shots/deep/t025.png`: green hoop, 3D arrow, sub, HUD depth badge).

### Known issues / notes

- The harness presses actions from a post-draw callback, which `Input.is_action_just_pressed` misses on the next frame; Main's
  fallback input tracks rising edges itself (the Controls autoload does its own edge detection).
- Exit warning "1 ObjectDB instance was leaked" is an `AudioStreamGeneratorPlayback` held by the GameAudio autoload (audio owner).
- `ui/Hud` logged "Invalid polygon data, triangulation failed" (a handful of lines at boot) in one earlier run; not seen since.
- `tools/godot-run.mjs` has no passthrough for user args; runs that need `--skip` / `--autopilot` / `--laps` call the Godot binary
  directly with the same arguments plus `--shots=<dir> --seconds=N --script=... --perf`.
- Boat-vs-boat separation is applied as a one-frame velocity correction because BoatPhysics owns its transform; the impulse
  exchange and yaw kicks are the web's.
- Gate arches follow the sea height with the web's 6/s lerp, sampled every third frame except the next gate.
