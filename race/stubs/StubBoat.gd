class_name StubBoat
extends Node3D
## Stand-in for boats/BoatPhysics.gd with the same public surface (see docs/GODOT-PORT.md), so the
## race, the game flow and the AI can be exercised before the real hull physics lands.
## Planar dynamics: thrust with the web game speed governor, quadratic drag, an outboard-style
## yaw model capped per hull, the boat riding the sampled sea (height + slope -> pitch/roll),
## land contact via ground_fn, beaching + rescue. Heading convention as the web game:
## heading 0 = +Z, growing toward +X (rotation.y = heading); +steer turns the bow to the visual right.

const G := 9.81
const WATER_RHO := 1000.0

var hull: Dictionary = StubHulls.HULLS.speedboat
var boat_id := "speedboat"
var color_index := 0
var throttle := 0.0
var steer := 0.0
var boost := 0.0
var dive := 0.0
var velocity := Vector3.ZERO
var angular := Vector3.ZERO          # world-space angular velocity; .y is the yaw rate (rad/s)
var forward := Vector3(0, 0, 1)
var right := Vector3(1, 0, 0)        # +X side of the hull (the web game `right`; visually the LEFT side)
var up := Vector3.UP
var heading := 0.0
var speed := 0.0
var speed_kmh := 0.0
var submersion := 1.0
var airborne := false
var slap_impulse := 0.0
var wake_strength := 0.0
var is_sub := false
var beached_time := 0.0
var ground_fn: Callable
var ocean: Node                      # anything with height_at(x, z) / sample(x, z)

var _pitch := 0.0
var _roll := 0.0
var _vy := 0.0
var _visual: Node3D
var _prev_wet := true


func _ready() -> void:
	if _visual == null:
		build_placeholder_visual()


func configure(id: String, h: Dictionary, sea: Node, color: int = 0) -> void:
	boat_id = id
	hull = h
	ocean = sea
	color_index = color
	set_meta("boat_id", id)
	set_meta("label", String(h.get("label", id)))


## Box hull + a cone bow, like Game.js placeholderHull. Used when no Boats.build_visual exists.
func build_placeholder_visual() -> void:
	var w: float = hull.get("width", 2.0)
	var l: float = hull.get("length", 6.0)
	var col: Color = StubHulls.COLORS[color_index % StubHulls.COLORS.size()]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.4
	var grp := Node3D.new()
	grp.name = "Visual"
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w, w * 0.45, l)
	body.mesh = box
	body.material_override = mat
	body.position.y = w * 0.1
	grp.add_child(body)
	var bow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = w * 0.5
	cone.height = l * 0.35
	cone.radial_segments = 4
	bow.mesh = cone
	bow.material_override = mat
	bow.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.UP, PI / 4), Vector3(0, w * 0.1, l * 0.5 + l * 0.17))
	grp.add_child(bow)
	var cabin := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(w * 0.6, w * 0.4, l * 0.25)
	cabin.mesh = cb
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.95, 0.95, 0.9)
	cabin.material_override = cm
	cabin.position = Vector3(0, w * 0.5, -l * 0.05)
	grp.add_child(cabin)
	_visual = grp
	add_child(grp)


func set_pose(x: float, y: float, z: float, heading_rad: float) -> void:
	position = Vector3(x, y, z)
	heading = heading_rad
	velocity = Vector3.ZERO
	angular = Vector3.ZERO
	_pitch = 0.0
	_roll = 0.0
	_vy = 0.0
	_sync_axes()


func reset() -> void:
	var h := _sea_h(position.x, position.z)
	set_pose(position.x, h + 0.2, position.z, heading)


## Find open water near the boat and put it back there, facing away from land (web BoatPhysics.rescue).
func rescue() -> void:
	if not ground_fn.is_valid():
		reset()
		return
	var x0 := position.x
	var z0 := position.z
	var r := 6.0
	while r <= 120.0:
		var a := 0.0
		while a < TAU:
			var x := x0 + cos(a) * r
			var z := z0 + sin(a) * r
			if _ground(x, z) < -3.5 and _ground(x + 4, z) < -3 and _ground(x - 4, z) < -3 and _ground(x, z + 4) < -3 and _ground(x, z - 4) < -3:
				set_pose(x, _sea_h(x, z) + 0.2, z, atan2(cos(a), sin(a)))
				return
			a += PI / 12
		r += 6.0
	reset()


func _ground(x: float, z: float) -> float:
	return ground_fn.call(x, z) if ground_fn.is_valid() else -50.0


func _sea_h(x: float, z: float) -> float:
	if ocean and ocean.has_method("height_at"):
		return ocean.height_at(x, z)
	return 0.0


func _sync_axes() -> void:
	forward = Vector3(sin(heading), 0, cos(heading))
	right = Vector3(cos(heading), 0, -sin(heading))
	rotation = Vector3(_pitch, heading, _roll)
	up = basis.y


## Advance the boat. wind = {"angle": rad, "speed": m/s} (sailboats), same as Game.update.
func update(dt: float, wind: Dictionary = {}) -> void:
	var steps := maxi(1, ceili(dt / (1.0 / 60.0)))
	var h := dt / steps
	for i in steps:
		_step(h, wind)
	speed = velocity.length()
	speed_kmh = speed * 3.6
	slap_impulse *= exp(-dt * 4.0)


func _step(dt: float, wind: Dictionary) -> void:
	var m: float = hull.get("mass", 1500.0)
	var max_speed: float = hull.get("max_speed", 20.0)
	var v_long := velocity.dot(forward)
	var v_lat := velocity.dot(right)
	var sea := Vector3.ZERO
	if ocean and ocean.has_method("sample"):
		sea = ocean.sample(position.x, position.z)
	else:
		sea.x = _sea_h(position.x, position.z)
	var surf := sea.x
	var draft: float = hull.get("draft", 0.5)
	var rest_y := surf - draft * 0.15
	var depth := rest_y - position.y
	var wet := depth > -draft * 0.9
	submersion = clampf(1.0 + depth / draft, 0.0, 1.0) if wet else 0.0
	airborne = not wet

	var acc := Vector3.ZERO
	if wet:
		# ---- thrust with the web governor: full to 3/4 of top speed, taper to the cap
		var thr := clampf(throttle, -0.5, 1.0)
		var boost_f := 1.0 + boost * 0.35
		var base_thrust: float = hull.get("thrust", 15000.0)
		var thrust_n := base_thrust * thr * boost_f
		if hull.get("sail", false) and not wind.is_empty():
			var rel := cos(float(wind.get("angle", 0.0)) - heading)
			var eff := clampf(0.45 + 0.55 * sin(acos(clampf(rel, -1, 1))), 0, 1) * (0.7 + 0.3 * minf(1.0, float(wind.get("speed", 5.0)) / 12.0))
			thrust_n = base_thrust * maxf(thr, 0.0) * eff * boost_f + base_thrust * 0.25 * minf(0.0, thr)
		var speed_ratio := absf(v_long) / (max_speed * boost_f)
		thrust_n *= clampf((1.0 - speed_ratio) * 4.0, 0.0, 1.0)
		# Outboard: the thrust vector swings with the helm (visual right = -X side).
		var steer_in := -steer
		var tdir := forward.rotated(Vector3.UP, -steer_in * 0.55)
		acc += tdir * (thrust_n * submersion / m)

		# ---- hydrodynamics (web coefficients)
		var area: float = hull.get("length", 6.0) * hull.get("width", 2.0)
		var f_long: float = -0.5 * WATER_RHO * hull.get("drag_long", 0.06) * area * 0.08 * v_long * absf(v_long) * submersion
		var f_grip := -m * 1.8 * v_lat * submersion
		var f_lat: float = -0.5 * WATER_RHO * hull.get("drag_lat", 1.5) * area * 0.08 * v_lat * absf(v_lat) * submersion
		acc += forward * (f_long / m) + right * ((f_grip + f_lat) / m)
		if v_long < -4.0:
			acc += forward * (-(v_long + 4.0) * 2.0)
		# Wave slope shoves the hull down the face a little.
		acc += Vector3(-sea.y, 0, -sea.z) * G * 0.35

		# ---- yaw: outboard torque grows with throttle, rudder lift with speed; damped and capped
		var authority: float = absf(thr) * hull.get("steer_torque", 0.7) * 1.6 + hull.get("rudder_lift", 0.3) * absf(v_long) * 0.18
		authority = minf(authority, 2.4)
		var yaw_acc := steer_in * authority * (0.35 + 0.65 * clampf(absf(v_long) / 4.0, 0, 1))
		yaw_acc -= angular.y * 1.6
		angular.y += yaw_acc * dt
		var max_yaw: float = hull.get("max_yaw", 1.1)
		angular.y = clampf(angular.y, -max_yaw, max_yaw)
	else:
		acc += Vector3(0, -G, 0)
		acc -= velocity * 0.08
		angular.y *= exp(-dt * 0.6)

	if ground_fn.is_valid():
		_collide_ground(dt)

	velocity.x += acc.x * dt
	velocity.z += acc.z * dt
	heading = wrapf(heading + angular.y * dt, -PI, PI)

	# ---- vertical: ride the surface with a stiff, damped spring; fly off crests at speed
	if wet:
		var spring: float = 60.0 * (1.0 - hull.get("planing", 0.5) * 0.35)
		_vy += (depth * spring - _vy * 9.0) * dt
		var wave_vy := 0.0
		if ocean and ocean.has_method("surface_velocity_y"):
			wave_vy = ocean.surface_velocity_y(position.x, position.z)
		_vy += (wave_vy - _vy) * (1.0 - exp(-dt * 3.0))
		if not _prev_wet and _vy < -2.2:
			slap_impulse = minf(1.0, -_vy / 6.0) * hull.get("bounce", 1.0)
	else:
		_vy -= G * dt
	position.y += _vy * dt
	position.x += velocity.x * dt
	position.z += velocity.z * dt
	velocity.y = _vy
	if position.y < surf - draft * 3.0:
		position.y = surf - draft * 3.0
		_vy = maxf(_vy, 0.0)
	_prev_wet = wet

	# ---- attitude: follow the wave slope, lean into turns, nose up under power
	var slope := Vector3(sea.y, 0, sea.z)
	var slope_pitch := -atan(forward.dot(slope))
	var slope_roll := atan(right.dot(slope))
	var speed_k := clampf(absf(v_long) / max_speed, 0, 1)
	var target_pitch: float = slope_pitch * submersion - 0.10 * hull.get("planing", 0.5) * speed_k * (1.0 - speed_k * 0.5)
	var target_roll: float = slope_roll * submersion * 0.8 - angular.y * speed_k * 0.35 * hull.get("roll", 1.0)
	_pitch += (target_pitch - _pitch) * (1.0 - exp(-dt * 4.0))
	_roll += (target_roll - _roll) * (1.0 - exp(-dt * 3.5))
	_sync_axes()
	wake_strength = clampf(absf(v_long) / max_speed, 0, 1) * submersion

	# Beached: out of the water with land under the hull.
	if ground_fn.is_valid() and _ground(position.x, position.z) > surf - draft:
		beached_time += dt
	else:
		beached_time = 0.0


## Sample bow, stern and both beams; push away from land and kill the velocity into it.
func _collide_ground(dt: float) -> void:
	var l: float = hull.get("length", 6.0)
	var w: float = hull.get("width", 2.0)
	var draft: float = hull.get("draft", 0.5)
	var pts := [forward * (l * 0.45), -forward * (l * 0.45), right * (w * 0.5), -right * (w * 0.5)]
	for lp in pts:
		var p: Vector3 = position + lp
		var g := _ground(p.x, p.z)
		var keel := p.y - draft
		var pen := g - keel
		if pen <= 0.0:
			continue
		var e := 1.0
		var n := Vector3(_ground(p.x - e, p.z) - _ground(p.x + e, p.z), 0, _ground(p.x, p.z - e) - _ground(p.x, p.z + e))
		if n.length_squared() < 1e-6:
			n = -forward
		n = n.normalized()
		var vn := velocity.dot(n)
		var scale := minf(pen, 1.5)
		velocity += n * ((G * 4.0 * scale + maxf(0.0, -vn) * 10.0) * dt)
		velocity.x -= velocity.x * 3.0 * minf(1.0, scale) * dt
		velocity.z -= velocity.z * 3.0 * minf(1.0, scale) * dt
		angular.y *= 1.0 - minf(1.0, scale) * dt * 2.0
