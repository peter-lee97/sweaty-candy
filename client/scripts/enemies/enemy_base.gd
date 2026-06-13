extends CharacterBody2D

@export var hp: int = 50
@export var move_speed: float = 125.0
@export var score_value: int = 100
@export var detection_range: float = 600.0
const MIN_CHASE_DISTANCE: float = 32.0

var _knockback: Vector2 = Vector2.ZERO

@onready var _vision_ray: RayCast2D = $VisionRay


func _physics_process(delta: float) -> void:
	var player := _find_nearest_player()
	if player and _has_line_of_sight(player) and global_position.distance_to(player.global_position) > MIN_CHASE_DISTANCE:
		velocity = global_position.direction_to(player.global_position) * move_speed + _knockback
	else:
		velocity = _knockback
	_knockback = _knockback.lerp(Vector2.ZERO, delta * 8.0)
	if _knockback.length() < 2.0:
		_knockback = Vector2.ZERO
	move_and_slide()


func _has_line_of_sight(target: Node2D) -> bool:
	var dir := global_position.direction_to(target.global_position)
	var dist := global_position.distance_to(target.global_position)
	if dist > detection_range:
		return false
	_vision_ray.target_position = dir * dist
	_vision_ray.force_raycast_update()
	return not _vision_ray.is_colliding()


func take_damage(amount: int, knockback_dir: Vector2) -> void:
	hp -= amount
	_knockback = knockback_dir * 400.0
	_flash_hit()
	if hp <= 0:
		_die()


func _flash_hit() -> void:
	$Sprite.modulate = Color.WHITE
	await get_tree().create_timer(0.1).timeout
	if is_queued_for_deletion():
		return
	$Sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _die() -> void:
	GameEvents.enemy_killed.emit(global_position, score_value)
	queue_free()


func _find_nearest_player() -> Node2D:
	var players: Array = get_tree().get_nodes_in_group("player")
	var nearest: Node2D
	var min_dist: float = INF
	for p in players:
		var dist: float = global_position.distance_squared_to(p.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = p
	return nearest
