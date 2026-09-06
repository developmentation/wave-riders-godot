extends Node
## Command-line test harness (autoload). Mirrors tools/game-smoke.mjs from the web build.
##
## Run:  godot --path . -- --shots=C:/out --script=throttle:5,steer_right:2 --seconds=12 --perf
## Every user arg after `--` is parsed here. The harness:
##   * simulates input actions per an "action:seconds,action:seconds" script (throttle stays held),
##   * saves a PNG at the end of every script step and every `--every=N` seconds,
##   * prints `PERF t=<s> fps=<n> frame_ms=<ms> ...` once per second when --perf is set,
##   * prints `STATE <json>` from any node in group "harness_state" that has get_harness_state(),
##   * quits when --seconds elapses. Without user args it does nothing.

var _active := false
var _shots_dir := ""
var _steps: Array = []
var _step_i := -1
var _step_t := 0.0
var _held: Dictionary = {}
var _t := 0.0
var _seconds := 0.0
var _perf := false
var _every := 0.0
var _last_every := 0.0
var _last_perf := -1.0
var _busy := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return
	_active = true
	for a in args:
		var kv := a.split("=", true, 1)
		var key := kv[0]
		var val := kv[1] if kv.size() > 1 else ""
		match key:
			"--shots":
				_shots_dir = val
			"--seconds":
				_seconds = float(val)
			"--perf":
				_perf = true
			"--every":
				_every = float(val)
			"--script":
				for part in val.split(",", false):
					var p := part.split(":")
					_steps.append({"action": p[0], "dur": float(p[1]) if p.size() > 1 else 1.0})
	if _shots_dir != "":
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	print("HARNESS start seconds=%s steps=%d shots=%s" % [_seconds, _steps.size(), _shots_dir])
	_next_step()


func _next_step() -> void:
	_step_i += 1
	_step_t = 0.0
	if _step_i >= _steps.size():
		return
	var s: Dictionary = _steps[_step_i]
	# throttle stays held for the rest of the run, like the web harness
	for a in _held.keys().duplicate():
		if a != "throttle":
			Input.action_release(a)
			_held.erase(a)
	if s.action == "pause" or s.action == "camera" or s.action == "reset_boat" or s.action == "horn":
		# One-shot actions: send a real key event so is_action_just_pressed() sees an edge.
		var key: int = {"pause": KEY_ESCAPE, "camera": KEY_C, "reset_boat": KEY_R, "horn": KEY_H}[s.action]
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.pressed = true
		Input.parse_input_event(ev)
		var up := InputEventKey.new()
		up.physical_keycode = key
		up.pressed = false
		get_tree().create_timer(0.15).timeout.connect(func(): Input.parse_input_event(up))
		return
	Input.action_press(s.action)
	_held[s.action] = true


func _process(dt: float) -> void:
	if not _active or _busy:
		return
	_t += dt
	if _step_i < _steps.size():
		_step_t += dt
		if _step_t >= _steps[_step_i].dur:
			await _shot("t%03d" % int(round(_t)))
			_next_step()
	if _every > 0.0 and _t - _last_every >= _every:
		_last_every = _t
		await _shot("e%03d" % int(round(_t)))
	if _perf and _t - _last_perf >= 1.0:
		_last_perf = _t
		var fps := Engine.get_frames_per_second()
		print("PERF t=%.1f fps=%d frame_ms=%.2f draw_calls=%d prims=%d" % [
			_t, fps, 1000.0 / maxf(fps, 1.0),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		for n in get_tree().get_nodes_in_group("harness_state"):
			if n.has_method("get_harness_state"):
				print("STATE ", JSON.stringify(n.get_harness_state()))
	if _seconds > 0.0 and _t >= _seconds:
		_busy = true
		await _shot("final")
		for a in _held.keys():
			Input.action_release(a)
		print("HARNESS done")
		get_tree().quit()


func _shot(shot_name: String) -> void:
	if _shots_dir == "":
		return
	_busy = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_shots_dir, shot_name]
	img.save_png(path)
	print("SHOT ", path)
	_busy = false
