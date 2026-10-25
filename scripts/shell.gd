class_name Shell
extends Node3D
# A fired round. Falls under gravity, loses penetration with range, and moves by raycast
# each physics tick so it never tunnels.

var main
var def: Dictionary
var mods := {}  # special-round changes: pen, damage, stun, stun_radius
var vel := Vector3.ZERO
var shooter
var shooter_rid: RID
var team := 0
var life := 14.0
const INCOMING_SECONDS := 1.6  # how long the incoming whistle is
var _incoming := false
var travelled := 0.0
var _heard := false


func _ready() -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var bullet: bool = def["kind"] == "bullet"
	bm.size = Vector3(0.07, 0.07, 2.5) if bullet else Vector3(0.18, 0.18, 4.0)
	if bullet:
		life = 1.5
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 0.9, 1.0) if not mods.is_empty() else Color(1.0, 0.85, 0.4)
	m.material_override = mat
	add_child(m)


# What the player hears of a round that is not theirs: a snap as it passes close by.
# (A falling shell used to whistle as well; that sound is out until a better one is found.)
func _fly_by(from: Vector3, to: Vector3) -> void:
	if _heard or travelled < 30.0 or (is_instance_valid(shooter) and shooter.is_mine()):
		return
	var ear: Vector3 = main.player_ctrl.cam.global_position
	var along := to - from
	var k := clampf((ear - from).dot(along) / maxf(along.length_squared(), 0.01), 0.0, 1.0)
	var nearest := from + along * k
	var bullet: bool = def["kind"] == "bullet"
	if nearest.distance_to(ear) < (7.0 if bullet else 16.0):
		_heard = true
		Sfx.play("zip", nearest, -6.0 if bullet else 2.0, 1.0 if bullet else 0.8, 18.0)


# A long shot is a hard shot, and pays for it: 5% more damage for every 100 m past 800, up to half as much again.
func _far_bonus() -> float:
	return 1.0 + clampf((travelled - 800.0) / 100.0 * 0.05, 0.0, 0.5)


func _pen_now() -> float:
	return float(def["pen"]) * float(mods.get("pen", 1.0)) * (1.0 - float(def["pen_loss_per_km"]) * travelled / 1000.0)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var from := global_position
	var pull: float = GameData.SHELL_GRAVITY * float(mods.get("gravity", 1.0))
	vel.y -= pull * delta
	if mods.has("indirect") and not _incoming and vel.y < 0.0:
		# A shell lobbed in by artillery is heard coming: the whistle starts so as to end as it lands.
		var up: float = maxf(global_position.y - main.map.height(global_position.x, global_position.z), 0.0)
		var left: float = (vel.y + sqrt(vel.y * vel.y + 2.0 * pull * up)) / pull
		if left <= INCOMING_SECONDS:
			_incoming = true
			Sfx.play("incoming", global_position + Vector3(vel.x, 0, vel.z) * left - Vector3(0, up, 0), 1.0, 1.0, 45.0, 0.02)
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 15 | Prop.LAYER)
	q.exclude = [shooter_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_fly_by(from, to)
		travelled += from.distance_to(to)
		global_position = to
		if vel.length_squared() > 1.0:
			look_at(to + vel, Vector3.UP)
		return
	var pos: Vector3 = hit["position"]
	travelled += from.distance_to(pos)
	var col = hit["collider"]
	# On a PC that is only watching the host's match, rounds are for show: they fly and burst,
	# and the host says what they did.
	var ghost: bool = mods.has("ghost")
	if col is Aircraft and col.team != team and not ghost:
		col.hurt(float(def.get("air_damage", def["damage"])) * (2.0 if def["kind"] == "bullet" else 1.0), shooter)  # (air_damage: what an anti-aircraft round does to an aircraft)
	if col is Prop:
		# Loose things are knocked flying: a bullet rocks them, a shell throws them.
		col.knock(vel.normalized() * (45.0 if def["kind"] == "bullet" else float(def["damage"]) * 28.0), pos)
	if col is Soldier and col.team != team and not ghost:
		col.hit("bullet" if def["kind"] == "bullet" else "blast", shooter)
	if def["kind"] == "bullet":
		if col is Tank and col.team != team and not ghost:
			col.take_hit(def, _pen_now(), 1.0, pos, vel.normalized(), hit["normal"], shooter)
		elif col is Tank and ghost:
			Fx.sparks(main, pos, -vel.normalized(), 0.2)
		elif not (col is Tank):
			Fx.dust(main, pos, 0.15)
		queue_free()
		return
	var he: bool = def["type"] == "HE"
	var weight := clampf(float(def["damage"]) / 220.0, 0.3, 3.0)
	if col is Tank:
		if he:
			main.spawn_fx(pos, 2.0 + weight, Color(1.0, 0.7, 0.2, 0.8), 0.25)
			Fx.smoke(main, pos, weight)
		if ghost:
			Fx.sparks(main, pos, -vel.normalized(), 1.0)
			Sfx.play("thud", pos, 0.0, 1.0, 22.0)
		elif col.team != team:
			var result: String = col.take_hit(def, _pen_now(), float(mods.get("damage", 1.0)) * _far_bonus(), pos, vel.normalized(), hit["normal"], shooter)
			main.tell_shooter(shooter, "%s  (%d m)" % [result, int(travelled)], result)
	else:
		# Dirt thrown up where the round lands, and the dust that hangs after it.
		Fx.dirt(main, pos, weight)
		Fx.dust(main, pos + Vector3(0, 0.5, 0), weight)
		Sfx.play("dirt", pos, 0.0, clampf(1.3 - weight * 0.15, 0.7, 1.3), 24.0)
	var radius: float = def["splash_radius"]
	if radius > 0.0:
		# A quick hot core, then smoke.
		main.spawn_fx(pos + Vector3(0, 0.6, 0), radius * 0.45, Color(1.0, 0.7, 0.25, 0.85), 0.22)
		Fx.smoke(main, pos + Vector3(0, 1.0, 0), radius * 0.35)
		if radius > 5.0:
			Fx.dirt(main, pos, radius * 0.4)
		if mods.has("indirect"):
			Sfx.play("arty_boom", pos, 0.0, 1.0, 45.0)
			# A heavy shell coming straight down throws up far more than a direct hit does.
			Fx.blast(main, pos, 2.6)
			Fx.dirt(main, pos, radius * 0.9)
			Fx.smoke(main, pos + Vector3(0, 2.0, 0), radius * 0.8)
			main.spawn_fx(pos + Vector3(0, 1.0, 0), radius * 0.8, Color(1.0, 0.75, 0.3, 0.9), 0.3)
		else:
			Sfx.play("explosion", pos, 0.0, clampf(1.5 - radius * 0.06, 0.6, 1.5), 45.0)
		for p in get_tree().get_nodes_in_group("props"):
			var gap: float = p.global_position.distance_to(pos)
			if gap < radius * 1.5 and p != col:
				p.knock(((p.global_position - pos).normalized() + Vector3(0, 0.4, 0)) * 5200.0 * (1.0 - gap / (radius * 1.5)), pos)
		var hits := 0
		for s in main.soldiers.duplicate():
			if s.team != team and s.global_position.distance_to(pos) < radius and not ghost:
				s.hit("blast", shooter)
		for t in main.tanks.duplicate():
			if t == col or t.team == team or ghost:
				continue
			var d: float = (t.global_position + Vector3(0, 1.2, 0)).distance_to(pos)
			if d < radius:
				t.take_splash(float(def["damage"]) * 0.7 * _far_bonus() * (1.0 - d / radius), float(def["pen"]), shooter)
				hits += 1
		if hits > 0 and not (col is Tank):
			main.tell_shooter(shooter, "Blast caught %d  (%d m)" % [hits, int(travelled)], "")
	if mods.has("stun") and not ghost:
		var reach: float = mods["stun_radius"]
		main.spawn_fx(pos, reach, Color(0.5, 0.8, 1.0, 0.5), 0.7)
		for t in main.tanks:
			if t.team != team and t.global_position.distance_to(pos) < reach:
				t.stun(mods["stun"])
	queue_free()
