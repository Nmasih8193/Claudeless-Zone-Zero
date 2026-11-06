class_name Puppet
extends CharacterView
## 2.5D cut-out puppet built straight from the character art.
## The art is a finely subdivided 3D plane; a generated vertex shader bends it around "jiggle zones"
## (hair, ribbons, tails, skirt hems, weapons...). Each zone is a damped spring simulated on the CPU,
## driven by movement, acceleration, wind and combat impulses. Body-level springs add squash/stretch,
## lean, hop, yaw sway and a paper-turn when the character changes facing.

const WORLD_HEIGHT := 3.0
const GRID_X := 44
const LAG := 0.03          # trailing offset per m/s of movement (x strength)
const INERTIA := 0.012     # reaction to acceleration (x strength)
const LIMIT := 0.45        # max zone travel in metres (x strength)
const WIND := 0.05         # idle sway amplitude (x strength)
const POWER := 1.4         # falloff exponent along a zone (higher = only the tip moves)

var art_dir: float = 1.0

var _body: Node3D
var _mat: ShaderMaterial
var _n: int = 0
var _params: Array[StringName] = []
var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _k: PackedFloat32Array = PackedFloat32Array()
var _c: PackedFloat32Array = PackedFloat32Array()
var _lag: PackedFloat32Array = PackedFloat32Array()
var _inertia: PackedFloat32Array = PackedFloat32Array()
var _limit: PackedFloat32Array = PackedFloat32Array()
var _imp: PackedFloat32Array = PackedFloat32Array()
var _phase: PackedFloat32Array = PackedFloat32Array()
var _weapon_idx: Array[int] = []

var _t: float = 0.0
var _run_phase: float = 0.0
var _face_dir: float = 1.0
var _flip_cur: float = 1.0
var _v_smooth: Vector2 = Vector2.ZERO
var _prev_v: Vector2 = Vector2.ZERO
var _sq: float = 0.0
var _sq_v: float = 0.0
var _roll: float = 0.0
var _roll_v: float = 0.0
var _yaw: float = 0.0
var _yaw_v: float = 0.0
var _hop: float = 0.0
var _hop_v: float = 0.0
var _flash: float = 0.0
var _swing_dir: float = 1.0
var _dead: bool = false

# ------------------------------------------------------------------ setup
func setup(cname: String) -> void:
	var def: Dictionary = PuppetConfig.get_def(cname)
	var tex: Texture2D = PuppetConfig.get_texture(cname)
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var ps := WORLD_HEIGHT / th
	art_dir = def["art_dir"]
	_face_dir = art_dir
	_flip_cur = 1.0
	var pivot_x: float = def["pivot_x"]
	var rows: Array = def["zones"]
	_n = rows.size()
	var zone_defs: Array = []
	for i in _n:
		var r: Array = rows[i]
		var rx := (float(r[1]) - pivot_x) * ps
		var ry := (th - float(r[2])) * ps
		var tx := (float(r[3]) - pivot_x) * ps
		var ty := (th - float(r[4])) * ps
		zone_defs.append([rx, ry, tx - rx, ty - ry, float(r[5]) * ps])
		_params.append(StringName("o%d" % i))
		var s := float(r[8])
		_k.append(float(r[6]))
		_c.append(float(r[7]))
		_lag.append(LAG * s)
		_inertia.append(INERTIA * s)
		_limit.append(LIMIT * s)
		_imp.append(s)
		_phase.append(float(i) * 1.9)
		_pos.append(Vector2.ZERO)
		_vel.append(Vector2.ZERO)
		if String(r[0]).begins_with("wpn"):
			_weapon_idx.append(i)

	# subdivided plane: x in [-pivot, W-pivot]*ps, y in [0, H]*ps (feet at y = 0)
	var gx := GRID_X
	var gy := clampi(roundi(float(gx) * th / tw), 8, 110)
	var x0 := (0.0 - pivot_x) * ps
	var w_m := tw * ps
	var h_m := th * ps
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in gy + 1:
		for i in gx + 1:
			var u := float(i) / float(gx)
			var v := float(j) / float(gy)
			verts.append(Vector3(x0 + u * w_m, (1.0 - v) * h_m, 0.0))
			uvs.append(Vector2(u, v))
			norms.append(Vector3(0.0, 0.0, 1.0))
	for j in gy:
		for i in gx:
			var a := j * (gx + 1) + i
			var b := a + 1
			var c := a + gx + 1
			var d := c + 1
			idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var sh := Shader.new()
	#sh.code = _build_shader(zone_defs)
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("tex", tex)

	_body = Node3D.new()
	add_child(_body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.extra_cull_margin = 3.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)

	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.02
	disc.radial_segments = 24
	disc.rings = 1
	shadow.mesh = disc
	shadow.material_override = Fx.flat_alpha_mat(Color(0.0, 0.0, 0.0, 0.32))
	shadow.scale = Vector3(1.0, 1.0, 0.55)
	shadow.position = Vector3(0.0, 0.04, 0.0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)

## Generates a vertex shader with one capsule-shaped influence zone per jiggle zone.
func _build_shader(zone_defs: Array) -> Shader:
	var s := "shader_type spatial;\nrender_mode unshaded, cull_disabled, fog_disabled;\n"
	s += "uniform sampler2D tex : source_color, filter_linear_mipmap;\n"
	s += "uniform vec3 flash_color = vec3(1.0, 0.25, 0.2);\n"
	s += "uniform float flash = 0.0;\n"
	for i in zone_defs.size():
		s += "uniform vec2 o%d = vec2(0.0);\n" % i
	s += "void vertex() {\n\tvec2 p = VERTEX.xy;\n\tvec2 d = vec2(0.0);\n"
	for i in zone_defs.size():
		var z: Array = zone_defs[i]
		var w := float(z[4])
		s += "\t{ vec2 r = vec2(%.5f, %.5f); vec2 ab = vec2(%.5f, %.5f);\n" % [float(z[0]), float(z[1]), float(z[2]), float(z[3])]
		s += "\t  float l2 = max(dot(ab, ab), 0.0001); float h = clamp(dot(p - r, ab) / l2, 0.0, 1.0);\n"
		s += "\t  float dist = length(p - (r + ab * h));\n"
		s += "\t  float wgt = (1.0 - smoothstep(%.5f, %.5f, dist)) * pow(h, %.3f);\n" % [w * 0.45, w, POWER]
		s += "\t  d += wgt * o%d; }\n" % i
	s += "\tVERTEX.xy += d;\n}\n"
	s += "void fragment() {\n\tvec4 c = texture(tex, UV);\n\tALBEDO = c.rgb + flash_color * flash;\n\tALPHA = c.a;\n\tALPHA_SCISSOR_THRESHOLD = 0.4;\n}\n"
	var sh := Shader.new()
	sh.code = s
	return sh

# ------------------------------------------------------------------ simulation
static func _step(x: float, v: float, target: float, k: float, c: float, dt: float) -> Vector2:
	v += (-k * (x - target) - c * v) * dt
	x += v * dt
	return Vector2(x, v)

## vel: screen-space velocity (x = right, y = toward the boss), st: Player.State, view_yaw: camera yaw.
func tick(delta: float, world_vel: Vector3, st: int, view_yaw: float, _facing_yaw: float) -> void:
	var right := Vector3(cos(view_yaw), 0.0, -sin(view_yaw))
	var fwd := Vector3(-sin(view_yaw), 0.0, -cos(view_yaw))
	var vel := Vector2(world_vel.dot(right), world_vel.dot(fwd))
	delta = clampf(delta, 0.0001, 1.0 / 30.0)
	rotation.y = view_yaw
	_t += delta
	var v := vel.limit_length(30.0)
	_v_smooth = _v_smooth.lerp(v, 1.0 - exp(-20.0 * delta))
	var acc := ((_v_smooth - _prev_v) / delta).limit_length(400.0)
	_prev_v = _v_smooth
	var speed := _v_smooth.length()
	if absf(_v_smooth.x) > 1.5 and not _dead:
		_face_dir = signf(_v_smooth.x)
	_flip_cur = move_toward(_flip_cur, _face_dir * art_dir, delta * 9.0)
	var xs := 1.0 if _flip_cur >= 0.0 else -1.0
	_step_zones(delta, acc)
	_step_body(delta, st, speed)
	_apply(xs)

func _step_zones(delta: float, acc: Vector2) -> void:
	var run := Vector2(_v_smooth.x, _v_smooth.y * 0.5)
	var accv := Vector2(acc.x, acc.y * 0.5)
	for i in _n:
		var ph := _phase[i]
		var target := -run * _lag[i]
		target += Vector2(sin(_t * 1.7 + ph), cos(_t * 2.3 + ph * 1.3) * 0.5) * WIND * _imp[i]
		var p := _pos[i]
		var v := _vel[i]
		var a := -_k[i] * (p - target) - _c[i] * v - accv * _inertia[i]
		v += a * delta
		p += v * delta
		var l := p.length()
		var lim := _limit[i]
		if l > lim:
			p *= lim / l
			v *= 0.6
		_pos[i] = p
		_vel[i] = v

func _step_body(delta: float, st: int, speed: float) -> void:
	var roll_t := 0.0
	var yaw_t := 0.0
	var sq_t := 0.012 * sin(_t * 2.2)            # breathing
	var hop_t := 0.0
	if st == Player.State.MOVE and speed > 0.5:
		_run_phase += delta * (6.0 + speed * 0.9)
		var f := clampf(speed / GameConfig.PLAYER_SPEED, 0.0, 1.0)
		hop_t = absf(sin(_run_phase)) * 0.14 * f
		sq_t += 0.035 * sin(_run_phase * 2.0) * f
		roll_t = -_v_smooth.x * 0.022
		yaw_t = _v_smooth.x * 0.018
	match st:
		Player.State.DODGE:
			sq_t = -0.14
			roll_t = 0.3
			if absf(_v_smooth.x) > 1.0:
				roll_t = -signf(_v_smooth.x) * 0.55
			yaw_t = _v_smooth.x * 0.03
		Player.State.SEQ:
			sq_t += 0.05 * sin(_t * 16.0)
			roll_t = 0.08 * sin(_t * 9.0)
			hop_t = 0.1 + 0.05 * sin(_t * 12.0)
		Player.State.DEAD:
			roll_t = 1.45
			sq_t = -0.1
	var r := _step(_sq, _sq_v, sq_t, 160.0, 9.0, delta)
	_sq = r.x
	_sq_v = r.y
	r = _step(_roll, _roll_v, roll_t, 90.0, 7.0, delta)
	_roll = r.x
	_roll_v = r.y
	r = _step(_yaw, _yaw_v, yaw_t, 80.0, 8.0, delta)
	_yaw = r.x
	_yaw_v = r.y
	r = _step(_hop, _hop_v, hop_t, 220.0, 12.0, delta)
	_hop = maxf(r.x, 0.0)
	_hop_v = r.y
	_flash = maxf(_flash - delta * 5.0, 0.0)

func _apply(xs: float) -> void:
	_body.position.y = _hop
	_body.rotation.z = _roll
	_body.rotation.y = _yaw
	var fx := _flip_cur
	if absf(fx) < 0.04:
		fx = 0.04 * xs               # never a zero-width (non-invertible) transform
	_body.scale = Vector3(fx * (1.0 - _sq * 0.5), 1.0 + _sq, 1.0)
	for i in _n:
		_mat.set_shader_parameter(_params[i], Vector2(_pos[i].x * xs, _pos[i].y))
	_mat.set_shader_parameter("flash", _flash * 0.6)

# ------------------------------------------------------------------ events (impulses)
## Kicks every zone (screen-space velocity), scaled by each zone's strength.
func kick(vec: Vector2) -> void:
	for i in _n:
		_vel[i] = _vel[i] + vec * _imp[i]

func on_attack(heavy: bool) -> void:
	_swing_dir = -_swing_dir
	var amt := 1.6 if heavy else 1.0
	_roll_v += _swing_dir * 5.0 * amt
	_sq_v += 2.5 * amt
	_hop_v += 1.2 * amt
	kick(Vector2(-_swing_dir * 5.0, 2.0) * amt)
	for i in _weapon_idx:
		_vel[i] = _vel[i] + Vector2(_swing_dir * 20.0, -8.0) * amt

func on_step(heavy: bool) -> void:
	var amt := 1.8 if heavy else 1.0
	_swing_dir = -_swing_dir
	_roll_v += _swing_dir * 4.0 * amt
	_sq_v += 2.0 * amt
	kick(Vector2(randf_range(-6.0, 6.0), randf_range(1.0, 5.0)) * amt)
	for i in _weapon_idx:
		_vel[i] = _vel[i] + Vector2(_swing_dir * 16.0, -6.0) * amt

func on_dodge() -> void:
	_roll_v += randf_range(-6.0, 6.0)
	_sq_v -= 1.5
	kick(Vector2(randf_range(-6.0, 6.0), 4.0))

func on_hurt() -> void:
	_flash = 1.0
	_sq_v -= 4.0
	_roll_v += randf_range(-6.0, 6.0)
	kick(Vector2(randf_range(-10.0, 10.0), randf_range(2.0, 8.0)))

func on_swap_in() -> void:
	_flip_cur = 0.0
	_hop_v += 5.0
	_sq_v += 3.0
	_dead = false
	kick(Vector2(randf_range(-8.0, 8.0), 6.0))

func on_dead() -> void:
	_dead = true
	kick(Vector2(0.0, -8.0))
