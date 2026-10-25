class_name WeaponModel
extends RefCounted
# Low-polygon models of the weapons the infantry carry, and of the arms that hold them in
# the first-person view. Everything is in metres. A weapon's barrel points along +Z and runs
# through the origin, which sits just above the trigger hand: the grip is under (0, 0, 0),
# the butt is behind it and the muzzle out in front. +X is the firer's left.
#
#   rifle        M4 carbine          carbine   the same with a short barrel (the medic's)
#   machine_gun  belt-fed light MG   pistol    Glock
#   launcher     RPG-7
#
# The rifle and carbine take a sight: "iron" (a rear aperture and the front post), "holo"
# (a window with a red ring in it) or "acog" (a 4x telescope). SIGHT_LINE is how far above
# the barrel each sight's line of sight is: the first-person view lifts the weapon until that
# line is in front of the eye when aiming.
#
# Shapes that are not plain boxes or bars are drawn as a side view, a list of (z, y)
# corners, and given a width: see _slab().

const KINDS := ["rifle", "carbine", "machine_gun", "pistol", "launcher"]
const SIGHTS := ["iron", "holo", "acog"]
const SIGHT_NAMES := {"iron": "Iron sights", "holo": "Holographic sight", "acog": "4x ACOG scope"}
const SIGHT_LINE := {"iron": 0.071, "holo": 0.088, "acog": 0.09, "pistol": 0.021, "machine_gun": 0.07, "launcher": 0.17}
const MUZZLE := {"rifle": 0.52, "carbine": 0.43, "machine_gun": 0.78, "pistol": 0.16, "launcher": 0.9}


static func build(kind: String, sight: String = "iron") -> Node3D:
	var root := Node3D.new()
	var metal := MeshUtil.material(Color(0.13, 0.135, 0.15), 0.5)
	metal.metallic = 0.5
	var mats := {
		"metal": metal,
		"steel": MeshUtil.material(Color(0.3, 0.31, 0.33), 0.4),
		"wood": MeshUtil.material(Color(0.34, 0.2, 0.1), 0.7),
		"black": MeshUtil.material(Color(0.055, 0.055, 0.06), 0.8),
		"olive": MeshUtil.material(Color(0.24, 0.28, 0.17), 0.8),
		"brass": MeshUtil.material(Color(0.72, 0.56, 0.2), 0.4),
		"tan": MeshUtil.material(Color(0.5, 0.43, 0.3), 0.8),
	}
	match kind:
		"carbine": _m4(root, mats, sight, true)
		"machine_gun": _machine_gun(root, mats)
		"pistol": _pistol(root, mats)
		"launcher": _launcher(root, mats)
		_: _m4(root, mats, sight, false)
	return root


# A flat-sided piece from its side view: corners as [z, y], `width` across, centred on x.
static func _slab(parent: Node3D, corners: Array, width: float, mat: Material, x: float = 0.0) -> void:
	var outline := PackedVector2Array()
	for c in corners:
		outline.append(Vector2(c[0], c[1]))
	var m := MeshInstance3D.new()
	m.mesh = MeshUtil.extrude_x(outline, width)
	m.material_override = mat
	m.position.x = x
	parent.add_child(m)


# A round bar along the barrel's line from z0 to z1, r0 thick at the back and r1 at the front.
static func _bar(parent: Node3D, z0: float, z1: float, r0: float, r1: float, mat: Material, off: Vector2 = Vector2.ZERO, flats: int = 8) -> void:
	var m := MeshUtil.cylinder(parent, r0, z1 - z0, Vector3(off.x, off.y, (z0 + z1) * 0.5), mat, r1)
	m.rotation.x = PI * 0.5
	(m.mesh as CylinderMesh).radial_segments = flats


# A length of accessory rail: a strip with a row of teeth along it.
static func _rail(parent: Node3D, z0: float, z1: float, y: float, mat: Material) -> void:
	MeshUtil.box(parent, Vector3(0.02, 0.008, z1 - z0), Vector3(0, y, (z0 + z1) * 0.5), mat)
	var z := z0 + 0.008
	while z < z1 - 0.004:
		MeshUtil.box(parent, Vector3(0.024, 0.006, 0.007), Vector3(0, y + 0.006, z), mat)
		z += 0.016


# The M4 carbine: flat-topped receiver with a rail, round ribbed handguard, the triangular
# front sight tower, a curved thirty-round magazine and a sliding stock on its buffer tube.
static func _m4(root: Node3D, m: Dictionary, sight: String, short: bool) -> void:
	var guard_end := 0.3 if short else 0.36
	var muzzle: float = MUZZLE["carbine" if short else "rifle"]
	# Upper and lower receiver.
	MeshUtil.box(root, Vector3(0.04, 0.052, 0.21), Vector3(0, 0.012, 0.025), m["metal"])
	_slab(root, [[-0.08, -0.012], [0.13, -0.012], [0.13, -0.05], [0.115, -0.066], [0.045, -0.066], [0.03, -0.05], [-0.08, -0.042]], 0.037, m["metal"])
	_rail(root, -0.08, 0.13, 0.042, m["metal"])
	MeshUtil.box(root, Vector3(0.004, 0.02, 0.058), Vector3(-0.021, 0.012, 0.05), m["black"])   # ejection port
	MeshUtil.box(root, Vector3(0.012, 0.012, 0.03), Vector3(-0.024, -0.004, 0.085), m["metal"])  # its door, hinged down
	_bar(root, -0.03, -0.01, 0.008, 0.008, m["metal"], Vector2(-0.026, 0.026), 6)                # forward assist
	MeshUtil.box(root, Vector3(0.036, 0.012, 0.03), Vector3(0, 0.03, -0.088), m["metal"])        # charging handle
	MeshUtil.box(root, Vector3(0.006, 0.014, 0.02), Vector3(0.021, -0.022, 0.06), m["steel"])    # bolt catch
	MeshUtil.box(root, Vector3(0.006, 0.012, 0.012), Vector3(0.021, -0.03, -0.01), m["steel"])   # safety lever
	# Grip, trigger and guard, magazine.
	_slab(root, [[-0.042, -0.042], [0.0, -0.042], [-0.028, -0.15], [-0.075, -0.142], [-0.06, -0.09]], 0.03, m["black"])
	MeshUtil.box(root, Vector3(0.006, 0.026, 0.008), Vector3(0, -0.058, 0.022), m["steel"])
	MeshUtil.box(root, Vector3(0.01, 0.005, 0.06), Vector3(0, -0.082, 0.02), m["metal"])
	_slab(root, [[0.05, -0.06], [0.108, -0.06], [0.118, -0.13], [0.062, -0.135]], 0.024, m["steel"])
	_slab(root, [[0.062, -0.135], [0.118, -0.13], [0.142, -0.2], [0.09, -0.212]], 0.024, m["steel"])
	MeshUtil.box(root, Vector3(0.028, 0.008, 0.058), Vector3(0, -0.208, 0.117), m["black"]).rotation.x = -0.25
	# Buffer tube and the sliding stock on it.
	_bar(root, -0.31, -0.08, 0.014, 0.014, m["metal"], Vector2(0, 0.004))
	_slab(root, [[-0.33, 0.026], [-0.2, 0.026], [-0.19, -0.014], [-0.215, -0.03], [-0.25, -0.1], [-0.33, -0.11]], 0.038, m["black"])
	MeshUtil.box(root, Vector3(0.04, 0.14, 0.012), Vector3(0, -0.042, -0.335), m["black"])       # butt pad
	MeshUtil.box(root, Vector3(0.01, 0.02, 0.04), Vector3(0, -0.035, -0.2), m["steel"])          # the stock's latch
	# Handguard: round, ribbed, with a strip of rail on top.
	_bar(root, 0.13, 0.142, 0.034, 0.034, m["metal"])                                            # delta ring
	_bar(root, 0.142, guard_end, 0.03, 0.027, m["black"])
	var rib := 0.16
	while rib < guard_end - 0.01:
		_bar(root, rib, rib + 0.006, 0.0315, 0.0315, m["metal"])
		rib += 0.028
	_rail(root, 0.145, guard_end - 0.01, 0.03, m["metal"])
	# Barrel, front sight tower, flash hider.
	_bar(root, guard_end, muzzle - 0.04, 0.009, 0.009, m["metal"])
	var tower := guard_end + 0.035
	_slab(root, [[tower - 0.022, -0.012], [tower + 0.022, -0.012], [tower + 0.008, 0.066], [tower - 0.004, 0.066]], 0.014, m["metal"])
	MeshUtil.box(root, Vector3(0.004, 0.012, 0.004), Vector3(0, 0.068, tower + 0.002), m["steel"])  # the front post
	for ear in [-0.008, 0.008]:
		MeshUtil.box(root, Vector3(0.003, 0.016, 0.012), Vector3(ear, 0.07, tower + 0.002), m["metal"])
	MeshUtil.box(root, Vector3(0.012, 0.024, 0.008), Vector3(0, -0.022, tower), m["metal"])     # sling swivel and bayonet lug
	_bar(root, muzzle - 0.045, muzzle, 0.0125, 0.0125, m["metal"])
	for slot in 3:
		MeshUtil.box(root, Vector3(0.027, 0.003, 0.022), Vector3(0, 0, muzzle - 0.02), m["black"]).rotation.z = slot * PI / 3.0
	_sight(root, m, sight)


# What sits on the receiver's rail: a folding rear aperture, a holographic sight, or a 4x scope.
static func _sight(root: Node3D, m: Dictionary, sight: String) -> void:
	match sight:
		"holo":
			var y: float = SIGHT_LINE["holo"]
			MeshUtil.box(root, Vector3(0.04, 0.02, 0.085), Vector3(0, 0.058, 0.0), m["black"])
			MeshUtil.box(root, Vector3(0.012, 0.014, 0.03), Vector3(0.024, 0.058, 0.0), m["metal"])  # the battery cap and buttons
			# The hood round the window: two sides, a top, and a glass you look through.
			for side in [-1.0, 1.0]:
				MeshUtil.box(root, Vector3(0.004, 0.044, 0.05), Vector3(side * 0.021, y, 0.012), m["black"])
			MeshUtil.box(root, Vector3(0.046, 0.004, 0.05), Vector3(0, y + 0.022, 0.012), m["black"])
			var glass := StandardMaterial3D.new()
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glass.albedo_color = Color(0.5, 0.8, 1.0, 0.1)
			MeshUtil.box(root, Vector3(0.038, 0.04, 0.002), Vector3(0, y, 0.03), glass)
			# The reticle: a ring and a dot, glowing red.
			var red := StandardMaterial3D.new()
			red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			red.albedo_color = Color(1.0, 0.12, 0.08)
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.0058
			torus.outer_radius = 0.0068
			torus.rings = 16
			torus.ring_segments = 4
			ring.mesh = torus
			ring.material_override = red
			ring.rotation.x = PI * 0.5
			ring.position = Vector3(0, y, 0.029)
			root.add_child(ring)
			MeshUtil.box(root, Vector3(0.0012, 0.0012, 0.001), Vector3(0, y, 0.029), red)
		"acog":
			var y: float = SIGHT_LINE["acog"]
			MeshUtil.box(root, Vector3(0.03, 0.022, 0.1), Vector3(0, 0.058, -0.01), m["black"])   # the mount
			for knob in [-0.035, 0.035]:
				_bar(root, knob - 0.008, knob + 0.008, 0.008, 0.008, m["steel"], Vector2(0.02, 0.058), 6)
			_bar(root, -0.085, -0.055, 0.021, 0.021, m["black"], Vector2(0, y))                   # eyepiece
			_bar(root, -0.055, 0.02, 0.017, 0.019, m["black"], Vector2(0, y))                     # body
			_bar(root, 0.02, 0.06, 0.019, 0.026, m["black"], Vector2(0, y))                       # the bell at the front
			_bar(root, 0.06, 0.075, 0.026, 0.026, m["black"], Vector2(0, y))
			var lens := MeshUtil.material(Color(0.25, 0.1, 0.3), 0.1)
			_bar(root, 0.074, 0.076, 0.023, 0.023, lens, Vector2(0, y))
			_bar(root, -0.086, -0.084, 0.018, 0.018, lens, Vector2(0, y))
			MeshUtil.box(root, Vector3(0.008, 0.006, 0.06), Vector3(0, y + 0.021, -0.01), MeshUtil.material(Color(0.9, 0.2, 0.12), 0.4))  # the fibre that lights the reticle
			MeshUtil.box(root, Vector3(0.012, 0.014, 0.014), Vector3(0, y + 0.02, 0.03), m["black"])
		_:
			# A folding rear sight: a base, two ears and the aperture between them.
			MeshUtil.box(root, Vector3(0.026, 0.012, 0.03), Vector3(0, 0.054, -0.06), m["metal"])
			for ear in [-0.011, 0.011]:
				MeshUtil.box(root, Vector3(0.004, 0.026, 0.014), Vector3(ear, 0.07, -0.06), m["metal"])
			MeshUtil.box(root, Vector3(0.018, 0.005, 0.004), Vector3(0, 0.0805, -0.06), m["metal"])
			MeshUtil.box(root, Vector3(0.018, 0.005, 0.004), Vector3(0, 0.0615, -0.06), m["metal"])
			MeshUtil.box(root, Vector3(0.005, 0.005, 0.008), Vector3(-0.016, 0.06, -0.06), m["steel"])  # windage knob


# A belt-fed light machine gun: heavy barrel, carrying handle, bipod, and a box of belt on its left.
static func _machine_gun(root: Node3D, m: Dictionary) -> void:
	MeshUtil.box(root, Vector3(0.05, 0.075, 0.35), Vector3(0, -0.01, 0.045), m["metal"])       # receiver
	MeshUtil.box(root, Vector3(0.056, 0.024, 0.2), Vector3(0, 0.038, 0.07), m["metal"])        # feed cover
	_rail(root, -0.02, 0.16, 0.052, m["metal"])
	for ear in [-0.011, 0.011]:
		MeshUtil.box(root, Vector3(0.004, 0.022, 0.014), Vector3(ear, 0.068, -0.07), m["metal"])  # rear sight
	_slab(root, [[-0.13, 0.025], [-0.34, 0.025], [-0.34, -0.1], [-0.3, -0.105], [-0.2, -0.05], [-0.13, -0.045]], 0.046, m["black"])  # butt
	MeshUtil.box(root, Vector3(0.03, 0.02, 0.1), Vector3(0, 0.04, -0.29), m["metal"])          # shoulder rest
	_slab(root, [[-0.04, -0.045], [0.0, -0.045], [-0.022, -0.14], [-0.066, -0.135]], 0.032, m["black"])  # grip
	MeshUtil.box(root, Vector3(0.008, 0.006, 0.075), Vector3(0, -0.082, 0.04), m["metal"])     # trigger guard
	_slab(root, [[0.22, 0.02], [0.44, 0.02], [0.44, -0.05], [0.22, -0.06]], 0.058, m["black"])  # fore-end
	_bar(root, 0.2, 0.71, 0.016, 0.015, m["metal"])                                            # barrel
	_bar(root, 0.42, 0.62, 0.012, 0.012, m["metal"], Vector2(0, -0.034))                       # gas cylinder
	_bar(root, 0.7, 0.78, 0.021, 0.019, m["metal"])                                            # flash hider
	MeshUtil.box(root, Vector3(0.007, 0.05, 0.014), Vector3(0, 0.045, 0.66), m["metal"])       # front sight
	# The carrying handle over the barrel.
	MeshUtil.rod(root, Vector3(0, 0.02, 0.25), Vector3(0, 0.085, 0.27), 0.006, m["metal"])
	MeshUtil.rod(root, Vector3(0, 0.02, 0.4), Vector3(0, 0.085, 0.38), 0.006, m["metal"])
	MeshUtil.rod(root, Vector3(0, 0.085, 0.26), Vector3(0, 0.085, 0.39), 0.011, m["black"])
	# The bipod, legs down and splayed.
	for side in [1.0, -1.0]:
		MeshUtil.rod(root, Vector3(0, -0.035, 0.62), Vector3(side * 0.14, -0.3, 0.67), 0.007, m["metal"])
		MeshUtil.box(root, Vector3(0.035, 0.01, 0.03), Vector3(side * 0.142, -0.303, 0.67), m["metal"])
	# The belt box hung on the left, and the belt running up out of it into the feed tray.
	MeshUtil.box(root, Vector3(0.075, 0.11, 0.14), Vector3(0.068, -0.075, 0.08), m["olive"])
	MeshUtil.box(root, Vector3(0.079, 0.012, 0.144), Vector3(0.068, -0.018, 0.08), m["metal"])
	for k in 5:
		MeshUtil.box(root, Vector3(0.011, 0.012, 0.055), Vector3(0.03 + k * 0.013, 0.03 - k * k * 0.0025, 0.08), m["brass"])


# A Glock: a square slide on a plastic frame, the grip raked back, a squared trigger guard.
static func _pistol(root: Node3D, m: Dictionary) -> void:
	MeshUtil.box(root, Vector3(0.026, 0.026, 0.186), Vector3(0, 0.002, 0.062), m["metal"])     # slide
	MeshUtil.box(root, Vector3(0.027, 0.004, 0.186), Vector3(0, 0.015, 0.062), m["black"])     # its flat top
	for k in 5:
		for side in [-1.0, 1.0]:
			MeshUtil.box(root, Vector3(0.002, 0.02, 0.004), Vector3(side * 0.0135, 0.002, -0.022 + k * 0.008), m["black"])  # serrations
	MeshUtil.box(root, Vector3(0.003, 0.012, 0.03), Vector3(-0.013, 0.006, 0.05), m["steel"])  # the barrel showing in the port
	MeshUtil.box(root, Vector3(0.024, 0.02, 0.118), Vector3(0, -0.02, 0.092), m["black"])      # dust cover
	MeshUtil.box(root, Vector3(0.02, 0.006, 0.03), Vector3(0, -0.032, 0.128), m["black"])      # its little rail
	_slab(root, [[-0.036, -0.012], [0.034, -0.012], [0.034, -0.03], [0.012, -0.03], [-0.012, -0.125], [-0.062, -0.115], [-0.045, -0.06]], 0.029, m["black"])  # frame and grip
	MeshUtil.box(root, Vector3(0.031, 0.008, 0.046), Vector3(0, -0.123, -0.036), m["black"]).rotation.x = 0.2  # magazine floor plate
	# The trigger guard: squared off at the front.
	MeshUtil.box(root, Vector3(0.012, 0.005, 0.05), Vector3(0, -0.062, 0.05), m["black"])
	MeshUtil.box(root, Vector3(0.012, 0.034, 0.005), Vector3(0, -0.046, 0.074), m["black"])
	MeshUtil.box(root, Vector3(0.006, 0.022, 0.005), Vector3(0, -0.044, 0.048), m["black"]).rotation.x = 0.3  # trigger
	_bar(root, 0.153, 0.157, 0.007, 0.007, m["black"], Vector2(0, 0.002), 6)                   # muzzle
	# Sights: a blade at the front, a notch at the back.
	MeshUtil.box(root, Vector3(0.004, 0.007, 0.008), Vector3(0, 0.019, 0.146), m["black"])
	for ear in [-0.0075, 0.0075]:
		MeshUtil.box(root, Vector3(0.005, 0.007, 0.008), Vector3(ear, 0.019, -0.022), m["black"])


# The RPG-7. A shoulder-fired rocket launcher: a tube that rests on the right shoulder with
# the rocket's fat warhead sticking out of the front and a flared venturi at the back.
static func _launcher(root: Node3D, m: Dictionary) -> void:
	var up := Vector2(-0.05, 0.11)  # the tube lies over the shoulder: above and to the right of a rifle's barrel
	_bar(root, -0.48, 0.42, 0.036, 0.036, m["olive"], up)                                      # tube
	_bar(root, -0.66, -0.48, 0.066, 0.036, m["olive"], up)                                     # the flared back end
	_bar(root, -0.67, -0.655, 0.05, 0.05, m["black"], up)
	_bar(root, -0.3, -0.02, 0.043, 0.043, m["wood"], up)                                       # the wooden heat guard
	_bar(root, 0.4, 0.425, 0.042, 0.042, m["metal"], up)                                       # muzzle ring
	# The rocket: neck, warhead, pointed nose. It is a part of its own (named Rocket) so it
	# can be hidden once fired and shown again when the next one is loaded.
	var rocket := Node3D.new()
	rocket.name = "Rocket"
	root.add_child(rocket)
	_bar(rocket, 0.42, 0.5, 0.028, 0.03, m["olive"], up)
	_bar(rocket, 0.5, 0.6, 0.03, 0.058, m["olive"], up)
	_bar(rocket, 0.6, 0.7, 0.058, 0.058, m["olive"], up)
	_bar(rocket, 0.7, 0.86, 0.058, 0.012, m["olive"], up)
	_bar(rocket, 0.86, 0.9, 0.012, 0.008, m["metal"], up)
	# Trigger housing and grips hanging under the tube, and the sight standing on its left.
	MeshUtil.box(root, Vector3(0.03, 0.05, 0.12), Vector3(up.x, up.y - 0.055, 0.0), m["metal"])
	_slab(root, [[-0.04, 0.03], [0.0, 0.03], [-0.022, -0.125], [-0.066, -0.12]], 0.03, m["wood"], up.x)
	_slab(root, [[-0.24, 0.07], [-0.2, 0.07], [-0.215, -0.05], [-0.255, -0.045]], 0.03, m["wood"], up.x)
	MeshUtil.box(root, Vector3(0.008, 0.006, 0.07), Vector3(up.x, 0.0, 0.035), m["metal"])
	MeshUtil.box(root, Vector3(0.035, 0.07, 0.13), Vector3(up.x + 0.055, up.y + 0.055, 0.02), m["black"])
	MeshUtil.box(root, Vector3(0.006, 0.05, 0.01), Vector3(up.x, up.y + 0.06, 0.36), m["metal"])
	MeshUtil.box(root, Vector3(0.012, 0.06, 0.01), Vector3(up.x, up.y + 0.065, -0.1), m["metal"])


# ---- arms for the first-person view ----

# A limb or a hand as a tube of oval rings: each ring is [z, half width, half height, x, y].
static func _limb(parent: Node3D, rings: Array, mat: Material, sides: int = 8) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var loops: Array = []
	for r in rings:
		var loop: Array = []
		for k in sides:
			var a := TAU * float(k) / float(sides)
			loop.append(Vector3(float(r[3]) + cos(a) * float(r[1]), float(r[4]) + sin(a) * float(r[2]), r[0]))
		loops.append(loop)
	for i in loops.size() - 1:
		var a: Array = loops[i]
		var b: Array = loops[i + 1]
		var centre := Vector3.ZERO
		for p in a + b:
			centre += p
		centre /= float(sides * 2)
		for k in sides:
			var n := (k + 1) % sides
			MeshUtil._tri(st, centre, a[k], a[n], b[n])
			MeshUtil._tri(st, centre, a[k], b[n], b[k])
	for end in [0, loops.size() - 1]:
		var loop: Array = loops[end]
		var mid := Vector3.ZERO
		for p in loop:
			mid += p
		mid /= float(sides)
		var inner: Vector3 = mid + Vector3(0, 0, 0.05 if end == 0 else -0.05)
		for k in range(1, sides - 1):
			MeshUtil._tri(st, inner, loop[0], loop[k], loop[k + 1])
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = mat
	parent.add_child(m)


# One arm, from the elbow to the fingertips, the hand closed round something. Its origin is
# the wrist; the forearm runs back along +Z and the hand reaches forward along -Z, palm
# down, with the fingers curled under and the thumb round the near side. `left` mirrors it.
# The sleeve has a cuff, the glove has a padded back, knuckles and separate fingers.
static func arm(left: bool, sleeve: Material, glove: Material) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.scale.x = -1.0 if left else 1.0
	root.add_child(body)
	# Forearm: thin at the wrist, thickening towards the elbow, with a turned-back cuff.
	_limb(body, [[0.0, 0.03, 0.026, 0, 0], [0.1, 0.04, 0.036, 0, -0.004], [0.24, 0.05, 0.046, 0, -0.008], [0.36, 0.052, 0.05, 0, -0.01]], sleeve)
	_limb(body, [[-0.012, 0.035, 0.031, 0, 0], [0.03, 0.036, 0.032, 0, 0]], sleeve)
	MeshUtil.box(body, Vector3(0.02, 0.004, 0.03), Vector3(0.0, 0.031, 0.01), glove)  # the cuff's strap
	# The back of the hand and the palm.
	_limb(body, [[-0.012, 0.03, 0.022, 0, 0], [-0.05, 0.043, 0.02, 0, 0.002], [-0.092, 0.042, 0.017, 0, 0.0]], glove)
	MeshUtil.box(body, Vector3(0.05, 0.008, 0.045), Vector3(0, 0.02, -0.055), sleeve)   # the padded panel on the back of the glove
	# Four fingers, each of three joints curling down and back under the palm.
	for f in 4:
		var x := -0.031 + f * 0.0205
		var long := 1.0 - absf(float(f) - 1.4) * 0.12
		MeshUtil.box(body, Vector3(0.017, 0.012, 0.012), Vector3(x, 0.014, -0.094), glove)  # knuckle
		var one := MeshUtil.box(body, Vector3(0.017, 0.017, 0.036 * long), Vector3(x, -0.004, -0.108), glove)
		one.rotation.x = 0.9
		var two := MeshUtil.box(body, Vector3(0.016, 0.016, 0.03 * long), Vector3(x, -0.03, -0.108), glove)
		two.rotation.x = 1.9
		var three := MeshUtil.box(body, Vector3(0.015, 0.015, 0.024 * long), Vector3(x, -0.043, -0.088), glove)
		three.rotation.x = 2.9
	# The thumb, round the inner side.
	var base := MeshUtil.box(body, Vector3(0.02, 0.02, 0.04), Vector3(-0.046, -0.006, -0.05), glove)
	base.rotation = Vector3(0.3, 0.5, 0)
	var tip := MeshUtil.box(body, Vector3(0.017, 0.017, 0.034), Vector3(-0.05, -0.022, -0.082), glove)
	tip.rotation = Vector3(0.7, 0.2, 0)
	return root
