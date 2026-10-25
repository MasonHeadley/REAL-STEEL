class_name Garage
extends VBoxContainer
# The garage: where a player sets up each vehicle's five loadouts. A loadout is its paint
# (pattern and three colours), a marking on the turret, and the equipment fitted to it
# (see kit.gd and data/attachments.json). The vehicle is shown turning slowly in a viewer
# beside the menu, rebuilt whenever anything is changed. Everything is saved as it is set.

const PATTERNS := ["standard", "blotch", "stripe", "digital", "plain"]
const BACKS := ["none", "disc", "square"]

var menu
var vehicle := ""
var index := 0
var viewer: SubViewportContainer
var _stage: Node3D
var _shown: Node3D
var _cam: Camera3D
var _turn := 0.6
var _dirty := false
var _pattern_pick: OptionButton


func setup(p_menu, layer: CanvasLayer) -> void:
	menu = p_menu
	add_theme_constant_override("separation", 5)
	vehicle = GameData.vehicle_order[0]
	index = int(Profile.active.get(vehicle, 0))
	# The viewer: a little world of its own with the vehicle in it.
	viewer = SubViewportContainer.new()
	viewer.stretch = true
	viewer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	viewer.offset_left = -730.0
	viewer.offset_right = -40.0
	viewer.offset_top = -300.0
	viewer.offset_bottom = 300.0
	viewer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewer.visible = false
	layer.add_child(viewer)
	var port := SubViewport.new()
	port.own_world_3d = true
	port.transparent_bg = true
	port.msaa_3d = Viewport.MSAA_4X
	viewer.add_child(port)
	_stage = Node3D.new()
	port.add_child(_stage)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 2.4, 0)
	_stage.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	_stage.add_child(env)
	MeshUtil.cylinder(_stage, 6.5, 0.1, Vector3(0, -0.05, 0), MeshUtil.material(Color(0.2, 0.21, 0.2), 0.9))
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_stage.add_child(_cam)
	_cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.3, 0) - Vector3(9.5, 5.0, -10.5)), Vector3(9.5, 5.0, -10.5))
	_fill()
	_show_vehicle()


func look() -> Dictionary:
	return Profile.loadout(vehicle, index)


func _process(delta: float) -> void:
	if not viewer.visible:
		return
	_turn += delta * 0.35
	if _dirty:
		_dirty = false
		_show_vehicle()
	if _shown != null:
		_shown.rotation.y = _turn


func _show_vehicle() -> void:
	if _shown != null:
		_shown.queue_free()
	var model := TankModel.build(Kit.apply(GameData.vehicles[vehicle], look()), Color(0.3, 0.55, 1.0), 0.15, 5, look())
	_shown = model["root"]
	_stage.add_child(_shown)
	_shown.rotation.y = _turn


func _changed(refill: bool = false) -> void:
	Profile.active[vehicle] = index
	Profile.save()
	_dirty = true
	if refill:
		_fill.call_deferred()


func _row(caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var l: Label = menu._label(row, "  " + caption, 16)
	l.custom_minimum_size = Vector2(150, 0)
	return row


func _options(row: Control, names: Array, chosen: int, picked: Callable, wide: float = 180.0) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.custom_minimum_size = Vector2(wide, 0)
	o.add_theme_font_size_override("font_size", 15)
	for n in names:
		o.add_item(String(n))
	o.select(clampi(chosen, 0, maxi(names.size() - 1, 0)))
	o.item_selected.connect(picked)
	row.add_child(o)
	return o


func _colour(row: Control, key: String, of: Dictionary) -> void:
	var b := ColorPickerButton.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 28)
	b.edit_alpha = false
	b.get_picker().presets_visible = false  # no "Swatches" panel: it only confused matters
	b.color = Color(String(of.get(key, "#808080")))
	b.color_changed.connect(func(c: Color):
		of[key] = "#" + c.to_html(false)
		if of.get("pattern", "") == "standard":
			# The standard factory paint has no colours to change: choosing one switches to a pattern that does.
			of["pattern"] = "blotch"
			if _pattern_pick != null and is_instance_valid(_pattern_pick):
				_pattern_pick.select(PATTERNS.find("blotch"))
		_changed())
	row.add_child(b)


# Lays the whole page out again from the loadout as it now stands.
func _fill() -> void:
	for c in get_children():
		c.queue_free()
	var lk := look()
	var camo: Dictionary = lk["camo"]
	var decal: Dictionary = lk["decal"]
	if not lk.has("slots"):
		lk["slots"] = {}
	var slots: Dictionary = lk["slots"]

	var top := _row("VEHICLE")
	_options(top, GameData.vehicle_order.map(func(id): return GameData.vehicles[id]["name"]), GameData.vehicle_order.find(vehicle), func(i: int):
		vehicle = GameData.vehicle_order[i]
		index = int(Profile.active.get(vehicle, 0))
		_changed(true), 230.0)
	var sets := _row("LOADOUT")
	for i in Profile.LOADOUTS:
		var b: Button = menu._item(sets, str(i + 1), func():
			index = i
			_changed(true), 20)
		b.add_theme_color_override("font_color", menu.AMBER if i == index else menu.DIM)
	menu._item(sets, "CLEAR", func():
		Profile.loadouts[vehicle][index] = Kit.blank()
		_changed(true), 15)

	menu._label(self, "PAINT", 16, menu.AMBER)
	var paint := _row("Pattern")
	_pattern_pick = _options(paint, PATTERNS.map(func(p): return p.capitalize()), PATTERNS.find(String(camo.get("pattern", "standard"))), func(i: int):
		camo["pattern"] = PATTERNS[i]
		_changed())
	for key in ["c1", "c2", "c3"]:
		_colour(paint, key, camo)
	var scale_row := _row("Pattern size")
	var slider := HSlider.new()
	slider.min_value = 0.4
	slider.max_value = 2.5
	slider.step = 0.1
	slider.value = float(camo.get("scale", 1.0))
	slider.custom_minimum_size = Vector2(260, 20)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float):
		camo["scale"] = v
		_changed())
	scale_row.add_child(slider)

	menu._label(self, "MARKING  (on both sides of the turret)", 16, menu.AMBER)
	var mark := _row("Letters or number")
	var text := LineEdit.new()
	text.max_length = 3
	text.text = String(decal.get("text", ""))
	text.custom_minimum_size = Vector2(90, 0)
	text.add_theme_font_size_override("font_size", 17)
	text.text_changed.connect(func(t: String):
		decal["text"] = t
		_changed())
	mark.add_child(text)
	_colour(mark, "colour", decal)
	_options(mark, ["No backing", "On a disc", "On a square"], BACKS.find(String(decal.get("back", "none"))), func(i: int):
		decal["back"] = BACKS[i]
		_changed(), 150.0)

	menu._label(self, "EQUIPMENT      you are level %d" % Profile.level(), 16, menu.AMBER)
	var notes: Array = []
	for place in Kit.PLACES:
		var row := _row(Kit.PLACE_NAMES[place])
		var fitted: Array = slots.get(place, [])
		var first_big: bool = fitted.size() > 0 and Kit.items.has(fitted[0]) and int(Kit.items[fitted[0]]["size"]) == 2
		for n in 2:
			# The second space only takes a small item, and is shut if the first holds a large one.
			var choices: Array = Kit.for_place(place).filter(func(id): return n == 0 or int(Kit.items[id]["size"]) == 1)
			var names: Array = ["- empty -"]
			for id in choices:
				var it: Dictionary = Kit.items[id]
				names.append("%s%s%s" % [it["name"], "  (large)" if int(it["size"]) == 2 else "", "   level %d" % int(it["level"]) if int(it["level"]) > Profile.level() else ""])
			var now: int = choices.find(fitted[n]) + 1 if n < fitted.size() else 0
			var pick := _options(row, names, now, func(i: int):
				var mine: Array = slots.get(place, []).duplicate()
				while mine.size() <= n:
					mine.append("")
				mine[n] = choices[i - 1] if i > 0 else ""
				if n == 0 and i > 0 and int(Kit.items[choices[i - 1]]["size"]) == 2:
					mine = [mine[0]]
				slots[place] = mine.filter(func(id): return id != "")
				_changed(true), 250.0)
			for k in choices.size():
				pick.set_item_disabled(k + 1, int(Kit.items[choices[k]]["level"]) > Profile.level())
			pick.disabled = n == 1 and first_big
		for id in fitted:
			if Kit.items.has(id):
				notes.append("%s: %s" % [Kit.items[id]["name"], Kit.items[id]["effect"]])
	var summary: Label = menu._label(self, "  " + ("\n  ".join(notes) if not notes.is_empty() else "Nothing fitted."), 13, menu.DIM)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.custom_minimum_size = Vector2(680, 0)
