class_name MapFile
extends RefCounted
# Maps made in the editor, kept as files in user://maps/<name>.json. A map (a "plan") is:
#   size       how many metres square it is
#   heights    the ground's height at every point of an 8-metre grid, row by row
#   roads      each a list of [x, z] points
#   buildings  each [x, z, width, depth, floors, kind (0 house, 1 shop, 2 tower), turn, wall colour, roof colour]
#   items      each [prefab name, x, z, turn]  (see prefabs.gd)
#   points     the three domination points, each [x, z]
#   spawns     where Blue and Red start, each [x, z]

static func path(map_name: String) -> String:
	return "user://maps/%s.json" % map_name


static func blank(size: float) -> Dictionary:
	return {"size": size, "heights": [], "roads": [], "buildings": [], "items": [], "trees": [], "points": [], "spawns": []}


static func read(map_name: String, new_size: float = 1200.0) -> Dictionary:
	if FileAccess.file_exists(path(map_name)):
		var plan = JSON.parse_string(FileAccess.get_file_as_string(path(map_name)))
		if plan is Dictionary and plan.has("size"):
			for key in blank(0.0):
				if not plan.has(key):
					plan[key] = []
			return plan
	return blank(new_size)


static func write(map_name: String, plan: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://maps")
	var f := FileAccess.open(path(map_name), FileAccess.WRITE)
	f.store_string(JSON.stringify(plan))
