extends Area3D

@export var lifetime: float = 3.0

var _direction: Vector3 = Vector3.FORWARD
var _speed: float = 25.0
var _damage: int = 25


func setup(start_position: Vector3, direction: Vector3, damage: int, speed: float) -> void:
	global_position = start_position
	_direction = direction.normalized()
	_speed = speed
	_damage = damage


func _physics_process(delta: float) -> void:
	position += _direction * _speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	for child in body.get_children():
		if child is HealthComponent:
			child.take_damage(_damage)
			break
	queue_free()
