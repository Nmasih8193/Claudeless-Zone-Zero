class_name Fx
extends RefCounted
## Cached materials/meshes + one-shot effect helpers (no per-hit allocations of shared resources).

const MAX_BURSTS := 40
const MAX_FX := 60

static var active_bursts: int = 0
static var active_fx: int = 0
static var _meshes: Dictionary = {}
static var _shrink: Curve
static var _arc: ArrayMesh
static var _quad: QuadMesh
static var _plane: PlaneMesh
static var _rock_mesh: BoxMesh
static var _spike_mesh: CylinderMesh
static var _spike_mat: ShaderMaterial

# ------------------------------------------------------------------ materials
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

static func shader_mat(sh: Shader, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m

## Cel-shaded material shared by the world props and the boss.
static func toon_mat(color: Color, glow: float = 0.0, rim: float = 0.3, rim_color: Color = Color(1.0, 1.0, 1.0)) -> ShaderMaterial:
	return shader_mat(Shaders.toon(), {"albedo": color, "glow": glow, "rim": rim, "rim_color": rim_color})

static func outline_mat(width: float = 0.012, color: Color = Color(0.06, 0.04, 0.09)) -> ShaderMaterial:
	return shader_mat(Shaders.outline(), {"width": width, "color": color})

# ------------------------------------------------------------------ cached meshes
static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1.0, 1.0)
	return _quad

static func plane2() -> PlaneMesh:
	if _plane == null:
		_plane = PlaneMesh.new()
		_plane.size = Vector2(2.0, 2.0)
	return _plane

static func shrink_curve() -> Curve:
	if _shrink == null:
		_shrink = Curve.new()
		_shrink.add_point(Vector2(0.0, 1.0))
		_shrink.add_point(Vector2(0.7, 0.6))
		_shrink.add_point(Vector2(1.0, 0.0))
	return _shrink

## Crescent in the XZ plane, centred on forward (-Z), radius 1. UV.x along the arc, UV.y inner->outer.
static func arc_mesh() -> ArrayMesh:
	if _arc != null:
		return _arc
	var n := 28
	var span := 3.4
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in n + 1:
		var f := float(i) / float(n)
		var a := lerpf(span * 0.5, -span * 0.5, f)
		var dir := Vector3(sin(a), 0.0, -cos(a))
		var lift := sin(f * PI) * 0.12
		var inner := 0.42 + 0.18 * sin(f * PI)
		verts.append(dir * inner + Vector3(0.0, lift, 0.0))
		uvs.append(Vector2(f, 0.0))
		verts.append(dir * 1.0 + Vector3(0.0, lift, 0.0))
		uvs.append(Vector2(f, 1.0))
	for i in n:
		var a0 := i * 2
		idx.append_array(PackedInt32Array([a0, a0 + 1, a0 + 2, a0 + 1, a0 + 3, a0 + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_arc = ArrayMesh.new()
	_arc.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _arc

static func _particle_mesh(e: int) -> Mesh:
	if _meshes.has(e):
		return _meshes[e]
	var mat := glow_mat(GameConfig.element_color(e), 4.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var out: Mesh
	if e == GameConfig.Element.ETHER:
		var s := SphereMesh.new()
		s.radius = 0.1
		s.height = 0.2
		s.radial_segments = 8
		s.rings = 4
		s.material = mat
		out = s
	else:
		var b := BoxMesh.new()
		if e == GameConfig.Element.ELECTRIC:
			b.size = Vector3(0.04, 0.04, 0.9)      # lightning arc
		elif e == GameConfig.Element.ICE:
			b.size = Vector3(0.1, 0.1, 0.5)        # ice shard
		else:
			b.size = Vector3(0.05, 0.05, 0.6)      # spark streak
		b.material = mat
		out = b
	_meshes[e] = out
	return out

static func _can_spawn(parent: Node) -> bool:
	return parent != null and parent.is_inside_tree() and active_fx < MAX_FX

static func _track(n: Node) -> void:
	active_fx += 1
	n.tree_exiting.connect(func() -> void: Fx.active_fx -= 1)

# ------------------------------------------------------------------ particles
static func burst(parent: Node, pos: Vector3, element: int, amount: int = 14, speed: float = 7.0) -> void:
	if parent == null or not parent.is_inside_tree() or active_bursts >= MAX_BURSTS:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.55
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed * 1.2
	p.damping_min = 4.0
	p.damping_max = 8.0
	p.particle_flag_align_y = true
	if element == GameConfig.Element.ETHER:
		p.gravity = Vector3(0.0, 2.0, 0.0)
	else:
		p.gravity = Vector3(0.0, -12.0, 0.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	p.scale_amount_curve = shrink_curve()
	p.mesh = _particle_mesh(element)
	active_bursts += 1
	p.tree_exiting.connect(func() -> void: Fx.active_bursts -= 1)
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(1.0).timeout.connect(p.queue_free)

## Chunks of concrete thrown up by slams and landings.
static func debris(parent: Node, pos: Vector3, amount: int = 18, speed: float = 9.0) -> void:
	if parent == null or not parent.is_inside_tree() or active_bursts >= MAX_BURSTS:
		return
	if _rock_mesh == null:
		_rock_mesh = BoxMesh.new()
		_rock_mesh.size = Vector3(0.3, 0.22, 0.26)
		_rock_mesh.material = toon_mat(Color(0.28, 0.27, 0.32), 0.0, 0.15)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 1.1
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 1.2
	p.emission_ring_inner_radius = 0.2
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed * 1.3
	p.gravity = Vector3(0.0, -24.0, 0.0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.8
	p.scale_amount_curve = shrink_curve()
	p.mesh = _rock_mesh
	active_bursts += 1
	p.tree_exiting.connect(func() -> void: Fx.active_bursts -= 1)
	parent.add_child(p)
	p.global_position = pos + Vector3(0.0, 0.2, 0.0)
	p.emitting = true
	p.get_tree().create_timer(1.6).timeout.connect(p.queue_free)

# ------------------------------------------------------------------ flashes
## Expanding glowing ring on the floor.
static func shockwave(parent: Node, pos: Vector3, color: Color, radius: float, duration: float = 0.35) -> void:
	if not _can_spawn(parent):
		return
	var ring := MeshInstance3D.new()
	ring.mesh = plane2()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := shader_mat(Shaders.ring(), {"color": color, "thickness": 0.16, "fade": 1.0})
	ring.material_override = mat
	_track(ring)
	parent.add_child(ring)
	ring.global_position = Vector3(pos.x, 0.08, pos.z)
	ring.scale = Vector3(0.3, 1.0, 0.3)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 1.0, radius), duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, duration * 1.3).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)

## Weapon slash crescent. yaw = facing, tilt = roll for diagonal swings, mirror flips the sweep.
static func slash(parent: Node, pos: Vector3, yaw: float, color: Color, radius: float = 2.2, heavy: bool = false, tilt: float = 0.0, mirror: bool = false) -> void:
	if not _can_spawn(parent):
		return
	var m := MeshInstance3D.new()
	m.mesh = arc_mesh()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := shader_mat(Shaders.slash(), {"color": color, "head": 0.0, "tail": 0.7 if heavy else 0.55, "fade": 1.0})
	m.material_override = mat
	_track(m)
	parent.add_child(m)
	m.global_position = pos
	m.rotation = Vector3(0.0, yaw, tilt)
	var s := radius * (1.25 if heavy else 1.0)
	m.scale = Vector3(-s if mirror else s, s, s)
	var dur := 0.2 if heavy else 0.13
	var tw := m.create_tween()
	tw.tween_property(mat, "shader_parameter/head", 1.6, dur).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "shader_parameter/fade", 0.0, dur * 1.6).set_delay(dur * 0.4)
	tw.tween_callback(m.queue_free)

## Small 4-point hit spark.
static func spark(parent: Node, pos: Vector3, color: Color, size: float = 1.6) -> void:
	_star(parent, pos, color, size, 0.12, randf() * TAU)

## The attack "flash" before an enemy hit lands: gold = parryable, red = must dodge.
static func glint(parent: Node, pos: Vector3, color: Color, size: float = 3.2) -> void:
	_star(parent, pos, color, size, 0.38, 0.0)

static func _star(parent: Node, pos: Vector3, color: Color, size: float, dur: float, spin: float) -> void:
	if not _can_spawn(parent):
		return
	var m := MeshInstance3D.new()
	m.mesh = quad()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := shader_mat(Shaders.star(), {"color": color, "fade": 1.0, "spin": spin})
	m.material_override = mat
	_track(m)
	parent.add_child(m)
	m.global_position = pos
	m.scale = Vector3.ONE * size * 0.2
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE * size, dur * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "shader_parameter/spin", spin + 0.6, dur)
	tw.tween_property(m, "scale", Vector3.ONE * size * 0.1, dur * 0.7).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mat, "shader_parameter/fade", 0.0, dur * 0.7)
	tw.tween_callback(m.queue_free)

## Corrupted crystal spikes bursting out of the floor.
static func spikes(parent: Node, pos: Vector3, radius: float, count: int = 7) -> void:
	if not _can_spawn(parent):
		return
	if _spike_mesh == null:
		_spike_mesh = CylinderMesh.new()
		_spike_mesh.top_radius = 0.0
		_spike_mesh.bottom_radius = 0.42
		_spike_mesh.height = 2.6
		_spike_mesh.radial_segments = 5
		_spike_mesh.rings = 1
		_spike_mat = toon_mat(Color(0.2, 0.06, 0.18), 1.4, 0.6, Color(1.0, 0.3, 0.7))
	var root := Node3D.new()
	_track(root)
	parent.add_child(root)
	root.global_position = Vector3(pos.x, 0.0, pos.z)
	for i in count:
		var s := MeshInstance3D.new()
		s.mesh = _spike_mesh
		s.material_override = _spike_mat
		var a := TAU * float(i) / float(count) + randf_range(-0.3, 0.3)
		var d := radius * randf_range(0.15, 0.75) if i > 0 else 0.0
		s.position = Vector3(cos(a) * d, 0.0, sin(a) * d)
		var out := Vector3(cos(a), 0.0, sin(a))
		s.rotation = Vector3(out.z * 0.35, randf() * TAU, -out.x * 0.35)
		var h := randf_range(0.7, 1.35) * (1.4 if i == 0 else 1.0)
		s.scale = Vector3(h, 0.01, h)
		root.add_child(s)
		var tw := s.create_tween()
		tw.tween_property(s, "scale", Vector3(h, h, h), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.45)
		tw.tween_property(s, "scale", Vector3(h * 0.6, 0.01, h * 0.6), 0.3).set_ease(Tween.EASE_IN)
	root.get_tree().create_timer(1.0).timeout.connect(root.queue_free)
