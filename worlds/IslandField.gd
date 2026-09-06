class_name IslandField
extends RefCounted
## Seeded heightfield island: port of src/game/Islands.js (islandProfile + createIslandField).
##
## The analytic profile is a cone / plateau / crescent silhouette, its coastline warped by
## low-frequency value noise, fbm bumps on the land, a sand terrace at the waterline and a
## sandy shelf that drops to DEEP a few radii out. The field is sampled once into a grid;
## the mesh is built from that grid and `sample()` interpolates the same grid across the
## same triangle split, so the hull collides with exactly the surface the player sees.
##
## The integer hashes replicate the web's Math.imul / >>> arithmetic bit for bit, so every
## island (and every palm) lands exactly where it does in the web game and the gate layouts
## validated there stay valid here.

const DEEP := -50.0            # metres; far-field sea floor
const CULL_DEPTH := -3.0       # triangles wholly below this are not drawn
const MAX_TRIS := 8000         # per terrain mesh
const MAX_PALMS := 40
const SHORE_WALL := 8.0

var def: Dictionary
var shape := "cone"
var is_arc := false
var cx := 0.0
var cz := 0.0
var bound_r := 0.0
var aspect := 1.0
# square parametrisation
var _half := 0.0
var _size := 0.0
var _x0 := 0.0
var _z0 := 0.0
# arc parametrisation
var _arc_r := 0.0
var _arc_thick := 0.0
var _arc_a0 := 0.0
var _arc_a1 := 0.0
var _u0 := 0.0
var _du := 1.0
var _v_half := 0.0
var _mid := 0.0
# sampled grid
var nu := 0
var nv := 0
var grid := PackedFloat32Array()
var tris := 0
var triangles := 0          # terrain triangles actually emitted (set by the builder)
var detail_triangles := 0


# ------------------------------------------------------------------ noise
static func imul(a: int, b: int) -> int:
	var r := (a * b) & 0xFFFFFFFF
	return r - 0x100000000 if r >= 0x80000000 else r


static func i32(a: int) -> int:
	a &= 0xFFFFFFFF
	return a - 0x100000000 if a >= 0x80000000 else a


static func ushr(a: int, n: int) -> int:
	return (a & 0xFFFFFFFF) >> n


static func hash2(ix: int, iz: int, seed: int) -> float:
	var h := i32(imul(ix, 374761393) + imul(iz, 668265263) + imul(seed, 1442695041))
	h = imul(h ^ ushr(h, 13), 1274126177)
	h ^= ushr(h, 16)
	return float(h & 0xFFFFFFFF) / 4294967296.0


## Value noise in [-1, 1] with a quintic fade.
static func vnoise(x: float, z: float, seed: int) -> float:
	var fxf := floorf(x)
	var fzf := floorf(z)
	var ix := int(fxf)
	var iz := int(fzf)
	var fx := x - fxf
	var fz := z - fzf
	fx = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
	fz = fz * fz * fz * (fz * (fz * 6.0 - 15.0) + 10.0)
	var a := hash2(ix, iz, seed)
	var b := hash2(ix + 1, iz, seed)
	var c := hash2(ix, iz + 1, seed)
	var d := hash2(ix + 1, iz + 1, seed)
	return (a + (b - a) * fx + (c - a) * fz + (a - b - c + d) * fx * fz) * 2.0 - 1.0


## Rotated fbm in roughly [-1, 1].
static func fbm(x: float, z: float, seed: int, octaves := 4) -> float:
	var sum := 0.0
	var amp := 0.5
	var norm := 0.0
	for i in octaves:
		sum += vnoise(x, z, seed + i * 131) * amp
		norm += amp
		var nx := x * 1.92 + z * 0.62 + 13.7
		var nz := -x * 0.62 + z * 1.92 + 7.1
		x = nx
		z = nz
		amp *= 0.5
	return sum / norm


## mulberry32: the web's seeded RNG (palm scatter, hut / lighthouse placement).
class Rng:
	var a: int
	func _init(seed: int) -> void:
		a = seed & 0xFFFFFFFF
	func next() -> float:
		a = IslandField.i32(a + 0x6D2B79F5)
		var t := IslandField.imul(a ^ IslandField.ushr(a, 15), 1 | a)
		t = IslandField.i32((t + IslandField.imul(t ^ IslandField.ushr(t, 7), 61 | t)) ^ t)
		return float((t ^ IslandField.ushr(t, 14)) & 0xFFFFFFFF) / 4294967296.0


static func wrap_pi(a: float) -> float:
	return atan2(sin(a), cos(a))


static func tanh_(x: float) -> float:
	if x > 20.0:
		return 1.0
	if x < -20.0:
		return -1.0
	var e := exp(2.0 * x)
	return (e - 1.0) / (e + 1.0)


# ------------------------------------------------------------- the field
## Analytic island profile in metres above mean sea level. `noise = false` skips the coastline
## warp and the fbm detail: a cheap stand-in for the seabed outside the sampled grid (all below
## the -3 m cull depth, so nothing visible depends on it).
static func island_profile(d: Dictionary, x: float, z: float, noise := true) -> float:
	var px: float = x - d.x
	var pz: float = z - d.z
	var dist_n: float
	var hmul := 1.0
	var scale: float = d.radius
	var shp: String = d.get("shape", "cone")
	if shp == "crescent":
		var arc: Dictionary = d.arc
		var a0: float = arc.a0
		var a1: float = arc.a1
		var ar: float = arc.r
		var thick: float = arc.thick
		var mid := (a0 + a1) * 0.5
		var ang := mid + wrap_pi(atan2(pz, px) - mid)
		var rad := sqrt(px * px + pz * pz)
		var ta := (ang - a0) / (a1 - a0)
		var dist: float
		if ta >= 0.0 and ta <= 1.0:
			dist = absf(rad - ar)
		else:
			var ae := a0 if ta < 0.0 else a1
			var ex := px - ar * cos(ae)
			var ez := pz - ar * sin(ae)
			dist = sqrt(ex * ex + ez * ez)
		dist_n = dist / thick
		scale = thick
		# the ridge tapers toward both horns
		hmul = 0.35 + 0.65 * sqrt(sin(PI * clampf(ta, 0.0, 1.0)))
	else:
		dist_n = sqrt(px * px + pz * pz) / float(d.radius)
	# coastline warp: a few noise cells across the island
	var seed: int = d.seed
	var wf := 1.6 / scale
	var warp: float = d.get("warp", 0.26)
	if noise:
		dist_n *= 1.0 + warp * fbm(px * wf + seed * 0.37, pz * wf, seed, 3)
	var core := 1.0 - dist_n
	var h: float
	var height: float = d.height
	if core > 0.0:
		var s: float
		if shp == "plateau":
			s = smoothstep(0.0, 0.72, core) * (0.85 + 0.15 * core)
		else:
			s = pow(core, 1.35) * 0.78 + 0.22 * smoothstep(0.45, 0.95, core)
		h = height * s * hmul
		if noise:
			var df := 4.5 / scale
			var detail: float = d.get("detail", 0.16)
			h += height * detail * fbm(px * df, pz * df, seed + 7, 4) * minf(1.0, core * 3.0) * hmul
	else:
		# sandy shelf: 16% grade to -6 m, then the drop-off (both scaled by def.shelf)
		var shelf: float = d.get("shelf", 1.0)
		h = maxf(core * scale * 0.16 / shelf, -6.0)
		var t := smoothstep(1.0 + 0.7 * shelf, 1.0 + 1.6 * shelf, dist_n)
		h = h * (1.0 - t) + DEEP * t
	# beach terrace: flatten the slope through the waterline
	var bw := 1.5
	h -= 0.7 * bw * tanh_(h / bw)
	return h


## Collision shaping for BoatPhysics.ground_fn: raise everything above the waterline by a
## few metres over the last quarter metre of shallows so the shoreline is a soft wall.
static func collision_height(h: float) -> float:
	return h + SHORE_WALL * smoothstep(-0.25, 0.0, h)


func _init(def_in: Dictionary) -> void:
	def = {"shape": "cone", "warp": 0.26, "detail": 0.16, "palms": 0}
	def.merge(def_in, true)
	shape = def.shape
	cx = def.x
	cz = def.z
	is_arc = shape == "crescent"
	if is_arc:
		var arc: Dictionary = def.arc
		_arc_r = arc.r
		_arc_thick = arc.thick
		_arc_a0 = arc.a0
		_arc_a1 = arc.a1
		var cap := 1.6 * _arc_thick / _arc_r
		_u0 = _arc_a0 - cap
		var u1: float = _arc_a1 + cap
		_du = u1 - _u0
		_v_half = 1.5 * _arc_thick
		_mid = (_u0 + u1) * 0.5
		bound_r = _arc_r + _v_half
		aspect = (_arc_r * _du) / (2.0 * _v_half)
	else:
		_half = def.radius * 1.4
		_x0 = cx - _half
		_z0 = cz - _half
		_size = _half * 2.0
		bound_r = _half * sqrt(2.0)
		aspect = 1.0
	_sample_grid()


func to_world(u: float, v: float) -> Vector2:
	if is_arc:
		var a := _u0 + u * _du
		var rad := _arc_r + (v - 0.5) * 2.0 * _v_half
		return Vector2(cx + rad * cos(a), cz + rad * sin(a))
	return Vector2(_x0 + u * _size, _z0 + v * _size)


func to_param(x: float, z: float) -> Vector2:
	if is_arc:
		var px := x - cx
		var pz := z - cz
		var a := _mid + wrap_pi(atan2(pz, px) - _mid)
		return Vector2((a - _u0) / _du, (sqrt(px * px + pz * pz) - _arc_r) / (2.0 * _v_half) + 0.5)
	return Vector2((x - _x0) / _size, (z - _z0) / _size)


func analytic(x: float, z: float) -> float:
	return island_profile(def, x, z)


## Sample the island into a grid whose visible triangle count fits the budget.
func _sample_grid() -> void:
	var target := sqrt(MAX_TRIS / 2.0 * 1.35)
	for iter in 4:
		nu = maxi(12, int(round(target * sqrt(aspect)))) + 1
		nv = maxi(12, int(round(target / sqrt(aspect)))) + 1
		grid.resize(nu * nv)
		for j in nv:
			var v := float(j) / float(nv - 1)
			for i in nu:
				var p := to_world(float(i) / float(nu - 1), v)
				grid[j * nu + i] = analytic(p.x, p.y)
		tris = 0
		for j in nv - 1:
			for i in nu - 1:
				var a := grid[j * nu + i]
				var b := grid[j * nu + i + 1]
				var c := grid[(j + 1) * nu + i]
				var d := grid[(j + 1) * nu + i + 1]
				if not (a < CULL_DEPTH and c < CULL_DEPTH and d < CULL_DEPTH):
					tris += 1
				if not (a < CULL_DEPTH and d < CULL_DEPTH and b < CULL_DEPTH):
					tris += 1
		if tris <= MAX_TRIS:
			break
		target *= sqrt(float(MAX_TRIS) / float(tris)) * 0.985


func in_bounds(x: float, z: float) -> bool:
	var p := to_param(x, z)
	return p.x >= 0.0 and p.x <= 1.0 and p.y >= 0.0 and p.y <= 1.0


## Height at (x, z): grid interpolation across the mesh's own triangles. O(1). Outside the grid
## (seabed below the cull depth) the analytic profile is used; `exact = false` drops its noise
## terms there, which is ~20x cheaper and what the runtime collision field uses.
func sample(x: float, z: float, exact := true) -> float:
	var dx := x - cx
	var dz := z - cz
	var br := bound_r + 60.0
	if dx * dx + dz * dz > br * br:
		return DEEP
	var p := to_param(x, z)
	var u := p.x
	var v := p.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return island_profile(def, x, z, exact)
	var fu0 := u * float(nu - 1)
	var fv0 := v * float(nv - 1)
	var i := mini(nu - 2, int(fu0))
	var j := mini(nv - 2, int(fv0))
	var fu := fu0 - i
	var fv := fv0 - j
	var a := grid[j * nu + i]
	var b := grid[j * nu + i + 1]
	var c := grid[(j + 1) * nu + i]
	var d := grid[(j + 1) * nu + i + 1]
	# split along the a-d diagonal, same as the mesh
	if fv > fu:
		return a + (c - a) * fv + (d - c) * fu
	return a + (b - a) * fu + (d - b) * fv


func slope(x: float, z: float, e := 1.5) -> float:
	var hx := sample(x + e, z) - sample(x - e, z)
	var hz := sample(x, z + e) - sample(x, z - e)
	return sqrt(hx * hx + hz * hz) / (2.0 * e)


## Max over a list of fields; DEEP far from everything.
static func fields_height(fields: Array, x: float, z: float) -> float:
	var h := DEEP
	for f in fields:
		var v: float = f.sample(x, z)
		if v > h:
			h = v
	return h


## Terrain height contribution of a pier so hulls bump into it instead of passing through.
static func pier_height(p: Dictionary, x: float, z: float) -> float:
	var fx := sin(p.heading)
	var fz := cos(p.heading)
	var dx: float = x - p.x
	var dz: float = z - p.z
	var along := dx * fx + dz * fz
	var across := -dx * fz + dz * fx
	var hw: float = p.get("width", 4.0) / 2.0 + 0.4
	var edge: float = minf(minf(along, p.length - along), hw - absf(across))
	if edge < -3.0:
		return DEEP
	return lerpf(-3.0, 1.0, clampf((edge + 3.0) / 3.5, 0.0, 1.0))
