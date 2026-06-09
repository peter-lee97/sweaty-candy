extends Camera2D

func _ready() -> void:
	process_callback = 1

func _physics_process(_delta: float) -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	global_position = players[0].global_position
