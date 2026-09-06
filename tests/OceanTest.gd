extends Node3D
## Ocean module test scene. Camera 6 m above the water looking at the horizon; weather cycles
## lagoon -> swell -> tempest every 4 s; a 5x5 grid of floating markers is placed each frame at
## Ocean.sample() heights/normals to prove CPU sampling matches the rendered surface; a half-submerged
## pillar exercises the shore depth fade; a rogue wave is launched during the tempest phase.
## Saves lagoon.png / swell.png / tempest.png into the harness --shots dir and reports the measured
## wave travel direction/speed (least squares on dh/dt = -c . grad h over the coarse grid).
## User args: --quality=low|medium|high|ultra  --hold=<weather id> (no cycling)  --debug=<n> (shader debug view)

const CYCLE := ["lagoon", "swell", "tempest"]
const STEP := 4.0

@onready var ocean: Node3D = $Ocean  # ocean/Ocean.gd (duck-typed so the test parses before the class cache knows Ocean)
@onready var cam: Camera3D = $Camera3D

var markers: Array[MeshInstance3D] = []
var pillar: MeshInstance3D
var t := 0.0
var phase := -1
var shots_dir := ""
var shots_done := {}
var quality := "medium"
var hold := ""
var cam_y := 6.0
var rogue_spawned := false
var wave_dir_deg := 0.0
var wave_speed := 0.0
var marker_mean := 0.0
var _busy := false
var stats := false
var _stats: Dictionary = {}
var ab: Dictionary = {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			quality = a.get_slice("=", 1)
		elif a.begins_with("--shots="):
			shots_dir = a.get_slice("=", 1)
		elif a.begins_with("--hold="):
			hold = a.get_slice("=", 1)
		elif a.begins_with("--debug="):
			ocean.debug_view = int(a.get_slice("=", 1))
		elif a == "--stats":
			stats = true
		elif a.begins_with("--ab="):
			for flag in a.get_slice("=", 1).split("+"):
				ab[flag] = true
	add_to_group("harness_state")
	ocean.set_quality(quality)
	ocean.debug_flags = ab
	var sky: Node = ocean.get_node_or_null("SkyWeather")
	if ab.has("nowater"):
		ocean.get_node("Surface").visible = false
	if ab.has("nosky") and sky:
		sky.clouds.visible = false
		sky.rain.visible = false
		sky.environment.glow_enabled = false
	if ab.has("noshadow") and sky:
		sky.sun.shadow_enabled = false
	if ab.has("nomsaa"):
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var first := hold if hold != "" else CYCLE[0]
	ocean.set_weather(OceanPresets.get_weather(first), true)
	phase = 0
	cam.position = Vector3(0.0, 6.0, 0.0)
	cam.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	cam.fov = 55.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 0.18, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.25, 0.1)
	mat.roughness = 0.6
	for i in 25:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = mat
		add_child(m)
		markers.append(m)
	pillar = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.6
	cyl.height = 12.0
	pillar.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.85, 0.78, 0.6)
	pillar.material_override = pm
	pillar.position = Vector3(9.0, -2.0, -26.0)
	add_child(pillar)
	ocean.set_focus(0.0, -12.0)


func _process(dt: float) -> void:
	t += dt
	if hold == "":
		var p := int(t / STEP) % CYCLE.size()
		if p != phase:
			phase = p
			ocean.set_weather(OceanPresets.get_weather(CYCLE[p]))
	var wid: String = hold if hold != "" else CYCLE[phase]
	# camera rides the sea 6 m above the surface
	var s: Vector3 = ocean.sample(cam.position.x, cam.position.z)
	cam_y = lerpf(cam_y, 6.0 + s.x, 1.0 - exp(-dt * 2.5))
	cam.position.y = cam_y
	ocean.set_focus(0.0, -12.0)
	# markers on a 5x5 grid, 3 m apart, centred 12 m ahead
	var sum := 0.0
	for i in 25:
		var x := float(i % 5 - 2) * 3.0
		var z := -12.0 + float(i / 5 - 2) * 3.0
		var smp: Vector3 = ocean.sample(x, z)
		var n := Vector3(-smp.y, 1.0, -smp.z).normalized()
		var m := markers[i]
		var basis := Basis()
		var fwd := Vector3.FORWARD
		var right := fwd.cross(n).normalized()
		fwd = n.cross(right).normalized()
		basis.x = right
		basis.y = n
		basis.z = -fwd
		m.global_transform = Transform3D(basis, Vector3(x, smp.x + 0.05, z))
		sum += smp.x
	marker_mean = sum / 25.0
	if wid == "tempest" and not rogue_spawned and t > 5.0:
		rogue_spawned = true
		ocean.spawn_rogue(Vector2(0.0, 1.0), 7.0, 130.0, 220.0)
	if int(t * 2.0) != int((t - dt) * 2.0):
		_estimate_wave_velocity()
		if stats and t > 1.0:
			_stats = ocean.debug_map_stats()
			print("MAPSTATS ", JSON.stringify(_stats))
	# per-weather screenshots near the end of each phase
	if shots_dir != "" and hold == "" and not _busy:
		var local := t - float(phase) * STEP
		if local > 3.55 and not shots_done.has(wid):
			shots_done[wid] = true
			_shot(wid)


func _estimate_wave_velocity() -> void:
	# dh/dt = -(c . grad h) least squares over a 13x13 patch of the coarse grid
	var a11 := 0.0
	var a12 := 0.0
	var a22 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	for iz in 13:
		for ix in 13:
			var x := float(ix - 6) * 12.0
			var z := -12.0 + float(iz - 6) * 12.0
			var smp: Vector3 = ocean.sample(x, z)
			var dhdt: float = ocean.last_dhdt
			a11 += smp.y * smp.y
			a12 += smp.y * smp.z
			a22 += smp.z * smp.z
			b1 += -dhdt * smp.y
			b2 += -dhdt * smp.z
	var det := a11 * a22 - a12 * a12
	if absf(det) < 1e-9:
		return
	var cx := (b1 * a22 - b2 * a12) / det
	var cz := (a11 * b2 - a12 * b1) / det
	wave_speed = Vector2(cx, cz).length()
	wave_dir_deg = rad_to_deg(atan2(cx, cz))


func _shot(name: String) -> void:
	_busy = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [shots_dir, name]
	img.save_png(path)
	print("SHOT ", path)
	_busy = false


func get_harness_state() -> Dictionary:
	return {
		"weather": hold if hold != "" else CYCLE[phase],
		"t": snappedf(t, 0.1),
		"cam_y": snappedf(cam_y, 0.01),
		"marker_mean_h": snappedf(marker_mean, 0.01),
		"wave_dir_deg": snappedf(wave_dir_deg, 0.1),
		"wave_speed": snappedf(wave_speed, 0.1),
		"wind_dir_deg": snappedf(float(ocean.weather.wind_dir_deg), 0.1),
		"gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()), 0.01),
		"cpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()), 0.01),
	}
