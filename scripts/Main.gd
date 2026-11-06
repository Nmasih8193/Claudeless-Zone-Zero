extends Node3D
## Builds the world, wires systems together, owns game flow, the input map, the camera rig,
## time effects (hit-stop / slow-mo) and scoring.

enum Phase { START, FIGHT, END }

var phase: Phase = Phase.START
var player: Player
var boss: Boss
var hud: HUD
var camera: CameraRig
var sfx: Sfx
var post: PostFx

var _alt_held: bool = false
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
	get_viewport().use_debanding = true
	_setup_input()
	add_child(Arena.new())

	camera = CameraRig.new()
	add_child(camera)
	camera.current = true

	player = Player.new()
	player.position = Vector3(0.0, 0.0, 9.0)
	player.locked = true                       # idles on the title screen until the fight starts
	boss = Boss.new()
	boss.position = Vector3(0.0, 0.0, -6.0)
	player.boss = boss
	boss.target = player
	add_child(player)
	add_child(boss)
	boss.face_instant(player.global_position)
	post = PostFx.new()
	add_child(post)
	hud = HUD.new()
	add_child(hud)
	hud.player = player
	sfx = Sfx.new()
	add_child(sfx)
	boss.sfx_requested.connect(func(n: String) -> void: sfx.play(n))
	player.sfx_requested.connect(func(n: String) -> void: sfx.play(n))
	sfx.play_music()

	boss.damage_taken.connect(_on_boss_damaged)
	boss.phase_changed.connect(_on_phase_changed)
	boss.stunned.connect(_on_boss_stunned)
	boss.shake_requested.connect(_add_shake)
	boss.defeated.connect(func() -> void: _end_fight("VICTORY"))
	boss.danger_warning.connect(_on_danger)
	boss.blasted.connect(_on_blasted)
	player.shake_requested.connect(_add_shake)
	player.time_fx_requested.connect(time_fx)
	player.time_fx_cancel.connect(_cancel_time_fx)
	player.perfect_dodged.connect(_on_perfect_dodge)
	player.points_awarded.connect(_on_points)
	player.damaged.connect(_on_player_damaged)
	player.ultimate_cast.connect(_on_ultimate)
	player.died.connect(func() -> void: _end_fight("DEFEAT"))
	player.chain_prompt.connect(_on_chain_prompt)
	player.assist_prompt.connect(func(t: String) -> void: hud.show_assist(t))
	player.cinematic_requested.connect(func(k: String, l: float) -> void: camera.cinematic(k, l))
	hud.overlay_changed.connect(func(_open: bool) -> void: _update_mouse())
	hud.action_requested.connect(_on_hud_action)

	player.update_lock_yaw()
	camera.setup(player, boss)
	hud.show_start()
	hud.sync(player, boss, time_left)
	_refresh_score()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ------------------------------------------------------------------ input map (ZZZ PC defaults + Xbox pad)
func _setup_input() -> void:
	var stick := 0.2
	_bind("move_left", [KEY_A], [], [[JOY_AXIS_LEFT_X, -1.0]], [], stick)
	_bind("move_right", [KEY_D], [], [[JOY_AXIS_LEFT_X, 1.0]], [], stick)
	_bind("move_forward", [KEY_W], [], [[JOY_AXIS_LEFT_Y, -1.0]], [], stick)
	_bind("move_back", [KEY_S], [], [[JOY_AXIS_LEFT_Y, 1.0]], [], stick)
	_bind("cam_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]], [], stick)
	_bind("cam_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]], [], stick)
	_bind("cam_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]], [], stick)
	_bind("cam_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]], [], stick)
	_bind("attack", [], [MOUSE_BUTTON_LEFT], [], [JOY_BUTTON_X])
	_bind("dodge", [KEY_SHIFT], [MOUSE_BUTTON_RIGHT], [], [JOY_BUTTON_A])
	_bind("special", [KEY_E], [], [], [JOY_BUTTON_Y])
	_bind("ultimate", [KEY_Q], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind("swap_next", [KEY_SPACE], [], [], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("swap_prev", [KEY_C], [], [], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("chain_left", [KEY_Q], [MOUSE_BUTTON_LEFT], [], [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_X])
	_bind("chain_right", [KEY_E], [MOUSE_BUTTON_RIGHT], [], [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_Y])
	_bind("lock_on", [], [MOUSE_BUTTON_MIDDLE], [], [JOY_BUTTON_RIGHT_STICK])
	_bind("summon_mouse", [KEY_ALT])
	_bind("interact", [KEY_F, KEY_ENTER, KEY_KP_ENTER], [], [], [JOY_BUTTON_A])
	_bind("restart", [KEY_R])
	_bind("pause", [KEY_ESCAPE], [], [], [JOY_BUTTON_START])
	_bind("handbook", [KEY_G], [], [], [JOY_BUTTON_BACK])
	_bind("interknot", [KEY_J], [], [], [JOY_BUTTON_DPAD_LEFT])
	_bind("squad", [KEY_T])
	_bind("wheel", [KEY_TAB], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])

func _bind(action: String, keys: Array = [], mouse: Array = [], axes: Array = [], buttons: Array = [], deadzone: float = 0.5) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
	for k: int in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k as Key
		InputMap.action_add_event(action, ev)
	for m: int in mouse:
		var mb := InputEventMouseButton.new()
		mb.button_index = m as MouseButton
		InputMap.action_add_event(action, mb)
	for a: Array in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = int(a[0]) as JoyAxis
		jm.axis_value = float(a[1])
		InputMap.action_add_event(action, jm)
	for b: int in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b as JoyButton
		InputMap.action_add_event(action, jb)

## Mouse is captured for camera control during the fight; ALT (held) or any menu shows it.
func _update_mouse() -> void:
	var fighting := phase == Phase.FIGHT
	if hud.overlay == "wheel":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.input_enabled = false
		return
	var show_cursor := hud.overlay != "" or _alt_held or not fighting
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show_cursor else Input.MOUSE_MODE_CAPTURED
	camera.input_enabled = fighting and hud.overlay == ""

# ------------------------------------------------------------------ camera / fx
func _add_shake(strength: float) -> void:
	camera.add_trauma(clampf(strength * 1.4, 0.0, 1.0))

## Slow-mo / hit-stop in REAL time. A stronger (lower) scale is never overridden by a weaker one.
func time_fx(time_scale: float, duration: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _fx_until_ms and time_scale > _fx_scale:
		return
	_fx_scale = time_scale
	_fx_until_ms = now + int(duration * 1000.0)
	Engine.time_scale = time_scale

func _cancel_time_fx() -> void:
	Engine.time_scale = 1.0
	_fx_scale = 1.0
	_fx_until_ms = 0

# ------------------------------------------------------------------ flow
func _unhandled_input(event: InputEvent) -> void:
	if camera.handle_input(event):
		return
	match phase:
		Phase.START:
			if event.is_action_pressed("interact"):
				_start_fight()
		Phase.END:
			if event.is_action_pressed("restart") or event.is_action_pressed("interact"):
				_restart()
		Phase.FIGHT:
			if event.is_action_pressed("lock_on"):
				camera.toggle_lock()
				hud.set_lock(camera.locked)
				sfx.play("swap", -6.0)
			elif event.is_action_pressed("summon_mouse"):
				_alt_held = true
				_update_mouse()
			elif event.is_action_released("summon_mouse"):
				_alt_held = false
				_update_mouse()
			elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _alt_held:
				_update_mouse()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_alt_held = false

func _start_fight() -> void:
	phase = Phase.FIGHT
	player.locked = false
	boss.active = true
	hud.clear_message()
	hud.can_pause = true
	hud.show_banner("FIGHT!")
	sfx.play("start")
	camera.in_fight = true
	camera.recenter()
	_update_mouse()

func _restart() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()

func _process(delta: float) -> void:
	if Engine.time_scale != 1.0 and Time.get_ticks_msec() >= _fx_until_ms:
		_cancel_time_fx()
	var real := delta / maxf(Engine.time_scale, 0.01)
	player.view_yaw = camera.yaw
	camera.update(minf(real, 0.05))
	var c := player.chars[player.active]
	post.low_hp = clampf((0.3 - c.hp / c.max_hp) / 0.3, 0.0, 1.0) if phase == Phase.FIGHT else 0.0
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

func _on_phase_changed(p: int) -> void:
	hud.show_banner("PHASE %d" % p)
	post.danger()

func _on_danger(text: String) -> void:
	hud.show_danger(text)
	post.danger()

func _on_blasted() -> void:
	hud.flash(Color(1.0, 0.8, 0.95), 0.85)
	post.ult(0.6)

func _on_hud_action(action: String) -> void:
	if action == "retry":
		_restart()

func _on_boss_stunned() -> void:
	hud.show_banner("STUNNED!")
	player.open_chain_prompt(true)

func _on_chain_prompt(left: int, right: int) -> void:
	hud.show_chain(left, right)
	post.set_chain(left >= 0 or right >= 0)

func _on_perfect_dodge() -> void:
	perfect_dodges += 1
	hud.show_banner("PERFECT DODGE!")
	post.perfect(GameConfig.PERFECT_DURATION)
	camera.kick_fov(-6.0)

func _on_points(pts: int, label: String) -> void:
	bonus_points += float(pts)
	if label.ends_with("Assist"):
		assists += 1
	elif label == "Chain Attack":
		chains += 1
		post.ult(0.4)
	if label == "Defensive Assist":
		hud.show_banner("DEFENSIVE ASSIST!")
		post.hit()
	hud.show_points(pts, label)
	_refresh_score()

func _on_player_damaged(amount: float) -> void:
	damage_taken += amount
	combo = 0
	post.hit()
	hud.flash(Color(1.0, 0.15, 0.1), 0.25)
	_refresh_score()

func _on_ultimate(color: Color) -> void:
	ults += 1
	hud.flash(color)
	post.ult(0.7)
	camera.kick_fov(8.0)

func _end_fight(outcome: String) -> void:
	if phase == Phase.END:
		return
	phase = Phase.END
	hud.can_pause = false
	_cancel_time_fx()
	player.locked = true
	var victory := outcome == "VICTORY"
	boss.active = false
	get_tree().call_group("projectiles", "queue_free")
	get_tree().call_group("hazards", "cancel")
	camera.in_fight = false
	camera.locked = false
	hud.set_lock(false)
	hud.show_chain(-1, -1)
	hud.show_assist("")
	post.set_chain(false)
	_update_mouse()
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
