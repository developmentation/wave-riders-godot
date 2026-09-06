class_name StubWorld
extends Node3D
## Bare-sea world used when worlds/World.gd is missing (Game.js fallback: no islands, a flat
## seabed, a sensible weather per id) or when the id is a dev course (race/DevCourse.gd).
## Same surface as the worlds/World.gd contract: build(id), height_at, terrain_at, def, update(dt).

var id := ""
var def: Dictionary = {}
var seabed := -50.0


func build(world_id: String, world_def: Dictionary = {}) -> void:
	id = world_id
	def = world_def
	if def.is_empty():
		def = {"id": id, "name": id.capitalize(), "start": {"x": 0.0, "z": 0.0, "heading": 0.0}, "portals": [], "gates": [], "laps": 0, "bounds": 900.0}
	seabed = float(def.get("seabed", -60.0 if def.get("underwater", false) else -50.0))


func height_at(_x: float, _z: float) -> float:
	return seabed


func terrain_at(_x: float, _z: float) -> Dictionary:
	return {"height": seabed, "land": false}


func update(_dt: float) -> void:
	pass
