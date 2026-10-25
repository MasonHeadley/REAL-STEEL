class_name TankModel
extends RefCounted
# Builds a vehicle's look from its row in the vehicles sheet. The hull proportions, turret
# shape and position, gun, skirts and the "extra" fitting give each of the eight its own outline.
#
# The running gear is real: a toothed drive sprocket at the back, an idler at the front,
# road wheels and return rollers, and a belt of separate track links that the vehicle moves
# round them as it drives (see Tank._animate_tracks).

const LINK_SPACING := 0.3
const TABLE_STEP := 0.03
const NO_ROLLERS := ["thumper", "mender"]  # vehicles whose track lies back along the tops of big wheels
const WHEEL_TRAVEL := 0.22  # how far a road wheel can move up or down on its suspension, metres


# wear runs from 0 (factory fresh) to 1 (a long campaign): dust in the paint, mud up the
# running gear and hull sides, chipped edges, and more of the crew's kit lashed on.
# seed_value fixes which kit a particular vehicle carries.
# The shape of each vehicle's upper hull and turret, as cross-sections from front to back
# (see MeshUtil.loft). Each is [z, half width at the bottom, half width at the top, bottom,
# top, shoulder], all as fractions: z of the length (-0.5 is the front), widths of the half
# width, heights of the height (for a hull, from the top of the tracks to the hull roof).
# They are modelled on the real vehicles the game's eight are loosely based on.
const HULLS := {
	# US T29/T30 heavy: a tall hull with a rounded cast nose.
	"bastion": [[-0.5, 0.7, 0.6, 0.0, 0.3, 0.0], [-0.44, 0.96, 0.84, 0.0, 0.62, 0.3], [-0.3, 0.98, 0.9, 0.0, 1.0, 0.25], [0.42, 0.98, 0.92, 0.0, 1.0, 0.2], [0.5, 0.98, 0.9, 0.0, 0.8, 0.2]],
	# IS-3: the pointed "pike" nose and sides that lean in.
	"warden": [[-0.5, 0.3, 0.16, 0.0, 0.4, 0.0], [-0.37, 0.98, 0.72, 0.0, 0.86, 0.3], [-0.22, 0.98, 0.8, 0.0, 1.0, 0.3], [0.4, 0.98, 0.85, 0.0, 1.0, 0.25], [0.5, 0.95, 0.8, 0.0, 0.7, 0.2]],
	# Leopard 1: a long, shallow glacis and flat deck.
	"lancer": [[-0.5, 0.95, 0.9, 0.0, 0.22, 0.0], [-0.2, 0.98, 0.92, 0.0, 1.0, 0.15], [0.45, 0.98, 0.92, 0.0, 1.0, 0.15], [0.5, 0.98, 0.9, 0.0, 0.85, 0.1]],
	# Kanonenjagdpanzer / Type 60: low, the glacis running straight up into the fighting compartment.
	"hornet": [[-0.5, 0.95, 0.88, 0.0, 0.3, 0.0], [-0.24, 0.98, 0.9, 0.0, 1.0, 0.2], [0.45, 0.98, 0.9, 0.0, 1.0, 0.2], [0.5, 0.98, 0.9, 0.0, 0.7, 0.1]],
	# M109: a plain aluminium box with a short sloped front.
	"thumper": [[-0.5, 0.96, 0.94, 0.0, 0.42, 0.0], [-0.33, 0.98, 0.96, 0.0, 1.0, 0.08], [0.5, 0.98, 0.96, 0.0, 1.0, 0.05]],
	# M41 Walker Bulldog: a stepped front and slab sides.
	"bulldog": [[-0.5, 0.95, 0.9, 0.0, 0.32, 0.0], [-0.3, 0.98, 0.92, 0.0, 0.88, 0.12], [-0.12, 0.98, 0.92, 0.0, 1.0, 0.12], [0.46, 0.98, 0.92, 0.0, 1.0, 0.12], [0.5, 0.98, 0.92, 0.0, 0.8, 0.1]],
	# PT-76: a long flat boat of a hull with a raked bow.
	"mender": [[-0.5, 0.82, 0.72, 0.0, 0.16, 0.0], [-0.28, 0.98, 0.9, 0.0, 1.0, 0.1], [0.48, 0.98, 0.9, 0.0, 1.0, 0.1], [0.5, 0.98, 0.9, 0.0, 0.6, 0.1]],
	# AMX-13: small, with a long sloping nose over the front engine.
	"wasp": [[-0.5, 0.95, 0.88, 0.0, 0.3, 0.0], [-0.12, 0.98, 0.9, 0.0, 1.0, 0.15], [0.47, 0.98, 0.9, 0.0, 1.0, 0.15], [0.5, 0.98, 0.9, 0.0, 0.75, 0.1]],
}
const TURRETS := {
	# T29/T30: a big cast turret, wide in the middle, with a long overhanging bustle.
	"bastion": [[-0.5, 0.5, 0.4, 0.15, 0.75, 0.3], [-0.3, 0.9, 0.7, 0.0, 0.95, 0.35], [0.05, 1.0, 0.8, 0.0, 1.0, 0.35], [0.3, 0.95, 0.8, 0.0, 1.0, 0.3], [0.5, 0.8, 0.7, 0.32, 0.9, 0.2]],
	# IS-3: the low upturned-bowl turret.
	"warden": [[-0.5, 0.4, 0.2, 0.0, 0.5, 0.5], [-0.3, 0.85, 0.45, 0.0, 0.8, 0.55], [0.0, 1.0, 0.55, 0.0, 1.0, 0.6], [0.3, 0.9, 0.5, 0.0, 0.85, 0.55], [0.5, 0.5, 0.25, 0.0, 0.5, 0.5]],
	# Leopard 1: a rounded cast turret, narrow at the mantlet, with a stowage bustle.
	"lancer": [[-0.5, 0.45, 0.35, 0.1, 0.7, 0.3], [-0.25, 0.85, 0.6, 0.0, 0.92, 0.4], [0.1, 1.0, 0.7, 0.0, 1.0, 0.4], [0.4, 0.9, 0.65, 0.1, 0.9, 0.3], [0.5, 0.7, 0.5, 0.25, 0.8, 0.2]],
	# Kanonenjagdpanzer: a fixed fighting compartment, its front plate well sloped.
	"hornet": [[-0.5, 0.9, 0.6, 0.0, 0.3, 0.2], [-0.15, 1.0, 0.75, 0.0, 1.0, 0.3], [0.3, 1.0, 0.8, 0.0, 1.0, 0.25], [0.5, 0.95, 0.8, 0.0, 0.6, 0.2]],
	# M109: the huge slab-sided turret with a sloped face.
	"thumper": [[-0.5, 0.85, 0.75, 0.0, 0.7, 0.15], [-0.35, 1.0, 0.9, 0.0, 1.0, 0.12], [0.45, 1.0, 0.92, 0.0, 1.0, 0.1], [0.5, 1.0, 0.92, 0.0, 0.95, 0.1]],
	# M41: a welded turret, pointed at the front, with a long bustle hanging over the deck.
	"bulldog": [[-0.5, 0.45, 0.4, 0.1, 0.75, 0.15], [-0.2, 0.95, 0.8, 0.0, 1.0, 0.2], [0.15, 1.0, 0.85, 0.0, 1.0, 0.2], [0.3, 0.9, 0.8, 0.35, 1.0, 0.15], [0.5, 0.8, 0.7, 0.4, 0.95, 0.15]],
	# PT-76: a small truncated cone.
	"mender": [[-0.5, 0.5, 0.3, 0.0, 0.6, 0.4], [-0.2, 0.9, 0.55, 0.0, 0.95, 0.5], [0.15, 1.0, 0.6, 0.0, 1.0, 0.5], [0.5, 0.6, 0.35, 0.0, 0.6, 0.4]],
	# AMX-13: the boxy oscillating turret with its long rear bustle for the autoloader.
	"wasp": [[-0.5, 0.5, 0.45, 0.2, 0.8, 0.15], [-0.2, 0.9, 0.8, 0.0, 1.0, 0.2], [0.2, 0.95, 0.85, 0.0, 1.0, 0.2], [0.5, 0.85, 0.75, 0.3, 0.9, 0.15]],
}


# Turns a shape's fractions into metres: z by `length`, widths by `half_width`, heights from
# `y0` by `height`.
static func _sized(shape: Array, length: float, half_width: float, y0: float, height: float) -> Array:
	return shape.map(func(s): return [s[0] * length, s[1] * half_width, s[2] * half_width, y0 + s[3] * height, y0 + s[4] * height, s[5]])


# Where the top of a shape is at some point along it: its height (index 4) or the half width
# of its top (index 2), as fractions.
static func _along(shape: Array, zf: float, what: int) -> float:
	for i in shape.size() - 1:
		if zf <= shape[i + 1][0]:
			return lerpf(shape[i][what], shape[i + 1][what], clampf(inverse_lerp(shape[i][0], shape[i + 1][0], zf), 0.0, 1.0))
	return shape[shape.size() - 1][what]


static var _marked := false   # the vehicle being built has a marking on its turret sides
static var _paint: Texture2D  # the custom camouflage of the vehicle being built, or null


static func build(def: Dictionary, team_color: Color, wear: float = 0.3, seed_value: int = 1, look: Dictionary = {}) -> Dictionary:
	_paint = Kit.camo_texture(look.get("camo", {}))
	_marked = String(look.get("decal", {}).get("text", "")) != ""
	var l: float = def["length"]
	var w: float = def["width"]
	var h: float = def["height"]
	var mud := Color(0.34, 0.27, 0.17)
	var base := Color(String(def["colour"])).lerp(team_color, 0.18).lerp(Color(0.56, 0.52, 0.42), wear * 0.3)
	var mats: Array = []
	var root := Node3D.new()

	var th := h * 0.34  # track height
	var tw := w * 0.17  # track width
	var ht := h * 0.58  # hull roof
	var hl := l * 0.5

	var hull_mat := _mat(base, mats)
	var lower_mat := _mat(base.darkened(0.3).lerp(mud, wear * 0.6), mats)
	var track_mat := _mat(Color(0.2, 0.19, 0.18).lerp(mud, wear * 0.55), mats, "")
	var wheel_mat := _mat(base.darkened(0.45).lerp(mud, wear * 0.6), mats, "")
	var hub_mat := _mat(base.lightened(0.15), mats, "")
	var metal_mat := _mat(Color(0.2, 0.2, 0.2), mats, "")

	_mesh(root, MeshUtil.extrude_x(PackedVector2Array([
		Vector2(hl * 0.95, 0.4), Vector2(hl, th), Vector2(-hl, th), Vector2(-hl * 0.82, 0.4)]), w - tw * 2.0), lower_mat)
	var hull_shape: Array = HULLS.get(def.get("hull_as", def["id"]), HULLS["lancer"])  # (hull_as / turret_as borrow another vehicle's shape)
	_mesh(root, MeshUtil.loft(_sized(hull_shape, l, w * 0.5, th, ht - th)), hull_mat)

	# Running gear. Wheels are collected with their radius so the vehicle can spin them.
	var gear: Array = []  # [pivot, radius, side index]
	var wheels := int(def["wheels"])
	# Some vehicles (the M109, the PT-76) run on big wheels with the track lying back along
	# their tops; the rest have smaller wheels and little rollers that carry the track back.
	var rollers: bool = not (String(def["id"]) in NO_ROLLERS)
	var wheel_r := th * (0.36 if rollers else 0.42)
	var end_r := th * 0.3
	var front := Vector2(-hl * 0.86, th * 0.62)  # idler centre (z, y)
	var rear := Vector2(hl * 0.86, th * 0.62)    # sprocket centre
	var road: Array = [[], []]         # the sprung road wheels on each side, front to back
	var wheel_spots: Array = [[], []]  # where each of them touches the ground, in hull space
	var wheel_z: Array = []
	var rubber_mat := _mat(Color(0.085, 0.085, 0.09).lerp(mud, wear * 0.45), mats, "")
	var gear_mats := {"rubber": rubber_mat, "steel": wheel_mat, "hub": hub_mat, "dark": metal_mat}
	var fixed := {}  # the parts of the suspension that do not turn, gathered into one mesh
	for si in 2:
		var side := -1.0 if si == 0 else 1.0
		var tx: float = side * (w * 0.5 - tw * 0.5)
		var inner: float = tx - side * tw * 0.42  # the hull's side of the wheels
		# One mesh of each kind of wheel a side, shared by every wheel of that kind.
		var road_mesh := _road_wheel_mesh(wheel_r, tw * 0.8, side, gear_mats)
		var idler_mesh := _end_wheel_mesh(end_r, tw * 0.7, side, false, gear_mats)
		var sprocket_mesh := _end_wheel_mesh(end_r, tw * 0.62, side, true, gear_mats)
		var roller_mesh := _roller_mesh(0.11, tw * 0.6, gear_mats)
		for i in wheels:
			var z := lerpf(-hl * 0.62, hl * 0.62, float(i) / float(maxi(wheels - 1, 1)))
			var road_wheel := _spinner(root, Vector3(tx, wheel_r + 0.1, z), road_mesh)
			gear.append([road_wheel, wheel_r, si])
			road[si].append(road_wheel)
			wheel_spots[si].append(Vector3(tx, 0.0, z))
			if si == 0:
				wheel_z.append(z)
			# The swing arm the wheel hangs on, trailing back from its pivot on the hull.
			var pivot_at := Vector3(inner, wheel_r + 0.34, z - wheel_r * 1.25)
			_strut(fixed, "steel", pivot_at, Vector3(inner, wheel_r + 0.1, z), 0.1)
			_drum(fixed, "steel", 0.1, 0.12, pivot_at)
			if i == 0 or i == wheels - 1:
				# A shock absorber on the first and last wheel.
				_strut(fixed, "dark", Vector3(inner, th * 0.92, z + wheel_r * 0.9), Vector3(inner, wheel_r + 0.16, z + 0.05), 0.07)
		gear.append([_spinner(root, Vector3(tx, front.y, front.x), idler_mesh), end_r, si])
		gear.append([_spinner(root, Vector3(tx, rear.y, rear.x), sprocket_mesh), end_r, si])
		# The final drive behind the sprocket and the arm that holds the idler out front.
		_drum(fixed, "steel", end_r * 0.7, tw * 0.5, Vector3(tx - side * tw * 0.55, rear.y, rear.x))
		_strut(fixed, "steel", Vector3(inner, front.y - 0.05, front.x + end_r * 1.6), Vector3(inner, front.y, front.x), 0.12)
		if rollers:
			for i in 3:
				var rz := lerpf(-hl * 0.45, hl * 0.45, float(i) / 2.0)
				gear.append([_spinner(root, Vector3(tx, th - 0.16, rz), roller_mesh), 0.11, si])
				_strut(fixed, "steel", Vector3(inner - side * 0.1, th - 0.1, rz), Vector3(tx, th - 0.16, rz), 0.07)
		MeshUtil.box(root, Vector3(tw + 0.1, 0.06, l * 0.96), Vector3(tx, th + 0.1, 0), hull_mat)
		if def["skirts"]:
			MeshUtil.box(root, Vector3(0.07, th * 0.45, l * 0.86), Vector3(side * (w * 0.5 + 0.02), th * 0.85, 0), hull_mat)
		var ex := MeshUtil.cylinder(root, 0.1, 0.5, Vector3(side * w * 0.2, ht * 0.8, hl + 0.2), metal_mat)
		ex.rotation.x = PI * 0.5
	var fixed_parts := MeshInstance3D.new()
	fixed_parts.mesh = _commit(fixed, gear_mats)
	root.add_child(fixed_parts)
	MeshUtil.box(root, Vector3(w * 0.55, 0.06, l * 0.22), Vector3(0, ht + 0.03, hl * 0.66), metal_mat)

	# The track: where a link sits at every few centimetres round the loop, for both sides.
	var loop := _track_loop(hl, th, front, rear, end_r + 0.07)
	var tables: Array = [[], []]
	var track_len: float = loop["length"]
	var steps := int(track_len / TABLE_STEP)
	for si in 2:
		var tx: float = (-1.0 if si == 0 else 1.0) * (w * 0.5 - tw * 0.5)
		for k in steps:
			tables[si].append(_on_loop(loop, float(k) * TABLE_STEP, tx))
	var per_side := int(track_len / LINK_SPACING)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _link_mesh(tw, LINK_SPACING)
	mm.instance_count = per_side * 2
	var belt := MultiMeshInstance3D.new()
	belt.multimesh = mm
	belt.material_override = track_mat
	root.add_child(belt)
	# For every place along the ground run, which pair of road wheels it lies between, so the
	# track there can rise and fall with them. -1 means that part of the loop is off the ground.
	var between := PackedInt32Array()
	var share := PackedFloat32Array()
	for t in tables[0]:
		var o: Vector3 = t.origin
		var idx := -1
		var f := 0.0
		if o.y < 0.09 and wheel_z.size() >= 2:
			idx = 0
			while idx < wheel_z.size() - 2 and float(wheel_z[idx + 1]) < o.z:
				idx += 1
			f = clampf((o.z - float(wheel_z[idx])) / maxf(float(wheel_z[idx + 1]) - float(wheel_z[idx]), 0.01), 0.0, 1.0)
		between.append(idx)
		share.append(f)
	var running := {"gear": gear, "belt": mm, "tables": tables, "per_side": per_side, "length": track_len,
		"road": road, "wheel_spots": wheel_spots, "wheel_y": wheel_r + 0.1, "between": between, "share": share}
	pose_tracks(running, 0.0, 0.0)

	# Turret (or the fixed casemate of a tank destroyer).
	var shape: String = def["turret_shape"]
	var tl: float = l * float(def["turret_len"])
	var twd: float = w * float(def["turret_wid"])
	var tth := h - ht
	var tur: Array = TURRETS.get(def.get("turret_as", def["id"]), TURRETS["lancer"])
	var top_y := tth * _along(tur, 0.1, 4)  # the roof where the hatches are
	var turret := Node3D.new()
	turret.position = Vector3(0, ht, l * float(def["turret_pos"]))
	root.add_child(turret)
	var shell_parent: Node3D = turret
	if shape == "casemate":
		# The superstructure is part of the hull; only the gun swings.
		shell_parent = Node3D.new()
		shell_parent.position = turret.position
		root.add_child(shell_parent)
	_mesh(shell_parent, MeshUtil.loft(_sized(tur, tl, twd * 0.5, 0.0, tth)), hull_mat)
	MeshUtil.cylinder(shell_parent, 0.32, 0.3, Vector3(twd * 0.18, top_y + 0.1, tl * 0.12), hull_mat)
	MeshUtil.box(shell_parent, Vector3(0.5, 0.05, 0.5), Vector3(-twd * 0.2, top_y + 0.02, tl * 0.1), lower_mat)
	# Bright team panel on the roof, so friend and foe read at a glance. It lies on the roof
	# behind the hatches, as wide as the roof is there.
	var panel := StandardMaterial3D.new()
	panel.albedo_color = team_color
	panel.emission_enabled = true
	panel.emission = team_color
	panel.emission_energy_multiplier = 0.5
	MeshUtil.box(shell_parent, Vector3(twd * _along(tur, 0.27, 2) * 0.8, 0.05, tl * 0.16), Vector3(0, tth * minf(_along(tur, 0.19, 4), _along(tur, 0.35, 4)) + 0.03, tl * 0.27), panel)
	# Gun: one barrel, or a pair for autocannons.
	var gun := Node3D.new()
	gun.position = Vector3(0, tth * 0.45, -tl * 0.5 + 0.1)
	turret.add_child(gun)
	MeshUtil.box(gun, Vector3(twd * 0.5, tth * 0.55, 0.45), Vector3(0, 0, -0.1), lower_mat)
	var gl: float = def["gun_length"]
	var r: float = maxf(float(def["gun_calibre"]) * 0.0009, 0.045)
	var barrels := int(def["barrels"])
	# The barrel sits on its own node so it can slide back in recoil.
	var slide := Node3D.new()
	gun.add_child(slide)
	for b in barrels:
		# (barrel_gap sets a pair of guns wide apart, outside the turret, as on an anti-aircraft tank.)
		var bx := 0.0 if barrels == 1 else (float(b) - 0.5) * float(def.get("barrel_gap", 0.44))
		if def.has("barrel_gap"):
			MeshUtil.box(gun, Vector3(0.34, 0.5, 1.5), Vector3(bx, 0, 0.35), lower_mat)  # the gun's cradle on the turret side
		var barrel := MeshUtil.cylinder(slide, r * 1.25, gl, Vector3(bx, 0, -gl * 0.5), metal_mat, r)
		barrel.rotation.x = -PI * 0.5
		if def["muzzle_brake"]:
			# A double-baffle brake: two collars with a gap that vents sideways.
			for k in 2:
				var brake := MeshUtil.cylinder(slide, r * 2.0, 0.2, Vector3(bx, 0, -gl + 0.12 + k * 0.3), metal_mat)
				brake.rotation.x = PI * 0.5
			MeshUtil.box(slide, Vector3(r * 4.6, r * 1.5, 0.1), Vector3(bx, 0, -gl + 0.27), metal_mat)
		elif barrels == 1:
			var evac := MeshUtil.cylinder(slide, r * 1.7, 0.6, Vector3(bx, 0, -gl * 0.62), metal_mat)
			evac.rotation.x = PI * 0.5
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0, -gl)
	gun.add_child(muzzle)

	_radar_node = null
	_extra(String(def["extra"]), root, shell_parent, l, w, ht, th, tl, twd, top_y, hull_mat, lower_mat, metal_mat)
	var radar := _radar_node
	_details(def, root, shell_parent, l, w, ht, th, tl, twd, tth, top_y, mats, hull_mat, lower_mat)
	_weathering(root, l, w, ht, th, wear, seed_value)
	_crew_kit(def, root, shell_parent, l, w, ht, th, tl, twd, tth, wear, seed_value, mats, team_color)
	_fit(look, root, shell_parent, l, w, ht, th, tl, twd, tth, tur, mats)
	_paint = null
	return {"root": root, "turret": turret, "gun": gun, "slide": slide, "muzzle": muzzle, "mats": mats, "running": running,
		"hull_top": ht, "turret_h": tth, "turret_len": tl, "turret_width": twd, "radar": radar}


# ---- Running gear parts -------------------------------------------------------------
# A wheel is many small shapes (tyres, discs, hub, bolts). Rather than a separate object
# for each, they are piled up by material and baked into one mesh, which every wheel of
# that kind on that side of the vehicle then shares. That keeps a match of twenty tanks cheap.

# Adds a shape, moved to where it belongs, to the pile of pieces that share a material.
static func _add(pile: Dictionary, key: String, mesh: Mesh, at: Transform3D) -> void:
	if not pile.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		pile[key] = st
	(pile[key] as SurfaceTool).append_from(mesh, 0, at)


# Bakes a pile into one mesh, one surface for each material.
static func _commit(pile: Dictionary, materials: Dictionary) -> ArrayMesh:
	var out := ArrayMesh.new()
	for key in pile:
		(pile[key] as SurfaceTool).commit(out)
		if materials.get(key) != null:
			out.surface_set_material(out.get_surface_count() - 1, materials[key])
	return out


# A disc on the axle (which runs along X): `radius` at the hull side, `outer` at the far side
# if it tapers, `width` thick, its middle `x` along the axle.
static func _disc(pile: Dictionary, key: String, radius: float, width: float, x: float, side: float = 1.0, outer: float = -1.0, flats: int = 16) -> void:
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if outer < 0.0 else outer
	cm.height = width
	cm.radial_segments = flats
	cm.rings = 1
	_add(pile, key, cm, Transform3D(Basis(Vector3.BACK, -side * PI * 0.5), Vector3(x, 0, 0)))


# A short drum lying across the vehicle at a point: pivots and housings.
static func _drum(pile: Dictionary, key: String, radius: float, width: float, at: Vector3) -> void:
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius
	cm.height = width
	cm.radial_segments = 10
	cm.rings = 1
	_add(pile, key, cm, Transform3D(Basis(Vector3.BACK, PI * 0.5), at))


static func _block(pile: Dictionary, key: String, size: Vector3, at: Vector3, turn: float = 0.0) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_add(pile, key, bm, Transform3D(Basis(Vector3.RIGHT, turn), at))


# A square bar from one point to another.
static func _strut(pile: Dictionary, key: String, a: Vector3, b: Vector3, thick: float) -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, a.distance_to(b))
	_add(pile, key, bm, Transform3D(Basis.looking_at(b - a, Vector3.RIGHT), (a + b) * 0.5))


# A mesh on its own pivot so it can be spun.
static func _spinner(root: Node3D, pos: Vector3, mesh: Mesh) -> Node3D:
	var pivot := MeshInstance3D.new()
	pivot.mesh = mesh
	pivot.position = pos
	root.add_child(pivot)
	return pivot


# A road wheel: a pair of steel discs with rubber tyres and a gap between them for the
# track's guide teeth, a dished outer face, a hub cap and a ring of bolts.
static func _road_wheel_mesh(radius: float, width: float, side: float, materials: Dictionary) -> ArrayMesh:
	var pile := {}
	for half in [-1.0, 1.0]:
		_disc(pile, "rubber", radius, width * 0.36, half * width * 0.27)
		_disc(pile, "steel", radius * 0.8, width * 0.4, half * width * 0.27)
	_disc(pile, "steel", radius * 0.3, width * 0.6, 0.0, 1.0, -1.0, 8)
	var face: float = side * (width * 0.47 + 0.02)
	_disc(pile, "steel", radius * 0.78, 0.05, face, side, radius * 0.5)   # the dished face
	_disc(pile, "hub", radius * 0.3, 0.09, face + side * 0.03, side, radius * 0.2, 8)  # hub cap
	for i in 6:
		var a := float(i) / 6.0 * TAU
		_block(pile, "hub", Vector3(0.05, radius * 0.13, radius * 0.13), Vector3(face + side * 0.015, cos(a) * radius * 0.52, sin(a) * radius * 0.52), a)
	return _commit(pile, materials)


# The idler at the front, or (toothed) the drive sprocket at the back: two rims on a drum,
# with lightening holes in the outer face so its turning can be seen.
static func _end_wheel_mesh(radius: float, width: float, side: float, toothed: bool, materials: Dictionary) -> ArrayMesh:
	var pile := {}
	_disc(pile, "steel", radius * 0.45, width * 0.9, 0.0, 1.0, -1.0, 10)
	for half in [-1.0, 1.0]:
		var x: float = half * width * 0.3
		_disc(pile, "steel", radius * (0.9 if toothed else 1.0), 0.07 if toothed else width * 0.28, x)
		if toothed:
			for i in 11:
				var a := float(i) / 11.0 * TAU
				_block(pile, "dark", Vector3(0.06, 0.13, 0.09), Vector3(x, cos(a), sin(a)) * Vector3(1, radius * 0.9 + 0.035, radius * 0.9 + 0.035), a)
	var face: float = side * (width * 0.3 + (0.04 if toothed else width * 0.14) + 0.005)
	for i in 5:
		var a := float(i) / 5.0 * TAU + 0.3
		var cm := CylinderMesh.new()
		cm.bottom_radius = radius * 0.16
		cm.top_radius = radius * 0.16
		cm.height = 0.02
		cm.radial_segments = 8
		cm.rings = 1
		_add(pile, "dark", cm, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(face, cos(a) * radius * 0.6, sin(a) * radius * 0.6)))
	_disc(pile, "hub", radius * 0.3, 0.1, face + side * 0.03, side, radius * 0.2, 8)
	return _commit(pile, materials)


# A little return roller that carries the top of the track.
static func _roller_mesh(radius: float, width: float, materials: Dictionary) -> ArrayMesh:
	var pile := {}
	for half in [-1.0, 1.0]:
		_disc(pile, "rubber", radius, width * 0.34, half * width * 0.28, 1.0, -1.0, 10)
	_disc(pile, "steel", radius * 0.5, width, 0.0, 1.0, -1.0, 8)
	return _commit(pile, materials)


# One link of track: the pad, a raised bar across its outside to bite the ground, a guide
# tooth on its inside that runs between the wheels, and the thicker ends where the pins go.
# A link's own +Y faces outwards from the loop. Its lowest point is kept where the plain
# link's was, so the tracks sit on the ground exactly as before.
static func _link_mesh(tw: float, pitch: float) -> ArrayMesh:
	var pile := {}
	_block(pile, "t", Vector3(tw, 0.05, pitch * 0.84), Vector3(0, -0.015, 0))
	_block(pile, "t", Vector3(tw * 0.96, 0.04, pitch * 0.3), Vector3(0, 0.02, 0))
	_block(pile, "t", Vector3(0.06, 0.1, pitch * 0.42), Vector3(0, -0.085, 0))
	for half in [-1.0, 1.0]:
		_block(pile, "t", Vector3(0.06, 0.065, pitch * 0.98), Vector3(half * (tw * 0.5 - 0.03), -0.012, 0))
	return _commit(pile, {})


# The closed path a track follows, as points in the (z, y) plane with the distance to each:
# along the ground under the road wheels, up round the idler, back along the top, and down
# round the sprocket.
static func _track_loop(hl: float, th: float, front: Vector2, rear: Vector2, end_r: float) -> Dictionary:
	var pts: Array = [Vector2(hl * 0.66, 0.05), Vector2(-hl * 0.66, 0.05)]
	for deg in [-70.0, -30.0, 10.0, 50.0, 90.0]:
		var a := deg_to_rad(deg)
		pts.append(front + Vector2(-cos(a), sin(a)) * end_r)
	pts.append(Vector2(0.0, th - 0.02))  # a little sag in the top run
	for deg in [90.0, 50.0, 10.0, -30.0, -70.0]:
		var a := deg_to_rad(deg)
		pts.append(rear + Vector2(cos(a), sin(a)) * end_r)
	pts.append(pts[0])
	var dist: Array = [0.0]
	for i in range(1, pts.size()):
		dist.append(float(dist[i - 1]) + pts[i].distance_to(pts[i - 1]))
	return {"points": pts, "dist": dist, "length": dist[dist.size() - 1]}


# Where a link sits (and which way it faces) a given distance round the loop.
static func _on_loop(loop: Dictionary, d: float, x: float) -> Transform3D:
	var pts: Array = loop["points"]
	var dist: Array = loop["dist"]
	var i := 1
	while i < dist.size() - 1 and float(dist[i]) < d:
		i += 1
	var a: Vector2 = pts[i - 1]
	var b: Vector2 = pts[i]
	var k := (d - float(dist[i - 1])) / maxf(float(dist[i]) - float(dist[i - 1]), 0.001)
	var p := a.lerp(b, k)
	var along := Vector3(0, b.y - a.y, b.x - a.x).normalized()
	var across := Vector3(1, 0, 0)
	return Transform3D(Basis(across, along.cross(across), along), Vector3(x, p.y, p.x))


# Sets every wheel and track link for how far each side's track has run (metres, forward positive).
# lift, if given, is how far each road wheel is pushed up (or hangs down) on its suspension:
# the wheels move, and the track on the ground bends to stay under them.
static func pose_tracks(running: Dictionary, left: float, right: float, lift = null) -> void:
	var travelled := [left, right]
	for g in running["gear"]:
		g[0].rotation.x = -float(travelled[g[2]]) / float(g[1])
	var mm: MultiMesh = running["belt"]
	var per_side: int = running["per_side"]
	var length: float = running["length"]
	var between: PackedInt32Array = running["between"]
	var share: PackedFloat32Array = running["share"]
	for si in 2:
		var ups: Array = lift[si] if lift != null else []
		if lift != null:
			var road: Array = running["road"][si]
			for i in road.size():
				road[i].position.y = float(running["wheel_y"]) + float(ups[i])
		var table: Array = running["tables"][si]
		var n := table.size()
		if running.get("shed", [false, false])[si]:
			# This side's track has been shot off: none of its links are drawn (they lie on the ground: see Tank).
			for i in per_side:
				mm.set_instance_transform(si * per_side + i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		for i in per_side:
			# Driving forward carries the links on the ground towards the rear.
			var d := fposmod(float(i) * LINK_SPACING - float(travelled[si]), length)
			var k := mini(int(d / TABLE_STEP), n - 1)
			var t: Transform3D = table[k]
			if lift != null and between[k] >= 0:
				t.origin.y += lerpf(ups[between[k]], ups[between[k] + 1], share[k])
			mm.set_instance_transform(si * per_side + i, t)


# The one fitting that marks out each vehicle.
# The machine gun on each vehicle's roof: the one its real counterpart carried.
#   m2    Browning M2 .50 (American: T29/T30, M109, M41, the M113-based missile carrier)
#   dshk  DShK 12.7 mm (Soviet: IS-3, PT-76)
#   mg3   MG3 7.62 mm (German: Leopard 1, Kanonenjagdpanzer, Gepard)
#   aa52  AA-52 7.5 mm (French: AMX-13)
const ROOF_GUNS := {"bastion": "m2", "thumper": "m2", "bulldog": "m2", "adats": "m2", "warden": "dshk", "mender": "dshk",
	"lancer": "mg3", "hornet": "mg3", "gepard": "mg3", "wasp": "aa52"}


# A machine gun on a pintle at `at` (the foot of the pintle), pointing forward (-Z).
static func _roof_gun(turret: Node3D, at: Vector3, kind: String, steel: Material, dark: Material, olive: Material) -> void:
	var g := Node3D.new()
	g.position = at + Vector3(0, 0.36, 0)  # the top of the pintle: the gun's pivot
	turret.add_child(g)
	MeshUtil.rod(turret, at, at + Vector3(0, 0.3, 0), 0.03, steel)
	# The cradle: a fork the gun sits in.
	MeshUtil.box(g, Vector3(0.14, 0.05, 0.1), Vector3(0, -0.05, 0), steel)
	for side in [1.0, -1.0]:
		MeshUtil.box(g, Vector3(0.015, 0.1, 0.08), Vector3(side * 0.065, 0.0, 0), steel)
	match kind:
		"m2":
			# Browning M2: a long slab of a receiver, a heavy barrel with a perforated jacket at
			# its root, twin spade grips at the back, and an ammunition box hung on the left.
			MeshUtil.box(g, Vector3(0.085, 0.13, 0.52), Vector3(0, 0.03, 0.08), dark)
			MeshUtil.box(g, Vector3(0.07, 0.03, 0.3), Vector3(0, 0.105, 0.02), steel)  # top cover
			MeshUtil.rod(g, Vector3(0, 0.04, -0.18), Vector3(0, 0.04, -0.5), 0.034, steel)  # barrel jacket
			MeshUtil.rod(g, Vector3(0, 0.04, -0.5), Vector3(0, 0.04, -1.15), 0.02, steel)
			for k in 4:
				MeshUtil.box(g, Vector3(0.072, 0.012, 0.03), Vector3(0, 0.04, -0.24 - k * 0.07), dark)  # the slots in the jacket
			for side in [1.0, -1.0]:
				MeshUtil.rod(g, Vector3(side * 0.035, 0.03, 0.34), Vector3(side * 0.035, 0.03, 0.44), 0.012, steel)
				MeshUtil.rod(g, Vector3(side * 0.035, -0.02, 0.44), Vector3(side * 0.035, 0.08, 0.44), 0.016, dark)  # spade grips
			MeshUtil.box(g, Vector3(0.012, 0.03, 0.05), Vector3(0, 0.03, 0.42), steel)  # the butterfly trigger
			MeshUtil.box(g, Vector3(0.11, 0.17, 0.3), Vector3(-0.11, -0.01, 0.02), olive)  # ammunition box
			MeshUtil.box(g, Vector3(0.05, 0.012, 0.03), Vector3(-0.055, 0.085, 0.0), steel)  # the belt going in
			MeshUtil.box(g, Vector3(0.006, 0.05, 0.012), Vector3(0, 0.12, -0.16), steel)  # rear sight
		"dshk":
			# DShK: a barrel ringed with cooling fins, a big flat muzzle brake, a round-backed
			# receiver with two wooden-handled grips, and a square ammunition box on the left.
			MeshUtil.box(g, Vector3(0.08, 0.11, 0.42), Vector3(0, 0.03, 0.1), dark)
			MeshUtil.rod(g, Vector3(0, 0.04, -0.1), Vector3(0, 0.04, -1.05), 0.019, steel)
			for k in 9:
				MeshUtil.cylinder(g, 0.036, 0.016, Vector3(0, 0.04, -0.16 - k * 0.055), steel).rotation.x = PI * 0.5
			MeshUtil.box(g, Vector3(0.11, 0.05, 0.1), Vector3(0, 0.04, -1.08), steel)  # muzzle brake
			for side in [1.0, -1.0]:
				MeshUtil.rod(g, Vector3(side * 0.05, 0.04, 0.3), Vector3(side * 0.05, 0.04, 0.46), 0.017, olive)
			MeshUtil.box(g, Vector3(0.14, 0.13, 0.2), Vector3(-0.12, 0.0, 0.05), olive)
			MeshUtil.box(g, Vector3(0.006, 0.07, 0.012), Vector3(0, 0.12, -0.05), steel)
		"mg3":
			# MG3: a slim gun with a square, slotted barrel jacket, a flared muzzle, a plastic
			# butt, and a belt drum on the left.
			MeshUtil.box(g, Vector3(0.05, 0.07, 0.34), Vector3(0, 0.03, 0.12), dark)
			MeshUtil.box(g, Vector3(0.045, 0.05, 0.56), Vector3(0, 0.035, -0.33), steel)  # jacket
			for k in 6:
				MeshUtil.box(g, Vector3(0.05, 0.022, 0.045), Vector3(0, 0.035, -0.12 - k * 0.08), dark)
			MeshUtil.cylinder(g, 0.022, 0.07, Vector3(0, 0.035, -0.64), steel, 0.03).rotation.x = -PI * 0.5
			MeshUtil.box(g, Vector3(0.04, 0.07, 0.24), Vector3(0, 0.02, 0.4), dark)  # butt
			MeshUtil.box(g, Vector3(0.03, 0.08, 0.035), Vector3(0, -0.03, 0.2), dark)  # grip
			MeshUtil.cylinder(g, 0.075, 0.07, Vector3(-0.07, 0.0, 0.1), olive).rotation.z = PI * 0.5
		_:
			# AA-52: plain and tubular, a thin barrel with a cone flash hider and a side-fed belt box.
			MeshUtil.rod(g, Vector3(0, 0.03, 0.32), Vector3(0, 0.03, -0.12), 0.036, dark)
			MeshUtil.rod(g, Vector3(0, 0.03, -0.12), Vector3(0, 0.03, -0.82), 0.016, steel)
			MeshUtil.cylinder(g, 0.016, 0.08, Vector3(0, 0.03, -0.86), steel, 0.03).rotation.x = -PI * 0.5
			MeshUtil.box(g, Vector3(0.03, 0.08, 0.035), Vector3(0, -0.035, 0.18), dark)
			MeshUtil.rod(g, Vector3(0, 0.03, 0.32), Vector3(0, 0.0, 0.52), 0.014, steel)  # the wire butt
			MeshUtil.box(g, Vector3(0.09, 0.1, 0.16), Vector3(-0.09, 0.01, 0.06), olive)


static var _radar_node: Node3D  # the turning part of the radar on the vehicle being built, if it has one

# A search radar's aerial on top of its mast: a curved dish made of seven flat panels bent
# round in an arc, with the feed horn held out in front of it on two struts. It sits on a
# pivot of its own so the vehicle can turn it (Tank spins it while the radar is on).
static func _aerial(turret: Node3D, at: Vector3, wide: float, tall: float, dish_mat: Material, metal_mat: Material) -> void:
	var pivot := Node3D.new()
	pivot.position = at
	turret.add_child(pivot)
	_radar_node = pivot
	var lean := Node3D.new()
	lean.rotation.x = -0.18  # tipped back a little, to look up
	pivot.add_child(lean)
	var bend := wide * 0.75  # the radius of the curve
	for k in 7:
		var a := (float(k) - 3.0) * 0.21
		var panel := MeshUtil.box(lean, Vector3(wide * 0.165, tall * (1.0 - absf(float(k) - 3.0) * 0.06), 0.06), Vector3(sin(a) * bend, tall * 0.5, (1.0 - cos(a)) * -bend), dish_mat)
		panel.rotation.y = a
	MeshUtil.box(lean, Vector3(wide * 1.0, 0.07, 0.07), Vector3(0, 0.03, 0.02), metal_mat)
	MeshUtil.box(lean, Vector3(0.16, 0.16, 0.2), Vector3(0, tall * 0.5, -bend * 0.55), metal_mat)
	for side in [1.0, -1.0]:
		MeshUtil.rod(lean, Vector3(side * wide * 0.3, 0.05, 0), Vector3(side * 0.06, tall * 0.5, -bend * 0.55), 0.025, metal_mat)


static func _extra(kind: String, root: Node3D, turret: Node3D, l: float, w: float, ht: float, th: float, tl: float, twd: float, top_y: float, hull_mat: Material, dark_mat: Material, metal_mat: Material) -> void:
	var hl := l * 0.5
	match kind:
		"dozer":
			var blade := MeshUtil.box(root, Vector3(w * 1.02, 0.9, 0.14), Vector3(0, 0.6, -hl - 0.45), metal_mat)
			blade.rotation.x = -0.25
			for side in [-1.0, 1.0]:
				MeshUtil.box(root, Vector3(0.14, 0.14, 0.7), Vector3(side * w * 0.3, 0.7, -hl - 0.15), metal_mat)
		"drums":
			for side in [-1.0, 1.0]:
				var drum := MeshUtil.cylinder(root, 0.3, w * 0.4, Vector3(side * w * 0.22, ht + 0.25, hl - 0.1), dark_mat)
				drum.rotation.z = PI * 0.5
		"basket":
			MeshUtil.box(turret, Vector3(twd * 0.9, top_y * 0.45, 0.7), Vector3(0, top_y * 0.45, tl * 0.5 + 0.35), dark_mat)
		"spade":
			var spade := MeshUtil.box(root, Vector3(w * 0.8, 0.7, 0.12), Vector3(0, th * 0.7, hl + 0.35), metal_mat)
			spade.rotation.x = 0.5
			# The arms it hangs from, so it is not floating behind the hull.
			for side in [-1.0, 1.0]:
				MeshUtil.rod(root, Vector3(side * w * 0.3, th * 0.95, hl - 0.05), Vector3(side * w * 0.3, th * 0.75, hl + 0.36), 0.07, metal_mat)
		"antenna":
			_whip(turret, Vector3(-twd * 0.3, top_y, tl * 0.4), 3.2, 0.03, metal_mat)
			_whip(turret, Vector3(twd * 0.3, top_y, tl * 0.4), 2.2, 0.03, metal_mat)
			MeshUtil.box(turret, Vector3(0.7, 0.3, 0.3), Vector3(0, top_y + 0.15, tl * 0.36), dark_mat)  # radio set, sitting on the roof
		"radar":
			# An anti-aircraft tank: a search radar aerial standing at the back of the turret roof
			# and a round tracking dish on its front.
			MeshUtil.cylinder(turret, 0.09, 0.9, Vector3(0, top_y + 0.45, tl * 0.38), metal_mat)
			_aerial(turret, Vector3(0, top_y + 0.95, tl * 0.38), twd * 1.0, 0.8, dark_mat, metal_mat)
			var dish := MeshUtil.cylinder(turret, 0.55, 0.16, Vector3(0, top_y * 0.62, -tl * 0.5 - 0.22), dark_mat, 0.3)
			dish.rotation.x = -PI * 0.5
		"launchers":
			# A missile carrier: a box of four launch tubes on each side of the turret, a radar
			# aerial on top and a sensor head between them.
			for side in [1.0, -1.0]:
				var px: float = side * (twd * 0.5 + 0.42)
				MeshUtil.box(turret, Vector3(0.74, 0.74, 1.9), Vector3(px, top_y * 0.62, 0.0), hull_mat)
				MeshUtil.box(turret, Vector3(0.3, 0.3, 0.5), Vector3(side * twd * 0.5, top_y * 0.6, 0.2), dark_mat)
				for k in 4:
					var tube := MeshUtil.cylinder(turret, 0.14, 0.06, Vector3(px + (float(k % 2) - 0.5) * 0.34, top_y * 0.62 + (float(k / 2) - 0.5) * 0.34, -0.96), metal_mat)
					tube.rotation.x = PI * 0.5
			MeshUtil.cylinder(turret, 0.08, 0.7, Vector3(0, top_y + 0.35, tl * 0.3), metal_mat)
			_aerial(turret, Vector3(0, top_y + 0.75, tl * 0.3), 1.6, 0.55, dark_mat, metal_mat)
			MeshUtil.box(turret, Vector3(0.5, 0.42, 0.5), Vector3(0, top_y + 0.2, -tl * 0.3), dark_mat)
		"crane":
			MeshUtil.box(root, Vector3(0.5, 0.9, 0.5), Vector3(w * 0.25, ht + 0.45, hl * 0.55), hull_mat)
			var boom := MeshUtil.box(root, Vector3(0.22, 0.22, l * 0.62), Vector3(w * 0.25, ht + 1.5, hl * 0.02), metal_mat)
			boom.rotation.x = 0.32
			MeshUtil.box(root, Vector3(0.3, 0.5, 0.3), Vector3(w * 0.25, ht + 1.95, -hl * 0.55), dark_mat)


# Is the rear of the hull deck clear of the turret as it turns? Something `tall` metres high
# standing at the back corners of the deck would be hit if the turret (or its bustle, tarpaulin
# and packs) overhangs it and sits low enough. A fixed casemate never swings.
static func _swing_clear(def: Dictionary, tall: float) -> bool:
	if def["turret_shape"] == "casemate":
		return float(def["turret_pos"]) + float(def["turret_len"]) * 0.5 < 0.3
	var l: float = def["length"]
	var w: float = def["width"]
	var reach := Vector2(l * float(def["turret_len"]) * 0.5 + 0.75, w * float(def["turret_wid"]) * 0.5).length()
	var corner := Vector2(l * (0.42 - float(def["turret_pos"])) - 0.25, w * 0.36 - 0.2).length()
	return corner > reach + 0.1 or tall < 0.0


# A radio aerial on its own pivot at the base, marked so the vehicle can find it and make it
# sway (tank.gd looks for the "whip" mark).
static func _whip(parent: Node3D, base: Vector3, length: float, radius: float, mat: Material) -> void:
	var pivot := Node3D.new()
	pivot.position = base
	pivot.set_meta("whip", true)
	parent.add_child(pivot)
	MeshUtil.cylinder(pivot, radius, length, Vector3(0, length * 0.5, 0), mat)


# Stowage and fittings: the clutter that makes a tank look lived in. Pioneer tools clamped
# to one fender, a tow cable looped along the other, spare track links on the glacis,
# headlights, tow shackles, fuel cans, a stowage bin, engine grille, hatches, periscopes,
# a commander's machine gun, smoke dischargers, an aerial and a rolled tarpaulin.
# Which side the tools go on is fixed per vehicle, so two of a kind match.
static func _details(def: Dictionary, root: Node3D, turret: Node3D, l: float, w: float, ht: float, th: float, tl: float, twd: float, tth: float, top_y: float, mats: Array, hull_mat: Material, dark_mat: Material) -> void:
	var hl := l * 0.5
	var shape: String = def["turret_shape"]
	var wood := _mat(Color(0.5, 0.36, 0.2), mats, "")
	var steel := _mat(Color(0.3, 0.3, 0.32), mats, "")
	var canvas := _mat(Color(0.5, 0.47, 0.33), mats, "")
	var lens := _mat(Color(0.95, 0.93, 0.75), mats, "")
	var fender_y := th + 0.15
	var fx := w * 0.5 - w * 0.085
	var ts := 1.0 if hash(String(def["id"])) % 2 == 0 else -1.0  # the side the tools are on

	# Pioneer tools, each held by two clamps.
	var tx := ts * fx
	var z0 := -hl * 0.12
	MeshUtil.rod(root, Vector3(tx - 0.14, fender_y, z0), Vector3(tx - 0.14, fender_y, z0 + 1.2), 0.025, wood)
	MeshUtil.box(root, Vector3(0.22, 0.03, 0.3), Vector3(tx - 0.14, fender_y, z0 - 0.14), steel)       # shovel
	MeshUtil.rod(root, Vector3(tx + 0.08, fender_y, z0 + 0.1), Vector3(tx + 0.08, fender_y, z0 + 0.95), 0.025, wood)
	MeshUtil.box(root, Vector3(0.22, 0.05, 0.12), Vector3(tx + 0.12, fender_y, z0 + 0.15), steel)     # axe
	MeshUtil.rod(root, Vector3(tx - 0.02, fender_y, z0 + 1.35), Vector3(tx - 0.02, fender_y, z0 + 2.5), 0.02, steel)
	MeshUtil.rod(root, Vector3(tx - 0.02, fender_y, z0 + 2.5), Vector3(tx + 0.06, fender_y + 0.04, z0 + 2.6), 0.02, steel)  # crowbar
	MeshUtil.rod(root, Vector3(tx + 0.18, fender_y, z0 + 1.35), Vector3(tx + 0.18, fender_y, z0 + 2.1), 0.025, wood)
	MeshUtil.box(root, Vector3(0.1, 0.1, 0.24), Vector3(tx + 0.18, fender_y + 0.02, z0 + 1.4), steel)  # sledgehammer
	for cz in [z0 + 0.35, z0 + 0.85, z0 + 1.6, z0 + 2.0]:
		MeshUtil.box(root, Vector3(0.46, 0.035, 0.05), Vector3(tx + 0.02, fender_y + 0.03, cz), dark_mat)

	# Stowage bin behind the tools.
	MeshUtil.box(root, Vector3(w * 0.15, 0.28, 0.8), Vector3(tx, fender_y + 0.13, hl * 0.82), hull_mat)
	MeshUtil.box(root, Vector3(w * 0.155, 0.03, 0.82), Vector3(tx, fender_y + 0.28, hl * 0.82), dark_mat)

	# Tow cable: out along the fender's edge and back, an eye at each end.
	var cx := -ts * fx
	var cable: Array = [
		Vector3(cx + 0.2, fender_y, -hl * 0.55), Vector3(cx + 0.22, fender_y, -hl * 0.2), Vector3(cx + 0.2, fender_y, hl * 0.2),
		Vector3(cx + 0.17, fender_y, hl * 0.52), Vector3(cx, fender_y + 0.02, hl * 0.62), Vector3(cx - 0.17, fender_y, hl * 0.52),
		Vector3(cx - 0.2, fender_y, hl * 0.15), Vector3(cx - 0.18, fender_y, -hl * 0.3)]
	for i in cable.size() - 1:
		MeshUtil.rod(root, cable[i], cable[i + 1], 0.03, steel)
	for end in [cable[0], cable[cable.size() - 1]]:
		MeshUtil.cylinder(root, 0.09, 0.05, end + Vector3(0, 0.0, -0.08), steel)
	for cz in [-hl * 0.35, hl * 0.05, hl * 0.4]:
		MeshUtil.box(root, Vector3(0.5, 0.03, 0.05), Vector3(cx, fender_y + 0.04, cz), dark_mat)

	# Spare track links bolted to the glacis.
	var nose := Vector2(-hl, th + (ht - th) * 0.3)
	var brow := Vector2(-hl * 0.42, ht)
	var slope := atan2(brow.y - nose.y, brow.x - nose.x)
	var mid := nose.lerp(brow, 0.55)
	for i in 3:
		var link := MeshUtil.box(root, Vector3(w * 0.14, 0.08, 0.3), Vector3((float(i) - 1.0) * w * 0.16, mid.y + 0.07, mid.x), steel)
		link.rotation.x = -slope

	# Headlights in guards, and tow shackles front and rear.
	var lamp := nose.lerp(brow, 0.22)
	for sx in [-1.0, 1.0]:
		var housing := MeshUtil.cylinder(root, 0.12, 0.14, Vector3(sx * w * 0.34, lamp.y + 0.16, lamp.x), dark_mat)
		housing.rotation.x = PI * 0.5
		var glass := MeshUtil.cylinder(root, 0.1, 0.03, Vector3(sx * w * 0.34, lamp.y + 0.16, lamp.x - 0.08), lens)
		glass.rotation.x = PI * 0.5
		MeshUtil.box(root, Vector3(0.3, 0.03, 0.22), Vector3(sx * w * 0.34, lamp.y + 0.31, lamp.x), dark_mat)
		for sz in [-1.0, 1.0]:
			MeshUtil.box(root, Vector3(0.09, 0.22, 0.14), Vector3(sx * w * 0.2, 0.62, sz * hl * 0.97), steel)
		# Mud flaps at both ends of each fender.
		for sz in [-1.0, 1.0]:
			MeshUtil.box(root, Vector3(w * 0.17, 0.3, 0.04), Vector3(sx * fx, th - 0.04, sz * hl * 0.99), dark_mat)
		# A line of bolt heads along the top edge of the hull side.
		var bz := -hl * 0.38
		while bz < hl * 0.95:
			MeshUtil.box(root, Vector3(0.04, 0.05, 0.05), Vector3(sx * w * 0.495, ht - 0.1, bz), dark_mat)
			bz += 0.55

	# Fuel cans strapped to the rear, engine grille slats, the driver's hatch and periscope.
	# (The cans lie flat, strapped down, on the rear corners of the deck: but only where the
	# turret's back end cannot sweep over them as it turns.)
	var deck_clear := _swing_clear(def, 0.34)
	for sx in [-1.0, 1.0]:
		if not deck_clear:
			break
		MeshUtil.box(root, Vector3(0.34, 0.2, 0.46), Vector3(sx * w * 0.36, ht + 0.1, hl * 0.84), dark_mat)
		var cap := MeshUtil.cylinder(root, 0.04, 0.06, Vector3(sx * w * 0.36 - 0.08, ht + 0.14, hl * 0.84 - 0.26), steel)
		cap.rotation.x = PI * 0.5
		MeshUtil.box(root, Vector3(0.36, 0.03, 0.08), Vector3(sx * w * 0.36, ht + 0.21, hl * 0.84), canvas)
	for i in 6:
		MeshUtil.box(root, Vector3(w * 0.5, 0.03, 0.05), Vector3(0, ht + 0.075, hl * 0.58 + float(i) * 0.09 * l / 7.0), steel)
	MeshUtil.cylinder(root, 0.3, 0.05, Vector3(-ts * w * 0.24, ht + 0.03, -hl * 0.34), dark_mat)
	MeshUtil.box(root, Vector3(0.24, 0.1, 0.08), Vector3(-ts * w * 0.24, ht + 0.06, -hl * 0.4), steel)
	MeshUtil.box(root, Vector3(0.2, 0.03, 0.05), Vector3(-ts * w * 0.24, ht + 0.07, -hl * 0.3), steel)

	# Turret fittings.
	var cup := Vector3(twd * 0.18, top_y + 0.1, tl * 0.12)
	for a in [0.0, 1.2, -1.2, 2.4, -2.4]:
		var p := MeshUtil.box(turret, Vector3(0.12, 0.08, 0.06), cup + Vector3(sin(a) * 0.3, 0.14, -cos(a) * 0.3), steel)
		p.rotation.y = -a
	# Commander's machine gun on a pintle.
	_roof_gun(turret, cup + Vector3(0.2, 0.1, -0.1), String(ROOF_GUNS.get(def.get("turret_as", def["id"]) if not ROOF_GUNS.has(def["id"]) else def["id"], "m2")), steel, dark_mat, _mat(Color(0.3, 0.33, 0.2), mats, ""))
	var tur: Array = TURRETS.get(def.get("turret_as", def["id"]), TURRETS["lancer"])
	if String(def["extra"]) != "antenna":
		var mast := Vector3(-twd * 0.5 * _along(tur, 0.34, 2) * 0.75, tth * _along(tur, 0.34, 4), tl * 0.34)
		MeshUtil.cylinder(turret, 0.05, 0.12, mast + Vector3(0, 0.06, 0), steel)
		_whip(turret, mast + Vector3(0, 0.1, 0), 2.2, 0.012, steel)
	if shape != "dome":
		# Smoke dischargers on the turret cheeks, lifting eyes on the roof, a tarpaulin behind.
		for sx in [-1.0, 1.0]:
			for i in 3:
				var from := Vector3(sx * twd * 0.5, tth * (0.45 + i * 0.14), -tl * 0.22)
				MeshUtil.rod(turret, from, from + Vector3(sx * 0.16, 0.14, -0.22), 0.05, steel)
			# (Both pairs are on the flat middle of the roof, which every turret shape has; further
			# out they hung in the air over a sloping front or back.)
			MeshUtil.box(turret, Vector3(0.05, 0.1, 0.14), Vector3(sx * twd * 0.5 * _along(tur, -0.08, 2) * 0.9, tth * _along(tur, -0.08, 4) + 0.05, -tl * 0.08), steel)
			MeshUtil.box(turret, Vector3(0.05, 0.1, 0.14), Vector3(sx * twd * 0.5 * _along(tur, 0.13, 2) * 0.92, tth * _along(tur, 0.13, 4) + 0.05, tl * 0.13), steel)
		if String(def["extra"]) != "basket":
			var roll := MeshUtil.cylinder(turret, 0.17, twd * 0.8, Vector3(0, tth * 0.5, tl * 0.5 + 0.18), canvas)
			roll.rotation.z = PI * 0.5
			for sx in [-1.0, 1.0]:
				MeshUtil.box(turret, Vector3(0.06, 0.38, 0.38), Vector3(sx * twd * 0.25, tth * 0.5, tl * 0.5 + 0.18), dark_mat)


# Dirt and damage from use: mud thrown up the hull sides and rear and caked on the mud flaps,
# and paint chipped down to bare metal on a worn vehicle.
static func _weathering(root: Node3D, l: float, w: float, ht: float, th: float, wear: float, seed_value: int) -> void:
	if wear < 0.12:
		return
	var hl := l * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var splash := StandardMaterial3D.new()
	splash.albedo_texture = Tex.named("mud")
	splash.albedo_color = Color(1, 1, 1, clampf(wear * 1.3, 0.0, 1.0))
	splash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	splash.roughness = 1.0
	splash.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rise := (ht - th) * lerpf(0.35, 0.95, wear)
	for sx in [-1.0, 1.0]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(l * 0.96, rise)
		q.mesh = qm
		q.material_override = splash
		q.position = Vector3(sx * (w * 0.492 + 0.04), th + rise * 0.5, 0)  # clear of the hull side, or the two flicker
		q.rotation.y = sx * PI * 0.5
		root.add_child(q)
	for sz in [-1.0, 1.0]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(w * 0.9, rise * 0.8)
		q.mesh = qm
		q.material_override = splash
		q.position = Vector3(0, th + rise * 0.4, sz * (hl + 0.012))
		q.rotation.y = 0.0 if sz > 0.0 else PI
		root.add_child(q)
	# Clods stuck to the mud flaps and fender edges.
	var clod := MeshUtil.material(Color(0.3, 0.23, 0.14), 1.0)
	for i in int(wear * 14.0):
		var sx := 1.0 if rng.randf() < 0.5 else -1.0
		var sz := 1.0 if rng.randf() < 0.5 else -1.0
		var s := rng.randf_range(0.06, 0.16)
		MeshUtil.box(root, Vector3(s, s * 0.7, s), Vector3(sx * (w * 0.5 - rng.randf_range(0.05, w * 0.17)), th - rng.randf_range(0.0, 0.22), sz * (hl * 0.99 + 0.03)), clod)
	if wear > 0.45:
		# Chipped paint: bright scrapes on the edges that catch on things.
		for i in int((wear - 0.3) * 9.0):
			var d := Decal.new()
			var size := rng.randf_range(0.3, 0.7)
			d.size = Vector3(size, 0.6, size)
			d.texture_albedo = Tex.named("gouge")
			d.texture_normal = Tex.named("gouge_normal")
			d.modulate = Color(0.75, 0.7, 0.62, 0.8)
			root.add_child(d)
			var sx := 1.0 if rng.randf() < 0.5 else -1.0
			# A decal projects down its own Y axis: lay that axis across the hull side.
			d.transform = Transform3D(Basis(Vector3(0, 0, 1), Vector3(sx, 0, 0), Vector3(0, sx, 0)).rotated(Vector3(sx, 0, 0), rng.randf() * TAU), Vector3(sx * (w * 0.49 + 0.03), rng.randf_range(th + 0.1, ht - 0.05), rng.randf_range(-hl * 0.9, hl * 0.9)))


# The crew's own things, tied on wherever there is room: packs, helmets, bedrolls, ammunition
# boxes, a rope, an unditching log, sandbags, a crate, a spare road wheel. A fresh vehicle
# carries a couple; a worn one is festooned. Kit goes in the turret basket if there is one.
static func _crew_kit(def: Dictionary, root: Node3D, turret: Node3D, l: float, w: float, ht: float, th: float, tl: float, twd: float, tth: float, wear: float, seed_value: int, mats: Array, team_color: Color) -> void:
	var hl := l * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	var canvas := _mat(Color(0.47, 0.45, 0.3), mats, "")
	var khaki := _mat(Color(0.56, 0.5, 0.36), mats, "")
	var wood := _mat(Color(0.5, 0.36, 0.2), mats, "")
	var steel := _mat(Color(0.26, 0.28, 0.24), mats, "")
	var strap := _mat(Color(0.2, 0.16, 0.1), mats, "")
	var helmet_mat := _mat(SoldierModel.PLASTIC[0 if team_color.b > team_color.r else 1].darkened(0.1), mats, "")
	var dome: bool = def["turret_shape"] == "dome"
	var basket: bool = def["extra"] == "basket"
	var side_y := lerpf(th + 0.3, ht - 0.25, 0.55)  # hanging on the hull side, above the fender
	# (Logs, sandbags and crates are left off: those are to become things the player chooses.)
	var kit := ["pack", "helmet", "bedroll", "ammo", "rope", "wheel", "pack", "helmet"]
	var count := clampi(int(round(lerpf(1.0, 4.0, wear) + rng.randf_range(-1.0, 1.0))), 1, kit.size())
	# Shuffle with this vehicle's seed.
	for i in range(kit.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: String = kit[i]
		kit[i] = kit[j]
		kit[j] = tmp
	var slot := 0  # successive places along the hull sides
	for n in count:
		var sx := 1.0 if slot % 2 == 0 else -1.0
		var hz := lerpf(-hl * 0.25, hl * 0.5, float(slot / 2) / 4.0) + rng.randf_range(-0.1, 0.1)
		var at := Vector3(sx * (w * 0.49 + 0.14), side_y, hz)
		match String(kit[n]):
			"pack":
				if basket or not dome:
					# On the turret: in the basket, or strapped to the back.
					var tz := tl * 0.5 + (0.38 if basket else 0.42)
					var tx := rng.randf_range(-twd * 0.3, twd * 0.3)
					MeshUtil.box(turret, Vector3(0.42, 0.5, 0.26), Vector3(tx, tth * 0.55, tz), canvas)
					MeshUtil.box(turret, Vector3(0.44, 0.07, 0.28), Vector3(tx, tth * 0.62, tz), strap)
					MeshUtil.box(turret, Vector3(0.3, 0.16, 0.1), Vector3(tx, tth * 0.4, tz + 0.16), khaki)
				else:
					MeshUtil.box(root, Vector3(0.26, 0.5, 0.42), at, canvas)
					MeshUtil.box(root, Vector3(0.28, 0.07, 0.44), at + Vector3(0, 0.08, 0), strap)
					slot += 1
			"helmet":
				var m := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.19
				sm.height = 0.19
				sm.is_hemisphere = true
				m.mesh = sm
				m.material_override = helmet_mat
				if dome:
					m.position = at + Vector3(-sx * 0.04, 0.1, 0)
					m.rotation.z = -sx * PI * 0.5
					root.add_child(m)
					slot += 1
				elif not _marked:  # (not where it would hang over the turret's marking)
					# Hung on the turret side by its chin strap.
					m.position = Vector3(sx * (twd * 0.5 + 0.04), tth * 0.55, rng.randf_range(-tl * 0.1, tl * 0.3))
					m.rotation.z = -sx * PI * 0.5
					turret.add_child(m)
			"bedroll":
				var roll := MeshUtil.cylinder(root, 0.15, 0.75, at + Vector3(0, -0.12, 0), khaki)
				roll.rotation.x = PI * 0.5
				for k in [-0.22, 0.22]:
					MeshUtil.box(root, Vector3(0.33, 0.33, 0.05), at + Vector3(0, -0.12, k), strap)
				slot += 1
			"ammo":
				for k in 2:
					MeshUtil.box(root, Vector3(0.2, 0.26, 0.4), at + Vector3(0, -0.14, k * 0.44 - 0.22), steel)
					MeshUtil.box(root, Vector3(0.06, 0.04, 0.16), at + Vector3(0, 0.02, k * 0.44 - 0.22), strap)
				slot += 1
			"rope":
				# A coil hung on a hook.
				var ring := 8
				for k in ring:
					var a0 := float(k) / ring * TAU
					var a1 := float(k + 1) / ring * TAU
					for r in [0.24, 0.3]:
						MeshUtil.rod(root, at + Vector3(0, cos(a0) * r, sin(a0) * r), at + Vector3(0, cos(a1) * r, sin(a1) * r), 0.035, khaki)
				slot += 1
			"log":
				# An unditching log lashed along the side.
				var lz := rng.randf_range(-hl * 0.1, hl * 0.2)
				MeshUtil.rod(root, Vector3(at.x, side_y - 0.25, lz - l * 0.28), Vector3(at.x, side_y - 0.25, lz + l * 0.28), 0.14, wood)
				for k in [-0.2, 0.2]:
					MeshUtil.box(root, Vector3(0.32, 0.32, 0.06), Vector3(at.x, side_y - 0.25, lz + k * l), strap)
			"sandbags":
				# A row laid flat on the glacis for a little extra protection.
				var low := Vector2(-hl, th + (ht - th) * 0.3)   # the foot of the glacis (z, y)
				var high := Vector2(-hl * 0.42, ht)             # its top edge
				var tilt := atan2(high.y - low.y, high.x - low.x)
				var spot := low.lerp(high, 0.28)
				for k in 4:
					var bag := MeshUtil.box(root, Vector3(w * 0.2, 0.2, 0.42), Vector3((float(k) - 1.5) * w * 0.21, spot.y + 0.12, spot.x), khaki)
					# Tilt it to lie along the slope of the plate (the same turn the spare links get).
					bag.rotation.x = -tilt
			"crate":
				if not _swing_clear(def, 0.5):
					continue  # the turret would sweep through it
				var crate_x := rng.randf_range(-w * 0.15, w * 0.15)
				MeshUtil.box(root, Vector3(0.7, 0.4, 0.5), Vector3(crate_x, ht + 0.26, hl * 0.74), wood)
				MeshUtil.box(root, Vector3(0.72, 0.05, 0.52), Vector3(crate_x, ht + 0.3, hl * 0.74), strap)
			"wheel":
				# A spare road wheel.
				var rw := MeshUtil.cylinder(root, th * 0.36, 0.14, Vector3(0, ht - 0.2, hl + 0.1), steel)
				rw.rotation.x = PI * 0.5
				var hub := MeshUtil.cylinder(root, th * 0.14, 0.18, Vector3(0, ht - 0.2, hl + 0.1), strap)
				hub.rotation.x = PI * 0.5


# Toy-plastic paint: a bit of shine.
# What a loadout adds to the model: a marking on both turret sides, and each piece of
# equipment as a simple shape in its place.
static func _fit(look: Dictionary, root: Node3D, turret: Node3D, l: float, w: float, ht: float, th: float, tl: float, twd: float, tth: float, tur: Array, mats: Array) -> void:
	var decal: Dictionary = look.get("decal", {})
	if String(decal.get("text", "")) != "":
		var ink := Color(String(decal.get("colour", "#f0f0e8")))
		var half := twd * 0.5 * _along(tur, 0.1, 1) + 0.06  # just outside the widest part of the turret side
		for side in [-1.0, 1.0]:
			var at := Vector3(side * half, tth * 0.5, tl * 0.1)
			var back := String(decal.get("back", "none"))
			if back != "none":
				var plate := MeshUtil.box(turret, Vector3(0.03, tth * 0.6, tth * 0.6), at, _mat(Color(0.1, 0.1, 0.1) if ink.get_luminance() > 0.5 else Color(0.92, 0.92, 0.88), mats, ""))
				if back == "disc":
					plate.mesh = CylinderMesh.new()
					plate.mesh.top_radius = tth * 0.32
					plate.mesh.bottom_radius = tth * 0.32
					plate.mesh.height = 0.03
					plate.rotation.z = PI * 0.5
			# Each character is set on the turret wall by itself, turned to lie on the wall
			# where it stands, so the marking bends round a curved turret. On a turret whose
			# sides lean in from low down, it goes on the upright part below the lean.
			var word := String(decal["text"]).left(3)
			var low: bool = _along(tur, 0.1, 5) > 0.45
			var tall := tth * (0.36 if low else 0.5)
			for i in word.length():
				var along: float = (float(i) - float(word.length() - 1) * 0.5) * tall * 0.62 * -side
				var zf: float = 0.1 + along / tl
				var wall: float = twd * 0.5 * _along(tur, zf, 1)
				var slope: float = twd * 0.5 * (_along(tur, zf + 0.04, 1) - _along(tur, zf - 0.04, 1)) / (tl * 0.08)
				var mark := Label3D.new()
				mark.text = word[i]
				mark.font_size = 160
				mark.double_sided = true
				mark.pixel_size = tall / 160.0
				mark.modulate = ink
				mark.outline_size = 0
				mark.shaded = true
				mark.position = Vector3(side * (wall + 0.1), tth * (0.27 if low else 0.5), tl * 0.1 + along)
				mark.rotation.y = atan2(side, -slope)
				turret.add_child(mark)
	Kit.load_sheet()
	var hl := l * 0.5
	var olive := _mat(Color(0.3, 0.33, 0.24), mats, "")
	var khaki := _mat(Color(0.56, 0.5, 0.36), mats, "")
	var wood := _mat(Color(0.5, 0.36, 0.2), mats, "")
	var steel := _mat(Color(0.28, 0.28, 0.28), mats, "")
	var slots: Dictionary = look.get("slots", {})
	for place in slots:
		var n := 0
		for id in slots[place]:
			if not Kit.items.has(id):
				continue
			var it: Dictionary = Kit.items[id]
			var big := int(it["size"]) == 2
			# Where this place is, and which way "along it" runs. A second small item sits beside the first.
			var on: Node3D = turret if place == "basket" else root
			var at := Vector3.ZERO
			var step := Vector3(0.7, 0, 0)
			match place:
				"front_upper":
					at = Vector3(0, th + (ht - th) * 0.62, -hl * 0.72)
				"front_lower":
					at = Vector3(0, th * 0.75, -hl - 0.12)
				"left", "right":
					at = Vector3((-1.0 if place == "left" else 1.0) * (w * 0.5 + 0.12), th + 0.34, -hl * 0.1)
					step = Vector3(0, 0, 1.1)
				"basket":
					at = Vector3(0, tth * 0.45, tl * 0.5 + 0.3)
				"deck":
					at = Vector3(0, ht + 0.16, hl * 0.42)
				"rear":
					at = Vector3(0, th + 0.4, hl + 0.2)
			if not big:
				at += step * (float(n) - 0.5)
			n += 1
			var across: bool = place != "left" and place != "right"
			match String(it["shape"]):
				"can":
					MeshUtil.box(on, Vector3(0.36, 0.22, 0.5) if across else Vector3(0.2, 0.44, 0.34), at, olive)
				"roll":
					var roll := MeshUtil.cylinder(on, 0.16, 0.9 if across else 0.8, at, khaki)
					roll.rotation = Vector3(0, 0, PI * 0.5) if across else Vector3(PI * 0.5, 0, 0)
				"log":
					var trunk := MeshUtil.cylinder(on, 0.15, l * 0.5, at, wood)
					trunk.rotation.x = PI * 0.5
				"bags":
					for k in 4:
						MeshUtil.box(on, Vector3(w * 0.2, 0.2, 0.42), at + Vector3((float(k) - 1.5) * w * 0.21, 0.02, 0), khaki)
				"plate":
					MeshUtil.box(on, Vector3(w * 0.5, 0.1, 0.5) if across else Vector3(0.06, 0.5, l * 0.6), at, steel)
				"lamp":
					var lamp := MeshUtil.cylinder(on, 0.11, 0.14, at, _mat(Color(0.95, 0.93, 0.75), mats, ""))
					lamp.rotation.x = PI * 0.5
				"blade":
					var blade := MeshUtil.box(on, Vector3(w * 1.02, 0.9, 0.14), at + Vector3(0, -0.1, -0.35), steel)
					blade.rotation.x = -0.25
				"coil":
					for k in 8:
						var a0 := float(k) / 8.0 * TAU
						var a1 := float(k + 1) / 8.0 * TAU
						var flat := func(a: float) -> Vector3: return (Vector3(cos(a), sin(a), 0) if across else Vector3(0, sin(a), cos(a))) * 0.24
						MeshUtil.rod(on, at + flat.call(a0), at + flat.call(a1), 0.035, khaki)
				_:
					MeshUtil.box(on, Vector3(0.5, 0.3, 0.36) if across else Vector3(0.24, 0.3, 0.5), at, olive)


static func _mat(color: Color, mats: Array, tex: String = "camo", tile: float = 3.0) -> StandardMaterial3D:
	if tex == "camo" and _paint != null:
		# The player's own paint: their picture, a little darker where the standard paint was darker.
		var custom := MeshUtil.material(Color(1, 1, 1).darkened(clampf(0.5 - color.get_luminance(), 0.0, 0.35)), 0.5, "", tile)
		custom.albedo_texture = _paint
		custom.uv1_triplanar = true
		custom.uv1_scale = Vector3.ONE / 3.5
		mats.append([custom, custom.albedo_color])
		return custom
	var mat := MeshUtil.material(color, 0.45, tex, tile)
	mats.append([mat, color])
	return mat


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	parent.add_child(m)
	return m
