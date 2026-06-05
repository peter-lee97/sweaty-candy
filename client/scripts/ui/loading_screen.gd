extends Control

const TARGET_SCENE_PATH: String = "res://scenes/game/game.tscn"

@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _progress_label: Label = %ProgressLabel
@onready var _status_label: Label = %StatusLabel

var _loading_started: bool = false


func _ready() -> void:
	_progress_bar.value = 0.0
	_progress_label.text = "0%"
	_status_label.text = "Loading assets..."
	var error: Error = ResourceLoader.load_threaded_request(TARGET_SCENE_PATH, "PackedScene", true)
	if error != OK:
		_show_error("Failed to start loading.")
		return
	_loading_started = true
	set_process(true)


func _process(_delta: float) -> void:
	if not _loading_started:
		return
	var progress: Array = []
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(TARGET_SCENE_PATH, progress)
	_update_progress(progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		ResourceLoader.THREAD_LOAD_LOADED:
			_loading_started = false
			var packed: PackedScene = ResourceLoader.load_threaded_get(TARGET_SCENE_PATH)
			if packed == null:
				_show_error("Loaded data is invalid.")
				return
			_status_label.text = "Starting game..."
			get_tree().change_scene_to_packed(packed)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loading_started = false
			_show_error("Failed to load game assets.")
		_:
			pass


func _update_progress(progress: Array) -> void:
	var ratio: float = 0.0
	if progress.size() > 0 and progress[0] is float:
		ratio = clamp(progress[0], 0.0, 1.0)
	var percent: int = int(round(ratio * 100.0))
	_progress_bar.value = percent
	_progress_label.text = "%d%%" % percent


func _show_error(message: String) -> void:
	_status_label.text = message
	_progress_label.text = "Error"
	set_process(false)
