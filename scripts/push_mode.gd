class_name PushMode
extends Node3D
# Push: the robot moves the barricade of whichever team stands next to it alone.

var main
var def: Dictionary
var robot_s := 0.0
var progress := [0.0, 0.0]
var controller := -1
var contested := false
var robot: Node3D
var barricades: Array = []


func setup(p_main, p_def: Dictionary) -> void:
	main = p_main
	def = p_def
	robot = _block(Vector3(4, 7, 4), Color(0.95, 0.95, 0.9), true)
	for t in 2:
		barricades.append(_block(Vector3(20, 3, 1.5), main.TEAM_COLORS[t], false))
	place()


func _block(size: Vector3, color: Color, glow: bool) -> Node3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.6
	m.material_override = mat
	m.layers = 2  # kept out of the satellite picture
	add_child(m)
	return m


func place() -> void:
	robot.position = main.path_pos(robot_s) + Vector3(0, 3.5, 0)
	for t in 2:
		var s: float = main.team_dir(t) * (progress[t] + 6.0)
		barricades[t].position = main.path_pos(s) + Vector3(0, 1.5, 0)


func tick(delta: float) -> void:
	var counts := [0, 0]
	var rp: Vector3 = main.path_pos(robot_s)
	for t in main.tanks:
		if t.global_position.distance_to(rp) <= float(def["capture_radius"]):
			counts[t.team] += 1
	for side in 2:
		counts[side] += main.landed_near(rp, float(def["capture_radius"]), side)
	contested = counts[0] > 0 and counts[1] > 0
	controller = -1
	if counts[0] > 0 and counts[1] == 0:
		controller = 0
	elif counts[1] > 0 and counts[0] == 0:
		controller = 1
	if controller >= 0:
		var dir: float = main.team_dir(controller)
		var r := robot_s * dir
		if r < progress[controller]:
			r = minf(r + float(def["return_speed"]) * delta, progress[controller])
		else:
			r += float(def["push_speed"]) * delta
			progress[controller] = r
		robot_s = r * dir
	place()
