extends CanvasLayer

@onready var health_bar: ProgressBar = %HealthBar
@onready var score_label: Label = %ScoreLabel
@onready var wave_label: Label = %WaveLabel
@onready var combo_label: Label = %ComboLabel
@onready var weapon_label: Label = %WeaponLabel
@onready var pause_toggle_button: Button = %PauseToggleButton
@onready var exit_hold_button: Button = %ExitHoldButton

const EXIT_HOLD_DURATION: float = 1.25

var _holding_exit: bool = false
var _exit_hold_elapsed: float = 0.0
var _exit_triggered: bool = false
var _pause_pressed_last_frame: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.player_health_changed.connect(_on_health_changed)
	GameEvents.score_updated.connect(_on_score_updated)
	GameEvents.wave_started.connect(_on_wave_started)
	GameEvents.weapon_changed.connect(_on_weapon_changed)
	GameEvents.pause_state_changed.connect(_on_pause_state_changed)
	pause_toggle_button.pressed.connect(_on_pause_button_pressed)
	exit_hold_button.button_down.connect(_on_exit_hold_started)
	exit_hold_button.button_up.connect(_on_exit_hold_released)
	pause_toggle_button.process_mode = Node.PROCESS_MODE_ALWAYS
	exit_hold_button.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_toggle_button.text = "▶"
	exit_hold_button.text = "⏻"
	_on_pause_state_changed(false)


func _process(delta: float) -> void:
	_handle_pause_hotkey()
	if not _holding_exit or _exit_triggered:
		return
	_exit_hold_elapsed += delta
	var ratio: float = clamp(_exit_hold_elapsed / EXIT_HOLD_DURATION, 0.0, 1.0)
	exit_hold_button.text = "⏻ %d%%" % int(ratio * 100.0)
	if _exit_hold_elapsed >= EXIT_HOLD_DURATION:
		_exit_triggered = true
		_holding_exit = false
		exit_hold_button.text = "⏻"
		GameEvents.exit_to_menu_requested.emit()


func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


func _on_score_updated(new_score: int, new_combo: int) -> void:
	score_label.text = "Score: %d" % new_score
	if new_combo > 1:
		combo_label.text = "x%d COMBO" % new_combo
		combo_label.visible = true
	else:
		combo_label.visible = false


func _on_wave_started(wave_number: int) -> void:
	wave_label.text = "Wave %d" % wave_number


func _on_weapon_changed(weapon_name: String) -> void:
	weapon_label.text = weapon_name


func _on_pause_state_changed(paused: bool) -> void:
	pause_toggle_button.text = "⏸" if paused else "▶"


func _on_pause_button_pressed() -> void:
	GameEvents.pause_toggle_requested.emit()


func _handle_pause_hotkey() -> void:
	var pause_pressed_now: bool = Input.is_action_pressed("pause")
	if pause_pressed_now and not _pause_pressed_last_frame:
		GameEvents.pause_toggle_requested.emit()
	_pause_pressed_last_frame = pause_pressed_now


func _on_exit_hold_started() -> void:
	_holding_exit = true
	_exit_hold_elapsed = 0.0
	_exit_triggered = false


func _on_exit_hold_released() -> void:
	_holding_exit = false
	_exit_hold_elapsed = 0.0
	if not _exit_triggered:
		exit_hold_button.text = "⏻"
