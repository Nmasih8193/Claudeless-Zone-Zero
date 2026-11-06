class_name Projectile
extends Node3D
## Boss energy orb: glides down to chest height, homes in briefly, leaves a glowing trail.

const HIT_RADIUS := 1.1
const CRUISE_Y := 1.3
static var _mesh: SphereMesh
static var _halo_mat: ShaderMaterial
static var _trail_mesh: SphereMesh

var velocity: Vector3 = Vector3.ZERO
var target: Player
var damage: float = 90.0
var life: float = 4.0
var homing: float = 0.0          # turn rate (rad/s) toward the target...
var homing_time: float = 0.0     # ...for this long after launch
var threat_id: int = 0
var _age: float = 0.0

func _ready() -> void:
	add_to_group("projectiles")
	threat_id = Hazard.new_id()
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 0.42
		_mesh.height = 0.84
		_mesh.radial_segments = 12
		_mesh.rings = 6
		var core := Fx.glow_mat(Color(1.0, 0.55, 0.85), 6.0)
		core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mesh.material = core
		_halo_mat = Fx.shader_mat(Shaders.soft_glow(), {"color": Color(1.0, 0.25, 0.6), "energy": 2.5})
		_trail_mesh = SphereMesh.new()
		_trail_mesh.radius = 0.22
		_trail_mesh.height = 0.44
		_trail_mesh.radial_segments = 8
		_trail_mesh.rings = 4
		var tm := Fx.glow_mat(Color(1.0, 0.3, 0.65), 4.0)
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_mesh.material = tm
	var m := MeshInstance3D.new()
	m.mesh = _mesh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	var halo := MeshInstance3D.new()
	halo.mesh = Fx.quad()
	halo.material_override = _halo_mat
	halo.scale = Vector3.ONE * 2.6
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	var trail := CPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.mesh = _trail_mesh
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.4
	trail.spread = 180.0
	trail.scale_amount_curve = Fx.shrink_curve()
	add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.35, 0.7)
	light.light_energy = 1.5
	light.omni_range = 4.0
	add_child(light)

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	life -= delta
	_age += delta
	if target != null and _age < homing_time and homing > 0.0:
		var to := target.global_position - global_position
		to.y = 0.0
		var flat_v := Vector3(velocity.x, 0.0, velocity.z)
		if to.length() > 0.5 and flat_v.length() > 0.1:
			var a := flat_v.signed_angle_to(to, Vector3.UP)
			flat_v = flat_v.rotated(Vector3.UP, clampf(a, -homing * delta, homing * delta))
			velocity = Vector3(flat_v.x, velocity.y, flat_v.z)
	var p := global_position + velocity * delta
	p.y = lerpf(p.y, CRUISE_Y, 1.0 - exp(-5.0 * delta))
	global_position = p
	var flat := Vector2(global_position.x, global_position.z)
	if life <= 0.0 or flat.length() > GameConfig.ARENA_RADIUS + 6.0:
		queue_free()
		return
	if target == null:
		return
	var d := target.global_position - global_position
	d.y = 0.0
	if d.length() < HIT_RADIUS and not target.is_invulnerable():
		target.take_damage(damage)
		Fx.burst(get_parent(), global_position, GameConfig.Element.ETHER, 12, 6.0)
		Fx.spark(get_parent(), global_position, Color(1.0, 0.4, 0.75), 2.0)
		queue_free()

## Non-zero while this orb is about to hit p (perfect-dodge / parry window).
func threat(p: Vector3) -> int:
	var d := p - global_position
	d.y = 0.0
	var v := Vector3(velocity.x, 0.0, velocity.z)
	var speed := v.length()
	if speed < 0.1:
		return 0
	var closing := d.dot(v / speed)
	if closing < -HIT_RADIUS:
		return 0
	var miss := (d - v / speed * closing).length()
	if miss < HIT_RADIUS + 0.8 and closing / speed <= GameConfig.PERFECT_WINDOW + 0.05:
		return threat_id
	return 0
