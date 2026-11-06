class_name Character
extends RefCounted
## Data + hooks for one squad member. Subclasses override the hooks.

var char_name: String = "?"
var element: int = GameConfig.Element.PHYSICAL
var color: Color = Color.WHITE
var accent: Color = Color.WHITE
var max_hp: float = 1000.0
var hp: float = 1000.0
var energy: float = 0.0
var attack_range: float = 3.4
var combo_damage: Array = [50.0]
var daze_per_hit: float = 2.0
var freeze_per_hit: float = 0.0
var energy_per_hit: float = 4.0
var ex_cost: float = 50.0
var stun_bonus: float = 1.0
var field_buff: float = 0.0
var seq_stand: float = 3.5
var weapon_size: Vector3 = Vector3(0.15, 0.15, 1.2)
var ex_rows: Array = []
var ex_len: float = 1.0
var ult_rows: Array = []
var ult_len: float = 2.0
var assist_rows: Array = []
var assist_len: float = 0.7
var chain_rows: Array = []
var chain_len: float = 1.0
var stacks: int = 0

func load_stats(d: Dictionary) -> void:
	char_name = d["name"]
	element = d["element"]
	color = d["color"]
	accent = d["accent"]
	max_hp = d["hp"]
	hp = max_hp
	attack_range = d["range"]
	combo_damage = d["combo"]
	daze_per_hit = d["daze"]
	freeze_per_hit = d["freeze"]
	energy_per_hit = d["energy_hit"]
	ex_cost = d["ex_cost"]
	stun_bonus = d["stun_bonus"]
	field_buff = d["field_buff"]
	seq_stand = d["stand"]
	weapon_size = d["weapon"]
	ex_rows = d["ex"]
	ex_len = d["ex_len"]
	ult_rows = d["ult"]
	ult_len = d["ult_len"]
	assist_rows = d["assist"]
	assist_len = d["assist_len"]
	chain_rows = d["chain"]
	chain_len = d["chain_len"]

func is_alive() -> bool:
	return hp > 0.0

## Rows are [time, damage, daze, freeze, shake].
func make_steps(rows: Array, mult: float = 1.0) -> Array:
	var out: Array = []
	for r: Array in rows:
		out.append({
			"t": float(r[0]), "char": -1, "dmg": float(r[1]) * mult,
			"daze": float(r[2]), "freeze": float(r[3]), "shake": float(r[4]), "elem": element,
		})
	return out

## Dodge Counter (attack during the perfect-dodge slow-mo): one big, high-daze strike.
func make_counter_steps() -> Array:
	var heavy: float = float(combo_damage[combo_damage.size() - 1])
	return make_steps([[0.1, heavy * 1.5, daze_per_hit * 5.0, freeze_per_hit * 1.5, 0.3]])

## Special Attack (E without enough energy for the EX version).
func make_special_steps() -> Array:
	var heavy: float = float(combo_damage[combo_damage.size() - 1])
	return make_steps([[0.14, heavy * 0.9, daze_per_hit * 2.5, freeze_per_hit, 0.15]])

# ---- Hooks (override) ----
func on_basic_hit(_ctx: Player, _idx: int) -> void:
	pass

func ex_start(_ctx: Player) -> void:
	pass

func make_ex_steps() -> Array:
	return make_steps(ex_rows)

func on_assist(_ctx: Player) -> void:
	pass
