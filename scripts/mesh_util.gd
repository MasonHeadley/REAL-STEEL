class_name MeshUtil
extends RefCounted
# Small helpers for building meshes and effects in code.


# Extrudes a convex side profile (x = depth along Z, y = height) across the X axis.
static func extrude_x(profile: PackedVector2Array, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c2 := Vector2.ZERO
	for p in profile:
		c2 += p
	c2 /= float(profile.size())
	var centre := Vector3(0, c2.y, c2.x)
	var hw := width * 0.5
	var n := profile.size()
	for i in range(1, n - 1):
		for sx in [-hw, hw]:
			_tri(st, centre, _p(profile[0], sx), _p(profile[i], sx), _p(profile[i + 1], sx))
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		_tri(st, centre, _p(a, -hw), _p(b, -hw), _p(b, hw))
		_tri(st, centre, _p(a, -hw), _p(b, hw), _p(a, hw))
	return st.commit()


# A faceted body made from a row of cross-sections along Z, joined up and capped at the ends.
# Each section is [z, half width at the bottom, half width at the top, bottom height,
# top height, shoulder]. The shoulder (0 to 1) is how far down from the top the sides start
# to lean in: 0 gives upright sides and a flat top, 0.5 a body that is all slope from half
# way up. Used for vehicle hulls and turrets, which taper in every direction.
static func loft(sections: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for s in sections:
		var break_y := lerpf(s[4], s[3], s[5])
		rings.append([Vector3(-s[1], s[3], s[0]), Vector3(-s[1], break_y, s[0]), Vector3(-s[2], s[4], s[0]),
			Vector3(s[2], s[4], s[0]), Vector3(s[1], break_y, s[0]), Vector3(s[1], s[3], s[0])])
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var centre := Vector3.ZERO
		for p in a + b:
			centre += p
		centre /= 12.0
		for k in 6:
			var n := (k + 1) % 6
			_tri(st, centre, a[k], a[n], b[n])
			_tri(st, centre, a[k], b[n], b[k])
	for end in [0, rings.size() - 1]:
		var r: Array = rings[end]
		var inside: Vector3 = (r[0] + r[2] + r[3] + r[5]) / 4.0 + Vector3(0, 0, 0.2 if end == 0 else -0.2)
		for k in range(1, 5):
			_tri(st, inside, r[0], r[k], r[k + 1])
	return st.commit()


# A rounded body made from a row of oval cross-sections along Z, joined up and capped: an
# aircraft's fuselage. Each section is given as for loft() ([z, half width, half width,
# bottom, top, ...]); the oval fills that width and height. `sides` is how many flats go round it.
static func tube(sections: Array, sides: int = 12) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for s in sections:
		var mid := (float(s[3]) + float(s[4])) * 0.5
		var ring: Array = []
		for k in sides:
			var a := TAU * float(k) / float(sides)
			ring.append(Vector3(cos(a) * maxf(s[1], s[2]), mid + sin(a) * (float(s[4]) - float(s[3])) * 0.5, s[0]))
		rings.append(ring)
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var centre := Vector3.ZERO
		for p in a + b:
			centre += p
		centre /= float(sides * 2)
		for k in sides:
			var n := (k + 1) % sides
			_tri(st, centre, a[k], a[n], b[n])
			_tri(st, centre, a[k], b[n], b[k])
	for end in [0, rings.size() - 1]:
		var r: Array = rings[end]
		var inside: Vector3 = (r[0] + r[sides / 2]) * 0.5 + Vector3(0, 0, 0.2 if end == 0 else -0.2)
		for k in range(1, sides - 1):
			_tri(st, inside, r[0], r[k], r[k + 1])
	return st.commit()


static func _p(v: Vector2, x: float) -> Vector3:
	return Vector3(x, v.y, v.x)


static func _tri(st: SurfaceTool, centre: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.dot((a + b + c) / 3.0 - centre) < 0.0:
		var tmp := b
		b = c
		c = tmp
		nrm = -nrm
	# a, b, c are now counter-clockwise from outside; Godot's front face is clockwise.
	for v in [a, c, b]:
		st.set_normal(nrm)
		st.add_vertex(v)


# tex names a texture from Tex; it is laid on by triplanar mapping, so no mesh needs UVs.
# tile is the size of one repeat in metres. world keeps the pattern fixed to the ground.
static func material(color: Color, rough: float = 0.85, tex: String = "", tile: float = 2.0, world: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if tex != "":
		mat.albedo_texture = Tex.named(tex)
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = world
		mat.uv1_scale = Vector3.ONE / tile
	elif rough <= 0.3:
		# Glass, water and anything polished: glossy, and catching a reflection of the sky.
		mat.roughness = rough * 0.35
		mat.metallic = 0.45
		mat.metallic_specular = 0.8
	else:
		# Everything else plain-coloured gets a faint worn grain (blotches, dirt run down from
		# above, speckle), so a flat colour no longer looks like moulded plastic.
		mat.albedo_texture = Tex.named("grime")
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = world
		mat.uv1_scale = Vector3.ONE / 3.0
	return mat


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, top_radius: float = -1.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 1
	m.mesh = cm
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


# A round bar from one point to another: tool handles, cables, gun barrels, bipod legs.
static func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = maxf(a.distance_to(b), 0.001)
	cm.radial_segments = 8
	cm.rings = 1
	m.mesh = cm
	m.material_override = mat
	var along := (b - a).normalized()
	var q := Quaternion(Vector3.UP, along) if absf(along.dot(Vector3.UP)) < 0.999 else Quaternion.IDENTITY
	m.transform = Transform3D(Basis(q), (a + b) * 0.5)
	parent.add_child(m)
	return m


# A rising puff emitter, off until told to emit. Used for smoke and fire.
static var _puff: GradientTexture2D


# A soft round blob, solid in the middle and fading to nothing at the edge, used for every
# puff of smoke and dust.
static func puff_texture() -> Texture2D:
	if _puff == null:
		var fade := Gradient.new()
		fade.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		_puff = GradientTexture2D.new()
		_puff.gradient = fade
		_puff.fill = GradientTexture2D.FILL_RADIAL
		_puff.fill_from = Vector2(0.5, 0.5)
		_puff.fill_to = Vector2(1.0, 0.5)
		_puff.width = 64
		_puff.height = 64
	return _puff


# Makes a particle material draw each particle as a soft sprite turned to the camera.
static func as_puffs(mat: StandardMaterial3D) -> void:
	mat.albedo_texture = puff_texture()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED


static func smoke(color: Color, amount: int, puff: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = 2.6
	p.local_coords = false
	var sm := QuadMesh.new()
	sm.size = Vector2(1.7, 1.7)
	p.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	as_puffs(mat)
	p.material_override = mat
	p.direction = Vector3.UP
	p.spread = 18.0
	p.gravity = Vector3(0.6, 1.2, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.scale_amount_min = puff * 0.7
	p.scale_amount_max = puff * 1.5
	p.color = color
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.85))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	return p
