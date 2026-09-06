class_name IslandBuilder
extends RefCounted
## Geometry for the toy islands: port of the Soup / terrain / palm / lighthouse / hut / pier
## builders in src/game/Islands.js. Everything is flat-shaded, face-coloured, non-indexed
## triangle soup in world space rendered with one shared vertex-colour material.

# Palette (sRGB hex like the web, stored linear). Saturated and warm: toy islands, not survey data.
static var PAL := {
	"sand_wet": _c("d9c184"), "sand": _c("f7e3a4"), "grass_a": _c("5fc23a"), "grass_b": _c("8ddb46"),
	"grass_high": _c("2f9440"), "rock": _c("b09a80"), "rock_dark": _c("8a7562"), "crown": _c("3d6f3a"),
	"trunk": _c("9a6b3c"), "trunk_dark": _c("7a5230"), "frond": _c("2f9e3d"), "frond_tip": _c("7fd24a"), "coconut": _c("6b4a2b"),
	"white": _c("f8f8f4"), "red": _c("e8402f"), "glass": _c("bfe9ff"), "roof": _c("d9382a"), "grey": _c("6a7079"),
	"wall": _c("f4d58a"), "wood": _c("9c6a3e"), "wood_dark": _c("7e5330"), "rope": _c("e8dcb8"),
}


static func _c(hex: String) -> Color:
	return Color.html(hex).srgb_to_linear()


## Flat-shaded, face-coloured, non-indexed triangle soup.
class Soup:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
		var n := (b - a).cross(c - a)
		var l := n.length()
		n = n / l if l > 0.0 else Vector3.UP
		pos.append(a)
		pos.append(b)
		pos.append(c)
		nrm.append(n)
		nrm.append(n)
		nrm.append(n)
		col.append(color)
		col.append(color)
		col.append(color)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
		tri(a, b, c, color)
		tri(a, c, d, color)

	func triangles() -> int:
		return pos.size() / 3

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if pos.is_empty():
			return m
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = col
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.metallic = 0.0
	return mat


# ------------------------------------------------------------------ terrain
static func terrain_color(h: float, slope: float, n: float, def: Dictionary) -> Color:
	var H: float = def.height
	# sand, wetter as it goes under
	var c: Color = PAL.sand_wet.lerp(PAL.sand, smoothstep(-1.6, 0.2, h))
	# grass: two greens picked by noise
	var g := smoothstep(1.35, 2.3, h)
	var grass: Color = PAL.grass_a.lerp(PAL.grass_b, clampf(0.5 + n * 0.9, 0.0, 1.0))
	c = c.lerp(grass, g)
	# highland: darker
	c = c.lerp(PAL.grass_high, smoothstep(0.45 * H, 0.85 * H, h) * 0.75)
	c = c.lerp(PAL.crown, smoothstep(0.85 * H, H * 1.05, h) * 0.6)
	# rock only on genuinely steep faces (slope is rise/run; 1.0 = 45 deg)
	var rk := smoothstep(1.15, 1.8, slope) * smoothstep(1.5, 3.0, h)
	c = c.lerp(PAL.rock.lerp(PAL.rock_dark, clampf(0.5 + n * 0.6, 0.0, 1.0)), rk)
	return c


static func _emit_terrain(soup: Soup, p: Vector3, q: Vector3, r: Vector3, seed: int, def: Dictionary) -> void:
	if p.y < IslandField.CULL_DEPTH and q.y < IslandField.CULL_DEPTH and r.y < IslandField.CULL_DEPTH:
		return
	var n := (q - p).cross(r - p)
	var slope := Vector2(n.x, n.z).length() / maxf(absf(n.y), 1e-3)
	var m := (p + q + r) / 3.0
	var nz := IslandField.fbm(m.x * 0.08, m.z * 0.08, seed + 99, 2)
	var col := terrain_color(m.y, slope, nz, def)
	if n.y >= 0.0:
		soup.tri(p, q, r, col)
	else:
		soup.tri(p, r, q, col)


## Terrain soup for one island field (<= MAX_TRIS triangles by construction).
static func build_terrain(field: IslandField, soup: Soup) -> void:
	var nu := field.nu
	var nv := field.nv
	var grid := field.grid
	var seed: int = field.def.seed
	var def := field.def
	# cache the parametric row above to halve the to_world calls
	var row: Array[Vector2] = []
	var next: Array[Vector2] = []
	row.resize(nu)
	next.resize(nu)
	for i in nu:
		row[i] = field.to_world(float(i) / float(nu - 1), 0.0)
	for j in nv - 1:
		var v1 := float(j + 1) / float(nv - 1)
		for i in nu:
			next[i] = field.to_world(float(i) / float(nu - 1), v1)
		for i in nu - 1:
			var a := Vector3(row[i].x, grid[j * nu + i], row[i].y)
			var b := Vector3(row[i + 1].x, grid[j * nu + i + 1], row[i + 1].y)
			var c := Vector3(next[i].x, grid[(j + 1) * nu + i], next[i].y)
			var d := Vector3(next[i + 1].x, grid[(j + 1) * nu + i + 1], next[i + 1].y)
			_emit_terrain(soup, a, c, d, seed, def)
			_emit_terrain(soup, a, d, b, seed, def)
		var tmp := row
		row = next
		next = tmp


# ------------------------------------------------------------- primitives
static func ring(cx: float, cy: float, cz: float, r: float, sides: int, phase := 0.0) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for k in sides:
		var a := phase + (float(k) / sides) * TAU
		pts.append(Vector3(cx + cos(a) * r, cy, cz + sin(a) * r))
	return pts


static func tube(soup: Soup, r0: Array[Vector3], r1: Array[Vector3], col: Color) -> void:
	var n := r0.size()
	for k in n:
		soup.quad(r0[k], r1[k], r1[(k + 1) % n], r0[(k + 1) % n], col)


static func cap(soup: Soup, rg: Array[Vector3], cx: float, cy: float, cz: float, col: Color, down := false) -> void:
	var n := rg.size()
	var c := Vector3(cx, cy, cz)
	for k in n:
		var p := rg[k]
		var q := rg[(k + 1) % n]
		if down:
			soup.tri(c, p, q, col)
		else:
			soup.tri(c, q, p, col)


static func cone(soup: Soup, rg: Array[Vector3], cx: float, cy: float, cz: float, col: Color) -> void:
	cap(soup, rg, cx, cy, cz, col, false)


static func cylinder(soup: Soup, cx: float, cz: float, y0: float, y1: float, r0: float, r1: float, sides: int, col: Color, caps := true) -> void:
	var a := ring(cx, y0, cz, r0, sides)
	var b := ring(cx, y1, cz, r1, sides)
	tube(soup, a, b, col)
	if caps:
		cap(soup, b, cx, y1, cz, col)
		cap(soup, a, cx, y0, cz, col, true)


static func box(soup: Soup, cx: float, cy: float, cz: float, sx: float, sy: float, sz: float, rot_y: float, col: Color, col_top := Color(-1, 0, 0)) -> void:
	if col_top.r < 0.0:
		col_top = col
	var c := cos(rot_y)
	var s := sin(rot_y)
	var hx := sx / 2.0
	var hy := sy / 2.0
	var hz := sz / 2.0
	var P := func(x: float, y: float, z: float) -> Vector3:
		return Vector3(cx + x * c + z * s, cy + y, cz - x * s + z * c)
	var p000: Vector3 = P.call(-hx, -hy, -hz)
	var p100: Vector3 = P.call(hx, -hy, -hz)
	var p010: Vector3 = P.call(-hx, hy, -hz)
	var p110: Vector3 = P.call(hx, hy, -hz)
	var p001: Vector3 = P.call(-hx, -hy, hz)
	var p101: Vector3 = P.call(hx, -hy, hz)
	var p011: Vector3 = P.call(-hx, hy, hz)
	var p111: Vector3 = P.call(hx, hy, hz)
	soup.quad(p010, p011, p111, p110, col_top)   # top
	soup.quad(p000, p100, p101, p001, col)       # bottom
	soup.quad(p000, p010, p110, p100, col)       # -z
	soup.quad(p101, p111, p011, p001, col)       # +z
	soup.quad(p001, p011, p010, p000, col)       # -x
	soup.quad(p100, p110, p111, p101, col)       # +x


# ---------------------------------------------------------------- details
## A palm at (x, y, z); size, lean and frond count from the rng like the web.
static func add_palm(soup: Soup, x: float, y: float, z: float, rng: IslandField.Rng, s := -1.0) -> void:
	if s < 0.0:
		s = 0.8 + rng.next() * 0.55
	var H := 5.2 * s
	var la := rng.next() * TAU
	var lean := (0.6 + rng.next() * 1.8) * s
	var lx := cos(la) * lean
	var lz := sin(la) * lean
	var segs := 4
	var sides := 5
	var prev: Array[Vector3] = []
	var trunk_col: Color = PAL.trunk.lerp(PAL.trunk_dark, rng.next() * 0.5)
	for k in segs + 1:
		var t := float(k) / segs
		var r := (0.30 - 0.14 * t) * s
		var rg := ring(x + lx * t * t, y - 0.3 + H * t, z + lz * t * t, r, sides, t * 0.4)
		if not prev.is_empty():
			tube(soup, prev, rg, trunk_col)
		prev = rg
	var tx := x + lx
	var ty := y - 0.3 + H
	var tz := z + lz
	# fronds
	var n := 6 + (1 if rng.next() < 0.5 else 0)
	var rot := rng.next() * TAU
	for i in n:
		var a := rot + (float(i) / n) * TAU + (rng.next() - 0.5) * 0.35
		var dx := cos(a)
		var dz := sin(a)
		var L := (2.6 + rng.next() * 1.0) * s
		var px := -dz
		var pz := dx
		var steps := 3
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for k in steps + 1:
			var t := float(k) / steps
			var lift := (0.85 * t - 1.55 * t * t) * s
			var w := (0.12 if k == 0 else 0.55 * (1.0 - t * 0.8)) * s
			var c0 := Vector3(tx + dx * L * t, ty + lift, tz + dz * L * t)
			var Lp := Vector3(c0.x + px * w, c0.y, c0.z + pz * w)
			var Rp := Vector3(c0.x - px * w, c0.y, c0.z - pz * w)
			if k > 0:
				var col: Color = PAL.frond.lerp(PAL.frond_tip, t * 0.85)
				soup.quad(prev_l, Lp, Rp, prev_r, col)      # top
				soup.quad(prev_r, Rp, Lp, prev_l, col)      # underside
			prev_l = Lp
			prev_r = Rp
	# a couple of coconuts
	for i in 2:
		var a := rng.next() * TAU
		cylinder(soup, tx + cos(a) * 0.28 * s, tz + sin(a) * 0.28 * s, ty - 0.55 * s, ty - 0.2 * s, 0.13 * s, 0.13 * s, 4, PAL.coconut)


## Palm mesh variant around the origin (unit size) for the MultiMesh.
static func palm_mesh(variant: int) -> ArrayMesh:
	var soup := Soup.new()
	var rng := IslandField.Rng.new(9001 + variant * 977)
	add_palm(soup, 0.0, 0.0, 0.0, rng, 1.0)
	return soup.mesh()


static func add_lighthouse(soup: Soup, x: float, y: float, z: float) -> void:
	var bands: Array = [PAL.white, PAL.red, PAL.white, PAL.red, PAL.white]
	var h := 3.0
	for i in bands.size():
		var r0 := 2.7 - i * 0.22
		var r1 := 2.7 - (i + 1) * 0.22
		cylinder(soup, x, z, y + i * h, y + (i + 1) * h, r0, r1, 10, bands[i], false)
	var top := y + bands.size() * h
	cylinder(soup, x, z, y - 1.5, y + 0.4, 3.4, 3.4, 10, PAL.grey)          # plinth
	cylinder(soup, x, z, top, top + 0.5, 2.4, 2.4, 10, PAL.grey)            # gallery
	cylinder(soup, x, z, top + 0.5, top + 3.0, 1.5, 1.5, 8, PAL.glass, false)   # lantern
	var rg := ring(x, top + 3.0, z, 2.1, 8)
	cylinder(soup, x, z, top + 2.8, top + 3.0, 2.1, 2.1, 8, PAL.roof)
	cone(soup, rg, x, top + 5.6, z, PAL.roof)
	cylinder(soup, x, z, top + 5.5, top + 6.3, 0.2, 0.2, 4, PAL.grey)


static func add_hut(soup: Soup, x: float, y: float, z: float, rot: float) -> void:
	box(soup, x, y + 1.3, z, 4.2, 2.6, 4.2, rot, PAL.wall)
	box(soup, x, y + 0.2, z, 5.6, 0.4, 5.6, rot, PAL.wood_dark, PAL.wood)
	var rg := ring(x, y + 2.55, z, 3.6, 4, rot + PI / 4.0)
	cone(soup, rg, x, y + 4.9, z, PAL.roof)
	# door
	var c := cos(rot)
	var s := sin(rot)
	box(soup, x + s * 2.12, y + 1.0, z + c * 2.12, 1.0, 1.9, 0.12, rot, PAL.wood_dark)


## Pier: deck planks on posts, running `length` metres from (x, z) along `heading`.
static func add_pier(soup: Soup, p: Dictionary) -> void:
	var fx := sin(p.heading)
	var fz := cos(p.heading)
	var w: float = p.get("width", 4.0)
	var deck_y: float = p.get("deck_y", 1.2)
	var length: float = p.length
	var cx: float = p.x + fx * length / 2.0
	var cz: float = p.z + fz * length / 2.0
	box(soup, cx, deck_y - 0.15, cz, w, 0.3, length, p.heading, PAL.wood_dark, PAL.wood)
	# rails
	box(soup, cx - fz * (w / 2.0 - 0.1), deck_y + 0.55, cz + fx * (w / 2.0 - 0.1), 0.12, 0.08, length, p.heading, PAL.rope)
	box(soup, cx + fz * (w / 2.0 - 0.1), deck_y + 0.55, cz - fx * (w / 2.0 - 0.1), 0.12, 0.08, length, p.heading, PAL.rope)
	var s := 0.0
	while s <= length:
		var px: float = p.x + fx * s
		var pz: float = p.z + fz * s
		for side: float in [-1.0, 1.0]:
			var ox := -fz * side * (w / 2.0 - 0.1)
			var oz := fx * side * (w / 2.0 - 0.1)
			box(soup, px + ox, deck_y - 1.2, pz + oz, 0.36, 4.4, 0.36, p.heading, PAL.wood_dark)
			box(soup, px + ox, deck_y + 0.55, pz + oz, 0.16, 1.1, 0.16, p.heading, PAL.wood_dark)
		s += 6.0
	# a couple of bollards at the sea end
	var ex: float = p.x + fx * (length - 1.2)
	var ez: float = p.z + fz * (length - 1.2)
	cylinder(soup, ex - fz * 1.2, ez + fx * 1.2, deck_y, deck_y + 0.7, 0.22, 0.2, 6, PAL.red)
	cylinder(soup, ex + fz * 1.2, ez - fx * 1.2, deck_y, deck_y + 0.7, 0.22, 0.2, 6, PAL.red)


## Palm sites on grass above 2 m: [Vector3(x, h, z), ...] (same rules as the web scatter).
static func scatter_palms(field: IslandField, rng: IslandField.Rng) -> Array[Vector3]:
	var count := mini(IslandField.MAX_PALMS, int(field.def.palms))
	var placed: Array[Vector3] = []
	if count <= 0:
		return placed
	var H: float = field.def.height
	var top := maxf(4.0, H * (0.98 if field.shape == "plateau" else 0.72))
	var tries := 0
	while tries < 600 and placed.size() < count:
		tries += 1
		var p := field.to_world(rng.next(), rng.next())
		var h := field.sample(p.x, p.y)
		if h < 2.2 or h > top:
			continue
		if field.slope(p.x, p.y) > 0.42:
			continue
		var ok := true
		for q in placed:
			if (q.x - p.x) * (q.x - p.x) + (q.z - p.y) * (q.z - p.y) < 4.5 * 4.5:
				ok = false
				break
		if not ok:
			continue
		placed.append(Vector3(p.x, h, p.y))
	return placed


## Site for a lighthouse / hut: the highest not-too-steep point of the island's middle,
## or the explicit {x, z} the def gives. Returns Vector3(x, h, z) or Vector3.INF.
static func pick_site(field: IslandField, spec, min_h: float, rng: IslandField.Rng) -> Vector3:
	if spec == null or spec == false:
		return Vector3.INF
	if spec is Dictionary:
		return Vector3(spec.x, field.sample(spec.x, spec.z), spec.z)
	var best := Vector3.INF
	for tries in 400:
		var p := field.to_world(0.2 + rng.next() * 0.6, 0.2 + rng.next() * 0.6)
		var h := field.sample(p.x, p.y)
		if h < min_h or field.slope(p.x, p.y, 4.0) > 0.3:
			continue
		if best == Vector3.INF or h > best.y:
			best = Vector3(p.x, h, p.y)
	return best
