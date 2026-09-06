extends Node3D
## Boats module test: StubOcean + one player boat driven by Controls with the
## FollowCamera, and every other catalog boat parked in a row ahead so one
## screenshot shows the whole fleet.
##   node tools/godot-run.mjs --seconds 12 --tag boats --scene res://tests/BoatsTest.tscn --script "throttle:5,steer_right:3,throttle:4"
## User args: --boat=<id> (player, default speedboat), --color=<i>, --lineup=0|1,
## --lineup_z=<m> (default 44), --lineup_dx=<m> (default 12), --lineup_yaw=<deg> (default 150),
## --view=<0..2>, --waves=<Hs>. Each can also come from env BOATS_TEST_<KEY> (e.g. BOATS_TEST_BOAT=jetski).

const BOAT_SCENE := preload("res://boats/Boat.tscn")

var player: BoatPhysics
var fleet: Array[BoatPhysics] = []
var cam: FollowCamera
var ocean: Node
var _label: Label
var _prev_slap := 0.0


## `--key=value` user arg, else the BOATS_TEST_<KEY> environment variable
## (tools/godot-run.mjs does not forward extra user args), else the default.
func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv[0] == "--" + key:
			return kv[1] if kv.size() > 1 else default
	var env := OS.get_environment("BOATS_TEST_" + key.to_upper())
	return env if env != "" else default


func _ready() -> void:
	ocean = $Ocean
	cam = $FollowCamera
	_label = $Hud/Label
	var hs := float(_arg("waves", "0.8"))
	ocean.set_weather({"swell_hs": hs})
	var id := _arg("boat", "speedboat")
	if not Boats.CATALOG.has(id) or id == "sub":
		id = "speedboat"
	var color := int(_arg("color", "0"))

	player = _spawn(id, color, 0.0, 0.0, 0.0)
	player.add_to_group("harness_state")
	cam.ocean = ocean
	cam.follow(player)
	cam.view_index = clampi(int(_arg("view", "0")), 0, 2)

	if _arg("lineup", "1") != "0":
		var yaw := deg_to_rad(float(_arg("lineup_yaw", "150")))
		var z0 := float(_arg("lineup_z", "44"))
		var dx := float(_arg("lineup_dx", "12"))
		var ids: Array = []
		for k in Hulls.IDS:
			if k != id:
				ids.append(k)
		var n := ids.size()
		for i in n:
			var x := (i - (n - 1) / 2.0) * dx
			var b := _spawn(ids[i], i % 3, x, z0, yaw)
			fleet.append(b)
			print("[Boats] lineup %s: %d tris, rest height %.2f m" % [ids[i], b.get_node("Visual").triangles, Hulls.rest_height(b.hull)])
	print("[Boats] player %s: %d tris" % [id, player.get_node("Visual").triangles])


func _spawn(id: String, color: int, x: float, z: float, heading: float) -> BoatPhysics:
	var b: BoatPhysics = BOAT_SCENE.instantiate()
	b.name = id
	b.configure(id, color, ocean)
	$Boats.add_child(b)
	b.set_pose(x, ocean.height_at(x, z) + Hulls.rest_height(b.hull), z, heading)
	return b


func _physics_process(_dt: float) -> void:
	# Controls is an autoload processed before us; feed the player before it integrates.
	player.throttle = Controls.throttle
	player.steer = Controls.steer
	player.boost = 1.0 if Controls.boost else 0.0


func _process(dt: float) -> void:
	if Controls.has("reset"):
		player.reset()
	if Controls.has("camera"):
		cam.next_view()
	ocean.set_focus(player.position.x, player.position.z)
	if player.slap_impulse > _prev_slap + 0.2:
		cam.impulse(player.slap_impulse * 0.6)
	_prev_slap = player.slap_impulse
	_label.text = "%s  %.0f km/h  thr %.2f steer %.2f  hdg %.2f  bank %.0f deg  sub %.2f  view %s  Hs %.2f\npos %.1f %.1f %.1f  fps %d" % [
		player.hull.label, player.speed_kmh, player.throttle, player.steer, player.heading,
		rad_to_deg(asin(clampf(player.right.y, -1, 1))), player.submersion, cam.view_name(), ocean.significant_wave_height,
		player.position.x, player.position.y, player.position.z, Engine.get_frames_per_second()]
