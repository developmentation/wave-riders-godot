class_name Race
extends Node3D
## Race: checkpoint gates, lap counting, standings, countdown, AI drivers. Port of src/game/Race.js.
##
## A gate is a plane through (x, z) facing `heading` (direction of travel, BoatPhysics convention:
## heading 0 = +Z, growing toward +X). A boat passes a gate when it crosses that plane going
## forwards within half the gate width of the centre. Gates are taken in order; a missed gate stays
## the target, nothing punishes.
##
## Visuals are big toy-like arches: two striped buoy pillars, a torus arch, lamp caps and a fluttering
## banner. The player's next gate glows green, the one after white, passed gates go dim; the
## start/finish gate is checkered. A yellow arrow hovers over the player pointing at the next gate.
##
## Usage (Main.gd):  var race := Race.new(); race.configure(self, world_def, {"laps": 3});
##   add_child(race); race.setup(); race.start(); ... race.update(dt) every frame; race.dispose().
## `game` is duck-typed: boats (Array of body nodes), player (body node or null), ocean (height_at),
## world (height_at), spawn_boat(id, x, z, heading, color) -> Node, remove_boat(node).
## Bodies are duck-typed too (position/heading/velocity/hull/throttle/steer/boost/angular/set_pose).

signal gate_passed(boat: Node, index: int)
signal lap(boat: Node, n: int)
signal finished(boat: Node, place: int, time: float)
signal countdown_tick(n: int)   # 3, 2, 1, 0 (= GO). Named _tick because `countdown` is the float property.

const DEFAULT_WIDTH := 24.0
const PILLAR_R := 1.0
const PILLAR_H := 5.0           # buoy pillar from 1.5 m below water to 3.5 m above
const PILLAR_BASE := -1.5
const ARCH_TUBE := 1.1

# Per-AI flavour so the pack does not drive in lock-step.
const PERSONALITIES := [
	{"gain": 2.2, "damp": 1.1, "aggression": 0.97, "lane": -0.28, "wobble": 0.035, "wobble_hz": 0.35, "brake": 1.0},
	{"gain": 1.8, "damp": 1.3, "aggression": 0.93, "lane": 0.30, "wobble": 0.05, "wobble_hz": 0.22, "brake": 1.15},
	{"gain": 2.5, "damp": 1.0, "aggression": 1.0, "lane": 0.05, "wobble": 0.025, "wobble_hz": 0.5, "brake": 0.9},
	{"gain": 2.0, "damp": 1.2, "aggression": 0.95, "lane": -0.12, "wobble": 0.04, "wobble_hz": 0.3, "brake": 1.05},
	{"gain": 2.3, "damp": 1.15, "aggression": 0.9, "lane": 0.18, "wobble": 0.03, "wobble_hz": 0.4, "brake": 1.0},
]
# Start grid slots relative to the start pose: [lateral (+X side), back].
const GRID := [[6, -8], [-6, -8], [0, -16], [12, -16], [-12, -16], [0, -24], [6, -32], [-6, -32]]

var game: Node
var world_def: Dictionary = {}
var laps := 3
var ai_count := 3
var ai_boats: Array = ["jetski", "sailboat", "pontoon"]
var rubber_band := true      # AI throttle cap when far ahead of the player, boost when far behind
var ai_assist := true        # AI yaw-rate top-up (<= 0.35 rad/s) where the hull cannot turn on its own
var autopilot := false       # drive the player's boat with the AI too (harness / screenshots)
var state := "setup"         # setup | countdown | racing | finished | disposed
var countdown := 0.0
var time := 0.0
var accepts_input := false
var gates: Array = []        # Dictionaries, see _build_gates
var racers: Array = []       # Dictionaries, see _make_racer
var standings: Array = []
var player: Dictionary = {}  # the player's racer record (empty when there is no player)
var ai_racers: Array = []    # AI body nodes
var course_length := 0.0

var _arrow: Node3D
var _arrow_yaw := 0.0
var _finished_count := 0
var _updates := 0
var _frame := 0
var _mats: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _start_behind := true
var _t := 0.0
var _last_count := 3


# ---------------------------------------------------------------- setup
func configure(game_: Node, def: Dictionary, opts: Dictionary = {}) -> Race:
	game = game_
	world_def = def
	laps = maxi(1, int(opts.get("laps", def.get("laps", 3))))
	ai_count = clampi(int(opts.get("ai_count", 3)), 0, GRID.size())
	ai_boats = opts.get("ai_boats", ai_boats)
	rubber_band = bool(opts.get("rubber_band", true))
	ai_assist = bool(opts.get("ai_assist", true))
	name = "Race"
	_build_gates()
	return self


## Place the player on the front row, spawn the AI behind, build the arrow.
func setup() -> void:
	var start: Dictionary = world_def.get("start", {"x": 0.0, "z": 0.0, "heading": 0.0})
	var h := float(start.get("heading", 0.0))
	var fx := sin(h)
	var fz := cos(h)
	var rx := cos(h)
	var rz := -sin(h)
	var ground := _ground_fn()

	var pb: Node = _player_body()
	if pb:
		_place_body(pb, float(start.x), float(start.z), h)

	ai_racers = []
	for i in ai_count:
		var lat := float(GRID[i][0])
		var back := float(GRID[i][1])
		var x := float(start.x) + rx * lat + fx * back
		var z := float(start.z) + rz * lat + fz * back
		var bid: String = ai_boats[i % ai_boats.size()]
		var boat: Node = _spawn_ai(bid, x, z, h, i + 1)
		if boat == null:
			continue
		boat.set_meta("ai", true)
		if not boat.has_meta("label"):
			boat.set_meta("label", "%s %d" % [bid, i + 1])
		ai_racers.append(boat)

	racers = []
	player = {}
	if pb:
		player = _make_racer(pb, {})
		if autopilot:
			player.ai = PERSONALITIES[2].duplicate()
			player.ai["phase"] = 0.0
			player.ai["stuck"] = 0
	for i in ai_racers.size():
		var pers: Dictionary = PERSONALITIES[i % PERSONALITIES.size()].duplicate()
		pers["phase"] = i * 1.7
		pers["stuck"] = 0
		_make_racer(ai_racers[i], pers)

	if ground.is_valid():
		for r in racers:
			r.body.set("ground_fn", ground)

	# If the world puts the start ahead of gate 0, the first target is gate 1.
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


func _place_body(b: Node, x: float, z: float, h: float) -> void:
	b.set_pose(x, _sea_h(x, z) + 0.3, z, h)


func _spawn_ai(bid: String, x: float, z: float, h: float, color: int) -> Node:
	if game and game.has_method("spawn_boat"):
		return game.spawn_boat(bid, x, z, h, color)
	return null


func _make_racer(boat: Node, ai: Dictionary) -> Dictionary:
	var r := {
		"boat": boat, "body": boat, "is_player": ai.is_empty(), "ai": ai,
		"lap": 1, "next_gate": 0, "gates_total": 0, "prev_s": 0.0,
		"finished": false, "finish_time": 0.0, "place": 0, "position": 0,
		"progress": 0.0, "lap_progress": 0.0, "dist_next": 0.0, "stuck_t": 0.0, "steer": 0.0, "dive": 0.0, "raw": 0.0,
	}
	racers.append(r)
	return r


# ------------------------------------------------------------- lifecycle
func start() -> void:
	if state == "disposed":
		return
	state = "countdown"
	countdown = 3.0      # the HUD shows ceil(countdown), so 3.0 reads "3" for a full second
	_last_count = 3
	time = 0.0
	accepts_input = false
	_freeze_all()
	countdown_tick.emit(3)


func update(dt: float) -> void:
	if state == "disposed" or state == "setup":
		return
	_updates += 1
	_frame += 1
	_t += dt

	if state == "countdown":
		countdown -= dt
		_freeze_all()
		var n := ceili(maxf(countdown, 0.0))
		if n != _last_count:
			_last_count = n
			countdown_tick.emit(n)
		if countdown <= 0.0:
			countdown = 0.0
			state = "racing"
			accepts_input = true
	else:
		time += dt

	var racing := state == "racing" or state == "finished"
	var boats := _boats()
	for r in racers:
		if not _alive(r, boats):
			continue
		if racing:
			_check_gate(r)
		_progress_of(r)
	_update_standings()

	if racing:
		for r in racers:
			if not r.ai.is_empty() and _alive(r, boats):
				_drive(r, dt)

	_update_visuals(dt)


func dispose() -> void:
	state = "disposed"
	accepts_input = true
	var boats := _boats()
	for boat in ai_racers:
		if not is_instance_valid(boat) or not boats.has(boat):
			continue
		if game and game.has_method("remove_boat"):
			game.remove_boat(boat)
		else:
			boats.erase(boat)
			boat.queue_free()
	ai_racers = []
	gates = []
	_arrow = null
	queue_free()


# ------------------------------------------------------------------ HUD
## World position of the player's next gate (arch centre).
func next_gate_pos() -> Vector3:
	var gate := _gate_of_player()
	if gate.is_empty():
		return Vector3.ZERO
	return Vector3(gate.x, gate.node.position.y + PILLAR_BASE + PILLAR_H + gate.width * 0.25, gate.z)


## Direction to the next gate relative to the player's heading (rad, +right).
func next_gate_dir() -> float:
	var gate := _gate_of_player()
	if player.is_empty() or gate.is_empty():
		return 0.0
	var p := body_pos(player.body)
	# heading grows toward +X, which is the boat's visual LEFT; negate for "+right".
	return -wrap_angle(bearing(p.x, p.z, gate.x, gate.z) - body_heading(player.body))


func _gate_of_player() -> Dictionary:
	var i: int = player.get("next_gate", 0) if not player.is_empty() else 0
	if i < 0 or i >= gates.size():
		return {}
	return gates[i]


# -------------------------------------------------------------- course
func _build_gates() -> void:
	var defs: Array = world_def.get("gates", [])
	gates = []
	for i in defs.size():
		var d: Dictionary = defs[i]
		var heading := float(d.get("heading", 0.0))
		var gate := {
			"index": i, "x": float(d.x), "y": 0.0, "z": float(d.z), "heading": heading, "width": float(d.get("width", DEFAULT_WIDTH)),
			"pos": Vector3(float(d.x), 0.0, float(d.z)),
			"dir": Vector3(sin(heading), 0, cos(heading)),
			"right": Vector3(cos(heading), 0, -sin(heading)),
			"is_finish": i == 0, "state": "", "node": null, "arch": null, "caps": [], "banner": null, "seg_len": 1.0,
		}
		gates.append(gate)
	var n := gates.size()
	course_length = 0.0
	for i in n:
		var a: Dictionary = gates[i]
		var b: Dictionary = gates[(i + 1) % n]
		a.seg_len = maxf(1.0, Vector2(b.x - a.x, b.z - a.z).length())   # length of the leg leaving gate i
		course_length += a.seg_len
	_build_materials()
	for gate in gates:
		_build_gate_visual(gate)


## True while `body` sits in the gate's plane band, inside the pillars (web gate.test).
func gate_test(gate: Dictionary, body: Node) -> bool:
	var p := body_pos(body)
	var dx: float = p.x - gate.x
	var dz: float = p.z - gate.z
	var s: float = dx * gate.dir.x + dz * gate.dir.z
	var l: float = dx * gate.right.x + dz * gate.right.z
	return absf(s) < 1.5 and absf(l) <= gate.width * 0.5


func _build_materials() -> void:
	var checker := checker_texture(32, 4, Color.WHITE, Color(0.063, 0.078, 0.094))
	var stripes := stripe_texture(12, Color(1.0, 0.415, 0.0), Color.WHITE)
	var banner_checker := checker_texture(8, 3, Color.WHITE, Color(0.063, 0.078, 0.094))
	_mats = {
		"pillar": _mk(Color.WHITE, Color.BLACK, 0.0, 0.55, stripes, Vector3(1, 2, 1)),
		"banner_plain": _mk_banner(Color(1.0, 0.478, 0.102), Color(0.5, 0.15, 0.0), 1.0, null),
		"banner_finish": _mk_banner(Color.WHITE, Color(0.2, 0.2, 0.2), 1.0, banner_checker),
		# Arch + lamp caps per state.
		"plain_next": _mk(Color(0.227, 1.0, 0.384), Color(0.08, 1.0, 0.14), 5.0, 0.4),
		"plain_after": _mk(Color(0.965, 0.965, 0.965), Color(1, 1, 1), 0.5, 0.45),
		"plain_far": _mk(Color(0.788, 0.816, 0.839), Color(1, 1, 1), 0.22, 0.5),
		"plain_dim": _mk(Color(0.353, 0.388, 0.424), Color.BLACK, 0.0, 0.6),
		"finish_next": _mk(Color(0.66, 1.0, 0.72), Color(0.1, 1.0, 0.19), 2.6, 0.4, checker),
		"finish_after": _mk(Color.WHITE, Color(1, 1, 1), 0.4, 0.45, checker),
		"finish_far": _mk(Color(0.847, 0.867, 0.886), Color(1, 1, 1), 0.2, 0.5, checker),
		"finish_dim": _mk(Color(0.416, 0.447, 0.478), Color.BLACK, 0.0, 0.6, checker),
		"arrow": _mk(Color(1.0, 0.824, 0.122), Color(1.0, 0.75, 0.07), 2.8, 0.45),
	}


func _mk(albedo: Color, emissive: Color, energy: float, rough: float, tex: Texture2D = null, uv_scale := Vector3.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	if tex:
		m.albedo_texture = tex
		m.uv1_scale = uv_scale
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emissive
		m.emission_energy_multiplier = energy
	return m


func _mk_banner(albedo: Color, emissive: Color, energy: float, tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://race/banner.gdshader")
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("emission", emissive)
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("use_tex", tex != null)
	if tex:
		m.set_shader_parameter("tex", tex)
	return m


static func checker_texture(cols: int, rows: int, a: Color, b: Color, px := 4) -> ImageTexture:
	var img := Image.create(cols * px, rows * px, true, Image.FORMAT_RGB8)
	for y in rows:
		for x in cols:
			img.fill_rect(Rect2i(x * px, y * px, px, px), b if (x + y) & 1 else a)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func stripe_texture(bands: int, a: Color, b: Color) -> ImageTexture:
	var img := Image.create(8, bands * 8, true, Image.FORMAT_RGB8)
	for i in bands:
		img.fill_rect(Rect2i(0, i * 8, 8, 8), b if i & 1 else a)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _mesh(key: String, make: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = make.call()
	return _mesh_cache[key]


## Upper half of a torus in the XY plane (u 0..PI), UV u along the arc, v around the tube.
static func half_torus(radius: float, tube: float, radial := 10, segments := 40) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments + 1:
		var u := PI * float(i) / segments
		var cu := cos(u)
		var su := sin(u)
		var c := Vector3(radius * cu, radius * su, 0)
		for j in radial + 1:
			var v := TAU * float(j) / radial
			var n := Vector3(cu * cos(v), su * cos(v), sin(v))
			st.set_normal(n)
			st.set_uv(Vector2(float(i) / segments, float(j) / radial))
			st.add_vertex(c + n * tube)
	for i in segments:
		for j in radial:
			var a := i * (radial + 1) + j
			var b := a + radial + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
			st.add_index(a + 1)
	return st.commit()


func _mi(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_gate_visual(gate: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Gate%d" % gate.index
	node.position = Vector3(gate.x, 0, gate.z)
	node.rotation.y = gate.heading
	var half: float = gate.width * 0.5
	var top := PILLAR_BASE + PILLAR_H
	var pillar_mesh := _mesh("pillar", func():
		var c := CylinderMesh.new()
		c.top_radius = PILLAR_R
		c.bottom_radius = PILLAR_R * 1.15
		c.height = PILLAR_H
		c.radial_segments = 14
		c.rings = 1
		return c)
	var cap_mesh := _mesh("cap", func():
		var s := SphereMesh.new()
		s.radius = PILLAR_R * 1.25
		s.height = PILLAR_R * 2.5
		s.radial_segments = 16
		s.rings = 12
		return s)
	var arch_mesh := _mesh("arch%.1f" % gate.width, func(): return half_torus(half, ARCH_TUBE))
	var banner_mesh := _mesh("banner", func():
		var p := PlaneMesh.new()
		p.orientation = PlaneMesh.FACE_Z
		p.size = Vector2(6, 2.2)
		p.subdivide_width = 8
		p.subdivide_depth = 3
		return p)
	var pole_mesh := _mesh("pole", func():
		var c := CylinderMesh.new()
		c.top_radius = 0.12
		c.bottom_radius = 0.12
		c.height = 3.2
		c.radial_segments = 6
		return c)

	for sx in [-1.0, 1.0]:
		_mi(pillar_mesh, _mats.pillar, Vector3(sx * half, PILLAR_BASE + PILLAR_H * 0.5, 0), node)
		gate.caps.append(_mi(cap_mesh, _mats.plain_far, Vector3(sx * half, top, 0), node))
	# The half torus lies in the local XY plane (x = across, y = up): exactly the arch.
	gate.arch = _mi(arch_mesh, _mats.plain_far, Vector3(0, top, 0), node)
	_mi(pole_mesh, _mats.pillar, Vector3(0, top + half + 1.4, 0), node)
	# Banner hangs off the pole toward +X; the shader flutters its free end.
	gate.banner = _mi(banner_mesh, _mats.banner_finish if gate.is_finish else _mats.banner_plain, Vector3(3.0, top + half + 1.9, 0), node)
	gate.node = node
	add_child(node)


func _build_arrow() -> void:
	if _arrow:
		return
	var grp := Node3D.new()
	grp.name = "Arrow"
	# Flat, wide arrow (read from behind and above): a slab shaft and a big flattened pyramid head.
	var shaft_mesh := _mesh("arrow_shaft", func():
		var b := BoxMesh.new()
		b.size = Vector3(1.1, 0.35, 2.6)
		return b)
	var head_mesh := _mesh("arrow_head", func():
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 1.6
		c.height = 2.0
		c.radial_segments = 4
		return c)
	_mi(shaft_mesh, _mats.arrow, Vector3(0, 0, -0.6), grp)
	var head := _mi(head_mesh, _mats.arrow, Vector3(0, 0, 1.7), grp)
	# Cone axis +Y -> +Z, turned 45 deg so a flat face is on top, squashed to a slab.
	head.transform = Transform3D(Basis.from_scale(Vector3(1, 0.35, 1)) * Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.UP, PI / 4), Vector3(0, 0, 1.7))
	grp.visible = not player.is_empty()
	_arrow = grp
	add_child(grp)


# ------------------------------------------------------------ progress
func _side_of(p: Vector3, gate: Dictionary) -> float:
	return (p.x - gate.x) * gate.dir.x + (p.z - gate.z) * gate.dir.z


func _check_gate(r: Dictionary) -> void:
	if r.next_gate >= gates.size():
		return
	var gate: Dictionary = gates[r.next_gate]
	var b: Node = r.body
	var p := body_pos(b)
	var s := _side_of(p, gate)
	if r.prev_s < 0.0 and s >= 0.0:
		var lateral: float = (p.x - gate.x) * gate.right.x + (p.z - gate.z) * gate.right.z
		var tol: float = gate.width * 0.5 + maxf(1.0, hull_num(b, "width", 2.0) * 0.5)
		var v := body_vel(b)
		var forwards: bool = v.x * gate.dir.x + v.z * gate.dir.z > 0.0
		if absf(lateral) <= tol and forwards:
			_pass_gate(r, gate)
	r.prev_s = s


func _pass_gate(r: Dictionary, gate: Dictionary) -> void:
	var n := gates.size()
	r.gates_total += 1
	gate_passed.emit(r.boat, gate.index)
	var first_start_crossing: bool = gate.index == 0 and _start_behind and r.gates_total == 1
	if gate.index == 0 and not first_start_crossing:
		if not r.finished and r.lap >= laps:
			r.finished = true
			r.finish_time = time
			_finished_count += 1
			r.place = _finished_count
			r.progress = 1.0
			if r.is_player:
				state = "finished"
			finished.emit(r.boat, r.place, r.finish_time)
		else:
			r.lap += 1
			if not r.finished:
				lap.emit(r.boat, r.lap)
	r.next_gate = (gate.index + 1) % n
	r.prev_s = _side_of(body_pos(r.body), gates[r.next_gate])


func _progress_of(r: Dictionary) -> void:
	var n := gates.size()
	if n == 0 or r.next_gate >= n:
		r.progress = 0.0
		return
	var gate: Dictionary = gates[r.next_gate]
	var p := body_pos(r.body)
	r.dist_next = _dist_to_gate(p, gate)
	var prev: Dictionary = gates[(r.next_gate - 1 + n) % n]
	var frac := clampf(1.0 - r.dist_next / prev.seg_len, 0.0, 1.0)
	var leg_index: int = n if r.next_gate == 0 else r.next_gate   # legs completed this lap + 1
	r.lap_progress = clampf((leg_index - 1 + frac) / n, 0.0, 1.0)
	if r.gates_total == 0 and _start_behind:
		r.lap_progress = 0.0   # still behind the start line
	r.raw = r.lap - 1 + r.lap_progress            # in laps, unbounded for AI after finishing
	r.progress = 1.0 if r.finished else clampf(r.raw / laps, 0.0, 1.0)


func _dist_to_gate(p: Vector3, gate: Dictionary) -> float:
	return Vector2(gate.x - p.x, gate.z - p.z).length()


func _update_standings() -> void:
	var boats := _boats()
	var list: Array = racers.filter(func(r): return _alive(r, boats))
	list.sort_custom(func(a, b):
		if a.finished != b.finished:
			return a.finished
		if a.finished and b.finished:
			return a.finish_time < b.finish_time
		if a.gates_total != b.gates_total:
			return a.gates_total > b.gates_total
		return a.dist_next < b.dist_next)
	standings = []
	for i in list.size():
		var r: Dictionary = list[i]
		r.position = i + 1
		var p := body_pos(r.body)
		standings.append({
			"boat": r.boat, "name": label_of(r.boat), "lap": mini(r.lap, laps), "gate": r.next_gate,
			"position": r.position, "progress": r.progress, "finished": r.finished, "finish_time": r.finish_time,
			"gates_total": r.gates_total, "ai": not r.is_player, "speed_kmh": body_speed(r.body) * 3.6,
			"stuck_nudges": int(r.ai.get("stuck", 0)), "x": p.x, "y": p.y, "z": p.z,
		})


func _freeze_all() -> void:
	for r in racers:
		var b: Node = r.body
		b.set("throttle", 0.0)
		b.set("steer", 0.0)
		b.set("boost", 0.0)
		if is_sub(b):
			b.set("dive", 0.0)


# ---------------------------------------------------------------- AI
func _drive(r: Dictionary, dt: float) -> void:
	var b: Node = r.body
	var ai: Dictionary = r.ai
	var n := gates.size()
	var gate: Dictionary = gates[r.next_gate]
	var after: Dictionary = gates[(r.next_gate + 1) % n]
	var p := body_pos(b)
	var fwd := body_fwd(b)
	var lat_axis := body_lat(b)
	var heading := body_heading(b)
	var max_speed := hull_num(b, "max_speed", 20.0)
	var speed := maxf(0.0, body_vel(b).dot(fwd))
	var speed_k := clampf(speed / max_speed, 0.0, 1.2)
	var dist: float = r.dist_next
	var half: float = gate.width * 0.5

	# Aim point on the gate line: cut toward the side the following gate is on, plus this
	# driver's preferred lane, never closer than 40 % to a pillar.
	var to_after_lat: float = (after.x - gate.x) * gate.right.x + (after.z - gate.z) * gate.right.z
	var offset: float = clampf(to_after_lat * 0.25, -half * 0.45, half * 0.45) + ai.lane * half
	offset = clampf(offset, -half * 0.6, half * 0.6)
	var ax: float = gate.x + gate.right.x * offset
	var az: float = gate.z + gate.right.z * offset
	var desired := bearing(p.x, p.z, ax, az)
	# Very close to the line the bearing gets twitchy: settle onto the gate heading.
	desired = lerp_angle_w(desired, gate.heading, smooth(-dist, -10, -3))
	# Look-ahead: start the turn toward the next leg before the gate.
	var turn_ahead := wrap_angle(bearing(gate.x, gate.z, after.x, after.z) - gate.heading)
	var look_w := smooth(-dist, -28, -6) * 0.45
	desired = lerp_angle_w(desired, bearing(p.x, p.z, after.x, after.z), look_w)
	# A little wobble so nobody drives on rails.
	desired += sin(_t * ai.wobble_hz * TAU + ai.phase) * ai.wobble

	# Terrain avoidance: three probes fanned ahead; steer toward the clear side.
	var avoid := 0.0
	var blocked := 0.0
	var ground := _body_ground(b)
	if ground.is_valid():
		var reach := clampf(speed * 2.2, 20.0, 40.0)
		var sea := 0.0
		var hit := [false, false, false]
		for k in 3:
			var side := k - 1
			var a := heading + side * 0.45
			var far: float = float(ground.call(p.x + sin(a) * reach, p.z + cos(a) * reach)) - sea
			var near: float = float(ground.call(p.x + sin(a) * reach * 0.5, p.z + cos(a) * reach * 0.5)) - sea
			hit[k] = maxf(far, near) > -1.2
		var left: bool = hit[0]
		var centre: bool = hit[1]
		var right_hit: bool = hit[2]
		if left:
			avoid += 0.7
			blocked += 0.5
		if right_hit:
			avoid -= 0.7
			blocked += 0.5
		if centre:
			blocked += 1.0
			# Turn toward the open side; if both sides are open, toward the next leg.
			if left and not right_hit:
				avoid += 0.9
			elif right_hit and not left:
				avoid -= 0.9
			else:
				avoid += 0.9 if turn_ahead >= 0.0 else -0.9
	# Keep clear of other boats just ahead.
	var crowd := 0.0
	for o in _boats():
		if o == b or not is_instance_valid(o):
			continue
		var d3 := body_pos(o) - p
		var d := d3.length()
		if d > 12.0 or d < 1e-3:
			continue
		if d3.dot(fwd) < 0.0:
			continue
		var lat := d3.dot(lat_axis)
		crowd += (-1.0 if lat >= 0.0 else 1.0) * (1.0 - d / 12.0) * 0.35
	desired += avoid * 0.7 + crowd

	# Proportional steering on heading error, damped by yaw rate. Gain eases off at speed
	# where the hull answers the helm more slowly but swings wide.
	var err := wrap_angle(desired - heading)
	var kp: float = ai.gain * clampf(1.35 - 0.55 * speed_k, 0.75, 1.35)
	var yaw_rate := body_yaw_rate(b)
	# Positive heading error = target toward +X = visual left = negative steer.
	var steer := -clampf(kp * err - ai.damp * yaw_rate, -1.0, 1.0)
	r.steer += (steer - r.steer) * (1.0 - exp(-dt * 7.0))
	b.set("steer", r.steer)

	# Steering assist (AI only): ease the yaw rate toward the commanded turn, capped at
	# 0.35 rad/s, where the hull cannot turn on its own (sailboat off the wind, top speed).
	if ai_assist and body_speed(b) > 1.5 and not bool(b.get("airborne")) and absf(err) > 0.08 and "angular" in b:
		var want := clampf(err * 0.9, -0.35, 0.35)
		var have: float = b.angular.y
		if have * signf(want) < absf(want):
			var ang: Vector3 = b.angular
			ang.y += (want - have) * (1.0 - exp(-dt * 1.2))
			b.angular = ang

	# Throttle: shed speed on the straight before a big corner (70..25 m out), power through it.
	var throttle: float = ai.aggression
	var abs_err := absf(err)
	var braking := smooth(-dist, -70, -25) * (1.0 - smooth(-dist, -18, -6)) * smooth(absf(turn_ahead), 0.4, 1.2) * smooth(speed_k, 0.45, 0.8)
	throttle *= 1.0 - braking * 0.6 * ai.brake
	throttle *= 1.0 - smooth(abs_err, 1.4, 2.6) * 0.4
	if blocked > 0.0:
		throttle *= 0.7
	throttle = maxf(throttle, 0.4)

	# Rubber band against the player, by track distance in metres.
	var boost := 0.0
	if rubber_band and not player.is_empty() and not player.finished and not r.finished:
		var gap_m: float = (r.raw - player.raw) * course_length   # + = AI ahead
		if gap_m > 0.0:
			var cap := lerpf(1.0, 0.55, smooth(gap_m, 55, 95))
			cap = lerpf(cap, 0.3, smooth(gap_m, 150, 240))
			throttle = minf(throttle, maxf(cap, smooth(abs_err, 0.3, 0.9)))
		else:
			boost = 0.72 * smooth(-gap_m, 95, 135) + 0.28 * smooth(-gap_m, 200, 320)
	elif r.finished:
		throttle = minf(throttle, 0.8)   # cruise after finishing
	b.set("throttle", throttle)
	b.set("boost", boost)

	# Stuck: barely moving for 4 s while trying to race. Point at the gate and shove.
	if body_speed(b) < 1.0 and state != "countdown":
		r.stuck_t += dt
	else:
		r.stuck_t = 0.0
	if r.stuck_t > 4.0:
		r.stuck_t = 0.0
		ai.stuck += 1
		var hd := bearing(p.x, p.z, gate.x, gate.z)
		b.set_pose(p.x, _sea_h(p.x, p.z) + 0.3, p.z, hd)
		b.set("velocity", Vector3(sin(hd) * 4.0, 0.0, cos(hd) * 4.0))
		r.steer = 0.0


# ------------------------------------------------------------- visuals
func _update_visuals(dt: float) -> void:
	var n := gates.size()
	if n == 0:
		return
	var next: int = player.get("next_gate", 0) if not player.is_empty() else 0
	var after := (next + 1) % n
	var sample_all := _frame % 3 == 0
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
			_apply_gate_state(gate, st)
		if sample_all or st == "next":
			var y := _sea_h(gate.x, gate.z)
			var node: Node3D = gate.node
			node.position.y += (y - node.position.y) * ((1.0 - exp(-dt * 6.0)) if dt > 0.0 else 1.0)
	_update_arrow(dt)


func _apply_gate_state(gate: Dictionary, st: String) -> void:
	var mat: Material = _mats[("finish_" if gate.is_finish else "plain_") + st]
	gate.arch.material_override = mat
	for c in gate.caps:
		c.material_override = mat


func _update_arrow(dt: float) -> void:
	if _arrow == null or player.is_empty():
		return
	var gate := _gate_of_player()
	var hide: bool = player.finished or state == "disposed" or gate.is_empty()
	_arrow.visible = not hide
	if hide:
		return
	var p := body_pos(player.body)
	var yaw := bearing(p.x, p.z, gate.x, gate.z)
	_arrow_yaw = lerp_angle_w(_arrow_yaw, yaw, 1.0 - exp(-dt * 5.0)) if dt > 0.0 else yaw
	var h := 4.0 if hull_num(player.body, "length", 6.0) < 4.0 else 6.0
	_arrow.position = Vector3(p.x, p.y + h + sin(_t * 2.2) * 0.35, p.z)
	_arrow.rotation = Vector3(0, _arrow_yaw, 0)
	# Nose down ~20 deg so the head is visible from the chase camera behind.
	_arrow.rotate_object_local(Vector3.RIGHT, 0.35)


func _passed_this_lap(r: Dictionary, i: int) -> bool:
	if r.gates_total == 0:
		return false
	if r.next_gate == 0:
		return i != 0   # heading back to the start line: everything else is done
	return i < r.next_gate


# ------------------------------------------------------------ game access
func _boats() -> Array:
	if game and "boats" in game and game.boats is Array:
		return game.boats
	return []


func _player_body() -> Node:
	if game and "player" in game:
		var p = game.player
		if p is Node and is_instance_valid(p):
			return p
	return null


func _alive(r: Dictionary, boats: Array) -> bool:
	return is_instance_valid(r.boat) and boats.has(r.boat)


func _ground_fn() -> Callable:
	if world_def.has("height_at") and world_def.height_at is Callable:
		return world_def.height_at
	if game and "world" in game and game.world != null and game.world.has_method("height_at"):
		return Callable(game.world, "height_at")
	return Callable()


func _body_ground(b: Node) -> Callable:
	var g = b.get("ground_fn")
	if g is Callable and g.is_valid():
		return g
	return Callable()


func _sea_h(x: float, z: float) -> float:
	if game and "ocean" in game and game.ocean != null and game.ocean.has_method("height_at"):
		return game.ocean.height_at(x, z)
	return 0.0


# ------------------------------------------------------------ body helpers (duck-typed)
static func body_pos(b: Node) -> Vector3:
	return (b as Node3D).global_position


static func body_heading(b: Node) -> float:
	if "heading" in b:
		return b.heading
	var f: Vector3 = (b as Node3D).global_basis.z
	return atan2(f.x, f.z)


static func body_fwd(b: Node) -> Vector3:
	var h := body_heading(b)
	return Vector3(sin(h), 0, cos(h))


## The +X side of the hull at heading 0 (the web game `right`; visually the boat's LEFT).
static func body_lat(b: Node) -> Vector3:
	var h := body_heading(b)
	return Vector3(cos(h), 0, -sin(h))


static func body_vel(b: Node) -> Vector3:
	var v = b.get("velocity")
	return v if v is Vector3 else Vector3.ZERO


static func body_speed(b: Node) -> float:
	var s = b.get("speed")
	return float(s) if s != null else body_vel(b).length()


static func body_yaw_rate(b: Node) -> float:
	var a = b.get("angular")
	if a is Vector3:
		return a.y
	var y = b.get("yaw_rate")
	return float(y) if y != null else 0.0


static func is_sub(b: Node) -> bool:
	return bool(b.get("is_sub"))


static func hull_of(b: Node) -> Dictionary:
	var h = b.get("hull")
	return h if h is Dictionary else {}


## Hull number by snake_case key, also accepting the web camelCase spelling.
static func hull_num(b: Node, key: String, default: float) -> float:
	var h := hull_of(b)
	if h.has(key):
		return float(h[key])
	var camel := key.to_camel_case()
	if h.has(camel):
		return float(h[camel])
	return default


static func label_of(boat: Node) -> String:
	if boat.has_meta("label"):
		return String(boat.get_meta("label"))
	if boat.has_meta("boat_id"):
		return String(boat.get_meta("boat_id"))
	return boat.name


static func wrap_angle(a: float) -> float:
	return atan2(sin(a), cos(a))


static func lerp_angle_w(a: float, b: float, t: float) -> float:
	return a + wrap_angle(b - a) * t


static func smooth(x: float, e0: float, e1: float) -> float:
	return smoothstep(e0, e1, x)


static func bearing(fx: float, fz: float, tx: float, tz: float) -> float:
	return atan2(tx - fx, tz - fz)
