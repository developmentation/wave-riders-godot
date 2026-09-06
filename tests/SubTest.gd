extends Node3D
## Submarine module test: StubOcean + The Deep Run + a player sub on the input map (throttle /
## steer_left / steer_right / dive_down / dive_up) with a local chase camera (12 m behind, 4 m
## above, under the surface once the sub is deeper than 3 m), emissive hoop rings at the def's
## gate positions (SubRace builds the real ones) and two AI subs following the hoops.
##   node tools/godot-run.mjs --seconds 16 --tag sub --scene res://tests/SubTest.tscn --script "throttle:4,dive_down:5,throttle:7" --every 3

const SubmarineScene := preload("res://boats/Submarine.tscn")
const SubmarineWorldScript := preload("res://worlds/SubmarineWorld.gd")

@onready var _ocean: Node3D = $Ocean
@onready var _cam: Camera3D = $Camera3D

var _world: SubmarineWorld
var _player: SubPhysics
var _ais: Array[SubPhysics] = []
var _ai_gate: Array[int] = []
var _ai_throttle: Array[float] = [0.9, 0.8]
var _cam_pos := Vector3.ZERO
var _cam_depth := 0.0
var _t := 0.0


func _ready() -> void:
	_world = SubmarineWorldScript.new()
	_world.name = "World"
	add_child(_world)
	_world.build("deep")
	var def := _world.def
	_ocean.set_weather(def.weather.patch, true)

	var start: Dictionary = def.start
	_player = _spawn(start.x, start.z, start.heading, 0)
	_ais.append(_spawn(start.x - 7.0, start.z - 10.0, start.heading, 1))
	_ais.append(_spawn(start.x + 7.0, start.z - 10.0, start.heading, 2))
	_ai_gate = [0, 0]
	_build_hoops(def.gates)

	_cam_pos = _player.position + Vector3(0, 4, -12)
	_cam.position = _cam_pos
	_cam.look_at(_player.position + Vector3(0, 0, 6), Vector3.UP)
	_cam.fov = 58.0
	_cam.near = 0.2
	_cam.far = 1500.0
	add_to_group("harness_state")
	var vis: SubmarineVisual = _player.get_node("Visual")
	print("[SubTest] sub visual %d triangles; %d seabed+kelp triangles" % [vis.triangles, _world.triangles])


func _spawn(x: float, z: float, heading: float, color: int) -> SubPhysics:
	var sub: SubPhysics = SubmarineScene.instantiate()
	sub.name = "Sub%d" % color
	var vis: SubmarineVisual = sub.get_node("Visual")
	vis.color_index = color
	sub.ground_fn = _world.height_at
	sub.ceiling_fn = _ocean.height_at
	add_child(sub)
	var s: float = _ocean.height_at(x, z)
	sub.set_pose(x, s - 0.5, z, heading)
	return sub


func _build_hoops(gates: Array) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 1.0, 0.35)
	mat.emission_energy_multiplier = 2.5
	mat.roughness = 0.5
	var root := Node3D.new()
	root.name = "Hoops"
	add_child(root)
	for g in gates:
		var t := TorusMesh.new()
		t.inner_radius = g.width / 2.0 - 0.35
		t.outer_radius = g.width / 2.0 + 0.35
		t.rings = 28
		t.ring_segments = 6
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.material_override = mat
		# TorusMesh lies in XZ (axis Y); stand it up and face it along the gate heading.
		mi.transform = Transform3D(Basis(Vector3.UP, g.heading) * Basis(Vector3.RIGHT, PI / 2), Vector3(g.x, g.y, g.z))
		root.add_child(mi)


func _process(dt: float) -> void:
	_t += dt
	# player input
	_player.throttle = Input.get_action_strength("throttle") - 0.5 * Input.get_action_strength("brake")
	_player.steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	_player.dive = Input.get_action_strength("dive_up") - Input.get_action_strength("dive_down")
	_player.boost = Input.get_action_strength("boost")
	if Input.is_action_just_pressed("reset_boat"):
		_player.rescue()
	# AI: steer and dive toward the next hoop
	var gates: Array = _world.def.gates
	for i in _ais.size():
		var b := _ais[i]
		var gi := _ai_gate[i]
		var g: Dictionary = gates[gi]
		var target := Vector3(g.x, g.y, g.z)
		var to := target - b.position
		var dist_xz := Vector2(to.x, to.z).length()
		var err := wrapf(atan2(to.x, to.z) - b.heading, -PI, PI)
		b.throttle = _ai_throttle[i] * (1.0 if absf(err) < 1.2 else 0.5)
		b.steer = clampf(-err * 1.6, -1.0, 1.0)
		b.dive = clampf(to.y * 0.15, -1.0, 1.0)
		var gate_fwd := Vector3(sin(g.heading), 0.0, cos(g.heading))
		var passed := Vector3(to.x, 0.0, to.z).dot(gate_fwd) < 0.0 and dist_xz < 30.0
		if dist_xz < maxf(g.width * 0.5, 6.0) or passed:
			_ai_gate[i] = (gi + 1) % gates.size()
	# chase camera: 12 m behind, 4 m above, looking along the sub's forward
	var fwd := _player.forward
	var fxz := Vector3(fwd.x, 0.0, fwd.z).normalized() if Vector2(fwd.x, fwd.z).length() > 1e-3 else Vector3(0, 0, 1)
	var want := _player.position - fxz * 12.0 + Vector3(0, 4, 0)
	var surf: float = _ocean.height_at(want.x, want.z)
	if _player.depth > 3.0:
		want.y = minf(want.y, surf - 1.5)
	else:
		want.y = maxf(want.y, surf + 1.5)
	var ground: float = _world.height_at(want.x, want.z)
	want.y = maxf(want.y, ground + 2.0)
	_cam_pos = _cam_pos.lerp(want, 1.0 - exp(-dt * 5.0))
	_cam.position = _cam_pos
	_cam.look_at(_player.position + fwd * 6.0, Vector3.UP)
	# underwater look follows the lens
	_cam_depth = _ocean.height_at(_cam_pos.x, _cam_pos.z) - _cam_pos.y
	_world.set_submerged(_cam_depth > 0.3, _cam_depth, _cam)
	_world.update(dt, _cam)
	_ocean.set_focus(_player.position.x, _player.position.z)


func get_harness_state() -> Dictionary:
	var p := _player.position
	return {
		"depth": snappedf(_player.depth, 0.01), "kmh": snappedf(_player.speed_kmh, 0.1),
		"pitch_deg": snappedf(rad_to_deg(_player.pitch), 0.1), "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
		"cam_depth": snappedf(_cam_depth, 0.01), "submerged": _world.submerged,
		"ai_gate": _ai_gate.duplicate(), "ai_depth": [snappedf(_ais[0].depth, 0.1), snappedf(_ais[1].depth, 0.1)],
	}
