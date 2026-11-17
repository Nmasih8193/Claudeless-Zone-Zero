class_name PostFx
extends CanvasLayer
## Full-screen grading pass drawn above the 3D view but below the HUD.
## Effects are short pulses driven in real time so they look right during slow-mo.

var _rect: ColorRect
var _mat: ShaderMaterial
var _perfect: float = 0.0
var _perfect_len: float = 1.0
var _ult: float = 0.0
var _ult_len: float = 1.0
var _danger: float = 0.0
var _hit: float = 0.0
var _chain: bool = false
var _chain_amt: float = 0.0
var low_hp: float = 0.0              # 0..1, set by Main

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = Fx.shader_mat(Shaders.post())
	_rect.material = _mat
	add_child(_rect)
	visible = GameConfig.GFX_POST_FX

## Perfect dodge: cold desaturated slow-mo look.
func perfect(duration: float) -> void:
	_perfect_len = maxf(duration, 0.1)
	_perfect = _perfect_len

## Ultimate / chain hit: radial blur + chromatic punch.
func ult(duration: float = 0.5) -> void:
	_ult_len = maxf(duration, 0.1)
	_ult = _ult_len

## Red border pulse for unparryable attacks.
func danger() -> void:
	_danger = 1.0

func hit() -> void:
	_hit = 1.0

func set_chain(on: bool) -> void:
	_chain = on

func _process(_delta: float) -> void:
	var dt := clampf(_delta / maxf(Engine.time_scale, 0.01), 0.0, 0.1)
	_perfect = maxf(_perfect - dt, 0.0)
	_ult = maxf(_ult - dt, 0.0)
	_danger = maxf(_danger - dt * 1.4, 0.0)
	_hit = maxf(_hit - dt * 3.0, 0.0)
	_chain_amt = lerpf(_chain_amt, 1.0 if _chain else 0.0, 1.0 - exp(-10.0 * dt))
	var pf := 0.0
	if _perfect > 0.0:
		var k := 1.0 - _perfect / _perfect_len
		pf = smoothstep(0.0, 0.08, k) * (1.0 - smoothstep(0.75, 1.0, k))
	var uf := _ult / _ult_len
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.008)
	_mat.set_shader_parameter("vignette", 0.32 + pf * 0.35 + _chain_amt * 0.4 + low_hp * 0.2)
	_mat.set_shader_parameter("desat", maxf(pf * 0.55, _chain_amt * 0.6))
	_mat.set_shader_parameter("tint", Color(0.55, 0.8, 1.0) if pf >= _chain_amt else Color(1.0, 0.85, 0.55))
	_mat.set_shader_parameter("tint_amt", maxf(pf * 0.5, _chain_amt * 0.35))
	_mat.set_shader_parameter("chroma", pf * 0.012 + uf * 0.02 + _hit * 0.008)
	_mat.set_shader_parameter("blur", uf * 0.09)
	_mat.set_shader_parameter("danger", maxf(_danger, low_hp * (0.35 + 0.35 * pulse)))
	_mat.set_shader_parameter("scan", _chain_amt)
