# Wave Riders — Godot 4.7 port: spec and module contracts

Goal: rebuild the web game (C:\dev\games\boats, see its `docs/GAME-DESIGN.md` for the design,
worlds, boats, racing rules and HUD — read it first) in Godot 4.7 (Forward+), with **much better
water** and **higher framerate**. Everything the web game has must exist here: 9 boats + submarine,
6 worlds (hub, lagoon, swell, storm, giant, tempest) + the Deep Run canyon, portals, races with AI,
hoops for subs, touch/keyboard/gamepad controls, HUD, synthesized audio, stars.

## Ground rules

- Godot 4.7.2 at `C:\dev\games\godot\Godot_v4.7.2-stable_win64_console.exe`. Project root is this
  folder. GDScript, typed, 2-space tabs → **use tabs** (Godot default). No C#.
- Test from the CLI, never by hand: `node tools/godot-run.mjs --seconds 10 --script "throttle:5,steer_right:2" --tag mytest --scene res://tests/MyTest.tscn`.
  It saves screenshots to `tools/shots/<tag>/`, prints `PERF fps=…` lines and any ERROR lines
  (exit 1 on errors). Every module ships a `tests/<Module>Test.tscn` scene that exercises it alone.
  Nodes in group `harness_state` with `get_harness_state() -> Dictionary` get their state logged.
- Performance target: **60 fps at 1280×720 on the Intel UHD in this machine** with the `medium`
  quality preset, and the `high`/`ultra` presets meant for discrete GPUs (bigger FFT, denser
  clipmap, SDFGI/volumetrics). Report measured fps for every module in isolation.
- Licences: GodotOceanWaves (MIT, Ethan Truong) may be ported/vendored with attribution in
  `CREDITS.md`. Kenney models are CC0 (copy from `C:\dev\games\boats\public\models\kenney-watercraft`).
  No other external assets. No downloaded audio.
- Godot 4.7 gotchas already found: `RenderingDevice` validates push-constant sizes exactly (do not
  pad to 16 bytes) and uniform writability must match the shader (`readonly`/`writeonly` images
  need matching `RDUniform`s). Run with the console binary to see errors.

## Node tree (target)

```
Main (Node3D, scripts/Main.gd)             game flow state machine: title→garage→hub→race→results
├─ Ocean (ocean/Ocean.tscn)                 FFT sea, weather, CPU height sampling
├─ Sky (WorldEnvironment + DirectionalLight3D, scripts/SkyWeather.gd)  driven by Ocean weather
├─ World (worlds/World.gd, built per world id)   islands, shore foam, portals, gates/hoops
├─ Boats (Node3D)                           player + AI: boats/Boat.tscn, boats/Submarine.tscn
├─ FollowCamera (Camera3D, scripts/FollowCamera.gd)
├─ Race (race/Race.gd or race/SubRace.gd)   spawned per race world
├─ HUD (CanvasLayer, ui/Hud.tscn)           screens + touch controls
└─ GameAudio (autoload)                     synthesized sound
```

## Contracts (GDScript)

```gdscript
# ocean/Ocean.gd  (class_name Ocean, extends Node3D)
signal weather_changed
func set_weather(w: Dictionary, immediate := false) -> void   # keys: wind_speed, wind_dir_deg, swell_hs, swell_period, choppiness,
                                                              #   foam, water_color: Color, sun_elev_deg, sun_azimuth_deg, cloud_cover, rain, fog, lightning_rate
func sample(x: float, z: float) -> Vector3       # (height, dh/dx, dh/dz) at world xz, from the CPU-side grid; O(1)
func height_at(x: float, z: float) -> float
func surface_velocity_y(x: float, z: float) -> float  # dh/dt for relative-velocity damping
func set_focus(x: float, z: float) -> void       # centre of the fine sampling grid (the player)
func set_quality(preset: String) -> void         # "low" | "medium" | "high" | "ultra"
var significant_wave_height: float

# boats/BoatPhysics.gd  (class_name BoatPhysics, extends Node3D)  — port of src/game/BoatPhysics.js
var hull: Dictionary            # from boats/Hulls.gd HULLS (same numbers as the web game)
var throttle: float; var steer: float; var boost: float; var dive: float
var velocity: Vector3; var heading: float; var speed_kmh: float; var submersion: float
var airborne: bool; var slap_impulse: float; var wake_strength: float; var is_sub: bool
var ground_fn: Callable         # (x, z) -> seabed/land height
func set_pose(x, y, z, heading) ; func reset() ; func rescue()
# steering convention: +steer turns the bow to the boat's visual right (screen right when following).

# boats/Boats.gd  static func build_visual(id: String, color_index: int) -> Node3D  (with `update(dt, body)`)
#   ids: jetski speedboat sailboat pontoon fishing tug airboat towboat rowboat sub

# worlds/Worlds.gd  const WORLDS := { hub, lagoon, swell, storm, giant, tempest, deep }  # same schema as the web Worlds.js
# worlds/World.gd   func build(id) ; func height_at(x, z) ; func terrain_at(x, z) ; var def ; func update(dt)
# worlds/Portals.gd func build(defs) ; func test(body) -> String (dest or "") ; func transition(callable) -> await
# race/Race.gd      same surface as the web Race.js: setup()/start()/update(dt)/dispose(), state, countdown, time, laps,
#                   player {lap,next_gate,position,finished,finish_time,progress}, standings, accepts_input, next_gate_dir(), signals gate/lap/finish/countdown
# race/SubRace.gd   3D hoops + AI submarines, adds next_gate_pitch()
# ui/Hud.gd         show(screen, data := {}) ; update(frame: Dictionary) ; signals: start, select_boat(id, color), pause, resume, camera, reset, mute, exit, horn, race_again, garage, matte
#                   touch controls write Controls.virtual = {steer, throttle, brake, boost, dive, active}
# scripts/Controls.gd (autoload "Controls") throttle/steer/boost/dive/actions from input map + Hud.virtual + gamepad; +steer = right
# audio/GameAudio.gd (autoload) unlock() set_engine(type, rpm, load, speed, submersion) splash(i) gate() portal() countdown(n) finish(place) horn(type) music(on) mood(m) mute(b)
```

## Quality presets (`scripts/Quality.gd`)

| preset | FFT | cascades | clipmap | shadows | extras |
| --- | --- | --- | --- | --- | --- |
| low | 128 | 2 | low | off | no SSR |
| medium (Intel UHD target) | 256 | 3 | medium | 1 cascade | SSR off, glow on |
| high | 512 | 3 | high | 2 cascades | SSR, SDFGI off |
| ultra | 1024 | 3 | high | 4 cascades | SSR, volumetric fog, SDFGI |

## Deliverable per module

Working scene + test scene, zero ERROR lines in `godot-run`, screenshots reviewed against the web
game's look (tools/shots in the web project and docs/reference there), measured fps, and a short
section in `docs/STATUS.md` (create/append) listing API, known issues and the integration steps.
