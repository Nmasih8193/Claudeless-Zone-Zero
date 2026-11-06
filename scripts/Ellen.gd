class_name Ellen
extends Character
## Ice main DPS. Basic hits build Flurry stacks that power up her EX.

func _init() -> void:
	load_stats(GameConfig.ELLEN)

func on_basic_hit(_ctx: Player, _idx: int) -> void:
	stacks = mini(stacks + 1, GameConfig.ELLEN_MAX_STACKS)

func make_ex_steps() -> Array:
	var out := make_steps(ex_rows, 1.0 + GameConfig.ELLEN_STACK_BONUS * float(stacks))
	stacks = 0
	return out
