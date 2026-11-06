class_name Player
extends Node3D
## Squad controller: one on-field body, three Characters (individual HP / energy).
## No physics engine is used; everything runs in _process for smooth motion.

signal shake_requested(strength: float)
signal time_fx_requested(time_scale: float, duration: float)
signal perfect_dodged
signal points_awarded(points: int, label: String)
signal swapped(index: int)
signal damaged(amount: float)
signal ultimate_cast(color: Color)
signal died
signal sfx_requested(sfx_name: String)

enum State { IDLE, MOVE, ATTACK, DODGE, SEQ, DEAD }

var chars: Array[Character] = []
var active: int = 0
var boss: Boss
var state: State = State.IDLE
var decibel: float = 0.0
var swap_cd: float = 0.0
var dodge_cd: float = 0.0
var chain_ready: bool = false
var assist_buff_t: float = 0.0
var lock_yaw: float = 0.0

var _combo_index: int = 0
var _combo_timer: float = 0.0
var _attack_timer: float = 0.0
var _lunge_t: float = 0.0
var _lunge_vel: Vector3 = Vector3.ZERO
var _dodge_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _i_frames: float = 0.0
var _assist_until_ms: int = 0
var _last_perfect_id: int = -1
var _seq: Array = []
var _seq_idx: int = 0
var _seq_time: float = 0.0
var _seq_len: float = 0.0
var _seq_pos: Vector3 = Vector3.ZERO
var _seq_kind: String = ""
var _visual_idx: int = 0

var locked: bool = false             # set by Main when the fight ends (animations keep running)
var view_yaw: float = 0.0           # set by Main each frame: the camera yaw (puppets face the camera)
var _visual: Node3D                  # logic orientation only (swing / back-step direction)
var _puppets: Array[CharacterView] = []
var _prev_pos: Vector3 = Vector3.ZERO
var _swing: MeshInstance3D
var _swing_mat: StandardMaterial3D
var _swing_tween: Tween

func _ready() -> void:
	chars.append(Ellen.new())
	chars.append(Nicole.new())
	chars.append(Anby.new())
	_prev_pos = global_position
	_build_visual()
	_apply_visual(0)

# ------------------------------------------------------------------ visuals
func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	for c in chars:
		var pup: CharacterView
		if GameConfig.USE_3D_MODELS:
			pup = Model3D.new()
		else:
			pup = Puppet.new()
		add_child(pup)
		pup.setup(c.char_name)
		pup.visible = false
		_puppets.append(pup)
	_swing = MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(3.4, 0.1, 1.4)
	_swing.mesh = sm
	_swing_mat = Fx.flat_alpha_mat(Color(0.6, 0.95, 1.0, 0.8))
	_swing.material_override = _swing_mat
	_swing.visible = false
	add_child(_swing)

func _apply_visual(i: int) -> void:
	for k in _puppets.size():
		_puppets[k].visible = (k == i)
	if i != _visual_idx:
		_puppets[i].on_swap_in()
	_visual_idx = i

func _swing_visual(element: int, heavy: bool) -> void:
	var yaw := _visual.rotation.y
	_swing.visible = true
	_swing.position = Vector3(-sin(yaw), 0.0, -cos(yaw)) * 1.9 + Vector3(0.0, 1.0, 0.0)
	_swing.rotation.y = yaw
	_swing_mat.albedo_color = Color(GameConfig.element_color(element), 0.8)
	var s: float = 1.7 if heavy else 1.1
	_swing.scale = Vector3(0.5, 1.0, 0.5)
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.tween_property(_swing, "scale", Vector3(s, 1.0, s), 0.1)
	_swing_tween.tween_callback(func() -> void: _swing.visible = false)

# ------------------------------------------------------------------ main loop
func update_lock_yaw() -> void:
	var to := boss.global_position - global_position
	to.y = 0.0
	if to.length() > 0.1:
		lock_yaw = atan2(-to.x, -to.z)

func is_invulnerable() -> bool:
	return state == State.DODGE or state == State.SEQ or _i_frames > 0.0

func _process(delta: float) -> void:
	if boss == null:
		return
	delta = minf(delta, 0.05)
	_update_puppet(delta)
	if state == State.DEAD or locked:
		return
	update_lock_yaw()
	_combo_timer = maxf(_combo_timer - delta, 0.0)
	if _combo_timer <= 0.0:
		_combo_index = 0
	dodge_cd = maxf(dodge_cd - delta, 0.0)
	swap_cd = maxf(swap_cd - delta, 0.0)
	_i_frames = maxf(_i_frames - delta, 0.0)
	assist_buff_t = maxf(assist_buff_t - delta, 0.0)
	for i in chars.size():
		if i != active:
			chars[i].energy = minf(chars[i].energy + GameConfig.OFF_FIELD_ENERGY_REGEN * delta, GameConfig.ENERGY_MAX)
	_handle_swap_input()
	match state:
		State.IDLE, State.MOVE:
			if not _try_actions():
				_handle_move(delta)
				if Input.is_action_pressed("attack"):
					_start_attack()
		State.ATTACK:
			_attack_timer -= delta
			if _lunge_t > 0.0:
				_lunge_t -= delta
				global_position += _lunge_vel * delta
			if not _try_actions() and _attack_timer <= 0.0:
				state = State.IDLE
		State.DODGE:
			_dodge_timer -= delta
			global_position += _dodge_dir * GameConfig.DODGE_SPEED * delta
			if _dodge_timer <= 0.0:
				_i_frames = maxf(_i_frames, GameConfig.DODGE_END_I_FRAMES)
				dodge_cd = GameConfig.DODGE_COOLDOWN
				state = State.IDLE
		State.SEQ:
			_process_seq(delta)
	_constrain()

func _update_puppet(delta: float) -> void:
	var v := (global_position - _prev_pos) / maxf(delta, 0.0001)
	_prev_pos = global_position
	_puppets[_visual_idx].tick(delta, v, int(state), view_yaw, _visual.rotation.y)

func _try_actions() -> bool:
	if Input.is_action_just_pressed("dodge") and dodge_cd <= 0.0:
		_start_dodge()
		return true
	if Input.is_action_just_pressed("ultimate") and _try_ultimate():
		return true
	if Input.is_action_just_pressed("ex") and _try_ex():
		return true
	if Input.is_action_just_pressed("chain") and _try_chain():
		return true
	return false

func _input_to_world(input: Vector2) -> Vector3:
	var fwd := Vector3(-sin(lock_yaw), 0.0, -cos(lock_yaw))
	var right := Vector3(cos(lock_yaw), 0.0, -sin(lock_yaw))
	return right * input.x + fwd * (-input.y)

func _handle_move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := _input_to_world(input)
	if dir.length() > 0.01:
		state = State.MOVE
		var face := atan2(-dir.x, -dir.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, face, 1.0 - exp(-18.0 * delta))
		global_position += dir * GameConfig.PLAYER_SPEED * delta
	else:
		state = State.IDLE

func _constrain() -> void:
	var p := global_position
	p.y = 0.0
	var d := p - boss.global_position
	d.y = 0.0
	var min_d := GameConfig.BOSS_RADIUS + 0.6
	var l := d.length()
	if l < min_d:
		var push := d / l if l > 0.001 else Vector3(0.0, 0.0, 1.0)
		p = boss.global_position + push * min_d
		p.y = 0.0
	var flat := Vector2(p.x, p.z)
	if flat.length() > GameConfig.ARENA_RADIUS:
		flat = flat.normalized() * GameConfig.ARENA_RADIUS
		p = Vector3(flat.x, 0.0, flat.y)
	global_position = p

func _hit_point() -> Vector3:
	var d := global_position - boss.global_position
	d.y = 0.0
	var dir := d.normalized() if d.length() > 0.01 else Vector3.BACK
	return boss.global_position + dir * GameConfig.BOSS_RADIUS + Vector3(0.0, 1.6, 0.0)

func _damage_mult(idx: int) -> float:
	var m := 1.0 + chars[active].field_buff
	if assist_buff_t > 0.0:
		m += GameConfig.ASSIST_BUFF
	if boss.is_stunned():
		m *= chars[idx].stun_bonus
	return m

func _gain_energy(a: float) -> void:
	var c := chars[active]
	c.energy = minf(c.energy + a, GameConfig.ENERGY_MAX)

func _gain_decibel(a: float) -> void:
	decibel = minf(decibel + a, GameConfig.DECIBEL_MAX)

# ------------------------------------------------------------------ basic attack
func _start_attack() -> void:
	var c := chars[active]
	state = State.ATTACK
	_attack_timer = GameConfig.ATTACK_TIME
	_combo_timer = GameConfig.COMBO_RESET
	var to := boss.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > 0.01:
		_visual.rotation.y = atan2(-to.x, -to.z)
	var gap := dist - GameConfig.BOSS_RADIUS
	var lunge_dist := GameConfig.LUNGE_SPEED * GameConfig.LUNGE_TIME
	if dist > 0.01 and gap > c.attack_range * 0.6 and gap <= c.attack_range + 2.5:
		_lunge_t = GameConfig.LUNGE_TIME
		_lunge_vel = to / dist * GameConfig.LUNGE_SPEED
	else:
		_lunge_t = 0.0
		lunge_dist = 0.0
	var idx := _combo_index
	var heavy := idx == c.combo_damage.size() - 1
	if gap - lunge_dist <= c.attack_range and boss.is_hittable():
		var dmg: float = float(c.combo_damage[idx]) * _damage_mult(active)
		boss.take_damage(dmg, c.element, c.daze_per_hit, c.freeze_per_hit)
		c.on_basic_hit(self, idx)
		_gain_energy(c.energy_per_hit)
		_gain_decibel(GameConfig.DECIBEL_PER_HIT)
		Fx.burst(get_parent(), _hit_point(), c.element, 22 if heavy else 10)
		if heavy:
			shake_requested.emit(GameConfig.HEAVY_SHAKE)
			sfx_requested.emit("hit_heavy")
			time_fx_requested.emit(0.05, GameConfig.HEAVY_HIT_STOP)
	_swing_visual(c.element, heavy)
	_puppets[_visual_idx].on_attack(heavy)
	sfx_requested.emit("swing")
	_combo_index = (_combo_index + 1) % c.combo_damage.size()

# ------------------------------------------------------------------ dodge / perfect dodge
func _start_dodge() -> void:
	var d := _input_to_world(Input.get_vector("move_left", "move_right", "move_forward", "move_back"))
	if d.length() < 0.01:
		var yaw := _visual.rotation.y
		d = Vector3(sin(yaw), 0.0, cos(yaw))    # back-step
	_dodge_dir = d.normalized()
	state = State.DODGE
	_dodge_timer = GameConfig.DODGE_TIME
	_lunge_t = 0.0
	_swing.visible = false
	_puppets[_visual_idx].on_dodge()
	sfx_requested.emit("dodge")
	if boss.is_threatening(global_position) and boss.attack_id != _last_perfect_id:
		_last_perfect_id = boss.attack_id
		_assist_until_ms = Time.get_ticks_msec() + int(GameConfig.PERFECT_DURATION * 1000.0)
		time_fx_requested.emit(GameConfig.PERFECT_TIMESCALE, GameConfig.PERFECT_DURATION)
		Fx.shockwave(get_parent(), global_position, Color(1.0, 0.95, 0.3), 5.0, 0.4)
		perfect_dodged.emit()
		sfx_requested.emit("perfect")
		points_awarded.emit(GameConfig.PERFECT_POINTS, "Perfect Dodge")

# ------------------------------------------------------------------ swapping / assist
func _next_alive(from: int, step: int) -> int:
	for k in range(1, 3):
		var i := posmod(from + step * k, 3)
		if chars[i].is_alive():
			return i
	return -1

func _handle_swap_input() -> void:
	if state == State.SEQ:
		return
	var want := -1
	if Input.is_action_just_pressed("swap_1"):
		want = 0
	elif Input.is_action_just_pressed("swap_2"):
		want = 1
	elif Input.is_action_just_pressed("swap_3"):
		want = 2
	elif Input.is_action_just_pressed("swap_next"):
		want = _next_alive(active, 1)
	elif Input.is_action_just_pressed("swap_prev"):
		want = _next_alive(active, -1)
	if want < 0 or want == active or not chars[want].is_alive():
		return
	if Time.get_ticks_msec() < _assist_until_ms:
		_assist_until_ms = 0
		_swap_to(want)
		_start_assist()
	elif swap_cd <= 0.0 and state != State.DODGE:
		_swap_to(want)
		swap_cd = GameConfig.SWAP_COOLDOWN

func _swap_to(i: int) -> void:
	active = i
	_apply_visual(i)
	_combo_index = 0
	if state == State.ATTACK:
		state = State.IDLE
	Fx.shockwave(get_parent(), global_position, chars[i].color, 3.0, 0.3)
	Fx.burst(get_parent(), global_position + Vector3(0.0, 1.0, 0.0), chars[i].element, 10, 5.0)
	sfx_requested.emit("swap")
	swapped.emit(i)

func _start_assist() -> void:
	var c := chars[active]
	c.on_assist(self)
	_gain_decibel(GameConfig.DECIBEL_ASSIST)
	dodge_cd = GameConfig.DODGE_COOLDOWN
	points_awarded.emit(GameConfig.ASSIST_POINTS, "Assist Attack")
	_begin_seq(c.make_steps(c.assist_rows), c.assist_len, "assist", c.seq_stand)

# ------------------------------------------------------------------ EX / ultimate / chain
func _try_ex() -> bool:
	var c := chars[active]
	if c.energy < c.ex_cost or not boss.is_hittable():
		return false
	c.energy -= c.ex_cost
	sfx_requested.emit("ex")
	c.ex_start(self)
	_begin_seq(c.make_ex_steps(), c.ex_len, "ex", c.seq_stand)
	return true

func _try_ultimate() -> bool:
	if decibel < GameConfig.DECIBEL_MAX or not boss.is_hittable():
		return false
	decibel = 0.0
	var c := chars[active]
	ultimate_cast.emit(c.color)
	sfx_requested.emit("ult")
	shake_requested.emit(0.4)
	time_fx_requested.emit(0.15, 0.3)
	_begin_seq(c.make_steps(c.ult_rows), c.ult_len, "ult", c.seq_stand)
	return true

func _try_chain() -> bool:
	if not chain_ready or not boss.is_stunned():
		return false
	chain_ready = false
	_gain_decibel(GameConfig.DECIBEL_CHAIN)
	points_awarded.emit(GameConfig.CHAIN_POINTS, "Chain Attack")
	sfx_requested.emit("chain")
	var steps: Array = []
	for r: Array in GameConfig.CHAIN_STEPS:
		var ci: int = r[1]
		steps.append({
			"t": float(r[0]), "char": ci, "dmg": float(r[2]), "daze": 0.0, "freeze": 0.0,
			"shake": float(r[3]), "elem": chars[ci].element,
		})
	_begin_seq(steps, GameConfig.CHAIN_LEN, "chain", GameConfig.BOSS_RADIUS + 1.5)
	return true

# ------------------------------------------------------------------ scripted sequences
func _begin_seq(steps: Array, length: float, kind: String, stand: float) -> void:
	_seq = steps
	_seq_idx = 0
	_seq_time = 0.0
	_seq_len = length
	_seq_kind = kind
	state = State.SEQ
	_lunge_t = 0.0
	_swing.visible = false
	var to := boss.global_position - global_position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	if stand < 0.0:
		_seq_pos = global_position
	else:
		_seq_pos = boss.global_position - dir * stand
	_seq_pos.y = 0.0
	_visual.rotation.y = atan2(-dir.x, -dir.z)

func _process_seq(delta: float) -> void:
	_seq_time += delta
	global_position = global_position.move_toward(_seq_pos, GameConfig.SEQ_MOVE_SPEED * delta)
	while _seq_idx < _seq.size() and _seq_time >= float(_seq[_seq_idx]["t"]):
		_fire_step(_seq[_seq_idx])
		_seq_idx += 1
	if _seq_time >= _seq_len:
		_end_seq()

func _fire_step(s: Dictionary) -> void:
	var ci: int = s["char"]
	if ci < 0:
		ci = active
	var c := chars[ci]
	if not c.is_alive():
		return
	if ci != _visual_idx:
		_apply_visual(ci)
	var elem: int = s["elem"]
	var dmg: float = float(s["dmg"]) * _damage_mult(ci)
	boss.take_damage(dmg, elem, float(s["daze"]), float(s["freeze"]))
	Fx.burst(get_parent(), _hit_point(), elem, 16)
	var sh: float = s["shake"]
	if sh > 0.0:
		shake_requested.emit(sh)
	if sh >= 0.3:
		time_fx_requested.emit(0.1, 0.05)
	if _seq_kind != "ult":
		_gain_decibel(GameConfig.DECIBEL_PER_HIT)
	_swing_visual(elem, sh >= 0.3)
	_puppets[_visual_idx].on_step(sh >= 0.3)

func _end_seq() -> void:
	if _seq_kind == "chain" and chars[0].is_alive() and active != 0:
		active = 0
		swapped.emit(0)
	_apply_visual(active)
	state = State.IDLE
	_i_frames = maxf(_i_frames, 0.3)
	_combo_index = 0

# ------------------------------------------------------------------ taking damage
func take_damage(amount: float) -> void:
	if state == State.DEAD or is_invulnerable():
		return
	var c := chars[active]
	c.hp = maxf(c.hp - amount, 0.0)
	_i_frames = GameConfig.HIT_I_FRAMES
	damaged.emit(amount)
	_puppets[_visual_idx].on_hurt()
	sfx_requested.emit("hurt")
	shake_requested.emit(0.3)
	if c.hp > 0.0:
		return
	var nxt := _next_alive(active, 1)
	if nxt < 0:
		state = State.DEAD
		_puppets[_visual_idx].on_dead()
		died.emit()
	else:
		_swap_to(nxt)
		swap_cd = 0.5
