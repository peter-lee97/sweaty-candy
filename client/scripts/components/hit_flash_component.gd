extends Node

@export var flash_duration: float = 0.1
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

static var _flash_material_cache: Dictionary = {}

var _mesh_instance: MeshInstance3D = null
var _original_material: Material = null
var _flash_material: Material = null
var _flash_timer: float = 0.0


func _ready() -> void:
	_mesh_instance = _find_mesh_instance(get_parent())
	if _mesh_instance:
		_flash_material = _get_or_create_flash_material()
	var health: HealthComponent = _find_health(get_parent())
	if health:
		health.health_changed.connect(_on_health_changed)
	set_process(false)


func _process(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		_flash_timer = 0.0
		if _mesh_instance and _original_material != null:
			_mesh_instance.material_override = _original_material
		set_process(false)


func _on_health_changed(current: int, _maximum: int) -> void:
	if current <= 0:
		return
	if _mesh_instance == null:
		return
	_original_material = _mesh_instance.material_override
	_mesh_instance.material_override = _flash_material
	_flash_timer = flash_duration
	set_process(true)


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
	return null


func _find_health(node: Node) -> HealthComponent:
	for child in node.get_children():
		if child is HealthComponent:
			return child
	return null


func _get_or_create_flash_material() -> Material:
	var cache_key: String = flash_color.to_html(true)
	if _flash_material_cache.has(cache_key):
		return _flash_material_cache[cache_key]
	var material := StandardMaterial3D.new()
	material.albedo_color = flash_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material_cache[cache_key] = material
	return material