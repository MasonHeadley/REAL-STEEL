extends CanvasLayer
# The deploy screen, shown whenever the player has no vehicle.
#   Left     the vehicles, one card each. Click to choose; hover to read about another.
#   Top right  the battle map: your team, enemies your team can see, the objective, and the
#              three places you can deploy. Click one to choose it.
#   Bottom right  everything about the vehicle in one place, grouped as Protection, Firepower
#              and Mobility, with every bar measured against the best in the roster.

const CARD := Vector2(192, 112)
const MAP_ASPECT := 1600.0 / 608.0
const GOLD := Color(1.0, 0.85, 0.45)
const GREY := Color(0.72, 0.74, 0.76)
const PANEL := Color(0.07, 0.085, 0.1, 0.94)
# Deploy points by lane number. Lane 2 is up the left flank, which is the top of the map.
const LANE_LETTER := ["C", "B", "A"]
const LANE_NAME := ["RIGHT FLANK", "ROAD", "LEFT FLANK"]

var main
var root: Control
var cards := {}
var selected := ""
var shown := ""
var lane := 1
var hover_lane := -1
var deploy: Button
var status: Label
var map_view: Control
var detail: Control
var font: Font
var best := {}  # the highest value of each stat across the roster, for scaling the bars
var _t := 0.0
var left_tabs := {}
var air_opts: Control
var air_loadouts := {}           # aircraft id -> what the player has hung on each of its pylons (see Ordnance)
const RACK_SIZE := Vector2(330, 179)  # the front view of the chosen aircraft, with a box on each pylon
var _rack_vp: Node
var _rack_tex: Texture2D
var _rack_dist := 20.0
var _rack_menu: PopupMenu
var _rack_pylon := -1
var _rack_hover := -1
var _man_stage: Node3D
var _man_model: SoldierModel
var _kit_pics := {}
# What each class carries: [picture, name, note] for the primary weapon, the side arm, the
# class's own tool, and what it throws.
const KITS := {
	"assault": [["rifle", "Assault rifle", "Left mouse fires, right mouse aims."], ["pistol", "Pistol", "Key 2 draws it. 12 rounds a magazine."], ["pouch", "Extra ammunition", "No special tool."], ["frag", "Frag grenades", "G throws one where you look."]],
	"gunner": [["lmg", "Light machine gun", "Heavy fire. Ctrl to crouch and steady it."], ["pistol", "Pistol", "Key 2 draws it. 12 rounds a magazine."], ["pouch", "Belt boxes", "No special tool."], ["frag", "Frag grenades", "G throws one where you look."]],
	"medic": [["carbine", "Carbine", "Left mouse fires, right mouse aims."], ["pistol", "Pistol", "Key 2 draws it. 12 rounds a magazine."], ["medkit", "Med kit", "Hold F beside a fallen teammate."], ["smoke", "Smoke grenades", "G throws one: cover for a rescue."]],
	"rocket": [["rifle", "Rifle", "Key 1. Left mouse fires."], ["pistol", "Pistol", "Key 2 draws it. 12 rounds a magazine."], ["launcher", "RPG-7", "Key 3. Three rockets; a few seconds to load each."], ["frag", "Frag grenades", "G throws one where you look."]],
	"engineer": [["rifle", "Rifle", "Left mouse fires, right mouse aims."], ["pistol", "Pistol", "Key 2 draws it. 12 rounds a magazine."], ["toolbox", "Tool kit", "Hold F beside a friendly vehicle."], ["mine", "Anti-tank mines", "Not built yet: G throws a grenade."]],
}


func _ready() -> void:
	layer = 5
	font = ThemeDB.fallback_font
	_measure_roster()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	root.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	# Top bar: where you are, and what you are waiting for.
	var bar := HBoxContainer.new()
	page.add_child(bar)
	_label(bar, "DEPLOY", 34, GOLD)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	status = _label(bar, "", 24)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	_label(left, "1.  CHOOSE WHAT TO BE", 17, GREY)
	# Tabs: ground vehicles, infantry, and (later) aircraft.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	left.add_child(tabs)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	for id in GameData.vehicle_order:
		# Vehicles switched off in the game rules are not offered.
		if Settings.vehicle_enabled(id):
			grid.add_child(_card(id))
	# Infantry: a short button for each class, and under them the chosen class turning slowly.
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 4)
	foot.visible = false
	left.add_child(foot)
	for id in GameData.infantry:
		if not Settings.rules["infantry"]:
			break  # switched off in the game rules
		var b := Button.new()
		b.custom_minimum_size = Vector2(CARD.x * 2.0 + 8.0, 32)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.text = "  " + String(GameData.infantry[id]["name"]).to_upper()
		b.pressed.connect(func(): _select("inf:" + id))
		foot.add_child(b)
		cards["inf:" + id] = b
	var stand := SubViewportContainer.new()
	stand.custom_minimum_size = Vector2(CARD.x * 2.0 + 8.0, 240)
	stand.stretch = true
	stand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(stand)
	var port := SubViewport.new()
	port.own_world_3d = true
	port.transparent_bg = true
	stand.add_child(port)
	_man_stage = Node3D.new()
	port.add_child(_man_stage)
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-40, 150, 0)
	_man_stage.add_child(lamp)
	var air_env := Environment.new()
	air_env.background_mode = Environment.BG_CLEAR_COLOR
	air_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air_env.ambient_light_color = Color(0.6, 0.62, 0.66)
	var man_cam := Camera3D.new()
	man_cam.environment = air_env
	man_cam.fov = 32.0
	_man_stage.add_child(man_cam)
	man_cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.95, 0) - Vector3(1.3, 1.5, -3.9)), Vector3(1.3, 1.5, -3.9))

	# Aircraft: a card each with its picture, like the vehicles.
	var sky := GridContainer.new()
	sky.columns = 2
	sky.add_theme_constant_override("h_separation", 8)
	sky.add_theme_constant_override("v_separation", 8)
	sky.visible = false
	left.add_child(sky)
	Aircraft.load_sheet()
	for id in Aircraft.order:
		var craft: Dictionary = Aircraft.sheet[id]
		if not Settings.rules["helis" if craft["kind"] == "heli" else "planes"]:
			continue  # switched off in the game rules
		var far := 1.2 if craft["kind"] == "heli" else 1.0
		var pic := _picture(AircraftModel.build(id, main.TEAM_COLORS[0])["root"], Vector3(11.5, 7.0, -14.0) * far, Vector3(0, 1.8, 0))
		sky.add_child(_plain_card("air:" + id, craft["name"], "Helicopter" if craft["kind"] == "heli" else "Aircraft", pic))
	var pages := {"GROUND": grid, "INFANTRY": foot, "AIR": sky}
	left_tabs = pages
	for tab_name in ["GROUND", "INFANTRY", "AIR"]:
		var tab := Button.new()
		tab.text = tab_name
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(124, 30)
		tab.add_theme_font_size_override("font_size", 14)
		tab.disabled = not pages.has(tab_name)
		tab.pressed.connect(func():
			for k in pages:
				pages[k].visible = k == tab_name)
		tabs.add_child(tab)
	var push_down := Control.new()
	push_down.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(push_down)
	_label(left, "3.  GO", 17, GREY)
	deploy = Button.new()
	deploy.custom_minimum_size = Vector2(CARD.x * 2.0 + 8.0, 66)
	deploy.custom_minimum_size = Vector2(CARD.x * 2.0 + 8.0, 78)
	# It is drawn by hand (see _draw_deploy): the button itself shows nothing of its own.
	for part in ["normal", "hover", "pressed", "disabled", "focus"]:
		deploy.add_theme_stylebox_override(part, StyleBoxEmpty.new())
	deploy.focus_mode = Control.FOCUS_NONE
	deploy.draw.connect(_draw_deploy)
	deploy.pressed.connect(_deploy)
	left.add_child(deploy)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_label(right, "2.  CHOOSE WHERE TO START  -  click A, B or C on the map", 17, GREY)
	map_view = Control.new()
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.size_flags_stretch_ratio = 1.25
	map_view.custom_minimum_size = Vector2(700, 270)
	map_view.draw.connect(_draw_map)
	map_view.gui_input.connect(_map_input)
	map_view.mouse_exited.connect(func(): hover_lane = -1)
	right.add_child(map_view)
	detail = Control.new()
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.custom_minimum_size = Vector2(700, 300)
	detail.draw.connect(_draw_detail)
	detail.gui_input.connect(func(e: InputEvent):
		# A click on an infantryman's PRIMARY box steps his rifle through its sights.
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and selected.begins_with("inf:"):
			var bw: float = (detail.size.x - 44.0 - 36.0) / 4.0
			if Rect2(22, 78, bw, detail.size.y - 100.0).has_point(e.position):
				Settings.set_inf_sight(WeaponModel.SIGHTS[(WeaponModel.SIGHTS.find(Settings.inf_sight) + 1) % WeaponModel.SIGHTS.size()])
				detail.queue_redraw())
	# What hangs on an aircraft's pylons: a front view of it with a green box on each pylon.
	# Clicking a box opens a list of what can go there.
	air_opts = Control.new()
	air_opts.position = Vector2(22, 156)
	air_opts.custom_minimum_size = RACK_SIZE
	air_opts.size = RACK_SIZE
	air_opts.visible = false
	air_opts.draw.connect(_draw_rack)
	air_opts.gui_input.connect(_rack_input)
	air_opts.mouse_exited.connect(func():
		_rack_hover = -1
		air_opts.queue_redraw())
	detail.add_child(air_opts)
	_rack_menu = PopupMenu.new()
	_rack_menu.id_pressed.connect(_rack_chosen)
	add_child(_rack_menu)
	right.add_child(detail)


func _label(parent: Control, text: String, px: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _measure_roster() -> void:
	best = {"pen": 1.0, "damage": 1.0, "speed": 1.0, "reverse": 1.0, "hp": 1.0, "armour": 1.0, "turn": 1.0, "traverse": 1.0, "rate": 0.01}
	for id in GameData.vehicle_order:
		var v: Dictionary = GameData.vehicles[id]
		best["speed"] = maxf(best["speed"], v["speed_fwd"])
		best["reverse"] = maxf(best["reverse"], v["speed_rev"])
		best["hp"] = maxf(best["hp"], v["hp"])
		best["turn"] = maxf(best["turn"], v["turn_rate"])
		best["traverse"] = maxf(best["traverse"], v["turret_traverse"])
		best["rate"] = maxf(best["rate"], 60.0 / float(v["reload"]))
		for k in v["armour"]:
			best["armour"] = maxf(best["armour"], v["armour"][k])
		for sid in v["shells"]:
			best["pen"] = maxf(best["pen"], GameData.shells[sid]["pen"])
			best["damage"] = maxf(best["damage"], GameData.shells[sid]["damage"])


# One card: a rendered picture of the vehicle, its name, and its role in the role's colour.
func _card(id: String) -> Button:
	var v: Dictionary = GameData.vehicles[id]
	var role: Dictionary = GameData.roles[v["role"]]
	var b := Button.new()
	b.custom_minimum_size = CARD
	b.toggle_mode = true
	b.clip_contents = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _select(id))
	b.mouse_entered.connect(func(): shown = id)
	b.mouse_exited.connect(func(): shown = selected if not selected.contains(":") else "")
	var stripe := ColorRect.new()
	stripe.color = Color(String(role["colour"]))
	stripe.position = Vector2(0, 0)
	stripe.size = Vector2(5, CARD.y)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(stripe)
	var pic := TextureRect.new()
	pic.texture = _portrait(v)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.position = Vector2(8, 2)
	pic.size = Vector2(CARD.x - 12, CARD.y - 40)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	var name_label := _label(b, v["name"], 15)
	name_label.position = Vector2(12, CARD.y - 40)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var role_label := _label(b, "%s  -  %s" % [role["name"], v["class"]], 12, Color(String(role["colour"])))
	role_label.position = Vector2(12, CARD.y - 21)
	role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards[id] = b
	return b


# Renders the vehicle's model once, in a little studio of its own, and returns the picture.
func _portrait(v: Dictionary) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(384, 208)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	vp.add_child(TankModel.build(v, main.TEAM_COLORS[0], 0.3, hash(String(v["id"])) % 1000 + 1)["root"])
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 150, 0)
	vp.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	var cam := Camera3D.new()
	cam.environment = env
	cam.fov = 30.0
	vp.add_child(cam)
	var reach: float = maxf(float(v["length"]) + float(v["gun_length"]) * 0.5, 7.0)
	cam.position = Vector3(reach * 0.8, reach * 0.42, -reach * 0.95)
	cam.look_at(Vector3(0, float(v["height"]) * 0.45, -float(v["gun_length"]) * 0.2), Vector3.UP)
	return vp.get_texture()


func _select(id: String) -> void:
	selected = id
	shown = id if not id.contains(":") else ""
	air_opts.visible = id.begins_with("air:")
	_rack_refresh()
	if id.begins_with("inf:"):
		# Stand the chosen class in the viewer.
		if _man_model != null and is_instance_valid(_man_model):
			_man_model.queue_free()
		_man_model = SoldierModel.new()
		_man_stage.add_child(_man_model)
		_man_model.build(int(main.player_slot.get("team", 0)), GameData.infantry[id.trim_prefix("inf:")]["kit"])
		_man_model.gun_low = 0.3
	for c in cards:
		cards[c].button_pressed = c == id


func _deploy() -> void:
	if selected.begins_with("air:"):
		main.deploy_aircraft(selected.trim_prefix("air:"), _air_loadout(selected.trim_prefix("air:")).duplicate())
	elif selected.begins_with("inf:"):
		main.deploy_infantry(selected.trim_prefix("inf:"), lane)
	elif selected != "" and float(main.player_slot["respawn_t"]) <= 0.0:
		main.deploy_player(selected, lane)


# ---- the map ----

# The map picture fills the space it is given without being stretched.
func _map_rect() -> Rect2:
	var s := map_view.size
	var aspect: float = main.map.half_len / PushMap.HALF_WIDTH  # the map picture is the same shape as the map
	var w := minf(s.x, s.y * aspect)
	var size := Vector2(w, w / aspect)
	return Rect2((s - size) * 0.5, size)


func _map_point(world: Vector3) -> Vector2:
	var r := _map_rect()
	return r.position + main.map_uv(world) * r.size


func _lane_at(pos: Vector2) -> int:
	var found := -1
	var nearest := 30.0
	for i in 3:
		var d: float = _map_point(main.spawn_point(0, i, 2)).distance_to(pos)
		if d < nearest:
			nearest = d
			found = i
	return found


func _map_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover_lane = _lane_at(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var hit := _lane_at(e.position)
		if hit >= 0:
			lane = hit


func _text(c: Control, pos: Vector2, s: String, px: int, col: Color = Color.WHITE) -> void:
	c.draw_string(font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.8))
	c.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _text_mid(c: Control, pos: Vector2, s: String, px: int, col: Color = Color.WHITE) -> void:
	_text(c, pos - Vector2(font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 0.5, 0), s, px, col)


func _draw_map() -> void:
	var mv := map_view
	var r := _map_rect()
	mv.draw_rect(Rect2(Vector2.ZERO, mv.size), PANEL)
	if main.sat_texture != null:
		mv.draw_texture_rect(main.sat_texture, r, false, Color(0.82, 0.86, 0.9))
	# Each team's end of the map is tinted its colour, fading towards the middle.
	var blue: Color = main.TEAM_COLORS[0]
	var red: Color = main.TEAM_COLORS[1]
	for i in 12:
		var k := float(i) / 12.0
		var a := 0.2 * (1.0 - k)
		mv.draw_rect(Rect2(r.position.x + r.size.x * 0.25 * k, r.position.y, r.size.x * 0.25 / 12.0 + 1.0, r.size.y), Color(blue, a))
		mv.draw_rect(Rect2(r.end.x - r.size.x * 0.25 * (k + 1.0 / 12.0), r.position.y, r.size.x * 0.25 / 12.0 + 1.0, r.size.y), Color(red, a))
	# A 100 metre grid.
	var per_m: float = r.size.x / (float(main.map.half_len) * 2.0)
	var gx := r.position.x
	while gx < r.end.x:
		mv.draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), Color(1, 1, 1, 0.06), 1.0)
		gx += 100.0 * per_m
	var gy := r.position.y
	while gy < r.end.y:
		mv.draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), Color(1, 1, 1, 0.06), 1.0)
		gy += 100.0 * per_m
	mv.draw_rect(r, Color(0.85, 0.7, 0.3), false, 2.0)
	_text(mv, r.position + Vector2(10, 22), "YOUR SIDE", 14, blue.lightened(0.3))
	var es := "ENEMY SIDE"
	_text(mv, Vector2(r.end.x - font.get_string_size(es, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x - 10, r.position.y + 22), es, 14, red.lightened(0.3))
	_text(mv, Vector2(r.position.x + 10, r.end.y - 10), "100 m squares", 11, Color(1, 1, 1, 0.5))

	# The objective, and in Push how far each team has shoved its barricade.
	var push: PushMode = main.push
	var objective := _map_point(main.objective_pos())
	if main.mode["kind"] == "push":
		for t in 2:
			var bp := _map_point(main.path_pos(main.team_dir(t) * push.progress[t]))
			mv.draw_line(bp + Vector2(0, -14), bp + Vector2(0, 14), main.TEAM_COLORS[t], 4.0)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	mv.draw_arc(objective, 13.0 + pulse * 3.0, 0, TAU, 28, Color(1, 1, 1, 0.9), 2.0)
	mv.draw_colored_polygon(PackedVector2Array([objective + Vector2(0, -8), objective + Vector2(8, 0), objective + Vector2(0, 8), objective + Vector2(-8, 0)]), Color.WHITE)
	_text_mid(mv, objective + Vector2(0, -22), "ROBOT" if main.mode["kind"] == "push" else "CENTRE", 13)

	# Your team: an arrow for each vehicle, pointing the way it faces, with who is in it.
	for t in main.tanks:
		var p := _map_point(t.global_position)
		if t.team == 0:
			var f := Vector2(-cos(t.heading), sin(t.heading))  # heading on the map: enemy is to the right
			var side := Vector2(-f.y, f.x)
			mv.draw_colored_polygon(PackedVector2Array([p + f * 10.0, p - f * 7.0 + side * 6.0, p - f * 7.0 - side * 6.0]), blue.lightened(0.15))
			mv.draw_polyline(PackedVector2Array([p + f * 10.0, p - f * 7.0 + side * 6.0, p - f * 7.0 - side * 6.0, p + f * 10.0]), Color.BLACK, 1.0)
			_text(mv, p + Vector2(11, 4), "%s  %s" % [t.display_name, t.def["name"]], 11, Color(0.85, 0.92, 1.0))
		elif t.spotted:
			# Enemies only while someone on your team can see them.
			mv.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)]), red)
			_text(mv, p + Vector2(11, 4), t.def["name"], 11, red.lightened(0.35))
	for s in main.soldiers:
		if s.team == 0:
			mv.draw_circle(_map_point(s.global_position), 1.8, Color(0.5, 0.9, 0.5))
	for p in main.pings:
		if p["team"] == 0:
			mv.draw_arc(_map_point(main.ping_pos(p)), 9.0, 0, TAU, 16, p["colour"], 2.0)

	# The three places to start. The chosen one is gold, with its distance to the objective.
	for i in 3:
		var world: Vector3 = main.spawn_point(0, i, 2)
		var sp := _map_point(world)
		var chosen := i == lane
		var hot := i == hover_lane
		var size := 19.0 if (chosen or hot) else 16.0
		if chosen:
			mv.draw_dashed_line(sp, objective, Color(GOLD, 0.7), 2.0, 8.0)
			mv.draw_arc(sp, size + 5.0 + pulse * 4.0, 0, TAU, 28, Color(GOLD, 0.8), 2.0)
		mv.draw_circle(sp, size, GOLD if chosen else Color(0.05, 0.08, 0.12, 0.92))
		mv.draw_arc(sp, size, 0, TAU, 28, GOLD if (chosen or hot) else Color(1, 1, 1, 0.8), 2.0)
		_text_mid(mv, sp + Vector2(0, 7), LANE_LETTER[i], 20, Color.BLACK if chosen else Color.WHITE)
		var tag: String = LANE_NAME[i]
		if chosen:
			tag += "  -  %d m to the objective" % int(world.distance_to(main.objective_pos()))
		_text_mid(mv, sp + Vector2(0, size + 16.0), tag, 12, GOLD if chosen else GREY)

	# Legend.
	var lx := r.end.x - 356.0
	var ly := r.end.y - 12.0
	mv.draw_rect(Rect2(lx - 8, ly - 14, 362, 22), Color(0, 0, 0, 0.55))
	mv.draw_colored_polygon(PackedVector2Array([Vector2(lx + 10, ly - 4), Vector2(lx, ly + 2), Vector2(lx, ly - 10)]), blue.lightened(0.15))
	_text(mv, Vector2(lx + 16, ly + 1), "your team", 11)
	mv.draw_colored_polygon(PackedVector2Array([Vector2(lx + 96, ly - 10), Vector2(lx + 102, ly - 4), Vector2(lx + 96, ly + 2), Vector2(lx + 90, ly - 4)]), red)
	_text(mv, Vector2(lx + 108, ly + 1), "enemy in sight", 11)
	mv.draw_circle(Vector2(lx + 212, ly - 4), 6.0, GOLD)
	_text(mv, Vector2(lx + 224, ly + 1), "start here", 11)
	mv.draw_line(Vector2(lx + 300, ly - 11), Vector2(lx + 300, ly + 3), blue, 3.0)
	_text(mv, Vector2(lx + 308, ly + 1), "barricade", 11)


# ---- the vehicle's details ----

# A labelled bar: what it measures, how it compares with the best in the roster, and the number.
func _stat(c: Control, pos: Vector2, width: float, label: String, value: float, top: float, shown_value: String, col: Color) -> void:
	_text(c, pos + Vector2(0, 12), label, 13, GREY)
	var bx := pos.x + 112.0
	var bw := width - 112.0 - 96.0
	c.draw_rect(Rect2(bx, pos.y + 2, bw, 11), Color(1, 1, 1, 0.1))
	c.draw_rect(Rect2(bx, pos.y + 2, bw * clampf(value / maxf(top, 0.001), 0.0, 1.0), 11), col)
	_text(c, Vector2(bx + bw + 10, pos.y + 12), shown_value, 14)


func _armour_colour(mm: float) -> Color:
	var k := clampf(mm / float(best["armour"]), 0.0, 1.0)
	return Color(0.95, 0.35, 0.3).lerp(Color(0.95, 0.85, 0.3), clampf(k * 2.0, 0.0, 1.0)).lerp(Color(0.4, 0.9, 0.45), clampf(k * 2.0 - 1.0, 0.0, 1.0))


func _draw_detail() -> void:
	var c := detail
	var w := c.size.x
	var h := c.size.y
	c.draw_rect(Rect2(Vector2.ZERO, c.size), PANEL)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(1, 1, 1, 0.12), false, 1.0)
	if selected.begins_with("air:"):
		_draw_air_card(c, w, h)
		return
	if selected.begins_with("inf:"):
		_draw_kit(c, w, h)
		return
	if shown == "" or not GameData.vehicles.has(shown):
		_text_mid(c, Vector2(w * 0.5, h * 0.5), "Hover over a vehicle to see what it does. Click to choose it.", 18, GREY)
		return
	var v: Dictionary = GameData.vehicles[shown]
	var role: Dictionary = GameData.roles[v["role"]]
	var role_col := Color(String(role["colour"]))
	var ab: Dictionary = GameData.abilities[v["ability"]]
	var a: Dictionary = v["armour"]

	# Header: what it is and what it is for.
	_text(c, Vector2(18, 36), v["name"], 28, GOLD)
	var name_w := font.get_string_size(v["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var chip := "%s  -  %s" % [String(role["name"]).to_upper(), String(v["class"]).to_upper()]
	var chip_w := font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18.0
	c.draw_rect(Rect2(30 + name_w, 16, chip_w, 24), Color(role_col, 0.28))
	c.draw_rect(Rect2(30 + name_w, 16, chip_w, 24), role_col, false, 1.0)
	_text(c, Vector2(39 + name_w, 33), chip, 13, role_col.lightened(0.3))
	_text(c, Vector2(18, 60), v["description"], 15, Color(0.86, 0.86, 0.86))

	# Ability, boxed on the right of the header so it is never missed.
	var ax := w * 0.6
	c.draw_rect(Rect2(ax, 10, w - ax - 12, 62), Color(GOLD, 0.1))
	c.draw_rect(Rect2(ax, 10, w - ax - 12, 62), Color(GOLD, 0.6), false, 1.0)
	_text(c, Vector2(ax + 10, 30), "ABILITY  [%s]   %s" % [Settings.binding_text("ability"), ab["name"]], 15, GOLD)
	var cd := "every %d s" % int(ab["cooldown"])
	_text(c, Vector2(w - 22 - font.get_string_size(cd, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 30), cd, 12, GREY)
	c.draw_multiline_string(font, Vector2(ax + 10, 48), ab["description"], HORIZONTAL_ALIGNMENT_LEFT, w - ax - 32, 13, 2, Color(0.92, 0.92, 0.92))

	var top := 84.0
	c.draw_line(Vector2(12, top - 6), Vector2(w - 12, top - 6), Color(1, 1, 1, 0.12), 1.0)
	var col_w := (w - 36.0) / 3.0
	var x1 := 18.0
	var x2 := x1 + col_w + 6.0
	var x3 := x2 + col_w + 6.0

	# PROTECTION: a plan view of the vehicle, nose to the right like the map, each plate
	# drawn in a colour from red (thin) to green (thick) with its thickness beside it.
	_text(c, Vector2(x1, top + 16), "PROTECTION", 15, GOLD)
	var hull := Rect2(x1 + 84, top + 52, 150, 66)
	c.draw_rect(hull, Color(1, 1, 1, 0.06))
	c.draw_line(hull.position + Vector2(hull.size.x, 0), hull.end, _armour_colour(a["hull_front"]), 6.0)
	c.draw_line(hull.position, hull.position + Vector2(hull.size.x, 0), _armour_colour(a["hull_side"]), 6.0)
	c.draw_line(hull.position + Vector2(0, hull.size.y), hull.end, _armour_colour(a["hull_side"]), 6.0)
	c.draw_line(hull.position, hull.position + Vector2(0, hull.size.y), _armour_colour(a["hull_rear"]), 6.0)
	var tc := hull.get_center() + Vector2(8, 0)
	c.draw_arc(tc, 22.0, -1.2, 1.2, 14, _armour_colour(a["turret_front"]), 5.0)
	c.draw_arc(tc, 22.0, 1.2, TAU - 1.2, 20, _armour_colour(a["turret_side"]), 5.0)
	c.draw_line(tc + Vector2(20, 0), tc + Vector2(92, 0), Color(0.75, 0.75, 0.75), 3.0)
	_text(c, Vector2(hull.end.x + 26, hull.get_center().y - 8), "FRONT", 11, GREY)
	_text(c, Vector2(hull.end.x + 26, hull.get_center().y + 12), "%d mm" % int(a["hull_front"]), 16, _armour_colour(a["hull_front"]))
	_text_mid(c, Vector2(hull.get_center().x, hull.position.y - 10), "SIDE  %d mm" % int(a["hull_side"]), 14, _armour_colour(a["hull_side"]))
	_text(c, Vector2(x1, hull.get_center().y - 8), "REAR", 11, GREY)
	_text(c, Vector2(x1, hull.get_center().y + 12), "%d mm" % int(a["hull_rear"]), 16, _armour_colour(a["hull_rear"]))
	_text_mid(c, Vector2(hull.get_center().x, hull.end.y + 22), "TURRET  front %d mm   side %d mm" % [int(a["turret_front"]), int(a["turret_side"])], 13, _armour_colour(a["turret_front"]))
	_stat(c, Vector2(x1, top + 162), col_w, "Health", v["hp"], best["hp"], str(int(v["hp"])), Color(0.4, 0.85, 0.45))

	# FIREPOWER: the gun, then each shell it carries with what it does.
	_text(c, Vector2(x2, top + 16), "FIREPOWER", 15, GOLD)
	var reload_s := float(v["reload"]) * float(Settings.rules["reload"])
	var gun := "%d mm gun%s" % [int(v["gun_calibre"]), "s (twin)" if int(v["barrels"]) > 1 else ""]
	_text(c, Vector2(x2 + 108, top + 16), gun, 13, GREY)
	_stat(c, Vector2(x2, top + 30), col_w, "Rate of fire", 60.0 / float(v["reload"]), best["rate"], "%.1f s reload" % reload_s, Color(0.95, 0.7, 0.3))
	var sy := top + 58.0
	var number := 1
	for sid in v["shells"]:
		var s: Dictionary = GameData.shells[sid]
		var kind := {"AP": "armour piercing", "HEAT": "shaped charge - no loss with range", "HE": "high explosive"}[String(s["type"])] as String
		_text(c, Vector2(x2, sy + 12), "[%d]  %s" % [number, s["name"]], 14)
		_text(c, Vector2(x2 + 150, sy + 12), kind + ("  -  %s m blast" % str(s["splash_radius"]) if float(s["splash_radius"]) > 0.0 else ""), 11, GREY)
		_stat(c, Vector2(x2, sy + 18), col_w, "Penetration", s["pen"], best["pen"], "%d mm" % int(s["pen"]), Color(0.45, 0.72, 1.0))
		_stat(c, Vector2(x2, sy + 36), col_w, "Damage", s["damage"], best["damage"], str(int(s["damage"])), Color(1.0, 0.5, 0.4))
		sy += 62.0
		number += 1
	var mg: Dictionary = GameData.shells[v["mg"]]
	_text(c, Vector2(x2, sy + 12), "[%s]  %s  -  for infantry and thin armour (%d mm)" % [Settings.binding_text("machine_gun"), mg["name"], int(mg["pen"])], 12, GREY)

	# MOBILITY.
	_text(c, Vector2(x3, top + 16), "MOBILITY", 15, GOLD)
	_stat(c, Vector2(x3, top + 30), col_w, "Top speed", v["speed_fwd"], best["speed"], "%d km/h" % int(v["speed_fwd"]), Color(0.5, 0.9, 0.6))
	_stat(c, Vector2(x3, top + 52), col_w, "Reverse", v["speed_rev"], best["reverse"], "%d km/h" % int(v["speed_rev"]), Color(0.5, 0.9, 0.6))
	_stat(c, Vector2(x3, top + 74), col_w, "Hull turning", v["turn_rate"], best["turn"], "%d deg/s" % int(v["turn_rate"]), Color(0.5, 0.9, 0.6))
	if float(v["traverse_limit"]) < 90.0:
		_text(c, Vector2(x3, top + 108), "NO TURRET", 14, Color(1.0, 0.6, 0.4))
		_text(c, Vector2(x3, top + 126), "The gun swings only %d degrees each side:" % int(v["traverse_limit"]), 12, GREY)
		_text(c, Vector2(x3, top + 142), "turn the whole vehicle to aim.", 12, GREY)
	else:
		_stat(c, Vector2(x3, top + 96), col_w, "Turret turning", v["turret_traverse"], best["traverse"], "%d deg/s" % int(v["turret_traverse"]), Color(0.5, 0.9, 0.6))
	_text(c, Vector2(x3, top + 176), "Gun elevation  %d to +%d degrees" % [int(v["elev_min"]), int(v["elev_max"])], 12, GREY)
	_text(c, Vector2(x3, top + 194), "Bars compare with the best vehicle in the roster.", 11, Color(1, 1, 1, 0.45))


# ---- the deploy button ----
var _dep_big := "DEPLOY"
var _dep_small := ""
var _dep_wait := 0.0

# Green when you can go, red with a countdown when you cannot yet. A white frame with corner
# marks, the fine horizontal lines of a camcorder picture, and a pale band drifting down it.
func _draw_deploy() -> void:
	var r := Rect2(Vector2.ZERO, deploy.size)
	var ready := not deploy.disabled
	var base := Color(0.1, 0.46, 0.18) if ready else (Color(0.5, 0.11, 0.1) if _dep_wait > 0.0 else Color(0.2, 0.22, 0.2))
	if ready and deploy.is_hovered():
		base = base.lightened(0.14)
	if ready and deploy.button_pressed:
		base = base.darkened(0.15)
	deploy.draw_rect(r, base)
	for y in range(0, int(r.size.y), 3):
		deploy.draw_line(Vector2(0, y), Vector2(r.size.x, y), Color(0, 0, 0, 0.17), 1.0)
	var band := fposmod(_t * 42.0, r.size.y + 40.0) - 20.0
	deploy.draw_rect(Rect2(0, band, r.size.x, 14.0).intersection(r), Color(1, 1, 1, 0.09))
	deploy.draw_rect(Rect2(0, band + 5.0, r.size.x, 2.0).intersection(r), Color(1, 1, 1, 0.12))
	var white := Color(1, 1, 1, 0.92 if ready else 0.6)
	deploy.draw_rect(r.grow(-4.0), white, false, 2.0)
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var at := Vector2(9.0 + corner.x * (r.size.x - 18.0), 9.0 + corner.y * (r.size.y - 18.0))
		var inward := Vector2(1.0 - corner.x * 2.0, 1.0 - corner.y * 2.0)
		deploy.draw_line(at, at + Vector2(inward.x * 14.0, 0), white, 3.0)
		deploy.draw_line(at, at + Vector2(0, inward.y * 14.0), white, 3.0)
	var big_px := 34
	var wide := font.get_string_size(_dep_big, HORIZONTAL_ALIGNMENT_LEFT, -1, big_px).x
	_text(deploy, Vector2((r.size.x - wide) * 0.5, r.size.y * 0.5 + 6.0), _dep_big, big_px, white)
	var small_wide := font.get_string_size(_dep_small, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_text(deploy, Vector2((r.size.x - small_wide) * 0.5, r.size.y - 13.0), _dep_small, 12, Color(1, 1, 1, 0.8))


# ---- the pylons of the chosen aircraft ----

func _air_loadout(id: String) -> Array:
	if not air_loadouts.has(id):
		air_loadouts[id] = (Aircraft.sheet[id]["loadout"] as Array).duplicate()
	return air_loadouts[id]


# Takes a fresh front-view picture of the chosen aircraft with what it now carries.
func _rack_refresh() -> void:
	if not selected.begins_with("air:"):
		return
	var id := selected.trim_prefix("air:")
	if _rack_vp != null and is_instance_valid(_rack_vp):
		_rack_vp.queue_free()
	# Wide enough to get the outermost pylon in, and no wider. (_rack_dist is half the width shown, metres.)
	var widest := 3.0
	for p in AircraftModel.pylon_points(id, int(Aircraft.sheet[id]["pylons"])):
		widest = maxf(widest, absf(p.x))
	_rack_dist = widest + 1.6
	# A plain drawing of it from dead ahead: everything white with a black edge, and no
	# perspective, so the nose cannot hide what is under the wings.
	var model: Node3D = AircraftModel.build(id, main.TEAM_COLORS[0], _air_loadout(id))["root"]
	var edge := StandardMaterial3D.new()
	edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge.albedo_color = Color(0.03, 0.03, 0.03)
	edge.cull_mode = BaseMaterial3D.CULL_FRONT
	edge.grow = true
	edge.grow_amount = 0.045
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.95, 0.96, 0.94)
	paper.roughness = 1.0
	paper.next_pass = edge
	for part in model.find_children("*", "MeshInstance3D", true, false):
		part.material_override = paper
	var vp := SubViewport.new()
	vp.size = Vector2i(int(RACK_SIZE.x) * 2, int(RACK_SIZE.y) * 2)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	vp.add_child(model)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.74, 0.78)
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-55, 160, 0)  # from above and in front: undersides and recesses go grey
	lamp.light_energy = 0.6
	vp.add_child(lamp)
	var cam := Camera3D.new()
	cam.environment = env
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = _rack_dist * 2.0 * RACK_SIZE.y / RACK_SIZE.x  # the height shown, metres
	vp.add_child(cam)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0, 1)), Vector3(0, 1.7, -80.0))
	_rack_tex = vp.get_texture()
	_rack_vp = vp
	air_opts.queue_redraw()


# Where each pylon's box goes on the picture. (The picture has no perspective: it shows
# _rack_dist metres either side of the middle, whatever the distance.)
func _rack_boxes() -> Array:
	var out: Array = []
	if not selected.begins_with("air:"):
		return out
	var id := selected.trim_prefix("air:")
	for p in AircraftModel.pylon_points(id, int(Aircraft.sheet[id]["pylons"])):
		var across: float = -p.x / _rack_dist
		var up: float = (p.y - 0.3 - 1.7) / (_rack_dist * RACK_SIZE.y / RACK_SIZE.x)
		var c := Vector2(RACK_SIZE.x * 0.5 * (1.0 + across), RACK_SIZE.y * 0.5 * (1.0 - up))
		out.append(Rect2(c - Vector2(12, 15), Vector2(24, 30)))
	return out


func _draw_rack() -> void:
	if _rack_tex == null or not selected.begins_with("air:"):
		return
	var id := selected.trim_prefix("air:")
	air_opts.draw_rect(Rect2(Vector2.ZERO, RACK_SIZE), Color(0.13, 0.2, 0.3))  # drawing-board blue, so the black edges show
	for gx in range(0, int(RACK_SIZE.x), 22):
		air_opts.draw_line(Vector2(gx, 0), Vector2(gx, RACK_SIZE.y), Color(1, 1, 1, 0.05), 1.0)
	for gy in range(0, int(RACK_SIZE.y), 22):
		air_opts.draw_line(Vector2(0, gy), Vector2(RACK_SIZE.x, gy), Color(1, 1, 1, 0.05), 1.0)
	air_opts.draw_texture_rect(_rack_tex, Rect2(Vector2.ZERO, RACK_SIZE), false)
	var carried := _air_loadout(id)
	var boxes := _rack_boxes()
	for i in boxes.size():
		var box: Rect2 = boxes[i]
		var green := Color(0.35, 1.0, 0.45, 1.0 if i == _rack_hover else 0.75)
		air_opts.draw_rect(box, green, false, 2.0 if i == _rack_hover else 1.2)
		# What is on it, written under the box (every other one a line lower, so they do not run together).
		var word: String = Ordnance.INFO[carried[i]]["short"]
		var wide := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_text(air_opts, Vector2(box.get_center().x - wide * 0.5, box.end.y + 11.0 + (10.0 if i % 2 == 1 else 0.0)), word, 10, green)


func _rack_input(e: InputEvent) -> void:
	if not selected.begins_with("air:"):
		return
	var boxes := _rack_boxes()
	if e is InputEventMouseMotion:
		var over := -1
		for i in boxes.size():
			if (boxes[i] as Rect2).grow(3.0).has_point(e.position):
				over = i
		if over != _rack_hover:
			_rack_hover = over
			air_opts.queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _rack_hover >= 0:
		# A list of what this pylon may carry.
		_rack_pylon = _rack_hover
		var row: Dictionary = Aircraft.sheet[selected.trim_prefix("air:")]
		_rack_menu.clear()
		var choices := Aircraft.allowed_on(row, _rack_pylon)
		for k in choices.size():
			_rack_menu.add_item(String(Ordnance.INFO[choices[k]]["name"]), k)
		_rack_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


func _rack_chosen(which: int) -> void:
	if _rack_pylon < 0 or not selected.begins_with("air:"):
		return
	var id := selected.trim_prefix("air:")
	var choices := Aircraft.allowed_on(Aircraft.sheet[id], _rack_pylon)
	_air_loadout(id)[_rack_pylon] = choices[which]
	_rack_refresh()
	detail.queue_redraw()


# A picture of a model, taken once in a little studio of its own.
func _picture(model: Node3D, eye: Vector3, aim: Vector3) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(384, 208)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	vp.add_child(model)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 150, 0)
	vp.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	var cam := Camera3D.new()
	cam.environment = env
	cam.fov = 30.0
	vp.add_child(cam)
	cam.transform = Transform3D(Basis.looking_at(aim - eye), eye)
	return vp.get_texture()


# A card with a picture, a name and a line under it (aircraft use these).
func _plain_card(key: String, title: String, sub: String, picture: Texture2D) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD
	b.toggle_mode = true
	b.clip_contents = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _select(key))
	var pic := TextureRect.new()
	pic.texture = picture
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.position = Vector2(8, 2)
	pic.size = Vector2(CARD.x - 12, CARD.y - 40)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	var name_label := _label(b, title, 15)
	name_label.position = Vector2(12, CARD.y - 40)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub_label := _label(b, sub, 12, GREY)
	sub_label.position = Vector2(12, CARD.y - 21)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards[key] = b
	return b


# A small model of a piece of kit, for its picture: a few boxes and tubes.
func _kit_model(kind: String) -> Node3D:
	var n := Node3D.new()
	var steel := MeshUtil.material(Color(0.2, 0.2, 0.21), 0.6)
	var wood := MeshUtil.material(Color(0.42, 0.3, 0.18), 0.8)
	var olive := MeshUtil.material(Color(0.3, 0.34, 0.24), 0.8)
	match kind:
		"rifle", "carbine", "lmg", "pistol", "launcher":
			# The same models the soldiers carry (WeaponModel), turned to point the way these pictures expect.
			var piece := WeaponModel.build("machine_gun" if kind == "lmg" else kind, Settings.inf_sight)
			piece.rotation.y = PI
			n.add_child(piece)
		"medkit":
			MeshUtil.box(n, Vector3(0.3, 0.2, 0.12), Vector3.ZERO, MeshUtil.material(Color(0.92, 0.92, 0.88), 0.7))
			var red := MeshUtil.material(Color(0.8, 0.1, 0.1), 0.7)
			MeshUtil.box(n, Vector3(0.12, 0.04, 0.01), Vector3(0, 0, -0.065), red)
			MeshUtil.box(n, Vector3(0.04, 0.12, 0.01), Vector3(0, 0, -0.065), red)
		"toolbox":
			MeshUtil.box(n, Vector3(0.36, 0.16, 0.16), Vector3.ZERO, MeshUtil.material(Color(0.6, 0.18, 0.14), 0.7))
			MeshUtil.box(n, Vector3(0.16, 0.03, 0.03), Vector3(0, 0.12, 0), steel)
		"pouch":
			MeshUtil.box(n, Vector3(0.2, 0.16, 0.08), Vector3.ZERO, MeshUtil.material(Color(0.5, 0.46, 0.32), 0.9))
			MeshUtil.box(n, Vector3(0.21, 0.05, 0.085), Vector3(0, 0.07, 0), olive)
		"frag":
			MeshUtil.cylinder(n, 0.05, 0.1, Vector3.ZERO, olive)
			MeshUtil.cylinder(n, 0.02, 0.05, Vector3(0, 0.07, 0), steel)
		"smoke":
			MeshUtil.cylinder(n, 0.04, 0.14, Vector3.ZERO, MeshUtil.material(Color(0.7, 0.7, 0.68), 0.6))
			MeshUtil.cylinder(n, 0.02, 0.04, Vector3(0, 0.09, 0), steel)
		"mine":
			MeshUtil.cylinder(n, 0.16, 0.06, Vector3.ZERO, olive)
			MeshUtil.cylinder(n, 0.05, 0.03, Vector3(0, 0.04, 0), steel)
	return n


# The chosen class's kit: four boxes, each with a picture of the thing and what it is for.
func _draw_kit(c: Control, w: float, h: float) -> void:
	var id := selected.trim_prefix("inf:")
	var who: Dictionary = GameData.infantry[id]
	_text(c, Vector2(22, 34), String(who["name"]).to_upper(), 26, GOLD)
	_text(c, Vector2(22, 58), String(Soldier.ABOUT.get(id, "")), 14, GREY)
	var titles := ["PRIMARY", "SIDE ARM", "CLASS TOOL", "THROWN"]
	var kit: Array = KITS.get(id, KITS["assault"])
	var bw := (w - 44.0 - 3.0 * 12.0) / 4.0
	for i in 4:
		var box := Rect2(22 + i * (bw + 12.0), 78, bw, h - 100.0)
		c.draw_rect(box, Color(1, 1, 1, 0.05))
		c.draw_rect(box, Color(1, 1, 1, 0.16), false, 1.0)
		_text(c, box.position + Vector2(10, 20), titles[i], 13, GOLD)
		var kind: String = kit[i][0]
		var sighted: bool = i == 0 and (kind == "rifle" or kind == "carbine")
		var pic_key: String = kind + (Settings.inf_sight if sighted else "")
		if sighted:
			# The rifle's sight: written here, and changed by clicking the box.
			_text(c, Vector2(box.position.x + 10, box.end.y - 26), "Sight: " + String(WeaponModel.SIGHT_NAMES[Settings.inf_sight]), 13, GOLD)
			_text(c, Vector2(box.position.x + 10, box.end.y - 10), "click to change", 11, GREY)
		if not _kit_pics.has(pic_key):
			var small: bool = ["rifle", "carbine", "lmg", "launcher"].find(kind) < 0
			_kit_pics[pic_key] = _picture(_kit_model(kind), Vector3(1.5, 0.5, -0.9) * (0.38 if small else 1.0) + Vector3(0, 0, -0.2 if not small else 0.0), Vector3(0, -0.02, -0.2 if not small else 0.0))
		c.draw_texture_rect(_kit_pics[pic_key], Rect2(box.position + Vector2(6, 26), Vector2(bw - 12.0, (bw - 12.0) * 208.0 / 384.0)), false)
		var y := box.position.y + 40.0 + (bw - 12.0) * 208.0 / 384.0
		_text(c, Vector2(box.position.x + 10, y), kit[i][1], 15)
		# The note, wrapped to the box.
		var words: PackedStringArray = String(kit[i][2]).split(" ")
		var line := ""
		for word in words:
			if font.get_string_size(line + word, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > bw - 20.0:
				y += 16.0
				_text(c, Vector2(box.position.x + 10, y), line, 12, GREY)
				line = ""
			line += word + " "
		_text(c, Vector2(box.position.x + 10, y + 16.0), line, 12, GREY)


# The chosen aircraft's card: what it is, how it flies, and (below, as two menus) its pylons.
func _draw_air_card(c: Control, w: float, _h: float) -> void:
	var a: Dictionary = Aircraft.sheet[selected.trim_prefix("air:")]
	var heli: bool = a["kind"] == "heli"
	_text(c, Vector2(22, 34), String(a["name"]), 26, GOLD)
	_text(c, Vector2(22, 58), String(a["about"]), 14, GREY)
	var col_w := w * 0.42
	_stat(c, Vector2(22, 84), col_w, "Top speed", float(a["speed"]), 150.0, "%d km/h" % int(float(a["speed"]) * 3.6), Color(0.5, 0.9, 0.55))
	_stat(c, Vector2(22, 112), col_w, "Turning", float(a["turn"]), 2.2, "%d deg/s" % int(rad_to_deg(float(a["turn"]))), Color(0.5, 0.9, 0.55))
	_stat(c, Vector2(22, 140), col_w, "Toughness", float(a["hp"]), 620.0, str(int(a["hp"])), Color(0.5, 0.9, 0.55))
	var x2 := w * 0.52
	_stat(c, Vector2(x2, 84), col_w, "Guns", float(a["gun_damage"]) / float(a["gun_gap"]), 320.0, "%d a second" % int(float(a["gun_damage"]) / float(a["gun_gap"])), Color(1.0, 0.55, 0.4))
	_stat(c, Vector2(x2, 112), col_w, "Rocket punch", float(a["rocket_pen"]), 240.0, "%d mm" % int(a["rocket_pen"]), Color(0.45, 0.72, 1.0))
	# What it carries now, and what that costs in speed.
	var carried := _air_loadout(String(a["id"]))
	var weight := 0.0
	var tally := {"rockets": 0, "bombs": 0, "missiles": 0}
	for kind in carried:
		var info: Dictionary = Ordnance.INFO[kind]
		weight += float(info["weight"])
		tally["rockets"] += int(info.get("rockets", 0))
		tally["missiles"] += int(info.get("missiles", 0))
		tally["bombs"] += 1 if info.has("bomb") else 0
	var nx := 22.0 + RACK_SIZE.x + 22.0
	_text(c, Vector2(nx, 176), "PYLONS  -  click a green box to change what hangs there", 15, GOLD)
	_text(c, Vector2(nx, 200), "Carrying: %d rockets, %d bombs, %d missiles.   Top speed with this load: %d km/h" % [tally["rockets"], tally["bombs"], tally["missiles"], int(float(a["speed"]) * (1.0 - Ordnance.SLOW_PER_WEIGHT * weight) * 3.6)], 13)
	_text(c, Vector2(nx, 222), "A 16-rocket pod holds twice as much as an 8 but weighs more than twice as much.", 13, GREY)
	_text(c, Vector2(nx, 240), "Bombs: 100 kg small burst, 500 kg large, 1000 kg enormous (inner pylons only).", 13, GREY)
	if int(tally["missiles"]) > 0 or (a["stores"] as Array).has("aam"):
		_text(c, Vector2(nx, 258), "Missiles are for aircraft: hold the sight button on one until the tone, then fire.", 13, GREY)
	_text(c, Vector2(nx, 284), "Helicopters start on the airstrip and can land to capture." if heli else "Planes start in the air. Stop on your own airstrip to rearm.", 13, GREY)
	_text(c, Vector2(nx, 302), "Flares (%d) throw off a missile that is following you." % int(a.get("flares", 2)), 13, GREY)


func _process(delta: float) -> void:
	if _t == 0.0:
		for a in main.args:
			if a.begins_with("--spawnpick="):
				_select.call_deferred(a.trim_prefix("--spawnpick="))
				for tab in left_tabs:
					left_tabs[tab].visible = (tab == "AIR") == a.contains("air:") and (tab == "INFANTRY") == a.contains("inf:")
	if _man_model != null and is_instance_valid(_man_model) and root.visible:
		_man_model.rotation.y += delta * 0.7
		_man_model.pose(delta)
	var pc: PlayerCtrl = main.player_ctrl
	var open: bool = main.state == "playing" and not main.match_over and not pc.auto and not pc.has_tank() and pc.phase != "killcam" and pc.phase != "redeploy" and not main.player_slot["ready"]
	if open and not root.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	root.visible = open
	if not open:
		return
	_t += delta
	map_view.queue_redraw()
	detail.queue_redraw()
	var wait := float(main.player_slot["respawn_t"])
	if main.prep_t > 0.0:
		status.text = "Battle begins in %d s" % int(ceil(main.prep_t))
		status.add_theme_color_override("font_color", GOLD)
	elif wait > 0.0:
		status.text = "You can deploy in %d s" % int(ceil(wait))
		status.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	else:
		status.text = "Ready to deploy"
		status.add_theme_color_override("font_color", Color(0.5, 0.95, 0.55))
	# Aircraft wait for the round to start, and for a while after the last one was lost.
	var air_wait: float = maxf(main.prep_t, main.air_ready_at - main.elapsed) if selected.begins_with("air:") else 0.0
	_dep_wait = maxf(wait, air_wait)
	if selected == "":
		_dep_big = "DEPLOY"
		_dep_small = "choose what to be first"
		deploy.disabled = true
	elif _dep_wait > 0.0:
		_dep_big = "%d" % int(ceil(_dep_wait))
		_dep_small = "aircraft take off when the battle begins" if (air_wait > 0.0 and main.prep_t > 0.0) else ("next aircraft ready in" if air_wait > wait else "you can deploy in")
		deploy.disabled = true
	else:
		_dep_big = "DEPLOY"
		_dep_small = "at %s  -  Enter" % LANE_LETTER[lane] if not selected.begins_with("air:") else "Enter"
		if GameData.vehicles.has(selected):
			_dep_small += "  -  loadout %d (keys 1 to 5)" % (int(Profile.active.get(selected, 0)) + 1)
		deploy.disabled = false
	deploy.queue_redraw()


func _unhandled_key_input(e: InputEvent) -> void:
	# While choosing where to deploy, the number keys pick which of the vehicle's five loadouts to take.
	if root.visible and selected != "" and e is InputEventKey and e.pressed and not e.echo and e.keycode >= KEY_1 and e.keycode <= KEY_5:
		Profile.active[selected] = e.keycode - KEY_1
		Profile.save()


func _unhandled_input(e: InputEvent) -> void:
	if root.visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ENTER and not main.match_over:
		_deploy()
