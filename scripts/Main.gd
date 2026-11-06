extends Node3D
## Builds the world in code, wires systems together, owns game flow, camera, shake and time effects.

enum Phase { START, FIGHT, END }

var phase: Phase = Phase.START
var player: Player
var boss: Boss
var hud: HUD
var camera: Camera3D
var sfx: Sfx

var _cam_yaw: float = 0.0
var _shake: float = 0.0
var _fx_until_ms: int = 0
var _fx_scale: float = 1.0

var time_left: float = GameConfig.FIGHT_TIME
var damage_dealt: float = 0.0
var damage_taken: float = 0.0
var dmg_score: float = 0.0
var bonus_points: float = 0.0
var combo: int = 0
var max_combo: int = 0
var combo_timer: float = 0.0
var perfect_dodges: int = 0
var assists: int = 0
var chains: int = 0
var ults: int = 0

func _ready() -> void:
	process_priority = 10          # run after Player/Boss so the camera sees final positions
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_setup_input()
	_build_environment()
	_build_arena()

	camera = Camera3D.new()
	camera.fov = GameConfig.CAM_FOV
	add_child(camera)
	camera.current = true

	player = Player.new()
	player.position = Vector3(0.0, 0.0, 9.0)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	boss = Boss.new()
	boss.position = Vector3(0.0, 0.0, -6.0)
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	player.boss = boss
	boss.target = player
	add_child(player)
	add_child(boss)
	hud = HUD.new()
	add_child(hud)
	sfx = Sfx.new()
	add_child(sfx)
	boss.sfx_requested.connect(func(n: String) -> void: sfx.play(n))
	player.sfx_requested.connect(func(n: String) -> void: sfx.play(n))
	sfx.play_music()

	boss.damage_taken.connect(_on_boss_damaged)
	boss.phase_changed.connect(func(p: int) -> void: hud.show_banner("PHASE %d" % p))
	boss.stunned.connect(_on_boss_stunned)
	boss.stun_ended.connect(func() -> void: player.chain_ready = false)
	boss.shake_requested.connect(_add_shake)
	boss.defeated.connect(func() -> void: _end_fight("VICTORY"))
	player.shake_requested.connect(_add_shake)
	player.time_fx_requested.connect(time_fx)
	player.perfect_dodged.connect(_on_perfect_dodge)
	player.points_awarded.connect(_on_points)
	player.damaged.connect(_on_player_damaged)
	player.ultimate_cast.connect(_on_ultimate)
	player.died.connect(func() -> void: _end_fight("DEFEAT"))

	player.update_lock_yaw()
	_cam_yaw = player.lock_yaw
	_update_camera(1.0)
	hud.show_start()
	_refresh_score()

# ------------------------------------------------------------------ input map
func _setup_input() -> void:
	_key("move_left", [KEY_A])
	_key("move_right", [KEY_D])
	_key("move_forward", [KEY_W])
	_key("move_back", [KEY_S])
	_key("attack", [KEY_J], true)
	_key("dodge", [KEY_K, KEY_SHIFT])
	_key("ex", [KEY_L])
	_key("ultimate", [KEY_SPACE])
	_key("chain", [KEY_F])
	_key("swap_1", [KEY_1])
	_key("swap_2", [KEY_2])
	_key("swap_3", [KEY_3])
	_key("swap_prev", [KEY_Q])
	_key("swap_next", [KEY_E])
	_key("pause", [KEY_ESCAPE])
	_key("start", [KEY_ENTER, KEY_KP_ENTER])
	_key("restart", [KEY_R])

func _key(action: String, keys: Array, with_mouse: bool = false) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k: int in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k as Key
		InputMap.action_add_event(action, ev)
	if with_mouse:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(action, m)

# ------------------------------------------------------------------ world
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.72, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.78, 0.9)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.64, 0.74, 0.84)
	env.fog_density = 0.012
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)

func _scene_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _build_arena() -> void:
	var floor_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = GameConfig.ARENA_RADIUS + 4.0
	cyl.bottom_radius = GameConfig.ARENA_RADIUS + 4.0
	cyl.height = 0.4
	cyl.radial_segments = 64
	cyl.rings = 1
	floor_mesh.mesh = cyl
	floor_mesh.material_override = _scene_mat(Color(0.42, 0.47, 0.52))
	floor_mesh.position.y = -0.2
	add_child(floor_mesh)

	var ground := MeshInstance3D.new()
	var big := CylinderMesh.new()
	big.top_radius = 90.0
	big.bottom_radius = 90.0
	big.height = 0.2
	big.radial_segments = 32
	big.rings = 1
	ground.mesh = big
	ground.material_override = _scene_mat(Color(0.3, 0.34, 0.4))
	ground.position.y = -0.6
	add_child(ground)

	var edge := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = GameConfig.ARENA_RADIUS + 0.8
	tor.outer_radius = GameConfig.ARENA_RADIUS + 1.2
	edge.mesh = tor
	edge.material_override = Fx.glow_mat(Color(0.3, 0.85, 1.0), 2.0)
	add_child(edge)
	for r: float in [8.0, 15.0]:
		var g := MeshInstance3D.new()
		var t2 := TorusMesh.new()
		t2.inner_radius = r - 0.05
		t2.outer_radius = r + 0.05
		g.mesh = t2
		g.material_override = _scene_mat(Color(0.3, 0.34, 0.4))
		g.position.y = 0.02
		add_child(g)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var mats: Array = [_scene_mat(Color(0.35, 0.4, 0.45)), _scene_mat(Color(0.5, 0.36, 0.3)), _scene_mat(Color(0.28, 0.33, 0.38))]
	for i in 28:
		var ang := TAU * float(i) / 28.0 + rng.randf_range(-0.1, 0.1)
		var rad := rng.randf_range(40.0, 54.0)
		var size := Vector3(rng.randf_range(2.0, 6.0), rng.randf_range(4.0, 18.0), rng.randf_range(2.0, 6.0))
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = size
		m.mesh = b
		m.material_override = mats[i % mats.size()]
		m.position = Vector3(cos(ang) * rad, size.y * 0.5 - 0.3, sin(ang) * rad)
		m.rotation = Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(0.0, TAU), rng.randf_range(-0.08, 0.08))
		add_child(m)
	for i in 6:
		var ang := TAU * float(i) / 6.0 + 0.3
		var sign_mesh := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(7.0, 1.4, 0.3)
		sign_mesh.mesh = sb
		sign_mesh.material_override = Fx.glow_mat(Color(1.0, 0.35, 0.75) if i % 2 == 0 else Color(0.3, 0.9, 1.0), 2.5)
		add_child(sign_mesh)
		var pos := Vector3(cos(ang) * 36.0, 9.0 + float(i % 3) * 2.5, sin(ang) * 36.0)
		sign_mesh.look_at_from_position(pos, Vector3(0.0, pos.y, 0.0), Vector3.UP)

# ------------------------------------------------------------------ camera / fx
func _update_camera(delta: float) -> void:
	_cam_yaw = lerp_angle(_cam_yaw, player.lock_yaw, 1.0 - exp(-5.0 * delta))
	player.view_yaw = _cam_yaw
	var back := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw))
	var p := player.global_position
	var desired := p + back * GameConfig.CAM_DIST + Vector3(0.0, GameConfig.CAM_HEIGHT, 0.0)
	camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-9.0 * delta))
	var focus := p.lerp(boss.global_position, 0.3) + Vector3(0.0, 2.2, 0.0)
	if camera.global_position.distance_to(focus) > 0.5:
		camera.look_at(focus, Vector3.UP)

func _add_shake(strength: float) -> void:
	_shake = maxf(_shake, strength)

## Slow-mo / hit-stop in REAL time. A stronger (lower) scale is never overridden by a weaker one.
func time_fx(time_scale: float, duration: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _fx_until_ms and time_scale > _fx_scale:
		return
	_fx_scale = time_scale
	_fx_until_ms = now + int(duration * 1000.0)
	Engine.time_scale = time_scale

# ------------------------------------------------------------------ flow
func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.START and event.is_action_pressed("start"):
		_start_fight()
	elif phase == Phase.END and event.is_action_pressed("restart"):
		Engine.time_scale = 1.0
		get_tree().paused = false
		get_tree().reload_current_scene()

func _start_fight() -> void:
	phase = Phase.FIGHT
	player.process_mode = Node.PROCESS_MODE_INHERIT
	boss.process_mode = Node.PROCESS_MODE_INHERIT
	hud.clear_message()
	hud.can_pause = true
	hud.show_banner("FIGHT!")
	sfx.play("start")

func _process(delta: float) -> void:
	if Engine.time_scale != 1.0 and Time.get_ticks_msec() >= _fx_until_ms:
		Engine.time_scale = 1.0
		_fx_scale = 1.0
	var real := delta / maxf(Engine.time_scale, 0.01)
	if _shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * _shake
		camera.v_offset = randf_range(-1.0, 1.0) * _shake
		_shake = maxf(_shake - 2.2 * real, 0.0)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	_update_camera(minf(real, 0.05))
	if Engine.get_process_frames() % 3 == 0:
		hud.sync(player, boss, time_left)
	if phase != Phase.FIGHT:
		return
	time_left = maxf(time_left - delta, 0.0)
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
			hud.set_combo(0)
			_refresh_score()
	if time_left <= 0.0:
		_end_fight("TIME UP")

# ------------------------------------------------------------------ score
func _combo_mult() -> float:
	return minf(1.0 + 0.1 * floorf(float(combo) / 4.0), GameConfig.MULT_MAX)

func _score() -> float:
	return maxf(dmg_score + bonus_points - damage_taken * GameConfig.SCORE_DAMAGE_TAKEN_PENALTY, 0.0)

func _grade_for(score: float) -> String:
	var g := "C"
	for t: Array in GameConfig.GRADE_THRESHOLDS:
		if score >= float(t[1]):
			g = t[0]
	return g

func _next_threshold(score: float) -> float:
	for t: Array in GameConfig.GRADE_THRESHOLDS:
		if score < float(t[1]):
			return float(t[1])
	var last: Array = GameConfig.GRADE_THRESHOLDS[GameConfig.GRADE_THRESHOLDS.size() - 1]
	return float(last[1])

func _refresh_score() -> void:
	var s := _score()
	hud.set_score(s, _combo_mult(), _grade_for(s), _next_threshold(s))
	hud.set_combo(combo)

# ------------------------------------------------------------------ event handlers
func _on_boss_damaged(amount: float) -> void:
	damage_dealt += amount
	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_timer = GameConfig.COMBO_TIMEOUT
	dmg_score += amount * GameConfig.SCORE_PER_DAMAGE * _combo_mult()
	_refresh_score()

func _on_boss_stunned() -> void:
	player.chain_ready = true
	hud.show_banner("STUNNED!")

func _on_perfect_dodge() -> void:
	perfect_dodges += 1
	hud.show_banner("PERFECT DODGE!")

func _on_points(pts: int, label: String) -> void:
	bonus_points += float(pts)
	if label == "Assist Attack":
		assists += 1
	elif label == "Chain Attack":
		chains += 1
	hud.show_points(pts, label)
	_refresh_score()

func _on_player_damaged(amount: float) -> void:
	damage_taken += amount
	combo = 0
	_refresh_score()

func _on_ultimate(color: Color) -> void:
	ults += 1
	hud.flash(color)

func _end_fight(outcome: String) -> void:
	if phase == Phase.END:
		return
	phase = Phase.END
	hud.can_pause = false
	Engine.time_scale = 1.0
	_fx_until_ms = 0
	player.locked = true
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().call_group("projectiles", "queue_free")
	var victory := outcome == "VICTORY"
	if victory:
		bonus_points += time_left * GameConfig.SCORE_PER_SEC_LEFT
	var s := _score()
	hud.set_score(s, _combo_mult(), _grade_for(s), _next_threshold(s))
	hud.sync(player, boss, time_left)
	sfx.play("win" if victory else "lose")
	hud.show_results(outcome, _grade_for(s), {
		"score": s, "damage": damage_dealt, "taken": damage_taken, "time_left": time_left,
		"max_combo": max_combo, "perfect_dodges": perfect_dodges,
		"assists": assists, "chains": chains, "ults": ults,
	})
