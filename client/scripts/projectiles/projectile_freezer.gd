extends Area3D

@export var lifetime: float = 3.0
@export var slow_multiplier: float = 0.5
@export var slow_duration: float = 2.0

var _direction: Vector3 = Vector3.FORWARD
var _speed: float = 20.0
var _damage: int = 10


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
	var applied_slow: bool = false
	for child in body.get_children():
		if child is HealthComponent:
			child.take_damage(_damage)
		if body.has_method("apply_slow"):
			if not applied_slow:
				body.apply_slow(slow_multiplier, slow_duration)
				applied_slow = true
	queue_free()
