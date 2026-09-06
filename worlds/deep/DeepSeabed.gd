class_name DeepSeabed
extends RefCounted
## The Deep Run's analytic seabed and course — port of the top half of the web game's
## src/game/SubmarineWorld.js. One instance is shared by the mesh builder (which samples it) and
## every submarine's `ground_fn` (which evaluates it per probe per substep), so `height_at` is
## exact for the mesh and allocation-free.
##
## Coordinates: metres, +Z is heading 0, +X is heading +PI/2 (heading = atan2(dx, dz), matching
## the boats). y negative = depth.

## The hoop path as a closed Catmull-Rom loop through these points. The canyon is carved along
## points 2..7; the basin holds 8..11; 12..16 is the shallow return over the plain, rising back to
## the surface start.
const PATH: Array = [
	[0.0, 0.0, 0.0],        # 0  start: surface, heading +z
	[6.0, -14.0, 90.0],     # 1  diving
	[22.0, -26.0, 170.0],   # 2  canyon mouth
	[58.0, -33.0, 250.0],   # 3  canyon
	[62.0, -41.0, 330.0],   # 4  canyon, tightest
	[22.0, -47.0, 400.0],   # 5  canyon
	[-26.0, -50.0, 470.0],  # 6  canyon, deepest
	[-8.0, -46.0, 540.0],   # 7  canyon exit
	[52.0, -42.0, 610.0],   # 8  into the basin
	[118.0, -40.0, 665.0],  # 9  basin
	[70.0, -38.0, 745.0],   # 10 basin, turning back
	[-55.0, -36.0, 735.0],  # 11 basin west
	[-160.0, -31.0, 655.0], # 12 return leg
	[-192.0, -26.0, 520.0], # 13
	[-172.0, -20.0, 380.0], # 14
	[-122.0, -14.0, 240.0], # 15
	[-58.0, -8.0, 110.0],   # 16 rising to the start
]
const N_PATH := 17
const GATE_IDX: Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16]
const CANYON_T0 := 1.6 / 17.0
const CANYON_T1 := 7.4 / 17.0
const CANYON_N := 28
const RIM_Y := -12.0          # rock table top
const FLOOR_MIN := -60.0
const TABLE_REACH := 150.0    # metres from the centreline the rock table fades out over
const NEAR_CELL := 10.0
const PLAIN_Y := -44.0
const BASIN := {"x": 50.0, "z": 690.0, "r": 140.0, "y": -54.0}
const WRECK := {"x": 40.0, "z": 690.0, "r": 22.0, "h": 9.0}
const PILLARS: Array = [
	{"x": -100.0, "z": 600.0, "r": 6.0, "h": 22.0}, {"x": 150.0, "z": 610.0, "r": 5.0, "h": 18.0},
	{"x": -20.0, "z": 790.0, "r": 7.0, "h": 26.0}, {"x": -240.0, "z": 450.0, "r": 6.0, "h": 20.0},
	{"x": 120.0, "z": 100.0, "r": 5.0, "h": 16.0}, {"x": -300.0, "z": 250.0, "r": 6.0, "h": 18.0},
]

# value-noise tables
var _perm := PackedInt32Array()
var _val := PackedFloat32Array()
# canyon centreline polyline: x, z, floor y, half-width per sample
var _cx := PackedFloat32Array()
var _cz := PackedFloat32Array()
var _cy := PackedFloat32Array()
var _cw := PackedFloat32Array()
var _box_x0 := INF
var _box_x1 := -INF
var _box_z0 := INF
var _box_z1 := -INF
var _near_nx := 0
var _near_nz := 0
var _near_idx := PackedInt32Array()
# pillars / wreck as flat arrays (height_at is hot)
var _pil_x := PackedFloat32Array()
var _pil_z := PackedFloat32Array()
var _pil_r := PackedFloat32Array()
var _pil_r2 := PackedFloat32Array()
var _pil_h := PackedFloat32Array()
var _pil_base := PackedFloat32Array()
var _wreck_base := 0.0
var _wreck_r2 := 0.0
# scratch for nearest_canyon (no allocation per call)
var near_d := 0.0
var near_s := 0.0
var near_floor := 0.0
var near_w := 0.0

## World def in the schema of the web Worlds.js (`gates: [{x, y, z, heading, width}]`).
var def: Dictionary


func _init() -> void:
	_build_noise()
	_build_canyon()
	for p in PILLARS:
		_pil_x.append(p.x)
		_pil_z.append(p.z)
		_pil_r.append(p.r)
		_pil_r2.append(p.r * p.r * 2.56)
		_pil_h.append(p.h)
		_pil_base.append(_base_seabed(p.x, p.z))
	_wreck_base = _base_seabed(WRECK.x, WRECK.z)
	_wreck_r2 = WRECK.r * WRECK.r
	_build_def()


# ------------------------------------------------------------------ noise
func _build_noise() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var p := PackedInt32Array()
	p.resize(256)
	for i in 256:
		p[i] = i
	for i in range(255, 0, -1):
		var j := rng.randi_range(0, i)
		var t := p[i]
		p[i] = p[j]
		p[j] = t
	_perm.resize(512)
	_val.resize(512)
	for i in 512:
		_perm[i] = p[i & 255]
		_val[i] = rng.randf() * 2.0 - 1.0


func noise2(x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - ix
	var fz := z - iz
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var X := ix & 255
	var Z := iz & 255
	var a := _val[_perm[X] + Z]
	var b := _val[_perm[X + 1] + Z]
	var c := _val[_perm[X] + Z + 1]
	var d := _val[_perm[X + 1] + Z + 1]
	return a + (b - a) * fx + (c - a) * fz + (a - b - c + d) * fx * fz


## Two rotated octaves in roughly [-1, 1]. `o` offsets the lattice so fields do not correlate.
func fbm2(x: float, z: float, o: float) -> float:
	var n0 := noise2(x + o, z + o * 0.37)
	var nx := x * 1.92 + z * 0.62 + 13.7
	var nz := -x * 0.62 + z * 1.92 + 7.1
	return (n0 + 0.5 * noise2(nx + o, nz)) / 1.5


# ------------------------------------------------------------------ course
## Closed Catmull-Rom through PATH; t in [0, 1) maps one control point per 1/N.
static func path_point(t: float) -> Vector3:
	t = fposmod(t, 1.0)
	var f := t * N_PATH
	var i := floori(f)
	var u := f - i
	var p0: Array = PATH[(i - 1 + N_PATH) % N_PATH]
	var p1: Array = PATH[i % N_PATH]
	var p2: Array = PATH[(i + 1) % N_PATH]
	var p3: Array = PATH[(i + 2) % N_PATH]
	var u2 := u * u
	var u3 := u2 * u
	var out := Vector3.ZERO
	for k in 3:
		out[k] = 0.5 * ((2.0 * p1[k]) + (-p0[k] + p2[k]) * u + (2.0 * p0[k] - 5.0 * p1[k] + 4.0 * p2[k] - p3[k]) * u2
			+ (-p0[k] + 3.0 * p1[k] - 3.0 * p2[k] + p3[k]) * u3)
	return out


static func path_heading(t: float) -> float:
	var a := path_point(t - 0.002)
	var b := path_point(t + 0.002)
	return atan2(b.x - a.x, b.z - a.z)


## Shortest distance from (x, z) to the hoop path's control polyline.
static func dist_to_path(x: float, z: float) -> float:
	var best := 1e9
	for i in N_PATH:
		var a: Array = PATH[i]
		var b: Array = PATH[(i + 1) % N_PATH]
		var bx: float = b[0] - a[0]
		var bz: float = b[2] - a[2]
		var f: float = ((x - a[0]) * bx + (z - a[2]) * bz) / (bx * bx + bz * bz)
		f = clampf(f, 0.0, 1.0)
		var dx: float = a[0] + bx * f - x
		var dz: float = a[2] + bz * f - z
		var d := sqrt(dx * dx + dz * dz)
		if d < best:
			best = d
	return best


func _build_canyon() -> void:
	_cx.resize(CANYON_N)
	_cz.resize(CANYON_N)
	_cy.resize(CANYON_N)
	_cw.resize(CANYON_N)
	for i in CANYON_N:
		var s := float(i) / (CANYON_N - 1)
		var p := path_point(lerpf(CANYON_T0, CANYON_T1, s))
		_cx[i] = p.x
		_cz[i] = p.z
		_cy[i] = maxf(p.y - 11.0, FLOOR_MIN)
		# wide mouth, 13 m half-width (26 m wall to wall) through the middle, wide exit
		_cw[i] = lerpf(22.0, 24.0, s) - 10.0 * smoothstep(0.15, 0.45, s) * smoothstep(0.85, 0.55, s) + 1.5 * sin(s * 23.0)
		_box_x0 = minf(_box_x0, p.x - TABLE_REACH)
		_box_x1 = maxf(_box_x1, p.x + TABLE_REACH)
		_box_z0 = minf(_box_z0, p.z - TABLE_REACH)
		_box_z1 = maxf(_box_z1, p.z + TABLE_REACH)
	# Coarse lookup of the nearest canyon segment per 10 m cell over the bounding box, so a query
	# tests that segment and its neighbours instead of all of them.
	_near_nx = ceili((_box_x1 - _box_x0) / NEAR_CELL) + 1
	_near_nz = ceili((_box_z1 - _box_z0) / NEAR_CELL) + 1
	_near_idx.resize(_near_nx * _near_nz)
	for j in _near_nz:
		for i in _near_nx:
			_nearest_segment(_box_x0 + (i + 0.5) * NEAR_CELL, _box_z0 + (j + 0.5) * NEAR_CELL, 0, CANYON_N - 1)
			_near_idx[j * _near_nx + i] = _seg_i


var _seg_d2 := 0.0
var _seg_i := 0
var _seg_f := 0.0


func _nearest_segment(x: float, z: float, i0: int, i1: int) -> void:
	var best := 1e9
	var bi := i0
	var bf := 0.0
	for i in range(i0, i1):
		var ax := _cx[i]
		var az := _cz[i]
		var bx := _cx[i + 1] - ax
		var bz := _cz[i + 1] - az
		var f := ((x - ax) * bx + (z - az) * bz) / (bx * bx + bz * bz)
		f = clampf(f, 0.0, 1.0)
		var dx := ax + bx * f - x
		var dz := az + bz * f - z
		var d := dx * dx + dz * dz
		if d < best:
			best = d
			bi = i
			bf = f
	_seg_d2 = best
	_seg_i = bi
	_seg_f = bf


## Nearest point on the canyon polyline into near_d / near_s / near_floor / near_w. Call inside the box.
func nearest_canyon(x: float, z: float) -> void:
	var ci := clampi(int((x - _box_x0) / NEAR_CELL), 0, _near_nx - 1)
	var cj := clampi(int((z - _box_z0) / NEAR_CELL), 0, _near_nz - 1)
	var guess := _near_idx[cj * _near_nx + ci]
	_nearest_segment(x, z, maxi(0, guess - 2), mini(CANYON_N - 1, guess + 3))
	var bi := _seg_i
	var bf := _seg_f
	near_d = sqrt(_seg_d2)
	near_s = (bi + bf) / float(CANYON_N - 1)
	near_floor = _cy[bi] + (_cy[bi + 1] - _cy[bi]) * bf
	near_w = _cw[bi] + (_cw[bi + 1] - _cw[bi]) * bf


## Canyon sample i (for the arches): [x, z, floor, half-width].
func canyon_sample(i: int) -> Array:
	return [_cx[i], _cz[i], _cy[i], _cw[i]]


# ------------------------------------------------------------------ seabed
## The seabed without pillars or the wreck (their bases are sampled from this).
func _base_seabed(x: float, z: float) -> float:
	var n1 := fbm2(x * 0.012, z * 0.012, 17.3)          # ~80 m sand hills
	var n2 := noise2(x * 0.06 + 91.1, z * 0.06 + 33.7)  # ripples and rubble (one octave: 1 m relief)
	# open plain, shoaling toward the surface start
	var h := PLAIN_Y + n1 * 6.0 + n2 * 1.2 + 14.0 * smoothstep(300.0, 40.0, sqrt(x * x + z * z))
	# the basin: a wide flat sandy bowl
	var bx: float = x - BASIN.x
	var bz: float = z - BASIN.z
	var basin: float = smoothstep(BASIN.r + 70.0, BASIN.r - 30.0, sqrt(bx * bx + bz * bz))
	h = lerpf(h, BASIN.y + n2 * 0.8, basin)
	# Nothing of the canyon reaches past its bounding box: most of the plain skips the search.
	if x < _box_x0 or x > _box_x1 or z < _box_z0 or z > _box_z1:
		return h
	# the rock table the canyon cuts through, fading out at both ends of the cut
	nearest_canyon(x, z)
	if near_d > TABLE_REACH:
		return h
	var along := smoothstep(0.0, 0.16, near_s) * smoothstep(1.0, 0.84, near_s)
	var table := smoothstep(TABLE_REACH, 80.0, near_d) * along * (1.0 - basin)
	h = lerpf(h, RIM_Y + n1 * 3.0 + n2 * 1.5, table)
	# carve: floor, then a steep craggy wall up to well above the table
	if near_d > near_w + 30.0:
		return h
	var dn := near_d + 5.0 * fbm2(x * 0.045, z * 0.045, 41.7)
	var carve := near_floor + n2 * 0.9 + (RIM_Y + 12.0 - near_floor) * smoothstep(near_w, near_w + 17.0, dn)
	return minf(h, carve)


## Seabed height (m, negative) at world (x, z). Exact for the mesh's own source function.
func height_at(x: float, z: float) -> float:
	var h := _base_seabed(x, z)
	for i in 6:
		var dx := x - _pil_x[i]
		var dz := z - _pil_z[i]
		var d2 := dx * dx + dz * dz
		if d2 < _pil_r2[i]:
			h = maxf(h, _pil_base[i] + _pil_h[i] * smoothstep(_pil_r[i] * 1.6, _pil_r[i] * 0.5, sqrt(d2)))
	var wx: float = x - WRECK.x
	var wz: float = z - WRECK.z
	var wd2 := wx * wx + wz * wz
	if wd2 < _wreck_r2:
		h = maxf(h, _wreck_base + WRECK.h * (1.0 - wd2 / _wreck_r2))
	return h


func pillar_base(i: int) -> float:
	return _pil_base[i]


func wreck_base() -> float:
	return _wreck_base


# --------------------------------------------------------------- world def
func _build_def() -> void:
	var gates: Array = []
	for i in GATE_IDX:
		var p: Array = PATH[i]
		var in_canyon: bool = i >= 3 and i <= 7
		var width := 14.0 if in_canyon else (16.0 if (i == 2 or i == 8) else 18.0)
		gates.append({"x": p[0], "y": p[1], "z": p[2], "heading": snappedf(path_heading(float(i) / N_PATH), 0.001), "width": width})
	def = {
		"id": "deep", "name": "The Deep Run", "icon": "submarine", "underwater": true,
		"weather": {
			"key": "clear",
			"patch": {
				"wind_speed": 4.0, "wind_dir_deg": 20.0, "swell_hs": 0.6, "swell_period": 8.0, "choppiness": 1.0,
				"foam": 0.4, "water_color": Color(0.045, 0.19, 0.20), "sun_elev_deg": 60.0, "sun_azimuth_deg": 223.0,
				"cloud_cover": 0.10, "rain": 0.0, "fog": 0.0, "lightning_rate": 0.0,
			},
		},
		"water": {"scatter": [0.045, 0.190, 0.200], "absorb": [0.010, 0.040, 0.050]},
		# Underwater look. color = the water column's glow near the surface; density per metre
		# (~80 m visibility); absorb = per-metre loss with depth (red first) that turns the
		# turquoise deep blue.
		"fog": {"color": [0.09, 0.31, 0.37], "density": 0.022, "absorb": [0.045, 0.015, 0.006]},
		"exposure": 0.85,
		"start": {"x": 0.0, "y": 0.0, "z": 0.0, "heading": 0.0},
		"gates": gates,
		"laps": 1,
		"portals": [{"x": 40.0, "z": -70.0, "heading": PI, "dest": "hub"}],
		"bounds": 900.0,
		"path": PATH,
	}
