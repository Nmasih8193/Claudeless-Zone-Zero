class_name Arena
extends Node3D
## The world: night-time neon plaza in front of a Hollow. Everything is generated in code.
## Graphics toggles live in GameConfig (GFX_*).

const SIGN_WORDS := ["NOODLES", "24H", "HOTEL", "ARCADE", "VIDEO", "BAR", "RAMEN", "KARAOKE"]
const NEON := [Color(1.0, 0.3, 0.75), Color(0.3, 0.9, 1.0), Color(1.0, 0.75, 0.25), Color(0.6, 1.0, 0.4), Color(0.75, 0.45, 1.0)]

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 1337
	_build_environment()
	_build_lights()
	_build_floor()
	_build_barriers()
	_build_lamps()
	_build_city()
	_build_props()
	_build_particles()

# ------------------------------------------------------------------ environment
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = Fx.shader_mat(Shaders.sky())
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.44, 0.72)
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(1, 0.3)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.6)
	env.set_glow_level(5, 0.35)
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.2, 0.42)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.2
	if GameConfig.GFX_VOLUMETRIC_FOG:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.014
		env.volumetric_fog_albedo = Color(0.75, 0.65, 0.95)
		env.volumetric_fog_emission = Color(0.06, 0.025, 0.09)
		env.volumetric_fog_emission_energy = 1.0
		env.volumetric_fog_length = 90.0
		env.volumetric_fog_anisotropy = 0.45
		env.volumetric_fog_sky_affect = 0.0
	if GameConfig.GFX_SSAO:
		env.ssao_enabled = true
		env.ssao_radius = 1.4
		env.ssao_intensity = 1.8
		env.ssao_power = 1.5
	if GameConfig.GFX_SSR:
		env.ssr_enabled = true
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _build_lights() -> void:
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50.0, -135.0, 0.0)
	moon.light_color = Color(0.78, 0.84, 1.0)
	moon.light_energy = 1.15
	moon.shadow_enabled = true
	moon.shadow_blur = 1.5
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if GameConfig.GFX_SHADOW_SPLITS >= 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 70.0
	moon.light_volumetric_fog_energy = 0.6
	add_child(moon)
	# magenta back/rim light from the city: gives characters a coloured anime rim
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-22.0, 45.0, 0.0)
	rim.light_color = Color(1.0, 0.42, 0.75)
	rim.light_energy = 0.55
	rim.shadow_enabled = false
	rim.light_volumetric_fog_energy = 0.0
	add_child(rim)

# ------------------------------------------------------------------ ground
func _build_floor() -> void:
	var f := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(260.0, 260.0)
	f.mesh = pm
	f.material_override = Fx.shader_mat(Shaders.floor_shader(), {"arena_r": GameConfig.ARENA_RADIUS})
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(f)
	# kerb ring with glowing inner edge
	var kerb := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = GameConfig.ARENA_RADIUS + 3.4
	tor.outer_radius = GameConfig.ARENA_RADIUS + 3.9
	tor.rings = 96
	kerb.mesh = tor
	kerb.scale = Vector3(1.0, 0.35, 1.0)
	kerb.material_override = Fx.toon_mat(Color(0.32, 0.32, 0.38), 0.0, 0.2)
	add_child(kerb)

func _build_barriers() -> void:
	var body := Fx.toon_mat(Color(0.62, 0.6, 0.58), 0.0, 0.25)
	var stripe := Fx.glow_mat(Color(1.0, 0.55, 0.12), 2.2)
	var n := 22
	var r := GameConfig.ARENA_RADIUS + 7.5          # leaves room for the orbit camera
	for i in n:
		if i % 7 == 3:
			continue
		var a := TAU * (float(i) + 0.5) / float(n)
		var holder := Node3D.new()
		holder.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		holder.rotation.y = -a + PI * 0.5
		add_child(holder)
		var seg_len := TAU * r / float(n) * 0.82
		_box(holder, Vector3(seg_len, 0.9, 0.6), body, Vector3(0.0, 0.45, 0.0))
		_box(holder, Vector3(seg_len * 0.98, 0.5, 0.35), body, Vector3(0.0, 1.05, 0.0))
		_box(holder, Vector3(seg_len * 0.99, 0.08, 0.37), stripe, Vector3(0.0, 0.95, 0.0))

func _build_lamps() -> void:
	var metal := Fx.toon_mat(Color(0.16, 0.16, 0.2), 0.0, 0.3)
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.2
		var r := GameConfig.ARENA_RADIUS + 5.6
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var inward := -base.normalized()
		var col: Color = Color(1.0, 0.78, 0.5) if i % 2 == 0 else Color(0.45, 0.85, 1.0)
		var holder := Node3D.new()
		holder.position = base
		add_child(holder)
		holder.look_at_from_position(base, base + inward, Vector3.UP)
		_cyl(holder, 0.12, 7.0, metal, Vector3(0.0, 3.5, 0.0))
		_box(holder, Vector3(0.14, 0.14, 2.0), metal, Vector3(0.0, 6.9, -0.9))
		_box(holder, Vector3(0.6, 0.18, 0.8), Fx.glow_mat(col, 4.0), Vector3(0.0, 6.75, -1.8))
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 2.4
		l.omni_range = 13.0
		l.omni_attenuation = 1.4
		l.position = Vector3(0.0, 6.2, -1.8)
		l.light_volumetric_fog_energy = 1.5
		holder.add_child(l)

# ------------------------------------------------------------------ city
func _build_city() -> void:
	# inner ring of blocks facing the plaza
	var count := 34
	for i in count:
		var a := TAU * float(i) / float(count) + _rng.randf_range(-0.05, 0.05)
		var rad := _rng.randf_range(44.0, 56.0)
		var size := Vector3(_rng.randf_range(7.0, 13.0), _rng.randf_range(12.0, 38.0), _rng.randf_range(7.0, 12.0))
		_building(Vector3(cos(a) * rad, 0.0, sin(a) * rad), size, -a + PI * 0.5 + _rng.randf_range(-0.15, 0.15), 0.4)
	# distant skyline silhouettes
	for i in 26:
		var a := TAU * float(i) / 26.0 + _rng.randf_range(-0.08, 0.08)
		var rad := _rng.randf_range(85.0, 115.0)
		var size := Vector3(_rng.randf_range(10.0, 18.0), _rng.randf_range(30.0, 70.0), _rng.randf_range(10.0, 18.0))
		_building(Vector3(cos(a) * rad, 0.0, sin(a) * rad), size, _rng.randf() * TAU, 0.22)
	# neon signs on the inner ring, facing the arena
	for i in SIGN_WORDS.size():
		var a := TAU * float(i) / float(SIGN_WORDS.size()) + 0.35
		var p := Vector3(cos(a) * 42.5, _rng.randf_range(7.0, 13.0), sin(a) * 42.5)
		_sign(p, SIGN_WORDS[i], NEON[i % NEON.size()])

func _building(pos: Vector3, size: Vector3, yaw: float, lit: float) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var tint := _rng.randf_range(0.8, 1.2)
	m.material_override = Fx.shader_mat(Shaders.building(), {
		"half_h": size.y * 0.5, "lit_ratio": lit,
		"wall": Color(0.08 * tint, 0.09 * tint, 0.13 * tint),
	})
	m.position = pos + Vector3(0.0, size.y * 0.5 - 0.1, 0.0)
	m.rotation.y = yaw
	add_child(m)
	# rooftop clutter
	if _rng.randf() < 0.7:
		var top := pos + Vector3(0.0, size.y, 0.0)
		var metal := Fx.toon_mat(Color(0.12, 0.12, 0.16), 0.0, 0.1)
		var off := Vector3(_rng.randf_range(-1.0, 1.0) * size.x * 0.3, 0.0, _rng.randf_range(-1.0, 1.0) * size.z * 0.3)
		if _rng.randf() < 0.5:
			_cyl(self, 1.2, 2.2, metal, top + off + Vector3(0.0, 1.1, 0.0))
		var h := _rng.randf_range(3.0, 8.0)
		_cyl(self, 0.08, h, metal, top - off + Vector3(0.0, h * 0.5, 0.0))
		var beacon := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.25
		s.height = 0.5
		beacon.mesh = s
		beacon.material_override = Fx.glow_mat(Color(1.0, 0.1, 0.1), 6.0)
		beacon.position = top - off + Vector3(0.0, h, 0.0)
		add_child(beacon)

func _sign(pos: Vector3, text: String, col: Color) -> void:
	var holder := Node3D.new()
	add_child(holder)
	holder.look_at_from_position(pos, Vector3(0.0, pos.y, 0.0), Vector3.UP)
	var w := 1.4 * float(text.length()) + 1.5
	_box(holder, Vector3(w, 2.6, 0.3), Fx.toon_mat(Color(0.05, 0.05, 0.08), 0.0, 0.0), Vector3.ZERO)
	_box(holder, Vector3(w + 0.2, 0.12, 0.35), Fx.glow_mat(col, 3.0), Vector3(0.0, 1.35, 0.0))
	_box(holder, Vector3(w + 0.2, 0.12, 0.35), Fx.glow_mat(col, 3.0), Vector3(0.0, -1.35, 0.0))
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 160
	lbl.pixel_size = 0.012
	lbl.outline_size = 0
	lbl.shaded = false
	lbl.modulate = Color(col.r * 2.2, col.g * 2.2, col.b * 2.2)
	lbl.position = Vector3(0.0, 0.0, -0.17)
	lbl.rotation.y = PI
	holder.add_child(lbl)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 3.0
	l.omni_range = 12.0
	l.position = Vector3(0.0, 0.0, -2.0)
	l.light_volumetric_fog_energy = 2.0
	holder.add_child(l)

func _build_props() -> void:
	var cols := [Color(0.55, 0.18, 0.14), Color(0.12, 0.4, 0.45), Color(0.75, 0.55, 0.12), Color(0.25, 0.27, 0.35)]
	var spots := [0.6, 1.7, 2.6, 3.9, 5.1]
	for k in spots.size():
		var a: float = spots[k]
		var r := _rng.randf_range(37.0, 40.0)
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var stack := _rng.randi_range(1, 3)
		for j in stack:
			var c: Color = cols[(k + j) % cols.size()]
			var m := _box(self, Vector3(2.5, 2.6, 6.0), Fx.toon_mat(c, 0.0, 0.2), base + Vector3(0.0, 1.3 + float(j) * 2.6, 0.0))
			m.rotation.y = -a + _rng.randf_range(-0.3, 0.3)
		for j in 3:
			var cone := Vector3(cos(a + 0.08 * float(j + 1)) * (r - 4.0), 0.0, sin(a + 0.08 * float(j + 1)) * (r - 4.0))
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.28
			cm.height = 0.75
			cm.radial_segments = 10
			var mi := MeshInstance3D.new()
			mi.mesh = cm
			mi.material_override = Fx.toon_mat(Color(1.0, 0.4, 0.1), 0.2, 0.3)
			mi.position = cone + Vector3(0.0, 0.375, 0.0)
			add_child(mi)

func _build_particles() -> void:
	var p := CPUParticles3D.new()
	p.amount = 160
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(34.0, 5.0, 34.0)
	p.position = Vector3(0.0, 4.0, 0.0)
	p.direction = Vector3.UP
	p.spread = 60.0
	p.gravity = Vector3(0.2, 0.25, 0.0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.6
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.16
	p.color = Color(1.0, 0.5, 0.75)
	p.hue_variation_min = -0.08
	p.hue_variation_max = 0.08
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = Fx.shader_mat(Shaders.soft_glow(), {"color": Color(1.0, 1.0, 1.0), "energy": 3.0})
	p.mesh = q
	add_child(p)

# ------------------------------------------------------------------ helpers
func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m

func _cyl(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	m.mesh = c
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m
