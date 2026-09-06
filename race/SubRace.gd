class_name SubRace
extends Race
## SubRace: the underwater race. Port of src/game/SubRace.js — same public surface as Race, with
## 3D hoops instead of arches and AI submarines instead of boats, plus next_gate_pitch().
##
## A hoop is a torus standing vertical at (x, y, z), its axis along `heading`. A sub passes a hoop
## when its centre crosses the hoop's plane going forwards inside the ring radius (plus half the
## hull width). The next hoop glows green, the following white, passed hoops dim; the next two carry
## a slowly turning ring of sparkle beads. The arrow points at the next hoop in 3D.

const SUB_DEFAULT_WIDTH := 14.0
const DEFAULT_Y := -15.0
const HOOP_TUBE := 0.55
const BEADS := 10

const SUB_PERSONALITIES := [
	{"gain": 2.2, "damp": 1.1, "aggression": 0.97, "lane": -0.25, "lane_y": 0.15, "wobble": 0.03, "wobble_hz": 0.35, "brake": 1.0},
	{"gain": 1.8, "damp": 1.3, "aggression": 0.93, "lane": 0.28, "lane_y": -0.2, "wobble": 0.045, "wobble_hz": 0.22, "brake": 1.15},
	{"gain": 2.5, "damp": 1.0, "aggression": 1.0, "lane": 0.05, "lane_y": 0.3, "wobble": 0.025, "wobble_hz": 0.5, "brake": 0.9},
	{"gain": 2.0, "damp": 1.2, "aggression": 0.95, "lane": -0.12, "lane_y": -0.1, "wobble": 0.04, "wobble_hz": 0.3, "brake": 1.05},
]
# Start grid slots relative to the start pose: [lateral, back, vertical].
const SUB_GRID := [[7, -9, -1.5], [-7, -9, -1.5], [0, -18, -3], [12, -18, -1], [-12, -18, -1], [0, -27, -2]]

var _arrow_dir := Vector3(0, 0, 1)


func configure(game_: Node, def: Dictionary, opts: Dictionary = {}) -> Race:
	super.configure(game_, def, opts)
	ai_count = clampi(int(opts.get("ai_count", 3)), 0, SUB_GRID.size())
	name = "SubRace"
	return self


# ---------------------------------------------------------------- setup
func setup() -> void:
	var start: Dictionary = world_def.get("start", {"x": 0.0, "z": 0.0, "heading": 0.0})
	var h := float(start.get("heading", 0.0))
	var fx := sin(h)
	var fz := cos(h)
	var rx := cos(h)
	var rz := -sin(h)
	var ground := _ground_fn()
	var ceiling := Callable(self, "_sea_h")
	var start_y: float = float(start.y) if start.has("y") else _sea_h(float(start.x), float(start.z)) - 0.5

	var pb: Node = _player_body()
	if pb:
		if ground.is_valid():
			pb.set("ground_fn", ground)
		if is_sub(pb):
			_ensure_ceiling(pb, ceiling)
			pb.set_pose(float(start.x), _clear_y(ground, float(start.x), start_y, float(start.z)), float(start.z), h)
		else:
			pb.set_pose(float(start.x), _sea_h(float(start.x), float(start.z)) + 0.3, float(start.z), h)

	ai_racers = []
	for i in ai_count:
		var lat := float(SUB_GRID[i][0])
		var back := float(SUB_GRID[i][1])
		var dy := float(SUB_GRID[i][2])
		var x := float(start.x) + rx * lat + fx * back
		var z := float(start.z) + rz * lat + fz * back
		var y := _clear_y(ground, x, minf(start_y + dy, _sea_h(x, z) - 0.5), z)
		var sub: Node = null
		if game and game.has_method("spawn_sub"):
			sub = game.spawn_sub(x, y, z, h, i + 1)
		if sub == null:
			continue
		sub.set_meta("ai", true)
		if not sub.has_meta("label") or String(sub.get_meta("label")) == "Submarine":
			sub.set_meta("label", "Sub %d" % (i + 1))
		ai_racers.append(sub)

	racers = []
	player = {}
	if pb:
		player = _make_racer(pb, {})
		if autopilot:
			player.ai = SUB_PERSONALITIES[2].duplicate()
			player.ai["phase"] = 0.0
			player.ai["stuck"] = 0
	for i in ai_racers.size():
		var pers: Dictionary = SUB_PERSONALITIES[i % SUB_PERSONALITIES.size()].duplicate()
		pers["phase"] = i * 1.7
		pers["stuck"] = 0
		_make_racer(ai_racers[i], pers)
	for r in racers:
		if ground.is_valid():
			r.body.set("ground_fn", ground)
		if is_sub(r.body):
			_ensure_ceiling(r.body, ceiling)

	if not gates.is_empty():
		var g0: Dictionary = gates[0]
		var s0: float = (float(start.x) - g0.x) * g0.dir.x + (float(start.z) - g0.z) * g0.dir.z
		_start_behind = s0 < -2.0
		for r in racers:
			r.next_gate = 0 if _start_behind else (1 % gates.size())
			r.prev_s = _side_of(body_pos(r.body), gates[r.next_gate])

	_build_arrow()
	_update_standings()
	_update_visuals(0.0)


func _ensure_ceiling(b: Node, ceiling: Callable) -> void:
	var c = b.get("ceiling_fn")
	if c is Callable and not c.is_valid():
		b.set("ceiling_fn", ceiling)


func _clear_y(ground: Callable, x: float, y: float, z: float) -> float:
	if ground.is_valid():
		return maxf(y, float(ground.call(x, z)) + 4.0)
	return y


# ------------------------------------------------------------------ HUD
func next_gate_pos() -> Vector3:
	var gate := _gate_of_player()
	return gate.pos if not gate.is_empty() else Vector3.ZERO


## Elevation of the next hoop relative to the player's pitch (rad, +up).
func next_gate_pitch() -> float:
	var gate := _gate_of_player()
	if player.is_empty() or gate.is_empty():
		return 0.0
	var b: Node = player.body
	var p := body_pos(b)
	var dh := Vector2(gate.x - p.x, gate.z - p.z).length()
	var pitch = b.get("pitch")
	return atan2(gate.y - p.y, maxf(dh, 1.0)) - (float(pitch) if pitch != null else 0.0)


# -------------------------------------------------------------- course
func _build_gates() -> void:
	var defs: Array = world_def.get("gates", [])
	gates = []
	for i in defs.size():
		var d: Dictionary = defs[i]
		var heading := float(d.get("heading", 0.0))
		var y := float(d.get("y", DEFAULT_Y))
		var width := float(d.get("width", SUB_DEFAULT_WIDTH))
		gates.append({
			"index": i, "x": float(d.x), "y": y, "z": float(d.z), "heading": heading, "width": width, "radius": width * 0.5,
			"pos": Vector3(float(d.x), y, float(d.z)),
			"dir": Vector3(sin(heading), 0, cos(heading)),
			"right": Vector3(cos(heading), 0, -sin(heading)),
			"is_finish": i == 0, "state": "", "node": null, "ring": null, "beads": null, "seg_len": 1.0,
		})
	var n := gates.size()
	course_length = 0.0
	for i in n:
		var a: Dictionary = gates[i]
		var b: Dictionary = gates[(i + 1) % n]
		a.seg_len = maxf(1.0, a.pos.distance_to(b.pos))
		course_length += a.seg_len
	_build_materials()
	for gate in gates:
		_build_gate_visual(gate)


## True while `body` is within the hoop's plane band and inside the ring.
func gate_test(gate: Dictionary, body: Node) -> bool:
	var p := body_pos(body)
	var dx: float = p.x - gate.x
	var dy: float = p.y - gate.y
	var dz: float = p.z - gate.z
	var s: float = dx * gate.dir.x + dz * gate.dir.z
	var l: float = dx * gate.right.x + dz * gate.right.z
	return absf(s) < 1.5 and Vector2(l, dy).length() <= gate.radius


func _build_materials() -> void:
	var checker := checker_texture(24, 2, Color.WHITE, Color(0.063, 0.078, 0.094))
	# Underwater is dim: hoops carry a strong emissive so they read from a long way off.
	_mats = {
		"plain_next": _mk(Color(0.227, 1.0, 0.384), Color(0.083, 1.0, 0.15), 6.0, 0.4),
		"plain_after": _mk(Color(0.965, 0.965, 0.965), Color(0.93, 0.93, 1.0), 1.5, 0.45),
		"plain_far": _mk(Color(0.788, 0.816, 0.839), Color(0.77, 0.85, 1.0), 0.65, 0.5),
		"plain_dim": _mk(Color(0.353, 0.388, 0.424), Color(0.57, 0.71, 1.0), 0.14, 0.6),
		"finish_next": _mk(Color(0.66, 1.0, 0.72), Color(0.094, 1.0, 0.19), 3.2, 0.4, checker),
		"finish_after": _mk(Color.WHITE, Color.WHITE, 1.0, 0.45, checker),
		"finish_far": _mk(Color(0.847, 0.867, 0.886), Color(0.9, 0.9, 1.0), 0.5, 0.5, checker),
		"finish_dim": _mk(Color(0.416, 0.447, 0.478), Color(0.8, 0.8, 1.0), 0.1, 0.6, checker),
		"bead": _mk(Color.WHITE, Color(1.0, 1.0, 0.83), 6.0, 0.3),
		"bead_next": _mk(Color(0.847, 1.0, 0.878), Color(0.31, 1.0, 0.375), 8.0, 0.3),
		"arrow": _mk(Color(1.0, 0.824, 0.122), Color(1.0, 0.75, 0.094), 3.2, 0.45),
	}


func _build_gate_visual(gate: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Hoop%d" % gate.index
	node.position = gate.pos
	node.rotation.y = gate.heading
	# Torus in the local XY plane: a ring standing vertical, axis along the travel direction.
	var ring_mesh := _mesh("ring%.1f" % gate.width, func():
		var t := TorusMesh.new()
		t.inner_radius = gate.radius - HOOP_TUBE
		t.outer_radius = gate.radius + HOOP_TUBE
		t.rings = 36
		t.ring_segments = 8
		return t)
	var ring := _mi(ring_mesh, _mats.plain_far, Vector3.ZERO, node)
	ring.rotation.x = PI / 2   # TorusMesh lies in XZ; stand it up into XY
	gate.ring = ring
	# Sparkle beads riding the ring, one merged mesh, turned slowly in _update_visuals.
	var bead_mesh := _mesh("beads%.1f" % gate.width, func():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var oct := SphereMesh.new()
		oct.radius = 0.42
		oct.height = 0.84
		oct.radial_segments = 4
		oct.rings = 2
		var arrays := oct.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for k in BEADS:
			var a := float(k) / BEADS * TAU
			var c := Vector3(cos(a) * gate.radius, sin(a) * gate.radius, 0)
			for ii in idx:
				st.add_vertex(verts[ii] + c)
		st.generate_normals()
		return st.commit())
	var beads := _mi(bead_mesh, _mats.bead, Vector3.ZERO, node)
	beads.visible = false
	gate.beads = beads
	gate.node = node
	add_child(node)


# ------------------------------------------------------------ progress
func _check_gate(r: Dictionary) -> void:
	if r.next_gate >= gates.size():
		return
	var gate: Dictionary = gates[r.next_gate]
	var b: Node = r.body
	var p := body_pos(b)
	var s := _side_of(p, gate)
	if r.prev_s < 0.0 and s >= 0.0:
		var lateral: float = (p.x - gate.x) * gate.right.x + (p.z - gate.z) * gate.right.z
		var off := Vector2(lateral, p.y - gate.y).length()
		var tol: float = gate.radius + maxf(1.0, hull_num(b, "width", 2.0) * 0.5)
		var v := body_vel(b)
		var forwards: bool = v.x * gate.dir.x + v.z * gate.dir.z > 0.0
		if off <= tol and forwards:
			_pass_gate(r, gate)
	r.prev_s = s


func _dist_to_gate(p: Vector3, gate: Dictionary) -> float:
	return p.distance_to(gate.pos)


# ---------------------------------------------------------------- AI
func _drive(r: Dictionary, dt: float) -> void:
	var b: Node = r.body
	var ai: Dictionary = r.ai
	var n := gates.size()
	var gate: Dictionary = gates[r.next_gate]
	var after: Dictionary = gates[(r.next_gate + 1) % n]
	var p := body_pos(b)
	var fwd3 := _body_fwd3(b)
	var fwd := body_fwd(b)
	var lat_axis := body_lat(b)
	var heading := body_heading(b)
	var max_speed := hull_num(b, "max_speed", 13.0)
	var speed := maxf(0.0, body_vel(b).dot(fwd3))
	var speed_k := clampf(speed / max_speed, 0.0, 1.2)
	var dist_h := Vector2(gate.x - p.x, gate.z - p.z).length()
	var rad: float = gate.radius

	# Aim point inside the hoop: cut toward the side the following hoop is on, plus this
	# driver's lane, never closer than 40 % to the rim.
	var to_after_lat: float = (after.x - gate.x) * gate.right.x + (after.z - gate.z) * gate.right.z
	var offset: float = clampf(to_after_lat * 0.25, -rad * 0.4, rad * 0.4) + ai.lane * rad
	offset = clampf(offset, -rad * 0.6, rad * 0.6)
	var ax: float = gate.x + gate.right.x * offset
	var az: float = gate.z + gate.right.z * offset
	var aim_y: float = gate.y + clampf((after.y - gate.y) * 0.2, -rad * 0.35, rad * 0.35) + ai.lane_y * rad
	var desired := bearing(p.x, p.z, ax, az)
	desired = lerp_angle_w(desired, gate.heading, smooth(-dist_h, -10, -3))
	var turn_ahead := wrap_angle(bearing(gate.x, gate.z, after.x, after.z) - gate.heading)
	var look_w := smooth(-dist_h, -28, -6) * 0.45
	desired = lerp_angle_w(desired, bearing(p.x, p.z, after.x, after.z), look_w)
	aim_y = lerpf(aim_y, after.y, look_w * 0.6)
	desired += sin(_t * ai.wobble_hz * TAU + ai.phase) * ai.wobble

	# Terrain: probe the seabed ahead (three fan probes) and directly below, the surface above.
	var avoid := 0.0
	var blocked := 0.0
	var climb := 0.0
	var ground := _body_ground(b)
	var surface := _surface_of(b, p)
	if ground.is_valid():
		var reach := clampf(speed * 3.0, 18.0, 40.0)
		var hit_l := false
		var hit_c := false
		var hit_r := false
		for side in [-1, 0, 1]:
			var a: float = heading + side * 0.45
			var far := float(ground.call(p.x + sin(a) * reach, p.z + cos(a) * reach))
			var near := float(ground.call(p.x + sin(a) * reach * 0.5, p.z + cos(a) * reach * 0.5))
			var clear := p.y - maxf(far, near)   # vertical clearance over the terrain ahead
			var hit := clear < 6.0
			if side < 0:
				hit_l = hit
			elif side > 0:
				hit_r = hit
			else:
				hit_c = hit
				if hit:
					climb = maxf(climb, (6.0 - clear) * 0.25)
		if hit_l:
			avoid += 0.7
			blocked += 0.5
		if hit_r:
			avoid -= 0.7
			blocked += 0.5
		if hit_c:
			blocked += 1.0
			if hit_l and not hit_r:
				avoid += 0.9
			elif hit_r and not hit_l:
				avoid -= 0.9
			else:
				avoid += 0.9 if turn_ahead >= 0.0 else -0.9
		var below := p.y - float(ground.call(p.x, p.z))
		if below < 4.0:
			climb = maxf(climb, (4.0 - below) * 0.4)
		# Never aim the sub into the seabed or through the surface.
		aim_y = maxf(aim_y, float(ground.call(ax, az)) + 5.0)
	aim_y = minf(aim_y, maxf(gate.y, surface - 2.5))

	# Keep clear of other subs just ahead.
	var crowd := 0.0
	var crowd_y := 0.0
	for o in _boats():
		if o == b or not is_instance_valid(o):
			continue
		var d3 := body_pos(o) - p
		var d := d3.length()
		if d > 12.0 or d < 1e-3:
			continue
		if d3.dot(fwd3) < 0.0:
			continue
		crowd += (-1.0 if d3.dot(lat_axis) >= 0.0 else 1.0) * (1.0 - d / 12.0) * 0.35
		crowd_y += (-1.0 if d3.y >= 0.0 else 1.0) * (1.0 - d / 12.0) * 0.5
	desired += avoid * 0.7 + crowd

	# Yaw: proportional on heading error, damped by yaw rate.
	var err := wrap_angle(desired - heading)
	var kp: float = ai.gain * clampf(1.35 - 0.55 * speed_k, 0.75, 1.35)
	var steer := -clampf(kp * err - ai.damp * body_yaw_rate(b), -1.0, 1.0)
	r.steer += (steer - r.steer) * (1.0 - exp(-dt * 7.0))
	b.set("steer", r.steer)

	# Dive: proportional on the height error with vertical-speed damping, plus terrain climb.
	var dy := aim_y - p.y
	var dive := clampf(dy * 0.35 - body_vel(b).y * 0.3, -1.0, 1.0) + climb + crowd_y
	dive = clampf(dive, -1.0, 1.0)
	r.dive += (dive - r.dive) * (1.0 - exp(-dt * 5.0))
	b.set("dive", r.dive)

	# Throttle: ease off for a big corner ahead, when far off heading, for a steep climb/dive, or when blocked.
	var throttle: float = ai.aggression
	var abs_err := absf(err)
	var braking := smooth(-dist_h, -70, -25) * (1.0 - smooth(-dist_h, -18, -6)) * smooth(absf(turn_ahead), 0.4, 1.2) * smooth(speed_k, 0.45, 0.8)
	throttle *= 1.0 - braking * 0.6 * ai.brake
	throttle *= 1.0 - smooth(abs_err, 1.4, 2.6) * 0.4
	var slope := absf(dy) / maxf(dist_h, 6.0)
	throttle *= 1.0 - smooth(slope, 0.35, 0.7) * 0.45
	if blocked > 0.0:
		throttle *= 0.7
	throttle = maxf(throttle, 0.4)

	var boost := 0.0
	if rubber_band and not player.is_empty() and not player.finished and not r.finished:
		var gap_m: float = (r.raw - player.raw) * course_length
		if gap_m > 0.0:
			var cap := lerpf(1.0, 0.55, smooth(gap_m, 55, 95))
			cap = lerpf(cap, 0.3, smooth(gap_m, 150, 240))
			throttle = minf(throttle, maxf(cap, smooth(abs_err, 0.3, 0.9)))
		else:
			boost = 0.72 * smooth(-gap_m, 95, 135) + 0.28 * smooth(-gap_m, 200, 320)
	elif r.finished:
		throttle = minf(throttle, 0.8)
	b.set("throttle", throttle)
	b.set("boost", boost)

	# Stuck: barely moving for 4 s while racing. Point at the hoop, clear of the bottom, and shove.
	if body_speed(b) < 1.0 and state != "countdown":
		r.stuck_t += dt
	else:
		r.stuck_t = 0.0
	if r.stuck_t > 4.0:
		r.stuck_t = 0.0
		ai.stuck += 1
		var hd := bearing(p.x, p.z, gate.x, gate.z)
		var y := p.y
		if ground.is_valid():
			y = maxf(p.y, float(ground.call(p.x, p.z)) + 4.0)
		y = minf(y, surface - 0.5)
		b.set_pose(p.x, y, p.z, hd)
		b.set("velocity", Vector3(sin(hd) * 4.0, 0.0, cos(hd) * 4.0))
		r.steer = 0.0
		r.dive = 0.0


func _body_fwd3(b: Node) -> Vector3:
	var f = b.get("forward")
	if f is Vector3 and f.length_squared() > 0.5:
		return f.normalized()
	return body_fwd(b)


func _surface_of(b: Node, p: Vector3) -> float:
	var s = b.get("surface_y")
	if s != null:
		return float(s)
	return _sea_h(p.x, p.z)


# ------------------------------------------------------------- visuals
func _update_visuals(dt: float) -> void:
	var n := gates.size()
	if n == 0:
		return
	var next: int = player.get("next_gate", 0) if not player.is_empty() else 0
	var after := (next + 1) % n
	for gate in gates:
		var i: int = gate.index
		var st := "far"
		if i == next:
			st = "next"
		elif i == after and n > 2:
			st = "after"
		elif not player.is_empty() and _passed_this_lap(player, i):
			st = "dim"
		if st != gate.state:
			gate.state = st
			gate.ring.material_override = _mats[("finish_" if gate.is_finish else "plain_") + st]
			gate.beads.visible = st == "next" or st == "after"
			gate.beads.material_override = _mats.bead_next if st == "next" else _mats.bead
		if gate.beads.visible:
			gate.beads.rotation.z += dt * (0.9 if st == "next" else 0.45)
	_update_arrow(dt)


func _update_arrow(dt: float) -> void:
	if _arrow == null or player.is_empty():
		return
	var gate := _gate_of_player()
	var hide: bool = player.finished or state == "disposed" or gate.is_empty()
	_arrow.visible = not hide
	if hide:
		return
	var b: Node = player.body
	var p := body_pos(b)
	var f := _body_fwd3(b)
	var to: Vector3 = gate.pos - p
	to = to.normalized() if to.length_squared() > 1e-4 else f
	if dt > 0.0:
		_arrow_dir = _arrow_dir.lerp(to, 1.0 - exp(-dt * 5.0)).normalized()
	else:
		_arrow_dir = to
	var h := 3.4 + sin(_t * 2.2) * 0.3
	var pos := Vector3(p.x + f.x * 1.5, p.y + h, p.z + f.z * 1.5)
	_arrow.position = pos
	# +Z of the arrow toward the hoop.
	var upv := Vector3.UP if absf(_arrow_dir.y) < 0.99 else Vector3.FORWARD
	_arrow.basis = Basis.looking_at(_arrow_dir, upv) * Basis(Vector3.UP, PI)
