class_name AircraftModel
extends RefCounted
# Low-polygon models of the six aircraft, each shaped after the real one. Everything is in
# metres, nose towards -Z, the ground at height 0.
#
# How the shapes are written down:
#   body    a row of rounded cross-sections: [z, half width, bottom, top, squareness 0-1]
#   wing    the right-hand wing's root and tip: [x, z of the leading edge, chord, thickness]
#           (the left one is mirrored); wing_y is its height, dihedral how far the tip rises
#   tail    the tailplane, written the same way
#   fin     root and tip: [z of the leading edge, chord, height]
#   canopy  [z front, z back, half width, height of its base, how tall]
# The two helicopters are too different to share a table and are built by hand further down.

const SHAPES := {
	# F-86 Sabre: nose intake, bubble canopy, low wings swept back 35 degrees.
	"sabre": {"paint": Color(0.72, 0.74, 0.76),
		"body": [[-5.7, 0.42, 1.05, 1.85], [-5.0, 0.6, 0.85, 2.05], [-3.5, 0.74, 0.72, 2.2], [-1.0, 0.78, 0.7, 2.25], [2.0, 0.68, 0.8, 2.15], [4.2, 0.5, 1.0, 2.0], [5.7, 0.36, 1.2, 1.9]],
		"wing": [[0.6, -1.6, 2.8, 0.28], [5.6, 1.3, 1.1, 0.1]], "wing_y": 1.0, "dihedral": 0.25,
		"tail": [[0.15, 4.0, 1.3, 0.12], [2.4, 5.2, 0.7, 0.06]], "tail_y": 2.2, "tail_rise": 0.3,
		"fin": [[3.2, 2.6, 2.0], [5.5, 0.9, 4.4]], "canopy": [-3.7, -1.3, 0.37, 2.15, 0.58], "intake": true},
	# MiG-15: stubby barrel of a fuselage, mid wings with fences, a tall swept fin with the tailplane high on it.
	"mig15": {"paint": Color(0.66, 0.68, 0.68),
		"body": [[-5.0, 0.55, 0.95, 1.95], [-4.2, 0.72, 0.8, 2.2], [-2.5, 0.84, 0.7, 2.4], [0.0, 0.84, 0.7, 2.4], [2.5, 0.7, 0.85, 2.25], [4.2, 0.5, 1.05, 2.05], [5.0, 0.42, 1.2, 1.95]],
		"wing": [[0.75, -1.2, 2.6, 0.28], [5.0, 1.7, 1.0, 0.1]], "wing_y": 1.5, "dihedral": -0.15,
		"tail": [[0.08, 4.7, 1.0, 0.1], [1.9, 5.7, 0.6, 0.05]], "tail_y": 4.0, "tail_rise": 0.0,
		"fin": [[2.4, 3.0, 2.2], [5.0, 1.2, 5.2]], "canopy": [-3.0, -0.9, 0.34, 2.33, 0.52], "intake": true, "fences": true},
	# A-1 Skyraider: big round engine, long straight wings, a four-bladed propeller.
	"skyraider": {"paint": Color(0.33, 0.38, 0.44),
		"body": [[-5.9, 0.78, 0.85, 2.4], [-5.0, 0.84, 0.8, 2.45], [-3.6, 0.82, 0.8, 2.45], [-1.0, 0.7, 0.8, 2.5], [1.5, 0.58, 0.95, 2.35], [3.5, 0.42, 1.15, 2.15], [5.9, 0.16, 1.5, 1.9]],
		"wing": [[0.7, -2.6, 2.9, 0.36], [7.6, -1.9, 1.4, 0.12]], "wing_y": 1.05, "dihedral": 0.45,
		"tail": [[0.15, 4.2, 1.5, 0.14], [2.7, 4.5, 1.0, 0.07]], "tail_y": 1.9, "tail_rise": 0.0,
		"fin": [[3.4, 2.5, 1.9], [4.8, 1.1, 4.3]], "canopy": [-2.3, -0.1, 0.37, 2.4, 0.58], "prop": 2.0, "blades": 4},
	# Il-10: pointed inline nose, a long glasshouse for pilot and gunner, straight wings.
	"il10": {"paint": Color(0.3, 0.38, 0.28),
		"body": [[-5.5, 0.3, 1.25, 1.85], [-5.0, 0.48, 1.05, 2.05], [-4.0, 0.62, 0.9, 2.25], [-1.0, 0.7, 0.8, 2.5], [1.5, 0.58, 0.95, 2.35], [3.5, 0.42, 1.15, 2.1], [5.5, 0.16, 1.5, 1.9]],
		"wing": [[0.7, -2.3, 3.0, 0.36], [6.7, -1.3, 1.2, 0.12]], "wing_y": 1.05, "dihedral": 0.4,
		"tail": [[0.15, 4.0, 1.4, 0.14], [2.5, 4.4, 0.8, 0.07]], "tail_y": 1.9, "tail_rise": 0.0,
		"fin": [[3.2, 2.3, 1.9], [4.6, 1.0, 4.1]], "canopy": [-2.6, 0.8, 0.37, 2.4, 0.6], "prop": 1.8, "blades": 3},
	# The helicopters: only the paint lives here ("rotor" marks them as helicopters).
	"apache": {"paint": Color(0.25, 0.29, 0.22), "rotor": true},
	"mi8": {"paint": Color(0.3, 0.36, 0.26), "rotor": true},
}


# Joins a row of rings of points into a closed skin, with a flat cap on each end.
static func _skin(parent: Node3D, rings: Array, mat: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = (rings[0] as Array).size()
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var centre := Vector3.ZERO
		for p in a + b:
			centre += p
		centre /= float(count * 2)
		for k in count:
			var n := (k + 1) % count
			MeshUtil._tri(st, centre, a[k], a[n], b[n])
			MeshUtil._tri(st, centre, a[k], b[n], b[k])
	var whole := Vector3.ZERO
	for ring in rings:
		for p in ring:
			whole += p
	whole /= float(count * rings.size())
	for end in [0, rings.size() - 1]:
		var r: Array = rings[end]
		for k in range(1, count - 1):
			MeshUtil._tri(st, whole, r[0], r[k], r[k + 1])
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = mat
	m.position = at
	parent.add_child(m)
	return m


# A rounded body from cross-sections [z, half width, bottom, top, squareness]: fuselages,
# canopies, engine pods, fuel tanks. Squareness 0 is an oval, 1 nearly a box.
static func _hull(parent: Node3D, sections: Array, mat: Material, at: Vector3 = Vector3.ZERO, sides: int = 14) -> MeshInstance3D:
	var rings: Array = []
	for s in sections:
		var mid: float = (float(s[2]) + float(s[3])) * 0.5
		var half: float = (float(s[3]) - float(s[2])) * 0.5
		var power: float = 1.0 - 0.7 * (float(s[4]) if s.size() > 4 else 0.0)
		var ring: Array = []
		for k in sides:
			var a := TAU * float(k) / float(sides)
			var cx := cos(a)
			var sy := sin(a)
			ring.append(Vector3(signf(cx) * pow(absf(cx), power) * float(s[1]), mid + signf(sy) * pow(absf(sy), power) * half, s[0]))
		rings.append(ring)
	return _skin(parent, rings, mat, at)


# A wing-shaped slab between two stations. A station is [leading-edge point, chord, thickness];
# the chord runs back along +Z, and `axis` is the way the thickness goes (up for a wing,
# sideways for a fin).
static func _foil(parent: Node3D, a: Array, b: Array, axis: Vector3, mat: Material) -> void:
	var rings: Array = []
	for s in [a, b]:
		var le: Vector3 = s[0]
		var c: float = s[1]
		var t: float = s[2]
		rings.append([le, le + Vector3(0, 0, c * 0.25) + axis * t * 0.5, le + Vector3(0, 0, c * 0.65) + axis * t * 0.35,
			le + Vector3(0, 0, c), le + Vector3(0, 0, c * 0.65) - axis * t * 0.35, le + Vector3(0, 0, c * 0.25) - axis * t * 0.5])
	_skin(parent, rings, mat)


# The station part of the way (0 root, 1 tip) between two stations.
static func _between(a: Array, b: Array, f: float) -> Array:
	return [(a[0] as Vector3).lerp(b[0], f), lerpf(a[1], b[1], f), lerpf(a[2], b[2], f)]


# A band of another colour painted round a wing or fin between two fractions of its length.
static func _band(parent: Node3D, a: Array, b: Array, from: float, to: float, axis: Vector3, mat: Material) -> void:
	var one := _between(a, b, from)
	var two := _between(a, b, to)
	for s in [one, two]:
		s[0] = (s[0] as Vector3) - Vector3(0, 0, 0.02)
		s[1] = float(s[1]) + 0.04
		s[2] = float(s[2]) + 0.03
	_foil(parent, one, two, axis, mat)


# A wheel on a leg: `top` is where the leg joins the aircraft, `hub` the middle of the wheel.
# A wheel on its leg, hinged where the leg meets the aircraft (	op), so it can fold away.
static func _wheel(parent: Node3D, top: Vector3, hub: Vector3, radius: float, tyre: Material, leg: Material) -> Node3D:
	var gear := Node3D.new()
	gear.position = top
	parent.add_child(gear)
	MeshUtil.rod(gear, Vector3.ZERO, hub - top, 0.07, leg)
	MeshUtil.cylinder(gear, radius, radius * 0.6, hub - top, tyre).rotation.z = PI * 0.5
	MeshUtil.cylinder(gear, radius * 0.45, radius * 0.64, hub - top, leg).rotation.z = PI * 0.5
	return gear


# A streamlined store lying along Z with its middle at `at`: a drop tank, a bomb, an engine pod.
static func _pod(parent: Node3D, at: Vector3, radius: float, length: float, mat: Material) -> void:
	var h := length * 0.5
	_hull(parent, [[-h, radius * 0.12, -radius * 0.12, radius * 0.12], [-h * 0.55, radius * 0.85, -radius * 0.85, radius * 0.85],
		[-h * 0.1, radius, -radius, radius], [h * 0.45, radius * 0.85, -radius * 0.85, radius * 0.85], [h, radius * 0.15, -radius * 0.15, radius * 0.15]], mat, at, 8)


# A bomb: a pod with four fins at the back.
static func _bomb(parent: Node3D, at: Vector3, radius: float, length: float, mat: Material) -> void:
	_pod(parent, at, radius, length, mat)
	MeshUtil.box(parent, Vector3(radius * 2.2, 0.03, length * 0.22), at + Vector3(0, 0, length * 0.4), mat)
	MeshUtil.box(parent, Vector3(0.03, radius * 2.2, length * 0.22), at + Vector3(0, 0, length * 0.4), mat)


# A tube of unguided rockets: a drum with a dark face of holes at the front.
static func _rocket_pod(parent: Node3D, at: Vector3, radius: float, length: float, mat: Material, black: Material) -> void:
	MeshUtil.cylinder(parent, radius, length, at, mat).rotation.x = PI * 0.5
	MeshUtil.cylinder(parent, radius * 0.82, 0.05, at - Vector3(0, 0, length * 0.5 + 0.01), black).rotation.x = PI * 0.5
	MeshUtil.cylinder(parent, radius * 0.6, length * 0.2, at + Vector3(0, 0, length * 0.58), mat, radius * 0.95).rotation.x = PI * 0.5


# A main rotor: a hub with drooping blades. Returns the part that turns.
static func _rotor(parent: Node3D, at: Vector3, radius: float, blades: int, chord: float, black: Material, dark: Material) -> Node3D:
	var mast := Node3D.new()
	mast.position = at
	parent.add_child(mast)
	MeshUtil.cylinder(mast, 0.42, 0.22, Vector3.ZERO, dark)
	MeshUtil.cylinder(mast, 0.2, 0.3, Vector3(0, 0.2, 0), dark, 0.1)
	for k in blades:
		var arm := Node3D.new()
		arm.rotation.y = float(k) / float(blades) * TAU
		mast.add_child(arm)
		var droop := Node3D.new()
		droop.rotation.z = -0.03  # blades hang a little under their own weight
		arm.add_child(droop)
		MeshUtil.box(droop, Vector3(1.0, 0.12, chord * 0.5), Vector3(0.7, 0, 0), dark)
		MeshUtil.box(droop, Vector3(radius - 1.1, 0.06, chord), Vector3(1.1 + (radius - 1.1) * 0.5, 0, 0), black)
	return mast


# A tail rotor on the side of the fin; `angles` are where its blades sit round the hub.
static func _tail_rotor(parent: Node3D, at: Vector3, radius: float, angles: Array, black: Material, dark: Material) -> Node3D:
	var hub := Node3D.new()
	hub.position = at
	parent.add_child(hub)
	MeshUtil.cylinder(hub, 0.13, 0.3, Vector3.ZERO, dark).rotation.z = PI * 0.5
	for a in angles:
		var arm := Node3D.new()
		arm.rotation.x = a
		hub.add_child(arm)
		MeshUtil.box(arm, Vector3(0.05, radius, 0.24), Vector3(0, radius * 0.5, 0), black)
	return hub


static var _sheet := {}

# An aircraft's row of data/aircraft.json. (Read here, not through Aircraft, so the models
# can be built by the picture tools, which run without the game's sounds loaded.)
static func sheet_row(id: String) -> Dictionary:
	if _sheet.is_empty():
		for row in JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft.json"))["rows"]:
			_sheet[row["id"]] = row
	return _sheet.get(id, {})


# Where the pilot's eyes are, in the model's space.
static func pilot_eye(id: String) -> Vector3:
	if id == "apache":
		return Vector3(0, 2.82, -2.95)
	if id == "mi8":
		return Vector3(0.45, 2.3, -8.05)
	var c: Array = SHAPES.get(id, SHAPES["sabre"])["canopy"]
	var long: float = float(c[1]) - float(c[0])
	return Vector3(0, float(c[3]) + float(c[4]) * 0.5, float(c[0]) + minf(long * 0.5, 1.15))


# The inside of the cockpit, as seen from the pilot's seat. Its origin is the pilot's eye,
# looking forward along -Z. A modern helicopter gets two glowing screens; the older aircraft
# get a panel of round dials and a gunsight. All have a control stick between the knees and
# a throttle (or collective) lever on the left, both of which move with the controls, and
# two warning lamps on the coaming that flash when a missile is coming.
# Returns {"root", "stick", "lever", "lamps": [...], "lamp_on", "lamp_off", "text": [Label3D...]}.
static func cockpit(id: String) -> Dictionary:
	var root := Node3D.new()
	var black := MeshUtil.material(Color(0.05, 0.05, 0.055), 0.9)
	var grey := MeshUtil.material(Color(0.2, 0.21, 0.22), 0.8)
	var metal := MeshUtil.material(Color(0.45, 0.46, 0.48), 0.5)
	var lamp_off := MeshUtil.material(Color(0.25, 0.04, 0.03), 0.6)
	var lamp_on := StandardMaterial3D.new()
	lamp_on.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_on.albedo_color = Color(1.0, 0.15, 0.1)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.05, 0.22, 0.1)
	var modern: bool = id == "apache"
	# The instrument panel under its glare shield, leaning away at the top.
	var panel := Node3D.new()
	panel.position = Vector3(0, -0.42, -0.82)
	panel.rotation.x = -0.22
	root.add_child(panel)
	MeshUtil.box(panel, Vector3(0.84, 0.38, 0.05), Vector3.ZERO, grey)
	MeshUtil.box(root, Vector3(0.92, 0.035, 0.36), Vector3(0, -0.2, -0.72), black)
	# The windscreen frame: a post each side and a bar across the top.
	for side in [-1.0, 1.0]:
		MeshUtil.rod(root, Vector3(side * 0.46, -0.2, -0.86), Vector3(side * 0.34, 0.4, -0.5), 0.018, black)
	MeshUtil.rod(root, Vector3(-0.34, 0.4, -0.5), Vector3(0.34, 0.4, -0.5), 0.018, black)
	var text: Array = []
	if modern:
		# Two multi-function displays: green screens with the flight figures written on them.
		for side in [-1.0, 1.0]:
			MeshUtil.box(panel, Vector3(0.27, 0.27, 0.02), Vector3(side * 0.2, 0.01, 0.03), black)
			MeshUtil.box(panel, Vector3(0.22, 0.22, 0.01), Vector3(side * 0.2, 0.01, 0.045), glow)
			for k in 5:
				MeshUtil.box(panel, Vector3(0.022, 0.012, 0.01), Vector3(side * 0.2 + (k - 2) * 0.045, -0.118, 0.045), metal)  # the buttons along the bottom
			var words := Label3D.new()
			words.pixel_size = 0.00075
			words.font_size = 40
			words.modulate = Color(0.45, 1.0, 0.55)
			words.shaded = false
			words.position = Vector3(side * 0.2, 0.01, 0.055)
			panel.add_child(words)
			text.append(words)
	else:
		# Six round dials, each with a needle, and a strip of figures above them.
		for k in 6:
			var at := Vector3((float(k % 3) - 1.0) * 0.2, 0.07 - float(k / 3) * 0.17, 0.03)
			var dial := MeshUtil.cylinder(panel, 0.07, 0.02, at, black)
			dial.rotation.x = PI * 0.5
			var rim := MeshUtil.cylinder(panel, 0.078, 0.012, at - Vector3(0, 0, 0.004), metal)
			rim.rotation.x = PI * 0.5
			var needle := MeshUtil.box(panel, Vector3(0.008, 0.055, 0.004), at + Vector3(0, 0, 0.014), MeshUtil.material(Color(0.9, 0.9, 0.85), 0.6))
			needle.rotation.z = float(k) * 1.1 - 2.0
		for side in [-1.0, 1.0]:
			var words := Label3D.new()
			words.pixel_size = 0.0007
			words.font_size = 36
			words.modulate = Color(1.0, 0.8, 0.35)
			words.shaded = false
			words.position = Vector3(side * 0.32, 0.165, 0.035)
			panel.add_child(words)
			text.append(words)
		# The reflector gunsight on top of the panel.
		MeshUtil.box(root, Vector3(0.09, 0.07, 0.1), Vector3(0, -0.15, -0.66), black)
		var glass := StandardMaterial3D.new()
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.albedo_color = Color(0.7, 0.9, 1.0, 0.12)
		glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		MeshUtil.box(root, Vector3(0.1, 0.11, 0.004), Vector3(0, -0.05, -0.66), glass)
		for side in [-1.0, 1.0]:
			MeshUtil.box(root, Vector3(0.006, 0.12, 0.006), Vector3(side * 0.052, -0.05, -0.66), metal)
	# Missile warning lamps.
	var lamps: Array = []
	for side in [-1.0, 1.0]:
		lamps.append(MeshUtil.box(root, Vector3(0.05, 0.035, 0.02), Vector3(side * 0.36, -0.165, -0.62), lamp_off))
	# Side consoles, the floor, and the seat's headrest behind.
	for side in [-1.0, 1.0]:
		MeshUtil.box(root, Vector3(0.16, 0.06, 1.0), Vector3(side * 0.44, -0.42, -0.15), grey)
		for k in 4:
			MeshUtil.box(root, Vector3(0.03, 0.02, 0.03), Vector3(side * 0.44, -0.38, -0.5 + k * 0.16), metal)  # switches
	MeshUtil.box(root, Vector3(1.0, 0.02, 1.4), Vector3(0, -0.85, -0.2), black)
	MeshUtil.box(root, Vector3(0.3, 0.36, 0.08), Vector3(0, -0.02, 0.32), grey)
	# The stick, on a pivot at the floor, and the throttle lever on the left console.
	var stick := Node3D.new()
	stick.position = Vector3(0, -0.8, -0.4)
	root.add_child(stick)
	MeshUtil.rod(stick, Vector3.ZERO, Vector3(0, 0.4, 0), 0.016, metal)
	MeshUtil.box(stick, Vector3(0.04, 0.12, 0.045), Vector3(0, 0.45, 0), black)
	MeshUtil.box(stick, Vector3(0.02, 0.02, 0.02), Vector3(0.0, 0.5, -0.02), lamp_off)  # the firing button
	var lever := Node3D.new()
	lever.position = Vector3(-0.44, -0.39, -0.28)
	root.add_child(lever)
	MeshUtil.rod(lever, Vector3.ZERO, Vector3(0, 0.15, 0), 0.012, metal)
	MeshUtil.box(lever, Vector3(0.05, 0.04, 0.04), Vector3(0, 0.16, 0), black)
	return {"root": root, "stick": stick, "lever": lever, "lamps": lamps, "lamp_on": lamp_on, "lamp_off": lamp_off, "text": text}


# Where each pylon's store hangs, in the model's space, from the left wing tip across to the
# right. `per_side` is how many pylons each wing has.
static func pylon_points(id: String, per_side: int) -> Array:
	var out: Array = []
	var spots: Array = []  # one wing's points, innermost first
	if id == "apache":
		spots = [Vector3(1.4, 1.22, -0.45), Vector3(2.25, 1.2, -0.4)]
	elif id == "mi8":
		spots = [Vector3(2.1, 1.5, -4.6), Vector3(2.95, 1.5, -4.6)]
	else:
		var shape: Dictionary = SHAPES.get(id, SHAPES["sabre"])
		var wing: Array = shape["wing"]
		var a := Vector3(float(wing[0][0]) * 0.5, shape["wing_y"], wing[0][1])
		var b := Vector3(wing[1][0], float(shape["wing_y"]) + float(shape["dihedral"]), wing[1][1])
		for f in ([0.42] if per_side <= 1 else ([0.36, 0.64] if per_side == 2 else [0.34, 0.54, 0.74])):
			var chord := lerpf(wing[0][2], wing[1][2], f)
			var thick := lerpf(wing[0][3], wing[1][3], f)
			spots.append(a.lerp(b, f) + Vector3(0, -thick * 0.5 - 0.16, chord * 0.42))
	spots = spots.slice(0, per_side)
	for k in range(spots.size() - 1, -1, -1):
		out.append(spots[k] * Vector3(-1, 1, 1))
	for k in spots.size():
		out.append(spots[k])
	return out


# Returns {"root": the model, "spin": [things that go round: [node, axis, turns a second]],
# "stores": the model of what hangs on each pylon (null where one is empty), "pylons": where}.
# `loadout` names the store on each pylon (see Ordnance); left out, the aircraft's usual one.
static func build(id: String, team_color: Color, loadout: Array = []) -> Dictionary:
	var row := sheet_row(id)
	var shape: Dictionary = SHAPES.get(id, SHAPES["sabre"])
	var root := Node3D.new()
	var mats := {
		"paint": MeshUtil.material(shape["paint"], 0.55),
		"dark": MeshUtil.material(Color(shape["paint"]).darkened(0.45), 0.6),
		"metal": MeshUtil.material(Color(0.3, 0.31, 0.32), 0.5),
		"glass": MeshUtil.material(Color(0.14, 0.22, 0.28), 0.12),
		"black": MeshUtil.material(Color(0.07, 0.07, 0.07), 0.8),
		"mark": MeshUtil.material(team_color, 0.5),
	}
	var spin: Array = []
	_gear = []
	if id == "apache":
		_apache(root, mats, spin)
	elif id == "mi8":
		_mi8(root, mats, spin)
	else:
		_plane(root, shape, mats, spin)
	# The glazing is marked, so it can be taken away when the view is from the pilot's seat.
	for part in root.get_children():
		if part is MeshInstance3D and part.material_override == mats["glass"]:
			part.set_meta("canopy", true)
	# In place of those, thin frames that can be seen past from inside (shown only then).
	# The pylons and what hangs on them.
	var points := pylon_points(id, int(row.get("pylons", 0)))
	var carried: Array = loadout if loadout.size() == points.size() else row.get("loadout", [])
	var stores: Array = []
	for i in points.size():
		MeshUtil.box(root, Vector3(0.09, 0.2, 0.8), (points[i] as Vector3) + Vector3(0, 0.07, 0), mats["dark"])
		var store := Ordnance.build(String(carried[i]) if i < carried.size() else "none", bool(row.get("east", false)))
		if store != null:
			store.position = points[i]
			root.add_child(store)
		stores.append(store)
	return {"root": root, "spin": spin, "stores": stores, "pylons": points, "gear": _gear.duplicate()}


# A plane's retracting wheels, collected while it is built: [leg, hinge axis, folded angle].
# (Helicopters keep theirs down.) aircraft.gd turns each leg by up to its angle to tuck it away.
static var _gear: Array = []


static func _plane(root: Node3D, shape: Dictionary, mats: Dictionary, spin: Array) -> void:
	var paint: Material = mats["paint"]
	var dark: Material = mats["dark"]
	var black: Material = mats["black"]
	var metal: Material = mats["metal"]
	var body: Array = shape["body"]
	var nose: Array = body[0]
	var last: Array = body[-1]
	var jet: bool = shape.get("intake", false)
	_hull(root, body, paint)

	# Wings and tailplanes, with the team's colour on the wing tips.
	var wing: Array = shape["wing"]
	var tail: Array = shape["tail"]
	var wing_y: float = shape["wing_y"]
	var rise: float = shape["dihedral"]
	var roots: Array = []
	var tips: Array = []
	for side in [1.0, -1.0]:
		var w0: Array = [Vector3(float(wing[0][0]) * side * 0.5, wing_y, wing[0][1]), wing[0][2], wing[0][3]]
		var w1: Array = [Vector3(float(wing[1][0]) * side, wing_y + rise, wing[1][1]), wing[1][2], wing[1][3]]
		_foil(root, w0, w1, Vector3.UP, paint)
		_band(root, w0, w1, 0.9, 1.0, Vector3.UP, mats["mark"])
		roots.append(w0)
		tips.append(w1)
		var t0: Array = [Vector3(0.0, shape["tail_y"], tail[0][1]), tail[0][2], tail[0][3]]
		var t1: Array = [Vector3(float(tail[1][0]) * side, float(shape["tail_y"]) + float(shape["tail_rise"]), tail[1][1]), tail[1][2], tail[1][3]]
		_foil(root, t0, t1, Vector3.UP, paint)

	# The fin, with a band of the team's colour near its top.
	var fin: Array = shape["fin"]
	var f0: Array = [Vector3(0, fin[0][2], fin[0][0]), fin[0][1], 0.18]
	var f1: Array = [Vector3(0, fin[1][2], fin[1][0]), fin[1][1], 0.07]
	_foil(root, f0, f1, Vector3.RIGHT, paint)
	_band(root, f0, f1, 0.68, 0.9, Vector3.RIGHT, mats["mark"])

	# The canopy: a glass blister with dark frames round it.
	var c: Array = shape["canopy"]
	var cz: float = c[0]
	var cl: float = float(c[1]) - cz
	var hw: float = c[2]
	var base: float = c[3]
	var tall: float = c[4]
	var flat_from := 0.18 if cl > 2.8 else 0.3
	var flat_to := 0.82 if cl > 2.8 else 0.62
	_hull(root, [[cz, hw * 0.3, base - 0.05, base + 0.1], [cz + cl * flat_from, hw, base - 0.12, base + tall],
		[cz + cl * flat_to, hw, base - 0.12, base + tall * 0.97], [cz + cl, hw * 0.45, base - 0.05, base + tall * 0.3]], mats["glass"], Vector3.ZERO, 10)
	var hoops := maxi(2, int(cl * (flat_to - flat_from) / 0.75) + 1)
	for k in hoops:
		var hz: float = cz + cl * lerpf(flat_from, flat_to, float(k) / float(hoops - 1))
		_hull(root, [[hz - 0.035, hw * 1.05, base - 0.12, base + tall + 0.02], [hz + 0.035, hw * 1.05, base - 0.12, base + tall + 0.02]], dark, Vector3.ZERO, 10).set_meta("canopy", true)  # (a solid disc: it goes with the glass when the view is from inside)

	# Where things hang under the wing: a point on its underside, part of the way out.
	var under := func(side_index: int, f: float) -> Vector3:
		var s := _between(roots[side_index], tips[side_index], f)
		return (s[0] as Vector3) + Vector3(0, -float(s[2]) * 0.5, float(s[1]) * 0.42)

	if jet:
		# The nose intake: a dark lip and a black hole.
		var mid: float = (float(nose[2]) + float(nose[3])) * 0.5
		var lip: float = float(nose[1])
		_hull(root, [[float(nose[0]) - 0.12, lip * 0.98, nose[2], nose[3]], [float(nose[0]) + 0.1, lip * 1.06, float(nose[2]) - 0.03, float(nose[3]) + 0.03]], dark)
		_hull(root, [[float(nose[0]) - 0.14, lip * 0.8, float(nose[2]) + 0.09, float(nose[3]) - 0.09], [float(nose[0]) - 0.1, lip * 0.8, float(nose[2]) + 0.09, float(nose[3]) - 0.09]], black)
		if shape.get("fences", false):
			# The MiG's intake is split down the middle, and its cannon hang under the nose.
			MeshUtil.box(root, Vector3(0.08, float(nose[3]) - float(nose[2]) - 0.12, 0.4), Vector3(0, mid, float(nose[0]) - 0.02), paint)
			for side in [1.0, -1.0]:
				MeshUtil.rod(root, Vector3(side * 0.28, float(nose[2]) - 0.02, float(nose[0]) + 1.6), Vector3(side * 0.28, float(nose[2]) + 0.02, float(nose[0]) + 0.1), 0.05, black)
		else:
			# The Sabre's six guns, three each side of the nose.
			for side in [1.0, -1.0]:
				for k in 3:
					MeshUtil.box(root, Vector3(0.08, 0.06, 0.4), Vector3(side * (lip + 0.1), mid - 0.16 + k * 0.16, float(nose[0]) + 1.0), black)
		# The jet pipe.
		var pipe_y: float = (float(last[2]) + float(last[3])) * 0.5
		MeshUtil.cylinder(root, float(last[1]) * 1.06, 0.55, Vector3(0, pipe_y, float(last[0]) - 0.15), metal).rotation.x = PI * 0.5
		MeshUtil.cylinder(root, float(last[1]) * 0.85, 0.06, Vector3(0, pipe_y, float(last[0]) + 0.13), black).rotation.x = PI * 0.5
		for i in 2:
			var side: float = 1.0 if i == 0 else -1.0
			if shape.get("fences", false):
				for f in [0.38, 0.68]:
					var s := _between(roots[i], tips[i], f)
					MeshUtil.box(root, Vector3(0.05, 0.2, float(s[1]) * 0.7), (s[0] as Vector3) + Vector3(0, float(s[2]) * 0.4 + 0.08, float(s[1]) * 0.38), paint)
			# Main wheels under the wing roots.
			var leg: Vector3 = under.call(i, 0.2)
			var main_leg := _wheel(root, leg, Vector3(leg.x, 0.3, leg.z + 0.1), 0.3, black, metal)
			MeshUtil.box(main_leg, Vector3(0.04, 0.5, 0.6), Vector3(side * 0.2, -0.3, 0), paint)  # its door
			_gear.append([main_leg, Vector3.BACK, -signf(leg.x) * 1.5])  # folds in under the wing
		var nose_z: float = float(nose[0]) + 1.9
		_gear.append([_wheel(root, Vector3(0, float(body[1][2]) + 0.1, nose_z - 0.1), Vector3(0, 0.26, nose_z), 0.26, black, metal), Vector3.RIGHT, 1.6])
		# The pitot tube on the right wing tip.
		var tip_le: Vector3 = tips[0][0]
		MeshUtil.rod(root, tip_le + Vector3(-0.15, 0, 0.2), tip_le + Vector3(-0.15, 0, -1.0), 0.025, metal)
	else:
		var hub_y: float = (float(nose[2]) + float(nose[3])) * 0.5
		var radial: bool = float(nose[1]) > 0.6
		var hub := Node3D.new()
		hub.position = Vector3(0, hub_y, float(nose[0]) - 0.25)
		root.add_child(hub)
		if radial:
			# A big round engine: a dark cowling ring, the black of the cylinders behind it, a small spinner.
			_hull(root, [[float(nose[0]) - 0.15, float(nose[1]) * 0.9, float(nose[2]) + 0.08, float(nose[3]) - 0.08], [float(nose[0]) + 0.25, float(nose[1]) * 1.04, float(nose[2]) - 0.03, float(nose[3]) + 0.03]], dark)
			MeshUtil.cylinder(root, float(nose[1]) * 0.72, 0.06, Vector3(0, hub_y, float(nose[0]) - 0.16), black).rotation.x = PI * 0.5
			MeshUtil.cylinder(hub, 0.24, 0.6, Vector3.ZERO, metal, 0.08).rotation.x = -PI * 0.5
			for side in [1.0, -1.0]:
				MeshUtil.box(root, Vector3(0.07, 0.3, 1.1), Vector3(side * (float(body[2][1]) + 0.02), hub_y - 0.25, float(body[2][0]) - 0.3), black)
		else:
			# An inline engine: a pointed spinner over the whole nose, and a row of exhaust stubs each side.
			MeshUtil.cylinder(hub, float(nose[1]) * 1.02, 0.9, Vector3(0, 0, -0.2), metal, 0.05).rotation.x = -PI * 0.5
			for side in [1.0, -1.0]:
				for k in 6:
					MeshUtil.box(root, Vector3(0.16, 0.07, 0.13), Vector3(side * (0.5 + k * 0.022), hub_y + 0.15, float(nose[0]) + 0.7 + k * 0.22), black)
			# The radiator scoop under the nose, and the rear gunner's machine gun.
			_hull(root, [[float(nose[0]) + 1.2, 0.3, 0.6, 1.05, 0.5], [float(nose[0]) + 3.0, 0.34, 0.55, 1.0, 0.5]], paint, Vector3.ZERO, 8)
			MeshUtil.rod(root, Vector3(0, base + tall * 0.6, cz + cl - 0.3), Vector3(0, base + tall * 0.95, cz + cl + 0.9), 0.04, black)
		var count: int = shape["blades"]
		var length: float = shape["prop"]
		for k in count:
			var arm := Node3D.new()
			arm.rotation.z = float(k) / float(count) * TAU
			hub.add_child(arm)
			# Each blade is twisted to bite the air, wider in the middle than at root or tip.
			var blade := MeshUtil.box(arm, Vector3(0.26, length - 0.2, 0.05), Vector3(0, length * 0.5 + 0.1, 0), black)
			blade.rotation.y = 0.5
			MeshUtil.box(arm, Vector3(0.27, 0.16, 0.055), Vector3(0, length - 0.08, 0), MeshUtil.material(Color(0.85, 0.7, 0.2), 0.6)).rotation.y = 0.5
		spin.append([hub, Vector3.BACK, 9.0])
		for i in 2:
			var side: float = 1.0 if i == 0 else -1.0
			# Wing cannon poking out of the leading edge.
			var gun := _between(roots[i], tips[i], 0.3)
			MeshUtil.rod(root, (gun[0] as Vector3) + Vector3(0, 0, 0.3), (gun[0] as Vector3) + Vector3(0, 0, -0.8), 0.045, black)
			# Main wheels on long legs under the wings (these aircraft sit on a tail wheel).
			var leg: Vector3 = under.call(i, 0.2)
			leg.z = float(wing[0][1]) + 0.9
			var main_leg := _wheel(root, leg, Vector3(leg.x, 0.42, leg.z - 0.15), 0.42, black, metal)
			MeshUtil.box(main_leg, Vector3(0.04, 0.55, 0.5), Vector3(side * 0.22, -0.32, -0.05), paint)  # its door
			_gear.append([main_leg, Vector3.BACK, -signf(leg.x) * 1.5])
			if not radial:
				_pod(root, leg + Vector3(0, -0.1, 0.9), 0.3, 2.8, paint)
		_gear.append([_wheel(root, Vector3(0, float(last[2]) + 0.05, float(last[0]) - 1.0), Vector3(0, 0.18, float(last[0]) - 0.8), 0.18, black, metal), Vector3.RIGHT, -1.6])  # the tail wheel folds back
		# The radio mast behind the cockpit, with a wire back to the fin.
		var mast_top := Vector3(0, base + tall + 0.6, cz + cl * 0.7)
		MeshUtil.rod(root, Vector3(0, base + tall - 0.05, cz + cl * 0.7), mast_top, 0.03, metal)
		MeshUtil.rod(root, mast_top, Vector3(0, float(fin[1][2]) - 0.1, float(fin[1][0]) + 0.1), 0.012, black)


# AH-64 Apache: a narrow, slab-sided fuselage with two cockpits in step, engines on its
# shoulders, stub wings carrying the weapons, a chin cannon and a four-bladed rotor.
static func _apache(root: Node3D, mats: Dictionary, spin: Array) -> void:
	var paint: Material = mats["paint"]
	var dark: Material = mats["dark"]
	var black: Material = mats["black"]
	var metal: Material = mats["metal"]
	var glass: Material = mats["glass"]
	_hull(root, [[-7.0, 0.22, 1.0, 1.45, 0.5], [-6.2, 0.45, 0.75, 1.75, 0.5], [-5.0, 0.58, 0.55, 2.0, 0.5], [-3.6, 0.62, 0.5, 2.3, 0.5],
		[-2.0, 0.7, 0.45, 2.6, 0.5], [0.5, 0.75, 0.5, 2.6, 0.5], [2.0, 0.5, 1.1, 2.3, 0.4], [4.5, 0.3, 1.45, 2.1, 0.2], [7.6, 0.18, 1.7, 2.0, 0.2]], paint)
	# The side sponsons that give the Apache its wide cheeks.
	for side in [1.0, -1.0]:
		_hull(root, [[-5.6, 0.12, 0.75, 1.3, 0.6], [-4.6, 0.3, 0.6, 1.5, 0.6], [-1.0, 0.3, 0.55, 1.5, 0.6], [0.6, 0.12, 0.7, 1.3, 0.6]], paint, Vector3(side * 0.7, 0, 0), 8)
	# Two cockpits in step: flat glass panels, the back seat higher than the front.
	_hull(root, [[-5.5, 0.3, 1.7, 1.85, 0.7], [-4.9, 0.44, 1.8, 2.5, 0.7], [-3.95, 0.47, 1.9, 2.72, 0.7], [-3.75, 0.48, 2.1, 3.02, 0.7],
		[-2.3, 0.5, 2.2, 3.14, 0.7], [-1.6, 0.42, 2.3, 2.85, 0.7]], glass, Vector3.ZERO, 8)
	for z in [-4.9, -3.85, -2.3]:
		var top := 2.52 if z < -4.0 else 3.16
		_hull(root, [[z - 0.04, 0.5, 1.85, top + 0.02, 0.7], [z + 0.04, 0.5, 1.85, top + 0.02, 0.7]], dark, Vector3.ZERO, 8).set_meta("canopy", true)
	MeshUtil.box(root, Vector3(0.07, 0.07, 3.4), Vector3(0, 3.12, -3.0), dark).rotation.x = -0.2
	# The engines, high on each side, with their intakes and upturned exhausts.
	for side in [1.0, -1.0]:
		var at := Vector3(side * 1.05, 0, 0)
		_hull(root, [[-1.1, 0.26, 2.05, 2.6, 0.3], [-0.6, 0.36, 1.95, 2.7, 0.3], [1.6, 0.36, 1.95, 2.7, 0.3], [2.3, 0.3, 2.05, 2.65, 0.3]], paint, at, 10)
		MeshUtil.cylinder(root, 0.2, 0.06, Vector3(side * 1.05, 2.32, -1.12), black).rotation.x = PI * 0.5
		MeshUtil.box(root, Vector3(0.5, 0.42, 0.5), Vector3(side * 1.08, 2.4, 2.45), black)
		MeshUtil.rod(root, Vector3(side * 0.6, 2.3, 0.3), Vector3(side * 0.9, 2.3, 0.3), 0.2, paint)
	# The rotor's gearbox housing, mast and blades.
	_hull(root, [[-1.6, 0.4, 2.5, 2.85, 0.4], [-0.9, 0.5, 2.5, 3.1, 0.4], [0.2, 0.5, 2.5, 3.1, 0.4], [1.2, 0.3, 2.4, 2.8, 0.4]], paint, Vector3.ZERO, 8)
	MeshUtil.cylinder(root, 0.16, 0.7, Vector3(0, 3.3, -0.5), metal)
	spin.append([_rotor(root, Vector3(0, 3.6, -0.5), 7.3, 4, 0.52, black, dark), Vector3.UP, 4.5])
	# Stub wings: two pylons each for the weapons.
	for side in [1.0, -1.0]:
		var w0: Array = [Vector3(side * 0.5, 1.5, -1.1), 1.4, 0.22]
		var w1: Array = [Vector3(side * 2.6, 1.42, -0.85), 0.95, 0.12]
		_foil(root, w0, w1, Vector3.UP, paint)
		_band(root, w0, w1, 0.86, 1.0, Vector3.UP, mats["mark"])
	# The chin cannon in its cradle, and the sensor turret on the nose.
	MeshUtil.box(root, Vector3(0.34, 0.3, 0.9), Vector3(0, 0.42, -3.9), dark)
	MeshUtil.rod(root, Vector3(0, 0.36, -4.2), Vector3(0, 0.3, -5.6), 0.06, black)
	MeshUtil.rod(root, Vector3(0, 0.36, -5.3), Vector3(0, 0.31, -5.65), 0.09, black)
	MeshUtil.cylinder(root, 0.34, 0.75, Vector3(0, 1.08, -7.1), dark).rotation.z = PI * 0.5
	MeshUtil.box(root, Vector3(0.3, 0.26, 0.08), Vector3(0.14, 1.08, -7.42), glass)
	MeshUtil.box(root, Vector3(0.4, 0.3, 0.5), Vector3(0, 1.6, -6.75), dark)
	# Fixed wheels on trailing legs, and a tail wheel.
	for side in [1.0, -1.0]:
		_wheel(root, Vector3(side * 0.7, 1.0, -3.0), Vector3(side * 1.2, 0.36, -2.4), 0.36, black, metal)
		MeshUtil.rod(root, Vector3(side * 0.7, 0.7, -1.6), Vector3(side * 1.15, 0.42, -2.35), 0.05, metal)
	_wheel(root, Vector3(0, 1.75, 6.6), Vector3(0, 0.22, 7.1), 0.22, black, metal)
	# The swept fin with its tail rotor (two pairs of blades in an X), and the tailplane low at the back.
	var f0: Array = [Vector3(0, 1.9, 5.9), 1.8, 0.2]
	var f1: Array = [Vector3(0, 4.3, 7.2), 1.0, 0.1]
	_foil(root, f0, f1, Vector3.RIGHT, paint)
	_band(root, f0, f1, 0.7, 0.9, Vector3.RIGHT, mats["mark"])
	for side in [1.0, -1.0]:
		_foil(root, [Vector3(0, 1.62, 7.0), 1.0, 0.1], [Vector3(side * 1.6, 1.62, 7.15), 0.75, 0.06], Vector3.UP, paint)
	spin.append([_tail_rotor(root, Vector3(0.32, 3.5, 7.75), 1.4, [0.0, 0.96, PI, PI + 0.96], black, dark), Vector3.RIGHT, 14.0])
	# The wire-cutter blade over the cockpit and a pair of aerials along the tail.
	MeshUtil.rod(root, Vector3(0, 3.1, -1.7), Vector3(0, 3.5, -2.1), 0.03, metal)
	MeshUtil.rod(root, Vector3(0, 2.05, 4.0), Vector3(0, 2.55, 4.3), 0.02, black)


# Mi-8: a fat round-nosed cabin with a glazed front, twin engines in a hump on the roof,
# a five-bladed rotor and a long tail boom.
static func _mi8(root: Node3D, mats: Dictionary, spin: Array) -> void:
	var paint: Material = mats["paint"]
	var dark: Material = mats["dark"]
	var black: Material = mats["black"]
	var metal: Material = mats["metal"]
	var glass: Material = mats["glass"]
	# The cabin and tail boom.
	_hull(root, [[-7.6, 1.22, 0.5, 2.95, 0.3], [-6.0, 1.3, 0.4, 3.15, 0.35], [2.0, 1.3, 0.4, 3.15, 0.35], [3.2, 1.15, 0.75, 3.1, 0.3],
		[4.6, 0.7, 1.55, 3.0, 0.2], [6.0, 0.42, 2.15, 2.95, 0.1], [10.0, 0.22, 2.5, 2.9, 0.0]], paint, Vector3.ZERO, 16)
	# The glazed nose, its lower half painted, with frames between the panes.
	_hull(root, [[-9.0, 0.45, 1.0, 1.9, 0.2], [-8.5, 0.95, 0.66, 2.5, 0.3], [-7.6, 1.21, 0.52, 2.93, 0.3]], glass, Vector3.ZERO, 16)
	_hull(root, [[-9.02, 0.47, 0.97, 1.42, 0.2], [-8.5, 0.98, 0.63, 1.52, 0.3], [-7.58, 1.24, 0.48, 1.6, 0.3]], paint, Vector3.ZERO, 16)
	_hull(root, [[-8.54, 0.97, 1.5, 2.53, 0.3], [-8.46, 0.99, 1.5, 2.56, 0.3]], dark, Vector3.ZERO, 16).set_meta("canopy", true)
	MeshUtil.rod(root, Vector3(0, 1.45, -9.0), Vector3(0, 2.95, -7.6), 0.05, dark)
	for side in [1.0, -1.0]:
		MeshUtil.rod(root, Vector3(side * 0.62, 1.45, -8.85), Vector3(side * 0.8, 2.75, -7.9), 0.04, dark)
	# The engine hump: two round intakes at the front, an exhaust pipe out of each side.
	_hull(root, [[-5.3, 0.6, 3.0, 3.55, 0.2], [-4.6, 0.82, 2.95, 3.95, 0.2], [-1.0, 0.86, 2.95, 4.0, 0.2], [1.2, 0.7, 2.95, 3.8, 0.2], [2.8, 0.3, 2.95, 3.3, 0.2]], paint, Vector3.ZERO, 12)
	for side in [1.0, -1.0]:
		MeshUtil.cylinder(root, 0.29, 0.5, Vector3(side * 0.4, 3.55, -5.0), dark).rotation.x = PI * 0.5
		MeshUtil.cylinder(root, 0.22, 0.05, Vector3(side * 0.4, 3.55, -5.27), black).rotation.x = PI * 0.5
		MeshUtil.cylinder(root, 0.2, 0.5, Vector3(side * 0.95, 3.5, -2.6), black).rotation.z = PI * 0.5
	# The rotor: gearbox fairing, mast, five long blades.
	MeshUtil.cylinder(root, 0.3, 0.5, Vector3(0, 4.15, -1.5), metal, 0.2)
	spin.append([_rotor(root, Vector3(0, 4.45, -1.5), 10.6, 5, 0.52, black, dark), Vector3.UP, 4.5])
	for side in [1.0, -1.0]:
		# Round cabin windows, the sliding door's outline on the left, and a fuel tank down each side.
		for k in 5:
			MeshUtil.cylinder(root, 0.27, 0.06, Vector3(side * 1.3, 2.25, -5.0 + k * 1.45), glass).rotation.z = PI * 0.5
			MeshUtil.cylinder(root, 0.32, 0.04, Vector3(side * 1.295, 2.25, -5.0 + k * 1.45), dark).rotation.z = PI * 0.5
		_hull(root, [[-3.6, 0.12, 0.95, 1.2], [-3.0, 0.34, 0.72, 1.42], [0.2, 0.34, 0.72, 1.42], [0.9, 0.12, 0.95, 1.2]], paint, Vector3(side * 1.5, 0, 0), 10)
		for z in [-2.6, -0.2]:
			_hull(root, [[z - 0.05, 0.36, 0.7, 1.44], [z + 0.05, 0.36, 0.7, 1.44]], dark, Vector3(side * 1.5, 0, 0), 10)
		# Weapon racks on outriggers: two pylons each side.
		MeshUtil.rod(root, Vector3(side * 1.2, 1.9, -4.6), Vector3(side * 3.0, 1.75, -4.6), 0.06, metal)
		MeshUtil.rod(root, Vector3(side * 1.2, 1.2, -4.6), Vector3(side * 2.2, 1.75, -4.6), 0.05, metal)
		# The main wheels, each on a tripod of struts out from the cabin.
		var hub := Vector3(side * 2.25, 0.45, 1.0)
		_wheel(root, Vector3(side * 1.25, 2.3, 0.8), hub + Vector3(-side * 0.25, 0.1, 0), 0.45, black, metal)
		MeshUtil.cylinder(root, 0.45, 0.28, hub, black).rotation.z = PI * 0.5
		MeshUtil.rod(root, Vector3(side * 1.2, 0.8, 0.0), hub + Vector3(-side * 0.2, 0, 0), 0.06, metal)
		MeshUtil.rod(root, Vector3(side * 1.2, 0.8, 2.0), hub + Vector3(-side * 0.2, 0, 0), 0.06, metal)
		# Twin nose wheels.
		MeshUtil.cylinder(root, 0.3, 0.18, Vector3(side * 0.16, 0.3, -6.9), black).rotation.z = PI * 0.5
		# The little tailplanes on the boom.
		_foil(root, [Vector3(0, 2.72, 8.3), 0.9, 0.1], [Vector3(side * 1.5, 2.72, 8.45), 0.65, 0.06], Vector3.UP, paint)
	MeshUtil.rod(root, Vector3(0, 0.7, -6.9), Vector3(0, 0.3, -6.9), 0.07, metal)
	# The team's colour in a band round the tail boom.
	_hull(root, [[6.6, 0.4, 2.2, 2.97, 0.05], [7.3, 0.36, 2.27, 2.96, 0.05]], mats["mark"], Vector3.ZERO, 16)
	# The tail pylon, its three-bladed rotor, and the skid that guards it.
	var f0: Array = [Vector3(0, 2.75, 8.4), 1.8, 0.24]
	var f1: Array = [Vector3(0, 5.0, 10.0), 1.0, 0.14]
	_foil(root, f0, f1, Vector3.RIGHT, paint)
	_band(root, f0, f1, 0.6, 0.82, Vector3.RIGHT, mats["mark"])
	spin.append([_tail_rotor(root, Vector3(0.36, 4.5, 10.45), 1.9, [0.0, TAU / 3.0, TAU * 2.0 / 3.0], black, dark), Vector3.RIGHT, 14.0])
	MeshUtil.rod(root, Vector3(0, 2.5, 8.6), Vector3(0, 1.7, 9.6), 0.04, metal)
	MeshUtil.rod(root, Vector3(0, 2.55, 9.8), Vector3(0, 1.7, 9.6), 0.03, metal)
	# Aerials along the boom and a light on the roof.
	MeshUtil.rod(root, Vector3(0, 2.95, 5.0), Vector3(0, 3.45, 5.2), 0.02, black)
	MeshUtil.box(root, Vector3(0.14, 0.12, 0.14), Vector3(0, 3.2, 3.6), MeshUtil.material(Color(0.7, 0.12, 0.1), 0.4))
