class_name Prop
extends RigidBody3D
# Something standing on the map that vehicles drive straight through and guns knock about:
# a parked car, a bus, a lamp-post, a fence, a stack of sandbags. It stands rigid, costing
# nothing, until a vehicle runs into it or a round or blast hits it; then it comes loose,
# is shoved, tips and tumbles like a real object, and goes rigid again where it comes to
# rest. Props are on collision layer 16: shells and bullets hit them, vehicles do not
# collide with them (tank.gd shoves whatever its hull overlaps).

const LAYER := 16
const HEAVY := 1000.0  # this heavy or more (cars, vans, lorries, buses) it is cover: hard to shift, never sent flying

static var remote := false  # this PC is watching a host's match: the host moves the props, not us

var prop_id := -1    # its number on the map, the same on every PC
var moved := false   # (host) it has been knocked about since the other PCs were last told where it is
var _goal := Transform3D.IDENTITY  # (watching PC) where the host says it is
var _loose := 0.0  # seconds left before it may go rigid again


# A prop the size of a box, with its origin at the middle of its base.
static func make(size: Vector3, weight: float) -> Prop:
	var p := Prop.new()
	p.mass = weight
	p.freeze = true
	p.collision_layer = LAYER
	p.collision_mask = 1 | 4 | LAYER
	p.angular_damp = 1.2
	p.linear_damp = 0.3
	p.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	p.center_of_mass = Vector3(0, size.y * 0.4, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	p.add_child(shape)
	p.add_to_group("props")
	p.set_physics_process(false)
	return p


# Hit or shoved: `push` is the blow (direction times strength), `at` where it landed.
func knock(push: Vector3, at: Vector3) -> void:
	if remote:
		return  # the host will say where it ends up
	moved = true
	freeze = false
	sleeping = false
	if mass >= HEAVY:
		# Heavy things are shoved along the ground, not thrown or spun.
		push.y = minf(push.y, 0.0)
		apply_central_impulse(push.limit_length(mass * 3.0))
	else:
		apply_impulse(push.limit_length(mass * 14.0), at - global_position)
	_loose = 5.0
	set_physics_process(true)


# (Watching PC) The host says the prop is here now: glide to it.
func follow(to: Transform3D) -> void:
	_goal = to
	_loose = 1.0
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if remote:
		global_transform = global_transform.interpolate_with(_goal, clampf(delta * 14.0, 0.0, 1.0))
		_loose -= delta
		if _loose <= 0.0:
			global_transform = _goal
			set_physics_process(false)
		return
	moved = true
	_loose -= delta
	if _loose <= 0.0 and linear_velocity.length() < 0.3 and angular_velocity.length() < 0.3:
		freeze = true
		set_physics_process(false)
	elif global_position.y < -40.0:
		queue_free()  # fell off the mat
