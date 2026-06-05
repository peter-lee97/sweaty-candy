extends Area3D

@export var heal_amount: int = 25

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("players"):
		return
	for child in body.get_children():
		if child is HealthComponent:
			child.heal(heal_amount)
			break
	queue_free()
