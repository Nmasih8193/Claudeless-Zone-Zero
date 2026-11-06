class_name HUD
extends CanvasLayer
## HUD laid out after the real game: squad top-left, boss/timer/score top-right,
## points popups mid-left, skill cluster bottom-right. Updated by sync() (throttled by Main).

signal pause_changed(is_paused: bool)

const W := 1280.0
const H := 720.0
const TEXT_DARK := Color(0.05, 0.08, 0.12)

var can_pause: bool = false

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
var _slot_ult: ColorRect
var _ult_ring: ColorRect
var _ult_pct: Label
var _chain_lbl: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_squad()
	_build_boss()
	_build_score()
	_build_skills()
	_build_overlays()

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

func _bar(pos: Vector2, size: Vector2, fill_color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = size
	b.size = size
	b.position = pos
	b.show_percentage = false
	b.max_value = 100.0
	b.value = 100.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := StyleBoxFlat.new()
	f.bg_color = fill_color
	var g := StyleBoxFlat.new()
	g.bg_color = Color(0.03, 0.04, 0.08, 0.85)
	b.add_theme_stylebox_override("fill", f)
	b.add_theme_stylebox_override("background", g)
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
	_rect(Vector2(1224.0, 18.0), Vector2(44.0, 44.0), Color(0.7, 0.1, 0.4))
	_label("B", Vector2(14.0, 4.0), 28, Color.WHITE, get_child(get_child_count() - 1))

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
	var t := _label(title, Vector2(6.0, px * 0.5 - 12.0), 15, Color.WHITE, r)
	t.size = Vector2(px - 12.0, 24.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var k := _label(key, Vector2(pos.x, pos.y + px + 2.0), 14, Color(0.8, 0.85, 0.9))
	k.size = Vector2(px, 20.0)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return r

func _build_skills() -> void:
	var y := 604.0
	_label("Q / E  swap     1 2 3  select", Vector2(920.0, y - 30.0), 15, Color(0.85, 0.9, 1.0))
	_slot(Vector2(940.0, y), "BASIC", "J / CLICK")
	_slot_dodge = _slot(Vector2(1020.0, y), "DODGE", "K / SHIFT")
	_slot_ex = _slot(Vector2(1100.0, y), "EX", "L")
	_ult_ring = _rect(Vector2(1172.0, y - 12.0), Vector2(92.0, 92.0), Color(1.0, 0.75, 0.1, 0.0))
	_slot_ult = _slot(Vector2(1182.0, y - 2.0), "ULT", "SPACE", 72.0)
	_ult_pct = _label("0%", Vector2(1182.0, y + 46.0), 14, Color(1.0, 0.9, 0.5))
	_ult_pct.size = Vector2(72.0, 20.0)
	_ult_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chain_lbl = _label("[ F ]  CHAIN ATTACK!", Vector2(340.0, 540.0), 40, Color(1.0, 0.9, 0.2))
	_chain_lbl.size = Vector2(600.0, 56.0)
	_chain_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chain_lbl.visible = false

func _build_overlays() -> void:
	_flash = _rect(Vector2.ZERO, Vector2(W, H), Color.WHITE)
	_flash.modulate.a = 0.0
	_veil = _rect(Vector2.ZERO, Vector2(W, H), Color(0.0, 0.0, 0.0, 0.62))
	_veil.visible = false
	_banner = _label("", Vector2(240.0, 200.0), 46, Color(1.0, 0.95, 0.2))
	_banner.size = Vector2(800.0, 64.0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg = _label("", Vector2(240.0, 110.0), 26)
	_msg.size = Vector2(800.0, 500.0)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

# ------------------------------------------------------------------ live updates
func _set_text(l: Label, s: String) -> void:
	if l.text != s:
		l.text = s

func sync(player: Player, boss: Boss, time_left: float) -> void:
	var a := player.active
	var c := player.chars[a]
	_sq_icon.color = c.color
	_set_text(_sq_letter, c.char_name.substr(0, 1))
	if _sq_face_name != c.char_name:
		_sq_face_name = c.char_name
		_sq_face.texture = PuppetConfig.portrait(c.char_name)
	_sq_hp.value = c.hp / c.max_hp * 100.0
	_set_text(_sq_hp_txt, "%d/%d" % [int(c.hp), int(c.max_hp)])
	_sq_en.value = c.energy / GameConfig.ENERGY_MAX * 100.0
	var slot := 0
	for i in player.chars.size():
		if i == a:
			continue
		var o := player.chars[i]
		_res_icon[slot].color = o.color if o.is_alive() else Color(0.25, 0.25, 0.28)
		_set_text(_res_letter[slot], o.char_name.substr(0, 1))
		if _res_face_name[slot] != o.char_name:
			_res_face_name[slot] = o.char_name
			_res_face[slot].texture = PuppetConfig.portrait(o.char_name)
		_res_icon[slot].modulate = Color.WHITE if o.is_alive() else Color(0.45, 0.45, 0.5)
		_res_hp[slot].value = o.hp / o.max_hp * 100.0
		_res_en[slot].value = o.energy / GameConfig.ENERGY_MAX * 100.0
		slot += 1
	var parts: PackedStringArray = []
	if player.assist_buff_t > 0.0:
		parts.append("ASSIST +%d%% (%ds)" % [roundi(GameConfig.ASSIST_BUFF * 100.0), ceili(player.assist_buff_t)])
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

	_slot_dodge.modulate.a = 0.4 if player.dodge_cd > 0.0 else 1.0
	_slot_ex.modulate.a = 1.0 if c.energy >= c.ex_cost else 0.4
	var ult_ready := player.decibel >= GameConfig.DECIBEL_MAX
	_slot_ult.modulate.a = 1.0 if ult_ready else 0.5
	_ult_ring.color.a = 0.55 + 0.35 * sin(float(Time.get_ticks_msec()) * 0.012) if ult_ready else 0.0
	_set_text(_ult_pct, "READY" if ult_ready else "%d%%" % int(player.decibel / GameConfig.DECIBEL_MAX * 100.0))
	var show_chain := player.chain_ready and boss.is_stunned()
	_chain_lbl.visible = show_chain
	if show_chain:
		_chain_lbl.modulate.a = 0.6 + 0.4 * sin(float(Time.get_ticks_msec()) * 0.02)

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

func flash(color: Color) -> void:
	_flash.color = color
	_flash.modulate.a = 0.75
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.45)

func show_message(text: String) -> void:
	_msg.text = text
	_veil.visible = true

func clear_message() -> void:
	_msg.text = ""
	_veil.visible = false

func show_start() -> void:
	show_message("DEADLY ASSAULT  -  PROTOTYPE\n\nWASD move (camera locks on the boss)\nJ / Click attack     K / Shift dodge     L EX skill\nQ / E or 1 2 3 swap     Space ultimate     F chain attack\n\nDodge inside the YELLOW flash = Perfect Dodge.\nSwap during the slow-mo = Quick Assist.\nFill the Daze bar (Anby!) to stun the boss, then chain.\n\nESC pause      Press ENTER to start")

func show_results(outcome: String, grade: String, stats: Dictionary) -> void:
	show_message("%s\n\nGRADE  %s\n\nScore: %s\nDamage dealt: %s\nDamage taken: %s\nTime left: %.1fs\nMax combo: %d\nPerfect dodges: %d   Assists: %d   Chains: %d   Ultimates: %d\n\nPress R to restart" % [
		outcome, grade, _commas(int(stats["score"])), _commas(int(stats["damage"])), _commas(int(stats["taken"])),
		float(stats["time_left"]), int(stats["max_combo"]), int(stats["perfect_dodges"]),
		int(stats["assists"]), int(stats["chains"]), int(stats["ults"])])

func _unhandled_input(event: InputEvent) -> void:
	if can_pause and event.is_action_pressed("pause"):
		var p := not get_tree().paused
		get_tree().paused = p
		if p:
			show_message("PAUSED\n\nESC to resume")
		else:
			clear_message()
		pause_changed.emit(p)
