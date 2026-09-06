extends SceneTree
## Headless submarine physics checks — port of the `sub` half of the web's tools/physics-sim.mjs.
##   godot --headless --path . --script res://tests/SubSim.gd
## Exit code 1 if any check fails.

var _failures := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	_run_checks()
	print("(%d ms)" % (Time.get_ticks_msec() - t0))
	if _failures > 0:
		print("\n%d sub check(s) FAILED" % _failures)
		quit(1)
	else:
		print("\nall sub checks passed")
		quit(0)


func _check(ok: bool, msg: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", msg])
	if not ok:
		_failures += 1


## Steps `s` for `seconds` at 60 Hz, calling `input(s, t)` before each step and `every(s, t)` once a
## second. Returns the max |roll| in degrees.
func _run(s: SubPhysics, seconds: float, input: Callable, every: Callable = Callable()) -> float:
	var dt := 1.0 / 60.0
	var max_roll := 0.0
	var n := roundi(seconds / dt)
	for i in n:
		input.call(s, i * dt)
		s.update(dt)
		max_roll = maxf(max_roll, absf(rad_to_deg(s.roll)))
		if every.is_valid() and i % 60 == 59:
			every.call(s, (i + 1) * dt)
	return max_roll


func _make(ground: Callable, ceiling: Callable) -> SubPhysics:
	var s := SubPhysics.new()
	s.auto_update = false
	s.ground_fn = ground
	s.ceiling_fn = ceiling
	return s


func _run_checks() -> void:
	var flat_ground := func(_x: float, _z: float) -> float: return -60.0
	var flat_sea := func(_x: float, _z: float) -> float: return 0.0
	print("\nsubmarine")

	# 1. Float at the surface with no input: the hull top sits at the waterline and stays there.
	var s := _make(flat_ground, flat_sea)
	s.set_pose(0, -0.5, 0, 0)
	_run(s, 6, func(b: SubPhysics, _t: float): b.throttle = 0.0; b.dive = 0.0)
	print("  surfaced rest: y=%.2f depth=%.2f submersion=%.2f ballast=%.2f" % [s.position.y, s.depth, s.submersion, s.ballast])
	_check(s.position.y > -0.9 and s.position.y < -0.2 and absf(s.velocity.y) < 0.05, "floats at the surface with the hull top out of the water")

	# 2. Surfaced driving: a slow boat, ~20 km/h.
	_run(s, 10, func(b: SubPhysics, _t: float): b.throttle = 1.0; b.dive = 0.0)
	print("  surfaced cruise: %.1f km/h depth=%.2f" % [s.speed_kmh, s.depth])
	_check(s.speed_kmh > 17 and s.speed_kmh < 23, "surfaced top speed ~20 km/h")
	_check(s.depth < 1.5, "stays surfaced while driving with the stick centred")

	# 3. Dive to 30 m at full throttle, then centre the stick and hold for 10 s.
	var st := {"t_dive": -1.0, "min_pitch": 0.0}
	var max_dive_roll := _run(s, 40, func(b: SubPhysics, t: float):
		b.throttle = 1.0
		b.dive = -1.0 if b.depth < 30.0 else 0.0
		if b.depth >= 30.0 and st.t_dive < 0.0:
			st.t_dive = t
		st.min_pitch = minf(st.min_pitch, rad_to_deg(b.pitch)))
	var hold_ref := s.depth
	var hold := {"min": INF, "max": -INF, "log": []}
	_run(s, 10, func(b: SubPhysics, _t: float): b.throttle = 1.0; b.dive = 0.0,
		func(b: SubPhysics, t: float):
			hold.log.append("%.0fs depth=%.2f pitch=%.1f v=%.1f" % [t, b.depth, rad_to_deg(b.pitch), b.speed_kmh])
			if t > 2.0:
				hold.min = minf(hold.min, b.depth)
				hold.max = maxf(hold.max, b.depth))
	print("  dive: nose down to %.1f deg, reached 30 m at t=%.1f s; hold from %.2f m -> [%.2f, %.2f] cruise %.1f km/h" % [st.min_pitch, st.t_dive, hold_ref, hold.min, hold.max, s.speed_kmh])
	print("    " + " | ".join(hold.log))
	_check(st.t_dive >= 0.0 and st.t_dive < 20.0, "reaches 30 m within 20 s")
	_check(st.min_pitch < -15.0 and st.min_pitch > -25.0, "planes pitch the nose down ~20 deg while diving")
	_check(hold.max - hold.min < 2.0 and absf(s.depth - hold_ref) < 1.0 + absf(hold_ref - 30.0), "holds depth within +-1 m at cruise")
	_check(s.speed_kmh > 27.0 and s.speed_kmh < 33.0, "submerged top speed ~30 km/h")

	# 4. Full-lock yaw at cruise: 0.5..0.9 rad/s, roll never past 15 deg.
	var yaw := {"sum": 0.0, "n": 0}
	var max_roll_turn := _run(s, 6, func(b: SubPhysics, t: float):
		b.throttle = 1.0; b.steer = 1.0; b.dive = 0.0
		if t > 2.0:
			yaw.sum += -b.angular.dot(b.up)
			yaw.n += 1)
	var yaw_rate: float = yaw.sum / yaw.n
	print("  full lock: yaw rate %.2f rad/s (positive = bow toward -X = right), max roll %.1f deg, depth %.2f" % [yaw_rate, max_roll_turn, s.depth])
	_check(yaw_rate > 0.5 and yaw_rate < 0.9, "full-lock yaw rate 0.5..0.9 rad/s")
	_check(max_roll_turn < 15.0 and max_dive_roll < 15.0, "roll never exceeds 15 deg")
	# Turning at stop (bow thruster).
	_run(s, 6, func(b: SubPhysics, _t: float): b.throttle = 0.0; b.steer = 0.0)
	yaw.sum = 0.0
	yaw.n = 0
	_run(s, 5, func(b: SubPhysics, t: float):
		b.throttle = 0.0; b.steer = 1.0
		if t > 2.0:
			yaw.sum += -b.angular.dot(b.up)
			yaw.n += 1)
	print("  stopped, full lock: yaw rate %.2f rad/s" % (yaw.sum / yaw.n))
	_check(yaw.sum / yaw.n > 0.2, "turns on the spot with the thruster")

	# 5. Surface and float.
	var surf := {"t": -1.0}
	_run(s, 40, func(b: SubPhysics, t: float):
		b.throttle = 0.5; b.steer = 0.0
		b.dive = 1.0 if b.depth > 1.2 else 0.0
		if b.depth <= 1.2 and surf.t < 0.0:
			surf.t = t)
	_run(s, 6, func(b: SubPhysics, _t: float): b.throttle = 0.0; b.dive = 0.0)
	print("  surfaced at t=%.1f s; rest y=%.2f vy=%.3f pitch=%.1f" % [surf.t, s.position.y, s.velocity.y, rad_to_deg(s.pitch)])
	_check(surf.t >= 0.0 and s.position.y > -0.9 and s.position.y < -0.2 and absf(s.velocity.y) < 0.05, "surfaces and floats again")

	# 6. Canyon wall at 30 km/h: a vertical step from -60 to 0 at x = 40. Never tunnels.
	var wall := func(x: float, _z: float) -> float: return 0.0 if x > 40.0 else -60.0
	s.free()
	s = _make(wall, flat_sea)
	s.set_pose(0, -12, 0, PI / 2)   # heading +X
	var mx := {"x": -INF}
	_run(s, 12, func(b: SubPhysics, _t: float):
		b.throttle = 1.0; b.dive = 0.0; b.steer = 0.0
		mx.x = maxf(mx.x, b.position.x))
	print("  wall: max x %.2f (wall at 40, hull half length 3), final speed %.1f km/h, y=%.1f" % [mx.x, s.speed_kmh, s.position.y])
	_check(mx.x < 40.0, "never passes through a canyon wall at full speed")

	# 7. Sloping seabed: driving into a 30 deg slope rides up and scrapes, no explosion.
	var slope := func(x: float, _z: float) -> float: return maxf(-60.0, -30.0 + x * 0.6)
	s.free()
	s = _make(slope, flat_sea)
	s.set_pose(-40, -25, 0, PI / 2)
	var ok := {"v": true}
	_run(s, 12, func(b: SubPhysics, _t: float):
		b.throttle = 1.0; b.dive = -1.0
		if not is_finite(b.position.y) or b.speed > 15.0:
			ok.v = false)
	var g := float(slope.call(s.position.x, s.position.z))
	print("  slope: final x=%.1f y=%.1f ground=%.1f speed=%.1f" % [s.position.x, s.position.y, g, s.speed_kmh])
	_check(ok.v and s.position.y - 0.95 >= g - 0.7, "rides a slope without sinking into it")

	# 8. Rescue from inside terrain.
	s.set_pose(60, -20, 0, 0)
	s.rescue()
	g = float(slope.call(s.position.x, s.position.z))
	print("  rescue -> x=%.1f y=%.1f ground=%.1f" % [s.position.x, s.position.y, g])
	_check(s.position.y - 0.95 > g + 1.0, "rescue finds open water")

	# 9. Cost: update() with a cheap flat seabed.
	s.free()
	s = _make(flat_ground, flat_sea)
	s.set_pose(0, -20, 0, 0)
	var t0 := Time.get_ticks_usec()
	_run(s, 10, func(b: SubPhysics, _t: float): b.throttle = 1.0; b.steer = 0.3)
	print("  cost: %.1f us per 60 Hz update (flat seabed)" % ((Time.get_ticks_usec() - t0) / 600.0))
	s.free()
