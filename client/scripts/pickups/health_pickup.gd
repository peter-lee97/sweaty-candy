extends Area2D

@export var heal_amount: int = 25

var _lifetime_timer: Timer


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_lifetime_timer = Timer.new()
	_lifetime_timer.wait_time = 10.0
	_lifetime_timer.one_shot = true
	_lifetime_timer.timeout.connect(_on_lifetime_expired)
	add_child(_lifetime_timer)


func activate(pos: Vector2) -> void:
	global_position = pos
	show()
	process_mode = Node.PROCESS_MODE_INHERIT
	_lifetime_timer.start()


func deactivate() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED
	_lifetime_timer.stop()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("heal"):
		body.heal(heal_amount)
		GameEvents.pickup_collected.emit(self)


func _on_lifetime_expired() -> void:
	GameEvents.pickup_expired.emit(self)
