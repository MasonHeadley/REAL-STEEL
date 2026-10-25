extends Node
# A match played over the network. main.gd adds one of these (always called "Netplay", so
# every PC's copy has the same address) when a lobby starts a match.
#
# The host's PC plays the real match: it drives the bots, moves every vehicle, flies every
# shell and decides every hit. Everyone else's PC is a window on to it:
#   - twenty times a second the host sends where every vehicle is, its health and where its
#     gun is pointing (_snap), and the others move their copies of the vehicles to match;
#   - things that happen once (a vehicle rolling out, a shot, a kill, smoke, the end of the
#     match) are sent as they happen, and are certain to arrive;
#   - each player's own controls (throttle, steering, where they are aiming, triggers) go
#     to the host many times a second (_input), and the host drives their vehicle with them.
# So what a joining player sees of their own vehicle is a moment behind their hands, by the
# time it takes to reach the host and come back.
#
# Soldiers and the loose objects on the map are the host's too: ten times a second it sends
# where every soldier is and what he is doing (_men), and where every object that has been
# knocked about has got to (_props).
#
# Aircraft work the same way (see the aircraft section below): the host flies every one of
# them, its own, the bots' and each joined player's (from that player's controls), and sends
# where they all are twenty times a second. A joined player on foot is the host's soldier
# too, moved by that player's controls.

const TANK_FIELDS := 16  # numbers sent for each vehicle in a snapshot
const HEAD_FIELDS := 11  # and for the match as a whole
const AIR_FIELDS := 21   # and for each aircraft

var main
var is_host := false
var _tick := 0
var _inputs := {}  # peer id -> the latest controls from that player
var _air_inputs := {}  # the same, for a player who is flying
var _man_inputs := {}  # and for one on foot


func _ready() -> void:
	is_host = multiplayer.is_server()
	if is_host:
		multiplayer.peer_disconnected.connect(_on_player_left)


func _slot_of(peer: int) -> Dictionary:
	for slot in main.slots:
		if int(slot.get("peer", 0)) == peer:
			return slot
	return {}


func _physics_process(_delta: float) -> void:
	if main.match_over:
		return
	if is_host:
		_drive_from_inputs()
		_tick += 1
		if _tick % 3 == 0:
			_snap.rpc(_pack())
			_send_airs()
		if _tick % 12 == 7:
			_send_own_men()
		if _tick % 90 == 1:
			_scores.rpc(_score_rows())
		if _tick % 12 == 4 and main.dom.size() == 3:
			var d := PackedFloat32Array([main.dom_score[0], main.dom_score[1]])
			for p in main.dom:
				d.append_array([p["owner"], p["progress"], p["taking"]])
			_points.rpc(d)
		if _tick % 6 == 2:
			_send_men()
		if _tick % 6 == 5:
			_send_props()
	else:
		_send_input()


# ---- the host: what everyone needs to know, as it happens ----

func tell_spawn(slot: Dictionary, t: Tank) -> void:
	_spawn.rpc(slot["id"], slot["vehicle_id"], slot["wear"], slot["wear_seed"], t.global_position, t.heading, slot.get("look", {}))


@rpc("authority", "call_remote", "reliable")
func _spawn(id: int, vehicle: String, wear: float, wear_seed: int, pos: Vector3, heading: float, look: Dictionary = {}) -> void:
	main.spawn_from_host(id, vehicle, wear, wear_seed, pos, heading, look)


func tell_died(t: Tank, killer, how: String, who: String) -> void:
	_died.rpc(t.slot["id"], killer.slot["id"] if killer != null else -1, how, who)


@rpc("authority", "call_remote", "reliable")
func _died(id: int, killer_id: int, how: String, who: String) -> void:
	main.died_from_host(id, killer_id, how, who)


func tell_shell(shooter: Tank, shell_id: String, pos: Vector3, dir: Vector3, speed: float, gravity: float, indirect: bool) -> void:
	_shell.rpc(shooter.slot["id"], shell_id, pos, dir, speed, gravity, indirect)


@rpc("authority", "call_remote", "reliable")
func _shell(id: int, shell_id: String, pos: Vector3, dir: Vector3, speed: float, gravity: float, indirect: bool) -> void:
	var t = main.slots[id]["tank"]
	if t != null and is_instance_valid(t) and GameData.shells.has(shell_id):
		t.show_shot()
		var how := {"speed": speed, "gravity": gravity}
		if indirect:
			how["indirect"] = true
		main.spawn_shell(t, GameData.shells[shell_id], pos, dir, how)


func tell_smoke(pos: Vector3, radius: float, seconds: float) -> void:
	_smoke.rpc(pos, radius, seconds)


@rpc("authority", "call_remote", "reliable")
func _smoke(pos: Vector3, radius: float, seconds: float) -> void:
	main.add_smoke(pos, radius, seconds)


# A joined player was hit: where from, for the mark on their screen.
func tell_hurt(peer: int, at: Vector3, known: bool) -> void:
	_hurt_mark.rpc_id(peer, at, known)


@rpc("authority", "call_remote", "unreliable")
func _hurt_mark(at: Vector3, known: bool) -> void:
	main.show_hurt(at, known)


# Something only one player should see or hear: the result of their shot, or points scored.
func tell_one(slot: Dictionary, text: String, result: String) -> void:
	if int(slot.get("peer", 0)) > 1:
		_msg.rpc_id(slot["peer"], text, result)


@rpc("authority", "call_remote", "reliable")
func _msg(text: String, result: String) -> void:
	main.show_msg(text)
	if result != "":
		main.shot_voice(result)


func tell_award(slot: Dictionary, text: String, colour: Color, what: String) -> void:
	if int(slot.get("peer", 0)) > 1:
		_popup.rpc_id(slot["peer"], text, colour, what)


@rpc("authority", "call_remote", "reliable")
func _popup(text: String, colour: Color, what: String) -> void:
	main.popups.push_front({"text": text, "colour": colour, "t": 4.0})
	if main.popups.size() > 5:
		main.popups.pop_back()
	if what == "kill":
		Sfx.play_ui("kill", 0.0)
	elif what == "assist":
		Sfx.play_ui("assist", -4.0, 0.8)


func tell_feed(line: String) -> void:
	_feed.rpc(line)


@rpc("authority", "call_remote", "reliable")
func _feed(line: String) -> void:
	main.feed.push_front(line)
	if main.feed.size() > 5:
		main.feed.pop_back()


func tell_end(winner: int) -> void:
	_end.rpc(winner, _score_rows())


@rpc("authority", "call_remote", "reliable")
func _end(winner: int, rows: Array) -> void:
	_scores(rows)
	main.finish_from_host(winner)


@rpc("authority", "call_remote", "unreliable_ordered")
func _points(d: PackedFloat32Array) -> void:
	if d.size() < 11 or main.dom.size() != 3:
		return
	main.dom_score = [d[0], d[1]]
	for i in 3:
		main.dom[i]["owner"] = int(d[2 + i * 3])
		main.dom[i]["progress"] = d[3 + i * 3]
		main.dom[i]["taking"] = int(d[4 + i * 3])
	main.dom_show()


# ---- emotes and pings ----

func ask_emote(id: String) -> void:
	_want_emote.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _want_emote(id: String) -> void:
	var slot := _slot_of(multiplayer.get_remote_sender_id())
	if is_host and not slot.is_empty() and slot["tank"] != null and is_instance_valid(slot["tank"]) and GameData.emotes.has(id):
		main.send_emote(slot["tank"], id)


func tell_emote(slot_id: int, id: String, sound: String) -> void:
	_emote.rpc(slot_id, id, sound)


@rpc("authority", "call_remote", "reliable")
func _emote(slot_id: int, id: String, sound: String) -> void:
	var t = main.slots[slot_id]["tank"] if slot_id >= 0 and slot_id < main.slots.size() else null
	if t != null and is_instance_valid(t) and GameData.emotes.has(id) and Sfx.BUS.has(sound):
		t.emote = id
		t.emote_t = 3.0
		Sfx.play(sound, t.global_position + Vector3(0, 4, 0), 2.0, GameData.emotes[id]["pitch"], 25.0)


# ping_id "" is a bare marker; otherwise one of the orders in the ping sheet.
func ask_ping(ping_id: String, pos: Vector3) -> void:
	_want_ping.rpc_id(1, ping_id, pos)


@rpc("any_peer", "call_remote", "reliable")
func _want_ping(ping_id: String, pos: Vector3) -> void:
	var slot := _slot_of(multiplayer.get_remote_sender_id())
	if not is_host or slot.is_empty() or slot["tank"] == null or not is_instance_valid(slot["tank"]):
		return
	if ping_id == "":
		main.mark_ping(slot["tank"], pos)
	elif GameData.pings.has(ping_id):
		main.issue_ping(slot["tank"], ping_id, pos)


func tell_ping(p: Dictionary) -> void:
	var target = p["target"]
	_ping.rpc(p["pos"], p["label"], p["colour"], p["t"], p["team"], p["order"], target.slot["id"] if target != null and is_instance_valid(target) else -1, p["by"].slot["id"])


@rpc("authority", "call_remote", "reliable")
func _ping(pos: Vector3, label: String, colour: Color, seconds: float, team: int, order: String, target_id: int, by_id: int) -> void:
	var target = main.slots[target_id]["tank"] if target_id >= 0 and target_id < main.slots.size() else null
	var by = main.slots[by_id]["tank"] if by_id >= 0 and by_id < main.slots.size() else null
	if order == "attack" and (target == null or not is_instance_valid(target)):
		return
	main.pings.append({"pos": pos, "label": label, "colour": colour, "t": seconds, "team": team, "order": order, "target": target, "by": by})
	if main.pings.size() > 6:
		main.pings.pop_front()
	if by != null and is_instance_valid(by) and by.is_mine():
		Sfx.play_ui("click", -4.0, 1.4)


# ---- soldiers and loose objects ----

func tell_man(id: int, team: int, kind: String, pos: Vector3, owner_id: int = -1) -> void:
	_man.rpc(id, team, kind, pos, owner_id)


@rpc("authority", "call_remote", "reliable")
func _man(id: int, team: int, kind: String, pos: Vector3, owner_id: int = -1) -> void:
	main.man_from_host(id, team, kind, pos, owner_id)


func _send_men() -> void:
	var d := PackedFloat32Array()
	for id in main.men.keys():
		var s = main.men[id]
		if not is_instance_valid(s):
			main.men.erase(id)
			continue
		d.append_array([id, s.global_position.x, s.global_position.z, s.rotation.y, s.flags()])
	if not d.is_empty():
		_men.rpc(d)


@rpc("authority", "call_remote", "unreliable_ordered")
func _men(d: PackedFloat32Array) -> void:
	for i in range(0, d.size() - 4, 5):
		var s = main.men.get(int(d[i]))
		if s != null and is_instance_valid(s):
			s.net_pos = Vector3(d[i + 1], 0, d[i + 2])
			s.net_yaw = d[i + 3]
			s.net_flags = int(d[i + 4])
			s.net_seen = main.elapsed


func tell_man_shot(id: int, mark: Vector3) -> void:
	_man_shot.rpc(id, mark)


@rpc("authority", "call_remote", "unreliable")
func _man_shot(id: int, mark: Vector3) -> void:
	var s = main.men.get(id)
	if s != null and is_instance_valid(s):
		s.show_shot(mark)


func tell_grenade(from: Vector3, to: Vector3, smoke: bool, team: int) -> void:
	_grenade.rpc(from, to, smoke, team)


@rpc("authority", "call_remote", "reliable")
func _grenade(from: Vector3, to: Vector3, smoke: bool, team: int) -> void:
	var g := Soldier.Grenade.new()
	g.main = main
	g.team = team
	main.add_child(g)
	g.launch(from, to, smoke)


# Every object that has moved since the last time: where it is now. One that has come to
# rest is sent once more, so everyone has its final place exactly.
func _send_props() -> void:
	var d := PackedFloat32Array()
	for p in main.map.props:
		if is_instance_valid(p) and p.moved:
			p.moved = not p.freeze
			var q: Quaternion = p.global_transform.basis.get_rotation_quaternion()
			d.append_array([p.prop_id, p.global_position.x, p.global_position.y, p.global_position.z, q.x, q.y, q.z, q.w])
			if d.size() >= 8 * 40:  # (kept under the size one network packet can carry)
				break  # plenty for one message; the rest go in the next
	if not d.is_empty():
		_props.rpc(d)


@rpc("authority", "call_remote", "unreliable_ordered")
func _props(d: PackedFloat32Array) -> void:
	for i in range(0, d.size() - 7, 8):
		var id := int(d[i])
		if id >= 0 and id < main.map.props.size() and is_instance_valid(main.map.props[id]):
			main.map.props[id].follow(Transform3D(Basis(Quaternion(d[i + 4], d[i + 5], d[i + 6], d[i + 7])), Vector3(d[i + 1], d[i + 2], d[i + 3])))


# ---- the host: the running picture ----

func _pack() -> PackedFloat32Array:
	var d := PackedFloat32Array([main.prep_t, main.time_left, main.elapsed, main.push.robot_s, main.push.progress[0], main.push.progress[1],
		main.team_kills[0], main.team_kills[1], main.push.controller, main.sky_scan[0], main.sky_scan[1]])
	for slot in main.slots:
		var t = slot["tank"]
		if t == null or not is_instance_valid(t):
			continue
		var flags := (1 if t.want_mg else 0) + (2 if t.spotted else 0) + (4 if t.auto_drop else 0) + (8 if t.revealed_t > 0.0 else 0) + (16 if t.radar_on else 0)
		d.append_array([slot["id"], t.global_position.x, t.global_position.y, t.global_position.z, t.heading, t.speed, t.hp,
			t.reload_left, t.reload_total, t.aim_point.x, t.aim_point.y, t.aim_point.z, flags, t.ability_cd, t.ability_left, t.shell_index])
	return d


@rpc("authority", "call_remote", "unreliable_ordered")
func _snap(d: PackedFloat32Array) -> void:
	if d.size() < HEAD_FIELDS:
		return
	main.prep_t = d[0]
	main.time_left = d[1]
	main.elapsed = d[2]
	main.push.robot_s = d[3]
	main.push.progress[0] = d[4]
	main.push.progress[1] = d[5]
	main.team_kills[0] = int(d[6])
	main.team_kills[1] = int(d[7])
	main.push.controller = int(d[8])
	main.sky_scan[0] = d[9]
	main.sky_scan[1] = d[10]
	main.push.place()
	var i := HEAD_FIELDS
	while i + TANK_FIELDS <= d.size():
		var id := int(d[i])
		if id >= 0 and id < main.slots.size():
			var t = main.slots[id]["tank"]
			if t != null and is_instance_valid(t):
				t.net_pos = Vector3(d[i + 1], d[i + 2], d[i + 3])
				t.net_heading = d[i + 4]
				t.net_speed = d[i + 5]
				if not is_equal_approx(t.hp, d[i + 6]):
					t.hp = d[i + 6]
					t.refresh_damage_look()
				t.reload_left = d[i + 7]
				t.reload_total = maxf(d[i + 8], 0.01)
				var flags := int(d[i + 12])
				t.spotted = flags & 2 != 0
				t.revealed_t = 1.0 if flags & 8 != 0 else 0.0
				t.ability_cd = d[i + 13]
				t.ability_left = d[i + 14]
				if not t.is_mine():
					t.radar_on = flags & 16 != 0
					# Our own gun follows our own aim at once; everyone else's follows the host.
					t.aim_point = Vector3(d[i + 9], d[i + 10], d[i + 11])
					t.want_mg = flags & 1 != 0
					t.auto_drop = flags & 4 != 0
					t.shell_index = int(d[i + 15])
		i += TANK_FIELDS


func _score_rows() -> Array:
	var rows: Array = []
	for slot in main.slots:
		rows.append([slot["id"], slot["kills"], slot["deaths"], slot["assists"], slot["points"], slot["vehicle_id"], slot["name"]])
	return rows


@rpc("authority", "call_remote", "reliable")
func _scores(rows: Array) -> void:
	for r in rows:
		if int(r[0]) < main.slots.size():
			var slot: Dictionary = main.slots[int(r[0])]
			slot["kills"] = r[1]
			slot["deaths"] = r[2]
			slot["assists"] = r[3]
			slot["points"] = r[4]
			if slot["tank"] == null:
				slot["vehicle_id"] = r[5] if not slot["camera"] else slot["vehicle_id"]
			slot["name"] = r[6]


# ---- a joining player: sending the controls ----

func _send_input() -> void:
	var pc = main.player_ctrl
	if pc.has_air() and not pc.air.dying and not pc.air.wrecked:
		# Flying: the same things the host's own pilot would feed his aircraft (see Aircraft.want).
		var w: Dictionary = pc.air.want
		var move: Vector3 = w.get("move", Vector3.ZERO)
		var dir: Vector3 = w.get("aim_dir", Vector3.FORWARD)
		var at: Vector3 = w.get("aim_at", pc.air.global_position + dir * 800.0)
		var bits := 0
		for i in AIR_KEYS.size():
			if w.get(AIR_KEYS[i], false):
				bits += 1 << i
		_air_controls.rpc_id(1, PackedFloat32Array([move.x, move.z, float(w.get("lift", 0.0)), float(w.get("yaw", 0.0)), dir.x, dir.y, dir.z, at.x, at.y, at.z, bits]))
		return
	if pc.has_man():
		var w: Dictionary = pc.man.want
		var move: Vector3 = w.get("move", Vector3.ZERO)
		var from: Vector3 = w.get("aim_from", pc.man.eye())
		var dir: Vector3 = w.get("aim_dir", Vector3.FORWARD)
		var bits := 0
		for i in MAN_KEYS.size():
			if w.get(MAN_KEYS[i], false):
				bits += 1 << i
		_man_controls.rpc_id(1, PackedFloat32Array([move.x, move.z, float(w.get("yaw", 0.0)), float(w.get("pitch", 0.0)), from.x, from.y, from.z, dir.x, dir.y, dir.z, int(w.get("weapon", 0)), bits]))
		return
	if not pc.has_tank():
		return
	var t: Tank = pc.tank
	_controls.rpc_id(1, PackedFloat32Array([t.throttle, t.steer, t.aim_point.x, t.aim_point.y, t.aim_point.z,
		1.0 if t.want_fire else 0.0, 1.0 if t.want_mg else 0.0, t.shell_index, t.zero_range]))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _controls(d: PackedFloat32Array) -> void:
	if is_host and d.size() >= 9:
		_inputs[multiplayer.get_remote_sender_id()] = d


func _drive_from_inputs() -> void:
	for peer in _air_inputs:
		var slot := _slot_of(peer)
		var a = slot.get("air") if not slot.is_empty() else null
		if a == null or not is_instance_valid(a) or a.dying or a.wrecked:
			continue
		var d: PackedFloat32Array = _air_inputs[peer]
		var bits := int(d[10])
		var w := {"move": Vector3(clampf(d[0], -1, 1), 0, clampf(d[1], -1, 1)), "lift": clampf(d[2], -1, 1), "yaw": d[3],
			"aim_dir": Vector3(d[4], d[5], d[6]).normalized(), "aim_at": Vector3(d[7], d[8], d[9])}
		for i in AIR_KEYS.size():
			w[AIR_KEYS[i]] = bits & (1 << i) != 0
		a.want = w
	for peer in _man_inputs:
		var slot := _slot_of(peer)
		var man = slot.get("man") if not slot.is_empty() else null
		if man == null or not is_instance_valid(man) or man.state != "up":
			continue
		var d: PackedFloat32Array = _man_inputs[peer]
		var bits := int(d[11])
		var w := {"move": Vector3(clampf(d[0], -1, 1), 0, clampf(d[1], -1, 1)), "yaw": d[2], "pitch": d[3],
			"aim_from": Vector3(d[4], d[5], d[6]), "aim_dir": Vector3(d[7], d[8], d[9]).normalized(), "weapon": int(d[10])}
		for i in MAN_KEYS.size():
			w[MAN_KEYS[i]] = bits & (1 << i) != 0
		man.want = w
	for peer in _inputs:
		var slot := _slot_of(peer)
		if slot.is_empty() or slot["tank"] == null or not is_instance_valid(slot["tank"]):
			continue
		var t: Tank = slot["tank"]
		var d: PackedFloat32Array = _inputs[peer]
		t.track_drive = true
		t.throttle = clampf(d[0], -1.0, 1.0)
		t.steer = clampf(d[1], -1.0, 1.0)
		t.aim_point = Vector3(d[2], d[3], d[4])
		t.want_fire = d[5] > 0.5
		t.want_mg = d[6] > 0.5
		t.shell_index = int(d[7])
		t.zero_range = d[8]


func ask_ability() -> void:
	_ability.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _ability() -> void:
	var slot := _slot_of(multiplayer.get_remote_sender_id())
	if is_host and not slot.is_empty() and slot["tank"] != null and is_instance_valid(slot["tank"]):
		slot["tank"].use_ability()


# The vehicle and starting place a player chose on their deploy screen.
func ask_pick(vehicle: String, lane: int, look: Dictionary = {}) -> void:
	_pick.rpc_id(1, vehicle, lane, look)


@rpc("any_peer", "call_remote", "reliable")
func _pick(vehicle: String, lane: int, look: Dictionary = {}) -> void:
	var slot := _slot_of(multiplayer.get_remote_sender_id())
	if is_host and not slot.is_empty() and GameData.vehicles.has(vehicle) and Settings.vehicle_enabled(vehicle):
		slot["vehicle_id"] = vehicle
		slot["look"] = look  # their paint, markings and equipment
		slot["lane"] = clampi(lane, 0, 2)
		slot["ready"] = true


# Someone dropped out: a bot takes their seat, and their vehicle if they had one.
func _on_player_left(peer: int) -> void:
	var slot := _slot_of(peer)
	_inputs.erase(peer)
	if slot.is_empty():
		return
	slot["peer"] = 0
	slot["human"] = false
	slot["ready"] = true
	if slot["vehicle_id"] == "":
		slot["vehicle_id"] = GameData.vehicle_order[randi() % GameData.vehicle_order.size()]
	var t = slot["tank"]
	if t != null and is_instance_valid(t):
		main.give_bot(t)
	tell_feed("%s left the match" % slot["name"])


# ---- aircraft ----
# Which of a pilot's (and a foot soldier's) on-off controls go in which bit of the number sent.
const AIR_KEYS := ["fire", "rocket", "bomb", "seek", "missile", "flare"]
const MAN_KEYS := ["sprint", "crouch", "prone", "jump", "fire", "aim", "use", "throw", "reload"]


func tell_air(a: Aircraft) -> void:
	_air.rpc(a.net_id, a.team, String(a.def["id"]), a.stores.map(func(st): return st["kind"]), a.global_position, a.yaw, int(a.owner_slot.get("id", -1)))


@rpc("authority", "call_remote", "reliable")
func _air(net_id: int, team: int, id: String, loadout: Array, pos: Vector3, yaw: float, owner_id: int) -> void:
	main.air_from_host(net_id, team, id, loadout, pos, yaw, owner_id)


# Where every aircraft is, how it is pointing and moving, and what state it is in.
func _send_airs() -> void:
	var d := PackedFloat32Array()
	for id in main.airs.keys():
		var a = main.airs[id]
		if not is_instance_valid(a):
			main.airs.erase(id)
			continue
		var q: Quaternion = a.global_transform.basis.get_rotation_quaternion()
		var v: Vector3 = a.motion()
		var flags := (1 if a.landed else 0) + (2 if a.dying else 0) + (4 if a.wrecked else 0) + (8 if a.flare_t > 0.0 else 0)
		var lock_id: int = a.lock.net_id if (a.lock != null and is_instance_valid(a.lock)) else -1
		d.append_array([id, a.global_position.x, a.global_position.y, a.global_position.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z,
			a.hp, flags, a.rockets, a.missiles, a.flares, a.bombs.size(), a.speed, a.throttle, lock_id + a.lock_t * 0.001 if lock_id >= 0 else -1.0,
			a.threat_dist if a.threat_t > 0.0 else -1.0])
	if not d.is_empty():
		_airs.rpc(d)


@rpc("authority", "call_remote", "unreliable_ordered")
func _airs(d: PackedFloat32Array) -> void:
	var i := 0
	while i + AIR_FIELDS <= d.size():
		var a = main.airs.get(int(d[i]))
		if a != null and is_instance_valid(a) and not a.wrecked:
			a.net_pos = Vector3(d[i + 1], d[i + 2], d[i + 3])
			a.net_rot = Quaternion(d[i + 4], d[i + 5], d[i + 6], d[i + 7]).normalized()
			a.net_vel = Vector3(d[i + 8], d[i + 9], d[i + 10])
			a.hp = d[i + 11]
			a.net_flags = int(d[i + 12])
			a.flare_t = 1.0 if a.net_flags & 8 != 0 else 0.0
			a.rockets = int(d[i + 13])
			a.missiles = int(d[i + 14])
			a.flares = int(d[i + 15])
			if a.bombs.size() != int(d[i + 16]):
				a.bombs.resize(int(d[i + 16]))
			a.speed = d[i + 17]
			a.throttle = d[i + 18]
			# (The seeker's target and how long it has had it travel as one number: the whole
			# part is the target, the rest is the time in thousandths.)
			var locked: float = d[i + 19]
			a.lock = main.airs.get(int(locked)) if locked >= 0.0 else null
			a.lock_t = (locked - floorf(locked)) * 1000.0 if locked >= 0.0 else 0.0
			a.threat_t = 0.3 if d[i + 20] >= 0.0 else 0.0
			a.threat_dist = d[i + 20] if d[i + 20] >= 0.0 else 9999.0
		i += AIR_FIELDS


# An aircraft has been shot down: what its pilot's screen should say, and the line for the feed.
func tell_air_down(net_id: int, text: String, line: String) -> void:
	_air_down.rpc(net_id, text, line)


@rpc("authority", "call_remote", "reliable")
func _air_down(net_id: int, text: String, line: String) -> void:
	var a = main.airs.get(net_id)
	if a != null and is_instance_valid(a):
		a.set_meta("down_text", text)
	if line != "":
		main.feed.push_front(line)
		if main.feed.size() > 5:
			main.feed.pop_back()


# Something fired from the air (or a rocket from the ground), for the other PCs to show.
func tell_air_fx(kind: String, from: Vector3, vel: Vector3, extra: int, east: bool) -> void:
	if kind == "gun":
		_air_gun.rpc(from, vel)
	else:
		_air_fx.rpc(kind, from, vel, extra, east)


@rpc("authority", "call_remote", "unreliable")
func _air_gun(from: Vector3, at: Vector3) -> void:
	Fx.tracer(main, from, at)
	Sfx.play("autocannon", from, -7.0, 1.1, 38.0, 0.03)


@rpc("authority", "call_remote", "reliable")
func _air_fx(kind: String, from: Vector3, vel: Vector3, extra: int, east: bool) -> void:
	match kind:
		"rocket":
			var r := Aircraft.Rocket.new()
			r.ghost_main = main
			r.east = east
			r.vel = vel
			main.add_child(r)
			r.global_position = from
			Sfx.play("rocket", from, -1.0, 0.9, 70.0)
		"bomb":
			var b := Aircraft.Bomb.new()
			b.main = main
			b.ghost = true
			b.weight = extra
			b.kind = "bomb%d" % extra
			b.east = east
			b.vel = vel
			main.add_child(b)
			b.global_position = from
		"missile":
			var m := Aircraft.Missile.new()
			m.main = main
			m.ghost = true
			m.target = main.airs.get(extra)
			m.vel = vel
			m.east = east
			main.add_child(m)
			m.global_position = from
			Sfx.play("rocket", from, 2.0, 0.8, 90.0)
		"flare":
			var f := Aircraft.Flare.new()
			f.vel = vel
			main.add_child(f)
			f.global_position = from


# A joined player asks for an aircraft with what they hung on it.
func ask_air(id: String, loadout: Array) -> void:
	_want_air.rpc_id(1, id, loadout)


@rpc("any_peer", "call_remote", "reliable")
func _want_air(id: String, loadout: Array) -> void:
	var slot := _slot_of(multiplayer.get_remote_sender_id())
	if is_host and not slot.is_empty():
		main.air_for_slot(slot, id, loadout)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _air_controls(d: PackedFloat32Array) -> void:
	if is_host and d.size() >= 11:
		_air_inputs[multiplayer.get_remote_sender_id()] = d


# ---- a joined player on foot ----

func ask_man(class_id: String, lane: int) -> void:
	_want_man.rpc_id(1, class_id, lane)


@rpc("any_peer", "call_remote", "reliable")
func _want_man(class_id: String, lane: int) -> void:
	var slot := _slot_of(multiplayer.get_remote_sender_id())
	if not is_host or slot.is_empty() or not GameData.infantry.has(class_id) or slot.get("tank") != null:
		return
	var had = slot.get("man")
	if had != null and is_instance_valid(had) and had.state == "up":
		return
	slot["vehicle_id"] = ""
	slot["ready"] = false
	slot["man"] = main.man_for_slot(slot, class_id, clampi(lane, 0, 2))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _man_controls(d: PackedFloat32Array) -> void:
	if is_host and d.size() >= 12:
		_man_inputs[multiplayer.get_remote_sender_id()] = d


# What each joined player on foot needs for their own screen: health, ammunition, weapon in hand.
func _send_own_men() -> void:
	for slot in main.slots:
		var man = slot.get("man")
		if int(slot.get("peer", 0)) > 1 and man != null and is_instance_valid(man):
			_own_man.rpc_id(int(slot["peer"]), PackedFloat32Array([man.net_id, man.hp, man.mag, man.mags, man.pistol, man.pistol_mags, man.grenades, man.rockets, man.weapon, man.reloading, man._fire_t]))


@rpc("authority", "call_remote", "unreliable_ordered")
func _own_man(d: PackedFloat32Array) -> void:
	var man = main.men.get(int(d[0]))
	if man == null or not is_instance_valid(man) or d.size() < 11:
		return
	man.hp = d[1]
	man.mag = int(d[2])
	man.mags = int(d[3])
	man.pistol = int(d[4])
	man.pistol_mags = int(d[5])
	man.grenades = int(d[6])
	man.rockets = int(d[7])
	man.weapon = int(d[8])
	man.reloading = d[9]
	man._fire_t = d[10]


# A joined player asks to give up what they are in and go back to the deploy screen.
func ask_redeploy() -> void:
	_want_redeploy.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _want_redeploy() -> void:
	var slot := _slot_of(multiplayer.get_remote_sender_id())
	if is_host and not slot.is_empty():
		main.redeploy_slot(slot)