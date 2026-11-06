class_name CameraRig
extends Camera3D
## ZZZ-style third-person orbit camera.
##  - Mouse (captured) / right stick orbits around the character; wheel zooms.
##  - Middle mouse / R3 toggles a soft lock-on that keeps the boss framed behind the character.
##  - Without lock-on it still helps: after ~1.5s of no camera input it eases toward the boss
##    when the boss drifts far off-screen (GameConfig.CAM_AUTO_FRAME).
##  - Avoids the floor, pulls in when the boss blocks the view, widens FOV while sprinting,
##    smooth trauma shake, and cinematic angles for Ultimates / Chain Attacks.
## Driven by Main with REAL (unscaled) delta, so it stays smooth during slow-mo.

var player: Player
var boss: Boss
var yaw: float = 0.0
var pitch: float = GameConfig.CAM_PITCH_DEFAULT
var zoom: float = GameConfig.CAM_DIST
var locked: bool = false
var input_enabled: bool = false
var in_fight: bool = false

var _pivot: Vector3 = Vector3.ZERO
var _dist: float = GameConfig.CAM_DIST
var _occl: float = 99.0
var _idle: float = 0.0
var _recenter: bool = false
var _trauma: float = 0.0
var _noise_t: float = 0.0
var _fov_kick: float = 0.0
var _sprint_fov: float = 0.0
var _cine_kind: String = ""
var _cine_t: float = 0.0
var _cine_len: float = 1.0
var _cine_side: float = 1.0
var _cine_yaw0: float = 0.0

func setup(p: Player, b: Boss) -> void:
	player = p
	boss = b
	fov = GameConfig.CAM_FOV
	near = 0.1
	far = 400.0
	yaw = _boss_yaw()
	snap()

## Jump straight to the resting position (no smoothing).
func snap() -> void:
	_pivot = player.global_position + Vector3(0.0, GameConfig.CAM_HEIGHT, 0.0)
	_dist = zoom
	_apply(yaw, pitch, _dist, _pivot, 0.0)

# ------------------------------------------------------------------ input
func handle_input(event: InputEvent) -> bool:
	if not input_enabled:
		return false
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var inv := -1.0 if GameConfig.CAM_INVERT_Y else 1.0
		yaw -= mm.relative.x * GameConfig.MOUSE_SENS
		pitch = clampf(pitch - mm.relative.y * GameConfig.MOUSE_SENS * inv, GameConfig.CAM_PITCH_MIN, GameConfig.CAM_PITCH_MAX)
		_idle = 0.0
		_recenter = false
		return true
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(zoom - 0.6, GameConfig.CAM_DIST_MIN)
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(zoom + 0.6, GameConfig.CAM_DIST_MAX)
			return true
	return false

func toggle_lock() -> void:
	locked = not locked

## Smoothly swing behind the character, facing the boss.
func recenter() -> void:
	_recenter = true

func add_trauma(amount: float) -> void:
	_trauma = clampf(maxf(_trauma, amount), 0.0, 1.0)

func kick_fov(amount: float) -> void:
	_fov_kick += amount

## kind: "ult" (orbit around the character) or "chain" (wide side shot of both fighters).
func cinematic(kind: String, length: float) -> void:
	_cine_kind = kind
	_cine_len = maxf(length, 0.3)
	_cine_t = _cine_len
	_cine_yaw0 = yaw
	_cine_side = -1.0 if randf() < 0.5 else 1.0

# ------------------------------------------------------------------ update
func _boss_yaw() -> float:
	var d := boss.global_position - player.global_position
	d.y = 0.0
	if d.length() < 0.1:
		return yaw
	return atan2(-d.x, -d.z)

func update(dt: float) -> void:
	if player == null or boss == null:
		return
	dt = clampf(dt, 0.0, 0.05)
	_noise_t += dt
	_idle += dt
	if input_enabled:
		var look := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
		if look.length() > 0.05:
			var inv := -1.0 if GameConfig.CAM_INVERT_Y else 1.0
			yaw -= look.x * GameConfig.PAD_SENS * dt
			pitch = clampf(pitch - look.y * GameConfig.PAD_SENS * 0.6 * dt * inv, GameConfig.CAM_PITCH_MIN, GameConfig.CAM_PITCH_MAX)
			_idle = 0.0
			_recenter = false

	var to_boss := boss.global_position - player.global_position
	to_boss.y = 0.0
	var boss_dist := to_boss.length()
	var boss_yaw := _boss_yaw()
	var boss_alive := boss.state != Boss.State.DEAD
	if not in_fight:
		yaw += 0.1 * dt                         # slow attract-mode orbit on the title / results
	elif locked and boss_alive:
		yaw = lerp_angle(yaw, boss_yaw, 1.0 - exp(-GameConfig.CAM_LOCK_SHARPNESS * dt))
		var want_pitch := -0.16 - clampf((boss.global_position.y) * 0.03, 0.0, 0.25)
		if _idle > 0.6:
			pitch = lerpf(pitch, want_pitch, 1.0 - exp(-2.0 * dt))
	elif _recenter:
		yaw = lerp_angle(yaw, boss_yaw, 1.0 - exp(-5.0 * dt))
		pitch = lerpf(pitch, GameConfig.CAM_PITCH_DEFAULT, 1.0 - exp(-5.0 * dt))
		if absf(wrapf(boss_yaw - yaw, -PI, PI)) < 0.02:
			_recenter = false
	elif GameConfig.CAM_AUTO_FRAME and boss_alive and _idle > 1.5 and boss_dist > 1.0:
		var diff := wrapf(boss_yaw - yaw, -PI, PI)
		var ad := absf(diff)
		if ad > 0.75:
			yaw += diff * (1.0 - exp(-0.9 * dt)) * smoothstep(0.75, 1.5, ad)

	# pivot follow (horizontal tight, vertical softer so hops don't bob the view)
	var tp := player.global_position + Vector3(0.0, GameConfig.CAM_HEIGHT, 0.0)
	var kf := 1.0 - exp(-GameConfig.CAM_FOLLOW * dt)
	_pivot.x = lerpf(_pivot.x, tp.x, kf)
	_pivot.z = lerpf(_pivot.z, tp.z, kf)
	_pivot.y = lerpf(_pivot.y, tp.y, 1.0 - exp(-5.0 * dt))

	# the boss is huge: back off a little when close so it fits on screen
	var near_boss := 1.0 + 0.18 * (1.0 - smoothstep(5.0, 11.0, boss_dist)) if boss_alive else 1.0
	_dist = lerpf(_dist, zoom * near_boss, 1.0 - exp(-6.0 * dt))

	# cinematic blend
	var y := yaw
	var p := pitch
	var d := _dist
	var pv := _pivot
	var fov_cine := 0.0
	if _cine_t > 0.0:
		_cine_t -= dt
		var k := clampf(1.0 - _cine_t / _cine_len, 0.0, 1.0)
		var w := smoothstep(0.0, 0.15, k) * (1.0 - smoothstep(0.82, 1.0, k))
		var cy := yaw
		var cp := pitch
		var cd := d
		var cpv := pv
		match _cine_kind:
			"ult":
				cy = _cine_yaw0 + _cine_side * (0.9 + k * 1.1)
				cp = -0.02 - 0.12 * k
				cd = 4.0 + k * 2.0
				cpv = player.global_position + Vector3(0.0, 1.25, 0.0)
				fov_cine = -6.0 * (1.0 - k)
			"chain":
				cy = boss_yaw + _cine_side * (1.3 + k * 0.25)
				cp = -0.14
				cd = 10.5
				cpv = player.global_position.lerp(boss.global_position, 0.45) + Vector3(0.0, 2.2, 0.0)
				fov_cine = 4.0
		y = lerp_angle(yaw, cy, w)
		p = lerpf(pitch, cp, w)
		d = lerpf(d, cd, w)
		pv = pv.lerp(cpv, w)
		fov_cine *= w

	# collision: keep above the floor, pull in when the boss blocks the line of sight
	var rot := Basis.from_euler(Vector3(p, y, 0.0))
	var back := rot * Vector3(0.0, 0.0, 1.0)
	if back.y < -0.01:
		var floor_d := (0.4 - pv.y) / back.y
		if floor_d > 0.0:
			d = minf(d, floor_d)
	# arena wall: near the edge, tilt to look down over the barriers before pulling in
	var reach := _wall_reach(pv, back)
	if reach < d:
		var k := clampf(1.0 - reach / d, 0.0, 1.0)
		p = lerpf(p, minf(p, -0.95), k)
		rot = Basis.from_euler(Vector3(p, y, 0.0))
		back = rot * Vector3(0.0, 0.0, 1.0)
		if back.y < -0.01:
			d = minf(d, maxf((0.4 - pv.y) / back.y, 0.5))
		d = minf(d, maxf(_wall_reach(pv, back), 2.2))
	var block := d
	if boss_alive and _cine_t <= 0.0:
		var bp := boss.global_position
		for i in range(2, 17):
			var s := d * float(i) / 16.0
			var q := pv + back * s
			var rel := Vector2(q.x - bp.x, q.z - bp.z)
			if rel.length() < GameConfig.BOSS_RADIUS * 0.95 and q.y > bp.y - 0.5 and q.y < bp.y + 7.8:
				block = maxf(s - 0.6, 1.4)
				break
	_occl = lerpf(_occl, block, 1.0 - exp(-(22.0 if block < _occl else 3.0) * dt))
	d = minf(d, _occl)

	# shake (smooth trauma noise) + fov
	_trauma = maxf(_trauma - 1.5 * dt, 0.0)
	var amt := pow(_trauma, 1.5)
	var nx := sin(_noise_t * 31.0) + sin(_noise_t * 17.3 + 1.7) * 0.6
	var ny := sin(_noise_t * 27.0 + 4.1) + sin(_noise_t * 13.1 + 0.3) * 0.6
	var nr := sin(_noise_t * 21.0 + 2.2)
	h_offset = nx * amt * 0.35
	v_offset = ny * amt * 0.35
	var sprinting := player.sprinting and in_fight
	_sprint_fov = lerpf(_sprint_fov, GameConfig.CAM_SPRINT_FOV if sprinting else 0.0, 1.0 - exp(-4.0 * dt))
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-5.0 * dt))
	fov = GameConfig.CAM_FOV + _sprint_fov + _fov_kick + fov_cine
	_apply(y, p, d, pv, nr * amt * 0.045)

## How far the camera can back away from pv along `back` before leaving the barrier ring.
func _wall_reach(pv: Vector3, back: Vector3) -> float:
	var wall_r := GameConfig.ARENA_RADIUS + 6.6        # inside the barrier ring (Arena.gd)
	var pxz := Vector2(pv.x, pv.z)
	var bxz := Vector2(back.x, back.z)
	var qa := bxz.length_squared()
	var qc := pxz.length_squared() - wall_r * wall_r
	if qa < 0.0001 or qc >= 0.0:
		return 999.0
	var qb := 2.0 * pxz.dot(bxz)
	return (-qb + sqrt(qb * qb - 4.0 * qa * qc)) / (2.0 * qa)

func _apply(y: float, p: float, d: float, pv: Vector3, roll: float) -> void:
	var b := Basis.from_euler(Vector3(p, y, roll))
	global_transform = Transform3D(b, pv + b * Vector3(0.0, 0.0, d))
