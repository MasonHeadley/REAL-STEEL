extends CanvasLayer
# The sound board for the test range: every sound in the game with a button for each of its
# variations, and every voice line. F1 shows and hides it.

var main
var panel: PanelContainer


func _ready() -> void:
	layer = 8
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.95)
	style.border_color = Color(0.85, 0.7, 0.3)
	style.set_border_width_all(2)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.custom_minimum_size = Vector2(620, 0)
	panel.offset_left = -640
	panel.offset_top = 90
	panel.offset_bottom = -20
	panel.offset_right = -20
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_label(column, "SOUND BOARD", 22, Color(1.0, 0.85, 0.45))
	_label(column, "Each number is one recording of that sound. Loops play for four seconds. F1 closes.", 12, Color(0.75, 0.75, 0.75))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var names: Array = Sfx.streams.keys()
	names.sort()
	for id in names:
		var row := HBoxContainer.new()
		list.add_child(row)
		var l := _label(row, "%s   (%s)" % [id, Sfx.BUS[id]], 14)
		l.custom_minimum_size = Vector2(230, 0)
		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(flow)
		for i in Sfx.streams[id].size():
			_button(flow, str(i + 1), func(): Sfx.audition(id, i))
	_label(list, "", 6)
	_label(list, "VOICE LINES", 16, Color(1.0, 0.85, 0.45))
	var voices := HFlowContainer.new()
	list.add_child(voices)
	for id in GameData.voices:
		_button(voices, String(GameData.voices[id]["text"]), func(): Sfx.say(id, true))
	panel.visible = false


func _label(parent: Control, text: String, px: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34, 28)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(action)
	parent.add_child(b)


func toggle() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif main.player_ctrl.has_tank():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
