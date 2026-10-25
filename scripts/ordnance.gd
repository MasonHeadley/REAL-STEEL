class_name Ordnance
extends RefCounted
# What hangs under an aircraft's wings: rocket pods, bombs and heat-seeking missiles. This is
# both the list of what there is (INFO) and the models of them.
#
# Models are in metres with the nose towards -Z, and the origin at the top of the store in
# the middle of its length: the point that hangs from the pylon. Western aircraft (`east`
# false) carry olive 'Mighty Mouse' rocket pods, fat low-drag bombs and white missiles;
# Soviet ones (`east` true) carry bare-metal S-5 pods with the tubes sticking out of the
# nose, grey bombs with a ring round the tail, and grey missiles.

# weight slows the aircraft: each point takes SLOW_PER_WEIGHT off its top speed while the
# store is still aboard. rockets / bomb (kg) / missiles say what it is.
const SLOW_PER_WEIGHT := 0.012
const INFO := {
	"none": {"name": "Empty", "short": "-", "weight": 0.0},
	"pod8": {"name": "8-rocket pod", "short": "8 RKT", "rockets": 8, "weight": 1.0},
	"pod16": {"name": "16-rocket pod", "short": "16 RKT", "rockets": 16, "weight": 2.2},
	"bomb100": {"name": "100 kg bomb", "short": "100 kg", "bomb": 100, "weight": 0.8},
	"bomb500": {"name": "500 kg bomb", "short": "500 kg", "bomb": 500, "weight": 2.6},
	"bomb1000": {"name": "1000 kg bomb", "short": "1000 kg", "bomb": 1000, "weight": 5.0},
	"aam": {"name": "Heat-seeking missile", "short": "MISSILE", "missiles": 1, "weight": 0.8},
}


# How many rockets, bombs or missiles a full store of this kind holds.
static func full(kind: String) -> int:
	var info: Dictionary = INFO.get(kind, {})
	return int(info.get("rockets", 0)) + int(info.get("missiles", 0)) + (1 if info.has("bomb") else 0)


static func _mats(east: bool) -> Dictionary:
	return {
		"body": MeshUtil.material(Color(0.5, 0.52, 0.52) if east else Color(0.3, 0.33, 0.2), 0.6),
		"dark": MeshUtil.material(Color(0.12, 0.12, 0.13), 0.7),
		"metal": MeshUtil.material(Color(0.42, 0.43, 0.45), 0.45),
		"band": MeshUtil.material(Color(0.85, 0.2, 0.15) if east else Color(0.9, 0.75, 0.15), 0.6),
		"white": MeshUtil.material(Color(0.55, 0.57, 0.55) if east else Color(0.88, 0.88, 0.85), 0.5),
	}


# A round piece along the store's length from z0 (front) to z1 (back), r0 across at the front
# and r1 at the back, its centre line `down` below the origin and `across` to one side.
static func _part(parent: Node3D, z0: float, z1: float, r0: float, r1: float, mat: Material, down: float, across: float = 0.0, flats: int = 10) -> void:
	var m := MeshUtil.cylinder(parent, r0, z1 - z0, Vector3(across, -down, (z0 + z1) * 0.5), mat, r1)
	m.rotation.x = PI * 0.5
	(m.mesh as CylinderMesh).radial_segments = flats


# The model of a store, or null for an empty pylon.
static func build(kind: String, east: bool) -> Node3D:
	var root := Node3D.new()
	var m := _mats(east)
	match kind:
		"pod8": _pod(root, m, east, 8)
		"pod16": _pod(root, m, east, 16)
		"bomb100": _bomb(root, m, east, 0.16, 1.3)
		"bomb500": _bomb(root, m, east, 0.24, 2.1)
		"bomb1000": _bomb(root, m, east, 0.33, 2.9)
		"aam": _missile(root, m, true)
		_:
			root.free()
			return null
	return root


# A rocket pod. Western: a plain drum with a flat face full of rocket noses and a tapered
# tail. Soviet (the UB-8 and UB-16 for S-5 rockets): a pointed nose with the launch tubes
# poking out of it in rings, and a perforated tail cone.
static func _pod(root: Node3D, m: Dictionary, east: bool, tubes: int) -> void:
	var r := (0.2 if tubes > 8 else 0.16) if east else (0.24 if tubes > 8 else 0.18)
	var rings: Array = [[1, 0.0], [5, 0.42], [10, 0.8]] if tubes > 8 else [[1, 0.0], [7, 0.66]]
	if east:
		_part(root, -0.45, 0.75, r, r, m["metal"], r)
		_part(root, -0.9, -0.45, r * 0.55, r, m["metal"], r)
		_part(root, 0.75, 1.15, r, r * 0.5, m["dark"], r)
		for ring in rings:
			for k in int(ring[0]):
				var a := TAU * float(k) / float(ring[0])
				var out: float = r * float(ring[1])
				# The inner tubes stick out furthest; the outer ring only just clears the nose cone.
				var front := -1.22 + 0.4 * float(ring[1])
				_part(root, front, -0.5, 0.036, 0.036, m["metal"], r - sin(a) * out, cos(a) * out, 6)
				_part(root, front - 0.005, front + 0.02, 0.028, 0.028, m["dark"], r - sin(a) * out, cos(a) * out, 6)
	else:
		_part(root, -0.85, 0.7, r, r, m["body"], r)
		_part(root, 0.7, 1.2, r, r * 0.4, m["body"], r)
		_part(root, -0.87, -0.84, r * 0.93, r * 0.93, m["dark"], r)
		_part(root, -0.2, -0.12, r * 1.03, r * 1.03, m["dark"], r)
		_part(root, 0.3, 0.38, r * 1.03, r * 1.03, m["dark"], r)
		for ring in rings:
			for k in int(ring[0]):
				var a := TAU * float(k) / float(ring[0])
				var out: float = r * float(ring[1])
				_part(root, -0.93, -0.86, 0.012, 0.03, m["metal"], r - sin(a) * out, cos(a) * out, 6)


# A bomb `r` across and `length` long. Western: a fat streamlined body with a yellow band and
# four plain fins. Soviet: a blunt-nosed drum with a ring round its fins.
static func _bomb(root: Node3D, m: Dictionary, east: bool, r: float, length: float) -> void:
	var h := length * 0.5
	if east:
		_part(root, -h, -h + length * 0.1, r * 0.55, r, m["body"], r)
		_part(root, -h + length * 0.1, h - length * 0.38, r, r, m["body"], r)
		_part(root, h - length * 0.38, h - length * 0.08, r, r * 0.28, m["body"], r)
		_part(root, h - length * 0.16, h, r * 0.95, r * 0.95, m["dark"], r, 0.0, 12)
		_part(root, -h + length * 0.13, -h + length * 0.16, r * 1.02, r * 1.02, m["band"], r)
	else:
		_part(root, -h, -h + length * 0.08, r * 0.3, r * 0.62, m["body"], r)
		_part(root, -h + length * 0.08, -h + length * 0.3, r * 0.62, r, m["body"], r)
		_part(root, -h + length * 0.3, h - length * 0.42, r, r, m["body"], r)
		_part(root, h - length * 0.42, h - length * 0.06, r, r * 0.22, m["body"], r)
		_part(root, -h + length * 0.1, -h + length * 0.13, r * 0.7, r * 0.76, m["band"], r)
	# Four fins at the tail, set as a cross (an X on the Western bomb).
	for k in 4:
		var fin := Node3D.new()
		fin.position = Vector3(0, -r, h - length * 0.12)
		fin.rotation.z = k * PI * 0.5 + (0.0 if east else PI * 0.25)
		root.add_child(fin)
		MeshUtil.box(fin, Vector3(0.025, r * 0.95, length * 0.22), Vector3(0, r * 0.55, 0), m["dark"] if east else m["body"])
	# The lugs it hangs by.
	for z in [-0.18, 0.18]:
		MeshUtil.box(root, Vector3(0.05, 0.05, 0.07), Vector3(0, 0.0, z * length), m["metal"])


# A heat-seeking missile: a thin tube with a glass eye, small fins at the nose and big ones at
# the tail. With `rail`, the launch rail it slides off is on top of it.
static func _missile(root: Node3D, m: Dictionary, rail: bool) -> void:
	var r := 0.065
	var down := r + (0.07 if rail else 0.0)
	_part(root, -1.4, -1.28, 0.02, r, m["dark"], down)
	_part(root, -1.28, 1.35, r, r, m["white"], down)
	_part(root, 1.35, 1.4, r, r * 0.7, m["dark"], down)
	_part(root, -0.75, -0.7, r * 1.04, r * 1.04, m["band"], down)
	for k in 4:
		var fin := Node3D.new()
		fin.position = Vector3(0, -down, 0)
		fin.rotation.z = k * PI * 0.5 + PI * 0.25
		root.add_child(fin)
		MeshUtil.box(fin, Vector3(0.015, 0.16, 0.22), Vector3(0, r + 0.07, -0.95), m["metal"])
		MeshUtil.box(fin, Vector3(0.015, 0.26, 0.5), Vector3(0, r + 0.12, 1.1), m["white"])
	if rail:
		MeshUtil.box(root, Vector3(0.07, 0.07, 2.0), Vector3(0, -0.035, 0.1), m["dark"])


# The things in flight: a rocket out of a pod, a missile off its rail.
static func flying(kind: String, east: bool) -> Node3D:
	var root := Node3D.new()
	var m := _mats(east)
	if kind == "missile":
		_missile(root, m, false)
		for child in root.get_children():
			child.position.y += 0.065  # centred on its own line of flight
	else:
		# A folding-fin rocket: a thin body, a pointed head, fins sprung open at the back.
		_part(root, -0.75, -0.55, 0.008, 0.035, m["dark"], 0.0, 0.0, 6)
		_part(root, -0.55, 0.7, 0.035, 0.035, m["metal"], 0.0, 0.0, 6)
		for k in 4:
			var fin := Node3D.new()
			fin.rotation.z = k * PI * 0.5
			root.add_child(fin)
			MeshUtil.box(fin, Vector3(0.008, 0.12, 0.16), Vector3(0, 0.08, 0.68), m["metal"]).rotation.x = -0.5
	return root
