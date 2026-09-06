class_name StubSub
extends Node3D
## Stand-in for boats/SubPhysics.gd (the web Submarine.js SubPhysics surface) so SubRace and the
## underwater flow can be tested before the real submarine lands. Full 3D motion: thrust along the
## nose, `dive` (+up) drives vertical speed and pitch, yaw like the boat stub, seabed via ground_fn,
## surface via ceiling_fn (never above the water). heading 0 = +Z, growing toward +X.

const G := 9.81

var hull: Dictionary = StubHulls.HULLS.sub
var boat_id := "sub"
var color_index := 0
var throttle := 0.0
var steer := 0.0
var boost := 0.0
var dive := 0.0
var velocity := Vector3.ZERO
var angular := Vector3.ZERO
var forward := Vector3(0, 0, 1)
var right := Vector3(1, 0, 0)
var up := Vector3.UP
var heading := 0.0
var pitch := 0.0
var roll := 0.0
var depth := 0.0
var surface_y := 0.0
var speed := 0.0
var speed_kmh := 0.0
var submersion := 1.0
var airborne := false
var slap_impulse := 0.0
var wake_strength := 0.0
var is_sub := true
var beached_time := 0.0
var scrape := 0.0
var ground_fn: Callable
var ceiling_fn: Callable
var ocean: Node
var _visual: Node3D


func _ready() -> void:
	if _visual == null:
		build_placeholder_visual()


func configure(sea: Node, color: int = 0) -> void:
	ocean = sea
	color_index = color
	set_meta("boat_id", "sub")
	set_meta("label", "Submarine")
	if not ceiling_fn.is_valid() and sea and sea.has_method("height_at"):
		ceiling_fn = Callable(sea, "height_at")


func build_placeholder_visual() -> void:
	var col: Color = StubHulls.COLORS[color_index % StubHulls.COLORS.size()]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.35
	var grp := Node3D.new()
	grp.name = "Visual"
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = hull.get("width", 2.0) * 0.5
	cap.height = hull.get("length", 7.5)
	body.mesh = cap
	body.material_override = mat
	body.rotation.x = PI / 2
	grp.add_child(body)
	var tower := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.9, 1.1, 1.8)
	tower.mesh = tb
	tower.material_override = mat
	tower.position = Vector3(0, 1.3, 0.4)
	grp.add_child(tower)
	var fin := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(3.2, 0.15, 1.0)
	fin.mesh = fb
	fin.material_override = mat
	fin.position = Vector3(0, 0, -3.2)
	grp.add_child(fin)
	_visual = grp
	add_child(grp)


func _surface(x: float, z: float) -> float:
	if ceiling_fn.is_valid():
		return ceiling_fn.call(x, z)
	if ocean and ocean.has_method("height_at"):
		return ocean.height_at(x, z)
	return 0.0


func _ground(x: float, z: float) -> float:
	return ground_fn.call(x, z) if ground_fn.is_valid() else -60.0


func set_pose(x: float, y: float, z: float, heading_rad: float) -> void:
	position = Vector3(x, y, z)
	heading = heading_rad
	pitch = 0.0
	roll = 0.0
	velocity = Vector3.ZERO
	angular = Vector3.ZERO
	surface_y = _surface(x, z)
	depth = maxf(0.0, surface_y - y)
	_sync_axes()


func reset() -> void:
	var p := position
	var y := p.y
	if ground_fn.is_valid():
		y = maxf(y, _ground(p.x, p.z) + hull.get("radius", 1.0) + 2.0)
	y = minf(y, _surface(p.x, p.z) - 0.5)
	set_pose(p.x, y, p.z, heading)


func rescue() -> void:
	var s := _surface(position.x, position.z)
	var want_y := minf(position.y, s - 0.5)
	if ground_fn.is_valid():
		want_y = maxf(want_y, _ground(position.x, position.z) + 4.0)
	set_pose(position.x, minf(want_y, s - 0.5), position.z, heading)


func _sync_axes() -> void:
	var cp := cos(pitch)
	forward = Vector3(sin(heading) * cp, sin(pitch), cos(heading) * cp)
	right = Vector3(cos(heading), 0, -sin(heading))
	rotation = Vector3.ZERO
	rotation.y = heading
	rotate_object_local(Vector3.RIGHT, -pitch)
	rotate_object_local(Vector3.FORWARD, roll)
	up = basis.y


func update(dt: float, _wind: Dictionary = {}) -> void:
	var steps := maxi(1, ceili(dt / (1.0 / 60.0)))
	var h := dt / steps
	for i in steps:
		_step(h)
	speed = velocity.length()
	speed_kmh = speed * 3.6
	slap_impulse *= exp(-dt * 4.0)


func _step(dt: float) -> void:
	var m: float = hull.get("mass", 5000.0)
	var max_speed: float = hull.get("max_speed", 13.0)
	surface_y = _surface(position.x, position.z)
	depth = maxf(0.0, surface_y - position.y)
	submersion = clampf(depth / 2.0, 0.0, 1.0)
	airborne = false
	var flat_fwd := Vector3(sin(heading), 0, cos(heading))
	var v_long := velocity.dot(flat_fwd)
	var v_lat := velocity.dot(right)

	var thr := clampf(throttle, -0.5, 1.0)
	var boost_f := 1.0 + boost * 0.35
	var thrust_n: float = hull.get("thrust", 20000.0) * thr * boost_f
	thrust_n *= clampf((1.0 - absf(v_long) / (max_speed * boost_f)) * 4.0, 0.0, 1.0)
	var acc := flat_fwd * (thrust_n / m)
	var area: float = hull.get("length", 7.5) * hull.get("width", 2.0)
	acc += flat_fwd * (-0.5 * 1000.0 * hull.get("drag_long", 0.06) * area * 0.08 * v_long * absf(v_long) / m)
	acc += right * ((-m * 2.2 * v_lat - 0.5 * 1000.0 * hull.get("drag_lat", 2.0) * area * 0.08 * v_lat * absf(v_lat)) / m)

	# Yaw
	var steer_in := -steer
	var authority: float = absf(thr) * hull.get("steer_torque", 0.8) * 1.4 + hull.get("rudder_lift", 0.5) * absf(v_long) * 0.16
	angular.y += (steer_in * minf(authority, 1.8) * (0.4 + 0.6 * clampf(absf(v_long) / 3.0, 0, 1)) - angular.y * 1.5) * dt
	var max_yaw: float = hull.get("max_yaw", 0.7)
	angular.y = clampf(angular.y, -max_yaw, max_yaw)
	heading = wrapf(heading + angular.y * dt, -PI, PI)

	# Vertical: ballast + planes. dive +1 = up. Slow vertical speed, faster with way on.
	var want_vy := clampf(dive, -1, 1) * (2.0 + 2.5 * clampf(absf(v_long) / max_speed, 0, 1))
	var vy := velocity.y + (want_vy - velocity.y) * (1.0 - exp(-dt * 1.8))
	var target_pitch := clampf(atan2(vy, maxf(absf(v_long), 2.0)), -0.5, 0.5)
	pitch += (target_pitch - pitch) * (1.0 - exp(-dt * 2.5))
	roll += (-angular.y * 0.25 - roll) * (1.0 - exp(-dt * 2.0))

	velocity.x += acc.x * dt
	velocity.z += acc.z * dt
	velocity.y = vy

	# Seabed
	scrape = 0.0
	if ground_fn.is_valid():
		var rad: float = hull.get("radius", 1.0)
		var g := _ground(position.x, position.z)
		var pen := g + rad - position.y
		if pen > 0.0:
			position.y = g + rad
			if velocity.y < 0:
				velocity.y = 0.0
			velocity.x *= exp(-dt * 3.0)
			velocity.z *= exp(-dt * 3.0)
			scrape = clampf(pen, 0, 1)
		# Look ahead: a wall in front stops the sub.
		var ahead: Vector3 = position + flat_fwd * (hull.get("length", 7.5) * 0.5)
		var ga := _ground(ahead.x, ahead.z)
		if ga > position.y - rad * 0.5:
			var vn := velocity.dot(flat_fwd)
			if vn > 0:
				velocity -= flat_fwd * vn
				velocity -= flat_fwd * 1.5
			scrape = 1.0
	position += Vector3(velocity.x, 0, velocity.z) * dt
	position.y += velocity.y * dt
	# Surface ceiling: the deck may break the surface, the hull never flies.
	var s := _surface(position.x, position.z)
	if position.y > s - 0.5:
		position.y = s - 0.5
		if velocity.y > 0:
			velocity.y = 0.0
	_sync_axes()
	wake_strength = clampf(absf(v_long) / max_speed, 0, 1) * (1.0 - submersion)
