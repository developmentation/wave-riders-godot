class_name Boats
## Boat catalog and visuals — port of src/game/Boats.js.
##
## Every visual is a Node3D whose local +Z is the hull's forward axis (what
## BoatPhysics integrates), origin at the body's centre of mass, keel at the
## depth that puts the hull's waterline on the still-water surface once the
## buoyancy springs have settled. Speedboat, sailboat, fishing boat, tug,
## airboat, tow boat and rowboat are the CC0 Kenney GLBs (imported by Godot
## without rotation: glTF +Z forward stays +Z, so `yaw` is 0); jet ski and
## pontoon are built here from primitives in the same chunky flat-colour toy
## style. The returned node has `update(dt, body)` for propeller/fan spin, sail
## trim, flag flutter, rowing oars, funnel smoke and the kid at the helm.

const MODEL_BASE := "res://assets/models/kenney-watercraft/"

## Kenney colormap palette, matched by eye to Textures/colormap.png.
const PALETTE := {
	"white": Color("f4f4f8"), "cream": Color("ffe6c4"), "sand": Color("e6c79c"),
	"red": Color("d84c48"), "orange": Color("ff7a3d"), "yellow": Color("ffc236"), "green": Color("49c687"),
	"blue": Color("5a8fdd"), "navy": Color("4f52c6"), "sky": Color("a9d9fb"), "purple": Color("9d6cf0"),
	"dark": Color("33343b"), "slate": Color("585d70"), "steel": Color("b7bccb"), "glass": Color("c6ecff"),
	"skin": Color("f3b98e"), "tan": Color("d39a6e"), "brown": Color("a35c3a"),
	"smoke": Color("dde2e8"),
}

## Same schema as the web BOAT_CATALOG (colors are palette keys here).
## Kenney units: roof = wheelhouse top [y, zAft, zFwd]; helm_z = where the kid stands.
const CATALOG := {
	"jetski": {
		"id": "jetski", "label": "Jet Ski", "hull": "jetski", "kind": "procedural", "file": "",
		"model_length": 3.3, "yaw": 0.0, "lift": 0.0, "waterline": 0.24,
		"colors": ["yellow", "orange", "green", "purple"],
		"description": "Zippy and bouncy — jump the waves!", "icon": "🏄",
		"stats": {"speed": 0.8, "turning": 1.0, "steady": 0.3},
	},
	"speedboat": {
		"id": "speedboat", "label": "Speedboat", "hull": "speedboat", "kind": "glb",
		"file": "boat-speed-a.glb", "model_length": 3.37, "yaw": 0.0, "lift": 0.0, "waterline": 0.36,
		# Colour variants are different Kenney hulls (index → variants[i]).
		"variants": [
			{"file": "boat-speed-a.glb", "length": 3.37},
			{"file": "boat-speed-b.glb", "length": 3.29},
			{"file": "boat-speed-c.glb", "length": 3.17},
			{"file": "boat-speed-g.glb", "length": 3.81},
			{"file": "boat-speed-i.glb", "length": 3.87},
			{"file": "boat-speed-j.glb", "length": 4.27},
		],
		"colors": ["red", "blue", "green", "yellow", "orange", "purple"],
		"description": "The fastest boat on the water!", "icon": "🚤",
		"stats": {"speed": 1.0, "turning": 0.6, "steady": 0.55},
	},
	"sailboat": {
		"id": "sailboat", "label": "Sailboat", "hull": "sailboat", "kind": "glb",
		"file": "boat-sail-a.glb", "model_length": 3.77, "yaw": 0.0, "lift": 0.0, "waterline": 0.55,
		"variants": [
			{"file": "boat-sail-a.glb", "length": 3.77},
			{"file": "boat-sail-b.glb", "length": 4.07},
		],
		"colors": ["white", "red"],
		"description": "Catch the wind and glide!", "icon": "⛵",
		"stats": {"speed": 0.45, "turning": 0.4, "steady": 0.7},
	},
	"pontoon": {
		"id": "pontoon", "label": "Pontoon", "hull": "pontoon", "kind": "procedural", "file": "",
		"model_length": 7.0, "yaw": 0.0, "lift": 0.0, "waterline": 0.3,
		"colors": ["blue", "red", "green", "purple"],
		"description": "Slow and steady party boat — toot the horn!", "icon": "🛥️",
		"stats": {"speed": 0.35, "turning": 0.35, "steady": 1.0},
	},
	# For the single-model Kenney boats the colour picks the trim: the kid's
	# helmet, pennant, crates, oar blades — the hull texture is fixed.
	"fishing": {
		"id": "fishing", "label": "Fishing Boat", "hull": "fishing", "kind": "glb",
		"file": "boat-fishing-small.glb", "model_length": 3.87, "yaw": 0.0, "lift": 0.0, "waterline": 0.42,
		"variants": [{"file": "boat-fishing-small.glb", "length": 3.87}],
		"colors": ["blue", "red", "green", "yellow"],
		"description": "Steady as a rock — toot the foghorn!", "icon": "🎣",
		"stats": {"speed": 0.4, "turning": 0.45, "steady": 0.9},
	},
	"tug": {
		"id": "tug", "label": "Tugboat", "hull": "tug", "kind": "glb",
		"file": "boat-tug-a.glb", "model_length": 3.47, "yaw": 0.0, "lift": 0.0, "waterline": 0.45,
		"variants": [
			{"file": "boat-tug-a.glb", "length": 3.47, "roof": [1.7, -1.63, 1.05], "helm_z": 0.62, "funnels": [[-0.87, 2.24], [0.12, 2.1]]},
			{"file": "boat-tug-b.glb", "length": 2.87, "roof": [1.7, -1.34, 0.75], "helm_z": 0.42, "funnels": [[-0.57, 2.24]]},
			{"file": "boat-tug-c.glb", "length": 2.87, "roof": [1.7, -1.34, 0.55], "helm_z": -0.12, "funnels": null},
		],
		"colors": ["red", "green", "yellow"],
		"description": "Big and strong — bumps through anything!", "icon": "🚢",
		"stats": {"speed": 0.3, "turning": 0.4, "steady": 1.0},
	},
	"airboat": {
		"id": "airboat", "label": "Airboat", "hull": "airboat", "kind": "glb",
		"file": "boat-fan.glb", "model_length": 2.87, "yaw": 0.0, "lift": 0.0, "waterline": 0.22,
		"variants": [{"file": "boat-fan.glb", "length": 2.87}],
		"colors": ["green", "orange", "purple", "sky"],
		"description": "Whoosh! Super fast and super slidey!", "icon": "🌀",
		"stats": {"speed": 0.85, "turning": 0.75, "steady": 0.35},
	},
	"towboat": {
		"id": "towboat", "label": "Tow Boat", "hull": "towboat", "kind": "glb",
		"file": "boat-tow-a.glb", "model_length": 6.12, "yaw": 0.0, "lift": 0.0, "waterline": 0.45,
		# roof = flat top the kid drives from [y, zAft, zFwd]; stacks = [[x, z, topY], ...].
		"variants": [
			{"file": "boat-tow-a.glb", "length": 6.12, "roof": [3.33, -1.5, 1.2], "roof_half_width": 0.45, "helm_z": 0.3, "stacks": [[-0.57, -1.65, 3.33], [0.57, -1.65, 3.33]]},
			{"file": "boat-tow-b.glb", "length": 6.12, "roof": [2.61, -1.6, 0.2], "roof_half_width": 0.66, "helm_z": -0.35, "stacks": [[-0.57, -1.65, 2.78], [0.57, -1.65, 2.78]]},
		],
		"colors": ["purple", "orange"],
		"description": "Twin smokestacks and a huge engine!", "icon": "⛴️",
		"stats": {"speed": 0.95, "turning": 0.55, "steady": 0.6},
	},
	"rowboat": {
		"id": "rowboat", "label": "Rowboat", "hull": "rowboat", "kind": "glb",
		"file": "boat-row-small.glb", "model_length": 2.37, "yaw": 0.0, "lift": 0.0, "waterline": 0.25,
		"variants": [{"file": "boat-row-small.glb", "length": 2.37}],
		"colors": ["red", "yellow", "green", "purple"],
		"description": "Row, row, row your boat — silly slow!", "icon": "🚣",
		"stats": {"speed": 0.15, "turning": 0.9, "steady": 0.5},
	},
	# Placeholder so build_visual("sub") never fails; boats/Submarine.tscn owns the real one.
	"sub": {
		"id": "sub", "label": "Submarine", "hull": "speedboat", "kind": "procedural", "file": "",
		"model_length": 6.0, "yaw": 0.0, "lift": 0.0, "waterline": 0.0,
		"colors": ["yellow", "red", "green", "blue"],
		"description": "Dive deep and swim through the hoops!", "icon": "🤿",
		"stats": {"speed": 0.4, "turning": 0.6, "steady": 0.8},
	},
}

const FLAG_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
instance uniform float wave = 0.8;
void vertex() {
	// UV.y is 0 on the pole edge and 1 at the free end: that is the flutter weight.
	float w = UV.y;
	float t = TIME * (5.0 + wave * 4.0);
	VERTEX.x += sin(t - w * 5.0) * w * w * 0.16 * wave;
	VERTEX.y += cos(t * 1.3 - w * 4.0) * w * 0.05 * wave;
}
void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
}
"""

static var _mats: Dictionary = {}
static var _flag_shader: Shader = null
static var _glb_cache: Dictionary = {}


# ------------------------------------------------------------------ helpers
static func color_of(c: Variant) -> Color:
	return PALETTE[c] if c is String else c


## Shared StandardMaterial3D per colour/roughness/metal so the whole fleet uses a handful.
static func material(color: Variant, roughness := 0.5, metal := 0.0) -> StandardMaterial3D:
	var col := color_of(color)
	var key := "%s|%.2f|%.2f" % [col.to_html(false), roughness, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = roughness
	m.metallic = metal
	_mats[key] = m
	return m


## Body-origin height above still water once the springs carry the weight (see Hulls).
static func rest_height(hull: Dictionary) -> float:
	return Hulls.rest_height(hull)


## Vertical position of the keel (model y = 0) in body space.
static func keel_y(spec: Dictionary) -> float:
	var hull: Dictionary = Hulls.HULLS[spec.hull]
	return -(rest_height(hull) + float(spec.waterline)) + float(spec.lift)


static func box(w: float, h: float, d: float) -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(w, h, d)
	return m


## Rounded box in the web build; BoxMesh reads the same at toy scale.
static func rbox(w: float, h: float, d: float, _r: float) -> Mesh:
	return box(w, h, d)


static func cyl(r_top: float, r_bot: float, h: float, seg := 12) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func sphere(r: float, w := 10, h := 7) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = w
	m.rings = h
	return m


## Upper half of a sphere (helmet shell, hair cap).
static func dome(r: float, w := 10, h := 5) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r
	m.is_hemisphere = true
	m.radial_segments = w
	m.rings = h
	return m


## Torus in the XY plane (three.js convention): ring radius r, tube radius t.
static func torus(r: float, t: float, rings := 6, ring_segments := 14) -> Mesh:
	var m := TorusMesh.new()
	m.inner_radius = r - t
	m.outer_radius = r + t
	m.rings = ring_segments
	m.ring_segments = rings
	return m


const TORUS_XY := Transform3D(Basis(Vector3(1, 0, 0), PI / 2.0), Vector3.ZERO)
## Cylinder lying along +z (bow-ward), centred.
const TUBE_ROT := Transform3D(Basis(Vector3(1, 0, 0), PI / 2.0), Vector3.ZERO)
## Cylinder lying along x (athwartships).
const BAR_ROT := Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3.ZERO)


static func at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


static func atv(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, p)


## three.js mat4(x, y, z, rx, ry, rz, s): Euler XYZ (Rx·Ry·Rz), uniform scale, then translate.
static func mat4(x: float, y: float, z: float, rx := 0.0, ry := 0.0, rz := 0.0, s := 1.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(rx, ry, rz), EULER_ORDER_XYZ).scaled(Vector3.ONE * s), Vector3(x, y, z))


static func rot_x(a: float) -> Transform3D:
	return Transform3D(Basis(Vector3(1, 0, 0), a), Vector3.ZERO)


static func rot_y(a: float) -> Transform3D:
	return Transform3D(Basis(Vector3(0, 1, 0), a), Vector3.ZERO)


static func rot_z(a: float) -> Transform3D:
	return Transform3D(Basis(Vector3(0, 0, 1), a), Vector3.ZERO)


## Plan-view hull outline extruded upward. `profile` is [[z, halfWidth], ...]
## from stern to bow. With a bevel the body swells by `bevel` in the middle and
## the total height stays `height`, base at y0.
static func hull_slab(profile: Array, y0: float, height: float, bevel := 0.0, scale_w := 1.0) -> Mesh:
	var n := profile.size()
	# closed outline: starboard side stern→bow, then port side bow→stern
	var outline: PackedVector2Array = []      # (x, z)
	var outer: PackedVector2Array = []        # bevel-expanded
	for i in n:
		var z: float = profile[i][0]
		var w: float = maxf(0.01, float(profile[i][1]) * scale_w - bevel)
		var dz := (-bevel if i == 0 else (bevel if i == n - 1 else 0.0))
		outline.append(Vector2(w, z))
		outer.append(Vector2(w + bevel, z + dz))
	for i in range(n - 1, -1, -1):
		var z: float = profile[i][0]
		var w: float = maxf(0.01, float(profile[i][1]) * scale_w - bevel)
		var dz := (-bevel if i == 0 else (bevel if i == n - 1 else 0.0))
		outline.append(Vector2(-w, z))
		outer.append(Vector2(-(w + bevel), z + dz))
	var rings: Array = []
	if bevel > 0.0:
		rings = [[outline, y0], [outer, y0 + bevel], [outer, y0 + height - bevel], [outline, y0 + height]]
	else:
		rings = [[outline, y0], [outline, y0 + height]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m := outline.size()
	# sides
	for r in rings.size() - 1:
		var a: PackedVector2Array = rings[r][0]
		var ya: float = rings[r][1]
		var b: PackedVector2Array = rings[r + 1][0]
		var yb: float = rings[r + 1][1]
		for i in m:
			var j := (i + 1) % m
			var p0 := Vector3(a[i].x, ya, a[i].y)
			var p1 := Vector3(a[j].x, ya, a[j].y)
			var p2 := Vector3(b[j].x, yb, b[j].y)
			var p3 := Vector3(b[i].x, yb, b[i].y)
			_quad(st, p0, p3, p2, p1)
	# caps
	var idx := Geometry2D.triangulate_polygon(outline)
	var top_y := y0 + height
	for t in range(0, idx.size(), 3):
		var a := outline[idx[t]]
		var b := outline[idx[t + 1]]
		var c := outline[idx[t + 2]]
		# top (normal +y) and bottom (normal -y)
		_tri(st, Vector3(a.x, top_y, a.y), Vector3(c.x, top_y, c.y), Vector3(b.x, top_y, b.y), Vector3.UP)
		_tri(st, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(c.x, y0, c.y), Vector3.DOWN)
	st.index()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n := Vector3.ZERO) -> void:
	var g := (b - a).cross(c - a)
	var nn := n if n != Vector3.ZERO else g.normalized()
	# Make (a, b, c) counter-clockwise about the outward normal, then emit it
	# clockwise: Godot front faces wind clockwise when seen from outside.
	if g.dot(nn) < 0.0:
		var t := b
		b = c
		c = t
	for p in [a, c, b]:
		st.set_normal(nn)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(d - a).normalized()
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


## A fluttering pennant hanging off a pole tip at (0,0,0), trailing aft (-z).
static func flag_mesh(len := 0.55, h := 0.3, segs := 6) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var z0 := -len * float(i) / segs
		var z1 := -len * float(i + 1) / segs
		var v0 := float(i) / segs
		var v1 := float(i + 1) / segs
		var quad := [Vector3(0, 0, z0), Vector3(0, -h, z0), Vector3(0, -h, z1), Vector3(0, 0, z1)]
		var uvs := [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]
		var order := [0, 1, 2, 0, 2, 3]
		for k in order:
			st.set_normal(Vector3(1, 0, 0))
			st.set_uv(uvs[k])
			st.add_vertex(quad[k])
	return st.commit()


static func flag(color: Variant, len := 0.55, h := 0.3) -> MeshInstance3D:
	if _flag_shader == null:
		_flag_shader = Shader.new()
		_flag_shader.code = FLAG_SHADER
	var key := "flag|" + color_of(color).to_html(false)
	var mat: ShaderMaterial
	if _mats.has(key):
		mat = _mats[key]
	else:
		mat = ShaderMaterial.new()
		mat.shader = _flag_shader
		mat.set_shader_parameter("albedo", color_of(color))
		_mats[key] = mat
	var mi := MeshInstance3D.new()
	mi.mesh = flag_mesh(len, h)
	mi.material_override = mat
	mi.set_instance_shader_parameter("wave", 0.8)
	return mi


static func load_kenney(file: String) -> Node3D:
	if not _glb_cache.has(file):
		_glb_cache[file] = load(MODEL_BASE + file)
	var ps: PackedScene = _glb_cache[file]
	return ps.instantiate() as Node3D


static func find_named(root: Node, target: String) -> Node3D:
	if root.name == target:
		return root as Node3D
	for c in root.get_children():
		var f := find_named(c, target)
		if f != null:
			return f
	return null


static func set_model_roughness(root: Node, roughness: float) -> void:
	for c in root.get_children():
		set_model_roughness(c, roughness)
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m is BaseMaterial3D:
				m.roughness = roughness


# ------------------------------------------------------------------ Builder
## Collects geometry per material and merges it into one mesh per material so
## a procedural boat costs a handful of draw calls. Animated parts ask for their
## own MeshInstance3D with `mesh()`.
class Builder extends RefCounted:
	var bins: Dictionary = {}    # material -> SurfaceTool
	var order: Array = []
	var tris := 0

	func add(mesh: Mesh, color: Variant, xf := Transform3D.IDENTITY, roughness := 0.5, metal := 0.0) -> void:
		var m := Boats.material(color, roughness, metal)
		if not bins.has(m):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			bins[m] = st
			order.append(m)
		var st: SurfaceTool = bins[m]
		for s in mesh.get_surface_count():
			st.append_from(mesh, s, xf)
			tris += mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size() / 3

	## Standalone mesh for parts that move on their own.
	func mesh(mesh: Mesh, color: Variant, roughness := 0.5, metal := 0.0, xf := Transform3D.IDENTITY) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = Boats.material(color, roughness, metal)
		mi.transform = xf
		return mi

	## Merge several meshes (with transforms) into one ArrayMesh sharing a material.
	func merged(parts: Array, color: Variant, roughness := 0.5, metal := 0.0) -> MeshInstance3D:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in parts:
			var mesh: Mesh = p[0]
			var xf: Transform3D = p[1] if p.size() > 1 else Transform3D.IDENTITY
			for s in mesh.get_surface_count():
				st.append_from(mesh, s, xf)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = Boats.material(color, roughness, metal)
		return mi

	## Merge queued geometry into `parent`, one surface per material.
	func flush(parent: Node3D, node_name := "Static") -> MeshInstance3D:
		if order.is_empty():
			return null
		var am := ArrayMesh.new()
		for m in order:
			var st: SurfaceTool = bins[m]
			st.commit(am)
			am.surface_set_material(am.get_surface_count() - 1, m)
		var mi := MeshInstance3D.new()
		mi.name = node_name
		mi.mesh = am
		parent.add_child(mi)
		bins.clear()
		order.clear()
		return mi


# ------------------------------------------------------------------- driver
## Procedural kid at the helm: big round head, helmet or hair, life vest,
## arms reaching the given hand targets (figure-local, metres before scale).
## `update(dt, steer, speed_k, accel_k)` leans the torso into turns and pulls
## it back under acceleration.
class Driver extends Node3D:
	var torso: Node3D
	var head: Node3D
	var base_pitch := 0.0
	var lean := 0.0
	var pitch_s := 0.0

	func update(dt: float, steer: float, speed_k: float, accel_k: float) -> void:
		var k := 1.0 - exp(-dt * 5.0)
		lean += ((-steer * 0.3) * (0.4 + 0.6 * speed_k) - lean) * k
		pitch_s += ((base_pitch - accel_k * 0.14 + speed_k * 0.06) - pitch_s) * k
		torso.rotation = Vector3(pitch_s, 0.0, lean)
		head.rotation = Vector3(0.0, -lean * 0.8, lean * 0.7)   # glances into the turn


static func build_driver(_shared: Builder, o: Dictionary = {}) -> Driver:
	var scale: float = o.get("scale", 1.0)
	var vest: Variant = o.get("vest", "orange")
	var shirt: Variant = o.get("shirt", "white")
	var helmet: Variant = o.get("helmet", "red")
	var hair: bool = o.get("hair", false)
	var skin: Variant = o.get("skin", "skin")
	var shorts: Variant = o.get("shorts", "navy")
	var hands: Array = o.get("hands", [[-0.26, 0.3, 0.45], [0.26, 0.3, 0.45]])
	var legs: String = o.get("legs", "seated")
	# Own builder: the caller's queued rig geometry must not be flushed into the torso.
	var B := Builder.new()
	var root := Driver.new()
	root.scale = Vector3.ONE * scale
	root.base_pitch = o.get("pitch", 0.0)
	var torso := Node3D.new()
	root.add_child(torso)
	var head := Node3D.new()
	head.position = Vector3(0, 0.52, 0)
	torso.add_child(head)
	root.torso = torso
	root.head = head

	# body: shirt under a chunky life vest with a white zip panel
	B.add(box(0.32, 0.42, 0.22), shirt, at(0, 0.22, 0), 0.6)
	B.add(rbox(0.38, 0.34, 0.3, 0.08), vest, at(0, 0.24, 0), 0.6)
	B.add(box(0.08, 0.26, 0.04), "white", at(0, 0.24, 0.15), 0.6)
	B.add(cyl(0.06, 0.06, 0.1, 6), skin, at(0, 0.46, 0), 0.7)   # neck
	# arms: from shoulders to the hand targets
	var shoulders := [Vector3(-0.2, 0.38, 0.02), Vector3(0.2, 0.38, 0.02)]
	for i in 2:
		var sh: Vector3 = shoulders[i]
		var hd := Vector3(hands[i][0], hands[i][1], hands[i][2])
		var dir := hd - sh
		var len := dir.length()
		var q := Quaternion(Vector3.UP, dir.normalized())
		B.add(cyl(0.05, 0.042, len, 6), shirt, Transform3D(Basis(q), sh) * at(0, len / 2.0, 0), 0.6)
		B.add(sphere(0.06, 5, 4), skin, atv(hd), 0.7)
	B.flush(torso, "Torso")

	# big round kid head
	B.add(sphere(0.19, 10, 7), skin, Transform3D.IDENTITY, 0.7)
	if hair:
		B.add(dome(0.2, 10, 4), helmet, at(0, 0.02, -0.02), 0.8)
	else:
		B.add(dome(0.215, 10, 5), helmet, at(0, 0.02, 0), 0.35)
		B.add(box(0.3, 0.035, 0.14), "dark", at(0, -0.005, 0.2), 0.4)   # visor peak
	# eyes: two dots read as a face from a long way off
	B.add(sphere(0.028, 5, 3), "dark", at(-0.07, 0.0, 0.175), 0.3)
	B.add(sphere(0.028, 5, 3), "dark", at(0.07, 0.0, 0.175), 0.3)
	B.flush(head, "Head")

	# legs
	if legs == "seated":
		B.add(box(0.15, 0.13, 0.4), shorts, at(-0.1, -0.05, 0.2), 0.7)
		B.add(box(0.15, 0.13, 0.4), shorts, at(0.1, -0.05, 0.2), 0.7)
		B.add(box(0.13, 0.36, 0.13), skin, at(-0.1, -0.28, 0.4), 0.7)
		B.add(box(0.13, 0.36, 0.13), skin, at(0.1, -0.28, 0.4), 0.7)
		B.add(box(0.14, 0.09, 0.22), "white", at(-0.1, -0.48, 0.45), 0.6)
		B.add(box(0.14, 0.09, 0.22), "white", at(0.1, -0.48, 0.45), 0.6)
	elif legs == "standing":
		B.add(box(0.15, 0.62, 0.15), shorts, at(-0.1, -0.31, 0), 0.7)
		B.add(box(0.15, 0.62, 0.15), shorts, at(0.1, -0.31, 0), 0.7)
		B.add(box(0.14, 0.09, 0.24), "white", at(-0.1, -0.64, 0.04), 0.6)
		B.add(box(0.14, 0.09, 0.24), "white", at(0.1, -0.64, 0.04), 0.6)
	B.flush(root, "Legs")
	return root


# ------------------------------------------------------------------- visual
## Node returned by build_visual: holds the animated parts and the per-boat update.
class BoatVisual extends Node3D:
	var id := ""
	var spec: Dictionary
	var color_index := 0
	var triangles := 0
	var parts: Dictionary = {}     # name -> Node3D
	var drivers: Array = []        # [Driver, steer factor, accel?]
	var pennants: Array = []       # MeshInstance3D with the flag material
	var puffs: Array = []          # smoke: {mm, i, top: Vector3, p, dx, dz}
	var smoke_mm: MultiMesh = null
	var rods: Array = []           # fishing: {rod, line, side, base}
	var oars: Array = []           # rowboat: {pivot, side}
	var st := {"steer": 0.0, "spin": 0.0, "rate": 0.0, "sheet": 0.0, "heel": 0.0, "t": 0.0, "pitch": 0.0, "sway": 0.0, "phase": PI * 1.5}

	func update(dt: float, body: Node) -> void:
		var hull: Dictionary = body.hull
		var speed_k := minf(1.0, float(body.speed) / float(hull.max_speed))
		var thr: float = body.throttle
		var steer: float = body.steer
		var accel := maxf(0.0, thr) * (1.0 - speed_k)
		var wind: Dictionary = body.wind if "wind" in body else {}
		var ws: float = wind.get("speed", 5.0)
		match id:
			"jetski":
				st.steer += (steer - st.steer) * (1.0 - exp(-dt * 8.0))
				parts.nozzle.rotation.y = -st.steer * 0.45
				parts.bars.rotation.y = -st.steer * 0.3
			"pontoon":
				st.steer += (steer - st.steer) * (1.0 - exp(-dt * 6.0))
				parts.motor.rotation.y = -st.steer * 0.5
				parts.wheel.rotation.z = -st.steer * 1.6
				st.spin += dt * (0.6 + absf(thr) * 34.0)
				parts.prop.rotation.z = st.spin
			"speedboat":
				st.steer += (steer - st.steer) * (1.0 - exp(-dt * 6.0))
				parts.wheel.rotation.z = -st.steer * 1.8
			"sailboat":
				var k := 1.0 - exp(-dt * 2.5)
				# apparent wind in the boat frame (wind blows toward (cos a, sin a))
				var wa: float = wind.get("angle", 0.0)
				var vel: Vector3 = body.velocity
				var awx := cos(wa) * ws - vel.x
				var awz := sin(wa) * ws - vel.z
				var h: float = body.heading
				var ch := cos(h)
				var sh := sin(h)
				var lx := awx * ch - awz * sh
				var lz := awx * sh + awz * ch
				var rel := atan2(lx, lz)                 # 0 = wind from astern (running)
				var strength := minf(1.0, Vector2(lx, lz).length() / 10.0)
				var mag := 0.12 + 1.15 * (1.0 + cos(rel)) * 0.5
				var side := (-1.0 if st.sheet < 0.0 else 1.0) if absf(sin(rel)) < 0.05 else signf(sin(rel))
				st.sheet += (-side * mag - st.sheet) * k
				if parts.has("sail"):
					parts.sail.rotation.y = st.sheet
				# heel to leeward, more when the wind is on the beam
				var heel_target := -sin(rel) * strength * 0.22 * (0.4 + 0.6 * speed_k)
				st.heel += (heel_target - st.heel) * k
				parts.heel.rotation.z = st.heel
				st.steer += (steer - st.steer) * (1.0 - exp(-dt * 6.0))
				parts.tiller.rotation.y = st.steer * 0.5
				accel = 0.0
			"fishing":
				var k := 1.0 - exp(-dt * 6.0)
				st.steer += (steer - st.steer) * k
				parts.wheel.rotation.z = -st.steer * 1.8
				st.t += dt
				# Rods bob with a slow sway plus a kick from wave slaps; the floats swing back with speed.
				var slap: float = body.slap_impulse
				st.pitch += (sin(st.t * 2.1) * 0.05 + slap * 0.25 - st.pitch) * (1.0 - exp(-dt * 4.0))
				st.sway += (speed_k * 0.9 - st.sway) * k
				for r in rods:
					var rx: float = r.base + st.pitch + sin(st.t * 3.3 + r.side) * 0.02
					var rod: Node3D = r.rod
					rod.rotation = Vector3(rx, 0.0, -r.side * 0.2)
					var line: Node3D = r.line
					# The line hangs straight down in world terms: undo the rod tilt, then trail aft with speed.
					line.rotation = Vector3(-rx + st.sway + sin(st.t * 4.0 + r.side * 2.0) * 0.05, 0.0, r.side * 0.2)
			"tug":
				st.steer += (steer - st.steer) * (1.0 - exp(-dt * 5.0))
				parts.wheel.rotation.z = -st.steer * 1.8
				_smoke(dt, body, speed_k)
			"airboat":
				st.steer += (steer - st.steer) * (1.0 - exp(-dt * 7.0))
				parts.stick.rotation.x = -st.steer * 0.35
				# The fan spins up and down with a little inertia.
				st.rate += ((1.5 + absf(thr) * 42.0) - st.rate) * (1.0 - exp(-dt * 2.5))
				st.spin = fmod(st.spin + dt * st.rate, TAU)
				if parts.has("fan"):
					parts.fan.rotation.z = st.spin
			"towboat":
				st.steer += (steer - st.steer) * (1.0 - exp(-dt * 6.0))
				parts.wheel.rotation.z = -st.steer * 1.8
				_smoke(dt, body, speed_k)
			"rowboat":
				# Stroke rate follows the throttle; reverse rows backwards; idle oars coast to the recovery position.
				var target := (2.6 + 2.2 * thr) if thr > 0.05 else (-2.4 if thr < -0.05 else 0.0)
				st.rate += (target - st.rate) * (1.0 - exp(-dt * 3.0))
				st.phase += dt * st.rate
				if absf(st.rate) < 0.3:
					var rest := PI * 1.5
					var d := atan2(sin(rest - st.phase), cos(rest - st.phase))
					st.phase += d * (1.0 - exp(-dt * 2.0))
				var sweep := -0.5 * cos(st.phase)             # -: blades forward, +: blades aft
				var dip := -0.26 - 0.16 * sin(st.phase)       # deeper while driving, lifted on recovery
				st.steer += (steer - st.steer) * (1.0 - exp(-dt * 5.0))
				for o in oars:
					var bias: float = 1.0 - st.steer * o.side * 0.5
					var pivot: Node3D = o.pivot
					pivot.rotation = Vector3(0.0, o.side * sweep * bias, -o.side * dip)
				accel = -sin(st.phase) * 0.6 * minf(1.0, absf(st.rate) / 2.5)
			"sub":
				st.spin += dt * (0.6 + absf(thr) * 30.0)
				parts.prop.rotation.z = st.spin
		for p in pennants:
			p.set_instance_shader_parameter("wave", 0.5 + minf(1.5, (ws + float(body.speed)) * 0.08))
		for d in drivers:
			var drv: Driver = d[0]
			drv.update(dt, steer * d[1], speed_k, accel if d[2] else 0.0)

	## Chunky opaque smoke puffs cycling up out of each stack top, quicker and
	## fatter under throttle, trailing aft with speed (one MultiMesh draw call).
	func _smoke(dt: float, body: Node, speed_k: float) -> void:
		if smoke_mm == null:
			return
		var thr := absf(float(body.throttle))
		var rate := 0.35 + thr * 0.75
		for pf in puffs:
			pf.p += dt * rate
			if pf.p >= 1.0:
				pf.p -= 1.0
				pf.dx = randf_range(-0.125, 0.125)
				pf.dz = randf_range(-0.1, 0.1)
			var p: float = pf.p
			# Small at the stack, swelling to ~0.35 m, then shrinking away as it drifts aft.
			var r := (0.1 + 0.28 * sin(minf(1.0, p * 1.1) * PI)) * (1.0 + 0.25 * thr)
			var top: Vector3 = pf.top
			var pos := Vector3(top.x + pf.dx * p * 3.0, top.y + 0.05 + p * 2.0, top.z + pf.dz - p * (0.6 + speed_k * 2.4))
			smoke_mm.set_instance_transform(pf.i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * maxf(0.001, r)), pos))


static func _add_driver(vis: BoatVisual, d: Driver, steer_factor := 1.0, accel := true) -> void:
	vis.drivers.append([d, steer_factor, accel])


static func _smoke_stacks(vis: BoatVisual, rig: Node3D, tops: Array, count := 3) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere(1.0, 6, 4)     # 36 tris a puff: chunky is the point
	mm.instance_count = tops.size() * count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material("smoke", 0.95)
	mmi.name = "Smoke"
	rig.add_child(mmi)
	var i := 0
	for top in tops:
		for k in count:
			vis.puffs.append({"i": i, "top": top, "p": (k + randf() * 0.5) / count, "dx": randf_range(-0.1, 0.1), "dz": randf_range(-0.1, 0.1)})
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), top))
			i += 1
	vis.smoke_mm = mm


# ------------------------------------------------------------------ jet ski
static func build_jetski(B: Builder, vis: BoatVisual, color: Variant) -> void:
	# Plan outline (stern → bow), half widths.
	var outline := [[-1.62, 0.5], [-1.3, 0.6], [-0.4, 0.62], [0.45, 0.6], [0.95, 0.5], [1.35, 0.3], [1.6, 0.08]]
	# stepped V hull: white keel step, white main hull, coloured deck, hood
	B.add(hull_slab(outline, 0.0, 0.2, 0.05, 0.62), "white", Transform3D.IDENTITY, 0.35)
	B.add(hull_slab(outline, 0.12, 0.3, 0.06, 0.96), "white", Transform3D.IDENTITY, 0.35)
	B.add(hull_slab(outline, 0.36, 0.08, 0.02, 1.02), "dark", Transform3D.IDENTITY, 0.85)    # rubber rub rail
	B.add(hull_slab(outline, 0.42, 0.2, 0.07, 0.97), color, Transform3D.IDENTITY, 0.4)       # deck
	var hood := [[0.05, 0.5], [0.5, 0.5], [0.95, 0.42], [1.3, 0.22], [1.5, 0.05]]
	B.add(hull_slab(hood, 0.6, 0.26, 0.09, 0.9), color, Transform3D.IDENTITY, 0.4)           # hood
	B.add(hull_slab([[0.1, 0.38], [0.6, 0.35], [1.1, 0.22]], 0.84, 0.05, 0.02), "white", Transform3D.IDENTITY, 0.4)  # hood stripe
	# footwell rubber mats
	B.add(box(0.22, 0.04, 1.35), "dark", at(-0.44, 0.62, -0.55), 0.9)
	B.add(box(0.22, 0.04, 1.35), "dark", at(0.44, 0.62, -0.55), 0.9)
	# seat: dark base, coloured saddle stripe, white piping
	B.add(rbox(0.46, 0.22, 1.45, 0.08), "dark", at(0, 0.74, -0.6), 0.75)
	B.add(box(0.34, 0.06, 1.2), "white", at(0, 0.85, -0.6), 0.7)
	B.add(box(0.22, 0.05, 1.05), color, at(0, 0.885, -0.62), 0.7)
	# rear grab handle + boarding step
	B.add(box(0.6, 0.05, 0.3), "dark", at(0, 0.5, -1.55), 0.85)
	B.add(cyl(0.03, 0.03, 0.4, 8), "steel", at(0, 0.72, -1.36) * BAR_ROT, 0.3, 0.7)
	# console pod + handlebar
	B.add(rbox(0.36, 0.3, 0.42, 0.06), "dark", at(0, 0.98, 0.42), 0.6)
	B.add(box(0.16, 0.1, 0.05), "sky", at(0, 1.06, 0.62), 0.2)          # dash display
	var bars := Node3D.new()
	bars.position = Vector3(0, 1.14, 0.38)
	bars.add_child(B.merged([[cyl(0.03, 0.03, 0.74, 8), BAR_ROT], [cyl(0.03, 0.03, 0.12, 8), at(0, -0.06, 0)]], "steel", 0.3, 0.7))
	bars.add_child(B.merged([[cyl(0.045, 0.045, 0.16, 8), at(-0.33, 0, 0) * BAR_ROT], [cyl(0.045, 0.045, 0.16, 8), at(0.33, 0, 0) * BAR_ROT]], "dark", 0.9))
	vis.add_child(bars)
	vis.parts.bars = bars
	# windshield
	B.add(box(0.5, 0.26, 0.03), "glass", mat4(0, 1.1, 0.72, -0.5), 0.12)
	# mirrors
	B.add(box(0.1, 0.07, 0.05), "dark", at(-0.36, 1.08, 0.66), 0.6)
	B.add(box(0.1, 0.07, 0.05), "dark", at(0.36, 1.08, 0.66), 0.6)
	# intake grate
	B.add(box(0.3, 0.03, 0.8), "dark", at(0, 0.005, -0.7), 0.9)
	var nozzle := Node3D.new()
	nozzle.position = Vector3(0, 0.16, -1.66)
	nozzle.add_child(B.mesh(cyl(0.1, 0.13, 0.26, 12), "dark", 0.7, 0.0, at(0, 0, -0.12) * TUBE_ROT))
	nozzle.add_child(B.mesh(cyl(0.07, 0.07, 0.02, 12), "steel", 0.3, 0.7, at(0, 0, -0.25) * TUBE_ROT))
	vis.add_child(nozzle)
	vis.parts.nozzle = nozzle
	B.flush(vis)

	# rider: sits forward on the saddle, leaning at the bars
	var driver := build_driver(B, {
		"scale": 0.92, "vest": "orange", "shirt": "white", "helmet": "navy" if color_of(color) == PALETTE.orange else "red", "shorts": "navy",
		"hands": [[-0.36, 0.3, 0.6], [0.36, 0.3, 0.6]], "pitch": 0.22,
	})
	driver.position = Vector3(0, 0.86, -0.42)
	vis.add_child(driver)
	_add_driver(vis, driver)


# ------------------------------------------------------------------ pontoon
static func build_pontoon(B: Builder, vis: BoatVisual, color: Variant) -> void:
	var L := 6.6
	var deck_y := 0.68
	# twin aluminium tubes with tapered noses
	for x in [-1.0, 1.0]:
		B.add(cyl(0.33, 0.33, L - 0.9, 12), "steel", at(x, 0.33, -0.15) * TUBE_ROT, 0.3, 0.75)
		B.add(cyl(0.1, 0.33, 0.9, 12), "steel", at(x, 0.33, L / 2.0 - 0.6) * rot_x(-PI / 2.0), 0.3, 0.75)
		B.add(cyl(0.33, 0.28, 0.2, 12), "steel", at(x, 0.33, -L / 2.0 + 0.2) * rot_x(PI / 2.0), 0.3, 0.75)
		B.add(box(0.7, 0.14, L - 1.0), "slate", at(x, 0.62, -0.1), 0.6)  # tube brackets
	# cross beams + deck
	B.add(box(2.4, 0.1, L - 0.6), "slate", at(0, 0.62, -0.05), 0.6)
	B.add(box(2.6, 0.12, L), "sand", at(0, deck_y, 0), 0.8)
	B.add(box(2.66, 0.05, L + 0.06), "white", at(0, deck_y - 0.06, 0), 0.5)   # deck trim
	# fence: coloured panels with white top rails and steel posts, gate at the bow
	var rail_y := deck_y + 0.06
	var panel_h := 0.62
	var panels := [
		[-1.27, -L / 2.0 + 0.05, -1.27, L / 2.0 - 0.9],
		[1.27, -L / 2.0 + 0.05, 1.27, L / 2.0 - 0.9],
		[-1.27, -L / 2.0 + 0.05, 1.27, -L / 2.0 + 0.05],
		[-1.27, L / 2.0 - 0.9, -0.45, L / 2.0 - 0.9],
		[0.45, L / 2.0 - 0.9, 1.27, L / 2.0 - 0.9],
	]
	for pn in panels:
		var x0: float = pn[0]
		var z0: float = pn[1]
		var x1: float = pn[2]
		var z1: float = pn[3]
		var dx := x1 - x0
		var dz := z1 - z0
		var len := Vector2(dx, dz).length()
		var ang := atan2(dx, dz)
		var cx := (x0 + x1) / 2.0
		var cz := (z0 + z1) / 2.0
		B.add(box(0.05, panel_h * 0.6, len), color, mat4(cx, rail_y + panel_h * 0.3 + 0.08, cz, 0, ang), 0.5)
		B.add(box(0.06, 0.08, len), "white", mat4(cx, rail_y + panel_h * 0.42 + 0.08, cz, 0, ang), 0.5)
		B.add(box(0.06, 0.05, len), "white", mat4(cx, rail_y + 0.06, cz, 0, ang), 0.5)
		B.add(cyl(0.035, 0.035, len, 6), "white", mat4(cx, rail_y + panel_h + 0.05, cz, 0, ang) * TUBE_ROT, 0.4)
		for t in [0.0, 1.0]:
			B.add(cyl(0.035, 0.035, panel_h + 0.08, 6), "steel", at(x0 + dx * t, rail_y + panel_h / 2.0 + 0.04, z0 + dz * t), 0.3, 0.7)
	# bimini canopy over the helm and rear bench
	var canopy_y := deck_y + 2.25
	for x in [-1.15, 1.15]:
		for z in [-2.5, 0.35]:
			B.add(cyl(0.035, 0.035, canopy_y - deck_y, 6), "steel", at(x, (canopy_y + deck_y) / 2.0, z), 0.3, 0.7)
	B.add(rbox(2.7, 0.1, 3.3, 0.05), color, at(0, canopy_y + 0.02, -1.05), 0.6)
	B.add(box(2.72, 0.04, 0.5), "white", at(0, canopy_y + 0.06, -1.05), 0.6)   # centre stripe
	B.add(box(2.7, 0.06, 3.3), "white", at(0, canopy_y - 0.03, -1.05), 0.6)    # underside
	# helm console (starboard) with windshield and wheel
	var console_x := 0.62
	var console_z := 0.1
	B.add(rbox(0.8, 0.95, 0.55, 0.06), "white", at(console_x, deck_y + 0.06 + 0.475, console_z), 0.4)
	B.add(box(0.6, 0.08, 0.35), color, at(console_x, deck_y + 1.0, console_z + 0.02), 0.5)
	B.add(box(0.78, 0.45, 0.03), "glass", mat4(console_x, deck_y + 1.2, console_z + 0.2, -0.35), 0.12)
	B.add(box(0.2, 0.12, 0.05), "sky", at(console_x, deck_y + 0.86, console_z - 0.27), 0.2)
	var wheel := helm_wheel(B, Vector3(console_x, deck_y + 0.95, console_z - 0.36), 0.19, -0.35, false)
	vis.add_child(wheel)
	vis.parts.wheel = wheel
	B.add(cyl(0.05, 0.06, 0.18, 8), "steel", at(console_x, deck_y + 0.88, console_z - 0.28) * rot_x(-0.35), 0.3, 0.7)
	# captain's pedestal seat
	B.add(cyl(0.06, 0.06, 0.4, 8), "steel", at(console_x, deck_y + 0.26, console_z - 0.95), 0.3, 0.7)
	B.add(box(0.6, 0.12, 0.55), "white", at(console_x, deck_y + 0.5, console_z - 0.95), 0.6)
	B.add(box(0.6, 0.55, 0.12), "white", at(console_x, deck_y + 0.8, console_z - 1.22), 0.6)
	B.add(rbox(0.48, 0.4, 0.06, 0.03), color, at(console_x, deck_y + 0.8, console_z - 1.15), 0.7)
	# benches: stern L-bench and bow lounge, white bases with coloured cushions
	for bn in [[0.0, -2.85, 2.35, 0.6], [-0.95, -1.6, 0.55, 1.9], [-0.95, 1.4, 0.55, 1.6], [0.95, 1.6, 0.55, 1.2]]:
		B.add(box(bn[2], 0.38, bn[3]), "white", at(bn[0], deck_y + 0.06 + 0.19, bn[1]), 0.5)
		B.add(rbox(bn[2] - 0.08, 0.12, bn[3] - 0.08, 0.05), color, at(bn[0], deck_y + 0.06 + 0.44, bn[1]), 0.75)
	# backrests along the fence for the stern bench
	B.add(rbox(2.3, 0.3, 0.1, 0.04), color, at(0, deck_y + 0.85, -3.15), 0.75)
	# cooler + tube: party boat props
	B.add(box(0.5, 0.36, 0.34), "sky", at(0.35, deck_y + 0.24, 2.0), 0.4)
	B.add(box(0.52, 0.06, 0.36), "white", at(0.35, deck_y + 0.44, 2.0), 0.4)
	# stern boarding ladder
	B.add(cyl(0.02, 0.02, 0.9, 6), "steel", at(-0.7, 0.3, -3.42), 0.3, 0.7)
	B.add(cyl(0.02, 0.02, 0.9, 6), "steel", at(-0.4, 0.3, -3.42), 0.3, 0.7)
	B.add(cyl(0.02, 0.02, 0.3, 6), "steel", at(-0.55, 0.15, -3.42) * BAR_ROT, 0.3, 0.7)
	B.add(cyl(0.02, 0.02, 0.3, 6), "steel", at(-0.55, 0.45, -3.42) * BAR_ROT, 0.3, 0.7)
	# flag pole at the stern quarter
	B.add(cyl(0.02, 0.025, 1.6, 6), "white", at(1.15, deck_y + 0.7 + 0.8, -3.2), 0.5)
	B.flush(vis)
	var pennant := flag("yellow", 0.7, 0.36)
	pennant.position = Vector3(1.15, deck_y + 2.28, -3.2)
	vis.add_child(pennant)
	vis.pennants.append(pennant)

	# outboard: pivots with the steering, propeller spins with throttle
	var motor := Node3D.new()
	motor.position = Vector3(0, deck_y - 0.1, -L / 2.0 - 0.1)
	var mb := Builder.new()
	mb.add(rbox(0.56, 0.5, 0.7, 0.1), "dark", at(0, 0.6, -0.2), 0.55)
	mb.add(box(0.5, 0.12, 0.55), color, at(0, 0.9, -0.2), 0.5)
	mb.add(box(0.3, 0.05, 0.4), "steel", at(0, 0.6, -0.55), 0.3, 0.7)
	mb.add(box(0.16, 1.05, 0.34), "dark", at(0, -0.05, -0.2), 0.55)
	mb.add(cyl(0.11, 0.11, 0.6, 10), "dark", at(0, -0.55, -0.15) * TUBE_ROT, 0.55)
	mb.flush(motor, "Motor")
	var prop := Node3D.new()
	prop.position = Vector3(0, -0.55, -0.5)
	var blades: Array = []
	for i in 3:
		blades.append([box(0.1, 0.3, 0.03), rot_z(float(i) / 3.0 * TAU) * rot_y(0.6) * at(0, 0.17, 0)])
	blades.append([cyl(0.05, 0.05, 0.1, 8), TUBE_ROT])
	prop.add_child(B.merged(blades, "steel", 0.3, 0.8))
	motor.add_child(prop)
	vis.add_child(motor)
	vis.parts.motor = motor
	vis.parts.prop = prop

	# captain at the helm, passenger on the stern bench
	var captain := build_driver(B, {
		"scale": 1.15, "vest": "orange", "shirt": "white", "helmet": "yellow", "hair": true, "shorts": "red" if color_of(color) == PALETTE.blue else "navy",
		"hands": [[-0.16, 0.32, 0.49], [0.16, 0.32, 0.49]], "pitch": 0.05,
	})
	captain.position = Vector3(console_x, deck_y + 0.58, console_z - 0.95)
	vis.add_child(captain)
	_add_driver(vis, captain)
	var passenger := build_driver(B, {
		"scale": 1.05, "vest": "red", "shirt": "green", "helmet": "brown", "hair": true, "shorts": "sky",
		"hands": [[-0.42, 0.62, 0.15], [0.42, 0.62, 0.15]], "pitch": -0.05,
	})
	passenger.position = Vector3(0.6, deck_y + 0.58, -2.75)
	vis.add_child(passenger)
	_add_driver(vis, passenger, 0.5, false)


# ------------------------------------------------------------- GLB boats
## Shared start for the Kenney boats: load the colour variant, scale it so the
## hull length matches the physics hull, sit the keel at the waterline and
## return a `rig` node in the same frame for the procedural bits.
## Returns {model, rig, s, variant}; K(x, y, z) = Vector3(x, y, z) * s converts Kenney units.
static func load_variant(vis: BoatVisual, spec: Dictionary, color_index: int, roughness := 0.45) -> Dictionary:
	var variants: Array = spec.variants
	var variant: Dictionary = variants[color_index % variants.size()]
	var s: float = float(Hulls.HULLS[spec.hull].length) / float(variant.length)
	var model := load_kenney(variant.file)
	set_model_roughness(model, roughness)
	model.name = "Model"
	model.scale = Vector3.ONE * s
	model.rotation.y = spec.yaw
	model.position.y = keel_y(spec)
	var rig := Node3D.new()
	rig.name = "Rig"
	rig.rotation.y = spec.yaw
	rig.position.y = keel_y(spec)
	vis.add_child(model)
	vis.add_child(rig)
	return {"model": model, "rig": rig, "s": s, "variant": variant}


## Helm wheel (torus + spokes) tilted back toward the driver, hub at `pos`.
static func helm_wheel(B: Builder, pos: Vector3, r := 0.2, tilt := -0.45, with_column := true) -> MeshInstance3D:
	var wheel := B.merged([
		[torus(r, 0.03, 6, 14), TORUS_XY],
		[cyl(0.02, 0.02, r * 1.9, 6), BAR_ROT],
		[cyl(0.02, 0.02, r * 1.9, 6), Transform3D.IDENTITY],
		[sphere(0.05, 8, 6), Transform3D.IDENTITY],
	], "dark", 0.6)
	wheel.rotation.x = tilt
	wheel.position = pos
	if with_column:
		B.add(cyl(0.04, 0.05, 0.3, 8), "steel", at(pos.x, pos.y - 0.05, pos.z + 0.12) * rot_x(tilt), 0.3, 0.7)
	return wheel


## Hand targets (figure-local) for a driver of scale `ds` at `seat` reaching a wheel hub at `wheel_pos`.
static func reach_for(seat: Vector3, wheel_pos: Vector3, ds: float, spread := 0.18, dz := 0.05) -> Array:
	var r := Vector3((wheel_pos.x - seat.x) / ds, (wheel_pos.y - seat.y) / ds, (wheel_pos.z - seat.z + dz) / ds)
	return [[r.x - spread, r.y, r.z], [r.x + spread, r.y, r.z]]


static func build_speedboat(B: Builder, vis: BoatVisual, spec: Dictionary, color_index: int) -> void:
	var lv := load_variant(vis, spec, color_index, 0.4)
	var rig: Node3D = lv.rig
	var s: float = lv.s
	var color: String = spec.colors[color_index % spec.colors.size()]
	# steering wheel ahead of the seat
	var wheel_pos := Vector3(0, 1.02, -0.45) * s
	var wheel := helm_wheel(B, wheel_pos, 0.2, -0.45)
	rig.add_child(wheel)
	vis.parts.wheel = wheel
	# pennant on the stern
	var pole_pos := Vector3(0.72, 0.85, -1.4) * s
	B.add(cyl(0.02, 0.025, 1.1, 6), "white", atv(pole_pos + Vector3(0, 0.55, 0)), 0.5)
	B.flush(rig)
	var pennant := flag(color, 0.6, 0.32)
	pennant.position = pole_pos + Vector3(0, 1.08, 0)
	rig.add_child(pennant)
	vis.pennants.append(pennant)
	# driver seated behind the wheel
	var seat := Vector3(0, 0.92, -0.98) * s
	var ds := 1.2
	var driver := build_driver(B, {
		"scale": ds, "vest": "orange", "shirt": "white", "helmet": color, "shorts": "navy",
		"hands": reach_for(seat, wheel_pos, ds), "pitch": 0.08,
	})
	driver.position = seat
	rig.add_child(driver)
	_add_driver(vis, driver)


static func build_sailboat(B: Builder, vis: BoatVisual, spec: Dictionary, color_index: int) -> void:
	var variants: Array = spec.variants
	var variant: Dictionary = variants[color_index % variants.size()]
	var s: float = float(Hulls.HULLS[spec.hull].length) / float(variant.length)
	var model := load_kenney(variant.file)
	set_model_roughness(model, 0.45)
	# heel pivot: the model swings about the body origin
	var heel := Node3D.new()
	heel.name = "Heel"
	vis.add_child(heel)
	model.scale = Vector3.ONE * s
	model.rotation.y = spec.yaw
	model.position.y = keel_y(spec)
	heel.add_child(model)
	var sail := find_named(model, "sail")
	if sail != null:
		vis.parts.sail = sail
	var rig := Node3D.new()
	rig.rotation.y = spec.yaw
	rig.position.y = keel_y(spec)
	heel.add_child(rig)
	vis.parts.heel = heel
	# masthead pennant
	var top := Vector3(0, 4.7, 0.58) * s
	if variant.file == "boat-sail-b.glb":
		top = Vector3(0, 4.45, -0.3) * s
	B.add(cyl(0.02, 0.02, 0.5, 6), "white", atv(top + Vector3(0, 0.2, 0)), 0.5)
	B.flush(rig)
	var pennant := flag("red", 0.7, 0.34)
	pennant.position = top + Vector3(0, 0.42, 0)
	rig.add_child(pennant)
	vis.pennants.append(pennant)
	# helm: the kid steers a tiller from the cockpit
	var seat := Vector3(0.0, 0.95, -1.15) * s
	var driver := build_driver(B, {
		"scale": 1.2, "vest": "yellow", "shirt": "white", "helmet": "red", "hair": true, "shorts": "navy",
		"hands": [[-0.15, 0.25, 0.42], [0.15, 0.25, 0.42]], "pitch": 0.0,
	})
	driver.position = seat
	rig.add_child(driver)
	_add_driver(vis, driver, 1.0, false)
	var tiller := B.mesh(cyl(0.025, 0.035, 1.0, 8), "brown", 0.6, 0.0)
	var tiller_pivot := Node3D.new()
	tiller_pivot.position = seat + Vector3(0, 0.12, -0.55)
	tiller.transform = at(0, 0.1, 0.5) * rot_x(PI / 2.0 - 0.25)
	tiller_pivot.add_child(tiller)
	rig.add_child(tiller_pivot)
	vis.parts.tiller = tiller_pivot


static func build_fishing(B: Builder, vis: BoatVisual, spec: Dictionary, color_index: int) -> void:
	var color: String = spec.colors[color_index % spec.colors.size()]
	var lv := load_variant(vis, spec, color_index, 0.5)
	var rig: Node3D = lv.rig
	var s: float = lv.s
	# Outside helm on the cabin's aft wall; the kid stands in the cockpit behind it.
	var wheel_pos := Vector3(0, 1.42, -0.3) * s
	var wheel := helm_wheel(B, wheel_pos, 0.2, -0.5)
	rig.add_child(wheel)
	vis.parts.wheel = wheel
	var ds := 1.1
	var seat := Vector3(0, 0.8, -0.62) * s
	seat.y += 0.64 * ds                                  # standing: feet on the cockpit floor
	var driver := build_driver(B, {
		"scale": ds, "vest": "yellow", "shirt": "white", "helmet": color, "hair": true, "shorts": "navy",
		"hands": reach_for(seat, wheel_pos, ds, 0.2), "pitch": 0.05, "legs": "standing",
	})
	driver.position = seat
	rig.add_child(driver)
	_add_driver(vis, driver)
	# Fish crates and a cooler on the deck in the trim colour.
	var floor_y := seat.y - 0.64 * ds
	B.add(rbox(0.55, 0.42, 0.55, 0.05), color, at(-0.48 * s, floor_y + 0.21, -1.35 * s), 0.6)
	B.add(rbox(0.55, 0.3, 0.55, 0.05), color, at(-0.48 * s, floor_y + 0.57, -1.35 * s), 0.6)
	B.add(rbox(0.5, 0.36, 0.4, 0.05), "white", at(0.5 * s, floor_y + 0.18, -1.5 * s), 0.5)
	# Rod holders on the stern gunwale; the rods fan out aft and bob with the sea.
	for side in [-1.0, 1.0]:
		var base := Vector3(side * 0.62, 1.05, -1.78) * s
		B.add(cyl(0.035, 0.035, 0.3, 8), "steel", atv(base + Vector3(0, 0.1, 0)), 0.3, 0.7)
		var rod := Node3D.new()
		rod.position = base + Vector3(0, 0.2, 0)
		rod.rotation = Vector3(0.95, 0, -side * 0.2)            # tip up and aft, splayed outward
		var RL := 2.6
		var rb := Builder.new()
		rb.add(cyl(0.008, 0.022, RL, 6), "dark", at(0, RL / 2.0, 0), 0.5)
		rb.add(cyl(0.028, 0.028, 0.35, 6), color, at(0, 0.3, 0), 0.6)     # grip
		rb.add(sphere(0.045, 6, 4), "steel", at(0, 0.55, 0.03), 0.3, 0.7) # reel
		rb.flush(rod, "Rod")
		# Line hangs from the tip to a red-and-white float.
		var line := Node3D.new()
		line.position = Vector3(0, RL, 0)
		var lb := Builder.new()
		lb.add(cyl(0.004, 0.004, 1.1, 3), "white", at(0, -0.55, 0), 0.5)
		lb.add(sphere(0.07, 8, 6), "red", at(0, -1.12, 0), 0.4)
		lb.add(dome(0.071, 8, 3), "white", at(0, -1.12, 0), 0.4)
		lb.flush(line, "Line")
		rod.add_child(line)
		rig.add_child(rod)
		vis.rods.append({"rod": rod, "line": line, "side": side, "base": 0.95})
	# Mast pennant.
	var top := Vector3(0, 2.6, -0.31) * s
	B.add(cyl(0.02, 0.02, 0.5, 6), "white", atv(top + Vector3(0, 0.2, 0)), 0.5)
	B.flush(rig)
	var pennant := flag(color, 0.6, 0.3)
	pennant.position = top + Vector3(0, 0.42, 0)
	rig.add_child(pennant)
	vis.pennants.append(pennant)


## Flying bridge on a flat roof: console with a wheel, a rail round the edge
## and the kid standing at the helm. Roof extents in metres (rig frame).
static func flying_bridge(B: Builder, vis: BoatVisual, rig: Node3D, o: Dictionary) -> void:
	var roof_y: float = o.roof_y
	var z_aft: float = o.z_aft
	var z_fwd: float = o.z_fwd
	var helm_z: float = o.helm_z
	var hw: float = o.half_width
	var color: Variant = o.color
	var ds: float = o.get("ds", 1.1)
	var console_z := helm_z + 0.42
	B.add(rbox(0.7, 0.55, 0.4, 0.06), "white", at(0, roof_y + 0.28, console_z), 0.4)
	B.add(box(0.6, 0.06, 0.3), color, at(0, roof_y + 0.58, console_z), 0.5)
	B.add(box(0.2, 0.1, 0.04), "sky", at(0, roof_y + 0.48, console_z - 0.2), 0.2)
	var wheel_pos := Vector3(0, roof_y + 0.62, console_z - 0.25)
	var wheel := helm_wheel(B, wheel_pos, 0.19, -0.5)
	rig.add_child(wheel)
	vis.parts.wheel = wheel
	var rail_h := 0.7
	for x in [-hw, hw]:
		B.add(cyl(0.025, 0.025, z_fwd - z_aft, 6), "white", at(x, roof_y + rail_h, (z_aft + z_fwd) / 2.0) * TUBE_ROT, 0.4)
		for z in [z_aft, (z_aft + z_fwd) / 2.0, z_fwd]:
			B.add(cyl(0.025, 0.025, rail_h, 6), "white", at(x, roof_y + rail_h / 2.0, z), 0.4)
	B.add(cyl(0.025, 0.025, hw * 2.0, 6), "white", at(0, roof_y + rail_h, z_fwd) * BAR_ROT, 0.4)
	B.add(cyl(0.025, 0.025, hw * 2.0, 6), "white", at(0, roof_y + rail_h, z_aft) * BAR_ROT, 0.4)
	var seat := Vector3(0, roof_y + 0.64 * ds, helm_z)
	var driver := build_driver(B, {
		"scale": ds, "vest": o.get("vest", "orange"), "shirt": "white", "helmet": o.get("helmet", color), "hair": false, "shorts": "navy",
		"hands": reach_for(seat, wheel_pos, ds, 0.2), "pitch": 0.05, "legs": "standing",
	})
	driver.position = seat
	rig.add_child(driver)
	_add_driver(vis, driver)


static func build_tug(B: Builder, vis: BoatVisual, spec: Dictionary, color_index: int) -> void:
	var color: String = spec.colors[color_index % spec.colors.size()]
	var lv := load_variant(vis, spec, color_index, 0.5)
	var rig: Node3D = lv.rig
	var s: float = lv.s
	var variant: Dictionary = lv.variant
	var roof_y: float = variant.roof[0]
	var roof_aft: float = variant.roof[1]
	var roof_fwd: float = variant.roof[2]
	# Funnels: Kenney's where the variant has them, a stubby procedural one otherwise.
	var funnels: Variant = variant.funnels
	if funnels == null:
		funnels = [[-0.9, roof_y + 0.5]]
		var f := Vector3(0, roof_y, -0.9) * s
		B.add(cyl(0.34, 0.4, 0.5 * s, 12), color, atv(f + Vector3(0, 0.25 * s, 0)), 0.5)
		B.add(cyl(0.36, 0.36, 0.1 * s, 12), "dark", atv(f + Vector3(0, 0.5 * s, 0)), 0.6)
	var roof := roof_y * s
	flying_bridge(B, vis, rig, {
		"roof_y": roof, "z_aft": roof_aft * s + 0.1, "z_fwd": roof_fwd * s - 0.1, "helm_z": float(variant.helm_z) * s, "half_width": 0.72 * s, "color": color,
	})
	# Life ring on the rail and a coil of rope on the foredeck: tug dressing.
	B.add(torus(0.28, 0.08, 5, 10), "white", mat4(0.72 * s + 0.02, roof + 0.35, roof_aft * s + 0.6, 0, PI / 2.0) * TORUS_XY, 0.6)
	B.add(torus(0.3, 0.1, 5, 10), "sand", mat4(0, 1.0 * s + 0.05, roof_fwd * s + 0.45, PI / 2.0) * TORUS_XY, 0.9)
	B.flush(rig)
	var tops: Array = []
	for fz in funnels:
		tops.append(Vector3(0, fz[1], fz[0]) * s)
	_smoke_stacks(vis, rig, tops, 4)


static func build_airboat(B: Builder, vis: BoatVisual, spec: Dictionary, color_index: int) -> void:
	var color: String = spec.colors[color_index % spec.colors.size()]
	var lv := load_variant(vis, spec, color_index, 0.45)
	var rig: Node3D = lv.rig
	var s: float = lv.s
	var fan := find_named(lv.model, "fan")
	if fan != null:
		vis.parts.fan = fan
	# Raised bucket seat is in the model; the kid sits on it with a tall rudder stick on the left.
	var ds := 1.1
	var seat := Vector3(0, 0.9, -0.3) * s
	var stick_base := Vector3(-0.33, 0.6, -0.05) * s
	var stick := Node3D.new()
	stick.position = stick_base
	var sb := Builder.new()
	sb.add(cyl(0.025, 0.035, 1.0, 8), "steel", at(0, 0.5, 0), 0.3, 0.7)
	sb.add(sphere(0.07, 8, 6), color, at(0, 1.0, 0), 0.5)
	sb.flush(stick, "Stick")
	rig.add_child(stick)
	vis.parts.stick = stick
	var stick_top := stick_base + Vector3(0, 0.95, 0)
	var driver := build_driver(B, {
		"scale": ds, "vest": color, "shirt": "white", "helmet": "white", "shorts": "dark",
		"hands": [[(stick_top.x - seat.x) / ds, (stick_top.y - seat.y) / ds, (stick_top.z - seat.z) / ds], [0.28, 0.05, 0.3]], "pitch": 0.0,
	})
	driver.position = seat
	rig.add_child(driver)
	_add_driver(vis, driver)
	# Ear defenders: two chunky cups on the helmet.
	driver.head.add_child(B.merged([[cyl(0.09, 0.09, 0.06, 8), at(-0.2, 0, 0) * BAR_ROT], [cyl(0.09, 0.09, 0.06, 8), at(0.2, 0, 0) * BAR_ROT]], color, 0.5))
	# Bow light and a number plate in the trim colour.
	var plate := Vector3(0.72, 0.62, 0.35) * s
	B.add(box(0.05, 0.36, 0.5), color, at(plate.x, plate.y + 0.2, plate.z), 0.5)
	B.add(box(0.05, 0.36, 0.5), color, at(-plate.x, plate.y + 0.2, plate.z), 0.5)
	B.flush(rig)


## Kenney's boat-tow is a river towboat (push boat): pilothouse, twin stacks
## and a bumper bow. The kid drives from a flying bridge on the roof, a
## passenger rides the aft deck, and both stacks puff.
static func build_towboat(B: Builder, vis: BoatVisual, spec: Dictionary, color_index: int) -> void:
	var color: String = spec.colors[color_index % spec.colors.size()]
	var lv := load_variant(vis, spec, color_index, 0.45)
	var rig: Node3D = lv.rig
	var s: float = lv.s
	var variant: Dictionary = lv.variant
	var roof_y: float = variant.roof[0]
	var roof_aft: float = variant.roof[1]
	var roof_fwd: float = variant.roof[2]
	var roof := roof_y * s
	var rhw: float = variant.roof_half_width
	flying_bridge(B, vis, rig, {
		"roof_y": roof, "z_aft": roof_aft * s + 0.1, "z_fwd": roof_fwd * s - 0.1, "helm_z": float(variant.helm_z) * s, "half_width": rhw * s, "color": color,
		"ds": 1.15, "helmet": "yellow", "vest": "red",
	})
	# Passenger sitting on the aft deck, arms up.
	var pax := build_driver(B, {
		"scale": 1.05, "vest": "orange", "shirt": "green", "helmet": "brown", "hair": true, "shorts": "sky",
		"hands": [[-0.4, 0.7, 0.1], [0.4, 0.7, 0.1]], "pitch": -0.05,
	})
	pax.position = Vector3(0.75, 1.45, -2.75) * s
	rig.add_child(pax)
	_add_driver(vis, pax, 0.6, false)
	# Life rings on the deckhouse sides, coloured bollards at the bow, pennant on the roof rail.
	for x in [-0.95, 0.95]:
		B.add(torus(0.3, 0.09, 5, 10), "white", mat4(x * s, 2.0 * s, -0.4 * s, 0, PI / 2.0) * TORUS_XY, 0.6)
	for x in [-0.55, 0.55]:
		B.add(cyl(0.12, 0.12, 0.45, 8), color, at(x * s, 1.45 * s + 0.22, 2.3 * s), 0.5)
	var pole := Vector3(-rhw * s + 0.15, roof, roof_aft * s + 0.3)
	B.add(cyl(0.02, 0.025, 1.2, 6), "white", atv(pole + Vector3(0, 0.6, 0)), 0.5)
	B.flush(rig)
	var pennant := flag(color, 0.6, 0.32)
	pennant.position = pole + Vector3(0, 1.18, 0)
	rig.add_child(pennant)
	vis.pennants.append(pennant)
	var tops: Array = []
	for stk in variant.stacks:
		tops.append(Vector3(stk[0], stk[2], stk[1]) * s)
	_smoke_stacks(vis, rig, tops, 3)


static func build_rowboat(B: Builder, vis: BoatVisual, spec: Dictionary, color_index: int) -> void:
	var color: String = spec.colors[color_index % spec.colors.size()]
	var lv := load_variant(vis, spec, color_index, 0.6)
	var rig: Node3D = lv.rig
	var s: float = lv.s
	# Kenney's oars are one static mesh; hide them and build a pair that row.
	var paddles := find_named(lv.model, "paddles")
	if paddles != null:
		paddles.visible = false
	var ds := 0.95
	var lock_z := -0.18
	var seat := Vector3(0, 0.58, lock_z - 0.33) * s
	for side in [-1.0, 1.0]:
		# side -1 = oar sticking out to -X; the handle points inboard.
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.71, 0.64, lock_z) * s
		var ob := Builder.new()
		ob.add(cyl(0.028, 0.028, 2.3, 8), "brown", at(side * 0.6, 0, 0) * BAR_ROT, 0.65)
		ob.add(rbox(0.5, 0.18, 0.04, 0.02), color, at(side * 1.5, 0, 0), 0.5)
		ob.add(cyl(0.035, 0.035, 0.3, 8), "dark", at(-side * 0.55, 0, 0) * BAR_ROT, 0.7)
		ob.flush(pivot, "Oar")
		B.add(cyl(0.03, 0.03, 0.14, 6), "steel", atv(pivot.position + Vector3(0, -0.02, 0)), 0.3, 0.7)
		rig.add_child(pivot)
		vis.oars.append({"pivot": pivot, "side": side})
	var driver := build_driver(B, {
		"scale": ds, "vest": "orange", "shirt": "white", "helmet": color, "hair": false, "shorts": "navy",
		"hands": [[-0.36, 0.2, 0.4], [0.36, 0.2, 0.4]], "pitch": 0.1,
	})
	driver.position = seat
	rig.add_child(driver)
	_add_driver(vis, driver)
	# Bucket and a rolled towel in the bow.
	var bow := Vector3(0, 0.25, 0.8) * s
	B.add(cyl(0.16, 0.13, 0.26, 10), color, at(bow.x - 0.2, bow.y + 0.13, bow.z), 0.5)
	B.add(cyl(0.09, 0.09, 0.4, 8), "white", at(bow.x + 0.25, bow.y + 0.09, bow.z - 0.1) * TUBE_ROT, 0.9)
	B.flush(rig)


## Placeholder submarine (yellow hull, conning tower, fins, prop) so the shared
## build path works before boats/Submarine.tscn lands.
static func build_sub(B: Builder, vis: BoatVisual, color: Variant) -> void:
	B.add(cyl(0.8, 0.8, 4.4, 14), color, TUBE_ROT, 0.45)
	B.add(sphere(0.8, 14, 8), color, at(0, 0, 2.2), 0.45)
	B.add(cyl(0.8, 0.45, 1.2, 14), color, at(0, 0, -2.8) * rot_x(PI / 2.0), 0.45)
	B.add(box(1.0, 0.9, 1.6), color, at(0, 1.0, 0.3), 0.45)
	B.add(box(0.14, 1.4, 0.7), "dark", at(0, 0.6, -3.0), 0.5)
	B.add(box(2.4, 0.1, 0.7), "dark", at(0, 0, -3.0), 0.5)
	B.add(cyl(0.06, 0.06, 0.9, 6), "steel", at(0, 1.85, 0.5), 0.3, 0.7)
	B.add(box(0.9, 0.3, 0.05), "glass", at(0, 1.0, 1.1), 0.1)
	B.flush(vis)
	var prop := Node3D.new()
	prop.position = Vector3(0, 0, -3.5)
	var blades: Array = []
	for i in 4:
		blades.append([box(0.14, 0.5, 0.04), rot_z(float(i) / 4.0 * TAU) * rot_y(0.6) * at(0, 0.3, 0)])
	blades.append([cyl(0.08, 0.08, 0.2, 8), TUBE_ROT])
	prop.add_child(B.merged(blades, "steel", 0.3, 0.8))
	vis.add_child(prop)
	vis.parts.prop = prop


# --------------------------------------------------------------- public API
## Build the visual for a catalog boat: a BoatVisual (Node3D) with update(dt, body).
static func build_visual(id: String, color_index := 0) -> Node3D:
	var spec: Dictionary = CATALOG.get(id, {})
	var vis := BoatVisual.new()
	if spec.is_empty():
		push_error("Boats: unknown boat '%s'" % id)
		return vis
	var B := Builder.new()
	var colors: Array = spec.colors
	var color: String = colors[color_index % colors.size()]
	vis.id = id
	vis.spec = spec
	vis.color_index = color_index
	vis.name = "boat-" + id
	match id:
		"jetski":
			build_jetski(B, vis, color)
			for c in vis.get_children():
				c.position.y += keel_y(spec)
		"pontoon":
			build_pontoon(B, vis, color)
			for c in vis.get_children():
				c.position.y += keel_y(spec)
		"speedboat":
			build_speedboat(B, vis, spec, color_index)
		"sailboat":
			build_sailboat(B, vis, spec, color_index)
		"fishing":
			build_fishing(B, vis, spec, color_index)
		"tug":
			build_tug(B, vis, spec, color_index)
		"airboat":
			build_airboat(B, vis, spec, color_index)
		"towboat":
			build_towboat(B, vis, spec, color_index)
		"rowboat":
			build_rowboat(B, vis, spec, color_index)
		"sub":
			build_sub(B, vis, color)
	vis.triangles = B.tris
	return vis
