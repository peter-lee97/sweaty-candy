extends Area3D

@export var lifetime: float = 3.0
@export var explosion_radius: float = 3.0

var _direction: Vector3 = Vector3.FORWARD
var _speed: float = 15.0
var _damage: int = 40


func setup(start_position: Vector3, direction: Vector3, damage: int, speed: float) -> void:
	global_position = start_position
	_direction = direction.normalized()
	_speed = speed
	_damage = damage


func _physics_process(delta: float) -> void:
	position += _direction * _speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	_explode()
	queue_free()


func _explode() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_access
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = explosion_radius
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 2
	var results: Array[Dictionary] = space_state.intersect_shape(query)
	for result: Dictionary in results:
		var collider: CollisionObject3D = result["collider"]
		for child in collider.get_children():
			if child is HealthComponent:
				child.take_damage(_damage)
				break
