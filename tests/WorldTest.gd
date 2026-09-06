extends Node3D
## World module test: StubOcean + World built from `--world=<id>` (default lagoon), the world's
## weather applied to the stub and a rough sky/sun mapping, emissive cylinders where the gates go,
## and a camera orbiting the start point slowly at 25 m so screenshots show islands, shore foam,
## portals and gate markers.
##   node tools/godot-run.mjs --seconds 10 --tag world-storm --scene res://tests/WorldTest.tscn --script "throttle:10" --extra "--world=storm"

const ORBIT_RADIUS := 55.0
const ORBIT_HEIGHT := 25.0
const ORBIT_PERIOD := 24.0         # seconds per revolution: a 10 s run sweeps 150 deg of horizon

var world: World
var world_id := "lagoon"
var _t := 0.0
var _start := Vector3.ZERO
var _heading := 0.0
var _orbit0 := 0.0
var _radius := ORBIT_RADIUS
var _nofoam := false
var _portal_hits := 0
var _tested := false

@onready var ocean: Node3D = $Ocean
@onready var cam: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var env: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	var at := PackedFloat64Array()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			world_id = a.split("=", true, 1)[1]
		elif a.begins_with("--at="):          # orbit this point instead of the start (x,z)
			for v in a.split("=", true, 1)[1].split(","):
				at.append(float(v))
		elif a.begins_with("--radius="):
			_radius = float(a.split("=", true, 1)[1])
		elif a == "--nofoam":                  # hide the shore foam to inspect the beaches
			_nofoam = true
	if not Worlds.WORLDS.has(world_id):
		push_error("WorldTest: unknown world '%s'" % world_id)
		world_id = "lagoon"
	ocean.add_to_group("ocean")
	world = World.new()
	world.ocean = ocean
	add_child(world)
	world.build(world_id)
	if _nofoam:
		world.shore_foam.visible = false
	Worlds.apply_world_weather(ocean, world.def, true)
	_apply_sky(Worlds.ocean_weather(world.def))
	_build_gate_markers()
	var s: Dictionary = world.def.start
	_start = Vector3(s.x, 0.0, s.z)
	if at.size() >= 2:
		_start = Vector3(at[0], 0.0, at[1])
	_heading = s.heading
	# begin on the far side of the start from the nearest island (so the first frames look at
	# land), then sweep half the horizon over the run
	var nearest := Vector3(s.x + sin(s.heading) * 100.0, 0.0, s.z + cos(s.heading) * 100.0)
	var best := INF
	for isl in world.def.islands:
		var d: float = Vector2(isl.x - s.x, isl.z - s.z).length()
		if d < best:
			best = d
			nearest = Vector3(isl.x, 0.0, isl.z)
	_orbit0 = atan2(_start.x - nearest.x, _start.z - nearest.z)
	ocean.set_focus(_start.x, _start.z)
	_place_camera(0.0)
	add_to_group("harness_state")
	print("[WorldTest] %s: %d islands, %d triangles, %d palms, %d gates, %d portals, %d foam verts, build %d ms" % [
		world_id, world.fields.size(), world.triangles, world.palms, world.def.gates.size(), world.portals.portals.size(),
		world.shore_foam.vertices, world.build_ms])
	# cost of the collision field: 20k samples spread over the course
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	var b: float = world.def.bounds
	for i in 20000:
		acc += world.height_at(fmod(i * 37.1, b * 2.0) - b, fmod(i * 91.7, b * 2.0) - b)
	var us := (Time.get_ticks_usec() - t0) / 20000.0
	print("[WorldTest] height_at: %.2f us per call (%d islands)" % [us, world.fields.size()])


## Simple emissive cylinders where gates go (Race builds the real hoops) + a crossbar for width.
func _build_gate_markers() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 1.0, 0.4)
	mat.emission_energy_multiplier = 2.0
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 28.0
	var gates: Array = world.def.gates
	for i in gates.size():
		var g: Dictionary = gates[i]
		var root := Node3D.new()
		root.position = Vector3(g.x, 0.0, g.z)
		root.rotation.y = g.heading
		var post := MeshInstance3D.new()
		post.mesh = cyl
		post.material_override = mat
		post.position.y = 12.0
		root.add_child(post)
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(g.width, 0.4, 0.4)
		bar.mesh = bm
		bar.material_override = mat
		bar.position.y = 6.0
		root.add_child(bar)
		# nubs on top count the gate index
		for k in i + 1:
			var nub := MeshInstance3D.new()
			var nm := BoxMesh.new()
			nm.size = Vector3(2.4, 0.6, 0.6)
			nub.mesh = nm
			nub.material_override = mat
			nub.position.y = 27.0 + k * 1.2
			root.add_child(nub)
		add_child(root)
	# start line: two short yellow posts
	var smat := StandardMaterial3D.new()
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.85, 0.1)
	smat.emission_energy_multiplier = 2.0
	var s: Dictionary = world.def.start
	var fx := sin(s.heading)
	var fz := cos(s.heading)
	for side: float in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.4
		pc.bottom_radius = 0.4
		pc.height = 8.0
		p.mesh = pc
		p.material_override = smat
		p.position = Vector3(s.x + fz * side * 12.0, 2.0, s.z - fx * side * 12.0)
		add_child(p)


## Rough sky / sun from the ocean weather record (the real Sky module owns this in the game).
func _apply_sky(w: Dictionary) -> void:
	var elev: float = deg_to_rad(w.sun_elev_deg)
	var az: float = deg_to_rad(w.sun_azimuth_deg)
	var dir := Vector3(sin(az) * cos(elev), sin(elev), cos(az) * cos(elev))
	if dir.length() > 0.001:
		sun.look_at_from_position(dir * 100.0, Vector3.ZERO, Vector3.UP)
	var cloud: float = w.cloud_cover
	var storm: float = w.get("storm", 0.0)
	# sun under the horizon: night-dark but legible (the web lights the tempest with the deck's own
	# glow and lightning; the Sky module owns that here)
	var night := clampf(-elev * 3.0, 0.0, 0.35)
	sun.light_energy = lerpf(1.2, 0.35, cloud) * (1.0 - night) * clampf(sin(maxf(elev, 0.08)) * 1.5, 0.2, 1.0)
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.7, 0.45), clampf(1.0 - elev * 4.0, 0.0, 1.0))
	var e: Environment = env.environment
	var sky := e.sky.sky_material as ProceduralSkyMaterial
	var clear_top := Color(0.2, 0.5, 0.9)
	var clear_hor := Color(0.75, 0.85, 0.95)
	var grey_top := Color(0.22, 0.24, 0.28)
	var grey_hor := Color(0.42, 0.44, 0.48)
	sky.sky_top_color = clear_top.lerp(grey_top, storm).darkened(night)
	sky.sky_horizon_color = clear_hor.lerp(grey_hor, storm).darkened(night)
	sky.ground_horizon_color = sky.sky_horizon_color.darkened(0.3)
	sky.ground_bottom_color = Color(0.05, 0.2, 0.35).lerp(Color(0.08, 0.08, 0.1), storm)
	sky.sun_angle_max = lerpf(25.0, 5.0, cloud)
	sky.sun_curve = 0.15
	e.ambient_light_energy = lerpf(1.0, 0.7, storm)
	var fog: float = w.fog + w.rain * 0.3
	e.fog_enabled = fog > 0.05
	e.fog_density = fog * 0.004
	e.fog_light_color = sky.sky_horizon_color
	e.fog_sky_affect = 0.4
	e.tonemap_exposure = maxf(w.get("exposure", 1.0), 0.85)


func _place_camera(t: float) -> void:
	var a := _orbit0 + t * TAU / ORBIT_PERIOD
	var pos := _start + Vector3(sin(a) * _radius, ORBIT_HEIGHT, cos(a) * _radius)
	# look through the start point toward the far side of the orbit so the view sweeps the horizon
	var look := _start - Vector3(sin(a), 0.0, cos(a)) * 60.0 + Vector3(0, 6, 0)
	cam.look_at_from_position(pos, look, Vector3.UP)


func _process(dt: float) -> void:
	_t += dt
	_place_camera(_t)
	Worlds.update_world_events(ocean, world.def, dt, _start)
	# exercise the hit test once with a fake body driven through the first portal
	if not _tested and _t > 0.5 and not world.def.portals.is_empty():
		_tested = true
		var p: Dictionary = world.def.portals[0]
		var n := Vector2(sin(p.heading), cos(p.heading))
		var body := Node3D.new()
		add_child(body)
		body.global_position = Vector3(p.x - n.x * 4.0, 0.3, p.z - n.y * 4.0)
		world.portals.test(body)
		body.global_position = Vector3(p.x + n.x * 4.0, 0.3, p.z + n.y * 4.0)
		var dest := world.portals.test(body)
		if dest != "":
			_portal_hits += 1
			print("[WorldTest] portal hit test -> ", dest)
			world.portals.transition(func() -> void: print("[WorldTest] transition callback"), dest)
		body.queue_free()


func get_harness_state() -> Dictionary:
	var st := world.get_harness_state()
	st["portal_hits"] = _portal_hits
	st["cam"] = [snappedf(cam.global_position.x, 0.1), snappedf(cam.global_position.y, 0.1), snappedf(cam.global_position.z, 0.1)]
	st["events"] = Worlds.event_state(world_id).get("next", {})
	return st
