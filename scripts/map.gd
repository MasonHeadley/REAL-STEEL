class_name PushMap
extends Node3D
# Builds the battlefield. There are two:
#
#   town    a town laid out like a child's road play mat, with the districts such a mat has:
#           a downtown of tall blocks on a square grid of streets, with a paved plaza at the
#           very centre; a roundabout; a neighbourhood of houses along winding streets; a
#           park with a pond; and open country at each end. The ground is flat in the city
#           and rolls in gentle hills everywhere else. The robot's route for Push winds
#           through all of it, marked by an orange line. Everything is the same turned about
#           the centre, so both teams get the same ground and the same distance to push.
#   range   the shooting range: an open field with one straight track, firing point,
#           distance boards and earth banks to stop the shot.
#
# The route is a line through the map measured by distance along it (s): 0 at the centre,
# negative towards Blue's end and positive towards Red's. route_at / route_dir / nearest_s
# turn between that distance and places on the ground.
# Collision layers: 1 = buildings and blocks, 2 = vehicles, 4 = the mat, 8 = toy soldiers.

static var HALF_WIDTH := 304.0  # half the mat's width; a custom map sets its own
const END_MARGIN := 200.0
const TOWN_HALF_WIDTH := 560.0  # the town's mat is 1120 m across: the old town in the middle, new ground either side
const MALL_X := 440.0           # the shopping centre is out to the east, the park and its hills to the west
const STEP := 8.0
const ROAD_HALF := 8.0
const SETBACK := 18.0    # from the middle of a street to the nearest building
const FLOOR_Y := -6.0
const STRIP_Z := 762.0    # how far from the centre each team's airstrip lies
const STRIP_HALF := 135.0 # half its length
const STRIP_Y := 4.0      # the height its ground is levelled to
const CORNER := 26.0     # how wide the route's turns are rounded, metres
# Downtown: a square grid of streets either side of the centre.
const DOWNTOWN_X := [-240.0, -120.0, 0.0, 120.0, 240.0]
const DOWNTOWN_Z := [-210.0, -100.0, 0.0, 100.0, 210.0]
const HILLS_FROM := 225.0  # how far from the centre line the ground starts to roll...
const HILLS_FULL := 350.0  # ...and where the hills reach their full height
const HILL_HEIGHT := 15.0
# Everything below describes Red's half; Blue's is the same turned about the centre.
const ROUNDABOUT := Vector2(120, 270)
const ROUNDABOUT_R := 30.0
const PARK := Rect2(-125, 240, 110, 185)
# The robot's route from the centre: up through downtown, half way round the roundabout,
# then winding through the neighbourhood and out into the country.
const ROUTE_IN := [Vector2(0, 0), Vector2(0, 100), Vector2(120, 100), Vector2(120, 240)]
const ROUTE_OUT := [Vector2(120, 330), Vector2(60, 400), Vector2(-40, 450), Vector2(-120, 520), Vector2(-120, 700)]
# The other streets outside downtown: what kind each is, and the points it runs through.
const OUTER_STREETS := [
	["country", [Vector2(-120, 210), Vector2(-140, 270), Vector2(-165, 340), Vector2(-140, 430), Vector2(-120, 520)]],
	["homes", [Vector2(120, 330), Vector2(200, 360), Vector2(250, 440), Vector2(225, 540), Vector2(130, 590), Vector2(20, 560), Vector2(-40, 450)]],
	["homes", [Vector2(200, 360), Vector2(275, 330)]],
	["homes", [Vector2(225, 540), Vector2(280, 600)]],
	["homes", [Vector2(0, 210), Vector2(10, 300), Vector2(60, 400)]],
	["homes", [Vector2(240, 210), Vector2(262, 320), Vector2(250, 440)]],
	["country", [Vector2(-240, 210), Vector2(-265, 330), Vector2(-250, 470), Vector2(-120, 520)]],
	["country", [Vector2(-290, 700), Vector2(-120, 700), Vector2(60, 725), Vector2(290, 700)]],
]
# Toy colours, but faded and a little grubby rather than fresh out of the box.
const WALLS := [Color(0.72, 0.66, 0.54), Color(0.62, 0.42, 0.34), Color(0.5, 0.56, 0.62), Color(0.7, 0.62, 0.42), Color(0.56, 0.6, 0.5), Color(0.66, 0.5, 0.44)]
const TOWERS := [Color(0.5, 0.54, 0.58), Color(0.62, 0.6, 0.55), Color(0.42, 0.46, 0.5), Color(0.58, 0.5, 0.44), Color(0.66, 0.66, 0.62)]
const ROOFS := [Color(0.5, 0.22, 0.18), Color(0.3, 0.32, 0.36), Color(0.36, 0.28, 0.2), Color(0.24, 0.36, 0.42)]
const CARS := [Color(0.7, 0.16, 0.14), Color(0.16, 0.34, 0.6), Color(0.8, 0.68, 0.2), Color(0.8, 0.8, 0.78), Color(0.2, 0.42, 0.26), Color(0.2, 0.2, 0.22)]
const BLOCK_COLOURS := [Color(0.68, 0.36, 0.34), Color(0.38, 0.48, 0.64), Color(0.72, 0.65, 0.38), Color(0.44, 0.6, 0.44), Color(0.62, 0.46, 0.62)]
var main
var layout := "town"
var half_len := 800.0
var nx := 0
var nz := 0
var heights := PackedFloat32Array()
var _roll := FastNoiseLite.new()
var _houses: Array = []  # centres (x, z) of everything solid, for steering round and hiding behind
var _route: PackedVector2Array = []   # points along the route, a few metres apart
var _route_s: PackedFloat32Array = [] # how far along each of them is
var _mats := {}
var plan := {}         # a map made in the editor (see map_file.gd); empty for the built-in maps
var made: Array = []   # what a custom map has had put on it: [kind, entry in the plan, node]
var _keep_heights := false
var _box_cells := {}   # Vector2i cell -> [[centre, half size, turn], ...] for every building that reaches into it
var props: Array = []  # every loose object on the map, in the order they were stood up
var _built: Array = []  # every building: where it is, how big, which way its front faces (for dressing it)
var _hills := FastNoiseLite.new()
var _streets: Array = []    # each {"kind": String, "pts": PackedVector2Array, "twin": bool}
var _street_cells := {}     # Vector2i cell -> [[point, street index], ...], to find streets near a place quickly

func build(p_main) -> void:
	main = p_main
	layout = "range" if main.mode["kind"] == "range" else ("town" if plan.is_empty() else "custom")
	HALF_WIDTH = TOWN_HALF_WIDTH if layout == "town" else 304.0
	half_len = main.half_len + END_MARGIN
	if layout == "custom":
		# A custom map is square; the game is told how long its Push route can be.
		HALF_WIDTH = float(plan["size"]) * 0.5
		half_len = HALF_WIDTH
		main.half_len = half_len - END_MARGIN
	_roll.seed = 77
	_roll.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_roll.frequency = 0.004
	_roll.fractal_octaves = 1
	_hills.seed = 5080
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.0065
	_hills.fractal_octaves = 2
	_lay_route()
	if layout == "town":
		_lay_streets()
	_terrain()
	_walls()
	if layout == "custom":
		for road in plan["roads"]:
			_add_street("homes", Array(curve(road.map(func(p): return Vector2(p[0], p[1])))), false)
		_road(_streets.map(func(s): return s["pts"]), Color(0.36, 0.35, 0.34))
		for entry in plan["buildings"]:
			place_building(entry)
		for entry in plan["items"]:
			place_item(entry)
		for entry in plan.get("trees", []):
			place_tree(entry)
		_surroundings()
		return
	if layout == "range":
		_road([[Vector2(0, -half_len), Vector2(0, half_len)]], Color(0.5, 0.46, 0.38))
		_range_field()
	else:
		_road(_streets.map(func(s): return s["pts"]), Color(0.36, 0.35, 0.34))
		_road_paint()
		_town()
		_outskirts()
	_trees()
	_surroundings()
	_merge_statics()


# Speed: the town is built from thousands of separate boxes (walls, roofs, windows, kerbs),
# and the graphics card draws each one on its own. Once everything is in place, the boxes that
# never move are melted together: one mesh per colour for each 120 m square of the map. Their
# collision stays as it was. Loose props (cars, benches) are left alone, as they can be knocked about.
const MERGE_CELL := 120.0

func _merge_statics() -> void:
	var piles := {}   # [cell, material, casts shadow] -> SurfaceTool
	var gone: Array = []
	for n in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n
		if m.mesh == null or not m.visible or _inside_prop(m):
			continue
		var box := m.global_transform * m.mesh.get_aabb()
		if box.size.x > MERGE_CELL or box.size.z > MERGE_CELL:
			continue  # the ground and other big pieces are one drawing already
		var centre := box.get_center()
		var cell := Vector2i(int(floor(centre.x / MERGE_CELL)), int(floor(centre.z / MERGE_CELL)))
		var shadow := m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in m.mesh.get_surface_count():
			var mat: Material = m.material_override
			if mat == null:
				mat = m.get_surface_override_material(s)
			if mat == null:
				mat = m.mesh.surface_get_material(s)
			var key := [cell, mat, shadow]
			if not piles.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				piles[key] = st
			(piles[key] as SurfaceTool).append_from(m.mesh, s, global_transform.affine_inverse() * m.global_transform)
		gone.append(m)
	for m in gone:
		m.get_parent().remove_child(m)
		m.free()
	for key in piles:
		var mi := MeshInstance3D.new()
		mi.mesh = (piles[key] as SurfaceTool).commit()
		mi.material_override = key[1]
		if not key[2]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _inside_prop(n: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != self:
		if p is RigidBody3D:
			return true
		p = p.get_parent()
	return false


# ---- the route and the streets ----

# A line through some corners, with the sharp ones rounded, as points a few metres apart.
func _dense(corners: Array, radius: float) -> PackedVector2Array:
	var line: Array = [corners[0]]
	for i in range(1, corners.size() - 1):
		var coming: Vector2 = corners[i] - corners[i - 1]
		var going: Vector2 = corners[i + 1] - corners[i]
		var r := minf(radius, minf(coming.length(), going.length()) * 0.45)
		if coming.normalized().dot(going.normalized()) > 0.9 or r < 2.0:
			line.append(corners[i])  # barely a turn, or no room to round it
			continue
		var a: Vector2 = corners[i] - coming.normalized() * r
		var b: Vector2 = corners[i] + going.normalized() * r
		for k in 7:
			var t := float(k) / 6.0
			line.append(a.lerp(corners[i], t).lerp(corners[i].lerp(b, t), t))
	line.append(corners[-1])
	var out := PackedVector2Array()
	for i in line.size() - 1:
		var from: Vector2 = line[i]
		var to: Vector2 = line[i + 1]
		var steps := maxi(1, int(ceil(from.distance_to(to) / 5.0)))
		for k in steps:
			out.append(from.lerp(to, float(k) / steps))
	out.append(line[-1])
	return out


func _lay_route() -> void:
	var corners: Array = []
	if layout != "town":
		corners = [Vector2(0, -half_len), Vector2(0, half_len)]
	else:
		var half: Array = ROUTE_IN.duplicate()
		# Half way round the roundabout, by its western side: in at the south, out at the north.
		for k in range(1, 12):
			var a := deg_to_rad(-90.0 - 15.0 * k)
			half.append(ROUNDABOUT + Vector2(cos(a), sin(a)) * ROUNDABOUT_R)
		half.append_array(ROUTE_OUT)
		for i in range(half.size() - 1, 0, -1):
			corners.append(-half[i])
		corners.append_array(half)
	_route = _dense(corners, CORNER)
	_route_s.resize(_route.size())
	var total := 0.0
	for i in _route.size():
		if i > 0:
			total += _route[i - 1].distance_to(_route[i])
		_route_s[i] = total
	# Measure from the middle, which (the two halves being the same) is the centre of the map.
	for i in _route_s.size():
		_route_s[i] -= total * 0.5


func _add_street(kind: String, corners: Array, mirrored: bool) -> void:
	var pts := _dense(corners, 45.0)
	var both: Array = [pts]
	if mirrored:
		var twin := PackedVector2Array()
		for p in pts:
			twin.append(-p)
		both.append(twin)
	for k in both.size():
		var index := _streets.size()
		_streets.append({"kind": kind, "pts": both[k], "twin": k == 1})
		for p in both[k]:
			var cell := Vector2i(int(floor(p.x / 40.0)), int(floor(p.y / 40.0)))
			if not _street_cells.has(cell):
				_street_cells[cell] = []
			_street_cells[cell].append([p, index])



func _lay_streets() -> void:
	for x in DOWNTOWN_X:
		_add_street("city", [Vector2(x, DOWNTOWN_Z[0]), Vector2(x, DOWNTOWN_Z[-1])], false)
	for z in DOWNTOWN_Z:
		_add_street("city", [Vector2(DOWNTOWN_X[0], z), Vector2(DOWNTOWN_X[-1], z)], false)
	_add_street("route", Array(_route), false)
	var ring: Array = []
	for k in 25:
		ring.append(ROUNDABOUT + Vector2(cos(k * TAU / 24.0), sin(k * TAU / 24.0)) * ROUNDABOUT_R)
	_add_street("city", ring, true)
	for s in OUTER_STREETS:
		_add_street(s[0], s[1], true)
	_add_street("strip", [Vector2(-STRIP_HALF, STRIP_Z), Vector2(STRIP_HALF, STRIP_Z)], true)
	# Roads out of downtown to the shopping centre (east) and the park (west), and a road
	# down the front of each, the same for both teams.
	for z in [-210.0, 0.0, 210.0]:
		_add_street("city", [Vector2(240, z), Vector2(MALL_X - 104.0, z)], false)
		_add_street("country", [Vector2(-240, z), Vector2(-MALL_X + 104.0, z * 1.05)], false)
	_add_street("city", [Vector2(MALL_X - 104.0, -215), Vector2(MALL_X - 104.0, 215)], false)
	_add_street("country", [Vector2(-MALL_X + 104.0, -222), Vector2(-MALL_X + 80.0, -110), Vector2(-MALL_X + 104.0, 0), Vector2(-MALL_X + 80.0, 110), Vector2(-MALL_X + 104.0, 222)], false)

# The place on the ground (x, z) that is s metres along the route.
func route_at(s: float) -> Vector2:
	var i := clampi(_route_s.bsearch(s) - 1, 0, _route.size() - 2)
	var span := _route_s[i + 1] - _route_s[i]
	return _route[i].lerp(_route[i + 1], clampf((s - _route_s[i]) / maxf(span, 0.001), 0.0, 1.0))


# Which way the route is heading there, towards Red's end.
func route_dir(s: float) -> Vector3:
	var d := route_at(s + 3.0) - route_at(s - 3.0)
	return Vector3(d.x, 0, d.y).normalized()


# How far along the route the nearest point of it is.
func nearest_s(pos: Vector3) -> float:
	var p := Vector2(pos.x, pos.z)
	var best := 0
	var best_d := INF
	for i in range(0, _route.size(), 2):
		var d := p.distance_squared_to(_route[i])
		if d < best_d:
			best_d = d
			best = i
	return _route_s[best]


func route_distance(pos: Vector3) -> float:
	var at := route_at(nearest_s(pos))
	return at.distance_to(Vector2(pos.x, pos.z))


# How far a point is from the middle of the nearest street (or the range's one track), up to
# about 60 metres. `not_street` leaves one street out of it.
func _street_distance(x: float, z: float, not_street: int = -1) -> float:
	if layout == "range":
		return absf(x)
	var p := Vector2(x, z)
	var cell := Vector2i(int(floor(x / 40.0)), int(floor(z / 40.0)))
	var best := 3600.0
	for cx in range(cell.x - 1, cell.x + 2):
		for cz in range(cell.y - 1, cell.y + 2):
			for entry in _street_cells.get(Vector2i(cx, cz), []):
				if entry[1] != not_street:
					best = minf(best, p.distance_squared_to(entry[0]))
	return sqrt(best)


# The height a vehicle's tracks stand at here: the ground's surface, or the road's if there is one.
func ground(x: float, z: float) -> float:
	return _surface(x, z) + road_lift(x, z)


# A smooth line through some points, with a point every few metres: it passes through each
# of them and bends gently between (a Catmull-Rom curve). Used for roads drawn in the editor.
func curve(corners: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := corners.size()
	if n < 2:
		return PackedVector2Array(corners)
	for i in n - 1:
		var p0: Vector2 = corners[maxi(i - 1, 0)]
		var p1: Vector2 = corners[i]
		var p2: Vector2 = corners[i + 1]
		var p3: Vector2 = corners[mini(i + 2, n - 1)]
		var steps := maxi(2, int(p1.distance_to(p2) / 5.0))
		for k in steps:
			var t := float(k) / steps
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	out.append(corners[n - 1])
	return out


# Plants a tree from a plan's entry: [x, z, size, kind (0 pine, 1 round)].
func place_tree(entry: Array) -> Node:
	var tree := Node3D.new()
	add_child(tree)
	tree.position = Vector3(entry[0], height(entry[0], entry[1]), entry[1])
	var s := float(entry[2])
	MeshUtil.cylinder(tree, 0.3 * s, 3.0 * s, Vector3(0, 1.5 * s, 0), _mat(Color(0.4, 0.26, 0.14), 0.6))
	var leaf := _mat([Color(0.14, 0.4, 0.18), Color(0.22, 0.48, 0.2), Color(0.12, 0.34, 0.2)][hash(str(entry)) % 3], 0.7)
	if int(entry[3]) == 0:
		var crown := MeshUtil.cylinder(tree, 2.2 * s, 5.5 * s, Vector3(0, 5.0 * s, 0), leaf, 0.0)
		crown.mesh.radial_segments = 7
	else:
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 2.6 * s
		sphere.height = 4.6 * s
		sphere.radial_segments = 7
		sphere.rings = 4
		ball.mesh = sphere
		ball.material_override = leaf
		ball.position = Vector3(0, 4.6 * s, 0)
		tree.add_child(ball)
	made.append(["tree", entry, tree])
	return tree


# How far above the bare ground a vehicle's tracks should ride here: the thickness of the
# road's paint if it is on a street, nothing otherwise.
func road_lift(x: float, z: float) -> float:
	return 0.26 * clampf((ROAD_HALF + 2.5 - _street_distance(x, z)) / 2.0, 0.0, 1.0)


# Moves a point out of any building it is inside (or within `margin` of), by the shortest way.
func keep_out(p: Vector3, margin: float) -> Vector3:
	for box in _box_cells.get(Vector2i(int(floor(p.x / 40.0)), int(floor(p.z / 40.0))), []):
		var local := Vector2(p.x - box[0].x, p.z - box[0].y).rotated(box[2])
		var half: Vector2 = box[1] + Vector2(margin, margin)
		if absf(local.x) < half.x and absf(local.y) < half.y:
			if half.x - absf(local.x) < half.y - absf(local.y):
				local.x = half.x * (1.0 if local.x >= 0.0 else -1.0)
			else:
				local.y = half.y * (1.0 if local.y >= 0.0 else -1.0)
			var out := local.rotated(-box[2])
			p = Vector3(box[0].x + out.x, p.y, box[0].y + out.y)
	return p


# The nearest point on any street to a place, and which way that street runs there:
# [point, direction], both (x, z).
func nearest_street(at: Vector2) -> Array:
	var best := [at, Vector2(0, 1)]
	var best_d := INF
	for street in _streets:
		var pts: PackedVector2Array = street["pts"]
		for i in range(0, pts.size() - 1, 2):
			var d := at.distance_squared_to(pts[i])
			if d < best_d:
				best_d = d
				best = [pts[i], (pts[i + 1] - pts[i]).normalized()]
	return best


# Points on the streets between `nearer` and `further` metres from a place: somewhere to drive to next.
func street_points_near(at: Vector2, nearer: float, further: float) -> Array:
	var found: Array = []
	for street in _streets:
		var pts: PackedVector2Array = street["pts"]
		for i in range(0, pts.size(), 5):
			var d := at.distance_to(pts[i])
			if d >= nearer and d <= further:
				found.append(pts[i])
	return found


func in_downtown(x: float, z: float) -> bool:
	return layout == "town" and absf(z) < DOWNTOWN_Z[-1] + 16.0 and absf(x) < DOWNTOWN_X[-1] + 16.0


# ---- the ground ----

# Flat in the city, with just the soft wrinkles of a mat; beyond it the ground rolls in low
# hills, rising gently from the edge of downtown. (Mirrored through the centre.)
# The plaza and the roundabouts sit on level ground, whatever the land round them does:
# inside each pad the height is that of its centre, blending out to the natural ground.
func _raw_height(x: float, z: float) -> float:
	if layout == "custom":
		# The plan says how high every grid point is (flat, if it has not been shaped yet).
		var saved: Array = plan["heights"]
		var i := int(round((z + half_len) / STEP)) * (int(HALF_WIDTH * 2.0 / STEP) + 1) + int(round((x + HALF_WIDTH) / STEP))
		return float(saved[i]) if i >= 0 and i < saved.size() else 0.0
	var h := _bare_height(x, z)
	if layout == "town":
		for pad in [[Vector2.ZERO, 40.0], [ROUNDABOUT, 48.0], [-ROUNDABOUT, 48.0], [Vector2(-MALL_X, 0), 30.0]]:
			var c: Vector2 = pad[0]
			var d := Vector2(x, z).distance_to(c)
			if d < float(pad[1]) + 45.0:
				h = lerpf(_bare_height(c.x, c.y), h, smoothstep(float(pad[1]), float(pad[1]) + 45.0, d))
	return h


# Is this place on one of the two airstrips?
func on_strip(pos: Vector3) -> bool:
	return layout == "town" and absf(absf(pos.z) - STRIP_Z) < 12.0 and absf(pos.x) < STRIP_HALF + 6.0


func _bare_height(x: float, z: float) -> float:
	if layout == "town":
		# The ground is levelled in a band across each end of the mat, for the airstrip.
		var level := 1.0 - smoothstep(16.0, 42.0, absf(absf(z) - STRIP_Z))
		if level > 0.0:
			return lerpf(_rolling_height(x, z), STRIP_Y, level)
	return _rolling_height(x, z)


# The park out to the west stands on hills of its own, the same north and south of the centre
# line so neither team has the better of them. (The shopping centre to the east is on the flat.)
func _park_hills(x: float, z: float) -> float:
	var into := smoothstep(-MALL_X + 110.0, -MALL_X + 10.0, x) * (1.0 - smoothstep(215.0, 300.0, absf(z)))
	return into * (_hills.get_noise_2d(x * 1.6, absf(z) * 1.6) * 13.0 + 6.0) if into > 0.0 else 0.0


func _rolling_height(x: float, z: float) -> float:
	if layout == "town" and x < -MALL_X + 112.0:
		return _rolling_height_old(x, z) + _park_hills(x, z)
	return _rolling_height_old(x, z)


func _rolling_height_old(x: float, z: float) -> float:
	var wrinkle := 0.5 * (_roll.get_noise_2d(x, z) + _roll.get_noise_2d(-x, -z)) * 3.0
	if layout == "range":
		return wrinkle * 1.6
	var hill := 0.5 * (_hills.get_noise_2d(x, z) + _hills.get_noise_2d(-x, -z))
	return wrinkle + smoothstep(HILLS_FROM, HILLS_FULL, absf(z)) * (hill * HILL_HEIGHT + HILL_HEIGHT * 0.25)

func height(x: float, z: float) -> float:
	var fx := clampf((x + HALF_WIDTH) / STEP, 0.0, float(nx - 1) - 0.001)
	var fz := clampf((z + half_len) / STEP, 0.0, float(nz - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var a := lerpf(heights[iz * nx + ix], heights[iz * nx + ix + 1], tx)
	var b := lerpf(heights[(iz + 1) * nx + ix], heights[(iz + 1) * nx + ix + 1], tx)
	return lerpf(a, b, tz)


# The closest solid thing to a point (x, z), or null if none is within reach.
func nearest_house(p: Vector2, reach: float):
	var best = null
	var best_d := reach
	for h in _houses:
		var d: float = h.distance_to(p)
		if d < best_d:
			best_d = d
			best = h
	return best


# Nudges a point (x, z) out of anything solid it would land in.
func free_spot(p: Vector2) -> Vector2:
	for i in 4:
		var h = nearest_house(p, 17.0)
		if h == null:
			break
		var away: Vector2 = p - h
		p = h + (away.normalized() if away.length() > 0.5 else Vector2(1, 0)) * 18.0
	return p


func normal(x: float, z: float) -> Vector3:
	var e := 2.0
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


func _mat(color: Color, rough: float = 0.8) -> StandardMaterial3D:
	var key := "%s %s" % [color, rough]
	if not _mats.has(key):
		_mats[key] = MeshUtil.material(color, rough)
	return _mats[key]


func _terrain() -> void:
	var first := get_child_count()
	_terrain_make()
	for i in range(first, get_child_count()):
		get_child(i).add_to_group("ground")  # so the editor can find the ground and remake it


func _terrain_make() -> void:
	nx = int(HALF_WIDTH * 2.0 / STEP) + 1
	nz = int(half_len * 2.0 / STEP) + 1
	heights.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			if not _keep_heights:
				heights[iz * nx + ix] = _raw_height(-HALF_WIDTH + ix * STEP, -half_len + iz * STEP)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var felt := Color(0.24, 0.4, 0.2) if layout == "town" else Color(0.38, 0.42, 0.24)
	var light := Color(0.36, 0.5, 0.25) if layout == "town" else Color(0.5, 0.48, 0.3)
	for iz in nz:
		for ix in nx:
			var x := -HALF_WIDTH + ix * STEP
			var z := -half_len + iz * STEP
			st.set_color(felt.lerp(light, clampf(_roll.get_noise_2d(x * 4.0, z * 4.0) * 0.5 + 0.5, 0.0, 1.0) * 0.6))
			st.set_normal(normal(x, z))
			st.add_vertex(Vector3(x, heights[iz * nx + ix], z))
	for iz in nz - 1:
		for ix in nx - 1:
			var i := iz * nx + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + nx)
			st.add_index(i + 1)
			st.add_index(i + nx + 1)
			st.add_index(i + nx)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.albedo_texture = Tex.named("grass")
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / 9.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var tri: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	tri.backface_collision = true
	shape.shape = tri
	body.add_child(shape)
	add_child(body)

	# The battlefield's edge: a skirt hanging down from its rim, to hide any crack between it
	# and the country beyond (see _surroundings).
	var skirt := SurfaceTool.new()
	skirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array = []
	for ix in nx:
		rim.append(Vector2(-HALF_WIDTH + ix * STEP, -half_len))
	for iz in nz:
		rim.append(Vector2(HALF_WIDTH, -half_len + iz * STEP))
	for ix in nx:
		rim.append(Vector2(HALF_WIDTH - ix * STEP, half_len))
	for iz in nz:
		rim.append(Vector2(-HALF_WIDTH, half_len - iz * STEP))
	for i in rim.size() - 1:
		var a: Vector2 = rim[i]
		var b: Vector2 = rim[i + 1]
		var at := Vector3(a.x, height(a.x, a.y), a.y)
		var bt := Vector3(b.x, height(b.x, b.y), b.y)
		var ab := Vector3(a.x, at.y - 14.0, a.y)
		var bb := Vector3(b.x, bt.y - 14.0, b.y)
		for v in [at, bt, ab, bt, bb, ab]:
			skirt.set_normal(Vector3.UP)
			skirt.add_vertex(v)
	var sk := MeshInstance3D.new()
	sk.mesh = skirt.commit()
	sk.material_override = MeshUtil.material(Color(0.12, 0.36, 0.15), 1.0)
	add_child(sk)


# A ribbon lying on the mat from a to b, `half` wide each side and `lift` above the ground.
# It is cut into small pieces, along and (if it is wide) across, each corner set on the
# ground beneath it, so it follows every rise and dip instead of bridging them.
func _ribbon(st: SurfaceTool, a: Vector2, b: Vector2, half: float, lift: float) -> void:
	var along := (b - a).normalized()
	var side := Vector2(-along.y, along.x)
	var steps := maxi(1, int(ceil(a.distance_to(b) / 4.0)))
	var strips := maxi(1, int(ceil(half * 2.0 / 4.0)))
	for k in steps:
		var p := a.lerp(b, float(k) / steps)
		var q := a.lerp(b, float(k + 1) / steps)
		for j in strips:
			var left := lerpf(-half, half, float(j) / strips)
			var right := lerpf(-half, half, float(j + 1) / strips)
			var corners: Array = []
			for c in [p + side * left, p + side * right, q + side * left, q + side * right]:
				corners.append(Vector3(c.x, _surface(c.x, c.y) + lift, c.y))
			for v in [corners[0], corners[2], corners[1], corners[1], corners[2], corners[3]]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)


# The height of the mat's actual surface at a point. The mat is drawn as triangles, two to
# each square of the height grid, so between grid points this differs a little from height().
func _surface(x: float, z: float) -> float:
	var fx := clampf((x + HALF_WIDTH) / STEP, 0.0, float(nx - 1) - 0.001)
	var fz := clampf((z + half_len) / STEP, 0.0, float(nz - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := heights[iz * nx + ix]
	var h10 := heights[iz * nx + ix + 1]
	var h01 := heights[(iz + 1) * nx + ix]
	var h11 := heights[(iz + 1) * nx + ix + 1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)

# Streets are printed on the mat: flat ribbons, each a list of points to run through.
func _road(streets: Array, colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each street is one unbroken strip that follows its line: at every point the road's
	# edge is square to the way the line is heading there, so a bend has no gaps on the outside.
	for street in streets:
		var n: int = street.size()
		var rows: Array = []
		for i in n:
			var along: Vector2 = (street[mini(i + 1, n - 1)] - street[maxi(i - 1, 0)]).normalized()
			var side := Vector2(-along.y, along.x) * ROAD_HALF
			var row: Array = []
			for k in 5:
				var c: Vector2 = street[i] + side * (float(k) / 2.0 - 1.0)
				row.append(Vector3(c.x, _surface(c.x, c.y) + 0.12, c.y))
			rows.append(row)
		for i in n - 1:
			for k in 4:
				for v in [rows[i][k], rows[i + 1][k], rows[i][k + 1], rows[i][k + 1], rows[i + 1][k], rows[i + 1][k + 1]]:
					st.set_normal(Vector3.UP)
					st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = MeshUtil.material(colour, 0.95, "asphalt", 6.0, true)
	add_child(mi)


# The paint on the streets: yellow dashes down the middle of each (left off where streets
# meet), and one unbroken orange line along the robot's route so it can be followed.
func _road_paint() -> void:
	var yellow := SurfaceTool.new()
	yellow.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in _streets.size():
		if _streets[index]["kind"] == "route":
			continue
		var pts: PackedVector2Array = _streets[index]["pts"]
		for i in range(0, pts.size() - 1, 2):
			if _street_distance(pts[i].x, pts[i].y, index) > 15.0:
				_ribbon(yellow, pts[i], pts[i + 1], 0.3, 0.16)
	var orange := SurfaceTool.new()
	orange.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, _route.size() - 2, 2):
		_ribbon(orange, _route[i], _route[i + 2], 0.7, 0.2)
	for pair in [[yellow, Color(0.85, 0.72, 0.2)], [orange, Color(0.95, 0.5, 0.12)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0].commit()
		mi.material_override = _mat(pair[1], 0.9)
		add_child(mi)

# Invisible walls at the mat's edge so nothing drives off it.
func _walls() -> void:
	for side in [-1.0, 1.0]:
		# (Marked as the edge of the world. Aircraft fly straight through them: see edges.)
		edges.append(_solid(Vector3(4, 200, half_len * 2.0), Vector3(side * (HALF_WIDTH + 2.0), 60, 0), 0.0, null))
		edges.append(_solid(Vector3(HALF_WIDTH * 2.0, 200, 4), Vector3(0, 60, side * (half_len + 2.0)), 0.0, null))
	for e in edges:
		e.set_meta("edge", true)


# ---- the edge of the battle ----
# Vehicles and soldiers on the ground are out of the battle in the last OOB_MARGIN metres
# before the invisible wall round the map; aircraft may go AIR_ROOM metres past the edge
# (room to line up a bombing run) before they are. Out of the battle, a 10 second countdown
# runs (main.gd _bounds_tick) and the HUD shows a RETURN TO COMBAT bar.
const OOB_MARGIN := 25.0
const AIR_ROOM := 700.0
const AIR_LIMIT := 900.0   # aircraft are stopped going any further than this past the edge
var edges: Array = []      # the invisible walls round the map

func out_of_bounds(pos: Vector3, air: bool) -> bool:
	var room := AIR_ROOM if air else -OOB_MARGIN
	return absf(pos.x) > HALF_WIDTH + room or absf(pos.z) > half_len + room


# How far inside the battle a point is (negative when outside), for steering bots back.
func inside_by(pos: Vector3, air: bool) -> float:
	var room := AIR_ROOM if air else -OOB_MARGIN
	return minf(HALF_WIDTH + room - absf(pos.x), half_len + room - absf(pos.z))


# The height of the ground anywhere, on the battlefield or out in the hills round it.
func ground_any(x: float, z: float) -> float:
	if absf(x) <= HALF_WIDTH and absf(z) <= half_len:
		return height(x, z)
	return far_height(x, z)


# A solid box. With no material it is collision only.
func _solid(size: Vector3, pos: Vector3, yaw: float, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	if mat != null:
		MeshUtil.box(body, size, Vector3.ZERO, mat)
	body.position = pos
	body.rotation.y = yaw
	add_child(body)
	return body


func _clear_of(x: float, z: float, gap: float) -> bool:
	for h in _houses:
		if Vector2(h.x - x, h.y - z).length() < gap:
			return false
	return true


# ---- the town ----

# Each district is built for Red's half of the mat and copied, turned about the centre,
# into Blue's.
func _town() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1958
	_plaza()
	_roundabout()
	_downtown(rng)
	_homes(rng)
	_park(rng)
	_country(rng)
	_dress(rng)
	_airfield()
	_lived_in()


# The new ground either side of the old town. East: a shopping centre, a long mall with a
# big store at each end, behind a car park full of cars. West: a park on rolling hills, with
# a pond, paths, benches and a good many trees. Both are the same north and south of the
# centre line, so they are as near to one team as to the other.
func _outskirts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	# ---- the shopping centre
	_building(Vector3(MALL_X + 40.0, 0, 0), Vector2(64, 190), 2, 50, Color(0.7, 0.68, 0.62), ROOFS[1], true)
	for end in [-1.0, 1.0]:
		_building(Vector3(MALL_X + 30.0, 0, end * 150.0), Vector2(84, 76), 3, 85, TOWERS[0 if end < 0.0 else 3], ROOFS[3], true)
	# The car park: strips of tarmac side by side, and rows of parked cars.
	var lot: Array = []
	for k in 5:
		lot.append([Vector2(MALL_X - 88.0 + k * 16.0, -200), Vector2(MALL_X - 88.0 + k * 16.0, 200)])
	_road(lot, Color(0.3, 0.3, 0.3))
	for row in [MALL_X - 72.0, MALL_X - 40.0, MALL_X - 24.0]:
		var z := -186.0
		while z < 190.0:
			if rng.randf() < 0.55 and absf(z) > 9.0 and absf(absf(z) - 210.0) > 12.0:
				_prop(["car", "car", "car", "van", "truck"][rng.randi() % 5], Vector2(row, z), PI * 0.5 + (PI if rng.randf() < 0.5 else 0.0), rng)
			z += 6.5
	for z in [-120.0, -40.0, 40.0, 120.0]:
		_prop("lamp", Vector2(MALL_X - 56.0, z), 0.0, rng)
		_prop("bus_stop", Vector2(MALL_X - 4.0, z + 20.0), -PI * 0.5, rng)
	_prop("bus", Vector2(MALL_X - 98.0, 60.0), 0.0, rng)
	_prop("bus", Vector2(MALL_X - 98.0, -60.0), PI, rng)
	# ---- the park
	var pond := Vector2(-MALL_X, 0)
	var water := MeshUtil.cylinder(self, 22.0, 0.1, Vector3(pond.x, height(pond.x, pond.y) + 0.2, pond.y), _mat(Color(0.22, 0.4, 0.52), 0.15))
	water.scale = Vector3(1.0, 1.0, 1.5)
	var gravel := SurfaceTool.new()
	gravel.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var path := curve([Vector2(-MALL_X + 100.0, side * 6.0), Vector2(-MALL_X + 40.0, side * 60.0), Vector2(-MALL_X - 30.0, side * 90.0), Vector2(-MALL_X - 80.0, side * 150.0), Vector2(-MALL_X - 20.0, side * 205.0), Vector2(-MALL_X + 90.0, side * 200.0)])
		for i in path.size() - 1:
			_ribbon(gravel, path[i], path[i + 1], 1.7, 0.13)
		for k in range(8, path.size() - 4, 14):
			_prop("bench", path[k] + Vector2(3.0, 0), PI * 0.5, rng)
	var walk := MeshInstance3D.new()
	walk.mesh = gravel.commit()
	walk.material_override = _mat(Color(0.66, 0.6, 0.46), 1.0)
	add_child(walk)
	var planted := 0
	var tries := 0
	while planted < 110 and tries < 2000:
		tries += 1
		var x := rng.randf_range(-TOWN_HALF_WIDTH + 12.0, -MALL_X + 96.0)
		var z := rng.randf_range(-222.0, 222.0)
		if Vector2(x, z * 0.66).distance_to(pond) < 30.0 or _street_distance(x, z) < 12.0:
			continue
		place_tree([x, z, rng.randf_range(0.8, 1.5), rng.randi() % 2])
		planted += 1


# A flat disc lying on the ground.
func _disc(at: Vector2, radius: float, lift: float, mat: Material) -> void:
	var d := MeshUtil.cylinder(self, radius, 0.06, Vector3(at.x, height(at.x, at.y) + lift, at.y), mat)
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# The plaza at the very centre, where the robot starts: paved and open, with a lamp-post
# and a planter at each corner well clear of the route.
func _plaza() -> void:
	_disc(Vector2.ZERO, 30.0, 0.14, _mat(Color(0.5, 0.48, 0.44), 0.9))
	_disc(Vector2.ZERO, 9.0, 0.17, _mat(Color(0.62, 0.56, 0.46), 0.9))
	for corner in [Vector2(21, 21), Vector2(-21, 21), Vector2(21, -21), Vector2(-21, -21)]:
		var at := Vector3(corner.x, height(corner.x, corner.y), corner.y)
		_solid(Vector3(4.0, 1.2, 4.0), at + Vector3(0, 0.6, 0), PI * 0.25, _mat(Color(0.6, 0.58, 0.54)))
		MeshUtil.cylinder(self, 1.6, 2.2, at + Vector3(0, 2.2, 0), _mat(Color(0.16, 0.4, 0.2), 0.7), 0.3)
		_houses.append(corner)


# A roundabout in each half: the ring of road is already laid; this is the island in the
# middle, a raised bed with a stone column, which the route goes half way round.
func _roundabout() -> void:
	for sign in [1.0, -1.0]:
		var c: Vector2 = ROUNDABOUT * sign
		var ground := height(c.x, c.y)
		_disc(c, ROUNDABOUT_R + ROAD_HALF, 0.11, MeshUtil.material(Color(0.36, 0.35, 0.34), 0.95, "asphalt", 6.0, true))
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var drum := CylinderShape3D.new()
		drum.radius = ROUNDABOUT_R - ROAD_HALF - 2.0
		drum.height = 5.0
		shape.shape = drum
		body.add_child(shape)
		body.position = Vector3(c.x, ground, c.y)
		add_child(body)
		MeshUtil.cylinder(body, ROUNDABOUT_R - ROAD_HALF - 1.0, 1.0, Vector3(0, 0.5, 0), _mat(Color(0.66, 0.64, 0.6)))
		MeshUtil.cylinder(body, ROUNDABOUT_R - ROAD_HALF - 2.2, 1.2, Vector3(0, 0.62, 0), _mat(Color(0.2, 0.42, 0.2), 0.9))
		MeshUtil.box(body, Vector3(3.0, 1.6, 3.0), Vector3(0, 1.9, 0), _mat(Color(0.62, 0.6, 0.56)))
		MeshUtil.cylinder(body, 0.9, 9.0, Vector3(0, 7.2, 0), _mat(Color(0.7, 0.68, 0.62)), 0.6)
		_houses.append(c)


# Downtown: every block of the grid is filled with tall buildings, six to a block, with
# alleys between them.
func _downtown(rng: RandomNumberGenerator) -> void:
	for bx in DOWNTOWN_X.size() - 1:
		for bz in range(2, DOWNTOWN_Z.size() - 1):  # Red's side of the centre line; Blue's is the copy
			var x0: float = DOWNTOWN_X[bx] + SETBACK
			var x1: float = DOWNTOWN_X[bx + 1] - SETBACK
			var z0: float = DOWNTOWN_Z[bz] + SETBACK
			var z1: float = DOWNTOWN_Z[bz + 1] - SETBACK
			# The gaps between a block's buildings are either closed up altogether or wide
			# enough to drive a tank through with room to spare: never a tight squeeze.
			var gap_x := 0.0 if rng.randf() < 0.5 else 11.0   # the alleys running through the block one way...
			var gap_z := 11.0 if (gap_x == 0.0 or rng.randf() < 0.5) else 0.0  # ...and the one running the other
			for lx in 3:
				for lz in 2:
					var c := Vector2(lerpf(x0, x1, (lx + 0.5) / 3.0), lerpf(z0, z1, (lz + 0.5) / 2.0))
					var size := Vector2((x1 - x0) / 3.0 - gap_x + 0.05, (z1 - z0) / 2.0 - gap_z + 0.05)
					var floors := rng.randi_range(4, 9)
					var style := 96 if rng.randf() < 0.05 else 85
					var wall: Color = TOWERS[rng.randi() % TOWERS.size()]
					var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
					if c.length() < 46.0:
						continue  # the plaza
					for sign in [1.0, -1.0]:
						_building(Vector3(c.x * sign, 0, c.y * sign), size, floors, style, wall, roof, (lx == 0) == (sign > 0.0))


# The neighbourhood: houses, and the odd corner shop, strung along the winding streets, each
# turned to face its street, with a gap between it and the next.
func _homes(rng: RandomNumberGenerator) -> void:
	for index in _streets.size():
		var street: Dictionary = _streets[index]
		if street["twin"] or not (street["kind"] == "homes" or street["kind"] == "route"):
			continue
		var pts: PackedVector2Array = street["pts"]
		var since := 30.0
		for i in range(1, pts.size() - 1):
			since += pts[i].distance_to(pts[i - 1])
			if since < 27.0 or pts[i].y < DOWNTOWN_Z[-1] + 30.0:
				continue
			since = rng.randf_range(-4.0, 3.0)
			var along := (pts[i + 1] - pts[i - 1]).normalized()
			var out := Vector2(-along.y, along.x)
			for side in [-1.0, 1.0]:
				var p: Vector2 = pts[i] + out * side * 22.5
				if rng.randf() < 0.14 or absf(p.x) > HALF_WIDTH - 18.0 or p.y > half_len - 18.0:
					continue
				if _street_distance(p.x, p.y) < 18.0 or not _clear_of(p.x, p.y, 21.0) or PARK.grow(10.0).has_point(p) or p.distance_to(ROUNDABOUT) < ROUNDABOUT_R + 24.0:
					continue
				var size := Vector2(rng.randf_range(11.0, 14.0), rng.randf_range(13.0, 17.0))
				var style := 50 if rng.randf() < 0.12 else 10
				var wall: Color = WALLS[rng.randi() % WALLS.size()]
				var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
				var floors := 1 + (rng.randi() % 2)
				var yaw := atan2(-out.y, out.x)  # the house's own X axis points away across the street
				var fenced := style < 40 and rng.randf() < 0.6
				for sign in [1.0, -1.0]:
					_building(Vector3(p.x * sign, 0, p.y * sign), size, floors, style, wall, roof, side > 0.0, yaw + (0.0 if sign > 0.0 else PI))
					if fenced:
						# A garden fence along the front of the plot, with a gap for the path.
						for k in [-2, -1, 1, 2]:
							var post: Vector2 = (pts[i] + out * side * 12.5 + along * (k * 4.1)) * sign
							_prop("picket", post, atan2(-along.y, along.x), rng)


# One building. style picks the kind (0-39 a house with a pitched roof, 40-77 a shop with an
# awning, 78-93 an office block, 94-99 the hospital). faces_west says whether its front is on
# its own -X side; yaw turns the whole thing.
func _building(pos: Vector3, size: Vector2, floors: int, style: int, wall: Color, roof: Color, faces_west: bool, yaw: float = 0.0) -> void:
	pos.y = height(pos.x, pos.z)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		pos.y = minf(pos.y, height(pos.x + corner.x * size.x * 0.5, pos.z + corner.y * size.y * 0.5))
	var tall := float(floors) * 3.6 + 0.6
	var found := 6.0  # below ground, so nothing shows under it on a slope
	if style >= 94:
		wall = Color(0.84, 0.84, 0.8)
	var body := _solid(Vector3(size.x, tall + found, size.y), pos + Vector3(0, (tall - found) * 0.5, 0), yaw, _mat(wall))
	var ground := -(tall - found) * 0.5
	var top := ground + tall
	var front := -1.0 if faces_west else 1.0
	var glass := _mat(Color(0.2, 0.28, 0.34), 0.25)
	var trim := _mat(wall.darkened(0.3))
	if floors > 3:
		# A tall block: strips of window running its full height, and a ledge at each few floors.
		for k in 3:
			var off := (float(k) - 1.0) * 0.3
			for side in [-1.0, 1.0]:
				MeshUtil.box(body, Vector3(0.12, tall - 4.2, size.y * 0.18), Vector3(side * (size.x * 0.5 + 0.02), ground + 3.6 + (tall - 4.2) * 0.5, off * size.y), glass)
				MeshUtil.box(body, Vector3(size.x * 0.18, tall - 4.2, 0.12), Vector3(off * size.x, ground + 3.6 + (tall - 4.2) * 0.5, side * (size.y * 0.5 + 0.02)), glass)
		MeshUtil.box(body, Vector3(size.x + 0.5, 0.4, size.y + 0.5), Vector3(0, ground + 3.4, 0), trim)
	else:
		# A band of window on each floor, all round.
		for f in floors:
			var wy := ground + 2.2 + float(f) * 3.6
			for side in [-1.0, 1.0]:
				MeshUtil.box(body, Vector3(0.12, 1.5, size.y * 0.78), Vector3(side * (size.x * 0.5 + 0.02), wy, 0), glass)
				MeshUtil.box(body, Vector3(size.x * 0.7, 1.5, 0.12), Vector3(0, wy, side * (size.y * 0.5 + 0.02)), glass)
	MeshUtil.box(body, Vector3(0.16, 2.3, 1.5), Vector3(front * (size.x * 0.5 + 0.04), ground + 1.15, size.y * 0.28), trim)
	if style < 40:
		# A pitched roof, its ridge running the length of the house.
		# (extrude_x runs the ridge across X; these houses are longer in Z, so it is turned.)
		var gable := MeshInstance3D.new()
		gable.position.y = top
		gable.material_override = _mat(roof)
		gable.mesh = MeshUtil.extrude_x(PackedVector2Array([Vector2(-size.x * 0.5 - 0.6, 0), Vector2(size.x * 0.5 + 0.6, 0), Vector2(size.x * 0.5 + 0.6, 0.3), Vector2(0, size.x * 0.34), Vector2(-size.x * 0.5 - 0.6, 0.3)]), size.y + 1.2)
		gable.rotation.y = PI * 0.5
		body.add_child(gable)
		MeshUtil.box(body, Vector3(1.2, 2.2, 1.2), Vector3(size.x * 0.2, top + size.x * 0.22, -size.y * 0.25), trim)  # chimney
	else:
		# A flat roof with a low wall round it and something on top.
		MeshUtil.box(body, Vector3(size.x + 0.5, 0.5, size.y + 0.5), Vector3(0, top + 0.25, 0), _mat(roof))
		MeshUtil.box(body, Vector3(size.x * 0.3, 1.0, size.y * 0.2), Vector3(-size.x * 0.15, top + 1.0, size.y * 0.2), _mat(Color(0.55, 0.56, 0.56)))
		if style < 78:
			var awning := MeshUtil.box(body, Vector3(2.4, 0.18, size.y * 0.8), Vector3(front * (size.x * 0.5 + 1.0), ground + 3.1, 0), _mat(roof.lerp(Color(0.8, 0.3, 0.2), 0.5)))
			awning.rotation.z = -front * 0.3
		elif style >= 94:
			var red := _mat(Color(0.75, 0.12, 0.1))
			MeshUtil.box(body, Vector3(size.x * 0.5, 0.2, size.x * 0.16), Vector3(0, top + 0.6, 0), red)
			MeshUtil.box(body, Vector3(size.x * 0.16, 0.2, size.x * 0.5), Vector3(0, top + 0.6, 0), red)
	var reach := int(ceil((size.length() * 0.5 + 3.0) / 40.0))
	var home := Vector2i(int(floor(pos.x / 40.0)), int(floor(pos.z / 40.0)))
	for cx in range(home.x - reach, home.x + reach + 1):
		for cz in range(home.y - reach, home.y + reach + 1):
			if not _box_cells.has(Vector2i(cx, cz)):
				_box_cells[Vector2i(cx, cz)] = []
			_box_cells[Vector2i(cx, cz)].append([Vector2(pos.x, pos.z), size * 0.5, yaw])
	_built.append({"at": Vector2(pos.x, pos.z), "y": pos.y, "size": size, "yaw": yaw, "floors": floors, "style": style, "front": front, "wall": wall})
	_houses.append(Vector2(pos.x, pos.z))
	if size.y > 19.0 or size.x > 19.0:
		var long := Vector2(0, size.y * 0.3) if size.y >= size.x else Vector2(size.x * 0.3, 0)
		for end in [-1.0, 1.0]:
			_houses.append(Vector2(pos.x, pos.z) + long.rotated(-yaw) * end)


# The park: a pond, a bandstand, gravel paths and benches. (Its trees come with the rest.)
func _park(_rng: RandomNumberGenerator) -> void:
	var gravel := SurfaceTool.new()
	gravel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := PARK.get_center()
	var paths: Array = [
		[Vector2(PARK.position.x, PARK.position.y + 12), c + Vector2(0, -50), c + Vector2(18, 0), c + Vector2(0, 55), Vector2(PARK.end.x, PARK.end.y - 8)],
		[Vector2(PARK.end.x, PARK.position.y + 30), c + Vector2(0, -50)],
		[c + Vector2(0, 55), Vector2(PARK.position.x, PARK.end.y - 20)]]
	for sign in [1.0, -1.0]:
		for path in paths:
			var pts := _dense(path.map(func(p): return p * sign), 30.0)
			for i in pts.size() - 1:
				_ribbon(gravel, pts[i], pts[i + 1], 1.6, 0.13)
		var pond: Vector2 = (c + Vector2(-16, 4)) * sign
		var water := MeshUtil.cylinder(self, 15.0, 0.1, Vector3(pond.x, height(pond.x, pond.y) + 0.16, pond.y), _mat(Color(0.22, 0.4, 0.52), 0.15))
		water.scale = Vector3(1.0, 1.0, 1.7)
		# The bandstand: eight posts and a pointed roof on a low plinth.
		var stand: Vector2 = (c + Vector2(4, -62)) * sign
		var base := Vector3(stand.x, height(stand.x, stand.y), stand.y)
		_solid(Vector3(8.0, 1.0, 8.0), base + Vector3(0, 0.5, 0), PI * 0.125, _mat(Color(0.7, 0.68, 0.62)))
		for k in 8:
			var a := k * TAU / 8.0
			MeshUtil.cylinder(self, 0.18, 3.4, base + Vector3(cos(a) * 3.6, 2.7, sin(a) * 3.6), _mat(Color(0.86, 0.86, 0.82)))
		var cap := MeshUtil.cylinder(self, 5.2, 2.4, base + Vector3(0, 5.6, 0), _mat(ROOFS[0]), 0.2)
		cap.mesh.radial_segments = 8
		_houses.append(stand)
		for k in 6:
			var bench: Vector2 = (c + Vector2(22 if k % 2 == 0 else -40, -70 + k * 26)) * sign
			MeshUtil.box(self, Vector3(0.7, 0.6, 2.6), Vector3(bench.x, height(bench.x, bench.y) + 0.3, bench.y), _mat(Color(0.42, 0.3, 0.2)))
	var mi := MeshInstance3D.new()
	mi.mesh = gravel.commit()
	mi.material_override = _mat(Color(0.66, 0.6, 0.46), 1.0)
	add_child(mi)


# The country at each end: a farm with a big barn beside the road, and round hay bales left
# out in the fields.
func _country(rng: RandomNumberGenerator) -> void:
	for sign in [1.0, -1.0]:
		_building(Vector3(-205 * sign, 0, 645 * sign), Vector2(16, 26), 2, 10, Color(0.56, 0.2, 0.16), Color(0.3, 0.3, 0.32), sign > 0.0, 0.2 + (0.0 if sign > 0.0 else PI))
		_building(Vector3(-235 * sign, 0, 610 * sign), Vector2(11, 13), 1, 10, WALLS[0], ROOFS[0], sign > 0.0, 0.2 + (0.0 if sign > 0.0 else PI))
		_building(Vector3(150 * sign, 0, 680 * sign), Vector2(12, 15), 1, 10, WALLS[3], ROOFS[2], sign < 0.0, -0.15 + (0.0 if sign > 0.0 else PI))
	var placed := 0
	var tries := 0
	while placed < 16 and tries < 600:
		tries += 1
		var x := rng.randf_range(-HALF_WIDTH + 30.0, HALF_WIDTH - 30.0)
		var z := rng.randf_range(560.0, half_len - 30.0)
		if _street_distance(x, z) < 14.0 or not _clear_of(x, z, 16.0):
			continue
		var yaw := rng.randf_range(0.0, PI)
		for sign in [1.0, -1.0]:
			var at := Vector3(x * sign, height(x * sign, z * sign), z * sign)
			_prop("bale", Vector2(at.x, at.z), yaw, rng)
		placed += 1


# Puts up a building from a plan's entry (see map_file.gd) and returns it.
func place_building(entry: Array) -> Node:
	var kind := int(entry[5])
	var walls: Array = TOWERS if kind == 2 else WALLS
	_building(Vector3(entry[0], 0, entry[1]), Vector2(entry[2], entry[3]), int(entry[4]), [10, 50, 85][kind], walls[int(entry[7]) % walls.size()], ROOFS[int(entry[8]) % ROOFS.size()], true, float(entry[6]))
	var node := get_child(get_child_count() - 1)
	made.append(["building", entry, node])
	return node


# Stands a prefab from a plan's entry on the ground and returns it.
func place_item(entry: Array) -> Node:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(entry))
	_prop(String(entry[0]), Vector2(entry[1], entry[2]), float(entry[3]), rng)
	var node := get_child(get_child_count() - 1)
	made.append(["item", entry, node])
	return node


# Makes the ground again from `heights` as they now stand (the editor changes them).
func reshape() -> void:
	for n in get_tree().get_nodes_in_group("ground"):
		n.free()
	_keep_heights = true
	_terrain()
	_keep_heights = false


# Stands one of the ready-made pieces (prefabs.gd) on the ground at a place, turned to yaw.
func _prop(id: String, at: Vector2, yaw: float, rng: RandomNumberGenerator) -> void:
	var p := Prefabs.build(id, rng)
	p.position = Vector3(at.x, _surface(at.x, at.y) + 0.03, at.y)
	p.rotation.y = yaw
	p.prop_id = props.size()  # the map is built the same on every PC, so the numbers match
	props.append(p)
	add_child(p)


# Everything loose that makes the town look lived in, all of it things a vehicle drives
# straight through and a gun knocks flying: street lamps, benches, bins and signs downtown;
# cars, vans, trucks and buses parked at the kerb; sandbags, crates and barrels along the
# robot's route for cover; rail fences beside the country road.
func _dress(rng: RandomNumberGenerator) -> void:
	var taken: Array = []  # where something already stands, so things are not stacked
	var free := func(p: Vector2, gap: float) -> bool:
		for q in taken:
			if p.distance_to(q) < gap:
				return false
		return _clear_of(p.x, p.y, 8.0)
	for index in _streets.size():
		var street: Dictionary = _streets[index]
		var pts: PackedVector2Array = street["pts"]
		if street["twin"] or pts.size() < 12:
			continue
		var kind: String = street["kind"]
		var n := 0
		for i in range(4, pts.size() - 4, 5):
			n += 1
			var along := (pts[i + 1] - pts[i - 1]).normalized()
			var out := Vector2(-along.y, along.x) * (1.0 if n % 2 == 0 else -1.0)
			# Nothing is stood where streets meet. Downtown that means the corners of the grid
			# (the route runs along grid streets there, so "another street nearby" would rule
			# out its whole length); elsewhere, anywhere another street comes close.
			var downtown := in_downtown(pts[i].x, pts[i].y)
			var crossing := pts[i].length() < 42.0
			if downtown:
				for gx in DOWNTOWN_X:
					for gz in DOWNTOWN_Z:
						crossing = crossing or (absf(pts[i].x - gx) < 21.0 and absf(pts[i].y - gz) < 21.0)
				if kind == "city" and route_distance(Vector3(pts[i].x, 0, pts[i].y)) < 5.0:
					continue  # this stretch is the route's to dress
			else:
				crossing = crossing or _street_distance(pts[i].x, pts[i].y, index) < 21.0
			var roll := rng.randf()
			var id := ""
			var off := ROAD_HALF + 2.8
			var yaw := atan2(-along.x, -along.y) + (PI if rng.randf() < 0.5 else 0.0)
			if kind == "city":
				if crossing:
					continue
				if n % 2 == 0:
					id = "lamp"
					off = ROAD_HALF + 1.4
					yaw = atan2(out.x, out.y)  # its arm reaches out over the street
				elif roll < 0.26:
					id = ["bench", "bin", "sign", "bus_stop"][rng.randi() % 4]
					off = ROAD_HALF + 4.6
					yaw = atan2(out.x, out.y)
				elif roll < 0.62:
					id = ["car", "car", "car", "van", "truck", "bus"][rng.randi() % 6]
			elif kind == "route":
				# Cover every so often, set across the verge so a vehicle can tuck in behind it.
				if crossing:
					continue
				if n % 3 == 0:
					id = ["sandbags", "sandbags", "crates", "barrels", "truck", "bus"][rng.randi() % 6]
					if id == "sandbags" or id == "crates" or id == "barrels":
						off = ROAD_HALF + 3.6
						yaw = atan2(-out.y, out.x)
				elif downtown and n % 2 == 0:
					id = "lamp"
					off = ROAD_HALF + 1.4
					yaw = atan2(out.x, out.y)
				elif downtown and roll < 0.45:
					id = ["car", "car", "van", "bench", "bin", "bus_stop"][rng.randi() % 6]
					if id == "bench" or id == "bin" or id == "bus_stop":
						off = ROAD_HALF + 4.6
						yaw = atan2(out.x, out.y)
				elif roll < 0.2:
					id = ["car", "van"][rng.randi() % 2]
			elif kind == "homes":
				if not crossing and roll < 0.3:
					id = ["car", "car", "van", "bin"][rng.randi() % 4]
			elif kind == "country":
				if not crossing and roll < 0.5:
					id = "fence"
					off = ROAD_HALF + 3.0
					yaw = atan2(-along.y, along.x)
				elif not crossing and roll < 0.58:
					id = ["truck", "barrels", "crates"][rng.randi() % 3]
			if id == "":
				continue
			var p := pts[i] + out * off
			if _street_distance(p.x, p.y) < ROAD_HALF + 0.9 or absf(p.x) > HALF_WIDTH - 10.0 or not free.call(p, 5.0 if (id == "lamp" or id == "fence") else 9.0):
				continue
			taken.append(p)
			taken.append(-p)
			for sign in [1.0, -1.0]:
				if sign < 0.0 and (kind == "city" or kind == "route") and p.length() < 1.0:
					continue
				_prop(id, p * sign, yaw + (0.0 if sign > 0.0 else PI), rng)
				if id == "fence":
					for k in [1, 2]:
						_prop(id, (p + along * (k * 4.05)) * sign, yaw + (0.0 if sign > 0.0 else PI), rng)

# ---- making the town look lived in ----
# _dress put things along the streets. This goes round the buildings themselves and puts
# what belongs where: paving and kerbs under the town centre; behind each shop or block,
# its back door, bins, a skip, air-conditioning boxes on the wall, drainpipes and a fire
# escape; in front, a sign over the door, planters, a cafe table or a newspaper box; on the
# roofs, tanks, vents and aerials; round each house, a porch, a mailbox, dustbins, a flower
# bed and something in the back garden; and on the roads, crossings and manhole covers.
# Small fixed things are gathered by colour into a few meshes (_bit); things that can be
# knocked over are props like any other.

var _bits := {}  # colour -> the pile of small fixed details in that colour

# A small fixed box of detail, turned about the upright by `yaw`.
# Each team's airfield, so it is more than a strip of road: two hangars and a control tower on
# the town side of the runway's west half, a concrete apron in front of them, lights down both
# edges of the runway, a windsock, and a chain-link fence round the lot (with gaps where roads
# cross it). Everything stands well clear of the runway itself, so nothing is in the way of
# a plane landing or taking off. Built for Red's end (+z) and mirrored for Blue's.
func _airfield() -> void:
	var concrete := Color(0.55, 0.54, 0.5)
	var steel := Color(0.42, 0.44, 0.42)
	var dark := Color(0.14, 0.15, 0.16)
	for side in [1.0, -1.0]:
		var at := func(x: float, z: float) -> Vector3: return Vector3(x, height(x, z * side), z * side)
		# The apron in front of the hangars, out to the runway.
		var apron: Vector3 = at.call(-92.0, 748.0)
		_bit(Vector3(120.0, 0.1, 13.0), apron + Vector3(0, 0.07, 0), 0.0, concrete)
		# Two hangars, their big doors facing the runway.
		for hx in [-130.0, -94.0]:
			var g: Vector3 = at.call(hx, 731.0)
			var wall := _mat(Color(0.5, 0.52, 0.48))
			_solid(Vector3(30.0, 12.0, 20.0), g + Vector3(0, 3.0, 0), 0.0, wall)
			var roof := MeshUtil.cylinder(self, 15.0, 20.0, g + Vector3(0, 9.0, 0), _mat(steel, 0.6))
			roof.rotation.x = PI * 0.5
			roof.scale = Vector3(1.0, 1.0, 0.42)  # a low curved roof
			_solid(Vector3(28.0, 5.0, 18.0), g + Vector3(0, 11.0, 0), 0.0, null)  # (so the roof is solid too)
			var face: float = g.z + side * 10.08
			_bit(Vector3(24.0, 7.6, 0.25), Vector3(g.x, g.y + 3.8, face), 0.0, dark)  # the doors
			for k in 5:
				_bit(Vector3(0.12, 7.6, 0.3), Vector3(g.x - 9.6 + k * 4.8, g.y + 3.8, face), 0.0, steel)  # door panels
			_bit(Vector3(25.0, 0.5, 0.4), Vector3(g.x, g.y + 7.85, face), 0.0, steel)  # door track
		# The control tower: a concrete shaft, a glass cab with a walkway round it, an aerial.
		var t: Vector3 = at.call(-55.0, 730.0)
		_solid(Vector3(5.0, 17.0, 5.0), t + Vector3(0, 5.5, 0), 0.0, _mat(concrete))
		_solid(Vector3(8.0, 3.2, 8.0), t + Vector3(0, 15.6, 0), 0.0, _mat(Color(0.2, 0.28, 0.34), 0.25))
		_bit(Vector3(9.4, 0.5, 9.4), t + Vector3(0, 17.45, 0), 0.0, concrete)       # roof
		_bit(Vector3(10.0, 0.25, 10.0), t + Vector3(0, 13.95, 0), 0.0, concrete)    # walkway
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			_bit(Vector3(0.25, 3.2, 0.25), t + Vector3(c.x * 4.0, 15.6, c.y * 4.0), 0.0, dark)  # cab corners
		_bit(Vector3(0.15, 5.0, 0.15), t + Vector3(2.5, 20.2, 2.5), 0.0, steel)     # aerial
		_bit(Vector3(1.2, 0.8, 1.6), t + Vector3(-2.0, 18.1, -1.5), 0.0, steel)    # radar box
		# A windsock on a pole beside the runway, blowing out across it.
		var w: Vector3 = at.call(10.0, 742.0)
		_bit(Vector3(0.14, 6.0, 0.14), w + Vector3(0, 3.0, 0), 0.0, steel)
		var sock := MeshUtil.cylinder(self, 0.45, 2.6, w + Vector3(1.3, 5.8, 0), _mat(Color(0.9, 0.4, 0.1), 0.7), 0.18)
		sock.rotation.z = PI * 0.5 + 0.25
		# Lights down both edges of the runway.
		for k in 19:
			var lx := -135.0 + k * 15.0
			for e in [-9.5, 9.5]:
				var l: Vector3 = at.call(lx, PushMap.STRIP_Z + e)
				_bit(Vector3(0.3, 0.35, 0.3), l + Vector3(0, 0.25, 0), 0.0, Color(0.95, 0.85, 0.5) if k % 2 == 0 else Color(0.9, 0.9, 0.88))
		# The fence: posts every 3 m, a rail along the top and bottom, chain-link between.
		var line := [Vector2(-165, 716), Vector2(-30, 716), Vector2(-30, 746), Vector2(165, 746), Vector2(165, 794), Vector2(-165, 794), Vector2(-165, 716)]
		var mesh_mat := StandardMaterial3D.new()
		mesh_mat.albedo_color = Color(0.5, 0.52, 0.5, 0.35)
		mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		for i in line.size() - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var n := int(a.distance_to(b) / 3.0)
			for k in n:
				var p := a.lerp(b, (k + 0.5) / n)
				if _street_distance(p.x, p.y * side) < 11.0:
					continue  # leave a gap where a road comes through
				var base: Vector3 = at.call(p.x, p.y)
				var dir := (b - a).normalized()
				var yaw := atan2(dir.x, dir.y * side)
				var span := a.distance_to(b) / n
				_bit(Vector3(0.09, 2.3, 0.09), base + Vector3(0, 1.15, 0), 0.0, steel)
				_bit(Vector3(0.05, 0.05, span), base + Vector3(0, 2.25, 0), yaw, steel)
				_bit(Vector3(0.05, 0.05, span), base + Vector3(0, 0.15, 0), yaw, steel)
				var panel := MeshUtil.box(self, Vector3(0.02, 2.1, span), base + Vector3(0, 1.2, 0), mesh_mat)
				panel.rotation.y = yaw
				panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Keep bots and placed things off the hangars and the tower.
		for hx in [-130.0, -94.0]:
			_houses.append(Vector2(hx, 731.0 * side))
		_houses.append(Vector2(-55.0, 730.0 * side))


func _bit(size: Vector3, pos: Vector3, yaw: float, colour: Color, tilt: float = 0.0) -> void:
	if not _bits.has(colour):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_bits[colour] = st
	var box := BoxMesh.new()
	box.size = size
	(_bits[colour] as SurfaceTool).append_from(box, 0, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt), pos))


# Whether a loose thing may stand here: off the roads, on the map, and not inside a building.
func _room_for(p: Vector2, taken: Array, gap: float) -> bool:
	if absf(p.x) > HALF_WIDTH - 8.0 or absf(p.y) > half_len - 8.0 or _street_distance(p.x, p.y) < ROAD_HALF + 1.3:
		return false
	var p3 := Vector3(p.x, 0, p.y)
	if keep_out(p3, 0.5) != p3:
		return false
	for q in taken:
		if p.distance_to(q) < gap:
			return false
	return true


func _lived_in() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var taken: Array = []
	for p in props:
		taken.append(Vector2(p.position.x, p.position.z))
	var concrete := Color(0.5, 0.5, 0.48)
	var kerb := Color(0.62, 0.62, 0.6)
	var iron := Color(0.2, 0.21, 0.22)
	var white := Color(0.88, 0.88, 0.84)
	# ---- the town centre is paved: each block a slab of concrete with a paler pavement round its edge
	var paving := SurfaceTool.new()
	paving.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walks := SurfaceTool.new()
	walks.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix in DOWNTOWN_X.size() - 1:
		for iz in DOWNTOWN_Z.size() - 1:
			var x0: float = float(DOWNTOWN_X[ix]) + ROAD_HALF
			var x1: float = float(DOWNTOWN_X[ix + 1]) - ROAD_HALF
			var z0: float = float(DOWNTOWN_Z[iz]) + ROAD_HALF
			var z1: float = float(DOWNTOWN_Z[iz + 1]) - ROAD_HALF
			var zc := (z0 + z1) * 0.5
			_ribbon(paving, Vector2(x0, zc), Vector2(x1, zc), (z1 - z0) * 0.5, 0.07)
			_ribbon(walks, Vector2(x0, z0 + 2.0), Vector2(x1, z0 + 2.0), 2.0, 0.12)
			_ribbon(walks, Vector2(x0, z1 - 2.0), Vector2(x1, z1 - 2.0), 2.0, 0.12)
			_ribbon(walks, Vector2(x0 + 2.0, z0), Vector2(x0 + 2.0, z1), 2.0, 0.12)
			_ribbon(walks, Vector2(x1 - 2.0, z0), Vector2(x1 - 2.0, z1), 2.0, 0.12)
	for pair in [[paving, concrete], [walks, kerb]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0].commit()
		mi.material_override = _mat(pair[1], 0.95)
		add_child(mi)
	# ---- crossings at every corner of the grid, and a manhole cover out in each junction
	for gx in DOWNTOWN_X:
		for gz in DOWNTOWN_Z:
			var y := _surface(gx, gz) + 0.3
			for arm in 4:
				var out := Vector2(0, 1).rotated(arm * PI * 0.5)
				var across := Vector2(out.y, -out.x)
				var mid: Vector2 = Vector2(gx, gz) + out * (ROAD_HALF + 3.0)
				if absf(mid.x) > 250.0 or absf(mid.y) > 220.0:
					continue  # no street leaves the grid here
				for k in 6:
					var stripe: Vector2 = mid + across * ((float(k) - 2.5) * 2.4)
					_bit(Vector3(1.1, 0.02, 3.0), Vector3(stripe.x, _surface(stripe.x, stripe.y) + 0.29, stripe.y), atan2(out.x, out.y), white)
			_bit(Vector3(1.0, 0.02, 1.0), Vector3(gx + 3.0, y, gz - 2.5), 0.4, iron)
			# A hydrant on one corner and a post box or telephone box on another.
			for corner in [[Vector2(1, 1), "hydrant"], [Vector2(-1, -1), ["mailbox", "phone", "newsbox"][rng.randi() % 3]]]:
				var at: Vector2 = Vector2(gx, gz) + (corner[0] as Vector2) * (ROAD_HALF + 2.2)
				if _room_for(at, taken, 3.0) and rng.randf() < 0.7:
					taken.append(at)
					_prop(String(corner[1]), at, rng.randf() * TAU, rng)
	# ---- every building
	for b in _built:
		var at: Vector2 = b["at"]
		var size: Vector2 = b["size"]
		var yaw: float = b["yaw"]
		var front: float = b["front"]
		var base: float = float(b["y"])
		var floors: int = b["floors"]
		var style: int = b["style"]
		var top: float = base + float(floors) * 3.6 + 0.6
		# A point given in the building's own frame (x across to its front or back, z along it), as a place on the map.
		var spot := func(lx: float, lz: float) -> Vector2:
			return at + Vector2(lx, lz).rotated(-yaw)
		var wall3 := func(lx: float, y: float, lz: float) -> Vector3:
			var p: Vector2 = spot.call(lx, lz)
			return Vector3(p.x, y, p.y)
		var hx := size.x * 0.5
		var hz := size.y * 0.5
		var dark: Color = (b["wall"] as Color).darkened(0.45)
		if style < 40:
			# A house. Porch over the door, flower bed under the front windows.
			var door_z := size.y * 0.28
			_bit(Vector3(1.4, 0.2, 2.2), wall3.call(front * (hx + 0.7), base + 0.1, door_z), yaw, concrete)
			_bit(Vector3(1.6, 0.1, 2.6), wall3.call(front * (hx + 0.8), base + 2.6, door_z), yaw, dark, 0.0)
			for post in [-1.1, 1.1]:
				_bit(Vector3(0.1, 2.5, 0.1), wall3.call(front * (hx + 1.4), base + 1.3, door_z + post), yaw, white)
			_bit(Vector3(0.7, 0.25, size.y * 0.42), wall3.call(front * (hx + 0.45), base + 0.12, -size.y * 0.2), yaw, Color(0.25, 0.18, 0.12))
			for k in 5:
				_bit(Vector3(0.22, 0.22, 0.22), wall3.call(front * (hx + 0.45), base + 0.36, -size.y * 0.2 + (k - 2) * size.y * 0.08), yaw + k, [Color(0.85, 0.2, 0.3), Color(0.95, 0.8, 0.2), Color(0.9, 0.9, 0.95), Color(0.75, 0.35, 0.7)][k % 4])
			_bit(Vector3(0.9, 1.2, 0.6), wall3.call(-front * hx * 0.3, top + 0.3, 0.0), yaw, dark)  # (a dormer or roof light)
			# Loose things: a mailbox out the front, dustbins down the side, something in the back garden.
			var things := [[spot.call(front * (hx + 6.0), door_z + 2.0), "mailbox"], [spot.call(front * hx * 0.5, hz + 1.2), "trash"],
				[spot.call(-front * (hx + 5.0 + rng.randf() * 3.0), rng.randf_range(-hz, hz) * 0.6), ["swing", "bbq", "doghouse", "washing", "woodpile", "table"][rng.randi() % 6]]]
			if rng.randf() < 0.5:
				things.append([spot.call(-front * (hx + 3.5), hz * 0.8), ["washing", "woodpile", "bbq", "bikes"][rng.randi() % 4]])
			for thing in things:
				if _room_for(thing[0], taken, 2.5):
					taken.append(thing[0])
					_prop(String(thing[1]), thing[0], yaw + rng.randf_range(-0.3, 0.3) + (PI * 0.5 if thing[1] == "washing" else 0.0), rng)
			continue
		# A shop, an office or a block of flats.
		# The back: a door with a step and a lamp over it, air-conditioning boxes, drainpipes.
		var back := -front
		var door_at := rng.randf_range(-hz * 0.5, hz * 0.5)
		_bit(Vector3(0.14, 2.2, 1.2), wall3.call(back * (hx + 0.05), base + 1.1, door_at), yaw, dark)
		_bit(Vector3(1.0, 0.18, 1.6), wall3.call(back * (hx + 0.5), base + 0.09, door_at), yaw, concrete)
		_bit(Vector3(0.3, 0.14, 0.3), wall3.call(back * (hx + 0.2), base + 2.6, door_at), yaw, Color(0.95, 0.9, 0.6))
		for k in 1 + rng.randi() % 3:
			var along := rng.randf_range(-hz * 0.8, hz * 0.8)
			var up := base + 2.6 + float(rng.randi() % maxi(floors, 1)) * 3.6
			_bit(Vector3(0.6, 0.7, 1.0), wall3.call(back * (hx + 0.32), up, along), yaw, Color(0.72, 0.73, 0.72))
			_bit(Vector3(0.05, 0.5, 0.8), wall3.call(back * (hx + 0.63), up, along), yaw, iron)
		for end in [-1.0, 1.0]:
			_bit(Vector3(0.14, top - base, 0.14), wall3.call(back * (hx + 0.1), (top + base) * 0.5, end * (hz - 0.4)), yaw, iron)
		if floors > 3:
			# A fire escape up one end: a landing at each floor, a railing, and ladders between.
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			for f in range(1, floors):
				var fy := base + float(f) * 3.6 + 0.4
				_bit(Vector3(3.2, 0.08, 1.1), wall3.call(back * hx * 0.4, fy, side * (hz + 0.6)), yaw, iron)
				_bit(Vector3(3.2, 0.06, 0.05), wall3.call(back * hx * 0.4, fy + 1.0, side * (hz + 1.12)), yaw, iron)
				for post in [-1.5, 0.0, 1.5]:
					_bit(Vector3(0.05, 1.0, 0.05), wall3.call(back * hx * 0.4 + post, fy + 0.5, side * (hz + 1.12)), yaw, iron)
				_bit(Vector3(0.45, 3.7, 0.06), wall3.call(back * hx * 0.4 + (1.2 if f % 2 == 0 else -1.2), fy - 1.8, side * (hz + 0.85)), yaw, iron)
		# On the roof: vents, a hatch, and on tall blocks a water tank on legs and an aerial.
		for k in 2 + rng.randi() % 2:
			_bit(Vector3(0.7, 0.6, 0.7), wall3.call(rng.randf_range(-hx, hx) * 0.7, top + 0.8, rng.randf_range(-hz, hz) * 0.7), yaw, Color(0.6, 0.6, 0.58))
		_bit(Vector3(1.6, 1.9, 1.6), wall3.call(hx * 0.5, top + 1.4, -hz * 0.5), yaw, (b["wall"] as Color).darkened(0.15))
		if floors > 3:
			_bit(Vector3(2.2, 2.0, 2.2), wall3.call(-hx * 0.4, top + 3.0, hz * 0.3), yaw, Color(0.45, 0.33, 0.24))
			for leg in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				_bit(Vector3(0.14, 1.6, 0.14), wall3.call(-hx * 0.4 + leg.x * 0.9, top + 1.3, hz * 0.3 + leg.y * 0.9), yaw, iron)
			_bit(Vector3(0.06, 5.0, 0.06), wall3.call(hx * 0.6, top + 3.0, hz * 0.6), yaw, iron)
		# The front: a name board over the door on shops, and things on the pavement.
		if style < 78:
			var board: Color = [Color(0.6, 0.16, 0.14), Color(0.14, 0.3, 0.5), Color(0.16, 0.4, 0.26), Color(0.75, 0.6, 0.15), Color(0.3, 0.2, 0.4)][rng.randi() % 5]
			_bit(Vector3(0.14, 0.8, size.y * 0.62), wall3.call(front * (hx + 0.08), base + 3.9, 0.0), yaw, board)
			_bit(Vector3(0.16, 0.26, size.y * 0.4), wall3.call(front * (hx + 0.1), base + 3.9, 0.0), yaw, white)
			_bit(Vector3(0.9, 0.7, 0.08), wall3.call(front * (hx + 0.55), base + 3.0, hz * 0.85), yaw, board)  # a hanging sign
		var out_front := [[spot.call(front * (hx + 1.0), size.y * 0.28 + 1.6), "planter"], [spot.call(front * (hx + 1.0), size.y * 0.28 - 1.6), "planter"],
			[spot.call(front * (hx + 2.6), rng.randf_range(-hz, hz) * 0.7), ["table", "table", "board", "newsbox", "bikes", "trash", "stall"][rng.randi() % 7] if style < 78 else ["bikes", "trash", "newsbox", "bench"][rng.randi() % 4]]]
		for thing in out_front:
			if rng.randf() < 0.6 and _room_for(thing[0], taken, 2.2):
				taken.append(thing[0])
				_prop(String(thing[1]), thing[0], yaw + (PI * 0.5 if front > 0.0 else -PI * 0.5), rng)
		# The alley behind: a skip, bins, bags, pallets, the odd crate or barrel.
		var behind := ["dumpster", "trash", "bags", "pallets", "trash", "crates", "barrels", "bags"]
		var slot_z := -hz * 0.8
		while slot_z < hz * 0.8:
			var where: Vector2 = spot.call(back * (hx + 1.5), slot_z)
			if absf(slot_z - door_at) > 1.6 and rng.randf() < 0.55 and _room_for(where, taken, 1.8):
				taken.append(where)
				_prop(behind[rng.randi() % behind.size()], where, yaw + (PI * 0.5 if back > 0.0 else -PI * 0.5) + rng.randf_range(-0.15, 0.15), rng)
				if rng.randf() < 0.5:
					# A sheet or two of old newspaper on the ground, and a puddle.
					_bit(Vector3(0.4, 0.01, 0.55), Vector3(where.x + rng.randf_range(-2, 2), _surface(where.x, where.y) + 0.09, where.y + rng.randf_range(-2, 2)), rng.randf() * TAU, white)
					_bit(Vector3(rng.randf_range(1.0, 2.4), 0.008, rng.randf_range(0.8, 1.8)), Vector3(where.x + rng.randf_range(-2.5, 2.5), _surface(where.x, where.y) + 0.085, where.y + rng.randf_range(-2.5, 2.5)), rng.randf() * TAU, Color(0.2, 0.22, 0.25))
			slot_z += rng.randf_range(2.4, 4.5)
	# ---- shopping trolleys left about the car park
	for k in 14:
		var where := Vector2(MALL_X - rng.randf_range(10.0, 90.0), rng.randf_range(-190.0, 190.0))
		if _room_for(where, taken, 2.0) or _street_distance(where.x, where.y) > 1.0 and keep_out(Vector3(where.x, 0, where.y), 0.5).x == where.x:
			taken.append(where)
			_prop("cart", where, rng.randf() * TAU, rng)
	# ---- everything fixed, baked into one mesh for each colour
	for colour in _bits:
		var mi := MeshInstance3D.new()
		mi.mesh = (_bits[colour] as SurfaceTool).commit()
		mi.material_override = _mat(colour, 0.85)
		add_child(mi)
	_bits = {}


# ---- the shooting range ----

# An open field with one track down it: earth banks behind the targets and along the sides
# to stop the shot, a roofed firing point where the player starts, a board every hundred
# metres saying how far it is, sandbags, and a couple of huts.
func _range_field() -> void:
	var earth := MeshUtil.material(Color(0.4, 0.34, 0.24), 1.0, "mud", 9.0, true)
	var timber := MeshUtil.material(Color(0.5, 0.38, 0.24), 0.8, "wood", 5.0)
	var tin := _mat(Color(0.42, 0.45, 0.42), 0.5)
	_solid(Vector3(HALF_WIDTH * 1.5, 26.0, 40.0), Vector3(0, 6.0, half_len - 70.0), 0.0, earth)
	for side in [-1.0, 1.0]:
		_solid(Vector3(26.0, 14.0, half_len * 1.5), Vector3(side * 190.0, 2.0, 80.0), 0.0, earth)
		_houses.append(Vector2(side * 190.0, 0.0))
	var start: float = main.RANGE_START
	# The firing point: a roof on posts beside the track, with a sandbag wall in front.
	var shed := Vector3(26.0, height(26.0, start), start - 4.0)
	for px in [-9.0, 9.0]:
		for pz in [-6.0, 6.0]:
			_solid(Vector3(0.5, 5.0, 0.5), shed + Vector3(px, 2.5, pz), 0.0, timber)
	var roof := MeshUtil.box(self, Vector3(21.0, 0.3, 15.0), shed + Vector3(0, 5.3, 0), tin)
	roof.rotation.x = 0.1
	_houses.append(Vector2(shed.x, shed.z))
	var bag := _mat(Color(0.55, 0.5, 0.36), 1.0)
	for row in 3:
		for k in 9 - row:
			_solid(Vector3(1.6, 0.6, 0.9), Vector3(18.0 + row * 0.8 + k * 1.7, height(22.0, start + 14.0) + 0.3 + row * 0.6, start + 14.0), 0.0, bag)
	# Distance boards along the track, measured from the firing point.
	var white := _mat(Color(0.9, 0.9, 0.86))
	var metres := 100
	while start + metres < half_len - 110.0:
		var z := start + metres
		for side in [-1.0, 1.0]:
			var at := Vector3(side * 14.0, height(side * 14.0, z), z)
			MeshUtil.box(self, Vector3(0.25, 3.0, 0.25), at + Vector3(0, 1.5, 0), timber)
			MeshUtil.box(self, Vector3(3.2, 1.6, 0.15), at + Vector3(0, 3.4, 0), white)
			var label := Label3D.new()
			label.text = str(metres)
			label.font_size = 160
			label.pixel_size = 0.008
			label.modulate = Color(0.1, 0.1, 0.1)
			label.position = at + Vector3(0, 3.4, -0.1)
			label.rotation.y = PI
			add_child(label)
		metres += 100
	# Huts and a flag at the back of the firing point.
	for hut in [Vector3(-40.0, 0, start - 30.0), Vector3(48.0, 0, start - 46.0)]:
		hut.y = height(hut.x, hut.z)
		_solid(Vector3(12.0, 5.0, 8.0), hut + Vector3(0, 2.5, 0), 0.3, timber)
		var lid := MeshUtil.box(self, Vector3(13.0, 0.3, 9.0), hut + Vector3(0, 5.2, 0), tin)
		lid.rotation.y = 0.3
		_houses.append(Vector2(hut.x, hut.z))
	var pole := Vector3(-14.0, height(-14.0, start - 8.0), start - 8.0)
	MeshUtil.cylinder(self, 0.12, 11.0, pole + Vector3(0, 5.5, 0), white)
	MeshUtil.box(self, Vector3(3.0, 1.8, 0.06), pole + Vector3(1.6, 10.0, 0), _mat(Color(0.8, 0.12, 0.1)))


# Plastic model trees: decoration only. None downtown; thick in the park and out in the
# country, scattered between the houses; on the range, out towards the edges.
func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var trunk := _mat(Color(0.4, 0.26, 0.14), 0.6)
	var leaves := [_mat(Color(0.14, 0.4, 0.18), 0.7), _mat(Color(0.22, 0.48, 0.2), 0.7), _mat(Color(0.12, 0.34, 0.2), 0.7)]
	var placed := 0
	var tries := 0
	while placed < 300 and tries < 9000:
		tries += 1
		var x := rng.randf_range(-HALF_WIDTH + 8.0, HALF_WIDTH - 8.0)
		var z := rng.randf_range(0.0, half_len - 8.0)
		var in_park := layout == "town" and PARK.has_point(Vector2(x, z))
		if layout == "town":
			if in_downtown(x, z) or (not in_park and z < 560.0 and rng.randf() < 0.45):
				continue
			if absf(x) > MALL_X - 125.0 and absf(z) < 225.0:
				continue  # the shopping centre and the west park are planted (or not) by _outskirts
			if in_park and Vector2(x, z).distance_to(PARK.get_center() + Vector2(-16, 4)) < 28.0:
				continue  # the pond
		if _street_distance(x, z) < (12.0 if layout == "town" else 120.0) or not _clear_of(x, z, 9.0 if in_park else 14.0):
			continue
		var size := rng.randf_range(0.8, 1.4)
		var mat: Material = leaves[rng.randi() % leaves.size()]
		var round_top := rng.randf() < 0.45
		for sign in [1.0, -1.0]:
			var p := Vector3(x * sign, height(x * sign, z * sign), z * sign)
			MeshUtil.cylinder(self, 0.3 * size, 3.0 * size, p + Vector3(0, 1.5 * size, 0), trunk)
			if round_top:
				var ball := MeshInstance3D.new()
				var sphere := SphereMesh.new()
				sphere.radius = 2.6 * size
				sphere.height = 4.6 * size
				sphere.radial_segments = 7
				sphere.rings = 4
				ball.mesh = sphere
				ball.material_override = mat
				ball.position = p + Vector3(0, 4.6 * size, 0)
				add_child(ball)
			else:
				var crown := MeshUtil.cylinder(self, 2.2 * size, 5.5 * size, p + Vector3(0, 5.0 * size, 0), mat, 0.0)
				crown.mesh.radial_segments = 7
		placed += 1

func _deco(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshUtil.box(self, size, pos, mat)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # or the ceiling would shade the whole mat
	return m


# ---- the country beyond the battlefield ----

const FAR_OUT := 3600.0   # how far the scenery runs past the middle of the map, metres
const FAR_STEP := 60.0    # the size of its squares: coarse, it is only ever seen from a distance
var _far := FastNoiseLite.new()


# The height of the land out beyond the edge. At the edge it meets the battlefield (a touch
# lower, so the two never fight over the same spot), then rises into rolling hills that get
# bigger towards the horizon.
func far_height(x: float, z: float) -> float:
	var cx := clampf(x, -HALF_WIDTH, HALF_WIDTH)
	var cz := clampf(z, -half_len, half_len)
	var d := Vector2(x - cx, z - cz).length()
	var edge := height(cx, cz)
	if d <= 0.0:
		return edge - 9.0  # under the battlefield itself
	var size := lerpf(22.0, 130.0, smoothstep(300.0, 2800.0, d))
	var hills := _far.get_noise_2d(x, z) * size + _far.get_noise_2d(x * 3.1 + 500.0, z * 3.1) * size * 0.2 + size * 0.3
	var rise := smoothstep(40.0, 900.0, d)
	return lerpf(edge - 4.0 * (1.0 - smoothstep(0.0, 120.0, d)), hills, rise)


# Rolling hills all round the battlefield, out to the horizon, with woods scattered over
# them. Scenery only: nothing out there can be reached or collided with.
func _surroundings() -> void:
	_far.seed = 31
	_far.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_far.frequency = 0.0011
	_far.fractal_octaves = 3
	var n := int(FAR_OUT * 2.0 / FAR_STEP) + 1
	var grass := Color(0.24, 0.4, 0.2) if layout == "town" else Color(0.38, 0.42, 0.24)
	var field := Color(0.44, 0.47, 0.25)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inside := PackedByteArray()  # corners well inside the battlefield: squares made only of these are left out
	for iz in n:
		for ix in n:
			var x := -FAR_OUT + ix * FAR_STEP
			var z := -FAR_OUT + iz * FAR_STEP
			var y := far_height(x, z)
			var e := FAR_STEP * 0.5
			st.set_color(grass.lerp(field, clampf(_far.get_noise_2d(x * 2.3 - 900.0, z * 2.3) * 1.4 + 0.3, 0.0, 1.0) * 0.7))
			st.set_normal(Vector3(far_height(x - e, z) - far_height(x + e, z), 2.0 * e, far_height(x, z - e) - far_height(x, z + e)).normalized())
			st.add_vertex(Vector3(x, y, z))
			inside.append(1 if (absf(x) < HALF_WIDTH and absf(z) < half_len) else 0)
	for iz in n - 1:
		for ix in n - 1:
			var i := iz * n + ix
			if inside[i] + inside[i + 1] + inside[i + n] + inside[i + n + 1] == 4:
				continue
			for k in [i, i + 1, i + n, i + 1, i + n + 1, i + n]:
				st.add_index(k)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.albedo_texture = Tex.named("grass")
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / 45.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var land := MeshInstance3D.new()
	land.mesh = st.commit()
	land.material_override = mat
	land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(land)

	# Woods: one simple fir, drawn a few thousand times, thick where the noise says and bare elsewhere.
	var fir := CylinderMesh.new()
	fir.top_radius = 0.0
	fir.bottom_radius = 4.5
	fir.height = 15.0
	fir.radial_segments = 6
	fir.rings = 1
	var woods := MultiMesh.new()
	woods.transform_format = MultiMesh.TRANSFORM_3D
	woods.mesh = fir
	var spots: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 30000:
		if spots.size() >= 4200:
			break
		var x := rng.randf_range(-FAR_OUT, FAR_OUT) * 0.82
		var z := rng.randf_range(-FAR_OUT, FAR_OUT) * 0.82
		if absf(x) < HALF_WIDTH + 25.0 and absf(z) < half_len + 25.0:
			continue
		if _far.get_noise_2d(x * 2.0 + 300.0, z * 2.0 - 700.0) < 0.05:
			continue
		var s := rng.randf_range(0.7, 1.5)
		spots.append(Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), Vector3(x, far_height(x, z) + 6.5 * s, z)))
	woods.instance_count = spots.size()
	for i in spots.size():
		woods.set_instance_transform(i, spots[i])
	var trees := MultiMeshInstance3D.new()
	trees.multimesh = woods
	trees.material_override = _mat(Color(0.13, 0.3, 0.16), 0.9)
	trees.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trees)