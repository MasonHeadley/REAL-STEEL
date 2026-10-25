extends CanvasLayer
# The menus: a dark panel of plain on-screen-display text.
# The start menu sits to one side over a live bots-only battle, shown as rough camcorder
# footage (camcorder.gd films it; the tape look and the viewfinder marks are drawn here).
# The pause menu freezes a real match and sits in the middle, with no tape look.
# Pages: main, mode (game mode), rules (game rules), settings (sound and mouse), controls, pause.

const PHOSPHOR := Color(0.93, 0.95, 0.9)  # the menu text
const DIM := Color(0.62, 0.64, 0.6)
const AMBER := Color(1.0, 0.8, 0.35)
const SCREEN := Vector2(780, 690)

var main
var tv: PanelContainer
var title: Label
var pages := {}
var footers := {}
var current := ""
# Where Back leads from each page while in the start menu.
const PARENT := {"single": "main", "multi": "main", "garage": "main", "graphics": "main", "lobby": "multi", "mode": "single", "rules": "single", "settings": "main", "controls": "main"}
var rebinding := ""
var bind_buttons := {}
var mode_buttons := {}
var vehicle_boxes := {}
var class_boxes := {}
var scan: Control
var tape: ColorRect
var _lobby_title: LineEdit
var _lobby_pass: LineEdit
var _join_address: LineEdit
var _net_note: Label
var _found_box: VBoxContainer
var _roster: VBoxContainer
var _test_page_done := false
var garage: Garage
var _rule: ColorRect
var _busy := ""  # what the game is waiting on ("Joining..."), shown with a turning wheel; "" for nothing
var _centre: CenterContainer
var _t := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The tape look, over the battle and under the menu.
	tape = ColorRect.new()
	tape.set_anchors_preset(Control.PRESET_FULL_RECT)
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look := ShaderMaterial.new()
	look.shader = preload("res://scripts/tape.gdshader")
	tape.material = look
	add_child(tape)

	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_centre = centre
	tv = PanelContainer.new()
	tv.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	centre.add_child(tv)

	# The panel the menu text sits on.
	var glass := PanelContainer.new()
	var tube := StyleBoxFlat.new()
	tube.bg_color = Color(0.03, 0.03, 0.03, 0.6)
	tube.border_color = Color(1, 1, 1, 0.3)
	tube.set_border_width_all(2)
	tube.set_corner_radius_all(3)
	tube.set_content_margin_all(30)
	glass.add_theme_stylebox_override("panel", tube)
	glass.custom_minimum_size = SCREEN
	tv.add_child(glass)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	glass.add_child(column)
	title = _label(column, "", 40, PHOSPHOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rule = ColorRect.new()
	var rule := _rule
	rule.color = DIM
	rule.custom_minimum_size = Vector2(0, 2)
	column.add_child(rule)
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	_build_main(_page(body, "main"))
	_build_single(_page(body, "single"))
	_build_multi(_page(body, "multi"))
	_build_lobby(_page(body, "lobby"))
	garage = Garage.new()
	_page(body, "garage").add_child(garage)
	garage.setup(self, self)
	_item(footers["garage"], "BACK", _back)
	_build_pause(_page(body, "pause"))
	_build_mode(_page(body, "mode"))
	_build_rules(_page(body, "rules"))
	_build_settings(_page(body, "settings"))
	_build_graphics(_page(body, "graphics"))
	_build_controls(_page(body, "controls"))

	# The viewfinder marks, drawn over everything.
	scan = Control.new()
	scan.set_anchors_preset(Control.PRESET_FULL_RECT)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scan.draw.connect(_draw_set)
	add_child(scan)
	show_page("")


# A page is a scrolling list with a footer underneath that never scrolls, so Back (and
# anything else put in the footer) is always on the screen however long the list is.
func _page(parent: Control, id: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 4)
	parent.add_child(page)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 30)
	page.add_child(foot)
	pages[id] = page
	footers[id] = foot
	return box


func _label(parent: Control, text: String, px: int, color: Color = PHOSPHOR) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


# A line of clickable text on the screen. It lights up and gets a cursor when pointed at.
func _item(parent: Control, text: String, action: Callable, px: int = 26) -> Button:
	var b := Button.new()
	b.text = "  " + text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", px)
	b.add_theme_color_override("font_color", PHOSPHOR)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.set_meta("label", text)
	b.mouse_entered.connect(func(): b.text = "> " + String(b.get_meta("label")))
	b.mouse_exited.connect(func(): b.text = "  " + String(b.get_meta("label")))
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _retitle(b: Button, text: String) -> void:
	b.set_meta("label", text)
	b.text = "  " + text


# The game's name in heavy letters of brushed steel, screwed on. Each letter is a handful of
# thick bars, given as [x, y, width, height] on a grid five wide and seven tall; "leg" is the
# one slanted bar (the R's). The bars are drawn three times over: once nudged up and left in
# a bright colour and once down and right in a dark one, to give the edges a bevel, then
# the steel itself on top. A screw goes near each end of every bar.
const LETTERS := {
	"[": {"wide": 3.0, "bars": [[0, 0, 1.5, 7], [0, 0, 3, 1.4], [0, 5.6, 3, 1.4]]},
	"]": {"wide": 3.0, "bars": [[1.5, 0, 1.5, 7], [0, 0, 3, 1.4], [0, 5.6, 3, 1.4]]},
	"R": {"wide": 5.0, "bars": [[0, 0, 1.5, 7], [0, 0, 5, 1.4], [3.5, 0, 1.5, 4.2], [0, 2.8, 5, 1.4]], "leg": [[2.0, 4.2], [3.6, 4.2], [5.0, 7.0], [3.4, 7.0]]},
	"E": {"wide": 5.0, "bars": [[0, 0, 1.5, 7], [0, 0, 5, 1.4], [0, 2.8, 4, 1.4], [0, 5.6, 5, 1.4]]},
	"A": {"wide": 5.0, "bars": [[0, 0, 1.5, 7], [3.5, 0, 1.5, 7], [0, 0, 5, 1.4], [0, 3.0, 5, 1.4]]},
	"L": {"wide": 5.0, "bars": [[0, 0, 1.5, 7], [0, 5.6, 5, 1.4]]},
	"S": {"wide": 5.0, "bars": [[0, 0, 5, 1.4], [0, 0, 1.5, 4.2], [0, 2.8, 5, 1.4], [3.5, 2.8, 1.5, 4.2], [0, 5.6, 5, 1.4]]},
	"T": {"wide": 5.0, "bars": [[0, 0, 5, 1.4], [1.75, 0, 1.5, 7]]},
}


func _draw_name(on: Control) -> void:
	var lines := ["[REAL]", "STEEL"]
	var unit := floorf(minf(on.size.x / 32.0, on.size.y / 15.5))
	for n in lines.size():
		var text: String = lines[n]
		var wide := -1.0
		for ch in text:
			wide += float(LETTERS[ch]["wide"]) + 1.0
		var x := (on.size.x - wide * unit) * 0.5
		for ch in text:
			_draw_letter(on, LETTERS[ch], Vector2(x, float(n) * unit * 8.2), unit)
			x += (float(LETTERS[ch]["wide"]) + 1.0) * unit


func _draw_letter(on: Control, letter: Dictionary, at: Vector2, unit: float) -> void:
	var shapes: Array = []  # every bar as four corners, in pixels
	for bar in letter["bars"]:
		var r := Rect2(at + Vector2(bar[0], bar[1]) * unit, Vector2(bar[2], bar[3]) * unit)
		shapes.append(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
	if letter.has("leg"):
		var leg := PackedVector2Array()
		for p in letter["leg"]:
			leg.append(at + Vector2(p[0], p[1]) * unit)
		shapes.append(leg)
	var top := at.y
	var tall := unit * 7.0
	# [how far the layer is nudged, its colour]; null means the steel itself.
	for layer in [[Vector2(5, 6), Color(0, 0, 0, 0.55)], [Vector2(2.5, 2.5), Color(0.2, 0.2, 0.2)], [Vector2(-2.5, -2.5), Color(0.98, 0.97, 0.92)], [Vector2.ZERO, null]]:
		for shape in shapes:
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			for p in shape:
				pts.append(p + layer[0])
				if layer[1] == null:
					# Brushed steel: bright at the top, a darker band below the middle, bright again at the foot.
					var k := clampf((p.y - top) / tall, 0.0, 1.0)
					cols.append(Color(0.86, 0.84, 0.78).lerp(Color(0.5, 0.49, 0.46), sin(k * PI * 0.9)))
				else:
					cols.append(layer[1])
			on.draw_polygon(pts, cols)
	# Screws: one near each end of every upright or level bar, none doubled up at a corner.
	var screws: Array = []
	for bar in letter["bars"]:
		var along := Vector2(0, 1) if bar[3] > bar[2] else Vector2(1, 0)
		var mid := Vector2(bar[0] + bar[2] * 0.5, bar[1] + bar[3] * 0.5)
		var reach: float = maxf(bar[2], bar[3]) * 0.5 - 0.72
		for end in [-1.0, 1.0]:
			var p: Vector2 = at + (mid + along * reach * end) * unit
			var doubled := false
			for q in screws:
				doubled = doubled or p.distance_to(q) < unit * 0.9
			if not doubled:
				screws.append(p)
	for i in screws.size():
		var p: Vector2 = screws[i]
		var slot := Vector2.from_angle(0.6 + i * 1.9) * unit * 0.2
		on.draw_circle(p + Vector2(1, 1), unit * 0.3, Color(0.2, 0.2, 0.2, 0.8))
		on.draw_circle(p, unit * 0.27, Color(0.72, 0.71, 0.66))
		on.draw_circle(p - Vector2(1, 1), unit * 0.17, Color(0.9, 0.89, 0.84))
		on.draw_line(p - slot, p + slot, Color(0.25, 0.25, 0.25), 2.0)

func _build_main(box: VBoxContainer) -> void:
	var plate := Control.new()
	plate.custom_minimum_size = Vector2(SCREEN.x - 70, 196)
	plate.draw.connect(_draw_name.bind(plate))
	box.add_child(plate)
	var rank := _label(box, "LEVEL %d      %d / %d XP" % [Profile.level(), Profile.into_level(), Profile.XP_PER_LEVEL], 16, AMBER)
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item(box, "SINGLE PLAYER", func(): show_page("single"), 27)
	_item(box, "MULTIPLAYER", func(): show_page("multi"), 27)
	_item(box, "GARAGE", func(): show_page("garage"), 27)
	_item(box, "SOUND AND MOUSE", func(): show_page("settings"))
	_item(box, "GRAPHICS", func(): show_page("graphics"))
	_item(box, "CONTROLS", func(): show_page("controls"))
	_item(box, "QUIT", func(): get_tree().quit())


func _build_single(box: VBoxContainer) -> void:
	_item(box, "QUICK BATTLE", func(): main.start_match(), 32)
	_label(box, "      You and four bots against five. Uses the mode and rules below.", 15, DIM)
	mode_buttons["main"] = _item(box, "", func(): show_page("mode"))
	_item(box, "GAME RULES", func(): show_page("rules"))
	_label(box, "", 8)
	var campaign := _item(box, "CAMPAIGN", func(): pass)
	campaign.disabled = true
	campaign.add_theme_color_override("font_disabled_color", DIM)
	_label(box, "      Not built yet.", 15, DIM)
	_label(box, "", 8)
	_item(box, "SHOOTING RANGE", func(): main.start_range())
	_label(box, "      Targets to shoot at, and a lane where guns shoot back at you.", 15, DIM)
	_label(box, "", 6)
	_label(box, "YOUR OWN MAPS", 17, AMBER)
	var named := _field(box, "MAP NAME", Settings.map_name, "my_map")
	named.text_changed.connect(func(t: String): Settings.map_name = t.strip_edges().to_lower().replace(" ", "_"))
	_item(box, "EDIT THIS MAP", func():
		Settings.edit_map = Settings.map_name if Settings.map_name != "" else "my_map"
		main.restart(true))
	var where: Array = [null]
	where[0] = _item(box, "PLAY ON:  the town", func():
		Settings.custom_map = "" if Settings.custom_map != "" else Settings.map_name
		_retitle(where[0], "PLAY ON:  " + ("the town" if Settings.custom_map == "" else "your map  \"%s\"" % Settings.custom_map)))
	_label(box, "      Your maps work in Deathmatch and Domination. Push runs straight up the middle.", 14, DIM)
	_item(footers["single"], "BACK", _back)
	_refresh_mode()


# A captioned box to type in.
func _field(parent: Control, caption: String, text: String, hint: String, secret: bool = false) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var l := _label(row, "  " + caption, 20)
	l.custom_minimum_size = Vector2(230, 0)
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = hint
	edit.secret = secret
	edit.max_length = 30
	edit.custom_minimum_size = Vector2(360, 0)
	edit.add_theme_font_size_override("font_size", 20)
	row.add_child(edit)
	return edit


# Multiplayer: say who you are, then open a lobby of your own or find someone else's.
func _build_multi(box: VBoxContainer) -> void:
	var who := _field(box, "YOUR NAME", Net.my_name, "")
	who.text_changed.connect(Net.set_my_name)
	_label(box, "", 6)
	_label(box, "HOST A LOBBY", 17, AMBER)
	_lobby_title = _field(box, "LOBBY NAME", "", "")
	_lobby_pass = _field(box, "PASSWORD", "", "", true)
	_label(box, "      Leave the password empty for an open lobby. It is also the one used when joining.", 14, DIM)
	_item(box, "OPEN LOBBY", func():
		_busy = "Opening the lobby"
		var problem := Net.host(_lobby_title.text, _lobby_pass.text)
		if problem != "":
			_busy = ""
			_net_note.text = problem)
	_label(box, "", 6)
	_label(box, "JOIN A LOBBY", 17, AMBER)
	_item(box, "FIND LOBBIES", func():
		_net_note.text = ""
		_busy = "Looking for lobbies"
		Net.search())
	_found_box = VBoxContainer.new()
	box.add_child(_found_box)
	_join_address = _field(box, "OR BY ADDRESS", "", "the host's IP address")
	_item(box, "JOIN THAT ADDRESS", func(): _join(_join_address.text))
	_net_note = _label(box, "", 17, AMBER)
	_net_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_note.custom_minimum_size = Vector2(SCREEN.x - 110, 0)
	_item(footers["multi"], "BACK", _back)
	_label(box, "      Connected through Steam: lobbies can be found from anywhere." if Net.steam_ok else "      Steam is not running: lobbies are only visible on your own network.", 14, DIM)
	Net.found.connect(_show_found)
	Net.started.connect(func(): main.restart(true))
	Net.changed.connect(_refresh_lobby)
	Net.closed.connect(func(reason: String):
		_busy = ""
		_net_note.text = reason
		if current == "lobby" or current == "mode" or current == "rules":
			show_page("multi"))


func _join(address: String) -> void:
	_net_note.text = ""
	_busy = "Joining"
	var problem := Net.join(address, _lobby_pass.text)
	if problem != "":
		_busy = ""
		_net_note.text = problem


func _show_found(lobbies: Array) -> void:
	_busy = ""
	for c in _found_box.get_children():
		c.queue_free()
	_net_note.text = "" if not lobbies.is_empty() else "No lobbies found."
	for l in lobbies:
		var address := String(l["address"])
		_item(_found_box, "%s    %d/%d%s" % [l["name"], l["players"], l["max"], "    (password)" if l["locked"] else ""], func(): _join(address), 22)


# The lobby: both teams, who wears the crown, and what is going to be played.
func _build_lobby(box: VBoxContainer) -> void:
	_roster = box
	_item(footers["lobby"], "LEAVE LOBBY", _back)


func _refresh_lobby() -> void:
	if not Net.active:
		return
	_busy = ""
	if current == "multi":
		show_page("lobby")  # we have just been let in
	for c in _roster.get_children():
		c.queue_free()
	var boss: bool = Net.is_leader()
	_label(_roster, "%s%s" % [Net.lobby_name, "   (password)" if Net.locked else ""], 19, AMBER)
	# The table: a column each for Blue, Red and the spectators, ten seats down.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 3)
	_roster.add_child(grid)
	var tints: Array = [main.TEAM_COLORS[0], main.TEAM_COLORS[1], Color(0.7, 0.7, 0.68)]
	var heads: Array = ["BLUE", "RED", "SPECTATORS"]
	for team in 3:
		var head := _label(grid, "%s   %d" % [heads[team], _seated(team)], 17, tints[team])
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.custom_minimum_size = Vector2(232, 0)
	var mine: int = Net.my_id()
	for seat in Net.SEATS:
		for team in 3:
			var who: int = Net.who_sits(team, seat)
			var cell := Button.new()
			cell.focus_mode = Control.FOCUS_NONE
			cell.custom_minimum_size = Vector2(232, 26)
			cell.add_theme_font_size_override("font_size", 16)
			cell.clip_text = true
			var tint: Color = tints[team]
			var filled := who != 0
			for state in ["normal", "hover", "pressed"]:
				var box := StyleBoxFlat.new()
				box.bg_color = tint.darkened(0.55 if filled else 0.8)
				box.bg_color.a = 0.9 if filled else 0.55
				if state == "hover":
					box.bg_color = box.bg_color.lightened(0.18)
				box.set_corner_radius_all(3)
				box.set_border_width_all(2 if who == mine else 0)
				box.border_color = AMBER
				box.content_margin_left = 34.0 if who == Net.leader and who > 0 else 10.0
				cell.add_theme_stylebox_override(state, box)
			cell.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if who > 0:
				cell.text = "%s%s" % [Net.members[who]["name"], "  (you)" if who == mine else ""]
				cell.add_theme_color_override("font_color", Color.WHITE)
				if who == Net.leader:
					var crown := Control.new()
					crown.position = Vector2(4, 3)
					crown.scale = Vector2(0.85, 0.85)
					crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
					crown.draw.connect(_draw_crown.bind(crown))
					cell.add_child(crown)
				cell.tooltip_text = "Right click: remove from the lobby.   Shift + right click: hand over the crown." if boss and who != mine else ""
			elif who < 0:
				cell.text = "BOT"
				cell.add_theme_color_override("font_color", tint.lightened(0.5))
				cell.tooltip_text = "Right click: take this bot out." if boss else ""
			else:
				cell.text = "open"
				cell.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
				cell.tooltip_text = "Click to sit here." + ("   Right click: put a bot here." if boss and team != Net.SPECTATOR else "")
			cell.gui_input.connect(_seat_clicked.bind(team, seat))
			grid.add_child(cell)
	var hint := "Click an open seat to move there."
	if boss:
		hint += "  Right click a seat to add or remove a bot, or to remove a player."
	_label(_roster, "  " + hint, 14, DIM)
	if boss:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		_roster.add_child(row)
		_item(row, "+ BLUE BOT", func(): _add_bot(0), 17)
		_item(row, "+ RED BOT", func(): _add_bot(1), 17)
		_item(row, "FILL 5 v 5", func(): Net.ask("fill"), 17)
		_item(row, "NO BOTS", func(): Net.ask("clear"), 17)
	var mode_id := String(Net.settings.get("mode", Settings.mode_id))
	var mode_name := String(GameData.modes[mode_id]["name"]).to_upper() if GameData.modes.has(mode_id) else "?"
	if boss:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		_roster.add_child(row)
		_item(row, "MODE:  " + mode_name, func(): show_page("mode"), 20)
		_item(row, "RULES", func(): show_page("rules"), 20)
		_item(_roster, "START MATCH", func():
			_busy = "Starting the match"
			Net.ask("start"), 28)
	else:
		var rules: Dictionary = Net.settings.get("rules", {})
		_label(_roster, "  MODE:  %s      reload x%.2f   damage x%.2f   %d min" % [mode_name, float(rules.get("reload", 1.0)), float(rules.get("damage", 1.0)), int(rules.get("minutes", 10))], 17, DIM)
		_label(_roster, "  The host (with the crown) chooses the mode and rules, and starts the match.", 15, DIM)


func _seated(team: int) -> int:
	var n := 0
	for seat in Net.SEATS:
		n += 1 if Net.who_sits(team, seat) != 0 else 0
	return n


# A seat in the lobby's table was clicked. Left: sit there. Right, for the host: put a bot in
# an empty seat, take a bot out, or remove a player (with Shift, give them the crown instead).
func _seat_clicked(e: InputEvent, team: int, seat: int) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	var who: int = Net.who_sits(team, seat)
	if e.button_index == MOUSE_BUTTON_LEFT and who == 0:
		Net.ask("sit", [team, seat])
	elif e.button_index == MOUSE_BUTTON_RIGHT and Net.is_leader():
		if who <= 0:
			Net.ask("bot", [team, seat])
		elif who != Net.my_id():
			Net.ask("crown" if e.shift_pressed else "kick", who)


func _add_bot(team: int) -> void:
	for seat in Net.SEATS:
		if Net.seat_free(team, seat):
			Net.ask("bot", [team, seat])
			return

# The host's crown, drawn beside their name.
func _draw_crown(on: Control) -> void:
	var gold := Color(1.0, 0.82, 0.25)
	on.draw_colored_polygon(PackedVector2Array([Vector2(3, 22), Vector2(1, 6), Vector2(9, 14), Vector2(16, 2), Vector2(23, 14), Vector2(31, 6), Vector2(29, 22)]), gold)
	on.draw_rect(Rect2(3, 22, 26, 3), gold.darkened(0.25))

func _build_pause(box: VBoxContainer) -> void:
	_item(box, "RESUME", func(): main.set_paused(false), 30)
	_item(box, "SOUND AND MOUSE", func(): show_page("settings"))
	_item(box, "GRAPHICS", func(): show_page("graphics"))
	_item(box, "CONTROLS", func(): show_page("controls"))
	_item(box, "REDEPLOY", func():
		# Gives up what you are in and takes you back to the deploy screen.
		main.set_paused(false)
		main.redeploy())
	_item(box, "RESTART MATCH", func():
		if not Net.in_match:  # in a networked match only the lobby can start another
			main.restart(true))
	_item(box, "MAIN MENU", func():
		Net.leave()  # (does nothing when not in a lobby)
		main.restart(false))
	_item(box, "QUIT GAME", func(): get_tree().quit())


func _build_mode(box: VBoxContainer) -> void:
	for id in GameData.mode_order:
		var m: Dictionary = GameData.modes[id]
		if m["kind"] == "range":
			continue  # the sound range has its own menu entry
		mode_buttons[id] = _item(box, "", func():
			Settings.set_mode(id)
			_refresh_mode(), 28)
		var about := _label(box, "      " + String(m["description"]), 15, DIM)
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		about.custom_minimum_size = Vector2(SCREEN.x - 110, 0)
	_item(footers["mode"], "BACK", _back)
	_refresh_mode()


func _refresh_mode() -> void:
	for id in GameData.mode_order:
		if mode_buttons.has(id):
			_retitle(mode_buttons[id], "[%s] %s" % ["X" if Settings.mode_id == id else " ", String(GameData.modes[id]["name"]).to_upper()])
	if mode_buttons.has("main") and GameData.modes.has(Settings.mode_id):
		_retitle(mode_buttons["main"], "GAME MODE:  " + String(GameData.modes[Settings.mode_id]["name"]).to_upper())


func _slider(parent: Control, text: String, value: float, lo: float, hi: float, suffix: String, changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var l := _label(row, text, 18)
	l.custom_minimum_size = Vector2(250, 0)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0 if suffix == "%" else 1.0
	s.value = value
	s.custom_minimum_size = Vector2(300, 26)
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var shown := _label(row, "", 17, AMBER)
	shown.custom_minimum_size = Vector2(80, 0)
	var show_value := func(v: float): shown.text = ("%d%%" % int(round(v * 100.0))) if suffix == "%" else ("%d %s" % [int(v), suffix])
	show_value.call(value)
	s.value_changed.connect(func(v: float):
		show_value.call(v)
		changed.call(v))


func _check(parent: Control, text: String, on: bool, toggled: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 17)
	c.add_theme_color_override("font_color", PHOSPHOR)
	c.add_theme_color_override("font_pressed_color", PHOSPHOR)
	c.add_theme_color_override("font_hover_color", Color.WHITE)
	c.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	c.add_theme_color_override("font_disabled_color", DIM)
	c.toggled.connect(toggled)
	parent.add_child(c)
	return c


# Game rules: numbers that bend the match, and which vehicles are allowed in it.
func _build_rules(box: VBoxContainer) -> void:
	_label(box, "These apply from the next match, for you and the bots.", 14, DIM)
	var r: Dictionary = Settings.rules
	_slider(box, "Reload time", r["reload"], 0.25, 2.0, "%", func(v: float): Settings.set_rule("reload", v))
	_slider(box, "Damage", r["damage"], 0.25, 3.0, "%", func(v: float): Settings.set_rule("damage", v))
	_slider(box, "Bot accuracy", r["bot_aim"], 0.25, 2.0, "%", func(v: float): Settings.set_rule("bot_aim", v))
	_slider(box, "Respawn wait", r["respawn"], 2.0, 20.0, "s", func(v: float): Settings.set_rule("respawn", v))
	_slider(box, "Match length", r["minutes"], 3.0, 20.0, "min", func(v: float): Settings.set_rule("minutes", v))
	_slider(box, "Bot aircraft arrive every", r.get("air_every", 50.0), 5.0, 120.0, "s", func(v: float): Settings.set_rule("air_every", v))
	_check(box, "Infantry  (bot squads, and playable on foot)", r["infantry"], func(on: bool): Settings.set_rule("infantry", on))

	_label(box, "VEHICLE TYPES", 18, AMBER)
	var types := GridContainer.new()
	types.columns = 3
	types.add_theme_constant_override("h_separation", 18)
	box.add_child(types)
	for cls in ["heavy", "medium", "destroyer", "artillery", "light"]:
		class_boxes[cls] = _check(types, cls.capitalize(), true, func(on: bool): _set_class(cls, on))
	_check(types, "Planes", r["planes"], func(on: bool): Settings.set_rule("planes", on))
	_check(types, "Helicopters", r["helis"], func(on: bool): Settings.set_rule("helis", on))
	_check(types, "Anti-aircraft", Settings.vehicle_enabled("gepard") or Settings.vehicle_enabled("adats"), func(on: bool):
		for id in GameData.vehicle_order:
			if GameData.vehicles[id].has("aa"):
				Settings.set_vehicle_enabled(id, on)
		_refresh_vehicles())

	_label(box, "VEHICLES", 18, AMBER)
	var each := GridContainer.new()
	each.columns = 3
	each.add_theme_constant_override("h_separation", 18)
	box.add_child(each)
	for id in GameData.vehicle_order:
		vehicle_boxes[id] = _check(each, GameData.vehicles[id]["name"], Settings.vehicle_enabled(id), func(on: bool): _set_vehicle(id, on))
	_item(footers["rules"], "BACK", _back)
	_refresh_vehicles()


func _set_vehicle(id: String, on: bool) -> void:
	Settings.set_vehicle_enabled(id, on)  # refuses to switch off the last one
	_refresh_vehicles()


func _set_class(cls: String, on: bool) -> void:
	for id in GameData.vehicle_order:
		if GameData.vehicles[id]["class"] == cls:
			Settings.set_vehicle_enabled(id, on)
	_refresh_vehicles()


func _refresh_vehicles() -> void:
	for id in vehicle_boxes:
		vehicle_boxes[id].set_pressed_no_signal(Settings.vehicle_enabled(id))
	for cls in class_boxes:
		var any := false
		for id in GameData.vehicle_order:
			if GameData.vehicles[id]["class"] == cls and Settings.vehicle_enabled(id):
				any = true
		class_boxes[cls].set_pressed_no_signal(any)


func _build_settings(box: VBoxContainer) -> void:
	var names := {"Master": "Everything", "Engine": "Engines and tracks", "Weapons": "Guns", "Effects": "Hits and explosions", "Voice": "Crew voices", "Interface": "Emotes and alerts", "Music": "Music"}
	for b in Settings.BUSES:
		_slider(box, names[b], Settings.volumes[b], 0.0, 1.0, "%", func(v: float): Settings.set_volume(b, v))
	_label(box, "", 6)
	_slider(box, "Mouse sensitivity", Settings.sensitivity, 0.2, 3.0, "%", func(v: float): Settings.set_sensitivity(v))
	_item(footers["settings"], "BACK", _back)


# Graphics: each choice takes effect at once, on the battle behind the menu, so it can be judged.
func _build_graphics(box: VBoxContainer) -> void:
	_label(box, "Changes show straight away on the footage behind this menu.", 14, DIM)
	var g: Dictionary = Settings.gfx
	_check(box, "Full screen  (F11 or Alt+Enter switches at any time)", g.get("fullscreen", false), func(on: bool): Settings.set_gfx("fullscreen", on))
	_check(box, "Gritty look  (dark worn colour, hard contrast, haze in the distance)", g["gritty"], func(on: bool): Settings.set_gfx("gritty", on))
	_check(box, "Haze that catches the light  (gritty look; slower)", g["haze"], func(on: bool): Settings.set_gfx("haze", on))
	_check(box, "Film look  (dark corners and grain)", g["film"], func(on: bool): Settings.set_gfx("film", on))
	# A choice of several is a line that steps to the next one each time it is clicked.
	var steps := [["shadows", "SHADOWS", ["off", "near only", "full"]], ["aa", "SMOOTH EDGES", ["off", "2x", "4x"]]]
	for step in steps:
		var key: String = step[0]
		var names: Array = step[2]
		var line: Array = [null]
		line[0] = _item(box, "%s:  %s" % [step[1], names[int(g[key])]], func():
			Settings.set_gfx(key, (int(Settings.gfx[key]) + 1) % names.size())
			_retitle(line[0], "%s:  %s" % [step[1], names[int(Settings.gfx[key])]]), 20)
	_slider(box, "Sharpness of the 3D picture", g["scale"], 0.5, 1.0, "%", func(v: float): Settings.set_gfx("scale", v))
	_check(box, "Soft shading in corners  (slower)", g["ssao"], func(on: bool): Settings.set_gfx("ssao", on))
	_check(box, "Glow on bright things", g["glow"], func(on: bool): Settings.set_gfx("glow", on))
	_check(box, "Smoke, dust and sparks", g["particles"], func(on: bool): Settings.set_gfx("particles", on))
	_check(box, "V-sync  (no tearing; turn off for the highest frame rate)", g["vsync"], func(on: bool): Settings.set_gfx("vsync", on))
	_label(box, "", 6)
	var tip := _label(box, "If the game runs slowly: lower the sharpness first, then shadows to near only, then smooth edges off.", 14, DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(SCREEN.x - 110, 0)
	_item(footers["graphics"], "BACK", _back)


func _build_controls(box: VBoxContainer) -> void:
	_label(box, "Click a binding, then press the key or mouse button you want.", 14, DIM)
	# One tab for each way of playing. Which tab an action belongs on is told by the start of its id.
	var tabs := [["GROUND VEHICLES", "", "Fixed: Esc pauses, numbers pick shells and emotes, the wheel sets the sight zero."],
		["INFANTRY", "inf_", "Moving, firing and aiming use the ground vehicle keys (drive, fire main gun, gunner sight)."],
		["AIRCRAFT", "air_", "Steering and throttle use the drive keys; guns are 'fire main gun' and rockets 'gunner sight'. The mouse steers."],
		["SPECTATING", "spec_", "Click and right click step to the next and previous vehicle."]]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var pages: Array = []
	var buttons: Array = []
	for tab in tabs:
		var pick := Button.new()
		pick.text = tab[0]
		pick.focus_mode = Control.FOCUS_NONE
		pick.custom_minimum_size = Vector2(170, 32)
		pick.add_theme_font_size_override("font_size", 15)
		row.add_child(pick)
		buttons.append(pick)
		var page := VBoxContainer.new()
		box.add_child(page)
		pages.append(page)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 2)
		page.add_child(grid)
		for a in Settings.ACTIONS:
			var id: String = a[0]
			var group := "inf_" if id.begins_with("inf_") else ("air_" if id.begins_with("air_") else ("spec_" if id.begins_with("spec_") else ""))
			if group != tab[1]:
				continue
			var l := _label(grid, a[1], 17)
			l.custom_minimum_size = Vector2(300, 0)
			var b := Button.new()
			b.custom_minimum_size = Vector2(240, 30)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 16)
			b.add_theme_color_override("font_color", AMBER)
			b.pressed.connect(func(): _start_rebind(id))
			grid.add_child(b)
			bind_buttons[id] = b
		_label(page, tab[2], 13, DIM)
	var show_tab := func(which: int) -> void:
		for i in pages.size():
			pages[i].visible = i == which
			buttons[i].add_theme_color_override("font_color", AMBER if i == which else DIM)
	for i in buttons.size():
		buttons[i].pressed.connect(show_tab.bind(i))
	show_tab.call(0)
	_item(footers["controls"], "BACK", _back)
	_item(footers["controls"], "RESET TO DEFAULTS", _reset_bindings)
	_refresh_bindings()

func _reset_bindings() -> void:
	Settings.reset_bindings()
	_refresh_bindings()


func _refresh_bindings() -> void:
	for id in bind_buttons:
		bind_buttons[id].text = Settings.binding_text(id)


func _start_rebind(id: String) -> void:
	_refresh_bindings()
	rebinding = id
	bind_buttons[id].text = "Press a key..."


func _back() -> void:
	rebinding = ""
	_refresh_bindings()
	if Net.active and (current == "mode" or current == "rules"):
		# The leader has been choosing what the lobby plays: tell everyone, and go back to it.
		Net.ask("settings", {"mode": Settings.mode_id, "rules": Settings.rules.duplicate(true)})
		show_page("lobby")
		return
	if current == "lobby":
		Net.leave()
	show_page(String(PARENT.get(current, "main")) if main.state == "menu" else "pause")


func show_page(id: String) -> void:
	current = id
	for p in pages:
		pages[p].visible = p == id
	tv.visible = id != ""
	scan.visible = id != ""
	garage.viewer.visible = id == "garage"
	title.visible = id != "main"  # the start page has the name in steel instead
	_rule.visible = id != "main"
	# Beside the footage in the start menu; in the middle when pausing a match.
	var filming: bool = main != null and main.state == "menu"
	tape.visible = filming
	_centre.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE if filming else Control.PRESET_FULL_RECT)
	if filming:
		_centre.offset_right = SCREEN.x + 110.0
	title.text = {"main": "", "single": "SINGLE PLAYER", "multi": "MULTIPLAYER", "garage": "GARAGE", "graphics": "GRAPHICS", "lobby": "LOBBY", "pause": "PAUSED", "mode": "GAME MODE", "rules": "GAME RULES", "settings": "SOUND AND MOUSE", "controls": "CONTROLS"}.get(id, "")
	if id != "":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if id == "lobby":
		_refresh_lobby()


func _process(delta: float) -> void:
	if not _test_page_done and main != null:
		# Test runs: --menupage=<page> opens the menu on that page (the lobby, once there is one).
		for a in main.args:
			if a.begins_with("--menupage=") and (a.trim_prefix("--menupage=") != "lobby" or Net.members.size() >= 3):
				show_page(a.trim_prefix("--menupage="))
				_test_page_done = true
	if tv.visible:
		_t += delta
		scan.queue_redraw()
	if tape.visible:
		var cc: Camcorder = main.player_ctrl.camcorder
		tape.material.set_shader_parameter("glitch", cc.glitch)
		tape.material.set_shader_parameter("wide", cc.wide)


# What a camcorder shows in its viewfinder: corner marks, a blinking REC light, the tape
# counter, the battery, which camera this is and the date.
func _draw_set() -> void:
	if not tape.visible:
		return
	var cc: Camcorder = main.player_ctrl.camcorder
	var sz := scan.size
	if _busy != "":
		# Waiting on the network: a wheel of dots, the brightest one going round.
		var hub := tv.get_global_rect().get_center()
		scan.draw_rect(Rect2(hub - Vector2(190, 90), Vector2(380, 180)), Color(0, 0, 0, 0.82))
		for k in 12:
			var a := k * TAU / 12.0
			var lit := fposmod(float(k) - _t * 12.0, 12.0) / 12.0
			scan.draw_circle(hub + Vector2(cos(a), sin(a)) * 30.0 + Vector2(0, -18), 4.5, Color(1, 0.86, 0.45, 0.15 + 0.85 * lit))
		var wide := ThemeDB.fallback_font.get_string_size(_busy + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		scan.draw_string(ThemeDB.fallback_font, hub + Vector2(-wide * 0.5, 56), _busy + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))
	var f := ThemeDB.fallback_font
	var ink := Color(1, 1, 1, 0.92)
	var shade := Color(0, 0, 0, 0.55)
	var m := 44.0
	for corner in [Vector2(m, m), Vector2(sz.x - m, m), Vector2(m, sz.y - m), Vector2(sz.x - m, sz.y - m)]:
		var sx := 1.0 if corner.x < sz.x * 0.5 else -1.0
		var sy := 1.0 if corner.y < sz.y * 0.5 else -1.0
		scan.draw_line(corner, corner + Vector2(64.0 * sx, 0), ink, 3.0)
		scan.draw_line(corner, corner + Vector2(0, 64.0 * sy), ink, 3.0)
	var right := sz.x - 80.0
	if fmod(_t, 1.1) < 0.65:
		scan.draw_circle(Vector2(right - 300, 88), 11.0, Color(1, 0.12, 0.1))
	var secs := int(cc.tape)
	var counter := "%d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60]
	for line in [["REC", Vector2(right - 280, 99), 30], [counter, Vector2(right - 190, 99), 30], [cc.label, Vector2(right - 620, sz.y - 112), 24]]:
		var at: Vector2 = line[1]
		var wide: float = 190.0 if at.y < 200.0 else 620.0
		var align := HORIZONTAL_ALIGNMENT_LEFT if line[0] == "REC" else HORIZONTAL_ALIGNMENT_RIGHT
		scan.draw_string(f, at + Vector2(2, 2), line[0], align, wide, line[2], shade)
		scan.draw_string(f, at, line[0], align, wide, line[2], ink)
	# Battery: a case with three cells, the last one flickering.
	var bat := Rect2(right - 76, 122, 70, 26)
	scan.draw_rect(bat, ink, false, 2.5)
	scan.draw_rect(Rect2(bat.end.x, bat.position.y + 7, 6, 12), ink)
	for i in 3:
		if i < 2 or fmod(_t, 2.4) < 1.6:
			scan.draw_rect(Rect2(bat.position.x + 5 + i * 21.0, bat.position.y + 5, 17, 16), ink)
	var now := Time.get_datetime_dict_from_system()
	var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	var hour := int(now["hour"])
	var stamp := "%s %02d %d   %s %d:%02d" % [months[int(now["month"]) - 1], now["day"], now["year"], "PM" if hour >= 12 else "AM", 12 if hour % 12 == 0 else hour % 12, now["minute"]]
	scan.draw_string(f, Vector2(right - 618, sz.y - 70), stamp, HORIZONTAL_ALIGNMENT_RIGHT, 620, 26, shade)
	scan.draw_string(f, Vector2(right - 620, sz.y - 72), stamp, HORIZONTAL_ALIGNMENT_RIGHT, 620, 26, Color(1, 0.86, 0.45, 0.95))

func _input(e: InputEvent) -> void:
	if rebinding != "":
		var key: bool = e is InputEventKey and e.pressed and not e.echo
		var click: bool = e is InputEventMouseButton and e.pressed
		if key or click:
			if not (key and e.keycode == KEY_ESCAPE):
				Settings.set_binding(rebinding, e)
			rebinding = ""
			_refresh_bindings()
			get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if current != "" and current != "main" and current != "pause":
			_back()
		elif main.match_over and main.state == "playing":
			main.restart(false)  # from the result or the podium, back to the start menu
		elif main.state == "paused":
			main.set_paused(false)
		elif main.state == "playing":
			main.set_paused(true)
