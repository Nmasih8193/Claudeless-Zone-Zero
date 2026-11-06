class_name Boss
extends Node3D

signal hp_changed(hp: float, max_hp: float)
signal damage_taken(amount: float)
signal phase_changed(phase: int)
signal stunned
signal stun_ended
signal shake_requested(strength: float)
signal defeated
signal sfx_requested(sfx_name: String)

enum State { IDLE, TELEGRAPH, CHARGING, RECOVER, STUNNED, DEAD }
enum Zone { NONE, CIRCLE, RECT, ALL }

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
var perfect_window: bool = false

var _state_timer: float = 0.0
var _tele_total: float = 1.0
var _attack_cd: float = 1.5
var _enrage_timer: float = 0.0
var _last_attack: int = -1
var _cur_attack: int = -1
var _zone: Zone = Zone.NONE
var _zone_center: Vector3 = Vector3.ZERO
var _zone_dir: Vector3 = Vector3.FORWARD
var _zone_len: float = 0.0
var _zone_w: float = 0.0
var _zone_r: float = 0.0
var _charge_from: Vector3 = Vector3.ZERO
var _charge_to: Vector3 = Vector3.ZERO
var _charge_time: float = 0.45
var _charge_dmg: float = 0.0
var _charge_hit: bool = false
var _pull_t: float = 0.0
var _pull_target: Vector3 = Vector3.ZERO
var _flash_t: float = 0.0

var _visual: Node3D
var _body_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _ice_shell: MeshInstance3D
var _ind_circle: MeshInstance3D
var _ind_rect: MeshInstance3D
var _circle_mat: StandardMaterial3D
var _rect_mat: StandardMaterial3D

func _ready() -> void:
	_enrage_timer = GameConfig.ENRAGE_DATA["first_delay"]
	_build_visual()

# ------------------------------------------------------------------ visuals
func _add_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	_visual.add_child(m)
	return m

func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.17, 0.16, 0.22)
	_body_mat.metallic = 0.6
	_body_mat.roughness = 0.4
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(1.0, 0.35, 0.45)
	_body_mat.emission_energy_multiplier = 0.0
	var trim_mat := Fx.glow_mat(Color(0.8, 0.1, 0.2), 1.2)
	_core_mat = Fx.glow_mat(Color(1.0, 0.2, 0.7), 2.5)
	_add_box(Vector3(4.4, 3.6, 2.8), Vector3(0.0, 3.9, 0.0), _body_mat)      # torso
	_add_box(Vector3(1.8, 1.3, 1.6), Vector3(0.0, 6.5, -0.1), _body_mat)     # head
	_add_box(Vector3(1.5, 1.4, 1.5), Vector3(-2.9, 5.4, 0.0), trim_mat)      # shoulders
	_add_box(Vector3(1.5, 1.4, 1.5), Vector3(2.9, 5.4, 0.0), trim_mat)
	_add_box(Vector3(1.1, 3.6, 1.1), Vector3(-2.9, 3.0, -0.3), _body_mat)    # arms
	_add_box(Vector3(1.1, 3.6, 1.1), Vector3(2.9, 3.0, -0.3), _body_mat)
	_add_box(Vector3(1.6, 2.2, 1.6), Vector3(-1.3, 1.1, 0.0), _body_mat)     # legs
	_add_box(Vector3(1.6, 2.2, 1.6), Vector3(1.3, 1.1, 0.0), _body_mat)
	_add_box(Vector3(1.4, 0.22, 0.2), Vector3(0.0, 6.55, -0.95), Fx.glow_mat(Color(1.0, 0.1, 0.2), 6.0))  # eye
	var core := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.75
	sph.height = 1.5
	core.mesh = sph
	core.material_override = _core_mat
	core.position = Vector3(0.0, 4.2, -1.45)
	_visual.add_child(core)

	_ice_shell = MeshInstance3D.new()
	var shell := BoxMesh.new()
	shell.size = Vector3(8.0, 8.8, 4.6)
	_ice_shell.mesh = shell
	_ice_shell.material_override = Fx.flat_alpha_mat(Color(0.5, 0.92, 1.0, 0.45))
	_ice_shell.position = Vector3(0.0, 4.4, 0.0)
	_ice_shell.visible = false
	add_child(_ice_shell)

	_circle_mat = Fx.flat_alpha_mat(Color(1.0, 0.12, 0.12, 0.3))
	_ind_circle = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.05
	disc.radial_segments = 48
	disc.rings = 1
	_ind_circle.mesh = disc
	_ind_circle.material_override = _circle_mat
	_ind_circle.top_level = true
	_ind_circle.visible = false
	add_child(_ind_circle)

	_rect_mat = Fx.flat_alpha_mat(Color(1.0, 0.12, 0.12, 0.3))
	_ind_rect = MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(1.0, 0.05, 1.0)
	_ind_rect.mesh = slab
	_ind_rect.material_override = _rect_mat
	_ind_rect.top_level = true
	_ind_rect.visible = false
	add_child(_ind_rect)

# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if state == State.DEAD or target == null:
		return
	delta = minf(delta, 0.05)
	_flash_t = maxf(_flash_t - delta * 6.0, 0.0)
	_body_mat.emission_energy_multiplier = _flash_t * 2.5
	def_down_t = maxf(def_down_t - delta, 0.0)
	_update_pull(delta)
	if frozen_t > 0.0:
		frozen_t -= delta
		if frozen_t <= 0.0:
			_ice_shell.visible = false
		return
	match state:
		State.IDLE:
			_process_idle(delta)
		State.TELEGRAPH:
			_process_telegraph(delta)
		State.CHARGING:
			_process_charging(delta)
		State.RECOVER:
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.IDLE
		State.STUNNED:
			stun_t -= delta
			if stun_t <= 0.0:
				_end_stun()

func _process_idle(delta: float) -> void:
	_face(target.global_position)
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > GameConfig.BOSS_RADIUS + 3.5:
		global_position += to / dist * GameConfig.BOSS_SPEED * delta
		_clamp_arena()
	_attack_cd -= delta
	if phase >= 3:
		_enrage_timer -= delta
	if _attack_cd <= 0.0:
		_start_attack(_choose_attack())

func _choose_attack() -> int:
	if phase >= 3 and _enrage_timer <= 0.0:
		_enrage_timer = GameConfig.ENRAGE_DATA["interval"]
		return GameConfig.Attack.ENRAGE
	var pool: Array = GameConfig.ATTACK_POOL[phase - 1]
	var pick: int = pool[randi() % pool.size()]
	if pick == _last_attack and pool.size() > 1:
		pick = pool[randi() % pool.size()]
	return pick

func _data(a: int) -> Dictionary:
	match a:
		GameConfig.Attack.SWEEP:
			return GameConfig.SWEEP_DATA
		GameConfig.Attack.VOLLEY:
			return GameConfig.VOLLEY_DATA
		GameConfig.Attack.CHARGE:
			return GameConfig.CHARGE_DATA
		GameConfig.Attack.ENRAGE:
			return GameConfig.ENRAGE_DATA
	return GameConfig.SLAM_DATA

# ------------------------------------------------------------------ attacks
func _start_attack(a: int) -> void:
	_cur_attack = a
	_last_attack = a
	attack_id += 1
	var d: Dictionary = _data(a)
	_tele_total = d["tele"]
	_state_timer = _tele_total
	state = State.TELEGRAPH
	perfect_window = false
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	_zone_dir = to / dist if dist > 0.01 else Vector3.FORWARD
	_zone_center = Vector3(global_position.x, 0.0, global_position.z)
	match a:
		GameConfig.Attack.SLAM:
			_zone = Zone.CIRCLE
			_zone_center = Vector3(target.global_position.x, 0.0, target.global_position.z)
			_zone_r = d["radius"]
		GameConfig.Attack.SWEEP:
			_zone = Zone.RECT
			_zone_len = d["length"]
			_zone_w = d["width"]
		GameConfig.Attack.CHARGE:
			_zone = Zone.RECT
			var overshoot: float = d["overshoot"]
			_zone_len = minf(dist + overshoot, GameConfig.ARENA_RADIUS * 1.5)
			_zone_w = d["width"]
		GameConfig.Attack.ENRAGE:
			_zone = Zone.ALL
		_:
			_zone = Zone.NONE
	_show_indicator()
	sfx_requested.emit("warn")

func _show_indicator() -> void:
	_ind_circle.visible = false
	_ind_rect.visible = false
	match _zone:
		Zone.CIRCLE:
			_ind_circle.visible = true
			_ind_circle.global_position = Vector3(_zone_center.x, 0.06, _zone_center.z)
			_ind_circle.scale = Vector3(_zone_r, 1.0, _zone_r)
		Zone.ALL:
			_ind_circle.visible = true
			_ind_circle.global_position = Vector3(0.0, 0.06, 0.0)
			_ind_circle.scale = Vector3(GameConfig.ARENA_RADIUS + 2.0, 1.0, GameConfig.ARENA_RADIUS + 2.0)
		Zone.RECT:
			_ind_rect.visible = true
			var c := _zone_center + _zone_dir * _zone_len * 0.5
			_ind_rect.global_position = Vector3(c.x, 0.06, c.z)
			_ind_rect.scale = Vector3(_zone_w, 1.0, _zone_len)
			_ind_rect.rotation.y = atan2(-_zone_dir.x, -_zone_dir.z)

func _hide_indicators() -> void:
	_ind_circle.visible = false
	_ind_rect.visible = false
	perfect_window = false

func _process_telegraph(delta: float) -> void:
	_state_timer -= delta
	var progress := 1.0 - clampf(_state_timer / _tele_total, 0.0, 1.0)
	perfect_window = _zone != Zone.NONE and _state_timer <= GameConfig.PERFECT_WINDOW
	var c := Color(1.0, 0.12, 0.12, 0.15 + 0.35 * progress)
	if perfect_window:
		c = Color(1.0, 0.95, 0.1, 0.7)
	_circle_mat.albedo_color = c
	_rect_mat.albedo_color = c
	_core_mat.emission_energy_multiplier = 2.5 + 5.0 * progress
	if _cur_attack == GameConfig.Attack.SLAM or _cur_attack == GameConfig.Attack.VOLLEY:
		_face(target.global_position)
	else:
		_visual.rotation.y = atan2(-_zone_dir.x, -_zone_dir.z)
	if _state_timer <= 0.0:
		_execute_attack()

func _execute_attack() -> void:
	var d: Dictionary = _data(_cur_attack)
	_hide_indicators()
	_core_mat.emission_energy_multiplier = 2.5
	match _cur_attack:
		GameConfig.Attack.SLAM, GameConfig.Attack.SWEEP, GameConfig.Attack.ENRAGE:
			var dmg: float = d["dmg"]
			if _in_zone(target.global_position, 0.0):
				target.take_damage(dmg)
			var fx_pos := _zone_center
			var fx_r := 5.0
			var strength := 0.5
			if _cur_attack == GameConfig.Attack.SWEEP:
				fx_pos = _zone_center + _zone_dir * _zone_len * 0.5
				fx_r = _zone_w
			elif _cur_attack == GameConfig.Attack.ENRAGE:
				fx_pos = Vector3.ZERO
				fx_r = GameConfig.ARENA_RADIUS + 2.0
				strength = 1.0
			Fx.shockwave(get_parent(), fx_pos, Color(1.0, 0.4, 0.2), fx_r, 0.4)
			sfx_requested.emit("slam")
			shake_requested.emit(strength)
			_begin_recover(GameConfig.BOSS_RECOVER_TIME)
		GameConfig.Attack.VOLLEY:
			_fire_volley(d)
			sfx_requested.emit("zap")
			_begin_recover(GameConfig.BOSS_RECOVER_TIME)
		GameConfig.Attack.CHARGE:
			state = State.CHARGING
			sfx_requested.emit("dodge")
			_charge_time = d["time"]
			_charge_dmg = d["dmg"]
			_state_timer = _charge_time
			_charge_hit = false
			_charge_from = global_position
			var travel := maxf(_zone_len - GameConfig.BOSS_RADIUS, 2.0)
			_charge_to = _charge_from + _zone_dir * travel
			var lim := GameConfig.ARENA_RADIUS - 3.0
			var flat := Vector2(_charge_to.x, _charge_to.z)
			if flat.length() > lim:
				flat = flat.normalized() * lim
				_charge_to = Vector3(flat.x, 0.0, flat.y)

func _process_charging(delta: float) -> void:
	_state_timer -= delta
	var t := 1.0 - clampf(_state_timer / _charge_time, 0.0, 1.0)
	global_position = _charge_from.lerp(_charge_to, t * t)
	if not _charge_hit:
		var d := target.global_position - global_position
		d.y = 0.0
		if d.length() <= GameConfig.BOSS_RADIUS + 0.7:
			_charge_hit = true
			target.take_damage(_charge_dmg)
	if _state_timer <= 0.0:
		shake_requested.emit(0.4)
		var rec: float = GameConfig.CHARGE_DATA["recover"]
		_begin_recover(rec)

func _fire_volley(d: Dictionary) -> void:
	var counts: Array = d["count"]
	var n: int = counts[phase - 1]
	var spread: float = d["spread"]
	var speed: float = d["speed"]
	var dmg: float = d["dmg"]
	var to := target.global_position - global_position
	to.y = 0.0
	var base_yaw := atan2(-to.x, -to.z)
	for i in n:
		var f := 0.0
		if n > 1:
			f = float(i) / float(n - 1) - 0.5
		var yaw := base_yaw + f * spread
		var p := Projectile.new()
		p.target = target
		p.damage = dmg
		p.velocity = Vector3(-sin(yaw), 0.0, -cos(yaw)) * speed
		get_parent().add_child(p)
		p.global_position = global_position + Vector3(0.0, 1.3, 0.0) + p.velocity.normalized() * (GameConfig.BOSS_RADIUS + 0.5)

func _begin_recover(t: float) -> void:
	state = State.RECOVER
	_state_timer = t
	_cur_attack = -1
	_attack_cd = GameConfig.BOSS_ATTACK_CD[phase - 1]

# ------------------------------------------------------------------ zones
func _in_zone(p: Vector3, margin: float) -> bool:
	var rel := p - _zone_center
	rel.y = 0.0
	match _zone:
		Zone.ALL:
			return true
		Zone.CIRCLE:
			return rel.length() <= _zone_r + margin
		Zone.RECT:
			var f := rel.dot(_zone_dir)
			var side := rel.dot(Vector3(-_zone_dir.z, 0.0, _zone_dir.x))
			return f >= -margin and f <= _zone_len + margin and absf(side) <= _zone_w * 0.5 + margin
	return false

## True while a perfect-dodge (yellow) window is open and pos is in the danger zone.
func is_threatening(p: Vector3) -> bool:
	return perfect_window and _in_zone(p, 1.2)

# ------------------------------------------------------------------ helpers
func _face(pos: Vector3) -> void:
	var d := pos - global_position
	d.y = 0.0
	if d.length() > 0.01:
		_visual.rotation.y = atan2(-d.x, -d.z)

func _clamp_arena() -> void:
	var flat := Vector2(global_position.x, global_position.z)
	var lim := GameConfig.ARENA_RADIUS - 3.0
	if flat.length() > lim:
		flat = flat.normalized() * lim
		global_position = Vector3(flat.x, 0.0, flat.y)

func _update_pull(delta: float) -> void:
	if _pull_t <= 0.0 or state == State.CHARGING:
		return
	_pull_t -= delta
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
	return state != State.DEAD

func is_stunned() -> bool:
	return state == State.STUNNED

func daze_ratio() -> float:
	if state == State.STUNNED:
		return clampf(stun_t / GameConfig.STUN_TIME, 0.0, 1.0)
	return clampf(daze / GameConfig.DAZE_MAX, 0.0, 1.0)

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
	_flash_t = 1.0
	DamageNumber.spawn(get_parent(), global_position + Vector3(0.0, 4.5, 0.0), dmg, GameConfig.element_color(element), crit)
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
	if state != State.STUNNED and freeze_amt > 0.0 and frozen_t <= 0.0:
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
	sfx_requested.emit("slam")
	if state != State.STUNNED:
		_hide_indicators()
		_begin_recover(GameConfig.PHASE_ROAR_TIME)

func _enter_stun() -> void:
	state = State.STUNNED
	stun_t = GameConfig.STUN_TIME
	frozen_t = 0.0
	freeze_buildup = 0.0
	_ice_shell.visible = false
	_hide_indicators()
	_cur_attack = -1
	_core_mat.emission_energy_multiplier = 0.5
	create_tween().tween_property(_visual, "rotation:x", 0.28, 0.35)
	shake_requested.emit(0.6)
	sfx_requested.emit("stun")
	stunned.emit()

func _end_stun() -> void:
	daze = 0.0
	_core_mat.emission_energy_multiplier = 2.5
	create_tween().tween_property(_visual, "rotation:x", 0.0, 0.3)
	_begin_recover(GameConfig.BOSS_RECOVER_TIME)
	stun_ended.emit()

func _freeze() -> void:
	freeze_buildup = 0.0
	frozen_t = GameConfig.FREEZE_TIME
	_ice_shell.visible = true
	if state == State.TELEGRAPH or state == State.CHARGING:
		_hide_indicators()
		_begin_recover(0.5)
	Fx.burst(get_parent(), global_position + Vector3(0.0, 3.0, 0.0), GameConfig.Element.ICE, 24, 9.0)
	sfx_requested.emit("freeze")

func _die() -> void:
	state = State.DEAD
	_hide_indicators()
	_ice_shell.visible = false
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3(1.0, 0.05, 1.0), 0.8)
	defeated.emit()
