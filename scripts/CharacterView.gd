class_name CharacterView
extends Node3D
## Interface between Player and whatever draws the character (3D Model3D or the 2.5D Puppet).

func setup(_cname: String) -> void:
	pass

## world_vel: world-space velocity. st: Player.State. view_yaw: camera yaw. facing_yaw: the character's logic heading.
func tick(_delta: float, _world_vel: Vector3, _st: int, _view_yaw: float, _facing_yaw: float) -> void:
	pass

func on_attack(_heavy: bool) -> void:
	pass

func on_step(_heavy: bool) -> void:
	pass

func on_dodge() -> void:
	pass

func on_hurt() -> void:
	pass

func on_swap_in() -> void:
	pass

func on_dead() -> void:
	pass
