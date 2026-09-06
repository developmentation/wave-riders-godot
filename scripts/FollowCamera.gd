class_name FollowCamera
extends Camera3D
## Chase camera — port of src/game/FollowCamera.js.
##
## Sits behind and above the boat, pulls back and widens as speed builds, looks
## a little ahead of the bow so turns read early, and never dips into a wave:
## the sampled sea surface under the lens sets a hard floor. Position is
## critically damped; orientation follows the boat's heading with a little lag
## so wave-slaps do not shake the view. `mode = "sub"` follows in 3D and stays
## under the surface while the sub is under; a non-empty `orbit` circles the
## boat for the title / garage.

const VIEWS := [
	{"name": "chase", "dist": 1.9, "height": 0.75, "look_ahead": 1.6, "look_up": 0.35, "fov": 52.0},
	{"name": "bow", "bow": true, "fov": 74.0},
	{"name": "close", "dist": 1.25, "height": 0.55, "look_ahead": 2.0, "look_up": 0.2, "fov": 60.0},
	{"name": "high", "dist": 2.8, "height": 1.7, "look_ahead": 1.2, "look_up": 0.0, "fov": 46.0},
]

## BoatPhysics (or SubPhysics) to follow.
var boat: Node = null
## Ocean for the surface floor (falls back to boat.ocean, then flat water).
var ocean: Node = null
var view_index := 0
var enabled := true
## "boat" | "sub"
var mode := "boat"
## {angle, dist, height, speed?, fov?} in multiples of hull length; empty = off.
var orbit: Dictionary = {}
var shake := 0.0

## Step itself from _process. Calling update(dt) from a game loop (Main.gd, after the
## boats have moved) turns this off so the camera is not stepped twice a frame.
var auto_update := true

var pos := Vector3.ZERO
var look := Vector3(0, 0, 1)
var heading_smooth := 0.0
var fov_s := 52.0
var _first := true


func follow(b: Node) -> void:
	boat = b
	_first = true


func next_view() -> void:
	view_index = (view_index + 1) % VIEWS.size()


func view_name() -> String:
	return VIEWS[view_index].name


func impulse(a: float) -> void:
	shake = minf(1.5, shake + a)


func _ocean() -> Node:
	if ocean != null:
		return ocean
	if boat != null and "ocean" in boat:
		return boat.ocean
	return null


func _sea_height(x: float, z: float) -> float:
	var o := _ocean()
	return float(o.height_at(x, z)) if o != null else 0.0


func _hs() -> float:
	var o := _ocean()
	return float(o.significant_wave_height) if o != null and "significant_wave_height" in o else 0.0


func _process(dt: float) -> void:
	if auto_update:
		_update(dt)


## Explicit step (web order: boats, collisions, race, then camera).
func update(dt: float) -> void:
	auto_update = false
	_update(dt)


func _update(dt: float) -> void:
	if boat == null or not enabled:
		return
	var b := boat
	var L := float(b.hull.length) if "hull" in b else 6.0
	var bp: Vector3 = b.position

	if not orbit.is_empty():
		var o := orbit
		o.angle = float(o.get("angle", 0.0)) + dt * float(o.get("speed", 0.25))
		var target := Vector3(sin(o.angle) * L * float(o.dist), L * float(o.height), cos(o.angle) * L * float(o.dist)) + bp
		var floor_y := _sea_height(target.x, target.z) + 1.0
		if target.y < floor_y:
			target.y = floor_y
		pos = pos.lerp(target, 1.0 if _first else 1.0 - exp(-dt * 3.0))
		var lk := bp + Vector3(0, L * 0.12, 0)
		look = look.lerp(lk, 1.0 if _first else 1.0 - exp(-dt * 4.0))
		_apply(dt, float(o.get("fov", 40.0)))
		return

	if mode == "sub":
		_update_sub(dt)
		return

	var view: Dictionary = VIEWS[view_index]
	if view.get("bow", false):
		_update_bow(dt, view)
		return
	# Heading lags the hull so wave yaw does not whip the camera.
	var dh := float(b.heading) - heading_smooth
	dh = atan2(sin(dh), cos(dh))
	heading_smooth += dh * (1.0 if _first else 1.0 - exp(-dt * 3.5))
	var speed_k := clampf(float(b.speed) / float(b.hull.max_speed), 0.0, 1.2)
	# A little extra reach in big seas, capped: standing far back and high flattens the
	# waves, and the sea-surface floor below keeps the lens out of the crests anyway.
	var hs := minf(_hs(), 2.0)
	var dist := L * float(view.dist) * (1.0 + speed_k * 0.35) + hs * 0.9
	var height := L * float(view.height) * (1.0 + speed_k * 0.15) + 0.6 + hs * 0.75

	var fx := sin(heading_smooth)
	var fz := cos(heading_smooth)
	var target := Vector3(bp.x - fx * dist, bp.y + height, bp.z - fz * dist)
	# Keep the lens clear of the sea whatever the swell is doing.
	var surf := _sea_height(target.x, target.z)
	var min_y := surf + 1.4 + hs * 0.45
	if target.y < min_y:
		target.y = min_y
	var k := 1.0 if _first else 1.0 - exp(-dt * 6.0)
	pos = pos.lerp(target, k)
	# Vertical follows a bit slower so the boat bobs in frame rather than the frame bobbing.
	var lk := Vector3(bp.x + fx * L * float(view.look_ahead), bp.y + L * float(view.look_up) + 0.3, bp.z + fz * L * float(view.look_ahead))
	look = look.lerp(lk, 1.0 if _first else 1.0 - exp(-dt * 8.0))
	_apply(dt, float(view.fov) + speed_k * 8.0)


## Bow camera: the lens rides on the foredeck at water level, looking down the boat's
## own heading, so every wave comes straight at the screen.
func _update_bow(dt: float, view: Dictionary) -> void:
	var b := boat
	var L := float(b.hull.length) if "hull" in b else 6.0
	var bp: Vector3 = b.position
	var fwd: Vector3 = b.forward if "forward" in b else Vector3(sin(float(b.heading)), 0.0, cos(float(b.heading)))
	var upv: Vector3 = b.up if "up" in b else Vector3.UP
	var speed_k := clampf(float(b.speed) / float(b.hull.max_speed), 0.0, 1.2)
	var target := bp + fwd * (L * 0.52) + upv * (L * 0.14 + 0.7)
	# Never let a crest cross the lens: the surface is sampled where the lens is and a
	# little ahead of it (the wave face the bow is about to climb).
	var surf := maxf(_sea_height(target.x, target.z), _sea_height(target.x + fwd.x * 3.0, target.z + fwd.z * 3.0))
	if target.y < surf + 0.9:
		target.y = surf + 0.9
	# Tracks the hull almost rigidly; the look point is damped so wave slaps nod rather than jolt.
	pos = pos.lerp(target, 1.0 if _first else 1.0 - exp(-dt * 30.0))
	var lk := target + fwd * (L * 3.0) - Vector3(0.0, L * 0.10, 0.0)
	look = look.lerp(lk, 1.0 if _first else 1.0 - exp(-dt * 10.0))
	heading_smooth = float(b.heading)
	_apply(dt, float(view.fov) + speed_k * 6.0)


## Submarine: follow in 3D, stay under the surface while the sub is under.
func _update_sub(dt: float) -> void:
	var b := boat
	var L := float(b.hull.length) if "hull" in b else 6.0
	var bp: Vector3 = b.position
	var dh := float(b.heading) - heading_smooth
	dh = atan2(sin(dh), cos(dh))
	heading_smooth += dh * (1.0 if _first else 1.0 - exp(-dt * 3.0))
	var pitch := clampf(float(b.pitch) if "pitch" in b else 0.0, -0.6, 0.6) * 0.5
	var fx := sin(heading_smooth)
	var fz := cos(heading_smooth)
	var dist := L * 2.2
	var height := L * 0.7
	var target := Vector3(bp.x - fx * dist, bp.y + height - sin(pitch) * dist * 0.5, bp.z - fz * dist)
	var surf := _sea_height(target.x, target.z)
	var depth := float(b.depth) if "depth" in b else (surf - bp.y)
	if depth > 2.5:
		# Under water: keep the lens at least 2 m below the surface so the frame never straddles it.
		if target.y > surf - 2.0:
			target.y = surf - 2.0
		var floor_y := -1e9
		if "ground_fn" in b and b.ground_fn.is_valid():
			floor_y = float(b.ground_fn.call(target.x, target.z)) + 2.5
		if target.y < floor_y:
			target.y = floor_y
	elif target.y < surf + 1.6:
		target.y = surf + 1.6
	pos = pos.lerp(target, 1.0 if _first else 1.0 - exp(-dt * 5.0))
	var lk := Vector3(bp.x + fx * L * 1.2, bp.y + sin(pitch) * L * 1.2, bp.z + fz * L * 1.2)
	look = look.lerp(lk, 1.0 if _first else 1.0 - exp(-dt * 7.0))
	_apply(dt, 58.0)


func _apply(dt: float, fov_target: float) -> void:
	fov_s += (fov_target - fov_s) * (1.0 if _first else 1.0 - exp(-dt * 3.0))
	var p := pos
	# Landing shake
	if shake > 0.001:
		var t := float(Time.get_ticks_msec())
		p.x += sin(t * 0.031) * shake * 0.12
		p.y += sin(t * 0.047) * shake * 0.10
		shake *= exp(-dt * 5.0)
	var fwd := look - p
	if fwd.length_squared() > 1e-8 and absf(fwd.normalized().dot(Vector3.UP)) < 0.999:
		look_at_from_position(p, look, Vector3.UP)
	else:
		position = p
	fov = fov_s
	_first = false
