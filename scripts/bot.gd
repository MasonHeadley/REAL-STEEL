class_name Bot
extends Node
# Drives one vehicle. How it plays comes from the vehicle's bot_style in the sheet:
#   front      parks on the enemy side of the objective and turns its front armour to the threat
#   sniper     hangs well back and shoots down the road
#   ambush     a gun without a turret: stops short and points the whole hull to aim
#   artillery  stays far back and lobs shells at enemies its team has spotted
#   scout      works a flank ahead of the team, to spot for it
#   escort     follows the nearest heavy, off to one side so it has a clear shot
#   flank      swings wide round the objective to get at the enemy's sides
# Nobody fires with a friend in the line of fire; a blocked bot shuffles sideways instead.
# A ping order from a teammate overrides where it goes (or what it shoots) for a while.

const ARTILLERY_RANGE := 1300.0
const ARTILLERY_MIN_RANGE := 70.0

var main
var tank: Tank
var style := "front"
var target: Tank
var has_los := false
var think := 0.0
var side := 0.0
var wing := 1.0  # which flank this bot favours: -1 or 1
var aim_err := Vector3.ZERO
var reverse_t := 0.0
var reverse_steer := 1.0
var detour_t := 0.0
var detour_steer := 0.0
var last_hp := 0.0
var fixed_gun := false
var blocked_t := 0.0  # how long a friend has been in the line of fire
var shift := Vector3.ZERO
var shift_t := 0.0
var _check_t := 0.0
var _check_pos := Vector3.ZERO
var _tries := 0
var _cover_stamp := -1
var _cover_pos := Vector3.ZERO
var _roam := Vector3.ZERO   # deathmatch: where it is prowling to
var _roam_until := 0.0


func _ready() -> void:
	tank.auto_drop = true
	style = String(tank.def["bot_style"])
	fixed_gun = float(tank.def["traverse_limit"]) < 90.0
	side = randf_range(-1.0, 1.0)
	wing = -1.0 if (int(tank.slot["index"]) % 2 == 0) else 1.0
	last_hp = tank.hp


var _burst_left := 0.0   # an automatic gun: seconds of this burst still to fire
var _rest_left := 0.0    # and seconds of the pause after it still to wait
var _hurt_at := -99.0    # when it last took damage
var _aa_hp := 0.0


# Fast-firing guns are fired in bursts with a pause between: 3 to 6 seconds on and 2 to 6
# off for a light tank's autocannon, 4 to 6 on and 4 to 6 off for an anti-aircraft gun.
func _in_burst(delta: float, wants: bool) -> bool:
	if _rest_left > 0.0:
		_rest_left -= delta
		return false
	if not wants:
		return false
	var aa: bool = tank.def.has("aa")
	if _burst_left <= 0.0:
		_burst_left = randf_range(4.0, 6.0) if aa else randf_range(3.0, 6.0)
	_burst_left -= delta
	if _burst_left <= 0.0:
		_rest_left = randf_range(4.0, 6.0) if aa else randf_range(2.0, 6.0)
	return true


func _physics_process(delta: float) -> void:
	if main.prep_t > 0.0:
		return  # waiting for the round to start
	if tank.hp < _aa_hp:
		_hurt_at = main.elapsed
	_aa_hp = tank.hp
	think -= delta
	shift_t -= delta
	if shift_t <= 0.0:
		shift = Vector3.ZERO
	if think <= 0.0:
		think = 0.4
		_pick_target()
		_use_ability()
	if style == "artillery":
		# With no clear line to its target it lobs the shell in over whatever is in the way.
		tank.high_arc = target != null and is_instance_valid(target) and not has_los and tank.global_position.distance_to(target.global_position) > 250.0
	_drive(delta)
	_shoot(delta)
	if tank.def["gun_sound"] == "autocannon":
		tank.want_fire = _in_burst(delta, tank.want_fire)


func _order() -> Dictionary:
	return main.orders[tank.team]


func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = [tank.get_rid()]
	return tank.get_world_3d().direct_space_state.intersect_ray(q)


func _sees(other: Tank) -> bool:
	return main.los(tank.eye(), other.global_position + Vector3(0, 1.5, 0))


# Picks from the enemies the team has spotted. Direct-fire guns need their own clear line;
# artillery will shell anything spotted. A designated target wins if it can be engaged.
func _pick_target() -> void:
	target = null
	has_los = false
	var arty := style == "artillery"
	var best := 99999.0
	var reach: float = ARTILLERY_RANGE if arty else float(main.mode["sight_range"])
	var order := _order()
	var wanted: Tank = order.get("target") if order.get("type", "") == "attack" else null
	for t in main.tanks:
		if t.team == tank.team or not t.spotted:
			continue
		var d := tank.global_position.distance_to(t.global_position)
		if d > reach or (arty and d < ARTILLERY_MIN_RANGE):
			continue
		# Anti-aircraft vehicles keep out of fights on the ground: they only shoot at a
		# vehicle that is right on top of them, or when they have just been hit.
		if tank.def.has("aa") and d > 150.0 and not (main.elapsed - _hurt_at < 6.0 and d < 380.0):
			continue
		if not (arty or _sees(t)):
			continue
		# Something this gun cannot hurt is a poor choice while anything else is in view.
		var score := d + (0.0 if _best_shell(t) >= 0 else 500.0)
		if t == wanted and d < ARTILLERY_RANGE:
			target = t
			best = -1.0
		elif score < best:
			best = score
			target = t
	has_los = target != null
	if target != null:
		tank.shell_index = maxi(_best_shell(target), 0)
	var dist := 300.0 if target == null else tank.global_position.distance_to(target.global_position)
	var spread := ((2.5 + dist / 120.0) if arty else (0.4 + dist / 300.0)) / maxf(float(Settings.rules["bot_aim"]), 0.2)
	aim_err = Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6) * (0.0 if arty else 1.0), randf_range(-1, 1)) * spread


# The shell to use on a target: HE if it will get inside, otherwise the best penetrator
# that can beat the front plate. Returns -1 if nothing carried can hurt it from the front.
func _best_shell(t: Tank) -> int:
	var ids: Array = tank.def["shells"]
	var front: float = t.def["armour"]["hull_front"]
	var pick := -1
	var pick_pen := 0.0
	for i in ids.size():
		var sd: Dictionary = GameData.shells[ids[i]]
		var pen: float = sd["pen"]
		if sd["type"] == "HE":
			if pen >= front or style == "artillery":
				return i
		elif pen >= front * 0.95 and pen > pick_pen:
			pick = i
			pick_pen = pen
	return pick


func _use_ability() -> void:
	var hit := tank.hp < last_hp
	last_hp = tank.hp
	if tank.ability_cd > 0.0:
		return
	var goal_far := tank.global_position.distance_to(_goal()) > 90.0
	match String(tank.ability["effect"]):
		"repair":
			if _ally_needs_repair():
				tank.use_ability()
		"armour":
			if hit:
				tank.use_ability()
		"smoke":
			if hit and tank.hp < tank.max_hp * 0.7:
				tank.use_ability()
		"reload":
			if target != null and tank.reload_left > 0.0:
				tank.use_ability()
		"sabot", "stun_shell":
			if target != null and tank.reload_left < 2.0:
				tank.use_ability()
		"scan":
			if target == null and not goal_far:
				tank.use_ability()
		"boost":
			if goal_far or hit:
				tank.use_ability()


func _ally_needs_repair() -> bool:
	for t in main.tanks:
		if t.team == tank.team and t.hp < t.max_hp * 0.65:
			if t.global_position.distance_to(tank.global_position) <= float(tank.ability["radius"]):
				return true
	return false


# Unit vector on the ground from a point towards the enemy.
func _threat_dir(from: Vector3) -> Vector3:
	if target != null and is_instance_valid(target):
		var d := target.global_position - from
		d.y = 0.0
		if d.length() > 1.0:
			return d.normalized()
	return main.path_forward(tank.team)


# A place on the route itself: `back` metres behind the objective (ahead of it if negative),
# and `lateral` metres to one side.
func _on_route(back: float, lateral: float) -> Vector3:
	var dir: float = main.team_dir(tank.team)
	var s: float = main.objective_s() - dir * back
	return main.path_pos(s) + (main.map.route_dir(s) * dir).cross(Vector3.UP) * lateral


func _nearest_shield() -> Tank:
	var best: Tank = null
	var best_d := 400.0
	for t in main.tanks:
		if t.team == tank.team and t != tank and t.def["role"] == "tank":
			var d := tank.global_position.distance_to(t.global_position)
			if d < best_d:
				best_d = d
				best = t
	return best


func _goal() -> Vector3:
	# Strayed near the edge of the battle (map.gd out_of_bounds): head back in first.
	if main.map.inside_by(tank.global_position, false) < 12.0:
		var home := Vector3(-tank.global_position.x, 0, -tank.global_position.z)
		return tank.global_position + home.normalized() * 60.0
	var g := _raw_goal() + shift
	# Never aim for a place in the last strip before the edge, where it would be out of the battle.
	var edge := PushMap.HALF_WIDTH - PushMap.OOB_MARGIN - 20.0
	var end: float = main.map.half_len - PushMap.OOB_MARGIN - 20.0
	g.x = clampf(g.x, -edge, edge)
	g.z = clampf(g.z, -end, end)
	# If the place it wants is a long way along the route, round a corner or two, it follows
	# the street there instead of trying to drive straight through the town.
	var my_s: float = main.map.nearest_s(tank.global_position)
	var goal_s: float = main.map.nearest_s(g)
	if main.mode["kind"] == "push" and absf(goal_s - my_s) > 60.0 and main.map.route_distance(tank.global_position) < 70.0:
		var next: float = my_s + 40.0 * signf(goal_s - my_s)
		return main.path_pos(next) + main.map.route_dir(next).cross(Vector3.UP) * side * 4.5
	return g


# Where an anti-aircraft vehicle wants to be: on its own side of the fight, behind its
# friends, and nearest to whichever of them an enemy aircraft is closest to.
func _aa_post() -> Vector3:
	var back: Vector3 = -main.path_forward(tank.team)
	var threat = null
	var near := INF
	for a in main.aircraft:
		if is_instance_valid(a) and a.team != tank.team and not a.dying and not a.wrecked:
			var d: float = a.global_position.distance_to(tank.global_position)
			if d < near:
				near = d
				threat = a
	var sum := Vector3.ZERO
	var count := 0
	var guard: Tank = null
	var guard_d := INF
	for t in main.tanks:
		if t.team == tank.team and t != tank and not t.def.has("aa"):
			sum += t.global_position
			count += 1
			if threat != null and t.global_position.distance_to(threat.global_position) < guard_d:
				guard_d = t.global_position.distance_to(threat.global_position)
				guard = t
	if count == 0:
		return tank.global_position
	var base: Vector3 = guard.global_position if guard != null else sum / float(count)
	return base + back * 85.0 + back.cross(Vector3.UP) * side * 25.0


func _raw_goal() -> Vector3:
	if tank.def.has("aa"):
		return _aa_post()
	var dir: float = main.team_dir(tank.team)
	var robot: Vector3 = main.objective_pos()
	var order := _order()
	var ahead: Vector3 = main.path_forward(tank.team)   # along the route towards the enemy
	var across := ahead.cross(Vector3.UP)
	var spread := across * (side * 6.0) + ahead * (float(tank.slot["index"]) * 5.0 - 10.0)
	match String(order.get("type", "")):
		"move":
			return order["pos"] + spread
		"follow":
			return order["by"].global_position + spread - ahead * 12.0
		"rush":
			return robot + across * (side * 6.0) - ahead * 4.0
		"cover":
			if _cover_stamp != order["stamp"]:
				_cover_stamp = order["stamp"]
				var house = main.map.nearest_house(Vector2(tank.global_position.x, tank.global_position.z), 160.0)
				if house == null:
					_cover_pos = tank.global_position - _threat_dir(tank.global_position) * 40.0
				else:
					var h := Vector3(house.x, 0, house.y)
					_cover_pos = h - _threat_dir(h) * 17.0 + Vector3(side * 5.0, 0, 0)
			return _cover_pos
		"attack":
			# Close in on a designated target that cannot be engaged from here.
			var t: Tank = order["target"]
			if style != "artillery" and target != t:
				return t.global_position - _threat_dir(tank.global_position) * 120.0 + spread
	if main.mode["kind"] == "domination":
		return main.dom_goal(tank) + Vector3(side * 9.0, 0, wing * 9.0)
	if main.mode["kind"] == "deathmatch":
		return _hunt()
	match style:
		# In a town there is no open country to stand off in: everyone works along the route,
		# some ahead of the objective, some well back down the street.
		"front":
			return _on_route(-14.0, side * 6.0)
		"sniper":
			return _on_route(110.0, side * 6.0)
		"ambush":
			return _on_route(45.0, side * 6.5)
		"artillery":
			return _on_route(230.0, side * 6.0)
		"scout":
			return _on_route(-35.0, wing * 6.5)
		"flank":
			return _on_route(-70.0, wing * 7.0)
		"escort":
			var shield := _nearest_shield()
			if shield != null:
				# Behind the heavy and off to one side, so the gun has a lane past it.
				var away := -_threat_dir(shield.global_position)
				return shield.global_position + away * 9.0 + away.cross(Vector3.UP) * wing * 10.0
			return _on_route(20.0, wing * 6.5)
	return _on_route(6.0, side * 7.0)


# Deathmatch has no objective to gather at. A bot with an enemy in mind closes to the range
# its kind of vehicle likes; one without prowls the streets, picking somewhere it can see
# down a street to, more often than not towards where the enemy started.
func _hunt() -> Vector3:
	if target != null and is_instance_valid(target):
		var reach := 150.0 if (style == "sniper" or style == "artillery") else (45.0 if (style == "flank" or style == "scout") else 75.0)
		return target.global_position - _threat_dir(tank.global_position) * reach
	var here := tank.global_position
	if main.elapsed >= _roam_until or here.distance_to(_roam) < 14.0:
		_roam_until = main.elapsed + randf_range(18.0, 30.0)
		var enemy_end: Vector3 = main.dm_spawn[1 - tank.team]
		var best := here
		var best_score := -INF
		# One bot in three makes for the middle of the fight; the rest prowl, but stay within
		# about 450 m of it rather than wandering off to the far corners of the map.
		var middle: Vector3 = main.objective_pos()
		if int(tank.slot["index"]) % 3 == 0 and here.distance_to(middle) > 60.0:
			_roam = middle + Vector3(side * 25.0, 0, wing * 20.0)
			return _roam
		var options: Array = main.map.street_points_near(Vector2(here.x, here.z), 60.0, 190.0).filter(func(p): return Vector2(middle.x, middle.z).distance_to(p) < 450.0)
		options.shuffle()
		for i in mini(options.size(), 10):
			var p := Vector3(options[i].x, here.y, options[i].y)
			var score := randf() * 120.0 - p.distance_to(enemy_end) * (0.5 if randf() < 0.7 else -0.2)
			if _ray(here + Vector3(0, 1.5, 0), p + Vector3(0, 1.5, 0), 1).is_empty():
				score += 150.0  # a clear run down a street
			if score > best_score:
				best_score = score
				best = p
		_roam = best
	return _roam


# Turns the hull towards a direction while standing still. Returns the remaining angle.
func _face(dir: Vector3) -> float:
	var local := tank.to_local(tank.global_position + dir * 10.0)
	var off := atan2(local.x, -local.z)
	tank.steer = clampf(off * 2.5, -1.0, 1.0) if absf(off) > 0.04 else 0.0
	return off


func _rest() -> void:
	_check_t = 0.0
	_check_pos = tank.global_position


func _drive(delta: float) -> void:
	var local := tank.to_local(_goal())
	var dist := Vector2(local.x, local.z).length()
	if reverse_t > 0.0:
		reverse_t -= delta
		tank.throttle = -1.0
		tank.steer = reverse_steer
		return
	if detour_t > 0.0:
		# Fresh out of reverse: swing wide round whatever was in the way before heading on.
		detour_t -= delta
		tank.throttle = 0.8
		tank.steer = detour_steer
		return
	# A gun without a turret has to stop and point the whole vehicle.
	if fixed_gun and has_los and dist < 150.0:
		tank.throttle = 0.0
		_face(_threat_dir(tank.global_position))
		_rest()
		return
	if dist < (4.0 if style == "escort" else 8.0):
		tank.throttle = 0.0
		tank.steer = 0.0
		_rest()
		if style == "front" or style == "sniper":
			# Square the front plate to whoever is shooting.
			_face(_threat_dir(tank.global_position))
		return
	var angle := atan2(local.x, -local.z)
	var steer := clampf(angle * 2.0, -1.0, 1.0)
	var throttle := 1.0 if absf(angle) < 1.0 else 0.3
	if dist < 20.0:
		throttle *= 0.6

	var from := tank.global_position + Vector3(0, 1.2, 0)
	var fwd := -tank.global_transform.basis.z
	var ahead := _ray(from, from + fwd * 18.0, 3)
	if not ahead.is_empty() and from.distance_to(ahead["position"]) < dist:
		var left := _ray(from, from + fwd.rotated(Vector3.UP, 0.7) * 18.0, 3)
		var right := _ray(from, from + fwd.rotated(Vector3.UP, -0.7) * 18.0, 3)
		var dl := 18.0 if left.is_empty() else from.distance_to(left["position"])
		var dr := 18.0 if right.is_empty() else from.distance_to(right["position"])
		steer = -1.0 if dl > dr else 1.0
		throttle = 0.6

	# Whiskers: a feeler out ahead from each front corner. If only one of them finds a wall,
	# the vehicle is about to clip it with that side, so it eases away before it does.
	var half := fwd.cross(Vector3.UP) * (float(tank.def["width"]) * 0.5 + 0.7)
	var feel_right := _ray(from + half, from + half + fwd * 12.0, 1)
	var feel_left := _ray(from - half, from - half + fwd * 12.0, 1)
	if feel_left.is_empty() != feel_right.is_empty():
		steer = clampf(steer + (0.8 if feel_right.is_empty() else -0.8), -1.0, 1.0)
		throttle = minf(throttle, 0.7)

	# Stuck check: it wants to go somewhere but has barely moved in two seconds, whether it
	# is jammed nose-first into a wall or sliding uselessly along one.
	_check_t += delta
	if tank.modules["tracks"] > 0.0:
		_rest()
	elif _check_t >= 2.0:
		var moved := tank.global_position.distance_to(_check_pos)
		_rest()
		if moved < 2.5:
			_back_out(from, fwd)
			return
		_tries = 0
	tank.throttle = throttle
	tank.steer = steer


# Reverses away from an obstacle, then drives round it on whichever side has more room.
# Each failed attempt backs up further and tries the other side.
func _back_out(from: Vector3, fwd: Vector3) -> void:
	var left := _ray(from, from + fwd.rotated(Vector3.UP, 1.0) * 22.0, 3)
	var right := _ray(from, from + fwd.rotated(Vector3.UP, -1.0) * 22.0, 3)
	var dl := 22.0 if left.is_empty() else from.distance_to(left["position"])
	var dr := 22.0 if right.is_empty() else from.distance_to(right["position"])
	var go := -1.0 if dl > dr else 1.0  # steer: -1 is left
	if absf(dl - dr) < 1.0:
		go = -1.0 if randf() < 0.5 else 1.0
	if _tries % 2 == 1:
		go = -go
	_tries += 1
	main.tally(tank.team, "backed_out")
	if _tries == 4:
		main.tally(tank.team, "still_stuck_after_4")
	var rev_speed := maxf(float(tank.def["speed_rev"]) / 3.6, 2.0)
	reverse_t = clampf((7.0 + _tries * 3.0) / rev_speed, 1.5, 5.0)
	reverse_steer = -go * 0.5  # swing the nose towards the open side while backing
	detour_t = 2.0 + _tries * 0.5
	detour_steer = go * 0.7


# True if a friendly vehicle sits between the muzzle and where the gun is pointing.
func _friend_in_the_way(reach: float) -> bool:
	var from := tank.muzzle.global_position
	var hit := _ray(from, from - tank.muzzle.global_transform.basis.z * reach, 2)
	return not hit.is_empty() and hit["collider"] is Tank and hit["collider"].team == tank.team


# An aircraft worth shooting at, or null. Anti-aircraft vehicles go for any aircraft in view
# out to 1600 m. Light tanks with a quick turret will have a go at a helicopter that comes
# close: within 420 m if they have nothing else to shoot, within 260 m regardless.
func _air_target():
	var aa: bool = tank.def.has("aa")
	if not aa and not (tank.def["class"] == "light" and float(tank.def["turret_traverse"]) >= 35.0):
		return null
	var best = null
	var reach := 1600.0 if aa else (420.0 if (target == null or not is_instance_valid(target)) else 260.0)
	for a in main.aircraft:
		if not is_instance_valid(a) or a.team == tank.team or a.dying or a.wrecked or (not aa and not a.heli):
			continue
		var d: float = tank.global_position.distance_to(a.global_position)
		if d < reach and _ray(tank.eye(), a.global_position + Vector3(0, 1.5, 0), 1).is_empty():
			reach = d
			best = a
	return best


func _shoot(delta: float) -> void:
	tank.want_fire = false
	tank.want_mg = false
	var air = _air_target()
	if air != null:
		var away: float = tank.global_position.distance_to(air.global_position)
		var guided: bool = tank.def.get("aa", "") == "missile"
		# Aim ahead of it by as far as it will fly while the shell is on its way (a missile needs no lead).
		var ahead: Vector3 = Vector3.ZERO if guided else air.motion() * (away / float(tank.current_shell()["velocity"]))
		tank.aim_point = air.global_position + Vector3(0, 1.5, 0) + ahead + (Vector3.ZERO if guided else aim_err * 0.5)
		var on_it := tank.gun_error() < 0.04
		tank.want_fire = tank.aa_locked() if guided else on_it
		tank.want_mg = on_it and away < 450.0 and not tank.def.has("aa")
		return
	if target == null or not is_instance_valid(target):
		blocked_t = 0.0
		# Nothing armoured to shoot: hose down any toy soldiers nearby with the machine gun.
		var man: Soldier = null
		var near := 140.0
		for s in main.soldiers:
			if s.team != tank.team and tank.global_position.distance_to(s.global_position) < near:
				near = tank.global_position.distance_to(s.global_position)
				man = s
		if man != null:
			tank.aim_point = man.global_position + Vector3(0, 1.4, 0)
			tank.want_mg = tank.gun_error() < 0.05 and not _friend_in_the_way(near)
			return
		var fwd := -tank.global_transform.basis.z
		tank.aim_point = tank.global_position + fwd * 200.0 + Vector3(0, 2, 0)
		return
	var sd := tank.current_shell()
	var d := tank.global_position.distance_to(target.global_position)
	# Lead the target, and allow for the shell carrying this vehicle's own motion with it.
	var lead: Vector3 = (target.velocity - tank.velocity) * (d / float(sd["velocity"]))
	tank.aim_point = target.global_position + Vector3(0, 1.3, 0) + lead + aim_err
	var on_target := tank.gun_error() < (0.035 if style == "artillery" else 0.02)
	# Hold fire while a friend is in the way (artillery fires over their heads).
	if on_target and style != "artillery" and _friend_in_the_way(d):
		blocked_t += delta
		if blocked_t > 0.8 and shift_t <= 0.0:
			# Shuffle sideways to open a lane.
			var across := _threat_dir(tank.global_position).cross(Vector3.UP)
			shift = across * 12.0 * (1.0 if randf() < 0.5 else -1.0)
			shift_t = 5.0
		return
	blocked_t = 0.0
	tank.want_fire = on_target
	# The machine gun is only worth firing at thin-skinned targets.
	var mg_pen: float = GameData.shells[tank.def["mg"]]["pen"]
	tank.want_mg = d < 450.0 and tank.gun_error() < 0.04 and float(target.def["armour"]["hull_side"]) <= mg_pen * 1.2
