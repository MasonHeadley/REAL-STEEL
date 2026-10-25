class_name PlayerCtrl
extends Node3D
# Camera and input for the local player's vehicle. Keys come from the bindings in settings.gd.
# phase says what the camera is doing:
#   idle     no vehicle: drifting high over the map behind the spawn screen
#   drop     just deployed: swooping down from the sky onto the vehicle
#   play     normal control (third person, gunner's sight, free look)
#   killcam  just died: watching whoever did it

const FOV_NORMAL := 60.0
const FOV_SNIPER := 12.0
const FOV_SNIPER_ARTILLERY := 30.0
const NUMBER_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
const DROP_HEIGHT := 380.0
const DROP_SECONDS := 2.6
const ZOOM_NEAR := 6.0
const ZOOM_FAR := 36.0
const KILLCAM_SECONDS := 6.2
const REDEPLOY_SECONDS := 5.0  # how long the black "redeploying" screen stays up
const KILL_LINGER := 1.0      # seconds the camera stays on your own wreck before it fades over to whoever did it
var kill_fade := 0.0          # 0 clear .. 1 black: the fade between the two
const ZERO_STEP := 25.0
const ZERO_MAX := 1200.0

var main
var tank: Tank
var cam: Camera3D
var phase := "idle"
var yaw := PI
var pitch := -0.18
var auto := false  # camera follows a bot (self-test and screenshots)
var demo := false  # start menu: the battle is filmed by the camcorder, no input
var air: Aircraft       # the aircraft the player is flying, when in the air
var man: Soldier        # the infantryman the player is, when on foot
var camcorder := Camcorder.new()
var spec_mode := 2      # spectating: 0 free camera, 1 a vehicle's gun view, 2 circling a vehicle
var spec_i := 0         # which vehicle is being watched
var _spec_pos := Vector3.ZERO
var _spec_reach := 18.0
var _spec_set := false
var _drone_hid := false
var shell_eta := 0.0     # artillery: seconds until the shell just fired comes down
var _eta_reload := 0.0
var spec_outline := true   # spectating: draw every vehicle's outline in its team's colour
var _outline_mats := {}
var force_sniper := false
var sniper := false
var sniper_toggle := false
var _aim_on_unit := false     # the crosshair is on a vehicle or a wreck
var _aimed := Vector3.ZERO    # the spot the gun was last laid on
var _was_look := false
var freelook := false
var emote_open := false
var ping_open := false
var ping_vec := Vector2.ZERO
var ping_point := Vector3.ZERO
const PING_TAP := 0.22   # holding the ping button longer than this opens the order wheel
var ping_held := 0.0
var _last_tap := 0
var drone := false       # artillery: the gunner's sight is a view from above the target area
var drone_point := Vector3.ZERO  # where on the ground the gun is being laid
var drone_height := 150.0   # how high the drone flies above the gun; the wheel changes it
var aim_dist := -1.0
const RANGING_SECONDS := 0.9
const RANGE_SHOWN_SECONDS := 8.0
var ranging := 0.0     # seconds until the rangefinder gives its answer
var ranged := -1.0     # the last range it gave, metres
var _ranged_t := 0.0   # how long that answer stays on the sight
var magnified := false # the gunner's sight is on its high magnification
var impact = null  # where an artillery shell would land right now
var kill_text := ""
var _pivot := Vector3(0, 60, 0)
var _held_view := Vector2.ZERO
var _phase_t := 0.0
var zoom := 13.0  # third-person camera distance, set with the mouse wheel
var _killer
var _death_pos := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps the camera drifting behind the menus
	cam = Camera3D.new()
	cam.far = 12000.0  # far enough to see the hills on the horizon
	cam.fov = FOV_NORMAL
	add_child(cam)
	cam.make_current()


func attach(t: Tank) -> void:
	tank = t
	yaw = t.heading
	pitch = -0.18
	sniper_toggle = false
	freelook = false
	emote_open = false
	ping_open = false
	if auto:
		phase = "play"
		return
	if main.mode["kind"] == "range":
		# No ceremony on the test range: straight into the seat.
		phase = "play"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	phase = "drop"
	_phase_t = 0.0
	Sfx.play_ui("whoosh", -6.0, 0.6)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func start_killcam(killer, death_pos: Vector3, text: String) -> void:
	if auto:
		phase = "idle"
		return
	if main.redeploying:
		# Asked for from the pause menu: no kill camera, a few seconds of black, then the deploy screen.
		phase = "redeploy"
		_phase_t = 0.0
		sniper = false
		return
	phase = "killcam"
	_phase_t = 0.0
	_killer = killer
	_death_pos = death_pos
	kill_text = text
	sniper = false
	emote_open = false
	ping_open = false


# The player is flying: the camera follows the aircraft and the controls go to it.
#   helicopter  W S forward and back, A D sideways, Space up, Ctrl down, mouse turns it
#   plane       the mouse points where it should fly, W S throttle
#   both        left mouse guns, right mouse rockets
func attach_air(a: Aircraft) -> void:
	air = a
	tank = null
	man = null
	yaw = a.yaw
	pitch = -0.12
	phase = "play"
	intro_t = -1.0
	_intro_wait = not a.heli and not auto  # a plane's flight opens with a fly-past
	if not auto:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func has_air() -> bool:
	return air != null and is_instance_valid(air)


# ---- the fly-past that opens a flight in a plane ----
# One of three shots, picked at random: the camera waits out ahead among the clouds, the
# plane tears past it, and the camera swings after it and catches up. The controls come back
# a moment before it has caught up, so by the time the picture settles you are already flying.
const INTRO_PASS := 1.6       # seconds from the start to the plane passing the camera (the sound is cut to match)
const INTRO_HANDOVER := 2.7   # when the controls come back
const INTRO_SECONDS := 3.3    # when the camera has caught up
var intro_t := -1.0           # how far into it we are; -1 when there is none
var _intro_wait := false      # one is owed, as soon as the round is under way
var _intro_cam := Vector3.ZERO
var _intro_clouds: Node3D


func _start_air_intro() -> void:
	_intro_wait = false
	intro_t = 0.0
	var nose: Vector3 = air.facing * Vector3.FORWARD
	var side := nose.cross(Vector3.UP).normalized()
	var meet: Vector3 = air.global_position + nose * air.speed * INTRO_PASS  # where it will be as it passes
	match randi() % 3:
		0:
			_intro_cam = meet + side * 16.0 - Vector3(0, 4.0, 0)       # low and to one side: it goes by close overhead
		1:
			_intro_cam = meet + Vector3(0, 24.0, 0) - side * 8.0       # from above: it passes underneath
		_:
			_intro_cam = meet + nose * 45.0 - Vector3(0, 7.0, 0) + side * 5.0  # head on: it comes straight at the camera and over
	# A few big soft clouds for it to come through.
	_intro_clouds = Node3D.new()
	main.add_child(_intro_clouds)
	var puff := StandardMaterial3D.new()
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.albedo_color = Color(1, 1, 1, 0.55)
	puff.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	MeshUtil.as_puffs(puff)
	for k in 14:
		var cloud := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * randf_range(50.0, 120.0)
		cloud.mesh = quad
		cloud.material_override = puff
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_intro_clouds.add_child(cloud)
		cloud.global_position = meet + nose * randf_range(-140.0, 260.0) + side * randf_range(-120.0, 120.0) * (1.0 if k % 2 == 0 else -1.0) + Vector3(0, randf_range(-45.0, 30.0), 0)
		if cloud.global_position.distance_to(_intro_cam) < 40.0:
			cloud.global_position += side * 60.0
	Sfx.play_ui("propby" if AircraftModel.SHAPES[String(air.def["id"])].has("prop") else "jetby", 0.0, 1.0, "Engine")


var first_person := false  # the view is from the pilot's seat, or through the soldier's eyes
var _cockpit := {}         # the cockpit interior being shown (see AircraftModel.cockpit)
var _cockpit_in: Aircraft
var _view_gun: Node3D      # the weapon and arms drawn in front of the camera for a soldier in first person
var _view_kind := ""
var _view_at := Vector3(0.17, -0.19, -0.38)


# Puts the cockpit interior into the aircraft (and takes its glazing away so you can see
# out), or takes the interior out again and puts the glazing back.
func _show_cockpit(on: bool) -> void:
	var here: bool = not _cockpit.is_empty() and is_instance_valid(_cockpit["root"])
	if on and here and _cockpit_in == air:
		return
	if here:
		_cockpit["root"].queue_free()
		if _cockpit_in != null and is_instance_valid(_cockpit_in):
			for part in _cockpit_in._model.get_children():
				if part.has_meta("canopy"):
					part.visible = true
	_cockpit = {}
	_cockpit_in = null
	if on and has_air():
		_cockpit = CockpitModel.build(String(air.def["id"]))
		air.add_child(_cockpit["root"])
		_cockpit["root"].position = AircraftModel.pilot_eye(String(air.def["id"]))
		_cockpit_in = air
		for part in air._model.get_children():
			if part.has_meta("canopy"):
				part.visible = false


# Moves the stick and the lever with the controls, flashes the warning lamps, and writes
# the figures on the screens.
func _work_cockpit() -> void:
	var w: Dictionary = air.want
	var move: Vector3 = w.get("move", Vector3.ZERO)
	var stick: Node3D = _cockpit["stick"]
	var lever: Node3D = _cockpit["lever"]
	if air.heli:
		stick.rotation = stick.rotation.lerp(Vector3(move.z * 0.28, 0, -move.x * 0.28), 0.2)
		lever.rotation.x = lerpf(lever.rotation.x, -float(w.get("lift", 0.0)) * 0.5, 0.2)
	else:
		# The stick goes the way the nose is being pulled.
		var pull: Vector3 = air.global_transform.basis.inverse() * (w.get("aim_dir", -air.global_transform.basis.z) as Vector3)
		stick.rotation = stick.rotation.lerp(Vector3(clampf(pull.y * 1.6, -0.35, 0.35), 0, clampf(-pull.x * 1.6, -0.35, 0.35)), 0.2)
		lever.rotation.x = lerpf(0.45, -0.45, air.throttle)
	var lit: bool = air.threat_t > 0.0 and int(main.elapsed * (14.0 if air.threat_dist < 100.0 else 5.0)) % 2 == 0
	for lamp in _cockpit["lamps"]:
		lamp.material_override = _cockpit["lamp_on"] if lit else _cockpit["lamp_off"]
	var text: Array = _cockpit["text"]
	var height := int(air.global_position.y - main.map.height(air.global_position.x, air.global_position.z))
	var heading := int(fposmod(-rad_to_deg(air.yaw), 360.0))
	if text.size() >= 2:
		# The screen: flight figures on the left half, weapons on the right.
		text[0].text = "SPD %3d\nALT %3d\nHDG %03d\n%s" % [int(air.speed * 3.6), height, heading, "MISSILE" if air.threat_t > 0.0 else "RWR OK"]
		text[1].text = "RKT %2d\nFLR %2d\nGUN OK\n%s" % [air.rockets, air.flares, ("%d M" % int(air_range)) if air_range > 0.0 else "NO TGT"]
	# The dials that are live: airspeed, height and heading. Each needle goes once round its dial over the range given.
	var needles: Dictionary = _cockpit.get("needles", {})
	if needles.has("speed"):
		needles["speed"].rotation.z = -TAU * 0.85 * clampf(air.speed / (float(air.def["speed"]) * 1.1), 0.0, 1.0)
	if needles.has("alt"):
		needles["alt"].rotation.z = -TAU * fposmod(float(height) / 300.0, 1.0)
	if needles.has("hdg"):
		needles["hdg"].rotation.z = deg_to_rad(float(heading))


var air_free := false     # looking about without steering (the free look key is held)
var _free_yaw := 0.0
var _free_pitch := 0.0
var air_range := 0.0      # metres to whatever the helicopter's sight is on

func _air_view() -> void:
	if _intro_wait and main.prep_t <= 0.0:
		_start_air_intro()
	# Where the aircraft is told to go and shoot is `aim`. The camera normally looks the same
	# way; holding free look turns the camera alone, and letting go snaps it back.
	air_free = not auto and Input.is_action_pressed("air_freelook")
	if not air_free:
		_free_yaw = 0.0
		_free_pitch = 0.0
	if intro_t >= 0.0 and intro_t < INTRO_HANDOVER:
		# Until the controls come back the plane flies itself, straight on, and the view lines up behind it.
		yaw = air.yaw
		pitch = -0.12
	var aim := Basis.from_euler(Vector3(pitch, yaw, 0))
	var look := Basis.from_euler(Vector3(clampf(pitch + _free_pitch, -1.4, 1.4), yaw + _free_yaw, 0))
	var eye := air.global_position + Vector3(0, 3.0, 0)
	var zoom := not auto and not air_free and Input.is_action_pressed("air_zoom")
	var back := Vector3(0, 3.5, 17.0 if air.heli else 21.0)
	var chase := Transform3D(look, eye + look * back)
	cam.global_transform = chase
	cam.fov = lerpf(cam.fov, 26.0 if zoom else FOV_NORMAL, 0.25)
	if not auto and Input.is_action_just_pressed("air_view"):
		first_person = not first_person
	if main.args.has("--firstperson"):
		first_person = true  # (for test pictures)
	var inside: bool = first_person and not air.dying and not air.wrecked and intro_t < 0.0
	_show_cockpit(inside)
	if inside:
		# From the pilot's seat. In a plane the view is fixed to the aircraft (it rolls and
		# pitches with it); in a helicopter the head turns with the aim. Free look turns the head.
		var seat: Vector3 = air.to_global(AircraftModel.pilot_eye(String(air.def["id"])))
		var head := Basis.from_euler(Vector3(_free_pitch, _free_yaw, 0))
		chase = Transform3D((aim if air.heli else air.global_transform.basis) * head, seat)
		cam.global_transform = chase
		cam.near = 0.04
		_work_cockpit()
	else:
		cam.near = 0.3
	if air.dying or air.wrecked:
		# Shot down: nothing to do but watch it go, from a little further back.
		cam.global_transform = Transform3D(look, eye + look * (back * 1.5)).looking_at(eye, Vector3.UP)
		return
	if intro_t >= 0.0:
		intro_t += get_process_delta_time()
		# The camera stays put, turning to follow the plane past, then flies after it.
		var fixed := Transform3D(Basis.IDENTITY, _intro_cam).looking_at(air.global_position, Vector3.UP)
		cam.global_transform = fixed.interpolate_with(chase, smoothstep(INTRO_PASS + 0.15, INTRO_SECONDS, intro_t))
		cam.fov = FOV_NORMAL
		if intro_t >= INTRO_SECONDS:
			intro_t = -1.0
			if _intro_clouds != null and is_instance_valid(_intro_clouds):
				get_tree().create_timer(6.0).timeout.connect(_intro_clouds.queue_free)
		elif intro_t < INTRO_HANDOVER:
			air.want = {}
			return
	if auto:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# What is under the middle of the screen (when not looking about): a helicopter's guns and
	# rockets are turned to hit exactly that.
	var sight_from := cam.global_position if inside else eye + aim * back
	var sight_dir := aim * Vector3.FORWARD
	var q := PhysicsRayQueryParameters3D.create(sight_from + sight_dir * 20.0, sight_from + sight_dir * 1200.0, 1 | 2 | 4 | 8)
	q.exclude = [air.get_rid()]
	var hit := air.get_world_3d().direct_space_state.intersect_ray(q)
	var aim_at: Vector3 = hit["position"] if not hit.is_empty() else sight_from + sight_dir * 1200.0
	air_range = sight_from.distance_to(aim_at) if not hit.is_empty() else 0.0
	# The sight button fires rockets, unless this is a plane with heat-seeking missiles
	# aboard: then it switches the seeker on, and the fire button looses a missile once it has a lock.
	var sight_held: bool = captured and Input.is_action_pressed("sight")
	var seeking: bool = sight_held and not air.heli and air.missiles > 0
	air.want = {
		"move": Vector3(Input.get_action_strength("right") - Input.get_action_strength("left"), 0, Input.get_action_strength("back") - Input.get_action_strength("forward")),
		"lift": Input.get_action_strength("air_up") - Input.get_action_strength("air_down"),
		"yaw": yaw, "aim_from": cam.global_position, "aim_dir": sight_dir, "aim_at": aim_at,
		"fire": captured and Input.is_action_pressed("fire"), "rocket": sight_held and not seeking, "bomb": Input.is_action_pressed("air_bomb"),
		"seek": seeking, "missile": seeking and Input.is_action_pressed("fire"), "flare": Input.is_action_pressed("air_flare"),
	}

# The player has deployed on foot: the camera and the controls go to that man.
func attach_man(s: Soldier) -> void:
	man = s
	tank = null
	yaw = s.rotation.y
	pitch = -0.05
	phase = "play"
	if not auto:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func has_man() -> bool:
	return man != null and is_instance_valid(man) and man.state == "up"


var _lying := false  # the player's man is lying down (toggled with Z)
var _z_was := false

func _man_controls() -> void:
	if auto:
		return  # a test is working him
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var aim := -cam.global_transform.basis.z
	# Z drops him flat and gets him up again; sprinting or crouching also gets him up.
	if man.want.is_empty():
		_lying = false  # a fresh man starts on his feet
	var z_down := Input.is_action_pressed("inf_prone")
	if z_down and not _z_was:
		_lying = not _lying
	_z_was = z_down
	if Input.is_action_pressed("inf_sprint") or Input.is_action_pressed("inf_crouch") or Input.is_action_pressed("inf_jump"):
		_lying = false
	man.want = {
		"prone": _lying,
		"move": Vector3(Input.get_action_strength("right") - Input.get_action_strength("left"), 0, Input.get_action_strength("back") - Input.get_action_strength("forward")),
		"sprint": Input.is_action_pressed("inf_sprint"), "crouch": Input.is_action_pressed("inf_crouch"), "jump": Input.is_action_pressed("inf_jump"),
		"yaw": yaw, "pitch": pitch,
		"fire": captured and Input.is_action_pressed("fire"), "aim": captured and Input.is_action_pressed("sight"),
		"use": Input.is_action_pressed("inf_use"), "throw": Input.is_action_pressed("inf_grenade"), "reload": Input.is_action_pressed("inf_reload"),
		"weapon": 1 if Input.is_action_pressed("inf_primary") else (2 if Input.is_action_pressed("inf_pistol") else (3 if Input.is_action_pressed("inf_special") else 0)),
		"aim_from": cam.global_position, "aim_dir": aim,
	}


# Over the man's right shoulder, closer in and narrower when he aims; pulled in if a wall is behind him.
# The weapon and a pair of arms, drawn fixed in front of the camera for a soldier seen
# through his own eyes (his body is hidden from his own view; everyone else still sees it).
# It sits low and to the right, comes up to the eye when aiming, bobs as he walks, jumps
# back when he fires and dips out of sight while he reloads.
var scope_view := false    # looking through the 4x scope: the HUD draws the scope's black surround and reticle
var ads := 0.0             # 0 weapon at the hip .. 1 fully up at the eye

func _show_view_gun(delta: float) -> void:
	var kind: String = man.model._kinds.get(man.weapon if man.model._kinds.has(man.weapon) else 1, "rifle")
	var sight: String = man.sight if (kind == "rifle" or kind == "carbine") else kind
	if _view_gun == null or not is_instance_valid(_view_gun) or kind != _view_kind:
		if _view_gun != null and is_instance_valid(_view_gun):
			_view_gun.queue_free()
		_view_kind = kind
		_view_gun = Node3D.new()
		cam.add_child(_view_gun)
		var piece := WeaponModel.build(kind, man.sight)
		piece.rotation.y = PI  # weapons are modelled pointing +Z; the camera looks along -Z
		_view_gun.add_child(piece)
		# His arms: modelled ones, sleeves in his side's colour, dark gloves.
		var sleeve := MeshUtil.material(SoldierModel.PLASTIC[man.team].darkened(0.12), 0.9)
		var glove := MeshUtil.material(Color(0.09, 0.09, 0.1), 0.75)
		# Right hand round the grip, the forearm running back, down and out to the right.
		var right := WeaponModel.arm(false, sleeve, glove)
		right.transform = Transform3D(Basis(Vector3.UP, 0.28) * Basis(Vector3.RIGHT, 0.75) * Basis(Vector3.BACK, 1.35), Vector3(0.04, -0.12, 0.1))
		_view_gun.add_child(right)
		# Left hand: under the fore-end, palm up; or wrapped round the right hand on a pistol.
		var left := WeaponModel.arm(true, sleeve, glove)
		match kind:
			"pistol":
				left.transform = Transform3D(Basis(Vector3.UP, -0.45) * Basis(Vector3.RIGHT, 0.75) * Basis(Vector3.BACK, -1.2), Vector3(-0.045, -0.12, 0.09))
			"launcher":
				left.transform = Transform3D(Basis(Vector3.UP, -0.6) * Basis(Vector3.RIGHT, 0.8) * Basis(Vector3.BACK, -1.3), Vector3(0.0, -0.02, 0.33))
			_:
				var reach := -0.2 if kind == "carbine" else (-0.3 if kind == "machine_gun" else -0.22)
				left.transform = Transform3D(Basis(Vector3.UP, -0.42) * Basis(Vector3.RIGHT, 0.8) * Basis(Vector3.BACK, PI * 0.92), Vector3(-0.06, -0.075 if kind != "machine_gun" else -0.1, reach + 0.085))
		_view_gun.add_child(left)
	var aiming: bool = man.want.get("aim", false) and man.reloading <= 0.0
	ads = move_toward(ads, 1.0 if aiming else 0.0, delta * 6.5)
	# At the hip it sits low and to the right; aiming, it comes up until the sight is in front of the eye.
	var hip := Vector3(0.15, -0.17, -0.34)
	var eye_dist: float = {"iron": -0.3, "holo": -0.28, "acog": -0.115, "pistol": -0.42, "machine_gun": -0.22, "launcher": -0.15}.get(sight, -0.22)
	var up := Vector3(0.0, -float(WeaponModel.SIGHT_LINE.get(sight, 0.07)), eye_dist)
	if kind == "launcher":
		hip = Vector3(0.14, -0.22, -0.18)
		up = Vector3(0.11, -0.17, -0.12)
	var moving: bool = (man.want.get("move", Vector3.ZERO) as Vector3).length() > 0.1
	var sprinting: bool = man.want.get("sprint", false) and moving and ads < 0.2
	var ease := ads * ads * (3.0 - 2.0 * ads)
	var busy := 1.0 if (man.reloading > 0.0 or (man.weapon == 3 and man._fire_t > 0.4)) else 0.0
	var down: float = _view_gun.get_meta("down", 0.0)
	down = move_toward(down, busy, delta * 4.0)
	_view_gun.set_meta("down", down)
	var tuck: float = _view_gun.get_meta("tuck", 0.0)
	tuck = move_toward(tuck, 1.0 if sprinting else 0.0, delta * 5.0)
	_view_gun.set_meta("tuck", tuck)
	var stride: float = man.model.stride
	var run: float = man.model.run * (1.0 - ease * 0.8)
	var kick: float = man.model.kick
	_view_gun.position = hip.lerp(up, ease) + Vector3(cos(stride) * 0.007 * run - 0.05 * tuck, absf(sin(stride)) * 0.009 * run - down * 0.24 - 0.06 * tuck, kick * (0.018 if ease > 0.5 else 0.035))
	_view_gun.rotation = Vector3(kick * (0.012 if ease > 0.5 else 0.05) - down * 0.75 - 0.3 * tuck, (1.0 - ease) * 0.045 + 0.5 * tuck, down * 0.4 + 0.25 * tuck)
	# The 4x scope: once it is up at the eye the view is through it.
	scope_view = sight == "acog" and ease > 0.92
	_view_gun.visible = not scope_view
	cam.fov = lerpf(cam.fov, 17.5 if scope_view else lerpf(FOV_NORMAL, 52.0, ease), 0.5 if scope_view else 0.3)

func _hide_view_gun() -> void:
	if _view_gun != null and is_instance_valid(_view_gun):
		_view_gun.queue_free()
	_view_gun = null
	_view_kind = ""
	scope_view = false
	ads = 0.0
	cam.near = 0.3


func _man_camera() -> void:
	if not auto and Input.is_action_just_pressed("inf_view"):
		first_person = not first_person
	if main.args.has("--firstperson"):
		first_person = true
	man.model.visible = not first_person
	if first_person:
		# Through his own eyes.
		var seeing := Basis.from_euler(Vector3(pitch, yaw, 0))
		cam.global_transform = Transform3D(seeing, man.eye() + Vector3(0, 0.06, 0) + seeing * Vector3(0, 0, -0.08))
		cam.near = 0.02
		_show_view_gun(get_process_delta_time())
		return
	_hide_view_gun()
	var aiming: bool = man.want.get("aim", false)
	var look := Basis.from_euler(Vector3(pitch, yaw, 0))
	var eye := man.eye() + Vector3(0, 0.15, 0)
	var back := look * Vector3(0.55, 0.2, 1.3 if aiming else 3.0)
	var q := PhysicsRayQueryParameters3D.create(eye, eye + back, 1 | 4)
	var hit := man.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		back = back.normalized() * maxf(eye.distance_to(hit["position"]) - 0.3, 0.3)
	cam.global_transform = Transform3D(look, eye + back)
	cam.fov = lerpf(cam.fov, 38.0 if aiming else FOV_NORMAL, 0.25)


func has_tank() -> bool:
	return tank != null and is_instance_valid(tank)


func in_control() -> bool:
	return phase == "play" and has_tank()


# Which slice of the ping wheel the cursor is in, or -1 while it sits in the middle.
func ping_choice() -> int:
	if ping_vec.length() < 38.0:
		return -1
	var n: int = GameData.ping_order.size()
	var a := fposmod(atan2(ping_vec.x, -ping_vec.y), TAU)  # 0 = up, clockwise
	return int(fposmod(a + PI / n, TAU) / (TAU / n)) % n


func _unhandled_input(e: InputEvent) -> void:
	if auto or demo or get_tree().paused:
		return
	if main.spectating:
		_spectate_input(e)
		return
	if has_air():
		if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and air_free:
			# Free look: the mouse turns the camera only; the aircraft keeps its heading.
			_free_yaw -= e.relative.x * 0.0022 * Settings.sensitivity
			_free_pitch = clampf(_free_pitch - e.relative.y * 0.0022 * Settings.sensitivity, -1.4, 1.4)
		elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var fine := cam.fov / FOV_NORMAL  # slower while zoomed in
			yaw -= e.relative.x * 0.0022 * Settings.sensitivity * fine
			pitch = clampf(pitch - e.relative.y * 0.0022 * Settings.sensitivity * fine, -1.3, 1.3)
		elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if has_man():
		# On foot: the mouse looks about; everything else is read as held keys (see _man_controls).
		if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var slow := (0.55 if man.want.get("aim", false) else 1.0) * (cam.fov / FOV_NORMAL if first_person else 1.0)  # (slower still through a scope)
			yaw -= e.relative.x * 0.0025 * Settings.sensitivity * slow
			pitch = clampf(pitch - e.relative.y * 0.0025 * Settings.sensitivity * slow, -1.2, 1.2)
		elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if drone and e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		drone_height = clampf(drone_height * (0.87 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.15), 50.0, 420.0)
		return
	if e is InputEventMouseMotion:
		if captured and ping_open and ping_held >= PING_TAP:
			ping_vec = (ping_vec + e.relative).limit_length(130.0)
		elif captured and drone and phase == "play":
			# The mouse slides the aiming point over the ground: up the screen is away from the gun.
			var away := Vector3(-sin(yaw), 0, -cos(yaw))
			drone_point += (away.cross(Vector3.UP) * e.relative.x - away * e.relative.y) * 0.0023 * drone_height * Settings.sensitivity
			var reach := drone_point - tank.global_position
			reach.y = 0.0
			drone_point = tank.global_position + reach.limit_length(float(tank.current_shell()["velocity"]) ** 2 / GameData.SHELL_GRAVITY * 0.97)
		elif captured and phase == "play":
			var sens := 0.0025 * cam.fov / FOV_NORMAL * Settings.sensitivity
			yaw -= e.relative.x * sens
			pitch = clampf(pitch - e.relative.y * sens, -1.2, 1.5 if (has_tank() and tank.def.has("aa")) else 0.6)
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ENTER and main.match_over and main.netplay == null:
		main.restart(true)
		return
	if e is InputEventKey and e.pressed and not e.echo and main.mode["kind"] == "range":
		# Test range keys.
		if e.keycode == KEY_F1 and main.args.has("--dev"):
			main.sound_board.toggle()
			return
		if e.keycode == KEY_F2:
			main.recall_player()
			return
		if e.keycode == KEY_F3:
			main.range_infantry()
			return
	if not in_control():
		return
	if e is InputEventMouseButton and e.pressed:
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		# The wheel sets the sight zero in the gunner's sight, and the camera distance outside it.
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var up: bool = e.button_index == MOUSE_BUTTON_WHEEL_UP
			if sniper:
				var lowest := 50.0 if tank.def["class"] == "artillery" else 0.0
				tank.zero_range = clampf(tank.zero_range + (ZERO_STEP if up else -ZERO_STEP), lowest, ZERO_MAX)
			else:
				zoom = clampf(zoom * (0.88 if up else 1.14), ZOOM_NEAR, ZOOM_FAR)
			return
	if e is InputEventKey and e.pressed and not e.echo:
		var n: int = NUMBER_KEYS.find(e.keycode)
		if n >= 0:
			if emote_open:
				if n < GameData.emote_order.size():
					main.send_emote(tank, GameData.emote_order[n])
				emote_open = false
			elif n < tank.def["shells"].size():
				tank.shell_index = n
			return
	if e.is_action_pressed("radar") and tank.def.has("aa"):
		# Radar off: the aerial stops, the aircraft markers go, and enemy pilots can no longer see it.
		tank.radar_on = not tank.radar_on
		main.show_msg("Radar on" if tank.radar_on else "Radar off  -  aircraft cannot see you, and you cannot see them")
		return
	if e.is_action_pressed("sight_toggle"):
		sniper_toggle = not sniper_toggle
	elif e.is_action_pressed("ability"):
		if main.net_client:
			main.netplay.ask_ability()
		else:
			tank.use_ability()
	elif e.is_action_pressed("emote"):
		emote_open = not emote_open
	elif e.is_action_pressed("rangefind") and drone:
		tank.high_arc = not tank.high_arc  # in the drone view this key swaps the flat shot for the lobbed one
	elif e.is_action_pressed("rangefind"):
		# The rangefinder takes a moment, then shows the range. Setting the sight to it is
		# up to the gunner (the wheel).
		ranging = RANGING_SECONDS
		ranged = -1.0
	elif e.is_action_pressed("ping") and captured:
		ping_open = true
		ping_held = 0.0
		ping_vec = Vector2.ZERO
		ping_point = drone_point if drone else _range_under_crosshair()
	elif e.is_action_released("ping") and ping_open and ping_held < PING_TAP:
		# A tap, not a hold. One tap leaves a marker; a second straight after makes it an attack order.
		ping_open = false
		var now := Time.get_ticks_msec()
		if now - _last_tap < 400:
			main.issue_ping(tank, "attack", ping_point)
		else:
			main.mark_ping(tank, ping_point)
		_last_tap = now
	elif e.is_action_released("ping") and ping_open:
		ping_open = false
		var choice := ping_choice()
		if choice >= 0:
			main.issue_ping(tank, GameData.ping_order[choice], ping_point)


func _physics_process(delta: float) -> void:
	if get_tree().paused or phase == "podium":
		return
	_phase_t += delta
	if phase == "killcam" and _phase_t >= KILLCAM_SECONDS:
		phase = "idle"
	if phase == "redeploy":
		if _phase_t >= REDEPLOY_SECONDS:
			phase = "idle"
			main.redeploying = false
			main.player_slot["respawn_t"] = 0.0
		return
	if not has_tank():
		if phase != "killcam":
			phase = "idle"
		sniper = false
		emote_open = false
		ping_open = false
		return
	if auto:
		sniper = force_sniper
		yaw = tank.heading + tank.turret.rotation.y + (1.3 if main.args.has("--side") else 0.0)
		if sniper:
			pitch = tank.gun.rotation.x
		_range_under_crosshair()
		if sniper and tank.def["class"] == "artillery" and main.args.has("--drone"):
			# Test: show the indirect-fire view, laid on a spot ahead with the high arc.
			drone = true
			drone_point = tank.global_position + Vector3(-sin(tank.heading), 0, -cos(tank.heading)) * 260.0
			drone_point.y = main.map.height(drone_point.x, drone_point.z)
			impact = tank.predict_impact()
		return
	if phase == "drop":
		if _phase_t >= DROP_SECONDS:
			phase = "play"
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	tank.track_drive = true
	tank.throttle = Input.get_action_strength("forward") - Input.get_action_strength("back")
	tank.steer = Input.get_action_strength("right") - Input.get_action_strength("left")
	tank.want_fire = captured and not ping_open and Input.is_action_pressed("fire")
	tank.want_mg = captured and Input.is_action_pressed("machine_gun")

	# Free look: remember where the gun was aimed, let the camera wander, snap back on release.
	var look := captured and Input.is_action_pressed("freelook")
	if look and not freelook:
		_held_view = Vector2(yaw, pitch)
	elif freelook and not look:
		yaw = _held_view.x
		pitch = _held_view.y
	freelook = look
	tank.hold_aim = freelook  # the turret stays where it is on the hull while you look about
	var was_sniper := sniper
	sniper = captured and not freelook and (sniper_toggle or Input.is_action_pressed("sight"))
	if sniper != was_sniper and not freelook and not _was_look and tank.def["class"] != "artillery":
		_keep_aim(sniper)
	_was_look = freelook
	if ping_open:
		ping_held += delta
	# Artillery has no gunner's sight: its "sight" is a view from above, for indirect fire.
	var was_drone := drone
	drone = sniper and tank.def["class"] == "artillery"
	if drone and not was_drone:
		var ahead := _range_under_crosshair()
		drone_point = ahead if aim_dist > 0.0 else tank.global_position + Vector3(-sin(yaw), 0, -cos(yaw)) * 250.0
	tank.auto_drop = drone  # the gun is raised to drop the shell on the point
	tank.leveled = drone    # and the vehicle digs in level, so the ground it stands on does not throw the shot off
	shell_eta = maxf(0.0, shell_eta - delta)
	if drone and tank.reload_left > _eta_reload + 0.5:
		shell_eta = maxf(float(tank.predict_path()["time"]), 0.0)  # just fired: this long until it lands
	_eta_reload = tank.reload_left
	if drone:
		if tank.high_arc:
			var out := drone_point - tank.global_position
			out.y = 0.0
			if out.length() < 250.0:
				drone_point = tank.global_position + (out.normalized() if out.length() > 1.0 else Vector3(-sin(yaw), 0, -cos(yaw))) * 250.0
		drone_point.y = main.map.height(drone_point.x, drone_point.z)
		tank.aim_point = drone_point
		impact = tank.predict_impact()
		return
	tank.high_arc = false
	if not freelook:
		var point := _steady_near(_range_under_crosshair())
		_aimed = point
		if ranging > 0.0:
			ranging -= delta
			if ranging <= 0.0:
				ranged = aim_dist
				_ranged_t = RANGE_SHOWN_SECONDS
		elif _ranged_t > 0.0:
			_ranged_t -= delta
			if _ranged_t <= 0.0:
				ranged = -1.0
		# In the gunner's sight the gun is not raised for the zero: the sight's level line
		# moves down its range marks instead, and the target is put on that line.
		if tank.zero_range > 0.0:
			# Zeroed sight: the shell crosses the line of sight at the zero range, so the
			# crosshair stays on the target while the gun is raised for the distance.
			var dir := -cam.global_transform.basis.z
			var lead_in := (tank.muzzle.global_position - cam.global_position).dot(dir)
			point = tank.ballistic_aim(cam.global_position + dir * (lead_in + tank.zero_range))
		tank.aim_point = point
	impact = tank.predict_impact() if tank.def["class"] == "artillery" else null


# Casts from the camera through the crosshair. Returns the point and records its range.
func _range_under_crosshair() -> Vector3:
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 2500.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 7)
	q.exclude = [tank.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_aim_on_unit = false
	if hit.is_empty():
		aim_dist = -1.0
		return to
	aim_dist = tank.muzzle.global_position.distance_to(hit["position"])
	_aim_on_unit = hit["collider"] is CollisionObject3D and hit["collider"].collision_layer & 2 != 0
	return hit["position"]


# The camera sits well above the gun. Up against a wall, the spot under the crosshair is
# high on the wall, and a gun laid on that spot rears up at it. So for anything close that
# is not a vehicle, the gun is never raised more than the camera itself is looking up: it
# stays level with your view and hits the wall at its own height. The effect fades out by
# 35 m, where the difference between the two no longer matters.
func _steady_near(point: Vector3) -> Vector3:
	if sniper or aim_dist < 0.0 or _aim_on_unit:
		return point
	var pivot: Vector3 = tank.gun.global_position
	var out := point - pivot
	var flat := Vector2(out.x, out.z).length()
	var share := smoothstep(10.0, 35.0, flat)
	if share >= 1.0 or flat < 0.5:
		return point
	var view_up := asin(clampf(-cam.global_transform.basis.z.y, -1.0, 1.0))
	var gun_up := atan2(out.y, flat)
	if gun_up <= view_up:
		return point
	return Vector3(point.x, pivot.y + tan(lerpf(view_up, gun_up, share)) * flat, point.z)


# Where the gunner's sight sits: on the turret roof, just above the gun.
func _sight_eye() -> Vector3:
	return tank.turret.global_transform * Vector3(0, tank.turret_h + 0.45, -0.4)


# Going into the gunner's sight, or coming out of it. The outside camera looks down on
# the vehicle from behind and above, the sight looks along the gun: the same mouse angle
# points the two at different places (close up, very different). So on each change the
# view is turned to look at the spot the other one was on.
func _keep_aim(into_sight: bool) -> void:
	if aim_dist < 0.0:
		return
	if into_sight:
		var to := _aimed - _sight_eye()
		if to.length() > 1.0:
			yaw = atan2(-to.x, -to.z)
			pitch = clampf(asin(to.normalized().y), -1.2, 1.5 if tank.def.has("aa") else 0.6)
		return
	for i in 4:
		var to := _aimed - _third_person().origin
		if to.length() < 1.0:
			return
		yaw = atan2(-to.x, -to.z)
		pitch = clampf(asin(to.normalized().y), -1.2, 1.5 if tank.def.has("aa") else 0.6)


func _third_person() -> Transform3D:
	var b := Basis.from_euler(Vector3(pitch, yaw, 0))
	if auto and main.args.has("--side"):
		return Transform3D(b, tank.global_position + Vector3(0, 1.2, 0) + b.z * 10.0)
	var pivot := tank.global_position + Vector3(0, 3.5 + zoom * 0.04, 0)
	var pos := pivot + b.z * zoom + Vector3(0, 1.5, 0)
	# Keep the camera out of houses and blocks: if something solid is between the vehicle
	# and where the camera wants to be, pull it in front of that.
	var q := PhysicsRayQueryParameters3D.create(pivot, pos, 1)
	var wall := get_world_3d().direct_space_state.intersect_ray(q)
	if not wall.is_empty():
		pos = wall["position"] + (pivot - pos).normalized() * 0.8
	pos.y = maxf(pos.y, main.map.height(pos.x, pos.z) + 1.0)
	return Transform3D(b, pos)


# ---- spectating: no vehicle, just a camera ----
# 1 free camera (W A S D to fly, Q and E down and up, Shift faster), 2 the view from a
# vehicle's gun, 3 circling a vehicle. Left and right click step through the vehicles.

func _spectate_input(e: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if e is InputEventMouseMotion and captured:
		yaw -= e.relative.x * 0.0025 * Settings.sensitivity
		pitch = clampf(pitch - e.relative.y * 0.0025 * Settings.sensitivity, -1.4, 1.4)
	elif e is InputEventMouseButton and e.pressed:
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif e.button_index == MOUSE_BUTTON_LEFT:
			spec_i += 1
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			spec_i -= 1
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_spec_reach = maxf(6.0, _spec_reach - 2.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_spec_reach = minf(60.0, _spec_reach + 2.0)
	elif e.is_action_pressed("spec_free"):
		spec_mode = 0
	elif e.is_action_pressed("spec_gunner"):
		spec_mode = 1
	elif e.is_action_pressed("spec_orbit"):
		spec_mode = 2
	elif e.is_action_pressed("spec_outline"):
		spec_outline = not spec_outline


# Who is being watched, for the HUD.
func spec_name() -> String:
	if spec_mode == 0 or main.tanks.is_empty():
		return "free camera"
	var t: Tank = main.tanks[posmod(spec_i, main.tanks.size())]
	return "%s  (%s)" % [t.display_name, t.def["name"]]


func _spectate(delta: float) -> void:
	# Every vehicle wears an outline in its team's colour, if outlines are on.
	for t in main.tanks:
		if t.get_meta("outlined", false) != spec_outline:
			t.set_meta("outlined", spec_outline)
			if not _outline_mats.has(t.team):
				var glow := StandardMaterial3D.new()
				glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				glow.albedo_color = main.TEAM_COLORS[t.team]
				glow.cull_mode = BaseMaterial3D.CULL_FRONT  # only the back faces, pushed outward: a rim round the shape
				glow.grow = true
				glow.grow_amount = 0.14
				_outline_mats[t.team] = glow
			for pair in t.mats:
				pair[0].next_pass = _outline_mats[t.team] if spec_outline else null
	var target: Tank = null
	if not main.tanks.is_empty():
		target = main.tanks[posmod(spec_i, main.tanks.size())]
	if not _spec_set:
		_spec_set = true
		_spec_pos = main.objective_pos() + Vector3(0, 30, 40)
		pitch = -0.5
	cam.fov = FOV_NORMAL
	if spec_mode == 1 and target != null:
		# What its gunner sees: from just above the gun, looking where the gun points.
		var gun := target.gun.global_transform.orthonormalized()
		cam.global_transform = Transform3D(gun.basis, gun.origin + gun.basis.y * 0.7 + gun.basis.z * 0.4)
		cam.fov = 45.0
	elif spec_mode == 2 and target != null:
		var focus := target.global_position + Vector3(0, 2.5, 0)
		var up := clampf(-pitch, -0.2, 1.3)
		var eye := focus + Vector3(sin(yaw) * cos(up), sin(up), cos(yaw) * cos(up)) * _spec_reach
		eye.y = maxf(eye.y, main.map.height(eye.x, eye.z) + 1.0)
		cam.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(focus, Vector3.UP)
	else:
		var look := Basis.from_euler(Vector3(pitch, yaw, 0))
		var move := Vector3(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		_spec_pos += look * move * (90.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 30.0) * delta
		_spec_pos.y = maxf(_spec_pos.y, main.map.height(_spec_pos.x, _spec_pos.z) + 1.5)
		cam.global_transform = Transform3D(look, _spec_pos)
		return
	_spec_pos = cam.global_position  # so the free camera picks up from wherever this one was


func _process(delta: float) -> void:
	# The camera's own movement counts towards the Doppler shift of aircraft, but only while
	# it is following something steadily: a camera that cuts would make every engine yelp.
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP if (phase == "play" and not demo) else Camera3D.DOPPLER_TRACKING_DISABLED
	cam.fov = FOV_NORMAL
	Sfx.set_inside(phase == "play" and has_tank() and sniper)
	if phase == "podium":
		# A slow drift from side to side in front of the winners.
		var sway: Transform3D = main.podium_cam
		sway.origin += Vector3(sin(main.end_t * 0.35) * 2.5, 0, 0)
		cam.global_transform = sway.looking_at(main.podium_cam.origin + Vector3(0, -4.0, 38.0), Vector3.UP)
		cam.fov = 50.0
		return
	if auto and main.args.has("--soldiers") and not main.soldiers.is_empty():
		# Test view: close on the first squad.
		var man: Vector3 = main.soldiers[0].global_position + Vector3(0, 1.3, 0)
		cam.global_transform = Transform3D(Basis.IDENTITY, man + Vector3(5.5, 1.6, -6.5)).looking_at(man + Vector3(1.5, 0, 0), Vector3.UP)
		return
	if has_air() and not demo:
		_air_view()
		return
	if has_man() and not demo:
		_man_controls()
		_man_camera()
		return
	if _view_gun != null:
		_hide_view_gun()  # no longer on foot
	if not _cockpit.is_empty() and not has_air():
		_cockpit = {}
		cam.near = 0.3
	if main.spectating and not demo:
		_spectate(delta)
		return
	if demo:
		camcorder.main = main
		for a in main.args:
			if a.begins_with("--camshot="):
				camcorder.only = a.trim_prefix("--camshot=")
		camcorder.update(cam, delta)
		return
	kill_fade = 0.0
	if phase == "killcam":
		# First the camera stays where it was, on what is left of you, and the picture fades
		# out; then it fades in again over the shoulder of whoever did it.
		kill_fade = smoothstep(KILL_LINGER * 0.55, KILL_LINGER, _phase_t) if _phase_t < KILL_LINGER else 1.0 - smoothstep(KILL_LINGER, KILL_LINGER + 0.5, _phase_t)
		if _phase_t < KILL_LINGER:
			return
		# Look over the killer's shoulder back towards the wreck.
		var focus := _death_pos
		var from := _death_pos + Vector3(0, 30, 30)
		if _killer != null and is_instance_valid(_killer):
			focus = _killer.global_position + Vector3(0, 2.0, 0)
			var back: Vector3 = focus - _death_pos
			back.y = 0.0
			back = back.normalized() if back.length() > 1.0 else Vector3(0, 0, 1)
			from = focus + back * (17.0 - _phase_t) + Vector3(0, 6.0 + (focus.y - _death_pos.y) * 0.1, 0)
		from.y = maxf(from.y, main.map.height(from.x, from.z) + 2.0)
		cam.global_transform = Transform3D(Basis.IDENTITY, from).looking_at(focus, Vector3.UP)
		return
	if not has_tank():
		yaw += delta * 0.1
		var b := Basis.from_euler(Vector3(-0.5, yaw, 0))
		cam.global_transform = Transform3D(b, _pivot + b.z * 110.0)
		return
	if phase == "drop":
		# One long swoop: from high overhead looking straight down, falling fast at first
		# and easing in behind the vehicle as it levels out.
		var k := clampf(_phase_t / DROP_SECONDS, 0.0, 1.0)
		var fall := 1.0 - pow(1.0 - k, 3.0)
		var fwd := Vector3(-sin(tank.heading), 0, -cos(tank.heading))
		var above := Transform3D(Basis.IDENTITY, tank.global_position + Vector3(0, DROP_HEIGHT, 0)).looking_at(tank.global_position, fwd)
		var level := smoothstep(0.35, 1.0, k)
		var t := above.interpolate_with(_third_person(), level)
		t.origin = above.origin.lerp(_third_person().origin, fall)
		cam.global_transform = t
		return
	# From above, only what the team has spotted is shown: the drone is not a free scout.
	if drone != _drone_hid:
		_drone_hid = drone
		if not drone:
			for t in main.tanks:
				t.visible = true
	if drone:
		for t in main.tanks:
			t.visible = t.team == tank.team or t.spotted
		tank.slide.get_parent().visible = true
		cam.fov = 60.0
		var away := Vector3(-sin(yaw), 0, -cos(yaw))
		cam.global_transform = Transform3D(Basis(away.cross(Vector3.UP), away, Vector3.UP), Vector3(drone_point.x, tank.global_position.y + drone_height, drone_point.z))  # a steady height, whatever the ground below does
		return
	tank.slide.get_parent().visible = not sniper  # the gun would only block the sight picture
	if sniper:
		cam.fov = FOV_SNIPER_ARTILLERY if tank.def["class"] == "artillery" else FOV_SNIPER
		# With the sight switched on (its toggle key), holding the sight button magnifies.
		magnified = sniper_toggle and Input.is_action_pressed("sight")
		if magnified:
			cam.fov *= 0.42
		var eye := tank.turret.global_transform * Vector3(0, tank.turret_h + 0.45, -0.4)
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0)), eye)
		return
	_pivot = tank.global_position
	cam.global_transform = _third_person()
