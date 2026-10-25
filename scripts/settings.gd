extends Node
# Player settings: key bindings, volume per sound category, mouse sensitivity.
# Saved to user://settings.cfg so they survive between sessions.

const PATH := "user://settings.cfg"

# Action id, name shown in the controls menu, default binding.
const ACTIONS := [
	["forward", "Drive forward", "key:87"],
	["back", "Reverse", "key:83"],
	["left", "Turn left", "key:65"],
	["right", "Turn right", "key:68"],
	["fire", "Fire main gun", "mouse:1"],
	["machine_gun", "Machine gun", "key:32"],
	["sight", "Gunner sight (hold) / magnify", "mouse:2"],
	["sight_toggle", "Gunner sight (toggle)", "key:4194325"],
	["freelook", "Free look (hold)", "key:67"],
	["ability", "Ability", "key:69"],
	["emote", "Emotes", "key:84"],
	["ping", "Ping wheel (hold)", "mouse:3"],
	["rangefind", "Set zero to range", "key:82"],
	["radar", "Anti-aircraft radar on / off", "key:71"],
	["map", "Big map", "key:77"],
	["map_out", "Minimap: zoom out", "key:91"],
	["map_in", "Minimap: zoom in", "key:93"],
	["inf_view", "First person / third person", "key:86"],
	["inf_sprint", "Sprint (hold)", "key:4194325"],
	["inf_crouch", "Crouch (hold)", "key:4194326"],
	["inf_prone", "Lie down / get up", "key:90"],
	["inf_jump", "Jump, or vault a low obstacle", "key:32"],
	["inf_reload", "Reload", "key:82"],
	["inf_use", "Use class tool (hold)", "key:70"],
	["inf_grenade", "Throw grenade", "key:71"],
	["inf_primary", "Primary weapon", "key:49"],
	["inf_pistol", "Pistol", "key:50"],
	["inf_special", "Class weapon (RPG-7)", "key:51"],
	["air_view", "Cockpit / outside view", "key:86"],
	["air_up", "Helicopter: climb", "key:32"],
	["air_down", "Helicopter: descend", "key:4194326"],
	["air_bomb", "Drop a bomb", "key:70"],
	["air_flare", "Flares (throws off a missile)", "key:71"],
	["air_freelook", "Free look (hold)", "key:67"],
	["air_zoom", "Zoom the sight (hold)", "key:90"],
	["spec_free", "Free camera", "key:49"],
	["spec_gunner", "Gunner's view of a vehicle", "key:50"],
	["spec_orbit", "Circle a vehicle", "key:51"],
	["spec_outline", "Team outlines on or off", "key:79"],
]
const BUSES := ["Master", "Engine", "Weapons", "Effects", "Voice", "Interface", "Music"]
const MOUSE_NAMES := {1: "Left mouse", 2: "Right mouse", 3: "Middle mouse", 4: "Wheel up", 5: "Wheel down", 8: "Mouse 4", 9: "Mouse 5"}

var bindings := {}
var volumes := {}
var sensitivity := 1.0
var mode_id := "push"
var player_name := ""  # shown to other people in a lobby; "Player" if left blank
# Game rules the player can change from the start menu. They apply from the next match.
var inf_sight := "iron"  # what the player's rifle carries: iron, holo or acog (see WeaponModel.SIGHTS)

func set_inf_sight(to: String) -> void:
	inf_sight = to
	save()

var rules := {"reload": 1.0, "damage": 1.0, "respawn": 8.0, "minutes": 10.0, "bot_aim": 1.0, "infantry": true, "planes": true, "helis": true, "air_every": 50.0, "disabled": []}
# Graphics choices (the Graphics page of the menu). shadows: 0 off, 1 near only, 2 full.
# aa: 0 off, 1 = 2x, 2 = 4x. scale: how much of full sharpness the 3D picture is drawn at.
var gfx := {"shadows": 2, "aa": 1, "scale": 1.0, "ssao": false, "glow": true, "gritty": true, "vsync": true, "particles": true,
	"haze": true, "film": true, "fullscreen": false}  # haze: light-catching air (gritty look only); film: vignette and grain over the picture; fullscreen: fill the screen instead of a window
var map_name := "my_map"   # the custom map named on the single-player page
var edit_map := ""          # set to a map's name to open it in the editor on the next load
var custom_map := ""        # set to a map's name to play on it instead of the town
var new_map_size := 1200.0
var skip_menu := false
var range_next := false  # the next scene load is the sound range, whatever mode is saved  # set when restarting a match, so it goes straight back into play


func _ready() -> void:
	if AudioServer.get_bus_effect_count(0) == 0:
		# Many loud sounds at once (a fast gun, a hit and an engine) add up past full volume,
		# which is heard as crackle. This holds the total just under it.
		var limit := AudioEffectHardLimiter.new()
		limit.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, limit)
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
			if ["Engine", "Weapons", "Effects"].has(b):
				# A low-pass that sfx.gd closes down when the player is buttoned up inside the
				# tank. Nothing else is added: a reverb here made every gun and hit sound as
				# if it were in a tunnel, and the recordings carry their own echo.
				var muffle := AudioEffectLowPassFilter.new()
				muffle.cutoff_hz = 20000.0
				AudioServer.add_bus_effect(AudioServer.bus_count - 1, muffle)
			if b == "Voice":
				# Make the crew sound like they are on a tank intercom.
				var high := AudioEffectHighPassFilter.new()
				high.cutoff_hz = 450.0
				var low := AudioEffectLowPassFilter.new()
				low.cutoff_hz = 3200.0
				var grit := AudioEffectDistortion.new()
				grit.mode = AudioEffectDistortion.MODE_OVERDRIVE
				grit.drive = 0.3
				for fx in [high, low, grit]:
					AudioServer.add_bus_effect(AudioServer.bus_count - 1, fx)
		volumes[b] = 0.8
	for a in ACTIONS:
		bindings[a[0]] = a[2]
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for a in ACTIONS:
			bindings[a[0]] = str(cfg.get_value("keys", a[0], a[2]))
		for b in BUSES:
			volumes[b] = clampf(float(cfg.get_value("volume", b, 0.8)), 0.0, 1.0)
		sensitivity = clampf(float(cfg.get_value("mouse", "sensitivity", 1.0)), 0.2, 3.0)
		mode_id = str(cfg.get_value("game", "mode", "push"))
		player_name = str(cfg.get_value("player", "name", player_name))
		inf_sight = str(cfg.get_value("player", "sight", "iron"))
		for k in rules:
			rules[k] = cfg.get_value("rules", k, rules[k])
		for k in gfx:
			gfx[k] = cfg.get_value("graphics", k, gfx[k])
	for a in ACTIONS:
		_apply_binding(a[0])
	for b in BUSES:
		_apply_volume(b)


func save() -> void:
	var cfg := ConfigFile.new()
	for a in ACTIONS:
		cfg.set_value("keys", a[0], bindings[a[0]])
	for b in BUSES:
		cfg.set_value("volume", b, volumes[b])
	cfg.set_value("mouse", "sensitivity", sensitivity)
	cfg.set_value("game", "mode", mode_id)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "sight", inf_sight)
	for k in rules:
		cfg.set_value("rules", k, rules[k])
	for k in gfx:
		cfg.set_value("graphics", k, gfx[k])
	cfg.save(PATH)


func _apply_binding(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var parts: PackedStringArray = String(bindings[action]).split(":")
	if parts.size() != 2:
		return
	if parts[0] == "mouse":
		var mb := InputEventMouseButton.new()
		mb.button_index = int(parts[1]) as MouseButton
		InputMap.action_add_event(action, mb)
	else:
		var k := InputEventKey.new()
		k.physical_keycode = int(parts[1]) as Key
		InputMap.action_add_event(action, k)


func _apply_volume(bus: String) -> void:
	var i := AudioServer.get_bus_index(bus)
	var v: float = volumes[bus]
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func set_volume(bus: String, v: float) -> void:
	volumes[bus] = clampf(v, 0.0, 1.0)
	_apply_volume(bus)
	save()


# Full screen or a window. (Full screen here is the borderless kind: alt-tab works and is instant.)
func _apply_window() -> void:
	var full: bool = gfx.get("fullscreen", false)
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if full and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not full and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# F11, or Alt+Enter, switches between full screen and a window from anywhere in the game.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed)):
		set_gfx("fullscreen", not bool(gfx.get("fullscreen", false)))
		get_viewport().set_input_as_handled()


func set_gfx(key: String, value) -> void:
	gfx[key] = value
	save()
	apply_graphics()


# Puts the graphics choices into effect: the ones that belong to the window and the screen
# here, the ones that belong to the scene's light and air in main.gd (apply_look).
func apply_graphics() -> void:
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(gfx["aa"]), 0, 2)]
	vp.scaling_3d_scale = clampf(float(gfx["scale"]), 0.5, 1.0)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if gfx["vsync"] else DisplayServer.VSYNC_DISABLED)
		_apply_window()
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("apply_look"):
		scene.apply_look()


func set_rule(key: String, value) -> void:
	rules[key] = value
	save()


func set_mode(id: String) -> void:
	mode_id = id
	save()


func vehicle_enabled(id: String) -> bool:
	return not rules["disabled"].has(id)


# Turns a vehicle on or off for players and bots. The last one left cannot be turned off.
func set_vehicle_enabled(id: String, on: bool) -> bool:
	var off: Array = rules["disabled"]
	if on:
		off.erase(id)
	elif not off.has(id):
		if off.size() >= GameData.vehicle_order.size() - 1:
			return false
		off.append(id)
	save()
	return true


# The vehicles a bot of this role may pick: enabled ones of the role, or failing that
# any enabled vehicle.
func enabled_for_role(role_id: String) -> Array:
	var out: Array = []
	for id in GameData.vehicles_for_role(role_id):
		if vehicle_enabled(id):
			out.append(id)
	if out.is_empty():
		for id in GameData.vehicle_order:
			if vehicle_enabled(id):
				out.append(id)
	return out if not out.is_empty() else GameData.vehicle_order.duplicate()


func set_sensitivity(v: float) -> void:
	sensitivity = clampf(v, 0.2, 3.0)
	save()


# Binds an action to the key or mouse button in the event. Returns false if it cannot be used.
func set_binding(action: String, e: InputEvent) -> bool:
	if e is InputEventKey:
		bindings[action] = "key:%d" % e.physical_keycode
	elif e is InputEventMouseButton:
		bindings[action] = "mouse:%d" % e.button_index
	else:
		return false
	_apply_binding(action)
	save()
	return true


func reset_bindings() -> void:
	for a in ACTIONS:
		bindings[a[0]] = a[2]
		_apply_binding(a[0])
	save()


func binding_text(action: String) -> String:
	var parts: PackedStringArray = String(bindings.get(action, "")).split(":")
	if parts.size() != 2:
		return "unbound"
	if parts[0] == "mouse":
		return MOUSE_NAMES.get(int(parts[1]), "Mouse %s" % parts[1])
	var code := int(parts[1]) as Key
	if DisplayServer.get_name() != "headless":
		code = DisplayServer.keyboard_get_keycode_from_physical(code)
	return OS.get_keycode_string(code).replace("BraceLeft", "[").replace("BraceRight", "]").replace("BracketLeft", "[").replace("BracketRight", "]")
