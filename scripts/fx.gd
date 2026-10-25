class_name Fx
extends RefCounted
# One-shot visual effects: dust, flung dirt, sparks, smoke, muzzle blasts, tracers.
# Each makes a few short-lived particles and cleans itself up. Kept modest on purpose:
# enough to sell the hit, not enough to hide the fight.

static var enabled := true


# A burst of particles that plays once and frees itself.
static func _burst(parent: Node, pos: Vector3, color: Color, amount: int, life: float, size: float, speed_lo: float, speed_hi: float, dir: Vector3, spread: float, gravity: Vector3, unshaded: bool, cube: bool = false) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	if cube:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * size
		p.mesh = bm
	else:
		var sm := QuadMesh.new()
		sm.size = Vector2(size, size) * 1.7
		p.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not cube:
		MeshUtil.as_puffs(mat)
		p.amount = amount * 2  # flat sprites need more of them to look as full as the balls did
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = mat
	p.direction = dir
	p.spread = spread
	p.gravity = gravity
	p.initial_velocity_min = speed_lo
	p.initial_velocity_max = speed_hi
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	if not cube:
		# Puffs swell as they thin out.
		var grow := Curve.new()
		grow.add_point(Vector2(0.0, 0.45))
		grow.add_point(Vector2(1.0, 1.6))
		p.scale_amount_curve = grow
	p.color = color
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)


# A small charge going off on the ground, as a grenade does: a flash, clods thrown up, a
# skirt of pale dust rolling outward along the ground, and a column of grey smoke that
# climbs out of the middle and hangs.
static func blast(parent: Node, pos: Vector3, size: float) -> void:
	if not enabled:
		return
	var up := pos + Vector3(0, 0.3, 0)
	_burst(parent, up, Color(1.0, 0.8, 0.4, 0.9), 6, 0.12, 0.9 * size, 2.0, 6.0, Vector3.UP, 80.0, Vector3.ZERO, true)
	dirt(parent, pos, 1.2 * size)
	_burst(parent, up, Color(0.72, 0.66, 0.54, 0.55), int(16 * size), 2.6, 1.5 * size, 3.0, 7.5, Vector3.UP, 86.0, Vector3(0.3, 0.2, 0), false)
	_burst(parent, up, Color(0.3, 0.3, 0.31, 0.75), int(14 * size), 3.4, 1.7 * size, 2.5, 8.0, Vector3.UP, 16.0, Vector3(0.4, 1.0, 0), false)
	_burst(parent, up + Vector3(0, 1.2, 0), Color(0.42, 0.42, 0.43, 0.6), int(10 * size), 4.2, 2.2 * size, 1.0, 4.0, Vector3.UP, 30.0, Vector3(0.5, 0.8, 0), false)

# Dust hanging in the air: a shell landing, a muzzle blast scouring the ground.
static func dust(parent: Node, pos: Vector3, size: float) -> void:
	if enabled:
		_burst(parent, pos, Color(0.62, 0.56, 0.44, 0.5), int(6 + size * 3.0), 1.6 + size * 0.25, 1.4 + size * 0.5, 1.0, 2.5 + size, Vector3.UP, 75.0, Vector3(0.4, 0.5, 0), false)


# Clods thrown up and falling back.
static func dirt(parent: Node, pos: Vector3, size: float) -> void:
	if enabled:
		_burst(parent, pos, Color(0.25, 0.2, 0.13, 1.0), int(8 + size * 4.0), 1.1, 0.16 + size * 0.03, 5.0 + size, 9.0 + size * 2.5, Vector3.UP, 38.0, Vector3(0, -19.0, 0), false, true)


# Bright chips off armour.
static func sparks(parent: Node, pos: Vector3, out_dir: Vector3, size: float) -> void:
	if enabled:
		_burst(parent, pos, Color(1.0, 0.8, 0.35, 1.0), int(8 + size * 5.0), 0.4, 0.09, 6.0, 16.0, out_dir, 50.0, Vector3(0, -12.0, 0), true, true)


# Dark smoke rolling up from a blast or a hit.
static func smoke(parent: Node, pos: Vector3, size: float) -> void:
	if enabled:
		_burst(parent, pos, Color(0.14, 0.13, 0.12, 0.6), int(5 + size * 2.0), 2.2 + size * 0.2, 1.2 + size * 0.5, 0.8, 2.2, Vector3.UP, 28.0, Vector3(0.5, 1.4, 0), false)


# A gun firing. The flash is a hot shape that stretches the way the blast goes: straight
# out of a plain muzzle, out to both sides of a muzzle brake. Big guns also throw grey
# smoke forward and scour dust off the ground underneath.
static func muzzle(parent: Node, pos: Vector3, dir: Vector3, calibre: float, brake: bool, ground_y: float) -> void:
	if not enabled:
		return
	var size := clampf(calibre / 60.0, 0.25, 3.0)
	var side := dir.cross(Vector3.UP).normalized()
	var jets: Array = [[dir, 1.0]]
	if brake:
		jets = [[dir, 0.45], [(side + dir * 0.25).normalized(), 0.9], [(-side + dir * 0.25).normalized(), 0.9]]
	for jet in jets:
		var d: Vector3 = jet[0]
		var reach: float = float(jet[1]) * size
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 8
		sm.rings = 4
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.82, 0.4, 0.95)
		m.material_override = mat
		parent.add_child(m)
		var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
		m.global_transform = Transform3D(Basis.looking_at(d, up), pos + d * reach * 1.1)
		m.scale = Vector3(0.45, 0.45, 1.0) * reach
		var tw := parent.create_tween()
		tw.tween_property(m, "scale", Vector3(0.9, 0.9, 3.0) * reach, 0.07)
		tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.09)
		tw.tween_callback(m.queue_free)
	if calibre < 50.0:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.5)
	light.light_energy = 3.0 * size
	light.omni_range = 14.0 * size
	parent.add_child(light)
	light.global_position = pos + dir
	parent.get_tree().create_timer(0.08).timeout.connect(light.queue_free)
	_burst(parent, pos + dir * size, Color(0.55, 0.53, 0.5, 0.45), int(4 + size * 2.0), 1.6, 1.0 + size * 0.5, 2.0, 5.0 + size * 2.0, dir, 22.0, Vector3(0.4, 0.6, 0), false)
	if calibre >= 90.0 and pos.y - ground_y < 4.5:
		dust(parent, Vector3(pos.x, ground_y + 0.3, pos.z) + dir * 2.0, size)


# A bullet you can see go: a short bright streak from one point to another.
static func tracer(parent: Node, from: Vector3, to: Vector3) -> void:
	if not enabled or from.distance_to(to) < 2.0:
		return
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 1.8)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.55)
	m.material_override = mat
	parent.add_child(m)
	m.global_transform = Transform3D(Basis.looking_at((to - from).normalized(), Vector3.UP), from)
	var tw := parent.create_tween()
	tw.tween_property(m, "global_position", to, from.distance_to(to) / 320.0)
	tw.tween_callback(m.queue_free)
