class_name Fx
extends RefCounted
## Cached materials/meshes + one-shot effect helpers (no per-hit allocations of shared resources).

const MAX_BURSTS := 40

static var active_bursts: int = 0
static var _meshes: Dictionary = {}

static func glow_mat(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

static func flat_alpha_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	return m

static func _particle_mesh(e: int) -> Mesh:
	if _meshes.has(e):
		return _meshes[e]
	var mat := glow_mat(GameConfig.element_color(e), 3.0)
	var out: Mesh
	if e == GameConfig.Element.ETHER:
		var s := SphereMesh.new()
		s.radius = 0.12
		s.height = 0.24
		s.radial_segments = 8
		s.rings = 4
		s.material = mat
		out = s
	else:
		var b := BoxMesh.new()
		if e == GameConfig.Element.ELECTRIC:
			b.size = Vector3(0.05, 0.05, 0.9)      # lightning arc
		elif e == GameConfig.Element.ICE:
			b.size = Vector3(0.12, 0.12, 0.45)     # ice shard
		else:
			b.size = Vector3(0.12, 0.12, 0.12)
		b.material = mat
		out = b
	_meshes[e] = out
	return out

static func burst(parent: Node, pos: Vector3, element: int, amount: int = 14, speed: float = 7.0) -> void:
	if parent == null or active_bursts >= MAX_BURSTS:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.6
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	if element == GameConfig.Element.ETHER:
		p.gravity = Vector3(0.0, 2.0, 0.0)
	else:
		p.gravity = Vector3(0.0, -9.0, 0.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	p.mesh = _particle_mesh(element)
	active_bursts += 1
	p.tree_exiting.connect(func() -> void: Fx.active_bursts -= 1)
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(1.2).timeout.connect(p.queue_free)

static func shockwave(parent: Node, pos: Vector3, color: Color, radius: float, duration: float = 0.35) -> void:
	if parent == null:
		return
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.2
	cyl.radial_segments = 32
	cyl.rings = 1
	ring.mesh = cyl
	var mat := flat_alpha_mat(Color(color, 0.7))
	ring.material_override = mat
	parent.add_child(ring)
	ring.global_position = Vector3(pos.x, 0.12, pos.z)
	ring.scale = Vector3(0.3, 1.0, 0.3)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 1.0, radius), duration)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(ring.queue_free)
