class_name Boss
extends Node3D
## Corrupted Colossus. Each attack is a timeline: it poses the rig (BossModel), spawns telegraphed
## Hazards, flashes a GOLD glint (parry with a Defensive Assist / perfect dodge) or a RED glint
## (unparryable, must dodge) right before the hit, then recovers, leaving a punish window.

signal hp_changed(hp: float, max_hp: float)
signal damage_taken(amount: float)
signal phase_changed(phase: int)
signal stunned
signal stun_ended
signal shake_requested(strength: float)
signal defeated
signal sfx_requested(sfx_name: String)
signal danger_warning(text: String)      # red-flash super attacks announce themselves
signal blasted                           # the arena-wide enrage detonation went off

enum State { IDLE, ATTACK, RECOVER, STUNNED, ROAR, DEAD }

const GOLD := Color(1.0, 0.8, 0.2)
const RED := Color(1.0, 0.1, 0.15)

var hp: float = GameConfig.BOSS_MAX_HP
var daze: float = 0.0
var freeze_buildup: float = 0.0
var frozen_t: float = 0.0
var stun_t: float = 0.0
var def_down_t: float = 0.0
var phase: int = 1
var state: State = State.IDLE
var target: Player
var attack_id: int = 0
var active: bool = false                 # false = idle pose only (title / results screens)

var _model: BossModel
var _t: float = 0.0
var _prev_t: float = 0.0
var _cur: int = -1
var _last_attack: int = -1
var _attack_cd: float = 2.0
var _enrage_timer: float = 0.0
var _state_timer: float = 0.0
var _hazards: Array[Hazard] = []
var _face_dir: Vector3 = Vector3.FORWARD
var _side: int = 1
var _move_vel: Vector3 = Vector3.ZERO
var _move_t: float = 0.0
var _strafe: float = 1.0
var _strafe_t: float = 2.0
var _fx_t: float = 0.0
var _prev_pos: Vector3 = Vector3.ZERO
var _pull_t: float = 0.0
var _pull_target: Vector3 = Vector3.ZERO
# leap / enrage jump
var _jump_from: Vector3 = Vector3.ZERO
var _jump_hz: Hazard = null
# charge
var _charge_from: Vector3 = Vector3.ZERO
var _charge_to: Vector3 = Vector3.ZERO
var _charge_hit: bool = false
var _charge_tid: int = 0
# beam
var _beam: MeshInstance3D = null
var _beam_low: MeshInstance3D = null
var _beam_light: OmniLight3D = null
var _beam_a0: float = 0.0
var _beam_a1: float = 0.0
var _beam_ang: float = 0.0
var _beam_tid: int = 0
# freeze shell
var _ice: Node3D

func _ready() -> void:
	_enrage_timer = GameConfig.ENRAGE_DATA["first_delay"]
	_model = BossModel.new()
	add_child(_model)
	_model.footstep.connect(_on_footstep)
	_build_ice()
	_prev_pos = global_position

func _build_ice() -> void:
	_ice = Node3D.new()
	add_child(_ice)
	var mat := Fx.shader_mat(Shaders.ice())
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 9:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(rng.randf_range(1.6, 2.8), rng.randf_range(3.0, 5.5), rng.randf_range(1.6, 2.6))
		m.mesh = b
		m.material_override = mat
		var a := TAU * float(i) / 9.0
		m.position = Vector3(cos(a) * 1.6, rng.randf_range(1.5, 5.5), sin(a) * 1.4)
		m.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ice.add_child(m)
	_ice.visible = false

# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if state == State.DEAD:
		_model.tick(delta, false)
		return
	if target == null or not active:
		_model.tick(delta, frozen_t > 0.0)
		return
	def_down_t = maxf(def_down_t - delta, 0.0)
	_update_pull(delta)
	var frozen := frozen_t > 0.0
	if frozen:
		frozen_t -= delta
		if frozen_t <= 0.0:
			_unfreeze()
	else:
		match state:
			State.IDLE:
				_process_idle(delta)
			State.ATTACK:
				_prev_t = _t
				_t += delta
				_process_attack(delta)
			State.RECOVER:
				_state_timer -= delta
				_turn_toward(target.global_position, delta, GameConfig.BOSS_TURN_SPEED * 0.5)
				if _state_timer <= 0.0:
					_enter_idle()
			State.ROAR:
				_state_timer -= delta
				if _state_timer <= 0.0:
					_enter_idle()
			State.STUNNED:
				stun_t -= delta
				_fx_t -= delta
				if _fx_t <= 0.0:
					_fx_t = 0.3
					Fx.spark(get_parent(), _model.point("head") + Vector3(randf_range(-1.2, 1.2), randf_range(0.4, 1.4), randf_range(-1.2, 1.2)), Color(1.0, 0.9, 0.3), 1.3)
				if stun_t <= 0.0:
					_end_stun()
		if _move_t > 0.0:
			_move_t -= delta
			var nxt := global_position + _move_vel * delta
			var to := target.global_position - nxt
			to.y = 0.0
			if to.length() > GameConfig.BOSS_RADIUS + 0.9 or _move_vel.dot(to) < 0.0:
				global_position = nxt
	var moved := global_position - _prev_pos
	moved.y = 0.0
	_model.walk_speed = moved.length() / maxf(delta, 0.0001)
	_prev_pos = global_position
	_model.tick(delta, frozen)
	_clamp_arena()

func _enter_idle() -> void:
	state = State.IDLE
	_model.tired = 0.0
	_model.set_pose("idle", 0.8)

func _process_idle(delta: float) -> void:
	_turn_toward(target.global_position, delta, GameConfig.BOSS_TURN_SPEED)
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > 0.01:
		var dir := to / dist
		if dist > GameConfig.BOSS_RADIUS + 4.5:
			global_position += dir * GameConfig.BOSS_SPEED * delta
		else:
			_strafe_t -= delta
			if _strafe_t <= 0.0:
				_strafe_t = randf_range(1.5, 3.0)
				_strafe = -_strafe
			global_position += Vector3(-dir.z, 0.0, dir.x) * _strafe * 0.9 * delta
	_attack_cd -= delta
	if phase >= 3:
		_enrage_timer -= delta
	if _attack_cd <= 0.0:
		_start_attack(_choose_attack())

func _choose_attack() -> int:
	if phase >= 3 and _enrage_timer <= 0.0:
		_enrage_timer = GameConfig.ENRAGE_DATA["interval"]
		return GameConfig.Attack.ENRAGE
	var pool: Array = (GameConfig.ATTACK_POOL[phase - 1] as Array).duplicate()
	var dist := _flat_dist(target.global_position)
	if dist > GameConfig.BOSS_MELEE_RANGE:
		for a: int in GameConfig.MELEE_ATTACKS:
			pool.erase(a)
	if dist > float(GameConfig.SLAM_DATA["reach"]):
		pool.erase(GameConfig.Attack.SLAM)
	if pool.is_empty():
		pool = [GameConfig.Attack.LEAP, GameConfig.Attack.CHARGE]
	var pick: int = pool[randi() % pool.size()]
	if pick == _last_attack and pool.size() > 1:
		pick = pool[randi() % pool.size()]
	return pick

# ------------------------------------------------------------------ attack framework
func _start_attack(a: int) -> void:
	_cur = a
	_last_attack = a
	attack_id += 1
	state = State.ATTACK
	_t = 0.0
	_prev_t = -0.001
	_face_dir = _dir_to(target.global_position)
	_side = 1 if randf() < 0.5 else -1
	_process_attack(0.0)

## True exactly once, on the frame the attack clock crosses `mark`.
func _at(mark: float) -> bool:
	return _prev_t < mark and _t >= mark

func _end_attack(recover: float) -> void:
	state = State.RECOVER
	_state_timer = recover
	_cur = -1
	_attack_cd = GameConfig.BOSS_ATTACK_CD[phase - 1]
	_model.set_pose("recover", 0.8)
	_model.tired = 1.0
	_model.set_charge(0.0)
	global_position.y = 0.0

func _process_attack(delta: float) -> void:
	match _cur:
		GameConfig.Attack.SLAM:
			_atk_slam(delta)
		GameConfig.Attack.SWEEP:
			_atk_sweep(delta)
		GameConfig.Attack.COMBO:
			_atk_combo(delta)
		GameConfig.Attack.QUAKE:
			_atk_quake(delta)
		GameConfig.Attack.LEAP:
			_atk_leap(delta)
		GameConfig.Attack.BEAM:
			_atk_beam(delta)
		GameConfig.Attack.ERUPTION:
			_atk_eruption(delta)
		GameConfig.Attack.VOLLEY:
			_atk_volley(delta)
		GameConfig.Attack.CHARGE:
			_atk_charge(delta)
		GameConfig.Attack.ENRAGE:
			_atk_enrage(delta)
		_:
			_end_attack(0.5)

func _hz(shape: int, origin: Vector3, dmg: float, tele: float, fx: String = "", parry: bool = true) -> Hazard:
	var h := Hazard.new()
	h.shape = shape
	h.origin = Vector3(origin.x, 0.0, origin.z)
	h.damage = dmg
	h.tele = tele
	h.target = target
	h.fx_kind = fx
	h.parryable = parry
	h.dir = _face_dir
	return h

func _add_hz(h: Hazard) -> Hazard:
	get_parent().add_child(h)
	_hazards.append(h)
	h.tree_exiting.connect(func() -> void: _hazards.erase(h))
	return h

func _glint(point_name: String, parry: bool, size: float = 3.4) -> void:
	Fx.glint(get_parent(), _model.point(point_name), GOLD if parry else RED, size)
	sfx_requested.emit("glint" if parry else "glint_red")

func _slash_fx(radius: float, right_hand: bool) -> void:
	var yaw := atan2(-_face_dir.x, -_face_dir.z)
	var tilt := 0.22 if right_hand else -0.22
	Fx.slash(get_parent(), global_position + Vector3(0.0, 2.6, 0.0), yaw, Color(1.0, 0.25, 0.55), radius, true, tilt, not right_hand)
	sfx_requested.emit("swing_heavy")

func _on_impact(_hit: bool, strength: float, snd: String) -> void:
	shake_requested.emit(strength)
	sfx_requested.emit(snd)

func _clamped_target(reach: float) -> Vector3:
	var c := target.global_position
	var off := c - global_position
	off.y = 0.0
	if off.length() > reach:
		off = off.normalized() * reach
	return global_position + off

# ------------------------------------------------------------------ attacks
## Overhead double-fist smash; the shockwave lands where the player stands.
func _atk_slam(delta: float) -> void:
	var d: Dictionary = GameConfig.SLAM_DATA
	var tele: float = d["tele"]
	if _at(0.0):
		_model.set_pose("slam_raise", 1.0)
		var h := _hz(Hazard.Shape.CIRCLE, _clamped_target(d["reach"]), d["dmg"], tele, "slam")
		h.radius = d["radius"]
		h.follow = target
		h.lock_time = 0.45
		h.resolved.connect(_on_impact.bind(0.55, "slam"))
		_add_hz(h)
		sfx_requested.emit("warn")
	if _t < tele - 0.3:
		_turn_toward(target.global_position, delta, 3.0)
	if _at(tele - GameConfig.PERFECT_WINDOW):
		_glint("hand_r", true)
	if _at(tele - 0.14):
		_model.set_pose("slam_hit", 3.2)
	if _at(tele):
		Fx.debris(get_parent(), _model.point("hand_r"), 10, 7.0)
	if _at(tele + 0.7):
		_model.set_pose("idle", 0.9)
	if _t >= tele + 1.0:
		_end_attack(0.6)

## One huge claw swipe across a wide cone.
func _atk_sweep(delta: float) -> void:
	var d: Dictionary = GameConfig.SWEEP_DATA
	var tele: float = d["tele"]
	var s := "r" if _side > 0 else "l"
	if _at(0.0):
		_model.set_pose("sweep_wind_" + s, 0.9)
		var h := _hz(Hazard.Shape.SECTOR, global_position, d["dmg"], tele)
		h.radius = d["radius"]
		h.half_angle = d["half_angle"]
		h.resolved.connect(_on_impact.bind(0.35, "hit_heavy"))
		_add_hz(h)
		sfx_requested.emit("warn")
	_turn_toward_dir(_face_dir, delta, 6.0)
	if _at(tele - GameConfig.PERFECT_WINDOW):
		_glint("hand_" + s, true)
	if _at(tele - 0.16):
		_model.set_pose("sweep_hit_" + s, 3.2)
		_lunge(_face_dir, 1.6, 0.25)
	if _at(tele - 0.06):
		_slash_fx(float(d["radius"]) * 0.9, _side > 0)
	if _at(tele + 0.6):
		_model.set_pose("idle", 0.8)
	if _t >= tele + 0.9:
		_end_attack(0.8)

## Right swipe -> left swipe -> overhead slam. Three separate gold flashes.
func _atk_combo(delta: float) -> void:
	var d: Dictionary = GameConfig.COMBO_DATA
	var hits: Array = d["hits"]
	var h1: float = hits[0]
	var h2: float = hits[1]
	var h3: float = hits[2]
	var pw := GameConfig.PERFECT_WINDOW
	if _at(0.0):
		_model.set_pose("sweep_wind_r", 1.0)
		_combo_cone(h1)
		sfx_requested.emit("warn")
	_turn_toward_dir(_face_dir, delta, 8.0)
	if _at(h1 - pw):
		_glint("hand_r", true, 2.8)
	if _at(h1 - 0.15):
		_model.set_pose("sweep_hit_r", 3.2)
		_lunge(_face_dir, 1.4, 0.22)
	if _at(h1 - 0.05):
		_slash_fx(float(d["radius"]) * 0.9, true)
	if _at(h1 + 0.08):
		_face_dir = _dir_to(target.global_position)
		_model.set_pose("sweep_wind_l", 1.8)
		_combo_cone(h2 - h1 - 0.08)
	if _at(h2 - pw):
		_glint("hand_l", true, 2.8)
	if _at(h2 - 0.15):
		_model.set_pose("sweep_hit_l", 3.2)
		_lunge(_face_dir, 1.4, 0.22)
	if _at(h2 - 0.05):
		_slash_fx(float(d["radius"]) * 0.9, false)
	if _at(h2 + 0.1):
		_face_dir = _dir_to(target.global_position)
		_model.set_pose("slam_raise", 1.6)
		var h := _hz(Hazard.Shape.CIRCLE, _clamped_target(7.0), d["slam_dmg"], h3 - h2 - 0.1, "slam")
		h.radius = d["slam_radius"]
		h.follow = target
		h.lock_time = 0.35
		h.resolved.connect(_on_impact.bind(0.6, "slam"))
		_add_hz(h)
	if _t > h2 + 0.1 and _t < h3 - 0.3:
		_face_dir = _dir_to(target.global_position)
	if _at(h3 - pw):
		_glint("hand_r", true, 3.6)
	if _at(h3 - 0.13):
		_model.set_pose("slam_hit", 3.4)
	if _at(h3 + 0.8):
		_model.set_pose("idle", 0.8)
	if _t >= h3 + 1.1:
		_end_attack(1.0)

func _combo_cone(tele: float) -> void:
	var d: Dictionary = GameConfig.COMBO_DATA
	var h := _hz(Hazard.Shape.SECTOR, global_position, d["dmg"], tele)
	h.radius = d["radius"]
	h.half_angle = d["half_angle"]
	h.resolved.connect(_on_impact.bind(0.3, "hit_heavy"))
	_add_hz(h)

## Alternating stomps; each one sends an expanding shockwave ring across the arena.
func _atk_quake(delta: float) -> void:
	var d: Dictionary = GameConfig.QUAKE_DATA
	var first: float = d["first"]
	var gap: float = d["gap"]
	var counts: Array = d["rings"]
	var n: int = counts[phase - 1]
	_turn_toward(target.global_position, delta, 1.5)
	for i in n:
		var t_hit := first + float(i) * gap
		var s := "r" if i % 2 == 0 else "l"
		if i == 0 and _at(0.0):
			_model.set_pose("stomp_raise_r", 0.9)
			sfx_requested.emit("warn")
		if i > 0 and _at(t_hit - gap * 0.55):
			_model.set_pose("stomp_raise_" + s, 2.0)
		if _at(t_hit - GameConfig.PERFECT_WINDOW):
			_glint("foot_" + s, true, 2.6)
		if _at(t_hit - 0.08):
			_model.set_pose("stomp_hit_" + s, 3.5)
		if _at(t_hit):
			var h := _hz(Hazard.Shape.RING, global_position, d["dmg"], 1.0)
			h.ring_speed = d["speed"]
			h.ring_width = d["width"]
			_add_hz(h)
			var foot := _model.point("foot_" + s)
			Fx.shockwave(get_parent(), foot, Color(1.0, 0.5, 0.25), 6.0, 0.35)
			Fx.debris(get_parent(), foot, 10, 8.0)
			shake_requested.emit(0.45)
			sfx_requested.emit("quake")
	if _t >= first + float(n - 1) * gap + 0.9:
		_model.set_pose("idle", 0.8)
		_end_attack(0.8)

## Leaps out of view; the landing zone hunts the player, then a meteor landing.
func _atk_leap(delta: float) -> void:
	var d: Dictionary = GameConfig.LEAP_DATA
	var crouch: float = d["crouch"]
	var air: float = d["air"]
	var land := crouch + air
	if _at(0.0):
		_model.set_pose("leap_crouch", 1.0)
		_model.set_charge(0.3)
		sfx_requested.emit("warn")
	if _t < crouch:
		_turn_toward(target.global_position, delta, 4.0)
	if _at(crouch):
		_model.set_pose("leap_air", 1.6)
		_jump_from = Vector3(global_position.x, 0.0, global_position.z)
		var h := _hz(Hazard.Shape.CIRCLE, target.global_position, d["dmg"], air, "land")
		h.radius = d["radius"]
		h.follow = target
		h.lock_time = d["lock"]
		h.resolved.connect(_on_impact.bind(0.9, "slam"))
		_jump_hz = _add_hz(h)
		Fx.shockwave(get_parent(), global_position, Color(1.0, 0.4, 0.7), 5.0, 0.3)
		Fx.debris(get_parent(), global_position, 12, 8.0)
		shake_requested.emit(0.3)
		sfx_requested.emit("leap")
	if _t >= crouch and _t < land:
		var s := clampf((_t - crouch) / air, 0.0, 1.0)
		var dest := _jump_from
		if _jump_hz != null and is_instance_valid(_jump_hz):
			dest = _jump_hz.origin
		var e := s * s * (3.0 - 2.0 * s)
		var p := _jump_from.lerp(dest, e)
		p.y = 4.0 * float(d["height"]) * s * (1.0 - s)
		global_position = p
		_turn_toward(dest + (dest - _jump_from), delta, 5.0)
	if _at(land - GameConfig.PERFECT_WINDOW):
		_glint("core", true, 4.0)
	if _at(land - 0.12):
		_model.set_pose("leap_land", 3.0)
	if _at(land):
		global_position.y = 0.0
		_model.set_charge(0.0)
	if _at(land + 0.9):
		_model.set_pose("idle", 0.7)
	if _t >= land + 1.2:
		_end_attack(1.3)

## Charges the core, then rakes a beam across a wide arc. RED flash: no parry.
func _atk_beam(delta: float) -> void:
	var d: Dictionary = GameConfig.BEAM_DATA
	var tele: float = d["tele"]
	var sweep: float = d["sweep"]
	var arc: float = d["arc"]
	if _at(0.0):
		_model.set_pose("beam_charge", 0.8)
		var center := atan2(-_face_dir.x, -_face_dir.z)
		_beam_a0 = center + float(_side) * arc * 0.5
		_beam_a1 = center - float(_side) * arc * 0.5
		var h := _hz(Hazard.Shape.SECTOR, global_position, 0.0, tele, "", false)
		h.radius = float(d["length"]) * 0.6
		h.half_angle = arc * 0.5
		_add_hz(h)
		danger_warning.emit("")
		sfx_requested.emit("charge")
	if _t < tele:
		_model.set_charge(_t / tele)
		_turn_toward_dir(Vector3(-sin(_beam_a0), 0.0, -cos(_beam_a0)), delta, 2.5)
		_fx_t -= delta
		if _fx_t <= 0.0:
			_fx_t = 0.12
			Fx.burst(get_parent(), _model.point("core"), GameConfig.Element.ETHER, 6, 4.0)
	if _at(tele - GameConfig.PERFECT_WINDOW):
		_glint("core", false, 4.2)
	if _at(tele):
		_model.set_pose("beam_fire", 2.0)
		_beam_tid = Hazard.new_id()
		_make_beam()
		shake_requested.emit(0.35)
		sfx_requested.emit("beam")
	if _t >= tele and _t < tele + sweep and _beam != null:
		var s := clampf((_t - tele) / sweep, 0.0, 1.0)
		_beam_ang = lerpf(_beam_a0, _beam_a1, s * s * (3.0 - 2.0 * s))
		_model.rotation.y = _beam_ang
		_update_beam(d)
		shake_requested.emit(0.1)
	if _at(tele + sweep):
		_remove_beam()
		_model.set_charge(0.0)
		_model.set_pose("idle", 0.7)
	if _t >= tele + sweep + 0.6:
		_end_attack(1.2)

func _make_beam() -> void:
	var mat := Fx.shader_mat(Shaders.beam(), {"color": Color(1.0, 0.2, 0.55), "fade": 1.0})
	for i in 2:
		var m := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.5
		cyl.height = 1.0
		cyl.radial_segments = 16
		cyl.rings = 1
		m.mesh = cyl
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.top_level = true
		add_child(m)
		if i == 0:
			_beam = m
		else:
			_beam_low = m
	_beam_light = OmniLight3D.new()
	_beam_light.light_color = Color(1.0, 0.3, 0.6)
	_beam_light.light_energy = 6.0
	_beam_light.omni_range = 9.0
	_beam_light.top_level = true
	add_child(_beam_light)

func _place_tube(m: MeshInstance3D, a: Vector3, b: Vector3, w: float) -> void:
	var dv := b - a
	var l := dv.length()
	if l < 0.01:
		return
	var axis := dv / l
	var rot := Basis(Quaternion(Vector3.UP, axis)) if absf(axis.dot(Vector3.UP)) < 0.999 else Basis.IDENTITY
	m.global_transform = Transform3D(rot * Basis.from_scale(Vector3(w, l, w)), (a + b) * 0.5)

func _update_beam(d: Dictionary) -> void:
	var dir := Vector3(-sin(_beam_ang), 0.0, -cos(_beam_ang))
	var core := _model.point("core")
	var ground := global_position + dir * 7.0 + Vector3(0.0, 0.9, 0.0)
	var length: float = d["length"]
	var far := global_position + dir * length + Vector3(0.0, 0.9, 0.0)
	var w: float = d["width"]
	_place_tube(_beam, core, ground, w * 1.2)
	_place_tube(_beam_low, ground, far, w)
	_beam_light.global_position = ground + Vector3(0.0, 0.6, 0.0)
	_fx_t -= get_process_delta_time()
	if _fx_t <= 0.0:
		_fx_t = 0.07
		Fx.spark(get_parent(), ground + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.8), randf_range(-0.6, 0.6)), Color(1.0, 0.4, 0.7), 2.2)
		Fx.burst(get_parent(), ground, GameConfig.Element.ETHER, 5, 6.0)
	var rel := target.global_position - global_position
	rel.y = 0.0
	var f := rel.dot(dir)
	var side := absf(rel.dot(Vector3(-dir.z, 0.0, dir.x)))
	if f > 0.0 and f < length and side < w * 0.5 + 0.5:
		target.take_damage(d["dmg"])

func _remove_beam() -> void:
	for n: Node in [_beam, _beam_low, _beam_light]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_beam = null
	_beam_low = null
	_beam_light = null

## Punches the floor: corrupted spikes erupt under the player, chasing them.
func _atk_eruption(delta: float) -> void:
	var d: Dictionary = GameConfig.ERUPTION_DATA
	var counts: Array = d["count"]
	var n: int = maxi(int(counts[phase - 1]), 4)
	var interval: float = d["interval"]
	var tele: float = d["tele"]
	var start := 0.55
	if _at(0.0):
		_model.set_pose("slam_raise", 1.1)
		sfx_requested.emit("warn")
	if _t < 0.5:
		_turn_toward(target.global_position, delta, 3.0)
	if _at(0.5):
		_model.set_pose("eruption", 3.2)
		shake_requested.emit(0.45)
		sfx_requested.emit("slam")
		Fx.shockwave(get_parent(), _model.point("hand_r"), Color(1.0, 0.3, 0.7), 7.0, 0.4)
		Fx.debris(get_parent(), _model.point("hand_l"), 14, 9.0)
	for i in n:
		var ti := start + float(i) * interval
		if _at(ti):
			var p := target.global_position + target.velocity * 0.35
			var flat := Vector2(p.x, p.z)
			if flat.length() > GameConfig.ARENA_RADIUS - 1.0:
				flat = flat.normalized() * (GameConfig.ARENA_RADIUS - 1.0)
			var h := _hz(Hazard.Shape.CIRCLE, Vector3(flat.x, 0.0, flat.y), d["dmg"], tele, "spikes")
			h.radius = d["radius"]
			h.resolved.connect(_on_impact.bind(0.22, "spike"))
			_add_hz(h)
	if _at(start + tele - GameConfig.PERFECT_WINDOW):
		_glint("hand_r", true, 3.0)
	var done := start + float(n - 1) * interval + tele
	if _at(done - 0.4):
		_model.set_pose("recover", 0.7)
	if _t >= done + 0.3:
		_end_attack(1.0)

## Two waves of homing orbs, one from each hand.
func _atk_volley(delta: float) -> void:
	var d: Dictionary = GameConfig.VOLLEY_DATA
	var tele: float = d["tele"]
	_face_dir = _dir_to(target.global_position)
	_turn_toward_dir(_face_dir, delta, 3.0)
	if _at(0.0):
		_model.set_pose("volley_r", 1.1)
		_model.set_charge(0.5)
		sfx_requested.emit("charge")
	if _at(tele - GameConfig.PERFECT_WINDOW):
		_glint("hand_r", true, 2.6)
	if _at(tele):
		_fire_volley(d, "hand_r")
		_model.kick("sh_r", Vector3(-6.0, 0.0, 0.0))
	if _at(tele + 0.15):
		_model.set_pose("volley_l", 1.6)
	if _at(tele + 0.7 - GameConfig.PERFECT_WINDOW):
		_glint("hand_l", true, 2.6)
	if _at(tele + 0.7):
		_fire_volley(d, "hand_l")
		_model.kick("sh_l", Vector3(-6.0, 0.0, 0.0))
	if _at(tele + 1.2):
		_model.set_pose("idle", 0.8)
		_model.set_charge(0.0)
	if _t >= tele + 1.4:
		_end_attack(0.8)

func _fire_volley(d: Dictionary, hand: String) -> void:
	var counts: Array = d["count"]
	var n: int = counts[phase - 1]
	var spread: float = d["spread"]
	var origin := _model.point(hand)
	var to := target.global_position - origin
	to.y = 0.0
	var base_yaw := atan2(-to.x, -to.z)
	for i in n:
		var f := 0.0
		if n > 1:
			f = float(i) / float(n - 1) - 0.5
		var yaw := base_yaw + f * spread
		var p := Projectile.new()
		p.target = target
		p.damage = d["dmg"]
		p.homing = d["homing"]
		p.homing_time = d["homing_time"]
		p.velocity = Vector3(-sin(yaw), 0.0, -cos(yaw)) * float(d["speed"])
		get_parent().add_child(p)
		p.global_position = origin
	Fx.burst(get_parent(), origin, GameConfig.Element.ETHER, 10, 6.0)
	sfx_requested.emit("zap")

## Shoulder-barge dash along a telegraphed lane.
func _atk_charge(delta: float) -> void:
	var d: Dictionary = GameConfig.CHARGE_DATA
	var tele: float = d["tele"]
	var time: float = d["time"]
	if _at(0.0):
		_model.set_pose("charge_crouch", 1.0)
		var dist := _flat_dist(target.global_position)
		var h := _hz(Hazard.Shape.RECT, global_position, 0.0, tele)
		h.length = minf(dist + float(d["overshoot"]), GameConfig.ARENA_RADIUS * 1.5)
		h.width = d["width"]
		_add_hz(h)
		_charge_to = global_position + _face_dir * maxf(h.length - GameConfig.BOSS_RADIUS, 2.0)
		_charge_from = global_position
		_charge_hit = false
		_charge_tid = Hazard.new_id()
		sfx_requested.emit("warn")
	_turn_toward_dir(_face_dir, delta, 8.0)
	if _at(tele - GameConfig.PERFECT_WINDOW):
		_glint("head", true, 3.4)
	if _at(tele):
		_model.set_pose("charge_run", 2.4)
		_charge_from = global_position
		var lim := GameConfig.ARENA_RADIUS - 3.0
		var flat := Vector2(_charge_to.x, _charge_to.z)
		if flat.length() > lim:
			flat = flat.normalized() * lim
			_charge_to = Vector3(flat.x, 0.0, flat.y)
		shake_requested.emit(0.25)
		sfx_requested.emit("dash")
	if _t >= tele and _t < tele + time:
		var s := clampf((_t - tele) / time, 0.0, 1.0)
		global_position = _charge_from.lerp(_charge_to, s * s)
		if not _charge_hit:
			var dd := target.global_position - global_position
			dd.y = 0.0
			if dd.length() <= GameConfig.BOSS_RADIUS + 0.7:
				_charge_hit = true
				target.take_damage(d["dmg"])
	if _at(tele + time):
		global_position = _charge_to
		_model.set_pose("charge_crouch", 2.5)
		Fx.shockwave(get_parent(), global_position, Color(1.0, 0.5, 0.3), 5.0, 0.3)
		Fx.debris(get_parent(), global_position + _face_dir * 2.0, 14, 8.0)
		shake_requested.emit(0.45)
		sfx_requested.emit("slam")
	if _at(tele + time + 0.7):
		_model.set_pose("idle", 0.8)
	if _t >= tele + time + 0.9:
		_end_attack(maxf(float(d["recover"]) - 0.9, 0.6))

## Leaps to the arena centre, gathers energy, detonates the whole arena. RED flash.
func _atk_enrage(delta: float) -> void:
	var d: Dictionary = GameConfig.ENRAGE_DATA
	var tele: float = d["tele"]
	var gather := 2.2
	if _at(0.0):
		_model.set_pose("roar", 1.0)
		_jump_from = Vector3(global_position.x, 0.0, global_position.z)
		danger_warning.emit("DANGER")
		shake_requested.emit(0.6)
		sfx_requested.emit("roar")
	if _at(0.9):
		_model.set_pose("leap_air", 1.4)
		sfx_requested.emit("leap")
	if _t >= 0.9 and _t < 1.9:
		var s := clampf((_t - 0.9) / 1.0, 0.0, 1.0)
		var p := _jump_from.lerp(Vector3.ZERO, s * s * (3.0 - 2.0 * s))
		p.y = 24.0 * s * (1.0 - s)
		global_position = p
	if _at(1.9):
		global_position = Vector3.ZERO
		_model.set_pose("leap_land", 3.0)
		Fx.shockwave(get_parent(), Vector3.ZERO, Color(1.0, 0.3, 0.6), 10.0, 0.4)
		Fx.debris(get_parent(), Vector3.ZERO, 20, 11.0)
		shake_requested.emit(0.6)
		sfx_requested.emit("slam")
	if _at(gather):
		_model.set_pose("enrage_gather", 0.8)
		var h := _hz(Hazard.Shape.ALL, Vector3.ZERO, d["dmg"], tele, "blast", false)
		h.resolved.connect(_on_blast)
		_add_hz(h)
		sfx_requested.emit("charge")
	if _t >= gather and _t < gather + tele:
		var a := (_t - gather) / tele
		_model.set_charge(a)
		_turn_toward(target.global_position, delta, 1.5)
		if randf() < a * 0.5:
			shake_requested.emit(0.08 + a * 0.15)
		_fx_t -= delta
		if _fx_t <= 0.0:
			_fx_t = 0.09
			Fx.burst(get_parent(), _model.point("core"), GameConfig.Element.ETHER, 8, 7.0 + a * 6.0)
	if _at(gather + tele - GameConfig.PERFECT_WINDOW):
		_glint("core", false, 6.0)
	if _at(gather + tele - 0.1):
		_model.set_pose("enrage_release", 3.5)
	if _at(gather + tele):
		_model.set_charge(0.0)
	if _at(gather + tele + 1.2):
		_model.set_pose("idle", 0.6)
	if _t >= gather + tele + 1.5:
		_end_attack(2.0)

func _on_blast(_hit: bool) -> void:
	shake_requested.emit(1.0)
	sfx_requested.emit("blast")
	blasted.emit()

## Called by Player: is any hit about to land on p? {} when not, else {"id", "parry"}.
func get_threat(p: Vector3) -> Dictionary:
	for h in _hazards:
		if is_instance_valid(h):
			var id := h.threat(p)
			if id != 0:
				return {"id": id, "parry": h.parryable}
	if state == State.ATTACK and _cur == GameConfig.Attack.CHARGE and not _charge_hit:
		var d: Dictionary = GameConfig.CHARGE_DATA
		var tele: float = d["tele"]
		var time: float = d["time"]
		if _t >= tele - GameConfig.PERFECT_WINDOW and _t < tele + time:
			var rel := p - global_position
			rel.y = 0.0
			var f := rel.dot(_face_dir)
			var side := absf(rel.dot(Vector3(-_face_dir.z, 0.0, _face_dir.x)))
			var from := _charge_from if _t >= tele else global_position
			var speed := 2.0 * from.distance_to(_charge_to) / time
			if f > 0.0 and side < float(d["width"]) * 0.5 + 1.0 and f - GameConfig.BOSS_RADIUS < speed * GameConfig.PERFECT_WINDOW + 1.0:
				return {"id": _charge_tid, "parry": true}
	if _beam != null:
		var rel2 := p - global_position
		rel2.y = 0.0
		var dist := rel2.length()
		var bd: Dictionary = GameConfig.BEAM_DATA
		if dist < float(bd["length"]) and dist > 0.1:
			var p_ang := atan2(-rel2.x, -rel2.z)
			var sgn := signf(_beam_a1 - _beam_a0)
			var remaining := wrapf(p_ang - _beam_ang, -PI, PI) * sgn
			var w := absf(_beam_a1 - _beam_a0) / float(bd["sweep"])
			var pad := (float(bd["width"]) * 0.5 + 0.6) / dist
			if remaining >= -pad and remaining <= w * GameConfig.PERFECT_WINDOW + pad:
				return {"id": _beam_tid, "parry": false}
	for n in get_tree().get_nodes_in_group("projectiles"):
		var pr := n as Projectile
		if pr != null:
			var id2 := pr.threat(p)
			if id2 != 0:
				return {"id": id2, "parry": true}
	return {}

func face_instant(p: Vector3) -> void:
	var d := _dir_to(p)
	_model.rotation.y = atan2(-d.x, -d.z)

func is_threatening(p: Vector3) -> bool:
	return not get_threat(p).is_empty()

# ------------------------------------------------------------------ helpers
func _dir_to(p: Vector3) -> Vector3:
	var d := p - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD

func _flat_dist(p: Vector3) -> float:
	var d := p - global_position
	d.y = 0.0
	return d.length()

func _turn_toward(p: Vector3, delta: float, rate: float) -> void:
	_turn_toward_dir(_dir_to(p), delta, rate)

func _turn_toward_dir(dir: Vector3, delta: float, rate: float) -> void:
	var want := atan2(-dir.x, -dir.z)
	var cur := _model.rotation.y
	var diff := wrapf(want - cur, -PI, PI)
	_model.rotation.y = cur + clampf(diff, -rate * delta, rate * delta)

func _lunge(dir: Vector3, dist: float, time: float) -> void:
	_move_vel = dir * dist / time
	_move_t = time

func _clamp_arena() -> void:
	var flat := Vector2(global_position.x, global_position.z)
	var lim := GameConfig.ARENA_RADIUS - 3.0
	if flat.length() > lim:
		flat = flat.normalized() * lim
		global_position = Vector3(flat.x, global_position.y, flat.y)

func _on_footstep(side: int) -> void:
	if state == State.DEAD or global_position.y > 0.3:
		return
	var heavy := state == State.ATTACK and _cur == GameConfig.Attack.CHARGE
	var foot := _model.point("foot_l" if side == 0 else "foot_r")
	Fx.shockwave(get_parent(), foot, Color(0.75, 0.7, 0.85), 2.2 if heavy else 1.6, 0.3)
	if _flat_dist(target.global_position) < 16.0:
		shake_requested.emit(0.12 if heavy else 0.05)
	sfx_requested.emit("step")

func _update_pull(delta: float) -> void:
	if _pull_t <= 0.0:
		return
	_pull_t -= delta
	if global_position.y > 0.3 or (state == State.ATTACK and _cur in [GameConfig.Attack.CHARGE, GameConfig.Attack.LEAP, GameConfig.Attack.ENRAGE]):
		return
	var to := _pull_target - global_position
	to.y = 0.0
	var stop := GameConfig.BOSS_RADIUS + 2.5
	var l := to.length()
	if l > stop:
		global_position += to / l * minf(GameConfig.PULL_SPEED * delta, l - stop)

func pull_toward(p: Vector3) -> void:
	_pull_target = p
	_pull_t = GameConfig.PULL_TIME

func apply_def_down() -> void:
	def_down_t = GameConfig.DEF_DOWN_TIME

func is_hittable() -> bool:
	return state != State.DEAD and global_position.y < 2.5

func is_stunned() -> bool:
	return state == State.STUNNED

func daze_ratio() -> float:
	if state == State.STUNNED:
		return clampf(stun_t / GameConfig.STUN_TIME, 0.0, 1.0)
	return clampf(daze / GameConfig.DAZE_MAX, 0.0, 1.0)

## Cancels everything in flight (stun, freeze, phase roar, death).
func _interrupt() -> void:
	for h in _hazards.duplicate():
		if is_instance_valid(h):
			(h as Hazard).cancel()
	_hazards.clear()
	_remove_beam()
	_move_t = 0.0
	_model.set_charge(0.0)
	global_position.y = 0.0
	_cur = -1

# ------------------------------------------------------------------ damage / status
func take_damage(base: float, element: int, daze_amt: float = 0.0, freeze_amt: float = 0.0) -> float:
	if state == State.DEAD:
		return 0.0
	var mult := 1.0
	if element == GameConfig.Element.ICE or element == GameConfig.Element.ETHER:
		mult *= GameConfig.WEAKNESS_MULT
	if def_down_t > 0.0:
		mult *= GameConfig.DEF_DOWN_MULT
	if state == State.STUNNED:
		mult *= GameConfig.STUN_DAMAGE_MULT
	if frozen_t > 0.0:
		mult *= GameConfig.FREEZE_DAMAGE_MULT
	var crit := randf() < GameConfig.CRIT_CHANCE
	if crit:
		mult *= GameConfig.CRIT_MULT
	var dmg := base * mult
	hp = maxf(hp - dmg, 0.0)
	_model.flinch(0.5 if base < 150.0 else 1.4)
	DamageNumber.spawn(get_parent(), global_position + Vector3(0.0, 5.6, 0.0), dmg, GameConfig.element_color(element), crit)
	sfx_requested.emit("crit" if crit else "hit")
	damage_taken.emit(dmg)
	hp_changed.emit(hp, GameConfig.BOSS_MAX_HP)
	if hp <= 0.0:
		_die()
		return dmg
	_check_phase()
	if state != State.STUNNED and daze_amt > 0.0:
		daze = minf(daze + daze_amt, GameConfig.DAZE_MAX)
		if daze >= GameConfig.DAZE_MAX:
			_enter_stun()
	if state != State.STUNNED and freeze_amt > 0.0 and frozen_t <= 0.0 and global_position.y < 0.3:
		freeze_buildup += freeze_amt
		if freeze_buildup >= GameConfig.FREEZE_MAX:
			_freeze()
	return dmg

func _check_phase() -> void:
	var ratio := hp / GameConfig.BOSS_MAX_HP
	var new_phase := 1
	if ratio <= float(GameConfig.PHASE_THRESHOLDS[0]):
		new_phase = 2
	if ratio <= float(GameConfig.PHASE_THRESHOLDS[1]):
		new_phase = 3
	if new_phase <= phase:
		return
	phase = new_phase
	phase_changed.emit(phase)
	shake_requested.emit(0.7)
	sfx_requested.emit("roar")
	if state != State.STUNNED:
		_interrupt()
		state = State.ROAR
		_state_timer = GameConfig.PHASE_ROAR_TIME
		_model.set_pose("roar", 1.3)
		Fx.shockwave(get_parent(), global_position, Color(1.0, 0.3, 0.65), 12.0, 0.5)

func _enter_stun() -> void:
	_interrupt()
	state = State.STUNNED
	stun_t = GameConfig.STUN_TIME
	frozen_t = 0.0
	freeze_buildup = 0.0
	_ice.visible = false
	_model.set_pose("stun", 1.4)
	_model.set_eye(0.3)
	shake_requested.emit(0.6)
	sfx_requested.emit("stun")
	stunned.emit()

func _end_stun() -> void:
	daze = 0.0
	_model.set_eye(1.0)
	_model.set_pose("idle", 0.6)
	state = State.RECOVER
	_state_timer = GameConfig.BOSS_RECOVER_TIME
	_attack_cd = GameConfig.BOSS_ATTACK_CD[phase - 1]
	stun_ended.emit()

func _freeze() -> void:
	freeze_buildup = 0.0
	frozen_t = GameConfig.FREEZE_TIME
	_ice.visible = true
	_ice.scale = Vector3.ONE * 0.6
	create_tween().tween_property(_ice, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if state == State.ATTACK:
		_interrupt()
		_end_attack(0.6)
	Fx.burst(get_parent(), global_position + Vector3(0.0, 3.0, 0.0), GameConfig.Element.ICE, 24, 9.0)
	sfx_requested.emit("freeze")

func _unfreeze() -> void:
	_ice.visible = false
	Fx.burst(get_parent(), global_position + Vector3(0.0, 3.0, 0.0), GameConfig.Element.ICE, 18, 7.0)

func _die() -> void:
	_interrupt()
	state = State.DEAD
	_ice.visible = false
	_model.set_pose("dead", 0.8)
	_model.set_eye(0.0)
	Fx.burst(get_parent(), _model.point("core"), GameConfig.Element.ETHER, 30, 10.0)
	Fx.shockwave(get_parent(), global_position, Color(1.0, 0.3, 0.65), 14.0, 0.6)
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(_model, "rotation:x", -1.35, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_model, "position:y", -0.6, 0.8)
	tw.tween_callback(_on_body_fell)
	defeated.emit()

func _on_body_fell() -> void:
	shake_requested.emit(0.8)
	sfx_requested.emit("slam")
	Fx.debris(get_parent(), global_position + _model.global_transform.basis.z * -4.0, 24, 10.0)
