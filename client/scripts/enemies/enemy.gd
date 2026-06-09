extends CharacterBody2D

@export var move_speed: float = 60.0
@export var max_health: int = 50
@export var contact_damage: int = 10
@export var contact_cooldown: float = 0.5

var health: int = max_health
var _contact_timer: float = 0.0

@onready var _sprite: ColorRect = %Sprite


func _ready() -> void:
	health = max_health


func _physics_process(delta: float) -> void:
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


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		_die()


func _die() -> void:
	GameEvents.enemy_killed.emit(global_position)
	queue_free()


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and _contact_timer <= 0.0:
		body.take_damage(contact_damage)
		_contact_timer = contact_cooldown
