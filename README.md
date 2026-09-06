# Wave Riders — Godot 4 edition

Kids' boat racing (and submarines) on a compute-shader FFT ocean. This is the Godot 4.7 rebuild of
the web game [wave-riders](https://github.com/developmentation/wave-riders), aimed at the highest
water quality and frame rate on a PC. Everything the web game has is here: nine boats plus a ferry
and a submarine, six surface worlds (harbour hub, lagoon, swell, storm, 50-foot Titan Swell, the
Perfect Storm with rogue waves), the Deep Run canyon for the sub, portals, races with AI, touch /
keyboard / gamepad controls, synthesized audio, stars.

## Play

Double-click **`play.bat`** (full screen, picks the discrete GPU automatically; `play.bat --editor`
opens the project in the Godot editor). Requires Godot 4.7.2 at `C:\dev\games\godot\`; download the
Windows 64-bit build from https://godotengine.org/download/windows/ and unzip it there if missing.

| Control | Keyboard | Gamepad |
| --- | --- | --- |
| Throttle / brake | W / S or ↑ / ↓ | A / RT, LT |
| Steer | A / D or ← / → | left stick |
| Boost / horn | Space / H | B |
| Submarine dive / rise | Q / E | LB / RB |
| Camera / reset boat / pause | C / R / Esc | X / Y / Start |

Quality presets (`scripts/Quality.gd`): `low`, `medium` (60 fps on an Intel UHD), `high` (default on a
discrete GPU), `ultra` (1024² FFT, SDFGI, volumetric fog). Force one with
`Godot_v4.7.2-stable_win64.exe --path . -- --quality=ultra`. Other dev switches after `--`:
`--skip=<lagoon|swell|storm|giant|tempest|deep|hub>`, `--boat=<id>`, `--autopilot=1`, `--matte=1`.

## Develop and test

```
node tools/godot-run.mjs --seconds 12 --tag demo --extra "--skip=lagoon" --script "throttle:5,steer_right:2,throttle:5" --every 4
```
Runs the game from the command line with the `Harness` autoload driving input, prints `PERF fps=…`
lines and errors, and saves screenshots to `tools/shots/<tag>/`. Add `--gpu 1` to test on the
integrated GPU, `--scene res://tests/<Name>.tscn` for a module test scene. Headless checks:
`godot --headless --path . -s tests/PhysicsSim.gd`, `-s tests/SubSim.gd`, `-s tools/check-worlds.gd`.
After adding a `class_name` script run `godot --headless --path . --import` once.

Design and module contracts: `docs/GODOT-PORT.md`. Per-module status, APIs and measurements:
`docs/STATUS.md`.

## Export a standalone build

1. In the editor: **Editor → Manage Export Templates → Download and Install** (once).
2. **Project → Export…**, add a **Windows Desktop** preset, set the path to `build/WaveRiders.exe`,
   Export Project. Ship the `.exe` and `.pck` together.
3. Command line: `Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/WaveRiders.exe`
   (after the preset exists in `export_presets.cfg`).

The ocean is a `RenderingDevice` compute pipeline (Forward+), so the Web (Compatibility renderer)
export is not supported; the web game linked above is the browser version.

## Credits

Ocean simulation based on GodotOceanWaves by Ethan Truong (MIT); boat models from Kenney's
Watercraft Kit (CC0); wildlife, worlds and game logic ported from the web game. See `CREDITS.md`.
