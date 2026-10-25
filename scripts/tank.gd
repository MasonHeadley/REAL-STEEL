class_name Tank
extends CharacterBody3D
# One ground vehicle, built from a row of the vehicles sheet.
# It follows the terrain height directly and only collides with buildings and other vehicles.

const MODULE_REPAIR_SECONDS := 10.0
const SOOT := Color(0.09, 0.09, 0.09)
const MAX_SCARS := 14
const ACCEL_SCALE := 0.6       # share of the sheet's acceleration actually used
const COAST := 0.5             # rolling with no throttle: slows at this share of its acceleration
const AMMO_BURN_SECONDS := 4.0  # from the ammunition catching fire to the vehicle blowing up
const BRAKE := 4.6             # pulling back while rolling forward: this many times the coasting rate
const BOT_SLOWING := 1.5       # bots slow down at this many times their acceleration
const EASED_SPEED := 0.85      # share of top speed kept while turning under power
const EASED_TURN := 0.5        # share of the on-the-spot turn rate while turning under power
const SKID_TURN := 0.9         # extra turn rate from braking one track at full speed (0.9 = nearly double)
const SKID_DRAG := 0.8         # extra slowing while doing it, on top of coasting
const YAW_RESPONSE := 4.0      # how quickly the hull picks up or loses its turn
const CLACKS_PER_M := 1.2  # track clacks heard per metre travelled, up to 14 a second
const STABILISER := 0.055    # radians of hull rock the gun stabiliser works over (about 3 degrees)
const STABILISER_GRIP := 0.7 # how much of that rock it actually cancels: 1 would be perfect
const SPRING := 120.0        # suspension stiffness and damping for the hull's rocking
const DAMPING := 13.0

var main
var def: Dictionary
var role: Dictionary
var ability: Dictionary
var slot: Dictionary
var team := 0
var display_name := ""

var hp := 1.0
var max_hp := 1.0
var throttle := 0.0
var steer := 0.0
var heading := 0.0
var aim_point := Vector3.ZERO
var want_fire := false
var want_mg := false
var auto_drop := false  # bots get their gun raised for range; the player sets a zero by hand
var zero_range := 0.0   # player's sight zero in metres (0 = gun points straight at the crosshair)
var speed := 0.0
var reload_left := 0.0
var _reload_sound := ""  # the player's loader noise still to be played this reload
var _reload_sound_at := 0.0
var reload_total := 1.0  # how long the current reload was when it began, for the HUD ring
var mg_cd := 0.0
var shell_index := 0
var modules := {"engine": 0.0, "tracks": 0.0, "gun": 0.0}
var ability_cd := 0.0
var ability_left := 0.0
var armed_t := 0.0      # a special next shell (sabot, concussion) is loaded while this runs
var spotted := false    # the enemy team can currently see this vehicle
var revealed_t := 0.0   # marked by an enemy scan
var emote := ""
var emote_t := 0.0

var visual: Node3D
var turret: Node3D
var gun: Node3D
var muzzle: Node3D
var mats: Array = []
var scars: Array = []
var smoke: CPUParticles3D
var fire: CPUParticles3D
var engine: AudioStreamPlayer3D
var tracks_sound: AudioStreamPlayer3D
var hull_top := 1.0
var turret_h := 1.0
var _up := Vector3.UP
var _aim_adjusted := Vector3.ZERO
var _barrel := 0
var _running: Dictionary
var _track_run := [0.0, 0.0]  # metres each track has travelled: left, right
var slide: Node3D            # the barrel, which slides back in recoil
var roar: AudioStreamPlayer3D
var rpm := 0.15              # engine speed, 0 (stalled) to 1 (red line)
var gear := 0
var hurt_by := {}            # enemy slot index -> match time it last damaged this vehicle
var _rock := Vector2.ZERO    # the hull's lean on its suspension: x = nose up/down, y = roll
var _rock_vel := Vector2.ZERO
var _whips: Array = []       # radio aerials, which sway
var _sweep: Area3D           # finds the loose things the hull is running into
var _sweep_t := 0.0
var leveled := false         # dug in for indirect fire: the hull sits level whatever the ground does, and cannot move
var high_arc := false        # indirect fire: lob the shell high so it drops behind cover
var credit = null            # a player on foot or in the air who hit it last (their slot), for the kill
var credit_t := 0.0
var aa_lock: Aircraft       # an anti-aircraft missile carrier: the aircraft its seeker is on
var aa_lock_t := 0.0         # and for how long
const AA_LOCK_SECONDS := 1.5 # how long the sight must be held on an aircraft before a missile will follow it
var _brew_t := 0.0           # killed on the move: seconds of burning still to go before it blows up
var _brew_by = null
var _brew_how := ""
var _aa_tone := 0.0
var kill_paid := false       # whoever killed it has already had their points (it is burning, about to blow)
var kill_who := ""
var radar_on := true         # an anti-aircraft vehicle's radar: on, it shows every aircraft and can be seen by them
var _radar: Node3D
var ammo_fire := 0.0         # the ammunition is burning: seconds until it goes up and takes the vehicle with it
var _ammo_by = null          # who set it alight, for the kill
var predict := false         # our own vehicle in a match the host is running: driven here at once, corrected gently
var puppet := false          # a copy of a vehicle another PC is driving (see netplay.gd)
var net_pos := Vector3.ZERO  # where the host last said it was
var net_heading := 0.0
var net_speed := 0.0
var track_drive := false     # driven from the keyboard, track by track (see _drive_tracks); bots are not
var _yaw_rate := 0.0         # how fast the hull is turning now, radians a second, right positive
var _recoil := 0.0           # how far back the barrel currently is, metres
var _last_speed := 0.0
var hold_aim := false        # free look: the turret stays put relative to the hull
var mg_sound: Node3D
var _clack_t := 0.0          # counts down to the next track link clacking
var _clack_pitch := 1.0      # lower for a heavier vehicle
var _gun_pitch := 0.0        # where the gunner has laid the gun, before the stabiliser acts
var _mg_shots := 0
var _dust_t := 0.0
var _wheel_lift: Array = [[], []]  # how far each road wheel is pushed up or hanging down


func setup(p_main, p_slot: Dictionary) -> void:
	main = p_main
	slot = p_slot
	def = Kit.apply(GameData.vehicles[slot["vehicle_id"]], slot.get("look", {}))
	role = GameData.roles[def["role"]]
	ability = GameData.abilities[def["ability"]]
	team = slot["team"]
	display_name = slot["name"]
	max_hp = def["hp"]
	hp = max_hp
	if def["class"] == "artillery":
		zero_range = 300.0
	collision_layer = 2
	collision_mask = 3
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_build()


func _build() -> void:
	var l: float = def["length"]
	var w: float = def["width"]
	var model := TankModel.build(def, main.TEAM_COLORS[team], slot.get("wear", 0.3), slot.get("wear_seed", 1), slot.get("look", {}))
	visual = model["root"]
	_radar = model.get("radar")
	slide = model["slide"]
	add_child(visual)
	turret = model["turret"]
	gun = model["gun"]
	muzzle = model["muzzle"]
	mats = model["mats"]
	hull_top = model["hull_top"]
	turret_h = model["turret_h"]
	_running = model["running"]
	_whips = visual.find_children("*", "Node3D", true, false).filter(func(n): return n.has_meta("whip"))

	var hull_shape := CollisionShape3D.new()
	var hb := BoxShape3D.new()
	hb.size = Vector3(w, hull_top - 0.1, l)
	hull_shape.shape = hb
	hull_shape.position = Vector3(0, 0.1 + (hull_top - 0.1) * 0.5, 0)
	add_child(hull_shape)
	var turret_shape := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(model["turret_width"], turret_h, model["turret_len"])
	turret_shape.shape = tb
	turret_shape.position = turret.position + Vector3(0, turret_h * 0.5, 0)
	add_child(turret_shape)

	smoke = MeshUtil.smoke(Color(0.22, 0.22, 0.22), 22, 1.3)
	fire = MeshUtil.smoke(Color(1.0, 0.45, 0.1), 14, 0.7)
	fire.lifetime = 0.9
	engine = Sfx.loop("engine", -6.0, 11.0)
	engine.position = Vector3(0, 1.5, l * 0.3)
	add_child(engine)
	roar = Sfx.loop("engine_roar", -40.0, 14.0)
	roar.position = engine.position
	add_child(roar)
	tracks_sound = Sfx.rattle("clack", 8.0)
	_clack_pitch = {"heavy": 0.68, "light": 1.0}.get(def["class"], 0.82)
	add_child(tracks_sound)
	# A rifle-calibre gun rattles; a heavy one barks. Each shot picks one of several recordings.
	mg_sound = Sfx.emitter("mg" if def["mg"] == "mg_762" else "mg_heavy", -3.0, 38.0)
	mg_sound.position = Vector3(0, hull_top + 0.6, -l * 0.3)
	add_child(mg_sound)
	# Whatever loose things the hull runs into get shoved out of the way (see prop.gd).
	_sweep = Area3D.new()
	_sweep.collision_layer = 0
	_sweep.collision_mask = Prop.LAYER
	_sweep.monitorable = false
	var reach := CollisionShape3D.new()
	var hull_box := BoxShape3D.new()
	hull_box.size = Vector3(float(def["width"]) + 0.3, 2.2, l + 0.4)
	reach.shape = hull_box
	reach.position.y = 1.2
	_sweep.add_child(reach)
	add_child(_sweep)
	for si in 2:
		_wheel_lift[si].resize(int(def["wheels"]))
		_wheel_lift[si].fill(0.0)
	for p in [smoke, fire]:
		p.position = Vector3(0, hull_top + 0.2, l * 0.3)
		visual.add_child(p)


func is_mine() -> bool:
	return slot.get("camera", false)


func effect_active(effect: String) -> bool:
	return ability_left > 0.0 and ability["effect"] == effect


func current_shell() -> Dictionary:
	var ids: Array = def["shells"]
	return GameData.shells[ids[shell_index % ids.size()]]


func eye() -> Vector3:
	return global_position + Vector3(0, 2.5, 0)


func _physics_process(delta: float) -> void:
	var was_loading := reload_left > 0.0
	reload_left = maxf(0.0, reload_left - delta)
	if _reload_sound != "" and reload_left <= _reload_sound_at:
		# The loader at work, timed so the breech closes as the gun comes ready.
		Sfx.play_ui(_reload_sound, 0.0 if Sfx.inside else -9.0, 1.0, "Interface")
		_reload_sound = ""
	if was_loading and reload_left <= 0.0 and is_mine():
		if float(def["reload"]) >= 3.0:
			Sfx.say("loaded")
		elif float(def["reload"]) >= 1.0:
			Sfx.play_ui("click")
	if _brew_t > 0.0:
		# Knocked out while moving: it rolls on, burning, for a moment, then goes up.
		_brew_t -= delta
		if _brew_t <= 0.0:
			_blow_up(_brew_by if (_brew_by != null and is_instance_valid(_brew_by)) else null, _brew_how)
			return
	if _radar != null and is_instance_valid(_radar):
		# The aerial turns while the radar is on. Switched off, it carries on round until it
		# faces backwards, stops there and folds down flat; switched on, it stands up and turns again.
		var dish: Node3D = _radar.get_child(0)
		if radar_on:
			dish.rotation.x = move_toward(dish.rotation.x, -0.18, 2.2 * delta)
			if dish.rotation.x > -0.4:
				_radar.rotation.y += 2.4 * delta
		elif absf(angle_difference(_radar.rotation.y, PI)) > 0.08:
			_radar.rotation.y += 2.4 * delta
		else:
			_radar.rotation.y = PI
			dish.rotation.x = move_toward(dish.rotation.x, -1.5, 1.6 * delta)
	_show_broken()
	if def.get("aa", "") == "missile" and not puppet:
		_aa_seek(delta)
	if ammo_fire > 0.0 and not puppet and not predict:
		ammo_fire -= delta
		if ammo_fire <= 0.0:
			_hurt(max_hp * 20.0, _ammo_by if _ammo_by != null and is_instance_valid(_ammo_by) else null, "Ammo cook-off")
			return
	ability_cd = maxf(0.0, ability_cd - delta)
	ability_left = maxf(0.0, ability_left - delta)
	armed_t = maxf(0.0, armed_t - delta)
	revealed_t = maxf(0.0, revealed_t - delta)
	emote_t = maxf(0.0, emote_t - delta)
	mg_cd = maxf(0.0, mg_cd - delta)
	for k in modules:
		modules[k] = maxf(0.0, modules[k] - delta)
	if main.prep_t > 0.0 or _brew_t > 0.0:
		# Engines running, guns loaded, nobody moves until the round starts.
		# (The same goes for a crew that has just been killed: nobody is driving or shooting.)
		throttle = 0.0
		steer = 0.0
		want_fire = false
		want_mg = false
	if leveled:
		throttle = 0.0
		steer = 0.0

	var flat := Vector3(-sin(heading), 0, -cos(heading))
	if puppet:
		# A copy of a vehicle that the host is driving: it is eased towards where the host
		# last said it was, and does no driving or shooting of its own.
		var ease := clampf(delta * 12.0, 0.0, 1.0)
		global_position = net_pos if global_position.distance_to(net_pos) > 25.0 else global_position.lerp(net_pos, ease)
		heading = lerp_angle(heading, net_heading, ease)
		speed = net_speed
		_yaw_rate = 0.0
		flat = Vector3(-sin(heading), 0, -cos(heading))
	else:
		var boost := float(ability["power"]) if effect_active("boost") else 1.0
		flat = Vector3(-sin(heading), 0, -cos(heading))
		var grade := (-global_transform.basis.z).y  # positive when climbing
		var eng := (0.5 if modules["engine"] > 0.0 else 1.0) * boost
		var target := 0.0
		var braking := 1.0
		if modules["tracks"] <= 0.0:
			var top_fwd := float(def["speed_fwd"]) / 3.6 * eng * clampf(1.0 - grade * 1.6, 0.35, 1.2)
			var top_rev := float(def["speed_rev"]) / 3.6 * eng * clampf(1.0 + grade * 1.6, 0.35, 1.2)
			var turn := deg_to_rad(def["turn_rate"])
			if track_drive:
				var drive := _drive_tracks(top_fwd, top_rev, turn)
				target = drive.x
				braking = drive.y
				# The hull has weight: it takes a moment to start turning and to stop.
				_yaw_rate = move_toward(_yaw_rate, drive.z, turn * YAW_RESPONSE * delta)
			else:
				target = throttle * (top_fwd if throttle >= 0.0 else top_rev)
				_yaw_rate = steer * turn
			heading -= _yaw_rate * delta
			flat = Vector3(-sin(heading), 0, -cos(heading))
		else:
			_yaw_rate = 0.0
		# These weigh tens of tonnes: they gather speed slowly and, left alone, roll on a long way.
		var rate: float = float(def["accel"]) * ACCEL_SCALE * boost
		if absf(target) < absf(speed) or signf(target) != signf(speed):
			rate *= (COAST * braking) if track_drive else BOT_SLOWING
		speed = move_toward(speed, target, rate * delta)
		velocity = flat * speed
		move_and_slide()
		speed = velocity.dot(flat)
		if predict:
			# The host has the last word on where we are, but its word arrives late. So the
			# vehicle answers the controls here straight away, and is drawn steadily towards
			# the host's position; only if the two have really parted company does it jump.
			var gap := net_pos - global_position
			gap.y = 0.0
			if gap.length() > 14.0:
				global_position = net_pos
				heading = net_heading
				speed = net_speed
			else:
				global_position += gap * minf(1.0, delta * 2.0)
				heading = lerp_angle(heading, net_heading, minf(1.0, delta * 1.5))
			flat = Vector3(-sin(heading), 0, -cos(heading))
		_sweep_t -= delta
		if _sweep_t <= 0.0 and (absf(speed) > 0.5 or absf(_yaw_rate) > 0.2):
			_sweep_t = 0.12
			for b in _sweep.get_overlapping_bodies():
				if b is Prop:
					# Thrown ahead and aside, harder the faster the vehicle is going.
					var away: Vector3 = b.global_position - global_position
					away.y = 0.0
					var push := (flat * signf(speed) * 0.7 + away.normalized() * 0.5).normalized() + Vector3(0, 0.22, 0)
					if b.mass >= Prop.HEAVY:
						# A car or a lorry: it is shouldered aside slowly, and it costs the vehicle its speed.
						var shove := (flat * signf(speed) * 0.8 + away.normalized() * 0.4).normalized()
						b.knock(shove * b.mass * clampf(absf(speed) * 0.25, 0.5, 2.2), global_position + Vector3(0, 0.5, 0))
						speed *= 0.84
					else:
						b.knock(push * b.mass * clampf(absf(speed) * 0.9, 2.0, 9.0), global_position + Vector3(0, 0.8, 0))

	# Sit on the ground and lean with it.
	var gp := global_position
	gp.y = main.map.ground(gp.x, gp.z)
	_up = _up.lerp(Vector3.UP if leveled else main.map.normal(gp.x, gp.z), minf(1.0, (2.0 if leveled else 6.0) * delta)).normalized()
	var right := flat.cross(_up).normalized()
	var fwd := _up.cross(right).normalized()
	global_transform = Transform3D(Basis(right, _up, -fwd), gp)

	_engine_note(delta)
	# Weight thrown about: braking dips the nose, pulling away lifts it.
	var accel := (speed - _last_speed) / maxf(delta, 0.001)
	_last_speed = speed
	_rock_vel.x += clampf(accel, -12.0, 12.0) * 0.0065
	# Tracks throw up a little dust at speed.
	_dust_t -= delta
	if _dust_t <= 0.0 and absf(speed) > 5.0:
		_dust_t = 0.4
		Fx.dust(main, global_position + global_transform.basis.z * float(def["length"]) * 0.5 * signf(speed) + Vector3(0, 0.3, 0), 0.25)

	_aim(delta)
	if want_fire and not puppet and not predict:
		fire_gun()
	if want_mg and mg_cd <= 0.0:
		mg_cd = 0.1
		var mg_dir := (-gun.global_transform.basis.z + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.006).normalized()
		main.spawn_shell(self, GameData.shells[def["mg"]], gun.global_transform * Vector3(0.3, 0.2, -0.6), mg_dir, {})
		Sfx.fire(mg_sound)
		if is_mine() and Sfx.inside:
			Sfx.mg_inside(mg_sound.get_meta("sound"))  # your own gun, clear, over the muffled world
		Fx.muzzle(main, gun.global_transform * Vector3(0.3, 0.2, -0.9), mg_dir, 12.0, false, global_position.y)
	var hurt := 1.0 - hp / max_hp
	var want_smoke: bool = hurt > 0.5 or modules["engine"] > 0.0
	if smoke.emitting != want_smoke:
		smoke.emitting = want_smoke
	if fire.emitting != (hurt > 0.75):
		fire.emitting = hurt > 0.75


# The chance a shell skids off instead of biting, from how far off square it struck: none
# when it hits within about 55 degrees of straight on, rising steadily to certain by about
# 78 degrees. Shaped charges need a steeper angle than solid shot before they fail.
func _glance_chance(type: String, cosv: float) -> float:
	var off_square := rad_to_deg(acos(clampf(cosv, 0.0, 1.0)))
	if type == "HEAT":
		return clampf((off_square - 68.0) / 16.0, 0.0, 1.0)
	return clampf((off_square - 55.0) / 23.0, 0.0, 1.0)


# Keyboard driving, worked out track by track the way a real tracked vehicle steers.
# Returns (speed to aim for, how hard it is braking, turn rate wanted in radians a second).
#   forward + turn      the inside track is eased off: a slow, wide turn that costs a little speed
#   turn only, rolling  the inside track is braked: the hull swings round it, faster the faster
#                       it was going, and scrubs its speed off doing it
#   turn only, stopped  neutral steering: the tracks run opposite ways and it turns on the spot
#   back while rolling  both tracks brake; it only goes into reverse once it has stopped
#   back + turn         the track on that side is held and the other reversed, so the nose
#                       swings the other way from the key (as it does in a real one)
func _drive_tracks(top_fwd: float, top_rev: float, turn: float) -> Vector3:
	var pace := clampf(absf(speed) / maxf(top_fwd, 0.1), 0.0, 1.2)
	var turning := absf(steer) > 0.1
	if throttle > 0.1:
		if speed < -0.5:
			return Vector3(0.0, BRAKE, 0.0)  # rolling backwards: stop first
		if turning:
			return Vector3(top_fwd * throttle * EASED_SPEED, 1.0, steer * turn * lerpf(EASED_TURN, EASED_TURN * 0.75, pace))
		return Vector3(top_fwd * throttle, 1.0, 0.0)
	if throttle < -0.1:
		if speed > 0.5:
			# Braking. One track can still be let off a little to steer.
			return Vector3(0.0, BRAKE, steer * turn * 0.5 * (0.4 + pace))
		if turning:
			return Vector3(-top_rev * 0.6, 1.0, -steer * turn * 0.6)
		return Vector3(-top_rev, 1.0, 0.0)
	if not turning:
		return Vector3(0.0, 1.0, 0.0)
	if absf(speed) > 1.0:
		# One track braked while the other rolls on.
		return Vector3(0.0, 1.0 + SKID_DRAG * absf(steer), steer * turn * (1.0 + SKID_TURN * pace) * signf(speed))
	return Vector3(0.0, 1.0, steer * turn)


# The engine's sound follows its revs, not the road speed. Revs climb through each gear and
# drop back at every change; at a standstill it idles, and it roars if the driver floors it
# with nowhere to go. A low idle layer gives way to a recorded roar as the revs rise.
func _engine_note(delta: float) -> void:
	var gears := int(def["gears"])
	var top := float(def["speed_fwd"]) / 3.6
	var pace := clampf(absf(speed) / top, 0.0, 1.3)
	var band := 1.0 / float(gears)
	var want_gear := clampi(int(pace / band), 0, gears - 1)
	if want_gear > gear and rpm > 0.86:
		gear += 1
	elif want_gear < gear and rpm < 0.42:
		gear -= 1
	gear = clampi(gear, 0, gears - 1)
	var within := clampf((pace - float(gear) * band) / band, 0.0, 1.25)
	var want_rpm := 0.3 + 0.62 * within if (gear > 0 or pace > 0.02) else 0.15
	if absf(throttle) > 0.1 or absf(steer) > 0.1:
		want_rpm = maxf(want_rpm, 0.45)  # working, even if barely moving
	if modules["engine"] > 0.0:
		want_rpm *= 0.75
	rpm = move_toward(rpm, want_rpm, (0.9 if want_rpm > rpm else 1.6) * delta)
	var load := clampf(absf(throttle) * 0.7 + absf(steer) * 0.3, 0.0, 1.0)
	engine.pitch_scale = 0.75 + rpm * 0.7
	engine.volume_db = lerpf(-7.0, -15.0, clampf(rpm * 1.4, 0.0, 1.0))
	roar.pitch_scale = 0.55 + rpm * 0.95
	roar.volume_db = lerpf(-34.0, -5.0, clampf((rpm - 0.12) * 1.5, 0.0, 1.0)) + load * 4.0
	# Track links: single clacks, closer together the faster the tracks run (or the harder
	# the vehicle is turning on the spot), and deeper and slower for a heavier vehicle.
	var roll := maxf(absf(speed), absf(_yaw_rate) * float(def["width"]) * 0.5)
	tracks_sound.pitch_scale = _clack_pitch
	tracks_sound.volume_db = lerpf(-20.0, -9.0, clampf(pace * 1.5, 0.0, 1.0))
	_clack_t -= delta * minf(roll * CLACKS_PER_M, 14.0) * _clack_pitch
	if _clack_t <= 0.0:
		_clack_t = randf_range(0.9, 1.1)
		var cam := get_viewport().get_camera_3d()
		if roll > 0.4 and not Sfx.muted and cam != null and cam.global_position.distance_to(global_position) < 140.0:
			tracks_sound.play()


# Things that only change how the vehicle looks: the hull rocking on its springs, the barrel
# running back and returning after a shot, and the tracks and wheels going round.
func _process(delta: float) -> void:
	# A damped spring pulls the hull level again after a shot or a hard stop.
	# (Taken in small steps and kept within bounds, so a slow frame cannot fling it about.)
	var left := minf(delta, 0.1)
	while left > 0.0:
		var dt := minf(left, 1.0 / 90.0)
		left -= dt
		_rock_vel += (-_rock * SPRING - _rock_vel * DAMPING) * dt
		_rock += _rock_vel * dt
	_rock = _rock.limit_length(0.3)
	_rock_vel = _rock_vel.limit_length(6.0)
	visual.rotation = Vector3(_rock.x, 0.0, _rock.y)
	_recoil = move_toward(_recoil, 0.0, delta * (0.9 + _recoil * 3.0))
	slide.position.z = _recoil

	# Aerials whip about with the hull: thrown back and forth as it rocks, swung outward in a
	# turn, and shivering on the move.
	var clock := Time.get_ticks_msec() * 0.001
	var shiver := clampf(absf(speed) * 0.004, 0.0, 0.05)
	# Which way the tips are thrown, worked out in the hull's space and then turned into the
	# space of whatever each aerial stands on, so one on a turret leans the right way
	# whichever way the turret is facing.
	var thrown := Vector3(clampf(_rock.y * 8.0 + _yaw_rate * 0.15, -0.6, 0.6), 0.0, clampf(_rock.x * 8.0, -0.6, 0.6))
	for i in _whips.size():
		var base: Node3D = _whips[i].get_parent()
		var tip: Vector3 = (visual.global_transform.basis.inverse() * base.global_transform.basis).inverse() * thrown
		var lean := Vector3(tip.z + sin(clock * 11.0 + i * 2.0) * shiver, 0.0, -tip.x + cos(clock * 9.0 + i) * shiver)
		_whips[i].rotation = _whips[i].rotation.lerp(lean, 1.0 - exp(-8.0 * delta))

	var yaw_rate := _yaw_rate
	if absf(speed) < 0.02 and absf(yaw_rate) < 0.01:
		return
	var half_width := float(def["width"]) * 0.42
	_track_run[0] += (speed + yaw_rate * half_width) * delta
	_track_run[1] += (speed - yaw_rate * half_width) * delta
	# Suspension: each road wheel rides up over a bump or drops into a hollow, as far as its
	# travel allows, and the track along the ground follows the wheels.
	var blend := minf(1.0, 14.0 * delta)
	for si in 2:
		var spots: Array = _running["wheel_spots"][si]
		for i in spots.size():
			var at: Vector3 = global_transform * spots[i]
			var want := clampf(main.map.ground(at.x, at.z) - at.y, -TankModel.WHEEL_TRAVEL, TankModel.WHEEL_TRAVEL)
			_wheel_lift[si][i] = lerpf(_wheel_lift[si][i], want, blend)
	TankModel.pose_tracks(_running, _track_run[0], _track_run[1], _wheel_lift)


func _aim(delta: float) -> void:
	# hold_aim (free look) leaves the turret and gun exactly where they are on the hull.
	if not hold_aim:
		_aim_adjusted = ballistic_aim(aim_point) if auto_drop else aim_point
		var local := to_local(_aim_adjusted) - turret.position
		var limit := deg_to_rad(def["traverse_limit"])
		var want_yaw := atan2(-local.x, -local.z)
		if limit < PI - 0.01:
			# A fixed gun only swings a little; the driver has to point the hull.
			want_yaw = clampf(want_yaw, -limit, limit)
			turret.rotation.y = move_toward(turret.rotation.y, want_yaw, deg_to_rad(def["turret_traverse"]) * delta)
		else:
			turret.rotation.y = rotate_toward(turret.rotation.y, want_yaw, deg_to_rad(def["turret_traverse"]) * delta)
		var flat := Vector2(local.x, local.z).length()
		var want_pitch := atan2(local.y - gun.position.y, maxf(flat, 0.1))
		want_pitch = clampf(want_pitch, deg_to_rad(def["elev_min"]), deg_to_rad(def["elev_max"]))
		_gun_pitch = move_toward(_gun_pitch, want_pitch, deg_to_rad(float(def.get("elev_rate", 20.0))) * delta)
	# Gun stabiliser: as the hull rocks on its springs, the gun is held level for the first
	# few degrees either way. Only a really hard lurch (slamming the brakes, a heavy hit)
	# gets past it and throws the aim off.
	var yaw: float = turret.rotation.y
	var tip := _rock.x * cos(yaw) - _rock.y * sin(yaw)
	gun.rotation.x = _gun_pitch - clampf(tip, -STABILISER, STABILISER) * STABILISER_GRIP


# The point to aim the gun at so a shell lands on target (flat, low arc).
# The lobbed shot (indirect fire, high arc) is not a real howitzer's: that would hang in the
# air for twenty seconds and could not reach anything close. Instead the gun is always laid
# at the same steep angle, the charge is chosen to suit the range (so near targets are hit
# with a gentle lob and far ones with a hard one), and the shell falls three times as fast.
# It comes down steeply behind cover at any range from about 250 m, in 6 to 12 seconds.
const HIGH_ARC_ANGLE := 1.08     # radians (62 degrees)
const HIGH_ARC_GRAVITY := 3.0    # how many times normal gravity the lobbed shell feels


func shot_gravity() -> float:
	return GameData.SHELL_GRAVITY * (HIGH_ARC_GRAVITY if high_arc else 1.0)


# The speed the shell leaves at: the shell's own, or for the lobbed shot the charge that
# carries it to the aiming point.
func shot_speed() -> float:
	var v: float = current_shell()["velocity"]
	if not high_arc:
		return v
	var d := aim_point - muzzle.global_position
	var x := maxf(Vector2(d.x, d.z).length(), 60.0)
	var fall := 2.0 * cos(HIGH_ARC_ANGLE) * cos(HIGH_ARC_ANGLE) * (x * tan(HIGH_ARC_ANGLE) - d.y)
	return v if fall <= 1.0 else sqrt(shot_gravity() * x * x / fall)


func ballistic_aim(target: Vector3) -> Vector3:
	var v := shot_speed()
	var g := shot_gravity()
	var o := muzzle.global_position
	var d := target - o
	var x := maxf(Vector2(d.x, d.z).length(), 0.1)
	if high_arc:
		return o + Vector3(d.x, x * tan(HIGH_ARC_ANGLE), d.z)
	var disc := v * v * v * v - g * (g * x * x + 2.0 * d.y * v * v)
	var tan_t := 1.0 if disc < 0.0 else (v * v - sqrt(disc)) / (g * x)
	return o + Vector3(d.x, x * tan_t, d.z)


# Flies an imaginary shell from the muzzle and returns where it lands, or null.
func predict_impact():
	var pos := muzzle.global_position
	var vel := -muzzle.global_transform.basis.z * shot_speed()
	var space := get_world_3d().direct_space_state
	var dt := 0.06
	for i in 260:
		vel.y -= shot_gravity() * dt
		var to := pos + vel * dt
		var q := PhysicsRayQueryParameters3D.create(pos, to, 7)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return hit["position"]
		pos = to
	return null


# The same flight, kept: the points along it, and how many seconds it takes. Returns
# {"points": [...], "time": seconds}; time is -1 if the shell never comes down in range.
func predict_path() -> Dictionary:
	var pos := muzzle.global_position
	var vel := -muzzle.global_transform.basis.z * shot_speed()
	var space := get_world_3d().direct_space_state
	var dt := 0.1
	var points: Array = [pos]
	for i in 320:
		vel.y -= shot_gravity() * dt
		var to := pos + vel * dt
		var q := PhysicsRayQueryParameters3D.create(pos, to, 7)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			points.append(hit["position"])
			return {"points": points, "time": (i + 1) * dt}
		pos = to
		points.append(pos)
	return {"points": points, "time": -1.0}


# Angle in radians between where the gun points and where it wants to point.
func gun_error() -> float:
	var to := (_aim_adjusted - muzzle.global_position).normalized()
	return (-muzzle.global_transform.basis.z).angle_to(to)


func fire_gun() -> bool:
	if reload_left > 0.0 or modules["gun"] > 0.0:
		return false
	reload_left = float(def["reload"]) * float(Settings.rules["reload"]) * (float(ability["reload_mult"]) if effect_active("reload") else 1.0)
	reload_total = reload_left
	if is_mine() and reload_left >= 2.5:
		# The long recording only fits a slow gun; quick loaders get the short one.
		_reload_sound = "reload_small" if def["gun_sound"] == "cannon_small" or reload_left < 6.0 else "reload"
		# Leave the shot itself a moment to ring before the loader starts.
		_reload_sound_at = minf(4.6 if _reload_sound == "reload" else 2.1, reload_left - 1.2)
	var mods := {}
	if armed_t > 0.0:
		armed_t = 0.0
		if ability["effect"] == "sabot":
			mods = {"pen": float(ability["power"]), "damage": float(ability["power2"]), "speed": 1.3}
		else:
			mods = {"stun": float(ability["power"]), "stun_radius": float(ability["radius"])}
	if high_arc:
		mods["speed"] = shot_speed() / float(current_shell()["velocity"])
		mods["gravity"] = HIGH_ARC_GRAVITY
	var from := muzzle.global_position
	if def.get("aa", "") == "missile":
		# A missile, not a shell: it leaves one launcher or the other and follows whatever
		# aircraft the seeker has locked. With no lock it flies straight.
		_barrel = 1 - _barrel
		from += muzzle.global_transform.basis.x * (float(_barrel) - 0.5) * (float(def["width"]) * float(def["turret_wid"]) + 0.84)
		Aircraft.Missile.launch(main, self, from, -muzzle.global_transform.basis.z * 90.0, aa_lock if aa_locked() else null, false)
		aa_lock_t = 0.0
		return true
	if int(def["barrels"]) > 1:
		_barrel = 1 - _barrel
		from += muzzle.global_transform.basis.x * (float(_barrel) - 0.5) * float(def.get("barrel_gap", 0.44))
	main.spawn_shell(self, current_shell(), from, -muzzle.global_transform.basis.z, mods)
	show_shot()
	return true


# What a shot does to the vehicle that fired it: the hull rocks and the barrel runs back.
# The bigger the gun and the lighter the vehicle, the harder it rocks. The shove comes back
# along the barrel, so a shot over the side rolls the hull instead of pitching it.
func show_shot() -> void:
	var calibre: float = def["gun_calibre"]
	var kick := clampf(pow(calibre / 100.0, 2.0) * 1150.0 / max_hp, 0.0, 4.6)
	var yaw: float = turret.rotation.y
	_rock_vel += Vector2(cos(yaw), -sin(yaw)) * kick
	_recoil = clampf(calibre / 260.0, 0.05, 0.6)


func aa_locked() -> bool:
	return aa_lock != null and is_instance_valid(aa_lock) and aa_lock_t >= AA_LOCK_SECONDS


# The missile carrier's seeker: the enemy aircraft nearest the line of the launchers, if it
# is close to that line and in plain view. Held there for AA_LOCK_SECONDS, it is locked.
func _aa_seek(delta: float) -> void:
	var found: Aircraft = null
	var best := 0.13
	var along := -muzzle.global_transform.basis.z
	for a in main.aircraft:
		if not is_instance_valid(a) or a.team == team or a.dying or a.wrecked:
			continue
		var to: Vector3 = a.global_position + Vector3(0, 1.5, 0) - muzzle.global_position
		var off := along.angle_to(to.normalized())
		if to.length() < 2600.0 and off < best and main.los(muzzle.global_position, a.global_position + Vector3(0, 1.5, 0)):
			best = off
			found = a
	aa_lock_t = aa_lock_t + delta if (found != null and found == aa_lock) else 0.0
	aa_lock = found
	if is_mine() and aa_lock != null:
		_aa_tone -= delta
		if _aa_tone <= 0.0:
			_aa_tone = 0.11 if aa_locked() else 0.42
			Sfx.play_ui("lock_tone", -9.0, 1.25 if aa_locked() else 0.8)


func use_ability() -> bool:
	if ability_cd > 0.0:
		return false
	ability_cd = ability["cooldown"]
	ability_left = ability["duration"]
	Sfx.play("ability", global_position, -4.0, 1.0, 12.0)
	var radius: float = ability["radius"]
	match String(ability["effect"]):
		"repair":
			for t in main.tanks:
				if t.team == team and t.global_position.distance_to(global_position) <= radius:
					t.hp = minf(t.max_hp, t.hp + t.max_hp * float(ability["heal_frac"]))
					for k in t.modules:
						t.modules[k] = 0.0
					t.refresh_damage_look()
					main.spawn_fx(t.global_position + Vector3(0, 2, 0), 5.0, Color(0.3, 1.0, 0.5, 0.5), 0.6)
		"smoke":
			main.add_smoke(global_position + (-global_transform.basis.z) * 8.0, radius, ability["duration"])
		"scan":
			main.spawn_fx(global_position + Vector3(0, 3, 0), 40.0, Color(0.4, 0.8, 1.0, 0.25), 0.8)
			for t in main.tanks:
				if t.team != team and t.global_position.distance_to(global_position) <= radius:
					t.revealed_t = ability["duration"]
		"skyscan":
			main.sky_scan[team] = main.elapsed + float(ability["duration"])
			main.spawn_fx(global_position + Vector3(0, 4, 0), 30.0, Color(0.4, 1.0, 0.6, 0.25), 0.8)
		"sabot", "stun_shell":
			armed_t = ability["duration"]
			main.spawn_fx(muzzle.global_position, 3.0, Color(0.5, 0.9, 1.0, 0.5), 0.4)
		_:
			main.spawn_fx(global_position + Vector3(0, 2, 0), 6.0, Color(1.0, 0.9, 0.3, 0.4), 0.5)
	return true


# Soot builds up on the paint as the vehicle is worn down.
func refresh_damage_look() -> void:
	if _brew_t > 0.0:
		return  # burnt black already
	var hurt := clampf(1.0 - hp / max_hp, 0.0, 1.0)
	for pair in mats:
		pair[0].albedo_color = pair[1].lerp(SOOT, hurt * 0.6)


# A hit mark painted onto the armour: a scorched hole where a round went in, a bright scrape
# where one bounced. The normal map makes the plate look pushed in around it.
func _add_scar(pos: Vector3, out_dir: Vector3, on_turret: bool, pierced: bool, calibre_scale: float) -> void:
	var d := Decal.new()
	var w := (0.75 if pierced else 0.6) * calibre_scale
	d.size = Vector3(w, 1.8, w)
	d.texture_albedo = Tex.named("hole" if pierced else "gouge")
	d.texture_normal = Tex.named("hole_normal" if pierced else "gouge_normal")
	d.upper_fade = 0.0
	d.lower_fade = 0.0
	var parent := turret if on_turret else visual
	parent.add_child(d)
	# A decal projects along its own down axis, so point its up axis out of the armour.
	var up := out_dir.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	d.global_transform = Transform3D(Basis(side, up, side.cross(up)).rotated(up, randf() * TAU), pos)
	scars.append(d)
	if scars.size() > MAX_SCARS:
		scars.pop_front().queue_free()


# ---- showing what is broken ----
var track_side := 0          # which track the last hit was nearest: -1 left, 1 right, 0 unknown
var _shown := {"tracks": false, "gun": false, "engine": false}
var _shed: Node3D            # the broken track lying on the ground
var _deck_fire: CPUParticles3D

# Makes each knocked-out module look it, and puts it right again when it is repaired.
#   tracks  the track on the side that was hit comes off and lies in pieces beside the vehicle
#   gun     the barrel droops, kinked, shorter, its muzzle brake gone
#   engine  flames come up through the engine deck
func _show_broken() -> void:
	for module in _shown:
		var broken: bool = modules[module] > 0.0
		if broken == _shown[module]:
			continue
		_shown[module] = broken
		match module:
			"tracks":
				var side := track_side if track_side != 0 else (1 if randf() < 0.5 else -1)
				_running["shed"] = [broken and side < 0, broken and side > 0]
				if _shed != null and is_instance_valid(_shed):
					_shed.queue_free()
				if broken:
					# The links, thrown off: a broken run of them along the ground on that side.
					_shed = Node3D.new()
					main.add_child(_shed)
					var soot := MeshUtil.material(Color(0.16, 0.15, 0.14), 0.9)
					var half_l: float = float(def["length"]) * 0.5
					var out: float = float(def["width"]) * 0.5 + 0.5
					var across: float = float(def["width"]) * 0.16
					for k in 16:
						if k % 5 == 3:
							continue  # gaps where it snapped
						var local := Vector3(side * (out + sin(k * 1.7) * 0.5), 0.06, lerpf(-half_l, half_l * 1.3, k / 15.0))
						var at := to_global(local)
						at.y = main.map.ground(at.x, at.z) + 0.05
						var link := MeshUtil.box(_shed, Vector3(across, 0.07, 0.36), Vector3.ZERO, soot)
						link.global_position = at
						link.rotation = Vector3(0, heading + sin(k * 2.3) * 0.5, 0)
					Fx.sparks(main, to_global(Vector3(side * out, 0.5, 0)), global_transform.basis.x * side, 0.8)
					Sfx.play("thud", global_position, 0.0, 0.7, 30.0)
			"gun":
				# Bent down and to one side, cut short (the brake and the last of the barrel are gone).
				slide.rotation = Vector3(-0.2, 0.14, 0.0) if broken else Vector3.ZERO
				slide.scale = Vector3(1, 1, 0.78) if broken else Vector3.ONE
				if broken:
					Fx.sparks(main, muzzle.global_position, -muzzle.global_transform.basis.z, 0.6)
			"engine":
				if _deck_fire == null:
					_deck_fire = MeshUtil.smoke(Color(1.0, 0.5, 0.12), 16, 0.9)
					_deck_fire.lifetime = 0.9
					_deck_fire.position = Vector3(0, hull_top + 0.1, float(def["length"]) * 0.3)
					add_child(_deck_fire)
				_deck_fire.emitting = broken


func _knock_out(module: String, seconds: float = MODULE_REPAIR_SECONDS) -> void:
	# Fitted equipment can shorten a repair (see kit.gd).
	seconds *= float(def.get("track_repair", 1.0)) if module == "tracks" else (float(def.get("engine_repair", 1.0)) if module == "engine" else 1.0)
	modules[module] = maxf(modules[module], seconds)
	if is_mine():
		Sfx.say({"tracks": "track", "engine": "engine", "gun": "gun"}[module])


# Blast from a shell that landed nearby. pen is the shell's HE penetration.
func take_splash(amount: float, pen: float, shooter) -> void:
	amount *= clampf(pen / float(def["armour"]["hull_side"]), 0.3, 1.2)
	if effect_active("armour"):
		amount *= float(ability["damage_taken_mult"])
	if randf() < 0.25:
		_knock_out("tracks")
	_hurt(amount, shooter, "Blast")


func stun(seconds: float) -> void:
	_knock_out("tracks", seconds)
	modules["gun"] = maxf(modules["gun"], seconds)
	main.spawn_fx(global_position + Vector3(0, 2, 0), 6.0, Color(0.6, 0.8, 1.0, 0.6), 0.6)


# Applies damage. Returns true if this destroyed the vehicle.
func _hurt(amount: float, shooter, how: String) -> bool:
	if _brew_t > 0.0:
		return false  # already dead and burning
	hp -= amount * float(Settings.rules["damage"])
	if amount > 0.0:
		main.damage_from(slot, shooter)
	if amount > 0.0 and shooter != null and is_instance_valid(shooter) and shooter.team != team:
		hurt_by[shooter.slot["id"]] = main.elapsed  # remembered for assists
	if main.mode["kind"] == "range" and is_mine():
		hp = maxf(hp, 1.0)  # on the test range you can be shot at all day
	refresh_damage_look()
	if hp > 0.0:
		return false
	if absf(speed) > 2.0 and how != "Ammo cook-off":
		# Killed on the move: it does not go up at once. Fire and smoke pour out of it for a
		# second or three while it rolls to a stop, and then it explodes.
		_brew_t = randf_range(1.0, 3.0)
		_brew_by = shooter
		_brew_how = how
		fire.emitting = true
		smoke.emitting = true
		# It is dead from this moment: whoever did it is paid now, and it turns black and
		# burns as it rolls, so nobody wastes another shell on it.
		for pair in mats:
			pair[0].albedo_color = Color(0.07, 0.07, 0.07)
		main.pay_kill(self, shooter)
		Sfx.play("explosion", global_position, 0.0, 0.8, 50.0)
		return true
	_blow_up(shooter, how)
	return true


func _blow_up(shooter, how: String) -> void:
	if _shed != null and is_instance_valid(_shed):
		get_tree().create_timer(30.0).timeout.connect(_shed.queue_free)
	main.spawn_fx(global_position + Vector3(0, 2, 0), 14.0, Color(1.0, 0.5, 0.1, 0.8), 0.9)
	Sfx.play("ammo", global_position, 4.0, 1.0, 70.0)
	main.on_tank_died(self, shooter, how)
	queue_free()


# Resolves one shell impact. pen is the shell's penetration at this range and dmg_mult scales
# its damage (special rounds). Returns a short result for the shooter's HUD ("" for bullets).
func take_hit(sd: Dictionary, pen: float, dmg_mult: float, pos: Vector3, dir: Vector3, normal: Vector3, shooter) -> String:
	var lp := to_local(pos)
	track_side = 1 if lp.x > 0.0 else -1  # (if this hit breaks a track, it is the one on this side)
	var on_turret := lp.y > hull_top + 0.02
	var key := ""
	var face := "side"
	var cosv := 1.0
	var roof := false
	if on_turret:
		var ld := turret.global_transform.basis.inverse() * dir
		if absf(ld.z) > absf(ld.x):
			face = "front" if ld.z > 0.0 else "side"
		key = "turret_" + face
		# How squarely it struck the plate it actually hit. (This used to take the better of the
		# front and side angles, so nothing ever glanced off a turret.)
		cosv = clampf(-dir.dot(normal), 0.0, 1.0)
		if def["turret_shape"] == "dome":
			cosv *= 0.88  # a rounded turret always presents some slope
		if absf(ld.y) > 0.6:
			roof = true
			key = "turret_side"
			cosv = absf(ld.y)
	else:
		var ln := global_transform.basis.inverse() * normal
		if absf(ln.y) > 0.7:
			roof = true
		elif ln.z < -0.5:
			face = "front"
		elif ln.z > 0.5:
			face = "rear"
		key = "hull_" + face
		cosv = clampf(-dir.dot(normal), 0.0, 1.0)
	var thick: float = def["armour"][key]
	if roof:
		thick *= 0.4
	var taken_mult := 1.0
	if effect_active("armour"):
		thick *= float(ability["armour_mult"])
		taken_mult = ability["damage_taken_mult"]
	var eff := thick / maxf(cosv, 0.15)
	var type: String = sd["type"]
	var out_dir := -dir if (on_turret or roof) else normal

	if sd["kind"] == "bullet":
		# Small arms: no module damage, no log line, and only the odd visible mark.
		var through := cosv >= 0.34 and pen >= eff
		# A bullet on armour is a sharp tick and a dull knock together. It sounds the same
		# whichever vehicle is hit and whether or not the round got through.
		Sfx.play("thud", pos, -12.0, 1.3, 12.0)
		Sfx.play("tink", pos, -5.0, 1.0, 16.0, 0.06)
		if is_mine():
			# From inside, every round on the hull comes through the armour.
			Sfx.play_ui("thud", 0.0 if Sfx.inside else -8.0, 1.2, "Interface")
			Sfx.play_ui("tink", -2.0 if Sfx.inside else -8.0, 1.0, "Interface")
		Fx.sparks(main, pos, out_dir, 0.2)
		if through:
			if randf() < 0.25:
				_add_scar(pos, out_dir, on_turret, true, 0.3)
			_hurt(float(sd["damage"]) * randf_range(0.8, 1.2) * taken_mult, shooter, "Machine gun")
		return ""

	var result := ""
	var dmg := 0.0
	var pierced := false
	var base := float(sd["damage"]) * dmg_mult * randf_range(0.85, 1.15)
	# module_mult (shells sheet): how likely this round is to knock out a module, against a
	# tank shell's 1. Small anti-aircraft rounds have a low one, or they would strip the tracks
	# and gun off anything in seconds.
	var wreck: float = float(sd.get("module_mult", 1.0))
	if type == "HE":
		# High explosive does not care much about angle. If it beats the plate the blast gets
		# inside; otherwise the damage falls away with how badly it was outmatched.
		var ratio := pen / maxf(thick, 1.0)
		if ratio >= 1.0:
			pierced = true
			result = "Overpressure"
			dmg = base * 1.3
			if randf() < wreck:
				_knock_out(["tracks", "engine", "gun"][randi() % 3])
		else:
			result = "Blast damage"
			dmg = base * clampf(ratio, 0.25, 1.0) * 0.7
			if randf() < 0.4 * wreck:
				_knock_out("tracks")
				result = "Track destroyed"
	elif randf() < _glance_chance(type, cosv):
		result = "Ricochet"
	elif pen >= eff:
		pierced = true
		result = "Penetration"
		dmg = base
		var roll := randf() / maxf(wreck, 0.001)
		if on_turret:
			if roll < 0.35:
				_knock_out("gun")
				result = "Gun knocked out"
		elif face == "rear":
			if roll < 0.6:
				_knock_out("engine")
				result = "Engine hit"
		elif face == "side":
			if roll < 0.14 and float(sd["damage"]) >= 150.0:
				# Into the ammunition. It catches and burns for a few seconds, then goes up.
				if ammo_fire <= 0.0:
					ammo_fire = AMMO_BURN_SECONDS
					_ammo_by = shooter
					fire.emitting = true
				result = "Ammo rack hit - burning"
			elif roll < 0.42:
				_knock_out("tracks")
				result = "Track destroyed"
		elif roll < 0.2:
			_knock_out("tracks")
			result = "Track destroyed"
	else:
		result = "Non-penetration"
	main.count_hit(result)
	main.tally(1 - team, "hit_" + key + ("_pen" if pierced else "_no"))
	var sound := "pen" if pierced else ("ricochet" if result == "Ricochet" else "thud")
	# Metal being holed: the lighter the round, the higher the note (the three pen recordings
	# run from light to heavy), with a dull knock under it for weight.
	var weight := 0 if float(sd["damage"]) < 60.0 else (1 if float(sd["damage"]) < 260.0 else 2)
	Sfx.play(sound, pos, 0.0, 1.0, 22.0, 0.05, weight if pierced else -1)
	if pierced:
		Sfx.play("thud", pos, -6.0, 0.9, 22.0)
	if is_mine():
		Sfx.play_ui(sound, 3.0 if Sfx.inside else -5.0, 0.85, "Interface")
	Fx.sparks(main, pos, out_dir, clampf(float(sd["damage"]) / 250.0, 0.4, 2.0))
	if pierced:
		Fx.smoke(main, pos, 0.8)
	# Taking a hit shoves the hull the way the shell was going.
	var shove := (global_transform.basis.inverse() * dir) * clampf(float(sd["damage"]) / max_hp, 0.0, 0.8)
	_rock_vel += Vector2(shove.z, -shove.x) * 2.7
	_add_scar(pos, out_dir, on_turret, pierced, clampf(float(sd["damage"]) / 300.0, 0.4, 1.6))
	if is_mine() and dmg > 30.0:
		Sfx.say("we_hit")
	if _hurt(dmg * taken_mult, shooter, result):
		return result + " - destroyed"
	return result
