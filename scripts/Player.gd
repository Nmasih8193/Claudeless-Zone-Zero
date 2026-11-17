class_name Player
extends Node3D
## Squad controller: one on-field body, three Characters (individual HP / energy).
## Controls follow Zenless Zone Zero's PC defaults (see Main._setup_input):
##   LMB basic attack | Shift / RMB dodge (hold = sprint) | E special / EX special | Q ultimate
##   Space / C switch next / previous | chain attack: LMB / Q = left agent, RMB / E = right agent
## Movement is relative to the camera (view_yaw, set by Main every frame).

signal shake_requested(strength: float)
signal time_fx_requested(time_scale: float, duration: float)
signal time_fx_cancel
signal perfect_dodged
signal points_awarded(points: int, label: String)
signal swapped(index: int)
signal damaged(amount: float)
signal ultimate_cast(color: Color)
signal died
signal sfx_requested(sfx_name: String)
signal chain_prompt(left: int, right: int)       # both -1 = prompt closed
signal assist_prompt(text: String)               # "" = hide
signal cinematic_requested(kind: String, length: float)

enum State { IDLE, MOVE, ATTACK, DODGE, SEQ, DEAD }

var chars: Array[Character] = []
var active: int = 0
var boss: Boss
var state: State = State.IDLE
var decibel: float = 0.0
var swap_cd: float = 0.0
var dodge_cd: float = 0.0
var assist_buff_t: float = 0.0
var lock_yaw: float = 0.0           # yaw that faces the boss
var view_yaw: float = 0.0           # camera yaw, set by Main
var velocity: Vector3 = Vector3.ZERO
var sprinting: bool = false
var locked: bool = false            # set by Main when the fight ends (animations keep running)

var _combo_index: int = 0
var _combo_timer: float = 0.0
var _attack_timer: float = 0.0
var _lunge_t: float = 0.0
var _lunge_vel: Vector3 = Vector3.ZERO
var _dodge_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _i_frames: float = 0.0
var _counter_until_ms: int = 0
var _followup_until_ms: int = 0
var _last_perfect_id: int = -1
var _seq: Array = []
var _seq_idx: int = 0
var _seq_time: float = 0.0
var _seq_len: float = 0.0
var _seq_pos: Vector3 = Vector3.ZERO
var _seq_kind: String = ""
var _visual_idx: int = 0
var _chain_open: bool = false
var _chain_until_ms: int = 0
var _chain_left: int = -1
var _chain_right: int = -1
var _chain_used: Array[int] = []
var _chain_pending: bool = false

var _visual: Node3D                  # logic orientation only (swing / back-step direction)
var _puppets: Array[CharacterView] = []
var _prev_pos: Vector3 = Vector3.ZERO

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

func _apply_visual(i: int) -> void:
	for k in _puppets.size():
		_puppets[k].visible = (k == i)
	if i != _visual_idx:
		_puppets[i].on_swap_in()
	_visual_idx = i

func _facing() -> Vector3:
	var yaw := _visual.rotation.y
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

## Weapon trail crescent in front of the character.
func _swing_visual(element: int, heavy: bool) -> void:
	var tilt := randf_range(-0.5, 0.5)
	var col := GameConfig.element_color(element)
	Fx.slash(get_parent(), global_position + Vector3(0.0, 1.1, 0.0) + _facing() * 0.3, _visual.rotation.y, col, 2.0 if heavy else 1.6, heavy, tilt, _combo_index % 2 == 1)

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
		sprinting = false
		return
	update_lock_yaw()
	if _chain_open:
		_process_chain_prompt()
		return
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
	_expire_prompts()
	_handle_swap_input()
	sprinting = false
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
			if not _try_counter() and _dodge_timer <= 0.0:
				_i_frames = maxf(_i_frames, GameConfig.DODGE_END_I_FRAMES)
				dodge_cd = GameConfig.DODGE_COOLDOWN
				state = State.IDLE
		State.SEQ:
			_process_seq(delta)
	_constrain()

func _update_puppet(delta: float) -> void:
	velocity = (global_position - _prev_pos) / maxf(delta, 0.0001)
	velocity.y = 0.0
	_prev_pos = global_position
	_puppets[_visual_idx].tick(delta, velocity, int(state), view_yaw, _visual.rotation.y)

func _expire_prompts() -> void:
	var now := Time.get_ticks_msec()
	if (_counter_until_ms > 0 and now >= _counter_until_ms) or (_followup_until_ms > 0 and now >= _followup_until_ms):
		_counter_until_ms = 0
		_followup_until_ms = 0
		assist_prompt.emit("")

func _try_actions() -> bool:
	if _try_counter():
		return true
	if Input.is_action_just_pressed("dodge") and dodge_cd <= 0.0:
		_start_dodge()
		return true
	if Input.is_action_just_pressed("ultimate") and _try_ultimate():
		return true
	if Input.is_action_just_pressed("special") and _try_special():
		return true
	return false

func _input_to_world(input: Vector2) -> Vector3:
	var fwd := Vector3(-sin(view_yaw), 0.0, -cos(view_yaw))
	var right := Vector3(cos(view_yaw), 0.0, -sin(view_yaw))
	return right * input.x + fwd * (-input.y)

func _handle_move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := _input_to_world(input)
	if dir.length() > 0.05:
		state = State.MOVE
		sprinting = Input.is_action_pressed("dodge")
		var face := atan2(-dir.x, -dir.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, face, 1.0 - exp(-16.0 * delta))
		var spd := GameConfig.SPRINT_SPEED if sprinting else GameConfig.PLAYER_SPEED
		global_position += dir.limit_length(1.0) * spd * delta
	else:
		state = State.IDLE

func _constrain() -> void:
	var p := global_position
	p.y = 0.0
	var d := p - boss.global_position
	d.y = 0.0
	var min_d := GameConfig.BOSS_RADIUS + 0.6
	var l := d.length()
	if l < min_d and boss.global_position.y < 2.0:
		var push := d / l if l > 0.001 else Vector3(0.0, 0.0, 1.0)
		var bp := boss.global_position
		bp.y = 0.0
		p = bp + push * min_d
	var flat := Vector2(p.x, p.z)
	if flat.length() > GameConfig.ARENA_RADIUS:
		flat = flat.normalized() * GameConfig.ARENA_RADIUS
		p = Vector3(flat.x, 0.0, flat.y)
	global_position = p

func _hit_point() -> Vector3:
	var d := global_position - boss.global_position
	d.y = 0.0
	var dir := d.normalized() if d.length() > 0.01 else Vector3.BACK
	return boss.global_position + dir * GameConfig.BOSS_RADIUS + Vector3(0.0, 2.2, 0.0)

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

func _face_boss() -> void:
	var to := boss.global_position - global_position
	to.y = 0.0
	if to.length() > 0.01:
		_visual.rotation.y = atan2(-to.x, -to.z)

# ------------------------------------------------------------------ basic attack
func _start_attack() -> void:
	var c := chars[active]
	state = State.ATTACK
	_attack_timer = GameConfig.ATTACK_TIME
	_combo_timer = GameConfig.COMBO_RESET
	var to := boss.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var gap := dist - GameConfig.BOSS_RADIUS
	# soft auto-target like ZZZ: snap toward the boss when it is reasonably close
	if dist > 0.01 and gap < c.attack_range + 6.0:
		_visual.rotation.y = atan2(-to.x, -to.z)
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
		var hp := _hit_point()
		Fx.burst(get_parent(), hp, c.element, 22 if heavy else 10)
		Fx.spark(get_parent(), hp, GameConfig.element_color(c.element), 2.4 if heavy else 1.5)
		if heavy:
			shake_requested.emit(GameConfig.HEAVY_SHAKE)
			sfx_requested.emit("hit_heavy")
			time_fx_requested.emit(0.05, GameConfig.HEAVY_HIT_STOP)
			_maybe_chain_on_heavy()
	_swing_visual(c.element, heavy)
	_puppets[_visual_idx].on_attack(heavy)
	sfx_requested.emit("swing")
	_combo_index = (_combo_index + 1) % c.combo_damage.size()

# ------------------------------------------------------------------ dodge / perfect dodge / counter
func _start_dodge() -> void:
	var d := _input_to_world(Input.get_vector("move_left", "move_right", "move_forward", "move_back"))
	if d.length() < 0.05:
		d = -_facing()                       # back-step, keep facing the same way
	else:
		_visual.rotation.y = atan2(-d.x, -d.z)
	_dodge_dir = d.normalized()
	state = State.DODGE
	_dodge_timer = GameConfig.DODGE_TIME
	_lunge_t = 0.0
	_puppets[_visual_idx].on_dodge()
	sfx_requested.emit("dodge")
	var th := boss.get_threat(global_position)
	if not th.is_empty() and int(th["id"]) != _last_perfect_id:
		_last_perfect_id = th["id"]
		_counter_until_ms = Time.get_ticks_msec() + int(GameConfig.PERFECT_DURATION * 1000.0)
		time_fx_requested.emit(GameConfig.PERFECT_TIMESCALE, GameConfig.PERFECT_DURATION)
		Fx.shockwave(get_parent(), global_position, Color(0.5, 0.85, 1.0), 6.0, 0.45)
		Fx.glint(get_parent(), global_position + Vector3(0.0, 1.2, 0.0), Color(0.6, 0.9, 1.0), 2.2)
		perfect_dodged.emit()
		sfx_requested.emit("perfect")
		points_awarded.emit(GameConfig.PERFECT_POINTS, "Perfect Dodge")
		assist_prompt.emit("[LMB] DODGE COUNTER        [SPACE / C] EVASIVE ASSIST")

## Attack during the perfect-dodge slow-mo -> Dodge Counter. Attack after a parry -> Assist Follow-Up.
func _try_counter() -> bool:
	if not Input.is_action_just_pressed("attack"):
		return false
	var now := Time.get_ticks_msec()
	if now < _counter_until_ms:
		_counter_until_ms = 0
		assist_prompt.emit("")
		time_fx_cancel.emit()
		var c := chars[active]
		sfx_requested.emit("counter")
		_begin_seq(c.make_counter_steps(), 0.5, "counter", c.seq_stand if c.seq_stand > 0.0 else -1.0)
		return true
	if now < _followup_until_ms:
		_followup_until_ms = 0
		assist_prompt.emit("")
		var c2 := chars[active]
		points_awarded.emit(int(GameConfig.ASSIST_POINTS * 0.5), "Assist Follow-Up")
		sfx_requested.emit("ex")
		_begin_seq(c2.make_steps(c2.assist_rows), c2.assist_len, "assist", c2.seq_stand)
		return true
	return false

# ------------------------------------------------------------------ swapping / assists
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
	if Input.is_action_just_pressed("swap_next"):
		want = _next_alive(active, 1)
	elif Input.is_action_just_pressed("swap_prev"):
		want = _next_alive(active, -1)
	if want < 0 or want == active or not chars[want].is_alive():
		return
	var now := Time.get_ticks_msec()
	if now < _counter_until_ms:
		# Evasive Assist: swap during the perfect-dodge slow-mo
		_counter_until_ms = 0
		assist_prompt.emit("")
		_swap_to(want)
		_start_assist("Evasive Assist")
		return
	var th := boss.get_threat(global_position)
	if not th.is_empty() and bool(th["parry"]) and int(th["id"]) != _last_perfect_id:
		_swap_to(want)
		_parry(int(th["id"]))
		return
	if swap_cd <= 0.0 and state != State.DODGE:
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

func _start_assist(label: String) -> void:
	var c := chars[active]
	c.on_assist(self)
	_gain_decibel(GameConfig.DECIBEL_ASSIST)
	dodge_cd = GameConfig.DODGE_COOLDOWN
	points_awarded.emit(GameConfig.ASSIST_POINTS, label)
	_begin_seq(c.make_steps(c.assist_rows), c.assist_len, "assist", c.seq_stand)

## Defensive Assist: the incoming agent blocks a GOLD-flash hit, dazes the boss, then
## LMB within FOLLOWUP_WINDOW launches the Assist Follow-Up.
func _parry(threat_id: int) -> void:
	var c := chars[active]
	_last_perfect_id = threat_id
	_i_frames = maxf(_i_frames, 0.6)
	state = State.IDLE
	_face_boss()
	c.on_assist(self)
	boss.take_damage(GameConfig.PARRY_DAMAGE * _damage_mult(active), c.element, GameConfig.PARRY_DAZE, c.freeze_per_hit * 2.0)
	var p := global_position + Vector3(0.0, 1.4, 0.0) + _facing() * 0.9
	Fx.glint(get_parent(), p, Color(1.0, 0.85, 0.3), 3.0)
	Fx.burst(get_parent(), p, c.element, 18, 8.0)
	Fx.shockwave(get_parent(), global_position, Color(1.0, 0.85, 0.3), 5.0, 0.3)
	sfx_requested.emit("parry")
	shake_requested.emit(0.4)
	time_fx_requested.emit(0.1, 0.3)
	_gain_decibel(GameConfig.DECIBEL_ASSIST)
	points_awarded.emit(GameConfig.ASSIST_POINTS, "Defensive Assist")
	_followup_until_ms = Time.get_ticks_msec() + int(GameConfig.FOLLOWUP_WINDOW * 1000.0)
	assist_prompt.emit("[LMB] ASSIST FOLLOW-UP")
	_puppets[_visual_idx].on_attack(true)

# ------------------------------------------------------------------ special / EX / ultimate
func _try_special() -> bool:
	var c := chars[active]
	if not boss.is_hittable():
		return false
	if c.energy >= c.ex_cost:
		c.energy -= c.ex_cost
		sfx_requested.emit("ex")
		c.ex_start(self)
		_begin_seq(c.make_ex_steps(), c.ex_len, "ex", c.seq_stand)
	else:
		sfx_requested.emit("swing")
		_begin_seq(c.make_special_steps(), 0.45, "special", c.seq_stand)
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
	cinematic_requested.emit("ult", c.ult_len + 0.3)
	_begin_seq(c.make_steps(c.ult_rows), c.ult_len, "ult", c.seq_stand)
	return true

# ------------------------------------------------------------------ chain attacks
## Opens the ZZZ chain picker: the world nearly freezes, the off-field agents appear left/right.
func open_chain_prompt(first: bool) -> void:
	if state == State.DEAD or locked or not boss.is_stunned():
		return
	if first:
		_chain_used.clear()
	if state == State.SEQ:
		_chain_pending = true
		return
	var l := posmod(active - 1, 3)
	var r := posmod(active + 1, 3)
	_chain_left = l if chars[l].is_alive() and not _chain_used.has(l) else -1
	_chain_right = r if chars[r].is_alive() and not _chain_used.has(r) else -1
	if _chain_left < 0 and _chain_right < 0:
		return
	_chain_open = true
	_chain_until_ms = Time.get_ticks_msec() + int(GameConfig.CHAIN_PROMPT_TIME * 1000.0)
	if state != State.IDLE:
		state = State.IDLE
	_lunge_t = 0.0
	time_fx_requested.emit(GameConfig.CHAIN_TIMESCALE, GameConfig.CHAIN_PROMPT_TIME + 0.2)
	chain_prompt.emit(_chain_left, _chain_right)
	sfx_requested.emit("chain")

func chain_time_left() -> float:
	return maxf(float(_chain_until_ms - Time.get_ticks_msec()) / 1000.0, 0.0) if _chain_open else 0.0

func _process_chain_prompt() -> void:
	var pick := -1
	if Input.is_action_just_pressed("chain_left") and _chain_left >= 0:
		pick = _chain_left
	elif Input.is_action_just_pressed("chain_right") and _chain_right >= 0:
		pick = _chain_right
	if pick >= 0:
		_do_chain(pick)
	elif Time.get_ticks_msec() >= _chain_until_ms or not boss.is_stunned():
		_close_chain()

func _close_chain() -> void:
	_chain_open = false
	chain_prompt.emit(-1, -1)
	time_fx_cancel.emit()

func _do_chain(i: int) -> void:
	_close_chain()
	_chain_used.append(i)
	if i != active:
		_swap_to(i)
	var c := chars[i]
	points_awarded.emit(GameConfig.CHAIN_POINTS, "Chain Attack")
	_gain_decibel(GameConfig.DECIBEL_CHAIN)
	cinematic_requested.emit("chain", c.chain_len + 0.25)
	_begin_seq(c.make_steps(c.chain_rows), c.chain_len, "chain", GameConfig.BOSS_RADIUS + 1.6)

## A heavy hit on a stunned boss re-opens the chain picker if it was skipped.
func _maybe_chain_on_heavy() -> void:
	if boss.is_stunned() and _chain_used.is_empty() and not _chain_open:
		open_chain_prompt(true)

# ------------------------------------------------------------------ scripted sequences
func _begin_seq(steps: Array, length: float, kind: String, stand: float) -> void:
	_seq = steps
	_seq_idx = 0
	_seq_time = 0.0
	_seq_len = length
	_seq_kind = kind
	state = State.SEQ
	_lunge_t = 0.0
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
	_face_boss()
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
	if not c.is_alive() or not boss.is_hittable():
		return
	if ci != _visual_idx:
		_apply_visual(ci)
	var elem: int = s["elem"]
	var dmg: float = float(s["dmg"]) * _damage_mult(ci)
	boss.take_damage(dmg, elem, float(s["daze"]), float(s["freeze"]))
	var hp := _hit_point()
	Fx.burst(get_parent(), hp, elem, 16)
	var sh: float = s["shake"]
	Fx.spark(get_parent(), hp, GameConfig.element_color(elem), 3.0 if sh >= 0.3 else 1.8)
	if sh > 0.0:
		shake_requested.emit(sh)
	if sh >= 0.3:
		time_fx_requested.emit(0.1, 0.05)
		sfx_requested.emit("hit_heavy")
	if _seq_kind != "ult":
		_gain_decibel(GameConfig.DECIBEL_PER_HIT)
	_combo_index += 1
	_swing_visual(elem, sh >= 0.3)
	_puppets[_visual_idx].on_step(sh >= 0.3)

func _end_seq() -> void:
	_apply_visual(active)
	state = State.IDLE
	_i_frames = maxf(_i_frames, 0.3)
	_combo_index = 0
	if _seq_kind == "chain" or _chain_pending:
		var first := _chain_pending and _seq_kind != "chain"
		_chain_pending = false
		open_chain_prompt(first)

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
	if state == State.ATTACK:
		state = State.IDLE
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
