class_name Camcorder
extends RefCounted
# The start menu's footage: the bots-only battle behind the menu, filmed as if by people who
# were there. It cuts between an aircraft circling a tank, action cameras bolted to a hull or
# a turret, and cameras worn by a soldier on his shoulder or clipped to his rifle.
# player_ctrl.gd calls update() every frame in place of its normal camera; menu.gd reads
# label, glitch, wide and tape to draw the tape look over the top.

const SHOTS := ["air", "helmet", "hull", "rifle", "air", "turret", "helmet"]
const NAMES := {"air": "AIR", "hull": "HULL", "turret": "TURRET", "helmet": "HELMET", "rifle": "RIFLE"}

var main
var only := ""      # test runs: film nothing but this kind of shot
var shot := ""
var label := ""
var glitch := 0.0   # 1 at a cut, fading: a burst of static and tearing
var wide := 0.0     # how much the lens bends the picture (action cameras)
var tape := 0.0     # seconds recorded, for the counter
var _left := 0.0
var _count := 0
var _tank: Tank
var _man: Soldier
var _orbit := 0.0
var _reach := 50.0
var _height := 30.0
var _side := 1.0
var _clock := 0.0
var _jolt := 0.0
var _last_reload := 0.0
var _noise := FastNoiseLite.new()
var _steady := Transform3D.IDENTITY  # the worn cameras' picture after steadying, before the rattle


func update(cam: Camera3D, delta: float) -> void:
	tape += delta
	_clock += delta
	_left -= delta
	glitch = move_toward(glitch, 0.0, delta * 2.5)
	_jolt = move_toward(_jolt, 0.0, delta * 5.0)
	if _left <= 0.0 or not _subject_ok():
		_cut()
	cam.near = 0.04
	match shot:
		"air":
			_air(cam, delta)
		"hull", "turret":
			_mounted(cam)
		"helmet", "rifle":
			_worn(cam, delta)


func _subject_ok() -> bool:
	if shot == "helmet" or shot == "rifle":
		return _man != null and is_instance_valid(_man) and _man.state != "dead"
	return _tank != null and is_instance_valid(_tank)


# Cuts to the next kind of shot, on someone who is in the thick of it if anyone is.
func _cut() -> void:
	_count += 1
	shot = SHOTS[_count % SHOTS.size()] if only == "" else only
	_man = null
	if shot == "helmet" or shot == "rifle":
		var men: Array = main.soldiers.filter(func(s): return s.state == "up")
		var busy: Array = men.filter(func(s): return s.foe != null and is_instance_valid(s.foe))
		if not busy.is_empty():
			men = busy
		if men.is_empty() or (shot == "rifle" and busy.is_empty()):
			shot = "air"  # (the rifle camera is only worth watching on a man who is aiming at someone)
		else:
			_man = men[randi() % men.size()]
	if _man == null:
		var tanks: Array = main.tanks.duplicate()
		var busy: Array = tanks.filter(func(t): return t.reload_left > 0.0 or t.hp < t.max_hp)
		if not busy.is_empty():
			tanks = busy
		_tank = null if tanks.is_empty() else tanks[randi() % tanks.size()]
		if _tank != null:
			_last_reload = _tank.reload_left
	_left = randf_range(7.0, 11.0)
	_orbit = randf() * TAU
	_reach = randf_range(42.0, 70.0)
	_height = randf_range(22.0, 40.0)
	_side = 1.0 if randf() < 0.5 else -1.0
	if shot == "hull" or shot == "turret":
		_side = -1.0  # mounted on the left, so the turret and gun fill the right of the picture, clear of the menu
	glitch = 1.0
	label = "CAM %d  %s" % [SHOTS.find(shot) + 1, NAMES[shot]]
	if _man == null and _tank != null:
		label += "   " + String(_tank.def["name"]).to_upper()


# A long lens from an aircraft circling overhead: slow drift, a hand that is not quite
# steady, and a zoom that keeps hunting.
func _air(cam: Camera3D, delta: float) -> void:
	if _tank == null:
		return
	_orbit += delta * 0.07 * _side
	var focus := _tank.global_position + Vector3(0, 2.0, 0)
	# Over the city it flies higher and looks down more steeply, to see into the streets
	# between the tall blocks.
	var downtown: bool = main.map.in_downtown(focus.x, focus.z)
	var eye := focus + Vector3(sin(_orbit), 0, cos(_orbit)) * (_reach * (0.55 if downtown else 1.0)) + Vector3(0, _height + (58.0 if downtown else 0.0), 0)
	eye.y = maxf(eye.y, main.map.height(eye.x, eye.z) + 4.0)
	var hand := Vector3(_noise.get_noise_2d(_clock * 22.0, 0.0), _noise.get_noise_2d(0.0, _clock * 22.0), _noise.get_noise_2d(_clock * 22.0, 50.0))
	cam.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(focus + hand * 2.2, Vector3.UP)
	cam.rotate_object_local(Vector3.FORWARD, _noise.get_noise_2d(_clock * 9.0, 90.0) * 0.05)
	cam.fov = 24.0 + sin(_clock * 0.45) * 4.0 + _noise.get_noise_2d(_clock * 30.0, 20.0) * 1.5
	wide = 0.0


# An action camera bolted on: it keeps its place on the vehicle whatever the vehicle does,
# buzzes with the engine and jumps when the gun fires.
func _mounted(cam: Camera3D) -> void:
	if _tank == null:
		return
	var w := float(_tank.def["width"])
	var l := float(_tank.def["length"])
	if _tank.reload_left > _last_reload + 0.05:
		_jolt = 1.0
	_last_reload = _tank.reload_left
	var at: Transform3D
	if shot == "hull":
		# On a bracket off the rear corner of the hull, outside the widest turret, looking
		# forward along the side with the turret and gun in the picture.
		var from := Vector3(_side * (w * 0.5 + 0.35), _tank.hull_top + 0.55, l * 0.46)
		at = _tank.global_transform * Transform3D(Basis.looking_at(Vector3(-_side * w * 0.15, _tank.hull_top + 0.8, -l) - from), from)
	else:
		# On the turret roof beside the gun, turning and looking wherever it does.
		var from := Vector3(_side * w * 0.3, _tank.turret_h + 0.75, 0.9)
		at = _tank.turret.global_transform * Transform3D(Basis.looking_at(Vector3(-_side * w * 0.25, _tank.turret_h * 0.3, -l * 1.4) - from), from)
	var buzz := 0.003 + absf(_tank.speed) * 0.0011 + _jolt * 0.05
	at.basis = at.basis * Basis.from_euler(Vector3(_noise.get_noise_2d(_clock * 900.0, 0.0) * buzz + _jolt * 0.05, _noise.get_noise_2d(0.0, _clock * 900.0) * buzz, _noise.get_noise_2d(_clock * 900.0, 70.0) * buzz))
	cam.global_transform = at.orthonormalized()
	cam.fov = 100.0
	wide = 0.4


# A camera a soldier is wearing. It moves as he moves; a little of the jolting is smoothed
# out, the way such a camera's own stabiliser would.
func _worn(cam: Camera3D, delta: float) -> void:
	if shot == "rifle" and not (_man.foe != null and is_instance_valid(_man.foe)):
		_left = minf(_left, 1.2)  # his fight is over: cut away rather than watch him run
	if _man.state != "up":
		_left = minf(_left, 2.0)  # he is hit: the picture stays on the ground a moment, then cuts
	var mount: Node3D = _man.model.shoulder_cam if shot == "helmet" else _man.model.gun_cam
	# The steadied picture is kept apart from the camera, and the rattle below is put on top
	# of it fresh each frame. (Steadying the camera itself fed each frame's rattle back into
	# the next, which made the helmet picture twitch.)
	var want := mount.global_transform.orthonormalized()
	if glitch > 0.9 or _steady == Transform3D.IDENTITY:
		_steady = want
	else:
		_steady = Transform3D(_steady.basis.slerp(want.basis, clampf(delta * 14.0, 0.0, 1.0)).orthonormalized(), _steady.origin.lerp(want.origin, clampf(delta * 30.0, 0.0, 1.0)))
	cam.global_transform = _steady
	if shot == "helmet":
		# A helmet is never still: it nods and rattles, more so on the run.
		var rattle := 0.01 + 0.022 * _man.model.run
		cam.rotate_object_local(Vector3.RIGHT, _noise.get_noise_2d(_clock * 260.0, 10.0) * rattle + sin(_man.model.stride * 2.0) * 0.022 * _man.model.run)
		cam.rotate_object_local(Vector3.UP, _noise.get_noise_2d(_clock * 200.0, 40.0) * rattle)
		cam.rotate_object_local(Vector3.FORWARD, _noise.get_noise_2d(_clock * 170.0, 80.0) * rattle * 1.5 + sin(_man.model.stride) * 0.03 * _man.model.run)
	cam.fov = 100.0 if shot == "helmet" else 88.0
	cam.near = 0.2 if shot == "helmet" else 0.04  # nothing nearer than 20 cm is drawn: that is his own helmet
	wide = 0.4
