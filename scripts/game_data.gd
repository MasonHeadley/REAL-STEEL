extends Node
# Loads the design sheets in res://data and checks every cell and cross-reference.

const SHELL_GRAVITY := 9.81

const COLUMNS := {
	"roles": ["id", "name", "colour", "blurb"],
	"abilities": ["id", "name", "effect", "cooldown", "duration", "armour_mult", "damage_taken_mult", "reload_mult", "radius", "heal_frac", "power", "power2", "description"],
	"shells": ["id", "name", "kind", "type", "pen", "pen_loss_per_km", "splash_radius", "damage", "velocity"],
	"vehicles": ["id", "gears", "name", "role", "class", "kind", "ability", "bot_style", "description", "length", "width", "height", "colour", "turret_shape", "turret_pos", "turret_len", "turret_wid", "skirts", "barrels", "extra", "gun_calibre", "gun_length", "muzzle_brake", "wheels", "hp", "speed_fwd", "speed_rev", "accel", "turn_rate", "turret_traverse", "traverse_limit", "elev_min", "elev_max", "armour", "reload", "shells", "mg", "gun_sound"],
	"emotes": ["id", "label", "face", "sound", "pitch"],
	"infantry": ["id", "name", "kit", "squad_share", "hp", "speed", "range", "burst", "shot_gap", "pause", "hit_chance", "damage", "grenades", "prone", "medic"],
	"pings": ["id", "label", "order", "voice", "colour"],
	"voices": ["id", "speaker", "text"],
	"modes": ["id", "name", "kind", "description", "kill_target", "path_half_length", "path_sway", "capture_radius", "push_speed", "return_speed", "match_seconds", "respawn_seconds", "spawn_behind_robot", "spawn_lanes", "sight_range", "team_size", "team_roles"],
}
const ARMOUR_KEYS := ["hull_front", "hull_side", "hull_rear", "turret_front", "turret_side"]
const EFFECTS := ["armour", "smoke", "reload", "sabot", "stun_shell", "scan", "skyscan", "repair", "boost"]
const ORDERS := ["attack", "move", "cover", "follow", "rush"]

var roles := {}
var abilities := {}
var shells := {}
var vehicles := {}
var emotes := {}
var infantry := {}
var pings := {}
var voices := {}
var modes := {}
var vehicle_order: Array = []
var emote_order: Array = []
var ping_order: Array = []
var mode_order: Array = []
var errors: Array = []


func _ready() -> void:
	roles = _load_sheet("roles")
	abilities = _load_sheet("abilities")
	shells = _load_sheet("shells")
	vehicles = _load_sheet("vehicles")
	emotes = _load_sheet("emotes")
	infantry = _load_sheet("infantry")
	for id in infantry:
		if not ["rifle", "machine_gun", "medical", "rocket", "tools"].has(infantry[id].get("kit", "")):
			errors.append("infantry/%s: unknown kit" % id)
	pings = _load_sheet("pings")
	voices = _load_sheet("voices")
	modes = _load_sheet("modes")
	_check_references()


func _load_sheet(sheet: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://data/%s.json" % sheet, FileAccess.READ)
	if f == null:
		errors.append("%s: sheet missing" % sheet)
		return out
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("rows"):
		errors.append("%s: not valid JSON with rows" % sheet)
		return out
	for row in data["rows"]:
		var id := str(row.get("id", "?"))
		for col in COLUMNS[sheet]:
			if not row.has(col) or row[col] == null or (row[col] is String and row[col] == ""):
				errors.append("%s/%s: empty cell '%s'" % [sheet, id, col])
		if out.has(id):
			errors.append("%s/%s: duplicate id" % [sheet, id])
		out[id] = row
		match sheet:
			"vehicles":
				vehicle_order.append(id)
			"emotes":
				emote_order.append(id)
			"pings":
				ping_order.append(id)
			"modes":
				mode_order.append(id)
	return out


func _check_references() -> void:
	for id in abilities:
		if not EFFECTS.has(abilities[id].get("effect", "")):
			errors.append("abilities/%s: unknown effect" % id)
	for id in vehicles:
		var v: Dictionary = vehicles[id]
		if not roles.has(v.get("role", "")):
			errors.append("vehicles/%s: role '%s' not in roles" % [id, v.get("role", "")])
		if not abilities.has(v.get("ability", "")):
			errors.append("vehicles/%s: ability '%s' not in abilities" % [id, v.get("ability", "")])
		for s in v.get("shells", []):
			if not shells.has(s):
				errors.append("vehicles/%s: shell '%s' not in shells" % [id, s])
			elif shells[s].get("kind", "") != "shell":
				errors.append("vehicles/%s: '%s' is not a main-gun shell" % [id, s])
		if not shells.has(v.get("mg", "")) or shells[v["mg"]].get("kind", "") != "bullet":
			errors.append("vehicles/%s: mg must name a bullet in shells" % id)
		if not ["cannon_large", "cannon_mid", "cannon_small", "autocannon"].has(v.get("gun_sound", "")):
			errors.append("vehicles/%s: gun_sound must be cannon_large, cannon_mid, cannon_small or autocannon" % id)
		if not ["front", "sniper", "ambush", "artillery", "scout", "escort", "flank"].has(v.get("bot_style", "")):
			errors.append("vehicles/%s: unknown bot_style" % id)
		if not ["heavy", "medium", "destroyer", "artillery", "light"].has(v.get("class", "")):
			errors.append("vehicles/%s: unknown class" % id)
		if not ["box", "dome", "wedge", "casemate", "slab"].has(v.get("turret_shape", "")):
			errors.append("vehicles/%s: unknown turret_shape" % id)
		if not ["none", "dozer", "drums", "basket", "spade", "antenna", "crane", "radar", "launchers"].has(v.get("extra", "")):
			errors.append("vehicles/%s: unknown extra" % id)
		if v.get("shells", []).is_empty():
			errors.append("vehicles/%s: no shells" % id)
		var arm = v.get("armour", {})
		for k in ARMOUR_KEYS:
			if typeof(arm) != TYPE_DICTIONARY or not arm.has(k):
				errors.append("vehicles/%s: empty cell 'armour.%s'" % [id, k])
	for id in shells:
		if not ["AP", "HE", "HEAT"].has(shells[id].get("type", "")):
			errors.append("shells/%s: unknown type" % id)
	for id in emotes:
		if not ["laugh", "cry", "angry", "wow", "none"].has(emotes[id].get("face", "")):
			errors.append("emotes/%s: unknown face" % id)
		if not Sfx.BUS.has(emotes[id].get("sound", "")):
			errors.append("emotes/%s: sound '%s' not in sfx" % [id, emotes[id].get("sound", "")])
	for id in Sfx.BUS:
		if not Sfx.streams.has(id):
			errors.append("sfx/%s: no sound file (run tools/make_sfx.gd)" % id)
	for id in pings:
		if not ORDERS.has(pings[id].get("order", "")):
			errors.append("pings/%s: unknown order" % id)
		if not voices.has(pings[id].get("voice", "")):
			errors.append("pings/%s: voice '%s' not in voices" % [id, pings[id].get("voice", "")])
	for id in voices:
		if not ResourceLoader.exists("res://voice/%s.wav" % id):
			errors.append("voices/%s: voice/%s.wav has not been generated (run tools/make_voices.ps1)" % [id, id])
	for id in modes:
		var m: Dictionary = modes[id]
		if not ["push", "deathmatch", "domination", "range"].has(m.get("kind", "")):
			errors.append("modes/%s: unknown kind" % id)
		for r in m.get("team_roles", []):
			if not roles.has(r):
				errors.append("modes/%s: role '%s' not in roles" % [id, r])
			elif vehicles_for_role(r).is_empty():
				errors.append("modes/%s: no vehicle has role '%s'" % [id, r])
		if m.get("team_roles", []).size() != int(m.get("team_size", 0)):
			errors.append("modes/%s: team_roles does not match team_size" % id)


func vehicles_for_role(role_id: String) -> Array:
	var out: Array = []
	for id in vehicle_order:
		if vehicles[id].get("role", "") == role_id:
			out.append(id)
	return out
