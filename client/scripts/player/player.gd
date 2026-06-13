extends CharacterBody2D

@export var move_speed: float = 300.0
@export var max_health: int = 100
@export var projectile_scene: PackedScene

var health: int = max_health
var shoot_cooldown: float = 0.25
var _shoot_timer: float = 0.0
var _aim_direction: Vector2 = Vector2.DOWN

var scent_trail: Array = []
var _scent_timer: float = 0.0
const SCENT_INTERVAL: float = 0.1
const SCENT_LIFETIME: float = 3.0
const MAX_SCENTS: int = 50


func _ready() -> void:
	pass


func get_scent_trail() -> Array:
	return scent_trail


func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * move_speed
	move_and_slide()

	if input_dir.length_squared() > 0.0:
		_aim_direction = input_dir

	_shoot_timer -= delta
	if Input.is_action_pressed("shoot") and _shoot_timer <= 0.0 and not GameEvents.ui_blocking_input:
		_shoot()
		_shoot_timer = shoot_cooldown

	_update_scent_trail(delta)


func _update_scent_trail(delta: float) -> void:
	_scent_timer += delta
	if _scent_timer >= SCENT_INTERVAL:
		_scent_timer = 0.0
		scent_trail.push_front({"position": global_position, "t": 0.0})
		while scent_trail.size() > MAX_SCENTS:
			scent_trail.pop_back()

	var to_remove: Array = []
	for scent in scent_trail:
		scent.t += delta
		if scent.t >= SCENT_LIFETIME:
			to_remove.append(scent)
	for scent in to_remove:
		scent_trail.erase(scent)


func _shoot() -> void:
	if not projectile_scene:
		return
	var projectile: Area2D = projectile_scene.instantiate()
	projectile.global_position = global_position
	projectile.set_direction(_aim_direction)
	get_tree().current_scene.add_child(projectile)
	GameEvents.projectile_fired.emit()


func take_damage(amount: int) -> void:
	health -= amount
	GameEvents.player_health_changed.emit(health, max_health)
	if health <= 0:
		_die()


func heal(amount: int) -> void:
	health = min(health + amount, max_health)
	GameEvents.player_health_changed.emit(health, max_health)


func _die() -> void:
	GameEvents.player_died.emit()
	queue_free()
