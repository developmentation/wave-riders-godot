class_name StubFollowCamera
extends Camera3D
## Minimal chase camera with the FollowCamera.js surface Main.gd uses: follow(body), next_view(),
## impulse(x), orbit (Dictionary: angle, dist, height, speed, fov; empty = chase), mode ("boat"/"sub"),
## update(dt). Replaced by scripts/FollowCamera.gd when it lands (Main prefers the real one).

const VIEWS := [
	{"back": 13.0, "up": 4.5, "ahead": 6.0, "fov": 60.0},
	{"back": 22.0, "up": 8.0, "ahead": 4.0, "fov": 55.0},
	{"back": -2.0, "up": 1.6, "ahead": 30.0, "fov": 70.0},
]

var body: Node3D
var orbit: Dictionary = {}
var mode := "boat"
var ocean: Node
var view := 0
var _shake := 0.0
var _pos := Vector3(0, 6, -14)
var _look := Vector3.ZERO
var _orbit_t := 0.0
var _snap := true


func follow(b: Node3D) -> void:
	body = b
	_snap = true


func next_view() -> void:
	view = (view + 1) % VIEWS.size()


func impulse(x: float) -> void:
	_shake = minf(1.5, _shake + x)


func _body_forward() -> Vector3:
	if body == null:
		return Vector3(0, 0, 1)
	if "heading" in body:
		var h: float = body.heading
		return Vector3(sin(h), 0, cos(h))
	return body.global_basis.z


func update(dt: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	var p := body.global_position
	var target: Vector3
	var look: Vector3
	if not orbit.is_empty():
		_orbit_t += dt * float(orbit.get("speed", 0.2))
		var a := float(orbit.get("angle", 0.6)) + _orbit_t
		var l := 6.0
		if "hull" in body:
			l = float(body.hull.get("length", 6.0))
		var dist := l * 2.2 * float(orbit.get("dist", 1.6))
		target = p + Vector3(sin(a) * dist, l * 0.6 * float(orbit.get("height", 0.5)) + 1.5, cos(a) * dist)
		look = p + Vector3(0, 0.6, 0)
		fov = float(orbit.get("fov", 45.0))
	else:
		var v: Dictionary = VIEWS[view]
		var f := _body_forward()
		var scale := 1.0
		if "hull" in body:
			scale = clampf(float(body.hull.get("length", 6.0)) / 6.0, 0.7, 1.4)
		target = p - f * (float(v.back) * scale) + Vector3(0, float(v.up) * scale, 0)
		look = p + f * float(v.ahead) + Vector3(0, 1.0, 0)
		fov = float(v.fov)
		if mode == "sub":
			target += Vector3(0, 1.5, 0)
	if _snap:
		_pos = target
		_look = look
		_snap = false
	else:
		var k := 1.0 - exp(-dt * 5.0)
		_pos = _pos.lerp(target, k)
		_look = _look.lerp(look, 1.0 - exp(-dt * 8.0))
	var pos := _pos
	if mode != "sub" and ocean and ocean.has_method("height_at"):
		pos.y = maxf(pos.y, ocean.height_at(pos.x, pos.z) + 1.2)
	if _shake > 0.001:
		pos += Vector3(sin(_orbit_t * 40.0 + Time.get_ticks_msec() * 0.03), cos(Time.get_ticks_msec() * 0.041), 0) * _shake * 0.15
		_shake *= exp(-dt * 6.0)
	global_position = pos
	if (_look - pos).length_squared() > 1e-4:
		look_at(_look, Vector3.UP)
