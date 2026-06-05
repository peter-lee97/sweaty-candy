extends Node3D
class_name Weapon

@export var weapon_name: String = "Blaster"
@export var fire_rate: float = 4.0
@export var damage: int = 25
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 25.0
@export var spread: float = 0.0
@export var projectile_count: int = 1
@export var ammo: int = -1
@export var muzzle_distance: float = 0.5

var _can_fire: bool = true
var _cooldown_timer: float = 0.0
var _entity_manager: Node = null


func _process(delta: float) -> void:
	if not _can_fire:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_cooldown_timer = 0.0
			_can_fire = true


func try_fire(from_position: Vector3, direction: Vector3) -> bool:
	if not _can_fire:
		return false
	if not _entity_manager:
		return false
	if ammo == 0:
		return false

	_can_fire = false
	_cooldown_timer = 1.0 / fire_rate

	if ammo > 0:
		ammo -= 1

	for i in range(projectile_count):
		var spread_angle: float = randf_range(-spread, spread)
		var dir: Vector3 = direction.rotated(Vector3.UP, spread_angle)
		var spawn_pos: Vector3 = from_position + dir * muzzle_distance
		var projectile: Node3D = projectile_scene.instantiate()
		_entity_manager.spawn_projectile(projectile, spawn_pos, dir, damage, projectile_speed)

	return true


func set_entity_manager(manager: Node) -> void:
	_entity_manager = manager


func get_entity_manager() -> Node:
	return _entity_manager
