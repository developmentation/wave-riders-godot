class_name Portals
extends Node3D
## Portal rings (port of src/game/Portals.js): 12 m glowing tori standing in the water, each
## filled with a swirling disc of "liquid light", topped by a floating icon, wrapped in a soft
## light column and a fountain of sparkles. Driving through one fires `test()` once;
## `transition()` runs the white-out that hides the world swap.
##
##   portals.ocean = ocean; portals.build(def.portals)
##   var dest := portals.test(boat)        # "" or a world id, once per crossing (3 s re-entry cooldown)
##   await portals.transition(func(): await game.load_world(dest))

const RING_RADIUS := 6.0
const TUBE := 0.5
const RING_Y := 6.3                      # torus centre above the (bobbing) sea
const ICON_Y := RING_Y + RING_RADIUS + TUBE + 3.4
const COLUMN_H := 26.0
const POOL_R := RING_RADIUS * 1.35
const SPARKLES := 160
const REENTRY_COOLDOWN := 3.0
const TRANSITION_OUT := 0.6
const TRANSITION_IN := 0.8

const PORTAL_TINTS := {
	"hub": {"tint": Color("ffe9a8"), "deep": Color("ffb347"), "label": "Harbour"},
	"lagoon": {"tint": Color("ffd84d"), "deep": Color("ff8a1a"), "label": "Sunny Lagoon"},
	"swell": {"tint": Color("4ff0ff"), "deep": Color("1a6cff"), "label": "Rolling Swell"},
	"storm": {"tint": Color("c07cff"), "deep": Color("6a2bff"), "label": "Storm Run"},
	"giant": {"tint": Color("3d7bff"), "deep": Color("0b2a9c"), "label": "Titan Swell"},
	# near-black purple heart with an electric violet rim
	"tempest": {"tint": Color("b48cff"), "deep": Color("160722"), "label": "The Perfect Storm"},
	"deep": {"tint": Color("3fe6d2"), "deep": Color("0b4a7a"), "label": "The Deep Run"},
}

var ocean: Node
var portals: Array = []          # {def, dest, root, ring, icon, normal, right, side, cooldown, bob_y, phase}
var transitioning := false
var last_dest := ""
var _t := 0.0
var _geo: Dictionary = {}
var _icons: Dictionary = {}
var _overlay: CanvasLayer
var _overlay_rect: ColorRect
var _overlay_mat: ShaderMaterial
var _shaders := {
	"disc": preload("res://shaders/portal_disc.gdshader"),
	"pool": preload("res://shaders/portal_pool.gdshader"),
	"column": preload("res://shaders/portal_column.gdshader"),
	"sparkles": preload("res://shaders/portal_sparkles.gdshader"),
	"transition": preload("res://shaders/portal_transition.gdshader"),
}


func _shared_geometry() -> Dictionary:
	if not _geo.is_empty():
		return _geo
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - TUBE
	torus.outer_radius = RING_RADIUS + TUBE
	torus.rings = 72
	torus.ring_segments = 12
	var disc := QuadMesh.new()
	disc.size = Vector2(RING_RADIUS * 2.0, RING_RADIUS * 2.0)
	var pool := QuadMesh.new()
	pool.size = Vector2(POOL_R * 2.0, POOL_R * 2.0)
	var column := CylinderMesh.new()
	column.top_radius = 0.9
	column.bottom_radius = RING_RADIUS * 0.55
	column.height = COLUMN_H
	column.radial_segments = 20
	column.rings = 1
	column.cap_top = false
	column.cap_bottom = false
	_geo = {"torus": torus, "disc": disc, "pool": pool, "column": column, "sparkles": _sparkle_mesh()}
	return _geo


## Sparkles: SPARKLES camera-facing quads animated entirely in the vertex shader from a per-quad
## seed (CUSTOM0); UV holds the corner offset.
func _sparkle_mesh() -> ArrayMesh:
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var custom := PackedFloat32Array()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in SPARKLES:
		var seed := Vector3(rng.randf(), rng.randf(), rng.randf())
		var base := i * 4
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			pos.append(Vector3(0, RING_Y, 0))
			uv.append(c)
			custom.append_array([seed.x, seed.y, seed.z, 0.0])
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	m.custom_aabb = AABB(Vector3(-RING_RADIUS * 2, -2, -RING_RADIUS * 2), Vector3(RING_RADIUS * 4, RING_RADIUS * 3 + 8, RING_RADIUS * 4))
	return m


func _glow_material(kind: String, tint: Color, deep: Color, phase: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shaders[kind]
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("deep", deep)
	m.set_shader_parameter("phase", phase)
	return m


## @param defs [{x, z, heading, dest}]
func build(defs: Array) -> void:
	dispose(false)
	var geo := _shared_geometry()
	for i in defs.size():
		var def: Dictionary = defs[i]
		var style: Dictionary = PORTAL_TINTS.get(def.dest, PORTAL_TINTS.hub)
		var tint: Color = style.tint
		var deep: Color = style.deep
		var phase := i * 2.39996
		var root := Node3D.new()
		root.name = "portal-" + str(def.dest)
		var y: float = ocean.height_at(def.x, def.z) if (ocean and ocean.has_method("height_at")) else 0.0
		root.position = Vector3(def.x, y, def.z)
		root.rotation.y = def.heading

		# ring frame: lit prop with an emissive glow in the destination's colour
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color("fff6dc")
		ring_mat.emission_enabled = true
		ring_mat.emission = tint
		ring_mat.emission_energy_multiplier = 1.8
		ring_mat.roughness = 0.28
		ring_mat.metallic = 0.45
		var ring := MeshInstance3D.new()
		ring.mesh = geo.torus
		ring.material_override = ring_mat
		ring.position.y = RING_Y
		ring.rotation.x = PI / 2.0         # TorusMesh lies flat; stand it up in the ring plane
		root.add_child(ring)

		var disc := MeshInstance3D.new()
		disc.mesh = geo.disc
		disc.material_override = _glow_material("disc", tint, deep, phase)
		disc.position.y = RING_Y
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(disc)

		var column := MeshInstance3D.new()
		column.mesh = geo.column
		column.material_override = _glow_material("column", tint, deep, phase)
		column.position.y = COLUMN_H * 0.5 - 1.5
		column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(column)

		var pool := MeshInstance3D.new()
		pool.mesh = geo.pool
		pool.material_override = _glow_material("pool", tint, deep, phase)
		pool.rotation.x = -PI / 2.0
		pool.position.y = 0.45
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pool)

		var icon := _build_icon(def.dest, tint)
		icon.position.y = ICON_Y
		icon.scale = Vector3.ONE * 1.7
		root.add_child(icon)

		var sparkles := MeshInstance3D.new()
		sparkles.mesh = geo.sparkles
		var sm := _glow_material("sparkles", tint, deep, phase)
		sparkles.material_override = sm
		sparkles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(sparkles)

		add_child(root)
		portals.append({
			"def": def, "dest": def.dest, "root": root, "ring": ring, "icon": icon,
			"normal": Vector2(sin(def.heading), cos(def.heading)),
			"right": Vector2(cos(def.heading), -sin(def.heading)),
			"side": 0, "cooldown": 0.0, "bob_y": y, "phase": phase,
		})


func update(dt: float) -> void:
	_t += dt
	for p in portals:
		# bob gently on the sampled sea; heavily damped so a storm swell does not fling a 12 m ring around
		var h: float = (ocean.height_at(p.def.x, p.def.z) if (ocean and ocean.has_method("height_at")) else 0.0) * 0.7
		p.bob_y += (h - p.bob_y) * (1.0 - exp(-dt * 1.6))
		var root: Node3D = p.root
		root.position.y = p.bob_y
		var icon: Node3D = p.icon
		icon.rotation.y += dt * 0.7
		icon.position.y = ICON_Y + sin(_t * 1.1 + p.phase) * 0.35
		var ring: Node3D = p.ring
		ring.rotation.z = sin(_t * 0.5 + p.phase) * 0.02
		if p.cooldown > 0.0:
			p.cooldown -= dt


## Destination id when `body` crossed a ring's plane inside its radius this frame, else "".
## Fires once per crossing; re-entry within 3 s is ignored so the boat can be teleported and
## coast through the far side.
func test(body) -> String:
	if transitioning or body == null:
		return ""
	var pos: Vector3 = body.global_position if body is Node3D else body.position
	for p in portals:
		var dx: float = pos.x - p.def.x
		var dz: float = pos.z - p.def.z
		var n: Vector2 = p.normal
		var d := dx * n.x + dz * n.y           # signed distance to the ring plane
		var side := 1 if d > 0.0 else -1
		if p.side == 0:
			p.side = side
			continue
		if side == p.side:
			continue
		p.side = side
		if p.cooldown > 0.0:
			continue
		var r: Vector2 = p.right
		var lateral := absf(dx * r.x + dz * r.y)
		# horizontal-only: boats live at the waterline, so height cannot miss
		if lateral < RING_RADIUS - TUBE * 0.5 and absf(d) < 12.0 and absf(pos.y - p.bob_y) < RING_RADIUS:
			p.cooldown = REENTRY_COOLDOWN
			last_dest = p.dest
			return p.dest
	return ""


## Full-screen white-out: an iris of warm light blooms from the centre (0.6 s), `cb` swaps the
## world behind it (awaited, may be a coroutine), then it dissolves (0.8 s).
func transition(cb: Callable, dest := "") -> void:
	if dest == "":
		dest = last_dest
	var style: Dictionary = PORTAL_TINTS.get(dest, PORTAL_TINTS.hub)
	_ensure_overlay()
	transitioning = true
	_overlay_mat.set_shader_parameter("tint", style.tint)
	_overlay_mat.set_shader_parameter("opacity", 1.0)
	_overlay_mat.set_shader_parameter("radius", 0.0)
	_overlay_rect.visible = true
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _overlay_mat.set_shader_parameter("radius", v), 0.0, 1.0, TRANSITION_OUT) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tw.finished
	if cb.is_valid():
		await cb.call()
	var tw2 := create_tween()
	tw2.tween_method(func(v: float) -> void: _overlay_mat.set_shader_parameter("opacity", v), 1.0, 0.0, TRANSITION_IN) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await tw2.finished
	_overlay_rect.visible = false
	transitioning = false


func _ensure_overlay() -> void:
	if _overlay:
		return
	_overlay = CanvasLayer.new()
	_overlay.name = "PortalTransition"
	_overlay.layer = 100
	_overlay_rect = ColorRect.new()
	_overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = _shaders.transition
	_overlay_rect.material = _overlay_mat
	_overlay_rect.visible = false
	_overlay.add_child(_overlay_rect)
	add_child(_overlay)


## @param full also drop the shared geometry and the overlay
func dispose(full := true) -> void:
	for p in portals:
		p.root.queue_free()
	portals.clear()
	if not full:
		return
	_geo.clear()
	_icons.clear()
	if _overlay:
		_overlay.queue_free()
		_overlay = null


# ------------------------------------------------------------------- icons
## Icon = Node3D of one MeshInstance3D per part; each part is merged, vertex-coloured geometry
## with one material (albedo white, emissive in the portal tint or the part's own hot colour).
func _build_icon(dest: String, tint: Color) -> Node3D:
	if not _icons.has(dest):
		var parts: Array
		match dest:
			"swell": parts = _wave_icon()
			"storm": parts = _storm_icon()
			"giant": parts = _giant_wave_icon()
			"tempest": parts = _tempest_icon()
			"deep": parts = _submarine_icon()
			_: parts = _sun_icon()
		_icons[dest] = parts
	var icon := Node3D.new()
	icon.name = "icon"
	for part in _icons[dest]:
		var mi := MeshInstance3D.new()
		mi.mesh = part.mesh
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.4
		mat.metallic = 0.1
		mat.emission_enabled = true
		if part.has("emissive"):
			mat.emission = part.emissive
			mat.emission_energy_multiplier = 1.6
		else:
			mat.emission = tint
			mat.emission_energy_multiplier = 1.1
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		icon.add_child(mi)
	return icon


## Merges coloured primitive meshes into one ArrayMesh.
class Merge:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	func add(mesh: Mesh, color: Color, xform := Transform3D.IDENTITY) -> void:
		var c := color.srgb_to_linear()
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var ind: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var base := pos.size()
			var nb := xform.basis.inverse().transposed()
			for i in v.size():
				pos.append(xform * v[i])
				nrm.append((nb * n[i]).normalized() if n.size() > i else Vector3.UP)
				col.append(c)
			if ind.is_empty():
				for i in v.size():
					idx.append(base + i)
			else:
				for i in ind:
					idx.append(base + i)

	## Extrude a 2D polygon (xy, CCW) along z: front and back faces plus side quads.
	func extrude(points: PackedVector2Array, depth: float, color: Color, xform := Transform3D.IDENTITY) -> void:
		var c := color.srgb_to_linear()
		var tri := Geometry2D.triangulate_polygon(points)
		if tri.is_empty():
			points.reverse()
			tri = Geometry2D.triangulate_polygon(points)
		var n := points.size()
		var base := pos.size()
		var hz := depth * 0.5
		# front (+z) and back (-z) faces
		for k in 2:
			var z := hz if k == 0 else -hz
			var normal := Vector3(0, 0, 1) if k == 0 else Vector3(0, 0, -1)
			for p in points:
				pos.append(xform * Vector3(p.x, p.y, z))
				nrm.append((xform.basis * normal).normalized())
				col.append(c)
		for i in range(0, tri.size(), 3):
			# Godot's triangulation winds clockwise for a CCW polygon; flip to face +z
			idx.append_array([base + tri[i], base + tri[i + 2], base + tri[i + 1]])
			idx.append_array([base + n + tri[i], base + n + tri[i + 1], base + n + tri[i + 2]])
		# sides
		for i in n:
			var a := points[i]
			var b := points[(i + 1) % n]
			var e := b - a
			var sn := Vector3(e.y, -e.x, 0).normalized()
			var sb := pos.size()
			for p in [Vector3(a.x, a.y, hz), Vector3(b.x, b.y, hz), Vector3(b.x, b.y, -hz), Vector3(a.x, a.y, -hz)]:
				pos.append(xform * p)
				nrm.append((xform.basis * sn).normalized())
				col.append(c)
			idx.append_array([sb, sb + 1, sb + 2, sb, sb + 2, sb + 3])

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


static func _sphere(r: float, rings := 12, segs := 20) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.rings = rings
	s.radial_segments = segs
	return s


static func _box(sx: float, sy: float, sz: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return b


static func _cyl(r: float, h: float, segs := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	return c


static func _at(x: float, y: float, z: float, basis := Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis, Vector3(x, y, z))


static func _bolt_points(dx := 0.0, scale := 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in [[0.5, 0.3], [-0.7, -1.3], [0.15, -1.3], [-0.75, -3.1], [1.05, -1.05], [0.25, -1.05], [1.15, 0.3]]:
		pts.append(Vector2(p[0] * scale + dx, p[1] * scale))
	return pts


func _sun_icon() -> Array:
	var m := Merge.new()
	m.add(_sphere(1.15, 14, 20), Color("ffe14a"))
	for i in 8:
		var rot := Basis(Vector3(0, 0, 1), i * PI / 4.0)
		m.add(_box(0.34, 1.15, 0.34), Color("ff9a1a"), Transform3D(rot, rot * Vector3(0, 2.05, 0)))
	return [{"mesh": m.mesh()}]


func _wave_icon() -> Array:
	# a wavy ribbon: sine top edge, offset bottom edge, extruded for thickness
	var m := Merge.new()
	var steps := 28
	var span := 4.6
	var amp := 0.62
	var thick := 0.62
	var pts := PackedVector2Array()
	for i in steps + 1:
		var x := -span / 2.0 + span * i / steps
		pts.append(Vector2(x, sin(x * 2.2) * amp + thick * 0.5))
	for i in range(steps, -1, -1):
		var x := -span / 2.0 + span * i / steps
		pts.append(Vector2(x, sin(x * 2.2) * amp - thick + thick * 0.5))
	m.extrude(pts, 0.5, Color("53e6ff"))
	var cx := -span / 2.0 + 0.55
	m.add(_sphere(0.42, 8, 12), Color("ffffff"), _at(cx, sin(cx * 2.2) * amp + 0.35, 0))
	return [{"mesh": m.mesh()}]


func _storm_icon() -> Array:
	var cloud := Merge.new()
	for b in [[0.0, 0.0, 0.0, 1.0], [-1.1, -0.2, 0.1, 0.75], [1.05, -0.15, -0.1, 0.8], [0.25, 0.5, 0.25, 0.7]]:
		cloud.add(_sphere(b[3], 12, 16), Color("cbb6ff"), _at(b[0], b[1] + 1.4, b[2]))
	# a big fat bolt with its own hot yellow emissive so it stays legible on the purple cloud
	var bolt := Merge.new()
	bolt.extrude(_bolt_points(), 0.45, Color("fff36b"), _at(-0.2, 0.55, 0))
	return [{"mesh": cloud.mesh()}, {"mesh": bolt.mesh(), "emissive": Color("ffd040")}]


## Partial torus (the curl of a breaking wave): centre origin, axis z, arc from 0 to `arc`.
static func _torus_arc(m: Merge, R: float, r: float, radial: int, tubular: int, arc: float, color: Color, xform: Transform3D) -> void:
	var c := color.srgb_to_linear()
	var base := m.pos.size()
	for j in tubular + 1:
		var u := arc * j / tubular
		for i in radial + 1:
			var v := TAU * i / radial
			var centre := Vector3(R * cos(u), R * sin(u), 0)
			var p := Vector3((R + r * cos(v)) * cos(u), (R + r * cos(v)) * sin(u), r * sin(v))
			m.pos.append(xform * p)
			m.nrm.append((xform.basis * (p - centre).normalized()).normalized())
			m.col.append(c)
	for j in tubular:
		for i in radial:
			var a := base + (radial + 1) * j + i
			var b := base + (radial + 1) * (j + 1) + i
			m.idx.append_array([a, b + 1, b, a, a + 1, b + 1])


func _giant_wave_icon() -> Array:
	# a breaking roller: a thick curl rearing over a sloped face, with a fat white lip
	var m := Merge.new()
	var curl_x := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.55), Vector3(0.35, 1.05, 0))
	_torus_arc(m, 1.55, 0.55, 12, 28, PI * 1.25, Color("2f6bff"), curl_x)
	var face := PackedVector2Array([Vector2(-2.7, -1.35), Vector2(1.9, -1.35), Vector2(1.9, -0.5), Vector2(0.4, 0.95), Vector2(-0.9, 0.35), Vector2(-2.7, -0.55)])
	m.extrude(face, 0.6, Color("1e4fd6"))
	var foam := Merge.new()
	for l in [[-0.95, 2.05, 0.42], [-0.3, 2.45, 0.5], [0.45, 2.6, 0.5], [1.15, 2.4, 0.42], [1.7, 1.95, 0.36]]:
		foam.add(_sphere(l[2], 8, 12), Color("ffffff"), _at(l[0], l[1], 0))
	return [{"mesh": m.mesh()}, {"mesh": foam.mesh(), "emissive": Color("dfe8ff")}]


func _tempest_icon() -> Array:
	# black thunderhead with two bolts: a darker, angrier cousin of the storm icon
	var cloud := Merge.new()
	for b in [[0.0, 0.0, 0.0, 1.1], [-1.25, -0.2, 0.1, 0.8], [1.2, -0.15, -0.1, 0.85], [0.3, 0.6, 0.25, 0.75], [-0.5, 0.45, -0.2, 0.6]]:
		cloud.add(_sphere(b[3], 12, 16), Color("3a2a5c"), _at(b[0], b[1] + 1.5, b[2]))
	var bolts := Merge.new()
	bolts.extrude(_bolt_points(-0.95, 0.95), 0.45, Color("fff36b"), _at(0, 0.6, 0))
	bolts.extrude(_bolt_points(0.75, 0.75), 0.45, Color("e6dcff"), _at(0, 0.6, 0))
	return [{"mesh": cloud.mesh()}, {"mesh": bolts.mesh(), "emissive": Color("ffe066")}]


func _submarine_icon() -> Array:
	# a chubby sub: capsule hull, conning tower, periscope, tail fins and a trail of bubbles
	var m := Merge.new()
	var hull := CapsuleMesh.new()
	hull.radius = 0.75
	hull.height = 2.6 + 1.5
	m.add(hull, Color("ffb43c"), Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3.ZERO))
	m.add(_box(1.0, 0.75, 0.7), Color("ff9a1a"), _at(0.15, 0.95, 0))
	m.add(_cyl(0.09, 0.8), Color("404a5c"), _at(0.35, 1.7, 0))
	m.add(_box(0.42, 0.16, 0.16), Color("404a5c"), _at(0.5, 2.05, 0))
	m.add(_box(0.5, 1.3, 0.14), Color("ff9a1a"), _at(-1.85, 0.1, 0))
	m.add(_box(0.5, 0.14, 1.3), Color("ff9a1a"), _at(-1.85, 0, 0))
	m.add(_cyl(0.22, 0.2, 12), Color("8ff3ff"), Transform3D(Basis(Vector3(1, 0, 0), PI / 2.0), Vector3(0.9, 0.05, 0.72)))
	var bubbles := Merge.new()
	for b in [[2.2, 0.9, 0.22], [2.55, 1.5, 0.16], [2.75, 2.05, 0.12]]:
		bubbles.add(_sphere(b[2], 8, 10), Color("ffffff"), _at(b[0], b[1], 0))
	return [{"mesh": m.mesh()}, {"mesh": bubbles.mesh(), "emissive": Color("9ffcff")}]
