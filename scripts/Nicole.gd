class_name Nicole
extends Character
## Ether support. EX pulls the boss in and applies Defense Down.
## On field: team damage buff (field_buff). Quick Assist leaves a timed buff.

func _init() -> void:
	load_stats(GameConfig.NICOLE)

func ex_start(ctx: Player) -> void:
	ctx.boss.pull_toward(ctx.global_position)
	ctx.boss.apply_def_down()

func on_assist(ctx: Player) -> void:
	ctx.assist_buff_t = GameConfig.ASSIST_BUFF_TIME
