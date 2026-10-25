extends Node
# Plays the game's sounds. Synthesised effects are built ahead of time by tools/make_sfx.gd
# into sfx/<name>_<n>.pcm; recorded ones live in sfx_pack/<name>_<n>.ogg and take their place.
# A sound with several files gets a random one each time it plays.
# Each sound plays on one of the volume categories set up in settings.gd.

const RATE := 44100
const MAX_VOICES := 56
const LOOPS := ["engine", "engine_roar", "music", "heli_far", "heli_near", "heli_in", "prop_far", "prop_near", "prop_in", "jet_far", "jet_near", "jet_in"]
const BURST_VOICES := 4  # players in a machine-gun emitter; each shot takes the next one
const MUFFLED_BUSES := ["Engine", "Weapons", "Effects"]
const BUS := {
	"cannon_large": "Weapons", "cannon_mid": "Weapons", "cannon_small": "Weapons", "pop": "Weapons", "autocannon": "Weapons",
	"cannon_mid_inside": "Interface", "cannon_small_inside": "Interface", "reload": "Interface", "reload_small": "Interface",
	"mg_inside": "Interface", "mg_heavy_inside": "Interface", "ammo": "Effects",
	"mg": "Weapons", "mg_heavy": "Weapons", "inf_mg": "Weapons",
	"suspense": "Interface", "music": "Music",
	"explosion": "Effects", "dirt": "Effects", "thud": "Effects", "pen": "Effects", "ricochet": "Effects", "tink": "Effects",
	"zip": "Effects", "grenade": "Effects", "wow_rare": "Interface", "incoming": "Effects", "arty_boom": "Effects",
	"heli_far": "Engine", "heli_near": "Engine", "heli_in": "Engine", "prop_far": "Engine", "prop_near": "Engine", "prop_in": "Engine",
	"jet_far": "Engine", "jet_near": "Engine", "jet_in": "Engine",
	"click": "Interface", "ability": "Interface", "laugh": "Interface", "cry": "Interface", "angry": "Interface", "wow": "Interface",
	"whoosh": "Interface", "tick": "Interface", "kill": "Interface", "assist": "Interface", "win": "Interface", "lose": "Interface",
	"engine": "Engine", "engine_roar": "Engine", "clack": "Engine", "levelup": "Interface",
	"rocket": "Weapons", "lock_tone": "Interface", "jetby": "Engine", "propby": "Engine",
}

var streams := {}  # name -> array of variations
var muted := false
var inside := false  # the player is buttoned up in the gunner's sight
var _voices := 0
var _rng := RandomNumberGenerator.new()
var _voice_player: AudioStreamPlayer
var _voice_cache := {}
var _last_shout := 0
var _inside_gun: Node
var _music: AudioStreamPlayer
var _audition: AudioStreamPlayer
var _audition_id := 0


func _ready() -> void:
	_rng.randomize()
	for id in BUS:
		var found: Array = []
		# Recorded sounds in sfx_pack take the place of the synthesised ones.
		while ResourceLoader.exists("res://sfx_pack/%s_%d.ogg" % [id, found.size()]):
			var rec = load("res://sfx_pack/%s_%d.ogg" % [id, found.size()])
			if LOOPS.has(id) and rec is AudioStreamOggVorbis:
				rec.loop = true
			found.append(rec)
		while found.is_empty() and FileAccess.file_exists("res://sfx/%s_%d.pcm" % [id, found.size()]):
			var s := AudioStreamWAV.new()
			s.format = AudioStreamWAV.FORMAT_16_BITS
			s.mix_rate = RATE
			s.data = FileAccess.get_file_as_bytes("res://sfx/%s_%d.pcm" % [id, found.size()])
			if LOOPS.has(id):
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_end = s.data.size() / 2
			found.append(s)
		if not found.is_empty():
			streams[id] = found
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = "Voice"
	_voice_player.volume_db = 2.0
	add_child(_voice_player)
	# Two sounds that run for as long as something is going on, not once per event.
	_inside_gun = Node.new()
	_inside_gun.set_meta("db", -2.0)
	for i in BURST_VOICES:
		var v := AudioStreamPlayer.new()
		v.bus = "Interface"
		_inside_gun.add_child(v)
	add_child(_inside_gun)
	_music = AudioStreamPlayer.new()
	_music.bus = BUS["music"]
	_music.stream = _pick("music")
	_music.volume_db = -6.0
	add_child(_music)


# The player's own machine gun while buttoned up in the sight: single reports recorded from
# inside (`sound` is that gun's outside sound), played straight to the player so they are not
# muffled with the rest of the world. One per bullet; nothing sounds after the trigger is let go.
func mg_inside(sound: String) -> void:
	var stream := _pick(sound + "_inside" if streams.has(sound + "_inside") else sound)
	if muted or stream == null:
		return
	_burst(_inside_gun, stream, _rng.randf_range(0.98, 1.02))


# Plays one particular recording of a sound on its own, for the sound board. Whatever was
# being auditioned before is cut off; a looping sound stops by itself after a few seconds.
func audition(sound: String, index: int) -> void:
	var list: Array = streams.get(sound, [])
	if index >= list.size():
		return
	if _audition == null:
		_audition = AudioStreamPlayer.new()
		add_child(_audition)
	_audition.stop()
	_audition.bus = BUS[sound]
	_audition.stream = list[index]
	_audition.play()
	_audition_id += 1
	if LOOPS.has(sound):
		var mine := _audition_id
		get_tree().create_timer(4.0).timeout.connect(func():
			if _audition_id == mine:
				_audition.stop())


# Menu music. It fades out when a match starts and comes back with the menu.
func music(on: bool) -> void:
	if _music.stream == null or muted:
		return
	if on and not _music.playing:
		_music.volume_db = -6.0
		_music.play()
	elif not on and _music.playing:
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", -50.0, 1.5)
		tw.tween_callback(_music.stop)


func _pick(sound: String) -> AudioStream:
	var list: Array = streams.get(sound, [])
	return null if list.is_empty() else list[_rng.randi() % list.size()]


# Through the gunner's sight the world outside is heard through armour: dull and distant.
# (The first effect on each of those buses is the low-pass filter added in settings.gd.)
func set_inside(on: bool) -> void:
	if on == inside:
		return
	inside = on
	for b in MUFFLED_BUSES:
		var fx := AudioServer.get_bus_effect(AudioServer.get_bus_index(b), 0)
		if fx is AudioEffectLowPassFilter:
			fx.cutoff_hz = 900.0 if on else 20000.0


# Plays a one-shot sound at a place in the world. Each play is pitched very slightly up or
# down (by up to `drift`) so repeats do not sound identical. `variant` picks one particular
# recording of the sound; -1 leaves it to chance.
func play(sound: String, pos: Vector3, db: float = 0.0, pitch: float = 1.0, reach: float = 30.0, drift: float = 0.05, variant: int = -1) -> void:
	var stream := _pick(sound)
	var list: Array = streams.get(sound, [])
	if variant >= 0 and not list.is_empty():
		stream = list[mini(variant, list.size() - 1)]
	if muted or stream == null or _voices >= MAX_VOICES:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = BUS[sound]
	p.volume_db = db
	p.pitch_scale = pitch * _rng.randf_range(1.0 - drift, 1.0 + drift)
	p.unit_size = reach
	p.max_distance = 2500.0
	_open_air(p)
	scene.add_child(p)
	p.global_position = pos
	p.play()
	_count(p)


# Keeps the tally of sounds in the air. It is counted down when the player leaves the tree
# for any reason, not just when it finishes, so restarting a match cannot leave the tally
# stuck at the limit (which used to silence every gun and hit until the game was restarted).
func _count(p: Node) -> void:
	_voices += 1
	p.tree_exited.connect(func(): _voices = maxi(_voices - 1, 0))
	p.finished.connect(p.queue_free)


# A sound source fixed to a vehicle for something that repeats quickly, like a machine gun.
# It holds a few players and each shot takes the next, so a shot is never cut off by the one
# after it (see _burst).
func emitter(sound: String, db: float, reach: float) -> Node3D:
	var e := Node3D.new()
	e.set_meta("sound", sound)
	e.set_meta("db", db)
	for i in BURST_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.bus = BUS[sound]
		p.unit_size = reach
		p.max_distance = 1500.0
		_open_air(p)
		e.add_child(p)
	return e


# One shot of a burst. The shot before it is faded out quickly rather than cut, so held fire
# stays crisp, and the last round of the burst is left to ring out with its whole echo.
func _burst(e: Node, stream: AudioStream, pitch: float) -> void:
	var n: int = e.get_meta("next", 0)
	var db: float = e.get_meta("db")
	var count := e.get_child_count()
	var last := e.get_child((n + count - 1) % count)
	if last.playing:
		var fade := last.create_tween()
		fade.tween_property(last, "volume_db", db - 30.0, 0.5)
		fade.tween_callback(last.stop)
		last.set_meta("fade", fade)
	var p := e.get_child(n)
	if p.has_meta("fade") and p.get_meta("fade").is_valid():
		p.get_meta("fade").kill()
	p.volume_db = db
	p.stream = stream
	p.pitch_scale = pitch
	p.play()
	e.set_meta("next", (n + 1) % count)


# A source for a rattle made of many short sounds, like track links: every play() picks one
# of the recordings at a slightly different pitch and level, and they overlap.
func rattle(sound: String, reach: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var mix := AudioStreamRandomizer.new()
	for s in streams.get(sound, []):
		mix.add_stream(-1, s)
	mix.random_pitch = 1.05
	mix.random_volume_offset_db = 2.0
	p.stream = mix
	p.bus = BUS[sound]
	p.unit_size = reach
	p.max_distance = 300.0
	p.max_polyphony = 4
	_open_air(p)
	return p


# By default the engine dulls a sound heavily as it gets further away, which on top of an
# echoey recording sounds boxed in. Outdoors the top end fades much more gently with distance.
func _open_air(p: AudioStreamPlayer3D) -> void:
	p.attenuation_filter_cutoff_hz = 9000.0
	p.attenuation_filter_db = -8.0


func fire(e: Node3D, pitch: float = 1.0) -> void:
	if muted:
		return
	_burst(e, _pick(e.get_meta("sound")), pitch * _rng.randf_range(0.98, 1.02))


# A soldier calling out. It comes from where he stands and carries about as far as a shout
# would, so it is only heard by a vehicle that is close. Soldiers have no radio to the tanks.
func shout(id: String, pos: Vector3, pitch: float = 1.0) -> void:
	var now := Time.get_ticks_msec()
	if muted or _voices >= MAX_VOICES or now - _last_shout < 900:
		return
	var scene := get_tree().current_scene
	var path := "res://voice/%s.wav" % id
	if scene == null or not ResourceLoader.exists(path):
		return
	_last_shout = now
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.bus = "Effects"
	p.volume_db = 4.0
	p.pitch_scale = pitch
	p.unit_size = 12.0
	p.max_distance = 90.0
	scene.add_child(p)
	p.global_position = pos
	p.play()
	_count(p)


# Plays a sound straight to the player, with no position. Sounds from inside the player's
# own vehicle use this with the Interface bus so the muffling does not touch them.
func play_ui(sound: String, db: float = -6.0, pitch: float = 1.0, bus: String = "") -> void:
	var stream := _pick(sound)
	if muted or stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = BUS[sound] if bus == "" else bus
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# Speaks a crew line from voices.json. A line already being spoken is only cut off by an
# urgent one, so the crew never talk over themselves.
func say(id: String, urgent: bool = false) -> void:
	if muted or (_voice_player.playing and not urgent):
		return
	if not _voice_cache.has(id):
		var path := "res://voice/%s.wav" % id
		_voice_cache[id] = load(path) if ResourceLoader.exists(path) else null
	if _voice_cache[id] == null:
		return
	_voice_player.stream = _voice_cache[id]
	_voice_player.play()


# A looping sound that follows a vehicle: "engine" or "engine_roar".
func loop(sound: String, db: float, reach: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _pick(sound)
	p.bus = BUS[sound]
	p.volume_db = db
	p.unit_size = reach
	p.max_distance = 500.0
	p.autoplay = not muted and p.stream != null
	_open_air(p)
	return p
