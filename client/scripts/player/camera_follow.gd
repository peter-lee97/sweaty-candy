extends Camera3D

@export var offset: Vector3 = Vector3(0.0, 18.0, 12.0)
@export var smoothing: float = 8.0

var _target: Node3D = null


func set_target(target: Node3D) -> void:
	_target = target
	if _target:
		global_position = _target.global_position + offset
		look_at(_target.global_position)


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var desired_pos: Vector3 = _target.global_position + offset
	global_position = global_position.lerp(desired_pos, smoothing * delta)
	look_at(_target.global_position)
