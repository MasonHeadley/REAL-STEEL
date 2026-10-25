class_name Prefabs
extends RefCounted
# The ready-made pieces a map is dressed with: vehicles, street furniture, fences, cover.
# Each is built by name with Prefabs.build(id, rng) and comes back as a Prop (see prop.gd),
# standing on its own origin and facing along its own -Z, ready to be placed and turned.
# LIST is every name there is, for anything (such as a map builder) that wants to offer them.

const LIST := ["car", "van", "truck", "bus", "lamp", "bench", "bin", "sign", "bus_stop", "fence", "picket", "sandbags", "crates", "barrels", "bale", "cone",
	"dumpster", "bags", "pallets", "hydrant", "mailbox", "newsbox", "planter", "bikes", "table", "board", "phone", "cart", "swing", "bbq", "doghouse", "washing", "woodpile", "stall"]
const PAINT := [Color(0.7, 0.16, 0.14), Color(0.16, 0.34, 0.6), Color(0.8, 0.68, 0.2), Color(0.8, 0.8, 0.78), Color(0.2, 0.42, 0.26), Color(0.2, 0.2, 0.22), Color(0.82, 0.45, 0.14)]

static var _mats := {}


static func _mat(color: Color, rough: float = 0.7) -> StandardMaterial3D:
	var key := "%s %s" % [color, rough]
	if not _mats.has(key):
		_mats[key] = MeshUtil.material(color, rough)
	return _mats[key]


static func build(id: String, rng: RandomNumberGenerator) -> Prop:
	var p := _build(id, rng)
	_bake(p)
	return p


# Speed: a prop is put together from many small shapes, and the graphics card draws each one
# separately, so a town of them was tens of thousands of drawings a frame. Here every shape
# is melted into one mesh with one part per colour, and small things stop being drawn once
# they are too far off to make out (a bench at 90 m, a car at 200 m, a bus at 260 m).
static func _bake(p: Prop) -> void:
	var tools := {}   # material -> SurfaceTool collecting every shape painted with it
	var parts: Array = []
	for mi in p.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var at: Transform3D = p.global_transform.affine_inverse() * m.global_transform if p.is_inside_tree() else _local_to(p, m)
		for s in m.mesh.get_surface_count():
			var mat: Material = m.material_override if m.material_override != null else m.mesh.surface_get_material(s)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
			tools[mat].append_from(m.mesh, s, at)
		parts.append(m)
	if parts.is_empty():
		return
	var mesh := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	for m in parts:
		m.get_parent().remove_child(m)
		m.free()
	var one := MeshInstance3D.new()
	one.mesh = mesh
	var size := mesh.get_aabb().size
	one.visibility_range_end = clampf(maxf(size.x, maxf(size.y, size.z)) * 45.0, 70.0, 260.0)
	one.visibility_range_end_margin = 6.0
	p.add_child(one)


# Where a shape sits relative to its prop, before either is placed in the world.
static func _local_to(p: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != p:
		t = (at as Node3D).transform * t
		at = at.get_parent()
	return t


static func _build(id: String, rng: RandomNumberGenerator) -> Prop:
	var tyre := _mat(Color(0.1, 0.1, 0.1), 0.9)
	var glass := _mat(Color(0.2, 0.28, 0.34), 0.25)
	var iron := _mat(Color(0.2, 0.22, 0.22), 0.6)
	var wood := _mat(Color(0.5, 0.38, 0.24), 0.85)
	var paint := _mat(PAINT[rng.randi() % PAINT.size()], 0.4)
	var white := _mat(Color(0.9, 0.9, 0.86), 0.7)
	# The plain bench and bin have been replaced by more detailed ones.
	if id == "bench":
		id = "bench2"
	elif id == "bin":
		id = "trash"
	match id:
		"bench2":
			# A park bench: slatted seat and back on iron ends with armrests. Now and then
			# someone has left a newspaper on it.
			var p := Prop.make(Vector3(2.0, 0.95, 0.7), 60.0)
			for k in 3:
				MeshUtil.box(p, Vector3(1.9, 0.04, 0.12), Vector3(0, 0.46, -0.2 + k * 0.17), wood)
				MeshUtil.box(p, Vector3(1.9, 0.11, 0.04), Vector3(0, 0.62 + k * 0.14, 0.26 + k * 0.02), wood)
			for sx in [-0.88, 0.88]:
				MeshUtil.box(p, Vector3(0.06, 0.46, 0.5), Vector3(sx, 0.23, 0), iron)
				MeshUtil.box(p, Vector3(0.06, 0.5, 0.06), Vector3(sx, 0.7, 0.28), iron)
				MeshUtil.box(p, Vector3(0.07, 0.05, 0.46), Vector3(sx, 0.66, 0.02), iron)  # armrest
			if rng.randf() < 0.45:
				var paper := MeshUtil.box(p, Vector3(0.3, 0.012, 0.42), Vector3(rng.randf_range(-0.6, 0.6), 0.49, -0.05), white)
				paper.rotation.y = rng.randf_range(-0.5, 0.5)
				MeshUtil.box(p, Vector3(0.24, 0.014, 0.05), paper.position + Vector3(0, 0.002, -0.12), _mat(Color(0.2, 0.2, 0.22), 0.8))  # the headline
			return p
		"trash":
			# A litter bin: a ribbed can with a domed lid, a handle on the lid and one each
			# side, and the town's badge on the front.
			var can := _mat(Color(0.24, 0.36, 0.28), 0.6)
			var p := Prop.make(Vector3(0.62, 1.0, 0.62), 18.0)
			MeshUtil.cylinder(p, 0.27, 0.8, Vector3(0, 0.4, 0), can, 0.3)
			for k in 3:
				MeshUtil.cylinder(p, 0.31, 0.03, Vector3(0, 0.2 + k * 0.25, 0), iron)
			MeshUtil.cylinder(p, 0.33, 0.07, Vector3(0, 0.83, 0), iron, 0.2)
			MeshUtil.box(p, Vector3(0.16, 0.05, 0.03), Vector3(0, 0.9, 0), iron)
			for sx in [-0.31, 0.31]:
				MeshUtil.box(p, Vector3(0.025, 0.14, 0.03), Vector3(sx, 0.6, 0), iron)
			MeshUtil.box(p, Vector3(0.16, 0.12, 0.012), Vector3(0, 0.5, -0.295), white)
			MeshUtil.box(p, Vector3(0.1, 0.03, 0.014), Vector3(0, 0.5, -0.297), _mat(Color(0.75, 0.2, 0.15), 0.6))
			return p
		"dumpster":
			# A wheeled skip for an alley: sloping lids, lifting bars each side, the firm's plate on the front.
			var skip := _mat([Color(0.16, 0.34, 0.24), Color(0.2, 0.28, 0.42), Color(0.42, 0.2, 0.16)][rng.randi() % 3], 0.7)
			var p := Prop.make(Vector3(2.0, 1.45, 1.15), 420.0)
			MeshUtil.box(p, Vector3(2.0, 1.0, 1.1), Vector3(0, 0.68, 0), skip)
			for half in [-0.5, 0.5]:
				var lid := MeshUtil.box(p, Vector3(0.98, 0.05, 1.14), Vector3(half, 1.24, 0), iron)
				lid.rotation.x = 0.12
			for sx in [-1.04, 1.04]:
				MeshUtil.box(p, Vector3(0.06, 0.08, 0.8), Vector3(sx, 0.95, 0), iron)
			MeshUtil.box(p, Vector3(0.6, 0.26, 0.02), Vector3(0, 0.75, -0.56), white)
			MeshUtil.box(p, Vector3(0.4, 0.06, 0.022), Vector3(0, 0.78, -0.565), skip)
			_wheels(p, 0.85, [-0.4, 0.4], 0.1, tyre)
			return p
		"bags":
			# Bin bags put out for the dustmen.
			var p := Prop.make(Vector3(1.3, 0.6, 1.0), 14.0)
			for k in 4:
				var bag := MeshInstance3D.new()
				var ball := SphereMesh.new()
				ball.radius = 0.3
				ball.height = 0.5
				ball.radial_segments = 6
				ball.rings = 3
				bag.mesh = ball
				bag.material_override = _mat(Color(0.07, 0.07, 0.08) if k % 2 == 0 else Color(0.12, 0.2, 0.14), 0.5)
				bag.position = Vector3(-0.4 + k * 0.28, 0.24 + (0.2 if k == 2 else 0.0), rng.randf_range(-0.25, 0.25))
				p.add_child(bag)
				MeshUtil.box(p, Vector3(0.06, 0.1, 0.06), bag.position + Vector3(0, 0.27, 0), bag.material_override)  # the knot
			return p
		"pallets":
			var p := Prop.make(Vector3(1.2, 0.7, 1.0), 70.0)
			for layer in 4:
				var y := 0.02 + layer * 0.16
				for k in 5:
					MeshUtil.box(p, Vector3(1.2, 0.025, 0.14), Vector3(0, y + 0.12, -0.42 + k * 0.21), wood)
				for sx in [-0.52, 0.0, 0.52]:
					MeshUtil.box(p, Vector3(0.1, 0.1, 1.0), Vector3(sx, y + 0.055, 0), wood)
			return p
		"hydrant":
			var red := _mat(Color(0.75, 0.14, 0.1), 0.5)
			var p := Prop.make(Vector3(0.45, 0.85, 0.45), 70.0)
			MeshUtil.cylinder(p, 0.16, 0.08, Vector3(0, 0.04, 0), red)
			MeshUtil.cylinder(p, 0.11, 0.55, Vector3(0, 0.35, 0), red)
			MeshUtil.cylinder(p, 0.13, 0.14, Vector3(0, 0.68, 0), red, 0.04)
			for sx in [-1.0, 1.0]:
				MeshUtil.cylinder(p, 0.055, 0.12, Vector3(sx * 0.15, 0.45, 0), iron).rotation.z = PI * 0.5
			MeshUtil.cylinder(p, 0.065, 0.1, Vector3(0, 0.45, -0.14), iron).rotation.x = PI * 0.5
			return p
		"mailbox":
			var blue := _mat(Color(0.14, 0.26, 0.52), 0.5)
			var p := Prop.make(Vector3(0.55, 1.25, 0.5), 45.0)
			for sx in [-0.2, 0.2]:
				for sz in [-0.18, 0.18]:
					MeshUtil.box(p, Vector3(0.04, 0.3, 0.04), Vector3(sx, 0.15, sz), iron)
			MeshUtil.box(p, Vector3(0.5, 0.7, 0.46), Vector3(0, 0.65, 0), blue)
			var top := MeshUtil.cylinder(p, 0.23, 0.5, Vector3(0, 1.0, 0), blue)
			top.rotation.z = PI * 0.5
			MeshUtil.box(p, Vector3(0.34, 0.04, 0.02), Vector3(0, 0.92, -0.235), iron)  # the slot
			MeshUtil.box(p, Vector3(0.3, 0.16, 0.012), Vector3(0, 0.62, -0.235), white)
			return p
		"newsbox":
			var p := Prop.make(Vector3(0.5, 1.1, 0.45), 30.0)
			MeshUtil.box(p, Vector3(0.1, 0.3, 0.1), Vector3(0, 0.15, 0), iron)
			MeshUtil.box(p, Vector3(0.48, 0.75, 0.42), Vector3(0, 0.68, 0), paint)
			MeshUtil.box(p, Vector3(0.36, 0.34, 0.02), Vector3(0, 0.82, -0.215), glass)
			MeshUtil.box(p, Vector3(0.28, 0.2, 0.01), Vector3(0, 0.8, -0.2), white)  # today's front page
			MeshUtil.box(p, Vector3(0.08, 0.05, 0.03), Vector3(0.14, 0.52, -0.22), iron)  # coin slot
			return p
		"planter":
			var p := Prop.make(Vector3(1.3, 1.0, 0.6), 140.0)
			MeshUtil.box(p, Vector3(1.3, 0.5, 0.6), Vector3(0, 0.25, 0), _mat(Color(0.56, 0.55, 0.52), 0.95))
			MeshUtil.box(p, Vector3(1.2, 0.04, 0.5), Vector3(0, 0.5, 0), _mat(Color(0.25, 0.18, 0.12), 1.0))
			for k in 3:
				var bush := MeshInstance3D.new()
				var ball := SphereMesh.new()
				ball.radius = 0.26
				ball.height = 0.48
				ball.radial_segments = 6
				ball.rings = 3
				bush.mesh = ball
				bush.material_override = _mat(Color(0.16, 0.4, 0.2) if k != 1 else Color(0.2, 0.46, 0.22), 0.9)
				bush.position = Vector3(-0.4 + k * 0.4, 0.7, 0)
				p.add_child(bush)
			for k in 4:
				MeshUtil.box(p, Vector3(0.07, 0.07, 0.07), Vector3(-0.5 + k * 0.33, 0.86, rng.randf_range(-0.15, 0.15)), _mat([Color(0.85, 0.2, 0.3), Color(0.95, 0.8, 0.2), Color(0.9, 0.9, 0.95)][k % 3], 0.6))  # flowers
			return p
		"bikes":
			# A hoop rack with two bicycles leaning in it.
			var p := Prop.make(Vector3(1.8, 1.05, 1.7), 40.0)
			MeshUtil.rod(p, Vector3(-0.8, 0.0, 0), Vector3(-0.8, 0.8, 0), 0.025, iron)
			MeshUtil.rod(p, Vector3(0.8, 0.0, 0), Vector3(0.8, 0.8, 0), 0.025, iron)
			MeshUtil.rod(p, Vector3(-0.8, 0.8, 0), Vector3(0.8, 0.8, 0), 0.025, iron)
			for k in 2:
				var x := -0.35 + k * 0.7
				var frame := _mat(PAINT[rng.randi() % PAINT.size()], 0.4)
				for wz in [-0.55, 0.55]:
					MeshUtil.cylinder(p, 0.33, 0.035, Vector3(x, 0.33, wz), tyre).rotation.z = PI * 0.5
				MeshUtil.rod(p, Vector3(x, 0.33, -0.55), Vector3(x, 0.8, -0.3), 0.02, frame)
				MeshUtil.rod(p, Vector3(x, 0.8, -0.3), Vector3(x, 0.75, 0.3), 0.02, frame)
				MeshUtil.rod(p, Vector3(x, 0.75, 0.3), Vector3(x, 0.33, 0.55), 0.02, frame)
				MeshUtil.rod(p, Vector3(x, 0.33, 0.55), Vector3(x, 0.38, 0.0), 0.02, frame)
				MeshUtil.rod(p, Vector3(x, 0.38, 0.0), Vector3(x, 0.8, -0.3), 0.02, frame)
				MeshUtil.rod(p, Vector3(x - 0.22, 0.95, -0.36), Vector3(x + 0.22, 0.95, -0.36), 0.015, iron)  # handlebars
				MeshUtil.box(p, Vector3(0.1, 0.04, 0.22), Vector3(x, 0.88, 0.3), tyre)  # saddle
			return p
		"table":
			# A pavement cafe table: round top, two chairs, a striped umbrella.
			var p := Prop.make(Vector3(1.7, 2.3, 1.7), 30.0)
			MeshUtil.cylinder(p, 0.42, 0.04, Vector3(0, 0.74, 0), white)
			MeshUtil.rod(p, Vector3(0, 0, 0), Vector3(0, 2.1, 0), 0.025, iron)
			MeshUtil.cylinder(p, 1.0, 0.35, Vector3(0, 2.1, 0), paint, 0.03)
			MeshUtil.cylinder(p, 0.5, 0.18, Vector3(0, 2.2, 0), white, 0.03)
			for sx in [-0.72, 0.72]:
				MeshUtil.box(p, Vector3(0.38, 0.04, 0.38), Vector3(sx, 0.45, 0), iron)
				MeshUtil.box(p, Vector3(0.04, 0.45, 0.38), Vector3(sx * 1.25, 0.68, 0), iron)
				for sz in [-0.16, 0.16]:
					MeshUtil.rod(p, Vector3(sx - 0.16, 0, sz), Vector3(sx - 0.16, 0.45, sz), 0.015, iron)
					MeshUtil.rod(p, Vector3(sx + 0.16, 0, sz), Vector3(sx + 0.16, 0.45, sz), 0.015, iron)
			MeshUtil.cylinder(p, 0.04, 0.1, Vector3(0.12, 0.81, 0.08), white)  # a cup left behind
			return p
		"board":
			# A shop's folding pavement sign.
			var p := Prop.make(Vector3(0.6, 1.0, 0.55), 8.0)
			for lean in [-1.0, 1.0]:
				var face := MeshUtil.box(p, Vector3(0.56, 0.95, 0.03), Vector3(0, 0.47, lean * 0.14), _mat(Color(0.12, 0.13, 0.12), 0.9))
				face.rotation.x = lean * 0.28
				var chalk := MeshUtil.box(p, Vector3(0.4, 0.06, 0.035), Vector3(0, 0.7, lean * 0.09), white)
				chalk.rotation.x = lean * 0.28
				var chalk2 := MeshUtil.box(p, Vector3(0.3, 0.04, 0.035), Vector3(0, 0.52, lean * 0.14), _mat(Color(0.9, 0.8, 0.3), 0.8))
				chalk2.rotation.x = lean * 0.28
			return p
		"phone":
			var red := _mat(Color(0.62, 0.12, 0.1), 0.5)
			var p := Prop.make(Vector3(0.95, 2.4, 0.95), 160.0)
			for sx in [-0.42, 0.42]:
				for sz in [-0.42, 0.42]:
					MeshUtil.box(p, Vector3(0.08, 2.2, 0.08), Vector3(sx, 1.1, sz), red)
			MeshUtil.box(p, Vector3(0.92, 0.2, 0.92), Vector3(0, 2.28, 0), red)
			MeshUtil.box(p, Vector3(0.6, 0.1, 0.02), Vector3(0, 2.28, -0.47), white)
			for face in [[Vector3(0.78, 1.8, 0.02), Vector3(0, 1.2, 0.42)], [Vector3(0.02, 1.8, 0.78), Vector3(0.42, 1.2, 0)], [Vector3(0.02, 1.8, 0.78), Vector3(-0.42, 1.2, 0)]]:
				MeshUtil.box(p, face[0], face[1], glass)
			MeshUtil.box(p, Vector3(0.25, 0.35, 0.12), Vector3(0, 1.3, 0.32), iron)  # the telephone
			return p
		"cart":
			# A shopping trolley left in the car park.
			var p := Prop.make(Vector3(0.6, 1.0, 0.95), 14.0)
			MeshUtil.box(p, Vector3(0.5, 0.02, 0.8), Vector3(0, 0.45, 0), iron)
			for sx in [-0.25, 0.25]:
				MeshUtil.box(p, Vector3(0.015, 0.35, 0.8), Vector3(sx, 0.63, 0), iron)
			for sz in [-0.4, 0.4]:
				MeshUtil.box(p, Vector3(0.5, 0.35, 0.015), Vector3(0, 0.63, sz), iron)
			MeshUtil.rod(p, Vector3(-0.25, 0.95, 0.46), Vector3(0.25, 0.95, 0.46), 0.018, _mat(Color(0.75, 0.2, 0.15), 0.5))
			_wheels(p, 0.22, [-0.35, 0.35], 0.06, tyre)
			return p
		"swing":
			var p := Prop.make(Vector3(2.6, 2.2, 1.5), 55.0)
			for sx in [-1.2, 1.2]:
				MeshUtil.rod(p, Vector3(sx, 0, -0.7), Vector3(sx, 2.1, 0), 0.035, paint)
				MeshUtil.rod(p, Vector3(sx, 0, 0.7), Vector3(sx, 2.1, 0), 0.035, paint)
			MeshUtil.rod(p, Vector3(-1.2, 2.1, 0), Vector3(1.2, 2.1, 0), 0.035, paint)
			for sx in [-0.5, 0.5]:
				for chain in [-0.18, 0.18]:
					MeshUtil.rod(p, Vector3(sx + chain, 2.1, 0), Vector3(sx + chain, 0.5, 0), 0.008, iron)
				MeshUtil.box(p, Vector3(0.45, 0.03, 0.16), Vector3(sx, 0.5, 0), wood)
			return p
		"bbq":
			var p := Prop.make(Vector3(0.6, 1.0, 0.6), 14.0)
			for a in 3:
				MeshUtil.rod(p, Vector3(cos(a * TAU / 3.0) * 0.25, 0, sin(a * TAU / 3.0) * 0.25), Vector3(0, 0.7, 0), 0.015, iron)
			MeshUtil.cylinder(p, 0.2, 0.2, Vector3(0, 0.75, 0), iron, 0.3)
			MeshUtil.cylinder(p, 0.31, 0.16, Vector3(0, 0.93, 0), _mat(Color(0.5, 0.1, 0.08), 0.4), 0.1)
			return p
		"doghouse":
			var p := Prop.make(Vector3(0.9, 0.95, 1.1), 30.0)
			MeshUtil.box(p, Vector3(0.8, 0.55, 1.0), Vector3(0, 0.28, 0), wood)
			for lean in [-1.0, 1.0]:
				var slope := MeshUtil.box(p, Vector3(0.58, 0.04, 1.14), Vector3(lean * 0.22, 0.72, 0), _mat(Color(0.5, 0.2, 0.16), 0.8))
				slope.rotation.z = -lean * 0.7
			MeshUtil.box(p, Vector3(0.34, 0.38, 0.02), Vector3(0, 0.2, -0.505), _mat(Color(0.05, 0.05, 0.05), 1.0))
			MeshUtil.cylinder(p, 0.12, 0.05, Vector3(0.5, 0.03, -0.75), iron)  # the bowl
			return p
		"washing":
			# A line of washing between two posts.
			var p := Prop.make(Vector3(3.4, 1.95, 0.3), 16.0)
			for sx in [-1.6, 1.6]:
				MeshUtil.rod(p, Vector3(sx, 0, 0), Vector3(sx, 1.9, 0), 0.03, wood)
				MeshUtil.box(p, Vector3(0.05, 0.05, 0.5), Vector3(sx, 1.88, 0), wood)
			MeshUtil.rod(p, Vector3(-1.6, 1.85, 0), Vector3(1.6, 1.85, 0), 0.006, white)
			for k in 5:
				var cloth: Color = [Color(0.9, 0.9, 0.88), Color(0.3, 0.45, 0.7), Color(0.8, 0.3, 0.3), Color(0.9, 0.85, 0.5), Color(0.5, 0.7, 0.55)][rng.randi() % 5]
				var tall := rng.randf_range(0.4, 0.95)
				MeshUtil.box(p, Vector3(0.45, tall, 0.015), Vector3(-1.2 + k * 0.6, 1.83 - tall * 0.5, 0), _mat(cloth, 0.9))
			return p
		"woodpile":
			var p := Prop.make(Vector3(1.7, 0.95, 0.6), 130.0)
			for row in 4:
				for k in 7 - row % 2:
					MeshUtil.cylinder(p, 0.11, 0.55, Vector3(-0.72 + k * 0.24 + (row % 2) * 0.12, 0.12 + row * 0.2, 0), wood).rotation.x = PI * 0.5
			return p
		"stall":
			# A market stall: trestle table, crates of fruit, a striped awning on four poles.
			var p := Prop.make(Vector3(2.6, 2.3, 1.7), 90.0)
			MeshUtil.box(p, Vector3(2.4, 0.06, 1.0), Vector3(0, 0.85, 0), wood)
			for sx in [-1.0, 1.0]:
				MeshUtil.box(p, Vector3(0.06, 0.85, 0.9), Vector3(sx, 0.42, 0), wood)
				for sz in [-0.75, 0.75]:
					MeshUtil.rod(p, Vector3(sx * 1.2, 0, sz), Vector3(sx * 1.2, 2.1, sz), 0.03, iron)
			for k in 6:
				var stripe := MeshUtil.box(p, Vector3(0.44, 0.03, 1.8), Vector3(-1.1 + k * 0.44, 2.15, 0), white if k % 2 == 0 else paint)
				stripe.rotation.x = 0.12
			for k in 4:
				MeshUtil.box(p, Vector3(0.5, 0.2, 0.36), Vector3(-0.85 + k * 0.57, 0.98, 0.1), wood)
				MeshUtil.box(p, Vector3(0.44, 0.08, 0.3), Vector3(-0.85 + k * 0.57, 1.09, 0.1), _mat([Color(0.85, 0.3, 0.15), Color(0.9, 0.75, 0.2), Color(0.3, 0.6, 0.25), Color(0.7, 0.15, 0.2)][k], 0.7))
			return p
		"car":
			var p := Prop.make(Vector3(1.9, 1.5, 4.4), 1200.0)
			MeshUtil.box(p, Vector3(1.9, 0.8, 4.4), Vector3(0, 0.75, 0), paint)
			MeshUtil.box(p, Vector3(1.7, 0.7, 2.2), Vector3(0, 1.45, 0.25), glass)
			MeshUtil.box(p, Vector3(1.74, 0.1, 2.24), Vector3(0, 1.83, 0.25), paint)
			_wheels(p, 0.95, [-1.4, 1.4], 0.4, tyre)
			return p
		"van":
			var p := Prop.make(Vector3(2.1, 2.4, 5.2), 2200.0)
			MeshUtil.box(p, Vector3(2.1, 1.9, 5.2), Vector3(0, 1.4, 0), paint)
			MeshUtil.box(p, Vector3(1.9, 0.7, 0.1), Vector3(0, 1.85, -2.6), glass)
			_wheels(p, 1.05, [-1.7, 1.7], 0.45, tyre)
			return p
		"truck":
			var p := Prop.make(Vector3(2.5, 3.0, 7.6), 5200.0)
			MeshUtil.box(p, Vector3(2.4, 1.9, 2.0), Vector3(0, 1.5, -2.8), paint)
			MeshUtil.box(p, Vector3(2.2, 0.7, 0.1), Vector3(0, 1.95, -3.82), glass)
			MeshUtil.box(p, Vector3(2.5, 2.3, 5.2), Vector3(0, 1.85, 1.1), _mat(Color(0.42, 0.44, 0.36), 0.9))
			_wheels(p, 1.25, [-2.8, 0.6, 2.4], 0.52, tyre)
			return p
		"bus":
			var p := Prop.make(Vector3(2.6, 3.1, 10.5), 7500.0)
			MeshUtil.box(p, Vector3(2.6, 2.5, 10.5), Vector3(0, 1.75, 0), paint)
			for side in [-1.0, 1.0]:
				MeshUtil.box(p, Vector3(0.08, 0.9, 9.0), Vector3(side * 1.3, 2.15, 0), glass)
			MeshUtil.box(p, Vector3(2.3, 1.0, 0.08), Vector3(0, 2.1, -5.26), glass)
			MeshUtil.box(p, Vector3(2.64, 0.14, 10.54), Vector3(0, 3.05, 0), _mat(Color(0.86, 0.86, 0.82)))
			_wheels(p, 1.3, [-3.6, 3.2], 0.52, tyre)
			return p
		"lamp":
			var p := Prop.make(Vector3(0.35, 7.2, 0.35), 90.0)
			MeshUtil.cylinder(p, 0.14, 7.0, Vector3(0, 3.5, 0), iron)
			MeshUtil.box(p, Vector3(0.3, 0.16, 1.4), Vector3(0, 7.0, -0.6), iron)
			MeshUtil.box(p, Vector3(0.5, 0.22, 0.6), Vector3(0, 6.9, -1.1), _mat(Color(0.95, 0.92, 0.75), 0.3))
			return p
		"bench":
			var p := Prop.make(Vector3(2.4, 0.9, 0.7), 60.0)
			MeshUtil.box(p, Vector3(2.4, 0.1, 0.6), Vector3(0, 0.5, 0), wood)
			MeshUtil.box(p, Vector3(2.4, 0.5, 0.08), Vector3(0, 0.85, 0.28), wood)
			for sx in [-1.0, 1.0]:
				MeshUtil.box(p, Vector3(0.1, 0.5, 0.6), Vector3(sx * 1.0, 0.25, 0), iron)
			return p
		"bin":
			var p := Prop.make(Vector3(0.7, 1.0, 0.7), 25.0)
			MeshUtil.cylinder(p, 0.34, 1.0, Vector3(0, 0.5, 0), _mat(Color(0.22, 0.34, 0.26), 0.6))
			return p
		"sign":
			var p := Prop.make(Vector3(0.3, 3.0, 0.3), 30.0)
			MeshUtil.cylinder(p, 0.06, 3.0, Vector3(0, 1.5, 0), iron)
			MeshUtil.box(p, Vector3(0.9, 0.9, 0.06), Vector3(0, 2.6, 0), _mat([Color(0.8, 0.14, 0.12), Color(0.9, 0.75, 0.15), Color(0.16, 0.34, 0.6)][rng.randi() % 3], 0.5))
			return p
		"bus_stop":
			var p := Prop.make(Vector3(4.0, 2.8, 1.6), 300.0)
			for sx in [-1.0, 1.0]:
				MeshUtil.box(p, Vector3(0.12, 2.6, 0.12), Vector3(sx * 1.9, 1.3, 0.7), iron)
			MeshUtil.box(p, Vector3(4.0, 2.2, 0.06), Vector3(0, 1.5, 0.75), glass)
			MeshUtil.box(p, Vector3(4.2, 0.12, 1.8), Vector3(0, 2.7, 0), iron)
			MeshUtil.box(p, Vector3(3.2, 0.1, 0.5), Vector3(0, 0.5, 0.4), wood)
			return p
		"fence":
			# A length of post-and-rail fence.
			var p := Prop.make(Vector3(4.0, 1.2, 0.2), 70.0)
			for sx in [-1.9, 0.0, 1.9]:
				MeshUtil.box(p, Vector3(0.14, 1.2, 0.14), Vector3(sx, 0.6, 0), wood)
			for y in [0.5, 1.0]:
				MeshUtil.box(p, Vector3(4.0, 0.12, 0.06), Vector3(0, y, 0), wood)
			return p
		"picket":
			# A length of white garden fence.
			var p := Prop.make(Vector3(4.0, 1.0, 0.16), 50.0)
			MeshUtil.box(p, Vector3(4.0, 0.08, 0.05), Vector3(0, 0.35, 0), white)
			MeshUtil.box(p, Vector3(4.0, 0.08, 0.05), Vector3(0, 0.75, 0), white)
			for k in 10:
				MeshUtil.box(p, Vector3(0.14, 1.0, 0.04), Vector3(-1.8 + k * 0.4, 0.5, 0.04), white)
			return p
		"sandbags":
			# A chest-high wall of sandbags, three courses.
			var bag := _mat(Color(0.55, 0.5, 0.36), 1.0)
			var p := Prop.make(Vector3(5.6, 1.5, 1.0), 900.0)
			for row in 3:
				for k in 4 - (row % 2):
					MeshUtil.box(p, Vector3(1.3, 0.48, 0.9), Vector3(-2.1 + k * 1.4 + (row % 2) * 0.7, 0.25 + row * 0.5, 0), bag)
			return p
		"crates":
			var p := Prop.make(Vector3(2.4, 2.2, 1.3), 220.0)
			MeshUtil.box(p, Vector3(1.2, 1.2, 1.2), Vector3(-0.6, 0.6, 0), wood)
			MeshUtil.box(p, Vector3(1.1, 1.1, 1.1), Vector3(0.62, 0.55, 0), wood)
			MeshUtil.box(p, Vector3(1.0, 1.0, 1.0), Vector3(-0.3, 1.7, 0), _mat(Color(0.42, 0.44, 0.3), 0.9))
			return p
		"barrels":
			var p := Prop.make(Vector3(1.9, 1.3, 1.0), 180.0)
			for k in 2:
				MeshUtil.cylinder(p, 0.42, 1.2, Vector3(-0.48 + k * 0.96, 0.6, 0), _mat([Color(0.5, 0.16, 0.12), Color(0.2, 0.3, 0.42), Color(0.3, 0.32, 0.28)][rng.randi() % 3], 0.6))
			return p
		"bale":
			var p := Prop.make(Vector3(3.4, 3.0, 3.0), 260.0)
			var roll := MeshUtil.cylinder(p, 1.5, 3.4, Vector3(0, 1.5, 0), _mat(Color(0.74, 0.64, 0.36), 1.0))
			roll.rotation.z = PI * 0.5
			return p
		"cone":
			var p := Prop.make(Vector3(0.5, 0.8, 0.5), 5.0)
			MeshUtil.cylinder(p, 0.24, 0.8, Vector3(0, 0.4, 0), _mat(Color(0.9, 0.4, 0.1), 0.6), 0.04)
			return p
	return Prop.make(Vector3.ONE, 50.0)


static func _wheels(p: Node3D, half_track: float, at_z: Array, radius: float, mat: Material) -> void:
	for wx in [-half_track, half_track]:
		for wz in at_z:
			var wheel := MeshUtil.cylinder(p, radius, 0.3, Vector3(wx, radius, wz), mat)
			wheel.rotation.z = PI * 0.5
