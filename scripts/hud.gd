extends Control
# Everything drawn over the 3D world during play. The spawn screen and menus are separate.

var main
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


# ---- the map: a small one in the corner, and a big one over the screen ----
# The small map follows you. Its zoom has four settings (the "zoom in" and "zoom out" keys).
# The "big map" key opens the whole map; there the same keys zoom, and the arrow keys move
# it about. Friends always show; enemies only while your team can see them (a spectator
# sees everyone).

const MAP_SPANS := [1600.0, 800.0, 400.0, 220.0]  # metres across the small map at each zoom
const BIG_SPANS := [1700.0, 1100.0, 700.0, 400.0] # and across the big one

var map_zoom := 2
var map_big := false
var _map_pan := Vector2.ZERO  # how far the big map has been moved, metres (along the map, across it)
var _map_box: Control


func _map_tick(delta: float) -> void:
	if _map_box == null:
		_map_box = Control.new()
		_map_box.clip_contents = true
		_map_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_box.draw.connect(_draw_map)
		add_child(_map_box)
	var playing: bool = main.state == "playing" and not main.match_over and main.sat_texture != null and (main.player_ctrl.has_tank() or main.player_ctrl.has_man() or main.player_ctrl.has_air() or main.spectating)
	_map_box.visible = playing
	if not playing:
		map_big = false
		return
	var sz := get_viewport_rect().size
	if map_big:
		var wide := sz.x * 0.86
		_map_box.size = Vector2(wide, minf(sz.y * 0.8, wide * 0.6))
		_map_box.position = (sz - _map_box.size) * 0.5
		var step: float = BIG_SPANS[map_zoom] * 0.6 * delta
		_map_pan.x += (float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))) * step
		_map_pan.y += (float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))) * step
	else:
		_map_box.size = Vector2(250, 250)
		_map_box.position = Vector2(16, 16)
	_map_box.queue_redraw()


func _unhandled_key_input(e: InputEvent) -> void:
	if _map_box == null or not _map_box.visible:
		return
	if e.is_action_pressed("map"):
		map_big = not map_big
		_map_pan = Vector2.ZERO
	elif e.is_action_pressed("map_in"):
		map_zoom = mini(map_zoom + 1, MAP_SPANS.size() - 1)
	elif e.is_action_pressed("map_out"):
		map_zoom = maxi(map_zoom - 1, 0)


func _draw_map() -> void:
	var box := _map_box
	var tex: Texture2D = main.sat_texture
	var pc: PlayerCtrl = main.player_ctrl
	var me: Vector3 = pc.tank.global_position if pc.has_tank() else (pc.man.global_position if pc.has_man() else (pc.air.global_position if pc.has_air() else pc.cam.global_position))
	var span: float = BIG_SPANS[map_zoom] if map_big else MAP_SPANS[map_zoom]
	var per_m: float = box.size.x / span
	# The whole picture of the map, drawn at this scale and slid so the right spot is in the middle.
	var full: Vector2 = Vector2(main.map.half_len * 2.0, PushMap.HALF_WIDTH * 2.0) * per_m
	var centre_uv: Vector2 = main.map_uv(me)
	if map_big:
		centre_uv = (Vector2(0.5, 0.5) if map_zoom == 0 else centre_uv) + _map_pan / Vector2(main.map.half_len * 2.0, PushMap.HALF_WIDTH * 2.0)
	var origin: Vector2 = box.size * 0.5 - centre_uv * full
	box.draw_rect(Rect2(Vector2.ZERO, box.size), Color(0.05, 0.06, 0.05, 0.85))
	box.draw_texture_rect(tex, Rect2(origin, full), false, Color(1, 1, 1, 0.92))
	var spot := func(world: Vector3) -> Vector2: return origin + main.map_uv(world) * full
	# The objective, then every vehicle that may be shown.
	var goal: Vector2 = spot.call(main.objective_pos())
	box.draw_colored_polygon(PackedVector2Array([goal + Vector2(0, -7), goal + Vector2(7, 0), goal + Vector2(0, 7), goal + Vector2(-7, 0)]), Color(1, 1, 1, 0.95))
	var my_team := int(main.player_slot.get("team", 0))
	for t in main.tanks:
		if not (main.spectating or t.team == my_team or t.spotted):
			continue
		var p: Vector2 = spot.call(t.global_position)
		var mine: bool = pc.has_tank() and t == pc.tank
		# An arrowhead pointing the way the hull faces. (On the map, up is the world's -X and right its +Z.)
		var nose := Vector2(-cos(t.heading), sin(t.heading))
		var wing := Vector2(-nose.y, nose.x)
		var r := 8.0 if mine else 6.0
		box.draw_colored_polygon(PackedVector2Array([p + nose * r * 1.4, p - nose * r * 0.7 + wing * r * 0.8, p - nose * r * 0.7 - wing * r * 0.8]), Color.WHITE if mine else main.TEAM_COLORS[t.team])
		if map_big:
			box.draw_string(font, p + Vector2(10, 4), t.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))
	if pc.has_man() or pc.has_air():
		# You, on foot or flying: a white arrowhead pointing the way you face.
		var here: Vector2 = spot.call(me)
		var face := Vector2(-cos(pc.yaw), sin(pc.yaw))
		var flank := Vector2(-face.y, face.x)
		box.draw_colored_polygon(PackedVector2Array([here + face * 11.0, here - face * 6.0 + flank * 6.0, here - face * 6.0 - flank * 6.0]), Color.WHITE)
	for i in main.dom.size():
		var where: Vector2 = spot.call(main.dom[i]["pos"])
		box.draw_arc(where, maxf(main.DOM_RADIUS * per_m, 9.0), 0, TAU, 28, main.dom_colour(i), 2.5)
		box.draw_string(font, where + Vector2(-5, 6), "ABC"[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, main.dom_colour(i))
	for p in main.pings:
		if p["team"] == my_team or main.spectating:
			var at: Vector2 = spot.call(main.ping_pos(p))
			box.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -7), at + Vector2(7, 0), at + Vector2(0, 7), at + Vector2(-7, 0)]), p["colour"])
	box.draw_rect(Rect2(Vector2.ONE, box.size - Vector2(2, 2)), Color(1, 0.86, 0.45, 0.8), false, 2.0)
	var keys := "%s map   %s %s zoom" % [Settings.binding_text("map"), Settings.binding_text("map_out"), Settings.binding_text("map_in")]
	if map_big:
		keys += "   arrow keys move"
	box.draw_string(font, Vector2(8, box.size.y - 8), keys, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))


func _process(_delta: float) -> void:
	_map_tick(_delta)
	for m in main.hurt_marks.duplicate():
		m["t"] -= _delta
		if m["t"] <= 0.0:
			main.hurt_marks.erase(m)
	queue_redraw()


func _txt(pos: Vector2, s: String, px: int = 16, col: Color = Color.WHITE) -> void:
	draw_string(font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.7))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _ctxt(pos: Vector2, s: String, px: int = 16, col: Color = Color.WHITE) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_txt(pos - Vector2(w * 0.5, 0), s, px, col)


func _draw() -> void:
	if main.state == "menu":
		return
	var sz := get_viewport_rect().size
	var pc: PlayerCtrl = main.player_ctrl
	if not main.podium_shown:
		_draw_push(sz)
		_draw_feed(sz)
	if pc.phase == "killcam":
		if pc.kill_fade > 0.0:
			draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, pc.kill_fade))
		if pc._phase_t >= pc.KILL_LINGER:
			draw_rect(Rect2(0, sz.y - 150, sz.x, 84), Color(0, 0, 0, 0.65))
			_ctxt(Vector2(sz.x * 0.5, sz.y - 116), "KILL CAM", 16, Color(1, 0.5, 0.4))
			_ctxt(Vector2(sz.x * 0.5, sz.y - 86), pc.kill_text, 24)
	elif pc.has_air():
		if pc.air.dying or pc.air.wrecked:
			_ctxt(Vector2(sz.x * 0.5, sz.y - 96), "SHOT DOWN" if pc.air.dying else "", 26, Color(1, 0.45, 0.35))
		elif pc.intro_t < 0.0 or pc.intro_t >= pc.INTRO_HANDOVER:
			_draw_who(pc, pc.air.team, pc.air.global_position)
			_draw_air(sz, pc)
			_draw_sky(sz, pc, pc.air.team, false, null)
	elif pc.has_man():
		_draw_who(pc, pc.man.team, pc.man.global_position)
		_draw_man(sz, pc)
	elif pc.has_tank():
		_draw_emotes(pc)
		_draw_markers(pc)
		_draw_men_marks(pc, pc.tank.team, pc.tank.global_position)
		_draw_pings(pc)
		if pc.phase == "play":
			_draw_tank(sz, pc)
			_draw_sky(sz, pc, pc.tank.team, pc.tank.def.has("aa"), pc.tank)
			if pc.emote_open:
				_draw_emote_bar(sz)
			if pc.ping_open and pc.ping_held >= pc.PING_TAP:
				_draw_ping_wheel(sz, pc)
	if (pc.has_tank() or pc.has_man() or pc.has_air()) and pc.phase != "killcam":
		_draw_hurt(sz, pc)
	if (pc.has_tank() or pc.has_man() or pc.has_air() or main.spectating) and not main.match_over and pc.phase != "killcam" and main.mode["kind"] != "range":
		_draw_compass(sz, pc)
	if main.spectating and not main.match_over:
		draw_rect(Rect2(sz.x * 0.5 - 430, sz.y - 96, 860, 62), Color(0, 0, 0, 0.5))
		_ctxt(Vector2(sz.x * 0.5, sz.y - 70), "SPECTATING   -   " + pc.spec_name(), 20, Color(1.0, 0.85, 0.45))
		_ctxt(Vector2(sz.x * 0.5, sz.y - 46), "%s free camera (W A S D, Q E, Shift)     %s gunner's view     %s circle     %s outlines     click / right click: next / previous vehicle" % [Settings.binding_text("spec_free"), Settings.binding_text("spec_gunner"), Settings.binding_text("spec_orbit"), Settings.binding_text("spec_outline")], 13, Color(0.9, 0.9, 0.9))
	if main.msg_t > 0.0 and not main.match_over:
		_ctxt(Vector2(sz.x * 0.5, sz.y * 0.5 + 70), main.msg, 22, Color(1, 0.9, 0.5))
	_draw_popups(sz)
	if main.prep_t > 0.0:
		var n := int(ceil(main.prep_t))
		draw_rect(Rect2(sz.x * 0.5 - 230, 96, 460, 96), Color(0, 0, 0, 0.5))
		_ctxt(Vector2(sz.x * 0.5, 126), "BATTLE BEGINS IN", 16, Color(0.85, 0.85, 0.85))
		_ctxt(Vector2(sz.x * 0.5, 176), str(n), 50, Color(1, 0.4, 0.3) if n <= 3 else Color(1, 0.9, 0.5))
	# Outside the battle: the same black band as the end of a match, and the seconds left.
	if main.oob_left >= 0.0 and not main.match_over and pc.phase != "killcam":
		draw_rect(Rect2(0, sz.y * 0.36, sz.x, 130), Color(0, 0, 0, 0.6))
		_ctxt(Vector2(sz.x * 0.5, sz.y * 0.36 + 60), "RETURN TO COMBAT", 46, Color(1.0, 0.32, 0.25))
		_ctxt(Vector2(sz.x * 0.5, sz.y * 0.36 + 108), "%d" % int(ceil(main.oob_left)), 34, Color(1, 0.9, 0.5))
	if main.match_over and not main.podium_shown:
		draw_rect(Rect2(0, sz.y * 0.36, sz.x, 130), Color(0, 0, 0, 0.6))
		var won: bool = main.winner == int(main.player_slot.get("team", 0))
		var t := "Draw" if main.winner < 0 else "%s team wins" % main.TEAM_NAMES[main.winner]
		_ctxt(Vector2(sz.x * 0.5, sz.y * 0.36 + 60), t, 46, main.TEAM_COLORS[main.winner] if main.winner >= 0 else Color.WHITE)
		_ctxt(Vector2(sz.x * 0.5, sz.y * 0.36 + 100), "Draw" if main.winner < 0 else ("Victory!" if won else "Defeat"), 20, Color(1, 0.9, 0.5))
		_ctxt(Vector2(sz.x * 0.5, sz.y * 0.36 + 150), main.reward_text, 20, Color(0.6, 0.9, 1.0))
	if pc.phase == "redeploy":
		# Black, with the lines, drifting band and flicker of the camcorder picture, and the word in red.
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.01, 0.01, 0.012))
		for y in range(0, int(sz.y), 4):
			draw_line(Vector2(0, y), Vector2(sz.x, y), Color(1, 1, 1, 0.035), 1.0)
		var roll := fposmod(main.elapsed * 150.0, sz.y + 120.0) - 60.0
		draw_rect(Rect2(0, roll, sz.x, 46.0), Color(1, 1, 1, 0.045))
		draw_rect(Rect2(0, roll + 18.0, sz.x, 3.0), Color(1, 1, 1, 0.09))
		for k in 5:
			var ty := fposmod(sin(float(k) * 12.7 + floor(main.elapsed * 9.0)) * 43758.5, 1.0) * sz.y
			draw_rect(Rect2(fposmod(float(k) * 377.0 + main.elapsed * 900.0, sz.x), ty, 120.0, 2.0), Color(1, 1, 1, 0.12))
		var shake := Vector2(sin(main.elapsed * 47.0) * 1.5, 0)
		_ctxt(sz * 0.5 + shake + Vector2(3, 0), "REDEPLOYING", 54, Color(0.2, 0.9, 1.0, 0.25))
		_ctxt(sz * 0.5 + shake, "REDEPLOYING", 54, Color(1.0, 0.16, 0.12))
		_ctxt(sz * 0.5 + Vector2(0, 46), "%d" % int(ceil(pc.REDEPLOY_SECONDS - pc._phase_t)), 22, Color(1.0, 0.16, 0.12, 0.8))
		_txt(Vector2(60, 70), "REC", 22, Color(1, 1, 1, 0.8))
		if int(main.elapsed * 2.0) % 2 == 0:
			draw_circle(Vector2(46, 62), 6.0, Color(1.0, 0.1, 0.1))
	if main.fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, main.fade))
	if main.podium_shown and main.fade < 0.6:
		_ctxt(Vector2(sz.x * 0.5, 70), "TOP PLAYERS", 40, Color(1.0, 0.85, 0.45))
		_ctxt(Vector2(sz.x * 0.5, sz.y - 30), "Enter: play again      Esc: main menu      Tab: scoreboard", 17, Color(0.9, 0.9, 0.9))
	if Input.is_physical_key_pressed(KEY_TAB) and main.prep_t <= 0.0:
		_draw_scoreboard(sz)


# You have been hit: a red arc round the middle of the screen on the side it came from
# (top of the ring = ahead of where you are looking, bottom = behind), fading over a couple
# of seconds, and a red tinge at the edges of the screen.
func _draw_hurt(sz: Vector2, pc: PlayerCtrl) -> void:
	var c := sz * 0.5
	var r := minf(sz.x, sz.y) * 0.24
	var inv := pc.cam.global_transform.basis.inverse()
	var worst := 0.0
	for m in main.hurt_marks:
		var k := clampf(float(m["t"]) / main.HURT_MARK_SECONDS, 0.0, 1.0)
		worst = maxf(worst, k)
		if not m["known"]:
			continue
		var to: Vector3 = inv * (m["at"] - pc.cam.global_position)
		var ang := atan2(to.x, -to.z) - PI * 0.5  # (on screen, straight up is a quarter turn back from the x axis)
		var col := Color(1.0, 0.12, 0.08, 0.85 * k)
		draw_arc(c, r, ang - 0.3, ang + 0.3, 14, col, 9.0, true)
		draw_arc(c, r + 9.0, ang - 0.12, ang + 0.12, 8, col, 7.0, true)
		var tip := c + Vector2.from_angle(ang) * (r + 26.0)
		var side := Vector2.from_angle(ang + PI * 0.5) * 11.0
		draw_colored_polygon(PackedVector2Array([tip, c + Vector2.from_angle(ang) * (r + 12.0) + side, c + Vector2.from_angle(ang) * (r + 12.0) - side]), col)
	if worst > 0.0:
		var edge := Color(0.8, 0.0, 0.0, 0.22 * worst)
		var w := sz.y * 0.07
		draw_rect(Rect2(0, 0, sz.x, w), edge)
		draw_rect(Rect2(0, sz.y - w, sz.x, w), edge)
		draw_rect(Rect2(0, w, w, sz.y - w * 2.0), edge)
		draw_rect(Rect2(sz.x - w, w, w, sz.y - w * 2.0), edge)


# The player's latest score lines, stacked beside the crosshair and fading out.
func _draw_popups(sz: Vector2) -> void:
	var y := sz.y * 0.5 - 20.0
	for p in main.popups:
		var c: Color = p["colour"]
		c.a = clampf(float(p["t"]), 0.0, 1.0)
		_txt(Vector2(sz.x * 0.5 + 150.0, y), p["text"], 20, c)
		y += 28.0


# Everyone's kills, deaths, assists and points, best first, with the two teams side by side.
func _draw_scoreboard(sz: Vector2) -> void:
	var w := 560.0
	var rows: Array = main.ranking()
	for team in 2:
		var x := sz.x * 0.5 + (-w - 10.0 if team == 0 else 10.0)
		var y := sz.y * 0.5 - 170.0
		draw_rect(Rect2(x, y, w, 300), Color(0, 0, 0, 0.78))
		draw_rect(Rect2(x, y, w, 40), Color(main.TEAM_COLORS[team], 0.55))
		_txt(Vector2(x + 14, y + 28), "%s team" % main.TEAM_NAMES[team], 20)
		var cols := [300.0, 370.0, 430.0, 490.0]
		var heads := ["K", "D", "A", "Points"]
		for i in 4:
			_txt(Vector2(x + cols[i], y + 28), heads[i], 15, Color(0.9, 0.9, 0.9))
		var ry := y + 70.0
		for s in rows:
			if s["team"] != team:
				continue
			var mine: bool = s["is_player"]
			var col := Color(1.0, 0.9, 0.5) if mine else Color.WHITE
			var vehicle := String(GameData.vehicles[s["vehicle_id"]]["name"]) if GameData.vehicles.has(s["vehicle_id"]) else "-"
			_txt(Vector2(x + 14, ry), s["name"], 17, col)
			_txt(Vector2(x + 120, ry), vehicle, 14, Color(0.75, 0.75, 0.75))
			var vals := [s["kills"], s["deaths"], s["assists"], s["points"]]
			for i in 4:
				_txt(Vector2(x + cols[i], ry), str(vals[i]), 17, col)
			ry += 40.0


func _draw_push(sz: Vector2) -> void:
	if main.mode["kind"] == "range":
		# The test range: what the keys do, and what is being fired at you right now.
		var mid := sz.x * 0.5
		draw_rect(Rect2(mid - 430, 10, 860, 62), Color(0, 0, 0, 0.5))
		_ctxt(Vector2(mid, 34), "SHOOTING RANGE", 20, Color(1.0, 0.85, 0.45))
		# (The sound board is a development tool: it is only there when the game is started with --dev.)
		_ctxt(Vector2(mid, 58), ("F1 sound board     " if main.args.has("--dev") else "") + "F2 change vehicle     F3 infantry squads     targets up the road     firing lane behind you", 14, Color(0.9, 0.9, 0.9))
		if main.range_note != "":
			draw_rect(Rect2(mid - 430, 80, 860, 40), Color(0.5, 0.05, 0.05, 0.6))
			_ctxt(Vector2(mid, 107), "INCOMING:  " + main.range_note, 18)
		elif main.player_ctrl.has_tank() and main.in_firing_lane(main.player_ctrl.tank.global_position):
			_ctxt(Vector2(mid, 107), "In the firing lane - guns laying on you...", 16, Color(1, 0.7, 0.5))
		return
	# The score, kept small, under the minimap: the clock, then a line for each team. In
	# Push each team's line is a bar filling as its barricade is pushed; otherwise its kills.
	var x := 16.0
	var y := 274.0
	var w := 250.0
	draw_rect(Rect2(x, y, w, 86), Color(0, 0, 0, 0.5))
	var secs := int(maxf(main.time_left, 0.0))
	var note := "first to %d kills" % int(main.mode["kill_target"])
	if main.mode["kind"] == "push":
		var p: PushMode = main.push
		note = "contested" if p.contested else ("%s pushing" % main.TEAM_NAMES[p.controller] if p.controller >= 0 else "robot waiting")
	_txt(Vector2(x + 10, y + 22), "%d:%02d" % [secs / 60, secs % 60], 18)
	if main.mode["kind"] == "domination":
		# The three points: a box each in its holder's colour, filling as it is being taken.
		for i in main.dom.size():
			var p: Dictionary = main.dom[i]
			var box := Rect2(x + 78 + i * 56.0, y + 6, 48, 22)
			draw_rect(box, Color(0.12, 0.12, 0.12))
			draw_rect(box, main.dom_colour(i), false, 2.0)
			if p["taking"] >= 0:
				draw_rect(Rect2(box.position, Vector2(box.size.x * clampf(p["progress"], 0.0, 1.0), box.size.y)), Color(main.TEAM_COLORS[p["taking"]], 0.7))
			_ctxt(box.get_center() + Vector2(0, 6), "ABC"[i], 16, main.dom_colour(i))
	else:
		_txt(Vector2(x + 70, y + 21), note, 13, Color(0.85, 0.85, 0.85))
	for team in 2:
		var ty := y + 46.0 + team * 20.0
		_txt(Vector2(x + 10, ty), main.TEAM_NAMES[team].to_upper(), 13, main.TEAM_COLORS[team])
		if main.mode["kind"] == "push":
			var done: float = clampf(main.push.progress[team] / main.half_len, 0.0, 1.0)
			draw_rect(Rect2(x + 56, ty - 10, 136, 10), Color(0.15, 0.15, 0.15))
			draw_rect(Rect2(x + 56, ty - 10, 136.0 * done, 10), main.TEAM_COLORS[team])
			_txt(Vector2(x + 198, ty), "%d m" % int(main.push.progress[team]), 13)
		elif main.mode["kind"] == "domination":
			var goal := float(main.mode["kill_target"])
			draw_rect(Rect2(x + 56, ty - 10, 136, 10), Color(0.15, 0.15, 0.15))
			draw_rect(Rect2(x + 56, ty - 10, 136.0 * clampf(main.dom_score[team] / goal, 0.0, 1.0), 10), main.TEAM_COLORS[team])
			_txt(Vector2(x + 198, ty), str(int(main.dom_score[team])), 13)
		else:
			_txt(Vector2(x + 56, ty + 1), str(main.team_kills[team]), 17)

func _draw_feed(sz: Vector2) -> void:
	var y := 30.0
	for line in main.feed:
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_txt(Vector2(sz.x - w - 16, y), line, 14)
		y += 20.0


# Name tags. Friends always show; enemies only while someone on your team can see them.
func _draw_markers(pc: PlayerCtrl) -> void:
	var cam := pc.cam
	for t in main.tanks:
		if t == pc.tank:
			continue
		var enemy: bool = t.team != pc.tank.team
		if enemy and not t.spotted:
			continue
		var wp: Vector3 = t.global_position + Vector3(0, 4.5, 0)
		if cam.is_position_behind(wp):
			continue
		var d: float = pc.tank.global_position.distance_to(t.global_position)
		var sp := cam.unproject_position(wp)
		var col: Color = main.TEAM_COLORS[t.team]
		draw_rect(Rect2(sp.x - 20, sp.y, 40, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(sp.x - 20, sp.y, 40.0 * clampf(t.hp / t.max_hp, 0, 1), 4), col)
		_ctxt(sp + Vector2(0, -5), "%s  %dm" % [t.def["name"], int(d)], 12, col)
		if enemy and t.revealed_t > 0.0:
			draw_arc(sp + Vector2(0, 2), 30.0, 0, TAU, 20, Color(0.5, 0.85, 1.0, 0.8), 1.5)


# A small chevron in the team's colour over each friendly soldier within 150 m.
func _draw_men_marks(pc: PlayerCtrl, team: int, me: Vector3) -> void:
	var on_screen := Rect2(Vector2.ZERO, get_viewport_rect().size)
	var col: Color = main.TEAM_COLORS[team].lightened(0.25)
	for s in main.soldiers:
		if s.team != team or s.state != "up" or s == main.player_man or s.global_position.distance_to(me) > 150.0:
			continue
		var wp: Vector3 = s.global_position + Vector3(0, 2.25, 0)
		if pc.cam.is_position_behind(wp):
			continue
		var sp := pc.cam.unproject_position(wp)
		if on_screen.has_point(sp):
			draw_polyline(PackedVector2Array([sp + Vector2(-5, -5), sp + Vector2(0, 0), sp + Vector2(5, -5)]), col, 2.0)


# Who is who, for a pilot or a man on foot. Every friendly vehicle and aircraft has a small
# arrow over it in the team's colour; one with a person in it has their name too. Enemy
# vehicles are marked only while a friendly ground unit has them spotted: aircraft and
# infantry do not spot for themselves, they are shown what the tanks see.
func _draw_who(pc: PlayerCtrl, team: int, me: Vector3) -> void:
	var cam := pc.cam
	var on_screen := Rect2(Vector2(-100, -100), get_viewport_rect().size + Vector2(200, 200))
	for t in main.tanks:
		var enemy: bool = t.team != team
		if enemy and not t.spotted:
			continue
		var wp: Vector3 = t.global_position + Vector3(0, 4.8, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		if not on_screen.has_point(sp):
			continue
		var col: Color = main.TEAM_COLORS[t.team].lightened(0.2)
		var away := int(me.distance_to(t.global_position))
		draw_colored_polygon(PackedVector2Array([sp + Vector2(-7, -8), sp + Vector2(7, -8), sp + Vector2(0, 3)]), col)
		var human: bool = t.slot.get("is_player", false) or t.slot.get("human", false) or int(t.slot.get("peer", 0)) > 0
		if enemy:
			_ctxt(sp + Vector2(0, -13), "%s  %dm" % [t.def["name"], away], 12, col)
		elif human:
			_ctxt(sp + Vector2(0, -13), "%s  %dm" % [t.display_name, away], 13, col)
	_draw_men_marks(pc, team, me)
	for a in main.aircraft:
		if not is_instance_valid(a) or a.team != team or a == main.player_air or a.wrecked:
			continue
		var wp: Vector3 = a.global_position + Vector3(0, 5.0, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		if not on_screen.has_point(sp):
			continue
		var col: Color = main.TEAM_COLORS[a.team].lightened(0.2)
		draw_colored_polygon(PackedVector2Array([sp + Vector2(-7, -8), sp + Vector2(7, -8), sp + Vector2(0, 3)]), col)
		if not a.owner_slot.is_empty():
			_ctxt(sp + Vector2(0, -13), String(a.owner_slot.get("name", "")), 13, col)


func _draw_pings(pc: PlayerCtrl) -> void:
	for p in main.pings:
		if p["team"] != pc.tank.team:
			continue
		var wp: Vector3 = main.ping_pos(p) + Vector3(0, 6.0, 0)
		if pc.cam.is_position_behind(wp):
			continue
		var sp := pc.cam.unproject_position(wp)
		var col: Color = p["colour"]
		if p["order"] == "mark":
			draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -9), sp + Vector2(9, 0), sp + Vector2(0, 9), sp + Vector2(-9, 0)]), col)
			_ctxt(sp + Vector2(0, -16), "%dm" % int(pc.tank.global_position.distance_to(wp)), 12, col)
			continue
		draw_colored_polygon(PackedVector2Array([sp + Vector2(0, 14), sp + Vector2(-10, -4), sp + Vector2(10, -4)]), col)
		draw_arc(sp, 18.0, 0, TAU, 20, col, 2.0)
		_ctxt(sp + Vector2(0, -26), "%s  %dm  (%ds)" % [p["label"], int(pc.tank.global_position.distance_to(wp)), int(p["t"])], 13, col)


func _draw_ping_wheel(sz: Vector2, pc: PlayerCtrl) -> void:
	var c := sz * 0.5
	var ids: Array = GameData.ping_order
	var n := ids.size()
	var choice := pc.ping_choice()
	draw_circle(c, 150.0, Color(0, 0, 0, 0.55))
	draw_arc(c, 150.0, 0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)
	draw_circle(c, 36.0, Color(0, 0, 0, 0.5))
	_ctxt(c + Vector2(0, 5), "cancel", 12, Color(0.75, 0.75, 0.75))
	for i in n:
		var a := float(i) / n * TAU
		var dir := Vector2(sin(a), -cos(a))
		var p: Dictionary = GameData.pings[ids[i]]
		var col := Color(String(p["colour"]))
		var edge := a + PI / n
		draw_line(c + Vector2(sin(edge), -cos(edge)) * 36.0, c + Vector2(sin(edge), -cos(edge)) * 150.0, Color(1, 1, 1, 0.25), 1.0)
		if i == choice:
			draw_circle(c + dir * 96.0, 44.0, Color(col.r, col.g, col.b, 0.35))
		_ctxt(c + dir * 96.0 + Vector2(0, 5), p["label"], 14 if i == choice else 13, col if i == choice else Color(0.9, 0.9, 0.9))
	draw_circle(c + pc.ping_vec, 5.0, Color.WHITE)


func _draw_tank(sz: Vector2, pc: PlayerCtrl) -> void:
	var t := pc.tank
	var c := sz * 0.5
	var arty: bool = t.def["class"] == "artillery"
	if pc.freelook:
		_ctxt(Vector2(c.x, c.y - 60), "FREE LOOK", 16, Color(1, 0.9, 0.5))
	if pc.drone:
		_draw_drone(sz, pc)
	elif pc.sniper:
		_draw_scope(sz, pc)
		_draw_reload_ring(c, 24.0, t)
	else:
		_draw_reload_ring(c, 16.0, t)
		draw_arc(c, 9.0, 0, TAU, 24, Color(1, 1, 1, 0.8), 1.5)
		draw_circle(c, 1.5, Color.WHITE)
		var range_text := "Range ---" if pc.aim_dist < 0.0 else "Range %d m" % int(pc.aim_dist)
		var zero_text := "   Zero %d m" % int(t.zero_range) if t.zero_range > 0.0 else "   Zero off"
		_txt(c + Vector2(22, 26), range_text + zero_text, 14, Color(1, 0.9, 0.5))
	# Artillery: a ring where the shell will come down.
	if pc.impact != null and not pc.cam.is_position_behind(pc.impact):
		var ip := pc.cam.unproject_position(pc.impact)
		var far: float = t.muzzle.global_position.distance_to(pc.impact)
		draw_arc(ip, 14.0, 0, TAU, 24, Color(1, 0.75, 0.2), 2.0)
		draw_line(ip + Vector2(-20, 0), ip + Vector2(20, 0), Color(1, 0.75, 0.2), 1.5)
		draw_line(ip + Vector2(0, -20), ip + Vector2(0, 20), Color(1, 0.75, 0.2), 1.5)
		_txt(ip + Vector2(22, -8), "lands %d m" % int(far), 15, Color(1, 0.85, 0.4))
	# Where the gun is really pointing (not for artillery, whose gun points at the sky).
	var from := t.muzzle.global_position
	var to := from - t.muzzle.global_transform.basis.z * (pc.aim_dist if pc.aim_dist > 50.0 else 400.0)
	if not arty and not pc.cam.is_position_behind(to):
		var gp := pc.cam.unproject_position(to)
		var gun_ready: bool = t.reload_left <= 0.0 and t.modules["gun"] <= 0.0
		draw_arc(gp, 5.0, 0, TAU, 16, Color(0.3, 1, 0.4) if gun_ready else Color(1, 0.4, 0.3), 2.0)

	# The vehicle's own panel, bottom right: what it is, its health, the state of the things
	# that can be knocked out, which shell is loaded, and its ability.
	var x := sz.x - 346.0
	var y := sz.y - 196.0
	draw_rect(Rect2(x - 10, y - 26, 340, 206), Color(0, 0, 0, 0.5))
	_txt(Vector2(x, y), "%s   [%s]" % [t.def["name"], t.role["name"]], 18)
	draw_rect(Rect2(x, y + 10, 320, 14), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(x, y + 10, 320.0 * clampf(t.hp / t.max_hp, 0, 1), 14), Color(0.3, 0.85, 0.4))
	_txt(Vector2(x + 4, y + 22), "%d / %d" % [int(t.hp), int(t.max_hp)], 12)
	var good := Color(0.7, 0.9, 0.7)
	var bad := Color(1, 0.35, 0.3)
	var n := 0
	for k in ["ammo", "engine", "tracks", "gun"]:
		var at := Vector2(x + (n % 2) * 165.0, y + 46.0 + (n / 2) * 20.0)
		if k == "ammo":
			# Burning ammunition cannot be put out: when the count runs down, the vehicle blows up.
			var burning: bool = t.ammo_fire > 0.0
			_txt(at, "Ammo  BURNING %ds" % int(ceil(t.ammo_fire)) if burning else "Ammo  ok", 14, bad if burning else good)
		else:
			var broken: bool = t.modules[k] > 0.0
			_txt(at, "%s  %s" % [k.capitalize(), "out %ds" % int(ceil(t.modules[k])) if broken else "ok"], 14, bad if broken else good)
		n += 1
	var ids: Array = t.def["shells"]
	for i in ids.size():
		var sel: bool = i == t.shell_index % ids.size()
		_txt(Vector2(x, y + 94.0 + i * 19.0), "%s[%d] %s" % ["> " if sel else "   ", i + 1, GameData.shells[ids[i]]["name"]], 14, Color.WHITE if sel else Color(0.6, 0.6, 0.6))
	_txt(Vector2(x + 200, y + 94), "%d km/h" % int(absf(t.speed) * 3.6), 14)
	if t.spotted:
		_txt(Vector2(x + 200, y + 113), "SPOTTED", 14, Color(1, 0.5, 0.4))
	var ab := "[%s] %s" % [Settings.binding_text("ability"), t.ability["name"]]
	if t.armed_t > 0.0:
		ab += "  LOADED %ds" % int(ceil(t.armed_t))
	elif t.ability_left > 0.0:
		ab += "  ACTIVE"
	elif t.ability_cd > 0.0:
		ab += "  %ds" % int(ceil(t.ability_cd))
	else:
		ab += "  ready"
	_txt(Vector2(x, y + 164), ab, 14, Color(1, 0.9, 0.5))

	# Reload, bottom centre, and the keys along the bottom left.
	var bx := sz.x * 0.5 - 150.0
	var by := sz.y - 40.0
	var frac := 1.0 - clampf(t.reload_left / maxf(t.reload_total, 0.01), 0, 1)
	draw_rect(Rect2(bx, by, 300, 10), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(bx, by, 300.0 * frac, 10), Color(0.3, 1, 0.4) if frac >= 1.0 else Color(1, 0.75, 0.3))
	var hint := "%s fire   %s MG   %s sight   %s range   %s free look   %s ping   %s emotes   Tab scores" % [
		Settings.binding_text("fire"), Settings.binding_text("machine_gun"), Settings.binding_text("sight"),
		Settings.binding_text("rangefind"), Settings.binding_text("freelook"), Settings.binding_text("ping"), Settings.binding_text("emote")]
	_txt(Vector2(16, sz.y - 14), hint, 12, Color(0.8, 0.8, 0.8))

# Indirect fire, seen from above: the shell's path from the gun to where it will land, how
# long it will be in the air, and whether the gun has been laid on the point yet.
var _drone_hp := 0.0
var _drone_hit_at := -99.0
var _drone_beep := 0.0

# Looking down from the drone you cannot see what is happening round your own vehicle, so
# you are told: when it is being hit, and when an enemy is close (a vehicle within 50 m, a
# soldier within 100 m).
func _drone_warning(sz: Vector2, t: Tank) -> void:
	if t.hp < _drone_hp:
		_drone_hit_at = main.elapsed
	_drone_hp = t.hp
	var lines: Array = []
	if main.elapsed - _drone_hit_at < 3.5:
		lines.append("TAKING FIRE")
	var near := 50.0
	var who := ""
	for v in main.tanks:
		if v.team != t.team and v.global_position.distance_to(t.global_position) < near:
			near = v.global_position.distance_to(t.global_position)
			who = "ENEMY VEHICLE  %d m" % int(near)
	if who == "":
		near = 100.0
		for s in main.soldiers:
			if s.team != t.team and s.state == "up" and s.global_position.distance_to(t.global_position) < near:
				near = s.global_position.distance_to(t.global_position)
				who = "ENEMY INFANTRY  %d m" % int(near)
	if who != "":
		lines.append(who)
	if lines.is_empty():
		return
	_drone_beep -= get_process_delta_time()
	if _drone_beep <= 0.0:
		_drone_beep = 0.8
		Sfx.play_ui("tick", -4.0, 1.4)
	if int(main.elapsed * 4.0) % 2 == 0:
		draw_rect(Rect2(sz.x * 0.5 - 260.0, sz.y * 0.16, 520.0, 30.0 + lines.size() * 28.0), Color(0.5, 0.0, 0.0, 0.55))
	for i in lines.size():
		_ctxt(Vector2(sz.x * 0.5, sz.y * 0.16 + 34.0 + i * 28.0), "WARNING  -  " + String(lines[i]), 22, Color(1.0, 0.85, 0.8))


func _draw_drone(sz: Vector2, pc: PlayerCtrl) -> void:
	var t := pc.tank
	_drone_warning(sz, t)
	var path: Dictionary = t.predict_path()
	var pts: Array = path["points"]
	var gold := Color(1, 0.8, 0.3)
	var line := PackedVector2Array()
	for p in pts:
		if not pc.cam.is_position_behind(p):
			line.append(pc.cam.unproject_position(p))
	if line.size() >= 2:
		draw_polyline(line, Color(1, 0.8, 0.3, 0.85), 2.5)
	var want := pc.cam.unproject_position(pc.drone_point)
	draw_arc(want, 22.0, 0, TAU, 32, Color(1, 1, 1, 0.9), 1.5)
	draw_line(want + Vector2(-30, 0), want + Vector2(30, 0), Color(1, 1, 1, 0.9), 1.0)
	draw_line(want + Vector2(0, -30), want + Vector2(0, 30), Color(1, 1, 1, 0.9), 1.0)
	var laid: bool = t.gun_error() < 0.02
	var away: float = t.global_position.distance_to(pc.drone_point)
	var flight: float = path["time"]
	draw_rect(Rect2(sz.x * 0.5 - 330, 70, 660, 74), Color(0, 0, 0, 0.55))
	_ctxt(Vector2(sz.x * 0.5, 96), "INDIRECT FIRE   -   %s arc   -   range %d m   -   flight %s" % ["HIGH" if t.high_arc else "low", int(away), "%.1f s" % flight if flight > 0.0 else "--"], 18, gold)
	_ctxt(Vector2(sz.x * 0.5, 120), "gun laid - fire when ready" if laid else "laying the gun...", 15, Color(0.4, 1, 0.5) if laid else Color(1, 0.6, 0.4))
	if pc.shell_eta > 0.0:
		draw_rect(Rect2(sz.x * 0.5 - 150, 152, 300, 40), Color(0.5, 0.05, 0.05, 0.6))
		_ctxt(Vector2(sz.x * 0.5, 180), "SHELL IMPACT IN  %.1f s" % pc.shell_eta, 20)
	_ctxt(Vector2(sz.x * 0.5, 138), "dug in level: cannot move     mouse moves the aiming point     %s swaps low and high arc" % Settings.binding_text("rangefind"), 12, Color(0.85, 0.85, 0.85))
	_draw_reload_ring(want, 32.0, t)


# Enemy aircraft, marked on the screen. They are marked for everyone on a team whose radar
# is sweeping (the anti-aircraft vehicles' Sky Scan), and always for an anti-aircraft
# vehicle that has one in plain view. The gun vehicle is also shown where to aim: a diamond
# out ahead of each aircraft, at the spot its shells will reach as the aircraft does. The
# missile vehicle is shown what its seeker is on, and when it has locked.
func _draw_sky(_sz: Vector2, pc: PlayerCtrl, team: int, aa: bool, t) -> void:
	var scanning: bool = main.sky_scan[team] > main.elapsed
	# An anti-aircraft vehicle with its radar on sees every aircraft there is, friend and foe,
	# each framed in its own side's colour. Radar off, the frames go.
	var radar: bool = aa and t != null and t.radar_on
	if t == null:
		# Flying: enemy radars that are switched on show as a green ring that pulses outwards.
		for v in main.tanks:
			if v.team != team and v.def.has("aa") and v.radar_on and not pc.cam.is_position_behind(v.global_position):
				var beat := fposmod(main.elapsed + float(v.get_instance_id() % 5) * 0.6, 3.0) / 3.0
				var spot := pc.cam.unproject_position(v.global_position + Vector3(0, 2.5, 0))
				draw_arc(spot, 6.0 + beat * 34.0, 0, TAU, 28, Color(0.35, 1.0, 0.45, 1.0 - beat), 2.0)
				draw_circle(spot, 2.5, Color(0.35, 1.0, 0.45, 0.9))
	for a in main.aircraft:
		if not is_instance_valid(a) or a.dying or a.wrecked or a == main.player_air:
			continue
		var foe: bool = a.team != team
		if not radar and not (scanning and foe):
			continue
		var at: Vector3 = a.global_position + Vector3(0, 1.5, 0)
		if pc.cam.is_position_behind(at):
			continue
		var red: Color = main.TEAM_COLORS[a.team].lightened(0.15)
		var p := pc.cam.unproject_position(at)
		var away: float = pc.cam.global_position.distance_to(at)
		# Corner brackets round it, and how far off it is.
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := p + Vector2(sx, sy) * 16.0
				draw_line(corner, corner - Vector2(sx * 8.0, 0), red, 2.0)
				draw_line(corner, corner - Vector2(0, sy * 8.0), red, 2.0)
		_txt(p + Vector2(22, 5), "%s  %d m" % [a.def["name"], int(away)], 12, red)
		if t == null or not foe:
			continue
		if t.def.get("aa", "") == "gun" and away < 2200.0:
			# Lead: where it will be when a shell fired now gets there.
			var v: float = float(t.current_shell()["velocity"])
			var meet: Vector3 = at
			for k in 3:
				meet = at + a.motion() * (t.muzzle.global_position.distance_to(meet) / v)
			if not pc.cam.is_position_behind(meet):
				var m := pc.cam.unproject_position(meet)
				var amber := Color(1.0, 0.85, 0.3)
				draw_line(p, m, Color(1.0, 0.85, 0.3, 0.45), 1.0)
				draw_polyline(PackedVector2Array([m + Vector2(0, -9), m + Vector2(9, 0), m + Vector2(0, 9), m + Vector2(-9, 0), m + Vector2(0, -9)]), amber, 2.0)
				_txt(m + Vector2(13, -8), "aim here", 11, amber)
		elif t.def.get("aa", "") == "missile" and t.aa_lock == a:
			var held: bool = t.aa_locked()
			var col := Color(1.0, 0.3, 0.25) if held else Color(0.4, 1.0, 0.5)
			var grow: float = 30.0 - 12.0 * clampf(t.aa_lock_t / t.AA_LOCK_SECONDS, 0.0, 1.0)
			draw_arc(p, grow, 0, TAU, 28, col, 2.0)
			_ctxt(p + Vector2(0, -grow - 8.0), "LOCKED - FIRE" if held else "locking...", 14, col)


# Flying: a gunsight where the guns point, and a panel with speed, height, damage and rockets.
func _draw_air(sz: Vector2, pc: PlayerCtrl) -> void:
	var a: Aircraft = pc.air
	var nose := -a.global_transform.basis.z
	var gun_from := a.global_position + Vector3(0, 1.2, 0) + nose * 6.0
	var aim := a.gun_aim(gun_from)
	var green := Color(0.4, 1.0, 0.5, 0.9)
	# The ring is where the weapons will actually hit. In a helicopter it follows your eye, so
	# it sits on the cross in the middle of the screen; if you look further round than the
	# guns can turn it stays on the nose and the cross goes red.
	var reach: float = pc.air_range if (a.heli and pc.air_range > 0.0 and aim != nose) else 400.0
	var far := gun_from + aim * reach
	if not pc.cam.is_position_behind(far):
		var at := pc.cam.unproject_position(far)
		draw_arc(at, 14.0, 0, TAU, 24, green, 1.5)
		draw_circle(at, 1.5, green)
	var c := sz * 0.5
	if pc.first_person and not a.heli:
		# From the cockpit the view is fixed to the nose, so where the mouse is steering to is marked.
		var steer: Vector3 = a.global_position + (a.want.get("aim_dir", nose) as Vector3) * 600.0
		if not pc.cam.is_position_behind(steer):
			var sp := pc.cam.unproject_position(steer)
			draw_arc(sp, 9.0, 0, TAU, 20, Color(1, 1, 1, 0.85), 1.5)
			draw_line(c, sp, Color(1, 1, 1, 0.18), 1.0)
	if a.heli and not pc.air_free:
		var on_target: bool = aim != nose
		var col := Color(1, 1, 1, 0.9) if on_target else Color(1.0, 0.4, 0.3, 0.9)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * 6.0, c + d * 20.0, col, 1.5)
		if pc.air_range > 0.0:
			_txt(c + Vector2(26, 22), "%d m" % int(pc.air_range), 14, col)
		if not on_target:
			_ctxt(c + Vector2(0, 46), "outside the guns' arc - turn towards it", 13, col)
	else:
		draw_circle(c, 2.0, Color(1, 1, 1, 0.7))
	if pc.air_free:
		_ctxt(Vector2(c.x, sz.y - 60.0), "FREE LOOK", 14, Color(1, 0.9, 0.5))
	# The missile seeker: while the sight button is held, a tall green box round the gunsight
	# shows what it can see. It goes red, with a marker on the aircraft, once it has a lock.
	if a.want.get("seek", false):
		var per_radian: float = (sz.y * 0.5) / tan(deg_to_rad(pc.cam.fov) * 0.5)
		var half := Vector2(tan(a.LOCK_BOX.x), tan(a.LOCK_BOX.y)) * per_radian
		var ahead := gun_from + nose * 500.0
		var mid: Vector2 = pc.cam.unproject_position(ahead) if not pc.cam.is_position_behind(ahead) else c
		var has_lock: bool = a.lock != null and a.lock_t >= a.LOCK_SECONDS
		var col := Color(1.0, 0.3, 0.25) if has_lock else Color(0.35, 1.0, 0.45)
		draw_rect(Rect2(mid - half, half * 2.0), col, false, 2.0)
		if a.lock != null and is_instance_valid(a.lock):
			var on: Vector3 = a.lock.global_position + Vector3(0, 1.5, 0)
			if not pc.cam.is_position_behind(on):
				var lp := pc.cam.unproject_position(on)
				var r := 26.0 - 12.0 * clampf(a.lock_t / a.LOCK_SECONDS, 0.0, 1.0)
				draw_polyline(PackedVector2Array([lp + Vector2(0, -r), lp + Vector2(r, 0), lp + Vector2(0, r), lp + Vector2(-r, 0), lp + Vector2(0, -r)]), col, 2.0)
		_ctxt(mid + Vector2(0, half.y + 20.0), ("LOCKED  -  %s fires" % Settings.binding_text("fire")) if has_lock else ("seeking..." if a.lock != null else "put an aircraft in the box"), 14, col)
	if a.threat_t > 0.0:
		# Red warning lights down both sides, blinking faster the closer the missile is.
		var close: bool = a.threat_dist < 100.0
		var lit: bool = int(main.elapsed * (16.0 if close else 5.0)) % 2 == 0
		if lit:
			_ctxt(Vector2(c.x, sz.y * 0.28), "MISSILE  %d m  -  %s for flares" % [int(a.threat_dist), Settings.binding_text("air_flare")], 24, Color(1.0, 0.3, 0.25))
			for side in [0.0, 1.0]:
				for k in 3:
					draw_circle(Vector2(26.0 + side * (sz.x - 52.0), sz.y * (0.38 + k * 0.08)), 11.0 if close else 8.0, Color(1.0, 0.15, 0.1, 0.9))
	var x := sz.x - 346.0
	var y := sz.y - 170.0
	draw_rect(Rect2(x - 10, y - 26, 340, 180), Color(0, 0, 0, 0.5))
	_txt(Vector2(x, y), "%s   [%s]" % [a.def["name"], "Helicopter" if a.heli else "Aircraft"], 18)
	draw_rect(Rect2(x, y + 10, 320, 14), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(x, y + 10, 320.0 * clampf(a.hp / float(a.def["hp"]), 0, 1), 14), Color(0.3, 0.85, 0.4))
	var height: float = a.global_position.y - main.map.height(a.global_position.x, a.global_position.z)
	_txt(Vector2(x, y + 48), "Speed  %d km/h" % int(a.speed * 3.6), 15)
	_txt(Vector2(x + 170, y + 48), "Height  %d m" % int(height), 15)
	var load_text := "Rockets %d   Bombs %d" % [a.rockets, a.bombs.size()]
	if a.missiles > 0 or (a.def["stores"] as Array).has("aam"):
		load_text = "Missiles %d" % a.missiles
	_txt(Vector2(x, y + 70), load_text + "   Flares %d" % a.flares, 15, Color(1, 0.9, 0.5))
	if not a.heli:
		_txt(Vector2(x + 222, y + 70), "Thr %d%%" % int(a.throttle * 100.0), 15)
	var state := ""
	if a.landed:
		state = "ON THE GROUND" + ("  -  rearming" if a.on_own_strip() and a._rearm_t > 0.0 else "")
	elif not a.heli and height < 25.0 and not main.map.on_strip(a.global_position):
		state = "PULL UP"
	_txt(Vector2(x, y + 94), state, 15, Color(1, 0.5, 0.4))
	_txt(Vector2(x, y + 122), ("W S A D, %s up, %s down, mouse turns and aims" % [Settings.binding_text("air_up"), Settings.binding_text("air_down")]) if a.heli else "mouse steers   W S throttle   land only on your airstrip", 12, Color(0.8, 0.8, 0.8))
	_txt(Vector2(x, y + 140), ("hold %s to seek, %s flares, %s look, %s zoom" % [Settings.binding_text("sight"), Settings.binding_text("air_flare"), Settings.binding_text("air_freelook"), Settings.binding_text("air_zoom")]) if (a.def["stores"] as Array).has("aam") else ("%s rockets  %s bomb  %s flares  %s look" % [Settings.binding_text("sight"), Settings.binding_text("air_bomb"), Settings.binding_text("air_flare"), Settings.binding_text("air_freelook")]), 12, Color(0.8, 0.8, 0.8))


# On foot: a small crosshair, and a panel with the man's class, health and what his keys do.
func _draw_man(sz: Vector2, pc: PlayerCtrl) -> void:
	var s: Soldier = pc.man
	var c := sz * 0.5
	if pc.scope_view:
		# Through the 4x scope: black all round a circle of view, and the scope's red chevron
		# with range bars under it.
		var r := sz.y * 0.44
		var rim := PackedVector2Array()
		for k in 49:
			rim.append(c + Vector2(cos(k * TAU / 48.0), sin(k * TAU / 48.0)) * r)
		for k in 48:
			var out_a := c + (rim[k] - c).normalized() * sz.x * 1.3
			var out_b := c + (rim[k + 1] - c).normalized() * sz.x * 1.3
			draw_colored_polygon(PackedVector2Array([rim[k], rim[k + 1], out_b, out_a]), Color.BLACK)
		draw_arc(c, r, 0, TAU, 64, Color(0, 0, 0, 0.9), 10.0)
		var red := Color(1.0, 0.16, 0.1, 0.95)
		draw_polyline(PackedVector2Array([c + Vector2(-9, 13), c, c + Vector2(9, 13)]), red, 2.5)
		for k in 3:
			draw_line(c + Vector2(-8.0 - k * 3.0, 30.0 + k * 20.0), c + Vector2(8.0 + k * 3.0, 30.0 + k * 20.0), Color(0, 0, 0, 0.85), 1.5)
		draw_line(c + Vector2(0, 14), c + Vector2(0, 100), Color(0, 0, 0, 0.85), 1.2)
	elif not (pc.first_person and pc.ads > 0.5):
		var open := 14.0 if s.want.get("move", Vector3.ZERO).length() > 0.1 else 8.0
		if s.want.get("aim", false):
			open *= 0.5
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * open, c + d * (open + 9.0), Color(1, 1, 1, 0.9), 2.0)
		draw_circle(c, 1.5, Color.WHITE)
	var x := sz.x - 346.0
	var y := sz.y - 150.0
	draw_rect(Rect2(x - 10, y - 26, 340, 160), Color(0, 0, 0, 0.5))
	_txt(Vector2(x, y), "%s   [Infantry]" % s.def["name"], 18)
	var full := float(s.def["hp"])
	draw_rect(Rect2(x, y + 10, 320, 14), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(x, y + 10, 320.0 * clampf(s.hp / full, 0, 1), 14), Color(0.3, 0.85, 0.4))
	var about: String = Soldier.ABOUT.get(s.def["id"], "")
	var lines := about.split(". ", false)
	for i in mini(lines.size(), 3):
		_txt(Vector2(x, y + 46 + i * 18.0), lines[i].trim_suffix(".").left(50), 13, Color(0.85, 0.85, 0.85))
	var held := "Primary  %d   + %d spare" % [s.mag, s.mags]
	if s.weapon == 2:
		held = "Pistol  %d   + %d spare" % [s.pistol, s.pistol_mags]
	elif s.weapon == 3:
		held = "RPG-7  %d rockets" % s.rockets
		if s._fire_t > 0.0 and s.rockets > 0:
			held += "    LOADING"
	if s.reloading > 0.0:
		held += "    RELOADING"
	_txt(Vector2(x, y + 104), "%s      Grenades %d" % [held, s.grenades], 14, Color(1, 0.9, 0.5))
	if s._use_t > 0.0:
		_ctxt(c + Vector2(0, 60), "working...", 16, Color(0.5, 1.0, 0.6))
	_txt(Vector2(x, y + 124), "1 2 3 weapons  %s reload  %s prone  %s jump / vault" % [Settings.binding_text("inf_reload"), Settings.binding_text("inf_prone"), Settings.binding_text("inf_jump")], 12, Color(0.8, 0.8, 0.8))


# The compass along the top: the bearing you are looking along in the middle, a strip of
# ticks sliding past behind it, and a diamond for each of your team's pings. North is the
# top of the map.
func _draw_compass(sz: Vector2, pc: PlayerCtrl) -> void:
	var mid := Vector2(sz.x * 0.5, 30.0)
	var wide := 300.0   # half the strip's width, pixels
	var per_deg := 4.0
	var f := -pc.cam.global_transform.basis.z
	var bearing := fposmod(rad_to_deg(atan2(f.z, f.x)), 360.0)
	draw_rect(Rect2(mid.x - wide - 8, 8, wide * 2.0 + 16, 46), Color(0, 0, 0, 0.45))
	var first := int(floor((bearing - wide / per_deg) / 5.0)) * 5
	var names := {0: "N", 90: "E", 180: "S", 270: "W"}
	for d in range(first, first + int(wide * 2.0 / per_deg) + 10, 5):
		var x := mid.x + (float(d) - bearing) * per_deg
		if absf(x - mid.x) > wide:
			continue
		var deg := posmod(d, 360)
		var big := deg % 15 == 0
		draw_line(Vector2(x, 44), Vector2(x, 34 if big else 39), Color(1, 1, 1, 0.8), 1.5 if big else 1.0)
		if big and absf(x - mid.x) > 34.0:
			_ctxt(Vector2(x, 28), names.get(deg, str(deg)), 14 if names.has(deg) else 11, Color(1, 0.86, 0.45) if names.has(deg) else Color(0.85, 0.85, 0.85))
	draw_rect(Rect2(mid.x - 30, 10, 60, 24), Color(0, 0, 0, 0.75))
	_ctxt(Vector2(mid.x, 28), "%03d" % (int(round(bearing)) % 360), 18)
	draw_colored_polygon(PackedVector2Array([Vector2(mid.x - 5, 52), Vector2(mid.x + 5, 52), Vector2(mid.x, 45)]), Color.WHITE)
	var my_team := int(main.player_slot.get("team", 0))
	for i in main.dom.size():
		var gap: Vector3 = main.dom[i]["pos"] - pc.cam.global_position
		var lx := mid.x + clampf(wrapf(rad_to_deg(atan2(gap.z, gap.x)) - bearing, -180.0, 180.0) * per_deg, -wide, wide)
		draw_rect(Rect2(lx - 9, 38, 18, 16), Color(0, 0, 0, 0.8))
		_ctxt(Vector2(lx, 52), "ABC"[i], 14, main.dom_colour(i))
	for p in main.pings:
		if p["team"] != my_team and not main.spectating:
			continue
		var to: Vector3 = main.ping_pos(p) - pc.cam.global_position
		var off := wrapf(rad_to_deg(atan2(to.z, to.x)) - bearing, -180.0, 180.0)
		var px := mid.x + clampf(off * per_deg, -wide, wide)
		draw_colored_polygon(PackedVector2Array([Vector2(px, 40), Vector2(px + 6, 46), Vector2(px, 52), Vector2(px - 6, 46)]), p["colour"])


# The main gun's reload as a ring round the crosshair. It fills clockwise from the top and
# disappears once the gun is ready. Guns that reload in under a second do not show one.
func _draw_reload_ring(c: Vector2, r: float, t: Tank) -> void:
	if t.reload_left <= 0.0 or t.reload_total < 0.8:
		return
	var frac := 1.0 - clampf(t.reload_left / t.reload_total, 0.0, 1.0)
	draw_arc(c, r, 0, TAU, 48, Color(0, 0, 0, 0.4), 4.0)
	draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, Color(1, 0.75, 0.3, 0.95), 3.0)


# Emotes float above the vehicle that sent them, for everyone to see.
func _draw_emotes(pc: PlayerCtrl) -> void:
	for t in main.tanks:
		if t.emote_t <= 0.0:
			continue
		var wp: Vector3 = t.global_position + Vector3(0, 7.0, 0)
		if pc.cam.is_position_behind(wp):
			continue
		var pop := clampf((3.0 - t.emote_t) * 7.0, 0.0, 1.0) * clampf(t.emote_t * 4.0, 0.0, 1.0)
		_draw_emote(pc.cam.unproject_position(wp), GameData.emotes[t.emote], 54.0 * pop, true)


func _draw_emote_bar(sz: Vector2) -> void:
	var ids: Array = GameData.emote_order
	var slot_w := 104.0
	var x0 := sz.x * 0.5 - slot_w * ids.size() * 0.5
	var y := sz.y - 190.0
	draw_rect(Rect2(x0 - 8, y - 46, slot_w * ids.size() + 16, 104), Color(0, 0, 0, 0.6))
	for i in ids.size():
		var c := Vector2(x0 + slot_w * (i + 0.5), y)
		_draw_emote(c, GameData.emotes[ids[i]], 40.0, false)
		_ctxt(c + Vector2(0, 48), "[%d]" % (i + 1), 15, Color(1, 0.9, 0.5))


# One emote: a face drawn from simple shapes, or a phrase in a speech bubble.
func _draw_emote(c: Vector2, e: Dictionary, s: float, bubble: bool) -> void:
	if s < 2.0:
		return
	var ink := Color(0.12, 0.1, 0.08)
	var face: String = e["face"]
	if face == "none":
		var px := int(s * 0.36)
		var w := font.get_string_size(e["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + s * 0.5
		if not bubble:
			w = minf(w, 100.0)
			px = 13
		draw_rect(Rect2(c.x - w * 0.5, c.y - s * 0.4, w, s * 0.8), Color(1, 1, 1, 0.95))
		draw_rect(Rect2(c.x - w * 0.5, c.y - s * 0.4, w, s * 0.8), ink, false, 2.0)
		if bubble:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, s * 0.4), c + Vector2(8, s * 0.4), c + Vector2(0, s * 0.62)]), Color(1, 1, 1, 0.95))
		var tw := font.get_string_size(e["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(font, c + Vector2(-tw * 0.5, px * 0.35), e["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
		return
	var r := s * 0.5
	var skin := Color(1.0, 0.82, 0.25)
	if face == "angry":
		skin = Color(0.95, 0.4, 0.25)
	elif face == "cry":
		skin = Color(0.95, 0.85, 0.45)
	draw_circle(c, r, skin)
	draw_arc(c, r, 0, TAU, 32, ink, 2.0)
	var le := c + Vector2(-r * 0.36, -r * 0.2)
	var re := c + Vector2(r * 0.36, -r * 0.2)
	var tear := Color(0.35, 0.65, 1.0)
	match face:
		"laugh":
			for eye in [le, re]:
				draw_arc(eye, r * 0.18, PI, TAU, 10, ink, 2.5)
			var mouth := PackedVector2Array()
			for i in 13:
				var a := float(i) / 12.0 * PI
				mouth.append(c + Vector2(cos(a) * r * 0.55, r * 0.12 + sin(a) * r * 0.5))
			draw_colored_polygon(mouth, ink)
			draw_circle(le + Vector2(-r * 0.3, r * 0.12), r * 0.11, tear)
			draw_circle(re + Vector2(r * 0.3, r * 0.12), r * 0.11, tear)
		"cry":
			for eye in [le, re]:
				draw_arc(eye, r * 0.16, 0, PI, 10, ink, 2.5)
				draw_rect(Rect2(eye.x - r * 0.08, eye.y + r * 0.15, r * 0.16, r * 0.75), tear)
			draw_arc(c + Vector2(0, r * 0.7), r * 0.32, PI * 1.15, PI * 1.85, 12, ink, 2.5)
		"angry":
			draw_line(le + Vector2(-r * 0.22, -r * 0.28), le + Vector2(r * 0.2, -r * 0.08), ink, 3.0)
			draw_line(re + Vector2(r * 0.22, -r * 0.28), re + Vector2(-r * 0.2, -r * 0.08), ink, 3.0)
			draw_circle(le, r * 0.1, ink)
			draw_circle(re, r * 0.1, ink)
			draw_arc(c + Vector2(0, r * 0.72), r * 0.36, PI * 1.2, PI * 1.8, 12, ink, 3.0)
		"wow":
			draw_circle(le, r * 0.15, Color.WHITE)
			draw_circle(re, r * 0.15, Color.WHITE)
			draw_circle(le, r * 0.07, ink)
			draw_circle(re, r * 0.07, ink)
			draw_circle(c + Vector2(0, r * 0.42), r * 0.2, ink)


# Gunner's sight: a scope ring with the rangefinder and the sight zero.
# With the zero off, a ladder of range marks shows how far to hold over instead.
func _draw_scope(sz: Vector2, pc: PlayerCtrl) -> void:
	var c := sz * 0.5
	var t := pc.tank
	var radius := sz.y * 0.47
	draw_arc(c, radius + sz.x * 0.5, 0, TAU, 96, Color(0, 0, 0, 0.92), sz.x)
	draw_arc(c, radius, 0, TAU, 96, Color(0, 0, 0), 3.0)
	var line := Color(0.05, 0.05, 0.05, 0.9)
	draw_line(c + Vector2(0, -radius), c + Vector2(0, -30), line, 1.5)
	draw_line(c + Vector2(0, -radius * 0.5), c + Vector2(0, radius * 0.9), line, 1.0)
	var sd := t.current_shell()
	# The range marks never move: one every 200 m down the upright line, each where a shell
	# fired level would have dropped to at that range. The level line is what moves: it sits
	# at the centre with the zero off, and slides down to the set range as the zero is raised.
	# Put the target where the two lines cross.
	var v: float = sd["velocity"]
	var half_fov := tan(deg_to_rad(pc.cam.fov) * 0.5)
	var drop := func(r: float) -> float:
		var k := GameData.SHELL_GRAVITY * r / (v * v)
		return -1.0 if k >= 1.0 else tan(0.5 * asin(k)) / half_fov * sz.y * 0.5
	# With the sight zeroed the gun is raised, so the centre is where a shell lands at the zero
	# range, and the whole column of marks slides up to put that range's mark on the centre.
	var shift: float = maxf(drop.call(t.zero_range), 0.0) if t.zero_range > 0.0 else 0.0
	for i in range(1, 16):
		var py: float = drop.call(i * 200.0)
		if py < 0.0:
			break
		py -= shift
		if absf(py) > radius - 30.0:
			continue
		var p := c + Vector2(0, py)
		var w := 26.0 if i % 2 == 0 else 14.0
		draw_line(p + Vector2(-w, 0), p + Vector2(w, 0), line, 1.5)
		if i % 2 == 0:
			draw_string(font, p + Vector2(w + 6, 5), str(i * 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, line)
	var cross := c
	draw_line(cross + Vector2(-radius, 0), cross + Vector2(-40, 0), line, 1.5)
	draw_line(cross + Vector2(40, 0), cross + Vector2(radius, 0), line, 1.5)
	draw_line(cross + Vector2(-8, 0), cross + Vector2(8, 0), line, 1.5)
	var rng := "Range  ---   (%s to measure)" % Settings.binding_text("rangefind")
	if pc.ranging > 0.0:
		rng = "Ranging" + ".".repeat(1 + int(pc.ranging * 6.0) % 3)
	elif pc.ranged > 0.0:
		rng = "Range  %d m" % int(pc.ranged)
	_txt(c + Vector2(60, -14), rng, 20, Color(1, 0.9, 0.5))
	var zero := "Zero off - marks are x100 m" if t.zero_range <= 0.0 else "Zero  %d m" % int(t.zero_range)
	var matched: bool = t.zero_range > 0.0 and pc.ranged > 0.0 and absf(pc.ranged - t.zero_range) < 20.0
	_txt(c + Vector2(60, 12), zero, 17, Color(0.4, 1.0, 0.5) if matched else Color(1, 1, 1))
	_ctxt(c + Vector2(0, -radius + 144), "%s   wheel sets the zero   hold %s to magnify (sight switched on with %s)" % [sd["name"], Settings.binding_text("sight"), Settings.binding_text("sight_toggle")], 13, Color(0.85, 0.85, 0.85))
