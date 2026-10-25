class_name Soldier
extends CharacterBody3D
# An army man, built from a row of the infantry sheet. His figure and how it moves are in
# soldier_model.gd; this is what he does.
#   assault  runs for the objective, trades rifle fire, lobs grenades at tanks that come close
#   gunner   drops prone behind a belt-fed machine gun and sprays enemy infantry
#   medic    throws a small smoke grenade over a fallen teammate, drags him behind cover
#            and gets him back on his feet
# Rifle and machine-gun fire knocks a soldier down, where a medic can still save him.
# Shells, blasts and tank tracks finish him. Blue's men are green, Red's tan, and each
# wears an armband in his team's colour.

const GRENADE_RANGE := 38.0
const DOWN_SECONDS := 30.0
const DRAG_SPEED := 3.2
const SHOULDER_TIME := 0.7   # seconds from first seeing an enemy to having the rifle in the shoulder
const KNEEL_WITHIN := 0.55    # share of his range inside which a gunner kneels instead of lying down
const HIP_ACCURACY := 0.35   # share of his usual hit chance while still firing from the hip

var main
var def: Dictionary
var team := 0
var state := "up"  # up, down or dead
var hp := 10.0
var side := Vector3.ZERO
var think := 0.0
var shoot_t := 0.0
var burst_left := 0
var grenade_t := 0.0
var smoke_t := 0.0
var down_t := 0.0
var prone := false
var foe: Soldier
var prey: Tank
var patient: Soldier   # medic: who he is going to, or dragging
var rescue := ""       # medic: "" (going to him), lift, drag or treat
var rescue_t := 0.0
var cover := Vector3.ZERO
var voice_pitch := 1.0
var _crouch := 0.0
var claimed_by: Soldier  # a downed man's medic
var body: Node3D
var model: SoldierModel
var muzzle: Node3D
# What each class can do when a player is the man (shown on the deploy screen too).
const ABOUT := {
	"assault": "Rifleman. Automatic rifle; quick on his feet.",
	"gunner": "Machine gunner. Belt-fed gun: slow to carry, heavy fire. Crouch to steady it.",
	"medic": "Medic. Carbine. Hold F beside a fallen teammate to get him up.",
	"rocket": "Anti-tank. An RPG-7 with three rockets that will hole most armour from the side or rear. Key 3 is the RPG, key 1 his rifle.",
	"engineer": "Engineer. Rifle. Hold F beside a friendly vehicle to repair it.",
}
var driven := false    # a player is this man: he does what `want` says and nothing of his own
var want := {}         # the player's controls (see player_ctrl.gd): move, sprint, yaw, pitch, fire, aim, use, crouch, aim_from, aim_dir
var rockets := 3
var weapon := 1        # which is in his hands: 1 primary, 2 pistol, 3 the class's special (the anti-tank man's launcher)
var mag_size := 20
var mag := 20          # rounds in the primary weapon
var mags := 3          # spare magazines (or belts)
var pistol := 12
var pistol_mags := 2
var grenades := 2
var reloading := 0.0   # seconds of reloading left
var _fire_t := 0.0
var _use_t := 0.0
var _aim_pitch := 0.0
var net_id := 0        # his number in a networked match, the same on every PC
var sight := "iron"    # the sight on his rifle (a player's choice; the squads carry iron sights)
var leader: Soldier    # the man he follows, if he is one of a player's squad
var owner_slot := {}   # the player who is this man (empty for one of the squads): who is paid for what he does
var puppet := false    # a copy of a soldier the host is running (see netplay.gd)
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_flags := 0     # what he is doing, as the host last reported it (see flags())
var net_seen := 0.0    # when the host last mentioned him
var _slide_t := 0.0    # seconds left of going sideways along a wall
var _slide_dir := 1.0
var _moving := false
var _fighting := false
var _engaged := 0.0  # how long he has had an enemy in view
var _kneel := false  # a gunner fighting at close range kneels to fire; further off he goes prone
var _carry := 0.55   # how low the rifle is carried, before lying prone is taken into account
var _lean := 0.0
var _pace := 0.0                 # how fast he is moving, metres a second (the model strides to match)
var _heading := Vector2(0, 1)    # which way he is stepping: x to his right, y ahead
var _reload_total := 1.0         # how long the reload under way takes in all
# A player's man moves at these shares of his class's speed (see data/infantry.json).
const PACE_WALK := 0.62
const PACE_SPRINT := 1.3
const PACE_AIM := 0.45
const PACE_CROUCH := 0.38
const PACE_CRAWL := 0.18
const ROCKET_RELOAD := 3.5       # seconds to push a fresh rocket into the RPG-7
const JUMP_SPEED := 4.4          # metres a second upwards: with the gravity below, a jump of about 0.8 m
const JUMP_GRAVITY := 12.0
const VAULT_HEIGHT := 1.35       # the tallest thing he can vault, metres
const VAULT_DISTANCE := 2.2      # how far a vault carries him
const VAULT_SECONDS := 0.55
var _air_y := 0.0                # how far his feet are off the ground
var _vy := 0.0
var _jump_was := false
var _vault_t := 0.0              # seconds of a vault still to go
var _vault_dir := Vector3.ZERO


func setup(p_main, p_team: int, p_def: Dictionary) -> void:
	main = p_main
	team = p_team
	def = p_def
	hp = def["hp"]
	collision_layer = 8
	collision_mask = 0
	side = Vector3(randf_range(-9.0, 9.0), 0, randf_range(-9.0, 9.0))  # his own place in the huddle round the objective
	shoot_t = randf_range(0.5, 2.0)
	grenade_t = randf_range(1.0, 4.0)
	var ahead: Vector3 = main.path_forward(team)
	rotation.y = atan2(-ahead.x, -ahead.z)  # he arrives facing the enemy's end, not whichever way the map happens to point
	voice_pitch = randf_range(0.88, 1.16)  # so the men do not all sound like one person
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.9
	shape.shape = cap
	shape.position.y = 0.95
	add_child(shape)
	_build()


# ---- the figure ----

func _build() -> void:
	body = Node3D.new()
	add_child(body)
	model = SoldierModel.new()
	body.add_child(model)
	model.build(team, def["kit"], sight)
	model.stride = randf() * TAU  # so a squad does not run in step
	muzzle = model.muzzle

# ---- behaviour ----

# What he is doing, packed into one number for sending to the other players' PCs.
func flags() -> int:
	return ["up", "down", "dead"].find(state) + (4 if _moving else 0) + (8 if prone else 0) + (16 if _kneel else 0) \
		+ (32 if _fighting else 0) + (64 if rescue == "drag" else 0) + (128 if (rescue == "lift" or rescue == "treat") else 0)


# A copy of a soldier the host is running: he is eased to where the host says he is and
# holds himself the way the host says he is holding himself. He decides nothing.
func _follow_host(delta: float) -> void:
	var ease := clampf(delta * 10.0, 0.0, 1.0)
	var to := Vector3(net_pos.x, main.map.height(net_pos.x, net_pos.z), net_pos.z)
	global_position = to if global_position.distance_to(to) > 20.0 else global_position.lerp(to, ease)
	rotation.y = lerp_angle(rotation.y, net_yaw, ease)
	var now: String = ["up", "down", "dead"][net_flags & 3]
	if now == "dead" and state != "dead":
		get_tree().create_timer(8.0).timeout.connect(queue_free)
	# Only men on their feet are kept in the match's list, as on the host. (A dead man left in
	# it was still there after he had been cleared away, and everything that looks through
	# the list - a grenade going off, for one - tripped over him.)
	if now != state:
		main.soldiers.erase(self)
		if now == "up":
			main.soldiers.append(self)
	state = now
	if state != "up" and main.player_man == self:
		main.player_man_down(self)  # ours, and the host says he is down
	if state != "up":
		_lean = move_toward(_lean, PI * 0.5, delta * 7.0)
		body.rotation.x = _lean
		body.position.y = 0.3
		model.run = 0.0
		model.crouch = 0.0
		model.lean = 0.0
		model.head_up = 0.0
		model.gun_low = move_toward(model.gun_low, 0.9, delta * 3.0)
		model.pose(delta)
		return
	_kneel = net_flags & 16 != 0
	rescue = "drag" if net_flags & 64 != 0 else ("treat" if net_flags & 128 != 0 else "")
	rescue_t += delta
	_show(delta, net_flags & 4 != 0, net_flags & 8 != 0, net_flags & 32 != 0)


# A shot, as it looks and sounds: the bang, the flash, the kick and the round going downrange.
func show_shot(mark: Vector3) -> void:
	var from := muzzle.global_position
	Sfx.play("inf_mg", from, -9.0, 0.9 if def["kit"] == "machine_gun" else 1.0, 18.0)
	Fx.muzzle(main, from, -muzzle.global_transform.basis.z, 12.0, false, global_position.y)
	model.kick = 1.0
	body.position.z = 0.07
	Fx.tracer(main, from, mark)


# ---- a player's man ----

# Hands a player's man his ammunition: four magazines for a rifle (20 rounds) or a carbine
# (30), one in the weapon; two 150-round belts for the machine gunner; a pistol for everyone.
func arm() -> void:
	var kit: String = def["kit"]
	mag_size = 150 if kit == "machine_gun" else (30 if kit == "medical" else 20)
	mag = mag_size
	mags = 1 if kit == "machine_gun" else 3
	pistol = 12
	pistol_mags = 2
	grenades = 4 if def["id"] == "assault" else 2  # the assault man's extra kit is more grenades
	def["rocket_damage"] = 230.0
	def["rocket_pen"] = 260.0


# What one of his rockets does to whatever it hit (rockets are the same ones aircraft fire).
func _strike(col, at: Vector3, dir: Vector3, normal: Vector3, damage: float, pen: float, _big: bool) -> void:
	if col is Tank and col.team != team:
		if driven:
			col.credit = owner_slot
			col.credit_t = main.elapsed
		var warhead: Dictionary = GameData.shells["76s_heat"].duplicate()
		warhead["damage"] = damage
		var result: String = col.take_hit(warhead, pen, 1.0, at, dir, normal, null)
		if driven:
			main.show_msg(result)
	elif col is Aircraft and col.team != team:
		col.hurt(damage, self)
	elif col is Prop:
		col.knock(dir * 9000.0, at)


# Where a round really goes: it falls on the way, more the slower it is and the further it flies.
func _dropped(hit: Dictionary, speed: float, mask: int) -> Dictionary:
	var from: Vector3 = want.get("aim_from", eye()) + hit["dir"] * 3.0
	var flight := from.distance_to(hit["position"]) / speed
	var dir: Vector3 = (hit["position"] - Vector3(0, 4.9 * flight * flight, 0) - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 650.0, mask)
	q.exclude = [get_rid()]
	var real := get_world_3d().direct_space_state.intersect_ray(q)
	if real.is_empty():
		real = {"position": from + dir * 650.0, "collider": null, "normal": -dir}
	real["dir"] = dir
	return real

func eye() -> Vector3:
	return global_position + Vector3(0, lerpf(1.62 - _crouch * 0.6, 0.4, absf(_lean) / (PI * 0.5)), 0)


func _driven(delta: float) -> void:
	think -= delta
	if think <= 0.0:
		think = 0.3
		_look_around()  # (this is where a vehicle driving over him is noticed)
		foe = null
		if state != "up":
			return
	rotation.y = float(want.get("yaw", rotation.y))
	if main.prep_t > 0.0:
		# Nobody moves or shoots until the round starts.
		for k in ["move", "fire", "throw", "jump", "use"]:
			want.erase(k)
	var lying: bool = want.get("prone", false)
	var crouching: bool = want.get("crouch", false) and not lying
	var aiming: bool = want.get("aim", false)
	var push: Vector3 = want.get("move", Vector3.ZERO)
	var moving := push.length() > 0.1
	_pace = 0.0
	if moving:
		# Lying down he crawls, crouched he creeps, aiming he walks carefully; Shift sprints, but only ahead.
		var share := PACE_WALK
		if lying:
			share = PACE_CRAWL
		elif crouching:
			share = PACE_CROUCH
		elif aiming:
			share = PACE_AIM
		elif want.get("sprint", false) and push.z < -0.5:
			share = PACE_SPRINT
		var pace := float(def["speed"]) * share
		_pace = pace
		_heading = Vector2(push.x, -push.z).normalized()
		var way := Basis(Vector3.UP, rotation.y) * push.normalized()
		# Fences, sandbags, crates and the like stop him. Anything no higher than his chest he
		# can get over: Space as he comes up to it vaults it, and a running jump clears the low ones.
		var low := _in_the_way(way, 0.45)
		if _vault_t <= 0.0 and low and _air_y < 0.55:
			moving = false
			_pace = 0.0
			if want.get("jump", false) and not lying and not _in_the_way(way, VAULT_HEIGHT):
				_vault_t = VAULT_SECONDS
				_vault_dir = way
				_vy = 0.0
		elif _vault_t <= 0.0:
			_step(way * pace * delta)
	if _vault_t > 0.0:
		# Over he goes: carried across in an arc, a hand down on the top of it.
		_vault_t -= delta
		_step(_vault_dir * (VAULT_DISTANCE / VAULT_SECONDS) * delta)
		_air_y = sin(clampf(1.0 - _vault_t / VAULT_SECONDS, 0.0, 1.0) * PI) * (VAULT_HEIGHT - 0.25)
		moving = false
	else:
		# Jumping: up on Space (once for each press), down under gravity.
		var jump: bool = want.get("jump", false)
		if jump and not _jump_was and _air_y <= 0.0 and not lying:
			_vy = JUMP_SPEED
		_jump_was = jump
		_vy -= JUMP_GRAVITY * delta
		_air_y = maxf(0.0, _air_y + _vy * delta)
		if _air_y <= 0.0:
			_vy = 0.0
	global_position.y = main.map.height(global_position.x, global_position.z) + _air_y
	_fire_t -= delta
	grenade_t -= delta
	if want.get("throw", false) and grenade_t <= 0.0 and grenades > 0:
		grenades -= 1
		# A grenade (the medic's is smoke), thrown at where he is looking, up to 35 m.
		grenade_t = 2.5
		model.throw = 1.0
		var mark := _aim_ray(0.0, 1 | 4)
		var out: Vector3 = mark["position"] - global_position
		var g := Grenade.new()
		g.main = main
		g.team = team
		main.add_child(g)
		g.launch(eye(), global_position + out.limit_length(35.0), def["medic"])
	# Changing weapon, and reloading the one in hand (R, or by itself when it runs dry).
	var pick := int(want.get("weapon", 0))
	if pick != 0 and pick != weapon and (pick < 3 or def["kit"] == "rocket"):
		weapon = pick
		reloading = 0.0
	var spare := mags if weapon == 1 else pistol_mags
	var loaded := mag if weapon == 1 else pistol
	var full := mag_size if weapon == 1 else 12
	if weapon != 3 and reloading <= 0.0 and spare > 0 and loaded < full and (want.get("reload", false) or loaded <= 0):
		reloading = 4.5 if (weapon == 1 and def["kit"] == "machine_gun") else (2.2 if weapon == 1 else 1.4)
		_reload_total = reloading
		Sfx.play("click", global_position, -6.0, 0.8, 8.0)
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			if weapon == 1:
				mag = mag_size
				mags -= 1
			else:
				pistol = 12
				pistol_mags -= 1
			Sfx.play("click", global_position, -4.0, 1.2, 8.0)
	var firing: bool = want.get("fire", false)
	if firing and _fire_t <= 0.0 and reloading <= 0.0:
		if weapon == 3:
			_fire_rocket()
		elif (mag if weapon == 1 else pistol) > 0:
			_fire_round(moving, aiming, crouching or lying)
	# The class's own job, on the use key.
	if want.get("use", false):
		_use(delta)
	else:
		_use_t = 0.0
	_kneel = crouching
	_aim_pitch = float(want.get("pitch", 0.0)) if (aiming or firing or _fire_t > -0.6) else 0.0
	_moving = moving
	_fighting = aiming or firing or _fire_t > -0.6 or crouching
	_show(delta, moving, lying, _fighting)


# Moves a player's man over the ground, kept on the map and out of buildings.
func _step(by: Vector3) -> void:
	var next := global_position + by
	next.x = clampf(next.x, -PushMap.HALF_WIDTH + 3.0, PushMap.HALF_WIDTH - 3.0)
	next.z = clampf(next.z, -main.map.half_len + 3.0, main.map.half_len - 3.0)
	next = main.map.keep_out(next, 0.7)
	global_position = Vector3(next.x, global_position.y, next.z)


# Whether something solid stands just ahead of him at this height above the ground.
func _in_the_way(way: Vector3, at_height: float) -> bool:
	var from := Vector3(global_position.x, main.map.height(global_position.x, global_position.z) + at_height, global_position.z)
	var q := PhysicsRayQueryParameters3D.create(from, from + way * 0.85, 1 | Prop.LAYER)
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _aim_ray(spread: float, mask: int) -> Dictionary:
	var dir: Vector3 = want.get("aim_dir", -global_transform.basis.z)
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	var from: Vector3 = want.get("aim_from", eye()) + dir * 3.0
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 600.0, mask)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		hit = {"position": from + dir * 600.0, "collider": null, "normal": -dir}
	hit["dir"] = dir
	return hit


func _fire_round(moving: bool, aiming: bool, crouching: bool) -> void:
	var side_arm := weapon == 2
	if side_arm:
		pistol -= 1
	else:
		mag -= 1
	_fire_t = 0.25 if side_arm else (float(def["shot_gap"]) if float(def["damage"]) > 0.0 else 0.25)
	var spread := (0.004 if aiming else 0.018) * (0.6 if crouching else 1.0) * (0.75 if want.get("prone", false) else 1.0) * (2.2 if moving else 1.0) * (1.6 if def["kit"] == "machine_gun" and not crouching else 1.0) * (1.8 if side_arm else 1.0)
	var mask := 1 | 2 | 4 | 8 | Prop.LAYER
	var hit := _dropped(_aim_ray(spread, mask), 330.0 if side_arm else 720.0, mask)
	show_shot(hit["position"])
	main.soldier_fired(self, hit["position"])
	var col = hit["collider"]
	var hurts := maxf(float(def["damage"]), 5.0) * (0.8 if side_arm else 1.0)
	if col is Soldier and col.team != team:
		col.hurt(hurts * randf_range(0.8, 1.3), self)
		if col.state != "up":
			main.award(owner_slot, "infantry")
	elif col is Tank and col.team != team:
		col.credit = owner_slot
		col.credit_t = main.elapsed
		var round: Dictionary = GameData.shells["mg_762"]
		col.take_hit(round, float(round["pen"]), 1.0, hit["position"], hit["dir"], hit["normal"], null)
	elif col is Aircraft and col.team != team:
		col.hurt(hurts, self)
	elif col is Prop:
		col.knock(hit["dir"] * 45.0, hit["position"])
	else:
		Fx.dust(main, hit["position"], 0.15)


# The anti-tank man's launcher: one of the same rockets aircraft carry, fired from the
# shoulder. It flies fast and falls as it goes, so aim high at long range. Three to a life.
func _fire_rocket() -> void:
	if rockets <= 0:
		_fire_t = 0.4
		return
	rockets -= 1
	_fire_t = ROCKET_RELOAD
	var dir: Vector3 = want.get("aim_dir", -global_transform.basis.z)
	var r := Aircraft.Rocket.new()
	r.owner_craft = self
	main.add_child(r)
	r.global_position = eye() + dir * 1.2
	r.vel = dir * 150.0
	main.tell_air_fx("rocket", r.global_position, r.vel, 0, false)
	Sfx.play("rocket", muzzle.global_position, 1.0, 0.9, 60.0)
	Fx.muzzle(main, muzzle.global_position, dir, 60.0, false, global_position.y)
	# The back-blast out of the rear of the tube.
	Fx.muzzle(main, muzzle.global_position - dir * 1.6, -dir, 45.0, false, global_position.y)
	Fx.dust(main, global_position - dir * 2.5, 0.5)
	model.kick = 1.0

func _use(delta: float) -> void:
	if def["medic"]:
		for s in main.downed:
			if s.team == team and s.global_position.distance_to(global_position) < 3.2:
				_use_t += delta
				_crouch = 1.0
				if _use_t >= 2.0:
					_use_t = 0.0
					s.revive()
					Sfx.shout("inf_up", global_position, voice_pitch)
				return
	elif def["kit"] == "tools":
		for t in main.tanks:
			if t.team == team and t.global_position.distance_to(global_position) < 8.0 and (t.hp < t.max_hp or t.modules["tracks"] > 0.0 or t.modules["engine"] > 0.0 or t.modules["gun"] > 0.0):
				t.hp = minf(t.max_hp, t.hp + t.max_hp * 0.06 * delta)
				for k in t.modules:
					t.modules[k] = maxf(0.0, t.modules[k] - delta * 2.0)
				t.refresh_damage_look()
				_use_t += delta
				return
	_use_t = 0.0


func _physics_process(delta: float) -> void:
	if puppet:
		_follow_host(delta)
		return
	if driven and state == "up":
		_driven(delta)
		return
	if state != "up":
		# Lying on his back. A downed man can still be saved for a while.
		_lean = move_toward(_lean, PI * 0.5, delta * 7.0)
		body.rotation.x = _lean
		body.position.y = 0.3
		model.run = 0.0
		model.crouch = 0.0
		model.lean = 0.0
		model.head_up = 0.0
		model.gun_low = move_toward(model.gun_low, 0.9, delta * 3.0)
		model.pose(delta)
		if state == "down":
			down_t -= delta
			if down_t <= 0.0:
				_finish()
		return
	think -= delta
	shoot_t -= delta
	grenade_t -= delta
	smoke_t -= delta
	if think <= 0.0:
		think = 0.35
		_look_around()
		if state != "up":
			return
	var moving := false
	var want_prone := false
	var fighting := false
	if def["medic"]:
		moving = _medic_duty(delta)
	elif foe != null and is_instance_valid(foe) and foe.state == "up":
		fighting = true
		_face(foe.global_position)
		if _engaged <= 0.0:
			_kneel = def["prone"] and global_position.distance_to(foe.global_position) < float(def["range"]) * KNEEL_WITHIN
		want_prone = def["prone"] and not _kneel
		if shoot_t <= 0.0:
			_shoot()
	elif _shoot_rocket(delta):
		fighting = true
	elif _shoot_air():
		fighting = true
	elif prey != null and is_instance_valid(prey) and def["grenades"] and grenades > 0:
		_face(prey.global_position)
		if grenade_t <= 0.0:
			grenades -= 1  # he carries two, like anyone: no more endless showers of them round a tank
			_throw_grenade()
	else:
		moving = _run_to(_way_to_objective(), float(def["speed"]), delta)
		if not moving:
			_face(global_position + main.path_forward(team) * 10.0)
	global_position.y = main.map.height(global_position.x, global_position.z)

	_moving = moving
	_fighting = fighting
	_show(delta, moving, want_prone, fighting)


# How he holds himself, from what he is doing.
func _show(delta: float, moving: bool, want_prone: bool, fighting: bool) -> void:
	# Pose. Prone lies him on his belly behind the gun. On the run he leans into it with the
	# rifle carried low; meeting an enemy he fires from the hip at first, then brings the
	# rifle up into the shoulder. A medic at work goes down on one knee to take hold or to
	# treat, and hunches over while he hauls.
	prone = want_prone
	_engaged = _engaged + delta if fighting else 0.0
	var bend := 0.0
	if rescue == "lift" or rescue == "treat":
		bend = 1.0
	elif rescue == "drag":
		bend = 0.3
	elif fighting and _kneel:
		bend = 0.85
	_crouch = move_toward(_crouch, bend, delta * 3.0)
	_lean = move_toward(_lean, -PI * 0.5 if prone else 0.0, delta * 6.0)
	var flat := absf(_lean) / (PI * 0.5)
	body.rotation.x = _lean
	body.position.y = 0.22 * flat
	body.position.z = move_toward(body.position.z, 0.0, delta * 0.6)  # settling after recoil
	var dragging := rescue == "drag"
	if not driven:
		# One of the squad (or a copy of a man another machine is running): he runs the way he faces.
		_heading = Vector2(0, 1)
		_pace = float(def["speed"]) * (0.5 if dragging else 1.0)
	model.run = move_toward(model.run, 1.0 if moving else 0.0, delta * 5.0)
	if moving:
		model.pace = move_toward(model.pace, _pace, delta * 12.0)
		model.heading = model.heading.lerp(_heading, clampf(delta * 10.0, 0.0, 1.0))
	# He leans into a run, more the faster it is, and only when going forwards.
	var into := clampf((_pace - 2.0) * 0.065, 0.0, 0.42) * maxf(_heading.y, -0.2) * (1.0 - flat) if moving else 0.0
	model.lean = move_toward(model.lean, 0.55 if dragging else into, delta * 2.5)
	model.crouch = _crouch
	model.flat = flat
	model.tuck = move_toward(model.tuck, clampf(_air_y / 0.45, 0.0, 1.0), delta * 9.0)
	model.vault = move_toward(model.vault, 1.0 if _vault_t > 0.0 else 0.0, delta * 7.0)
	model.weapon = weapon
	model.reload = 0.0
	model.loaded = rockets > 0 and _fire_t <= ROCKET_RELOAD * 0.3
	if weapon == 3 and _fire_t > 0.0 and rockets > 0:
		model.reload = 1.0 - _fire_t / ROCKET_RELOAD
	model.head_up = 1.1 * flat
	model.work = sin(rescue_t * 9.0) if rescue == "treat" else 0.0
	var gun_to := 0.55  # carried low
	if fighting and _kneel:
		gun_to = -0.3  # kneeling tips him forward; this brings the muzzle back up level
	elif fighting:
		gun_to = 0.0 if _engaged >= SHOULDER_TIME else 0.3
	elif rescue != "":
		gun_to = 0.9
	if driven and reloading > 0.0:
		gun_to = 0.7
		model.reload = 1.0 - reloading / _reload_total
	if driven and moving and _pace > float(def["speed"]) and not fighting:
		gun_to = 0.75  # sprinting: the weapon carried right down across his body
	_carry = move_toward(_carry, gun_to, delta * 4.0)
	# Going prone, the rifle comes up exactly as fast as the body goes down, so it always
	# points the way he faces (it used to lag and swing over his head as he got up).
	model.gun_low = lerpf(_carry, -1.5, flat) - _aim_pitch  # (a player's man raises and lowers the rifle with his aim)
	model.pose(delta)

func _face(point: Vector3) -> void:
	var d := point - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 0.2)


# Runs towards a point, sliding round houses and blocks. Returns true while still on the way.
func _run_to(goal: Vector3, pace: float, delta: float, close: float = 5.0) -> bool:
	var to := goal - global_position
	to.y = 0.0
	if to.length() <= close:
		return false
	var step := to.normalized() * pace * delta
	var next := global_position + step
	var house = main.map.nearest_house(Vector2(next.x, next.z), 11.0)
	if house != null:
		var away := Vector3(next.x - house.x, 0, next.z - house.y).normalized()
		next += (away + away.cross(Vector3.UP) * 0.8) * pace * delta
	# He faces the way he is actually going. (He used to face his goal even while a wall or
	# a building was turning him aside, and so ran sideways or backwards along it.)
	var from := global_position
	if _slide_t > 0.0:
		# Working his way along a wall that was in his way.
		_slide_t -= delta
		next = from + step.rotated(Vector3.UP, _slide_dir * 1.35)
	# A bot never walks into the strip at the edge of the battle (map.gd out_of_bounds).
	var edge := PushMap.HALF_WIDTH - PushMap.OOB_MARGIN - 5.0
	var end: float = main.map.half_len - PushMap.OOB_MARGIN - 5.0
	next.x = clampf(next.x, -edge, edge)
	next.z = clampf(next.z, -end, end)
	global_position = main.map.keep_out(next, 0.8)
	var went := global_position - from
	went.y = 0.0
	if went.length() < pace * delta * 0.35:
		# Hardly moved: something solid is in the way. Turn along it, the other way if that fails too.
		_slide_dir = -_slide_dir if _slide_t > 0.0 else (1.0 if randf() < 0.5 else -1.0)
		_slide_t = 2.2
	_face(global_position + (went if went.length() > pace * delta * 0.3 else step))
	return true


# Where to run to next on the way to the objective. In Push the route winds between
# buildings, so a man far from the objective follows the route round its corners instead
# of making straight for it through whatever is in the way.
func _way_to_objective() -> Vector3:
	if leader != null and is_instance_valid(leader) and leader.state == "up":
		# One of a player's squad: he keeps station on his leader, a few metres off to his own side.
		return leader.global_position + Vector3(side.x, 0, side.z).normalized() * 6.0 - leader.global_transform.basis.z * -4.0
	var goal: Vector3 = main.objective_pos() + side - main.path_forward(team) * 22.0
	if main.mode["kind"] != "push":
		return goal
	var my_s: float = main.map.nearest_s(global_position)
	var goal_s: float = main.map.nearest_s(goal)
	if absf(goal_s - my_s) < 45.0:
		return goal
	var next_s: float = my_s + 25.0 * signf(goal_s - my_s)
	return main.path_pos(next_s) + main.map.route_dir(next_s).cross(Vector3.UP) * (side.x * 1.2)


func _look_around() -> void:
	foe = null
	prey = null
	var best: float = def["range"]
	for s in main.soldiers:
		if s.team != team and s.state == "up":
			var d := global_position.distance_to(s.global_position)
			if d < best:
				best = d
				foe = s
	if foe != null and not main.los(global_position + Vector3(0, 1.5, 0), foe.global_position + Vector3(0, 1.5, 0)):
		foe = null
	for t in main.tanks:
		var d := global_position.distance_to(t.global_position)
		if t.team != team:
			# Anything that drives over him flattens him.
			if d < float(t.def["width"]) * 0.5 + 0.8 and absf(t.speed) > 1.0:
				hit("crush")
				return
			if foe == null and d < GRENADE_RANGE:
				prey = t


func _shoot() -> void:
	if burst_left <= 0:
		burst_left = int(def["burst"])
	burst_left -= 1
	shoot_t = float(def["shot_gap"]) if burst_left > 0 else float(def["pause"]) * randf_range(0.8, 1.3)
	# The gun kicks, flashes at the muzzle and sends a visible round downrange: a near miss
	# goes wide of the man, a hit goes into him.
	var aim := -muzzle.global_transform.basis.z
	var from_hip: bool = not prone and not _kneel and _engaged < SHOULDER_TIME
	var landed := randf() < float(def["hit_chance"]) * (HIP_ACCURACY if from_hip else 1.0)
	var mark := foe.global_position + Vector3(0, 1.1, 0)
	if not landed:
		mark += Vector3(randf_range(-2.5, 2.5), randf_range(-1.0, 1.5), randf_range(-2.5, 2.5)) + aim * 12.0
	show_shot(mark)
	main.soldier_fired(self, mark)
	if def["prone"] and burst_left == int(def["burst"]) - 1 and randf() < 0.4:
		Sfx.shout("inf_cover", global_position, voice_pitch)
	if landed:
		foe.hurt(float(def["damage"]) * randf_range(0.7, 1.3), self)
		if foe.state != "up" and randf() < 0.4:
			Sfx.shout("inf_got_him", global_position, voice_pitch)


# The squad's anti-tank man: an enemy vehicle in plain view within ROCKET_RANGE gets a rocket,
# then he reloads. Three rockets. Returns true while he is busy with it.
const ROCKET_RANGE := 95.0
var _rocket_wait := 0.0

func _shoot_rocket(delta: float) -> bool:
	if def["kit"] != "rocket" or rockets <= 0:
		weapon = 1
		return false
	_rocket_wait -= delta
	var mark: Tank = null
	var near := ROCKET_RANGE
	for t in main.tanks:
		if t.team != team:
			var d: float = t.global_position.distance_to(global_position)
			if d < near and d > 12.0 and main.los(global_position + Vector3(0, 1.5, 0), t.global_position + Vector3(0, 1.5, 0)):
				near = d
				mark = t
	if mark == null:
		weapon = 1
		return false
	weapon = 3
	_face(mark.global_position)
	_fire_t = _rocket_wait  # (what the model reads to show him reloading)
	if _rocket_wait <= 0.0 and _engaged > 0.8:
		_rocket_wait = ROCKET_RELOAD + randf_range(1.5, 4.0)
		rockets -= 1
		var aim: Vector3 = (mark.global_position + Vector3(0, 1.2 + near * 0.012, 0) + Vector3(randf_range(-1.5, 1.5), randf_range(-0.6, 0.6), randf_range(-1.5, 1.5)) - muzzle.global_position).normalized()
		var r := Aircraft.Rocket.new()
		r.owner_craft = self
		main.add_child(r)
		r.global_position = muzzle.global_position
		r.vel = aim * 150.0
		main.tell_air_fx("rocket", r.global_position, r.vel, 0, false)
		Sfx.play("rocket", muzzle.global_position, 0.0, 0.9, 60.0)
		Fx.muzzle(main, muzzle.global_position, aim, 60.0, false, global_position.y)
		Fx.muzzle(main, muzzle.global_position - aim * 1.6, -aim, 45.0, false, global_position.y)
		model.kick = 1.0
		Sfx.shout("inf_tank", global_position, voice_pitch)
	return true


# A helicopter within AIR_RANGE gets shot at with whatever he is carrying. Returns true if
# he is doing so (he turns to face it and fires his usual bursts).
const AIR_RANGE := 75.0

func _shoot_air() -> bool:
	if def["medic"] or float(def["damage"]) <= 0.0:
		return false
	var heli: Aircraft = null
	var near := AIR_RANGE
	for a in main.aircraft:
		if is_instance_valid(a) and a.heli and a.team != team and not a.dying and not a.wrecked:
			var d: float = a.global_position.distance_to(global_position)
			if d < near:
				near = d
				heli = a
	if heli == null:
		return false
	_face(heli.global_position)
	if shoot_t <= 0.0:
		if burst_left <= 0:
			burst_left = int(def["burst"])
		burst_left -= 1
		shoot_t = float(def["shot_gap"]) if burst_left > 0 else float(def["pause"]) * randf_range(0.8, 1.3)
		var landed := randf() < float(def["hit_chance"])
		var mark := heli.global_position + Vector3(0, 1.5, 0)
		if not landed:
			mark += Vector3(randf_range(-5, 5), randf_range(-3, 4), randf_range(-5, 5))
		show_shot(mark)
		if landed:
			heli.hurt(float(def["damage"]) * 1.5, self)
	return true


func _throw_grenade() -> void:
	grenade_t = randf_range(4.0, 7.0)
	model.throw = 1.0
	Sfx.shout("inf_grenade" if randf() < 0.6 else "inf_tank", global_position, voice_pitch)
	var g := Grenade.new()
	g.main = main
	g.team = team
	main.add_child(g)
	g.launch(global_position + Vector3(0, 1.8, 0), prey.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), false)


# The medic's job. Returns true while he is on the move.
func _medic_duty(delta: float) -> bool:
	if patient != null and (not is_instance_valid(patient) or patient.state != "down"):
		patient = null
		rescue = ""
	if patient == null:
		# Look for the nearest man down that nobody else is already going for.
		var best := 100.0
		for s in main.downed:
			if s.team == team and (s.claimed_by == null or not is_instance_valid(s.claimed_by) or s.claimed_by.state != "up"):
				var d := global_position.distance_to(s.global_position)
				if d < best:
					best = d
					patient = s
		if patient != null:
			patient.claimed_by = self
	if patient == null:
		# Nobody to help: trail the squad, a little further back.
		return _run_to(main.objective_pos() + side - main.path_forward(team) * 36.0, float(def["speed"]), delta)
	patient.down_t = maxf(patient.down_t, 6.0)  # he will not bleed out while a medic has him
	match rescue:
		"":
			var d := global_position.distance_to(patient.global_position)
			if d < 26.0 and smoke_t <= 0.0:
				# A small smoke grenade to hide the rescue.
				smoke_t = 14.0
				model.throw = 1.0
				var g := Grenade.new()
				g.main = main
				g.team = team
				main.add_child(g)
				g.launch(global_position + Vector3(0, 1.8, 0), patient.global_position, true)
			if _run_to(patient.global_position, float(def["speed"]), delta, 1.7):
				return true
			# Reached him: get down and take hold. Pick the nearest cover, on the side away
			# from the enemy, to haul him to.
			rescue = "lift"
			rescue_t = 1.0
			Sfx.shout("inf_gotcha", global_position, voice_pitch)
			var back: Vector3 = main.path_forward(team)
			var house = main.map.nearest_house(Vector2(global_position.x, global_position.z), 70.0)
			cover = global_position - back * 18.0
			if house != null:
				cover = Vector3(house.x, 0, house.y) - back * 13.0
			return false
		"lift":
			_face(patient.global_position)
			rescue_t -= delta
			if rescue_t <= 0.0:
				rescue = "drag"
			return false
		"drag":
			# He backs away towards cover, bent over, hauling the casualty by the shoulders:
			# facing the man he is pulling, who trails head-first behind his heels.
			var to := cover - global_position
			to.y = 0.0
			if to.length() <= 2.5:
				rescue = "treat"
				rescue_t = 3.0
				return false
			var heading := to.normalized()
			var next := global_position + heading * DRAG_SPEED * delta
			var house = main.map.nearest_house(Vector2(next.x, next.z), 11.0)
			if house != null:
				var away := Vector3(next.x - house.x, 0, next.z - house.y).normalized()
				next += (away + away.cross(Vector3.UP) * 0.8) * DRAG_SPEED * delta
			global_position = main.map.keep_out(next, 0.8)
			var trail := global_position - heading * 1.7
			patient.global_position = Vector3(trail.x, main.map.height(trail.x, trail.z), trail.z)
			var d := patient.global_position - global_position
			rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 0.3)
			patient.rotation.y = atan2(-d.x, -d.z)  # lying on his back, head towards the medic
			return true
		"treat":
			# Kneeling over him behind cover, working.
			_face(patient.global_position)
			rescue_t -= delta
			if rescue_t <= 0.0:
				Sfx.shout("inf_up", global_position, voice_pitch)
				patient.revive()
				patient = null
				rescue = ""
			return false
	return false


func hurt(amount: float, by = null) -> void:
	hp -= amount
	main.damage_from(owner_slot, by)
	if hp <= 0.0:
		hit("bullet")


# What stopped him. Bullets leave him down and savable; anything heavier is final.
func hit(what: String, by = null) -> void:
	if state == "dead" or (state == "down" and what == "bullet"):
		return
	if driven:
		what = "blast"  # a player's man is out of the fight at once: he comes back as a new man
		main.player_man_down(self)
	if state == "up":
		if by != null and is_instance_valid(by) and by is Tank:
			main.award(by.slot, "infantry")
		main.soldiers.erase(self)
		collision_layer = 0
		rotation.y += randf_range(-0.6, 0.6)
		if patient != null and is_instance_valid(patient):
			patient.claimed_by = null
		patient = null
		rescue = ""
		foe = null
		Sfx.shout("inf_down" if what == "bullet" else "inf_medic", global_position, voice_pitch)
	if what == "bullet":
		main.tally(team, "downed")
		state = "down"
		down_t = DOWN_SECONDS
		main.downed.append(self)
	else:
		_finish()


func _finish() -> void:
	state = "dead"
	main.downed.erase(self)
	get_tree().create_timer(8.0).timeout.connect(queue_free)


# A medic got to him in time.
func revive() -> void:
	if state != "down":
		return
	main.downed.erase(self)
	main.soldiers.append(self)
	main.tally(team, "revived")
	state = "up"
	hp = def["hp"]
	claimed_by = null
	collision_layer = 8
	main.spawn_fx(global_position + Vector3(0, 2, 0), 3.0, Color(0.3, 1.0, 0.5, 0.5), 0.5)


# A thrown grenade: a slow arc, then a small blast, or a puff of smoke for the medic's.
class Grenade extends Node3D:
	const BLAST := 6.0
	const DAMAGE := 40.0
	const SMOKE_RADIUS := 7.0
	const SMOKE_SECONDS := 10.0

	var main
	var team := 0
	var smoke := false
	var ghost := false  # a copy on a PC that is only watching: it bursts, but the host decides who is hurt
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var t := 0.0
	var flight := 1.2

	func launch(p_from: Vector3, p_to: Vector3, p_smoke: bool) -> void:
		from = p_from
		to = p_to
		smoke = p_smoke
		if main.net_client:
			ghost = true
		elif main.netplay != null:
			main.netplay.tell_grenade(p_from, p_to, p_smoke, team)
		flight = clampf(from.distance_to(to) / 22.0, 0.7, 1.8)
		if smoke:
			MeshUtil.cylinder(self, 0.12, 0.4, Vector3.ZERO, MeshUtil.material(Color(0.85, 0.85, 0.82), 0.4))
		else:
			# A pineapple grenade: a ribbed egg of dark iron, with the fuse and lever on top.
			var iron := MeshUtil.material(Color(0.2, 0.22, 0.17), 0.85)
			var m := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.11
			sm.height = 0.3
			sm.radial_segments = 8
			sm.rings = 4
			m.mesh = sm
			m.material_override = iron
			add_child(m)
			for ring in [-0.06, 0.0, 0.06]:
				MeshUtil.cylinder(self, 0.118 - absf(ring) * 0.5, 0.02, Vector3(0, ring, 0), iron)
			var steel := MeshUtil.material(Color(0.45, 0.45, 0.42), 0.6)
			MeshUtil.cylinder(self, 0.04, 0.09, Vector3(0, 0.17, 0), steel)
			MeshUtil.box(self, Vector3(0.03, 0.2, 0.012), Vector3(0.055, 0.08, 0), steel)
		global_position = from

	func _physics_process(delta: float) -> void:
		t += delta
		var k := t / flight
		if k < 1.0:
			global_position = from.lerp(to, k) + Vector3(0, sin(k * PI) * 7.0, 0)
			rotation.x += delta * 9.0
			return
		# It goes off once, whatever happens below: stop here and now, and clear it away.
		set_physics_process(false)
		queue_free()
		if smoke:
			if not ghost:
				main.add_smoke(to, SMOKE_RADIUS, SMOKE_SECONDS)  # (the host tells the others about the smoke itself)
			Sfx.play("pop", to, -14.0, 1.6, 14.0)
			return
		main.spawn_fx(to + Vector3(0, 1, 0), BLAST * 0.4, Color(1.0, 0.7, 0.2, 0.8), 0.2)
		Sfx.play("grenade", to, -2.0, 0.82, 30.0)
		Fx.blast(main, to, 1.0)
		if ghost:
			return
		for tank in main.tanks.duplicate():
			if not is_instance_valid(tank):
				continue
			var d: float = tank.global_position.distance_to(to)
			if tank.team != team and d < BLAST:
				tank.take_splash(DAMAGE * (1.0 - d / BLAST), 20.0, null)
		for s in main.soldiers.duplicate():
			if is_instance_valid(s) and s.team != team and s.global_position.distance_to(to) < BLAST:
				s.hit("blast")
