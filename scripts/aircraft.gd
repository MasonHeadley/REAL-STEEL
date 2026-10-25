class_name Aircraft
extends CharacterBody3D
# A helicopter or a plane, flown by a player or by a simple bot pilot
# (data/aircraft.json; models in aircraft_model.gd; what it carries in ordnance.gd).
#
# Helicopters go where they are pointed: forward and back, sideways, up and down, turning to
# face where the pilot looks. They can set down anywhere, and one sitting on the ground
# counts towards capturing an objective.
# Planes never stop flying: they hold between their stalling speed and their top speed and
# turn towards where the pilot looks. Touching the ground wrecks one, except on its own
# team's airstrip at landing speed, where it rolls to a stop.
# Either kind, stopped on its own airstrip, is repaired and rearmed.
#
# The pilot's controls arrive in `want` (see player_ctrl.gd, or _bot_think below): move,
# lift, yaw, aim_dir, aim_at, fire, rocket, bomb, seek, missile, flare.
#
# Shot down, it does not vanish: something breaks off, it spins down burning, and it blows
# up where it lands, leaving a burnt wreck (see _go_down and _fall).

const CEILING := 420.0
const REARM_SECONDS := 4.0
const GUN_ARC := 0.9          # how far off the nose a helicopter's weapons can turn, radians
const LOCK_SECONDS := 2.0     # how long a missile's seeker must be held on an aircraft before it has it
const LOCK_RANGE := 1400.0
const LOCK_BOX := Vector2(0.1, 0.19)  # the seeker's view: this far off the nose sideways, and up and down (radians)
const FLARE_SECONDS := 2.5    # how long a flare goes on fooling missiles

static var sheet := {}
static var order: Array = []

var main
var def: Dictionary
var team := 0
var hp := 100.0
var want := {}
var heli := false
var bot := false          # flown by the computer
var landed := false
var speed := 0.0          # a plane's speed through the air, m/s
var throttle := 0.7       # a plane's throttle, 0..1
var facing := Basis.IDENTITY  # a plane's attitude
var yaw := 0.0
var stores: Array = []    # one for each pylon: {"kind", "left", "node", "at"}
var rockets := 0          # how many rockets, missiles and flares are left (counted from the stores)
var missiles := 0
var flares := 0
var bombs: Array = []     # the weights, kg, of the bombs still aboard
var flare_t := 0.0        # more than 0 while its flares are burning
var lock: Aircraft        # what its missile seeker is looking at
var lock_t := 0.0         # and for how long it has been
var threat_t := 0.0       # more than 0 while a missile is homing on it
var dying := false        # shot down and falling
var wrecked := false      # on the ground, burnt out
var _vel := Vector3.ZERO
var _gun_t := 0.0
var _rocket_t := 0.0
var _missile_t := 0.0
var _flare_cd := 0.0
var _tone_t := 0.0
var _rearm_t := 0.0
var _bomb_t := 0.0
var _rearmed := true      # nothing to do on the strip until it has been away
var _grace := 0.0         # just off the ground: seconds during which brushing it is forgiven
var _side := 1.0
var _model: Node3D
var _spin: Array = []
var _far: AudioStreamPlayer3D
var _near: AudioStreamPlayer3D
var _inside: AudioStreamPlayer
var _hidden := false   # something solid is between it and the listener
var _hidden_t := 0.0
var _killer = null        # who shot it down
var _spin_rate := 0.0     # how fast it is spinning as it falls
var _fall := Vector3.ZERO
var net_id := -1          # its number in a networked match, the same on every PC
var puppet := false       # a copy of an aircraft the host is flying: it goes where the host says and decides nothing
var remote_pilot := false # (host) flown by a player on another PC, whose controls arrive over the network
var owner_slot := {}      # the player flying it (empty for a bot): who is paid for what it kills
var net_pos := Vector3.ZERO
var net_vel := Vector3.ZERO
var net_rot := Quaternion.IDENTITY
var net_flags := 0
var _roll := 0.0          # how far a falling plane has rolled over
var threat_dist := 9999.0 # how far off the missile homing on it is
var _warn_t := 0.0
var _bot_t := 0.0
var _bot_target = null
var _bot_away := 0.0      # a bot plane pulling out of its attack: seconds left
var _gear: Array = []     # a plane's wheels that fold away (see AircraftModel _gear)
var gear_down := 1.0      # 1 wheels down, 0 tucked away


static func load_sheet() -> void:
	if not sheet.is_empty():
		return
	for row in JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft.json"))["rows"]:
		sheet[row["id"]] = row
		order.append(row["id"])


# What may hang on a pylon of this aircraft. A 1000 kg bomb only goes on the innermost ones.
static func allowed_on(row: Dictionary, pylon: int) -> Array:
	var per_side := int(row["pylons"])
	var inner := pylon == per_side - 1 or pylon == per_side
	var out: Array = []
	for kind in row["stores"]:
		if kind != "bomb1000" or inner:
			out.append(kind)
	return out


# A loadout made fit for this aircraft: the right length, and nothing it cannot carry.
static func fit_loadout(row: Dictionary, loadout: Array) -> Array:
	var usual: Array = row["loadout"]
	var out: Array = []
	for i in usual.size():
		var kind = loadout[i] if i < loadout.size() else usual[i]
		out.append(kind if (kind is String and allowed_on(row, i).has(kind)) else usual[i])
	return out


func setup(p_main, p_team: int, id: String, loadout: Array = []) -> void:
	main = p_main
	team = p_team
	load_sheet()
	def = sheet[id]
	heli = def["kind"] == "heli"
	hp = def["hp"]
	collision_layer = 2
	collision_mask = 1
	for e in main.map.edges:
		add_collision_exception_with(e)  # it flies straight through the invisible walls round the map
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 11.0)
	shape.shape = box
	shape.position.y = 1.6
	add_child(shape)
	var carried := fit_loadout(def, loadout)
	var built := AircraftModel.build(id, main.TEAM_COLORS[team], carried)
	_model = built["root"]
	_spin = built["spin"]
	_gear = built.get("gear", [])
	add_child(_model)
	for i in carried.size():
		stores.append({"kind": carried[i], "left": 0, "node": built["stores"][i], "at": built["pylons"][i]})
	_arm()
	# Three sounds: how it sounds from far off, from close by, and from the pilot's seat.
	# Whoever is flying hears the last; everyone else hears the first two, mixed by distance.
	var kind := "heli" if heli else ("prop" if AircraftModel.SHAPES[id].has("prop") else "jet")
	_far = Sfx.loop(kind + "_far", -80.0, 90.0)
	_near = Sfx.loop(kind + "_near", -80.0, 45.0)
	for p in [_far, _near]:
		p.max_distance = 1800.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP  # the pitch drops as it passes
		add_child(p)
	_inside = AudioStreamPlayer.new()
	var seats: Array = Sfx.streams.get(kind + "_in", [])
	if not seats.is_empty():
		_inside.stream = seats[(1 if id == "apache" else 0) % seats.size()]
	_inside.bus = "Engine"
	_inside.volume_db = -80.0
	_inside.autoplay = not Sfx.muted and _inside.stream != null
	add_child(_inside)


# ---- what it carries ----

# Fills every pylon again (at the start, and when rearmed on the airstrip).
func _arm() -> void:
	for st in stores:
		st["left"] = Ordnance.full(st["kind"])
		if st["node"] != null:
			st["node"].visible = true
	flares = int(def.get("flares", 2))
	_count()


func _count() -> void:
	rockets = 0
	missiles = 0
	bombs = []
	for st in stores:
		var info: Dictionary = Ordnance.INFO[st["kind"]]
		if info.has("rockets"):
			rockets += int(st["left"])
		elif info.has("missiles"):
			missiles += int(st["left"])
		elif info.has("bomb") and int(st["left"]) > 0:
			bombs.append(int(info["bomb"]))


# How much it is carrying, in the weight points that slow it (a half-empty pod weighs half).
func load_weight() -> float:
	var sum := 0.0
	for st in stores:
		var whole := Ordnance.full(st["kind"])
		if whole > 0:
			sum += float(Ordnance.INFO[st["kind"]]["weight"]) * (0.4 + 0.6 * float(st["left"]) / float(whole) if not Ordnance.INFO[st["kind"]].has("bomb") else float(st["left"]))
	return sum


func top_speed() -> float:
	return float(def["speed"]) * (1.0 - Ordnance.SLOW_PER_WEIGHT * load_weight())


# The fullest store that holds this sort of thing ("rockets", "bomb" or "missiles"), taking
# from each wing in turn so the aircraft empties evenly. Null if there is none left.
func _next_store(what: String):
	var best = null
	var best_score := -1.0
	for st in stores:
		if Ordnance.INFO[st["kind"]].has(what) and int(st["left"]) > 0:
			var score := float(st["left"]) + (1000.0 if signf((st["at"] as Vector3).x) == _side else 0.0)
			if score > best_score:
				best_score = score
				best = st
	if best != null:
		_side = -_side
	return best


func is_mine() -> bool:
	return main.player_air == self


func on_own_strip() -> bool:
	return main.map.on_strip(global_position) and signf(global_position.z) == (-1.0 if team == 0 else 1.0)


# A plane's wheels fold away once it is flying, and come down again when it is low and slow
# near a runway (or on the ground). Takes a couple of seconds either way.
func _gear_tick(delta: float) -> void:
	if _gear.is_empty():
		return
	var spd: float = net_vel.length() if puppet else speed
	var low := global_position.y - _ground()
	var near_strip: bool = absf(absf(global_position.z) - PushMap.STRIP_Z) < 450.0 and absf(global_position.x) < PushMap.STRIP_HALF + 450.0
	var down := landed or low < 4.0 or (near_strip and low < 90.0 and spd < float(def["stall"]) * 1.8)
	gear_down = move_toward(gear_down, 1.0 if down else 0.0, delta * 0.6)
	for g in _gear:
		(g[0] as Node3D).transform.basis = Basis(g[1], float(g[2]) * (1.0 - gear_down))


func _ground() -> float:
	return main.map.ground_any(global_position.x, global_position.z)


func _physics_process(delta: float) -> void:
	if wrecked:
		return
	if puppet:
		_follow_host(delta)
		_gear_tick(delta)
		return
	if dying:
		_fall_down(delta)
		return
	if main.prep_t > 0.0:
		# Engines running, nobody moves or shoots until the round starts.
		for s in _spin:
			s[0].rotate(s[1], s[2] * TAU * delta)
		want = {}
		_sound(delta)
		return
	if bot:
		_bot_think(delta)
	if heli:
		_fly_heli(delta)
	else:
		_fly_plane(delta)
	if dying or wrecked:
		return
	# Aircraft may go well past the edge of the map (see map.gd AIR_ROOM), but no further than this.
	var far: float = PushMap.AIR_LIMIT
	global_position.x = clampf(global_position.x, -PushMap.HALF_WIDTH - far, PushMap.HALF_WIDTH + far)
	global_position.z = clampf(global_position.z, -main.map.half_len - far, main.map.half_len + far)
	for s in _spin:
		s[0].rotate(s[1], s[2] * TAU * delta * (0.35 if landed and heli else 1.0))
	_gear_tick(delta)
	_sound(delta)
	_weapons(delta)
	# Stopped on its own airstrip: patched up and rearmed.
	if landed and on_own_strip() and speed < 3.0 and not _rearmed:
		_rearm_t += delta
		if _rearm_t >= REARM_SECONDS:
			_rearm_t = 0.0
			_rearmed = true
			_arm()
			hp = def["hp"]
			if is_mine():
				main.show_msg("Rearmed and repaired")
	else:
		_rearm_t = 0.0


func _sound(delta: float) -> void:
	# How hard the engine is working, 0 to 1.
	var power := throttle if not heli else clampf(0.45 + speed / float(def["speed"]) * 0.4 + absf(float(want.get("lift", 0.0))) * 0.25, 0.0, 1.0)
	if landed:
		power *= 0.5
	if is_mine():
		# From the pilot's seat: louder and higher the harder the engine is working.
		_inside.volume_db = lerpf(-14.0, -3.0, power)
		_inside.pitch_scale = lerpf(0.82, 1.22, power)
		_far.volume_db = -80.0
		_near.volume_db = -80.0
		return
	_inside.volume_db = -80.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Close by it is the near recording, far off the distant one, and a blend between.
	var away := cam.global_position.distance_to(global_position)
	var k := clampf((away - 110.0) / 340.0, 0.0, 1.0)
	_hidden_t -= delta
	if _hidden_t <= 0.0:
		_hidden_t = 0.25
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, global_position + Vector3(0, 1.5, 0), 1)
		_hidden = not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	var dull := -8.0 if _hidden else 0.0
	for pair in [[_near, 1.0 - k], [_far, k]]:
		var p: AudioStreamPlayer3D = pair[0]
		p.volume_db = move_toward(p.volume_db, maxf(linear_to_db(maxf(pair[1], 0.001)), -60.0) + dull, 60.0 * delta)
		p.pitch_scale = lerpf(0.9, 1.1, power)
		# Behind a building the top of the sound is lost.
		p.attenuation_filter_cutoff_hz = 1300.0 if _hidden else 9000.0
		p.attenuation_filter_db = -30.0 if _hidden else -8.0


# A copy of an aircraft the host is flying. It glides to where the host last said it was
# (carried on at its last known speed between messages), and shows what the host says is
# happening to it: shot down, it breaks up and burns; wrecked, it lies where it fell.
func _follow_host(delta: float) -> void:
	net_pos += net_vel * delta
	var ease := clampf(delta * 12.0, 0.0, 1.0)
	global_position = net_pos if global_position.distance_to(net_pos) > 80.0 else global_position.lerp(net_pos, ease)
	global_transform.basis = Basis(global_transform.basis.get_rotation_quaternion().slerp(net_rot, ease))
	landed = net_flags & 1 != 0
	if net_flags & 2 != 0 and not dying:
		dying = true
		_break_up()
	if net_flags & 4 != 0:
		_crash(net_pos, false)
		return
	for s in _spin:
		s[0].rotate(s[1], s[2] * TAU * delta * (0.35 if landed and heli else 1.0))
	_gear_tick(delta)
	_sound(delta)
	if is_mine():
		_tones(delta)


# What the pilot hears: the missile warning, and the seeker's ticking and its lock tone.
func _tones(delta: float) -> void:
	if threat_t > 0.0:
		# A missile is coming: beeps, quicker the closer it gets, and one long tone inside 100 m.
		_warn_t -= delta
		if _warn_t <= 0.0:
			_warn_t = 0.07 if threat_dist < 100.0 else clampf(threat_dist / 900.0, 0.12, 0.7)
			Sfx.play_ui("lock_tone", -5.0, 1.6)
	if lock != null and is_instance_valid(lock):
		_tone_t -= delta
		if _tone_t <= 0.0:
			var has_it := lock_t >= LOCK_SECONDS
			_tone_t = 0.11 if has_it else 0.42
			Sfx.play_ui("lock_tone", -9.0, 1.25 if has_it else 0.8)


# ---- flying ----

func _fly_heli(delta: float) -> void:
	var push: Vector3 = want.get("move", Vector3.ZERO)
	var lift: float = want.get("lift", 0.0)
	var top := top_speed()
	if not landed or lift > 0.0:
		yaw = lerp_angle(yaw, float(want.get("yaw", yaw)), minf(1.0, float(def["turn"]) * delta))
	var level := Basis(Vector3.UP, yaw)
	var go := Vector3.ZERO if landed else level * Vector3(push.x * 0.6, 0, push.z) * top
	_vel.x = lerpf(_vel.x, go.x, minf(1.0, 1.1 * delta))
	_vel.z = lerpf(_vel.z, go.z, minf(1.0, 1.1 * delta))
	_vel.y = lerpf(_vel.y, lift * float(def["climb"]), minf(1.0, 2.5 * delta))
	velocity = _vel
	move_and_slide()
	_vel = velocity
	var ground := _ground()
	if global_position.y <= ground + 0.02:
		global_position.y = ground
		_vel.y = maxf(_vel.y, 0.0)
		if not landed and Vector2(_vel.x, _vel.z).length() > 16.0:
			hurt(float(def["hp"]) * 0.6, null)  # came down far too fast across the ground
		landed = lift <= 0.0
		if not landed:
			_rearmed = false
	else:
		landed = false
	global_position.y = minf(global_position.y, CEILING)
	speed = _vel.length()
	rotation = Vector3(0, yaw, 0)
	# It leans the way it is going, and dips or lifts its nose towards where the pilot is aiming.
	var across := level.inverse() * _vel
	var aim_dir: Vector3 = want.get("aim_dir", level * Vector3.FORWARD)
	var nod := clampf(asin(clampf(aim_dir.y, -1.0, 1.0)), -0.45, 0.25) * 0.6 if not landed else 0.0
	_model.rotation = _model.rotation.lerp(Vector3(clampf(across.z / top, -1, 1) * 0.3 + nod, 0, clampf(-across.x / top, -1, 1) * 0.3), minf(1.0, 4.0 * delta))


func _fly_plane(delta: float) -> void:
	var push: Vector3 = want.get("move", Vector3.ZERO)
	throttle = clampf(throttle - push.z * 0.6 * delta, 0.0, 1.0)
	var top := top_speed()
	var stall := float(def["stall"])
	var ground := _ground()
	if landed:
		# Rolling on the ground: it steers a little, and lifts off once it is going fast enough.
		speed = move_toward(speed, throttle * top, (16.0 if throttle * top > speed else 22.0) * delta)
		yaw -= push.x * 0.6 * delta * clampf(speed / 10.0, 0.0, 1.0)
		facing = Basis(Vector3.UP, yaw)
		global_position += facing * Vector3.FORWARD * speed * delta
		global_position.y = _ground()
		if speed > stall * 1.05:
			# Off the ground: lifted clear, nose up, and a few seconds' grace near the ground.
			landed = false
			_rearmed = false
			_grace = 4.0
			global_position.y += 2.4
			facing = facing * Basis(Vector3.RIGHT, 0.22)
		elif not main.map.on_strip(global_position) and speed > 6.0:
			hurt(float(def["hp"]) * 0.5 * delta, null)  # off the strip into the rough
	else:
		speed = clampf(move_toward(speed, lerpf(stall, top, throttle), 22.0 * delta), stall * 0.9, top)
		# Turn towards where the pilot is looking, as fast as the aircraft can.
		var aim: Vector3 = want.get("aim_dir", facing * Vector3.FORWARD)
		var nose := facing * Vector3.FORWARD
		var off := nose.angle_to(aim)
		if off > 0.002:
			var axis := nose.cross(aim).normalized()
			facing = (Basis(axis, minf(off, float(def["turn"]) * delta)) * facing).orthonormalized()
		nose = facing * Vector3.FORWARD
		# Keep the wings level-ish, rolled into the turn.
		var flat := Vector3(nose.x, 0, nose.z).normalized()
		yaw = atan2(-flat.x, -flat.z)
		var hard := 1.0 + 0.9 * clampf(speed / float(def["speed"]), 0.0, 1.0)  # the faster it goes, the further over it leans
		var bank := clampf(nose.cross(aim).y * 2.6 * hard, -1.45, 1.45) if off > 0.02 else 0.0
		facing = Basis.looking_at(nose, Vector3.UP).rotated(nose, -bank).slerp(facing, 0.82).orthonormalized()
		velocity = nose * speed
		move_and_slide()
		for i in get_slide_collision_count():
			if not get_slide_collision(i).get_collider().has_meta("edge"):
				hurt(9999.0, null)  # flew into a building
				return
		# Only at the very limit, far past the edge of the map, is the nose brought round towards the middle.
		if main.map.inside_by(global_position, true) < PushMap.AIR_ROOM - PushMap.AIR_LIMIT + 60.0:
			var home := (Vector3(0, global_position.y, 0) - global_position).normalized()
			facing = Basis.looking_at(nose.slerp(home, minf(1.0, 1.6 * delta)), Vector3.UP)
		global_position.y = minf(global_position.y, CEILING)
		_grace -= delta
		if global_position.y <= ground + 1.3 and (_grace > 0.0 or nose.y > 0.04):
			global_position.y = ground + 1.3  # climbing away, or only just airborne: it skims, it does not crash
		elif global_position.y <= ground + 1.3:
			if main.map.on_strip(global_position) and speed < stall * 1.7 and nose.y > -0.3:
				landed = true
				global_position.y = ground
			else:
				hurt(9999.0, null)  # into the ground
				return
	global_transform = Transform3D(facing, global_position)
	_model.rotation = Vector3.ZERO


# ---- the bot pilot ----

# Fills `want` the way a player's hands would. A helicopter comes up to its target, stands
# off and shoots; a plane dives on it, pulls out, flies clear and comes round again. Jets
# go for other aircraft first and use their missiles on them.
func _bot_think(delta: float) -> void:
	_bot_t -= delta
	if _bot_t <= 0.0:
		_bot_t = 0.7
		_bot_target = _bot_pick()
	var tgt = _bot_target if (_bot_target != null and is_instance_valid(_bot_target)) else null
	var goal: Vector3 = tgt.global_position + Vector3(0, 1.5, 0) if tgt != null else main.objective_pos() + Vector3(0, 30.0, 0)
	# Well outside the map (going round for another pass), it heads back in before it is out of the battle.
	if main.map.inside_by(global_position, true) < PushMap.AIR_ROOM - 250.0:
		tgt = null
		_bot_away = 0.0
		goal = Vector3(0, global_position.y, 0)
	var to := goal - global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	var nose := -global_transform.basis.z
	var clock: float = main.elapsed + float(get_instance_id() % 7)
	want = {"flare": threat_t > 0.0 and randf() < delta * 1.2}
	if heli:
		var height := global_position.y - _ground()
		want["lift"] = clampf((42.0 - height) / 8.0, -1.0, 1.0)
		want["yaw"] = atan2(-flat.x, -flat.z) if dist > 2.0 else yaw
		want["move"] = Vector3(sin(clock * 0.45) * 0.7, 0, -1.0 if dist > 190.0 else (0.7 if dist < 110.0 else 0.0))
		want["aim_dir"] = to.normalized()
		want["aim_at"] = goal
		var shooting: bool = tgt != null and dist < 330.0 and height > 12.0
		want["fire"] = shooting and int(clock * 1.4) % 3 == 0
		want["rocket"] = shooting and tgt is Tank and int(clock) % 5 == 0
		return
	# A plane.
	want["move"] = Vector3(0, 0, -1.0 if throttle < 0.85 else 0.0)
	var aim := to.normalized()
	var height := global_position.y - _ground()
	_bot_away -= delta
	var chasing: bool = tgt is Aircraft
	if not chasing and _bot_away <= 0.0 and (to.length() < 240.0 or height < 45.0):
		_bot_away = 8.0  # close enough: pull out and go round again
	if _bot_away > 0.0:
		aim = (Vector3(nose.x, 0, nose.z).normalized() + Vector3(0, 0.4, 0)).normalized()
	elif not chasing and tgt == null:
		aim = (flat.normalized() + Vector3(0, clampf((120.0 - height) / 200.0, -0.2, 0.3), 0)).normalized()
	if height < 40.0 and aim.y < 0.25:
		aim = (aim + Vector3(0, 0.5, 0)).normalized()
	if tgt != null and _bot_away <= 0.0:
		# It does not hold its sights dead on the target. It walks its fire through it: the nose
		# swings from short of the target to beyond it, and from one side to the other, so the
		# middle of each burst is what passes over it.
		var along := flat.normalized() if dist > 1.0 else nose
		var beside := along.cross(Vector3.UP)
		var reach := to.length()
		aim = (to + along * sin(clock * 1.7) * reach * 0.07 + beside * sin(clock * 1.1) * reach * 0.05 + Vector3(0, sin(clock * 2.3) * reach * (0.05 if chasing else 0.0), 0)).normalized()
		if height < 40.0 and aim.y < 0.25:
			aim = (aim + Vector3(0, 0.5, 0)).normalized()
	want["aim_dir"] = aim
	# It fires in short bursts while the target is anywhere near the nose, not only when it is dead ahead.
	var on_it: bool = tgt != null and _bot_away <= 0.0 and nose.angle_to(to.normalized()) < 0.12 and int(clock * 0.9) % 2 == 0
	want["fire"] = on_it and to.length() < 650.0
	want["rocket"] = on_it and tgt is Tank and to.length() < 600.0 and nose.angle_to(to.normalized()) < 0.06
	want["bomb"] = tgt is Tank and _bot_away <= 0.0 and dist < 60.0 + speed * sqrt(maxf(height, 1.0) / 4.9) * 0.9 and nose.angle_to(flat.normalized()) < 0.5
	want["seek"] = chasing and missiles > 0
	want["missile"] = chasing and lock_t >= LOCK_SECONDS


func _bot_pick():
	var best = null
	var best_d := INF
	if not heli:
		# Other aircraft first.
		for a in main.aircraft:
			if is_instance_valid(a) and a.team != team and not a.dying and not a.wrecked and not a.landed:
				var d: float = a.global_position.distance_to(global_position)
				if d < 1600.0 and d < best_d:
					best_d = d
					best = a
		if best != null:
			return best
	for t in main.tanks:
		var d: float = t.global_position.distance_to(global_position)
		if t.team != team and d < (700.0 if heli else 2500.0) and d < best_d:
			best_d = d
			best = t
	return best


# How it is moving through the air, for anything that must aim ahead of it.
func motion() -> Vector3:
	if dying:
		return _fall
	return _vel if heli else velocity


# ---- weapons ----

# Which way the weapons fire. A plane's point where the plane does. A helicopter's turn to
# hit the very spot the pilot is looking at ("aim_at", found by player_ctrl.gd), as long as
# that is within GUN_ARC of the nose; past that they fire straight ahead.
func gun_aim(from: Vector3) -> Vector3:
	var nose := -global_transform.basis.z
	if not heli:
		return nose
	var aim: Vector3 = want.get("aim_dir", nose)
	if want.has("aim_at"):
		aim = ((want["aim_at"] as Vector3) - from).normalized()
	return aim if nose.angle_to(aim) <= GUN_ARC else nose


func _weapons(delta: float) -> void:
	_gun_t -= delta
	_rocket_t -= delta
	_missile_t -= delta
	_bomb_t -= delta
	_flare_cd -= delta
	flare_t -= delta
	threat_t -= delta
	var nose := -global_transform.basis.z
	var from := global_position + Vector3(0, 1.2, 0) + nose * 6.0
	var aim := gun_aim(from)
	if threat_t <= 0.0:
		threat_dist = 9999.0
	_seek(delta, nose)
	if is_mine():
		_tones(delta)
	var locked := lock != null and lock_t >= LOCK_SECONDS
	if want.get("fire", false) and _gun_t <= 0.0 and not (want.get("seek", false) and locked):
		_gun_t = float(def["gun_gap"])
		var dir := (aim + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (0.022 if bot else 0.006)).normalized()  # a bot's shooting is looser
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 900.0, 1 | 2 | 4 | 8 | Prop.LAYER)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var at: Vector3 = hit["position"] if not hit.is_empty() else from + dir * 900.0
		Fx.tracer(main, from, at)
		Sfx.play("autocannon", from, -7.0, 1.1, 38.0, 0.03)
		main.tell_air_fx("gun", from, at, 0, false)
		if not hit.is_empty():
			_strike(hit["collider"], at, dir, hit["normal"], float(def["gun_damage"]), 60.0, false)
	if want.get("bomb", false) and _bomb_t <= 0.0 and not landed:
		var rack = _next_store("bomb")
		if rack != null:
			_bomb_t = 0.35
			rack["left"] = 0
			if rack["node"] != null:
				rack["node"].visible = false
			var b := Bomb.new()
			b.main = main
			b.team = team
			b.weight = int(Ordnance.INFO[rack["kind"]]["bomb"])
			b.kind = rack["kind"]
			b.east = def.get("east", false)
			b.mine = not owner_slot.is_empty()
			b.slot = owner_slot
			b.vel = _vel if heli else velocity
			main.add_child(b)
			b.global_position = to_global(rack["at"]) - Vector3(0, 0.5, 0)
			main.tell_air_fx("bomb", b.global_position, b.vel, b.weight, b.east)
			_count()
	if want.get("rocket", false) and _rocket_t <= 0.0:
		var pod = _next_store("rockets")
		if pod != null:
			_rocket_t = 0.22
			pod["left"] = int(pod["left"]) - 1
			var r := Rocket.new()
			r.owner_craft = self
			r.east = def.get("east", false)
			main.add_child(r)
			r.global_position = to_global(pod["at"]) + nose * 1.5 - Vector3(0, 0.3, 0)
			r.vel = aim * 240.0 + (velocity if not heli else _vel)
			Sfx.play("rocket", r.global_position, -1.0, 0.9, 70.0)
			main.tell_air_fx("rocket", r.global_position, r.vel, 0, r.east)
			_count()
	if want.get("missile", false) and locked and _missile_t <= 0.0:
		var rail = _next_store("missiles")
		if rail != null:
			_missile_t = 1.0
			rail["left"] = 0
			if rail["node"] != null:
				rail["node"].visible = false
			Missile.launch(main, self, to_global(rail["at"]) + nose * 2.0, nose * (speed + 60.0), lock, def.get("east", false))
			lock_t = 0.0
			_count()
	if want.get("flare", false) and _flare_cd <= 0.0 and flares > 0:
		flares -= 1
		_flare_cd = 1.5
		flare_t = FLARE_SECONDS
		Sfx.play("click", global_position, 0.0, 0.7, 30.0)
		for k in 4:
			var f := Flare.new()
			f.vel = (velocity if not heli else _vel) * 0.6 + global_transform.basis.x * (k - 1.5) * 9.0 + Vector3(0, -6.0, 0)
			main.add_child(f)
			f.global_position = global_position + Vector3(0, 0.5, 0)
			main.tell_air_fx("flare", f.global_position, f.vel, 0, false)


# The missile seeker. While the pilot holds it on (want "seek"), it looks straight ahead in a
# tall narrow box; an enemy aircraft held inside that box for LOCK_SECONDS is locked. The
# player hears it: slow ticks while it has something, a fast tone once it is locked.
func _seek(delta: float, nose: Vector3) -> void:
	var found: Aircraft = null
	if want.get("seek", false) and missiles > 0 and not heli:
		var best := INF
		for a in main.aircraft:
			if not is_instance_valid(a) or a.team == team or a.dying or a.wrecked:
				continue
			var to: Vector3 = a.global_position + Vector3(0, 1.5, 0) - global_position
			var local := global_transform.basis.inverse() * to
			if local.z > -30.0 or to.length() > LOCK_RANGE:
				continue
			if absf(atan2(local.x, -local.z)) > LOCK_BOX.x or absf(atan2(local.y, -local.z)) > LOCK_BOX.y:
				continue
			var q := PhysicsRayQueryParameters3D.create(global_position + nose * 8.0, a.global_position + Vector3(0, 1.5, 0), 1 | 4)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty() and to.length() < best:
				best = to.length()
				found = a
	if found != null and found == lock:
		lock_t += delta
	else:
		lock_t = 0.0
	lock = found


# What a round or a rocket does to whatever it hit.
func _strike(col, at: Vector3, dir: Vector3, normal: Vector3, damage: float, pen: float, big: bool) -> void:
	if col is Tank and col.team != team:
		if not owner_slot.is_empty():
			col.credit = owner_slot
			col.credit_t = main.elapsed
		var like: Dictionary = GameData.shells["76s_heat" if big else "30_ap"].duplicate()
		like["damage"] = damage
		var result: String = col.take_hit(like, pen, 1.0, at, dir, normal, null)
		if big and is_mine():
			main.show_msg(result)
	elif col is Soldier and col.team != team:
		if not owner_slot.is_empty() and col.state == "up":
			main.award(owner_slot, "infantry")
		col.hit("blast" if big else "bullet")
	elif col is Aircraft and col.team != team:
		col.hurt(damage, self)
	elif col is Prop:
		col.knock(dir * (9000.0 if big else 60.0), at)
	elif not big:
		Fx.dust(main, at, 0.2)


# ---- being hit, and going down ----

func hurt(amount: float, by) -> void:
	if hp <= 0.0 or dying or wrecked:
		return
	if main.args.has("--airlog"):
		print("AIRLOG hurt %.0f at %s ground %.1f speed %.0f landed %s hits %d" % [amount, global_position.snapped(Vector3.ONE), _ground(), speed, landed, get_slide_collision_count()])
	hp -= amount
	main.damage_from(owner_slot, by)
	if by != null:
		_killer = by
	if hp > 0.0:
		return
	_go_down()


# Shot down. Something breaks off (a helicopter's tail; a plane's wing or tail), it catches
# fire, and from here _fall_down flies it: out of control, losing height faster and faster.
func _go_down() -> void:
	_break_up()
	main.air_shot_down(self, _killer)


func _break_up() -> void:
	dying = true
	hp = 0.0
	want = {}
	lock = null
	collision_layer = 0  # nothing more can hit it
	main.spawn_fx(global_position + Vector3(0, 2, 0), 9.0, Color(1.0, 0.5, 0.1, 0.8), 0.5)
	Fx.blast(main, global_position + Vector3(0, 1.5, 0), 1.4)
	Sfx.play("explosion", global_position, 3.0, 0.9, 80.0)
	# The fall starts from how it was moving when it was hit.
	_fall = _vel if heli else velocity
	if landed:
		_fall = Vector3.ZERO
	# What breaks off: every part of the model that lies in the chosen bit of it.
	var pick := 0 if heli else randi() % 3  # 0 the tail, 1 the left wing, 2 the right wing
	var loose := Debris.new()
	loose.main = main
	loose.vel = _fall * 0.8 + Vector3(randf_range(-6, 6), 5.0, randf_range(-6, 6))
	main.add_child(loose)
	loose.global_transform = _model.global_transform
	for part in _model.get_children():
		var middle: Vector3 = part.position
		if part is MeshInstance3D and part.mesh != null:
			middle = part.transform * part.mesh.get_aabb().get_center()
		var goes: bool = middle.z > (5.2 if heli else 3.6) if pick == 0 else (middle.x * (-1.0 if pick == 1 else 1.0) > 1.3 and absf(middle.z) < 3.4)
		if goes:
			_spin = _spin.filter(func(s): return s[0] != part)
			part.reparent(loose)
	# Fire and smoke pour out of it all the way down (and the smoke goes on after).
	for look in [[Color(1.0, 0.55, 0.12, 0.9), 26, 2.2], [Color(0.08, 0.08, 0.08, 0.85), 34, 3.6]]:
		var p := MeshUtil.smoke(look[0], look[1], look[2])
		p.position = Vector3(0, 1.8, 1.0)
		p.name = "Fire" if look[1] == 26 else "Smoke"
		add_child(p)
		p.emitting = true
	_spin_rate = 1.5 if heli else 0.4
	_roll = 0.0


# Falling out of the sky. A helicopter spins faster and faster about its mast; a plane rolls
# and its nose drops. Either way the fall begins at whatever rate it was climbing or sinking
# when it was hit and speeds up the further it goes, never past the aircraft's own top speed.
func _fall_down(delta: float) -> void:
	var top := float(def["speed"])
	_fall.y -= (5.0 + absf(_fall.y) * 0.9) * delta
	_fall.x *= 1.0 - 0.25 * delta
	_fall.z *= 1.0 - 0.25 * delta
	_fall = _fall.limit_length(top)
	_spin_rate = minf(_spin_rate + 2.5 * delta, 7.5)
	var from := global_position + Vector3(0, 1.0, 0)
	var to := from + _fall * delta
	var q := PhysicsRayQueryParameters3D.create(from, to + _fall.normalized() * 2.0, 1 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var ground: float = main.map.ground_any(to.x, to.z)
	if not hit.is_empty() or to.y - 1.0 <= ground or (landed and _spin_rate > 4.0):
		_crash(hit["position"] if not hit.is_empty() else Vector3(to.x, ground, to.z), not hit.is_empty() and to.y - 1.0 > ground + 3.0)
		return
	global_position = to - Vector3(0, 1.0, 0)
	if heli:
		yaw += _spin_rate * delta
		rotation = Vector3(sin(main.elapsed * 3.0) * 0.25, yaw, cos(main.elapsed * 2.3) * 0.3)
	else:
		var nose := (_fall.normalized() if _fall.length() > 1.0 else facing * Vector3.FORWARD)
		# (The roll builds up from nothing: it used to jump straight to a fast spin.)
		_roll += _spin_rate * 0.55 * delta
		facing = Basis.looking_at(nose, Vector3.UP).rotated(nose, _roll)
		global_transform = Transform3D(facing, global_position)
	for s in _spin:
		s[0].rotate(s[1], s[2] * TAU * delta * 0.4)
	_sound(delta)


# It hits: the explosion, and then what is left of it lies burnt where it fell.
func _crash(at: Vector3, on_a_building: bool) -> void:
	dying = false
	wrecked = true
	global_position = at
	main.spawn_fx(at + Vector3(0, 2, 0), 18.0, Color(1.0, 0.5, 0.1, 0.85), 0.9)
	Fx.blast(main, at, 2.6)
	Fx.dirt(main, at, 7.0)
	Sfx.play("ammo", at, 4.0, 0.9, 90.0)
	for p in [_far, _near, _inside]:
		p.stop()
	# Burnt black, lying askew. On a roof it stays where it struck; on the ground it settles flat.
	var soot := MeshUtil.material(Color(0.06, 0.06, 0.06), 0.95)
	for part in _model.find_children("*", "MeshInstance3D", true, false):
		part.material_override = soot
	rotation = Vector3(randf_range(-0.25, 0.25), rotation.y, randf_range(0.3, 0.6) * (1.0 if randf() < 0.5 else -1.0))
	_model.rotation = Vector3.ZERO
	_model.position.y = 0.0 if on_a_building else -0.5
	if has_node("Fire"):
		get_tree().create_timer(6.0).timeout.connect(func():
			if is_instance_valid(self) and has_node("Fire"):
				(get_node("Fire") as CPUParticles3D).emitting = false)
	main.aircraft.erase(self)
	# Whoever was flying it sees it burn for a moment before the game moves on.
	get_tree().create_timer(1.2).timeout.connect(func():
		if is_instance_valid(self):
			main.air_wrecked(self, _killer))
	get_tree().create_timer(40.0).timeout.connect(queue_free)


# A bomb: it leaves with the aircraft's own speed and falls. The heavier it is, the bigger
# the burst: 100 kg clears a street corner, 1000 kg a whole block. It is heard whistling down.
class Bomb extends Node3D:
	var main
	var team := 0
	var weight := 100
	var kind := "bomb100"
	var east := false
	var mine := false  # dropped by a player: kills with it are theirs
	var slot := {}     # that player
	var ghost := false # a copy of a bomb the host dropped: it falls and bursts for show, and hurts nothing
	var vel := Vector3.ZERO
	var _heard := false

	func _ready() -> void:
		var body := Ordnance.build(kind, east)
		if body != null:
			add_child(body)

	func _physics_process(delta: float) -> void:
		# It starts with whatever rate the aircraft was climbing or sinking at, then drops
		# faster and faster (more than plain gravity: bombs that floated down looked wrong).
		vel.y = maxf(vel.y - (12.0 + absf(minf(vel.y, 0.0)) * 0.5) * delta, -220.0)
		vel.x *= 1.0 - 0.08 * delta
		vel.z *= 1.0 - 0.08 * delta
		var from := global_position
		var to := from + vel * delta
		var ground: float = main.map.ground_any(to.x, to.z)
		if not _heard and vel.y < 0.0:
			var up := maxf(from.y - ground, 0.0)
			var left := (vel.y + sqrt(vel.y * vel.y + 2.0 * 9.81 * up)) / 9.81
			if left <= 1.6:
				_heard = true
				Sfx.play("incoming", Vector3(from.x + vel.x * left, ground, from.z + vel.z * left), 2.0, 1.0, 45.0, 0.02)
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() and to.y > ground:
			global_position = to
			if vel.length() > 1.0:
				look_at(to + vel, Vector3.UP)
			return
		_burst(hit["position"] if not hit.is_empty() else Vector3(to.x, ground, to.z))

	func _burst(at: Vector3) -> void:
		var step := 0 if weight <= 100 else (1 if weight <= 500 else 2)
		var radius: float = [12.0, 24.0, 36.0][step]
		var damage: float = [300.0, 800.0, 1500.0][step]
		var pen: float = [50.0, 110.0, 180.0][step]
		main.spawn_fx(at + Vector3(0, 1.5, 0), radius * 0.6, Color(1.0, 0.72, 0.28, 0.9), 0.4)
		Fx.blast(main, at, [1.6, 3.2, 5.0][step])
		Fx.dirt(main, at, radius * 0.6)
		Fx.smoke(main, at + Vector3(0, 2.5, 0), radius * 0.6)
		Fx.dust(main, at + Vector3(0, 1.0, 0), radius * 0.5)
		Sfx.play("ammo", at, 4.0, [1.15, 0.95, 0.8][step], 70.0)
		if ghost:
			queue_free()
			return
		for t in main.tanks.duplicate():
			var d: float = t.global_position.distance_to(at)
			if t.team != team and d < radius:
				if mine:
					t.credit = slot
					t.credit_t = main.elapsed
				t.take_splash(damage * (1.0 - d / radius), pen, null)
		for s in main.soldiers.duplicate():
			if s.team != team and s.global_position.distance_to(at) < radius:
				s.hit("blast")
		for p in get_tree().get_nodes_in_group("props"):
			var gap: float = p.global_position.distance_to(at)
			if gap < radius * 1.3:
				p.knock(((p.global_position - at).normalized() + Vector3(0, 0.5, 0)) * 9000.0 * (1.0 - gap / (radius * 1.3)), at)
		queue_free()


# An unguided rocket: it flies straight and fast, drooping a little, and bursts on what it hits.
class Rocket extends Node3D:
	var owner_craft
	var vel := Vector3.ZERO
	var life := 5.0
	var east := false
	var ghost_main = null  # set on a copy of a rocket the host fired: it flies and bursts for show only

	func _ready() -> void:
		add_child(Ordnance.flying("rocket", east))
		var trail := MeshUtil.smoke(Color(0.8, 0.8, 0.8, 0.5), 14, 0.5)
		trail.lifetime = 0.7
		add_child(trail)
		trail.emitting = true

	func _physics_process(delta: float) -> void:
		life -= delta
		vel.y -= 6.0 * delta  # rockets fall as they fly
		var from := global_position
		var to := from + vel * delta
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4 | 8 | Prop.LAYER)
		if is_instance_valid(owner_craft):
			q.exclude = [owner_craft.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() and life > 0.0:
			global_position = to
			look_at(to + vel, Vector3.UP)
			return
		var at: Vector3 = hit["position"] if not hit.is_empty() else to
		if ghost_main != null:
			ghost_main.spawn_fx(at, 4.0, Color(1.0, 0.7, 0.25, 0.85), 0.25)
			Fx.blast(ghost_main, at, 1.2)
			Sfx.play("explosion", at, 0.0, 1.1, 45.0)
		elif is_instance_valid(owner_craft):
			var craft = owner_craft
			var main = craft.main
			main.spawn_fx(at, 4.0, Color(1.0, 0.7, 0.25, 0.85), 0.25)
			Fx.blast(main, at, 1.2)
			Sfx.play("explosion", at, 0.0, 1.1, 45.0)
			if not hit.is_empty():
				craft._strike(hit["collider"], at, vel.normalized(), hit["normal"], float(craft.def["rocket_damage"]), float(craft.def["rocket_pen"]), true)
			for s in main.soldiers.duplicate():
				if s.team != craft.team and s.global_position.distance_to(at) < 6.0:
					s.hit("blast")
			for t in main.tanks.duplicate():
				if t.team != craft.team and t != hit.get("collider") and t.global_position.distance_to(at) < 5.0:
					t.take_splash(float(craft.def["rocket_damage"]) * 0.4, 30.0, null)
		queue_free()


# A heat-seeking missile. It turns after its target as hard as it can and bursts beside it.
# Flares fool it (most of the time), and it is spent if it hits a building or the ground, or
# runs out of fuel. An aircraft's missile is one of these; so is an anti-aircraft vehicle's.
# With no target it flies straight, and will still burst on whatever it hits.
class Missile extends Node3D:
	const SPEED := 330.0
	const TURN := 1.9        # radians a second: more than any aircraft, but not by a lot at close range
	const NEAR := 9.0        # it bursts within this many metres of its target
	var main
	var team := 0
	var by               # who fired it, for the kill
	var target
	var vel := Vector3.ZERO
	var life := 9.0
	var damage := 330.0
	var east := false
	var ghost := false   # a copy of a missile the host fired: it flies and bursts for show only
	var _fooled := false

	static func launch(p_main, p_by, from: Vector3, p_vel: Vector3, p_target, p_east: bool) -> Missile:
		var m := Missile.new()
		m.main = p_main
		m.by = p_by
		m.team = p_by.team
		m.target = p_target
		m.vel = p_vel
		m.east = p_east
		p_main.add_child(m)
		m.global_position = from
		Sfx.play("rocket", from, 2.0, 0.8, 90.0)
		p_main.tell_air_fx("missile", from, p_vel, int(p_target.net_id) if (p_target != null and p_target is Aircraft) else -1, p_east)
		return m

	func _ready() -> void:
		add_child(Ordnance.flying("missile", east))
		var trail := MeshUtil.smoke(Color(0.9, 0.9, 0.9, 0.6), 30, 0.9)
		trail.lifetime = 1.6
		add_child(trail)
		trail.emitting = true

	func _physics_process(delta: float) -> void:
		life -= delta
		var has_target: bool = target != null and is_instance_valid(target) and not (target is Aircraft and (target.dying or target.wrecked))
		var speed := minf(vel.length() + 260.0 * delta, SPEED)
		var dir := vel.normalized()
		if has_target:
			var mark: Vector3 = target.global_position + Vector3(0, 1.5, 0)
			if target is Aircraft and not ghost:
				target.threat_t = 0.4
				target.threat_dist = global_position.distance_to(mark)
				if target.flare_t > 0.0 and not _fooled:
					_fooled = true
					if randf() < 0.8:
						target = null  # it goes for the flare and flies on blind
						has_target = false
			if has_target:
				var to := mark - global_position
				if to.length() < NEAR:
					_burst(global_position, target)
					return
				var off := dir.angle_to(to.normalized())
				if off > 0.001:
					dir = (Basis(dir.cross(to).normalized(), minf(off, TURN * delta)) * dir).normalized()
		vel = dir * speed
		var from := global_position
		var to_pos := from + vel * delta
		var q := PhysicsRayQueryParameters3D.create(from, to_pos, 1 | 2 | 4)
		if by != null and is_instance_valid(by):
			q.exclude = [by.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			_burst(hit["position"], hit["collider"])
			return
		if life <= 0.0:
			_burst(to_pos, null)
			return
		global_position = to_pos
		look_at(to_pos + vel, Vector3.UP)

	func _burst(at: Vector3, what) -> void:
		main.spawn_fx(at, 6.0, Color(1.0, 0.7, 0.25, 0.85), 0.3)
		Fx.blast(main, at, 1.5)
		Sfx.play("explosion", at, 2.0, 1.0, 70.0)
		var shooter = by if (by != null and is_instance_valid(by)) else null
		if ghost:
			queue_free()
			return
		if what is Aircraft and what.team != team:
			what.hurt(damage, shooter)
		elif what is Tank and what.team != team:
			var warhead: Dictionary = GameData.shells["76s_heat"].duplicate()
			warhead["damage"] = damage
			what.take_hit(warhead, 400.0, 1.0, at, vel.normalized(), -vel.normalized(), shooter if shooter is Tank else null)
		queue_free()


# A flare: a bright spark that drops away behind the aircraft and burns out.
class Flare extends Node3D:
	var vel := Vector3.ZERO
	var life := 2.5

	func _ready() -> void:
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(1.0, 0.9, 0.6)
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 6
		sphere.rings = 3
		ball.mesh = sphere
		ball.material_override = glow
		add_child(ball)
		var trail := MeshUtil.smoke(Color(1.0, 0.95, 0.85, 0.5), 16, 0.8)
		trail.lifetime = 1.2
		add_child(trail)
		trail.emitting = true

	func _physics_process(delta: float) -> void:
		life -= delta
		vel.y -= 7.0 * delta
		vel *= 1.0 - 0.8 * delta
		global_position += vel * delta
		if life <= 0.0:
			queue_free()


# A piece broken off an aircraft: it tumbles away and falls, and lies where it lands for a while.
class Debris extends Node3D:
	var main
	var vel := Vector3.ZERO
	var _down := false
	var _turn := Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))

	func _physics_process(delta: float) -> void:
		if _down:
			return
		vel.y -= 9.81 * delta
		global_position += vel * delta
		rotation += _turn * delta
		var ground: float = main.map.ground_any(global_position.x, global_position.z)
		if global_position.y <= ground + 0.3:
			global_position.y = ground + 0.3
			_down = true
			Fx.dust(main, global_position, 1.5)
			get_tree().create_timer(30.0).timeout.connect(queue_free)
