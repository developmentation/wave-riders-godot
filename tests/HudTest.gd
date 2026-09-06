extends Node3D
## HUD test: the stub ocean as a backdrop, the HUD on top, fake race data, and a screen cycle
## title → garage → hub → race → results → paused → race … so harness screenshots capture all.
##   node tools/godot-run.mjs --seconds 20 --tag hud --scene res://tests/HudTest.tscn --script "throttle:1,throttle:20" --every 3
## Flags (user args after `--`, or env): --touch / WR_TOUCH=1 forces touch controls,
## --sub / WR_SUB=1 forces submarine mode, --screen=<name> / WR_SCREEN holds one screen.

const HudScene := preload("res://ui/Hud.tscn")
# Switch times (s): title until 1.5, then 3 s per screen; race gets 6 s.
const CYCLE := [["title", 1.6], ["garage", 3.0], ["hub", 3.0], ["race", 6.0], ["results", 3.0], ["paused", 3.0]]

var hud: Hud
var _t := 0.0
var _cycle_i := -1
var _cycle_t := 0.0
var _fixed_screen := ""
var _sub := false
var _fake := {"t": 0.0, "lap": 1, "countdown": 2.2}
var _race_t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_sub = args.has("--sub") or OS.get_environment("WR_SUB") == "1"
	for a in args:
		if a.begins_with("--screen="):
			_fixed_screen = a.substr(9)
	if OS.get_environment("WR_SCREEN") != "":
		_fixed_screen = OS.get_environment("WR_SCREEN")
	hud = HudScene.instantiate()
	add_child(hud)
	hud.set_stars({"lagoon": {"stars": 3, "best": 79.9}, "swell": {"stars": 1, "best": 130.2}, "deep": 2})
	for sig in ["start", "select_boat", "pause", "resume", "camera", "reset", "mute", "exit", "horn", "race_again", "garage", "matte", "fullscreen", "tilt"]:
		hud.connect(sig, _on_signal.bind(sig))
	add_to_group("harness_state")
	if _fixed_screen != "":
		_show(_fixed_screen)
	else:
		_next()


func _on_signal(a = null, b = null, c = null) -> void:
	var args := []
	for v in [a, b, c]:
		if v != null:
			args.append(v)
	var name: String = args.pop_back() if not args.is_empty() else "?"
	print("HUD signal ", name, " ", args)


func _show(n: String) -> void:
	if n == "race":
		_fake = {"t": 0.0, "lap": 1, "countdown": 2.2}
		_race_t = 0.0
	if n == "results":
		hud.show_screen("results", {"place": 2, "time": 83.4, "best": 79.9, "stars": 2})
	else:
		hud.show_screen(n)


func _next() -> void:
	_cycle_i = (_cycle_i + 1) % CYCLE.size()
	_cycle_t = 0.0
	_show(CYCLE[_cycle_i][0])


func _process(dt: float) -> void:
	_t += dt
	if _fixed_screen == "":
		_cycle_t += dt
		if _cycle_t >= CYCLE[_cycle_i][1]:
			_next()
	# Fake race data (mirrors Hud.js devInstall).
	if hud.screen == "race" or hud.screen == "hub":
		if _fake["countdown"] > 0.0:
			_fake["countdown"] -= dt
		else:
			_fake["t"] += dt
			_fake["lap"] = mini(3, 1 + int(_fake["t"] / 8.0))
		_race_t += dt
	var a := _t * 0.35
	# Hold the arrow behind us for a while so WRONG WAY! shows up in the screenshots.
	var dir := atan2(sin(a), cos(a))
	if _race_t > 2.3 and _race_t < 6.5:
		dir = PI - 0.2
	var speed := 55.0 + 45.0 * sin(_t * 0.9)
	if _fake["countdown"] > 0.0:
		speed = 0.0
	hud.update({
		"speed_kmh": speed, "lap": _fake["lap"], "laps": 3, "position": 2, "racers": 4,
		"time": _fake["t"], "countdown": _fake["countdown"], "next_gate_dir": dir,
		"next_gate_pitch": 0.5 * sin(_t * 0.5), "submerged": _sub, "depth": 12.0 + 8.0 * sin(_t * 0.4),
		"state": "racing", "world": "lagoon", "best_time": 79.9, "stars": 2,
	})


func get_harness_state() -> Dictionary:
	return {"test": "hud", "screen": hud.screen, "t": snappedf(_t, 0.1)}
