class_name Shaders
extends RefCounted
## Every custom shader in the game, compiled once and cached.
## Kept as code strings so the project stays a pure "scripts only" build.

static var _cache: Dictionary = {}

static func _compile(key: String, code: String) -> Shader:
	if _cache.has(key):
		return _cache[key]
	var s := Shader.new()
	s.code = code
	_cache[key] = s
	return s

# ------------------------------------------------------------------ characters
## Cel-shaded anime look: crisp 2-band key light, tinted shadows, toon specular, fresnel rim.
static func toon() -> Shader:
	return _compile("toon", """
shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shade : source_color = vec4(0.62, 0.56, 0.78, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim = 0.35;
uniform float spec = 0.12;
uniform float glow = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform float flash = 0.0;
void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.8;
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float r = smoothstep(0.62, 0.72, fres);
	EMISSION = albedo.rgb * glow + rim_color.rgb * r * rim + flash_color.rgb * flash;
}
void light() {
	float ndl = dot(NORMAL, LIGHT);
	if (LIGHT_IS_DIRECTIONAL) {
		float lit = smoothstep(0.0, 0.06, ndl) * smoothstep(0.25, 0.55, ATTENUATION);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(shade.rgb * 0.35, vec3(1.0), lit);
		vec3 h = normalize(LIGHT + VIEW);
		float s = pow(max(dot(NORMAL, h), 0.0), 48.0);
		SPECULAR_LIGHT += LIGHT_COLOR / PI * smoothstep(0.45, 0.5, s) * spec * lit;
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * smoothstep(-0.1, 0.4, ndl) * ATTENUATION * 0.9;
	}
}
""")

## Inverted-hull outline; width grows a little with distance so silhouettes stay readable.
static func outline() -> Shader:
	return _compile("outline", """
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform vec4 color : source_color = vec4(0.06, 0.04, 0.09, 1.0);
uniform float width = 0.012;
void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += NORMAL * width * clamp(d / 7.0, 0.7, 3.0);
}
void fragment() {
	ALBEDO = color.rgb;
}
""")

# ------------------------------------------------------------------ world
const _NOISE := """
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return v;
}
"""

## Wet concrete plaza: tiles, grime, reflective puddles (SSR), glowing arena markings.
static func floor_shader() -> Shader:
	return _compile("floor", """
shader_type spatial;
uniform vec3 tile_a : source_color = vec3(0.20, 0.21, 0.26);
uniform vec3 tile_b : source_color = vec3(0.13, 0.14, 0.18);
uniform vec3 street : source_color = vec3(0.07, 0.07, 0.09);
uniform vec3 line_col : source_color = vec3(0.25, 0.85, 1.0);
uniform vec3 warn_col : source_color = vec3(1.0, 0.65, 0.1);
uniform float arena_r = 24.0;
varying vec3 wpos;
""" + _NOISE + """
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wpos.xz;
	float r = length(p);
	float ang = atan(p.y, p.x);
	vec2 g = p / 2.0;
	vec2 gf = abs(fract(g) - 0.5);
	float grout = smoothstep(0.465, 0.49, max(gf.x, gf.y));
	vec3 col = mix(tile_a, tile_b, hash(floor(g)) * 0.6 + fbm(p * 0.3) * 0.4);
	col *= 1.0 - grout * 0.5;
	float outside = smoothstep(arena_r + 3.5, arena_r + 4.5, r);
	vec2 lane = abs(fract(p / 7.0) - 0.5);
	float dash = step(0.5, fract(p.x * 0.25)) * smoothstep(0.03, 0.0, abs(lane.y - 0.0)) ;
	col = mix(col, street * (0.8 + 0.4 * fbm(p * 0.5)), outside);
	col += vec3(0.5) * dash * outside * 0.3;
	col *= mix(0.7, 1.12, fbm(p * 0.13 + 3.0));
	float wet = smoothstep(0.5, 0.6, fbm(p * 0.09 + 11.0));
	float ring_edge = smoothstep(0.16, 0.0, abs(r - arena_r - 0.6));
	float ring_edge2 = smoothstep(0.05, 0.0, abs(r - arena_r - 1.1));
	float ring1 = smoothstep(0.05, 0.0, abs(r - 8.0));
	float ring2 = smoothstep(0.05, 0.0, abs(r - 15.0));
	float spokes = smoothstep(0.996, 1.0, cos(ang * 8.0)) * step(8.0, r) * step(r, arena_r);
	float band = step(arena_r - 0.9, r) * step(r, arena_r + 0.3);
	float stripes = step(0.5, fract(ang * arena_r / 1.4 + r * 0.2));
	col = mix(col, mix(vec3(0.05), warn_col * 0.6, stripes), band * 0.85);
	float center = smoothstep(2.2, 2.0, r) * smoothstep(1.8, 2.0, r);
	ALBEDO = col * (1.0 - wet * 0.45);
	ROUGHNESS = mix(0.78, 0.04, wet);
	SPECULAR = 0.5;
	EMISSION = line_col * (ring_edge * 2.6 + ring_edge2 * 1.2 + (ring1 + ring2) * 0.7 + spokes * 0.45 + center * 0.8)
		+ warn_col * band * stripes * 0.25;
}
""")

## City block facades: procedural lit windows (local space, so rotated boxes still work).
static func building() -> Shader:
	return _compile("building", """
shader_type spatial;
uniform vec3 wall : source_color = vec3(0.09, 0.10, 0.14);
uniform vec3 win_a : source_color = vec3(1.0, 0.78, 0.45);
uniform vec3 win_b : source_color = vec3(0.45, 0.85, 1.0);
uniform vec3 win_c : source_color = vec3(1.0, 0.4, 0.8);
uniform float half_h = 5.0;
uniform float lit_ratio = 0.38;
varying vec3 lpos;
varying vec3 lnorm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
}
void fragment() {
	float seed = hash(NODE_POSITION_WORLD.xz);
	vec3 col = wall * (0.8 + 0.4 * seed);
	vec3 em = vec3(0.0);
	float rough = 0.9;
	if (abs(lnorm.y) < 0.5) {
		float h = abs(lnorm.x) > 0.5 ? lpos.z : lpos.x;
		vec2 uv = vec2(h, lpos.y + half_h);
		vec2 cell = uv / vec2(1.5, 2.1);
		vec2 id = floor(cell) + seed * 91.0;
		vec2 f = fract(cell);
		float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.22, f.y) * step(f.y, 0.78);
		float floor_line = smoothstep(0.06, 0.0, abs(f.y - 0.02));
		float on = step(1.0 - lit_ratio, hash(id));
		float pick = hash(id * 1.37 + 4.0);
		vec3 wc = pick < 0.6 ? win_a : (pick < 0.88 ? win_b : win_c);
		float ground = step(lpos.y + half_h, 2.2);
		col = mix(col, vec3(0.03, 0.035, 0.05), win);
		col *= 1.0 - floor_line * 0.35;
		em = wc * win * on * (0.7 + 0.9 * hash(id + 3.1)) * (1.0 - ground) * 1.6;
		rough = mix(0.9, 0.15, win);
	} else {
		col *= 0.55;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = em;
}
""")

## Night sky: gradient, stars, and a giant Hollow (black sphere with a swirling, glowing rim).
static func sky() -> Shader:
	return _compile("sky", """
shader_type sky;
uniform vec3 top : source_color = vec3(0.015, 0.02, 0.06);
uniform vec3 mid : source_color = vec3(0.08, 0.05, 0.17);
uniform vec3 horizon : source_color = vec3(0.50, 0.17, 0.42);
uniform vec3 hollow_col : source_color = vec3(1.0, 0.32, 0.62);
uniform vec3 hollow_dir = vec3(-0.62, 0.30, -0.72);
uniform float hollow_size = 0.34;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 c = mix(horizon, mid, smoothstep(-0.02, 0.22, h));
	c = mix(c, top, smoothstep(0.22, 0.85, h));
	c = mix(c, vec3(0.02, 0.015, 0.035), smoothstep(0.0, -0.25, h));
	vec2 sp = d.xz / max(d.y + 0.35, 0.05) * 90.0;
	vec2 id = floor(sp);
	float st = step(0.985, hash(id)) * smoothstep(0.5, 0.0, length(fract(sp) - 0.5)) * smoothstep(0.05, 0.4, h);
	c += vec3(0.8, 0.85, 1.0) * st * (0.5 + 0.5 * sin(TIME * 2.0 + hash(id) * 40.0));
	vec3 hd = normalize(hollow_dir);
	float ang = acos(clamp(dot(d, hd), -1.0, 1.0));
	vec3 t1 = normalize(cross(hd, vec3(0.0, 1.0, 0.0)));
	vec3 t2 = cross(t1, hd);
	float phi = atan(dot(d, t2), dot(d, t1));
	float sw = 0.5 + 0.5 * sin(phi * 6.0 + ang * 38.0 - TIME * 0.35);
	float inside = smoothstep(hollow_size, hollow_size - 0.012, ang);
	float rim = exp(-abs(ang - hollow_size) * 45.0);
	float halo = exp(-max(ang - hollow_size, 0.0) * 7.0) * step(hollow_size, ang);
	vec3 core = mix(vec3(0.0), vec3(0.16, 0.02, 0.14), sw * smoothstep(0.0, hollow_size, ang));
	c = mix(c, core, inside);
	c += hollow_col * (rim * 2.2 * (0.75 + 0.25 * sw) + halo * 0.35);
	COLOR = c;
}
""")

# ------------------------------------------------------------------ combat fx
## Ground telegraph: shape 0 circle, 1 rect (fills from the boss outward), 2 sector, 3 full arena.
static func telegraph() -> Shader:
	return _compile("telegraph", """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.15, 0.1, 1.0);
uniform float progress = 0.0;
uniform int shape = 0;
uniform float half_angle = 1.0;
uniform float intensity = 1.0;
varying vec2 lp;
void vertex() {
	lp = VERTEX.xz;
}
void fragment() {
	float edge = 0.0;
	float fc = 0.0;
	float rr = length(lp);
	if (shape == 1) {
		vec2 va = abs(lp);
		edge = max(smoothstep(0.93, 1.0, va.x), smoothstep(0.97, 1.0, va.y));
		fc = (1.0 - lp.y) * 0.5;
	} else {
		if (rr > 1.0) { discard; }
		edge = smoothstep(0.94, 1.0, rr);
		if (shape == 2) {
			float sa = atan(lp.x, -lp.y);
			if (abs(sa) > half_angle) { discard; }
			edge = max(edge, smoothstep(half_angle - 0.05, half_angle, abs(sa)));
		}
		fc = rr;
	}
	float filled = step(fc, progress);
	float front = smoothstep(0.035, 0.0, abs(fc - progress)) * step(0.01, progress);
	float stripes = step(0.55, fract((lp.x + lp.y) * 5.0 - TIME * 1.4)) * 0.07;
	float alpha_v = 0.08 + stripes + filled * 0.2 + edge * 0.7 + front * 0.6;
	ALBEDO = color.rgb * (1.2 + edge * 1.2 + front * 1.5);
	ALPHA = clamp(alpha_v * intensity, 0.0, 1.0);
}
""")

## Expanding ring band (shockwaves). PlaneMesh 2x2; `thickness` is relative to the radius.
static func ring() -> Shader:
	return _compile("ring", """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform float thickness = 0.12;
uniform float fade = 1.0;
varying vec2 lp;
void vertex() { lp = VERTEX.xz; }
void fragment() {
	float r = length(lp);
	float b = smoothstep(1.0 - thickness, 1.0 - thickness * 0.4, r) * smoothstep(1.0, 0.97, r);
	float inner = smoothstep(1.0 - thickness * 3.0, 1.0, r) * 0.25;
	ALBEDO = color.rgb * 2.0;
	ALPHA = clamp((b + inner) * fade, 0.0, 1.0);
}
""")

## Vertical glowing wall (quake rings, beam): open cylinder, brightest at the base.
static func energy_wall() -> Shader:
	return _compile("energy_wall", """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.3, 0.6, 1.0);
uniform float fade = 1.0;
uniform float height = 1.0;
varying float vy;
varying float vang;
void vertex() {
	vy = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	vang = atan(VERTEX.z, VERTEX.x);
}
void fragment() {
	float v = 1.0 - vy;
	float flick = 0.85 + 0.15 * sin(TIME * 40.0 + vang * 30.0);
	float wa = pow(v, 2.4) * flick + smoothstep(0.93, 1.0, v) * 0.8;
	ALBEDO = color.rgb * 2.5;
	ALPHA = clamp(wa * fade, 0.0, 1.0);
}
""")

## Glowing tube (boss core beam). Brightest where the surface faces the camera.
static func beam() -> Shader:
	return _compile("beam", """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.2, 0.5, 1.0);
uniform float fade = 1.0;
void fragment() {
	float f = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float flick = 0.9 + 0.1 * sin(TIME * 55.0);
	ALBEDO = mix(color.rgb * 2.2, vec3(2.4), pow(f, 5.0)) * flick;
	ALPHA = clamp(pow(f, 1.4) * fade, 0.0, 1.0);
}
""")

## Weapon slash crescent. UV.x runs along the arc, UV.y from inner (0) to outer (1) edge.
static func slash() -> Shader:
	return _compile("slash", """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(0.5, 0.9, 1.0, 1.0);
uniform float head = 0.0;
uniform float tail = 0.55;
uniform float fade = 1.0;
void fragment() {
	float x = UV.x;
	float along = smoothstep(head - tail, head, x) * step(x, head);
	float across = smoothstep(0.0, 0.7, UV.y) * smoothstep(1.0, 0.85, UV.y);
	float core = smoothstep(0.75, 0.95, UV.y) * smoothstep(1.0, 0.93, UV.y);
	vec3 c = mix(color.rgb * 1.6, vec3(1.6), core * along);
	ALBEDO = c * 1.5;
	ALPHA = clamp(along * (across * 0.8 + core) * fade, 0.0, 1.0);
}
""")

## 4-point star flash (hit sparks and the gold/red attack glint). Billboarded quad.
static func star() -> Shader:
	return _compile("star", """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform float fade = 1.0;
uniform float spin = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float cs = cos(spin);
	float sn = sin(spin);
	p = mat2(vec2(cs, -sn), vec2(sn, cs)) * p;
	vec2 a = abs(p);
	float rays = max(exp(-a.y * 26.0) * (1.0 - a.x), exp(-a.x * 26.0) * (1.0 - a.y));
	vec2 q = mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071)) * p;
	vec2 b = abs(q);
	float diag = max(exp(-b.y * 40.0) * (1.0 - b.x * 1.6), exp(-b.x * 40.0) * (1.0 - b.y * 1.6)) * 0.45;
	float glow = exp(-length(p) * 5.0);
	float v = clamp(rays + max(diag, 0.0) + glow, 0.0, 2.0);
	ALBEDO = mix(color.rgb, vec3(1.0), clamp(glow * 1.2, 0.0, 1.0)) * 3.0;
	ALPHA = clamp(v * fade, 0.0, 1.0);
}
""")

## Soft additive billboard sprite (orb halos, embers).
static func soft_glow() -> Shader:
	return _compile("soft_glow", """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform float energy = 2.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float g = pow(clamp(1.0 - d, 0.0, 1.0), 2.0);
	ALBEDO = color.rgb * energy * COLOR.rgb;
	ALPHA = clamp(g * COLOR.a, 0.0, 1.0);
}
""")

## Translucent ice for the freeze shell.
static func ice() -> Shader:
	return _compile("ice", """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
uniform vec4 tint : source_color = vec4(0.55, 0.9, 1.0, 0.45);
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.05;
	METALLIC = 0.2;
	SPECULAR = 0.9;
	EMISSION = tint.rgb * (0.25 + fres * 1.6);
	ALPHA = clamp(tint.a + fres * 0.5, 0.0, 0.95);
}
""")

# ------------------------------------------------------------------ screen
## Full-screen post: vignette, chromatic aberration, desaturation/tint (perfect dodge, chain),
## radial blur (ultimate) and a pulsing red danger border.
static func post() -> Shader:
	return _compile("post", """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.32;
uniform float chroma = 0.0;
uniform float desat = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tint_amt = 0.0;
uniform float blur = 0.0;
uniform float danger = 0.0;
uniform float scan = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	vec3 c = vec3(0.0);
	if (blur > 0.001) {
		for (int i = 0; i < 8; i++) {
			c += texture(screen_tex, uv - dir * blur * float(i) / 8.0).rgb;
		}
		c /= 8.0;
	} else {
		c = texture(screen_tex, uv).rgb;
	}
	if (chroma > 0.0005) {
		c.r = mix(c.r, texture(screen_tex, uv + dir * chroma).r, 0.85);
		c.b = mix(c.b, texture(screen_tex, uv - dir * chroma).b, 0.85);
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat);
	c = mix(c, c * tint * 1.4, tint_amt);
	float r = length(dir * vec2(1.0, 0.75));
	float v = smoothstep(0.85, 0.25, r);
	c *= mix(1.0, v, vignette);
	c = mix(c, vec3(1.0, 0.05, 0.08), smoothstep(0.38, 0.75, r) * danger * 0.55);
	c *= 1.0 - scan * 0.08 * step(0.5, fract(SCREEN_UV.y * 240.0));
	COLOR = vec4(c, 1.0);
}
""")
