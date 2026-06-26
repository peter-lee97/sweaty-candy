extends CharacterBody2D

@export var move_speed: float = 300.0
@export var max_health: int = 100

var health: int = max_health
var shoot_cooldown: float = 0.25
var _shoot_timer: float = 0.0
var _aim_direction: Vector2 = Vector2.DOWN
var _knockback: Vector2 = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if has_meta("network_id"):
		return
	if not visible:
		return
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * move_speed + _knockback
	move_and_slide()
	_knockback = _knockback.lerp(Vector2.ZERO, delta * 8.0)
	if _knockback.length() < 2.0:
		_knockback = Vector2.ZERO

	if input_dir.length_squared() > 0.0:
		_aim_direction = input_dir

	_shoot_timer -= delta
	if Input.is_action_pressed("shoot") and _shoot_timer <= 0.0 and not GameEvents.ui_blocking_input:
		_shoot()
		_shoot_timer = shoot_cooldown


func _shoot() -> void:
	if GameData.multiplayer_session_active:
		return
	GameEvents.spawn_projectile_requested.emit(global_position, _aim_direction)
	GameEvents.projectile_fired.emit()


func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	health -= amount
	_knockback = knockback_dir * 500.0
	GameEvents.player_health_changed.emit(health, max_health)
	if health <= 0:
		_die()


func heal(amount: int) -> void:
	health = min(health + amount, max_health)
	GameEvents.player_health_changed.emit(health, max_health)


func _die() -> void:
	GameEvents.player_died.emit()
	queue_free()
