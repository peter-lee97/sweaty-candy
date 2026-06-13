extends CharacterBody2D

@export var speed: float = 500.0
@export var damage: int = 25

var _direction: Vector2 = Vector2.RIGHT


func set_direction(dir: Vector2) -> void:
	_direction = dir


func _physics_process(delta: float) -> void:
	var collision := move_and_collide(_direction * speed * delta)
	if collision:
		var body := collision.get_collider()
		if body.is_in_group("world") or body.is_in_group("obstacle"):
			queue_free()
		elif body.is_in_group("enemy") and body.has_method("take_damage"):
			body.take_damage(damage, global_position.direction_to(body.global_position))
			queue_free()
