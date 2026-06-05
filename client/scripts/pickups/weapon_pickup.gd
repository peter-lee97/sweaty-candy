extends Area3D

@export var weapon_index: int = 0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("players"):
		return
	if body.has_method("cycle_weapon"):
		var target_index: int = weapon_index
		var current: int = 0
		if body.has_method("_current_weapon_index"):
			current = body._current_weapon_index
		var diff: int = target_index - current
		if diff > 0:
			for i in range(diff):
				body.cycle_weapon(1)
		elif diff < 0:
			for i in range(-diff):
				body.cycle_weapon(-1)
	queue_free()
