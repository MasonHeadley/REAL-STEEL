extends Node3D
# Runs one Push match: builds the world, owns the player slots, spawns and respawns vehicles,
# and keeps the shared team state: who is spotted, smoke clouds, orders from pings.
#
# Command line (after "--"):
#   --preflight        check the design sheets and quit
#   --selftest         play a bots-only match fast, print the result and quit
#   --shot=<file.png>  follow a bot, save a screenshot after a few seconds and quit
#   --sniper           with --shot: take it through the gunner's sight
#   --scars            with --shot: put test hit marks on the followed tank's rear
#   --emote            with --shot: show the emote bar and an emote on the followed tank
#   --vehicle=<id>     with --shot: which vehicle to follow
#   --side             with --shot: view the followed vehicle from the side, close up
#   --menushot=<file>  save a screenshot of the start menu and quit
#   --endshot=<file>   play a 25 second match, then save a screenshot of the podium and quit
#   --mode=range --rangetest=<file>   sit in the sound range's firing lane, count what arrives,
#                      save a screenshot and quit
#   --spawnshot=<file> save a screenshot of the spawn screen and quit

const TEAM_NAMES := ["Blue", "Red"]
const TEAM_COLORS := [Color(0.3, 0.55, 1.0), Color(1.0, 0.35, 0.3)]
const BOT_NAMES := ["Anvil", "Badger", "Cobalt", "Dagger", "Ember", "Falcon", "Granite", "Hammer", "Iron", "Javelin"]
const SELFTEST_SECONDS := 240.0
const DEMO_MINUTES := 20.0   # how long the battle behind the start menu runs before it starts over
const ORDER_SECONDS := 20.0

var mode: Dictionary
var half_len := 600.0
var slots: Array = []
var tanks: Array = []
var push: PushMode
var map: PushMap
var player_slot: Dictionary = {}
var player_ctrl: PlayerCtrl
var menu
var spawn_screen
var sat_texture: Texture2D
var feed: Array = []
var msg := ""
var msg_t := 0.0
var time_left := 600.0
var elapsed := 0.0
var match_over := false
var winner := -1
var state := "playing"  # menu, playing or paused
var selftest := false
var shot_path := ""
var args: PackedStringArray
var stats := {"shots": 0, "Penetration": 0, "Ricochet": 0, "Non-penetration": 0, "modules": 0, "kills": 0}
var team_stats := [{}, {}]  # per-team tallies for the self-test
var smokes: Array = []      # {pos, radius, t, node}
var orders: Array = [{}, {}]  # the standing ping order for each team's bots
var pings: Array = []       # markers shown on the HUD and the map
const PREP_SECONDS := 20.0
const BANNER_SECONDS := 8.0
# Points: what each thing a player does is worth, the words shown for it and their colour.
const SCORE := {
	"kill": [100, "Enemy destroyed", Color(1.0, 0.82, 0.25)],
	"assist": [50, "Assist", Color(0.45, 0.72, 1.0)],
	"objective": [10, "On the objective", Color(0.5, 0.95, 0.55)],
	"infantry": [10, "Infantry", Color(0.92, 0.92, 0.92)],
}
const ASSIST_SECONDS := 15.0
const AUTOCANNON_PITCH := 0.93  # the recording played a touch low
const STREAK_STEP := 300     # points in one life for each streak level
const STREAK_BONUS := 50     # bonus per level: 50, then 100, then 150...
const PODIUM_SECONDS := 60.0 # how long the podium stays up before returning to the menu
const SUSPENSE_LEAD := 3.8   # how far into the closing sting its big moment comes, seconds
const RANGE_START := -100.0  # sound range: where on the road the player starts
const RANGE_LANE_NEAR := 90.0   # how far behind the start the firing lane begins
const RANGE_LANE := 100.0       # and how long it is

var sound_board
var range_active: Tank       # the range gun whose turn it is
var range_hit := false       # is it aiming to hit, or to miss close
var range_mg := false        # does this turn include a burst of machine gun
var range_note := ""         # what the player is currently being shot at with
var _range_t := 1.0
var _range_turn := -1
var _range_test := ""        # --rangetest=<file>: where to save the range self-test's screenshot

var _suspense_played := false

var prep_t := 0.0           # seconds until the round starts; nobody may move before then
var popups: Array = []      # the player's recent score lines: {text, colour, t}
var end_t := 0.0            # seconds since the match ended
var fade := 0.0             # 0 = clear, 1 = screen fully black
var podium_shown := false
var podium_cam := Transform3D.IDENTITY
var _tick_at := 999
var _objective_t := 0.0
var demo := false           # the bots-only battle that plays behind the start menu
var soldiers: Array = []    # toy soldiers on their feet
var downed: Array = []      # toy soldiers knocked down, waiting for a medic
var team_kills := [0, 0]
var _soldier_t := 3.0
var _next_report := 30.0
var _spot_t := 0.0
var _voice_t := 0.0
var _spotted_voice_t := 0.0
var _order_stamp := 0
const CENTRE_SPREAD := 350.0     # how far to either side of the map's middle a match's centre may fall
var dom_shift := 0.0            # domination: how far across the map this match's points have been moved
const DOM_RADIUS := 22.0        # the size of a domination ring
const DOM_SECONDS := 10.0      # how long it takes to capture one
# Where the three points are. A is nearer Blue's end and C the same distance nearer Red's,
# with B in the middle, so the ground is the same for both teams.
const DOM_PLACES := [Vector2(-240, -100), Vector2(0, 0), Vector2(240, 100)]
var dom: Array = []            # domination: [{pos, owner (-1 nobody), progress (0..1), taking (team or -1), ring, plume}]
var dom_score := [0.0, 0.0]
var netplay = null            # a networked match's go-between (netplay.gd), or null
var _sun: DirectionalLight3D
var _env: Environment
var aircraft: Array = []      # every aircraft in the match
var player_air: Aircraft     # the one the player is flying, if any
var _test_man_made := false
var player_man: Soldier      # the infantryman the player is, if they deployed on foot
var men := {}                # every soldier by his number, for a networked match
var _man_count := 0
var reward_text := ""         # what the player gained when the match ended
var spectating := false      # this player has no vehicle in the match and is only watching
const HURT_MARK_SECONDS := 2.5
var hurt_marks: Array = []   # where the player was just hit from: {at, known, t}, drawn by hud.gd
var net_client := false     # this PC is watching a match the host is playing
var dm_centre := Vector3.ZERO                       # deathmatch: the middle of this match's battlefield
var dm_spawn: Array = [Vector3.ZERO, Vector3.ZERO]  # and where each team starts
var dm_facing: Array = [Vector3.FORWARD, Vector3.BACK]


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	var want_vehicle := ""
	for a in args:
		if a == "--selftest":
			selftest = true
		elif a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--vehicle="):
			want_vehicle = a.substr(10)
		elif a.begins_with("--editmap="):   # open the map editor on this map
			Settings.edit_map = a.substr(10)
		elif a.begins_with("--custommap="): # play on this map
			Settings.custom_map = a.substr(12)
	for e in GameData.errors:
		push_error("sheet: " + e)
		print("PREFLIGHT ", e)
	if args.has("--preflight") or not GameData.errors.is_empty():
		print("PREFLIGHT %s (%d problems)" % ["clean" if GameData.errors.is_empty() else "FAILED", GameData.errors.size()])
		get_tree().quit(0 if GameData.errors.is_empty() else 1)
		return

	var mode_id: String = Settings.mode_id
	if mode_id == "range":
		mode_id = "push"  # the range is never the saved mode; it is asked for each time
	for a in args:
		if a.begins_with("--mode="):  # for tests: play this mode without changing the saved choice
			mode_id = a.substr(7)
	if Settings.range_next:
		Settings.range_next = false
		mode_id = "range"
	mode = GameData.modes[mode_id if GameData.modes.has(mode_id) else "push"]
	var on_range: bool = mode["kind"] == "range"
	if on_range:
		Settings.skip_menu = true
	half_len = mode["path_half_length"]
	time_left = 999999.0 if on_range else float(Settings.rules["minutes"]) * 60.0
	if demo:
		time_left = DEMO_MINUTES * 60.0
	var spawn_shot := false
	for a in args:
		spawn_shot = spawn_shot or a.begins_with("--spawnshot=") or a.begins_with("--endshot=")
	# Unless something asks to go straight into a match, open on the start menu with a
	# bots-only battle running behind it.
	demo = not (selftest or shot_path != "" or spawn_shot or Settings.skip_menu)
	Settings.skip_menu = false
	state = "menu" if demo else "playing"
	if demo:
		Net.in_match = false  # back at the menu: whatever match there was is over
	elif Net.in_match:
		netplay = load("res://scripts/netplay.gd").new()
		netplay.name = "Netplay"
		netplay.main = self
		add_child(netplay)
		net_client = not multiplayer.is_server()
		Net.closed.connect(func(_reason: String): restart(false))
	Prop.remote = net_client
	# A real match opens with a countdown, so there is time to choose a vehicle.
	prep_t = 0.0 if (demo or selftest or shot_path != "" or on_range) else PREP_SECONDS
	Fx.enabled = not selftest
	_environment()
	map = PushMap.new()
	add_child(map)
	if Settings.edit_map != "":
		map.plan = MapFile.read(Settings.edit_map, Settings.new_map_size)
	elif Settings.custom_map != "" and not on_range and not demo:
		map.plan = MapFile.read(Settings.custom_map)
	map.build(self)
	if Settings.edit_map != "":
		# The map editor: no match, no players, just the map and the tools to change it.
		state = "editor"
		var editor = load("res://scripts/editor.gd").new()
		editor.main = self
		add_child(editor)
		set_physics_process(false)
		return
	if roaming():
		if netplay != null:
			seed(Net.match_seed)  # so every PC picks the same starting places
		_pick_dm_spawns()
		randomize()
	if mode["kind"] == "domination":
		_make_points()
	_capture_satellite()
	push = PushMode.new()
	add_child(push)
	push.setup(self, mode)
	push.visible = mode["kind"] == "push"

	player_ctrl = PlayerCtrl.new()
	player_ctrl.main = self
	player_ctrl.demo = demo
	player_ctrl.auto = selftest or shot_path != ""
	player_ctrl.force_sniper = args.has("--sniper")
	add_child(player_ctrl)

	var layer := CanvasLayer.new()
	add_child(layer)
	var hud = load("res://scripts/hud.gd").new()
	hud.main = self
	layer.add_child(hud)
	spawn_screen = load("res://scripts/spawn_screen.gd").new()
	spawn_screen.main = self
	add_child(spawn_screen)
	if on_range:
		sound_board = load("res://scripts/sound_board.gd").new()
		sound_board.main = self
		add_child(sound_board)
		_mark_firing_lane()

	_make_slots(want_vehicle)
	Sfx.muted = selftest
	menu = load("res://scripts/menu.gd").new()
	menu.main = self
	add_child(menu)
	for a in args:
		if a.begins_with("--menushot="):
			get_tree().create_timer(26.0 if args.has("--late") else (8.5 if args.has("--early") else 14.0), true).timeout.connect(_save_shot.bind(a.substr(11)))
		elif a.begins_with("--spawnshot="):
			get_tree().create_timer(9.0, true).timeout.connect(_save_shot.bind(a.substr(12)))
		elif a.begins_with("--endshot="):
			# Test: a very short bots-only match, then straight through the ending.
			prep_t = 0.0
			time_left = 25.0
			for slot in slots:
				if slot["is_player"]:
					slot["is_player"] = false
					slot["vehicle_id"] = "bastion"
					slot["ready"] = true
			get_tree().create_timer(25.0 + BANNER_SECONDS + 4.5, true).timeout.connect(_save_shot.bind(a.substr(10)))
	if demo:
		menu.show_page("lobby" if Net.active else "main")
	Sfx.music(demo)
	if selftest:
		Engine.time_scale = 8.0
		Engine.max_physics_steps_per_frame = 16


var _sky: ProceduralSkyMaterial

func _environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 350.0
	add_child(sun)
	_sun = sun
	# Outdoors: a sky with broken cloud. Its colours are set in apply_look.
	var env := Environment.new()
	_sky = ProceduralSkyMaterial.new()
	_sky.sun_angle_max = 12.0
	var cloud := FastNoiseLite.new()
	cloud.seed = 5
	cloud.frequency = 0.006
	cloud.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 0.78, 1.0])
	ramp.colors = PackedColorArray([Color.BLACK, Color.BLACK, Color(0.55, 0.55, 0.55), Color(0.9, 0.9, 0.9)])
	var clouds := NoiseTexture2D.new()
	clouds.width = 1024
	clouds.height = 512
	clouds.seamless = true
	clouds.noise = cloud
	clouds.color_ramp = ramp
	_sky.sky_cover = clouds
	var sky := Sky.new()
	sky.sky_material = _sky
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.fog_sky_affect = 0.3
	env.background_color = Color(0.93, 0.92, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.8, 0.76)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	_film_layer()
	Settings.apply_graphics()


# The scene's share of the graphics settings: shadows, and the look of the light and air.
# "Gritty" is the dark, worn battlefield look: flatter colour, harder contrast, a brown haze
# that swallows the distance, and a lower, warmer light. Without it the game is bright and clean.
func apply_look() -> void:
	if _env == null:
		return
	var g: Dictionary = Settings.gfx
	_sun.shadow_enabled = int(g["shadows"]) > 0
	_sun.directional_shadow_max_distance = 350.0 if int(g["shadows"]) >= 2 else 140.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(g["shadows"]) >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.shadow_blur = 1.5
	_env.ssao_enabled = g["ssao"]
	_env.ssao_radius = 1.6
	_env.ssao_intensity = 2.4
	var gritty: bool = g["gritty"]
	# Bloom: bright flashes and fire spread a soft glow. The gritty look uses the stronger,
	# film-like version from the trailer stills (tools/trailer_shots.gd).
	_env.glow_enabled = g["glow"]
	_env.glow_normalized = false
	_env.glow_intensity = 0.9 if gritty else 0.5
	_env.glow_bloom = 0.06 if gritty else 0.0
	_env.glow_hdr_threshold = 1.1 if gritty else 1.0
	_env.glow_hdr_scale = 2.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for i in 7:
		_env.set_glow_level(i, 1.0 if i in ([1, 3, 5] if gritty else [2, 4]) else 0.0)
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES if gritty else Environment.TONE_MAPPER_LINEAR
	_env.tonemap_white = 6.0 if gritty else 1.0
	# The colour grade: flatter, harder colour, and a curve that lifts the blacks towards a dark
	# teal-green and dulls the whites towards a warm cream, like worn film stock.
	_env.adjustment_enabled = gritty
	_env.adjustment_saturation = 0.68
	_env.adjustment_contrast = 1.24
	_env.adjustment_brightness = 0.93
	_env.adjustment_color_correction = _film_grade() if gritty else null
	_env.fog_enabled = gritty
	_env.fog_light_color = Color(0.52, 0.5, 0.45)
	_env.fog_density = 0.0014
	_env.fog_aerial_perspective = 0.35
	_env.fog_sun_scatter = 0.25
	_env.fog_sky_affect = 0.45
	# Haze that catches the light: thin dusty air that the sun shines through.
	_env.volumetric_fog_enabled = gritty and bool(g.get("haze", true))
	_env.volumetric_fog_density = 0.0019
	_env.volumetric_fog_albedo = Color(0.7, 0.67, 0.62)
	_env.volumetric_fog_anisotropy = 0.3
	_env.volumetric_fog_length = 220.0
	_env.volumetric_fog_detail_spread = 2.0
	_env.volumetric_fog_gi_inject = 0.6
	_env.volumetric_fog_sky_affect = 0.0
	# The sky: grey and heavy for the gritty look, blue otherwise. The ground colour is what
	# shows below the horizon, where the far hills end.
	_sky.sky_top_color = Color(0.25, 0.28, 0.32) if gritty else Color(0.22, 0.42, 0.78)
	_sky.sky_horizon_color = Color(0.55, 0.53, 0.49) if gritty else Color(0.68, 0.8, 0.92)
	_sky.ground_horizon_color = _sky.sky_horizon_color
	_sky.ground_bottom_color = Color(0.25, 0.27, 0.23) if gritty else Color(0.3, 0.33, 0.27)
	_sky.sky_cover_modulate = Color(0.46, 0.44, 0.42) if gritty else Color(0.85, 0.85, 0.85)
	_env.background_color = Color(0.55, 0.53, 0.49) if gritty else Color(0.93, 0.92, 0.88)
	_env.ambient_light_color = Color(0.62, 0.62, 0.6) if gritty else Color(0.82, 0.8, 0.76)
	_env.ambient_light_energy = 0.5 if gritty else 0.7
	_sun.light_color = Color(1.0, 0.9, 0.78) if gritty else Color.WHITE
	_sun.light_energy = 1.4 if gritty else 1.0
	_film.visible = bool(g.get("film", true))
	Fx.enabled = not selftest and bool(g["particles"])


# The gritty look's colour grade, as a curve for each of red, green and blue: what black,
# middle grey and white become.
func _film_grade() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.035, 0.05, 0.055), Color(0.47, 0.46, 0.42), Color(1.0, 0.93, 0.8)])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


# A pass over the finished 3D picture, under the HUD and menus: slight colour fringing at the
# edges, film grain and darkened corners. Shown or hidden by the "film look" setting.
var _film: CanvasLayer

func _film_layer() -> void:
	_film = CanvasLayer.new()
	_film.layer = -1  # above the 3D world, below the HUD and every menu
	add_child(_film)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float vignette = 0.5;
uniform float grain = 0.045;
uniform float fringe = 0.0025;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + fract(TIME) * 61.0) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	vec2 off = d * dot(d, d) * fringe * 4.0;
	vec3 c = vec3(texture(screen, uv + off).r, texture(screen, uv).g, texture(screen, uv - off).b);
	float edge = length(d * vec2(1.0, 0.78));
	c *= mix(1.0 - vignette, 1.0, smoothstep(0.78, 0.22, edge));
	float n = hash(floor(FRAGCOORD.xy)) - 0.5;
	c += n * grain * (1.0 - 0.6 * dot(c, vec3(0.33)));
	COLOR = vec4(c, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	_film.add_child(rect)


# A straight-down photograph of the map, taken once, for the spawn screen.
# Blue's end of the map is at the bottom of the picture.
func _capture_satellite() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, int(1600.0 * PushMap.HALF_WIDTH / map.half_len))  # the same shape as the map
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	vp.world_3d = get_world_3d()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = PushMap.HALF_WIDTH * 2.0  # the picture's height; its width covers the map's length
	cam.far = 2000.0
	cam.cull_mask = 1
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.12, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.75)
	cam.environment = env
	vp.add_child(cam)
	# Looking straight down with Red's end to the right and the left flank at the top.
	cam.global_transform = Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3(0, 700, 0))
	sat_texture = vp.get_texture()


# Where a world position sits on the satellite picture, as a 0..1 fraction of its size.
# The picture is landscape: Blue's end on the left, Red's on the right.
func map_uv(pos: Vector3) -> Vector2:
	return Vector2((pos.z + map.half_len) / (map.half_len * 2.0), (PushMap.HALF_WIDTH - pos.x) / (PushMap.HALF_WIDTH * 2.0))


# One slot's worth of fields. A slot is a seat in the match: a player or a bot, and the
# vehicle it currently has.
func _slot(id: int, team: int, index: int, is_player: bool, slot_name: String, vehicle: String) -> Dictionary:
	return {
		"team": team, "index": index, "is_player": is_player, "camera": is_player,
		"name": slot_name, "vehicle_id": vehicle, "lane": 1, "ready": not is_player,
		"tank": null, "respawn_t": 0.0, "id": id,
		"kills": 0, "deaths": 0, "assists": 0, "points": 0, "used": {},
	}


# The sound range has no teams as such: the player, a row of targets up the road to shoot
# at, and a battery of guns down the road that fire on anyone in the firing lane.
func _make_range_slots() -> void:
	player_slot = _slot(0, 0, 2, true, "You", "")
	for a in args:
		if a.begins_with("--rangetest="):
			_range_test = a.substr(12)
			player_slot["vehicle_id"] = "lancer"
			player_slot["ready"] = true
	player_slot["post"] = path_pos(RANGE_START)
	player_slot["heading"] = PI
	slots.append(player_slot)
	var targets := [["bastion", 80.0], ["lancer", 170.0], ["wasp", 260.0], ["hornet", 380.0]]
	for i in targets.size():
		var s := _slot(slots.size(), 1, i, false, "Target %d" % (i + 1), targets[i][0])
		s["post"] = path_pos(RANGE_START + float(targets[i][1])) + Vector3(-6.0 if i % 2 == 0 else 6.0, 0, 0)
		s["heading"] = 0.0
		s["job"] = "target"
		slots.append(s)
	var guns := ["wasp", "bulldog", "bastion", "thumper"]
	for i in guns.size():
		var s := _slot(slots.size(), 1, i, false, "Range gun", guns[i])
		s["post"] = path_pos(RANGE_START - 380.0) + Vector3((float(i) - 1.5) * 12.0, 0, 0)
		s["heading"] = PI
		s["job"] = "gun"
		slots.append(s)


# The stretch of road where the range guns will engage: RANGE_LANE metres long, starting
# RANGE_LANE_NEAR metres behind where the player starts.
func in_firing_lane(pos: Vector3) -> bool:
	var s := pos.z
	return s < RANGE_START - RANGE_LANE_NEAR and s > RANGE_START - RANGE_LANE_NEAR - RANGE_LANE and absf(pos.x - path_x(s)) < 11.0


# Red and white bars across both ends of the firing lane, and signs saying what is where.
func _mark_firing_lane() -> void:
	var red := MeshUtil.material(Color(0.9, 0.15, 0.1), 0.6)
	var white := MeshUtil.material(Color(0.95, 0.95, 0.95), 0.6)
	for end in [RANGE_START - RANGE_LANE_NEAR, RANGE_START - RANGE_LANE_NEAR - RANGE_LANE]:
		var at: Vector3 = path_pos(end)
		for k in 10:
			MeshUtil.box(self, Vector3(2.0, 0.12, 1.4), at + Vector3((float(k) - 4.5) * 2.0, 0.2, 0), red if k % 2 == 0 else white)
	var s := RANGE_START - RANGE_LANE_NEAR
	while s > RANGE_START - RANGE_LANE_NEAR - RANGE_LANE:
		for side in [-1.0, 1.0]:
			MeshUtil.box(self, Vector3(0.4, 0.12, 5.0), path_pos(s) + Vector3(side * 10.0, 0.2, 0), red)
		s -= 10.0
	var signs := [[RANGE_START - RANGE_LANE_NEAR + 14.0, "FIRING LANE\ndrive in to be shot at", PI], [RANGE_START + 30.0, "TARGETS\nup the road", PI]]
	for sg in signs:
		var l := Label3D.new()
		l.text = sg[1]
		l.font_size = 160
		l.pixel_size = 0.02
		l.outline_size = 40
		l.modulate = Color(1.0, 0.9, 0.4)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = path_pos(sg[0]) + Vector3(0, 9.0, 0)
		add_child(l)


# Runs the range's guns. While the player is in the lane, one gun at a time takes a turn every
# few seconds, so each sound is heard on its own: a full round of near misses, then a round of
# hits, with a burst of machine gun on every other turn.
func _range_tick(delta: float) -> void:
	range_note = ""
	if not player_ctrl.has_tank():
		range_active = null
		return
	var mine: Tank = player_ctrl.tank
	if _range_test != "":
		# Self-test: sit in the firing lane and count what arrives, then photograph it.
		var spot := path_pos(RANGE_START - RANGE_LANE_NEAR - 50.0)
		mine.global_position = Vector3(spot.x, mine.global_position.y, spot.z)
		if elapsed > 24.0:
			var hits := 0
			for k in team_stats[1]:
				if String(k).begins_with("hit_"):
					hits += int(team_stats[1][k])
			print("RANGETEST guns_fired=%d hits_on_player=%d targets=%d note='%s'" % [team_stats[1].get("shots", 0), hits, tanks.size() - 1, range_note])
			var path := _range_test
			_range_test = ""
			_save_shot(path)
	mine.hp = minf(mine.max_hp, mine.hp + mine.max_hp * 0.25 * delta)  # patched up as fast as it is hit
	mine.refresh_damage_look()
	if not in_firing_lane(mine.global_position):
		range_active = null
		_range_t = 1.0
		return
	var guns: Array = []
	for slot in slots:
		if slot.get("job", "") == "gun" and slot["tank"] != null:
			guns.append(slot["tank"])
	if guns.is_empty():
		return
	_range_t -= delta
	if _range_t <= 0.0:
		_range_t = 3.5
		_range_turn += 1
		range_active = guns[_range_turn % guns.size()]
		range_hit = (_range_turn / guns.size()) % 2 == 1
		range_mg = _range_turn % 2 == 1
	if range_active != null and is_instance_valid(range_active):
		range_note = "%s  -  %s%s  -  %s" % [range_active.def["name"], range_active.current_shell()["name"], "  +  machine gun" if range_mg else "", "aimed to HIT" if range_hit else "aimed to MISS close"]


# Sound range: take the player's vehicle away so another can be chosen.
func recall_player() -> void:
	if player_ctrl.has_tank():
		var t := player_ctrl.tank
		tanks.erase(t)
		t.queue_free()
	player_slot["tank"] = null
	player_slot["ready"] = false
	player_slot["respawn_t"] = 0.0
	player_ctrl.phase = "idle"


# Sound range: a squad of each side near the targets, to hear infantry fight.
func range_infantry() -> void:
	for team in 2:
		var at := path_pos(RANGE_START + 40.0 + team * 70.0)
		for id in GameData.infantry:
			var s := Soldier.new()
			s.setup(self, team, GameData.infantry[id])
			add_child(s)
			var p := at + Vector3(randf_range(-8, 8), 0, randf_range(-5, 5))
			s.global_position = Vector3(p.x, map.height(p.x, p.z), p.z)
			soldiers.append(s)


func start_range() -> void:
	Settings.range_next = true
	restart(true)


func _make_slots(want_vehicle: String) -> void:
	if mode["kind"] == "range":
		_make_range_slots()
		return
	var roles: Array = mode["team_roles"]
	if netplay != null:
		# A networked match: the lobby has already decided who sits where.
		for seat in Net.seats:
			var mine: bool = seat["peer"] == Net.my_id()
			var human: bool = seat["peer"] != 0
			var choices: Array = Settings.enabled_for_role(roles[int(seat["index"]) % roles.size()])
			var slot := _slot(seat["id"], seat["team"], seat["index"], mine, seat["name"] if human else BOT_NAMES[int(seat["id"]) % BOT_NAMES.size()], "" if human else choices[randi() % choices.size()])
			slot["human"] = human
			slot["peer"] = seat["peer"]
			slot["ready"] = not human
			slot["respawn_t"] = randf_range(0.0, 1.0)
			slots.append(slot)
			if mine:
				player_slot = slot
		if player_slot.is_empty():
			# No seat in the match: a spectator. A stand-in slot keeps the screens that ask
			# about "the player" happy; it is never given a vehicle.
			spectating = true
			player_slot = _slot(-1, 0, 0, false, "Spectator", "")
			player_slot["ready"] = true
		return
	var n := 0
	for team in 2:
		for i in roles.size():
			var camera := team == 0 and i == 0 and not demo
			var is_player := camera and not player_ctrl.auto
			var options: Array = Settings.enabled_for_role(roles[i])
			var vehicle: String = options[randi() % options.size()]
			if camera and GameData.vehicles.has(want_vehicle):
				vehicle = want_vehicle
			var slot := {
				"team": team, "index": i, "is_player": is_player, "camera": camera,
				"name": "You" if is_player else BOT_NAMES[n % BOT_NAMES.size()],
				"vehicle_id": "" if is_player else vehicle,
				"lane": 1 if roles[i] == "tank" else randi() % 3,
				"ready": not is_player,
				"tank": null, "respawn_t": randf_range(0.0, 1.0), "id": n,
				"kills": 0, "deaths": 0, "assists": 0, "points": 0, "used": {},
			}
			slots.append(slot)
			if camera:
				player_slot = slot
			n += 1


# Leaves the start menu's demo battle and begins a real match.
func start_match() -> void:
	restart(true)


# The place both teams are fighting over: the robot in Push, the middle of the map otherwise.
func objective_pos() -> Vector3:
	if mode["kind"] == "domination" and dom.size() == 3:
		return dom[1]["pos"]
	if mode["kind"] == "deathmatch":
		return dm_centre
	return path_pos(push.robot_s if mode["kind"] == "push" else 0.0)


# Where a team's infantry come into the fight: a good deal closer than the vehicles do,
# about 130 m short of the objective, tucked in behind the nearest building so they arrive
# out of sight of it.
func inf_spawn(team: int) -> Vector3:
	var fwd: Vector3 = path_forward(team)
	var want: Vector3 = objective_pos() - fwd * 130.0
	want.x = clampf(want.x, -PushMap.HALF_WIDTH + 20.0, PushMap.HALF_WIDTH - 20.0)
	want.z = clampf(want.z, -map.half_len + 20.0, map.half_len - 20.0)
	var house = map.nearest_house(Vector2(want.x, want.z), 90.0)
	if house != null:
		want = Vector3(house.x, 0, house.y) - fwd * 17.0
	var free: Vector2 = map.free_spot(Vector2(want.x, want.z))
	return Vector3(free.x, map.height(free.x, free.y), free.y)


# One of the squad's soldiers, run by the computer.
func _squad_man(team: int, id: String, at: Vector3, leader: Soldier = null) -> Soldier:
	var s := Soldier.new()
	s.leader = leader
	s.setup(self, team, GameData.infantry[id])
	add_child(s)
	var p := at + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	p = map.keep_out(p, 0.8)
	s.global_position = Vector3(p.x, map.height(p.x, p.z), p.z)
	soldiers.append(s)
	_man_count += 1
	s.net_id = _man_count
	men[s.net_id] = s
	if netplay != null:
		netplay.tell_man(s.net_id, team, id, s.global_position)
	return s


# Drops a squad of soldiers at a team's infantry start: one of each class.
func _spawn_squad(team: int) -> void:
	var at := inf_spawn(team)
	var squad: Array = []
	for id in GameData.infantry:
		for n in int(GameData.infantry[id]["squad_share"]):
			squad.append(id)
	for id in squad:
		var s := Soldier.new()
		s.setup(self, team, GameData.infantry[id])
		add_child(s)
		var p := at + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		s.global_position = Vector3(p.x, map.height(p.x, p.z), p.z)
		soldiers.append(s)
		_man_count += 1
		s.net_id = _man_count
		men[s.net_id] = s
		if netplay != null:
			netplay.tell_man(s.net_id, team, id, s.global_position)


func set_paused(on: bool) -> void:
	if state == "menu" or (match_over and on):
		return
	state = "paused" if on else "playing"
	get_tree().paused = on and netplay == null  # a networked match goes on behind the menu
	menu.show_page("pause" if on else "")
	if not on and player_ctrl.has_tank():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Starts the scene again: straight into a new match, or back to the start menu.
func restart(straight_in: bool) -> void:
	Settings.skip_menu = straight_in
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func team_dir(team: int) -> float:
	return 1.0 if team == 0 else -1.0


# The robot's route: s is the distance along it, from -half_len (Blue's end) through 0 at
# the centre to +half_len (Red's end). The map lays the route out (map.gd); it has turns in
# it, so "forward" is whichever way the route runs at that point, not a fixed direction.
func path_x(s: float) -> float:
	return map.route_at(s).x


func path_pos(s: float) -> Vector3:
	var p: Vector2 = map.route_at(s)
	return Vector3(p.x, map.height(p.x, p.y), p.y)


# How far along the route the objective is.
func objective_s() -> float:
	return push.robot_s if mode["kind"] == "push" else 0.0


# The direction along the route at the objective, towards the enemy's end for this team.
func path_forward(team: int) -> Vector3:
	if roaming():
		var across: Vector3 = dm_spawn[1 - team] - dm_spawn[team]
		return Vector3(across.x, 0, across.z).normalized()
	return map.route_dir(objective_s()) * team_dir(team)


# Where a team's vehicle would appear if it deployed now in the given lane.
func spawn_point(team: int, lane: int, index: int) -> Vector3:
	var dir := team_dir(team)
	var end := half_len + 80.0
	# The team forms up on its street in two files, a street's width apart, one pair behind
	# another. The lane shifts the whole column a little to one side. If the place is taken
	# (someone is still sitting where they deployed) the next place back is used instead.
	# Where the column forms up, and which way it faces. B (the middle choice) is on the
	# team's own street. A and C are on the nearest other street about 150 m out to the
	# left and to the right; where there is no such street, further back instead.
	var centre: Vector2
	var facing: Vector3
	if roaming():
		centre = Vector2(dm_spawn[team].x, dm_spawn[team].z)
		facing = dm_facing[team]
	else:
		var s0 := dir * clampf(push.robot_s * dir - float(mode["spawn_behind_robot"]), -end, end)
		centre = map.route_at(s0)
		facing = map.route_dir(s0) * dir
	if lane != 1:
		var out := facing.cross(Vector3.UP) * (-1.0 if lane == 0 else 1.0)
		var street: Array = map.nearest_street(centre + Vector2(out.x, out.z) * 150.0)
		var gap: float = street[0].distance_to(centre)
		if gap < 90.0 or gap > 240.0:
			street = map.nearest_street(centre - Vector2(facing.x, facing.z) * (130.0 if lane == 0 else 260.0))
		var to_fight := objective_pos() - Vector3(street[0].x, 0, street[0].y)
		var along := Vector3(street[1].x, 0, street[1].y)
		centre = street[0]
		facing = along if along.dot(to_fight) >= 0.0 else -along
	var across := facing.cross(Vector3.UP)
	var spot := Vector3.ZERO
	for place in range(index, index + 10):
		var at := centre - Vector2(facing.x, facing.z) * (float(place / 2) * 13.0)
		var off := (float(place % 2) - 0.5) * 8.0
		var x := clampf(at.x + across.x * off, -PushMap.HALF_WIDTH + 30.0, PushMap.HALF_WIDTH - 30.0)
		var z := clampf(at.y + across.z * off, -map.half_len + 30.0, map.half_len - 30.0)
		var p: Vector2 = map.free_spot(Vector2(x, z))
		spot = Vector3(p.x, map.height(p.x, p.y), p.y)
		var taken := false
		for t in tanks:
			taken = taken or t.global_position.distance_to(spot) < 7.5
		if not taken:
			break
	return spot

# Deathmatch has no route to line up on, so each match the two teams start at opposite ends
# of a line through a point near the middle of the map: the point and the direction of the
# line are picked afresh every time, so no two matches open the same way.
func _pick_dm_spawns() -> void:
	if map.plan.get("spawns", []).size() == 2:
		# A custom map says where each team starts; they face the middle.
		dm_centre = Vector3(0, map.height(0, 0), 0)
		for team in 2:
			var at: Array = map.plan["spawns"][team]
			dm_spawn[team] = Vector3(at[0], 0, at[1])
			dm_facing[team] = (Vector3.ZERO - dm_spawn[team]).normalized() if dm_spawn[team].length() > 1.0 else Vector3.FORWARD
		return
	# The middle of this match's fight can be anywhere across the map: up at the shopping
	# centre, down in the park, or anywhere between (CENTRE_SPREAD metres either side).
	var centre := Vector2(randf_range(-CENTRE_SPREAD, CENTRE_SPREAD), randf_range(-140.0, 140.0))
	var angle := randf() * TAU
	if absf(centre.x) > 150.0:
		# Far out to one side there is no room for a team beyond it: the teams face each
		# other roughly along the map's length instead, so both start the same distance away.
		angle = (PI * 0.5 if randf() < 0.5 else -PI * 0.5) + randf_range(-0.6, 0.6)
	if mode["kind"] == "domination":
		# Domination: Blue from its end of the map, Red from the other, and the three points
		# moved bodily across the map by the same random amount.
		dom_shift = centre.x
		centre = Vector2(dom_shift, 0.0)
		angle = -PI * 0.5
	var middle: Array = map.nearest_street(centre)
	dm_centre = Vector3(middle[0].x, map.height(middle[0].x, middle[0].y), middle[0].y)
	for team in 2:
		var out := Vector2(cos(angle), sin(angle)) * (1.0 if team == 0 else -1.0)
		var want := centre + out * 330.0
		want.x = clampf(want.x, -PushMap.HALF_WIDTH + 50.0, PushMap.HALF_WIDTH - 50.0)
		want.y = clampf(want.y, -map.half_len + 110.0, map.half_len - 110.0)
		var street: Array = map.nearest_street(want)
		dm_spawn[team] = Vector3(street[0].x, 0, street[0].y)
		# Facing along their street, whichever way is more towards the middle.
		var along := Vector3(street[1].x, 0, street[1].y)
		dm_facing[team] = along if along.dot(dm_centre - dm_spawn[team]) >= 0.0 else -along


# Called by the spawn screen when the player presses Deploy.
func deploy_player(vehicle_id: String, lane: int) -> void:
	player_slot["vehicle_id"] = vehicle_id
	player_slot["look"] = Profile.loadout(vehicle_id)  # the loadout chosen for this vehicle
	player_slot["lane"] = lane
	player_slot["ready"] = true
	if net_client:
		netplay.ask_pick(vehicle_id, lane, player_slot["look"])


# Adds to a player's score. The local player also sees the line and hears it.
func award(slot: Dictionary, what: String, detail: String = "") -> void:
	var s: Array = SCORE[what]
	slot["points"] += int(s[0])
	# Streaks: every STREAK_STEP points earned without dying pays a growing bonus.
	var before := int(slot.get("life_points", 0))
	slot["life_points"] = before + int(s[0])
	var level := int(slot["life_points"]) / STREAK_STEP
	if what != "streak" and level > before / STREAK_STEP:
		slot["points"] += STREAK_BONUS * level
		if slot["is_player"]:
			popups.push_front({"text": "+%d  Streak x%d" % [STREAK_BONUS * level, level], "colour": Color(1.0, 0.55, 0.2), "t": 5.0})
			Sfx.play_ui("ability", -2.0, 1.0 + level * 0.12)
	var line := "+%d  %s%s" % [s[0], s[1], ("  -  " + detail) if detail != "" else ""]
	if netplay != null and not net_client:
		netplay.tell_award(slot, line, s[2], what)
	if not slot["is_player"]:
		return
	popups.push_front({"text": line, "colour": s[2], "t": 4.0})
	if popups.size() > 5:
		popups.pop_back()
	if what == "kill":
		Sfx.play_ui("kill", 0.0)
	elif what == "assist":
		Sfx.play_ui("assist", -4.0, 0.8)


func _spawn(slot: Dictionary) -> void:
	# Each vehicle that rolls out has its own history: some fresh from the works, some
	# filthy and hung with kit.
	slot["wear"] = pow(randf(), 1.2)
	slot["wear_seed"] = randi() % 100000 + 1
	var t := Tank.new()
	t.setup(self, slot)
	var dir := team_dir(slot["team"])
	add_child(t)
	t.global_position = spawn_point(slot["team"], slot["lane"], slot["index"])
	# Facing along the route, towards the enemy's end.
	var street: Array = map.nearest_street(Vector2(t.global_position.x, t.global_position.z))
	var along := Vector3(street[1].x, 0, street[1].y)
	if along.dot(objective_pos() - t.global_position) < 0.0:
		along = -along  # along its street, whichever way leads towards the fight
	if slot.has("post"):
		# A fixed place and facing (the shooting range).
		t.global_position = slot["post"]
		along = Vector3(0, 0, 1.0 if is_equal_approx(slot["heading"], PI) else -1.0)
	t.heading = atan2(-along.x, -along.z)
	t.aim_point = t.global_position + Vector3(0, 2, 0) + along * 200.0
	if slot["camera"]:
		player_ctrl.attach(t)
		if slot["is_player"]:
			slot["ready"] = false
			Sfx.say("moving_out")
		if args.has("--scars"):
			_test_scars.call_deferred(t)
	if slot.get("job", "") == "gun":
		var gun := RangeBot.new()
		gun.main = self
		gun.tank = t
		t.add_child(gun)
	elif slot.get("job", "") == "target":
		pass  # a target just sits there
	elif slot.get("human", false) and not slot["is_player"]:
		# Someone on another PC is driving this one: it waits for their controls, and they
		# will choose again next time.
		t.track_drive = true
		slot["ready"] = false
	elif not slot["is_player"]:
		give_bot(t)
	tanks.append(t)
	slot["tank"] = t
	if netplay != null:
		netplay.tell_spawn(slot, t)
	if slot.get("greet", false):
		slot["greet"] = false
		send_emote(t, "good_luck")


func give_bot(t: Tank) -> void:
	var b := Bot.new()
	b.main = self
	b.tank = t
	t.add_child(b)


# ---- a networked match, on a PC that is not the host (see netplay.gd) ----

# The host has rolled a vehicle out: make our copy of it.
func spawn_from_host(id: int, vehicle: String, wear: float, wear_seed: int, pos: Vector3, heading: float, look: Dictionary = {}) -> void:
	if id < 0 or id >= slots.size() or not GameData.vehicles.has(vehicle):
		return
	var slot: Dictionary = slots[id]
	if not slot["camera"]:
		slot["look"] = look  # someone else's vehicle: painted and fitted out as they chose
	if slot["tank"] != null and is_instance_valid(slot["tank"]):
		tanks.erase(slot["tank"])
		slot["tank"].queue_free()
	slot["vehicle_id"] = vehicle
	slot["wear"] = wear
	slot["wear_seed"] = wear_seed
	var t := Tank.new()
	t.setup(self, slot)
	if slot["camera"]:
		t.predict = true  # ours: it answers our controls at once (see tank.gd)
		t.track_drive = true
	else:
		t.puppet = true
	add_child(t)
	t.global_position = pos
	t.heading = heading
	t.net_pos = pos
	t.net_heading = heading
	t.aim_point = pos + Vector3(-sin(heading), 0.1, -cos(heading)) * 200.0
	tanks.append(t)
	slot["tank"] = t
	if slot["camera"]:
		player_ctrl.attach(t)
		slot["ready"] = false
		Sfx.say("moving_out")


# The host says a vehicle has been destroyed.
func died_from_host(id: int, killer_id: int, how: String, who: String) -> void:
	if id < 0 or id >= slots.size():
		return
	var t = slots[id]["tank"]
	if t == null or not is_instance_valid(t):
		return
	var killer = slots[killer_id]["tank"] if killer_id >= 0 and killer_id < slots.size() else null
	if killer != null and not is_instance_valid(killer):
		killer = null
	spawn_fx(t.global_position + Vector3(0, 2, 0), 14.0, Color(1.0, 0.5, 0.1, 0.8), 0.9)
	Sfx.play("ammo", t.global_position, 4.0, 1.0, 70.0)
	tanks.erase(t)
	_leave_wreck(t)
	t.slot["tank"] = null
	t.slot["respawn_t"] = float(Settings.rules["respawn"])
	feed.push_front("%s  destroyed  %s (%s)" % [who, t.display_name, t.def["name"]])
	if feed.size() > 5:
		feed.pop_back()
	if t.slot["camera"]:
		var dist := int(killer.global_position.distance_to(t.global_position)) if killer != null else 0
		player_ctrl.start_killcam(killer, t.global_position, "Destroyed by %s  -  %s  -  %d m" % [who, how, dist])
	t.queue_free()


# The host has sent a soldier on to the field: make our copy of him.
func man_from_host(id: int, team: int, kind: String, pos: Vector3, owner_id: int = -1) -> void:
	if men.has(id) or not GameData.infantry.has(kind):
		return
	var s := Soldier.new()
	s.setup(self, team, GameData.infantry[kind])
	s.puppet = true
	s.net_id = id
	s.net_pos = pos
	s.net_seen = elapsed
	add_child(s)
	s.global_position = pos
	soldiers.append(s)
	men[id] = s
	if owner_id >= 0 and owner_id == int(player_slot.get("id", -2)):
		# He is ours: the camera and the controls go to him (the host moves him).
		s.owner_slot = player_slot
		s.arm()
		player_man = s
		player_slot["vehicle_id"] = ""
		player_slot["ready"] = true
		player_ctrl.attach_man(s)


# (Host) A soldier fired: let the other PCs see and hear it.
func soldier_fired(s: Soldier, mark: Vector3) -> void:
	if netplay != null and not net_client:
		netplay.tell_man_shot(s.net_id, mark)


# The host says the match is over.
func finish_from_host(p_winner: int) -> void:
	match_over = true
	winner = p_winner
	_reward()
	Sfx.play_ui("win" if winner == int(player_slot.get("team", 0)) else "lose", 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---- the player in the air ----

# Puts the player into the match flying the chosen aircraft. Helicopters start on their
# team's airstrip; planes start in the air above it, heading for the fight.
func deploy_aircraft(id: String, loadout: Array = []) -> void:
	Aircraft.load_sheet()
	if not Aircraft.sheet.has(id) or float(player_slot.get("respawn_t", 0.0)) > 0.0:
		return
	if prep_t > 0.0 or elapsed < air_ready_at:
		return  # aircraft wait for the round to start, and for AIR_WAIT after the last one was lost
	if net_client:
		netplay.ask_air(id, loadout)  # the host makes it, and tells us (see air_from_host)
		return
	var a := _put_aircraft(int(player_slot["team"]), id, loadout, player_slot)
	player_air = a
	player_slot["vehicle_id"] = ""
	player_slot["ready"] = true
	player_ctrl.attach_air(a)


# Makes an aircraft and sets it at its team's end of the map: a helicopter on the airstrip,
# a plane in the air above it, heading for the fight.
func _put_aircraft(team: int, id: String, loadout: Array, owner: Dictionary = {}) -> Aircraft:
	var end := -1.0 if team == 0 else 1.0
	var a := Aircraft.new()
	a.setup(self, team, id, loadout)
	a.owner_slot = owner
	_air_count += 1
	a.net_id = _air_count
	airs[a.net_id] = a
	add_child(a)
	a.yaw = PI if team == 0 else 0.0  # nose towards the middle of the map
	if a.heli:
		a.global_position = Vector3(randf_range(-60.0, 60.0), PushMap.STRIP_Y, end * PushMap.STRIP_Z)
		a.landed = true
	else:
		a.global_position = Vector3(randf_range(-80.0, 80.0), 110.0, end * (PushMap.STRIP_Z - 20.0))
		a.speed = float(a.def["speed"]) * 0.8
		a.throttle = 0.8
		a.facing = Basis(Vector3.UP, a.yaw)
		a.velocity = a.facing * Vector3.FORWARD * a.speed
	a.rotation.y = a.yaw
	aircraft.append(a)
	if netplay != null and not net_client:
		netplay.tell_air(a)
	return a


# (A PC watching the host's match) The host has put an aircraft up: make our copy of it. If
# it is the one we asked for, we are now flying it.
func air_from_host(net_id: int, team: int, id: String, loadout: Array, pos: Vector3, yaw: float, owner_id: int) -> void:
	Aircraft.load_sheet()
	if airs.has(net_id) or not Aircraft.sheet.has(id):
		return
	var a := Aircraft.new()
	a.setup(self, team, id, loadout)
	a.puppet = true
	a.net_id = net_id
	a.net_pos = pos
	a.net_rot = Quaternion(Vector3.UP, yaw)
	a.yaw = yaw
	a.facing = Basis(Vector3.UP, yaw)
	airs[net_id] = a
	add_child(a)
	a.global_position = pos
	a.rotation.y = yaw
	aircraft.append(a)
	if owner_id >= 0 and owner_id == int(player_slot.get("id", -2)):
		a.owner_slot = player_slot
		player_air = a
		player_slot["vehicle_id"] = ""
		player_slot["ready"] = true
		player_ctrl.attach_air(a)


# (Host) A joined player asks for an aircraft.
func air_for_slot(slot: Dictionary, id: String, loadout: Array) -> void:
	Aircraft.load_sheet()
	if not Aircraft.sheet.has(id) or prep_t > 0.0 or slot.get("tank") != null:
		return
	if not Settings.rules["helis" if Aircraft.sheet[id]["kind"] == "heli" else "planes"]:
		return
	var had = slot.get("air")
	if had != null and is_instance_valid(had) and not had.wrecked:
		return
	slot["vehicle_id"] = ""  # (so the host does not also roll a tank out for them)
	slot["ready"] = false
	var a := _put_aircraft(int(slot["team"]), id, loadout, slot)
	a.remote_pilot = true
	slot["air"] = a


# Something an aircraft, a missile carrier or a rocket man has fired, for the other PCs to
# see and hear (they show it; only the host decides what it hits).
func tell_air_fx(kind: String, from: Vector3, vel: Vector3, extra: int, east: bool) -> void:
	if netplay != null and not net_client:
		netplay.tell_air_fx(kind, from, vel, extra, east)


# ---- aircraft flown by the computer ----

var airs := {}                       # net id -> aircraft, for matching them up between PCs
var _air_count := 0
var sky_scan := [0.0, 0.0]           # until when (match time) each team's radar shows it every enemy aircraft
var _bot_air: Array = [null, null]   # each team's bot aircraft, if it has one up
var _bot_air_wait := [22.0, 30.0]    # seconds until each team's next one arrives
var air_ready_at := 0.0              # match time before which the player may not take another aircraft
const AIR_WAIT := 30.0               # seconds between losing an aircraft and being allowed another
var redeploying := false             # the player asked to redeploy: the death under way is theirs, by choice


# Once a second: a team with no bot aircraft counts down to its next one. Western types for
# Blue, Soviet ones for Red, and only the kinds the game rules allow. Not in network matches
# (aircraft are not sent between PCs yet), nor on the range.
func _bot_air_tick() -> void:
	if net_client or demo or mode["kind"] == "range":
		return
	Aircraft.load_sheet()
	for team in 2:
		if _bot_air[team] != null and is_instance_valid(_bot_air[team]) and not _bot_air[team].wrecked:
			continue
		_bot_air_wait[team] -= 1.0
		if _bot_air_wait[team] > 0.0:
			continue
		_bot_air_wait[team] = float(Settings.rules.get("air_every", 50.0))  # (set on the game rules page)
		var choices: Array = []
		for id in Aircraft.order:
			var row: Dictionary = Aircraft.sheet[id]
			if bool(row["east"]) == (team == 1) and Settings.rules["helis" if row["kind"] == "heli" else "planes"]:
				choices.append(id)
		if choices.is_empty():
			continue
		var a := _put_aircraft(team, choices[randi() % choices.size()], [])
		a.bot = true
		_bot_air[team] = a


# An aircraft has just been shot down (it is still falling). Whoever did it is paid.
func air_shot_down(a: Aircraft, by) -> void:
	var who := ""
	var slot = null
	if by is Tank:
		slot = by.slot
		who = "%s (%s)" % [by.display_name, by.def["name"]]
	elif by is Aircraft:
		who = String(by.def["name"])
		slot = by.owner_slot if not by.owner_slot.is_empty() else null
	elif by is Soldier:
		who = "Infantry"
		slot = by.owner_slot if not by.owner_slot.is_empty() else null
	if a.remote_pilot and not a.owner_slot.is_empty():
		a.owner_slot["deaths"] += 1
	if by != null and by.team != a.team:
		team_kills[1 - a.team] += 1
		if slot != null and not slot.is_empty():
			award(slot, "kill", a.def["name"])
			slot["kills"] += 1
	if redeploying and a == player_air:
		who = ""
	a.set_meta("down_text", ("Shot down by %s" % who) if who != "" else ("Redeploy" if redeploying and a == player_air else "Crashed"))
	if selftest:
		print("AIRDOWN %s (team %d) by %s after %d s" % [a.def["id"], a.team, who if who != "" else "crash", int(elapsed)])
	if netplay != null and not net_client:
		netplay.tell_air_down(a.net_id, String(a.get_meta("down_text", "Shot down")), String(feed[0]) if not feed.is_empty() else "")
	feed.push_front(("%s  shot down  %s" % [who, a.def["name"]]) if who != "" else ("%s  crashed" % a.def["name"]))
	if feed.size() > 5:
		feed.pop_back()


# It has hit the ground and burnt for a moment. If the player was flying it, the game moves
# on now: a look at whoever shot it down, then the wait to deploy again.
func air_wrecked(a: Aircraft, by) -> void:
	if a != player_air:
		return
	var killer = by if (by != null and is_instance_valid(by)) else null
	var at := a.global_position
	player_air_down(a)
	player_ctrl.start_killcam(killer, at, String(a.get_meta("down_text", "Shot down")))


# (Host) A joined player asks to redeploy: whatever they are in dies.
func redeploy_slot(slot: Dictionary) -> void:
	var t = slot.get("tank")
	var a = slot.get("air")
	var man = slot.get("man")
	if a != null and is_instance_valid(a) and not a.dying and not a.wrecked:
		a.hurt(99999.0, null)
	elif man != null and is_instance_valid(man) and man.state == "up":
		man.hurt(99999.0)
	elif t != null and is_instance_valid(t):
		t._hurt(t.max_hp * 50.0, null, "Redeploy")


# The player gives up what they are in and goes back to the deploy screen (from the pause
# menu). Whatever they were in dies the way it would if it had been shot: a tank burns and
# blows up, an aircraft falls, a soldier drops. Then a short black "redeploying" screen.
func redeploy() -> void:
	if match_over or redeploying or player_slot.is_empty():
		return
	if net_client:
		# The host does the killing; the black screen is ours to show when it has.
		if player_ctrl.has_tank() or player_ctrl.has_air() or player_ctrl.has_man():
			redeploying = true
			netplay.ask_redeploy()
		return
	var t = player_slot.get("tank")
	if player_air != null and is_instance_valid(player_air) and not player_air.dying and not player_air.wrecked:
		redeploying = true
		player_air.hurt(99999.0, null)
	elif player_man != null and is_instance_valid(player_man) and player_man.state == "up":
		redeploying = true
		player_man.hurt(99999.0)
	elif t != null and is_instance_valid(t) and not net_client:
		redeploying = true
		t._hurt(t.max_hp * 50.0, null, "Redeploy")


func player_air_down(a: Aircraft) -> void:
	if a != player_air:
		return
	player_air = null
	player_slot["ready"] = false
	player_slot["respawn_t"] = float(Settings.rules["respawn"])
	player_slot["deaths"] += 1
	air_ready_at = elapsed + AIR_WAIT
	player_ctrl.air = null
	player_ctrl.phase = "idle"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# How many of a team's helicopters are sitting on the ground within reach of a place:
# a landed helicopter helps capture, as a vehicle does.
func landed_near(pos: Vector3, reach: float, team: int) -> int:
	var n := 0
	for a in aircraft:
		if is_instance_valid(a) and a.heli and a.landed and a.team == team and a.global_position.distance_to(pos) <= reach:
			n += 1
	return n


# ---- the player on foot ----

# Makes a player's soldier: the host's own, or (host) one for a joined player, whose
# controls then arrive over the network.
func man_for_slot(slot: Dictionary, class_id: String, lane: int) -> Soldier:
	var team := int(slot["team"])
	var s := Soldier.new()
	if slot == player_slot:
		s.sight = Settings.inf_sight  # the sight the player chose on the deploy screen
		for a in args:
			if a.begins_with("--sight="):
				s.sight = a.trim_prefix("--sight=")  # (for test pictures)
	s.setup(self, team, GameData.infantry[class_id])
	s.driven = true
	s.owner_slot = slot
	s.arm()
	add_child(s)
	var at := inf_spawn(team) + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
	at = map.keep_out(at, 0.8)
	s.global_position = Vector3(at.x, map.height(at.x, at.z), at.z)
	soldiers.append(s)
	_man_count += 1
	s.net_id = _man_count
	men[s.net_id] = s
	if netplay != null:
		netplay.tell_man(s.net_id, team, class_id, s.global_position, int(slot.get("id", -1)))
	# The rest of his squad comes with him: one of each of the other classes, run by the
	# computer. They go where he goes and fight whatever is in front of them.
	for id in GameData.infantry:
		if id != class_id:
			_squad_man(team, id, s.global_position, s)
	return s


# Puts the player into the match as an infantryman of the chosen class.
func deploy_infantry(class_id: String, lane: int) -> void:
	if not GameData.infantry.has(class_id) or float(player_slot.get("respawn_t", 0.0)) > 0.0:
		return
	if net_client:
		netplay.ask_man(class_id, lane)  # the host makes him, and tells us (see man_from_host)
		return
	var s := man_for_slot(player_slot, class_id, lane)
	player_man = s
	player_slot["vehicle_id"] = ""
	player_slot["ready"] = true
	player_ctrl.attach_man(s)


func player_man_down(s: Soldier) -> void:
	if s != player_man:
		return
	player_man = null
	player_slot["ready"] = false
	player_slot["respawn_t"] = float(Settings.rules["respawn"])
	player_slot["deaths"] += 1
	player_ctrl.man = null
	player_ctrl.phase = "idle"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The camera stays on where he fell for a moment before the game moves on.
	player_ctrl.start_killcam(null, s.global_position, "You were killed")


# ---- domination ----

func roaming() -> bool:
	return mode["kind"] == "deathmatch" or mode["kind"] == "domination"


func _make_points() -> void:
	# (Moved across by this match's shift, and drawn in a little when that takes them near the edge.)
	var squeeze := 1.0 - absf(dom_shift) / CENTRE_SPREAD * 0.45
	var places: Array = DOM_PLACES.map(func(p): return Vector2(dom_shift + p.x * squeeze, p.y))
	if map.plan.get("points", []).size() == 3:
		places = map.plan["points"].map(func(p): return Vector2(p[0], p[1]))  # a custom map's own points
	for place in places:
		var pos := Vector3(place.x, map.height(place.x, place.y), place.y)
		var ring := MeshInstance3D.new()
		ring.mesh = _ground_ring(pos, DOM_RADIUS)
		var paint := StandardMaterial3D.new()
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		paint.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring.material_override = paint
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.layers = 2  # kept out of the satellite picture
		add_child(ring)
		var plume := MeshUtil.smoke(Color.WHITE, 36, 3.0)
		plume.lifetime = 5.0
		add_child(plume)
		plume.global_position = pos + Vector3(0, 1.0, 0)
		plume.emitting = true
		dom.append({"pos": pos, "owner": -1, "progress": 0.0, "taking": -1, "ring": ring, "plume": plume})
	dom_show()


# A capture ring painted on the ground: a band 0.8 m wide that rises and falls with the
# ground (and kerbs and road) all the way round, instead of a flat hoop that floats over
# a dip or sinks into a hill.
func _ground_ring(centre: Vector3, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var steps := 160
	for i in steps + 1:
		var a := TAU * i / steps
		var d := Vector2(cos(a), sin(a))
		for r in [radius - 0.8, radius]:
			var x: float = centre.x + d.x * r
			var z: float = centre.z + d.y * r
			st.add_vertex(Vector3(x, map.ground(x, z) + 0.18, z))
	return st.commit()


# The colour a point shows: its owner's, or white while nobody holds it.
func dom_colour(i: int) -> Color:
	var owner := int(dom[i]["owner"])
	return TEAM_COLORS[owner] if owner >= 0 else Color(0.95, 0.95, 0.95)


func dom_show() -> void:
	for i in dom.size():
		var c := dom_colour(i)
		dom[i]["ring"].material_override.albedo_color = c
		dom[i]["plume"].color = Color(c.r, c.g, c.b, 0.7)


# A team alone in a ring takes it over ten seconds. With both teams in it nothing changes;
# left empty, a half-finished capture drains away. Every point held scores once a second.
func _dom_tick(delta: float) -> void:
	for i in dom.size():
		var p: Dictionary = dom[i]
		var here := [0, 0]
		for t in tanks:
			if t.global_position.distance_to(p["pos"]) <= DOM_RADIUS:
				here[t.team] += 1
		for side in 2:
			here[side] += landed_near(p["pos"], DOM_RADIUS, side)
		var team := 0 if here[0] > 0 and here[1] == 0 else (1 if here[1] > 0 and here[0] == 0 else -1)
		if here[0] > 0 and here[1] > 0:
			pass  # contested
		elif team >= 0 and team != p["owner"]:
			if p["taking"] != team:
				p["taking"] = team
				p["progress"] = 0.0
			p["progress"] += delta / DOM_SECONDS
			if p["progress"] >= 1.0:
				p["owner"] = team
				p["taking"] = -1
				p["progress"] = 0.0
				dom_show()
				feed.push_front("%s team took point %s" % [TEAM_NAMES[team], "ABC"[i]])
				if netplay != null:
					netplay.tell_feed(feed[0])
				for t in tanks:
					if t.team == team and t.global_position.distance_to(p["pos"]) <= DOM_RADIUS:
						award(t.slot, "objective")
		else:
			p["progress"] = maxf(0.0, p["progress"] - delta / DOM_SECONDS)
			if p["progress"] <= 0.0:
				p["taking"] = -1
		if p["owner"] >= 0:
			dom_score[p["owner"]] += delta


# Where a bot should go in Domination: bots are shared out over the points, each making for
# "its" point unless its team already holds that one, in which case the nearest it does not.
func dom_goal(t: Tank) -> Vector3:
	var mine: Dictionary = dom[(int(t.slot["index"]) + (0 if t.team == 0 else 2)) % 3]
	if mine["owner"] != t.team:
		return mine["pos"]
	var best: Vector3 = mine["pos"]
	var best_d := INF
	for p in dom:
		var d: float = t.global_position.distance_to(p["pos"])
		if p["owner"] != t.team and d < best_d:
			best_d = d
			best = p["pos"]
	return best


# The match is over: the player's points become experience (see profile.gd).
func _reward() -> void:
	if spectating or player_slot.is_empty() or mode["kind"] == "range":
		return
	var with_people: bool = netplay != null and Net.members.size() > 1
	reward_text = Profile.add_match(int(player_slot.get("points", 0)), winner == int(player_slot.get("team", 0)), with_people)
	if reward_text.contains("LEVEL UP"):
		Sfx.play_ui("levelup", -4.0)


# A bare marker on the ground for the team to see (a tap of the ping button): no order goes with it.
func mark_ping(by: Tank, pos: Vector3) -> void:
	if net_client:
		netplay.ask_ping("", pos)
		return
	pings.append({"pos": pos, "label": "", "colour": Color(1.0, 0.9, 0.4), "t": 12.0, "team": by.team, "order": "mark", "target": null, "by": by})
	if pings.size() > 6:
		pings.pop_front()
	if netplay != null:
		netplay.tell_ping(pings[-1])
	if by.is_mine():
		Sfx.play_ui("click", -4.0, 1.4)


# Tells whoever fired a round what it did: on this PC if they are here, otherwise over the
# network to the player who fired it.
func tell_shooter(shooter, text: String, result: String) -> void:
	if shooter == null or not is_instance_valid(shooter):
		return
	if shooter.is_mine():
		show_msg(text)
		if result != "":
			shot_voice(result)
	elif netplay != null:
		netplay.tell_one(shooter.slot, text, result)


func _test_scars(t: Tank) -> void:
	var back := t.global_transform.basis.z
	var sd: Dictionary = GameData.shells["76_ap"]
	for i in 4:
		var p := t.global_transform * Vector3(-1.0 + i * 0.65, t.hull_top * 0.6, float(t.def["length"]) * 0.5)
		t.take_hit(sd, 999.0 if i % 2 == 0 else 0.0, 0.3, p, -back, back, null)


func spawn_shell(shooter: Tank, sd: Dictionary, pos: Vector3, dir: Vector3, mods: Dictionary) -> void:
	if sd["kind"] != "bullet" and shooter.def["class"] == "artillery" and shooter.auto_drop and not mods.has("indirect"):
		mods = mods.duplicate()
		mods["indirect"] = true  # dropped in from a gun that cannot see the target: it whistles on the way down
	if net_client:
		mods = mods.duplicate()
		mods["ghost"] = true  # only the host's rounds do anything
	elif netplay != null and sd["kind"] != "bullet":
		netplay.tell_shell(shooter, sd["id"], pos, dir, float(mods.get("speed", 1.0)), float(mods.get("gravity", 1.0)), mods.has("indirect"))
	var s := Shell.new()
	s.main = self
	s.def = sd
	s.mods = mods
	s.shooter = shooter
	s.shooter_rid = shooter.get_rid()
	s.team = shooter.team
	# The round carries the vehicle's own motion with it: fire sideways on the move and it
	# drifts the way you were going.
	s.vel = dir * float(sd["velocity"]) * float(mods.get("speed", 1.0)) + shooter.velocity
	add_child(s)
	s.global_position = pos
	s.look_at(pos + dir, Vector3.UP)
	if mods.has("gravity") or mods.has("indirect"):
		s.life = 45.0  # a lobbed shell is in the air far longer than a direct one
	if sd["kind"] == "bullet":
		return  # the vehicle's own machine-gun emitter makes the sound
	var calibre: float = shooter.def["gun_calibre"]
	Fx.muzzle(self, pos, dir, calibre, shooter.def["muzzle_brake"], map.height(pos.x, pos.z))
	# Each gun has its own set of recordings (gun_sound in the vehicles sheet). They are whole
	# shots with their own echo, so nothing is layered on top. Your own gun is a little louder.
	var sound: String = shooter.def["gun_sound"]
	var mine := shooter.is_mine()
	if sound == "autocannon":
		Sfx.play(sound, pos, 0.0 if mine else -5.0, AUTOCANNON_PITCH, 34.0, 0.03)  # (kept quieter and shorter-ranged than the big guns: a fast gun otherwise drowns the whole battle)
	else:
		Sfx.play(sound, pos, 4.0 if mine else 2.0, 1.0, 85.0, 0.03)
	if mine and Sfx.inside:
		# Buttoned up behind the sight you hear it from beside the breech. These play well
		# under full volume: a fast gun stacks several shots, and that used to overload and crackle.
		if sound == "autocannon":
			Sfx.play_ui(sound, -7.0, AUTOCANNON_PITCH * 0.92, "Interface")
		elif sound == "cannon_small":
			Sfx.play_ui("cannon_small_inside", 0.0)
		else:
			# No large-calibre recording from inside yet: the medium one, pitched down.
			Sfx.play_ui("cannon_mid_inside", 0.0, 0.88 if sound == "cannon_large" else 1.0)
	stats["shots"] += 1
	tally(shooter.team, "shots")


# A player's vehicle or man has been hurt: mark on that player's screen which way it came
# from. (No direction is known for some things, a mine or a crash: then the mark is a plain flash.)
func damage_from(slot, by) -> void:
	if not (slot is Dictionary) or slot.is_empty():
		return
	var known: bool = by != null and is_instance_valid(by) and by is Node3D
	var at: Vector3 = by.global_position if known else Vector3.ZERO
	if slot == player_slot:
		show_hurt(at, known)
	elif netplay != null and not net_client and int(slot.get("peer", 0)) > 1:
		netplay.tell_hurt(int(slot["peer"]), at, known)


func show_hurt(at: Vector3, known: bool) -> void:
	# Many small hits from one place (a machine gun) keep one mark alive, not a pile of them.
	for m in hurt_marks:
		if m["known"] == known and m["at"].distance_to(at) < 12.0:
			m["t"] = HURT_MARK_SECONDS
			m["at"] = at
			return
	hurt_marks.append({"at": at, "known": known, "t": HURT_MARK_SECONDS})
	if hurt_marks.size() > 8:
		hurt_marks.pop_front()


func spawn_fx(pos: Vector3, radius: float, color: Color, dur: float) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	m.material_override = mat
	add_child(m)
	m.global_position = pos
	m.scale = Vector3.ONE * radius * 0.3
	var tw := create_tween()
	tw.tween_property(m, "scale", Vector3.ONE * radius, dur)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.tween_callback(m.queue_free)


# A smoke cloud: thick puffs to look at, and a sphere nobody can see through.
func add_smoke(pos: Vector3, radius: float, seconds: float) -> void:
	if netplay != null and not net_client:
		netplay.tell_smoke(pos, radius, seconds)
	var p := MeshUtil.smoke(Color(0.82, 0.82, 0.8), 70, radius * 0.5)
	p.lifetime = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.7
	p.gravity = Vector3(0.2, 0.3, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	add_child(p)
	p.global_position = pos + Vector3(0, 3.0, 0)
	p.emitting = true
	smokes.append({"pos": pos + Vector3(0, 3.0, 0), "radius": radius, "t": seconds, "node": p})


# True when nothing solid and no smoke lies between two points.
func los(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 5)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return false
	for s in smokes:
		var c: Vector3 = s["pos"]
		var ab := to - from
		var k := clampf((c - from).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		if (from + ab * k).distance_to(c) < float(s["radius"]):
			return false
	return true


# Works out which vehicles each team can currently see. A vehicle is spotted when any enemy
# within sight range has a clear line to it, or it has been marked by a scan.
func _update_spotting() -> void:
	var sight: float = mode["sight_range"]
	var mine := player_ctrl.has_tank()
	for t in tanks:
		var seen: bool = t.revealed_t > 0.0
		if not seen:
			for a in tanks:
				if a.team != t.team and a.global_position.distance_to(t.global_position) < sight and los(a.eye(), t.global_position + Vector3(0, 1.5, 0)):
					seen = true
					break
		if not seen:
			# A player on foot spots for the team too (the bot squads do not).
			for man in soldiers:
				if man.driven and man.team != t.team and man.state == "up" and man.global_position.distance_to(t.global_position) < sight and los(man.eye(), t.global_position + Vector3(0, 1.5, 0)):
					seen = true
					break
		if seen and not t.spotted and mine and t.team != player_ctrl.tank.team and _spotted_voice_t <= 0.0:
			_spotted_voice_t = 12.0
			Sfx.say("spotted")
		t.spotted = seen


func tally(team: int, key: String) -> void:
	team_stats[team][key] = int(team_stats[team].get(key, 0)) + 1


func count_hit(result: String) -> void:
	if stats.has(result):
		stats[result] += 1
	else:
		stats["Penetration"] += 1
		stats["modules"] += 1


func show_msg(text: String) -> void:
	msg = text
	msg_t = 2.0


# The crew calls out what the player's last shot did.
func shot_voice(result: String) -> void:
	# Only a kill is "Enemy destroyed". ("Track destroyed" also ends in that word, which used
	# to set it off for a broken track.)
	if result.ends_with(" - destroyed"):
		Sfx.say("kill", true)
	elif _voice_t <= 0.0:
		_voice_t = 2.5
		Sfx.say("hit_ricochet" if result == "Ricochet" else ("hit_nonpen" if result == "Non-penetration" else "hit_pen"))


# Shows an emote above a vehicle for a few seconds.
func send_emote(t: Tank, id: String) -> void:
	if net_client:
		netplay.ask_emote(id)  # the host shows it to everyone, us included
		return
	var e: Dictionary = GameData.emotes[id]
	t.emote = id
	t.emote_t = 3.0
	var sound: String = e["sound"]
	if sound == "wow" and randf() < 0.05:
		sound = "wow_rare"  # once in a while, the other gasp
	Sfx.play(sound, t.global_position + Vector3(0, 4, 0), 2.0, e["pitch"], 25.0)
	if netplay != null:
		netplay.tell_emote(t.slot["id"], id, sound)


# A ping from the wheel: marks a spot and gives the sender's team an order for a while.
func issue_ping(by: Tank, ping_id: String, pos: Vector3) -> void:
	if net_client:
		netplay.ask_ping(ping_id, pos)
		return
	var p: Dictionary = GameData.pings[ping_id]
	var order: String = p["order"]
	var target: Tank = null
	if order == "attack":
		var best := 60.0
		for t in tanks:
			if t.team != by.team and t.spotted and t.global_position.distance_to(pos) < best:
				best = t.global_position.distance_to(pos)
				target = t
		if target == null:
			if by.is_mine():
				show_msg("No spotted enemy there")
			return
	_order_stamp += 1
	orders[by.team] = {"type": order, "pos": pos, "target": target, "by": by, "t": ORDER_SECONDS, "stamp": _order_stamp}
	pings.append({"pos": pos, "label": p["label"], "colour": Color(String(p["colour"])), "t": ORDER_SECONDS, "team": by.team, "order": order, "target": target, "by": by})
	if pings.size() > 6:
		pings.pop_front()
	if netplay != null:
		netplay.tell_ping(pings[-1])
	if by.is_mine():
		Sfx.say(p["voice"], true)
		get_tree().create_timer(1.6).timeout.connect(func(): Sfx.say("roger", true))


# Where a ping marker currently is: it sticks to a designated target or a leader.
func ping_pos(p: Dictionary) -> Vector3:
	if p["order"] == "attack" and is_instance_valid(p["target"]):
		return p["target"].global_position
	if p["order"] == "follow" and is_instance_valid(p["by"]):
		return p["by"].global_position
	if p["order"] == "rush":
		return objective_pos()
	return p["pos"]


# Pays whoever killed a vehicle and puts it in the kill feed. This happens the moment it is
# killed; a vehicle killed on the move burns for a second or three before it blows up, and
# the points and the sound must not wait for that.
func pay_kill(t: Tank, killer) -> void:
	if t.kill_paid:
		return
	t.kill_paid = true
	stats["kills"] += 1
	var who := "Infantry"  # the only thing that kills without a vehicle behind it is a grenade
	var alive: bool = killer != null and is_instance_valid(killer)
	team_kills[1 - t.team] += 1
	if not alive and t.credit != null and elapsed - t.credit_t < 5.0:
		# Killed by a player who was on foot or flying.
		award(t.credit, "kill", t.def["name"])
		t.credit["kills"] += 1
		who = String(t.credit["name"])
	# Anyone else who hurt it in the last few seconds gets an assist.
	for s in slots:
		if t.hurt_by.has(s["id"]) and elapsed - float(t.hurt_by[s["id"]]) <= ASSIST_SECONDS and not (alive and killer.slot["id"] == s["id"]):
			s["assists"] += 1
			award(s, "assist", t.def["name"])
	if alive:
		award(killer.slot, "kill", t.def["name"])
		killer.slot["kills"] += 1
		who = "%s (%s)" % [killer.display_name, killer.def["name"]]
		# Bots gloat now and then.
		if not killer.slot["is_player"] and randf() < 0.3:
			send_emote(killer, ["laugh", "wow", "well_played"][randi() % 3])
	if redeploying and t.slot.get("camera", false):
		who = "Redeploy"
	t.kill_who = who
	feed.push_front(("%s (%s)  redeployed" % [t.display_name, t.def["name"]]) if who == "Redeploy" else ("%s  destroyed  %s (%s)" % [who, t.display_name, t.def["name"]]))
	if feed.size() > 5:
		feed.pop_back()


func on_tank_died(t: Tank, killer, how: String) -> void:
	pay_kill(t, killer)
	var who: String = t.kill_who
	var alive: bool = killer != null and is_instance_valid(killer)
	tanks.erase(t)
	_leave_wreck(t)
	t.slot["tank"] = null
	t.slot["deaths"] += 1
	t.slot["respawn_t"] = 3.0 if mode["kind"] == "range" else float(Settings.rules["respawn"])
	t.slot["life_points"] = 0  # a streak ends with the vehicle
	if netplay != null:
		netplay.tell_died(t, killer if alive else null, how, who)
	if t.slot["camera"]:
		var dist := int(killer.global_position.distance_to(t.global_position)) if alive else 0
		player_ctrl.start_killcam(killer if alive else null, t.global_position, "Destroyed by %s  -  %s  -  %d m" % [who, how, dist])


# ---- out of bounds ----
# Anyone outside the battle (map.gd out_of_bounds) has OOB_SECONDS to get back before they
# are lost: a vehicle is destroyed, a soldier falls, an aircraft goes down.
const OOB_SECONDS := 10.0
var _oob := {}           # instance id -> seconds it has spent outside
var oob_left := -1.0     # the player's seconds left to get back, or -1 while inside (hud.gd draws the bar)
var _own_oob := 0.0

func _bounds_tick(delta: float) -> void:
	if mode["kind"] == "range":
		return
	var units: Array = []
	for t in tanks:
		if is_instance_valid(t):
			units.append(t)
	for s in soldiers:
		if is_instance_valid(s) and s.state == "up":
			units.append(s)
	for a in aircraft:
		if is_instance_valid(a) and not a.dying and not a.wrecked and not a.puppet:
			units.append(a)
	var seen := {}
	for u in units:
		var id: int = u.get_instance_id()
		seen[id] = true
		if not map.out_of_bounds(u.global_position, u is Aircraft):
			_oob.erase(id)
			continue
		_oob[id] = float(_oob.get(id, 0.0)) + delta
		if _oob[id] >= OOB_SECONDS:
			_oob.erase(id)
			if selftest:
				print("OOB lost ", u.name, " at ", u.global_position.round())  # (the self-test counts these)
			if u is Tank:
				u._hurt(999999.0, null, "Left the battle")
			elif u is Soldier:
				u.hit("blast")
			else:
				u.hurt(99999.0, null)
	for id in _oob.keys():
		if not seen.has(id):
			_oob.erase(id)
	_own_bounds(delta)


# The countdown on the player's own screen.
func _own_bounds(delta: float) -> void:
	var me = null
	if player_air != null and is_instance_valid(player_air) and not player_air.dying and not player_air.wrecked:
		me = player_air
	elif player_man != null and is_instance_valid(player_man) and player_man.state == "up":
		me = player_man
	elif player_slot.get("tank") != null and is_instance_valid(player_slot["tank"]):
		me = player_slot["tank"]
	if me == null or mode["kind"] == "range" or not map.out_of_bounds(me.global_position, me is Aircraft):
		_own_oob = 0.0
		oob_left = -1.0
		return
	_own_oob += delta
	oob_left = maxf(0.0, OOB_SECONDS - _own_oob)


# The burnt-out hull stays on the field for a while.
func _leave_wreck(t: Tank) -> void:
	var v := t.visual
	v.reparent(self)
	for pair in t.mats:
		pair[0].albedo_color = Color(0.07, 0.07, 0.07)
	t.turret.rotation.z = randf_range(-0.2, 0.2)
	t.gun.rotation.x = -0.1
	t.gun.visible = true
	t.smoke.emitting = true
	t.fire.emitting = true
	# It is solid: shells stop on it and vehicles cannot drive through it.
	var hulk := StaticBody3D.new()
	hulk.collision_layer = 1
	hulk.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(t.def["width"]), float(t.def["height"]) * 0.75, float(t.def["length"]))
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	hulk.add_child(shape)
	v.add_child(hulk)
	get_tree().create_timer(30.0).timeout.connect(v.queue_free)


func _tick(seconds_left: float, quiet_at: float) -> void:
	# One tick per second, creeping up from barely audible to plainly there at the end.
	var whole := int(ceil(seconds_left))
	if whole == _tick_at or whole <= 0:
		return
	_tick_at = whole
	var k := clampf(1.0 - seconds_left / quiet_at, 0.0, 1.0)
	Sfx.play_ui("tick", lerpf(-34.0, -9.0, k * k), 1.25 if whole <= 3 else 1.0)


func _physics_process(delta: float) -> void:
	if push == null:
		return
	for p in popups.duplicate():
		p["t"] -= delta
		if p["t"] <= 0.0:
			popups.erase(p)
	if match_over:
		_after_match(delta)
		return
	msg_t -= delta
	if net_client:
		# The host is playing the match; here there are only the clocks to tick: the match's,
		# and our own wait to deploy again (the deploy screen will not let us go until it is up).
		if player_slot.get("tank") == null:
			player_slot["respawn_t"] = maxf(0.0, float(player_slot.get("respawn_t", 0.0)) - delta)
		if prep_t > 0.0:
			_tick(prep_t, PREP_SECONDS)
		elif time_left <= 30.0:
			_tick(time_left, 30.0)
		for s in smokes.duplicate():
			s["t"] -= delta
			if s["t"] <= 0.0:
				s["node"].emitting = false
				get_tree().create_timer(4.0).timeout.connect(s["node"].queue_free)
				smokes.erase(s)
		for p in pings.duplicate():
			p["t"] -= delta
			if p["t"] <= 0.0:
				pings.erase(p)
		# Soldiers the host has stopped mentioning are gone.
		for id in men.keys():
			var s = men[id]
			if not is_instance_valid(s):
				men.erase(id)
			elif elapsed - s.net_seen > 4.0 and prep_t <= 0.0:
				soldiers.erase(s)
				men.erase(id)
				s.queue_free()
		if prep_t <= 0.0:
			_own_bounds(delta)  # (the host decides who is out too long; this only shows our own bar)
		return
	for slot in slots:
		if slot["tank"] == null:
			slot["respawn_t"] -= delta
			if slot["respawn_t"] <= 0.0 and slot["ready"] and slot["vehicle_id"] != "":
				if not slot["is_player"] and not slot.get("camera", false) and int(slot["deaths"]) > 0 and netplay == null and randf() < 0.35 and GameData.vehicles.has(slot["vehicle_id"]):
					# A bot coming back sometimes picks something else that does the same job.
					var others: Array = Settings.enabled_for_role(String(GameData.vehicles[slot["vehicle_id"]]["role"]))
					slot["vehicle_id"] = others[randi() % others.size()]
				_spawn(slot)
	if prep_t > 0.0:
		# Counting down to the start: vehicles may deploy, nothing else happens yet.
		_tick(prep_t, PREP_SECONDS)
		prep_t -= delta
		if prep_t <= 0.0:
			Sfx.play_ui("ability", -2.0)
			_tick_at = 999
		return
	elapsed += delta
	time_left -= delta
	_bounds_tick(delta)
	if time_left <= 30.0:
		_tick(time_left, 30.0)
	# The closing sting is timed so its big moment, 3.8 seconds in, lands on the final second.
	if time_left <= SUSPENSE_LEAD and not _suspense_played:
		_suspense_played = true
		Sfx.play_ui("suspense", -2.0)
	# Once a second: note which vehicle each player is in, and pay those holding the objective.
	_objective_t -= delta
	if _objective_t <= 0.0:
		_objective_t = 1.0
		_bot_air_tick()
		var holding: bool = mode["kind"] == "push" and push.controller >= 0
		# (Time in an aircraft or on foot counts too, under "air:<id>" or "inf:<class>".)
		var mine := ""
		if player_air != null and is_instance_valid(player_air):
			mine = "air:" + String(player_air.def["id"])
		elif player_man != null and is_instance_valid(player_man) and player_man.state == "up":
			mine = "inf:" + String(player_man.def["id"])
		if mine != "" and not player_slot.is_empty():
			player_slot["used"][mine] = int(player_slot["used"].get(mine, 0)) + 1
		for slot in slots:
			var t = slot["tank"]
			if t == null:
				continue
			slot["used"][slot["vehicle_id"]] = int(slot["used"].get(slot["vehicle_id"], 0)) + 1
			if holding and t.team == push.controller and t.global_position.distance_to(objective_pos()) <= float(mode["capture_radius"]):
				slot["hold"] = int(slot.get("hold", 0)) + 1
				if slot["hold"] % 4 == 0:
					award(slot, "objective")
	_voice_t -= delta
	_spotted_voice_t -= delta
	if mode["kind"] == "push":
		push.tick(delta)
	if mode["kind"] == "domination":
		_dom_tick(delta)
	if mode["kind"] == "range":
		_range_tick(delta)
	_soldier_t -= delta
	if _soldier_t <= 0.0 and (Settings.rules["infantry"] or state == "menu") and mode["kind"] != "range":
		_soldier_t = 7.0
		for team in 2:
			var count := 0
			for s in soldiers:
				count += 1 if s.team == team else 0
			if count <= 8:
				_spawn_squad(team)
	_spot_t -= delta
	if _spot_t <= 0.0:
		_spot_t = 0.25
		_update_spotting()
	for s in smokes.duplicate():
		s["t"] -= delta
		if s["t"] <= 0.0:
			s["node"].emitting = false
			get_tree().create_timer(4.0).timeout.connect(s["node"].queue_free)
			smokes.erase(s)
	for team in 2:
		if not orders[team].is_empty():
			orders[team]["t"] -= delta
			var o: Dictionary = orders[team]
			if o["t"] <= 0.0 or (o["type"] == "attack" and not is_instance_valid(o["target"])) or (o["type"] == "follow" and not is_instance_valid(o["by"])):
				orders[team] = {}
	for p in pings.duplicate():
		p["t"] -= delta
		if p["t"] <= 0.0 or (p["order"] == "attack" and not is_instance_valid(p["target"])):
			pings.erase(p)
	var target := int(mode["kill_target"])
	var by_kills: bool = mode["kind"] == "deathmatch" and (team_kills[0] >= target or team_kills[1] >= target)
	if mode["kind"] == "domination":
		by_kills = dom_score[0] >= target or dom_score[1] >= target
	if demo:
		# The battle behind the menu is only there to be watched: it runs its full time
		# however the score stands.
		if time_left <= 0.0:
			_end_match()
	elif push.progress[0] >= half_len or push.progress[1] >= half_len or by_kills or time_left <= 0.0:
		_end_match()

	if selftest and elapsed >= _next_report:
		_next_report += 30.0
		print("t=%ds robot=%.0f blue=%.0f red=%.0f alive=%d %s" % [int(elapsed), push.robot_s, push.progress[0], push.progress[1], tanks.size(), str(stats)])
	if selftest and elapsed >= SELFTEST_SECONDS:
		_end_match()
	if shot_path != "" and elapsed >= 14.5 and player_ctrl.has_tank() and args.has("--emote"):
		player_ctrl.emote_open = true
		if player_ctrl.tank.emote_t <= 0.0:
			send_emote(player_ctrl.tank, "laugh")
	for a in args:
		if a.begins_with("--air=") and elapsed >= 3.0:
			if player_air == null and not _test_man_made:
				_test_man_made = true
				var had = player_slot.get("tank")
				if had != null and is_instance_valid(had):
					tanks.erase(had)
					had.queue_free()
					player_slot["tank"] = null
				player_slot["respawn_t"] = 0.0
				deploy_aircraft(a.trim_prefix("--air="))
			if player_air != null and is_instance_valid(player_air):
				var ahead := Basis(Vector3.UP, player_air.yaw) * Vector3.FORWARD
				player_ctrl.yaw = player_air.yaw
				player_air.want = {"move": Vector3(0, 0, -1), "lift": 1.0 if player_air.global_position.y < 60.0 else 0.0, "yaw": player_air.yaw, "aim_dir": (ahead + Vector3(0.25 if not player_air.heli else 0.0, -0.12 if player_air.heli else 0.0, 0)).normalized(), "fire": int(elapsed) % 2 == 0, "rocket": int(elapsed * 2.0) % 5 == 0}
				# --airkill shoots the test aircraft down a few seconds before the picture is taken, to show it falling.
				if args.has("--airkill") and elapsed >= 13.2 and not player_air.dying and not player_air.wrecked:
					player_air.hurt(99999.0, null)
		if a.begins_with("--infantry=") and elapsed >= 3.0:
			if player_man == null and not _test_man_made and not player_slot.is_empty():
				_test_man_made = true
				var had = player_slot.get("tank")
				if had != null and is_instance_valid(had):
					tanks.erase(had)
					had.queue_free()
					player_slot["tank"] = null
				player_slot["respawn_t"] = 0.0
				player_slot["vehicle_id"] = ""
				deploy_infantry(a.trim_prefix("--infantry="), 1)
			if player_man != null and is_instance_valid(player_man):
				player_ctrl.yaw = player_man.rotation.y
				var into := Basis(Vector3.UP, player_ctrl.yaw) * Vector3.FORWARD
				player_man.want = {"move": Vector3(0, 0, -1), "sprint": false, "yaw": player_ctrl.yaw, "pitch": 0.0, "fire": int(elapsed) % 3 == 0, "aim": int(elapsed) % 6 < 3, "aim_from": player_man.eye(), "aim_dir": into}
				# --infmove=prone|crouch|back|left|sprint|rocket has him move that way instead, for a picture of it.
				for b in OS.get_cmdline_user_args():
					if b.begins_with("--infmove="):
						var how := b.trim_prefix("--infmove=")
						player_man.want["aim"] = how == "aim"
						if how == "aim":
							player_man.want["move"] = Vector3.ZERO
							player_man.want["fire"] = false
						player_man.want["fire"] = how == "rocket" and int(elapsed * 2.0) % 9 == 0
						player_man.want["prone"] = how == "prone"
						player_man.want["jump"] = how == "jump" and int(elapsed * 2.0) % 2 == 0
						player_man.want["crouch"] = how == "crouch"
						player_man.want["sprint"] = how == "sprint"
						player_man.want["move"] = Vector3(0, 0, 1) if how == "back" else (Vector3(-1, 0, 0) if how == "left" else (Vector3.ZERO if how == "rocket" else Vector3(0, 0, -1)))
	if shot_path != "" and elapsed >= 16.0:
		var path := shot_path
		shot_path = ""
		_save_shot(path)


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT saved ", path)
	get_tree().quit()


func _end_match() -> void:
	match_over = true
	var score: Array = push.progress if mode["kind"] == "push" else (dom_score if mode["kind"] == "domination" else team_kills)
	if score[0] > score[1]:
		winner = 0
	elif score[1] > score[0]:
		winner = 1
	if netplay != null:
		netplay.tell_end(winner)
	if demo:
		# The menu's battle just starts over.
		get_tree().create_timer(4.0).timeout.connect(restart.bind(false))
	elif selftest:
		_report_selftest()
	else:
		_reward()
		# A little tune: bright if the player's team won, glum if it lost.
		Sfx.play_ui("win" if winner == int(player_slot.get("team", 0)) else "lose", 0.0)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# The players in order of points, best first.
func ranking() -> Array:
	var order := slots.duplicate()
	order.sort_custom(func(a, b): return a["points"] > b["points"])
	return order


# After the final whistle: the banner stays up for a while, the screen fades to black, and
# then the three best players are shown on a podium.
func _after_match(delta: float) -> void:
	if demo or selftest:
		return
	end_t += delta
	if not podium_shown:
		fade = clampf((end_t - BANNER_SECONDS) / 1.2, 0.0, 1.0)
		if fade >= 1.0:
			podium_shown = true
			_build_podium()
	else:
		fade = clampf(1.0 - (end_t - BANNER_SECONDS - 1.6) / 1.2, 0.0, 1.0)
		# Nobody started another round: go back to the menu (the lobby, once there is one).
		if end_t > BANNER_SECONDS + PODIUM_SECONDS:
			restart(false)


# The podium stands on a parade ground in the hills beside the battlefield: three blocks of
# different heights, each with what that winner used most on top (a tank, an aircraft, or
# the soldier they fought as) and their name over it.
func _build_podium() -> void:
	for t in tanks.duplicate():
		t.queue_free()
	tanks.clear()
	var at := Vector3(PushMap.HALF_WIDTH + 460.0, 0.0, -300.0)
	at.y = map.far_height(at.x, at.z) + 6.0
	MeshUtil.box(self, Vector3(90.0, 40.0, 70.0), at + Vector3(0, -20.0, -6.0), MeshUtil.material(Color(0.46, 0.45, 0.43), 0.9))
	var top := ranking().slice(0, 3)
	var places := [[0.0, 9.0], [-13.0, 6.0], [13.0, 4.0]]  # x offset and block height: 1st, 2nd, 3rd
	var medal := [Color(1.0, 0.82, 0.25), Color(0.8, 0.82, 0.86), Color(0.8, 0.5, 0.25)]
	for i in top.size():
		var slot: Dictionary = top[i]
		var x: float = places[i][0]
		var h: float = places[i][1]
		var block_mat := MeshUtil.material(PushMap.BLOCK_COLOURS[i % PushMap.BLOCK_COLOURS.size()], 0.5)
		MeshUtil.box(self, Vector3(12.0, h, 12.0), at + Vector3(x, h * 0.5, 0), MeshUtil.material(Color(0.86, 0.72, 0.5), 0.6, "wood", 5.0))
		MeshUtil.box(self, Vector3(9.6, h * 0.8, 0.1), at + Vector3(x, h * 0.5, -6.02), block_mat)
		# The vehicle they spent longest in, or the one they finished in.
		var vehicle: String = slot["vehicle_id"]
		var most := 0
		for id in slot["used"]:
			if int(slot["used"][id]) > most:
				most = int(slot["used"][id])
				vehicle = id
		# (A test can say what the player should be shown as: --endas=air:apache or --endas=inf:medic.)
		for a in args:
			if a.begins_with("--endas=") and slot.get("camera", false):
				vehicle = a.trim_prefix("--endas=")
		var used_name := ""
		if GameData.vehicles.has(vehicle):
			used_name = GameData.vehicles[vehicle]["name"]
			var model: Node3D = TankModel.build(GameData.vehicles[vehicle], TEAM_COLORS[slot["team"]], slot.get("wear", 0.3), slot.get("wear_seed", 1))["root"]
			add_child(model)
			model.position = at + Vector3(x, h, 0)
			model.rotation.y = 0.5 - i * 0.5
		elif vehicle.begins_with("air:") and Aircraft.sheet.has(vehicle.trim_prefix("air:")):
			# Flew most of the match: their aircraft, shrunk a little to sit on the block.
			used_name = Aircraft.sheet[vehicle.trim_prefix("air:")]["name"]
			var craft: Node3D = AircraftModel.build(vehicle.trim_prefix("air:"), TEAM_COLORS[slot["team"]])["root"]
			add_child(craft)
			craft.scale = Vector3.ONE * 0.62
			craft.position = at + Vector3(x, h, 0)
			craft.rotation.y = 0.5 - i * 0.5
		elif vehicle.begins_with("inf:") and GameData.infantry.has(vehicle.trim_prefix("inf:")):
			# Fought on foot: the soldier, three times life size so he is not lost beside the tanks.
			var who: Dictionary = GameData.infantry[vehicle.trim_prefix("inf:")]
			used_name = who["name"]
			var man := SoldierModel.new()
			add_child(man)
			man.build(slot["team"], who["kit"])
			man.gun_low = 0.45
			man.pose(0.0)
			man.scale = Vector3.ONE * 3.0
			man.position = at + Vector3(x, h, 0)
			man.rotation.y = 0.5 - i * 0.5 + PI
		var number := Label3D.new()
		number.text = str(i + 1)
		number.font_size = 220
		number.pixel_size = 0.016
		number.modulate = medal[i]
		number.position = at + Vector3(x, h * 0.5, -6.1)
		number.rotation.y = PI
		add_child(number)
		var name_tag := Label3D.new()
		name_tag.text = "%s\n%s  -  %d points" % [slot["name"], used_name, slot["points"]]
		name_tag.font_size = 96
		name_tag.pixel_size = 0.014
		name_tag.modulate = TEAM_COLORS[slot["team"]].lightened(0.3)
		name_tag.outline_size = 24
		name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_tag.position = at + Vector3(x, h + 6.5, 0)
		add_child(name_tag)
	var lamp := SpotLight3D.new()
	lamp.light_energy = 6.0
	lamp.spot_range = 90.0
	lamp.spot_angle = 38.0
	add_child(lamp)
	lamp.global_transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 40, -30)).looking_at(at + Vector3(0, 5, 0), Vector3.UP)
	podium_cam = Transform3D(Basis.IDENTITY, at + Vector3(0, 11.0, -38.0)).looking_at(at + Vector3(0, 7.0, 0), Vector3.UP)
	player_ctrl.phase = "podium"


# Prints the bots-only test's verdict and quits.
func _report_selftest() -> void:
	if selftest:
		var ok: bool = stats["shots"] > 0 and stats["Penetration"] > 0 and stats["kills"] > 0 and (mode["kind"] != "push" or push.progress[0] > 0.0 or push.progress[1] > 0.0)
		var tk := [0, 0]
		for sl in slots:
			tk[sl["team"]] += sl["kills"]
		print("TEAMSHOTS blue=%d red=%d" % [team_stats[0].get("shots", 0), team_stats[1].get("shots", 0)])
		print("TEAMKILLS blue=%d red=%d  tanks left blue=%d red=%d  aircraft up=%d" % [tk[0], tk[1], tanks.filter(func(t): return t.team == 0).size(), tanks.filter(func(t): return t.team == 1).size(), aircraft.size()])
		print("UNSTUCK backed_out=%d still_stuck_after_4=%d" % [team_stats[0].get("backed_out", 0) + team_stats[1].get("backed_out", 0), team_stats[0].get("still_stuck_after_4", 0) + team_stats[1].get("still_stuck_after_4", 0)])
		print("INFANTRY downed=%d revived=%d" % [team_stats[0].get("downed", 0) + team_stats[1].get("downed", 0), team_stats[0].get("revived", 0) + team_stats[1].get("revived", 0)])
		print("TEAMKILLS blue=%d red=%d  %s" % [tk[0], tk[1], str(slots.map(func(x): return x["vehicle_id"]))])
		print("SELFTEST %s winner=%d blue=%.0f red=%.0f %s" % ["PASS" if ok else "FAIL", winner, push.progress[0], push.progress[1], str(stats)])
		get_tree().quit(0 if ok else 1)
