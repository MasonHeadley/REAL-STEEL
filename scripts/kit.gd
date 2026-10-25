class_name Kit
extends RefCounted
# Equipment a player fits to a vehicle (data/attachments.json), and what a loadout does.
#
# A loadout is a dictionary:
#   "camo":  {"pattern": standard | blotch | stripe | digital | plain, "c1", "c2", "c3": colours as "#rrggbb", "scale": number}
#   "decal": {"text": up to 3 characters, "colour": "#rrggbb", "back": none | disc | square}
#   "slots": {place: [item ids]}  where place is one of PLACES
# Every place holds two units: two small items or one large one.

const PLACES := ["front_upper", "front_lower", "left", "right", "basket", "deck", "rear"]
const PLACE_NAMES := {"front_upper": "Upper glacis", "front_lower": "Lower glacis", "left": "Left side", "right": "Right side", "basket": "Turret basket", "deck": "Engine deck", "rear": "Rear"}

static var items := {}
static var order: Array = []


static func load_sheet() -> void:
	if not items.is_empty():
		return
	var sheet = JSON.parse_string(FileAccess.get_file_as_string("res://data/attachments.json"))
	for row in sheet["rows"]:
		items[row["id"]] = row
		order.append(row["id"])


# The items that can go in a place.
static func for_place(place: String) -> Array:
	load_sheet()
	var kind := "side" if (place == "left" or place == "right") else place
	return order.filter(func(id): return items[id]["slot"] == kind)


static func blank() -> Dictionary:
	return {"camo": {"pattern": "standard", "c1": "#5d6b4d", "c2": "#3c4632", "c3": "#8a8468", "scale": 1.0},
		"decal": {"text": "", "colour": "#f0f0e8", "back": "none"}, "slots": {}}


# A vehicle's sheet row with a loadout's equipment applied. Returns a changed copy.
static func apply(def: Dictionary, look: Dictionary) -> Dictionary:
	load_sheet()
	var out := def.duplicate(true)
	out["track_repair"] = 1.0
	out["engine_repair"] = 1.0
	for place in look.get("slots", {}):
		for id in look["slots"][place]:
			if not items.has(id):
				continue
			var it: Dictionary = items[id]
			var amount := float(it["amount"])
			match String(it["stat"]):
				"accel":
					out["accel"] = float(out["accel"]) * amount
				"reload":
					out["reload"] = float(out["reload"]) * amount
				"track_repair", "engine_repair":
					out[it["stat"]] = float(out[it["stat"]]) * amount
				"front_armour":
					out["armour"]["hull_front"] = float(out["armour"]["hull_front"]) + amount
				"side_armour":
					out["armour"]["hull_side"] = float(out["armour"]["hull_side"]) + amount
			# Weight: anything that adds armour slows the vehicle a little.
			if String(it["stat"]).ends_with("armour"):
				out["speed_fwd"] = float(out["speed_fwd"]) * (1.0 - amount * 0.002)
	return out


# The camouflage picture for a loadout: three colours laid out in the chosen pattern.
# Returns null for the standard factory paint.
static func camo_texture(camo: Dictionary) -> ImageTexture:
	var pattern := String(camo.get("pattern", "standard"))
	if pattern == "standard":
		return null
	var cols := [Color(String(camo.get("c1", "#5d6b4d"))), Color(String(camo.get("c2", "#3c4632"))), Color(String(camo.get("c3", "#8a8468")))]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.035 / maxf(float(camo.get("scale", 1.0)), 0.2)
	var cell := maxi(4, int(10.0 * float(camo.get("scale", 1.0))))
	for y in size:
		for x in size:
			var c: Color = cols[0]
			if pattern == "blotch" or pattern == "digital":
				# (The texture repeats, so the noise is sampled round a circle to make its edges meet.)
				var sx := x - x % cell if pattern == "digital" else x
				var sy := y - y % cell if pattern == "digital" else y
				var ax := float(sx) / size * TAU
				var ay := float(sy) / size * TAU
				var r := size / TAU
				var v := noise.get_noise_3d(cos(ax) * r + cos(ay) * r, sin(ax) * r, sin(ay) * r)
				var w := noise.get_noise_3d(sin(ax) * r + 90.0, cos(ay) * r + 40.0, sin(ay) * r + cos(ax) * r)
				c = cols[1] if v > 0.12 else (cols[2] if w > 0.28 else cols[0])
			elif pattern == "stripe":
				# Measured out from the middle of the picture, so the stripes are mirrored left
				# and right; and a whole number of them fit, so the picture repeats without a seam.
				var every := float(size) / maxf(1.0, round(float(size) / (78.0 * float(camo.get("scale", 1.0)))))
				var band := fposmod(float(absi(x - size / 2) + y) / every * 3.0 + sin(float(y) / size * TAU) * 0.35, 3.0)
				c = cols[int(band)]
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
