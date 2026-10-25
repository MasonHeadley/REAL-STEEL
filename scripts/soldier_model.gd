class_name SoldierModel
extends Node3D
# The army man's figure: a rigged soldier model (models/soldier.glb) recoloured as a moulded
# toy in his side's colour, and moved by code rather than by canned animations.
#
# The model stands in a firing stance with the rifle in the shoulder. Every frame the bones
# are put back to that stance and then turned by the amounts below, so any mix of running,
# leaning, lowering the gun, kneeling and so on can be shown at once. soldier.gd sets the
# amounts; pose() applies them.
#
# All turning is done in the model's own space, where the rifle points along +Z, +X is the
# man's left and +Y is up: a positive turn about X tips something forward and down.

const SCENE := preload("res://models/soldier.glb")
const HEIGHT := 1.8              # metres: man-sized beside the vehicles
const MODEL_HEIGHT := 31.0       # the model's own units
const GRIP_TO_BARREL := Vector3(1.4, 1.05, 0.0)  # from the right hand's bone to the line of the barrel, model units
const TO_MODEL := MODEL_HEIGHT / HEIGHT          # metres to the model's units
# How each weapon is held. Metres, in the weapon's own space (see WeaponModel: barrel along +Z,
# +X his left, the origin just above the trigger hand):
#   shift   how far the weapon is moved from where a rifle sits in the shoulder
#   left    where the left wrist goes; the hand closes round whatever is just above and ahead of it
#   muzzle  where its rounds leave
const HOLDS := {
	"rifle": {"shift": Vector3.ZERO, "left": Vector3(0.05, -0.065, 0.24), "muzzle": Vector3(0, 0, 0.52)},
	"carbine": {"shift": Vector3.ZERO, "left": Vector3(0.05, -0.065, 0.2), "muzzle": Vector3(0, 0, 0.43)},
	"machine_gun": {"shift": Vector3.ZERO, "left": Vector3(0.055, -0.085, 0.28), "muzzle": Vector3(0, 0, 0.78)},
	"pistol": {"shift": Vector3(0.06, 0.03, 0.12), "left": Vector3(0.05, -0.08, -0.03), "muzzle": Vector3(0, 0, 0.16)},
	"launcher": {"shift": Vector3(0, 0, 0.1), "left": Vector3(0.02, -0.04, -0.25), "muzzle": Vector3(-0.05, 0.11, 0.9)},
}
const PLASTIC := [Color(0.2, 0.36, 0.17), Color(0.62, 0.53, 0.34)]  # green, tan
const ARMBAND := [Color(0.15, 0.35, 0.95), Color(0.9, 0.15, 0.12)]  # team blue, team red
# How dark each part of the model is moulded, by its material's name.
const SHADES := {"Material.001": 0.45, "Material.004": 0.3, "Material.002": 0.14, "Material.003": 0.0}

# The pose, set from outside.
var stride := 0.0     # running cycle, radians; advance it to move the legs
var run := 0.0        # 0 standing .. 1 running
var lean := 0.0       # forward lean of the whole body, radians (a sprint is about 0.3)
var gun_low := 0.0    # how far the rifle is lowered from the shoulder, radians (negative raises it)
var crouch := 0.0     # 0 standing .. 1 down on one knee
var throw := 0.0      # 0..1, left arm up and over (the right keeps hold of the rifle)
var head_up := 0.0    # head tipped back, radians: looking forward while lying prone
var kick := 0.0       # recoil, fades by itself
var work := 0.0       # medic's hands busy: -1..1
var weapon := 1       # what is in his hands: 1 his main weapon, 2 the pistol, 3 the rocket launcher
var heading := Vector2(0, 1)  # which way he is stepping: x to his right, y ahead (so (0, -1) is backing up)
var pace := 4.0       # how fast he is moving over the ground, metres a second: sets the length and beat of his stride
var flat := 0.0       # 0 upright .. 1 lying on his belly (soldier.gd tips the whole figure over; this lays the limbs out)
var reload := 0.0     # 0 not reloading, else how far through it he is (0..1): the left hand leaves the weapon and comes back
var loaded := true    # whether a rocket shows in the launcher
var tuck := 0.0       # 0..1, off the ground in a jump: the knees come up
var vault := 0.0      # 0..1, going over an obstacle: bent forward, the left hand down on top of it

var skel: Skeleton3D
var muzzle := Node3D.new()        # where rounds leave, in the soldier's space
var gun_cam := Node3D.new()       # a camera clipped to the rifle
var shoulder_cam := Node3D.new()  # a camera on the helmet
var _rig := Node3D.new()
var _bones := {}
var _guns: Node3D       # carries the weapons, moved with his hands every frame
var _arms := {}         # weapon number -> its model (see WeaponModel)
var _kinds := {}        # weapon number -> which kind of weapon it is (a key of HOLDS)
var _rocket: Node3D     # the rocket sitting in the launcher, hidden once it has been fired
var _len := {}          # bone name -> its length, for reaching hands and feet to a point


func build(team: int, kit: String, sight: String = "iron") -> void:
	_rig.scale = Vector3.ONE * (HEIGHT / MODEL_HEIGHT)
	_rig.rotation.y = PI  # the model aims along +Z; the game's forward is -Z
	add_child(_rig)
	var scene: Node3D = SCENE.instantiate()
	_rig.add_child(scene)
	skel = scene.find_children("*", "Skeleton3D", true, false)[0]
	for ap in scene.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	for n in ["hips", "spine", "chest", "neck", "head", "arm.L", "arm.R", "forearm.L", "forearm.R", "upleg.L", "upleg.R", "leg.L", "leg.R", "foot.L", "foot.R", "toe.L", "toe.R", "hand.L", "hand.R"]:
		_bones[n] = skel.find_bone(n)
	var base: Color = PLASTIC[team]
	var mats := {}
	var gunmetal := MeshUtil.material(Color(0.17, 0.18, 0.2), 0.45)
	gunmetal.metallic = 0.6
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			if String(mi.name).begins_with("M4"):
				mi.visible = false  # the model's own rifle: replaced by the weapons built below
				continue
			var shade: float = SHADES.get(mi.mesh.surface_get_material(s).resource_name, 0.08)
			if not mats.has(shade):
				mats[shade] = MeshUtil.material(base.darkened(shade), 0.82)
			mi.set_surface_override_material(s, mats[shade])
	# A band in the team's colour round each upper arm. A medic's are white with a red cross.
	var band_mat := MeshUtil.material(Color(0.92, 0.92, 0.88) if kit == "medical" else ARMBAND[team], 0.7)
	for side in ["arm.L", "arm.R"]:
		var at := _attach(side)
		MeshUtil.cylinder(at, 1.55, 1.5, Vector3(0, 2.0, 0), band_mat)
		if kit == "medical":
			var red := MeshUtil.material(Color(0.8, 0.1, 0.1), 0.7)
			for a in 4:
				var cross := Node3D.new()
				cross.rotation.y = a * PI * 0.5
				at.add_child(cross)
				MeshUtil.box(cross, Vector3(0.9, 0.3, 0.1), Vector3(0, 2.0, 1.56), red)
				MeshUtil.box(cross, Vector3(0.3, 0.9, 0.1), Vector3(0, 2.0, 1.56), red)
	if kit == "medical":
		# The helmet stays the colour of the rest of him, with a white disc and red cross
		# painted on the front, the back and both sides.
		var red := MeshUtil.material(Color(0.8, 0.1, 0.1), 0.7)
		var helmet := _attach("head")
		for a in 4:
			# Where the shell is on each side, measured off the model (tools/measure_helmet.gd):
			# [how far out from the middle of the helmet, how high, how far it leans in].
			var fit: Array = [[2.68, 4.1, -0.75], [2.36, 3.2, -0.5], [2.65, 3.7, -0.8], [2.36, 3.2, -0.5]][a]
			var mark := Node3D.new()
			mark.position = Vector3(-0.1, fit[1], 0.5)
			mark.rotation.y = a * PI * 0.5
			helmet.add_child(mark)
			var face := Node3D.new()
			face.position = Vector3(0, 0, fit[0])
			face.rotation.x = fit[2]
			mark.add_child(face)
			var disc := MeshUtil.cylinder(face, 0.72, 0.08, Vector3.ZERO, band_mat)
			disc.rotation.x = PI * 0.5
			MeshUtil.box(face, Vector3(0.95, 0.3, 0.06), Vector3(0, 0, 0.05), red)
			MeshUtil.box(face, Vector3(0.3, 0.95, 0.06), Vector3(0, 0, 0.05), red)
	# His weapons (WeaponModel builds them in metres; the figure is in its own, bigger units).
	# All of them ride on one carrier that follows his hands; only the one in use is shown.
	var to_model := MODEL_HEIGHT / HEIGHT
	_guns = Node3D.new()
	_rig.add_child(_guns)
	var carried := {1: "machine_gun" if kit == "machine_gun" else ("carbine" if kit == "medical" else "rifle"), 2: "pistol"}
	if kit == "rocket":
		carried[3] = "launcher"
	for slot in carried:
		var piece := WeaponModel.build(carried[slot], sight)
		piece.scale = Vector3.ONE * to_model
		_guns.add_child(piece)
		_arms[slot] = piece
		_kinds[slot] = carried[slot]
		if carried[slot] == "launcher":
			_rocket = piece.get_node("Rocket")
	for pair in [["arm.L", "forearm.L"], ["forearm.L", "hand.L"], ["arm.R", "forearm.R"], ["forearm.R", "hand.R"],
			["upleg.L", "leg.L"], ["leg.L", "foot.L"], ["upleg.R", "leg.R"], ["leg.R", "foot.R"]]:
		_len[pair[0]] = skel.get_bone_global_rest(_bones[pair[0]]).origin.distance_to(skel.get_bone_global_rest(_bones[pair[1]]).origin)
	if kit == "tools":
		MeshUtil.box(_attach("chest"), Vector3(4.2, 3.0, 1.8), Vector3(0, 1.0, -3.0), MeshUtil.material(Color(0.5, 0.2, 0.15), 0.8))
	for n in [muzzle, shoulder_cam]:
		add_child(n)
	# The rifle camera is fixed to the rifle itself (which is carried by the right hand): well
	# forward on the handguard, clear of his head whatever he is doing, with the front sight
	# and barrel in the bottom of its picture. It goes wherever the gun points.
	var grip_rest := skel.get_bone_global_rest(_bones["hand.R"])
	var on_gun := _attach("hand.R")
	on_gun.add_child(gun_cam)
	gun_cam.transform = grip_rest.affine_inverse() * Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -0.24), grip_rest.origin + Vector3(1.5, 5.6, 5.4))
	pose(0.0)


func _attach(bone: String) -> BoneAttachment3D:
	var at := BoneAttachment3D.new()
	at.bone_name = bone
	skel.add_child(at)
	return at


# Turns one bone about an axis of the model's space, pivoting on the bone's own joint.
func _turn(bone: String, axis: Vector3, angle: float) -> void:
	if is_zero_approx(angle):
		return
	var i: int = _bones[bone]
	var g := skel.get_bone_global_pose(i)
	g.basis = Basis(axis, angle) * g.basis
	skel.set_bone_global_pose(i, g)


# Swings a bone so that it points, from its own joint to the joint of `child`, along `dir`
# (a direction in the model's space). `weight` 0 leaves it alone, 1 takes it all the way.
# Used for the legs, so a running leg goes exactly where it is told whatever odd angle the
# model's standing pose left it at.
func _point(bone: String, child: String, dir: Vector3, weight: float) -> void:
	if weight <= 0.001:
		return
	var i: int = _bones[bone]
	var g := skel.get_bone_global_pose(i)
	var now := (skel.get_bone_global_pose(_bones[child]).origin - g.origin).normalized()
	var to := now.slerp(dir.normalized(), weight)
	g.basis = Basis(Quaternion(now, to)) * g.basis
	skel.set_bone_global_pose(i, g)


# The same, but swinging the bone round some other point, so both arms and the rifle they
# hold can move as one piece.
func _swing(bone: String, axis: Vector3, angle: float, pivot: Vector3) -> void:
	if is_zero_approx(angle):
		return
	var i: int = _bones[bone]
	var g := skel.get_bone_global_pose(i)
	var turn := Basis(axis, angle)
	skel.set_bone_global_pose(i, Transform3D(turn * g.basis, pivot + turn * (g.origin - pivot)))


# Bends a two-bone limb (upper arm and forearm, or thigh and shin) so that its end, the
# wrist or the ankle, lands on `target`. `pole` is the way the elbow or knee should stick
# out. `weight` 0 leaves the limb alone, 1 takes it all the way.
func _reach(upper: String, mid: String, end: String, target: Vector3, pole: Vector3, weight: float = 1.0) -> void:
	if weight <= 0.001:
		return
	var from := skel.get_bone_global_pose(_bones[upper]).origin
	var a: float = _len[upper]
	var b: float = _len[mid]
	var to := target - from
	var d := clampf(to.length(), absf(a - b) + 0.05, a + b - 0.05)
	var dir := to.normalized()
	var along := (a * a + d * d - b * b) / (2.0 * d)
	var out := sqrt(maxf(a * a - along * along, 0.0))
	var side := pole - dir * pole.dot(dir)
	side = side.normalized() if side.length() > 0.001 else Vector3.UP
	_point(upper, mid, dir * along + side * out, weight)
	var joint := skel.get_bone_global_pose(_bones[mid]).origin
	_point(mid, end, from + dir * d - joint, weight)


func pose(delta: float) -> void:
	kick = move_toward(kick, 0.0, delta * 7.0)
	throw = move_toward(throw, 0.0, delta * 2.2)
	skel.reset_bone_poses()
	# Which way he is stepping, in the model's space (+Z ahead, +X his left).
	var step_dir := Vector3(-heading.x, 0, heading.y)
	step_dir = step_dir.normalized() if step_dir.length() > 0.05 else Vector3(0, 0, 1)
	var upright := 1.0 - flat
	var speed := maxf(pace, 0.6)
	# The stride: longer and quicker the faster he goes, shorter when crouched. The beat is
	# what would plant each foot without sliding, capped so a sprint is not a blur.
	var step_m := clampf(0.3 + 0.075 * speed, 0.3, 0.95) * lerpf(1.0, 0.8, crouch)
	var rate := minf(PI * speed / step_m, 6.0 + speed * 0.85)
	if flat > 0.5:
		rate = (5.0 + speed * 1.5) * (-1.0 if heading.y < -0.3 else 1.0)  # crawling; backwards runs the cycle in reverse
	stride += delta * rate * run
	var step := step_m * TO_MODEL
	var s := sin(stride)
	var c := cos(stride)

	# The body. Standing still and crouched he is down on one knee; crouched and moving he
	# walks bent low on both legs. Striding out, the hips drop just enough for the legs to reach.
	var kneel := crouch * (1.0 - run)
	var leg_reach := sqrt(maxf(13.5 * 13.5 - step * step * 0.25, 4.0))
	var drop := kneel * 6.2 + run * upright * (crouch * 3.8 + maxf(0.0, 12.6 - leg_reach) + 0.3)
	var bob := absf(c) * (0.3 + 0.07 * speed) * run * upright
	var hips: int = _bones["hips"]
	skel.set_bone_pose_position(hips, skel.get_bone_rest(hips).origin + Vector3(0, bob - drop, -lean * 2.0))
	var bend := lean + crouch * 0.35 + vault * 0.5
	_turn("hips", Vector3.RIGHT, bend * 0.6)
	_turn("hips", Vector3.UP, s * 0.12 * run * upright)  # the hips twist with each step
	_turn("spine", Vector3.RIGHT, bend * 0.4)
	_turn("chest", Vector3.UP, -s * 0.16 * run * upright)
	# Crawling, the whole body snakes from side to side.
	_turn("hips", Vector3.BACK, -s * 0.1 * run * flat)
	_turn("spine", Vector3.BACK, s * 0.16 * run * flat)
	# The head stays looking where he is going, and nods a little with his feet.
	_turn("neck", Vector3.RIGHT, -head_up * 0.5)
	_turn("head", Vector3.RIGHT, -bend * 0.8 + absf(s) * 0.07 * run * upright - head_up * 0.5)

	# Legs.
	for g in [["L", stride, 1.0], ["R", stride + PI, -1.0]]:
		var side: String = g[0]
		var phase: float = g[1]
		var out: float = g[2]  # +1 for his left leg, -1 for his right
		# Down on one knee: one knee forward and up, the other on the ground.
		if kneel > 0.001:
			# (The feet are put where they belong and the knees bend to suit. Turning the
			# joints by fixed angles, as before, threw the legs out behind him.)
			var seat := skel.get_bone_global_pose(_bones["upleg." + side]).origin
			if side == "L":
				# The front leg: foot flat on the ground ahead of him, knee up in front.
				_reach("upleg.L", "leg.L", "foot.L", Vector3(seat.x + 0.6, 1.15, seat.z + 5.2), Vector3(0.1, 0.5, 1.0), kneel)
				_point("foot.L", "toe.L", Vector3(0, -0.3, 1.0), kneel)
			else:
				# The back leg: knee down on the ground under him, shin and foot laid back behind.
				_reach("upleg.R", "leg.R", "foot.R", Vector3(seat.x - 0.6, 1.3, seat.z - 4.8), Vector3(0.0, -1.0, 0.25), kneel)
				_point("foot.R", "toe.R", Vector3(0, -0.7, -1.0), kneel)
		# Walking, running, backing up, side-stepping: the foot is carried round a loop in the
		# direction he is going (on the ground going back, lifted coming forward) and the knee
		# bends however it must to put it there. The same loop serves every direction.
		var walking := run * upright
		if walking > 0.001:
			var top := skel.get_bone_global_pose(_bones["upleg." + side]).origin
			var lift := maxf(0.0, sin(phase))
			var ankle := Vector3(top.x + out * 0.3, 1.15 + lift * (0.9 + 0.3 * speed), top.z) + step_dir * (-cos(phase) * step * 0.5)
			_reach("upleg." + side, "leg." + side, "foot." + side, ankle, Vector3(out * 0.15, 0.0, 1.0), walking)
			_point("foot." + side, "toe." + side, Vector3(0, -0.35 - lift * 0.5, 1.0), walking)
		# In the air: both knees drawn up under him (and swung to one side in a vault).
		if tuck > 0.001:
			var hip_at := skel.get_bone_global_pose(_bones["upleg." + side]).origin
			_reach("upleg." + side, "leg." + side, "foot." + side, hip_at + Vector3(out * 0.4 + vault * 3.5, -6.5, 2.5 - out * 1.5), Vector3(out * 0.15, 0.0, 1.0), tuck * upright)
		# Lying down: legs out straight behind him, a little apart. Crawling, each knee in
		# turn is drawn up and out to the side, then pushes back.
		if flat > 0.001:
			var drawn := maxf(0.0, sin(phase)) * run
			_point("upleg." + side, "leg." + side, Vector3(out * (0.18 + 0.9 * drawn), -1.0 + 0.5 * drawn, 0.05), flat)
			_point("leg." + side, "foot." + side, Vector3(out * (0.1 - 0.6 * drawn), -1.0, 0.0), flat)
			_point("foot." + side, "toe." + side, Vector3(out * 0.4, -1.0, 0.0), flat)

	# Arms and weapon. Both arms turn together so the gun comes down out of the shoulder (or
	# up, lying prone); on the move it swings from side to side with his steps.
	var low := gun_low - kick * 0.12 + work * 0.2
	var sway := s * (0.05 + 0.012 * speed) * run * (1.0 + flat)
	var between := (skel.get_bone_global_pose(_bones["arm.L"]).origin + skel.get_bone_global_pose(_bones["arm.R"]).origin) * 0.5
	for side in ["arm.L", "arm.R"]:
		_swing(side, Vector3.RIGHT, low, between)
		_swing(side, Vector3.UP, sway, between)
	# Where the weapon is: carried by that swing, then moved to where its kind is held.
	var shown := weapon if _arms.has(weapon) else 1
	var hold: Dictionary = HOLDS[_kinds.get(shown, "rifle")]
	var grip := skel.get_bone_global_pose(_bones["hand.R"]).origin
	var gun := Basis(Vector3.UP, sway) * Basis(Vector3.RIGHT, low + bend)
	var origin: Vector3 = grip + gun * (GRIP_TO_BARREL + (hold["shift"] as Vector3) * TO_MODEL)
	# Then the hands are brought to the weapon: the right to its grip, the left to wherever
	# this weapon is supported. Reloading, the left hand goes away for a fresh magazine (to
	# his belt) or a fresh rocket (over his shoulder) and comes back.
	_reach("arm.R", "forearm.R", "hand.R", origin - gun * GRIP_TO_BARREL, Vector3(-0.7, -1.0, -0.4))
	if throw > 0.0:
		# Wind up over the shoulder, then through.
		var t := sin(throw * PI)
		_turn("arm.L", Vector3.RIGHT, -2.4 * t)
		_turn("forearm.L", Vector3.RIGHT, -0.7 * t)
	else:
		var left_to: Vector3 = origin + gun * ((hold["left"] as Vector3) * TO_MODEL)
		if vault > 0.0:
			# The left hand goes down onto the top of what he is going over.
			left_to = left_to.lerp(skel.get_bone_global_pose(hips).origin + Vector3(4.5, -1.0, 6.0), vault)
		if reload > 0.0:
			var fetch := skel.get_bone_global_pose(hips).origin + Vector3(3.4, 1.5, 2.6)
			if shown == 3:
				fetch = skel.get_bone_global_pose(_bones["chest"]).origin + Vector3(2.0, 5.5, -2.5)
			left_to = left_to.lerp(fetch, sin(clampf(reload, 0.0, 1.0) * PI))
		_reach("arm.L", "forearm.L", "hand.L", left_to, Vector3(0.7, -1.0, -0.4))

	# Things that ride on the figure, placed in the soldier's own space.
	var to_me := _rig.transform  # the skeleton sits at the rig's origin
	var body := Basis(Vector3.RIGHT, bend - head_up * 1.4)
	_place(muzzle, to_me, origin + gun * ((hold["muzzle"] as Vector3) * TO_MODEL), gun)
	# The helmet camera is on the front rim, looking slightly down at his hands and rifle.
	var head := skel.get_bone_global_pose(_bones["head"]).origin
	_place(shoulder_cam, to_me, head + body * Vector3(0.0, 4.3, 4.9), body * Basis(Vector3.RIGHT, 0.1))
	_guns.transform = Transform3D(gun, origin)
	for slot in _arms:
		_arms[slot].visible = slot == shown
	if _rocket != null:
		_rocket.visible = loaded

# Puts a marker at a point of the model's space, facing along the model's +Z (so the
# marker's own forward, -Z, is the way the rifle points).
func _place(n: Node3D, to_me: Transform3D, at: Vector3, facing: Basis) -> void:
	n.transform = Transform3D(to_me.basis.orthonormalized() * facing * Basis(Vector3.UP, PI), to_me * at)
