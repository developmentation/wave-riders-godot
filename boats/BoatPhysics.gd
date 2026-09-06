class_name BoatPhysics
extends Node3D
## Small-craft rigid body on a sampled sea — port of src/game/BoatPhysics.js.
##
## The hull is a handful of buoyancy points. Each one that sits below the
## sampled surface pushes up with a spring-damper proportional to its
## submersion, so waves genuinely lift, drop, roll and pitch the boat. Thrust
## is applied at the stern and rotates with the steering angle like an
## outboard, so steering authority grows with throttle and a boat coasting
## with the engine off turns slowly. Lateral drag acts below the centre of
## mass, which is what leans a planing hull *into* a turn. A gentle upright
## assist and a roll clamp keep it forgiving for kids.
##
## Units: metres, seconds, kilograms. +Z is the hull's forward axis in local
## space (the Kenney models point +Z too, so the catalog uses yaw 0).
## The node's own transform is the body pose (written once per physics tick).
##
## Steering convention: +steer turns the bow to the boat's visual right (screen
## right when following). The hull faces +Z, so its visual starboard is -X and
## the sign is flipped once inside `_step` (steer_in = -steer).

const G := 9.81
const WATER_RHO := 1000.0
const SUBSTEP := 1.0 / 120.0

## Catalog id used by Boat.tscn to build the visual; the hull table key is
## Boats.CATALOG[boat_id].hull (they coincide for every boat but the sub).
@export var boat_id := "speedboat"
@export var color_index := 0
## Build the visual (Boats.build_visual) on _ready when this node has no "Visual" child.
@export var auto_visual := true
## Integrate in _physics_process. Off for headless sims that call advance() themselves.
@export var simulate := true

var hull: Dictionary
## Ocean node implementing sample(x, z) -> Vector3(h, dh/dx, dh/dz), height_at(x, z),
## surface_velocity_y(x, z) and significant_wave_height. Null = flat calm water.
var ocean: Node = null
## (x, z) -> terrain height; empty Callable = open sea.
var ground_fn: Callable = Callable()
## Wind for the sailboat: {"angle": rad (blows toward (cos, sin)), "speed": m/s}.
## Empty = no point-of-sail model (the web sim's `wind = null`).
var wind := {"angle": 0.0, "speed": 5.0}

# input
var throttle := 0.0   # -0.5 .. 1
var steer := 0.0      # -1 .. 1 (positive = turn right)
var boost := 0.0      # 0..1
var dive := 0.0       # submarine only; kept for the shared interface
var is_sub := false

# state
var velocity := Vector3.ZERO
var angular := Vector3.ZERO           # world-space angular velocity (rad/s)
var forward := Vector3(0, 0, 1)
var right := Vector3(1, 0, 0)
var up := Vector3(0, 1, 0)
var heading := 0.0
var pitch := 0.0                      # bow up positive (for the camera's sub protocol)
var depth := 0.0                      # surface height minus body origin (>0 = under)

# derived, for camera / audio / fx
var speed := 0.0
var speed_kmh := 0.0
var submersion := 0.0                 # 0 = airborne, 1 = fully settled
var airborne := false
var slap_impulse := 0.0               # set on hard landings, decays; audio/spray listen to it
var wake_strength := 0.0
var sail_efficiency := 1.0
var beached_time := 0.0
var contacts: Array[float] = []

var inertia := Vector3.ONE
var point_count := 0
var spring_k := 0.0
var damping := 0.0
var _local_points: Array[Vector3] = []
var _prev_wet := 0
var _pos := Vector3.ZERO
var _quat := Quaternion.IDENTITY
var _visual: Node3D = null
var _hull_explicit := false


func _init() -> void:
	set_hull(Hulls.HULLS.speedboat)
	_hull_explicit = false


func _ready() -> void:
	# A hull set from code (configure/set_hull) wins over the exported boat_id.
	var cat: Dictionary = Boats.CATALOG.get(boat_id, {})
	if not _hull_explicit and not cat.is_empty():
		set_hull(Hulls.HULLS[cat.hull])
	if ocean == null:
		var oceans := get_tree().get_nodes_in_group("ocean")
		if not oceans.is_empty():
			ocean = oceans[0]
	_visual = get_node_or_null("Visual") as Node3D
	if _visual == null and auto_visual:
		_visual = Boats.build_visual(boat_id, color_index)
		_visual.name = "Visual"
		add_child(_visual)
	_write_transform()


func set_hull(h: Dictionary) -> void:
	hull = h
	_hull_explicit = true
	var m: float = hull.mass
	var L: float = hull.length
	var W: float = hull.width
	var H := maxf(0.6, W * 0.5)
	# Box inertia, then a small boost so the hull does not spin like a top.
	inertia = Vector3(
		m * (W * W + H * H) / 12.0 * 1.4,
		m * (L * L + W * W) / 12.0 * 1.6,
		m * (L * L + H * H) / 12.0 * 1.4)
	_local_points.clear()
	for p in hull.buoyancy_points:
		_local_points.append(Vector3(p[0], p[1], p[2]))
	point_count = _local_points.size()
	# Stiff and well damped: the hull should track the surface closely rather
	# than sink into a rising wave and pop out of a falling one.
	spring_k = (m * G) / (hull.draft * point_count) * Hulls.SPRING_FACTOR
	damping = 2.0 * sqrt(spring_k * m / point_count) * 0.7


## Configure everything in one call (Main.gd / tests).
func configure(id: String, color: int, ocean_node: Node, ground: Callable = Callable()) -> void:
	boat_id = id
	color_index = color
	var cat: Dictionary = Boats.CATALOG.get(id, {})
	set_hull(Hulls.HULLS[cat.hull] if not cat.is_empty() else Hulls.HULLS.speedboat)
	ocean = ocean_node
	ground_fn = ground


# ------------------------------------------------------------------ sea helpers
func sea_sample(x: float, z: float) -> Vector3:
	return ocean.sample(x, z) if ocean != null else Vector3.ZERO


func sea_height(x: float, z: float) -> float:
	return ocean.height_at(x, z) if ocean != null else 0.0


func sea_dhdt(x: float, z: float) -> float:
	return clampf(ocean.surface_velocity_y(x, z), -12.0, 12.0) if ocean != null else 0.0


func sea_hs() -> float:
	return ocean.significant_wave_height if ocean != null and "significant_wave_height" in ocean else 0.0


func ground_at(x: float, z: float) -> float:
	return ground_fn.call(x, z) if ground_fn.is_valid() else -1e9


# ------------------------------------------------------------------- pose API
func set_pose(x: float, y: float, z: float, heading_rad: float) -> void:
	_pos = Vector3(x, y, z)
	_quat = Quaternion(Vector3.UP, heading_rad)
	velocity = Vector3.ZERO
	angular = Vector3.ZERO
	heading = heading_rad
	_sync_axes()
	_write_transform()


## Put the boat back upright at its current spot (kids' panic button).
func reset() -> void:
	var h := sea_height(_pos.x, _pos.z)
	set_pose(_pos.x, h + 0.2, _pos.z, heading)


## Find open water near the boat and put it back there, facing away from land.
func rescue() -> void:
	if not ground_fn.is_valid():
		reset()
		return
	var x0 := _pos.x
	var z0 := _pos.z
	var best_x := 0.0
	var best_z := 0.0
	var best_a := 0.0
	var found := false
	var r := 6.0
	while r <= 120.0 and not found:
		var a := 0.0
		while a < TAU:
			var x := x0 + cos(a) * r
			var z := z0 + sin(a) * r
			if ground_at(x, z) < -3.5 and ground_at(x + 4, z) < -3 and ground_at(x - 4, z) < -3 and ground_at(x, z + 4) < -3 and ground_at(x, z - 4) < -3:
				best_x = x
				best_z = z
				best_a = a
				found = true
				break
			a += PI / 12.0
		r += 6.0
	if not found:
		reset()
		return
	var h := sea_height(best_x, best_z)
	set_pose(best_x, h + 0.2, best_z, atan2(cos(best_a), sin(best_a)))


## Snapshot for the CLI harness (group "harness_state").
func get_harness_state() -> Dictionary:
	return {
		"boat": boat_id,
		"pos": [snappedf(_pos.x, 0.01), snappedf(_pos.y, 0.01), snappedf(_pos.z, 0.01)],
		"speed_kmh": snappedf(speed_kmh, 0.1),
		"heading": snappedf(heading, 0.001),
		"submersion": snappedf(submersion, 0.01),
		"bank_deg": snappedf(rad_to_deg(asin(clampf(right.y, -1, 1))), 0.1),
		"throttle": snappedf(throttle, 0.01), "steer": snappedf(steer, 0.01),
	}


# --------------------------------------------------------------------- update
func _physics_process(dt: float) -> void:
	if simulate:
		advance(dt)


func _process(dt: float) -> void:
	if _visual != null and _visual.has_method("update"):
		_visual.update(dt, self)


## Advance with fixed 1/120 s substeps and write the pose to the node transform.
func advance(dt: float) -> void:
	var steps := maxi(1, ceili(dt / SUBSTEP - 1e-6))
	var h := dt / steps
	for i in steps:
		_step(h)
	speed = velocity.length()
	speed_kmh = speed * 3.6
	slap_impulse *= exp(-dt * 4.0)
	_write_transform()


func _sync_axes() -> void:
	forward = _quat * Vector3(0, 0, 1)
	right = _quat * Vector3(1, 0, 0)
	up = _quat * Vector3(0, 1, 0)
	heading = atan2(forward.x, forward.z)
	pitch = asin(clampf(forward.y, -1.0, 1.0))


func _write_transform() -> void:
	transform = Transform3D(Basis(_quat), _pos)


func _step(dt: float) -> void:
	var m: float = hull.mass
	var force := Vector3(0, -m * G, 0)
	var torque := Vector3.ZERO
	_sync_axes()

	# ------------------------------------------------------------ buoyancy
	var wet := 0
	var sum_depth := 0.0
	var fwd_speed := velocity.dot(forward)
	var planing: float = hull.planing * smoothstep(4.0, hull.max_speed * 0.7, absf(fwd_speed))
	for i in point_count:
		var lp := _local_points[i]
		var p := _quat * lp + _pos
		var s := sea_sample(p.x, p.z)
		var water_vy := sea_dhdt(p.x, p.z)   # surface vertical velocity here
		var d := s.x - p.y
		if d <= 0.0:
			continue
		wet += 1
		sum_depth += d
		# velocity of this point (v + ω × r)
		var r := p - _pos
		var pv := angular.cross(r) + velocity
		# Planing lift: at speed the hull rides on the water rather than in it,
		# so the springs ease off and the boat lifts and levels out.
		var k := spring_k * (1.0 - planing * 0.45)
		# Damping on the velocity relative to the water, not the world.
		var fy := k * minf(d, hull.draft * 2.5) - damping * (pv.y - water_vy) * (1.0 + planing * 0.6)
		if fy < 0.0:
			fy *= 0.35   # water does not pull the hull down
		var lift := fy + m * G / point_count * planing * 0.5 * (1.25 if lp.z > 0.0 else 0.75)
		# Along the wave normal: a face slope shoves the hull sideways as well as up.
		var fv := Vector3(-s.y, 1.0, -s.z).normalized() * lift
		force += fv
		torque += r.cross(fv)
	submersion = float(wet) / point_count
	airborne = wet == 0

	# Hard landing: a lot of hull entering the water fast.
	if wet >= 2 and velocity.y < -2.2 and _prev_wet < 2:
		slap_impulse = minf(1.0, -velocity.y / 6.0) * hull.bounce
	_prev_wet = wet

	if wet > 0:
		# ------------------------------------------------------------ thrust
		var thr := clampf(throttle, -0.5, 1.0)
		var bst := 1.0 + boost * 0.35
		var thrust_n: float = hull.thrust * thr * bst
		if hull.get("sail", false) and not wind.is_empty():
			# Point of sail: fastest across the wind, nothing head-to-wind.
			var rel := cos(float(wind.angle) - heading)
			var eff := clampf(0.45 + 0.55 * sin(acos(clampf(rel, -1.0, 1.0))), 0.0, 1.0) * (0.7 + 0.3 * minf(1.0, float(wind.speed) / 12.0))
			thrust_n = hull.thrust * maxf(thr, 0.0) * eff * bst + hull.thrust * 0.25 * minf(0.0, thr)
			sail_efficiency = eff
		# Speed governor: full thrust until three quarters of top speed, then a taper to the cap.
		var speed_ratio: float = absf(fwd_speed) / (hull.max_speed * bst)
		thrust_n *= clampf((1.0 - speed_ratio) * 4.0, 0.0, 1.0)
		# Screen convention: the hull faces +Z, so its visual starboard side is -X.
		# Positive steer must swing the bow toward -X; flip the sign here once so
		# every consumer can keep "positive = right".
		var steer_in := -steer
		var steer_angle := steer_in * 0.55
		# Outboard: thrust vector rotates with the steering, applied at the stern.
		var tv := forward.rotated(up, -steer_angle)
		tv.y = 0.0
		tv = tv.normalized() * (thrust_n * submersion)
		force += tv
		var stern: Vector3 = forward * (-float(hull.length) * 0.45) + up * -0.25
		torque += stern.cross(tv) * hull.steer_torque

		# Rudder lift: a coasting boat still answers the helm, more so at speed.
		var rudder: float = steer_in * hull.rudder_lift * fwd_speed * absf(fwd_speed) * m * 0.02 * submersion
		torque.y += rudder

		# ------------------------------------------------------- hydrodynamics
		var v_long := velocity.dot(forward)
		var v_lat := velocity.dot(right)
		var area: float = hull.length * hull.width
		var f_long: float = -0.5 * WATER_RHO * hull.drag_long * area * 0.08 * v_long * absf(v_long) * submersion
		# Grip (linear) keeps the boat from sliding and acts at the centre of
		# mass; only the quadratic hull drag acts down at the keel, which is what
		# banks a planing hull into the turn.
		var f_grip := -m * 1.8 * v_lat * submersion
		var f_lat: float = -0.5 * WATER_RHO * hull.drag_lat * area * 0.08 * v_lat * absf(v_lat) * submersion
		force += forward * f_long
		force += right * f_grip
		var lat_v := right * f_lat
		force += lat_v
		var keel: Vector3 = up * (-float(hull.draft) * 1.0 * float(hull.roll))
		torque += keel.cross(lat_v)
		# Reverse gets a low ceiling.
		if v_long < -4.0:
			force += forward * (-(v_long + 4.0) * m * 2.0)

		# Angular damping in water (yaw a bit less so slides feel alive).
		var wx := angular.dot(right)
		var wy := angular.dot(up)
		var wz := angular.dot(forward)
		torque += right * (-wx * inertia.x * 4.5 * submersion)
		torque += up * (-wy * inertia.y * 2.2 * submersion)
		torque += forward * (-wz * inertia.z * 4.5 * submersion)

		# Upright spring: a strong metacentric restoring moment, stiffening hard
		# past a 20 degree bank so a turn reads as a lean, not a capsize.
		var tilt := up.cross(Vector3.UP)   # axis to rotate toward upright, |tilt| = sin(bank)
		var bank := asin(minf(1.0, tilt.length()))
		var stiff := 1.0 + 6.0 * smoothstep(0.3, 0.6, bank)
		torque += tilt * (m * G * hull.width * 0.9 * stiff)
	else:
		# In the air: light drag and a little damping so flips stay controlled.
		force += velocity * -0.8
		torque += angular * (-inertia.x * 0.6)

	# ------------------------------------------------------------- terrain
	if ground_fn.is_valid():
		force = _collide_ground(force)

	# ------------------------------------------------------------ integrate
	velocity += force * (dt / m)
	# torque → angular acceleration in the body frame (diagonal inertia)
	var tx := torque.dot(right) / inertia.x
	var ty := torque.dot(up) / inertia.y
	var tz := torque.dot(forward) / inertia.z
	angular += right * (tx * dt) + up * (ty * dt) + forward * (tz * dt)
	# Clamp spin so a wave cannot flip the boat into a barrel roll, and cap the
	# yaw rate per hull so a light jet ski turns tight but never spins like a top.
	var max_spin := 2.6
	if angular.length_squared() > max_spin * max_spin:
		angular = angular.normalized() * max_spin
	var wyaw := angular.dot(up)
	var max_yaw: float = hull.get("max_yaw", 1.2)
	if absf(wyaw) > max_yaw:
		angular += up * (signf(wyaw) * max_yaw - wyaw)

	_pos += velocity * dt
	var angle := angular.length() * dt
	if angle > 1e-7:
		_quat = (Quaternion(angular.normalized(), angle) * _quat).normalized()

	# Never let the hull settle far below the surface even in a freak wave.
	var surf := sea_height(_pos.x, _pos.z)
	if _pos.y < surf - hull.draft * 3.0:
		_pos.y = surf - hull.draft * 3.0
		if velocity.y < 0.0:
			velocity.y *= -0.2
	_sync_axes()
	depth = surf - _pos.y
	wake_strength = clampf(absf(fwd_speed) / hull.max_speed, 0.0, 1.0) * submersion

	# Beached: hull entirely out of the water with land under it. Count the
	# seconds so the game can rescue the boat back to open water.
	if ground_fn.is_valid() and airborne and ground_at(_pos.x, _pos.z) > surf - hull.draft:
		beached_time += dt
	else:
		beached_time = 0.0


func _collide_ground(force: Vector3) -> Vector3:
	# Sample bow, stern and both beams; push away from land and kill the
	# velocity into it. The terrain height under the hull is compared with
	# the keel, so a sloping beach slows you down before it stops you.
	contacts.clear()
	for i in point_count:
		var p := _quat * _local_points[i] + _pos
		var ground := ground_at(p.x, p.z)
		var keel: float = p.y - hull.draft
		var pen := ground - keel
		if pen <= 0.0:
			continue
		var e := 1.0
		var nx := ground_at(p.x - e, p.z) - ground_at(p.x + e, p.z)
		var nz := ground_at(p.x, p.z - e) - ground_at(p.x, p.z + e)
		# Treat land as a wall, not a ramp: keep the push mostly horizontal so a
		# boat at full throttle bumps and slides along the beach instead of
		# launching up it and beaching on the grass.
		var n := Vector3(nx, 0.0, nz)
		if n.length_squared() < 1e-6:
			n = Vector3(-forward.x, 0.0, -forward.z)
		n = n.normalized()
		var vn := velocity.dot(n)
		var scale := minf(pen, 1.5)
		force += n * (hull.mass * (G * 4.0 * scale + maxf(0.0, -vn) * 10.0))
		contacts.append(pen)
		# Scrape: strong friction on the horizontal velocity.
		force.x -= velocity.x * hull.mass * 3.0 * minf(1.0, scale)
		force.z -= velocity.z * hull.mass * 3.0 * minf(1.0, scale)
	return force
