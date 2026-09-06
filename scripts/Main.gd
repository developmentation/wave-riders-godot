extends Node3D
## Placeholder main scene: a flat sea plane and a box "boat" so the harness can be
## validated end to end. The ocean, boats and game flow replace this (see docs/GODOT-PORT.md).

var _boat: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	sea.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.35, 0.55)
	mat.roughness = 0.15
	mat.metallic = 0.2
	sea.material_override = mat
	add_child(sea)
	_boat = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.3, 1.0, 6.4)
	_boat.mesh = box
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.5, 0.1)
	_boat.material_override = bm
	_boat.position = Vector3(0, 0.3, 0)
	add_child(_boat)
	add_to_group("harness_state")


func _process(dt: float) -> void:
	_t += dt
	var thr := Input.get_action_strength("throttle")
	var steer := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	_boat.rotate_y(-steer * dt * 0.8)
	_boat.position += -_boat.transform.basis.z * thr * dt * 8.0
	_boat.position.y = 0.3 + sin(_t * 1.5) * 0.15


func get_harness_state() -> Dictionary:
	return {"pos": [snappedf(_boat.position.x, 0.01), snappedf(_boat.position.y, 0.01), snappedf(_boat.position.z, 0.01)]}
