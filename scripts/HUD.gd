class_name HUD
extends CanvasLayer
## HUD laid out after the real game: squad top-left, boss/timer/score top-right,
## points popups mid-left, skill cluster bottom-right. Updated by sync() (throttled by Main).
## Also owns the navigation screens bound to ZZZ's keys: G Proxy Handbook, J Inter-Knot,
## T Squad, Tab / LT Shortcut Wheel, Esc pause. Opening one pauses the fight.

signal pause_changed(is_paused: bool)
signal overlay_changed(open: bool)
signal action_requested(action: String)

const W := 1280.0
const H := 720.0
const TEXT_DARK := Color(0.05, 0.08, 0.12)
const GOLD := Color(1.0, 0.82, 0.25)
const WHEEL_ITEMS := ["PROXY HANDBOOK", "SQUAD", "INTER-KNOT", "RETRY"]
const WHEEL_KEYS := ["G", "T", "J", "R"]

var can_pause: bool = false
var overlay: String = ""
var player: Player

var _veil: ColorRect
var _flash: ColorRect
var _msg: Label
var _banner: Label
var _banner_tween: Tween
var _flash_tween: Tween
var _pts_box: Control
var _pts_lbl: Label
var _pts_sub: Label
var _pts_tween: Tween
var _combo_lbl: Label
var _sq_icon: ColorRect
var _sq_letter: Label
var _sq_face: TextureRect
var _sq_face_name: String = ""
var _res_face: Array[TextureRect] = []
var _res_face_name: Array[String] = ["", ""]
var _sq_hp: ProgressBar
var _sq_hp_txt: Label
var _sq_en: ProgressBar
var _buffs: Label
var _res_icon: Array[ColorRect] = []
var _res_letter: Array[Label] = []
var _res_hp: Array[ProgressBar] = []
var _res_en: Array[ProgressBar] = []
var _boss_phase: Label
var _boss_hp: ProgressBar
var _boss_stun: ProgressBar
var _stun_fill: StyleBoxFlat
var _boss_status: Label
var _time_bar: ProgressBar
var _time_lbl: Label
var _score_lbl: Label
var _badge: ColorRect
var _badge_lbl: Label
var _slot_dodge: ColorRect
var _slot_ex: ColorRect
var _slot_ex_title: Label
var _slot_ult: ColorRect
var _ult_ring: ColorRect
var _ult_pct: Label
var _assist_lbl: Label
var _lock_lbl: Label
var _danger_lbl: Label
var _danger_tween: Tween
# chain picker
var _chain_root: Control
var _chain_cards: Array[Panel] = []
var _chain_faces: Array[TextureRect] = []
var _chain_names: Array[Label] = []
var _chain_timer: ProgressBar
# overlays
var _panel: Panel
var _panel_title: Label
var _panel_body: RichTextLabel
var _wheel: Control
var _wheel_items: Array[Panel] = []
var _wheel_vec: Vector2 = Vector2.ZERO
var _wheel_pick: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_squad()
	_build_boss()
	_build_score()
	_build_skills()
	_build_chain()
	_build_overlays()
	_build_panel()
	_build_wheel()

# ------------------------------------------------------------------ builders
func _rect(pos: Vector2, size: Vector2, color: Color, parent: Node = null) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(r)
	else:
		add_child(r)
	return r

func _label(text: String, pos: Vector2, font_px: int, color: Color = Color.WHITE, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(l)
	else:
		add_child(l)
	return l

func _style(bg: Color, radius: int = 6, border: Color = Color(0.0, 0.0, 0.0, 0.0), bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s

func _bar(pos: Vector2, size: Vector2, fill_color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = size
	b.size = size
	b.position = pos
	b.show_percentage = false
	b.max_value = 100.0
	b.value = 100.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("fill", _style(fill_color, 3))
	b.add_theme_stylebox_override("background", _style(Color(0.03, 0.04, 0.08, 0.85), 3))
	add_child(b)
	return b

func _face_rect(parent: Control, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.size = size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t

func _build_squad() -> void:
	_rect(Vector2(14.0, 10.0), Vector2(792.0, 100.0), Color(0.0, 0.0, 0.0, 0.3))
	_sq_icon = _rect(Vector2(24.0, 18.0), Vector2(64.0, 64.0), Color.WHITE)
	_sq_letter = _label("E", Vector2(18.0, 6.0), 40, TEXT_DARK, _sq_icon)
	_sq_letter.visible = false
	_sq_face = _face_rect(_sq_icon, Vector2(64.0, 64.0))
	_sq_hp = _bar(Vector2(100.0, 24.0), Vector2(400.0, 22.0), Color(0.45, 0.95, 0.2))
	_sq_hp_txt = _label("", Vector2(104.0, 46.0), 16)
	_sq_en = _bar(Vector2(100.0, 72.0), Vector2(260.0, 8.0), Color(0.3, 0.7, 1.0))
	_sq_en.value = 0.0
	_buffs = _label("", Vector2(100.0, 82.0), 14, Color(1.0, 0.85, 0.4))
	for k in 2:
		var x := 530.0 + float(k) * 140.0
		var ic := _rect(Vector2(x, 20.0), Vector2(46.0, 46.0), Color.WHITE)
		var lt := _label("N", Vector2(12.0, 4.0), 28, TEXT_DARK, ic)
		var hp := _bar(Vector2(x + 52.0, 24.0), Vector2(72.0, 12.0), Color(0.45, 0.95, 0.2))
		var en := _bar(Vector2(x + 52.0, 42.0), Vector2(72.0, 7.0), Color(0.3, 0.7, 1.0))
		_label("C" if k == 0 else "SPACE", Vector2(x + 52.0, 50.0), 12, Color(0.75, 0.8, 0.9))
		lt.visible = false
		_res_face.append(_face_rect(ic, Vector2(46.0, 46.0)))
		_res_icon.append(ic)
		_res_letter.append(lt)
		_res_hp.append(hp)
		_res_en.append(en)

func _build_boss() -> void:
	_label("CORRUPTED COLOSSUS", Vector2(900.0, 0.0), 14, Color(1.0, 0.5, 0.65))
	_boss_phase = _label("PHASE 1", Vector2(812.0, 16.0), 22, Color(1.0, 0.85, 0.2))
	_boss_hp = _bar(Vector2(900.0, 24.0), Vector2(316.0, 20.0), Color(0.55, 0.92, 0.2))
	_rect(Vector2(900.0 + 316.0 * 0.66 - 1.0, 24.0), Vector2(2.0, 20.0), Color(0.0, 0.0, 0.0, 0.9))
	_rect(Vector2(900.0 + 316.0 * 0.33 - 1.0, 24.0), Vector2(2.0, 20.0), Color(0.0, 0.0, 0.0, 0.9))
	_boss_stun = _bar(Vector2(900.0, 48.0), Vector2(316.0, 9.0), Color(1.0, 0.6, 0.1))
	_boss_stun.value = 0.0
	_stun_fill = _boss_stun.get_theme_stylebox("fill") as StyleBoxFlat
	_boss_status = _label("", Vector2(900.0, 58.0), 14, Color(0.7, 0.95, 1.0))
	var badge := _rect(Vector2(1224.0, 18.0), Vector2(44.0, 44.0), Color(0.7, 0.1, 0.4))
	_label("B", Vector2(14.0, 4.0), 28, Color.WHITE, badge)

func _build_score() -> void:
	_rect(Vector2(1222.0, 80.0), Vector2(46.0, 30.0), Color(0.75, 0.12, 0.12))
	_label("TIME", Vector2(1226.0, 82.0), 14)
	_time_bar = _bar(Vector2(900.0, 86.0), Vector2(316.0, 14.0), Color(0.9, 0.2, 0.15))
	_time_lbl = _label("00:04:00", Vector2(1090.0, 98.0), 22)
	_rect(Vector2(880.0, 140.0), Vector2(360.0, 34.0), Color(0.05, 0.07, 0.1, 0.85))
	_score_lbl = _label("", Vector2(890.0, 144.0), 18)
	_badge = _rect(Vector2(1234.0, 134.0), Vector2(40.0, 40.0), Color(0.5, 0.5, 0.55))
	_badge_lbl = _label("C", Vector2(10.0, 0.0), 28, Color.WHITE, _badge)
	_pts_box = Control.new()
	_pts_box.position = Vector2(24.0, 120.0)
	_pts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pts_box.modulate.a = 0.0
	add_child(_pts_box)
	_pts_lbl = _label("", Vector2(0.0, 0.0), 44, Color(0.3, 1.0, 0.8), _pts_box)
	_pts_sub = _label("", Vector2(4.0, 54.0), 18, Color(0.8, 1.0, 0.95), _pts_box)
	_combo_lbl = _label("", Vector2(24.0, 200.0), 34, Color(0.5, 0.95, 1.0))

func _slot(pos: Vector2, title: String, key: String, px: float = 64.0) -> ColorRect:
	var r := _rect(pos, Vector2(px, px), Color(0.08, 0.1, 0.15, 0.92))
	var t := _label(title, Vector2(4.0, px * 0.5 - 12.0), 14, Color.WHITE, r)
	t.size = Vector2(px - 8.0, 24.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.name = "Title"
	var k := _label(key, Vector2(pos.x - 10.0, pos.y + px + 2.0), 13, Color(0.8, 0.85, 0.9))
	k.size = Vector2(px + 20.0, 20.0)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return r

func _build_skills() -> void:
	var y := 604.0
	_label("SPACE / C  switch agent      MMB  lock-on      ALT  cursor", Vector2(820.0, y - 30.0), 14, Color(0.85, 0.9, 1.0))
	_slot(Vector2(940.0, y), "BASIC", "LMB")
	_slot_dodge = _slot(Vector2(1020.0, y), "DODGE", "SHIFT / RMB")
	_slot_ex = _slot(Vector2(1100.0, y), "SPECIAL", "E")
	_slot_ex_title = _slot_ex.get_node("Title") as Label
	_ult_ring = _rect(Vector2(1172.0, y - 12.0), Vector2(92.0, 92.0), Color(1.0, 0.75, 0.1, 0.0))
	_slot_ult = _slot(Vector2(1182.0, y - 2.0), "ULT", "Q", 72.0)
	_ult_pct = _label("0%", Vector2(1182.0, y + 46.0), 14, Color(1.0, 0.9, 0.5))
	_ult_pct.size = Vector2(72.0, 20.0)
	_ult_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_assist_lbl = _label("", Vector2(240.0, 560.0), 24, Color(0.6, 0.95, 1.0))
	_assist_lbl.size = Vector2(800.0, 40.0)
	_assist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_lbl = _label("", Vector2(560.0, 690.0), 16, Color(1.0, 0.5, 0.6))
	_lock_lbl.size = Vector2(160.0, 24.0)
	_lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_chain() -> void:
	_chain_root = Control.new()
	_chain_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chain_root.visible = false
	add_child(_chain_root)
	var title := _label("CHAIN ATTACK", Vector2(340.0, 250.0), 52, GOLD, _chain_root)
	title.size = Vector2(600.0, 70.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var keys := ["LMB  /  Q", "RMB  /  E"]
	for k in 2:
		var p := Panel.new()
		p.position = Vector2(400.0 + float(k) * 330.0, 330.0)
		p.size = Vector2(150.0, 190.0)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_theme_stylebox_override("panel", _style(Color(0.05, 0.06, 0.1, 0.9), 10, GOLD, 3))
		_chain_root.add_child(p)
		var face := _face_rect(p, Vector2(134.0, 120.0))
		face.position = Vector2(8.0, 8.0)
		var nm := _label("", Vector2(0.0, 128.0), 20, Color.WHITE, p)
		nm.size = Vector2(150.0, 26.0)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var kl := _label(keys[k], Vector2(0.0, 156.0), 16, GOLD, p)
		kl.size = Vector2(150.0, 24.0)
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_chain_cards.append(p)
		_chain_faces.append(face)
		_chain_names.append(nm)
	_chain_timer = ProgressBar.new()
	_chain_timer.position = Vector2(440.0, 535.0)
	_chain_timer.size = Vector2(400.0, 8.0)
	_chain_timer.show_percentage = false
	_chain_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chain_timer.add_theme_stylebox_override("fill", _style(GOLD, 3))
	_chain_timer.add_theme_stylebox_override("background", _style(Color(0.0, 0.0, 0.0, 0.6), 3))
	_chain_root.add_child(_chain_timer)

func _build_overlays() -> void:
	_flash = _rect(Vector2.ZERO, Vector2(W, H), Color.WHITE)
	_flash.modulate.a = 0.0
	_veil = _rect(Vector2.ZERO, Vector2(W, H), Color(0.0, 0.0, 0.0, 0.62))
	_veil.visible = false
	_banner = _label("", Vector2(240.0, 200.0), 46, Color(1.0, 0.95, 0.2))
	_banner.size = Vector2(800.0, 64.0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_danger_lbl = _label("", Vector2(240.0, 130.0), 58, Color(1.0, 0.15, 0.2))
	_danger_lbl.size = Vector2(800.0, 80.0)
	_danger_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_danger_lbl.modulate.a = 0.0
	_msg = _label("", Vector2(140.0, 80.0), 26)
	_msg.size = Vector2(1000.0, 560.0)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_panel() -> void:
	_panel = Panel.new()
	_panel.position = Vector2(200.0, 60.0)
	_panel.size = Vector2(880.0, 600.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _style(Color(0.04, 0.05, 0.09, 0.94), 14, Color(0.3, 0.85, 1.0, 0.8), 2))
	_panel.visible = false
	add_child(_panel)
	_rect(Vector2(0.0, 0.0), Vector2(880.0, 6.0), GOLD, _panel)
	_panel_title = _label("", Vector2(30.0, 18.0), 34, GOLD, _panel)
	_panel_body = RichTextLabel.new()
	_panel_body.bbcode_enabled = true
	_panel_body.position = Vector2(30.0, 72.0)
	_panel_body.size = Vector2(820.0, 490.0)
	_panel_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_body.add_theme_font_size_override("normal_font_size", 17)
	_panel_body.add_theme_font_size_override("bold_font_size", 17)
	_panel_body.scroll_active = false
	_panel.add_child(_panel_body)
	var hint := _label("Press the same key or ESC to close", Vector2(30.0, 566.0), 14, Color(0.7, 0.75, 0.85), _panel)
	hint.size = Vector2(820.0, 20.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _build_wheel() -> void:
	_wheel = Control.new()
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.visible = false
	add_child(_wheel)
	_rect(Vector2.ZERO, Vector2(W, H), Color(0.0, 0.0, 0.0, 0.45), _wheel)
	var c := Vector2(W * 0.5, H * 0.5)
	var hub := Panel.new()
	hub.position = c - Vector2(40.0, 40.0)
	hub.size = Vector2(80.0, 80.0)
	hub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hub.add_theme_stylebox_override("panel", _style(Color(0.05, 0.06, 0.1, 0.9), 40, GOLD, 2))
	_wheel.add_child(hub)
	var offs := [Vector2(0.0, -170.0), Vector2(230.0, 0.0), Vector2(0.0, 170.0), Vector2(-230.0, 0.0)]
	for i in 4:
		var p := Panel.new()
		p.size = Vector2(220.0, 64.0)
		p.pivot_offset = p.size * 0.5
		p.position = c + (offs[i] as Vector2) - p.size * 0.5
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_theme_stylebox_override("panel", _style(Color(0.06, 0.08, 0.13, 0.95), 12, Color(0.3, 0.85, 1.0, 0.7), 2))
		_wheel.add_child(p)
		var l := _label(WHEEL_ITEMS[i], Vector2(0.0, 8.0), 20, Color.WHITE, p)
		l.size = Vector2(220.0, 28.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var k := _label(WHEEL_KEYS[i], Vector2(0.0, 36.0), 14, GOLD, p)
		k.size = Vector2(220.0, 20.0)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_wheel_items.append(p)
	var tip := _label("Move the mouse / stick toward an option, release TAB / LT to select", Vector2(0.0, H * 0.5 + 240.0), 16, Color(0.8, 0.85, 0.95), _wheel)
	tip.size = Vector2(W, 24.0)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

# ------------------------------------------------------------------ live updates
func _set_text(l: Label, s: String) -> void:
	if l.text != s:
		l.text = s

func sync(p: Player, boss: Boss, time_left: float) -> void:
	player = p
	var a := p.active
	var c := p.chars[a]
	_sq_icon.color = c.color
	_set_text(_sq_letter, c.char_name.substr(0, 1))
	if _sq_face_name != c.char_name:
		_sq_face_name = c.char_name
		_sq_face.texture = PuppetConfig.portrait(c.char_name)
	_sq_hp.value = c.hp / c.max_hp * 100.0
	_set_text(_sq_hp_txt, "%d/%d" % [int(c.hp), int(c.max_hp)])
	_sq_en.value = c.energy / GameConfig.ENERGY_MAX * 100.0
	var order := [posmod(a - 1, 3), posmod(a + 1, 3)]
	for slot in 2:
		var o := p.chars[int(order[slot])]
		_res_icon[slot].color = o.color if o.is_alive() else Color(0.25, 0.25, 0.28)
		_set_text(_res_letter[slot], o.char_name.substr(0, 1))
		if _res_face_name[slot] != o.char_name:
			_res_face_name[slot] = o.char_name
			_res_face[slot].texture = PuppetConfig.portrait(o.char_name)
		_res_icon[slot].modulate = Color.WHITE if o.is_alive() else Color(0.45, 0.45, 0.5)
		_res_hp[slot].value = o.hp / o.max_hp * 100.0
		_res_en[slot].value = o.energy / GameConfig.ENERGY_MAX * 100.0
	var parts: PackedStringArray = []
	if p.assist_buff_t > 0.0:
		parts.append("ASSIST +%d%% (%ds)" % [roundi(GameConfig.ASSIST_BUFF * 100.0), ceili(p.assist_buff_t)])
	if c.field_buff > 0.0:
		parts.append("FIELD +%d%%" % roundi(c.field_buff * 100.0))
	if c.stacks > 0:
		parts.append("FLURRY x%d" % c.stacks)
	_set_text(_buffs, "   ".join(parts))

	_boss_hp.value = boss.hp / GameConfig.BOSS_MAX_HP * 100.0
	_boss_stun.value = boss.daze_ratio() * 100.0
	if _stun_fill != null:
		_stun_fill.bg_color = Color(1.0, 0.25, 0.2) if boss.is_stunned() else Color(1.0, 0.6, 0.1)
	_set_text(_boss_phase, "PHASE %d" % boss.phase)
	var st: PackedStringArray = []
	if boss.is_stunned():
		st.append("STUNNED %.1fs" % boss.stun_t)
	if boss.frozen_t > 0.0:
		st.append("FROZEN")
	if boss.def_down_t > 0.0:
		st.append("DEF DOWN")
	_set_text(_boss_status, "   ".join(st))

	_time_bar.value = time_left / GameConfig.FIGHT_TIME * 100.0
	var m := floori(time_left / 60.0)
	var s := floori(time_left - float(m) * 60.0)
	_set_text(_time_lbl, "00:%02d:%02d" % [m, s])

	_slot_dodge.modulate.a = 0.4 if p.dodge_cd > 0.0 else 1.0
	var ex_ready := c.energy >= c.ex_cost
	_slot_ex.modulate.a = 1.0
	_slot_ex.color = Color(0.1, 0.35, 0.6, 0.95) if ex_ready else Color(0.08, 0.1, 0.15, 0.92)
	_set_text(_slot_ex_title, "EX" if ex_ready else "SPECIAL")
	var ult_ready := p.decibel >= GameConfig.DECIBEL_MAX
	_slot_ult.modulate.a = 1.0 if ult_ready else 0.5
	_ult_ring.color.a = 0.55 + 0.35 * sin(float(Time.get_ticks_msec()) * 0.012) if ult_ready else 0.0
	_set_text(_ult_pct, "READY" if ult_ready else "%d%%" % int(p.decibel / GameConfig.DECIBEL_MAX * 100.0))
	if _chain_root.visible:
		_chain_timer.value = p.chain_time_left() / GameConfig.CHAIN_PROMPT_TIME * 100.0
	if _assist_lbl.text != "":
		_assist_lbl.modulate.a = 0.7 + 0.3 * sin(float(Time.get_ticks_msec()) * 0.02)

func set_lock(on: bool) -> void:
	_set_text(_lock_lbl, "LOCK-ON" if on else "")

func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

func set_score(score: float, mult: float, grade: String, next_threshold: float) -> void:
	_set_text(_score_lbl, "Current Score: (x%.1f) %s/%s" % [mult, _commas(int(score)), _commas(int(next_threshold))])
	_set_text(_badge_lbl, grade)
	match grade:
		"S":
			_badge.color = Color(1.0, 0.35, 0.2)
		"A":
			_badge.color = Color(1.0, 0.75, 0.15)
		"B":
			_badge.color = Color(0.2, 0.5, 1.0)
		_:
			_badge.color = Color(0.5, 0.5, 0.55)

func set_combo(n: int) -> void:
	_set_text(_combo_lbl, "" if n < 2 else "%d HITS" % n)

func show_points(pts: int, label: String) -> void:
	_pts_lbl.text = "%d PTS" % pts
	_pts_sub.text = label
	_pts_box.modulate.a = 1.0
	if _pts_tween != null and _pts_tween.is_valid():
		_pts_tween.kill()
	_pts_tween = create_tween()
	_pts_tween.tween_interval(1.5)
	_pts_tween.tween_property(_pts_box, "modulate:a", 0.0, 0.5)

func show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.0)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.4)

func show_danger(text: String) -> void:
	if text == "":
		return
	_danger_lbl.text = text
	_danger_lbl.modulate.a = 1.0
	if _danger_tween != null and _danger_tween.is_valid():
		_danger_tween.kill()
	_danger_tween = create_tween()
	for i in 3:
		_danger_tween.tween_property(_danger_lbl, "modulate:a", 0.25, 0.18)
		_danger_tween.tween_property(_danger_lbl, "modulate:a", 1.0, 0.18)
	_danger_tween.tween_property(_danger_lbl, "modulate:a", 0.0, 0.4)

func show_assist(text: String) -> void:
	_assist_lbl.text = text
	_assist_lbl.modulate.a = 1.0

func show_chain(left: int, right: int) -> void:
	if left < 0 and right < 0 or player == null:
		_chain_root.visible = false
		return
	_chain_root.visible = true
	var idx := [left, right]
	for k in 2:
		var i: int = idx[k]
		_chain_cards[k].visible = i >= 0
		if i >= 0:
			var c := player.chars[i]
			_chain_faces[k].texture = PuppetConfig.portrait(c.char_name)
			_chain_names[k].text = c.char_name
			_chain_names[k].add_theme_color_override("font_color", c.color)
	_chain_timer.value = 100.0

func flash(color: Color, strength: float = 0.75) -> void:
	_flash.color = color
	_flash.modulate.a = strength
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.45)

func show_message(text: String, font_px: int = 26) -> void:
	_msg.text = text
	_msg.add_theme_font_size_override("font_size", font_px)
	_veil.visible = true

func clear_message() -> void:
	_msg.text = ""
	_veil.visible = false

func show_start() -> void:
	show_message("DEADLY ASSAULT  -  PROTOTYPE\n\n" +
		"MOUSE  look around      WASD  move      SHIFT / RMB  dodge  (hold = sprint)\n" +
		"LMB  attack      E  special  (EX when energy is full)      Q  ultimate\n" +
		"SPACE / C  switch agent      MMB  lock-on      WHEEL  zoom      ALT  show cursor\n\n" +
		"GOLD flash: swap in for a Defensive Assist, or perfect-dodge it.\n" +
		"RED flash: unblockable - dodge it!\n" +
		"After a perfect dodge:  LMB = Dodge Counter,  SPACE / C = Evasive Assist.\n" +
		"Stun the boss to open the Chain Attack picker  (LMB = left agent, RMB = right).\n\n" +
		"G  Proxy Handbook     J  Inter-Knot     T  Squad     TAB  Shortcut Wheel     ESC  pause\n" +
		"Controller supported (Xbox layout).\n\n" +
		"Press  F / ENTER  (or A)  to enter the Hollow", 19)

func show_results(outcome: String, grade: String, stats: Dictionary) -> void:
	show_message("%s\n\nGRADE  %s\n\nScore: %s\nDamage dealt: %s\nDamage taken: %s\nTime left: %.1fs\nMax combo: %d\nPerfect dodges: %d   Assists: %d   Chains: %d   Ultimates: %d\n\nPress F / R to retry" % [
		outcome, grade, _commas(int(stats["score"])), _commas(int(stats["damage"])), _commas(int(stats["taken"])),
		float(stats["time_left"]), int(stats["max_combo"]), int(stats["perfect_dodges"]),
		int(stats["assists"]), int(stats["chains"]), int(stats["ults"])])

# ------------------------------------------------------------------ navigation screens
func _open(what: String) -> void:
	overlay = what
	get_tree().paused = true
	_panel.visible = true
	match what:
		"pause":
			_panel_title.text = "PAUSED"
			_panel_body.text = _pause_text()
		"handbook":
			_panel_title.text = "PROXY HANDBOOK"
			_panel_body.text = _handbook_text()
		"interknot":
			_panel_title.text = "INTER-KNOT"
			_panel_body.text = _interknot_text()
		"squad":
			_panel_title.text = "SQUAD"
			_panel_body.text = _squad_text()
	overlay_changed.emit(true)
	pause_changed.emit(true)

func _close() -> void:
	overlay = ""
	_panel.visible = false
	_wheel.visible = false
	get_tree().paused = false
	overlay_changed.emit(false)
	pause_changed.emit(false)

func _toggle(what: String) -> void:
	if overlay == what:
		_close()
	elif overlay == "" or overlay == "pause" or _panel.visible:
		_open(what)

func _open_wheel() -> void:
	overlay = "wheel"
	_wheel_vec = Vector2.ZERO
	_wheel_pick = -1
	_update_wheel_pick()
	_wheel.visible = true
	get_tree().paused = true
	overlay_changed.emit(true)

func _close_wheel(activate: bool) -> void:
	_wheel.visible = false
	var pick := _wheel_pick
	overlay = ""
	get_tree().paused = false
	overlay_changed.emit(false)
	if not activate or pick < 0:
		return
	match pick:
		0:
			_open("handbook")
		1:
			_open("squad")
		2:
			_open("interknot")
		3:
			action_requested.emit("retry")

func _update_wheel_pick() -> void:
	_wheel_pick = -1
	if _wheel_vec.length() > 35.0:
		var ang := _wheel_vec.angle()
		if absf(ang + PI * 0.5) <= PI * 0.25:
			_wheel_pick = 0
		elif absf(ang) < PI * 0.25:
			_wheel_pick = 1
		elif absf(ang - PI * 0.5) <= PI * 0.25:
			_wheel_pick = 2
		else:
			_wheel_pick = 3
	for i in _wheel_items.size():
		var on := i == _wheel_pick
		_wheel_items[i].modulate = Color(1.35, 1.2, 0.7) if on else Color(1.0, 1.0, 1.0, 0.85)
		_wheel_items[i].scale = Vector2.ONE * (1.08 if on else 1.0)

func _process(_delta: float) -> void:
	if overlay != "wheel":
		return
	var v := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if v.length() < 0.3:
		v = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v.length() > 0.5:
		_wheel_vec = v * 120.0
		_update_wheel_pick()

func _unhandled_input(event: InputEvent) -> void:
	if overlay == "wheel":
		if event is InputEventMouseMotion:
			_wheel_vec = (_wheel_vec + (event as InputEventMouseMotion).relative).limit_length(150.0)
			_update_wheel_pick()
			get_viewport().set_input_as_handled()
		elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_X:
			_close_wheel(false)
			_open("squad")
			get_viewport().set_input_as_handled()
		elif event.is_action_released("wheel") or event.is_action_pressed("pause"):
			_close_wheel(event.is_action_released("wheel"))
			get_viewport().set_input_as_handled()
		return
	if not can_pause:
		return
	var handled := true
	if event.is_action_pressed("pause"):
		if overlay == "":
			_open("pause")
		else:
			_close()
	elif event.is_action_pressed("handbook"):
		_toggle("handbook")
	elif event.is_action_pressed("interknot"):
		_toggle("interknot")
	elif event.is_action_pressed("squad"):
		_toggle("squad")
	elif event.is_action_pressed("wheel") and overlay == "":
		_open_wheel()
	elif overlay == "pause" and event.is_action_pressed("restart"):
		_close()
		action_requested.emit("retry")
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()

func _pause_text() -> String:
	return "[center]\n[b]ESC[/b]  resume\n\n[b]R[/b]  retry\n\n[b]G[/b]  Proxy Handbook      [b]J[/b]  Inter-Knot      [b]T[/b]  Squad\n\n[b]TAB[/b] (hold)  Shortcut Wheel[/center]"

func _handbook_text() -> String:
	var y := "[color=#ffd23f]"
	return (y + "COMBAT[/color]\n" +
		"[b]LMB[/b] basic attack (hold to keep the combo going)    [b]E[/b] special / EX special (needs energy)\n" +
		"[b]SHIFT / RMB[/b] dodge - hold after dodging to sprint    [b]Q[/b] ultimate (Decibel 100%)\n" +
		"[b]SPACE / C[/b] switch agent    [b]MMB[/b] lock-on    [b]MOUSE[/b] camera    [b]WHEEL[/b] zoom\n\n" +
		y + "READING THE BOSS[/color]\n" +
		"[color=#ffcc33]GOLD flash[/color]: the hit can be parried. Swap in an agent right then for a [b]Defensive Assist[/b],\n" +
		"   then press LMB for the [b]Assist Follow-Up[/b]. A perfect dodge works too.\n" +
		"[color=#ff3344]RED flash[/color]: unblockable (core beam, arena detonation). Dodge through it.\n" +
		"Dodge just as a hit is about to land = [b]Perfect Dodge[/b] (slow-mo):\n" +
		"   LMB = [b]Dodge Counter[/b],  SPACE / C = [b]Evasive Assist[/b].\n\n" +
		y + "STUN & CHAIN[/color]\n" +
		"Fill the Daze bar (Anby is best at it) to stun the Colossus. Time freezes and the\n" +
		"Chain Attack picker opens: [b]LMB / Q[/b] = left agent, [b]RMB / E[/b] = right agent. Up to 3 chains.\n\n" +
		y + "THE COLOSSUS[/color]\n" +
		"Smash - Claw Sweep - 3-hit String - Quake Stomps (dodge through the rings) - Meteor Leap\n" +
		"(the landing zone follows you) - Core Beam (RED) - Homing Orbs - Shoulder Charge -\n" +
		"Spike Eruption (keeps chasing you) - Annihilation (phase 3, RED, whole arena).")

func _interknot_text() -> String:
	var posts := [
		["NightRunner_77", "PSA: when the big guy stomps, the rings come out one per stomp. Dodge INTO them, the i-frames carry you through."],
		["sharkmaid_main", "ELLEN FREEZE GANG. Fill the frost on it and it just stands there in an ice cube taking damage. Bonus dmg too."],
		["proxy_404", "the leap one... the circle FOLLOWS you until the last half second. keep running, then dodge when it stops."],
		["bunny_bank", "Nicole EX pulls it in and shreds its DEF. Then swap. Then profit. Literally, I'm charging for this advice."],
		["static_anby", "Anby. Daze. Chain. Repeat."],
		["hollow_diver", "RED flash = do NOT try to parry. I tried to parry the beam. I am writing this from the clinic."],
		["sixth_street_cat", "you can hold TAB to bring up the shortcut wheel btw. also G opens the handbook if you forget anything"],
	]
	var out := ""
	for p: Array in posts:
		out += "[color=#5fd8ff][b]@%s[/b][/color]\n%s\n\n" % [p[0], p[1]]
	return out

func _squad_text() -> String:
	if player == null:
		return ""
	var roles := {"ELLEN": "Attack  -  Ice. Basic hits stack Flurry; her EX spends it for big damage and Freeze.",
		"NICOLE": "Support  -  Ether. On-field damage buff; EX pulls the boss in and applies DEF DOWN.",
		"ANBY": "Stun  -  Electric. Huge Daze per hit. The fastest way to a Chain Attack."}
	var out := ""
	for i in player.chars.size():
		var c := player.chars[i]
		var tag := "  [color=#ffd23f](ON FIELD)[/color]" if i == player.active else ""
		out += "[font_size=22][b][color=#%s]%s[/color][/b][/font_size]%s\n" % [c.color.to_html(false), c.char_name, tag]
		out += "HP %d / %d      Energy %d / %d\n" % [int(c.hp), int(c.max_hp), int(c.energy), int(GameConfig.ENERGY_MAX)]
		out += "%s\n\n" % roles.get(c.char_name, "")
	out += "Decibel: %d%%" % int(player.decibel / GameConfig.DECIBEL_MAX * 100.0)
	return out
