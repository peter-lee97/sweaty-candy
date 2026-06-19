extends Button

@export var hold_duration: float = 3.0
@export var quit_on_hold: bool = false

var _hold_timer: float = 0.0
var _is_holding: bool = false


func _ready() -> void:
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	set_process(false)
	text = "X"


func _process(delta: float) -> void:
	if _is_holding:
		_hold_timer += delta
		var progress: float = _hold_timer / hold_duration
		text = "%d%%" % int(progress * 100.0)
		modulate = Color(1.0, 1.0 - progress * 0.6, 1.0 - progress * 0.6)
		if _hold_timer >= hold_duration:
			_is_holding = false
			GameEvents.ui_blocking_input = false
			if quit_on_hold:
				get_tree().quit()
			else:
				if GameData.multiplayer_session_active:
					NetworkClient.disconnect_from_server()
					GameData.clear_multiplayer_session()
				get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_button_down() -> void:
	_is_holding = true
	_hold_timer = 0.0
	set_process(true)
	GameEvents.ui_blocking_input = true


func _on_button_up() -> void:
	_is_holding = false
	_hold_timer = 0.0
	set_process(false)
	text = "X"
	modulate = Color.WHITE
	GameEvents.ui_blocking_input = false
