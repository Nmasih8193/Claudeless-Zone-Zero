class_name DamageNumber
extends Label3D

const MAX_ACTIVE := 60
static var active: int = 0

static func spawn(parent: Node, pos: Vector3, amount: float, color: Color, crit: bool) -> void:
	if parent == null or active >= MAX_ACTIVE:
		return
	var n := DamageNumber.new()
	active += 1
	n.tree_exiting.connect(func() -> void: DamageNumber.active -= 1)
	n.text = str(roundi(amount)) + ("!!" if crit else "")
	n.modulate = color
	n.outline_modulate = Color(0.0, 0.05, 0.1)
	n.outline_size = 14
	n.font_size = 110 if crit else 64
	n.pixel_size = 0.01
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.no_depth_test = true
	n.shaded = false
	parent.add_child(n)
	n.global_position = pos + Vector3(randf_range(-1.0, 1.0), randf_range(0.0, 0.8), randf_range(-0.4, 0.4))
	var rise := n.position.y + (3.2 if crit else 2.4)
	var tw := n.create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "position:y", rise, 0.9)
	tw.tween_property(n, "modulate:a", 0.0, 0.45).set_delay(0.45)
	tw.chain().tween_callback(n.queue_free)
