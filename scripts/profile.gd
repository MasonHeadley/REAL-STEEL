extends Node
# The player's level. Points scored in a match become experience when it ends, and every
# XP_PER_LEVEL of experience is a level. It is kept in user://profile.cfg on this PC.
#
# The numbers to change when testing are these three:
const XP_PER_LEVEL := 1000    # experience needed for each level
const BOT_MATCH_RATE := 0.5   # share of a match's points that count when no other person was playing
const WIN_BONUS := 150        # extra experience for being on the winning team

const PATH := "user://profile.cfg"

const LOADOUTS := 5

var xp := 0
var loadouts := {}   # vehicle id -> five loadouts (see kit.gd)
var active := {}     # vehicle id -> which of the five is in use (0..4)


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		xp = int(cfg.get_value("profile", "xp", 0))
		var saved = JSON.parse_string(str(cfg.get_value("garage", "loadouts", "{}")))
		var chosen = JSON.parse_string(str(cfg.get_value("garage", "active", "{}")))
		if saved is Dictionary:
			loadouts = saved
		if chosen is Dictionary:
			active = chosen


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "xp", xp)
	cfg.set_value("garage", "loadouts", JSON.stringify(loadouts))
	cfg.set_value("garage", "active", JSON.stringify(active))
	cfg.save(PATH)


# One of a vehicle's five loadouts (made blank the first time it is asked for).
func loadout(vehicle: String, index: int = -1) -> Dictionary:
	if not loadouts.has(vehicle):
		loadouts[vehicle] = []
	while loadouts[vehicle].size() < LOADOUTS:
		loadouts[vehicle].append(Kit.blank())
	return loadouts[vehicle][clampi(int(active.get(vehicle, 0)) if index < 0 else index, 0, LOADOUTS - 1)]


func level() -> int:
	return 1 + xp / XP_PER_LEVEL


# Experience into the current level, out of XP_PER_LEVEL.
func into_level() -> int:
	return xp % XP_PER_LEVEL


# Adds a finished match's reward. Returns a line saying what was gained.
func add_match(points: int, won: bool, with_people: bool) -> String:
	var before := level()
	var gain := int(round(float(points + (WIN_BONUS if won else 0)) * (1.0 if with_people else BOT_MATCH_RATE)))
	xp += gain
	save()
	return "+%d XP%s" % [gain, "     LEVEL UP!  Level %d" % level() if level() > before else "     Level %d  (%d / %d)" % [level(), into_level(), XP_PER_LEVEL]]
