extends Node2D
## Audio test: every engine type for 2 s (rpm sweep), then every one-shot, with music + weather
## loops underneath. Prints `AUDIO t=<s> rms=<n> peak=<n> voices=<n>` once per second from an
## AudioEffectCapture on Master so silence (rms 0) or clipping (peak ≥ 1) show in the log.
##   node tools/godot-run.mjs --seconds 20 --tag audio --scene res://tests/AudioTest.tscn

const ENGINES := ["jetski", "speedboat", "pontoon", "sailboat", "sub"]
## [time, callable-name, args]
var _events := [
	[10.4, "gate", []], [11.0, "wrong_gate", []], [11.6, "portal", []],
	[13.8, "countdown", [3]], [14.3, "countdown", [2]], [14.8, "countdown", [1]], [15.3, "countdown", [0]],
	[16.0, "finish", [1]], [17.4, "finish", [2]], [18.2, "finish", [4]],
	[19.2, "horn", ["speedboat"]], [19.9, "horn", ["jetski"]], [20.3, "horn", ["pontoon"]], [21.1, "horn", ["sailboat"]], [21.9, "horn", ["sub"]],
	[22.9, "star", []], [23.4, "click", []], [23.6, "splash", [0.8]], [24.0, "lightning", [300.0]],
	[10.5, "mood", ["race"]], [16.0, "mood", ["storm"]], [16.0, "rain", [0.8]], [16.0, "wind", [0.7]],
]
var _t := 0.0
var _last_print := 0.0
var _fired: Array = []
var _label: Label
var _worst_peak := 0.0
var _min_rms := 1.0
var _sum_rms := 0.0
var _n_rms := 0


func _ready() -> void:
	add_to_group("harness_state")
	GameAudio.unlock()
	GameAudio.music(true)
	GameAudio.mood("hub")
	GameAudio.debug_level()  # installs the capture
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 22)
	add_child(_label)
	print("AUDIO test start: engines %s then one-shots" % [ENGINES])


func _process(dt: float) -> void:
	_t += dt
	# Engines: 2 s each with an rpm sweep, then idle-out.
	var ei := int(_t / 2.0)
	var status := ""
	if ei < ENGINES.size():
		var u := fmod(_t, 2.0) / 2.0
		var rpm := 0.15 + 0.95 * (0.5 - 0.5 * cos(u * TAU))
		var load := 1.0 if u < 0.6 else 0.0   # throttle drop → speedboat crackle
		GameAudio.set_engine(ENGINES[ei], rpm, load, rpm * 0.9, 1.0 if ENGINES[ei] != "sub" else 0.3, false)
		status = "engine %s rpm %.2f" % [ENGINES[ei], rpm]
	elif ei == ENGINES.size():
		GameAudio.stop_engine()
		status = "engine off"
	for e in _events:
		if _t >= e[0] and not _fired.has(e):
			_fired.append(e)
			GameAudio.callv(e[1], e[2])
			print("AUDIO t=%.1f %s%s" % [_t, e[1], str(e[2])])
			status = "%s %s" % [e[1], e[2]]
	if _t - _last_print >= 1.0:
		_last_print = _t
		var lv := GameAudio.debug_level()
		var st := GameAudio.get_harness_state()
		print("AUDIO t=%.1f rms=%.4f peak=%.3f voices=%d %s" % [_t, lv["rms"], lv["peak"], st["audio_voices"], status])
		if lv["frames"] > 0:
			_worst_peak = maxf(_worst_peak, lv["peak"])
			_min_rms = minf(_min_rms, lv["rms"])
			_sum_rms += lv["rms"]
			_n_rms += 1
	_label.text = "GameAudio test  t=%.1f\n%s\nvoices=%d" % [_t, status, GameAudio.get_harness_state()["audio_voices"]]


func _exit_tree() -> void:
	if _n_rms > 0:
		print("AUDIO summary: mean rms=%.4f min rms=%.4f worst peak=%.3f" % [_sum_rms / _n_rms, _min_rms, _worst_peak])


func get_harness_state() -> Dictionary:
	return {"test": "audio", "t": snappedf(_t, 0.1)}
