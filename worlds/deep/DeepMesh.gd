class_name DeepMesh
extends RefCounted
## Geometry for The Deep Run — port of the mesh half of the web game's src/game/SubmarineWorld.js.
## A flat-shaded, face-coloured triangle soup (world space, linear vertex colours) that becomes
## chunked ArrayMeshes: seabed tiles with skirts, rock pillars, the wreck pile, two canyon arches.
## Plus the kelp MultiMesh and the marine-snow particle set-up.

const TILE := 100.0

# Palette (sRGB hex -> linear)
static var PAL := {
	"sand": Color.html("e9d9a6").srgb_to_linear(), "sand_deep": Color.html("b8b391").srgb_to_linear(),
	"rock": Color.html("66594d").srgb_to_linear(), "rock_dark": Color.html("3a322b").srgb_to_linear(),
	"algae": Color.html("4f8a34").srgb_to_linear(), "algae_light": Color.html("83b23c").srgb_to_linear(),
	"kelp": Color.html("3f6b1f").srgb_to_linear(), "kelp_tip": Color.html("8fb83a").srgb_to_linear(),
	"wreck": Color.html("3b3a3d").srgb_to_linear(),
}

var pos := PackedVector3Array()
var nrm := PackedVector3Array()
var col := PackedColorArray()


func clear() -> void:
	pos.clear()
	nrm.clear()
	col.clear()


func triangles() -> int:
	return pos.size() / 3


func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Godot's front face is clockwise (the web convention was counter-clockwise), so the
	# geometric normal is kept but the vertices are emitted a, c, b.
	var n := (b - a).cross(c - a)
	var l := n.length()
	n = n / l if l > 0.0 else Vector3.UP
	pos.append(a)
	pos.append(c)
	pos.append(b)
	nrm.append(n)
	nrm.append(n)
	nrm.append(n)
	col.append(color)
	col.append(color)
	col.append(color)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	tri(a, b, c, color)
	tri(a, c, d, color)


func box(cx: float, cy: float, cz: float, sx: float, sy: float, sz: float, rot_y: float, color: Color, color_top: Color) -> void:
	var c := cos(rot_y)
	var s := sin(rot_y)
	var hx := sx / 2.0
	var hy := sy / 2.0
	var hz := sz / 2.0
	var P := func(x: float, y: float, z: float) -> Vector3: return Vector3(cx + x * c + z * s, cy + y, cz - x * s + z * c)
	var p000: Vector3 = P.call(-hx, -hy, -hz)
	var p100: Vector3 = P.call(hx, -hy, -hz)
	var p010: Vector3 = P.call(-hx, hy, -hz)
	var p110: Vector3 = P.call(hx, hy, -hz)
	var p001: Vector3 = P.call(-hx, -hy, hz)
	var p101: Vector3 = P.call(hx, -hy, hz)
	var p011: Vector3 = P.call(-hx, hy, hz)
	var p111: Vector3 = P.call(hx, hy, hz)
	quad(p010, p011, p111, p110, color_top)   # top
	quad(p000, p100, p101, p001, color)       # bottom
	quad(p000, p010, p110, p100, color)       # -z
	quad(p101, p111, p011, p001, color)       # +z
	quad(p001, p011, p010, p000, color)       # -x
	quad(p100, p110, p111, p101, color)       # +x


## Commit the soup into an ArrayMesh (one surface) with the given material.
func to_mesh(material: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


# ------------------------------------------------------------------ colours
static func seabed_color(h: float, slope: float, n: float) -> Color:
	var c: Color = PAL.sand.lerp(PAL.sand_deep, smoothstep(-25.0, -60.0, h))
	# algae on flat-ish ledges high up: the table top and the canyon rims
	var algae := smoothstep(-30.0, -14.0, h) * (1.0 - smoothstep(0.5, 0.9, slope)) * clampf(0.55 + n * 1.2, 0.0, 1.0)
	c = c.lerp(PAL.algae.lerp(PAL.algae_light, clampf(0.5 + n, 0.0, 1.0)), algae)
	# rock on steep faces (slope = rise/run; 1 = 45 deg)
	c = c.lerp(PAL.rock.lerp(PAL.rock_dark, clampf(0.5 + n * 0.8, 0.0, 1.0)), smoothstep(0.5, 1.1, slope))
	return c


# ------------------------------------------------------------------- tiles
## One heightfield tile with a skirt hanging from its edges (hides LOD seams).
func build_tile(sb: DeepSeabed, x0: float, z0: float, cells: int) -> void:
	var n := cells + 1
	var step := TILE / cells
	var grid := PackedFloat32Array()
	grid.resize(n * n)
	for j in n:
		for i in n:
			grid[j * n + i] = sb.height_at(x0 + i * step, z0 + j * step)
	for j in cells:
		for i in cells:
			var p := Vector3(x0 + i * step, grid[j * n + i], z0 + j * step)
			var q := Vector3(p.x + step, grid[j * n + i + 1], p.z)
			var r := Vector3(p.x, grid[(j + 1) * n + i], p.z + step)
			var s := Vector3(q.x, grid[(j + 1) * n + i + 1], r.z)
			# alternate the diagonal so the sand does not show a bias
			if (i + j) & 1:
				_emit(sb, p, r, s)
				_emit(sb, p, s, q)
			else:
				_emit(sb, p, r, q)
				_emit(sb, q, r, s)
	# skirts: a wall dropping from each edge, coloured like deep rock
	var DROP := 12.0
	for i in cells:
		var xa := x0 + i * step
		var xb := xa + step
		var za := z0 + i * step
		var zb := za + step
		_skirt(xa, z0, grid[i], xb, z0, grid[i + 1], DROP)
		_skirt(xa, z0 + TILE, grid[cells * n + i], xb, z0 + TILE, grid[cells * n + i + 1], DROP)
		_skirt(x0, za, grid[i * n], x0, zb, grid[(i + 1) * n], DROP)
		_skirt(x0 + TILE, za, grid[i * n + cells], x0 + TILE, zb, grid[(i + 1) * n + cells], DROP)


func _emit(sb: DeepSeabed, p: Vector3, q: Vector3, r: Vector3) -> void:
	var nn := (q - p).cross(r - p)
	var slope := sqrt(nn.x * nn.x + nn.z * nn.z) / maxf(absf(nn.y), 1e-3)
	var mid := (p + q + r) / 3.0
	var c := seabed_color(mid.y, slope, sb.fbm2(mid.x * 0.05, mid.z * 0.05, 511.0))
	if nn.y >= 0.0:
		tri(p, q, r, c)
	else:
		tri(p, r, q, c)


func _skirt(ax: float, az: float, ah: float, bx: float, bz: float, bh: float, drop: float) -> void:
	var a := Vector3(ax, ah, az)
	var b := Vector3(bx, bh, bz)
	var a2 := Vector3(ax, ah - drop, az)
	var b2 := Vector3(bx, bh - drop, bz)
	quad(a, b, b2, a2, PAL.rock_dark)
	quad(a2, b2, b, a, PAL.rock_dark)


# ----------------------------------------------------------------- details
func add_pillar(sb: DeepSeabed, idx: int, rng: RandomNumberGenerator) -> void:
	var p: Dictionary = DeepSeabed.PILLARS[idx]
	var base := sb.pillar_base(idx)
	var sides := 7
	var segs := 5
	var prev: Array = []
	for k in segs + 1:
		var t := float(k) / segs
		var y: float = base - 2.0 + (p.h + 2.0) * t
		var r: float = p.r * (1.15 - 0.55 * t) * (0.85 + 0.3 * sin(t * 9.0 + p.x))
		var ring: Array = []
		for s in sides:
			var a := (float(s) / sides) * TAU + t * 0.5
			var rr := r * (0.8 + 0.4 * rng.randf())
			ring.append(Vector3(p.x + cos(a) * rr, y, p.z + sin(a) * rr))
		if not prev.is_empty():
			for s in sides:
				var c: Color = PAL.rock.lerp(PAL.rock_dark, rng.randf() * 0.7)
				quad(prev[s], ring[s], ring[(s + 1) % sides], prev[(s + 1) % sides], c)
		prev = ring
		if k == segs:
			var c: Color = PAL.algae.lerp(PAL.rock, 0.5)
			for s in sides:
				tri(Vector3(p.x, y + 0.6, p.z), ring[(s + 1) % sides], ring[s], c)


## Wreck-like rock pile: tilted slabs and a broken "keel" leaning on each other.
func add_wreck(sb: DeepSeabed, rng: RandomNumberGenerator) -> void:
	var W: Dictionary = DeepSeabed.WRECK
	var y0 := sb.wreck_base()
	var slabs := 11
	for i in slabs:
		var a := (float(i) / slabs) * TAU + rng.randf() * 0.5
		var r := 4.0 + rng.randf() * 12.0
		var x: float = W.x + cos(a) * r
		var z: float = W.z + sin(a) * r
		var h := 3.0 + rng.randf() * 7.0
		var c: Color = PAL.wreck.lerp(PAL.rock_dark, rng.randf() * 0.6)
		box(x, y0 + h * 0.35, z, 2.0 + rng.randf() * 4.0, h, 6.0 + rng.randf() * 9.0, rng.randf() * PI, c, c.lerp(PAL.algae, 0.35))
	# the keel: one long slab across the middle, hull-ribs off it
	box(W.x, y0 + 5.0, W.z, 3.5, 4.0, 30.0, 0.5, PAL.wreck, PAL.wreck.lerp(PAL.algae, 0.3))
	for i in range(-2, 3):
		var t := i * 5.5
		box(W.x + sin(0.5) * t, y0 + 8.0, W.z + cos(0.5) * t, 14.0, 1.2, 1.2, 0.5, PAL.wreck, PAL.wreck)


## An arch across the canyon: a row of boxes on a semi-ellipse from rim to rim.
func add_arch(sb: DeepSeabed, s: float, rng: RandomNumberGenerator) -> void:
	var i := mini(DeepSeabed.CANYON_N - 2, floori(s * (DeepSeabed.CANYON_N - 1)))
	var c0 := sb.canyon_sample(i)
	var c1 := sb.canyon_sample(i + 1)
	var tx: float = c1[0] - c0[0]
	var tz: float = c1[1] - c0[1]
	var tl := maxf(sqrt(tx * tx + tz * tz), 1.0)
	var px := -tz / tl
	var pz := tx / tl
	var cx: float = c0[0]
	var cz: float = c0[1]
	var floor_y: float = c0[2]
	var half: float = c0[3] + 14.0
	var apex := floor_y + 32.0
	var n := 9
	var heading := atan2(tx, tz)
	for k in n:
		var u := -1.0 + (2.0 * (k + 0.5)) / n
		var x := cx + px * half * u
		var z := cz + pz * half * u
		var y := floor_y + (apex - floor_y) * sqrt(maxf(1.0 - u * u * 0.92, 0.04)) - 2.0
		var c: Color = PAL.rock.lerp(PAL.rock_dark, 0.4 + rng.randf() * 0.5)
		box(x, y, z, 2.0 * half / n + 1.5, 5.0 + rng.randf() * 2.0, 6.0 + rng.randf() * 3.0, heading, c, c.lerp(PAL.algae, 0.3))


# -------------------------------------------------------------------- kelp
## The unit kelp ribbon: 1 m tall, 1 m wide at the root tapering to 0.4 at the tip, 6 segments,
## UV.y = height fraction, vertex colours kelp -> kelp_tip. Instances scale it to (w, H, w).
static func kelp_ribbon(material: Material) -> ArrayMesh:
	var segs := 6
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	var uv := PackedVector2Array()
	var push := func(p: Vector3, t: float) -> void:
		v.append(p)
		nn.append(Vector3(0, 0, 1))
		cc.append(PAL.kelp.lerp(PAL.kelp_tip, t))
		uv.append(Vector2(0.0, t))
	for k in segs:
		var t0 := float(k) / segs
		var t1 := float(k + 1) / segs
		var w0 := 0.5 * (1.0 - t0 * 0.6)
		var w1 := 0.5 * (1.0 - t1 * 0.6)
		var a := Vector3(-w0, t0, 0)
		var b := Vector3(w0, t0, 0)
		var c := Vector3(w1, t1, 0)
		var d := Vector3(-w1, t1, 0)
		push.call(a, t0); push.call(b, t0); push.call(c, t1)
		push.call(a, t0); push.call(c, t1); push.call(d, t1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nn
	arrays[Mesh.ARRAY_COLOR] = cc
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


## Places `count` strands lining the hoop path and the basin; returns the MultiMesh.
static func build_kelp(sb: DeepSeabed, rng: RandomNumberGenerator, count: int, material: Material) -> MultiMesh:
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var tries := 0
	var basin: Dictionary = DeepSeabed.BASIN
	while tries < count * 12 and xforms.size() < count:
		tries += 1
		var x: float
		var z: float
		if rng.randf() < 0.62:
			# lining the canyon floor edges and the shallows either side of the path
			var t := rng.randf()
			var p := DeepSeabed.path_point(t)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var h := DeepSeabed.path_heading(t)
			var off := 10.0 + rng.randf() * 26.0
			x = p.x + cos(h) * side * off
			z = p.z - sin(h) * side * off
		else:
			var a := rng.randf() * TAU
			var r: float = rng.randf() * basin.r
			x = basin.x + cos(a) * r
			z = basin.z + sin(a) * r
		var y := sb.height_at(x, z)
		if y < -61.0 or y > -8.0:
			continue
		var dx := sb.height_at(x + 1.5, z) - sb.height_at(x - 1.5, z)
		var dz := sb.height_at(x, z + 1.5) - sb.height_at(x, z - 1.5)
		if sqrt(dx * dx + dz * dz) / 3.0 > 0.7:
			continue
		if DeepSeabed.dist_to_path(x, z) < 9.0:
			continue
		var H := 5.0 + rng.randf() * 6.0
		var w0 := 0.7 + rng.randf() * 0.4
		var phase := rng.randf()
		var facing := rng.randf() * TAU
		var lean := (rng.randf() - 0.5) * 0.25 * H
		var basis := Basis(Vector3.UP, facing) * Basis.from_scale(Vector3(w0 * 2.0, H, 1.0))
		xforms.append(Transform3D(basis, Vector3(x, y - 0.3, z)))
		customs.append(Color(phase, lean, 0.0, 0.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = kelp_ribbon(material)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i])
	return mm


# ------------------------------------------------------------- marine snow
## A 56 m box of slowly sinking motes (and a few rising bubbles) that Main/World keeps centred on
## the camera. Particles live in world space so moving the emitter does not drag them along.
static func build_snow(material: Material, count: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "MarineSnow"
	p.amount = count
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.local_coords = false
	p.fixed_fps = 30
	p.interpolate = true
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 28, 28)
	pm.direction = Vector3(0.35, -0.18, 0.12)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3.ZERO
	pm.scale_min = 1.0
	pm.scale_max = 1.0
	# random per-particle seed in COLOR.rg (sampled at a random offset), alpha envelope over life
	pm.color_initial_ramp = _noise_ramp(2001)
	pm.color_ramp = _alpha_ramp()
	p.process_material = pm
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(1, 1)
	quad_mesh.material = material
	p.draw_pass_1 = quad_mesh
	return p


## A gradient of random colours (constant interpolation) so a particle's initial colour is a seed.
static func _noise_ramp(seed: int) -> GradientTexture1D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	var n := 64
	for i in n:
		offsets.append(float(i) / n)
		colors.append(Color(rng.randf(), rng.randf(), rng.randf(), 1.0))
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 64
	return tex


static func _alpha_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 0.85, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 32
	return tex
