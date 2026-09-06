class_name World
extends Node3D
## One surface world (port of buildWorld in src/game/Worlds.js + buildIslands in Islands.js):
## heightfield islands (one vertex-coloured ArrayMesh each, <= 8k triangles), palms as a
## MultiMesh, lighthouse / hut / pier props, the shore-foam band, and the portals.
## Gate and hoop positions are exposed through `def` (Race builds their visuals).
##
##   var world := World.new(); world.ocean = ocean; add_child(world); world.build("lagoon")
##   boat.ground_fn = world.height_at           # collision field (soft wall past the shoreline)
##   world.terrain_at(x, z)                     # the surface the mesh shows
##   world.portals.test(body) -> dest           # see Portals.gd
##   world.update(dt)                           # or leave auto_update on
##
## `def.probe_span` is the game's concern (pass it to the ocean's focus/probe API).

const PALM_VARIANTS := 3

var id := ""
var def: Dictionary = {}
var ocean: Node                      # Ocean / StubOcean; set before build()
var auto_update := true              # call update(dt) from _process; Main may drive it instead
var fields: Array[IslandField] = []
var piers: Array = []
var portals: Portals
var shore_foam: ShoreFoam
var material: StandardMaterial3D
var triangles := 0
var palms := 0
var build_ms := 0
var _meshes: Array[Node3D] = []
var _palm_meshes: Array[ArrayMesh] = []


func _ready() -> void:
	if ocean == null:
		ocean = get_tree().get_first_node_in_group("ocean")
	if ocean == null and get_parent():
		ocean = get_parent().get_node_or_null("Ocean")


func _process(dt: float) -> void:
	if auto_update:
		update(dt)


## Build the world `world_id` (disposes the previous one).
func build(world_id: String) -> void:
	dispose()
	if not Worlds.WORLDS.has(world_id):
		push_error("World: unknown world '%s'" % world_id)
		return
	var t0 := Time.get_ticks_msec()
	id = world_id
	def = Worlds.WORLDS[id]
	name = "World-" + id
	Worlds.reset_world_events(id)
	material = IslandBuilder.material()
	piers = def.get("piers", [])
	triangles = 0
	palms = 0

	var props := IslandBuilder.Soup.new()
	var palm_sites: Array[Vector3] = []
	for isl in def.islands:
		var field := IslandField.new(isl)
		fields.append(field)
		var soup := IslandBuilder.Soup.new()
		IslandBuilder.build_terrain(field, soup)
		field.triangles = soup.triangles()
		triangles += field.triangles
		var mi := MeshInstance3D.new()
		mi.name = "island-%d" % int(isl.seed)
		mi.mesh = soup.mesh()
		mi.material_override = material
		add_child(mi)
		_meshes.append(mi)
		# per-island details: palms, lighthouse, hut
		var rng := IslandField.Rng.new(int(isl.seed) * 7919 + 17)
		var sites := IslandBuilder.scatter_palms(field, rng)
		palm_sites.append_array(sites)
		var before := props.triangles()
		var lh := IslandBuilder.pick_site(field, isl.get("lighthouse"), 4.0, rng)
		if lh != Vector3.INF:
			IslandBuilder.add_lighthouse(props, lh.x, lh.y - 0.4, lh.z)
		var hut := IslandBuilder.pick_site(field, isl.get("hut"), 2.2, rng)
		if hut != Vector3.INF:
			IslandBuilder.add_hut(props, hut.x, hut.y - 0.2, hut.z, rng.next() * TAU)
		field.detail_triangles = props.triangles() - before
	for p in piers:
		IslandBuilder.add_pier(props, p)
	if props.triangles() > 0:
		var pm := MeshInstance3D.new()
		pm.name = "props"
		pm.mesh = props.mesh()
		pm.material_override = material
		add_child(pm)
		_meshes.append(pm)
		triangles += props.triangles()

	_build_palms(palm_sites)

	shore_foam = ShoreFoam.new()
	shore_foam.name = "ShoreFoam"
	add_child(shore_foam)
	shore_foam.build(self, ocean)
	triangles += shore_foam.triangles

	portals = Portals.new()
	portals.name = "Portals"
	portals.ocean = ocean
	add_child(portals)
	portals.build(def.get("portals", []))

	build_ms = Time.get_ticks_msec() - t0
	print("[World] %s: %d islands, %d terrain+prop triangles, %d palms, %d portals, built in %d ms" % [
		id, fields.size(), triangles, palms, portals.portals.size(), build_ms])


## Palms: PALM_VARIANTS mesh variants, one MultiMeshInstance3D each, random yaw and size.
func _build_palms(sites: Array[Vector3]) -> void:
	palms = sites.size()
	if palms == 0:
		return
	if _palm_meshes.is_empty():
		for v in PALM_VARIANTS:
			_palm_meshes.append(IslandBuilder.palm_mesh(v))
	var rng := IslandField.Rng.new(4242)
	var buckets: Array = []
	for v in PALM_VARIANTS:
		buckets.append([])
	for s in sites:
		buckets[int(rng.next() * PALM_VARIANTS) % PALM_VARIANTS].append(s)
	for v in PALM_VARIANTS:
		var list: Array = buckets[v]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _palm_meshes[v]
		mm.instance_count = list.size()
		for i in list.size():
			var s: Vector3 = list[i]
			var size := 0.8 + rng.next() * 0.55
			var basis := Basis.from_euler(Vector3(0.0, rng.next() * TAU, 0.0)).scaled(Vector3.ONE * size)
			mm.set_instance_transform(i, Transform3D(basis, s))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "palms-%d" % v
		mmi.multimesh = mm
		mmi.material_override = material
		add_child(mmi)
		_meshes.append(mmi)
		triangles += _palm_meshes[v].get_faces().size() / 3 * list.size()


## The surface the mesh shows: max over the island fields and piers, DEEP far from land.
## `exact` = the web's full analytic profile beyond the sampled grids (deep seabed only); the
## default fast path skips the noise there (see IslandField.sample).
func terrain_at(x: float, z: float, exact := false) -> float:
	var h := IslandField.DEEP
	for f in fields:
		var v := f.sample(x, z, exact)
		if v > h:
			h = v
	for p in piers:
		var v := IslandField.pier_height(p, x, z)
		if v > h:
			h = v
	return h


## Collision field for BoatPhysics.ground_fn: true seabed in the water, a soft wall from the
## shoreline up (IslandField.collision_height).
func height_at(x: float, z: float) -> float:
	return IslandField.collision_height(terrain_at(x, z))


func update(dt: float) -> void:
	if def.is_empty():
		return
	if shore_foam:
		shore_foam.update(dt)
	if portals:
		portals.update(dt)


func dispose() -> void:
	for m in _meshes:
		m.queue_free()
	_meshes.clear()
	if shore_foam:
		shore_foam.queue_free()
		shore_foam = null
	if portals:
		portals.queue_free()
		portals = null
	fields.clear()
	piers = []
	if id != "":
		Worlds.reset_world_events(id)
	id = ""
	def = {}
	triangles = 0
	palms = 0


func get_harness_state() -> Dictionary:
	return {"world": id, "triangles": triangles, "palms": palms, "islands": fields.size(),
		"portals": portals.portals.size() if portals else 0, "foam_verts": shore_foam.vertices if shore_foam else 0,
		"build_ms": build_ms}
