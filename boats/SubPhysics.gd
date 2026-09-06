class_name SubPhysics
extends Node3D
## Submarine rigid body — port of SubPhysics in the web game's src/game/Submarine.js.
##
## Same frame as BoatPhysics: local +Z is forward, heading = atan2(forward.x, forward.z), and
## positive steer swings the bow toward -X, which is the visual right when following.
## The hull is neutrally buoyant when submerged; `dive` pumps ballast (net buoyancy +-30 %) and,
## once the boat has way on, pitches the nose up to +-20 deg with the stern planes so the thrust
## itself carries the sub up or down. At the surface the wetted fraction of the hull gives the
## buoyancy, so the hull top stops at the waterline and the sub bobs and drives like a slow boat.
## The seabed is a heightfield (`ground_fn`): contact probes are pushed out along the local terrain
## normal, scraped, and probed one step ahead along the velocity so a canyon wall at full speed is
## a bump, never a tunnel. Fixed 1/120 s substeps.
##
## The node's own transform is written once per update() (position + quaternion), so a visual
## child inherits the pose. `auto_update` runs update() from _physics_process; Main may switch it
## off and drive update(dt) itself (the web Game.update order).

const G := 9.81
const SUB_HULL := {
	"id": "sub", "label": "Submarine", "length": 6.0, "width": 2.2, "mass": 4000.0, "draft": 0.95,
	"radius": 0.95, "max_speed": 30.0 / 3.6, "surface_speed": 20.0 / 3.6, "thrust": 20000.0,
	"max_yaw": 0.75, "max_pitch": deg_to_rad(20.0), "planing": 0.0, "is_sub": true,
}
## Collision probes in hull space: [x, y, z, radius]. The keel of each probe is y - radius.
const PROBES: Array = [
	[0.0, 0.0, 0.0, 0.95], [0.0, 0.0, 2.5, 0.5], [0.0, 0.0, -2.5, 0.5],
	[0.85, 0.0, 0.3, 0.35], [-0.85, 0.0, 0.3, 0.35],
]

var hull: Dictionary = SUB_HULL
var is_sub := true
@export var auto_update := true

# input
var throttle := 0.0     ## -0.5 .. 1
var steer := 0.0        ## -1 .. 1, + = right
var dive := 0.0         ## -1 .. 1, + = up
var boost := 0.0        ## 0 .. 1

# state
var velocity := Vector3.ZERO
var angular := Vector3.ZERO     ## world-space angular velocity (rad/s)
var forward := Vector3(0, 0, 1)
var right := Vector3(1, 0, 0)
var up := Vector3(0, 1, 0)
var heading := 0.0
var pitch := 0.0        ## rad, + = nose up
var roll := 0.0         ## rad
var depth := 0.0        ## metres below the surface (>= 0)
var submersion := 0.0   ## 0 surfaced .. 1 hull fully under
var ballast := 1.0      ## -1 heavy .. 1 light (tanks blown = floats)
var speed := 0.0
var speed_kmh := 0.0
var surface_y := 0.0
var scrape := 0.0       ## 0..1 terrain contact strength this frame (audio / fx)
# BoatPhysics-compatible fields read by Game / Wake / Audio
var airborne := false
var slap_impulse := 0.0
var wake_strength := 0.0
var beached_time := 0.0
var contacts: Array[float] = []

## (x, z) -> seabed height. Invalid Callable = no terrain.
var ground_fn: Callable
## (x, z) -> sea surface height. Invalid Callable = flat sea at y = 0.
var ceiling_fn: Callable

var _pos := Vector3.ZERO
var _quat := Quaternion.IDENTITY
var _prev_surface := INF     # INF = "no previous sample"


func _physics_process(dt: float) -> void:
	if auto_update:
		update(dt)


func set_pose(x: float, y: float, z: float, heading_rad: float) -> void:
	_pos = Vector3(x, y, z)
	_quat = Quaternion(Vector3.UP, heading_rad)
	velocity = Vector3.ZERO
	angular = Vector3.ZERO
	_sync_axes()
	var s := _surface(x, z)
	surface_y = s
	depth = maxf(0.0, s - y)
	# Near the surface the tanks are blown (floats like a boat); at depth, neutral.
	ballast = 1.0 if depth < 2.5 else 0.0
	_prev_surface = INF
	_apply_transform()


## Upright at the current spot, clear of the seabed.
func reset() -> void:
	var y := _pos.y
	if ground_fn.is_valid():
		y = maxf(y, float(ground_fn.call(_pos.x, _pos.z)) + float(hull.radius) + 2.0)
	y = minf(y, _surface(_pos.x, _pos.z) - 0.5)
	set_pose(_pos.x, y, _pos.z, heading)


## Move back to the nearest open water (clear of terrain), keeping depth where possible.
func rescue() -> void:
	var x0 := _pos.x
	var z0 := _pos.z
	var s := _surface(x0, z0)
	if not ground_fn.is_valid():
		set_pose(x0, minf(_pos.y, s - 0.5), z0, heading)
		return
	var want_y := minf(_pos.y, s - 0.5)
	if _clear_at(x0, z0, want_y):
		set_pose(x0, want_y, z0, heading)
		return
	var r := 6.0
	while r <= 150.0:
		var a := 0.0
		while a < TAU:
			var x := x0 + cos(a) * r
			var z := z0 + sin(a) * r
			if _clear_at(x, z, want_y):
				set_pose(x, want_y, z, atan2(cos(a), sin(a)))
				return
			a += PI / 12.0
		r += 6.0
	# Nothing open at this depth: rise to the surface here.
	set_pose(x0, s - 0.5, z0, heading)


func _clear_at(x: float, z: float, y: float) -> bool:
	return float(ground_fn.call(x, z)) < y - 5.0 and float(ground_fn.call(x + 4.0, z)) < y - 4.0 \
		and float(ground_fn.call(x - 4.0, z)) < y - 4.0 and float(ground_fn.call(x, z + 4.0)) < y - 4.0 \
		and float(ground_fn.call(x, z - 4.0)) < y - 4.0


func _surface(x: float, z: float) -> float:
	return float(ceiling_fn.call(x, z)) if ceiling_fn.is_valid() else 0.0


func _ground(x: float, z: float) -> float:
	return float(ground_fn.call(x, z))


func _sync_axes() -> void:
	forward = _quat * Vector3(0, 0, 1)
	right = _quat * Vector3(1, 0, 0)
	up = _quat * Vector3(0, 1, 0)
	heading = atan2(forward.x, forward.z)
	pitch = asin(clampf(forward.y, -1.0, 1.0))
	roll = asin(clampf(right.y, -1.0, 1.0))


func _apply_transform() -> void:
	transform = Transform3D(Basis(_quat), _pos)


## Advance with fixed 1/120 s substeps.
func update(dt: float) -> void:
	if dt <= 0.0:
		return
	var steps := maxi(1, ceili(dt / (1.0 / 120.0)))
	var h := dt / steps
	scrape = 0.0
	for i in steps:
		_step(h)
	speed = velocity.length()
	speed_kmh = speed * 3.6
	slap_impulse *= exp(-dt * 4.0)
	_apply_transform()


func _step(dt: float) -> void:
	var m: float = hull.mass
	var R: float = hull.radius
	_sync_axes()

	# ------------------------------------------------------------- water
	var s := _surface(_pos.x, _pos.z)
	surface_y = s
	var water_vy := 0.0 if _prev_surface == INF else clampf((s - _prev_surface) / dt, -6.0, 6.0)
	_prev_surface = s
	# Submerged fraction of the hull, linear from the keel to the hull top.
	var wet := clampf((s - (_pos.y - R)) / (2.0 * R), 0.0, 1.0)
	depth = maxf(0.0, s - _pos.y)
	submersion = clampf(1.0 + (s - 0.6 - (_pos.y + R)) / 1.2, 0.0, 1.0)
	var sub := submersion

	# Ballast: follow the dive input; with the stick centred a surfaced sub stays light
	# (keeps floating) and a submerged one goes neutral.
	var dv := clampf(dive, -1.0, 1.0)
	var target := dv
	if absf(dv) < 0.05:
		target = 1.0 if (ballast > 0.2 and depth < 2.5) else 0.0
	ballast += (target - ballast) * (1.0 - exp(-dt * 2.0))

	var F := Vector3(0.0, -m * G, 0.0)
	# Buoyancy of the wetted hull; neutral at ballast 0 when fully under.
	F.y += wet * m * G * (1.0 + 0.3 * ballast)
	# Vertical damping against the water (follows the swell when surfaced).
	F.y -= (velocity.y - water_vy * (1.0 - sub)) * m * 0.9 * (0.4 + 0.6 * wet)

	# ------------------------------------------------------------ thrust
	var v_long := velocity.dot(forward)
	var v_lat := velocity.dot(right)
	var v_up := velocity.dot(up)
	var thr := clampf(throttle, -0.5, 1.0)
	var boost_k := 1.0 + 0.3 * clampf(boost, 0.0, 1.0)
	var max_v: float = lerpf(hull.surface_speed, hull.max_speed, sub) * boost_k
	var thrust_n: float = hull.thrust * thr * boost_k * (0.5 + 0.5 * wet)
	# Governor: full thrust to three quarters of top speed, then a taper to the cap.
	var ratio := v_long / max_v if thr >= 0.0 else -v_long / (max_v * 0.5)
	thrust_n *= clampf((1.0 - ratio) * 6.0, 0.0, 1.0)
	F += forward * thrust_n

	# -------------------------------------------------------------- drag
	var wet_k := 0.5 + 0.5 * wet
	F += forward * (-(55.0 * v_long * absf(v_long) + m * 0.05 * v_long) * wet_k)
	F += right * (-(4500.0 * v_lat * absf(v_lat) + m * 1.2 * v_lat) * wet_k)
	F += up * (-(4500.0 * v_up * absf(v_up) + m * 0.6 * v_up) * wet_k)

	# ------------------------------------------------------------ terrain
	contacts.clear()
	if ground_fn.is_valid():
		F = _collide_ground(F, dt)

	# -------------------------------------------------------- orientation
	# Attitude is driven by three damped trackers (planes, rudder + bow thruster, hydrostatic
	# roll righting) expressed as body-frame angular accelerations. Signs: +rotation about
	# `right` pitches the nose DOWN, +rotation about `up` yaws the bow toward +X (heading grows,
	# visual left), +rotation about `forward` lifts the +X side (roll grows).
	var speed_f := absf(v_long)
	var w_r := angular.dot(right)
	var w_u := angular.dot(up)
	var w_f := angular.dot(forward)
	# Planes: authority grows with way on; at the surface follow the swell slope instead.
	var plane_auth := smoothstep(0.3, 4.0, speed_f)
	var pitch_target: float = dv * hull.max_pitch * plane_auth
	if wet < 0.999:
		var s_bow := _surface(_pos.x + forward.x * 2.6, _pos.z + forward.z * 2.6)
		var s_stern := _surface(_pos.x - forward.x * 2.6, _pos.z - forward.z * 2.6)
		var slope := atan2(s_bow - s_stern, 5.2)
		pitch_target = lerpf(slope, pitch_target, clampf(sub * 2.0, 0.0, 1.0))
	var a_pitch_up := 5.0 * (pitch_target - pitch) + 4.5 * w_r   # + w_r: nose-down rate opposes nose-up error
	# Yaw: rudder authority with speed plus a low-speed thruster so it turns when stopped.
	var yaw_auth := 0.4 + 0.6 * smoothstep(0.0, 4.0, speed_f)
	var yaw_target: float = -clampf(steer, -1.0, 1.0) * hull.max_yaw * yaw_auth
	var a_yaw := (yaw_target - w_u) * 3.5
	# Roll: strong righting, a small bank into the turn (positive steer lifts the +X side).
	var roll_target := clampf(steer, -1.0, 1.0) * 0.14 * smoothstep(1.0, 5.0, speed_f)
	var a_roll := 10.0 * (roll_target - roll) - 6.5 * w_f

	# ---------------------------------------------------------- integrate
	velocity += F * (dt / m)
	angular += right * (-a_pitch_up * dt) + up * (a_yaw * dt) + forward * (a_roll * dt)
	if angular.length_squared() > 4.0:
		angular = angular.normalized() * 2.0
	_pos += velocity * dt
	var ang := angular.length() * dt
	if ang > 1e-7:
		var q := Quaternion(angular / (angular.length()), ang)
		_quat = (q * _quat).normalized()
	_sync_axes()
	wake_strength = clampf(absf(v_long) / float(hull.surface_speed), 0.0, 1.0) * (1.0 - sub)


func _collide_ground(F: Vector3, dt: float) -> Vector3:
	var m: float = hull.mass
	var e := 1.0
	var best_push := 0.0
	var push := Vector3.ZERO
	for pr in PROBES:
		var p: Vector3 = _quat * Vector3(pr[0], pr[1], pr[2]) + _pos
		var r: float = pr[3]
		var pen := _ground(p.x, p.z) - (p.y - r)
		if pen <= 0.0:
			# Look ahead along the velocity (two substeps plus the probe's own radius, since a
			# heightfield test only sees what is under the probe centre): kill the approach
			# speed before contact so a canyon wall is met at the hull's leading edge.
			var sp := velocity.length()
			if sp < 1e-3:
				continue
			p += velocity * (dt * 2.0 + r / sp)
			var pen_n := _ground(p.x, p.z) - (p.y - r)
			if pen_n <= 0.0:
				continue
			var n := Vector3(_ground(p.x - e, p.z) - _ground(p.x + e, p.z), 2.0 * e,
				_ground(p.x, p.z - e) - _ground(p.x, p.z + e)).normalized()
			var vn := velocity.dot(n)
			if vn < 0.0:
				velocity += n * (-vn)
			continue
		var n := Vector3(_ground(p.x - e, p.z) - _ground(p.x + e, p.z), 2.0 * e,
			_ground(p.x, p.z - e) - _ground(p.x, p.z + e)).normalized()
		# Hard stop: the perpendicular distance out of the surface is pen * n.y.
		var d := minf(pen * n.y, 0.6)
		if d > best_push:
			best_push = d
			push = n * d
		var vn := velocity.dot(n)
		if vn < 0.0:
			velocity += n * (-vn * 1.15)
		# Spring so a resting hull settles onto the bottom, and scrape friction.
		var scale := minf(pen, 1.5)
		F += n * (m * G * 2.0 * scale)
		F += velocity * (-m * 2.5 * minf(1.0, scale))
		contacts.append(pen)
		scrape = maxf(scrape, clampf(velocity.length() / 4.0, 0.0, 1.0))
	if best_push > 0.0:
		_pos += push
	return F


func get_harness_state() -> Dictionary:
	return {
		"depth": snappedf(depth, 0.01), "kmh": snappedf(speed_kmh, 0.1), "pitch_deg": snappedf(rad_to_deg(pitch), 0.1),
		"pos": [snappedf(_pos.x, 0.01), snappedf(_pos.y, 0.01), snappedf(_pos.z, 0.01)],
	}
