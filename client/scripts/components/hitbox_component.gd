extends Area3D
class_name HitboxComponent

@export var damage: int = 10
@export var damage_cooldown: float = 1.0

var _cooldowns: Dictionary = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	set_process(false)


func _process(delta: float) -> void:
	if _cooldowns.is_empty():
		return
	var expired: Array = []
	for body: Node3D in _cooldowns:
		_cooldowns[body] -= delta
		if _cooldowns[body] <= 0.0:
			expired.append(body)
	for body: Node3D in expired:
		_cooldowns.erase(body)
	if _cooldowns.is_empty():
		set_process(false)


func _on_body_entered(body: Node3D) -> void:
	if _cooldowns.has(body):
		return
	var health: HealthComponent = _find_health(body)
	if health == null or health.is_dead():
		return
	health.take_damage(damage)
	_cooldowns[body] = damage_cooldown
	set_process(true)


func _find_health(node: Node) -> HealthComponent:
	for child in node.get_children():
		if child is HealthComponent:
			return child
	return null
