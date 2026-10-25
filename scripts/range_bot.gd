class_name RangeBot
extends Node
# A gun on the sound range. It sits still and does nothing until the range picks it (see
# Main._range_tick) while the player is in the firing lane. Then it lays on the player and
# fires once: wide on a "near miss" turn, on target on a "hit" turn. Autocannons fire a
# short string instead of one round, and a turn can add a burst of machine gun.

var main
var tank: Tank
var shots_left := 0
var mg_left := 0.0
var _was_active := false
var _last_reload := 0.0


func _ready() -> void:
	tank.auto_drop = true


func _physics_process(delta: float) -> void:
	tank.throttle = 0.0
	tank.steer = 0.0
	tank.want_fire = false
	tank.want_mg = false
	var mine: Tank = main.player_ctrl.tank if main.player_ctrl.has_tank() else null
	var active: bool = mine != null and main.range_active == tank
	if active and not _was_active:
		shots_left = 6 if float(tank.def["reload"]) < 1.0 else 1
		mg_left = 1.2 if main.range_mg else 0.0
	_was_active = active
	if not active:
		return
	var aim := mine.global_position + Vector3(0, 1.4, 0)
	if not main.range_hit:
		# Wide and a little high: close enough to hear it go past.
		var across := (aim - tank.global_position).cross(Vector3.UP).normalized()
		aim += across * 7.0 + Vector3(0, 2.5, 0)
	tank.aim_point = aim
	var laid := tank.gun_error() < 0.03
	if tank.reload_left > _last_reload + 0.05:
		shots_left -= 1  # the reload timer jumping means a round just left
	_last_reload = tank.reload_left
	tank.want_fire = laid and shots_left > 0
	if laid and mg_left > 0.0:
		mg_left -= delta
		tank.want_mg = true
