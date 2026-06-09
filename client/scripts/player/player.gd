extends CharacterBody2D

@export var move_speed: float = 300.0
@export var max_health: int = 100
@export var projectile_scene: PackedScene

var health: int = max_health
var shoot_cooldown: float = 0.25
var _shoot_timer: float = 0.0
var _aim_direction: Vector2 = Vector2.DOWN

@onready var _sprite: ColorRect = %Sprite


func _ready() -> void:
	health = max_health


func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * move_speed
	move_and_slide()

	if input_dir.length_squared() > 0.0:
		_aim_direction = input_dir

	_shoot_timer -= delta
	if Input.is_action_pressed("shoot") and _shoot_timer <= 0.0:
		_shoot()
		_shoot_timer = shoot_cooldown


func _shoot() -> void:
	if not projectile_scene:
		return
	var projectile: Area2D = projectile_scene.instantiate()
	projectile.global_position = global_position
	projectile.set_direction(_aim_direction)
	get_tree().current_scene.add_child(projectile)


func take_damage(amount: int) -> void:
	health -= amount
	GameEvents.player_health_changed.emit(health, max_health)
	if health <= 0:
		_die()


func _die() -> void:
	GameEvents.player_died.emit()
	queue_free()
