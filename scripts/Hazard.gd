class_name Hazard
extends Node3D
## A telegraphed boss hit. A glowing ground zone fills up toward the moment of impact, turns
## GOLD (parryable: Defensive Assist works) or flashing RED (must dodge) for the last
## PERFECT_WINDOW seconds, then damages the player if they are inside and not invulnerable.
## RING hazards are moving shockwaves instead: they expand from the origin and hit once.

signal resolved(hit: bool)

enum Shape { CIRCLE, RECT, SECTOR, ALL, RING }

const RED := Color(1.0, 0.13, 0.1)
const GOLD := Color(1.0, 0.8, 0.12)
const HOT_RED := Color(1.0, 0.02, 0.12)

static var _next_id: int = 1000

var shape: int = Shape.CIRCLE
var origin: Vector3 = Vector3.ZERO      # centre (circle) or start point (rect / sector / ring)
var radius: float = 3.0
var length: float = 10.0
var width: float = 4.0
var half_angle: float = 1.0
var dir: Vector3 = Vector3.FORWARD
var tele: float = 1.0
var damage: float = 100.0
var parryable: bool = true
var target: Player
var follow: Node3D = null               # the zone hunts this node...
var lock_time: float = 0.4              # ...until this many seconds before impact
var fx_kind: String = ""                # "slam", "spikes", "blast", "land" or "" (silent)
var ring_speed: float = 11.0
var ring_width: float = 1.1
var ring_color: Color = Color(1.0, 0.35, 0.65)

var threat_id: int = 0
var _t_left: float = 0.0
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _wall: MeshInstance3D
var _wall_mat: ShaderMaterial
var _floor_mat: ShaderMaterial
var _ring_r: float = 0.0
var _ring_hit: bool = false
var _done: bool = false

static func new_id() -> int:
	_next_id += 1
	return _next_id

func _ready() -> void:
	add_to_group("hazards")
	threat_id = Hazard.new_id()
	_t_left = tele
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	origin.y = 0.0
	if shape == Shape.RING:
		_build_ring()
	else:
		_build_zone()
	_place()

# ------------------------------------------------------------------ visuals
func _build_zone() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = Fx.plane2()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := 0
	match shape:
		Shape.RECT:
			sh = 1
		Shape.SECTOR:
			sh = 2
	_mat = Fx.shader_mat(Shaders.telegraph(), {"color": RED, "progress": 0.0, "shape": sh, "half_angle": half_angle, "intensity": 0.0})
	_mesh.material_override = _mat
	_mesh.top_level = true
	add_child(_mesh)
	var tw := create_tween()
	tw.tween_property(_mat, "shader_parameter/intensity", 1.0, 0.12)

func _build_ring() -> void:
	_wall = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.4
	cyl.radial_segments = 64
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_wall.mesh = cyl
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall_mat = Fx.shader_mat(Shaders.energy_wall(), {"color": ring_color, "fade": 1.0, "height": 1.4})
	_wall.material_override = _wall_mat
	_wall.top_level = true
	add_child(_wall)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = Fx.plane2()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor_mat = Fx.shader_mat(Shaders.ring(), {"color": ring_color, "thickness": 0.08, "fade": 1.0})
	_mesh.material_override = _floor_mat
	_mesh.top_level = true
	add_child(_mesh)
	_ring_r = 1.5

func _place() -> void:
	var yaw := atan2(-dir.x, -dir.z)
	match shape:
		Shape.CIRCLE:
			_mesh.global_position = origin + Vector3(0.0, 0.05, 0.0)
			_mesh.scale = Vector3(radius, 1.0, radius)
		Shape.ALL:
			_mesh.global_position = Vector3(0.0, 0.05, 0.0)
			_mesh.scale = Vector3.ONE * (GameConfig.ARENA_RADIUS + 2.0)
		Shape.RECT:
			_mesh.global_position = origin + dir * length * 0.5 + Vector3(0.0, 0.05, 0.0)
			_mesh.rotation = Vector3(0.0, yaw, 0.0)
			_mesh.scale = Vector3(width * 0.5, 1.0, length * 0.5)
		Shape.SECTOR:
			_mesh.global_position = origin + Vector3(0.0, 0.05, 0.0)
			_mesh.rotation = Vector3(0.0, yaw, 0.0)
			_mesh.scale = Vector3(radius, 1.0, radius)
		Shape.RING:
			var s := maxf(_ring_r, 0.1)
			_wall.global_position = origin + Vector3(0.0, 0.7, 0.0)
			_wall.scale = Vector3(s, 1.0, s)
			_mesh.global_position = origin + Vector3(0.0, 0.06, 0.0)
			_mesh.scale = Vector3(s + ring_width * 0.5, 1.0, s + ring_width * 0.5)

# ------------------------------------------------------------------ simulation
func _process(delta: float) -> void:
	if _done:
		return
	delta = minf(delta, 0.05)
	if shape == Shape.RING:
		_process_ring(delta)
		return
	_t_left -= delta
	if follow != null and is_instance_valid(follow) and _t_left > lock_time:
		var fp := follow.global_position
		origin = origin.lerp(Vector3(fp.x, 0.0, fp.z), 1.0 - exp(-7.0 * delta))
		_place()
	_mat.set_shader_parameter("progress", 1.0 - clampf(_t_left / tele, 0.0, 1.0))
	if is_flashing():
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.04)
		_mat.set_shader_parameter("color", GOLD if parryable else HOT_RED.lerp(Color(1.0, 0.6, 0.6), pulse * 0.4))
	if _t_left <= 0.0:
		_resolve()

func _process_ring(delta: float) -> void:
	_ring_r += ring_speed * delta
	_place()
	var fade := clampf((GameConfig.ARENA_RADIUS + 5.0 - _ring_r) / 4.0, 0.0, 1.0)
	_wall_mat.set_shader_parameter("fade", fade)
	_floor_mat.set_shader_parameter("fade", fade)
	if not _ring_hit and target != null and contains(target.global_position, 0.0):
		_ring_hit = true
		target.take_damage(damage)
	if _ring_r > GameConfig.ARENA_RADIUS + 5.0:
		_done = true
		queue_free()

func is_flashing() -> bool:
	return not _done and shape != Shape.RING and _t_left <= GameConfig.PERFECT_WINDOW

func time_left() -> float:
	return _t_left

func contains(p: Vector3, margin: float) -> bool:
	var rel := p - origin
	rel.y = 0.0
	match shape:
		Shape.ALL:
			return true
		Shape.CIRCLE:
			return rel.length() <= radius + margin
		Shape.RECT:
			var f := rel.dot(dir)
			var side := rel.dot(Vector3(-dir.z, 0.0, dir.x))
			return f >= -margin and f <= length + margin and absf(side) <= width * 0.5 + margin
		Shape.SECTOR:
			var d := rel.length()
			if d > radius + margin:
				return false
			if d < 1.0:
				return true
			var ang := acos(clampf(rel.normalized().dot(dir), -1.0, 1.0))
			return ang <= half_angle + margin / d
		Shape.RING:
			return absf(rel.length() - _ring_r) <= ring_width * 0.5 + margin
	return false

## Non-zero while this hit is about to land on p (the perfect-dodge / parry window).
func threat(p: Vector3) -> int:
	if _done or damage <= 0.0:
		return 0
	if shape == Shape.RING:
		if _ring_hit:
			return 0
		var rel := p - origin
		rel.y = 0.0
		var ahead := rel.length() - _ring_r
		if ahead >= -ring_width * 0.5 and ahead <= ring_speed * GameConfig.PERFECT_WINDOW + 0.6:
			return threat_id
		return 0
	if is_flashing() and contains(p, 1.2):
		return threat_id
	return 0

func _resolve() -> void:
	_done = true
	var hit := false
	if damage > 0.0 and target != null and contains(target.global_position, 0.0):
		hit = not target.is_invulnerable()
		target.take_damage(damage)
	_spawn_fx()
	resolved.emit(hit)
	_fade_out(0.12)

## Removes the hazard without it landing (boss stunned / frozen / killed mid-attack).
func cancel() -> void:
	if _done:
		return
	_done = true
	_fade_out(0.15)

func _fade_out(t: float) -> void:
	var tw := create_tween()
	if _mat != null:
		tw.tween_property(_mat, "shader_parameter/intensity", 0.0, t)
	if _wall_mat != null:
		tw.parallel().tween_property(_wall_mat, "shader_parameter/fade", 0.0, t)
		tw.parallel().tween_property(_floor_mat, "shader_parameter/fade", 0.0, t)
	tw.tween_callback(queue_free)

func _spawn_fx() -> void:
	var p := get_parent()
	match fx_kind:
		"slam":
			Fx.shockwave(p, origin, Color(1.0, 0.45, 0.2), radius * 1.4, 0.4)
			Fx.debris(p, origin, 16, 9.0)
		"land":
			Fx.shockwave(p, origin, Color(1.0, 0.3, 0.6), radius * 1.8, 0.5)
			Fx.shockwave(p, origin, Color(1.0, 0.7, 0.3), radius * 1.1, 0.3)
			Fx.debris(p, origin, 26, 12.0)
		"spikes":
			Fx.spikes(p, origin, radius, 7)
			Fx.shockwave(p, origin, Color(1.0, 0.25, 0.7), radius * 1.2, 0.3)
		"blast":
			Fx.shockwave(p, Vector3.ZERO, Color(1.0, 0.25, 0.6), GameConfig.ARENA_RADIUS + 6.0, 0.7)
			Fx.shockwave(p, Vector3.ZERO, Color(1.0, 0.85, 0.9), GameConfig.ARENA_RADIUS * 0.7, 0.45)
			for i in 6:
				var a := TAU * float(i) / 6.0
				Fx.debris(p, Vector3(cos(a), 0.0, sin(a)) * randf_range(5.0, 18.0), 10, 12.0)
