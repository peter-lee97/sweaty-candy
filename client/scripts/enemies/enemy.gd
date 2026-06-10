extends CharacterBody2D

@export var move_speed: float = 60.0
@export var max_health: int = 50
@export var contact_damage: int = 10
@export var contact_cooldown: float = 0.5
@export var knockback_strength: float = 300.0
@export var enemy_color: Color = Color(0.9, 0.2, 0.2, 1.0)
@export var enemy_size: Vector2 = Vector2(24, 24)

var health: int
var _contact_timer: float = 0.0
var _is_dead: bool = false
var _is_knocked_back: bool = false


func _ready() -> void:
	health = max_health
	%Sprite.size = enemy_size
	%Sprite.position = -enemy_size / 2.0
	%Sprite.color = enemy_color


func _physics_process(delta: float) -> void:
	if _is_knocked_back:
		return

	_contact_timer -= delta

	var player: Node2D = _find_nearest_player()
	if player:
		var direction: Vector2 = (player.global_position - global_position).normalized()
		velocity = direction * move_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()


func _find_nearest_player() -> Node2D:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0]


func _apply_knockback(dir: Vector2) -> void:
	_is_knocked_back = true
	var knock_dir := dir.normalized()
	var target_pos := global_position + knock_dir * 15.0
	var tween := create_tween()
	tween.tween_property(self, "global_position", target_pos, 0.08)
	tween.tween_callback(func(): _is_knocked_back = false)


func take_damage(amount: int, from_dir: Vector2 = Vector2.ZERO) -> void:
	if _is_dead:
		return
	health -= amount
	_flash_hit()
	if health <= 0:
		_die()
	elif from_dir != Vector2.ZERO:
		_apply_knockback(from_dir)


func _flash_hit() -> void:
	var tween := create_tween()
	tween.tween_property(%Sprite, "color", Color.WHITE, 0.05)
	tween.tween_property(%Sprite, "color", enemy_color, 0.1)


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	GameEvents.enemy_killed.emit(global_position)
	queue_free()


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and _contact_timer <= 0.0:
		body.take_damage(contact_damage)
		_contact_timer = contact_cooldown
