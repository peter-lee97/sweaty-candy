extends CharacterBody3D

@export var move_speed: float = 6.0
@export var accepts_local_input: bool = true
@export var emits_global_events: bool = true

@onready var health_component: HealthComponent = %HealthComponent
@onready var weapon_anchor: Node3D = %WeaponAnchor

var _aim_direction: Vector3 = Vector3.FORWARD
var _weapon: Node3D = null
var _weapon_scenes: Array[PackedScene] = []
var _current_weapon_index: int = 0

signal player_died


func _ready() -> void:
	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)
	if emits_global_events:
		GameEvents.player_health_changed.emit(health_component.max_health, health_component.max_health)


func _physics_process(delta: float) -> void:
	if not accepts_local_input:
		return
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	var move_dir := Vector3(input_dir.x, 0.0, input_dir.y).normalized()
	velocity = move_dir * move_speed
	move_and_slide()

	if move_dir != Vector3.ZERO:
		_aim_direction = move_dir

	if Input.is_action_pressed("shoot") and _weapon and not _is_pointer_over_ui():
		_weapon.try_fire(global_position + Vector3(0, 0.5, 0), _aim_direction)


func set_weapon_scenes(scenes: Array[PackedScene]) -> void:
	_weapon_scenes = scenes


func equip_weapon(weapon_node: Node3D) -> void:
	if _weapon:
		_weapon.queue_free()
	_weapon = weapon_node
	weapon_anchor.add_child(_weapon)
	if emits_global_events:
		GameEvents.weapon_changed.emit(_weapon.weapon_name)


func cycle_weapon(direction: int) -> void:
	if _weapon_scenes.size() == 0:
		return
	_current_weapon_index = wrapi(_current_weapon_index + direction, 0, _weapon_scenes.size())
	var entity_manager: Node = _weapon.get_entity_manager() if _weapon and _weapon.has_method("get_entity_manager") else null
	var new_weapon: Node3D = _weapon_scenes[_current_weapon_index].instantiate()
	if entity_manager:
		new_weapon.set_entity_manager(entity_manager)
	equip_weapon(new_weapon)


func take_damage(_amount: int) -> void:
	pass


func _on_died() -> void:
	player_died.emit()
	if emits_global_events:
		GameEvents.player_died.emit()


func _on_health_changed(current: int, maximum: int) -> void:
	if emits_global_events:
		GameEvents.player_health_changed.emit(current, maximum)


func _is_pointer_over_ui() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var hovered_control: Control = viewport.gui_get_hovered_control()
	return _is_pause_or_quit_control(hovered_control)


func _is_pause_or_quit_control(control: Control) -> bool:
	var current: Control = control
	while current != null:
		if current.name == "PauseToggleButton" or current.name == "ExitHoldButton":
			return true
		current = current.get_parent() as Control
	return false
