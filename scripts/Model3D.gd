class_name Model3D
extends CharacterView
## Procedural 3D character model built from primitives (stylised, toon-shaded, outlined).
## Skeleton = nested Node3D pivots. Secondary motion = a 3D spring per "jiggle pivot":
## hair, ribbons, tails, skirt panels, plush ears and weapons all swing and lag behind movement.

const SKIRT_BASE_K := 55.0

class JNode:
	var node: Node3D
	var d: Vector3 = Vector3.DOWN
	var k: float = 40.0
	var c: float = 2.5
	var lag: float = 0.06
	var inertia: float = 0.012
	var limit: float = 1.0
	var wind: float = 0.15
	var phase: float = 0.0
	var yaw: float = 0.0
	var rot: Vector3 = Vector3.ZERO
	var rotv: Vector3 = Vector3.ZERO

static var _outline: StandardMaterial3D

var _root: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _elbow_r: Node3D
var _elbow_l: Node3D
var _hand_r: Node3D
var _hand_l: Node3D
var _leg_r: Node3D
var _leg_l: Node3D
var _knee_r: Node3D
var _knee_l: Node3D
var _jn: Array = []
var _mats: Array = []
var _weapon: JNode = null
var _pose_arm_r: Vector3 = Vector3(0.15, 0.0, 0.0)
var _pose_arm_l: Vector3 = Vector3(0.1, 0.0, 0.0)
var _pose_elbow_r: float = 0.25
var _pose_elbow_l: float = 0.2

var _t: float = 0.0
var _run_phase: float = 0.0
var _v_smooth: Vector3 = Vector3.ZERO
var _prev_v: Vector3 = Vector3.ZERO
var _atk: float = 0.0
var _atk_v: float = 0.0
var _pitch: float = 0.0
var _pitch_v: float = 0.0
var _hop: float = 0.0
var _hop_v: float = 0.0
var _sq: float = 0.0
var _sq_v: float = 0.0
var _flash: float = 0.0
var _flash_on: bool = false
var _swing_dir: float = 1.0

# ------------------------------------------------------------------ helpers
func _mat(color: Color, outline: bool = true, emit: float = 0.0) -> StandardMaterial3D:
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.albedo_color = Color(0.07, 0.05, 0.09)
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = 0.012
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	m.set_meta("emit", emit)
	if outline:
		m.next_pass = _outline
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
	s.radial_segments = 16
	s.rings = 8
	return _mi(parent, s, mat, pos, Vector3.ZERO, scl)

func _cap(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0 + 0.002)
	c.radial_segments = 12
	c.rings = 4
	return _mi(parent, c, mat, pos, rot, scl)

func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(parent, b, mat, pos, rot)

func _cyl(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 1
	return _mi(parent, c, mat, pos, rot)

func _align(d: Vector3) -> Basis:
	var u := d.dot(Vector3.UP)
	if u > 0.999:
		return Basis.IDENTITY
	if u < -0.999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, d))

func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

## A spring pivot. The item hangs/points along d (in the parent's frame) and lags behind motion.
func _jig(parent: Node3D, pos: Vector3, d: Vector3, k: float, c: float, lag: float = 0.06, inertia: float = 0.012, limit: float = 1.0, yaw: float = 0.0) -> JNode:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	var j := JNode.new()
	j.node = p
	j.d = d.normalized()
	j.k = k
	j.c = c
	j.lag = lag
	j.inertia = inertia
	j.limit = limit
	j.phase = float(_jn.size()) * 1.7
	j.yaw = yaw
	_jn.append(j)
	return j

## Chain of capsule segments, each a spring pivot nested in the previous one (whip-like follow-through).
func _chain(parent: Node3D, pos: Vector3, dirs: Array, seg_len: float, r0: float, r1: float, mat: Material, k: float, c: float, lag: float = 0.07, inertia: float = 0.015, limit: float = 0.9, yaw: float = 0.0) -> JNode:
	var n := dirs.size()
	var cur: Node3D = parent
	var cur_pos := pos
	var last: JNode = null
	for i in n:
		var d: Vector3 = dirs[i]
		d = d.normalized()
		var f := float(i) / float(maxi(n - 1, 1))
		var j := _jig(cur, cur_pos, d, k * (1.0 + 0.12 * float(i)), c, lag * (1.0 + 0.2 * float(i)), inertia, limit, yaw)
		var r := lerpf(r0, r1, f)
		_cap(j.node, r, seg_len + r, mat, d * seg_len * 0.5, _align(d).get_euler())
		cur = j.node
		cur_pos = d * seg_len
		last = j
	return last

# ------------------------------------------------------------------ rig
func setup(cname: String) -> void:
	_root = Node3D.new()
	add_child(_root)
	match cname:
		"NICOLE":
			_build_rig(Color(0.98, 0.85, 0.78), Color(0.96, 0.62, 0.72), Color(0.55, 0.8, 0.35), Color(0.92, 0.92, 0.94), Color(0.13, 0.13, 0.15), Color(0.1, 0.1, 0.12), Color(0.11, 0.11, 0.13), Color(0.12, 0.12, 0.14))
			_extras_nicole()
		"ANBY":
			_build_rig(Color(0.98, 0.88, 0.82), Color(0.88, 0.9, 0.95), Color(0.95, 0.65, 0.2), Color(0.55, 0.82, 0.18), Color(0.13, 0.14, 0.15), Color(0.1, 0.1, 0.12), Color(0.12, 0.12, 0.14), Color(0.55, 0.82, 0.18))
			_extras_anby()
		_:
			_build_rig(Color(0.98, 0.9, 0.86), Color(0.1, 0.09, 0.12), Color(0.85, 0.15, 0.2), Color(0.12, 0.11, 0.15), Color(0.12, 0.11, 0.15), Color(0.1, 0.09, 0.12), Color(0.3, 0.22, 0.22), Color(0.1, 0.1, 0.12))
			_extras_ellen()

func _build_rig(skin: Color, hair: Color, eye: Color, top: Color, sleeve: Color, bottom: Color, legs: Color, boots: Color) -> void:
	var skin_m := _mat(skin)
	var hair_m := _mat(hair)
	var top_m := _mat(top)
	var sleeve_m := _mat(sleeve)
	var bottom_m := _mat(bottom)
	var legs_m := _mat(legs)
	var boots_m := _mat(boots, false)
	_hips = _node(_root, Vector3(0.0, 1.05, 0.0))
	_sph(_hips, 0.27, bottom_m, Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.62, 0.8))
	_torso = _node(_hips, Vector3(0.0, 0.12, 0.0))
	_cap(_torso, 0.26, 0.8, top_m, Vector3(0.0, 0.38, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.75))
	_cyl(_torso, 0.09, 0.2, skin_m, Vector3(0.0, 0.86, 0.0))
	_head = _node(_torso, Vector3(0.0, 0.95, 0.0))
	_sph(_head, 0.34, skin_m, Vector3(0.0, 0.28, 0.0))
	_sph(_head, 0.37, hair_m, Vector3(0.0, 0.34, 0.03), Vector3(1.0, 0.9, 1.0))
	_box(_head, Vector3(0.6, 0.1, 0.08), hair_m, Vector3(0.0, 0.41, -0.325), Vector3(0.25, 0.0, 0.0))
	var white_m := _mat(Color(0.97, 0.97, 1.0), false)
	var eye_m := _mat(eye, false, 0.4)
	var pupil_m := _mat(Color(0.08, 0.06, 0.1), false)
	for side in [-1.0, 1.0]:
		_sph(_head, 0.07, white_m, Vector3(side * 0.125, 0.27, -0.322), Vector3(1.0, 1.2, 0.35))
		_sph(_head, 0.052, eye_m, Vector3(side * 0.125, 0.265, -0.336), Vector3(1.0, 1.3, 0.35))
		_sph(_head, 0.024, pupil_m, Vector3(side * 0.125, 0.265, -0.345), Vector3(1.0, 1.3, 0.3))
	_box(_head, Vector3(0.06, 0.012, 0.01), pupil_m, Vector3(0.0, 0.1, -0.335))
	for side in [-1.0, 1.0]:
		var sh := _node(_torso, Vector3(side * 0.36, 0.72, 0.0))
		_cap(sh, 0.085, 0.4, sleeve_m, Vector3(0.0, -0.2, 0.0))
		var el := _node(sh, Vector3(0.0, -0.38, 0.0))
		_cap(el, 0.07, 0.38, sleeve_m, Vector3(0.0, -0.19, 0.0))
		var hand := _node(el, Vector3(0.0, -0.38, 0.0))
		_sph(hand, 0.085, skin_m, Vector3.ZERO)
		if side > 0.0:
			_arm_r = sh
			_elbow_r = el
			_hand_r = hand
		else:
			_arm_l = sh
			_elbow_l = el
			_hand_l = hand
	for side in [-1.0, 1.0]:
		var lg := _node(_hips, Vector3(side * 0.15, -0.03, 0.0))
		_cap(lg, 0.12, 0.52, legs_m, Vector3(0.0, -0.25, 0.0))
		var kn := _node(lg, Vector3(0.0, -0.5, 0.0))
		_cap(kn, 0.095, 0.46, legs_m, Vector3(0.0, -0.23, 0.0))
		_box(kn, Vector3(0.26, 0.15, 0.38), boots_m, Vector3(0.0, -0.46, -0.04))
		if side > 0.0:
			_leg_r = lg
			_knee_r = kn
		else:
			_leg_l = lg
			_knee_l = kn

## Hanging skirt of n spring panels. Panels live in a yawed holder so each flares outward (+Z of the holder).
func _skirt(color: Color, n: int, length: float, width: float, k: float, radius: float = 0.2, y: float = -0.06) -> void:
	var m := _mat(color, false)
	for i in n:
		var a := TAU * float(i) / float(n)
		var holder := _node(_hips, Vector3(0.0, y, 0.0))
		holder.rotation.y = a
		var d := Vector3(0.0, -0.9, 0.45).normalized()
		var j := _jig(holder, Vector3(0.0, 0.0, radius), d, k, 2.6, 0.08, 0.016, 1.0, a)
		_box(j.node, Vector3(width, length, 0.03), m, d * length * 0.5, _align(d).get_euler())

# ------------------------------------------------------------------ characters
func _extras_nicole() -> void:
	var pink := _mat(Color(0.96, 0.62, 0.72))
	var black := _mat(Color(0.1, 0.1, 0.12), false)
	var white := _mat(Color(0.95, 0.95, 0.97), false)
	var green := _mat(Color(0.65, 0.8, 0.15))
	var grey := _mat(Color(0.55, 0.58, 0.66))
	# long wavy hair
	_chain(_head, Vector3(0.2, 0.6, 0.12), [Vector3(0.5, -0.4, 0.5), Vector3(0.3, -0.9, 0.3), Vector3(0.1, -1, 0.2), Vector3(-0.1, -1, 0.1), Vector3(0.1, -1, 0.0)], 0.3, 0.11, 0.05, pink, 38.0, 2.1)
	_chain(_head, Vector3(-0.2, 0.5, 0.15), [Vector3(-0.5, -0.5, 0.4), Vector3(-0.3, -0.9, 0.3), Vector3(-0.1, -1, 0.2), Vector3(0.1, -1, 0.1), Vector3(-0.1, -1, 0.0)], 0.3, 0.12, 0.05, pink, 36.0, 2.0)
	_chain(_head, Vector3(0.3, 0.3, -0.05), [Vector3(0.2, -1, 0.0), Vector3(0.1, -1, 0.0)], 0.22, 0.07, 0.045, pink, 60.0, 2.8)
	_chain(_head, Vector3(-0.3, 0.3, -0.05), [Vector3(-0.2, -1, 0.0), Vector3(-0.1, -1, 0.0)], 0.22, 0.07, 0.045, pink, 60.0, 2.8)
	# ribbons
	for side in [-1.0, 1.0]:
		var j := _jig(_head, Vector3(side * 0.16, 0.68, 0.0), Vector3(side * 0.5, 1.0, 0.0), 80.0, 3.2, 0.07, 0.012, 1.0)
		_box(j.node, Vector3(0.26, 0.17, 0.04), black, Vector3(side * 0.06, 0.12, 0.0), Vector3(0.0, 0.0, side * 0.5))
		_box(j.node, Vector3(0.12, 0.1, 0.05), black, Vector3(0.0, 0.05, 0.0))
	# fur-trim shorts
	_cyl(_hips, 0.17, 0.05, white, Vector3(0.15, -0.12, 0.0))
	_cyl(_hips, 0.17, 0.05, white, Vector3(-0.15, -0.12, 0.0))
	_cyl(_hips, 0.29, 0.07, black, Vector3(0.0, 0.1, 0.0))
	# bunny plush
	var pj := _jig(_hips, Vector3(-0.28, 0.0, -0.08), Vector3.DOWN, 55.0, 3.0, 0.08, 0.016, 1.0)
	_sph(pj.node, 0.13, green, Vector3(0.0, -0.14, 0.0), Vector3(1.0, 1.1, 0.8))
	_sph(pj.node, 0.03, white, Vector3(-0.03, -0.12, -0.1), Vector3(1.0, 1.0, 0.4))
	for side in [-1.0, 1.0]:
		var ej := _jig(pj.node, Vector3(side * 0.06, -0.05, 0.0), Vector3(side * 0.15, 1.0, 0.0), 70.0, 3.0, 0.08, 0.016, 1.0)
		_cap(ej.node, 0.032, 0.24, green, Vector3(0.0, 0.12, 0.0))
	# strap tail with ring
	var tail := _chain(_hips, Vector3(0.2, 0.0, 0.15), [Vector3(0.5, -0.3, 0.6), Vector3(0.3, -0.7, 0.6), Vector3(0.0, -1, 0.3), Vector3(-0.2, -1, 0.1), Vector3(-0.3, -1, 0.0)], 0.3, 0.045, 0.03, grey, 32.0, 1.9, 0.09, 0.02, 1.0)
	_cyl(tail.node, 0.07, 0.025, _mat(Color(0.8, 0.75, 0.55), false), Vector3(0.0, -0.36, 0.0), Vector3(PI * 0.5, 0.0, 0.0))
	# suitcase in the right hand
	_weapon = _jig(_hand_r, Vector3(0.0, -0.02, 0.0), Vector3.DOWN, 28.0, 2.0, 0.05, 0.02, 0.9)
	_box(_weapon.node, Vector3(0.7, 0.5, 0.26), _mat(Color(0.18, 0.18, 0.2), false), Vector3(0.0, -0.4, 0.0))
	_box(_weapon.node, Vector3(0.72, 0.04, 0.28), _mat(Color(0.35, 0.3, 0.15), false), Vector3(0.0, -0.4, 0.0))
	_cyl(_weapon.node, 0.15, 0.012, _mat(Color(0.9, 0.7, 0.2), false, 0.8), Vector3(0.0, -0.4, -0.135), Vector3(PI * 0.5, 0.0, 0.0))
	_box(_weapon.node, Vector3(0.1, 0.03, 0.03), _mat(Color(1.0, 0.45, 0.1), false, 1.5), Vector3(0.25, -0.62, -0.14))
	_pose_arm_r = Vector3(0.1, 0.0, 0.1)
	_pose_elbow_r = 0.15
	_pose_arm_l = Vector3(1.3, 0.0, -0.25)       # peace-sign pose
	_pose_elbow_l = 1.1

func _extras_anby() -> void:
	var silver := _mat(Color(0.88, 0.9, 0.95))
	var black := _mat(Color(0.1, 0.1, 0.12))
	var steel := _mat(Color(0.6, 0.63, 0.68), false)
	# chunky bob + headphones
	for side in [-1.0, 1.0]:
		_chain(_head, Vector3(side * 0.28, 0.3, 0.0), [Vector3(side * 0.15, -1, 0.0), Vector3(side * 0.1, -1, 0.05)], 0.16, 0.12, 0.09, silver, 85.0, 3.2)
		_chain(_head, Vector3(side * 0.15, 0.35, 0.25), [Vector3(0.0, -1, 0.2), Vector3(0.0, -1, 0.1)], 0.15, 0.12, 0.09, silver, 85.0, 3.2)
		_sph(_head, 0.09, black, Vector3(side * 0.37, 0.3, 0.0))
	_skirt(Color(0.1, 0.1, 0.12), 6, 0.38, 0.3, 60.0)
	# black jacket panel on the torso
	_box(_torso, Vector3(0.1, 0.5, 0.04), _mat(Color(0.1, 0.1, 0.12), false), Vector3(0.0, 0.4, -0.2))
	# sword (blade runs along the forearm direction when the arm is raised)
	_weapon = _jig(_hand_r, Vector3(0.0, -0.02, 0.0), Vector3(0.2, -1.0, 0.0), 50.0, 3.5, 0.04, 0.015, 0.6)
	_box(_weapon.node, Vector3(0.14, 0.1, 0.05), _mat(Color(0.2, 0.2, 0.22), false), Vector3(0.0, -0.1, 0.0))
	_box(_weapon.node, Vector3(0.05, 1.35, 0.14), steel, Vector3(0.0, -0.8, 0.0))
	_pose_arm_r = Vector3(1.25, 0.0, 0.0)
	_pose_elbow_r = 0.35
	_pose_arm_l = Vector3(0.15, 0.0, 0.0)

func _extras_ellen() -> void:
	var black := _mat(Color(0.1, 0.09, 0.12))
	var white := _mat(Color(0.95, 0.95, 0.97), false)
	var red := _mat(Color(0.8, 0.12, 0.18), false)
	var tail_m := _mat(Color(0.27, 0.2, 0.33))
	var steel := _mat(Color(0.6, 0.62, 0.7), false)
	# bob hair
	for side in [-1.0, 1.0]:
		_chain(_head, Vector3(side * 0.3, 0.3, 0.0), [Vector3(side * 0.15, -1, 0.0), Vector3(side * 0.1, -1, 0.05)], 0.18, 0.12, 0.09, black, 80.0, 3.2)
		_chain(_head, Vector3(side * 0.15, 0.35, 0.25), [Vector3(0.0, -1, 0.2), Vector3(0.0, -1, 0.1)], 0.16, 0.12, 0.09, black, 80.0, 3.2)
		_sph(_head, 0.04, red, Vector3(side * 0.31, 0.12, 0.0))
	# maid headdress with frills
	_box(_head, Vector3(0.66, 0.09, 0.2), white, Vector3(0.0, 0.64, -0.08), Vector3(-0.3, 0.0, 0.0))
	for side in [-1.0, 1.0]:
		var fj := _jig(_head, Vector3(side * 0.2, 0.68, -0.05), Vector3(side * 0.2, 1.0, 0.0), 90.0, 3.2, 0.06, 0.012, 0.9)
		_box(fj.node, Vector3(0.18, 0.14, 0.04), white, Vector3(0.0, 0.07, 0.0))
	# dress details
	_box(_torso, Vector3(0.36, 0.55, 0.03), white, Vector3(0.0, 0.28, -0.205))
	_cyl(_torso, 0.2, 0.06, white, Vector3(0.0, 0.84, 0.0))
	_box(_torso, Vector3(0.18, 0.1, 0.04), red, Vector3(0.0, 0.5, 0.2))
	for side in [-1.0, 1.0]:
		_sph(_torso, 0.13, black, Vector3(side * 0.36, 0.74, 0.0))
		_sph(_torso, 0.09, white, Vector3(side * 0.36, 0.2, 0.0), Vector3(1.0, 0.5, 1.0))
	_skirt(Color(0.1, 0.09, 0.12), 8, 0.4, 0.26, 45.0, 0.2, -0.05)
	_skirt(Color(0.93, 0.93, 0.97), 8, 0.24, 0.26, 42.0, 0.22, -0.16)
	# red high heels
	for side in [-1.0, 1.0]:
		var kn: Node3D = _knee_r if side > 0.0 else _knee_l
		_box(kn, Vector3(0.1, 0.12, 0.1), red, Vector3(0.0, -0.5, 0.14))
	# big shark tail
	var tail := _chain(_hips, Vector3(0.0, -0.05, 0.22), [Vector3(0, -0.1, 1), Vector3(0, -0.35, 0.9), Vector3(0, -0.65, 0.7), Vector3(0, -0.9, 0.4), Vector3(0, -1, 0.15), Vector3(0, -1, -0.1)], 0.42, 0.24, 0.06, tail_m, 22.0, 1.5, 0.09, 0.02, 0.8)
	for side in [-1.0, 1.0]:
		_box(tail.node, Vector3(0.04, 0.36, 0.2), tail_m, Vector3(side * 0.06, -0.38, 0.0), Vector3(0.0, 0.0, side * 0.45))
	# thin spiked tail
	var spike := _chain(_hips, Vector3(0.2, 0.1, 0.25), [Vector3(0.4, 0.3, 0.9), Vector3(0.5, -0.1, 0.8), Vector3(0.5, -0.4, 0.6), Vector3(0.3, -0.8, 0.4)], 0.25, 0.03, 0.02, black, 40.0, 2.0, 0.09, 0.02, 1.0)
	_box(spike.node, Vector3(0.03, 0.22, 0.1), black, Vector3(0.0, -0.2, 0.0), Vector3(0.0, 0.0, 0.5))
	# scythe: shaft runs through the hand, blade at the top
	_weapon = _jig(_hand_r, Vector3(0.0, 0.0, 0.0), Vector3.UP, 25.0, 2.0, 0.04, 0.012, 0.7)
	_cyl(_weapon.node, 0.035, 2.0, _mat(Color(0.35, 0.36, 0.4), false), Vector3(0.0, 0.35, 0.0))
	_box(_weapon.node, Vector3(0.03, 0.3, 1.1), steel, Vector3(0.0, 1.28, -0.5), Vector3(-0.15, 0.0, 0.0))
	_box(_weapon.node, Vector3(0.05, 0.1, 0.12), red, Vector3(0.0, 1.05, 0.0))
	_pose_arm_r = Vector3(0.35, 0.0, 0.1)
	_pose_elbow_r = 0.55

# ------------------------------------------------------------------ simulation
func _step_jiggle(delta: float, vl: Vector3, al: Vector3) -> void:
	for jv in _jn:
		var j: JNode = jv
		var vf := vl.rotated(Vector3.UP, -j.yaw)
		var af := al.rotated(Vector3.UP, -j.yaw)
		var target := j.d.cross(-vf) * j.lag
		var wind := Vector3(sin(_t * 1.8 + j.phase), 0.0, cos(_t * 2.2 + j.phase * 1.3)) * 0.12
		var force := -j.k * (j.rot - target) - j.c * j.rotv + j.d.cross(-af) * j.inertia + j.d.cross(wind)
		j.rotv += force * delta
		j.rot += j.rotv * delta
		var l := j.rot.length()
		if l > j.limit:
			j.rot *= j.limit / l
			j.rotv *= 0.6
		j.node.basis = Basis.from_euler(j.rot)

static func _step(x: float, v: float, target: float, k: float, c: float, dt: float) -> Vector2:
	v += (-k * (x - target) - c * v) * dt
	x += v * dt
	return Vector2(x, v)

func tick(delta: float, world_vel: Vector3, st: int, _view_yaw: float, facing_yaw: float) -> void:
	delta = clampf(delta, 0.0001, 1.0 / 30.0)
	_t += delta
	var v := world_vel.limit_length(30.0)
	_v_smooth = _v_smooth.lerp(v, 1.0 - exp(-18.0 * delta))
	var acc := ((_v_smooth - _prev_v) / delta).limit_length(250.0)
	_prev_v = _v_smooth
	_root.rotation.y = lerp_angle(_root.rotation.y, facing_yaw, 1.0 - exp(-22.0 * delta))
	var vl := _v_smooth.rotated(Vector3.UP, -_root.rotation.y)
	var al := acc.rotated(Vector3.UP, -_root.rotation.y)
	_step_jiggle(delta, vl, al)
	_step_body(delta, st, _v_smooth.length())

func _step_body(delta: float, st: int, speed: float) -> void:
	var moving := st == Player.State.MOVE and speed > 0.5
	var f := 0.0
	if moving:
		f = clampf(speed / GameConfig.PLAYER_SPEED, 0.0, 1.0)
		_run_phase += delta * (7.0 + speed * 0.9)
	var s := sin(_run_phase)
	var pitch_t := -0.12 * f
	var hop_t := absf(s) * 0.07 * f
	var sq_t := 0.012 * sin(_t * 2.2)
	match st:
		Player.State.DODGE:
			pitch_t = -0.7
			sq_t = -0.12
		Player.State.SEQ:
			sq_t += 0.04 * sin(_t * 16.0)
			hop_t = 0.1 + 0.05 * sin(_t * 12.0)
		Player.State.DEAD:
			pitch_t = 1.5
			sq_t = -0.05
	var r := _step(_pitch, _pitch_v, pitch_t, 90.0, 8.0, delta)
	_pitch = r.x
	_pitch_v = r.y
	r = _step(_hop, _hop_v, hop_t, 220.0, 12.0, delta)
	_hop = maxf(r.x, 0.0)
	_hop_v = r.y
	r = _step(_sq, _sq_v, sq_t, 160.0, 9.0, delta)
	_sq = r.x
	_sq_v = r.y
	r = _step(_atk, _atk_v, 0.0, 120.0, 7.0, delta)
	_atk = r.x
	_atk_v = r.y
	_root.rotation.x = _pitch
	_root.position.y = _hop
	_root.scale = Vector3(1.0 - _sq * 0.5, 1.0 + _sq, 1.0 - _sq * 0.5)
	# legs
	_leg_r.rotation.x = s * 0.9 * f
	_leg_l.rotation.x = -s * 0.9 * f
	_knee_r.rotation.x = -maxf(0.0, sin(_run_phase + 1.2)) * 1.1 * f
	_knee_l.rotation.x = -maxf(0.0, sin(_run_phase + PI + 1.2)) * 1.1 * f
	if st == Player.State.DODGE:
		_leg_r.rotation.x = 0.6
		_leg_l.rotation.x = -0.5
		_knee_l.rotation.x = -0.8
	# torso / arms
	var breathe := sin(_t * 2.2)
	_torso.scale.y = 1.0 + 0.012 * breathe
	_hips.position.y = 1.05
	_torso.rotation.y = s * 0.12 * f + _atk * 0.3
	_torso.rotation.x = -0.05 * f
	_arm_r.rotation = _pose_arm_r + Vector3(-s * 0.6 * f + _atk, 0.0, 0.0)
	_arm_l.rotation = _pose_arm_l + Vector3(s * 0.6 * f + 0.02 * breathe, 0.0, 0.0)
	_elbow_r.rotation.x = _pose_elbow_r
	_elbow_l.rotation.x = _pose_elbow_l
	_head.rotation.x = -0.05 * breathe - _pitch * 0.4
	# hurt flash
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 5.0, 0.0)
		_flash_on = true
		for mv in _mats:
			var m: StandardMaterial3D = mv
			m.emission_enabled = true
			m.emission = Color(1.0, 0.2, 0.15)
			m.emission_energy_multiplier = _flash * 1.6
	elif _flash_on:
		_flash_on = false
		for mv in _mats:
			var m: StandardMaterial3D = mv
			var e: float = m.get_meta("emit")
			m.emission_enabled = e > 0.0
			m.emission = m.albedo_color
			m.emission_energy_multiplier = e

# ------------------------------------------------------------------ events
func _kick(strength: float) -> void:
	for jv in _jn:
		var j: JNode = jv
		j.rotv += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength

func _kick_weapon(v: Vector3) -> void:
	if _weapon != null:
		_weapon.rotv += v

func on_attack(heavy: bool) -> void:
	_swing_dir = -_swing_dir
	var amt := 1.6 if heavy else 1.0
	_atk_v += 14.0 * amt
	_pitch_v += -1.5 * amt
	_sq_v += 1.5 * amt
	_kick(3.0 * amt)
	_kick_weapon(Vector3(-9.0 * amt, 0.0, _swing_dir * 7.0 * amt))

func on_step(heavy: bool) -> void:
	_swing_dir = -_swing_dir
	var amt := 1.8 if heavy else 1.0
	_atk_v += 12.0 * amt
	_pitch_v += -1.0 * amt
	_sq_v += 1.2 * amt
	_kick(3.5 * amt)
	_kick_weapon(Vector3(-8.0 * amt, 0.0, _swing_dir * 8.0 * amt))

func on_dodge() -> void:
	_pitch_v += -2.0
	_kick(4.0)

func on_hurt() -> void:
	_flash = 1.0
	_pitch_v += 3.0
	_sq_v -= 2.5
	_kick(6.0)

func on_swap_in() -> void:
	_hop_v += 5.0
	_sq_v += 3.0
	_kick(5.0)

func on_dead() -> void:
	_kick(5.0)
