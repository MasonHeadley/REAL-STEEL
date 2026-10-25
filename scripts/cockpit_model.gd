class_name CockpitModel
extends RefCounted
# The inside of each aircraft's cockpit, as seen from the pilot's seat, modelled after the
# real one. The origin is the pilot's eye, looking forward along -Z, +X to his right, in
# metres. Each has its own canopy framing, instrument panel, gunsight and colours:
#
#   mig15      pale blue-grey; a great round canopy bow with a strut running back overhead,
#              an oval windscreen frame, a gunsight with a round leather pad
#   sabre      black and dark steel; a riveted bow, a tall narrow windscreen with a tilted
#              sight glass, a radar scope low in the middle of the panel
#   skyraider  a thick dark hoop, a flat-fronted windscreen, a wide hooded panel in two rows
#   il10       pale grey-green; straight angular frames, a light panel of big dials
#   apache     a narrow tandem seat: flat panes in slim frames, a breaker panel up on the
#              left, a green screen in the middle of the panel
#   mi8        a wide cabin: tall panes between posts, the panel on a hooded pedestal
#
# Frames are kept slimmer than the real ones so more of the outside can be seen.
#
# build() returns {"root", "stick", "lever", "lamps": [...], "lamp_on", "lamp_off",
# "text": [Label3D...] (screens that show figures), "needles": {"speed", "alt", "hdg"}}.
# player_ctrl.gd moves the stick, lever and needles and flashes the lamps.


static func _mat(c: Color, rough: float = 0.8) -> StandardMaterial3D:
	return MeshUtil.material(c, rough)


# An arch of straight pieces round part of an oval standing across the cockpit: a canopy
# bow or a windscreen frame. Angles are in degrees, 0 at the right, 90 at the top. Rivets,
# if a material is given for them, are dotted along it.
static func _arch(root: Node3D, centre: Vector3, rx: float, ry: float, from: float, to: float, pieces: int, thick: float, deep: float, mat: Material, rivet: Material = null) -> void:
	for k in pieces:
		var a := deg_to_rad(lerpf(from, to, float(k) / float(pieces)))
		var b := deg_to_rad(lerpf(from, to, float(k + 1) / float(pieces)))
		var pa := Vector3(cos(a) * rx, sin(a) * ry, 0)
		var pb := Vector3(cos(b) * rx, sin(b) * ry, 0)
		var piece := MeshUtil.box(root, Vector3(pa.distance_to(pb) + thick * 0.35, thick, deep), centre + (pa + pb) * 0.5, mat)
		piece.rotation.z = atan2(pb.y - pa.y, pb.x - pa.x)
		if rivet != null:
			MeshUtil.box(root, Vector3(0.016, 0.016, 0.01), centre + (pa + pb) * 0.5 + Vector3(0, 0, deep * 0.5 + 0.004), rivet)


# A straight bar of frame from one point to another.
static func _bar(root: Node3D, a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var m := MeshUtil.box(root, Vector3(thick, thick, a.distance_to(b)), (a + b) * 0.5, mat)
	m.transform = Transform3D(Basis.looking_at(b - a, Vector3(0.01, 1, 0.02)), (a + b) * 0.5)


# A round instrument on a panel (which faces +Z, towards the pilot): black face, pale rim,
# white marks round the edge and a white needle. Returns the needle's pivot, to be turned.
static func _dial(panel: Node3D, at: Vector2, r: float, mats: Dictionary, needle: float = 0.0) -> Node3D:
	var face := MeshUtil.cylinder(panel, r, 0.012, Vector3(at.x, at.y, 0.03), mats["face"])
	face.rotation.x = PI * 0.5
	var rim := MeshUtil.cylinder(panel, r * 1.12, 0.008, Vector3(at.x, at.y, 0.025), mats["rim"])
	rim.rotation.x = PI * 0.5
	for k in 8:
		var a := k * TAU / 8.0
		var mark := MeshUtil.box(panel, Vector3(r * 0.06, r * 0.2, 0.003), Vector3(at.x + cos(a) * r * 0.8, at.y + sin(a) * r * 0.8, 0.038), mats["white"])
		mark.rotation.z = a - PI * 0.5
	var pivot := Node3D.new()
	pivot.position = Vector3(at.x, at.y, 0.041)
	pivot.rotation.z = needle
	panel.add_child(pivot)
	MeshUtil.box(pivot, Vector3(r * 0.08, r * 0.78, 0.003), Vector3(0, r * 0.3, 0), mats["white"])
	MeshUtil.box(pivot, Vector3(r * 0.2, r * 0.2, 0.004), Vector3.ZERO, mats["rim"])
	return pivot


# The artificial horizon: blue above, brown below, a white line across.
static func _horizon(panel: Node3D, at: Vector2, r: float, mats: Dictionary) -> void:
	var rim := MeshUtil.cylinder(panel, r * 1.12, 0.008, Vector3(at.x, at.y, 0.025), mats["rim"])
	rim.rotation.x = PI * 0.5
	MeshUtil.box(panel, Vector3(r * 1.5, r * 0.75, 0.01), Vector3(at.x, at.y + r * 0.375, 0.032), _mat(Color(0.2, 0.5, 0.8), 0.5))
	MeshUtil.box(panel, Vector3(r * 1.5, r * 0.75, 0.01), Vector3(at.x, at.y - r * 0.375, 0.032), _mat(Color(0.42, 0.28, 0.16), 0.6))
	MeshUtil.box(panel, Vector3(r * 1.3, r * 0.06, 0.004), Vector3(at.x, at.y, 0.04), mats["white"])


static func build(id: String) -> Dictionary:
	var root := Node3D.new()
	var black := _mat(Color(0.045, 0.045, 0.05), 0.9)
	var mats := {"face": _mat(Color(0.03, 0.03, 0.035), 0.6), "rim": _mat(Color(0.45, 0.46, 0.48), 0.5), "white": _mat(Color(0.92, 0.92, 0.88), 0.6)}
	var lamp_off := _mat(Color(0.25, 0.04, 0.03), 0.6)
	var lamp_on := StandardMaterial3D.new()
	lamp_on.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_on.albedo_color = Color(1.0, 0.15, 0.1)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(0.75, 0.92, 1.0, 0.13)
	var amber := StandardMaterial3D.new()
	amber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amber.albedo_color = Color(1.0, 0.82, 0.35)
	var out := {"root": root, "lamps": [], "lamp_on": lamp_on, "lamp_off": lamp_off, "text": [], "needles": {}}
	# What each cockpit is painted, and where its panel sits.
	var look: Dictionary = {
		"mig15": {"wall": Color(0.56, 0.63, 0.66), "frame": Color(0.7, 0.75, 0.76), "panel": Color(0.1, 0.1, 0.11), "wide": 0.74},
		"sabre": {"wall": Color(0.13, 0.13, 0.14), "frame": Color(0.3, 0.31, 0.33), "panel": Color(0.07, 0.07, 0.08), "wide": 0.8},
		"skyraider": {"wall": Color(0.12, 0.13, 0.15), "frame": Color(0.2, 0.22, 0.27), "panel": Color(0.07, 0.07, 0.08), "wide": 0.92},
		"il10": {"wall": Color(0.5, 0.57, 0.5), "frame": Color(0.56, 0.63, 0.56), "panel": Color(0.6, 0.63, 0.6), "wide": 0.8},
		"apache": {"wall": Color(0.2, 0.21, 0.22), "frame": Color(0.25, 0.26, 0.28), "panel": Color(0.1, 0.1, 0.11), "wide": 0.66},
		"mi8": {"wall": Color(0.1, 0.1, 0.11), "frame": Color(0.08, 0.08, 0.09), "panel": Color(0.06, 0.06, 0.07), "wide": 0.62},
	}.get(id, {"wall": Color(0.2, 0.2, 0.22), "frame": Color(0.3, 0.3, 0.32), "panel": Color(0.08, 0.08, 0.09), "wide": 0.8})
	var wall := _mat(look["wall"])
	var frame := _mat(look["frame"], 0.6)
	var rivet := _mat((look["frame"] as Color).darkened(0.35), 0.5)
	var wide: float = look["wide"]
	var mid := -0.42 if id == "mi8" else 0.0  # the Mi-8's pilot sits to one side of its panel
	var lift := 0.0 if (id == "apache" or id == "mi8") else 0.1  # planes: the panel is raised to show over the nose

	# ---- the instrument panel, leaning away at the top, under its hood
	var panel := Node3D.new()
	panel.position = Vector3(mid * 0.5, -0.43 + lift, -0.8)
	panel.rotation.x = -0.2
	root.add_child(panel)
	MeshUtil.box(panel, Vector3(wide, 0.4, 0.04), Vector3.ZERO, _mat(look["panel"]))
	# The hood over it: a shallow arch, so the top of the panel is in shade.
	_arch(root, Vector3(mid * 0.5, -0.36 + lift, -0.72), wide * 0.56, 0.16, 12.0, 168.0, 9, 0.03, 0.26, black)
	var needles: Dictionary = out["needles"]
	match id:
		"apache":
			# A green screen in the middle with the figures on it, dials either side, two small screens below.
			MeshUtil.box(panel, Vector3(0.24, 0.22, 0.02), Vector3(0, 0.05, 0.02), black)
			var screen := StandardMaterial3D.new()
			screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			screen.albedo_color = Color(0.04, 0.2, 0.09)
			MeshUtil.box(panel, Vector3(0.2, 0.18, 0.01), Vector3(0, 0.05, 0.034), screen)
			for side in [-1.0, 1.0]:
				var words := Label3D.new()
				words.pixel_size = 0.00042
				words.font_size = 40
				words.modulate = Color(0.45, 1.0, 0.55)
				words.shaded = false
				words.position = Vector3(side * 0.05, 0.05, 0.042)
				panel.add_child(words)
				(out["text"] as Array).append(words)
			needles["speed"] = _dial(panel, Vector2(-0.22, 0.08), 0.055, mats)
			needles["alt"] = _dial(panel, Vector2(0.22, 0.08), 0.055, mats)
			_horizon(panel, Vector2(-0.2, -0.1), 0.05, mats)
			needles["hdg"] = _dial(panel, Vector2(0.2, -0.1), 0.05, mats)
			for k in 2:
				MeshUtil.box(panel, Vector3(0.09, 0.08, 0.012), Vector3(-0.05 + k * 0.1, -0.12, 0.026), screen)
			MeshUtil.box(panel, Vector3(0.12, 0.03, 0.012), Vector3(0, 0.18, 0.026), _mat(Color(0.85, 0.75, 0.15), 0.6))  # the caution strip
			# Vertical tape gauges on the left.
			for k in 2:
				MeshUtil.box(panel, Vector3(0.022, 0.14, 0.012), Vector3(-0.3 + k * 0.035, -0.04, 0.026), screen)
		"sabre":
			# The big compass and the horizon side by side, a radar scope below them, small dials round about.
			needles["hdg"] = _dial(panel, Vector2(-0.06, 0.07), 0.075, mats)
			_horizon(panel, Vector2(0.1, 0.07), 0.065, mats)
			var scope := StandardMaterial3D.new()
			scope.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			scope.albedo_color = Color(0.55, 0.6, 0.3)
			var tube := MeshUtil.cylinder(panel, 0.085, 0.03, Vector3(0.02, -0.11, 0.03), black)
			tube.rotation.x = PI * 0.5
			var face := MeshUtil.cylinder(panel, 0.062, 0.006, Vector3(0.02, -0.11, 0.048), scope)
			face.rotation.x = PI * 0.5
			needles["speed"] = _dial(panel, Vector2(-0.2, 0.08), 0.045, mats)
			needles["alt"] = _dial(panel, Vector2(-0.2, -0.03), 0.045, mats)
			for at in [Vector2(-0.3, 0.08), Vector2(-0.3, -0.03), Vector2(-0.25, -0.13), Vector2(0.22, 0.09), Vector2(0.3, -0.01), Vector2(0.2, -0.04), Vector2(0.3, -0.12), Vector2(0.2, -0.14), Vector2(-0.14, -0.12)]:
				_dial(panel, at, 0.04, mats, at.x * 9.0)
			for k in 3:
				MeshUtil.box(panel, Vector3(0.016, 0.016, 0.012), Vector3(0.16 + k * 0.001, 0.02 - k * 0.03, 0.026), _mat(Color(0.75, 0.15, 0.1), 0.5))  # warning lights down the middle
		"mig15":
			# Two clusters of dials either side of the stick, the horizon among the left-hand ones.
			needles["speed"] = _dial(panel, Vector2(-0.2, 0.1), 0.05, mats)
			_horizon(panel, Vector2(-0.08, 0.1), 0.05, mats)
			needles["alt"] = _dial(panel, Vector2(0.12, 0.1), 0.05, mats)
			needles["hdg"] = _dial(panel, Vector2(0.24, 0.1), 0.05, mats)
			for at in [Vector2(-0.2, -0.02), Vector2(-0.08, -0.02), Vector2(-0.2, -0.13), Vector2(-0.08, -0.13), Vector2(0.12, -0.02), Vector2(0.24, -0.02), Vector2(0.12, -0.13), Vector2(0.24, -0.13), Vector2(0.02, -0.06), Vector2(-0.31, 0.05)]:
				_dial(panel, at, 0.043, mats, at.y * 20.0 + at.x * 7.0)
			MeshUtil.box(panel, Vector3(0.05, 0.05, 0.02), Vector3(0.02, -0.15, 0.03), _mat(Color(0.85, 0.75, 0.15), 0.5))
		"skyraider":
			# Two long rows of dials right across.
			for k in 7:
				var top := _dial(panel, Vector2(-0.36 + k * 0.12, 0.08), 0.047, mats, k * 0.9)
				_dial(panel, Vector2(-0.36 + k * 0.12, -0.06), 0.045, mats, 2.0 - k * 0.7)
				if k == 2:
					needles["speed"] = top
				elif k == 4:
					needles["alt"] = top
				elif k == 5:
					needles["hdg"] = top
			_horizon(panel, Vector2(0.0, 0.08), 0.047, mats)
			for k in 6:
				MeshUtil.box(panel, Vector3(0.02, 0.035, 0.014), Vector3(-0.15 + k * 0.06, -0.16, 0.026), mats["rim"])  # a row of switches
		"il10":
			# A light panel with a few large black dials.
			needles["speed"] = _dial(panel, Vector2(-0.22, 0.07), 0.062, mats)
			needles["hdg"] = _dial(panel, Vector2(-0.07, 0.09), 0.055, mats)
			needles["alt"] = _dial(panel, Vector2(0.1, 0.08), 0.062, mats)
			for at in [Vector2(0.26, 0.09), Vector2(-0.22, -0.08), Vector2(-0.06, -0.06), Vector2(0.1, -0.08), Vector2(0.25, -0.06), Vector2(0.33, -0.13)]:
				_dial(panel, at, 0.055, mats, at.x * 8.0)
			MeshUtil.box(panel, Vector3(0.1, 0.06, 0.012), Vector3(-0.32, 0.0, 0.026), mats["white"])  # a placard
		_:
			# Mi-8: three rows of dials on the pedestal with the blue horizon among them.
			for row in 3:
				for col in 3:
					var d := _dial(panel, Vector2(-0.19 + col * 0.14, 0.11 - row * 0.12), 0.048, mats, row * 1.3 + col * 0.8)
					if row == 0 and col == 0:
						needles["speed"] = d
					elif row == 0 and col == 2:
						needles["alt"] = d
					elif row == 1 and col == 0:
						needles["hdg"] = d
			_horizon(panel, Vector2(0.22, 0.02), 0.07, mats)
			# The other pilot's panel, away to the left.
			var second := Node3D.new()
			second.position = Vector3(-1.05, -0.45, -0.75)
			second.rotation.x = -0.2
			root.add_child(second)
			MeshUtil.box(second, Vector3(0.5, 0.36, 0.04), Vector3.ZERO, _mat(look["panel"]))
			for k in 6:
				_dial(second, Vector2(-0.15 + (k % 3) * 0.15, 0.07 - (k / 3) * 0.14), 0.05, mats, k * 1.1)

	# ---- canopy and windscreen frames
	match id:
		"mig15":
			_arch(root, Vector3(0, -0.5, -0.74), 0.6, 0.96, 14.0, 166.0, 12, 0.06, 0.07, frame, rivet)
			_arch(root, Vector3(0, -0.32, -1.0), 0.3, 0.62, 18.0, 162.0, 9, 0.04, 0.05, frame)
			_bar(root, Vector3(0, 0.44, -0.74), Vector3(0, 0.62, 0.5), 0.07, _mat((look["frame"] as Color).darkened(0.45)))
		"sabre":
			_arch(root, Vector3(0, -0.52, -0.72), 0.6, 0.96, 14.0, 166.0, 12, 0.065, 0.08, frame, rivet)
			for side in [-1.0, 1.0]:
				_bar(root, Vector3(side * 0.24, -0.2, -0.98), Vector3(side * 0.13, 0.42, -0.74), 0.04, black)
			_bar(root, Vector3(-0.13, 0.42, -0.74), Vector3(0.13, 0.42, -0.74), 0.04, black)
		"skyraider":
			_arch(root, Vector3(0, -0.5, -0.7), 0.62, 0.92, 12.0, 168.0, 12, 0.09, 0.09, frame, rivet)
			for side in [-1.0, 1.0]:
				_bar(root, Vector3(side * 0.17, -0.2, -1.02), Vector3(side * 0.2, 0.36, -0.66), 0.03, frame)
			_bar(root, Vector3(-0.2, 0.36, -0.66), Vector3(0.2, 0.36, -0.66), 0.03, frame)
		"il10":
			# Straight bars: a flat front pane, a pane angled back each side, bars running back overhead.
			for side in [-1.0, 1.0]:
				_bar(root, Vector3(side * 0.2, -0.2, -0.98), Vector3(side * 0.2, 0.34, -0.72), 0.035, frame)
				_bar(root, Vector3(side * 0.52, -0.22, -0.5), Vector3(side * 0.36, 0.42, -0.42), 0.04, frame)
				_bar(root, Vector3(side * 0.2, 0.34, -0.72), Vector3(side * 0.36, 0.42, -0.42), 0.035, frame)
				_bar(root, Vector3(side * 0.36, 0.42, -0.42), Vector3(side * 0.36, 0.44, 0.5), 0.035, frame)
			_bar(root, Vector3(-0.2, 0.34, -0.72), Vector3(0.2, 0.34, -0.72), 0.035, frame)
			_bar(root, Vector3(-0.36, 0.42, -0.42), Vector3(0.36, 0.42, -0.42), 0.035, frame)
		"apache":
			# Flat panes: one ahead, one each side, the roof rails running back and outwards.
			for side in [-1.0, 1.0]:
				_bar(root, Vector3(side * 0.24, -0.22, -1.0), Vector3(side * 0.2, 0.36, -0.68), 0.03, frame)
				_bar(root, Vector3(side * 0.2, 0.36, -0.68), Vector3(side * 0.42, 0.46, 0.3), 0.035, frame)
				_bar(root, Vector3(side * 0.5, -0.24, -0.55), Vector3(side * 0.42, 0.44, -0.1), 0.03, frame)
			_bar(root, Vector3(-0.2, 0.36, -0.68), Vector3(0.2, 0.36, -0.68), 0.03, frame)
			# The circuit-breaker panel, up on the left, leaning in over the pilot's shoulder.
			var breakers := Node3D.new()
			breakers.position = Vector3(-0.36, 0.36, -0.22)
			breakers.rotation = Vector3(0.1, 0.0, -0.75)
			root.add_child(breakers)
			MeshUtil.box(breakers, Vector3(0.2, 0.02, 0.7), Vector3.ZERO, frame)
			for row in 3:
				for k in 9:
					MeshUtil.cylinder(breakers, 0.011, 0.02, Vector3(-0.06 + row * 0.06, -0.018, -0.3 + k * 0.075), black)
			# The sight turret out on the nose, seen over the coaming.
			var ball := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.11
			sphere.height = 0.2
			sphere.radial_segments = 8
			sphere.rings = 4
			ball.mesh = sphere
			ball.material_override = _mat(Color(0.5, 0.52, 0.5), 0.5)
			ball.position = Vector3(0, -0.3, -1.25)
			root.add_child(ball)
		_:
			# Mi-8: tall panes between upright posts, a sill below and a beam above.
			for x in [-1.38, -0.42, 0.4, 0.72]:
				_bar(root, Vector3(x, -0.24, -1.05 + absf(x + 0.42) * 0.28), Vector3(x * 0.96, 0.52, -0.8 + absf(x + 0.42) * 0.28), 0.035, frame)
			_bar(root, Vector3(-1.4, 0.52, -0.52), Vector3(-0.42, 0.52, -0.8), 0.035, frame)
			_bar(root, Vector3(-0.42, 0.52, -0.8), Vector3(0.72, 0.52, -0.5), 0.035, frame)
			_bar(root, Vector3(0.72, -0.24, -0.72), Vector3(0.78, 0.5, 0.4), 0.035, frame)

	# ---- the gunsight
	if id == "apache":
		pass  # (it aims with the helmet: nothing on the coaming)
	elif id == "mi8":
		# A sight glass hung from the roof beam, with its round setting dial.
		_bar(root, Vector3(-0.1, 0.5, -0.74), Vector3(-0.1, 0.2, -0.7), 0.025, black)
		MeshUtil.box(root, Vector3(0.09, 0.1, 0.004), Vector3(-0.1, 0.14, -0.7), glass)
		var knob := MeshUtil.cylinder(root, 0.06, 0.03, Vector3(-0.22, 0.4, -0.72), mats["rim"])
		knob.rotation.x = PI * 0.5
	else:
		var low := -0.2 + lift
		MeshUtil.box(root, Vector3(0.1, 0.09, 0.14), Vector3(0, low, -0.7), black)
		if id == "mig15" or id == "il10":
			# The Soviet sights have a round leather pad facing the pilot's forehead.
			var pad := MeshUtil.cylinder(root, 0.045, 0.03, Vector3(0, low + 0.03, -0.62), _mat(Color(0.36, 0.22, 0.14), 0.9))
			pad.rotation.x = PI * 0.5
		var plate := MeshUtil.box(root, Vector3(0.11, 0.13, 0.004), Vector3(0, low + 0.12, -0.72), glass)
		plate.rotation.x = -0.5 if id == "sabre" else -0.25
		for side in [-1.0, 1.0]:
			MeshUtil.box(root, Vector3(0.006, 0.13, 0.008), Vector3(side * 0.057, low + 0.12, -0.72), black).rotation.x = plate.rotation.x
		# The ring and dot it throws on the glass.
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.024
		torus.outer_radius = 0.026
		torus.rings = 20
		torus.ring_segments = 4
		ring.mesh = torus
		ring.material_override = amber
		ring.rotation.x = PI * 0.5
		ring.position = Vector3(0, low + 0.2, -0.74)
		root.add_child(ring)
		MeshUtil.box(root, Vector3(0.004, 0.004, 0.002), Vector3(0, low + 0.2, -0.74), amber)
		if id == "sabre":
			# The range box beside the sight, and the missile panel under it.
			MeshUtil.box(root, Vector3(0.13, 0.22, 0.08), Vector3(0.3, 0.06, -0.86), black)
			MeshUtil.box(root, Vector3(0.09, 0.06, 0.004), Vector3(0.3, 0.07, -0.815), mats["white"])
			MeshUtil.box(root, Vector3(0.2, 0.06, 0.05), Vector3(-0.14, low + 0.02, -0.68), black)
			MeshUtil.box(root, Vector3(0.02, 0.02, 0.01), Vector3(-0.08, low + 0.02, -0.65), lamp_off)

	# ---- missile warning lamps on the hood
	for side in [-1.0, 1.0]:
		(out["lamps"] as Array).append(MeshUtil.box(root, Vector3(0.04, 0.03, 0.02), Vector3(mid * 0.5 + side * wide * 0.4, -0.2 + lift, -0.6), lamp_off))

	# ---- the sides: the cockpit walls with their sills, consoles with switches, and the floor
	for side in [-1.0, 1.0]:
		if id == "mi8":
			if side > 0.0:
				MeshUtil.box(root, Vector3(0.05, 0.7, 1.6), Vector3(0.82, -0.6, -0.1), wall)
			continue
		MeshUtil.box(root, Vector3(0.05, 0.5, 1.7), Vector3(side * 0.56, -0.5, -0.2), wall)
		MeshUtil.box(root, Vector3(0.1, 0.04, 1.7), Vector3(side * 0.53, -0.25, -0.2), frame)  # the canopy sill
		MeshUtil.box(root, Vector3(0.16, 0.06, 0.9), Vector3(side * 0.44, -0.47, -0.15), _mat((look["panel"] as Color).lightened(0.08)))
		for k in 5:
			MeshUtil.box(root, Vector3(0.022, 0.03, 0.022), Vector3(side * 0.44, -0.43, -0.5 + k * 0.14), mats["rim"])
		if id == "mig15":
			# Padded rests on the sills and the big round canopy handles above them.
			MeshUtil.box(root, Vector3(0.14, 0.2, 0.3), Vector3(side * 0.47, -0.3, -0.42), _mat(Color(0.72, 0.76, 0.78), 0.9))
			_bar(root, Vector3(side * 0.52, -0.24, -0.66), Vector3(side * 0.5, -0.14, -0.7), 0.016, black)
			var grip := MeshUtil.cylinder(root, 0.024, 0.04, Vector3(side * 0.5, -0.12, -0.7), _mat(Color(0.3, 0.16, 0.1), 0.6))
			grip.rotation.z = PI * 0.5
		if id == "sabre" and side > 0.0:
			MeshUtil.box(root, Vector3(0.012, 0.09, 0.5), Vector3(0.525, -0.38, -0.25), _mat(Color(0.7, 0.12, 0.1), 0.6))  # the red emergency placard
			MeshUtil.box(root, Vector3(0.014, 0.02, 0.4), Vector3(0.522, -0.38, -0.25), mats["white"])
	MeshUtil.box(root, Vector3(1.8 if id == "mi8" else 1.1, 0.02, 1.7), Vector3(mid, -0.88, -0.2), black)
	MeshUtil.box(root, Vector3(0.32, 0.4, 0.08), Vector3(0, -0.02, 0.34), _mat(look["wall"].darkened(0.3)))  # the headrest behind
	# Rudder pedals.
	for side in [-1.0, 1.0]:
		MeshUtil.box(root, Vector3(0.12, 0.16, 0.03), Vector3(side * 0.16, -0.72, -0.85), mats["rim"]).rotation.x = -0.4

	# ---- the stick between the knees and the throttle (or collective) on the left
	var stick := Node3D.new()
	stick.position = Vector3(0, -0.84, -0.42)
	root.add_child(stick)
	MeshUtil.rod(stick, Vector3.ZERO, Vector3(0, 0.36, 0), 0.016, mats["rim"])
	MeshUtil.box(stick, Vector3(0.042, 0.13, 0.05), Vector3(0, 0.42, 0), black)
	MeshUtil.box(stick, Vector3(0.05, 0.03, 0.06), Vector3(0, 0.49, -0.01), black)
	MeshUtil.box(stick, Vector3(0.018, 0.018, 0.02), Vector3(0.0, 0.5, -0.04), lamp_off)  # the firing button
	var lever := Node3D.new()
	lever.position = Vector3(-0.44, -0.42, -0.3)
	root.add_child(lever)
	MeshUtil.rod(lever, Vector3.ZERO, Vector3(0, 0.15, 0), 0.012, mats["rim"])
	MeshUtil.box(lever, Vector3(0.05, 0.045, 0.045), Vector3(0, 0.17, 0), _mat(Color(0.62, 0.12, 0.1), 0.5) if id == "il10" else black)
	MeshUtil.box(root, Vector3(0.06, 0.03, 0.26), Vector3(-0.44, -0.42, -0.3), mats["rim"])  # the quadrant it slides in
	out["stick"] = stick
	out["lever"] = lever
	return out
