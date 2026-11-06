class_name PuppetConfig
extends RefCounted
## Art + jiggle-zone data for each character. All coordinates are PIXELS of the art file.
## Zone row: [name, root_x, root_y, tip_x, tip_y, radius_px, stiffness k, damping c, strength]
##   - A zone bends the art around the segment root->tip (root stays put, tip moves most).
##   - Lower k / lower c = floppier & bouncier.  strength scales lag, inertia, wind, kick and max travel.
##   - Names starting with "wpn" get an extra swing impulse on attacks.

const NICOLE := {
	"art": "res://art/nicole.png", "art_dir": 1.0, "pivot_x": 740.0,
	"face": Rect2(600.0, 130.0, 340.0, 340.0),
	"zones": [
		["hair_up", 600, 280, 310, 340, 200, 45.0, 2.4, 1.0],
		["hair_low", 560, 420, 430, 760, 230, 40.0, 2.2, 1.0],
		["hair_r", 960, 520, 900, 740, 140, 55.0, 2.6, 0.9],
		["ribbon_a", 720, 130, 660, 20, 110, 90.0, 3.0, 0.8],
		["ribbon_b", 850, 190, 950, 120, 100, 90.0, 3.0, 0.8],
		["plush", 560, 640, 500, 800, 150, 70.0, 3.0, 1.1],
		["tail", 850, 930, 420, 1440, 170, 35.0, 1.9, 1.2],
		["wpn_case", 300, 880, 130, 1040, 250, 30.0, 2.2, 1.0],
	],
}

const ANBY := {
	"art": "res://art/anby.png", "art_dir": -1.0, "pivot_x": 215.0,
	"face": Rect2(190.0, 0.0, 110.0, 110.0),
	"zones": [
		["wpn_sword", 190, 115, 10, 210, 60, 40.0, 2.4, 1.0],
		["hair_l", 228, 50, 212, 68, 24, 90.0, 3.2, 0.7],
		["hair_r", 268, 52, 300, 72, 26, 90.0, 3.2, 0.7],
		["skirt_l", 165, 185, 148, 206, 28, 70.0, 3.0, 0.7],
		["skirt_r", 258, 224, 276, 246, 28, 70.0, 3.0, 0.7],
		["skirt_c", 232, 228, 244, 256, 28, 80.0, 3.2, 0.6],
		["cuff", 305, 218, 336, 245, 28, 80.0, 3.0, 0.6],
	],
}

const ELLEN := {
	"art": "res://art/ellen.png", "art_dir": -1.0, "pivot_x": 740.0,
	"face": Rect2(620.0, 40.0, 220.0, 220.0),
	"zones": [
		["wpn_blade", 470, 860, 20, 1130, 220, 30.0, 2.2, 1.0],
		["wpn_handle", 800, 560, 1170, 110, 140, 50.0, 2.8, 0.7],
		["shark_tail", 700, 900, 470, 1260, 260, 28.0, 1.8, 1.3],
		["spike_tail", 900, 370, 1010, 590, 130, 55.0, 2.4, 1.2],
		["hair_l", 660, 150, 650, 238, 90, 80.0, 3.2, 0.8],
		["hair_r", 790, 140, 810, 218, 70, 80.0, 3.2, 0.8],
		["headdress", 700, 100, 700, 20, 120, 90.0, 3.2, 0.6],
		["skirt", 520, 560, 390, 740, 200, 45.0, 2.3, 1.0],
		["collar", 800, 235, 850, 285, 60, 80.0, 3.0, 0.5],
	],
}

static var _tex_cache: Dictionary = {}
static var _face_cache: Dictionary = {}

static func get_def(cname: String) -> Dictionary:
	match cname:
		"NICOLE":
			return NICOLE
		"ANBY":
			return ANBY
	return ELLEN

## Loads the art (with generated mipmaps) once and caches it.
static func get_texture(cname: String) -> Texture2D:
	if _tex_cache.has(cname):
		return _tex_cache[cname]
	var def := get_def(cname)
	var path: String = def["art"]
	var img: Image = null
	var t := load(path) as Texture2D
	if t != null:
		img = t.get_image()
	if img == null or img.is_empty():
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		push_warning("Missing character art: " + path)
		img = Image.create(64, 128, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.0, 1.0, 1.0))
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_tex_cache[cname] = out
	return out

static func portrait(cname: String) -> Texture2D:
	if _face_cache.has(cname):
		return _face_cache[cname]
	var a := AtlasTexture.new()
	a.atlas = get_texture(cname)
	a.region = get_def(cname)["face"]
	_face_cache[cname] = a
	return a
