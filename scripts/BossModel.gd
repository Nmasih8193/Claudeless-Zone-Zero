class_name BossModel
extends Node3D
## Procedural rig for the Corrupted Colossus.
## Every joint is a damped spring chasing a named pose ("slam_raise", "sweep_hit_r", ...), so
## wind-ups, strikes and recoveries get weight, overshoot and follow-through for free.
## A walk cycle, breathing, hit flinches and footstep events are layered on top.

signal footstep(side: int)

const ZETA := 0.62
const BASE_HIPS := 2.75
const JOINTS := ["torso", "chest", "head", "jaw", "sh_l", "sh_r", "el_l", "el_r", "hand_l", "hand_r", "leg_l", "leg_r", "knee_l", "knee_r"]
const CROUCH := [[0.0, 0.05, -0.1], [0.18, 0.33, -0.72], [0.31, 0.45, -0.98], [0.47, 0.56, -1.23], [0.64, 0.65, -1.43], [1.0, 0.82, -1.83], [1.24, 0.9, -2.05]]

class Spring:
	var x: Vector3 = Vector3.ZERO
	var v: Vector3 = Vector3.ZERO
	var t: Vector3 = Vector3.ZERO

var pose_name: String = ""
var walk_speed: float = 0.0          # set by Boss each frame (m/s)
var tired: float = 0.0               # heavier breathing while recovering

var _nodes: Dictionary = {}
var _springs: Dictionary = {}
var _hips_spring := Spring.new()
var _k: float = 40.0
var _hips: Node3D
var _mats: Array[ShaderMaterial] = []
var _core_mat: ShaderMaterial
var _eye_mat: ShaderMaterial
var _mouth_mat: ShaderMaterial
var _vein_mats: Array[ShaderMaterial] = []
var _core: MeshInstance3D
var _core_light: OmniLight3D
var _shards: Array[Node3D] = []
var _t: float = 0.0
var _walk_phase: float = 0.0
var _walk_amt: float = 0.0
var _last_step: int = 0
var _flash: float = 0.0
var _flash_on: bool = false
var _charge: float = 0.0
var _eye: float = 1.0

# ------------------------------------------------------------------ building helpers
func _mat(c: Color, glow: float = 0.0, rim: float = 0.3, spec: float = 0.1, outline: bool = true) -> ShaderMaterial:
	var m := Fx.toon_mat(c, glow, rim, Color(1.0, 0.35, 0.65))
	m.set_shader_parameter("spec", spec)
	m.set_shader_parameter("shade", Color(0.55, 0.45, 0.75))
	if outline:
		m.next_pass = Fx.outline_mat(0.03)
	_mats.append(m)
	return m

func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	m.scale = scl
	parent.add_child(m)
	return m

func _sph(parent: Node3D, r: float, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 10
	return _mi(parent, s, mat, pos, Vector3.ZERO, scl)

func _cap(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0 + 0.002)
	c.radial_segments = 16
	c.rings = 4
	return _mi(parent, c, mat, pos, rot, scl)

func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(parent, b, mat, pos, rot)

## Cone pointing along +Y of its own frame, rotated by rot.
func _cone(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, segs: int = 6) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return _mi(parent, c, mat, pos + Basis.from_euler(rot) * Vector3(0.0, h * 0.5, 0.0), rot)

func _joint(jname: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	_nodes[jname] = n
	_springs[jname] = Spring.new()
	return n

# ------------------------------------------------------------------ rig
func _ready() -> void:
	var body := _mat(Color(0.1, 0.09, 0.13), 0.0, 0.35, 0.08)
	var armor := _mat(Color(0.24, 0.21, 0.3), 0.0, 0.3, 0.55)
	var dark := _mat(Color(0.13, 0.11, 0.16), 0.0, 0.3, 0.35)
	var vein := _mat(Color(1.0, 0.18, 0.55), 2.6, 0.0, 0.0, false)
	var crystal := _mat(Color(0.4, 0.06, 0.32), 1.3, 0.8, 0.6)
	var claw := _mat(Color(0.85, 0.8, 0.9), 0.4, 0.4, 0.8)
	_vein_mats.append(vein)
	_vein_mats.append(crystal)
	_eye_mat = _mat(Color(1.0, 0.12, 0.16), 6.0, 0.0, 0.0, false)
	_mouth_mat = _mat(Color(1.0, 0.35, 0.6), 3.0, 0.0, 0.0, false)
	_core_mat = _mat(Color(1.0, 0.32, 0.78), 3.0, 0.0, 0.0, false)

	_hips = Node3D.new()
	_hips.position = Vector3(0.0, BASE_HIPS, 0.0)
	add_child(_hips)
	_sph(_hips, 1.0, armor, Vector3.ZERO, Vector3(1.25, 0.7, 0.95))
	_box(_hips, Vector3(1.0, 0.9, 0.2), dark, Vector3(0.0, -0.35, -0.85), Vector3(0.2, 0.0, 0.0))
	_box(_hips, Vector3(0.12, 0.6, 0.06), vein, Vector3(0.0, -0.3, -0.97), Vector3(0.2, 0.0, 0.0))

	# legs
	for side: float in [-1.0, 1.0]:
		var s := "_l" if side < 0.0 else "_r"
		var leg := _joint("leg" + s, _hips, Vector3(side * 1.05, -0.15, 0.0))
		_cap(leg, 0.58, 1.7, body, Vector3(0.0, -0.7, 0.0))
		_box(leg, Vector3(0.75, 0.9, 0.14), armor, Vector3(side * 0.1, -0.6, -0.55), Vector3(0.1, 0.0, 0.0))
		_sph(leg, 0.48, armor, Vector3(0.0, -1.38, -0.18), Vector3(1.0, 0.9, 0.8))
		var knee := _joint("knee" + s, leg, Vector3(0.0, -1.4, 0.0))
		_cap(knee, 0.46, 1.35, body, Vector3(0.0, -0.55, 0.0))
		_box(knee, Vector3(0.6, 0.85, 0.16), dark, Vector3(0.0, -0.55, -0.42))
		_box(knee, Vector3(1.05, 0.45, 1.6), armor, Vector3(0.0, -1.0, -0.25))
		for k in 3:
			_cone(knee, 0.12, 0.45, claw, Vector3((float(k) - 1.0) * 0.32, -1.1, -1.0), Vector3(-PI * 0.5, 0.0, 0.0), 5)

	# torso & chest
	var torso := _joint("torso", _hips, Vector3(0.0, 0.3, 0.0))
	_cap(torso, 0.85, 1.9, body, Vector3(0.0, 0.75, 0.0))
	for i in 3:
		_box(torso, Vector3(1.2 - float(i) * 0.15, 0.08, 0.06), vein, Vector3(0.0, 0.3 + float(i) * 0.38, -0.84))
	var chest := _joint("chest", torso, Vector3(0.0, 1.5, 0.0))
	_sph(chest, 1.0, armor, Vector3(0.0, 0.75, 0.05), Vector3(2.0, 1.25, 1.3))
	_box(chest, Vector3(2.6, 1.5, 0.35), dark, Vector3(0.0, 0.75, -1.1), Vector3(0.12, 0.0, 0.0))
	for side: float in [-1.0, 1.0]:
		_box(chest, Vector3(0.9, 0.07, 0.05), vein, Vector3(side * 0.85, 0.35, -1.27), Vector3(0.12, 0.0, side * 0.5))
		_box(chest, Vector3(0.7, 0.07, 0.05), vein, Vector3(side * 0.8, 1.15, -1.22), Vector3(0.12, 0.0, -side * 0.35))
	_core = _sph(chest, 0.55, _core_mat, Vector3(0.0, 0.75, -1.3))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.58
	ring.outer_radius = 0.8
	_mi(chest, ring, armor, Vector3(0.0, 0.75, -1.25), Vector3(PI * 0.5, 0.0, 0.0))
	_core_light = OmniLight3D.new()
	_core_light.light_color = Color(1.0, 0.3, 0.7)
	_core_light.light_energy = 2.0
	_core_light.omni_range = 10.0
	_core_light.position = Vector3(0.0, 0.75, -2.0)
	chest.add_child(_core_light)
	# corrupted crystals growing out of the back
	var cr := [[0.0, 1.3, 0.9, -0.5, 0.0, 1.5], [-0.7, 1.0, 0.8, -0.7, -0.4, 1.1], [0.7, 1.0, 0.8, -0.7, 0.4, 1.1], [-0.4, 0.3, 0.9, -1.0, -0.2, 0.9], [0.4, 0.3, 0.9, -1.0, 0.2, 0.9]]
	for c: Array in cr:
		_cone(chest, 0.28 * float(c[5]), 1.7 * float(c[5]), crystal, Vector3(float(c[0]), float(c[1]), float(c[2])), Vector3(float(c[3]), 0.0, float(c[4])), 5)
	_cap(chest, 0.45, 0.9, body, Vector3(0.0, 1.55, -0.2))

	# head
	var head := _joint("head", chest, Vector3(0.0, 1.75, -0.4))
	_sph(head, 0.6, armor, Vector3(0.0, 0.2, -0.1), Vector3(1.15, 0.95, 1.25))
	_box(head, Vector3(1.1, 0.35, 0.5), dark, Vector3(0.0, 0.18, -0.62))
	_box(head, Vector3(0.95, 0.12, 0.1), _eye_mat, Vector3(0.0, 0.2, -0.88))
	_cone(head, 0.1, 0.5, armor, Vector3(0.0, 0.62, -0.35), Vector3(-0.5, 0.0, 0.0), 4)
	for side: float in [-1.0, 1.0]:
		var hb := Vector3(side * 0.55, 0.45, -0.05)
		_cone(head, 0.2, 0.9, dark, hb, Vector3(-0.35, 0.0, -side * 0.75), 6)
		var tip := hb + Basis.from_euler(Vector3(-0.35, 0.0, -side * 0.75)) * Vector3(0.0, 0.8, 0.0)
		_cone(head, 0.12, 0.8, crystal, tip, Vector3(0.6, 0.0, -side * 0.25), 5)
	var jaw := _joint("jaw", head, Vector3(0.0, -0.12, -0.15))
	_box(jaw, Vector3(0.95, 0.3, 0.85), armor, Vector3(0.0, -0.15, -0.38))
	_box(jaw, Vector3(0.7, 0.08, 0.6), _mouth_mat, Vector3(0.0, 0.02, -0.42))
	for k in 4:
		_cone(jaw, 0.06, 0.18, claw, Vector3((float(k) - 1.5) * 0.2, 0.0, -0.78), Vector3.ZERO, 4)

	# arms
	for side: float in [-1.0, 1.0]:
		var s := "_l" if side < 0.0 else "_r"
		var sh := _joint("sh" + s, chest, Vector3(side * 2.15, 1.2, 0.0))
		_sph(sh, 0.92, armor, Vector3(side * 0.25, 0.3, 0.0), Vector3(1.15, 0.85, 1.05))
		for k in 3:
			_cone(sh, 0.16, 0.75, crystal, Vector3(side * (0.3 + float(k) * 0.25), 0.9, (float(k) - 1.0) * 0.35), Vector3(0.0, 0.0, -side * (0.25 + float(k) * 0.2)), 5)
		_cap(sh, 0.5, 1.9, body, Vector3(0.0, -0.85, 0.0))
		var el := _joint("el" + s, sh, Vector3(0.0, -1.75, 0.0))
		_cone(el, 0.18, 0.7, dark, Vector3(0.0, 0.0, 0.35), Vector3(PI * 0.62, 0.0, 0.0), 5)
		_cap(el, 0.64, 2.0, armor, Vector3(0.0, -0.85, 0.0))
		_box(el, Vector3(0.08, 1.4, 0.05), vein, Vector3(side * 0.2, -0.85, -0.64))
		var hand := _joint("hand" + s, el, Vector3(0.0, -1.85, 0.0))
		_sph(hand, 0.62, dark, Vector3(0.0, -0.35, 0.0), Vector3(1.0, 0.85, 1.05))
		for k in 3:
			var cx := (float(k) - 1.0) * 0.32
			_cone(hand, 0.14, 0.85, claw, Vector3(cx, -0.65, -0.3), Vector3(PI - 0.35, 0.0, 0.0), 5)
		_cone(hand, 0.14, 0.6, claw, Vector3(-side * 0.45, -0.45, -0.1), Vector3(PI - 0.2, 0.0, side * 0.6), 5)

	# floating corruption shards orbiting the upper body
	for i in 6:
		var sh_node := Node3D.new()
		add_child(sh_node)
		_mi(sh_node, _shard_mesh(), crystal, Vector3.ZERO, Vector3(randf() * TAU, randf() * TAU, 0.0), Vector3.ONE * randf_range(0.6, 1.2))
		_shards.append(sh_node)

	set_pose("idle", 10.0)
	for j: String in JOINTS:
		var sp: Spring = _springs[j]
		sp.x = sp.t
	_hips_spring.x = _hips_spring.t
	tick(0.001, false)

func _shard_mesh() -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.22
	c.height = 0.9
	c.radial_segments = 4
	c.rings = 1
	return c

# ------------------------------------------------------------------ poses
static func _crouch(p: Dictionary, drop: float) -> void:
	var a: float = 0.33
	var b: float = -0.72
	for i in range(1, CROUCH.size()):
		var lo: Array = CROUCH[i - 1]
		var hi: Array = CROUCH[i]
		if drop <= float(hi[0]) or i == CROUCH.size() - 1:
			var f := clampf((drop - float(lo[0])) / (float(hi[0]) - float(lo[0])), 0.0, 1.0)
			a = lerpf(float(lo[1]), float(hi[1]), f)
			b = lerpf(float(lo[2]), float(hi[2]), f)
			break
	p["leg_l"] = Vector3(a, 0.0, -0.07)
	p["leg_r"] = Vector3(a, 0.0, 0.07)
	p["knee_l"] = Vector3(b, 0.0, 0.0)
	p["knee_r"] = Vector3(b, 0.0, 0.0)
	var h: Vector3 = p.get("hips", Vector3.ZERO)
	p["hips"] = Vector3(h.x, -drop, h.z)

static func _mirror(p: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in p:
		var v: Vector3 = p[key]
		var nk := key
		if key.ends_with("_l"):
			nk = key.substr(0, key.length() - 2) + "_r"
		elif key.ends_with("_r"):
			nk = key.substr(0, key.length() - 2) + "_l"
		if key == "hips":
			out[nk] = Vector3(-v.x, v.y, v.z)
		else:
			out[nk] = Vector3(v.x, -v.y, -v.z)
	return out

static func _arms(p: Dictionary, sh: Vector3, el: float, hand: float = 0.2) -> void:
	p["sh_r"] = sh
	p["sh_l"] = Vector3(sh.x, -sh.y, -sh.z)
	p["el_r"] = Vector3(el, 0.0, 0.0)
	p["el_l"] = Vector3(el, 0.0, 0.0)
	p["hand_r"] = Vector3(hand, 0.0, 0.0)
	p["hand_l"] = Vector3(hand, 0.0, 0.0)

static func pose(pname: String) -> Dictionary:
	if pname.ends_with("_l"):
		return _mirror(pose(pname.substr(0, pname.length() - 2) + "_r"))
	var p: Dictionary = {
		"hips": Vector3.ZERO, "torso": Vector3(-0.18, 0.0, 0.0), "chest": Vector3(-0.08, 0.0, 0.0),
		"head": Vector3(0.22, 0.0, 0.0), "jaw": Vector3.ZERO,
	}
	_arms(p, Vector3(0.3, 0.0, 0.22), 0.55)
	_crouch(p, 0.18)
	match pname:
		"slam_raise":
			_crouch(p, 0.0)
			p["hips"] = Vector3(0.0, 0.08, 0.1)
			p["torso"] = Vector3(0.22, 0.0, 0.0)
			p["chest"] = Vector3(0.15, 0.0, 0.0)
			p["head"] = Vector3(0.3, 0.0, 0.0)
			p["jaw"] = Vector3(-0.3, 0.0, 0.0)
			_arms(p, Vector3(2.8, 0.0, -0.3), 0.95, 0.5)
		"slam_hit":
			p["hips"] = Vector3(0.0, 0.0, 0.4)
			_crouch(p, 0.64)
			p["torso"] = Vector3(-0.85, 0.0, 0.0)
			p["chest"] = Vector3(-0.35, 0.0, 0.0)
			p["head"] = Vector3(0.8, 0.0, 0.0)
			_arms(p, Vector3(1.95, 0.0, 0.1), 0.12, -0.3)
		"sweep_wind_r":
			_crouch(p, 0.31)
			p["torso"] = Vector3(-0.25, -0.75, 0.05)
			p["chest"] = Vector3(-0.1, -0.3, 0.0)
			p["head"] = Vector3(0.3, 0.65, 0.0)
			p["sh_r"] = Vector3(0.2, 0.0, 1.25)
			p["el_r"] = Vector3(0.9, 0.0, 0.0)
			p["hand_r"] = Vector3(0.5, 0.0, 0.0)
			p["sh_l"] = Vector3(0.9, 0.0, -0.35)
			p["el_l"] = Vector3(0.8, 0.0, 0.0)
		"sweep_hit_r":
			p["hips"] = Vector3(0.0, 0.0, -0.3)
			_crouch(p, 0.47)
			p["torso"] = Vector3(-0.35, 0.85, -0.05)
			p["chest"] = Vector3(-0.1, 0.35, 0.0)
			p["head"] = Vector3(0.3, -0.95, 0.0)
			p["sh_r"] = Vector3(1.45, 0.0, -0.35)
			p["el_r"] = Vector3(0.25, 0.0, 0.0)
			p["hand_r"] = Vector3(-0.3, 0.0, 0.0)
			p["sh_l"] = Vector3(0.2, 0.0, -0.7)
			p["el_l"] = Vector3(0.6, 0.0, 0.0)
		"charge_crouch":
			p["hips"] = Vector3(0.0, 0.0, 0.3)
			_crouch(p, 0.64)
			p["torso"] = Vector3(-0.75, -0.35, 0.0)
			p["chest"] = Vector3(-0.2, 0.0, 0.0)
			p["head"] = Vector3(0.85, 0.3, 0.0)
			p["sh_r"] = Vector3(0.6, 0.0, 0.5)
			p["sh_l"] = Vector3(-0.2, 0.0, -0.45)
			p["el_r"] = Vector3(0.9, 0.0, 0.0)
		"charge_run":
			_crouch(p, 0.47)
			p["torso"] = Vector3(-0.9, -0.45, 0.0)
			p["chest"] = Vector3(-0.2, 0.0, 0.0)
			p["head"] = Vector3(0.95, 0.35, 0.0)
			p["sh_r"] = Vector3(1.6, 0.0, 0.3)
			p["el_r"] = Vector3(0.9, 0.0, 0.0)
			p["sh_l"] = Vector3(0.6, 0.0, -0.4)
		"roar":
			_crouch(p, 0.0)
			p["hips"] = Vector3(0.0, 0.1, 0.0)
			p["torso"] = Vector3(0.3, 0.0, 0.0)
			p["chest"] = Vector3(0.25, 0.0, 0.0)
			p["head"] = Vector3(0.5, 0.0, 0.0)
			p["jaw"] = Vector3(-0.75, 0.0, 0.0)
			_arms(p, Vector3(0.5, 0.0, 1.4), 0.9, 0.6)
		"stun":
			p["hips"] = Vector3(0.0, 0.0, 0.2)
			_crouch(p, 1.24)
			p["torso"] = Vector3(-0.55, 0.0, 0.0)
			p["chest"] = Vector3(-0.25, 0.0, 0.0)
			p["head"] = Vector3(-0.35, 0.2, 0.15)
			p["jaw"] = Vector3(-0.25, 0.0, 0.0)
			_arms(p, Vector3(0.55, 0.0, 0.1), 0.15, 0.0)
		"dead":
			p["hips"] = Vector3(0.0, 0.0, 0.2)
			_crouch(p, 1.24)
			p["torso"] = Vector3(-0.9, 0.0, 0.1)
			p["chest"] = Vector3(-0.3, 0.0, 0.0)
			p["head"] = Vector3(-0.6, 0.3, 0.2)
			p["jaw"] = Vector3(-0.5, 0.0, 0.0)
			_arms(p, Vector3(0.9, 0.0, 0.3), 0.1, 0.0)
		"leap_crouch":
			p["hips"] = Vector3(0.0, 0.0, 0.3)
			_crouch(p, 1.0)
			p["torso"] = Vector3(-0.6, 0.0, 0.0)
			p["chest"] = Vector3(-0.2, 0.0, 0.0)
			p["head"] = Vector3(0.85, 0.0, 0.0)
			_arms(p, Vector3(-0.6, 0.0, 0.5), 0.5, 0.3)
		"leap_air":
			_crouch(p, 0.0)
			p["leg_l"] = Vector3(1.3, 0.0, -0.15)
			p["leg_r"] = Vector3(1.3, 0.0, 0.15)
			p["knee_l"] = Vector3(-1.9, 0.0, 0.0)
			p["knee_r"] = Vector3(-1.9, 0.0, 0.0)
			p["torso"] = Vector3(0.15, 0.0, 0.0)
			p["chest"] = Vector3(0.1, 0.0, 0.0)
			p["head"] = Vector3(0.1, 0.0, 0.0)
			p["jaw"] = Vector3(-0.5, 0.0, 0.0)
			_arms(p, Vector3(2.7, 0.0, -0.3), 0.7, 0.4)
		"leap_land":
			p["hips"] = Vector3(0.0, 0.0, 0.4)
			_crouch(p, 1.24)
			p["torso"] = Vector3(-0.6, 0.0, 0.0)
			p["chest"] = Vector3(-0.3, 0.0, 0.0)
			p["head"] = Vector3(0.9, 0.0, 0.0)
			p["jaw"] = Vector3(-0.4, 0.0, 0.0)
			_arms(p, Vector3(1.5, 0.0, 0.9), 0.2, -0.3)
		"beam_charge":
			_crouch(p, 0.31)
			p["torso"] = Vector3(0.28, 0.0, 0.0)
			p["chest"] = Vector3(0.3, 0.0, 0.0)
			p["head"] = Vector3(0.45, 0.0, 0.0)
			p["jaw"] = Vector3(-0.3, 0.0, 0.0)
			_arms(p, Vector3(-0.4, 0.0, 1.0), 0.5, 0.6)
		"beam_fire":
			p["hips"] = Vector3(0.0, 0.0, 0.25)
			_crouch(p, 0.47)
			p["torso"] = Vector3(-0.05, 0.0, 0.0)
			p["chest"] = Vector3(0.0, 0.0, 0.0)
			p["head"] = Vector3(0.15, 0.0, 0.0)
			p["jaw"] = Vector3(-0.55, 0.0, 0.0)
			_arms(p, Vector3(0.35, 0.0, 1.1), 1.0, 0.5)
		"volley_r":
			_crouch(p, 0.31)
			p["torso"] = Vector3(-0.1, 0.25, 0.0)
			p["chest"] = Vector3(0.05, 0.0, 0.0)
			p["head"] = Vector3(0.25, -0.2, 0.0)
			p["sh_r"] = Vector3(1.75, 0.0, 0.0)
			p["el_r"] = Vector3(0.05, 0.0, 0.0)
			p["hand_r"] = Vector3(-0.8, 0.0, 0.0)
			p["sh_l"] = Vector3(0.3, 0.0, -0.4)
		"stomp_raise_r":
			p["leg_l"] = Vector3(0.1, 0.0, -0.1)
			p["knee_l"] = Vector3(-0.2, 0.0, 0.0)
			p["leg_r"] = Vector3(1.25, 0.0, 0.15)
			p["knee_r"] = Vector3(-1.4, 0.0, 0.0)
			p["hips"] = Vector3(-0.25, 0.1, 0.0)
			p["torso"] = Vector3(0.15, 0.0, -0.08)
			p["chest"] = Vector3(0.1, 0.0, 0.0)
			p["head"] = Vector3(0.2, 0.0, 0.0)
			_arms(p, Vector3(0.6, 0.0, 0.9), 0.7)
		"stomp_hit_r":
			p["leg_r"] = Vector3(0.35, 0.0, 0.12)
			p["knee_r"] = Vector3(-0.5, 0.0, 0.0)
			p["leg_l"] = Vector3(0.45, 0.0, -0.1)
			p["knee_l"] = Vector3(-0.95, 0.0, 0.0)
			p["hips"] = Vector3(0.1, -0.35, 0.0)
			p["torso"] = Vector3(-0.45, 0.0, 0.06)
			p["chest"] = Vector3(-0.2, 0.0, 0.0)
			p["head"] = Vector3(0.6, 0.0, 0.0)
			p["jaw"] = Vector3(-0.3, 0.0, 0.0)
			_arms(p, Vector3(0.9, 0.0, 0.6), 0.4)
		"eruption":
			p["hips"] = Vector3(0.0, 0.0, 0.45)
			_crouch(p, 1.0)
			p["torso"] = Vector3(-0.95, 0.0, 0.0)
			p["chest"] = Vector3(-0.35, 0.0, 0.0)
			p["head"] = Vector3(0.95, 0.0, 0.0)
			_arms(p, Vector3(2.0, 0.0, 0.25), 0.0, -0.4)
		"enrage_gather":
			_crouch(p, 0.64)
			p["torso"] = Vector3(-0.35, 0.0, 0.0)
			p["chest"] = Vector3(-0.25, 0.0, 0.0)
			p["head"] = Vector3(-0.2, 0.0, 0.0)
			_arms(p, Vector3(1.35, 0.0, -0.75), 1.3, 0.4)
		"enrage_release":
			_crouch(p, 0.0)
			p["hips"] = Vector3(0.0, 0.15, 0.0)
			p["torso"] = Vector3(0.4, 0.0, 0.0)
			p["chest"] = Vector3(0.3, 0.0, 0.0)
			p["head"] = Vector3(0.65, 0.0, 0.0)
			p["jaw"] = Vector3(-0.85, 0.0, 0.0)
			_arms(p, Vector3(0.2, 0.0, 1.7), 0.3, 0.8)
		"recover":
			_crouch(p, 0.31)
			p["torso"] = Vector3(-0.4, 0.0, 0.0)
			p["chest"] = Vector3(-0.15, 0.0, 0.0)
			p["head"] = Vector3(0.45, 0.0, 0.0)
			p["jaw"] = Vector3(-0.15, 0.0, 0.0)
			_arms(p, Vector3(0.45, 0.0, 0.15), 0.3)
	return p

## speed scales spring stiffness: ~0.6 slow wind-up, 1 normal, 3 snappy strike.
func set_pose(pname: String, speed: float = 1.0) -> void:
	pose_name = pname
	_k = 40.0 * speed * speed
	var p := BossModel.pose(pname)
	for j: String in JOINTS:
		var sp: Spring = _springs[j]
		sp.t = p.get(j, Vector3.ZERO)
	_hips_spring.t = p.get("hips", Vector3.ZERO)

# ------------------------------------------------------------------ effects api
func flinch(strength: float) -> void:
	for j: String in ["torso", "chest", "head"]:
		var sp: Spring = _springs[j]
		sp.v += Vector3(randf_range(0.2, 1.0) * strength, randf_range(-1.0, 1.0) * strength * 0.6, randf_range(-1.0, 1.0) * strength * 0.4)
	_flash = 1.0

func kick(jname: String, v: Vector3) -> void:
	if _springs.has(jname):
		var sp: Spring = _springs[jname]
		sp.v += v

## 0..1: core brightness/size and its light (charging the beam, enrage...).
func set_charge(a: float) -> void:
	_charge = clampf(a, 0.0, 1.0)

func set_eye(e: float) -> void:
	_eye = e

## World position of a named point, for effects: hand_l/hand_r/core/head/foot_l/foot_r/mouth.
func point(pname: String) -> Vector3:
	match pname:
		"core":
			return _core.global_position
		"head":
			return (_nodes["head"] as Node3D).to_global(Vector3(0.0, 0.2, -0.9))
		"mouth":
			return (_nodes["jaw"] as Node3D).to_global(Vector3(0.0, 0.0, -0.7))
		"hand_l", "hand_r":
			return (_nodes[pname] as Node3D).to_global(Vector3(0.0, -0.7, -0.2))
		"foot_l":
			return (_nodes["knee_l"] as Node3D).to_global(Vector3(0.0, -1.1, -0.3))
		"foot_r":
			return (_nodes["knee_r"] as Node3D).to_global(Vector3(0.0, -1.1, -0.3))
	return global_position

# ------------------------------------------------------------------ simulation
func tick(delta: float, frozen: bool) -> void:
	if frozen:
		return
	delta = clampf(delta, 0.0, 0.05)
	_t += delta
	var c := 2.0 * ZETA * sqrt(_k)
	var h := delta * 0.5
	for _i in 2:
		for j: String in JOINTS:
			var sp: Spring = _springs[j]
			sp.v += (-_k * (sp.x - sp.t) - c * sp.v) * h
			sp.x += sp.v * h
		_hips_spring.v += (-_k * (_hips_spring.x - _hips_spring.t) - c * _hips_spring.v) * h
		_hips_spring.x += _hips_spring.v * h

	# walk cycle (only while idling / walking between attacks)
	var want := clampf(walk_speed / 3.0, 0.0, 1.4) if pose_name == "idle" or pose_name == "charge_run" else 0.0
	_walk_amt = lerpf(_walk_amt, want, 1.0 - exp(-6.0 * delta))
	if _walk_amt > 0.02:
		_walk_phase += delta * (2.4 + walk_speed * 0.6)
		var st := int(floor(_walk_phase / PI))
		if st != _last_step:
			_last_step = st
			footstep.emit(st % 2)
	var w := _walk_amt
	var s := sin(_walk_phase)
	var add: Dictionary = {
		"leg_l": Vector3(s * 0.5 * w, 0.0, 0.0),
		"leg_r": Vector3(-s * 0.5 * w, 0.0, 0.0),
		"knee_l": Vector3(-maxf(0.0, sin(_walk_phase + 1.3)) * 0.9 * w, 0.0, 0.0),
		"knee_r": Vector3(-maxf(0.0, sin(_walk_phase + PI + 1.3)) * 0.9 * w, 0.0, 0.0),
		"torso": Vector3(0.0, s * 0.08 * w, s * 0.05 * w),
		"sh_l": Vector3(-s * 0.25 * w, 0.0, 0.0),
		"sh_r": Vector3(s * 0.25 * w, 0.0, 0.0),
	}
	var breath := sin(_t * (1.6 + tired * 1.6)) * (1.0 + tired * 1.5)
	add["chest"] = add.get("chest", Vector3.ZERO) + Vector3(breath * 0.03, 0.0, 0.0)
	add["head"] = Vector3(-breath * 0.02, sin(_t * 0.7) * 0.05, 0.0)
	add["sh_l"] = add["sh_l"] + Vector3(0.0, 0.0, -breath * 0.03)
	add["sh_r"] = add["sh_r"] + Vector3(0.0, 0.0, breath * 0.03)
	for j: String in JOINTS:
		var sp: Spring = _springs[j]
		var n: Node3D = _nodes[j]
		n.rotation = sp.x + (add[j] as Vector3 if add.has(j) else Vector3.ZERO)
	var bob := -absf(cos(_walk_phase)) * 0.14 * w + breath * 0.025
	_hips.position = Vector3(0.0, BASE_HIPS + bob, 0.0) + _hips_spring.x

	# floating shards
	for i in _shards.size():
		var a := _t * 0.6 + TAU * float(i) / float(_shards.size())
		var r := 3.4 + 0.4 * sin(_t * 1.3 + float(i))
		var sn := _shards[i]
		sn.position = Vector3(cos(a) * r, 5.0 + sin(_t * 1.1 + float(i) * 1.7) * 0.9 + float(i % 3) * 0.6, sin(a) * r)
		sn.rotation = Vector3(_t * 0.9 + float(i), _t * 1.3, 0.0)

	# glow / flash
	_flash = maxf(_flash - delta * 6.0, 0.0)
	var pulse := 0.5 + 0.5 * sin(_t * (3.0 + _charge * 14.0))
	_core_mat.set_shader_parameter("glow", 2.5 + _charge * 9.0 + pulse * (1.0 + _charge * 2.0))
	_core.scale = Vector3.ONE * (1.0 + _charge * 0.55 + pulse * 0.05)
	_core_light.light_energy = (1.6 + _charge * 7.0 + pulse * 0.6) * _eye
	_eye_mat.set_shader_parameter("glow", 6.0 * _eye)
	for vm in _vein_mats:
		vm.set_shader_parameter("glow", (1.6 + _charge * 3.5 + pulse * 0.6) * maxf(_eye, 0.25))
	if _flash > 0.0 or _flash_on:
		_flash_on = _flash > 0.0
		for m in _mats:
			m.set_shader_parameter("flash", _flash * 0.8)
