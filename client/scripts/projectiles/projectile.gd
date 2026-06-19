extends CharacterBody2D

@export var speed: float = 500.0
@export var damage: int = 25

var _direction: Vector2 = Vector2.RIGHT


func set_direction(dir: Vector2) -> void:
	_direction = dir


func activate(pos: Vector2, dir: Vector2) -> void:
	global_position = pos
	_direction = dir
	show()
	process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(true)


func deactivate() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED


func _physics_process(delta: float) -> void:
	if GameData.multiplayer_session_active:
		position += _direction * speed * delta
		return
	var collision := move_and_collide(_direction * speed * delta)
	if collision:
		var body := collision.get_collider()
		if body.is_in_group("world") or body.is_in_group("obstacle"):
			GameEvents.projectile_expired.emit(self)
		elif body.is_in_group("enemy") and body.has_method("take_damage"):
			body.take_damage(damage, global_position.direction_to(body.global_position))
			GameEvents.projectile_hit.emit()
			GameEvents.projectile_expired.emit(self)
