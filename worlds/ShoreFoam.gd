class_name ShoreFoam
extends MeshInstance3D
## Shore foam: the white swash line where the sea meets every beach (port of ShoreFoam.js).
##
## At build time each island's waterline is traced by marching rays through `world.terrain_at`
## (radially for round islands, across the ridge for a crescent) to where the sand crosses
## WATERLINE. A band of ROWS vertex rows straddles that line, from a couple of metres up the
## beach to SEAWARD metres out. Every island shares one mesh and one material: one draw call.
##
## A few times per second each island re-lays its vertices on max(sand, ocean.height_at) so the
## band rides the swell; islands far from the camera rest on the mean surface and refresh
## rarely. The shader animates a surging swash line plus foam pulses travelling shoreward.

const RAYS := 96                     # waterline samples per island (per side for a crescent)
const ROWS := 4                      # vertex rows across the band
const ROW_T := [0.0, 0.22, 0.58, 1.0]   # across-coordinate of each row (0 beach .. 1 sea)
const BEACH := 2.0                   # metres the band reaches up the sand
const SEAWARD := 8.0                 # metres out to sea at Hs 0; grows with the swell
const WATERLINE := -0.1              # terrain height that defines the shoreline
const LIFT := 0.14                   # band sits this far above the sampled sea (+ a share of Hs)
const SAND_LIFT := 0.15              # and this far above exposed sand
const NEAR_RANGE := 350.0            # islands closer than this (+ their radius) ride the waves
const NEAR_PERIOD := 0.2             # seconds between re-lays for near islands
const FAR_PERIOD := 2.0

var ocean: Node
var world: Node
var islands: Array = []              # {start, count, pts: PackedVector2Array, nrm: PackedVector2Array, terrain: PackedFloat32Array, cx, cz, r, timer, near}
var seaward := SEAWARD
var offsets: Array[float] = []
var vertices := 0
var triangles := 0
var _positions := PackedVector3Array()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _indices := PackedInt32Array()
var _mesh: ArrayMesh
var _mat: ShaderMaterial
var _dirty := false


func _init() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/shore_foam.gdshader")
	_mesh = ArrayMesh.new()
	mesh = _mesh
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0       # world-space band; never let the AABB cull it


# ------------------------------------------------------------ waterline trace
## Walk outward from (x0, z0) along (dx, dz) from r0 to r1 and return the first radius where the
## terrain drops below WATERLINE, refined by bisection; -1 when the ray never leaves land.
func _crossing(x0: float, z0: float, dx: float, dz: float, r0: float, r1: float, step: float) -> float:
	var prev := r0
	if world.terrain_at(x0 + dx * r0, z0 + dz * r0) < WATERLINE:
		return -1.0
	var r := r0 + step
	while r <= r1 + 1e-6:
		if world.terrain_at(x0 + dx * r, z0 + dz * r) < WATERLINE:
			var a := prev
			var b := r
			for i in 7:
				var m := (a + b) * 0.5
				if world.terrain_at(x0 + dx * m, z0 + dz * m) < WATERLINE:
					b = m
				else:
					a = m
			return (a + b) * 0.5
		prev = r
		r += step
	return -1.0


## Radial trace for a cone / plateau island: [points, outward normals].
func _trace_round(d: Dictionary) -> Array:
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	var r_min: float = d.radius * 0.3
	var r_max: float = d.radius * 1.9
	for i in RAYS:
		var a := (float(i) / RAYS) * TAU
		var dx := cos(a)
		var dz := sin(a)
		var r := _crossing(d.x, d.z, dx, dz, r_min, r_max, 2.5)
		if r < 0.0:
			continue
		pts.append(Vector2(d.x + dx * r, d.z + dz * r))
		nrm.append(Vector2(dx, dz))
	return [pts, nrm]


## Crescent: outer coast a0 -> a1 then inner coast a1 -> a0, chained into one closed loop.
func _trace_arc(d: Dictionary) -> Array:
	var arc: Dictionary = d.arc
	var cap: float = 1.6 * arc.thick / arc.r
	var u0: float = arc.a0 - cap
	var u1: float = arc.a1 + cap
	var outer_p := PackedVector2Array()
	var outer_n := PackedVector2Array()
	var inner_p := PackedVector2Array()
	var inner_n := PackedVector2Array()
	var reach: float = minf(arc.thick * 2.2, arc.r - 1.0)
	for i in RAYS + 1:
		var a := u0 + (u1 - u0) * (float(i) / RAYS)
		var dx := cos(a)
		var dz := sin(a)
		var rx: float = d.x + dx * arc.r
		var rz: float = d.z + dz * arc.r
		var ro := _crossing(rx, rz, dx, dz, 0.0, reach, 2.5)
		var ri := _crossing(rx, rz, -dx, -dz, 0.0, reach, 2.5)
		if ro < 0.0 or ri < 0.0:
			continue
		outer_p.append(Vector2(rx + dx * ro, rz + dz * ro))
		outer_n.append(Vector2(dx, dz))
		inner_p.append(Vector2(rx - dx * ri, rz - dz * ri))
		inner_n.append(Vector2(-dx, -dz))
	inner_p.reverse()
	inner_n.reverse()
	outer_p.append_array(inner_p)
	outer_n.append_array(inner_n)
	return [outer_p, outer_n]


# ------------------------------------------------------------------ build
func build(world_in: Node, ocean_in: Node) -> void:
	_clear()
	world = world_in
	ocean = ocean_in
	if world == null or not world.has_method("terrain_at"):
		return
	var def: Dictionary = world.def
	var defs: Array = def.get("islands", [])
	if defs.is_empty():
		return
	var hs: float = def.weather.get("patch", {}).get("swell_hs", 0.5)
	seaward = SEAWARD + hs * 2.5
	_mat.set_shader_parameter("surf", clampf(0.9 + hs * 0.4, 0.9, 1.8))
	offsets.clear()
	for t in ROW_T:
		offsets.append(-BEACH + t * (BEACH + seaward))

	var total := 0
	for i in defs.size():
		var d: Dictionary = defs[i]
		var traced: Array = _trace_arc(d) if (d.get("shape", "") == "crescent" and d.has("arc")) else _trace_round(d)
		var pts: PackedVector2Array = traced[0]
		var nrm: PackedVector2Array = traced[1]
		if pts.size() < 3:
			continue
		# sand height under every vertex is static: sample it once
		var terrain := PackedFloat32Array()
		terrain.resize(pts.size() * ROWS)
		var c := Vector2.ZERO
		for k in pts.size():
			c += pts[k]
			for r in ROWS:
				var o := offsets[r]
				terrain[k * ROWS + r] = world.terrain_at(pts[k].x + nrm[k].x * o, pts[k].y + nrm[k].y * o)
		c /= pts.size()
		var rad := 0.0
		for p in pts:
			rad = maxf(rad, (p - c).length())
		islands.append({"start": total, "count": pts.size(), "pts": pts, "nrm": nrm, "terrain": terrain,
			"seed": islands.size(), "cx": c.x, "cz": c.y, "r": rad + seaward, "timer": randf() * NEAR_PERIOD, "near": false})
		total += pts.size()
	if total == 0:
		return

	vertices = total * ROWS
	_positions.resize(vertices)
	_uv.resize(vertices)
	_uv2.resize(vertices)
	_indices.resize(total * (ROWS - 1) * 6)
	var o := 0
	for isl in islands:
		var count: int = isl.count
		var start: int = isl.start
		var nrm: PackedVector2Array = isl.nrm
		for i in count:
			var i1 := (i + 1) % count
			for k in ROWS:
				var v := (start + i) * ROWS + k
				_uv[v] = Vector2(ROW_T[k], float(isl.seed))
				_uv2[v] = nrm[i]
				if k < ROWS - 1:
					var a := v
					var b := (start + i1) * ROWS + k
					var c := v + 1
					var d := b + 1
					_indices[o] = a
					_indices[o + 1] = b
					_indices[o + 2] = c
					_indices[o + 3] = c
					_indices[o + 4] = b
					_indices[o + 5] = d
					o += 6
	triangles = total * (ROWS - 1) * 2
	for isl in islands:
		_lay_island(isl, false)
	_upload()


func _sea_height(x: float, z: float) -> float:
	if ocean and ocean.has_method("height_at"):
		return ocean.height_at(x, z)
	return 0.0


func _lay_island(isl: Dictionary, near: bool) -> void:
	var hs := 0.0
	if ocean and "significant_wave_height" in ocean:
		hs = ocean.significant_wave_height
	# near: ride the sampled sea; far: the band is edge-on and sub-pixel, rest on the mean
	# surface a little higher so the surf line keeps a pixel of height
	var lift: float = LIFT + hs * 0.25 if near else LIFT + 0.5 + hs * 0.40
	var pts: PackedVector2Array = isl.pts
	var nrm: PackedVector2Array = isl.nrm
	var terrain: PackedFloat32Array = isl.terrain
	var start: int = isl.start
	for i in pts.size():
		var p := pts[i]
		var n := nrm[i]
		for k in ROWS:
			var o := offsets[k]
			var x := p.x + n.x * o
			var z := p.y + n.y * o
			var h: float = (_sea_height(x, z) if near else 0.0) + lift
			_positions[(start + i) * ROWS + k] = Vector3(x, maxf(terrain[i * ROWS + k] + SAND_LIFT, h), z)
	_dirty = true


func _upload() -> void:
	_mesh.clear_surfaces()
	if _positions.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _positions
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_INDEX] = _indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_dirty = false


func update(dt: float) -> void:
	if islands.is_empty() or dt <= 0.0:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var focus := cam.global_position if cam else Vector3.ZERO
	for isl in islands:
		var near := Vector2(isl.cx - focus.x, isl.cz - focus.z).length() < NEAR_RANGE + float(isl.r)
		isl.timer -= dt
		if isl.timer > 0.0 and near == isl.near:
			continue
		isl.near = near
		isl.timer = NEAR_PERIOD if near else FAR_PERIOD
		_lay_island(isl, near)
	if _dirty:
		_upload()


func _clear() -> void:
	islands.clear()
	_positions = PackedVector3Array()
	_uv = PackedVector2Array()
	_uv2 = PackedVector2Array()
	_indices = PackedInt32Array()
	_mesh.clear_surfaces()
	vertices = 0
	triangles = 0
