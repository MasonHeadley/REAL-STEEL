class_name Tex
extends RefCounted
# Textures painted in code at start-up. Surface textures are grey detail maps that the
# material's colour is multiplied by; the hit marks are colour + normal map pairs for decals.

const SIZE := 256

static var _cache := {}


static func named(id: String) -> Texture2D:
	if not _cache.has(id):
		_cache[id] = _make(id)
	return _cache[id]


static func _make(id: String) -> Texture2D:
	match id:
		"grass":
			return _surface(_grass, 0.04, 1)
		"asphalt":
			return _surface(_asphalt, 0.02, 2)
		"plaster":
			return _surface(_plaster, 0.03, 3)
		"roof":
			return _surface(_roof, 0.05, 4)
		"camo":
			return _surface(_camo, 0.012, 5)
		"track":
			return _surface(_track, 0.05, 6)
		"brick":
			return _surface(_brick, 0.03, 7)
		"wood":
			return _surface(_wood, 0.02, 8)
		"wallpaper":
			return _surface(_wallpaper, 0.02, 9)
		"grime":
			return _grime()
		"mud":
			return _mud()
		"hole":
			return _mark(false, false)
		"hole_normal":
			return _mark(false, true)
		"gouge":
			return _mark(true, false)
		"gouge_normal":
			return _mark(true, true)
	return null


static func _grass(n: float, r: float, _x: int, _y: int) -> float:
	return lerpf(0.7, 1.12, n) + r * 0.1


static func _asphalt(n: float, r: float, _x: int, _y: int) -> float:
	return lerpf(0.8, 1.0, n) + r * 0.16


static func _plaster(n: float, r: float, _x: int, y: int) -> float:
	var course := 0.9 if y % 32 < 2 else 1.0
	return (lerpf(0.82, 1.06, n) + r * 0.04) * course


static func _roof(n: float, r: float, x: int, y: int) -> float:
	var row := y / 16
	var tx := (x + (8 if row % 2 == 0 else 0)) % 16
	var edge := 0.6 if (y % 16 < 2 or tx < 1) else 1.0
	return (0.8 + float(y % 16) / 16.0 * 0.3 + n * 0.15 + r * 0.05) * edge


static func _camo(n: float, r: float, _x: int, _y: int) -> float:
	return lerpf(0.62, 1.0, smoothstep(0.5, 0.58, n)) * (0.95 + r * 0.1)


# Moulded plastic bricks: a seam every half tile, staggered like real brickwork.
static func _brick(_n: float, r: float, x: int, y: int) -> float:
	var row := y / 128
	var seam := y % 128 < 3 or (x + (128 if row % 2 == 0 else 0)) % 256 < 3
	return (0.7 if seam else 1.0) + r * 0.02


static func _wood(n: float, r: float, x: int, _y: int) -> float:
	return (0.55 if x % 64 < 2 else 1.0) * (0.82 + n * 0.22 + r * 0.04)


static func _wallpaper(_n: float, r: float, x: int, _y: int) -> float:
	return (1.0 if x % 64 < 32 else 0.86) + r * 0.02


static func _track(_n: float, r: float, _x: int, y: int) -> float:
	return (0.55 if y % 20 < 6 else 1.0) + r * 0.08


# Weathering for any plain surface: big soft blotches of wear, darker runs of dirt down each
# column (on a wall these hang straight down, as rain leaves them), and a fine speckle.
static func _grime() -> Texture2D:
	var blot_noise := FastNoiseLite.new()
	blot_noise.seed = 41
	blot_noise.frequency = 0.012
	blot_noise.fractal_octaves = 4
	var run_noise := FastNoiseLite.new()
	run_noise.seed = 42
	run_noise.frequency = 0.05
	run_noise.fractal_octaves = 2
	var blots := blot_noise.get_seamless_image(SIZE, SIZE)
	var runs := run_noise.get_seamless_image(SIZE, SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	var img := Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var n := blots.get_pixel(x, y).r
			var run := smoothstep(0.55, 0.85, runs.get_pixel(x, 0).r) * (0.4 + runs.get_pixel(x, y).r)
			var v := clampf(lerpf(0.86, 1.02, n) - run * 0.06 + (rng.randf() - 0.5) * 0.04, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# Mud thrown up a hull side: thick and solid along the bottom edge, breaking up into
# spatter towards the top. Transparent where there is none.
static func _mud() -> Texture2D:
	var size := 128
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	for y in size:
		var up := 1.0 - float(y) / float(size)  # 0 at the bottom edge, 1 at the top
		for x in size:
			var n := noise.get_noise_2d(x, y * 0.6) * 0.5 + 0.5
			var a := clampf((n * 1.5 + 0.35 - up * 1.75) * 2.2, 0.0, 1.0)
			if rng.randf() < 0.04 * (1.0 - up):
				a = maxf(a, 0.8)  # stray spatter
			var v := 0.85 + n * 0.3
			img.set_pixel(x, y, Color(0.36 * v, 0.28 * v, 0.17 * v, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# f(noise 0..1, random -0.5..0.5, x, y) returns brightness.
static func _surface(f: Callable, freq: float, seed_value: int) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = freq
	noise.fractal_octaves = 3
	var base := noise.get_seamless_image(SIZE, SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var img := Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var v: float = clampf(f.call(base.get_pixel(x, y).r, rng.randf() - 0.5, x, y), 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# A hit mark. "gouge" is a shallow bright scrape from a bounce; otherwise a punched, scorched hole.
# The normal map version makes the armour look pushed in around it.
static func _mark(gouge: bool, normal_map: bool) -> Texture2D:
	var size := 96
	var rng := RandomNumberGenerator.new()
	rng.seed = 9 if gouge else 8
	var streaks := PackedFloat32Array()
	for i in 24:
		streaks.append(rng.randf_range(0.55, 1.0))
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) / float(size) * 2.0 - Vector2.ONE
			if gouge:
				p.x *= 0.45  # stretched along the direction of the bounce
			var r := p.length()
			var reach: float = streaks[int((p.angle() + PI) / TAU * 24.0) % 24]
			var c := Color(0, 0, 0, 0)
			if normal_map:
				# Walls of the dent lean in towards its centre.
				var depth_edge := 0.75 if gouge else 0.55
				var slope := 0.0
				if r < depth_edge and r > 0.02:
					slope = sin(r / depth_edge * PI) * (0.9 if gouge else 1.6)
				var n := Vector3(-p.x / maxf(r, 0.001) * slope, p.y / maxf(r, 0.001) * slope, 1.0).normalized()
				c = Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0)
			elif gouge:
				var a := (1.0 - smoothstep(0.35, 0.8, r)) * 0.9
				var v := lerpf(0.75, 0.4, smoothstep(0.0, 0.7, r)) + rng.randf_range(-0.06, 0.06)
				c = Color(v, v, v * 0.97, a)
			else:
				var a := 1.0 - smoothstep(0.3 * reach, 0.95 * reach, r)
				var v := 0.0 if r < 0.2 else lerpf(0.02, 0.22, smoothstep(0.2, 0.9, r)) + rng.randf_range(0.0, 0.05)
				c = Color(v * 1.1, v, v * 0.9, a)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
