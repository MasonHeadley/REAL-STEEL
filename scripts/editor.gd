extends Node3D
# The map editor. It works on one custom map (see map_file.gd): shaping the ground, laying
# roads, and placing buildings, loose objects, the three domination points and the two
# teams' starting places. main.gd starts it in place of a match when Settings.edit_map is set.
#
# Flying:   W A S D, Q down, E up, Shift faster; hold the right mouse button to look about.
# Tools:    click one on the left (or press its number). Left click on the ground uses it.
# Keys:     [ ] brush or building size   R turn   F floors   T next kind / object / point
#           Enter finish a road   Backspace undo the last road point (or the last road)
#           Ctrl+S save   Esc save and go back to the menu

const TOOLS := [["raise", "Raise ground"], ["lower", "Lower ground"], ["flatten", "Flatten"], ["smooth", "Smooth"], ["road", "Road"],
	["building", "Building"], ["object", "Object"], ["point", "Domination point"], ["spawn", "Team start"], ["erase", "Erase"],
	["tree", "Tree"], ["forest", "Forest brush"]]  # the second ten are on Alt + number
const KINDS := ["house", "shop", "tower"]

var main
var map: PushMap
var plan: Dictionary
var cam := Camera3D.new()
var yaw := 0.0
var pitch := -0.7
var tool := "raise"
var radius := 30.0        # the ground brush, metres
var size := 14.0          # a building's width, metres
var turn := 0.0
var floors := 2
var kind := 0             # which of KINDS a new building is
var object_i := 0         # which of Prefabs.LIST a new object is
var point_i := 0          # which domination point, or which team's start, is being placed
var _draft: Array = []    # the road being drawn
var _road_nodes: Array = []
var _markers: Array = []
var _level := 0.0         # the height "flatten" is working to
var _remesh_t := 0.0
var _dirty := false
var _ring := MeshInstance3D.new()
var _status: Label
var _buttons := {}
var tree_kind := 0        # 0 pine, 1 round
var _forest_t := 0.0
var _ghost: Node3D        # a see-through copy of what a click would place, under the mouse
var _ghost_key := ""


func _ready() -> void:
	map = main.map
	plan = map.plan
	add_child(cam)
	cam.far = 4000.0
	cam.global_position = Vector3(0, 140, 190)
	cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Clear air and plain colour while editing, whatever the graphics settings say.
	main._env.fog_enabled = false
	main._env.adjustment_enabled = false
	var hoop := TorusMesh.new()
	hoop.inner_radius = 0.94
	hoop.outer_radius = 1.0
	_ring.mesh = hoop
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color(1, 0.85, 0.3)
	paint.no_depth_test = true
	_ring.material_override = paint
	add_child(_ring)
	# The tools, down the left; what is going on, along the bottom.
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(14, 14)
	panel.add_theme_constant_override("separation", 3)
	layer.add_child(panel)
	for i in TOOLS.size():
		var b := Button.new()
		b.text = "%s%d  %s" % ["Alt+" if i >= 10 else "", (i + 1) % 10, TOOLS[i][1]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(210, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.pressed.connect(_pick.bind(TOOLS[i][0]))
		panel.add_child(b)
		_buttons[TOOLS[i][0]] = b
	for extra in [["SAVE  (Ctrl+S)", _save], ["NEW 800 m MAP", _new.bind(800.0)], ["NEW 1200 m MAP", _new.bind(1200.0)], ["NEW 1600 m MAP", _new.bind(1600.0)], ["SAVE AND LEAVE  (Esc)", _leave]]:
		var b := Button.new()
		b.text = extra[0]
		b.custom_minimum_size = Vector2(210, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(extra[1])
		panel.add_child(b)
	_status = Label.new()
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -74.0
	_status.offset_left = 14.0
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 5)
	layer.add_child(_status)
	_pick("raise")
	_redraw_roads()
	_redraw_markers()
	if main.args.has("--edittest"):
		_test.call_deferred()


# A test: uses every tool once, saves, and takes a picture (--editmap=<name> --edittest --shot=<file>).
func _test() -> void:
	await get_tree().create_timer(1.0).timeout
	radius = 70.0
	tool = "raise"
	for i in 40:
		_shape(Vector3(260, 0, -200), 0.1)
		_shape(Vector3(-280, 0, 240), 0.1)
	map.reshape()
	plan["roads"] = [[[-400, 0], [-100, 60], [100, -60], [400, 0]], [[0, -450], [0, 450]]]
	_redraw_roads()
	tool = "building"
	for i in 8:
		kind = i % 3
		_click(Vector3(-160 + i * 45.0, 0, 40.0 if i % 2 == 0 else -40.0))
	tool = "object"
	for i in Prefabs.LIST.size():
		object_i = i
		_click(Vector3(14.0, 0, -200.0 + i * 24.0))
	tool = "tree"
	for i in 12:
		tree_kind = i % 2
		_click(Vector3(-200.0 + i * 12.0, 0, 150.0))
	tool = "point"
	for i in 3:
		point_i = i
		_click(Vector3((i - 1) * 220.0, 0, (i - 1) * 60.0))
	tool = "spawn"
	for i in 2:
		point_i = i
		_click(Vector3(0, 0, (i * 2 - 1) * 400.0))
	_save()
	print("EDITTEST saved %d buildings %d items %d roads %d heights" % [plan["buildings"].size(), plan["items"].size(), plan["roads"].size(), plan["heights"].size()])
	await get_tree().create_timer(1.0).timeout
	main._save_shot(main.shot_path)


func _pick(id: String) -> void:
	tool = id
	_draft = []
	for k in _buttons:
		_buttons[k].button_pressed = k == id
	_redraw_roads()


# The place on the ground under the mouse, or null if it is over the sky.
func _spot():
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(mouse) * 4000.0, 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else null


func _process(delta: float) -> void:
	# Flying.
	var look := Basis.from_euler(Vector3(pitch, yaw, 0))
	if not Input.is_physical_key_pressed(KEY_CTRL):
		var move := Vector3(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		cam.global_position += look * move * (260.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 80.0) * delta
	cam.global_transform = Transform3D(look, cam.global_position)
	var at = _spot()
	var shaping := ["raise", "lower", "flatten", "smooth"].has(tool)
	if tool == "forest":
		shaping = false
	_ring.visible = at != null
	if at != null:
		var r := radius if (shaping or tool == "forest") else (size * 0.6 if tool == "building" else 3.0)
		_ring.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(r, 2.0, r)), at + Vector3(0, 0.4, 0))
	_show_ghost(at)
	if tool == "road" and not _draft.is_empty():
		_redraw_roads()
	# The forest brush plants a tree somewhere in its circle several times a second while held.
	_forest_t -= delta
	if tool == "forest" and at != null and _forest_t <= 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().gui_get_hovered_control() == null:
		_forest_t = 0.07
		var out := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * radius
		_plant(at.x + out.x, at.z + out.y, randf_range(0.8, 1.4))
	# Shaping the ground goes on for as long as the button is held.
	_remesh_t -= delta
	if shaping and at != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and get_viewport().gui_get_hovered_control() == null:
		_shape(at, delta)
		_dirty = true
	if _dirty and (_remesh_t <= 0.0 or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		_dirty = false
		_remesh_t = 0.2
		map.reshape()
		_redraw_roads()
	var about := {"raise": "hold to raise", "lower": "hold to lower", "flatten": "hold to level to where you first clicked", "smooth": "hold to smooth",
		"road": "click points, Enter to finish (%d so far)" % _draft.size(), "building": "%s, %d floors, %d m  -  T kind, F floors, [ ] size, R turn" % [KINDS[kind], floors, int(size)],
		"object": "%s  -  T next, R turn" % Prefabs.LIST[object_i], "point": "point %s  -  T next" % "ABC"[point_i % 3], "spawn": "%s team  -  T other team" % ["Blue", "Red"][point_i % 2], "erase": "click a building, object, tree or road to remove it",
		"tree": "%s tree  -  T kind, [ ] size" % ["pine", "round"][tree_kind], "forest": "hold to scatter %s trees over the brush  -  T kind" % ["pine", "round"][tree_kind]}
	_status.text = "%s:  %s\nMap \"%s\", %d m square.   W A S D fly, Q E down and up, Shift fast, hold right mouse to look.   [ ] brush %d m.   Ctrl+S save, Esc leave." % [
		tool.to_upper(), about[tool], Settings.edit_map, int(plan["size"]), int(radius)]


func _plant(x: float, z: float, tree_size: float) -> void:
	if not plan.has("trees"):
		plan["trees"] = []
	var entry := [snappedf(x, 0.1), snappedf(z, 0.1), snappedf(tree_size, 0.05), tree_kind]
	plan["trees"].append(entry)
	map.place_tree(entry)


# The ghost: what the next click would place, drawn in see-through green exactly where and
# how it would stand. It is made again whenever the choice (tool, kind, size, turn) changes.
func _show_ghost(at) -> void:
	var key := "%s %d %d %d %.1f %d %d" % [tool, kind, object_i, floors, size, tree_kind, int(at != null)]
	if not ["building", "object", "tree"].has(tool) or at == null:
		key = ""
	if key != _ghost_key:
		_ghost_key = key
		if _ghost != null and is_instance_valid(_ghost):
			_ghost.free()
		_ghost = null
		if key != "":
			_ghost = Node3D.new()
			add_child(_ghost)
			if tool == "building":
				var tall := float(floors + (3 if kind == 2 else 0)) * 3.6 + 0.6
				MeshUtil.box(_ghost, Vector3(size, tall, size * (1.0 if kind == 2 else 1.25)), Vector3(0, tall * 0.5, 0), null)
			elif tool == "object":
				var prop := Prefabs.build(Prefabs.LIST[object_i], RandomNumberGenerator.new())
				prop.collision_layer = 0
				prop.remove_from_group("props")
				_ghost.add_child(prop)
			else:
				var s := clampf(size / 14.0, 0.6, 2.5)
				MeshUtil.cylinder(_ghost, 2.2 * s, 8.0 * s, Vector3(0, 4.0 * s, 0), null, 0.3 * s)
			var green := StandardMaterial3D.new()
			green.albedo_color = Color(0.3, 1.0, 0.4, 0.45)
			green.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			for part in _ghost.find_children("*", "MeshInstance3D", true, false):
				part.material_override = green
	if _ghost != null:
		_ghost.global_position = at
		_ghost.rotation.y = turn if tool != "tree" else 0.0


# One moment of a ground tool at a place: every grid point within the brush is moved,
# most at the middle and less towards the edge.
func _shape(at: Vector3, delta: float) -> void:
	var step := PushMap.STEP
	var cx := int(round((at.x + PushMap.HALF_WIDTH) / step))
	var cz := int(round((at.z + map.half_len) / step))
	var reach := int(ceil(radius / step))
	for iz in range(maxi(cz - reach, 0), mini(cz + reach + 1, map.nz)):
		for ix in range(maxi(cx - reach, 0), mini(cx + reach + 1, map.nx)):
			var d := Vector2(ix - cx, iz - cz).length() * step
			if d > radius:
				continue
			var w := pow(1.0 - d / radius, 2.0)
			var i := iz * map.nx + ix
			var h := map.heights[i]
			match tool:
				"raise":
					h += 14.0 * w * delta
				"lower":
					h -= 14.0 * w * delta
				"flatten":
					h = lerpf(h, _level, minf(1.0, 5.0 * w * delta))
				"smooth":
					var around := 0.0
					for n in [i - 1, i + 1, i - map.nx, i + map.nx]:
						around += map.heights[clampi(n, 0, map.heights.size() - 1)]
					h = lerpf(h, around * 0.25, minf(1.0, 6.0 * w * delta))
			map.heights[i] = clampf(h, -5.0, 80.0)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= e.relative.x * 0.004
		pitch = clampf(pitch - e.relative.y * 0.004, -1.5, 1.2)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var at = _spot()
		if at != null:
			_click(at)
	elif e is InputEventKey and e.pressed and not e.echo:
		_key(e)


func _click(at: Vector3) -> void:
	match tool:
		"flatten":
			_level = at.y
		"road":
			_draft.append([snappedf(at.x, 0.1), snappedf(at.z, 0.1)])
			_redraw_roads()
		"building":
			var entry := [snappedf(at.x, 0.1), snappedf(at.z, 0.1), size, size * (1.0 if kind == 2 else 1.25), floors + (3 if kind == 2 else 0), kind, turn, randi() % 6, randi() % 4]
			plan["buildings"].append(entry)
			map.place_building(entry)
		"object":
			var entry := [Prefabs.LIST[object_i], snappedf(at.x, 0.1), snappedf(at.z, 0.1), turn]
			plan["items"].append(entry)
			map.place_item(entry)
		"tree":
			_plant(at.x, at.z, clampf(size / 14.0, 0.6, 2.5))
		"point":
			while plan["points"].size() < 3:
				plan["points"].append([(plan["points"].size() - 1) * 150.0, 0.0])
			plan["points"][point_i % 3] = [snappedf(at.x, 0.1), snappedf(at.z, 0.1)]
			_redraw_markers()
		"spawn":
			while plan["spawns"].size() < 2:
				plan["spawns"].append([0.0, (plan["spawns"].size() * 2 - 1) * float(plan["size"]) * 0.35])
			plan["spawns"][point_i % 2] = [snappedf(at.x, 0.1), snappedf(at.z, 0.1)]
			_redraw_markers()
		"erase":
			# Whatever was put nearest the click goes, if it is within reach.
			var best := -1
			var best_d := 12.0
			for i in map.made.size():
				var entry: Array = map.made[i][1]
				var where := Vector2(entry[0], entry[1]) if map.made[i][0] != "item" else Vector2(entry[1], entry[2])
				if where.distance_to(Vector2(at.x, at.z)) < best_d:
					best_d = where.distance_to(Vector2(at.x, at.z))
					best = i
			if best >= 0:
				var gone: Array = map.made[best]
				plan[{"building": "buildings", "item": "items", "tree": "trees"}[gone[0]]].erase(gone[1])
				gone[2].queue_free()
				map.made.remove_at(best)
			else:
				# Nothing placed there: a road, if the click is on one.
				for road in plan["roads"]:
					for p in map.curve(road.map(func(c): return Vector2(c[0], c[1]))):
						if p.distance_to(Vector2(at.x, at.z)) < PushMap.ROAD_HALF + 2.0:
							plan["roads"].erase(road)
							_redraw_roads()
							return


func _key(e: InputEventKey) -> void:
	if e.keycode == KEY_S and e.ctrl_pressed:
		_save()
	elif e.keycode == KEY_ESCAPE:
		_leave()
	elif e.keycode >= KEY_0 and e.keycode <= KEY_9:
		# The number keys pick the first ten tools; with Alt held, the next ten.
		var n: int = (e.keycode - KEY_1 + 10) % 10 + (10 if e.alt_pressed else 0)
		if n < TOOLS.size():
			_pick(TOOLS[n][0])
	elif e.keycode == KEY_BRACKETLEFT or e.keycode == KEY_BRACKETRIGHT:
		var up := e.keycode == KEY_BRACKETRIGHT
		if tool == "building":
			size = clampf(size + (2.0 if up else -2.0), 8.0, 60.0)
		else:
			radius = clampf(radius * (1.25 if up else 0.8), 8.0, 200.0)
	elif e.keycode == KEY_R:
		turn = fposmod(turn + PI / 12.0, TAU)
	elif e.keycode == KEY_F:
		floors = floors % 6 + 1
	elif e.keycode == KEY_T:
		tree_kind = 1 - tree_kind if (tool == "tree" or tool == "forest") else tree_kind
		kind = (kind + 1) % KINDS.size() if tool == "building" else kind
		object_i = (object_i + 1) % Prefabs.LIST.size() if tool == "object" else object_i
		point_i += 1 if (tool == "point" or tool == "spawn") else 0
	elif e.keycode == KEY_ENTER and tool == "road" and _draft.size() >= 2:
		plan["roads"].append(_draft)
		_draft = []
		_redraw_roads()
	elif e.keycode == KEY_BACKSPACE and tool == "road":
		if not _draft.is_empty():
			_draft.pop_back()
		elif not plan["roads"].is_empty():
			plan["roads"].pop_back()
		_redraw_roads()


# Lays every road again, the one being drawn included, on the ground as it now is.
func _redraw_roads() -> void:
	for n in _road_nodes:
		if is_instance_valid(n):
			n.free()
	_road_nodes = []
	var lines: Array = []
	# (The road being drawn is shown as far as the mouse, so its curve can be seen before the click.)
	var drawing: Array = _draft.duplicate()
	var tip = _spot() if (tool == "road" and not _draft.is_empty() and cam.is_inside_tree()) else null
	if tip != null:
		drawing.append([tip.x, tip.z])
	for road in plan["roads"] + ([drawing] if drawing.size() >= 2 else []):
		lines.append(map.curve(road.map(func(p): return Vector2(p[0], p[1]))))
	if lines.is_empty():
		return
	var first := map.get_child_count()
	map._road(lines, Color(0.36, 0.35, 0.34))
	for i in range(first, map.get_child_count()):
		_road_nodes.append(map.get_child(i))


# A post for each domination point (white) and each team's start (in its colour).
func _redraw_markers() -> void:
	for n in _markers:
		n.queue_free()
	_markers = []
	var posts: Array = []
	for i in plan["points"].size():
		posts.append([plan["points"][i], Color.WHITE, "ABC"[i]])
	for i in plan["spawns"].size():
		posts.append([plan["spawns"][i], main.TEAM_COLORS[i], ["BLUE START", "RED START"][i]])
	for post in posts:
		var at := Vector3(post[0][0], map.height(post[0][0], post[0][1]), post[0][1])
		var paint := StandardMaterial3D.new()
		paint.albedo_color = post[1]
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var pole := MeshUtil.cylinder(self, 1.0, 30.0, at + Vector3(0, 15, 0), paint)
		var label := Label3D.new()
		label.text = post[2]
		label.font_size = 200
		label.pixel_size = 0.06
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = post[1]
		label.position = Vector3(0, 22, 0)
		pole.add_child(label)
		_markers.append(pole)


func _save() -> void:
	plan["heights"] = Array(map.heights).map(func(h): return snappedf(h, 0.1))
	MapFile.write(Settings.edit_map, plan)
	_status.text = "Saved."


func _new(metres: float) -> void:
	# Starts this map again, empty and flat, at another size.
	MapFile.write(Settings.edit_map, MapFile.blank(metres))
	main.restart(true)


func _leave() -> void:
	_save()
	Settings.custom_map = Settings.edit_map  # ready to be played on
	Settings.edit_map = ""
	main.restart(false)
