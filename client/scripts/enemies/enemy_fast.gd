extends CharacterBody3D

@export var move_speed: float = 2.5
@export var score_value: int = 150
@export var knockback_force: float = 10.0
@export var knockback_decay: float = 18.0

@onready var health_component: HealthComponent = %HealthComponent
@onready var hitbox_component: HitboxComponent = %HitboxComponent

const DEATH_PARTICLES_SCRIPT = preload("res://scripts/effects/death_particles.gd")

var _player: CharacterBody3D = null
var _knockback_velocity: Vector3 = Vector3.ZERO
var _speed_multiplier: float = 1.0
var _slow_timer: float = 0.0


func _ready() -> void:
	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)


func _physics_process(delta: float) -> void:
	_update_slow(delta)
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		velocity = _knockback_velocity
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, knockback_decay * delta)
		move_and_slide()
		return

	var direction: Vector3 = (_player.global_position - global_position)
	direction.y = 0.0
	direction = direction.normalized()
	velocity = direction * (move_speed * _speed_multiplier) + _knockback_velocity
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, knockback_decay * delta)
	move_and_slide()


func _find_player() -> CharacterBody3D:
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	if players.size() > 0:
		return players[0]
	return null


func _on_died() -> void:
	GameEvents.enemy_killed.emit(score_value, global_position)
	_spawn_death_particles()
	queue_free()


func _spawn_death_particles() -> void:
	var n := Node3D.new()
	n.set_script(DEATH_PARTICLES_SCRIPT)
	n.setup(Color.ORANGE)
	get_parent().add_child(n)
	n.global_position = global_position


func _on_health_changed(current: int, _maximum: int) -> void:
	if current >= health_component.max_health:
		return
	if _player == null or not is_instance_valid(_player):
		return
	var away_from_player: Vector3 = (global_position - _player.global_position)
	away_from_player.y = 0.0
	_knockback_velocity = away_from_player.normalized() * knockback_force


func apply_slow(multiplier: float, duration: float) -> void:
	_speed_multiplier = multiplier
	_slow_timer = duration


func _update_slow(delta: float) -> void:
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_speed_multiplier = 1.0
