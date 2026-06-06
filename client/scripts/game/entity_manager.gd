extends Node3D

@onready var players: Node3D = $Players
@onready var enemies: Node3D = $Enemies
@onready var projectiles: Node3D = $Projectiles
@onready var pickups: Node3D = $Pickups


func spawn_enemy(enemy: Node3D, position: Vector3) -> void:
	enemies.add_child(enemy)
	enemy.global_position = position


func spawn_projectile(projectile: Node3D, position: Vector3, direction: Vector3, damage: int, speed: float) -> void:
	projectiles.add_child(projectile)
	projectile.setup(position, direction, damage, speed)


func spawn_pickup(pickup: Node3D, spawn_position: Vector3) -> void:
	pickups.add_child(pickup)
	pickup.global_position = spawn_position


func get_enemy_count() -> int:
	return enemies.get_child_count()


func clear_all() -> void:
	for child in enemies.get_children():
		child.queue_free()
	for child in projectiles.get_children():
		child.queue_free()
	for child in pickups.get_children():
		child.queue_free()
