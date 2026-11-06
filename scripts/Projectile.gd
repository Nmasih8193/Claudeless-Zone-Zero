class_name Projectile
extends Node3D

const HIT_RADIUS := 1.1
static var _mesh: SphereMesh

var velocity: Vector3 = Vector3.ZERO
var target: Player
var damage: float = 90.0
var life: float = 4.0

func _ready() -> void:
	add_to_group("projectiles")
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 0.55
		_mesh.height = 1.1
		_mesh.radial_segments = 12
		_mesh.rings = 6
		_mesh.material = Fx.glow_mat(Color(1.0, 0.45, 0.1), 4.0)
	var m := MeshInstance3D.new()
	m.mesh = _mesh
	add_child(m)

func _process(delta: float) -> void:
	life -= delta
	global_position += velocity * delta
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
		Fx.burst(get_parent(), global_position, GameConfig.Element.PHYSICAL, 8, 5.0)
		queue_free()
