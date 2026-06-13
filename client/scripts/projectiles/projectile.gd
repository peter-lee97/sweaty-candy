extends Area2D

@export var speed: float = 500.0
@export var damage: int = 25

var _direction: Vector2 = Vector2.RIGHT


func set_direction(dir: Vector2) -> void:
	_direction = dir


func _physics_process(delta: float) -> void:
	position += _direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("world"):
		queue_free()
